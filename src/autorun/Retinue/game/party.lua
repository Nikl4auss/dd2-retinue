-- REFramework glue: reads the party each frame into views (uses sdk) and the status-line rows.
-- The decisions live in Retinue/{roster,targets,status}.lua; who is a target is decided in Retinue/targets.lua.

local hooks = require("Retinue.hooks")
local ids = require("Retinue.ids")
local roster = require("Retinue.roster")

local M = {}

local OWNER_CONTEXT = "app.PawnOwnerContext"

-- A managed or Lua string as a Lua string, else nil.
local function as_string(v)
    if type(v) == "string" then return v end
    if v ~= nil then -- a managed object (userdata): its ToString
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

-- The CurrentContext of the given type (a full type name) in a pawn's context holder (chara:call("get_Context")),
-- nil when the holder has none. Throws when a read fails.
function M.holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

-- Returns an object with:
--   refresh()      -- the pcall'd party read; on a throw clears the views and reports "refresh"
--   views()        -- array (party order) of { slot, character_id, owner, offline_id, name, chara }; empty when no
--                     party is loaded. slot = index in _PartyPawnList (0 main pawn, 1-2 hired pawns); owner is the
--                     PawnOwnerContext _Name (string|nil), offline_id its canonical _OfflineID (nil for the main
--                     pawn's zero GUID), name the display name; character_id and chara are read every frame, the
--                     other three only when the party's CharacterID list changes or after an incomplete read
--   changed()      -- true on the frame the cached part was re-read (the roster store refreshes its cache then)
--   rows(set)      -- nil when no party is loaded, else an array of read_row results (the status.format input) for
--                     the views whose character_id is in set (the current targets), in party order
--   level(view)    -- the pawn's level read now (nil on failure), for the menu
--   failed         -- boolean, last refresh threw
--   has_main_pawn() -- whether the main pawn is in the party as of the last refresh (false when no party)
function M.new(report)
    local td_guibase = sdk.find_type_definition("app.GUIBase")
    local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")

    local function try(fn)
        local ok, v = pcall(fn)
        if ok then return v end
        return nil
    end

    -- Set by refresh each frame. party_loaded: PawnManager and its party list exist.
    local party_loaded = false
    local party_views = {}
    local main_pawn_in_party = false
    local was_changed = false
    -- The cached part, keyed by the party's CharacterID list: cache_key = "slot:id,..." of the last read (nil =
    -- none valid), cache[n] = { owner, offline_id, name } for views[n]. A CharacterID can only be reused by another
    -- pawn across a dismiss, which changes the list, so the key is safe.
    local cache_key, cache = nil, {}

    -- Owner, canonical Offline ID and name of one pawn; each read under its own pcall. complete = false when the
    -- owner context or the name could not be read (the next frame reads again).
    local function read_identity(chara)
        local info, complete = {}, true
        local ctx = nil
        local okc, errc = pcall(function()
            local holder = chara:call("get_Context")
            if not holder then return end
            ctx = M.holder_context(holder, OWNER_CONTEXT)
        end)
        if not okc then report("owner context", errc) end
        if ctx then
            local okn, name = pcall(function() return as_string(ctx:get_field("_Name")) end)
            if okn then info.owner = name else report("owner name", name); complete = false end
            local oko, guid = pcall(function() return as_string(ctx:get_field("_OfflineID")) end)
            if oko then
                info.offline_id = roster.canonical_id(guid) -- nil for the zero GUID (the main pawn)
                if guid == nil then complete = false end
            else
                report("offline id", guid)
                complete = false
            end
        else
            complete = false
        end
        local name = m_gui_name and try(function() return m_gui_name:call(nil, chara) end)
        name = name ~= nil and tostring(name) or nil
        if name == "" then name = nil end
        info.name = name
        -- Without getName (a game update removed it) a nil name is permanent, not an incomplete read.
        if name == nil and m_gui_name then complete = false end
        return info, complete
    end

    local function refresh_views()
        party_views = {}
        party_loaded = false
        main_pawn_in_party = false
        was_changed = false
        local pm = sdk.get_managed_singleton("app.PawnManager")
        local party_list = pm and pm:get_field("_PartyPawnList")
        if not party_list then
            cache_key, cache = nil, {}
            return
        end
        party_loaded = true -- a save is loaded
        local key_parts = {}
        for i = 0, party_list:call("get_Count") - 1 do
            local pawn = party_list:call("get_Item", i)
            local chara = pawn and pawn:call("get_CachedCharacter")
            if chara then
                local id = hooks.to_u32(chara:call("get_CharaID"))
                if id ~= nil then
                    party_views[#party_views + 1] = { slot = i, character_id = id, chara = chara }
                    key_parts[#key_parts + 1] = i .. ":" .. tostring(id)
                    if id == ids.MAIN_PAWN then main_pawn_in_party = true end
                end
            end
        end
        local key = table.concat(key_parts, ",")
        if key ~= cache_key then
            was_changed = true
            local complete_all = true
            local new_cache = {}
            for n, view in ipairs(party_views) do
                local info, complete = read_identity(view.chara)
                new_cache[n] = info
                if not complete then complete_all = false end
            end
            cache = new_cache
            -- An incomplete read leaves the key unset, so the next frame reads again.
            cache_key = complete_all and key or nil
        end
        for n, view in ipairs(party_views) do
            local info = cache[n]
            view.owner, view.offline_id, view.name = info.owner, info.offline_id, info.name
        end
    end

    -- One status-line row. Each field is read under its own pcall, so one failure shows "?" for that field only.
    local function read_row(chara)
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
        local ok, err = pcall(refresh_views)
        party.failed = not ok
        if not ok then
            party_views = {}
            party_loaded = false
            main_pawn_in_party = false
            was_changed = false
            cache_key, cache = nil, {}
            report("refresh", err)
        end
    end

    function party.views()
        return party_views
    end

    function party.changed()
        return was_changed
    end

    function party.rows(set)
        if not party_loaded then return nil end
        local rows = {}
        for _, view in ipairs(party_views) do
            if set[view.character_id] then rows[#rows + 1] = read_row(view.chara) end
        end
        return rows
    end

    function party.level(view)
        local st = try(function() return view.chara:call("get_Human"):call("get_StatusContext") end)
        return st and try(function() return st:call("get_Level") end) or nil
    end

    function party.has_main_pawn()
        return main_pawn_in_party
    end

    return party
end

return M
