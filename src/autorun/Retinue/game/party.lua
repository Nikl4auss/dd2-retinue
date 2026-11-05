-- REFramework glue: reads the party each frame and the status-line rows (uses sdk).
-- The decisions live in Retinue/{targets,status}.lua.

local hooks = require("Retinue.hooks")
local targets = require("Retinue.targets")

local M = {}

-- state: shared table; refresh writes state.targets. is_hired may be nil.
-- Returns an object with:
--   refresh()  -- the pcall'd party read; on a throw clears the targets and reports "refresh"
--   rows()     -- nil when no party is loaded, else an array of read_row results (the status.format input)
--   failed     -- boolean, last refresh threw
function M.new(state, is_hired, report)
    local td_guibase = sdk.find_type_definition("app.GUIBase")
    local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")

    -- Set by refresh_targets each frame; read by rows. party_loaded: PawnManager and its party list exist.
    -- target_charas: app.Character of each party pawn in state.targets, in party order.
    local party_loaded = false
    local target_charas = {}

    local function refresh_targets()
        state.targets = {}
        party_loaded = false
        target_charas = {}
        local pm = sdk.get_managed_singleton("app.PawnManager")
        if not pm then return end
        local party_list = pm:get_field("_PartyPawnList")
        if not party_list then return end
        party_loaded = true -- a save is loaded; without isSubPawn there are simply no targets
        if not is_hired then return end
        local party_ids, party_charas = {}, {}
        for i = 0, party_list:call("get_Count") - 1 do
            local pawn = party_list:call("get_Item", i)
            local chara = pawn and pawn:call("get_CachedCharacter")
            if chara then
                local id = hooks.to_u32(chara:call("get_CharaID"))
                if id ~= nil then
                    local n = #party_ids + 1
                    party_ids[n] = id
                    party_charas[n] = chara
                end
            end
        end
        local set = targets.build(party_ids, is_hired)
        local charas = {}
        for i, id in ipairs(party_ids) do
            if set[id] then charas[#charas + 1] = party_charas[i] end
        end
        state.targets = set
        target_charas = charas
    end

    -- One status-line row. Each field is read under its own pcall, so one failure shows "?" for that field only.
    local function read_row(chara)
        local function try(fn)
            local ok, v = pcall(fn)
            if ok then return v end
            return nil
        end
        local human = try(function() return chara:call("get_Human") end)
        local st = human and try(function() return human:call("get_StatusContext") end)
        local jc = human and try(function() return human:call("get_JobContext") end)
        local job = jc and try(function() return jc:call("get_Job") end)
        local name = m_gui_name and try(function() return m_gui_name:call(nil, chara) end)
        return {
            name = name ~= nil and tostring(name) or nil,
            level = st and try(function() return st:call("get_Level") end) or nil,
            job = job,
            rank = jc and job and try(function() return jc:call("calcJobRank", job) end) or nil,
            discipline = jc and try(function() return jc:call("get_ConsumableExpProp") end) or nil,
        }
    end

    local party = { failed = false }

    function party.refresh()
        local ok, err = pcall(refresh_targets)
        party.failed = not ok
        if not ok then
            state.targets = {}
            party_loaded = false
            target_charas = {}
            report("refresh", err)
        end
    end

    function party.rows()
        if not party_loaded then return nil end
        local rows = {}
        for i, chara in ipairs(target_charas) do rows[i] = read_row(chara) end
        return rows
    end

    return party
end

return M
