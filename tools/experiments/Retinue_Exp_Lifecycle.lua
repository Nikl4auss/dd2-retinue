-- Retinue Exp Lifecycle: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- What it answers (M2): what does the game do to a hired pawn on dismiss, lost, re-hire and save/load?
-- Is the ContextDBMS record deleted (and when)? What does the Rift's dismissed list keep? Does a re-hired pawn
-- come back with the same OfflineID / CharacterID / state? Which lost path fires, and does a lost pawn reach a
-- Rift list? See tools/experiments/README.md for the procedure.
--
-- The hooks are LOG-ONLY: they never change an argument or a return value, and none of them is a method the
-- mod hooks (the mod hooks only app.ExpDispenser members and GuiManager.reqJobRankUp), so this script can be
-- linked TOGETHER with the mod (deploy.sh --lifecycle).
-- The test-actions panel CALLS game methods (grant exp, dismiss, force lost) and so CHANGES saves:
-- BACK UP FIRST (tools/saves.sh backup <label>), once per run.
--
-- Output: reframework/data/Retinue/experiments/lifecycle_<timestamp>.json (one file per session, flushed every
-- 2 s when changed). Nothing is persisted between sessions. Hooks cannot be removed in REFramework, so all of
-- them are installed at load. Every hook body is wrapped in pcall: a bug here must never break a game call.
-- API names were checked against this game version's il2cpp_dump.json; conventions follow Retinue_Exp_Hooks.lua.

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "lifecycle_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 20000
local SPEC_CALL_CAP = 2000 -- per chatty (collapsing) hook, so none can exhaust the shared cap
local SNAPSHOT_CAP = 400
local ERROR_CAP = 200
local STACK_MAX = 64
local TRACKED_MAX = 64
local LIST_CAP = 64
local LOG_LINES = 12
local CONFIRM_SECONDS = 10.0
local AFTER_ACTION_SECONDS = 1.0
local EVENT_SNAPSHOT_FRAMES = 2
local STATE_REUSE_SECONDS = 0.25
local DEFAULT_EXP, DEFAULT_JP = 10000, 233 -- as UDD2P's Sphinx reward

local JOB_NAMES = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief", [5] = "Warrior",
    [6] = "Sorcerer", [7] = "Mystic Spearhand", [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}
local JOB_COUNT = 10

-- Session state (never persisted).
local log_calls, auto_snap = true, true
local suppress_log = false -- true while the script itself reads game state
local snap_label = ""
local hook_status, flush_status, refresh_status = "hooks not installed yet", "", "no data yet"
local flush_requested = false -- set by the UI, honoured in the update callback
local names = {} -- CharacterID -> last seen display name

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    started_clock = os.clock(),
    constants = {
        script = "Retinue_Exp_Lifecycle",
        main_id = MAIN_ID,
        call_cap = CALL_CAP,
        snapshot_cap = SNAPSHOT_CAP,
        refresh_seconds = REFRESH_SECONDS,
        flush_seconds = FLUSH_SECONDS,
        job_names = JOB_NAMES,
    },
    snapshots = {},
    calls = {},
    actions = {},
    errors = {},
    hooks = { installed = {}, missing = {} },
    dropped = 0, -- call entries lost to the shared cap or to a per-hook cap
    dropped_by_spec = {}, -- the part of `dropped` lost to a per-hook cap, by hook
    dropped_snapshots = 0,
}
local calls = run.calls
local seq, dirty, frame_no = 0, true, 0
local last_flush, last_refresh = -FLUSH_SECONDS, -REFRESH_SECONDS
local stack = {} -- frames of in-flight hooked calls (pre pushes, post pops)
local last_entry, last_collapse_key = nil, nil
local spec_counts = {} -- hook key -> entries appended so far, for the per-hook cap

-- Pawn tracking: every (CharacterID, OfflineID) seen since session start.
local tracked, tracked_order, by_id, uniq_to_id = {}, {}, {}, {}
local state_cache = {} -- CharacterID -> { t, seq } of the last full state recorded from a hook
local dismissed_count, lost_timer_count = nil, nil
local limits_tries = 0

local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_pu_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")
local m_pu_is_main = td_pawn_util and td_pawn_util:get_method("isMainPawn(app.CharacterID)")
local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")
local td_dbms = sdk.find_type_definition("app.ContextDBMS")
local m_has_record = td_dbms and td_dbms:get_method("hasRecord(app.UniqueID)")
local td_im = sdk.find_type_definition("app.ItemManager")
local m_get_equip = td_im and td_im:get_method("getEquipData(app.CharacterID)")
local td_pm = sdk.find_type_definition("app.PawnManager")
local td_exp = sdk.find_type_definition("app.ExpDispenser")
local td_npc = sdk.find_type_definition("app.NPCManager")

-- ---------------------------------------------------------------------------------------------------------
-- Small helpers

-- Returns the value, or "ERR: ..." so one broken read never hides the rest.
local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return "ERR: " .. tostring(v)
end

local function str(v)
    if v == nil then return "nil" end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and s then return tostring(s) end
    end
    return tostring(v)
end

