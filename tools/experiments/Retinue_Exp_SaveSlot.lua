-- Retinue Exp SaveSlot: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- What it answers (M2, ticket 14 "Which save slot is loaded, and can a new game be told apart?"): the mod keeps one
-- roster per save slot, so it must know which of the player's three slots is loaded. In the game's code the three
-- player-visible slots are UNITS (app.GameSystem.UnitNumber, UNIT_MAX_COUNT, SLOT_PER_UNIT) and each unit has several
-- internal save SLOTS (auto, add-auto, manual, back, clear); on disk that is data000.bin, data00-1.bin and
-- data001slot.bin .. data009slot.bin. On every load and every save this script records every value that could identify
-- the unit and the save type, and every hook that could signal a new game or NG+, so a run can tell:
--   Q1  which value maps to the player's slot 1-3 (and how the dataNNNslot.bin files group per unit: pair this log with
--       the file watcher tools/experiments/watch_saves.sh);
--   Q2  whether that value is stable across save types (auto / inn / manual / clear), a reload and a relaunch;
--   Q3  when during a load it is first correct (the 1 s poll's `changes` list, against `entered-world`);
--   Q4  how a NEW GAME over an existing unit and an NG+ (the Clear save) can be detected: which hook fires, which
--       counter or play time drops, which slot type is written.
-- Every snapshot has the same shape (see slot_state()): app.GameSystem (LatestSaveSlot, the unit/slot arrays, the
-- per-unit lists, SaveSlotType per slot, detail contents, UnitInfoData), app.SaveDataManager, app.MainFlowManager, the
-- last-seen app.SaveUnitSelectGUIFlowController and the world (in_world, party, the player's name).
--
-- The script is LOG-ONLY: it never changes an argument or a return value (every pre hook returns CALL_ORIGINAL, no
-- post hook returns anything but the original value) and never calls a game method that writes. The only game calls it
-- makes are getters (getLatestSaveSlot, getLatestSaveSlotNum, getSaveSlotType, getSlotTimeStamp, getDetailContents,
-- getLoadingGameSlotId, get_* ...). None of the hooked methods is hooked by the mod (the mod hooks only
-- app.ExpDispenser members and GuiManager.reqJobRankUp; checked with grep over src/), so this script can be linked
-- TOGETHER with the mod and with the other experiments (deploy.sh --saveslot). The saves are only read, but BACK UP
-- FIRST all the same (tools/saves.sh backup <label>): the ticket's runs load and overwrite the player's real slots.
--
-- Output: reframework/data/Retinue/experiments/saveslot_<timestamp>.json (one file per session, flushed every 2 s when
-- changed). Hooks cannot be removed in REFramework, so all of them are installed at load. Every hook body is wrapped in
-- pcall: a bug here must never break a game call. Game state is read in the update callback
-- (re.on_pre_application_entry("UpdateBehavior")), never in the UI callback; a hook only reads fields of its arguments
-- and of GameSystem / MainFlowManager / SaveDataManager (logged as `state` on the call entry) and QUEUES the full
-- snapshot for the next frame. API names were checked against this game version's il2cpp_dump.json; helpers are copied
-- from Retinue_Exp_StatusUI.lua (scripts are standalone). NOT RUN IN GAME YET.
--
-- Hook argument indexes: instance methods have args[2] = this and the first parameter at args[3]; static methods have
-- the first parameter at args[2]. Every method hooked here is an instance method.
--
-- Arrays in a snapshot are Lua lists in index order: the first element is index 0 (unit 0 = player slot 1 ... to be
-- confirmed by the run).

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "saveslot_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 8000 -- shared cap of the `calls` list
local DEFAULT_SPEC_CAP = 300 -- per-hook cap of logged entries (pre phase)
local BIG_SPEC_CAP = 1000
local CHATTY_SPEC_CAP = 30
local SNAPSHOT_CAP = 400 -- automatic snapshots
local MANUAL_CAP = 100 -- manual snapshots (button and markers)
local CHANGE_CAP = 600
local MARKER_CAP = 200
local ERROR_CAP = 200
local STACK_MAX = 32
local ARRAY_CAP = 16
local SLOT_LOOP_CAP = 32
local UNIT_LOOP_CAP = 8
local AFTER_THROTTLE_SECONDS = 2.0
local FIELD_SCAN_CAP = 20
local LOG_LINES = 8
local CONSTANT_RETRIES = 30

-- Session state (never persisted).
local markers_text = ""
local hook_status, flush_status = "hooks not installed yet", ""
local flush_requested = false
local names = {}
local enum_cache = {}
local work_queue = {}
local in_self_call = false
local suc_last = nil -- plain copy of the unit-select controller's fields, read in its hooks (never a live reference)
local suc_seen, suc_dropped = 0, 0
local live = nil -- last slot_state(), plain data for the panel
local last_key, last_world = nil, nil
local auto_count, manual_count = 0, 0
local after_last = {} -- hook key -> os.clock() of the last queued `after:` snapshot
local constants_tries = 0

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    constants = {
        script = "Retinue_Exp_SaveSlot",
        main_id = MAIN_ID,
        call_cap = CALL_CAP,
        default_spec_cap = DEFAULT_SPEC_CAP,
        snapshot_cap = SNAPSHOT_CAP,
        manual_cap = MANUAL_CAP,
        note = "arrays are lists in index order: element 1 is index 0",
    },
    markers = {},
    snapshots = {},
    changes = {},
    calls = {},
    errors = {},
    hooks = { installed = {}, missing = {} },
    dropped = 0,
    dropped_by_spec = {},
    snapshots_dropped = 0,
    manual_dropped = 0,
    changes_dropped = 0,
    after_suppressed = {}, -- hook key -> count of `after:` snapshots skipped by the 2 s throttle
    self_calls = {}, -- hook key -> hooks fired by this script's own getter calls (not logged)
    count_by_spec = {}, -- hook -> { pre, post }: every call seen, logged or not
}
local calls = run.calls
local seq, dirty = 0, true
local last_flush, last_refresh = -FLUSH_SECONDS, -REFRESH_SECONDS
local logged_by_spec = {}
local frames = {} -- hook key -> stack of in-flight frames (pre pushes, post pops)

-- ---------------------------------------------------------------------------------------------------------
-- Small helpers

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

local function sanitize(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
    if t == "table" then
        -- REFramework's json writes an empty Lua table as null: write a marker object instead (read it as [])
        if next(v) == nil then return { _empty = true } end
        local o = {}
        for k, x in pairs(v) do o[k] = sanitize(x) end
        return o
    end
    return str(v)
end

local function nz(t)
    if next(t) == nil then return { _empty = true } end
    return t
end

local function wall() return os.date("%H:%M:%S") end
local function is_err(v) return type(v) == "string" and v:sub(1, 5) == "ERR: " end
local function clip(s, n) s = tostring(s); if #s > n then return s:sub(1, n) .. "..." end return s end

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

-- A field read as plain data (strings stay strings, userdata become their ToString, errors become "ERR: ...").
local function field(o, name)
    local v = try(function() return o:get_field(name) end)
    if type(v) == "userdata" then return str(v) end
    return v
end

-- A field read raw (arrays and objects stay userdata).
local function rfield(o, name) return try(function() return o:get_field(name) end) end

-- A method call: plain result / raw result.
local function rcall(o, name, ...)
    local a = table.pack(...)
    return try(function() return o:call(name, table.unpack(a, 1, a.n)) end)
end
local function call(o, name, ...)
    local v = rcall(o, name, ...)
    if type(v) == "userdata" then return str(v) end
    return v
end

-- A backing field of an auto-property: <Name>k__BackingField.
local function bf(o, name) return field(o, "<" .. name .. ">k__BackingField") end

local function singleton(name) return sdk.get_managed_singleton(name) end

-- Hook argument decoding (args[n] are raw pointer-sized values).
local function arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end
local function arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
local function arg_bool(a) return (sdk.to_int64(a) & 1) == 1 end

local function to_managed(a)
    if a == nil then return nil end
    if sdk.to_int64(a) == 0 then return nil end
    return sdk.to_managed_object(a)
end

local function type_name_of(o)
    return try(function() return o:get_type_definition():get_full_name() end)
end

-- System.Guid (a value type) -> canonical lowercase string. Reads the raw 16 bytes (as TalkUI / Guild Contracts do).
local function guid_str(v)
    if v == nil then return nil end
    if type(v) == "string" then return v:lower() end
    if type(v) ~= "userdata" then return tostring(v) end
    local ok, s = pcall(function()
        local lo, hi = v:read_qword(0), v:read_qword(8)
        return string.format("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            lo & 0xFFFFFFFF, (lo >> 32) & 0xFFFF, (lo >> 48) & 0xFFFF,
            hi & 0xFF, (hi >> 8) & 0xFF, (hi >> 16) & 0xFF, (hi >> 24) & 0xFF,
            (hi >> 32) & 0xFF, (hi >> 40) & 0xFF, (hi >> 48) & 0xFF, (hi >> 56) & 0xFF)
    end)
    if ok and s then return s end
    return "unreadable"
end

-- ---------------------------------------------------------------------------------------------------------
-- Enums, arrays, method lookup

local function enum_name(type_name, v)
    if type(v) ~= "number" then return nil end
    local map = enum_cache[type_name]
    if map == nil then
        map = {}
        pcall(function()
            local td = sdk.find_type_definition(type_name)
            for _, f in ipairs(td:get_fields()) do
                if f:is_static() then
                    local val = f:get_data(nil)
                    if type(val) == "number" then map[val] = f:get_name() end
                end
            end
        end)
        enum_cache[type_name] = map
    end
    return map[v]
end

-- { v = number, name = enum member name } for a number; anything else unchanged.
local function en(type_name, v)
    if type(v) ~= "number" then return v end
    return { v = v, name = enum_name(type_name, v) }
end

local function elements(arr, cap)
    cap = cap or 16
    if arr == nil or type(arr) ~= "userdata" then return {} end
    local out = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do
            if i > cap then break end
            out[i] = v
        end
        return out
    end
    local n = try(function() return arr:call("get_Length") end)
    if type(n) == "number" then
        for i = 0, math.min(n, cap) - 1 do out[i + 1] = arr:call("GetValue", i) end
    end
    return out
end

local function plain(v)
    if type(v) == "userdata" then return str(v) end
    return v
end

-- A primitive array (Int32[], Boolean[], Int64[], UInt32[]) as a plain Lua list; errors / nil as a string.
local function list_of(arr, cap)
    if arr == nil then return "nil" end
    if type(arr) ~= "userdata" then return arr end
    local out = {}
    for i, v in ipairs(elements(arr, cap)) do out[i] = plain(v) end
    return out
end

-- An object array: (list that may have nil holes, real length). Null elements stay nil.
local function obj_elems(arr, cap)
    if type(arr) ~= "userdata" then return {}, 0 end
    local n = try(function() return arr:call("get_Length") end)
    local t = try(function() return arr:get_elements() end)
    if type(n) ~= "number" then n = type(t) == "table" and #t or 0 end
    local out = {}
    if type(t) == "table" then
        for i = 1, math.min(n, cap) do out[i] = t[i] end
    end
    return out, n
end

local function join(v)
    if type(v) ~= "table" then return tostring(v) end
    local p = {}
    for i, x in ipairs(v) do p[i] = tostring(x) end
    return table.concat(p, ",")
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

local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_name_chara = td_guibase and td_guibase:get_method("getName(app.Character)")

-- ---------------------------------------------------------------------------------------------------------
-- Logging

local function next_seq() seq = seq + 1; return seq end
local function queue_work(fn) work_queue[#work_queue + 1] = fn end

local function append_entry(spec, entry)
    if #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
        return nil
    end
    entry = sanitize(entry)
    if entry.phase == "pre" then logged_by_spec[spec.key] = (logged_by_spec[spec.key] or 0) + 1 end
    calls[#calls + 1] = entry
    dirty = true
    return entry
end

-- ---------------------------------------------------------------------------------------------------------
-- Pawns, names, world (as StatusUI's party_entries; no live objects leave this function)

local function holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

-- OfflineID of a live actor (PawnOwnerContext._OfflineID), or nil.
local function offline_of(chara)
    local ok, v = pcall(function()
        local holder = chara:call("get_Context")
        if not holder then return nil end
        local owner = holder_context(holder, "app.PawnOwnerContext")
        if not owner then return nil end
        return guid_str(owner:get_field("_OfflineID"))
    end)
    if ok then return v end
    return nil
end

local function level_of(chara)
    local ok, v = pcall(function()
        local human = chara:call("get_Human")
        local st = human and human:call("get_StatusContext")
        return st and st:call("get_Level")
    end)
    if ok and type(v) == "number" then return v end
    return nil
end

-- Party pawns (main pawn included, flagged): { id, slot, name, level, offline, main }.
local function party_entries()
    local out = {}
    local pm = singleton("app.PawnManager")
    local party = pm and pm:get_field("_PartyPawnList")
    if not party then return out end
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara then
            local id = to_u32(chara:call("get_CharaID"))
            if type(id) == "number" then
                local nm = m_name_chara and try(function() return m_name_chara:call(nil, chara) end)
                if type(nm) == "userdata" then nm = str(nm) end
                if type(nm) == "string" and not is_err(nm) then names[id] = nm end
                out[#out + 1] = { id = id, slot = i + 1, name = names[id], level = level_of(chara),
                    offline = offline_of(chara), main = id == MAIN_ID }
            end
        end
    end
    return out
end

-- The player's name (app.GUIBase.getName(app.Character) of CharacterManager's ManualPlayer), or nil.
local function player_name()
    local cm = singleton("app.CharacterManager")
    local player = cm and cm:call("get_ManualPlayer")
    if not player or not m_name_chara then return nil end
    local nm = m_name_chara:call(nil, player)
    if type(nm) == "userdata" then nm = str(nm) end
    return nm
end

-- ---------------------------------------------------------------------------------------------------------
-- Constants (statics read once; retried from the poll while a read fails: the types may not be initialised at load)

local CONSTANT_SOURCES = {
    { "app.GameSystem", { "SAVE_SLOT_ADDAUTO", "SAVE_SLOT_AUTO", "SAVE_SLOT_BACK", "SAVE_SLOT_CLEAR", "SAVE_SLOT_DEMO",
        "SAVE_SLOT_MANUAL", "SAVE_SLOT_SYSTEM", "SLOT_MAX_COUNT", "SLOT_PER_UNIT", "UNIT_MAX_COUNT" } },
    { "app.SaveUnitSelectGUIFlowController", { "UnitMaxCount", "UnitPerModelCount" } },
    { "app.ui030901", { "SaveDataTypeCount" } },
}

-- Returns true when every constant was read.
local function read_constants()
    local all = true
    for _, src in ipairs(CONSTANT_SOURCES) do
        local tn, fields = src[1], src[2]
        local td = sdk.find_type_definition(tn)
        for _, name in ipairs(fields) do
            local key = tn .. "." .. name
            local cur = run.constants[key]
            if cur == nil or is_err(cur) then
                local v = try(function() return td:get_field(name):get_data(nil) end)
                if v == nil then v = "ERR: nil" end
                run.constants[key] = plain(v)
                if is_err(v) or v == "ERR: nil" then all = false end
            end
        end
    end
    dirty = true
    return all
end
local constants_complete = false
do
    local ok, res = pcall(read_constants)
    if ok then constants_complete = res else log_error("read_constants", res) end
end

local function const_num(name, default, cap)
    local v = run.constants["app.GameSystem." .. name]
    if type(v) == "number" and v >= 1 then return math.min(math.tointeger(v) or default, cap) end
    return default
end

-- ---------------------------------------------------------------------------------------------------------
-- The snapshot

-- The per-slot / per-unit sections are built by small functions so one failure does not lose the rest.
local function game_system_state()
    local gs = singleton("app.GameSystem")
    if not gs then return "no GameSystem" end
    local g = {}
    g.LatestSaveSlot = field(gs, "LatestSaveSlot")
    g.LatestSaveSlotArray = list_of(rfield(gs, "LatestSaveSlotArray"), ARRAY_CAP)
    g.SlotTimeStampArray = list_of(rfield(gs, "SlotTimeStampArray"), SLOT_LOOP_CAP)
    g.UnitNumber_field = bf(gs, "UnitNumber")
    g.UnitNumber = call(gs, "get_UnitNumber")
    g.UnitPlayCountList = list_of(rcall(gs, "get_UnitPlayCountList"), ARRAY_CAP)
    g.IsGameClearedList = list_of(rcall(gs, "get_IsGameClearedList"), ARRAY_CAP)
    g.GameClearDataMidstList = list_of(rcall(gs, "get_GameClearDataMidstList"), ARRAY_CAP)
    g.GameLastSaveList = list_of(rcall(gs, "get_GameLastSaveList"), ARRAY_CAP)
    g.IsNRDSavedList = list_of(rcall(gs, "get_IsNRDSavedList"), ARRAY_CAP)
    g.CachedExistSlotArray = list_of(rcall(gs, "get_CachedExistSlotArray"), SLOT_LOOP_CAP)
    for _, n in ipairs({ "IsGameCleared", "GameClearDataMidst", "GameLstSave", "IsNotNewGameMenu", "GameSaveDataHash" }) do
        g[n] = call(gs, "get_" .. n)
    end
    for _, n in ipairs({ "Auto", "AddAuto", "Manual", "Back", "Clear" }) do
        g["CachedSlot" .. n] = call(gs, "get_CachedSlot" .. n)
        g["CachedExistSlot" .. n] = call(gs, "get_CachedExistSlot" .. n)
    end
    g.getLatestSaveSlot = call(gs, "getLatestSaveSlot")

    local per_unit = {}
    for i = 0, const_num("UNIT_MAX_COUNT", 3, UNIT_LOOP_CAP) - 1 do
        per_unit[tostring(i)] = call(gs, "getLatestSaveSlotNum", i)
    end
    g.getLatestSaveSlotNum = per_unit

    local types, stamps = {}, {}
    for s = 0, const_num("SLOT_MAX_COUNT", 16, SLOT_LOOP_CAP) - 1 do
        types[tostring(s)] = en("app.GameSystem.SaveSlotType", call(gs, "getSaveSlotType", s))
        stamps[tostring(s)] = call(gs, "getSlotTimeStamp", s)
    end
    g.getSaveSlotType = types
    g.getSlotTimeStamp = stamps
    local ls = tonumber(g.LatestSaveSlot)
    if ls then g.getSaveSlotType_of_LatestSaveSlot = en("app.GameSystem.SaveSlotType", call(gs, "getSaveSlotType", ls)) end

    local d = rcall(gs, "getDetailContents")
    if type(d) == "userdata" then
        g.detail = { SaveCount = field(d, "SaveCount"), ActualPlayingTime = field(d, "ActualPlayingTime"),
            Difficulty = field(d, "Difficulty"), MainPlayer = field(d, "MainPlayer"), Memo = field(d, "Memo") }
    else
        g.detail = plain(d)
    end

    local units = {}
    local arr, n = obj_elems(rcall(gs, "get_UnitInfoDataList"), UNIT_LOOP_CAP)
    for i = 1, math.min(n, UNIT_LOOP_CAP) do
        local o = arr[i]
        if o == nil then
            units[i] = "null"
        else
            local pm = field(o, "PlayMode")
            local sid = try(function() return guid_str(o:get_field("ServerSlotId")) end)
            units[i] = { PlayTime = field(o, "PlayTime"), IsRestartData = field(o, "IsRestartData"),
                PlayMode = en("app.PlayModeType", pm), IsCasualMode = field(o, "IsCasualMode"), ServerSlotId = sid }
        end
    end
    g.UnitInfoDataList = units
    return g
end

local function save_data_manager_state()
    local sdm = singleton("app.SaveDataManager")
    if not sdm then return "no SaveDataManager" end
    local p = field(sdm, "CurrentProcess")
    local req = rfield(sdm, "CurrentRequest")
    local r
    if type(req) == "userdata" then
        local cmd = field(req, "Command")
        r = { str = str(req), SlotId = bf(req, "SlotId"), isTarget = bf(req, "isTarget"),
            Command = en("app.SaveDataManager.Request.CommandType", cmd) }
    else
        r = plain(req)
    end
    return { getLoadingGameSlotId = call(sdm, "getLoadingGameSlotId"),
        CurrentProcess = en("app.SaveDataManager.Process", p), CurrentRequest = r }
end

local function main_flow_state()
    local m = singleton("app.MainFlowManager")
    if not m then return "no MainFlowManager" end
    local s = {}
    for _, n in ipairs({ "get_LastLoadedSlot", "get_isNewGameFlow", "get_ContinueCount", "get_IsRestart", "get_IsTitleMenuPhase" }) do
        s[n] = call(m, n)
    end
    for _, n in ipairs({ "ContinueSlot", "IsContinueFlow", "IsNewGameFlow", "_IsRestart", "IsSuccessLoadSaveData" }) do
        s[n] = field(m, n)
    end
    return s
end

-- Fields of a SaveUnitSelectGUIFlowController, read only inside its own hooks (the object is alive there). The live
-- reference is never kept across frames: a freed component could crash a later read instead of erroring. Snapshots
-- carry the last plain copy (suc_last) with the hook and wall time it was read at.
local function unit_select_fields(o)
    local flow = field(o, "CurrFlow")
    local st = call(o, "get_SelectStartType")
    return { UseSaveUnitNo = field(o, "UseSaveUnitNo"), UseSaveSlotNo = field(o, "UseSaveSlotNo"),
        LatestUnitNo = field(o, "LatestUnitNo"),
        get_IsNewGame = call(o, "get_IsNewGame"),
        get_SelectStartType = en("app.MainFlowManager.StartType", st),
        CurrFlow = en("app.SaveUnitSelectGUIFlowController.FlowId", flow),
        CachedExistUnitData = list_of(rfield(o, "CachedExistUnitData"), ARRAY_CAP) }
end

local function unit_select_state()
    return suc_last
end

local function world_state(title_phase)
    local w = {}
    local party = party_entries()
    local has_main = false
    for _, e in ipairs(party) do if e.id == MAIN_ID then has_main = true end end
    w.in_world = has_main and title_phase ~= true
    w.party_has_main = has_main
    w.party = party
    w.player_name = try(player_name)
    return w
end

local function section(state, name, fn)
    local ok, v = pcall(fn)
    if ok then state[name] = v else state[name] = { error = tostring(v) } end
end

local function slot_state_inner()
    local st = {}
    section(st, "gs", game_system_state)
    section(st, "sdm", save_data_manager_state)
    section(st, "mfm", main_flow_state)
    section(st, "suc", unit_select_state)
    local title = type(st.mfm) == "table" and st.mfm.get_IsTitleMenuPhase or nil
    section(st, "world", function() return world_state(title) end)
    return st
end

-- Own getter calls fire the hooks below: in_self_call keeps them out of the log.
local function slot_state()
    local was = in_self_call
    in_self_call = true
    local ok, st = pcall(slot_state_inner)
    in_self_call = was
    if not ok then
        log_error("slot_state", st)
        return { error = tostring(st) }
    end
    return st
end

-- Cheap field reads only (a hook may run this): the values that matter most, without a single method call.
local function quick_state()
    local q = {}
    local gs = singleton("app.GameSystem")
    if gs then
        q.LatestSaveSlot = field(gs, "LatestSaveSlot")
        q.LatestSaveSlotArray = list_of(rfield(gs, "LatestSaveSlotArray"), UNIT_LOOP_CAP)
        q.UnitNumber = bf(gs, "UnitNumber")
        q.UnitPlayCountList = list_of(rfield(gs, "<UnitPlayCountList>k__BackingField"), UNIT_LOOP_CAP)
    end
    local m = singleton("app.MainFlowManager")
    if m then
        q.LastLoadedSlot = bf(m, "LastLoadedSlot")
        q.ContinueSlot = field(m, "ContinueSlot")
        q.IsNewGameFlow = field(m, "IsNewGameFlow")
        q.IsContinueFlow = field(m, "IsContinueFlow")
    end
    local sdm = singleton("app.SaveDataManager")
    if sdm then
        local p = field(sdm, "CurrentProcess")
        q.CurrentProcess = type(p) == "number" and (enum_name("app.SaveDataManager.Process", p) or p) or p
    end
    return q
end

local function take_snapshot(label, kind, state)
    local manual = kind == "manual"
    if manual then
        if manual_count >= MANUAL_CAP then run.manual_dropped = run.manual_dropped + 1; return nil end
    elseif auto_count >= SNAPSHOT_CAP then
        run.snapshots_dropped = run.snapshots_dropped + 1
        return nil
    end
    state = state or slot_state()
    local snap = sanitize({ label = label, kind = kind, seq = next_seq(), t = os.clock(), wall = wall(), state = state })
    run.snapshots[#run.snapshots + 1] = snap
    if manual then manual_count = manual_count + 1 else auto_count = auto_count + 1 end
    dirty = true
    return snap
end

-- ---------------------------------------------------------------------------------------------------------
-- The 1 s poll: change detection, world transitions

local function key_of(st)
    local g = type(st.gs) == "table" and st.gs or {}
    local s = type(st.sdm) == "table" and st.sdm or {}
    local m = type(st.mfm) == "table" and st.mfm or {}
    local w = type(st.world) == "table" and st.world or {}
    local d = type(g.detail) == "table" and g.detail or {}
    local k = {
        LatestSaveSlot = g.LatestSaveSlot, UnitNumber = g.UnitNumber, getLatestSaveSlot = g.getLatestSaveSlot,
        getLoadingGameSlotId = s.getLoadingGameSlotId, LastLoadedSlot = m.get_LastLoadedSlot, SaveCount = d.SaveCount,
        in_world = w.in_world, IsTitleMenuPhase = m.get_IsTitleMenuPhase, UnitPlayCountList = join(g.UnitPlayCountList),
    }
    for name, v in pairs(k) do k[name] = tostring(v) end
    return k
end

local function poll()
    local state = slot_state()
    live = sanitize(state)
    local key = key_of(state)
    local world = type(state.world) == "table" and state.world.in_world or nil

    local world_label = nil
    if last_world ~= nil and world ~= nil and world ~= last_world then
        world_label = world and "entered-world" or "left-world"
    end
    if world ~= nil then last_world = world end

    local from, to, changed = {}, {}, false
    if last_key == nil then
        changed = true
        to = key
    else
        for name, v in pairs(key) do
            if last_key[name] ~= v then changed = true; from[name] = last_key[name]; to[name] = v end
        end
    end
    local first = last_key == nil
    last_key = key

    local stored = nil
    if world_label then
        stored = take_snapshot(world_label, "world", state)
    elseif changed then
        stored = take_snapshot(first and "poll-initial" or "poll-change", "poll", state)
    end
    if changed then
        if #run.changes < CHANGE_CAP then
            run.changes[#run.changes + 1] = sanitize({ t = os.clock(), wall = wall(), from = from, to = to,
                initial = first or nil, snapshot = stored and stored.label or nil, world = world_label })
            dirty = true
        else
            run.changes_dropped = run.changes_dropped + 1
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook decoders

-- Generic read of slot-like primitive fields of an object (and its parent types), capped.
local function slotlike_fields(o)
    local out = { type = type_name_of(o), HashValue = field(o, "HashValue"), VersionValue = field(o, "VersionValue") }
    local td = try(function() return o:get_type_definition() end)
    local found, depth = 0, 0
    while type(td) == "userdata" and depth < 6 and found < FIELD_SCAN_CAP do
        local fields = try(function() return td:get_fields() end)
        if type(fields) == "table" then
            for _, f in ipairs(fields) do
                if found >= FIELD_SCAN_CAP then break end
                local ok, name = pcall(function() return f:get_name() end)
                if ok and type(name) == "string" and not f:is_static()
                    and (name:find("[Ss]lot") or name:find("[Uu]nit") or name:find("Count") or name:find("Time")) then
                    local v = try(function() return o:get_field(name) end)
                    if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
                        out[name] = v
                        found = found + 1
                    end
                end
            end
        end
        td = try(function() return td:get_parent_type() end)
        depth = depth + 1
    end
    return out
end

local function decode_character(ci)
    if type(ci) ~= "userdata" then return plain(ci) end
    return { Name = bf(ci, "Name"), Level = bf(ci, "Level"), IsEmpty = bf(ci, "IsEmpty"), Job = bf(ci, "Job") }
end

-- app.ui030902.MainListInfo (an entry of the unit list)
local function decode_unit_item(a)
    local o = to_managed(a)
    if o == nil then return "nil" end
    local d = { UnitNo = bf(o, "UnitNo"), IsEmpty = bf(o, "IsEmpty"), IsCurrentUnit = bf(o, "IsCurrentUnit"),
        IsRestartData = bf(o, "IsRestartData") }
    d.ArisenInfo = decode_character(try(function() return o:get_field("<ArisenInfo>k__BackingField") end))
    d.PawnInfo = decode_character(try(function() return o:get_field("<PawnInfo>k__BackingField") end))
    local ui = try(function() return o:get_field("<UnitInfo>k__BackingField") end)
    if type(ui) == "userdata" then
        d.UnitInfo = { PlaceName = bf(ui, "PlaceName"), PlayMode = bf(ui, "PlayMode"), PlayTime = bf(ui, "PlayTime"),
            SavedTime = bf(ui, "SavedTime"), IsClearData = bf(ui, "IsClearData") }
    else
        d.UnitInfo = plain(ui)
    end
    return d
end

-- app.ui030901.MainListInfo (an entry of the save list of one unit)
local function decode_save_item(a)
    local o = to_managed(a)
    if o == nil then return "nil" end
    local d = { SaveSlotNo = bf(o, "SaveSlotNo"), IsEmpty = bf(o, "IsEmpty"), IsLatestData = bf(o, "IsLatestData"),
        IsRestartData = bf(o, "IsRestartData") }
    d.ArisenInfo = decode_character(try(function() return o:get_field("<ArisenInfo>k__BackingField") end))
    d.PawnInfo = decode_character(try(function() return o:get_field("<PawnInfo>k__BackingField") end))
    local si = try(function() return o:get_field("<SlotInfo>k__BackingField") end)
    if type(si) == "userdata" then
        d.SlotInfo = { PlaceName = bf(si, "PlaceName"), PlayTime = bf(si, "PlayTime"), SavedTime = bf(si, "SavedTime"),
            DayValue = bf(si, "DayValue"),
            MainFlowStartType = en("app.MainFlowManager.StartType", bf(si, "MainFlowStartType")),
            SaveDataType = en("app.ui030901.SaveDataType", bf(si, "SaveDataType")) }
    else
        d.SlotInfo = plain(si)
    end
    return d
end

local function decode_save_object(a)
    local o = to_managed(a)
    if o == nil then return "nil" end
    return slotlike_fields(o)
end

-- One argument by kind: "i32" "u32" "bool" "obj" (type name) "u32arr" "enum:<Type>" or a function(arg).
local function decode_one(kind, a)
    if type(kind) == "function" then return kind(a) end
    if kind == "i32" then return arg_i32(a)
    elseif kind == "u32" then return arg_u32(a)
    elseif kind == "bool" then return arg_bool(a)
    elseif kind == "obj" then
        local o = to_managed(a)
        if o == nil then return "nil" end
        return type_name_of(o)
    elseif kind == "u32arr" then
        local o = to_managed(a)
        if o == nil then return "nil" end
        return list_of(o, ARRAY_CAP)
    elseif kind:sub(1, 5) == "enum:" then
        local v = arg_i32(a)
        return { v = v, name = enum_name(kind:sub(6), v) }
    end
    return "?"
end

local function decode_args(kinds, args)
    local vals = {}
    for i, kind in ipairs(kinds or {}) do
        local ok, v = pcall(decode_one, kind, args[2 + i])
        vals[i] = ok and v or ("ERR: " .. tostring(v))
    end
    return vals
end

local function decode_ret(kind, retval)
    if kind == "i32" then return arg_i32(retval)
    elseif kind == "bool" then return arg_bool(retval)
    elseif kind == "saveobj" then return decode_save_object(retval)
    end
    return "?"
end

-- ---------------------------------------------------------------------------------------------------------
-- Hooks

local GS, SDM, MFM, SUC = "app.GameSystem", "app.SaveDataManager", "app.MainFlowManager", "app.SaveUnitSelectGUIFlowController"
local UI1 = "app.ui030901"
local START = "enum:app.MainFlowManager.StartType"
local SLOT_REQ = "obj" -- app.SaveDataManager.SaveLoadRequestArgs: only its presence is logged

-- Spec fields: key, type, sig, args (kinds), ret (kind), cap, chatty (no quick state, no `after:` snapshot),
-- capture (remember `this` as the unit-select controller), on_pre (extra work), quiet (counted, not logged).
local SPECS = {
    -- app.GameSystem
    { key = "GameSystem.loadGameSaveData", type = GS, sig = "loadGameSaveData(app.SaveDataBase)",
      args = { decode_save_object }, cap = BIG_SPEC_CAP },
    { key = "GameSystem.saveGameSaveData", type = GS, sig = "saveGameSaveData()", ret = "saveobj", cap = BIG_SPEC_CAP },
    { key = "GameSystem.loadSystemSaveData", type = GS, sig = "loadSystemSaveData(app.SaveDataBase)",
      args = { decode_save_object } },
    { key = "GameSystem.saveSystemSaveData", type = GS, sig = "saveSystemSaveData()", ret = "saveobj" },
    { key = "GameSystem.setLatestSaveSlotNum", type = GS, sig = "setLatestSaveSlotNum(System.Int32)", args = { "i32" } },
    { key = "GameSystem.updateLatestSaveSlot", type = GS, sig = "updateLatestSaveSlot()" },
    { key = "GameSystem.checkLatestSaveSlot", type = GS, sig = "checkLatestSaveSlot(System.Int32)",
      args = { "i32" }, ret = "i32" },
    { key = "GameSystem.setUnitNumber", type = GS, sig = "setUnitNumber(System.Int32)", args = { "i32" } },
    { key = "GameSystem.set_UnitNumber", type = GS, sig = "set_UnitNumber(System.Int32)", args = { "i32" } },
    { key = "GameSystem.updateUnitDataList", type = GS, sig = "updateUnitDataList(System.Int32, System.Boolean)",
      args = { "i32", "bool" } },
    { key = "GameSystem.updateUnitDataPlayMode", type = GS, sig = "updateUnitDataPlayMode()" },
    { key = "GameSystem.setCleared", type = GS, sig = "setCleared()" },
    { key = "GameSystem.resetCleared", type = GS, sig = "resetCleared()" },
    { key = "GameSystem.clear", type = GS, sig = "clear()" },
    { key = "GameSystem.BootConvertUnitData", type = GS, sig = "BootConvertUnitData(System.Int32)", args = { "i32" } },
    { key = "GameSystem.updateSlotTimeStamp", type = GS, sig = "updateSlotTimeStamp(System.Boolean)", args = { "bool" } },
    { key = "GameSystem.updateSlotCheckCache", type = GS, sig = "updateSlotCheckCache(System.Boolean)", args = { "bool" } },
    { key = "GameSystem.setGameClearDataMidst", type = GS, sig = "setGameClearDataMidst(System.Boolean)", args = { "bool" } },
    { key = "GameSystem.setGameLstSave", type = GS, sig = "setGameLstSave(System.Boolean)", args = { "bool" } },

    -- app.SaveDataManager
    { key = "SaveDataManager.requestLoad", type = SDM,
      sig = "requestLoad(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { "i32", SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestLoadAuto", type = SDM,
      sig = "requestLoadAuto(app.SaveDataManager.SaveLoadRequestArgs)", args = { SLOT_REQ }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestLoadManual", type = SDM,
      sig = "requestLoadManual(System.Int32, app.SaveDataManager.SaveLoadRequestArgs)",
      args = { "i32", SLOT_REQ }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestLoadSlot", type = SDM,
      sig = "requestLoadSlot(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { "i32", SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestSave", type = SDM,
      sig = "requestSave(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { "i32", SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestSaveAuto", type = SDM,
      sig = "requestSaveAuto(app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestSaveManual", type = SDM,
      sig = "requestSaveManual(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { "i32", SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.requestSaveSlot", type = SDM,
      sig = "requestSaveSlot(System.Int32, app.SaveDataManager.SaveLoadRequestArgs, System.UInt32[])",
      args = { "i32", SLOT_REQ, "u32arr" }, cap = BIG_SPEC_CAP },
    { key = "SaveDataManager.loadGame", type = SDM, sig = "loadGame()" },
    { key = "SaveDataManager.loadGameSaveData", type = SDM, sig = "loadGameSaveData()" },
    { key = "SaveDataManager.saveGameSaveData", type = SDM, sig = "saveGameSaveData()" },
    { key = "SaveDataManager.isExistSaveData", type = SDM, sig = "isExistSaveData(System.Int32)", args = { "i32" },
      ret = "bool", chatty = true, cap = CHATTY_SPEC_CAP },
    { key = "SaveDataManager.getLoadingGameSlotId", type = SDM, sig = "getLoadingGameSlotId()", ret = "i32",
      chatty = true, cap = CHATTY_SPEC_CAP },

    -- app.MainFlowManager
    { key = "MainFlowManager.requestStartType", type = MFM, sig = "requestStartType(app.MainFlowManager.StartType)",
      args = { START }, cap = BIG_SPEC_CAP },
    { key = "MainFlowManager.requestLoadGameData", type = MFM, sig = "requestLoadGameData(System.Int32)", args = { "i32" } },
    { key = "MainFlowManager.setContinueSlot", type = MFM, sig = "setContinueSlot(System.Int32)", args = { "i32" } },
    { key = "MainFlowManager.set_LastLoadedSlot", type = MFM, sig = "set_LastLoadedSlot(System.Int32)", args = { "i32" } },
    { key = "MainFlowManager.restart", type = MFM, sig = "restart()" },
    { key = "MainFlowManager.LoadSaveDataSuccess", type = MFM, sig = "LoadSaveDataSuccess()" },
    { key = "MainFlowManager.onCompleteSceneLoad", type = MFM, sig = "onCompleteSceneLoad()" },
    { key = "MainFlowManager.onPlayStartEvent", type = MFM, sig = "onPlayStartEvent()" },
    { key = "MainFlowManager.addContinueCount", type = MFM, sig = "addContinueCount()" },

    -- app.SaveUnitSelectGUIFlowController (a component: `this` is remembered for the snapshots)
    { key = "SaveUnitSelect.setUseUnitNo", type = SUC, sig = "setUseUnitNo(System.Int32)", args = { "i32" },
      capture = true, cap = BIG_SPEC_CAP },
    { key = "SaveUnitSelect.resetUseUnitNo", type = SUC, sig = "resetUseUnitNo()", capture = true },
    { key = "SaveUnitSelect.onDecideUnitList", type = SUC, sig = "onDecideUnitList(app.ui030902.MainListInfo)",
      args = { decode_unit_item }, capture = true, cap = BIG_SPEC_CAP },
    { key = "SaveUnitSelect.onDecideSaveList", type = SUC, sig = "onDecideSaveList(app.ui030901.MainListInfo)",
      args = { decode_save_item }, capture = true, cap = BIG_SPEC_CAP },
    { key = "SaveUnitSelect.onExecuteGameRestart", type = SUC, sig = "onExecuteGameRestart(app.ui030902.MainListInfo)",
      args = { decode_unit_item }, capture = true },
    { key = "SaveUnitSelect.set_IsNewGame", type = SUC, sig = "set_IsNewGame(System.Boolean)", args = { "bool" },
      capture = true },
    { key = "SaveUnitSelect.set_SelectStartType", type = SUC, sig = "set_SelectStartType(app.MainFlowManager.StartType)",
      args = { START }, capture = true },
    { key = "SaveUnitSelect.requestStartFlow", type = SUC, sig = "requestStartFlow()", capture = true },
    { key = "SaveUnitSelect.executeConfirm", type = SUC,
      sig = "executeConfirm(app.SaveUnitSelectGUIFlowController.ConfirmDialogType)",
      args = { "enum:app.SaveUnitSelectGUIFlowController.ConfirmDialogType" }, capture = true, cap = BIG_SPEC_CAP },
    { key = "SaveUnitSelect.transitFlow", type = SUC, sig = "transitFlow(app.SaveUnitSelectGUIFlowController.FlowId)",
      args = { "enum:app.SaveUnitSelectGUIFlowController.FlowId" }, capture = true, cap = 200 },
    -- Not in the brief's list: forget the remembered controller when the game destroys it (a dangling `this` must not
    -- be read by the snapshots). Counted only.
    { key = "SaveUnitSelect.onDestroy", type = SUC, sig = "onDestroy()", quiet = true, chatty = true, forget = true },

    -- app.ui030901
    { key = "ui030901.calcSaveSlotNo", type = UI1, sig = "calcSaveSlotNo(app.ui030901.SaveDataType)",
      args = { "enum:app.ui030901.SaveDataType" }, ret = "i32", chatty = true, cap = 60 },
}

for _, spec in ipairs(SPECS) do
    spec.cap = spec.cap or DEFAULT_SPEC_CAP
end

local function count_of(spec)
    local c = run.count_by_spec[spec.key]
    if not c then c = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = c end
    return c
end

-- Queue the full `after:<key>` snapshot for the next frame, at most one per hook key per 2 s.
local function queue_after(spec)
    local now = os.clock()
    local last = after_last[spec.key]
    if last and now - last < AFTER_THROTTLE_SECONDS then
        run.after_suppressed[spec.key] = (run.after_suppressed[spec.key] or 0) + 1
        return
    end
    after_last[spec.key] = now
    queue_work(function() take_snapshot("after:" .. spec.key, "hook") end)
end

local function pre_body(spec, args)
    local c = count_of(spec)
    c.pre = c.pre + 1
    local st = frames[spec.key]
    if not st then st = {}; frames[spec.key] = st end
    if #st >= STACK_MAX then st = {}; frames[spec.key] = st; log_error("stack", spec.key) end
    if in_self_call then
        -- fired by this script's own getter calls: pushed so the post pops it, never logged
        run.self_calls[spec.key] = (run.self_calls[spec.key] or 0) + 1
        st[#st + 1] = { spec = spec, self = true }
        return
    end
    local frame = { spec = spec, seq = next_seq() }
    st[#st + 1] = frame -- pushed first: post must find it even if the rest of this body throws
    if spec.capture and not spec.forget then
        local ok, o = pcall(to_managed, args[2])
        if ok and o ~= nil then
            local ok2, f = pcall(unit_select_fields, o)
            if ok2 then
                f.read_in, f.wall = spec.key, wall()
                suc_last = f
                suc_seen = suc_seen + 1
            else
                log_error("unit_select_fields " .. spec.key, f)
            end
        end
    end
    if spec.quiet then return end
    local n = logged_by_spec[spec.key] or 0
    if #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
    elseif n >= spec.cap then
        run.dropped = run.dropped + 1
        run.dropped_by_spec[spec.key] = (run.dropped_by_spec[spec.key] or 0) + 1
    else
        frame.log = true
    end
    if not frame.log then return end
    local e = { seq = frame.seq, t = os.clock(), wall = wall(), method = spec.key, phase = "pre" }
    if spec.args then
        local ok, vals = pcall(decode_args, spec.args, args)
        e.args = ok and vals or ("ERR: " .. tostring(vals))
    end
    if not spec.chatty then
        local ok, q = pcall(quick_state)
        e.state = ok and q or ("ERR: " .. tostring(q))
    end
    frame.logged = append_entry(spec, e) ~= nil
end

local function post_body(spec, retval)
    local c = count_of(spec)
    c.post = c.post + 1
    local st = frames[spec.key]
    local frame = st and st[#st]
    if not frame then return end
    st[#st] = nil
    if frame.self or spec.quiet then return end
    if frame.logged then
        local e = { seq = next_seq(), t = os.clock(), wall = wall(), method = spec.key, phase = "post", pre_seq = frame.seq }
        if spec.ret then
            local ok, v = pcall(decode_ret, spec.ret, retval)
            e.ret = ok and v or ("ERR: " .. tostring(v))
        end
        if not spec.chatty then
            local ok, q = pcall(quick_state)
            e.state = ok and q or ("ERR: " .. tostring(q))
        end
        append_entry(spec, e)
    end
    if not spec.chatty then queue_after(spec) end
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
    for _, key in ipairs(installed) do run.count_by_spec[key] = { pre = 0, post = 0 } end
    if #missing == 0 then
        hook_status = string.format("all %d hooks installed", #installed)
    else
        hook_status = string.format("%d/%d hooks installed; MISSING: %s", #installed, #SPECS, table.concat(missing, ", "))
    end
    dirty = true
end

-- ---------------------------------------------------------------------------------------------------------
-- Update-thread work: queued snapshots, once-a-second poll, flush

local function refresh()
    if not constants_complete and constants_tries < CONSTANT_RETRIES then
        constants_tries = constants_tries + 1
        local ok, res = pcall(read_constants)
        if ok then constants_complete = res else log_error("read_constants", res) end
    end
    local ok, err = pcall(poll)
    if not ok then log_error("poll", err) end
end

local function flush()
    last_flush = os.clock()
    local ok, err = pcall(function()
        local out = {}
        for k, v in pairs(run) do out[k] = type(v) == "table" and nz(v) or v end
        out.hooks = { installed = nz(run.hooks.installed), missing = nz(run.hooks.missing) }
        out.last_state = live or "none"
        out.summary = {
            calls_logged = #calls, calls_dropped = run.dropped, snapshots = #run.snapshots, changes = #run.changes,
            markers = #run.markers, errors = #run.errors, snapshots_dropped = run.snapshots_dropped,
            manual_dropped = run.manual_dropped, unit_select_seen = suc_seen, unit_select_dropped = suc_dropped,
            constants_complete = constants_complete,
        }
        json.dump_file(RUN_FILE, out)
    end)
    if ok then
        dirty = false
        flush_status = "Flushed " .. wall()
    else
        flush_status = "Flush FAILED: " .. tostring(err)
    end
end

install_hooks()

re.on_pre_application_entry("UpdateBehavior", function()
    local now = os.clock()
    if #work_queue > 0 then
        local q = work_queue
        work_queue = {}
        for _, fn in ipairs(q) do
            local ok, err = pcall(fn)
            if not ok then log_error("work", err) end
        end
    end
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
-- UI (draws cached data and sets flags / queues work; makes no game calls)

local function sget(t, ...)
    for _, k in ipairs({ ... }) do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

local function show(v)
    if type(v) == "table" then
        if v._empty then return "[]" end
        if v.v ~= nil and v.name ~= nil then return tostring(v.name) .. "(" .. tostring(v.v) .. ")" end
        if v[1] ~= nil then return "[" .. join(v) .. "]" end
        return "{...}"
    end
    return tostring(v)
end

local function row(label, v) imgui.text(string.format("%-34s %s", label, show(v))) end

local function draw_live()
    if not live then imgui.text("(no snapshot yet)"); return end
    local g, s, m, w = live.gs, live.sdm, live.mfm, live.world
    row("UnitNumber", sget(g, "UnitNumber"))
    row("LatestSaveSlot", sget(g, "LatestSaveSlot"))
    row("getLatestSaveSlot()", sget(g, "getLatestSaveSlot"))
    row("SaveSlotType of LatestSaveSlot", sget(g, "getSaveSlotType_of_LatestSaveSlot"))
    local pu = {}
    local per = sget(g, "getLatestSaveSlotNum")
    if type(per) == "table" then
        for i = 0, UNIT_LOOP_CAP - 1 do
            if per[tostring(i)] ~= nil then pu[#pu + 1] = string.format("u%d=%s", i, tostring(per[tostring(i)])) end
        end
    end
    row("getLatestSaveSlotNum", table.concat(pu, " "))
    row("LastLoadedSlot", sget(m, "get_LastLoadedSlot"))
    row("getLoadingGameSlotId", sget(s, "getLoadingGameSlotId"))
    row("SaveCount", sget(g, "detail", "SaveCount"))
    row("ActualPlayingTime", sget(g, "detail", "ActualPlayingTime"))
    row("UnitPlayCountList", sget(g, "UnitPlayCountList"))
    row("IsGameClearedList", sget(g, "IsGameClearedList"))
    row("in_world", sget(w, "in_world"))
    local party = {}
    for _, e in ipairs(sget(w, "party") or {}) do party[#party + 1] = tostring(e.name or e.id) end
    row("party", table.concat(party, ", "))
    row("player", sget(w, "player_name"))
    row("SaveUnitSelect controller", suc_last and ("read in " .. tostring(suc_last.read_in) .. " at " .. tostring(suc_last.wall)) or "none")
end

local function fmt_change(c)
    local p = {}
    for k, v in pairs(c.to or {}) do
        local f = c.from and c.from[k]
        p[#p + 1] = f ~= nil and (k .. ": " .. tostring(f) .. " -> " .. tostring(v)) or (k .. "=" .. tostring(v))
    end
    table.sort(p)
    return string.format("%s %s%s", c.wall, c.world and ("[" .. c.world .. "] ") or "", clip(table.concat(p, "; "), 160))
end

local function draw_body()
    imgui.text("THROWAWAY. Log-only: calls getters and writes only its own run file. Back up first.")
    imgui.text(hook_status)
    imgui.text("Run file: reframework/data/" .. RUN_FILE)
    local seen = 0
    for _, c in pairs(run.count_by_spec) do seen = seen + c.pre + c.post end
    imgui.text(string.format("Calls: %d logged, %d dropped, %d seen | snapshots %d (+%d dropped) | changes %d | errors %d",
        #calls, run.dropped, seen, #run.snapshots, run.snapshots_dropped + run.manual_dropped, #run.changes, #run.errors))
    imgui.text(flush_status)
    if not constants_complete then imgui.text("constants: not all read yet (retrying)") end

    if imgui.tree_node("Live state (refreshed every second)") then
        local ok, err = pcall(draw_live)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end

    local ch, v = imgui.input_text("Marker", markers_text)
    if ch then markers_text = v end
    imgui.same_line()
    if imgui.button("Add marker") and markers_text ~= "" then
        local text = markers_text
        queue_work(function()
            if #run.markers >= MARKER_CAP then return end
            run.markers[#run.markers + 1] = { t = os.clock(), wall = wall(), label = text }
            take_snapshot("marker:" .. text, "manual")
            dirty = true
        end)
    end
    if #run.markers > 0 then imgui.text("last marker: " .. run.markers[#run.markers].label) end
    if imgui.button("Snapshot now") then queue_work(function() take_snapshot("manual", "manual") end) end
    imgui.same_line()
    if imgui.button("Flush log now") then flush_requested = true end

    imgui.text("Last changes:")
    for i = math.max(1, #run.changes - LOG_LINES + 1), #run.changes do
        imgui.text("  " .. fmt_change(run.changes[i]))
    end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Exp SaveSlot (EXPERIMENT)") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
