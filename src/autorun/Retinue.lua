-- Retinue (Dragon's Dogma 2, REFramework Lua): hired pawns level up.
--
-- At this stage the mod does one thing: pre-hooks on app.ExpDispenser.checkLevelUp and
-- app.ExpDispenser.addJobPoint replace the CharacterID of a hired pawn in your party with the main pawn's
-- fixed ID, so the game's own level-up path runs for them and they gain levels, discipline and vocation
-- rank from any exp source. Notifications still name the main pawn. The REFramework menu has a
-- "Retinue" section with one checkbox (in memory only, on at load) and a status line naming the party
-- pawns progression applies to (name, level, vocation, rank), read only while the menu is drawn. If a
-- hooked method cannot be found after a game update, no hook is installed and the menu says so.
--
-- Do NOT deploy tools/experiments/Retinue_Exp_Hooks.lua alongside this script: both would hook the same
-- methods and rewrite the same arguments.
--
-- The decisions live in Retinue/{targets,progression,errlog,status}.lua (pure, tested by tests/run.sh); this file
-- and Retinue/hooks.lua are the REFramework glue. Every hook body runs under pcall.

local errlog = require("Retinue.errlog")
local hooks = require("Retinue.hooks")
local progression = require("Retinue.progression")
local status = require("Retinue.status")
local targets = require("Retinue.targets")

local state = { enabled = true, available = false, targets = {} }
local missing = {}

local report = errlog.new(function(msg) log.error(msg) end)

-- Core pre body, shared by both hooks. The write is the last statement, so an error leaves the args as
-- passed. Booleans, exp and job points are never read or written.
local function make_entry(spec)
    return {
        key = spec.key, type = spec.type, sig = spec.sig,
        pre = function(args)
            local id = hooks.arg_u32(args[spec.id_arg])
            local new = progression.rewrite_id(id, state)
            if new then args[spec.id_arg] = sdk.to_ptr(new) end
        end,
    }
end

local entries = {}
for i, spec in ipairs(hooks.SPECS) do entries[i] = make_entry(spec) end

state.available, missing = hooks.install(entries, report)

-- Party read: called, never hooked.
local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")

local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")

-- Set by refresh_targets each frame; read by draw. party_loaded: PawnManager and its party list exist.
-- target_charas: app.Character of each party pawn in state.targets, in party order.
local party_loaded = false
local target_charas = {}

local function is_hired(id)
    local r = m_is_sub:call(nil, id)
    return r == true or r == 1
end

local function refresh_targets()
    state.targets = {}
    party_loaded = false
    target_charas = {}
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return end
    local party = pm:get_field("_PartyPawnList")
    if not party then return end
    party_loaded = true -- a save is loaded; without isSubPawn there are simply no targets
    if not m_is_sub then return end
    local party_ids, party_charas = {}, {}
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
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

re.on_frame(function()
    local ok, err = pcall(refresh_targets)
    if not ok then
        state.targets = {}
        party_loaded = false
        target_charas = {}
        report("refresh", err)
    end
end)

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

local function draw()
    local changed, value = imgui.checkbox("Hired pawns gain levels and vocation ranks", state.enabled)
    if changed then state.enabled = value end
    local rows = nil
    if party_loaded then
        rows = {}
        for i, chara in ipairs(target_charas) do rows[i] = read_row(chara) end
    end
    imgui.text(status.format(rows))
    for _, method_name in ipairs(missing) do
        imgui.text("Progression unavailable: " .. method_name .. " not found (game update?)")
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("Retinue") then
        local ok, err = pcall(draw)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
end)