-- Makes a value safe for json.dump_file (no userdata/functions).
local function sanitize(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
    if t == "table" then
        local o = {}
        for k, x in pairs(v) do o[k] = sanitize(x) end
        return o
    end
    return str(v)
end

local function wall() return os.date("%H:%M:%S") end

local function log_error(where, err)
    if #run.errors < ERROR_CAP then
        run.errors[#run.errors + 1] = { t = os.clock(), where = where, err = tostring(err) }
        dirty = true
    end
end

local function to_u32(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return i & 0xFFFFFFFF end
    end
    return v
end

local function is_err(v) return type(v) == "string" and v:sub(1, 5) == "ERR: " end

-- Hook argument decoding (args[n] are raw pointer-sized values).
local function arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end
local function arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
local function arg_bool(a) return (sdk.to_int64(a) & 1) == 1 end
local function arg_nonnull(a) return sdk.to_int64(a) ~= 0 end

-- Reads a System.Guid passed by value (hidden pointer) in a hook. In-game-only: falls back to "unreadable".
local function arg_guid(a)
    if sdk.to_valuetype then
        local ok, v = pcall(sdk.to_valuetype, a, "System.Guid")
        if ok and v ~= nil then return str(v) end
    end
    local ok2, o = pcall(sdk.to_managed_object, a)
    if ok2 and o ~= nil then return str(o) end
    return "unreadable"
end

local function read_int_array(arr)
    if arr == nil then return nil end
    local out = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do out[i] = type(v) == "number" and v or str(v) end
        return out
    end
    local n = arr:call("get_Length")
    for i = 0, n - 1 do
        local v = arr:call("GetValue", i)
        out[i + 1] = type(v) == "number" and v or str(v)
    end
    return out
end

-- Reads a List<T> of numbers/enums (capped).
local function read_list(list)
    if list == nil then return nil end
    local n = list:call("get_Count")
    local out = { count = n, items = {} }
    for i = 0, math.min(n, LIST_CAP) - 1 do
        local v = list:call("get_Item", i)
        out.items[#out.items + 1] = type(v) == "number" and v or str(v)
    end
    return out
end

local function job_label(job)
    if type(job) ~= "number" then return str(job) end
    return string.format("%d (%s)", job, JOB_NAMES[job] or "?")
end

local function singleton(name) return sdk.get_managed_singleton(name) end

-- ContextHolder.Contexts is Dictionary<System.Type, ContextInfoBase>.
local function holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

-- ContextDatabaseRecord.ContextDict is Dictionary<System.Type, Context>.
local function record_context(record, type_name)
    local dict = record:get_field("ContextDict")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key)
end

-- Entries of a Dictionary<K,V> through its backing array (no enumerator needed).
local function dict_pairs(dict)
    local out = {}
    local count = dict:get_field("_count")
    local entries = dict:get_field("_entries"):get_elements()
    for i = 1, math.min(type(count) == "number" and count or #entries, #entries, LIST_CAP) do
        local e = entries[i]
        local nxt = e:get_field("next")
        -- .NET Core layout: a removed entry sits on the free list with next < -1
        if not (type(nxt) == "number" and nxt < -1) then
            out[#out + 1] = { key = e:get_field("key"), value = e:get_field("value") }
        end
    end
    return out
end

-- app.StrayPawnFactoryDataOffline -> plain table.
local function decode_offline(d)
    if d == nil then return nil end
    local r = {}
    local cid = try(function() return d:get_field("CharaID") end)
    r.CharaID = to_u32(cid)
    r.OfflineID = try(function() return str(d:get_field("OfflineID")) end)
    r.Level = try(function() return d:get_field("Level") end)
    local job = try(function() return d:get_field("Job") end)
    r.Job = job
    r.job_name = type(job) == "number" and JOB_NAMES[job] or nil
    r.name = try(function() return d:call("get_PawnName") end)
    return r
end

-- ---------------------------------------------------------------------------------------------------------
-- Pawn identity and tracking

-- Offline ID (as a string) and UniqueID object of a live actor, from its PawnOwnerContext.
local function owner_of(chara)
    local holder = chara:call("get_Context")
    if not holder then return nil end
    local owner = holder_context(holder, "app.PawnOwnerContext")
    local offline
    if owner then offline = str(owner:get_field("_OfflineID")) end
    return offline, holder:call("get_UniqID"), holder
end

local function chara_id_of(chara)
    return to_u32(chara:call("get_CharaID"))
end

local function upsert(ident, party_slot)
    if type(ident.id) ~= "number" then return nil end
    local id, offline = ident.id, ident.offline
    local row = by_id[id]
    if row and offline and row.offline and row.offline ~= offline then row = nil end -- the ID was reused
    if not row then
        if #tracked_order >= TRACKED_MAX then return nil end
        row = { id = id, offline = offline, first_clock = os.clock() }
        tracked_order[#tracked_order + 1] = row
        by_id[id] = row
    end
    if offline and not row.offline then row.offline = offline end
    if ident.name then row.name = ident.name end
    if ident.uniq_str then
        row.uniq_str, row.uniq_obj = ident.uniq_str, ident.uniq_obj
        uniq_to_id[ident.uniq_str] = id
    end
    if party_slot then row.in_party, row.slot, row.last_party_clock = true, party_slot, os.clock() end
    tracked[id .. "/" .. tostring(row.offline)] = row
    return row
end

-- Identity of an app.Character (live actor). Safe to call from hooks: reads only.
local function ident_of_chara(chara)
    local ident = { chara = chara }
    local ok, err = pcall(function()
        ident.id = chara_id_of(chara)
        local nm = str(try(function() return m_gui_name:call(nil, chara) end))
        ident.name = nm
        names[ident.id] = nm
        local offline, uniq_obj = owner_of(chara)
        ident.offline = offline
        if uniq_obj then ident.uniq_obj, ident.uniq_str = uniq_obj, str(uniq_obj) end
    end)
    if not ok then ident.err = tostring(err) end
    if ident.id then upsert(ident) end
    return ident
end

local function ident_of_id(id)
    local row = by_id[id]
    return { id = id, name = names[id] or (row and row.name), offline = row and row.offline }
end

-- ---------------------------------------------------------------------------------------------------------
-- Party access

local function party_list()
    local pm = singleton("app.PawnManager")
    if not pm then return nil end
    return pm:get_field("_PartyPawnList")
end

-- Live actor of CharacterID `id` in the party, or nil.
local function find_party_chara(id)
    local party = party_list()
    if not party then return nil end
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara and chara_id_of(chara) == id then return chara end
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- Pawn state (snapshots and "last chance" reads in hooks)

local function record_state(id, uniq_obj)
    local out = {}
    local dbms = singleton("app.ContextDBMS")
    out.by_charid = try(function()
        local c2k = dbms:call("get_CurrentDB"):get_field("IndexCreator"):get_field("CharacterID2Keys")
        return c2k:call("ContainsKey", id)
    end)
    if uniq_obj then
        out.by_uniqid = try(function() return m_has_record:call(dbms, uniq_obj) end)
    end
    return out
end

-- The ContextDatabaseRecord of CharacterID `id`, or nil.
local function find_record(id)
    local dbms = singleton("app.ContextDBMS")
    local db = dbms:call("get_CurrentDB")
    local c2k = db:get_field("IndexCreator"):get_field("CharacterID2Keys")
    if not c2k:call("ContainsKey", id) then return nil end
    local key = c2k:call("get_Item", id)
    return db:call("getRecordInfo", key):call("get_Record")
end

local function job_numbers(r, jc)
    local cur = try(function() return jc:get_field("CurrentJob") end)
    if type(cur) ~= "number" then cur = try(function() return jc:call("get_Job") end) end
    r.current_job = type(cur) == "number" and job_label(cur) or cur
    r.discipline = try(function() return jc:get_field("ConsumableExp") end)
    r.culmative_exp = try(function() return read_int_array(jc:get_field("CulmativeExp")) end)
    local ranks = {}
    for j = 1, JOB_COUNT do ranks[j] = try(function() return jc:call("calcJobRank", j) end) end
    r.job_ranks = ranks -- index = JobEnum value 1..10
    if type(cur) == "number" then r.current_rank = try(function() return jc:call("calcJobRank", cur) end) end
end

local function context_fields(r, get_ctx)
    local owner = try(get_ctx, "app.PawnOwnerContext")
    if type(owner) == "userdata" then
        r.offline_id = try(function() return str(owner:get_field("_OfflineID")) end)
        local user = try(function() return str(owner:get_field("_UserId")) end)
        r.owner_user_id = user
        -- CAPCOM pawns carry an all-zero _UserId (to be confirmed in game); anything else is another player.
        r.owner = (type(user) == "string" and user:match("^[0%-]+$")) and "capcom" or "user"
        r.owner_name = try(function() return owner:get_field("_Name") end)
        r.owner_level = try(function() return owner:get_field("_Level") end)
        r.owner_slot_id = try(function() return str(owner:get_field("_SlotId")) end)
        r.owner_offline_data = try(function() return decode_offline(owner:get_field("_OfflineData")) end)
    else r.owner = owner == nil and "none" or owner end

    local sub = try(get_ctx, "app.SubPawnDataContext")
    if type(sub) == "userdata" then
        r.hire_time = try(function() return sub:get_field("_HireTime") end)
    end

    local wc = try(get_ctx, "app.WeaponContext")
    if type(wc) == "userdata" then
        r.weapons = {
            left = try(function() return wc:get_field("LeftWeapon") end),
            right = try(function() return wc:get_field("RightWeapon") end),
        }
    end

    local sk = try(get_ctx, "app.HumanSkillContext")
    if type(sk) == "userdata" then
        r.skills = try(function()
            local out = { equiped = {} }
            local arr = sk:get_field("EquipedSkills"):get_elements()
            for i, e in ipairs(arr) do out.equiped[i] = read_int_array(e:get_field("Skills")) end
            out.normal = read_list(sk:call("getEnableNormalSkillIDs"))
            return out
        end)
    end
end

local function read_equipment(id)
    local im = singleton("app.ItemManager")
    -- getEquipData probably returns EmptyEquipData rather than null for an unknown ID: ask hasEquipData first
    if im:call("hasEquipData", id) ~= true then return { present = false } end
    local red = m_get_equip:call(im, id)
    if red == nil then return { present = false } end
    local out = { present = true, slots = {} }
    out.item_ids = read_list(red:call("getItemIds"))
    local list = red:call("get_EquipList")
    for i = 0, math.min(list:call("get_Count"), LIST_CAP) - 1 do
        local sd = list:call("get_Item", i)
        out.slots[#out.slots + 1] = {
            index = i, -- EquipData.SlotEnum order; the index-to-slot mapping is not assumed
            item_id = try(function() return sd:get_field("_ItemId") end),
            equip_slot = try(function() return sd:get_field("_EquipSlot") end),
        }
    end
    return out
end

-- Full state of one pawn. `chara` is the live actor or nil (then the ContextDBMS record is read, if any).
-- opts.light: skip the Rift-list lookup (used inside hooks, where manager locks may be held).
local function read_pawn_state(id, chara, opts)
    local r = { character_id = id }
    local row = by_id[id]
    local uniq_obj = row and row.uniq_obj
    local get_ctx
    if chara then
        r.source = "actor"
        r.name = str(try(function() return m_gui_name:call(nil, chara) end))
        local holder = chara:call("get_Context")
        if holder then
            r.is_restore = try(function() return holder:call("get_IsRestore") end)
            r.is_store = try(function() return holder:call("get_IsStore") end)
            uniq_obj = holder:call("get_UniqID") or uniq_obj
            r.uniq_id = str(uniq_obj)
            get_ctx = function(t) return holder_context(holder, t) end
        end
        local human = chara:call("get_Human")
        if human then
            local st = human:call("get_StatusContext")
            if st then
                r.level = try(function() return st:call("get_Level") end)
                r.exp = try(function() return st:call("get_Exp") end)
            end
            local jc = human:call("get_JobContext")
            if jc then try(job_numbers, r, jc) end
        end
    else
        r.name = names[id]
        local rec = try(find_record, id)
        if type(rec) == "userdata" then
            r.source = "record"
            get_ctx = function(t) return record_context(rec, t) end
            local st = try(get_ctx, "app.HumanStatusContext")
            if type(st) == "userdata" then
                r.level = try(function() return st:call("get_Level") end)
                r.exp = try(function() return st:call("get_Exp") end)
            end
            local jc = try(get_ctx, "app.JobContext")
            if type(jc) == "userdata" then try(job_numbers, r, jc) end
        else
            r.source = is_err(rec) and rec or "none"
        end
    end
    if get_ctx then context_fields(r, get_ctx) end
    r.offline_id = r.offline_id or (row and row.offline)
    r.record = record_state(id, uniq_obj)
    r.equipment = try(read_equipment, id)
    if not (opts and opts.light) then
        local npc = singleton("app.NPCManager")
        r.in_dismissed_list = try(function() return npc:call("isStrayPawn_DisMissList", id) end)
    end
    return r
end

-- ---------------------------------------------------------------------------------------------------------
-- World state

local function read_world()
    local w = {}
    local pm = singleton("app.PawnManager")
    local npc = singleton("app.NPCManager")
    if pm then
        w.party = try(function()
            local out = {}
            local party = pm:get_field("_PartyPawnList")
            for i = 0, party:call("get_Count") - 1 do
                local pawn = party:call("get_Item", i)
                local chara = pawn and pawn:call("get_CachedCharacter")
                out[#out + 1] = chara and chara_id_of(chara) or "no character"
            end
            return out
        end)
        w.saved_party = try(function()
            local out = {}
            local saved = pm:get_field("_SavedPartyPawnList")
            for i = 0, saved:call("get_Count") - 1 do out[#out + 1] = to_u32(saved:call("get_Item", i)) end
            return out
        end)
        w.lost_timers = try(function()
            local out = {}
            for _, p in ipairs(dict_pairs(pm:get_field("_PawnLostTimers"))) do
                out[#out + 1] = {
                    id = to_u32(p.key),
                    time = try(function() return p.value:get_field("Time") end),
                    paused = try(function() return p.value:get_field("IsPaused") end),
                    unique_id = try(function() return str(p.value:get_field("UniqueID")) end),
                }
            end
            return out
        end)
        w.lost_disabled = try(function() return pm:get_field("_IsDisableLost") end)
        w.pawn_lost_time = try(function() return pm:get_field("PawnLostTime") end)
    end
    if npc then
        w.dismissed_list = try(function()
            local out = {}
            local list = npc:call("getStrayPawn_DisMissList")
            for i = 0, math.min(list:call("get_Count"), LIST_CAP) - 1 do
                local e = list:call("get_Item", i)
                out[#out + 1] = decode_offline(e:get_field("OfflineData"))
            end
            return out
        end)
    end
    return w
end

local function read_limits()
    local c = run.constants
    if c.StrayPawnPastInformationMax == nil then
        local v = try(function() return td_npc:get_field("StrayPawnPastInformationMax"):get_data(nil) end)
        if type(v) == "number" then c.StrayPawnPastInformationMax = v end
    end
    if c.RelationPawnDismissNum == nil then
        local v = try(function()
            -- PawnServerController is a via.Behavior, not a singleton: reach it through NetworkManager
            return singleton("app.NetworkManager"):call("getPawnServerModeController"):call("get_PawnRentalConfig")
                :get_field("StrayPawnCacheParam"):get_field("RelationPawnDismissNum")
        end)
        if type(v) == "number" then c.RelationPawnDismissNum = v end
    end
    limits_tries = limits_tries + 1
    if limits_tries >= 10 then
        c.StrayPawnPastInformationMax = c.StrayPawnPastInformationMax or "unavailable"
        c.RelationPawnDismissNum = c.RelationPawnDismissNum or "unavailable"
    end
    dirty = true
    return c.StrayPawnPastInformationMax ~= nil and c.RelationPawnDismissNum ~= nil
end

-- Takes a snapshot now. Returns its index in run.snapshots (nil if the cap was hit).
local function take_snapshot(label, kind)
    if #run.snapshots >= SNAPSHOT_CAP then
        run.dropped_snapshots = run.dropped_snapshots + 1
        return nil
    end
    local idx
    local was = suppress_log
    suppress_log = true
    local ok, err = pcall(function()
        local pawns, in_party = {}, {}
        local party = party_list()
        if party then
            for i = 0, party:call("get_Count") - 1 do
                local pawn = party:call("get_Item", i)
                local chara = pawn and pawn:call("get_CachedCharacter")
                local r
                if not chara then
                    r = { slot = i + 1, error = pawn and "no character" or "nil pawn" }
                else
                    local ident = ident_of_chara(chara)
                    upsert(ident, i + 1)
                    local ok_r, v = pcall(read_pawn_state, ident.id, chara)
                    r = ok_r and v or { character_id = ident.id, error = tostring(v) }
                    r.slot, r.in_party = i + 1, true
                    in_party[ident.id] = true
                end
                pawns[#pawns + 1] = sanitize(r)
            end
        end
        for _, row in ipairs(tracked_order) do
            if not in_party[row.id] or by_id[row.id] ~= row then
                local ok_r, v
                if by_id[row.id] == row then
                    ok_r, v = pcall(read_pawn_state, row.id, nil)
                else -- its CharacterID now belongs to another pawn: reading by ID would return that one
                    ok_r, v = true, { character_id = row.id, superseded = true }
                end
                local r = ok_r and v or { character_id = row.id, error = tostring(v) }
                r.in_party = false
                r.offline_id = r.offline_id or row.offline
                r.name = r.name or row.name
                pawns[#pawns + 1] = sanitize(r)
            end
        end
        local world = sanitize(read_world())
        run.snapshots[#run.snapshots + 1] = {
            label = label, kind = kind or "manual", time = wall(), t = os.clock(), seq = seq,
            pawns = pawns, world = world,
        }
        idx = #run.snapshots
        dirty = true
    end)
    suppress_log = was
    if not ok then log_error("snapshot " .. tostring(label), err) end
    return idx
end

-- Deferred snapshots: run a few frames (or seconds) after the event, never inside the hook that raised it.
local pending = {}
local function schedule_snapshot(label, opts)
    opts = opts or {}
    if not auto_snap and not opts.force then return end
    for _, p in ipairs(pending) do
        if p.label == label then return end
    end
    pending[#pending + 1] = {
        label = label, kind = opts.kind or "auto",
        due_frame = frame_no + (opts.frames or EVENT_SNAPSHOT_FRAMES),
        due_clock = os.clock() + (opts.seconds or 0),
        on_done = opts.on_done,
    }
end

local function process_pending()
    local now = os.clock()
    local keep = {}
    for _, p in ipairs(pending) do
        if frame_no >= p.due_frame and now >= p.due_clock then
            local idx = take_snapshot(p.label, p.kind)
            if p.on_done then pcall(p.on_done, idx) end
        else
            keep[#keep + 1] = p
        end
    end
    pending = keep
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook specs
-- Every hooked method is an instance method: args[1] is the thread context, args[2] `this`, parameters from
-- args[3] (param k at args[2 + k]). `params`: { name, kind }; the pawn's identity (CharacterID, OfflineID,
-- name) is merged from every parameter that yields one; `ret`: return decoder; `post`: also log the
-- post phase; `state`: record the pawn's full state in pre (last chance to read it); `snap`: label of the
-- deferred snapshot scheduled in post; `reread`: re-read the pawn's identity in post; `collapse`: merge
-- consecutive identical entries (and cap the hook at SPEC_CALL_CAP entries).

local function P(name, kind) return { name, kind } end

local PM, NPC, DBMS, DB = "app.PawnManager", "app.NPCManager", "app.ContextDBMS", "app.ContextDatabase"
local SPECS = {
    { key = "PawnManager.dismissPawn(CharacterID)", type = PM, sig = "dismissPawn(app.CharacterID)",
      params = { P("id", "cid") }, post = true, state = true, snap = "auto:dismiss" },
    { key = "PawnManager.dismissPawn(Character)", type = PM, sig = "dismissPawn(app.Character)",
      params = { P("chara", "chara") }, post = true, state = true, snap = "auto:dismiss" },
    { key = "PawnManager.dismissPawn(Pawn)", type = PM, sig = "dismissPawn(app.Pawn)",
      params = { P("pawn", "pawn") }, post = true, state = true, snap = "auto:dismiss" },
    { key = "SoundVoiceManager.onDismissUnloadPawnEvent", type = "app.SoundVoiceManager",
      sig = "onDismissUnloadPawnEvent(app.CharacterID)", params = { P("id", "cid") } },
    { key = "NPCManager.addStrayPawn_DisMissList", type = NPC,
      sig = "addStrayPawn_DisMissList(app.CharacterID, app.StrayPawnFactoryDataOffline)",
      params = { P("id", "cid"), P("data", "offdata") }, post = true },
    { key = "ContextDBMS.deleteRecord(UniqueID)", type = DBMS, sig = "deleteRecord(app.UniqueID)",
      params = { P("uniq", "uniq") }, post = true },
    { key = "ContextDBMS.deleteRecord(CharacterID)", type = DBMS, sig = "deleteRecord(app.CharacterID)",
      params = { P("id", "cid") }, post = true },
    { key = "ContextDatabase.deleteContexts(Key)", type = DB, sig = "deleteContexts(app.ContextDatabaseKey)",
      params = { P("key", "dbkey") }, collapse = true },
    { key = "ContextDatabase.deleteContexts(Func)", type = DB,
      sig = "deleteContexts(System.Func`2<app.IContextDatabaseIndexCreator,app.ContextDatabaseKey>)",
      params = { P("fn_nonnull", "ptr") }, collapse = true },
    { key = "Human.setDisableContextStoreOnDissmissPawn", type = "app.Human",
      sig = "setDisableContextStoreOnDissmissPawn(app.Character)", params = { P("chara", "chara") } },
    { key = "Human.setEnableContextStoreOnHirePawn", type = "app.Human",
      sig = "setEnableContextStoreOnHirePawn(app.Character)", params = { P("chara", "chara") } },
    { key = "ItemManager.returnSubPawnItems", type = "app.ItemManager", sig = "returnSubPawnItems(app.CharacterID)",
      params = { P("id", "cid") }, post = true },
    { key = "PawnManager.setPawnLostTimer", type = PM, sig = "setPawnLostTimer(app.Character)",
      params = { P("chara", "chara_light") }, collapse = true },
    { key = "PawnManager.resetPawnLostTimer(Character)", type = PM, sig = "resetPawnLostTimer(app.Character)",
      params = { P("chara", "chara_light") }, collapse = true },
    { key = "PawnManager.resetPawnLostTimer(CharacterID)", type = PM, sig = "resetPawnLostTimer(app.CharacterID)",
      params = { P("id", "cid") }, collapse = true },
    { key = "PawnManager.lost", type = PM, sig = "lost(app.CharacterID, System.Boolean, System.Boolean)",
      params = { P("id", "cid"), P("b1", "bool"), P("b2", "bool") }, post = true, state = true,
      snap = "auto:lost" },
    { key = "PawnManager.pawnLost(Character)", type = PM,
      sig = "pawnLost(app.Character, System.Boolean, System.Boolean)",
      params = { P("chara", "chara"), P("b1", "bool"), P("b2", "bool") }, post = true, state = true,
      snap = "auto:lost" },
    { key = "PawnManager.pawnLost(InstanceInfo)", type = PM, sig = "pawnLost(app.InstanceInfo, app.DummyArg_2_0_0_37)",
      params = { P("info_nonnull", "ptr") }, post = true, snap = "auto:lost" },
    { key = "PawnManager.lostDeadPawns", type = PM, sig = "lostDeadPawns()", params = {}, post = true,
      snap = "auto:lost" },
    { key = "PawnManager.lostAllPawns", type = PM, sig = "lostAllPawns()", params = {}, post = true,
      snap = "auto:lost" },
    { key = "NPCManager.eventStrayPawnLost", type = NPC, sig = "eventStrayPawnLost(app.CharacterID)",
      params = { P("id", "cid") } },
    { key = "NPCManager.addStrayPawn_HireTime_DismissNotInstance", type = NPC,
      sig = "addStrayPawn_HireTime_DismissNotInstance(app.CharacterID)", params = { P("id", "cid") } },
    { key = "PawnManager.hirePawn", type = PM, sig = "hirePawn(app.Character, System.Boolean)",
      params = { P("chara", "chara"), P("flag", "bool") }, ret = "bool", post = true, reread = true,
      snap = "auto:hire-post" },
    { key = "ItemManager.onHirePawn", type = "app.ItemManager", sig = "onHirePawn(app.Character)",
      params = { P("chara", "chara") } },
    { key = "StrayPawnManager.getUnusedOfflineCharacterID(List,List)", type = "app.StrayPawnManager",
      sig = "getUnusedOfflineCharacterID(System.Collections.Generic.List`1<app.CharacterID>, System.Collections.Generic.List`1<System.Guid>)",
      params = { P("in_use", "list_cid"), P("offline_ids", "list_count") }, ret = "cid", post = true },
    { key = "StrayPawnManager.getUnusedOfflineCharacterID(List,Guid,Boolean)", type = "app.StrayPawnManager",
      sig = "getUnusedOfflineCharacterID(System.Collections.Generic.List`1<app.CharacterID>, System.Guid, System.Boolean)",
      params = { P("in_use", "list_cid"), P("offline_id", "guid"), P("flag", "bool") }, ret = "cid", post = true },
    { key = "StrayPawnFactoryProductOffline.restorePastInformation", type = "app.StrayPawnFactoryProductOffline",
      sig = "restorePastInformation(app.CharacterID, System.Guid)",
      params = { P("id", "cid"), P("offline_id", "guid") }, post = true },
    { key = "StrayPawnFactory.preOrderFromRecord", type = "app.StrayPawnFactory",
      sig = "preOrderFromRecord(app.CharacterID, app.StrayPawnFactorySelectRecord)",
      params = { P("id", "cid"), P("record", "selrec") }, ret = "bool", post = true },
    { key = "StrayPawnFactory.makeRimSearchedOfflineProduct", type = "app.StrayPawnFactory",
      sig = "makeRimSearchedOfflineProduct(app.CharacterID, app.StrayPawnFactoryDataOffline, app.StrayPawnFactoryRimSearch.QuestKnowledgeSet)",
      params = { P("id", "cid"), P("data", "offdata"), P("knowledge_nonnull", "ptr") }, ret = "ptr", post = true },
    { key = "ContextDBMS.restoreContextsToHolder(UniqueID)", type = DBMS,
      sig = "restoreContextsToHolder(app.UniqueID, app.ContextHolder)",
      params = { P("uniq", "uniq"), P("holder", "holder") }, collapse = true },
    { key = "ContextDBMS.restoreContextsToHolder(Int64)", type = DBMS,
      sig = "restoreContextsToHolder(System.Int64, app.ContextHolder)",
      params = { P("key64", "i64"), P("holder", "holder") }, collapse = true },
    { key = "ContextDBMS.createNewRecordIfNotExist", type = DBMS,
      sig = "createNewRecordIfNotExist(app.UniqueID, app.CharacterID, System.Action`1<app.ContextDatabaseRecord>)",
      params = { P("uniq", "uniq"), P("id", "cid"), P("fn_nonnull", "ptr") }, collapse = true },
    { key = "FacilityManager.startRim", type = "app.FacilityManager", sig = "startRim(app.GimmickBase)",
      params = { P("gimmick", "obj") }, post = true, snap = "auto:rift-start" },
    { key = "FacilityManager.endInteractRimAction()", type = "app.FacilityManager", sig = "endInteractRimAction()",
      params = {}, post = true, snap = "auto:rift-end" },
    { key = "FacilityManager.endInteractRimAction(String)", type = "app.FacilityManager",
      sig = "endInteractRimAction(System.String)", params = { P("name_nonnull", "ptr") }, post = true,
      snap = "auto:rift-end" },
    { key = "PawnManager.registPawn", type = PM, sig = "registPawn(app.Character)",
      params = { P("chara", "chara_light") }, ret = "ptr", post = true },
    { key = "PawnManager.unregistPawn", type = PM, sig = "unregistPawn(app.Character)",
      params = { P("chara", "chara_light") }, post = true },
}

for _, spec in ipairs(SPECS) do
    if spec.collapse then spec.cap = SPEC_CALL_CAP end
end

-- Decoders: (raw arg) -> value stored in the entry, optional identity { id, offline, name, chara }.
local DEC = {
    i32 = function(a) return arg_i32(a) end,
    i64 = function(a) return sdk.to_int64(a) end,
    bool = function(a) return arg_bool(a) end,
    ptr = function(a) return arg_nonnull(a) end,
    guid = function(a)
        local s = arg_guid(a)
        return s, { offline = s ~= "unreadable" and s or nil }
    end,
    cid = function(a)
        local id = arg_u32(a)
        return id, ident_of_id(id)
    end,
    chara = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local ident = ident_of_chara(o)
        return ident.id or ident.err or "?", ident
    end,
    -- Only the CharacterID is read from the actor; the rest comes from the cache (for possibly hot methods).
    chara_light = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local id = chara_id_of(o)
        local ident = ident_of_id(id)
        ident.chara = o
        return id, ident
    end,
    pawn = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local chara = o:call("get_CachedCharacter")
        if chara == nil then return "no character" end
        local ident = ident_of_chara(chara)
        return ident.id or ident.err or "?", ident
    end,
    uniq = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local s = str(o)
        local id = uniq_to_id[s]
        local ident = id and ident_of_id(id) or {}
        return s, ident
    end,
    holder = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local s = str(try(function() return o:call("get_UniqID") end))
        return { uniq = s, is_restore = try(function() return o:call("get_IsRestore") end) }
    end,
    dbkey = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        return try(function() return o:get_field("KeyForSystem") end)
    end,
    offdata = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local d = decode_offline(o)
        return d, { id = type(d.CharaID) == "number" and d.CharaID or nil, offline = d.OfflineID }
    end,
    selrec = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local d = try(function() return decode_offline(o:get_field("OfflinePawnData")) end)
        local out = { data = d, is_online = try(function() return o:get_field("<IsOnline>k__BackingField") end),
            slot_id = try(function() return str(o:get_field("SlotId")) end) }
        return out, type(d) == "table" and { offline = d.OfflineID } or nil
    end,
    obj = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        return try(function() return o:get_type_definition():get_full_name() end)
    end,
    list_cid = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local l = read_list(o)
        local ids = {}
        for i, v in ipairs(l.items) do ids[i] = to_u32(v) end
        return { count = l.count, ids = ids }
    end,
    list_count = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        return { count = try(function() return o:call("get_Count") end) }
    end,
}

local RET_DEC = {
    bool = function(r) return arg_bool(r) end,
    ptr = function(r) return arg_nonnull(r) end,
    cid = function(r)
        local id = arg_u32(r)
        return id, ident_of_id(id)
    end,
}

local function decode_args(spec, args, frame)
    local out = {}
    for k, p in ipairs(spec.params) do
        local ok, v, ident = pcall(DEC[p[2]], args[2 + k])
        if ok then
            out[p[1]] = v
            if ident then
                local f = frame.ident
                if not f then
                    frame.ident = ident
                else -- fill what the first identity lacks (e.g. OfflineID from a Guid argument)
                    f.id = f.id or ident.id
                    f.offline = f.offline or ident.offline
                    f.name = f.name or ident.name
                    f.chara = f.chara or ident.chara
                end
            end
        else
            out[p[1]] = "ERR: " .. tostring(v)
        end
    end
    return out
end

-- Flat text of a value, for the collapse key.
local function flat(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. flat(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function append_entry(spec, entry)
    if #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
        return nil
    end
    entry = sanitize(entry)
    if spec.collapse then
        local k = table.concat({ entry.method, entry.phase, tostring(entry.id), tostring(entry.depth),
            flat(entry.args), flat(entry.ret) }, "|")
        if last_entry and calls[#calls] == last_entry and last_collapse_key == k then
            last_entry.count = (last_entry.count or 1) + 1
            last_entry.last_seq, last_entry.last_t = entry.seq, entry.t
            dirty = true
            return last_entry
        end
        entry.count = 1
        last_collapse_key = k
    else
        last_collapse_key = nil
    end
    if spec.cap then
        local n = spec_counts[spec.key] or 0
        if n >= spec.cap then
            run.dropped = run.dropped + 1
            run.dropped_by_spec[spec.key] = (run.dropped_by_spec[spec.key] or 0) + 1
            return nil
        end
        spec_counts[spec.key] = n + 1
    end
    calls[#calls + 1] = entry
    last_entry = entry
    dirty = true
    return entry
end

-- Full state of the target pawn, read inside the hook (last chance before the game drops it).
local function capture_state(frame, entry_seq)
    local ident = frame.ident or {}
    local id = ident.id
    if type(id) ~= "number" then return { note = "no CharacterID in the arguments" } end
    local cached = state_cache[id]
    if cached and os.clock() - cached.t < STATE_REUSE_SECONDS then
        return { same_as_seq = cached.seq }
    end
    local chara = ident.chara or find_party_chara(id)
    local r = read_pawn_state(id, chara, { light = true })
    r.found_actor = chara ~= nil
    state_cache[id] = { t = os.clock(), seq = entry_seq }
    return r
end

local function pre_body(spec, args)
    local depth = #stack
    if depth >= STACK_MAX then
        stack = {}
        depth = 0
        log_error("stack", "in-flight stack overflow, reset")
    end
    local frame = { key = spec.key, depth = depth }
    stack[depth + 1] = frame -- pushed first: post must find it even if the rest of this body throws
    seq = seq + 1
    if not log_calls or suppress_log then return end
    if #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
        return
    end
    local was = suppress_log
    suppress_log = true -- our own reads below must not be logged
    local ok, err = pcall(function()
        local dec = decode_args(spec, args, frame)
        local ident = frame.ident or {}
        local entry = {
            seq = seq, t = os.clock(), depth = depth, method = spec.key, phase = "pre",
            id = ident.id, offline_id = ident.offline, name = ident.name, args = dec,
        }
        frame.id, frame.offline = ident.id, ident.offline
        if spec.state then entry.state = capture_state(frame, seq) end
        frame.logged = append_entry(spec, entry) ~= nil
        frame.pre_seq = seq
    end)
    suppress_log = was
    if not ok then log_error("pre " .. spec.key, err) end
end

local function post_body(spec, retval)
    local frame
    for i = #stack, 1, -1 do
        if stack[i].key == spec.key then
            frame = stack[i]
            for j = #stack, i, -1 do stack[j] = nil end -- also drops frames whose post never ran
            break
        end
    end
    if not frame then return end
    if spec.snap then schedule_snapshot(spec.snap) end
    if not (spec.post and frame.logged) then return end
    local entry = {
        seq = nil, t = os.clock(), depth = frame.depth, method = spec.key, phase = "post",
        id = frame.id, offline_id = frame.offline, pre_seq = frame.pre_seq,
    }
    seq = seq + 1
    entry.seq = seq
    if spec.ret then
        local ok, v, ident = pcall(RET_DEC[spec.ret], retval)
        entry.ret = ok and v or ("ERR: " .. tostring(v))
        if ok and ident and spec.ret == "cid" then
            entry.ret_name, entry.ret_offline_id = ident.name, ident.offline
        end
    end
    -- Re-read the OfflineID (`reread` specs only): after hirePawn the pawn's contexts are the new ones.
    if spec.reread and frame.ident and frame.ident.chara then
        local was = suppress_log
        suppress_log = true
        local ident = ident_of_chara(frame.ident.chara)
        suppress_log = was
        entry.offline_id = ident.offline or entry.offline_id
        entry.id = ident.id or entry.id
    end
    append_entry(spec, entry)
end

local function find_method(td, sig)
    local m = td:get_method(sig)
    if m then return m end
    local name, plist = sig:match("^([^%(]+)%((.*)%)$")
    if not name then return nil end
    local want = {}
    for p in plist:gmatch("[^,%s]+") do want[#want + 1] = p:match("([^%.]+)$") end
    for _, cand in ipairs(td:get_methods()) do
        if cand:get_name() == name then
            local ok, types = pcall(function() return cand:get_param_types() end)
            if ok and type(types) == "table" and #types == #want then
                local same = true
                for i, t in ipairs(types) do
                    local full = t:get_full_name() or ""
                    if full:match("([^%.]+)$") ~= want[i] then same = false; break end
                end
                if same then return cand end
            end
        end
    end
    return nil
end

local function install_hooks()
    local installed, missing = {}, {}
    for _, spec in ipairs(SPECS) do
        local ok, err = pcall(function()
            local td = sdk.find_type_definition(spec.type)
            if not td then error("type not found: " .. spec.type) end
            local m = find_method(td, spec.sig)
            if not m then error("method not found: " .. spec.sig) end
            sdk.hook(m,
                function(args)
                    local ok_pre, e = pcall(pre_body, spec, args)
                    if not ok_pre then log_error("pre " .. spec.key, e) end
                    return sdk.PreHookResult.CALL_ORIGINAL
                end,
                function(retval)
                    local ok_post, e = pcall(post_body, spec, retval)
                    if not ok_post then log_error("post " .. spec.key, e) end
                    return retval
                end)
        end)
        if ok then installed[#installed + 1] = spec.key
        else
            missing[#missing + 1] = spec.key
            log_error("install " .. spec.key, err)
        end
    end
    run.hooks.installed, run.hooks.missing = installed, missing
    if #missing == 0 then
        hook_status = string.format("all %d hooks installed", #installed)
    else
        hook_status = string.format("%d/%d hooks installed; MISSING: %s", #installed, #SPECS,
            table.concat(missing, ", "))
    end
    dirty = true
end

-- ---------------------------------------------------------------------------------------------------------
-- Test actions (calls, no hooks). Queued by the UI, executed in the update callback (game thread).

local ta = { slot = 1, exp_text = tostring(DEFAULT_EXP), jp_text = tostring(DEFAULT_JP), b1 = false, b2 = false }
local armed = nil -- { kind, slot, id, b1, b2, deadline }
local action_queue = {}
local m_exp_add = td_exp and td_exp:get_method("addExpAndJobPoint(app.CharacterID, System.Int32, System.Int32, app.Character)")
local m_dismiss_id = td_pm and td_pm:get_method("dismissPawn(app.CharacterID)")
local m_lost = td_pm and td_pm:get_method("lost(app.CharacterID, System.Boolean, System.Boolean)")
local td_cm = sdk.find_type_definition("app.CharacterManager")
local action_status = ""

-- The party member in slot N (1-based), or nil + why. Refuses the main pawn and the player.
local function resolve_target(slot)
    local pm = singleton("app.PawnManager")
    if not pm then return nil, "PawnManager not available" end
    local party = pm:get_field("_PartyPawnList")
    if slot < 1 or slot > party:call("get_Count") then return nil, "no pawn in slot " .. slot end
    local pawn = party:call("get_Item", slot - 1)
    local chara = pawn and pawn:call("get_CachedCharacter")
    if not chara then return nil, "slot " .. slot .. " has no character" end
    local id = chara_id_of(chara)
    if id == MAIN_ID then return nil, "refused: main pawn ch100000_00" end
    if m_pu_is_main:call(nil, id) == true then return nil, "refused: main pawn" end
    local cm = singleton("app.CharacterManager")
    local player = cm and cm:call("get_ManualPlayer")
    if player and chara_id_of(player) == id then return nil, "refused: the player" end
    if m_pu_is_sub:call(nil, id) ~= true then return nil, "refused: not a hired pawn" end
    return { id = id, chara = chara, pawn = pawn, ident = ident_of_chara(chara) }
end

local function run_action(job)
    local entry = {
        seq_before = seq, t = os.clock(), wall = wall(), kind = job.kind, slot = job.slot, args = job.args,
    }
    run.actions[#run.actions + 1] = entry
    dirty = true
    local target, why = resolve_target(job.slot)
    if not target then
        entry.ok, entry.error = false, why
        return
    end
    if job.expect_id and job.expect_id ~= target.id then
        entry.ok, entry.error = false, string.format("refused: slot %d now holds %d, armed for %d", job.slot,
            target.id, job.expect_id)
        return
    end
    entry.id, entry.name, entry.offline_id = target.id, target.ident.name, target.ident.offline
    entry.snapshot_before = take_snapshot(string.format("action:%s slot%d before", job.kind, job.slot), "action")
    local ok, res = pcall(function()
        if job.kind == "grant_exp" then
            return m_exp_add:call(nil, target.id, job.args.exp, job.args.job_point, target.chara)
        elseif job.kind == "dismiss" then
            return m_dismiss_id:call(singleton("app.PawnManager"), target.id)
        elseif job.kind == "lost" then
            return m_lost:call(singleton("app.PawnManager"), target.id, job.args.b1, job.args.b2)
        end
        error("unknown action " .. tostring(job.kind))
    end)
    entry.ok = ok
    if ok then entry.result = res == nil and "void" or str(res) else entry.error = tostring(res) end
    entry.seq_after = seq
    schedule_snapshot(string.format("action:%s slot%d after (action %d)", job.kind, job.slot, #run.actions), {
        seconds = AFTER_ACTION_SECONDS, force = true, kind = "action",
        on_done = function(idx) entry.snapshot_after = idx; dirty = true end,
    })
    action_status = string.format("%s slot %d: %s", job.kind, job.slot, ok and "called" or ("FAILED " .. tostring(res)))
end

local function queue_action(job) action_queue[#action_queue + 1] = job end

local function process_actions()
    if #action_queue == 0 then return end
    local q = action_queue
    action_queue = {}
    for _, job in ipairs(q) do
        local ok, err = pcall(run_action, job)
        if not ok then log_error("action " .. tostring(job.kind), err) end
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Once-a-second refresh (update callback, never inside hooks)

local auto_start_done = false

local function refresh()
    local was = suppress_log
    suppress_log = true
    local ok, err = pcall(function()
        local pm = singleton("app.PawnManager")
        if not pm then refresh_status = "PawnManager not available (load a save)"; return end
        for _, row in ipairs(tracked_order) do row.in_party, row.slot = false, nil end
        local party = pm:get_field("_PartyPawnList")
        local n = party:call("get_Count")
        for i = 0, n - 1 do
            local pawn = party:call("get_Item", i)
            local chara = pawn and pawn:call("get_CachedCharacter")
            if chara then
                local ident = ident_of_chara(chara)
                local row = upsert(ident, i + 1)
                if row then
                    local human = chara:call("get_Human")
                    local st = human and human:call("get_StatusContext")
                    if st then
                        row.level = try(function() return st:call("get_Level") end)
                        row.exp = try(function() return st:call("get_Exp") end)
                    end
                    local jc = human and human:call("get_JobContext")
                    if jc then row.job = try(function() return job_label(jc:call("get_Job")) end) end
                    row.record, row.dismissed = true, nil
                end
            end
        end
        local npc = singleton("app.NPCManager")
        for _, row in ipairs(tracked_order) do
            row.superseded = by_id[row.id] ~= row
            if not row.in_party and not row.superseded then
                local rs = record_state(row.id, row.uniq_obj)
                row.record = rs.by_charid
                if npc then row.dismissed = try(function() return npc:call("isStrayPawn_DisMissList", row.id) end) end
            end
        end
        dismissed_count = npc and try(function() return npc:call("getStrayPawn_DisMissList"):call("get_Count") end)
        lost_timer_count = try(function() return pm:get_field("_PawnLostTimers"):call("get_Count") end)
        refresh_status = string.format("%d party pawns, %d tracked", n, #tracked_order)
        if not auto_start_done and n > 0 then
            auto_start_done = true
            take_snapshot("auto:start", "auto")
        end
    end)
    suppress_log = was
    if not ok then
        refresh_status = "refresh failed: " .. tostring(err)
        log_error("refresh", err)
    end
    if run.constants.StrayPawnPastInformationMax == nil or run.constants.RelationPawnDismissNum == nil then
        local ok_l, e = pcall(read_limits)
        if not ok_l then log_error("read_limits", e) end
    end
end

local function flush()
    last_flush = os.clock()
    local ok, err = pcall(function() json.dump_file(RUN_FILE, run) end)
    if ok then
        dirty = false
        flush_status = "Flushed " .. wall()
    else
        flush_status = "Flush FAILED: " .. tostring(err)
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Wiring

install_hooks()

-- All game-state work (queued actions, deferred snapshots, the refresh, the flush) runs on the game thread at
-- the start of each update, as the mod does: re.on_frame and re.on_draw_ui may run on the render thread.
-- The draw side below only draws and sets flags.
re.on_pre_application_entry("UpdateBehavior", function()
    frame_no = frame_no + 1
    local now = os.clock()
    local ok, err = pcall(process_actions)
    if not ok then log_error("process_actions", err) end
    ok, err = pcall(process_pending)
    if not ok then log_error("process_pending", err) end
    if now - last_refresh >= REFRESH_SECONDS then
        last_refresh = now
        refresh()
    end
    if flush_requested or (dirty and now - last_flush >= FLUSH_SECONDS) then
        flush_requested = false
        flush()
    end
end)

if re.on_script_reset then
    re.on_script_reset(function() pcall(flush) end)
end

-- ---------------------------------------------------------------------------------------------------------
-- UI

local function fmt_entry(e)
    local parts = { string.format("#%d t=%.1f %s%s %s id=%s", e.seq, e.t, string.rep(">", e.depth or 0),
        e.method, e.phase or "", tostring(e.id)) }
    if e.offline_id then parts[#parts + 1] = "off=" .. tostring(e.offline_id):sub(1, 8) end
    if e.ret ~= nil then parts[#parts + 1] = "ret=" .. tostring(e.ret) end
    if e.count and e.count > 1 then parts[#parts + 1] = "x" .. e.count end
    return table.concat(parts, " ")
end

local function row_status(row)
    if row.superseded then return "CharacterID reused by another pawn" end
    if row.in_party then return "in party slot " .. tostring(row.slot) end
    if row.record == true then return "away (record present)" end
    if row.record == false then return "record gone" end
    return "?"
end

-- Tracked row currently in party slot N (from the once-a-second refresh; the UI makes no game calls).
local function slot_row(slot)
    for _, row in ipairs(tracked_order) do
        if row.in_party and row.slot == slot then return row end
    end
    return nil
end

local function party_name(slot)
    local row = slot_row(slot)
    if not row then return "empty slot" end
    local tag = row.id == MAIN_ID and "  [MAIN PAWN: refused]" or ""
    return string.format("%d (%s)%s", row.id, tostring(row.name), tag)
end

local function confirm_button(kind, label, extra)
    local is_armed = armed and armed.kind == kind and armed.slot == ta.slot and armed.b1 == ta.b1
        and armed.b2 == ta.b2 and os.clock() < armed.deadline
    local row = slot_row(ta.slot)
    if imgui.button((is_armed and "CONFIRM " or "") .. label .. "##" .. kind) then
        if not row then
            action_status = "no pawn in slot " .. ta.slot
        elseif is_armed and armed.id ~= row.id then
            armed = nil
            action_status = string.format("refused: slot %d no longer holds the pawn it was armed for", ta.slot)
        elseif is_armed then
            local armed_id = armed.id
            armed = nil
            queue_action({ kind = kind, slot = ta.slot, expect_id = armed_id, args = extra })
        else
            armed = { kind = kind, slot = ta.slot, id = row.id, b1 = ta.b1, b2 = ta.b2,
                deadline = os.clock() + CONFIRM_SECONDS }
        end
    end
    if is_armed then
        imgui.same_line()
        imgui.text(string.format("click again within %.0f s to run on %s", armed.deadline - os.clock(),
            party_name(ta.slot)))
    end
end

local function draw_actions()
    imgui.text("These CALL the game and change the save. Back up first. The main pawn and the player are refused.")
    local ch, v = imgui.slider_int("Party slot", ta.slot, 1, 4)
    if ch then ta.slot = v end
    imgui.text("Target: " .. party_name(ta.slot))

    local ch_e, et = imgui.input_text("exp", ta.exp_text)
    if ch_e then ta.exp_text = et end
    local ch_j, jt = imgui.input_text("job point", ta.jp_text)
    if ch_j then ta.jp_text = jt end
    if imgui.button("Grant exp##grant_exp") then
        local exp, jp = math.tointeger(tonumber(ta.exp_text)), math.tointeger(tonumber(ta.jp_text))
        if exp and jp then
            queue_action({ kind = "grant_exp", slot = ta.slot, args = { exp = exp, job_point = jp } })
        else
            action_status = "exp and job point must be whole numbers"
        end
    end

    confirm_button("dismiss", "Dismiss slot " .. ta.slot, {})
    local ch1, b1 = imgui.checkbox("lost: bool 1", ta.b1)
    if ch1 then ta.b1 = b1 end
    imgui.same_line()
    local ch2, b2 = imgui.checkbox("lost: bool 2", ta.b2)
    if ch2 then ta.b2 = b2 end
    confirm_button("lost", "Force lost slot " .. ta.slot, { b1 = ta.b1, b2 = ta.b2 })
    imgui.text(action_status)
    for i = math.max(1, #run.actions - 3), #run.actions do
        local a = run.actions[i]
        imgui.text(string.format("action %s slot%s id=%s ok=%s %s", a.kind, tostring(a.slot), tostring(a.id),
            tostring(a.ok), tostring(a.error or a.result or "")))
    end
end

local function draw_body()
    imgui.text("Log-only hooks; the test actions below change the save. Back up first (tools/saves.sh backup).")
    imgui.text(hook_status)
    imgui.text(refresh_status)
    imgui.text(string.format("Run file: reframework/data/%s  entries: %d calls, %d snapshots, %d actions, "
        .. "%d dropped, %d errors", RUN_FILE, #calls, #run.snapshots, #run.actions, run.dropped, #run.errors))
    imgui.text(flush_status)

    imgui.text(string.format("Dismissed list: %s entries   lost timers: %s   StrayPawnPastInformationMax: %s   "
        .. "RelationPawnDismissNum: %s", str(dismissed_count), str(lost_timer_count),
        str(run.constants.StrayPawnPastInformationMax), str(run.constants.RelationPawnDismissNum)))

    imgui.text("Tracked pawns (every CharacterID/OfflineID seen this session):")
    for _, row in ipairs(tracked_order) do
        imgui.text(string.format("%s  off=%s  %s  Lv %s  Exp %s  %s  %s%s", tostring(row.id),
            tostring(row.offline or "?"):sub(1, 8), tostring(row.name or "?"), str(row.level), str(row.exp),
            str(row.job), row_status(row), row.dismissed == true and "  [in dismissed list]" or ""))
    end

    local ch_a, a = imgui.checkbox("Auto snapshots on events", auto_snap)
    if ch_a then auto_snap = a end
    imgui.same_line()
    local ch_l, lg = imgui.checkbox("Log calls", log_calls)
    if ch_l then log_calls = lg end
    local ch_t, lbl = imgui.input_text("Snapshot label", snap_label)
    if ch_t then snap_label = lbl end
    if imgui.button("Snapshot") then
        schedule_snapshot(snap_label ~= "" and snap_label or "manual", { force = true, frames = 1, kind = "manual" })
    end
    imgui.same_line()
    if imgui.button("Flush log now") then flush_requested = true end

    if imgui.tree_node("Test actions") then
        local ok, err = pcall(draw_actions)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end

    for i = math.max(1, #calls - LOG_LINES + 1), #calls do imgui.text(fmt_entry(calls[i])) end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Lifecycle (EXPERIMENT)") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
