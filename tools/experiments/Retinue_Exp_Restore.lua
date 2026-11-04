-- Retinue Exp Restore: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- What it answers (M2, ticket "Can a backup be written into a re-hired pawn?"): can a stored backup (level, exp,
-- stat growth, extra status boost, discipline, CulmativeExp) be written into a pawn just re-hired from the Rift,
-- matched by OfflineID on hirePawn post; does it stick through save, reload and a full relaunch; when does the
-- pawn's ContextDBMS record become writable; and where does equipment the player gave the pawn go on dismiss and
-- on lost. See tools/experiments/README.md for the procedure.
--
-- The hooks are LOG-ONLY (except the backup capture in dismissPawn pre, which only reads the game): they never
-- change an argument or a return value, and none of them is a method the mod hooks (the mod hooks only
-- app.ExpDispenser members and GuiManager.reqJobRankUp), so this script can be linked TOGETHER with the mod and
-- with the lifecycle script (deploy.sh --restore). Hooking a method the lifecycle script also hooks (hirePawn,
-- dismissPawn, returnSubPawnItems) is fine in REFramework.
-- The Restore write (button or an automatic mode) CHANGES the live pawn and so the save: BACK UP FIRST
-- (tools/saves.sh backup <label>). With the default settings the script writes nothing to the game.
--
-- Output:
--   reframework/data/Retinue/experiments/restore_<timestamp>.json  one run file per session, flushed every 2 s
--   reframework/data/Retinue/experiments/restore_backups/<offline_id>.json + index.json  the backups. UNLIKE the
--   lifecycle script these persist between sessions (the restore happens after a relaunch). tools/saves.sh restore
--   wipes reframework/data/Retinue, backups included.
-- Hooks cannot be removed in REFramework, so all of them are installed at load. Every hook body is wrapped in
-- pcall: a bug here must never break a game call. Game state is only touched in the update callback
-- (re.on_pre_application_entry("UpdateBehavior")), never in the UI callback; hooks only read.
-- API names were checked against this game version's il2cpp_dump.json; helpers are copied from
-- Retinue_Exp_Lifecycle.lua (scripts are standalone).

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "restore_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local BACKUP_DIR = RUN_DIR .. "restore_backups/"
local INDEX_FILE = BACKUP_DIR .. "index.json"
local BACKUP_VERSION = 1
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 20000
local DEFAULT_SPEC_CAP = 300
local IMPORTANT_SPEC_CAP = 2000
local LIST_CAP_ENTRIES = 2000 -- cap of every non-call list (returns, compares, transitions, ...)
local ERROR_CAP = 200
local STACK_MAX = 16
local TIMER_MAX = 500
local LIST_CAP = 64
local LOG_LINES = 12
local DIFF_LINES = 24
local CONFIRM_SECONDS = 10.0
local ABSENT_SECONDS = 30.0
local MODE2_SECONDS = 2.0
local AFTER_SECONDS_1, AFTER_SECONDS_2 = 1.0, 10.0
local DISMISS_DEDUPE_SECONDS = 1.0
local JOB_COUNT = 10

local RESTORE_MODES = {
    "0 Log only (default)", "1 Auto: next frame after hirePawn post", "2 Auto: after 2 s",
}
local IP_MODES = { "0 fields on the existing object (default)", "1 setIncreaseParam(new object)" }
-- app.IncreaseStatus: backup key, field name
local IP_FIELDS = {
    { "hit_point", "_HitPoint" }, { "stamina", "_Stamina" }, { "attack", "_Attack" }, { "defence", "_Defence" },
    { "magic_attack", "_MagicAttack" }, { "magic_defence", "_MagicDefence" }, { "blow", "_Blow" },
    { "weight", "_Weight" },
}
local IP_CAPS = {
    { "hit_point", "IsCapHitPoint" }, { "stamina", "IsCapStamina" }, { "attack", "IsCapAttack" },
    { "defence", "IsCapDefence" }, { "magic_attack", "IsCapMagicAttack" }, { "magic_defence", "IsCapMagicDefence" },
    { "blow", "IsCapBlow" }, { "weight", "IsCapWeight" },
}

-- Session settings (never persisted). Defaults write nothing to the game.
local restore_mode, ip_mode = 0, 0
local ignore_guard, auto_capture, log_calls = false, true, true
local hook_status, flush_status, refresh_status, backup_status = "hooks not installed yet", "", "no data yet", ""
local action_status = ""
local flush_requested = false
local names = {} -- CharacterID -> last seen display name

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    constants = {
        script = "Retinue_Exp_Restore",
        main_id = MAIN_ID,
        call_cap = CALL_CAP,
        default_spec_cap = DEFAULT_SPEC_CAP,
        important_spec_cap = IMPORTANT_SPEC_CAP,
        refresh_seconds = REFRESH_SECONDS,
        flush_seconds = FLUSH_SECONDS,
        backup_dir = BACKUP_DIR,
        backup_version = BACKUP_VERSION,
        restore_modes = RESTORE_MODES,
        ip_modes = IP_MODES,
    },
    calls = {},
    actions = {}, -- capture, restore, delete_backup, refused/failed button presses
    compares = {},
    returns = {}, -- hirePawn post detection: hire_post, reread, return_matched, restore_waiting, ...
    record_transitions = {},
    markers = {},
    item_counts = {},
    notes = {}, -- pawn-absent, settings changes, ...
    errors = {},
    hooks = { installed = {}, missing = {} },
    dropped = 0,
    dropped_by_spec = {},
    count_by_spec = {}, -- hook -> { pre = n, post = n }: every call seen, logged or not
}
local calls = run.calls
local logged_by_spec = {}
local seq, dirty, frame_no = 0, true, 0
local last_flush, last_refresh = -FLUSH_SECONDS, -REFRESH_SECONDS

-- State shared between hooks, the update callback and the UI.
local backups, backup_order = {}, {} -- OfflineID -> backup table; load/capture order
local pending_write = {} -- OfflineID -> true: backup file to (re)write in the update callback
local index_dirty = false
local party_rows = {} -- from the refresh: { slot, id, offline, name, level, exp }
local known_ids = {} -- CharacterID -> true: party pawns and backed-up pawns (cap bypass for item hooks)
local id_to_offline = {} -- CharacterID -> OfflineID
local first_seen, absent_noted = {}, {} -- per OfflineID, per session
local party_nonempty_since = nil
local last_record_key = {} -- OfflineID -> last record-state key
local last_dismiss_capture = {} -- OfflineID -> os.clock() of the last dismissPawn-pre capture or count schedule
local last_restore_view, last_compare_view = nil, nil -- for the panel
local job_queue = {}
local timers = {}
local ui = { slot = 1, compare_label = "compare", marker_label = "saved", backup_pick = 1 }
local armed = nil -- { key, deadline }

local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_pu_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")
local m_pu_is_main = td_pawn_util and td_pawn_util:get_method("isMainPawn(app.CharacterID)")
local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")
local td_dbms = sdk.find_type_definition("app.ContextDBMS")
local m_has_record = td_dbms and td_dbms:get_method("hasRecord(app.UniqueID)")
local td_im = sdk.find_type_definition("app.ItemManager")

-- ---------------------------------------------------------------------------------------------------------
-- Small helpers (copied from Retinue_Exp_Lifecycle.lua)

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

-- Makes a value safe for json.dump_file (no userdata/functions). REFramework writes an empty table as null, so
-- an empty table becomes the marker object { _empty = true } (read it as []).
local function sanitize(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
    if t == "table" then
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

-- A list as stored in JSON: {} or { _empty = true } read back as no elements.
local function lst(t)
    if type(t) ~= "table" or t._empty then return {} end
    return t
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

local function to_int(v)
    if type(v) == "number" then return math.tointeger(v) or v end
    return v
end

local function is_err(v) return type(v) == "string" and v:sub(1, 5) == "ERR: " end

local function arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end
local function arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
local function arg_bool(a) return (sdk.to_int64(a) & 1) == 1 end

local function singleton(name) return sdk.get_managed_singleton(name) end

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

local m_get_equip = td_im and find_method(td_im, "getEquipData(app.CharacterID)")
-- getHaveAllNum / getHavePartyNum have a Predicate overload: take the Int32 one explicitly
local m_have_all = td_im and find_method(td_im, "getHaveAllNum(System.Int32)")
local m_have_party = td_im and find_method(td_im, "getHavePartyNum(System.Int32)")

-- Lists of numbers/enums (capped).
local function read_list_numbers(list)
    if list == nil then return nil end
    local n = list:call("get_Count")
    local out = {}
    for i = 0, math.min(n, LIST_CAP) - 1 do
        local v = list:call("get_Item", i)
        out[#out + 1] = type(v) == "number" and v or str(v)
    end
    return out
end

-- Numbers of a List<T> or of an array (Skills is an array in the lifecycle script's reads); capped.
local function read_numbers_any(obj)
    if obj == nil then return nil end
    local ok, elems = pcall(function() return obj:get_elements() end)
    if ok and type(elems) == "table" then
        local out = {}
        for i = 1, math.min(#elems, LIST_CAP) do
            local v = elems[i]
            out[i] = type(v) == "number" and v or (tonumber(str(v)) or str(v))
        end
        return out
    end
    return read_list_numbers(obj)
end

-- Int32[] -> plain Lua integers. The first lifecycle run showed that get_elements() hands back boxed elements
-- (they came out as strings via str()), so every element goes through tonumber(str(v)).
local function read_num_array(arr)
    if arr == nil then return nil end
    local raw = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do raw[i] = v end
    else
        local n = arr:call("get_Length")
        for i = 0, n - 1 do raw[i + 1] = arr:call("GetValue", i) end
    end
    local out = {}
    for i, v in ipairs(raw) do
        local n = type(v) == "number" and v or tonumber(str(v))
        if n == nil then error("array element " .. i .. " is not a number: " .. str(v)) end
        out[i] = to_int(n)
    end
    return out
end

local function holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

local function chara_id_of(chara) return to_u32(chara:call("get_CharaID")) end

local function valid_offline(s)
    return type(s) == "string" and #s >= 32 and s:match("^[%x%-]+$") ~= nil and s:match("^[0%-]+$") == nil
end

-- OfflineID as a string, read directly from the actor's PawnOwnerContext: the value, or "nil: ..." / "ERR: ..."
-- (reading it inside hirePawn post is one of the questions).
local function read_offline_direct(chara)
    local ok, v = pcall(function()
        local holder = chara:call("get_Context")
        if not holder then return "nil: no ContextHolder" end
        local owner = holder_context(holder, "app.PawnOwnerContext")
        if not owner then return "nil: no PawnOwnerContext" end
        return str(owner:get_field("_OfflineID"))
    end)
    return ok and v or ("ERR: " .. tostring(v))
end

-- Offline ID (as a string), UniqueID object and ContextHolder of a live actor.
local function owner_of(chara)
    local holder = chara:call("get_Context")
    if not holder then return nil end
    local owner = holder_context(holder, "app.PawnOwnerContext")
    local offline
    if owner then offline = str(owner:get_field("_OfflineID")) end
    return offline, holder:call("get_UniqID"), holder
end

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

local function party_list()
    local pm = singleton("app.PawnManager")
    if not pm then return nil end
    return pm:get_field("_PartyPawnList")
end

-- Live actors of the party: { slot, chara, pawn }.
local function party_charas()
    local out = {}
    local party = party_list()
    if not party then return out end
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara then out[#out + 1] = { slot = i + 1, chara = chara, pawn = pawn } end
    end
    return out
end

local function find_party_chara(id)
    for _, p in ipairs(party_charas()) do
        if chara_id_of(p.chara) == id then return p.chara end
    end
    return nil
end

-- Live actor with this OfflineID (preferred) or CharacterID, or nil.
local function find_chara(offline, id)
    local list = party_charas()
    if valid_offline(offline) then
        for _, p in ipairs(list) do
            if read_offline_direct(p.chara) == offline then
                return p.chara, p.slot
            end
        end
    end
    if type(id) == "number" then
        for _, p in ipairs(list) do
            if chara_id_of(p.chara) == id then return p.chara, p.slot end
        end
    end
    return nil
end

local function chara_name(chara)
    return str(try(function() return m_gui_name:call(nil, chara) end))
end

-- Refuses the main pawn, the player and non-hired pawns. Returns the CharacterID, or nil + why.
local function hired_check(chara)
    local id = chara_id_of(chara)
    if id == MAIN_ID then return nil, "refused: main pawn ch100000_00" end
    if m_pu_is_main:call(nil, id) == true then return nil, "refused: main pawn" end
    local cm = singleton("app.CharacterManager")
    local player = cm and cm:call("get_ManualPlayer")
    if player and chara_id_of(player) == id then return nil, "refused: the player" end
    if m_pu_is_sub:call(nil, id) ~= true then return nil, "refused: not a hired pawn" end
    return id
end

-- Appends a sanitized copy of `entry` to a run list (capped) and returns the stored copy (mutate it with put()).
local function add(list, entry)
    if #list >= LIST_CAP_ENTRIES then
        run.dropped = run.dropped + 1
        return nil
    end
    local stored = sanitize(entry)
    list[#list + 1] = stored
    dirty = true
    return stored
end

local function put(stored, key, value)
    if stored then
        stored[key] = sanitize(value)
        dirty = true
    end
end

local function note(kind, fields)
    fields = fields or {}
    fields.kind, fields.t, fields.wall = kind, os.clock(), wall()
    return add(run.notes, fields)
end

local function later(fn, opts)
    opts = opts or {}
    if #timers >= TIMER_MAX then
        log_error("later", "timer list full")
        return
    end
    timers[#timers + 1] = {
        fn = fn, due_frame = frame_no + (opts.frames or 0), due_clock = os.clock() + (opts.seconds or 0),
    }
end

local function process_timers()
    local now = os.clock()
    local keep, due = {}, {}
    for _, t in ipairs(timers) do
        if frame_no >= t.due_frame and now >= t.due_clock then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    for _, t in ipairs(due) do
        local ok, err = pcall(t.fn)
        if not ok then log_error("timer", err) end
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Reading a pawn: restored fields, verification fields, recorded-only data

local function read_equip(id)
    local im = singleton("app.ItemManager")
    -- getEquipData probably returns EmptyEquipData rather than null for an unknown ID: ask hasEquipData first
    if im:call("hasEquipData", id) ~= true then return false, nil end
    local red = m_get_equip:call(im, id)
    if red == nil then return false, nil end
    return true, read_list_numbers(red:call("getItemIds")) or {}
end

-- Restored + verification fields of a live actor (every field via try: one broken read never hides the rest).
local function read_fields(chara)
    local r = {}
    local human = chara:call("get_Human")
    if not human then r.error = "no Human"; return r end
    local st = human:call("get_StatusContext")
    local jc = human:call("get_JobContext")
    if st then
        r.level = try(function() return st:call("get_Level") end)
        r.exp = try(function() return st:call("get_Exp") end)
        local ip = try(function()
            local o = st:get_field("_IncreaseParams")
            if o == nil then o = st:call("get_IncreaseParams") end
            return o
        end)
        if type(ip) == "userdata" then
            local t, caps = {}, {}
            for _, f in ipairs(IP_FIELDS) do t[f[1]] = try(function() return ip:get_field(f[2]) end) end
            for _, f in ipairs(IP_CAPS) do caps[f[1]] = try(function() return ip:get_field(f[2]) end) end
            r.increase_params, r.increase_params_caps = t, caps
            r.increase_params_readonly = try(function() return ip:get_field("ReadOnly") end)
        else
            r.increase_params = ip == nil and "ERR: _IncreaseParams is nil" or ip
        end
        r.extra_status_boost = try(function() return st:get_field("_AcquiredExtraStatusBoost") end)
    else
        r.error = "no HumanStatusContext"
    end
    if jc then
        r.discipline = try(function() return jc:get_field("ConsumableExp") end)
        r.culmative_exp = try(function() return read_num_array(jc:get_field("CulmativeExp")) end)
        local cur = try(function() return jc:get_field("CurrentJob") end)
        r.current_job = cur
        r.qualified_job_bits = try(function() return jc:get_field("QualifiedJobBits") end)
        r.changed_job_bits = try(function() return jc:get_field("ChangedJobBits") end)
        local ranks = {}
        for j = 1, JOB_COUNT do ranks[j] = try(function() return jc:call("calcJobRank", j) end) end
        r.job_ranks = ranks -- index = JobEnum value 1..10
        if st and type(cur) == "number" then
            r.max_hp = try(function() return st:call("calcMaxHp", cur) end)
            r.max_stamina = try(function() return st:call("calcMaxStamina", cur) end)
        end
    else
        r.error = (r.error and (r.error .. "; ") or "") .. "no JobContext"
    end
    return r
end

local function all_numbers(t)
    if type(t) ~= "table" then return false end
    for _, v in pairs(t) do
        if type(v) ~= "number" then return false end
    end
    return true
end

-- A backup needs every restored field readable: otherwise it would overwrite a good backup with a bad one.
local function valid_restored(r)
    for _, k in ipairs({ "level", "exp", "extra_status_boost", "discipline" }) do
        if type(r[k]) ~= "number" then return false, k .. " unreadable: " .. str(r[k]) end
    end
    if type(r.increase_params) ~= "table" then return false, "increase_params unreadable: " .. str(r.increase_params) end
    for _, f in ipairs(IP_FIELDS) do
        if type(r.increase_params[f[1]]) ~= "number" then return false, "increase_params." .. f[1] .. " unreadable" end
    end
    if not all_numbers(r.culmative_exp) or #r.culmative_exp == 0 then return false, "culmative_exp unreadable" end
    return true
end

local function read_skills(holder)
    local sk = try(holder_context, holder, "app.HumanSkillContext")
    if type(sk) ~= "userdata" then return sk == nil and "none" or sk end
    return try(function()
        local out = { equiped = {} }
        local arr = sk:get_field("EquipedSkills"):get_elements()
        for i, e in ipairs(arr) do out.equiped[i] = read_numbers_any(e:get_field("Skills")) or {} end
        out.normal = read_list_numbers(sk:call("getEnableNormalSkillIDs")) or {}
        return out
    end)
end

-- Builds a backup from a live hired pawn. Returns the (unsanitized) table, or nil + why.
local function build_backup(chara, source)
    local id, why = hired_check(chara)
    if not id then return nil, why end
    local offline, _, holder = owner_of(chara)
    if not valid_offline(offline) then return nil, "refused: no usable OfflineID (" .. str(offline) .. ")" end
    local r = read_fields(chara)
    local ok, bad = valid_restored(r)
    if not ok then return nil, "not captured: " .. bad end
    local name = chara_name(chara)
    names[id] = name
    r.version, r.offline_id, r.name, r.character_id = BACKUP_VERSION, offline, name, id
    r.captured, r.source = os.date("%Y-%m-%d %H:%M:%S"), source
    -- recorded only
    local present, ids = false, nil
    local okq, perr = pcall(function() present, ids = read_equip(id) end)
    r.equipment_present = okq and present or false
    r.item_ids = (okq and ids) or {}
    if not okq then r.item_ids_error = tostring(perr) end
    local all, party = {}, {}
    for _, item in ipairs(r.item_ids) do
        all[tostring(item)] = try(function() return m_have_all:call(singleton("app.ItemManager"), item) end)
        party[tostring(item)] = try(function() return m_have_party:call(singleton("app.ItemManager"), item) end)
    end
    r.item_have_all_num, r.item_have_party_num = all, party
    r.skills = holder and read_skills(holder) or "none"
    return r
end

-- ---------------------------------------------------------------------------------------------------------
-- Backup storage (memory + files)

local function safe_name(offline) return (tostring(offline):gsub("[^%w%-_]", "_")) end

local function valid_loaded_backup(b, offline)
    if type(b) ~= "table" then return false, "not a table" end
    if b.version ~= BACKUP_VERSION then return false, "version " .. str(b.version) end
    if b.offline_id ~= offline then return false, "offline_id mismatch" end
    return valid_restored(b)
end

local function load_backups()
    local ok, idx = pcall(json.load_file, INDEX_FILE)
    if not ok or type(idx) ~= "table" then
        backup_status = "no backup index (starting empty)"
        return
    end
    local loaded, bad = 0, 0
    for _, offline in ipairs(lst(idx.offline_ids)) do
        local okb, b = pcall(json.load_file, BACKUP_DIR .. safe_name(offline) .. ".json")
        local valid, why = false, "unreadable"
        if okb then valid, why = valid_loaded_backup(b, offline) end
        if valid then
            backups[offline] = b
            backup_order[#backup_order + 1] = offline
            if type(b.character_id) == "number" then
                id_to_offline[b.character_id] = offline
                known_ids[b.character_id] = true
            end
            loaded = loaded + 1
        else
            bad = bad + 1
            log_error("load backup " .. tostring(offline), why)
        end
    end
    backup_status = string.format("%d backups loaded, %d unusable", loaded, bad)
end

local function store_backup(b)
    local s = sanitize(b)
    if backups[b.offline_id] == nil then backup_order[#backup_order + 1] = b.offline_id end
    backups[b.offline_id] = s
    pending_write[b.offline_id] = true
    index_dirty = true
    first_seen[b.offline_id] = true -- a pawn we just captured is not "first seen" later this session
    if type(b.character_id) == "number" then
        id_to_offline[b.character_id] = b.offline_id
        known_ids[b.character_id] = true
    end
    dirty = true
    return s
end

local function write_file_checked(path, data)
    json.dump_file(path, data)
    -- json.dump_file returns true even when the file cannot be opened: read it back when fs.read exists
    if fs and fs.read then
        local okr, text = pcall(fs.read, path)
        if not okr or text == nil or text == "" then return false, "read-back empty" end
    end
    return true
end

local function write_backups()
    for offline in pairs(pending_write) do
        pending_write[offline] = nil
        local b = backups[offline]
        if b then
            local ok, res, why = pcall(write_file_checked, BACKUP_DIR .. safe_name(offline) .. ".json", b)
            if ok and res then backup_status = "Backup file written " .. wall()
            else backup_status = "Backup write FAILED: " .. tostring(ok and why or res) end
        end
    end
    if index_dirty then
        index_dirty = false
        local list = {}
        for i, offline in ipairs(backup_order) do list[i] = offline end
        local ok, res, why = pcall(write_file_checked, INDEX_FILE, { version = 1, offline_ids = nz(list) })
        if not (ok and res) then backup_status = "Index write FAILED: " .. tostring(ok and why or res) end
    end
end

local function delete_backup(offline)
    if not backups[offline] then return false, "no such backup" end
    backups[offline] = nil
    for i, o in ipairs(backup_order) do
        if o == offline then table.remove(backup_order, i); break end
    end
    pending_write[offline] = nil
    index_dirty = true
    -- Lua cannot delete reliably here: try os.remove, else leave a tombstone (unlisted files are never loaded)
    local path = BACKUP_DIR .. safe_name(offline) .. ".json"
    local removed = pcall(function()
        local ok, err = os.remove("reframework/data/" .. path)
        if not ok then error(tostring(err)) end
    end)
    if not removed then pcall(json.dump_file, path, { version = BACKUP_VERSION, deleted = true, offline_id = offline }) end
    return true, removed and "file removed" or "file overwritten with a tombstone"
end

-- ---------------------------------------------------------------------------------------------------------
-- Diffs

local function values_equal(a, b)
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-3 end
    return tostring(a) == tostring(b)
end

local function sorted_join(t)
    local c = {}
    for i, v in ipairs(lst(t)) do c[i] = tonumber(v) or v end
    table.sort(c, function(x, y) return tostring(x) < tostring(y) end)
    local s = {}
    for i, v in ipairs(c) do s[i] = tostring(v) end
    return "[" .. table.concat(s, ",") .. "]"
end

-- Field-by-field diff of the backup's `bk` against a live read `cur`: restored + verification fields, plus the
-- equipment item_ids when `with_items`. Rows: { field, expected, actual, equal }.
local function diff_fields(bk, cur, with_items)
    local rows = {}
    local function row(field, expected, actual)
        rows[#rows + 1] = { field = field, expected = expected, actual = actual, equal = values_equal(expected, actual) }
    end
    for _, k in ipairs({ "level", "exp", "extra_status_boost", "discipline", "current_job", "qualified_job_bits",
        "changed_job_bits", "max_hp", "max_stamina", "increase_params_readonly" }) do
        row(k, bk[k], cur[k])
    end
    local bip, cip = type(bk.increase_params) == "table" and bk.increase_params or {},
        type(cur.increase_params) == "table" and cur.increase_params or {}
    for _, f in ipairs(IP_FIELDS) do row("increase_params." .. f[1], bip[f[1]], cip[f[1]]) end
    local bcap, ccap = type(bk.increase_params_caps) == "table" and bk.increase_params_caps or {},
        type(cur.increase_params_caps) == "table" and cur.increase_params_caps or {}
    for _, f in ipairs(IP_CAPS) do row("increase_params_caps." .. f[1], bcap[f[1]], ccap[f[1]]) end
    local bc, cc = lst(bk.culmative_exp), type(cur.culmative_exp) == "table" and cur.culmative_exp or {}
    for i = 1, math.max(#bc, #cc) do row("culmative_exp[" .. i .. "]", bc[i], cc[i]) end
    local br, cr = lst(bk.job_ranks), type(cur.job_ranks) == "table" and cur.job_ranks or {}
    for i = 1, math.max(#br, #cr, JOB_COUNT) do row("job_ranks[" .. i .. "]", br[i], cr[i]) end
    if with_items then row("item_ids", sorted_join(bk.item_ids), sorted_join(cur.item_ids)) end
    local n_diff = 0
    for _, r in ipairs(rows) do
        if not r.equal then n_diff = n_diff + 1 end
    end
    return { rows = rows, n = #rows, n_diff = n_diff, all_equal = n_diff == 0 }
end

-- ---------------------------------------------------------------------------------------------------------
-- Compare

local function do_compare(offline, chara, label)
    local bk = backups[offline]
    local entry = { t = os.clock(), wall = wall(), label = label, offline_id = offline }
    if not bk then
        entry.ok, entry.error = false, "no backup for this OfflineID"
        add(run.compares, entry)
        return
    end
    local id = chara_id_of(chara)
    entry.character_id, entry.name = id, chara_name(chara)
    local cur = read_fields(chara)
    local present, ids = false, nil
    local okq = pcall(function() present, ids = read_equip(id) end)
    cur.item_ids = (okq and ids) or {}
    local _, uniq_obj, holder = owner_of(chara)
    entry.record = record_state(id, uniq_obj)
    if holder then
        entry.is_restore = try(function() return holder:call("get_IsRestore") end)
        entry.is_store = try(function() return holder:call("get_IsStore") end)
    end
    local d = diff_fields(bk, cur, true)
    entry.ok, entry.n_diff, entry.all_equal, entry.diff = true, d.n_diff, d.all_equal, d.rows
    entry.live = { level = cur.level, exp = cur.exp, discipline = cur.discipline, current_job = cur.current_job }
    entry.backup_captured, entry.backup_source = bk.captured, bk.source
    add(run.compares, entry)
    last_compare_view = { label = label, name = entry.name, wall = entry.wall, rows = d.rows, n = d.n, n_diff = d.n_diff }
    action_status = string.format("compare '%s' %s: %d of %d fields differ", label, tostring(entry.name), d.n_diff, d.n)
end

-- ---------------------------------------------------------------------------------------------------------
-- Restore write (update callback only, on the LIVE actor)

local function step(writes, field, method, fn)
    local ok, res = pcall(fn)
    local w = { field = field, method = method, ok = ok }
    if not ok then w.error = tostring(res)
    elseif res ~= nil and type(res) ~= "userdata" then w.result = res end
    writes[#writes + 1] = w
    return ok, res
end

local function need_number(v, what)
    if type(v) ~= "number" then error("backup value missing or not a number: " .. what .. "=" .. str(v)) end
    return to_int(v)
end

-- Writes `vals` (Lua integers) into the existing Int32[] `arr` (JobContext.CulmativeExp; 1-based position = JobEnum).
-- Tries, in order: arr:call("SetValue", sdk.create_int32(v), i); index assignment arr[i] = v; then the game's own
-- JobContext methods per differing element: set_NowJobCulmativeExpProp(v) for the current job, addJobExp(job, delta)
-- for the others. A method counts only if reading the array back gives `vals`. The first in-game run (2026-11-04)
-- showed set_element does not exist and SetValue returns without changing the array.
-- Returns the method that worked (or nil) and the attempts.
local function write_array(arr, vals, jc)
    local n = arr:call("get_Length")
    if n ~= #vals then return nil, { { error = string.format("length mismatch: game %s, backup %d", str(n), #vals) } } end
    local function readback_equal()
        local okb, back = pcall(read_num_array, arr)
        if not (okb and type(back) == "table" and #back == #vals) then return false, nil end
        for i = 1, #vals do
            if back[i] ~= vals[i] then return false, back end
        end
        return true, back
    end
    local methods = {
        { "SetValue", function()
            for i = 0, n - 1 do arr:call("SetValue", sdk.create_int32(vals[i + 1]), i) end
        end },
        { "index assign", function()
            for i = 0, n - 1 do arr[i] = vals[i + 1] end
        end },
        { "game methods (set_NowJobCulmativeExpProp / addJobExp)", function(attempt)
            local _, back = readback_equal()
            if not back then error("array not readable") end
            local cur = to_int(jc:get_field("CurrentJob"))
            local disc_before = to_int(jc:get_field("ConsumableExp"))
            local calls = {}
            for i = 1, #vals do
                if back[i] ~= vals[i] then
                    if i == cur then
                        jc:call("set_NowJobCulmativeExpProp", vals[i])
                        calls[#calls + 1] = string.format("set_NowJobCulmativeExpProp(%d) job %d", vals[i], i)
                    else
                        jc:call("addJobExp(app.Character.JobEnum, System.Int32)", i, vals[i] - back[i])
                        calls[#calls + 1] = string.format("addJobExp(%d, %d)", i, vals[i] - back[i])
                    end
                end
            end
            attempt.calls = calls
            local disc_after = to_int(jc:get_field("ConsumableExp"))
            attempt.discipline_before, attempt.discipline_after = disc_before, disc_after
            if disc_after ~= disc_before then
                jc:call("set_ConsumableExpProp", disc_before) -- the game method touched discipline: put it back
                attempt.discipline_reset = to_int(jc:get_field("ConsumableExp"))
            end
        end },
    }
    local attempts = {}
    for _, m in ipairs(methods) do
        local attempt = { method = m[1] }
        local ok, err = pcall(m[2], attempt)
        attempt.ok = ok
        if not ok then attempt.error = tostring(err) end
        local same, back = readback_equal()
        attempt.readback_equal, attempt.readback = same, back
        attempts[#attempts + 1] = attempt
        if same then return m[1], attempts end
    end
    return nil, attempts
end

local function set_ip_fields(writes, obj, bk, prefix)
    local ip = type(bk.increase_params) == "table" and bk.increase_params or {}
    for _, f in ipairs(IP_FIELDS) do
        step(writes, "increase_params." .. f[1], prefix .. "set_field " .. f[2], function()
            obj:set_field(f[2], need_number(ip[f[1]], f[1]))
        end)
    end
end

-- Writes the backup of `offline` into the live actor `chara`. Returns the stored action entry.
local function do_restore(offline, chara, source)
    local bk = backups[offline]
    local entry = { kind = "restore", source = source, t = os.clock(), wall = wall(), offline_id = offline,
        ip_mode = ip_mode, ignore_guard = ignore_guard, restore_mode = restore_mode, writes = {} }
    local stored
    local function finish(ok, err)
        entry.ok, entry.error = ok, err
        stored = add(run.actions, entry)
        action_status = string.format("restore %s: %s", source, ok and "written" or ("NOT written: " .. tostring(err)))
        return stored
    end
    if not bk then return finish(false, "no backup for this OfflineID") end
    local id, why = hired_check(chara)
    entry.character_id, entry.name = id or chara_id_of(chara), chara_name(chara)
    if not id then return finish(false, why) end
    local human = chara:call("get_Human")
    local st = human and human:call("get_StatusContext")
    local jc = human and human:call("get_JobContext")
    if not (st and jc) then return finish(false, "no StatusContext or JobContext on the live actor") end
    entry.before = read_fields(chara)
    local live_level = entry.before.level
    if type(live_level) == "number" and type(bk.level) == "number" and live_level > bk.level and not ignore_guard then
        return finish(false, string.format("level guard: live level %s is above the backup's %s", str(live_level),
            str(bk.level)))
    end
    local writes = entry.writes

    step(writes, "level", "set_Level", function() st:call("set_Level", need_number(bk.level, "level")) end)
    step(writes, "exp", "set_Exp", function() st:call("set_Exp", need_number(bk.exp, "exp")) end)

    if ip_mode == 0 then
        local ip = try(function() return st:get_field("_IncreaseParams") end)
        if type(ip) ~= "userdata" then
            writes[#writes + 1] = { field = "increase_params", method = "get_field _IncreaseParams", ok = false,
                error = str(ip) }
        else
            local ro = try(function() return ip:get_field("ReadOnly") end)
            local was_ro = ro == true
            writes[#writes + 1] = { field = "increase_params.ReadOnly", method = "read", ok = true, result = ro }
            if was_ro then
                step(writes, "increase_params.ReadOnly", "setReadOnly(false)", function() ip:call("setReadOnly", false) end)
            end
            set_ip_fields(writes, ip, bk, "")
            if was_ro then
                step(writes, "increase_params.ReadOnly", "setReadOnly(true) (restored)", function()
                    ip:call("setReadOnly", true)
                end)
            end
        end
    else
        local obj
        local ok_new = step(writes, "increase_params", "sdk.create_instance(app.IncreaseStatus)", function()
            obj = sdk.create_instance("app.IncreaseStatus")
            if obj == nil then error("create_instance returned nil") end
            pcall(function() obj:add_ref() end)
        end)
        if ok_new then
            step(writes, "increase_params", ".ctor", function() obj:call(".ctor") end)
            set_ip_fields(writes, obj, bk, "new object: ")
            step(writes, "increase_params", "setIncreaseParam(new object)", function()
                st:call("setIncreaseParam", obj)
            end)
        end
    end

    local boost = to_int(bk.extra_status_boost)
    step(writes, "extra_status_boost", "setExtraStatusBoost", function()
        st:call("setExtraStatusBoost", need_number(bk.extra_status_boost, "extra_status_boost"))
    end)
    local back = try(function() return st:get_field("_AcquiredExtraStatusBoost") end)
    writes[#writes + 1] = { field = "extra_status_boost", method = "readback _AcquiredExtraStatusBoost", ok = true,
        result = back }
    if not values_equal(back, boost) then
        step(writes, "extra_status_boost", "FALLBACK set_field _AcquiredExtraStatusBoost", function()
            st:set_field("_AcquiredExtraStatusBoost", boost)
        end)
    end

    local disc = to_int(bk.discipline)
    step(writes, "discipline", "set_ConsumableExpProp", function()
        jc:call("set_ConsumableExpProp", need_number(bk.discipline, "discipline"))
    end)
    back = try(function() return jc:get_field("ConsumableExp") end)
    writes[#writes + 1] = { field = "discipline", method = "readback ConsumableExp", ok = true, result = back }
    if not values_equal(back, disc) then
        step(writes, "discipline", "FALLBACK set_field ConsumableExp", function() jc:set_field("ConsumableExp", disc) end)
    end

    local worked, attempts
    local ok_arr, err_arr = pcall(function()
        local arr = jc:get_field("CulmativeExp")
        if arr == nil then error("CulmativeExp is nil") end
        local vals = {}
        for i, v in ipairs(lst(bk.culmative_exp)) do vals[i] = need_number(v, "culmative_exp[" .. i .. "]") end
        worked, attempts = write_array(arr, vals, jc)
    end)
    local w = { field = "culmative_exp", method = worked or "none worked", ok = ok_arr and worked ~= nil,
        attempts = attempts }
    if not ok_arr then w.error = tostring(err_arr) end
    writes[#writes + 1] = w

    entry.after = read_fields(chara)
    local d = diff_fields(bk, entry.after, false)
    entry.diff_after = { n_diff = d.n_diff, all_equal = d.all_equal }
    finish(true, nil)
    last_restore_view = { stage = "after", name = entry.name, wall = entry.wall, source = source,
        rows = d.rows, n = d.n, n_diff = d.n_diff }

    -- the game may overwrite the values later: re-read at +1 s and +10 s
    for _, stage in ipairs({ { "after_1s", AFTER_SECONDS_1 }, { "after_10s", AFTER_SECONDS_2 } }) do
        later(function()
            local c = find_chara(offline, entry.character_id)
            if not c then
                put(stored, stage[1], { error = "pawn no longer in the party" })
                return
            end
            local r = read_fields(c)
            local dd = diff_fields(bk, r, false)
            put(stored, stage[1], r)
            put(stored, "diff_" .. stage[1], { n_diff = dd.n_diff, all_equal = dd.all_equal })
            if stage[1] == "after_10s" then put(stored, "diff", dd.rows) end
            last_restore_view = { stage = stage[1], name = entry.name, wall = entry.wall, source = source,
                rows = dd.rows, n = dd.n, n_diff = dd.n_diff }
        end, { seconds = stage[2] })
    end
    return stored
end

-- ---------------------------------------------------------------------------------------------------------
-- Item counts (equipment destination)

local function log_item_counts(offline, label)
    local bk = backups[offline]
    local entry = { kind = "item_counts", t = os.clock(), wall = wall(), label = label, offline_id = offline }
    if not bk then
        entry.error = "no backup for this OfflineID"
        add(run.item_counts, entry)
        return
    end
    entry.name, entry.character_id = bk.name, bk.character_id
    local im = singleton("app.ItemManager")
    local counts = {}
    for _, item in ipairs(lst(bk.item_ids)) do
        local k = tostring(item)
        counts[k] = {
            all = try(function() return m_have_all:call(im, item) end),
            party = try(function() return m_have_party:call(im, item) end),
            at_backup_all = bk.item_have_all_num and bk.item_have_all_num[k],
            at_backup_party = bk.item_have_party_num and bk.item_have_party_num[k],
        }
    end
    entry.counts = counts
    if type(bk.character_id) == "number" then
        local okq, present, ids = pcall(read_equip, bk.character_id)
        entry.equip_now = okq and { present = present, item_ids = ids or {} } or ("ERR: " .. tostring(present))
    end
    add(run.item_counts, entry)
end

-- ---------------------------------------------------------------------------------------------------------
-- Return detection (hirePawn pre/post, then re-reads in the update callback)

local return_n = 0

local function return_log(kind, ev, fields)
    fields = fields or {}
    fields.kind, fields.event, fields.t, fields.wall = kind, ev.n, os.clock(), wall()
    fields.character_id = fields.character_id or ev.id
    fields.name = fields.name or ev.name
    return add(run.returns, fields)
end

local function maybe_restore(ev, label)
    if not ev.matched or ev.restored then return end
    if ev.mode == 0 then return end
    if ev.mode == 2 and os.clock() < ev.t + MODE2_SECONDS then return end
    local chara = find_chara(ev.matched, ev.id)
    if not chara then
        return_log("restore_waiting", ev, { label = label, error = "matched pawn not in the party yet" })
        return
    end
    ev.restored = true
    do_restore(ev.matched, chara, "auto-mode" .. ev.mode .. "@" .. label)
end

local function match_check(ev, offline, label)
    if ev.matched or not valid_offline(offline) then return end
    if backups[offline] then
        ev.matched = offline
        local bk = backups[offline]
        return_log("return_matched", ev, { source = label, offline_id = offline, mode = ev.mode,
            backup_level = bk.level, backup_exp = bk.exp, backup_captured = bk.captured })
    elseif not ev.unmatched_logged then
        ev.unmatched_logged = true
        return_log("return_unmatched", ev, { source = label, offline_id = offline, note = "no backup for this OfflineID" })
    end
end

local function reread(ev, label)
    local chara = find_chara(ev.offline_post, ev.id)
    if not chara then
        return_log("reread", ev, { label = label, found = false })
        return false
    end
    local e = { label = label, found = true }
    e.character_id = chara_id_of(chara)
    e.offline_id = read_offline_direct(chara)
    local human = chara:call("get_Human")
    local st = human and human:call("get_StatusContext")
    if st then
        e.level = try(function() return st:call("get_Level") end)
        e.exp = try(function() return st:call("get_Exp") end)
    end
    local _, uniq_obj, holder = owner_of(chara)
    e.record = record_state(e.character_id, uniq_obj)
    if holder then
        e.is_restore = try(function() return holder:call("get_IsRestore") end)
        e.is_store = try(function() return holder:call("get_IsStore") end)
    end
    return_log("reread", ev, e)
    match_check(ev, valid_offline(e.offline_id) and e.offline_id or ev.offline_post, label)
    return true
end

local function schedule_return(ev)
    later(function()
        reread(ev, "1f")
        maybe_restore(ev, "1f")
    end, { frames = 1 })
    later(function()
        reread(ev, "1s")
        maybe_restore(ev, "1s")
    end, { seconds = 1.0 })
    if ev.mode == 2 then
        later(function()
            if not ev.matched then reread(ev, "2s") end
            maybe_restore(ev, "2s")
        end, { seconds = MODE2_SECONDS })
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook specs

local function P(name, kind) return { name, kind } end

local PM, IM = "app.PawnManager", "app.ItemManager"

-- hirePawn pre: keep the Character argument for post.
local function on_pre_hire(spec, args, frame, dec)
    local o = sdk.to_managed_object(args[3])
    frame.chara = o
    local out = {}
    if o then
        out.offline_id_in_pre = read_offline_direct(o)
        out.hire_name = chara_name(o)
    end
    return out
end

-- hirePawn post: the OfflineID is read directly inside post (one of the questions), then the re-reads and the
-- optional restore are scheduled for the update callback.
local function on_post_hire(spec, frame, retval)
    local ev = { n = return_n + 1, t = os.clock(), mode = restore_mode }
    return_n = ev.n
    local out = { ret = try(arg_bool, retval), restore_mode = restore_mode }
    local chara = frame.chara
    if chara then
        out.offline_id_in_post = read_offline_direct(chara)
        ev.id = try(chara_id_of, chara)
        if type(ev.id) ~= "number" then ev.id = nil end
        ev.name = chara_name(chara)
        out.id, out.name = ev.id, ev.name
        if valid_offline(out.offline_id_in_post) then ev.offline_post = out.offline_id_in_post end
        local human = chara:call("get_Human")
        local st = human and human:call("get_StatusContext")
        if st then
            out.level_in_post = try(function() return st:call("get_Level") end)
            out.exp_in_post = try(function() return st:call("get_Exp") end)
        end
        local _, uniq_obj = owner_of(chara)
        if ev.id then out.record = record_state(ev.id, uniq_obj) end
    else
        out.offline_id_in_post = "nil: no Character argument kept from pre"
    end
    return_log("hire_post", ev, { offline_id_in_post = out.offline_id_in_post, level_in_post = out.level_in_post,
        exp_in_post = out.exp_in_post, record = out.record, restore_mode = restore_mode, ret = out.ret })
    match_check(ev, ev.offline_post, "post")
    schedule_return(ev)
    return out
end

-- dismissPawn pre: capture the pawn's backup (read-only; the file is written in the update callback) and
-- schedule the item counts.
local function on_pre_dismiss(spec, args, frame, dec)
    local ident = frame.ident or {}
    local chara = ident.chara or (ident.id and find_party_chara(ident.id))
    if not chara then return { auto_capture = "skipped: no party character for this pawn" } end
    local id, why = hired_check(chara)
    if not id then return { auto_capture = "skipped: " .. why } end
    local offline = read_offline_direct(chara)
    if not valid_offline(offline) then return { auto_capture = "skipped: OfflineID " .. str(offline) } end
    local out = { offline_id = offline }
    local now = os.clock()
    local nested = last_dismiss_capture[offline] and now - last_dismiss_capture[offline] < DISMISS_DEDUPE_SECONDS
    if auto_capture and not nested then
        local b, err = build_backup(chara, "dismissPawn-pre")
        if b then
            store_backup(b)
            out.auto_capture = string.format("captured Lv %s Exp %s", str(b.level), str(b.exp))
        else
            out.auto_capture = "failed: " .. tostring(err)
        end
    elseif nested then
        out.auto_capture = "skipped: already handled for this dismiss (nested overload)"
    else
        out.auto_capture = "off"
    end
    if not nested then
        last_dismiss_capture[offline] = now
        if backups[offline] then
            later(function() log_item_counts(offline, "dismiss+1s") end, { seconds = 1.0 })
            later(function() log_item_counts(offline, "dismiss+5s") end, { seconds = 5.0 })
            out.item_counts_scheduled = true
        end
    end
    return out
end

local SPECS = {
    { key = "PawnManager.dismissPawn(CharacterID)", type = PM, sig = "dismissPawn(app.CharacterID)",
      params = { P("id", "cid") }, post = true, important = true, on_pre = on_pre_dismiss },
    { key = "PawnManager.dismissPawn(Character)", type = PM, sig = "dismissPawn(app.Character)",
      params = { P("chara", "chara") }, post = true, important = true, on_pre = on_pre_dismiss },
    { key = "PawnManager.dismissPawn(Pawn)", type = PM, sig = "dismissPawn(app.Pawn)",
      params = { P("pawn", "pawn") }, post = true, important = true, on_pre = on_pre_dismiss },
    { key = "PawnManager.hirePawn", type = PM, sig = "hirePawn(app.Character, System.Boolean)",
      params = { P("chara", "chara"), P("flag", "bool") }, post = true, important = true,
      on_pre = on_pre_hire, on_post = on_post_hire },
    -- Item destination: item id / count / owner are the first three parameters (itemId, num, CharacterID by
    -- ItemManager convention; the dump has no parameter names, so the order is an assumption).
    { key = "ItemManager.addStorageNoLock", type = IM,
      sig = "addStorageNoLock(System.Int32, System.Int32, app.CharacterID, app.ItemDefine.GetItemOption, System.Int32, System.Int32)",
      params = { P("item_id", "i32"), P("count", "i32"), P("chara_id", "cid"), P("option", "skip"),
          P("i5", "i32"), P("i6", "i32") }, bypass_known = true },
    { key = "ItemManager.addItemToStorageNoLock", type = IM,
      sig = "addItemToStorageNoLock(System.Int32, System.Int32, app.CharacterID, app.ItemDefine.GetItemOption, System.Int32, System.Int32, System.Boolean)",
      params = { P("item_id", "i32"), P("count", "i32"), P("chara_id", "cid"), P("option", "skip"),
          P("i5", "i32"), P("i6", "i32"), P("flag", "bool") }, bypass_known = true },
    { key = "ItemManager.subStorageNoLock(Int32,Int32,CharacterID,Int32)", type = IM,
      sig = "subStorageNoLock(System.Int32, System.Int32, app.CharacterID, System.Int32)",
      params = { P("item_id", "i32"), P("count", "i32"), P("chara_id", "cid"), P("i4", "i32") }, bypass_known = true },
    { key = "ItemManager.removeEquipData", type = IM, sig = "removeEquipData(app.CharacterID)",
      params = { P("chara_id", "cid") }, post = true, bypass_known = true },
    { key = "ItemManager.returnSubPawnItems", type = IM, sig = "returnSubPawnItems(app.CharacterID)",
      params = { P("chara_id", "cid") }, post = true, bypass_known = true },
}
for _, spec in ipairs(SPECS) do
    spec.cap = spec.important and IMPORTANT_SPEC_CAP or DEFAULT_SPEC_CAP
    spec.stack = {}
end

-- Decoders: (raw arg) -> value, optional identity { id, chara, offline }.
local DEC = {
    i32 = function(a) return arg_i32(a) end,
    bool = function(a) return arg_bool(a) end,
    skip = function() return nil end,
    cid = function(a)
        local id = arg_u32(a)
        return id, { id = id, name = names[id] }
    end,
    chara = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local id = chara_id_of(o)
        return id, { id = id, chara = o }
    end,
    pawn = function(a)
        local o = sdk.to_managed_object(a)
        if o == nil then return "nil" end
        local chara = o:call("get_CachedCharacter")
        if chara == nil then return "no character" end
        local id = chara_id_of(chara)
        return id, { id = id, chara = chara }
    end,
}

local function decode_args(spec, args, frame)
    local out = {}
    for k, p in ipairs(spec.params) do
        local ok, v, ident = pcall(DEC[p[2]], args[2 + k])
        if ok then
            out[p[1]] = v
            if ident and not frame.ident then frame.ident = ident end
        else
            out[p[1]] = "ERR: " .. tostring(v)
        end
    end
    return out
end

local function append_entry(entry)
    if #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
        return nil
    end
    entry = sanitize(entry)
    calls[#calls + 1] = entry
    dirty = true
    return entry
end

local function pre_body(spec, args)
    seq = seq + 1
    local cnt = run.count_by_spec[spec.key]
    if not cnt then cnt = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = cnt end
    cnt.pre = cnt.pre + 1
    if #spec.stack >= STACK_MAX then spec.stack = {} end
    local frame = { seq = seq }
    spec.stack[#spec.stack + 1] = frame -- pushed first: post must find it even if the rest of this body throws
    local dec = decode_args(spec, args, frame)
    local extra
    if spec.on_pre then
        local ok, res = pcall(spec.on_pre, spec, args, frame, dec)
        if ok then extra = res else extra = { on_pre_error = tostring(res) }; log_error("on_pre " .. spec.key, res) end
    end
    if not log_calls then return end
    local ident = frame.ident or {}
    local known = type(ident.id) == "number" and known_ids[ident.id] == true
    local n = logged_by_spec[spec.key] or 0
    if n >= spec.cap and not (spec.bypass_known and known and n < IMPORTANT_SPEC_CAP) then
        run.dropped = run.dropped + 1
        run.dropped_by_spec[spec.key] = (run.dropped_by_spec[spec.key] or 0) + 1
        return
    end
    local entry = { seq = seq, t = os.clock(), wall = wall(), method = spec.key, phase = "pre", id = ident.id,
        args = next(dec) and dec or nil }
    if type(ident.id) == "number" then
        entry.name = names[ident.id]
        entry.known_pawn = known or nil
        entry.backup_offline_id = id_to_offline[ident.id]
    end
    if extra then
        for k, v in pairs(extra) do entry[k] = v end
    end
    local stored = append_entry(entry)
    frame.logged = stored ~= nil
    frame.id = ident.id
    if stored then logged_by_spec[spec.key] = n + 1 end
end

local function post_body(spec, retval)
    local cnt = run.count_by_spec[spec.key]
    if not cnt then cnt = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = cnt end
    cnt.post = cnt.post + 1
    local frame = table.remove(spec.stack)
    if not frame then return end
    local extra
    if spec.on_post then
        local ok, res = pcall(spec.on_post, spec, frame, retval)
        if ok then extra = res else extra = { on_post_error = tostring(res) }; log_error("on_post " .. spec.key, res) end
    end
    if not (spec.post and (frame.logged or extra)) then return end
    seq = seq + 1
    local entry = { seq = seq, t = os.clock(), wall = wall(), method = spec.key, phase = "post", id = frame.id,
        pre_seq = frame.seq }
    if extra then
        for k, v in pairs(extra) do entry[k] = v end
    end
    append_entry(entry)
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
-- Button actions (queued by the UI, run in the update callback)

local function queue_job(job) job_queue[#job_queue + 1] = job end

-- The party member in slot N: { id, chara, offline, name } or nil + why.
local function resolve_target(slot)
    local list = party_charas()
    local p
    for _, c in ipairs(list) do
        if c.slot == slot then p = c end
    end
    if not p then return nil, "no pawn in slot " .. slot end
    local id, why = hired_check(p.chara)
    if not id then return nil, why end
    local offline = read_offline_direct(p.chara)
    if not valid_offline(offline) then return nil, "refused: no usable OfflineID (" .. str(offline) .. ")" end
    return { id = id, chara = p.chara, offline = offline, name = chara_name(p.chara) }
end

local function run_job(job)
    local entry = { t = os.clock(), wall = wall(), kind = job.kind, slot = job.slot, label = job.label }
    if job.kind == "marker" then
        add(run.markers, { t = entry.t, wall = entry.wall, label = job.label })
        action_status = "marker '" .. tostring(job.label) .. "'"
        return
    elseif job.kind == "setting" then
        note("setting", { name = job.name, value = job.value })
        return
    elseif job.kind == "item_counts" then
        log_item_counts(job.offline, "button")
        action_status = "item counts logged"
        return
    elseif job.kind == "delete_backup" then
        entry.offline_id, entry.name = job.offline, backups[job.offline] and backups[job.offline].name
        local ok, how = delete_backup(job.offline)
        entry.ok, entry.result = ok, how
        add(run.actions, entry)
        action_status = ok and ("backup deleted (" .. how .. ")") or ("delete failed: " .. how)
        return
    end
    local target, why = resolve_target(job.slot)
    if not target then
        entry.ok, entry.error = false, why
        add(run.actions, entry)
        action_status = job.kind .. " slot " .. job.slot .. ": " .. tostring(why)
        return
    end
    if job.expect_id and job.expect_id ~= target.id then
        entry.ok, entry.error = false, string.format("refused: slot %d now holds %d, armed for %d", job.slot, target.id,
            job.expect_id)
        add(run.actions, entry)
        action_status = entry.error
        return
    end
    entry.character_id, entry.name, entry.offline_id = target.id, target.name, target.offline
    if job.kind == "capture" then
        local b, err = build_backup(target.chara, "button")
        if not b then
            entry.ok, entry.error = false, err
        else
            store_backup(b)
            entry.ok = true
            entry.summary = { level = b.level, exp = b.exp, discipline = b.discipline, item_ids = b.item_ids }
        end
        add(run.actions, entry)
        action_status = string.format("capture slot %d: %s", job.slot, entry.ok and "stored" or tostring(entry.error))
    elseif job.kind == "restore" then
        if not backups[target.offline] then
            entry.ok, entry.error = false, "refused: no backup for this OfflineID"
            add(run.actions, entry)
            action_status = entry.error
        else
            do_restore(target.offline, target.chara, "button")
        end
    elseif job.kind == "compare" then
        do_compare(target.offline, target.chara, job.label)
    else
        log_error("run_job", "unknown job " .. tostring(job.kind))
    end
end

local function process_jobs()
    if #job_queue == 0 then return end
    local q = job_queue
    job_queue = {}
    for _, job in ipairs(q) do
        local ok, err = pcall(run_job, job)
        if not ok then
            log_error("job " .. tostring(job.kind), err)
            action_status = tostring(job.kind) .. " FAILED: " .. tostring(err)
        end
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Once-a-second refresh (update callback, never inside hooks)

local function refresh()
    local ok, err = pcall(function()
        local pm = singleton("app.PawnManager")
        if not pm then refresh_status = "PawnManager not available (load a save)"; party_rows = {}; return end
        local rows, ids = {}, {}
        local list = party_charas()
        local now = os.clock()
        for _, p in ipairs(list) do
            local chara = p.chara
            local id = chara_id_of(chara)
            local offline, uniq_obj, holder = owner_of(chara)
            local row = { slot = p.slot, id = id, offline = offline, name = chara_name(chara) }
            names[id] = row.name
            ids[id] = true
            if valid_offline(offline) then id_to_offline[id] = offline end
            local human = chara:call("get_Human")
            local st = human and human:call("get_StatusContext")
            if st then
                row.level = try(function() return st:call("get_Level") end)
                row.exp = try(function() return st:call("get_Exp") end)
            end
            rows[#rows + 1] = row
            local bk = valid_offline(offline) and backups[offline] or nil
            if bk then
                -- record writability: log only changes
                local rs = record_state(id, uniq_obj)
                local state = { by_charid = rs.by_charid, by_uniqid = rs.by_uniqid }
                if holder then
                    state.is_restore = try(function() return holder:call("get_IsRestore") end)
                    state.is_store = try(function() return holder:call("get_IsStore") end)
                end
                local key = table.concat({ tostring(state.by_charid), tostring(state.by_uniqid),
                    tostring(state.is_restore), tostring(state.is_store) }, "|")
                if last_record_key[offline] ~= key then
                    add(run.record_transitions, { t = now, wall = wall(), offline_id = offline, name = row.name,
                        character_id = id, state = state, previous = last_record_key[offline] or "first observation" })
                    last_record_key[offline] = key
                end
                if not first_seen[offline] then
                    first_seen[offline] = true
                    do_compare(offline, chara, "auto:first-seen")
                end
            end
        end
        party_rows = rows
        known_ids = {}
        for id in pairs(ids) do known_ids[id] = true end
        for _, b in pairs(backups) do
            if type(b.character_id) == "number" then known_ids[b.character_id] = true end
        end
        if #rows > 0 and not party_nonempty_since then party_nonempty_since = now end
        if party_nonempty_since and now - party_nonempty_since >= ABSENT_SECONDS then
            for _, offline in ipairs(backup_order) do
                if not first_seen[offline] and not absent_noted[offline] then
                    absent_noted[offline] = true
                    note("pawn-absent", { offline_id = offline, name = backups[offline].name,
                        seconds_party_nonempty = now - party_nonempty_since })
                end
            end
        end
        refresh_status = string.format("%d party pawns, %d backups", #rows, #backup_order)
    end)
    if not ok then
        refresh_status = "refresh failed: " .. tostring(err)
        log_error("refresh", err)
    end
end

local function flush()
    last_flush = os.clock()
    local ok, err = pcall(function()
        local out = {}
        for k, v in pairs(run) do out[k] = type(v) == "table" and nz(v) or v end
        out.hooks = { installed = nz(run.hooks.installed), missing = nz(run.hooks.missing) }
        out.summary = {
            calls_logged = #calls, calls_dropped = run.dropped, actions = #run.actions, compares = #run.compares,
            returns = #run.returns, record_transitions = #run.record_transitions, markers = #run.markers,
            item_counts = #run.item_counts, notes = #run.notes, errors = #run.errors, backups = #backup_order,
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

-- ---------------------------------------------------------------------------------------------------------
-- Wiring

install_hooks()
do
    local ok, err = pcall(load_backups)
    if not ok then backup_status = "backup load failed: " .. tostring(err); log_error("load_backups", err) end
end

re.on_pre_application_entry("UpdateBehavior", function()
    frame_no = frame_no + 1
    local now = os.clock()
    local ok, err = pcall(process_jobs)
    if not ok then log_error("process_jobs", err) end
    ok, err = pcall(process_timers)
    if not ok then log_error("process_timers", err) end
    if now - last_refresh >= REFRESH_SECONDS then
        last_refresh = now
        refresh()
    end
    ok, err = pcall(write_backups)
    if not ok then log_error("write_backups", err) end
    if flush_requested or (dirty and now - last_flush >= FLUSH_SECONDS) then
        flush_requested = false
        flush()
    end
end)

if re.on_script_reset then
    re.on_script_reset(function() pcall(write_backups); pcall(flush) end)
end

-- ---------------------------------------------------------------------------------------------------------
-- UI (draws and sets flags; never calls the game)

local function slot_row(slot)
    for _, row in ipairs(party_rows) do
        if row.slot == slot then return row end
    end
    return nil
end

local function slot_desc(slot)
    local row = slot_row(slot)
    if not row then return "empty slot" end
    local tag = row.id == MAIN_ID and "  [MAIN PAWN: refused]" or ""
    local has = (valid_offline(row.offline) and backups[row.offline]) and "  [has backup]" or ""
    return string.format("%d (%s)  Lv %s  Exp %s  off=%s%s%s", row.id, tostring(row.name), str(row.level), str(row.exp),
        tostring(row.offline or "?"):sub(1, 8), has, tag)
end

local function confirm_click(key, label, fn)
    local is_armed = armed and armed.key == key and os.clock() < armed.deadline
    if imgui.button((is_armed and "CONFIRM " or "") .. label .. "###" .. key) then
        if is_armed then
            armed = nil
            fn()
        else
            armed = { key = key, deadline = os.clock() + CONFIRM_SECONDS }
        end
    end
    if is_armed then
        imgui.same_line()
        imgui.text(string.format("click again within %.0f s", armed.deadline - os.clock()))
    end
end

local function draw_diff(title, view)
    if not view then
        imgui.text(title .. ": none yet")
        return
    end
    imgui.text(string.format("%s [%s] %s %s: %d of %d fields differ%s", title, tostring(view.stage or view.label),
        tostring(view.name), tostring(view.wall), view.n_diff, view.n, view.n_diff == 0 and "  (ALL EQUAL)" or ""))
    local shown = 0
    for _, r in ipairs(view.rows) do
        if not r.equal then
            shown = shown + 1
            if shown <= DIFF_LINES then
                imgui.text(string.format("  %-34s expected %s   actual %s", r.field, str(r.expected), str(r.actual)))
            end
        end
    end
    if shown > DIFF_LINES then imgui.text(string.format("  ... %d more", shown - DIFF_LINES)) end
end

local function fmt_entry(e)
    local parts = { string.format("#%d t=%.1f %s %s id=%s", e.seq or 0, e.t or 0, tostring(e.method), tostring(e.phase),
        tostring(e.id)) }
    if e.args and e.args.item_id then
        parts[#parts + 1] = string.format("item=%s x%s", tostring(e.args.item_id), tostring(e.args.count))
    end
    if e.auto_capture then parts[#parts + 1] = "capture: " .. tostring(e.auto_capture) end
    if e.offline_id_in_post then parts[#parts + 1] = "off_in_post=" .. tostring(e.offline_id_in_post):sub(1, 8) end
    return table.concat(parts, " ")
end

local function setting_changed(name, value)
    queue_job({ kind = "setting", name = name, value = value })
end

local function draw_settings()
    local ch, idx = imgui.combo("Restore mode", restore_mode + 1, RESTORE_MODES)
    if ch then restore_mode = idx - 1; setting_changed("restore_mode", restore_mode) end
    local ch2, idx2 = imgui.combo("IncreaseParams write", ip_mode + 1, IP_MODES)
    if ch2 then ip_mode = idx2 - 1; setting_changed("ip_mode", ip_mode) end
    local ch3, g = imgui.checkbox("Ignore level guard", ignore_guard)
    if ch3 then ignore_guard = g; setting_changed("ignore_guard", g) end
    imgui.same_line()
    local ch4, a = imgui.checkbox("Auto-capture on dismiss", auto_capture)
    if ch4 then auto_capture = a; setting_changed("auto_capture", a) end
    imgui.same_line()
    local ch5, l = imgui.checkbox("Log calls", log_calls)
    if ch5 then log_calls = l end
end

local function draw_buttons()
    imgui.text("Restore CHANGES the pawn and the save. Back up first. The main pawn and the player are refused.")
    local ch, v = imgui.slider_int("Party slot", ui.slot, 1, 4)
    if ch then ui.slot = v end
    imgui.text("Target: " .. slot_desc(ui.slot))
    local row = slot_row(ui.slot)

    if imgui.button("Capture backup of slot " .. ui.slot .. "###capture") then
        queue_job({ kind = "capture", slot = ui.slot })
    end
    if row then
        confirm_click(string.format("restore:%d:%s:%s", ui.slot, tostring(row.id), tostring(row.offline)),
            "Restore backup into slot " .. ui.slot, function()
                queue_job({ kind = "restore", slot = ui.slot, expect_id = row.id })
            end)
    else
        imgui.text("(restore: no pawn in this slot)")
    end

    local c, lbl = imgui.input_text("Compare label", ui.compare_label)
    if c then ui.compare_label = lbl end
    if imgui.button("Compare slot " .. ui.slot .. " with backup###compare") then
        queue_job({ kind = "compare", slot = ui.slot, label = ui.compare_label })
    end

    local cm, mk = imgui.input_text("Marker", ui.marker_label)
    if cm then ui.marker_label = mk end
    imgui.same_line()
    if imgui.button("Add marker###marker") then queue_job({ kind = "marker", label = ui.marker_label }) end
    imgui.same_line()
    if imgui.button("Flush now") then flush_requested = true end
    imgui.text(action_status)
end

local function draw_backups()
    imgui.text(backup_status)
    if #backup_order == 0 then
        imgui.text("No backups.")
        return
    end
    for _, offline in ipairs(backup_order) do
        local b = backups[offline]
        imgui.text(string.format("%s  off=%s  Lv %s  Exp %s  Disc %s  captured %s  (%s)", tostring(b.name), offline,
            str(b.level), str(b.exp), str(b.discipline), tostring(b.captured), tostring(b.source)))
        imgui.same_line()
        confirm_click("delete:" .. offline, "Delete", function() queue_job({ kind = "delete_backup", offline = offline }) end)
    end
    local ch, v = imgui.slider_int("Backup for item counts", math.min(ui.backup_pick, #backup_order), 1, #backup_order)
    if ch then ui.backup_pick = v end
    local pick = backup_order[math.min(ui.backup_pick, #backup_order)]
    if pick and imgui.button("Item counts for backup " .. math.min(ui.backup_pick, #backup_order) .. " ("
        .. tostring(backups[pick].name) .. ")###itemcounts") then
        queue_job({ kind = "item_counts", offline = pick })
    end
end

local function draw_body()
    imgui.text("Log-only hooks; Restore and the automatic modes write to the pawn. Back up first (tools/saves.sh backup).")
    imgui.text(hook_status)
    imgui.text(refresh_status)
    imgui.text("Run file: reframework/data/" .. RUN_FILE)
    imgui.text("Backups: reframework/data/" .. BACKUP_DIR)
    imgui.text(flush_status)
    local seen = 0
    for _, c in pairs(run.count_by_spec) do seen = seen + c.pre + c.post end
    imgui.text(string.format("Calls: %d logged, %d dropped, %d seen | %d actions, %d compares, %d returns, %d errors",
        #calls, run.dropped, seen, #run.actions, #run.compares, #run.returns, #run.errors))

    if imgui.tree_node("Settings") then
        local ok, err = pcall(draw_settings)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Actions") then
        local ok, err = pcall(draw_buttons)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Backups") then
        local ok, err = pcall(draw_backups)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    draw_diff("Last restore diff (backup vs live)", last_restore_view)
    draw_diff("Last compare", last_compare_view)
    for i = math.max(1, #calls - LOG_LINES + 1), #calls do imgui.text(fmt_entry(calls[i])) end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Restore (EXPERIMENT)") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
