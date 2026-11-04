-- Retinue Exp StatusUI: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- What it answers (M2, ticket 13 "Where does the player see the retinue's status in game?"): which native surfaces can
-- carry the retinue's status without the REFramework menu. It only SHOWS candidate surfaces with sample text so the
-- player can judge them in game; it never writes the roster, a backup, pawn data or a save.
--   P1  Transient notices (buttons): GuiManager.requestNoButtonDialog, requestDispPupUpMessage /
--       requestDispSystemPopupMessage (text substituted for a Guid we choose, via the message-lookup hooks),
--       reqLevelUp (the level-up notice, finding 0003), setTalkBalloonMessage / addTalkSubtitleMessage (a line over
--       the pawn's head).
--   P2  The root talk menu of a hired party pawn: a fifth row with status text, optionally disabled (greyed out?),
--       using TalkUI's verified fifth-entry + redirect-to-Never-mind mechanics (finding 0007).
--   P3  The Status page (ui060601_01): a suffix on the name of a hired pawn's tab.
--   P4  The Rift's "previously hired" list (ui041401): a prefix / suffix on the name of listed pawns.
--   P5  The game's own yes/no dialog (requestDialog, TalkUI's verified Q3 path) with the adopt text and the gear
--       warning, to see line wrapping and length.
-- Every "dump text children" button logs the via.gui.Text widgets of a page (path + message) so one run reveals
-- where a name lives if the likely field is wrong. See tools/experiments/README.md for the procedure.
--
-- Everything that changes what the player sees is OFF at load (nothing is persisted between sessions). The buttons CALL
-- game methods that only draw UI. BACK UP FIRST (tools/saves.sh backup <label>), once per run: the talk-menu row can
-- end a conversation oddly, and calling a GuiManager method with made-up arguments has never been tried in game.
-- None of the hooked methods is hooked by the mod, so this script can be linked TOGETHER with the mod
-- (deploy.sh --statusui). The text-lookup hooks (via.gui.message.get ...) sit on a path every piece of text goes
-- through, so they are installed only the first time "Substitute text" is ticked (REFramework cannot remove hooks).
--
-- Output: reframework/data/Retinue/experiments/statusui_<timestamp>.json (one file per session, flushed every 2 s
-- when changed). Every hook body is wrapped in pcall: a bug here must never break a game call. Conventions follow
-- Retinue_Exp_TalkUI.lua; API names were checked against this game version's il2cpp_dump.json. NOT RUN IN GAME YET.
--
-- Hook argument indexes: instance methods have args[2] = this and the first parameter at args[3]; static methods have
-- the first parameter at args[2].

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn: never a target
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "statusui_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 3000 -- shared cap of the `calls` list
local DEFAULT_SPEC_CAP = 200 -- per-hook cap of logged entries (pre phase)
local CHATTY_SPEC_CAP = 8
local EVENT_CAP = 800
local ERROR_CAP = 200
local MARKER_CAP = 200
local DUMP_CAP = 8 -- text-tree dumps kept in the run file
local DUMP_TEXT_CAP = 400 -- via.gui.Text entries per dump
local DUMP_OBJECT_CAP = 1500 -- objects visited per dump
local RIFT_ENTRY_CAP = 60
local STACK_MAX = 32
local LOG_LINES = 8
local DIALOG_POLL_SECONDS = 60
local FALLBACK_NAME, FALLBACK_LEVEL = "Folken", 27

-- Verified in the first TalkUI runs (finding 0007).
local ROOT_NODE_ID = "4c4acb4e-1531-45ea-9f6a-e4152e473e2e" -- ShopChoiceNode: the party-pawn root menu
local NEVERMIND_GUID = "cde9623d-2e45-424a-b326-daa8c3b7078c" -- ChoiceId / message Guid of "Never mind."
local DISMISS_GUID_PREFIX = "7d3962d3" -- ChoiceId of Dismiss (only the first 8 digits are recorded)
-- A Guid this script owns: nothing in the game uses it, so a substitution for it can never touch another text.
local OWN_GUID = "5ec0ffee-0000-4000-8000-00000000a001"

-- requestDialog(String overload) positional kinds; GUESS = TalkUI's neutral values for parameters 6..21 (verified to
-- open a Yes/No dialog in game, finding 0007 Q3).
local DIALOG_KINDS = { "str", "str", "str", "str", "str", "bool", "i32", "bool", "u32", "i32", "i32", "tex",
    "bool", "bool", "bool", "bool", "bool", "f32", "bool", "bool", "bool" }
local DIALOG_GUESS = {
    [6] = false, [7] = 0, [8] = false, [9] = 0, [10] = 0, [11] = 0, [12] = nil,
    [13] = false, [14] = false, [15] = false, [16] = false, [17] = false, [18] = 0.0,
    [19] = false, [20] = false, [21] = false,
}

-- Session state (never persisted). Every mutating toggle is false at load.
local toggles = { subst = false, p2_row = false, p2_disabled = false, p3 = false, p4 = false, autohide = true }
-- Sample texts. {name} and {lv} are replaced by the selected hired pawn (or "Folken" / 27); a literal \n is a newline.
local txt = {
    notice = "{name} returned — Lv {lv} restored",
    popup = "{name} returned — Lv {lv} restored",
    speech = "Back, Arisen. Level {lv}, all restored.",
    p2_row = "Release (Retinue · Lv {lv})",
    p2_disabled = "Adopt — retinue locked",
    p3_suffix = " · Retinue",
    p4_prefix = "★ ",
    p4_suffix = " — Retinue, Lv {lv}",
    p4_filter = "", -- an OfflineID; empty = mark every listed pawn
    p5_main = "Adopt {name} into your retinue?\\nGear you give them is lost if they're dismissed or lost.",
    p5_yes = "Yes",
    p5_no = "No",
}
local num = { nb_arg = "0", nb_hide_s = "10", popup_arg = "0", lv_old = "26", lv_new = "27", balloon_s = "4.0" }
local flags = { balloon_a = false, balloon_b = false, subtitle_b = false }
local subst = { guid = OWN_GUID, guid_input = OWN_GUID, q = nil, text = "", hits = {} } -- text = what the hooks return for guid
local sel_id = nil -- CharacterID of the sample pawn
local markers, marker_text = {}, ""
local notice = nil -- { text, t }
local party_cache = {} -- { {id, slot, name, level, offline} }: refreshed once a second, read by the panel
local hook_status, flush_status = "hooks not installed yet", ""
local probe_missing = {} -- probe name -> why it is disabled
local flush_requested = false
local names = {}
local enum_cache = {}
local work_queue = {}
local in_self_call = false
local text_hooks = { installed = false, status = "not installed (tick Substitute text)" }
local pinned = {} -- text -> pinned managed string
local hook_fallback_store = {}
local autohide_at = nil -- os.clock() at which B1's dialog is hidden again

-- P2
local nci_recent = {} -- newChoiceInfo results since the last startNode, in call order: { guid, addr, msg }
local menu_gen = 0
local row_state = nil -- { gen, pos, nm, disabled, last_sel, cursor_events }
local p2_last = nil -- panel line about the last party-pawn menu seen
-- P3 / P4
local armed = { status = false, rift = false, rift_item = false }
local status_last, rift_page = nil, nil -- plain tables for the panel
local rift_entries = {} -- offline -> { name, level, ... } (cap RIFT_ENTRY_CAP)
local rift_entry_count = 0
local last_addr = { status = nil, status_t = nil, rift = nil, rift_t = nil }
-- P5
local dialog_poll, dialog_live = nil, nil

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    constants = {
        script = "Retinue_Exp_StatusUI",
        main_id = MAIN_ID,
        root_node_id = ROOT_NODE_ID,
        nevermind_guid = NEVERMIND_GUID,
        own_guid = OWN_GUID,
        dialog_guess = DIALOG_GUESS,
        call_cap = CALL_CAP,
        default_spec_cap = DEFAULT_SPEC_CAP,
        event_cap = EVENT_CAP,
    },
    markers = {},
    events = {},
    calls = {},
    errors = {},
    text_dumps = {},
    hooks = { installed = {}, missing = {} },
    dropped = 0,
    dropped_by_spec = {},
    dropped_events = 0,
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

local function singleton(name) return sdk.get_managed_singleton(name) end

-- Hook argument decoding (args[n] are raw pointer-sized values).
local function arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end
local function arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
local function arg_bool(a) return (sdk.to_int64(a) & 1) == 1 end
local function arg_nonnull(a) return sdk.to_int64(a) ~= 0 end

local function to_managed(a)
    if a == nil then return nil end
    if sdk.to_int64(a) == 0 then return nil end
    return sdk.to_managed_object(a)
end

local function arg_string(a)
    local o = to_managed(a)
    if o == nil then return "nil" end
    return str(o)
end

-- Single parameters travel in XMM registers on x64: this read may be garbage for them (logged as such).
local function arg_f32(a)
    if sdk.to_float then
        local ok, f = pcall(sdk.to_float, a)
        if ok and type(f) == "number" then return f end
    end
    local bits = sdk.to_int64(a) & 0xFFFFFFFF
    local ok, f = pcall(function() return (string.unpack("<f", string.pack("<I4", bits))) end)
    if ok then return f end
    return "bits=" .. tostring(bits)
end

-- ---------------------------------------------------------------------------------------------------------
-- Guids

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

local function is_guid(s) return type(s) == "string" and s:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil end
local function is_zero_guid(s) return s == nil or (type(s) == "string" and s:match("^[0%-]+$") ~= nil) end

-- "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -> { lo, hi } (the raw qword pair of a .NET Guid), or nil.
local function parse_guid(s)
    if type(s) ~= "string" then return nil end
    local a, b, c, d, e = s:lower():match("^(%x%x%x%x%x%x%x%x)%-(%x%x%x%x)%-(%x%x%x%x)%-(%x%x%x%x)%-(%x%x%x%x%x%x%x%x%x%x%x%x)$")
    if not a then return nil end
    local lo = tonumber(a, 16) | (tonumber(b, 16) << 32) | (tonumber(c, 16) << 48)
    local tail = d .. e
    local hi = 0
    for i = 0, 7 do hi = hi | (tonumber(tail:sub(i * 2 + 1, i * 2 + 2), 16) << (8 * i)) end
    return { lo = lo, hi = hi }
end

local guid_base_offset = nil
-- A usable System.Guid value from a qword pair (Guild Contracts' technique): create_instance + write at the first
-- field's offset + re-view through to_valuetype. nil when any step is missing.
local function make_guid_valuetype(q)
    if not q then return nil end
    local ok, vt = pcall(function()
        local td = sdk.find_type_definition("System.Guid")
        if not td then return nil end
        if not guid_base_offset then
            local f = td:get_field("mData1")
            guid_base_offset = f and f:get_offset_from_base()
        end
        if not guid_base_offset then return nil end
        local o = td:create_instance()
        if not o then return nil end
        o:add_ref()
        o:write_qword(guid_base_offset, q.lo)
        o:write_qword(guid_base_offset + 8, q.hi)
        return sdk.to_valuetype(o:get_address() + guid_base_offset, "System.Guid")
    end)
    if ok then return vt end
    return nil
end

-- Reads a Guid passed by value (hidden pointer) in a hook.
local function arg_guid(a)
    if sdk.to_valuetype then
        local ok, v = pcall(sdk.to_valuetype, a, "System.Guid")
        if ok and v ~= nil then return guid_str(v) end
    end
    return "unreadable"
end

local function arg_qwords(a)
    local ok, lo, hi = pcall(function()
        local v = sdk.to_valuetype(a, "System.Guid")
        return v:read_qword(0), v:read_qword(8)
    end)
    if ok and lo ~= nil then return { lo = lo, hi = hi } end
    return nil
end

local function set_subst_guid(s)
    local q = parse_guid(s)
    if not q then return false end
    subst.guid, subst.guid_input, subst.q = s:lower(), s:lower(), q
    return true
end
set_subst_guid(OWN_GUID)

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

local function enum_value(type_name, member)
    local ok, v = pcall(function()
        local td = sdk.find_type_definition(type_name)
        for _, f in ipairs(td:get_fields()) do
            if f:is_static() and f:get_name() == member then return f:get_data(nil) end
        end
        return nil
    end)
    if ok then return v end
    return nil
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

-- (method, nil) or (nil, why)
local function lookup(type_name, sig)
    local ok, td = pcall(sdk.find_type_definition, type_name)
    if not ok or not td then return nil, "type not found: " .. type_name end
    local ok2, m = pcall(find_method, td, sig)
    if ok2 and m then return m end
    return nil, "method not found: " .. type_name .. "." .. sig
end

local GM = "app.GuiManager"
local M = {} -- registered methods; a missing one disables its probe
local function reg(name, type_name, sig)
    local m, why = lookup(type_name, sig)
    M[name] = m
    if not m then probe_missing[name] = why end
end

reg("nb_str", GM, "requestNoButtonDialog(System.String, System.UInt32)")
reg("hide_dialog", GM, "requestHideDialog()")
reg("popup", GM, "requestDispPupUpMessage(System.Guid, System.UInt32)")
reg("syspopup", GM, "requestDispSystemPopupMessage(System.Guid, System.Guid[])")
reg("hide_popup", GM, "requestHidePopUpMessage()")
reg("hide_syspopup", GM, "requestHideSystemPopupMessage()")
reg("level_up", GM, "reqLevelUp(app.CharacterID, System.Int32, System.Int32)")
reg("balloon", GM, "setTalkBalloonMessage(via.GameObject, System.Guid, via.gui.GenderType, via.gui.GenderType, "
    .. "System.Boolean, System.Single, System.UInt32, app.WwiseVoiceController, app.WwiseContainerApp, "
    .. "System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, "
    .. "System.Boolean)")
reg("subtitle", GM, "addTalkSubtitleMessage(via.GameObject, System.Guid, via.gui.GenderType, via.gui.GenderType, "
    .. "System.UInt32, app.WwiseVoiceController, app.WwiseContainerApp, "
    .. "System.Action`1<soundlib.SoundManager.RequestInfo>, System.Action`1<soundlib.SoundManager.RequestInfo>, "
    .. "System.Boolean)")
reg("request_dialog", GM, "requestDialog(System.String, System.String, System.String, System.String, System.String, "
    .. "System.Boolean, System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, "
    .. "via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, System.Boolean, "
    .. "System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)")
reg("msg_get", "via.gui.message", "get(System.Guid)")
reg("msg_exist", "via.gui.message", "isExistGuid(System.Guid)")
reg("new_guid", "System.Guid", "NewGuid()")

local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_name_id = td_guibase and td_guibase:get_method("getName(app.CharacterID)")
local m_name_chara = td_guibase and td_guibase:get_method("getName(app.Character)")
local m_name_cdata = td_guibase and find_method(td_guibase, "getName(app.GUIBase.CharaData)")

-- ---------------------------------------------------------------------------------------------------------
-- Logging

local function next_seq() seq = seq + 1; return seq end

local function add_event(kind, fields)
    if #run.events >= EVENT_CAP then
        run.dropped_events = run.dropped_events + 1
        return nil
    end
    local e = { seq = next_seq(), t = os.clock(), wall = wall(), kind = kind }
    for k, v in pairs(fields or {}) do e[k] = v end
    e = sanitize(e)
    run.events[#run.events + 1] = e
    dirty = true
    return e
end

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

local function queue_work(fn) work_queue[#work_queue + 1] = fn end

for name, why in pairs(probe_missing) do log_error("probe disabled: " .. name, why) end

-- ---------------------------------------------------------------------------------------------------------
-- Pawns and names

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

-- Party pawns (main pawn included, flagged): { id, slot, name, level, offline, chara }. chara is a live object:
-- only the update thread uses it, the panel gets copies without it.
local function party_entries(with_chara)
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
                local e = { id = id, slot = i + 1, name = names[id], level = level_of(chara),
                    offline = offline_of(chara), main = id == MAIN_ID }
                if with_chara then e.chara = chara end
                out[#out + 1] = e
            end
        end
    end
    return out
end

local function hired_entries()
    local out = {}
    for _, e in ipairs(party_cache) do
        if not e.main and e.id ~= 0 then out[#out + 1] = e end
    end
    return out
end

-- Cached entry for a CharacterID, or nil.
local function pawn_entry(id)
    for _, e in ipairs(party_cache) do
        if e.id == id then return e end
    end
    return nil
end

-- The sample pawn: the selected hired pawn, else the first one, else nil.
local function sample_pawn()
    local hired = hired_entries()
    for _, e in ipairs(hired) do
        if e.id == sel_id then return e end
    end
    return hired[1]
end

local function is_hired_party_pawn(id)
    if type(id) ~= "number" or id == MAIN_ID or id == 0 then return false end
    return pawn_entry(id) ~= nil
end

local function find_party_chara(id)
    for _, e in ipairs(party_entries(true)) do
        if e.id == id then return e.chara end
    end
    return nil
end

local function name_of(id)
    if type(id) ~= "number" then return nil end
    if names[id] then return names[id] end
    local nm = m_name_id and try(function() return m_name_id:call(nil, id) end)
    if type(nm) == "userdata" then nm = str(nm) end
    if type(nm) == "string" and not is_err(nm) and nm ~= "" then
        names[id] = nm
        return nm
    end
    return nil
end

-- Replaces {name} / {lv} (the sample pawn, or the given overrides) and turns a literal \n into a newline.
local function resolve(tpl, name, lv)
    local p = sample_pawn()
    name = name or (p and p.name) or FALLBACK_NAME
    lv = lv or (p and p.level) or FALLBACK_LEVEL
    local s = tostring(tpl)
    s = s:gsub("{name}", function() return tostring(name) end)
    s = s:gsub("{lv}", function() return tostring(lv) end)
    s = s:gsub("\\n", "\n")
    return s
end

local function to_int_or(s, d)
    local n = tonumber(s)
    if n == nil then return d end
    return math.tointeger(n) or d
end

-- ---------------------------------------------------------------------------------------------------------
-- Message-text substitution (B2 / B4): hooks on the lookups that turn a message Guid into a string. Installed lazily.

local function hook_store()
    if thread and thread.get_hook_storage then
        local ok, st = pcall(thread.get_hook_storage)
        if ok and st then return st end
    end
    return hook_fallback_store
end

local function pinned_string(text)
    local s = pinned[text]
    if s then return s end
    local n = 0
    for _ in pairs(pinned) do n = n + 1 end
    if n >= 64 then pinned = {} end
    s = sdk.create_managed_string(text)
    local ok = pcall(function() s:add_ref_permanent() end)
    if not ok then pcall(function() s:add_ref() end) end
    pinned[text] = s
    return s
end

local function install_text_hook(key, type_name, sig, guid_of)
    local m, why = lookup(type_name, sig)
    if not m then
        text_hooks.missing = text_hooks.missing or {}
        text_hooks.missing[#text_hooks.missing + 1] = key
        log_error("text hook " .. key, why)
        return false
    end
    local ok, err = pcall(function()
        sdk.hook(m,
            function(args)
                if not toggles.subst or not subst.q or subst.text == "" then return sdk.PreHookResult.CALL_ORIGINAL end
                local ok_pre, hit = pcall(function()
                    local q = guid_of(args)
                    return q ~= nil and q.lo == subst.q.lo and q.hi == subst.q.hi
                end)
                if ok_pre and hit then hook_store().sui_hit = key end
                return sdk.PreHookResult.CALL_ORIGINAL
            end,
            function(retval)
                local st = hook_store()
                if st.sui_hit ~= key then return retval end
                st.sui_hit = nil
                local ok_post, ptr = pcall(function() return sdk.to_ptr(pinned_string(subst.text)) end)
                subst.hits[key] = (subst.hits[key] or 0) + 1
                if subst.hits[key] <= 5 then
                    queue_work(function() add_event("subst_hit", { hook = key, text = clip(subst.text, 120), ok = ok_post }) end)
                end
                if ok_post and ptr then return ptr end
                return retval
            end)
    end)
    if not ok then
        text_hooks.missing = text_hooks.missing or {}
        text_hooks.missing[#text_hooks.missing + 1] = key
        log_error("text hook " .. key, err)
        return false
    end
    text_hooks.installed_keys = text_hooks.installed_keys or {}
    text_hooks.installed_keys[#text_hooks.installed_keys + 1] = key
    return true
end

local function install_text_hooks()
    if text_hooks.installed then return end
    text_hooks.installed = true
    -- GUESS: which of these the popup / balloon text goes through is unknown (Guild Contracts found message.get
    -- silent after a game update, then working again); all are installed and the hit counters tell which one fires.
    install_text_hook("message.get(Guid)", "via.gui.message", "get(System.Guid)", function(a) return arg_qwords(a[2]) end)
    install_text_hook("message.get(Guid,Language)", "via.gui.message", "get(System.Guid, via.Language)",
        function(a) return arg_qwords(a[2]) end)
    install_text_hook("GUIBase.getMsg(Guid)", "app.GUIBase", "getMsg(System.Guid)", function(a) return arg_qwords(a[3]) end)
    local mad_td = sdk.find_type_definition("via.gui.MessageAccessData")
    local function mad_guid(a)
        local mad = mad_td and sdk.to_valuetype(a[2], mad_td)
        local g = mad and mad:call("get_Guid")
        if not g then return nil end
        return { lo = g:read_qword(0), hi = g:read_qword(8) }
    end
    install_text_hook("MessageAccessData.get_Message()", "via.gui.MessageAccessData", "get_Message()", mad_guid)
    install_text_hook("MessageAccessData.getMessage(Language)", "via.gui.MessageAccessData", "getMessage(via.Language)", mad_guid)
    text_hooks.status = string.format("installed %d, missing %d", #(text_hooks.installed_keys or {}), #(text_hooks.missing or {}))
    add_event("text_hooks_installed", { installed = text_hooks.installed_keys, missing = text_hooks.missing })
end

-- ---------------------------------------------------------------------------------------------------------
-- P1 actions (run in the update callback)

-- Calls fn, logs one `call` event with the probe name, the shown arguments, the result or the exception.
local function run_call(probe, shown, fn)
    local e = { probe = probe, args = shown }
    in_self_call = true
    local ok, res = pcall(fn)
    in_self_call = false
    e.ok = ok
    if ok then
        if res == nil then e.result = "void/nil"
        elseif type(res) == "userdata" then e.result = str(res)
        else e.result = res end
    else
        e.error = tostring(res)
    end
    add_event("call", e)
    return ok, res
end

local function unavailable(name)
    add_event("probe_unavailable", { probe = name, why = probe_missing[name] or "method not registered" })
end

local function gm_or_log(probe)
    local gm = singleton("app.GuiManager")
    if not gm then add_event("call", { probe = probe, ok = false, error = "GuiManager not available" }) end
    return gm
end

local function dialog_displayed()
    local gm = singleton("app.GuiManager")
    return gm and try(function() return gm:call("IsDispDialogGui") end)
end

local function do_nobutton(use_arg)
    if not M.nb_str then return unavailable("nb_str") end
    local gm = gm_or_log("requestNoButtonDialog")
    if not gm then return end
    local text = resolve(txt.notice)
    local arg = use_arg and to_int_or(num.nb_arg, 0) or 0
    run_call("requestNoButtonDialog(String,UInt32)", { text = text, u32 = arg, displayed_before = dialog_displayed() },
        function() return M.nb_str:call(gm, sdk.create_managed_string(text), arg) end)
    local secs = tonumber(num.nb_hide_s) or 0
    if toggles.autohide and secs > 0 then autohide_at = os.clock() + secs else autohide_at = nil end
end

local function do_hide_dialog(reason)
    if not M.hide_dialog then return unavailable("hide_dialog") end
    local gm = gm_or_log("requestHideDialog")
    if not gm then return end
    run_call("requestHideDialog()", { reason = reason, displayed_before = dialog_displayed() },
        function() return M.hide_dialog:call(gm) end)
    autohide_at = nil
end

local function guid_args()
    local vt = make_guid_valuetype(subst.q)
    -- fallback: the value NewGuid() returned, kept for the "New random Guid" button (still the active Guid)
    if not vt and subst.vt and subst.vt_guid == subst.guid then vt = subst.vt end
    if not vt then return nil, "could not build a System.Guid value (create_instance / mData1 offset)" end
    return vt
end

-- The text the substitution hooks return for the chosen Guid; set just before each popup / balloon call.
local function set_subst_text(template)
    subst.text = resolve(template)
    return subst.text
end

local function do_popup()
    if not M.popup then return unavailable("popup") end
    local gm = gm_or_log("requestDispPupUpMessage")
    if not gm then return end
    local vt, why = guid_args()
    if not vt then add_event("call", { probe = "popup", ok = false, error = why }); return end
    local text = set_subst_text(txt.popup)
    local arg = to_int_or(num.popup_arg, 0)
    run_call("requestDispPupUpMessage(Guid,UInt32)", { guid = subst.guid, text = text, substituting = toggles.subst, u32 = arg },
        function() return M.popup:call(gm, vt, arg) end)
end

local function do_syspopup(with_array)
    if not M.syspopup then return unavailable("syspopup") end
    local gm = gm_or_log("syspopup")
    if not gm then return end
    local vt, why = guid_args()
    if not vt then add_event("call", { probe = "syspopup", ok = false, error = why }); return end
    local text = set_subst_text(txt.popup)
    local shown = { guid = subst.guid, text = text, substituting = toggles.subst, params = with_array and "empty Guid[]" or "nil" }
    run_call("requestDispSystemPopupMessage(Guid,Guid[])", shown, function()
        local arr = nil
        if with_array then
            local ok_a, a = pcall(sdk.create_managed_array, "System.Guid", 0)
            if not ok_a or a == nil then ok_a, a = pcall(sdk.create_managed_array, sdk.find_type_definition("System.Guid"), 0) end
            if not ok_a or a == nil then error("sdk.create_managed_array failed: " .. tostring(a)) end
            arr = a
        end
        return M.syspopup:call(gm, vt, arr)
    end)
end

local function do_hide(name, label)
    if not M[name] then return unavailable(name) end
    local gm = gm_or_log(label)
    if not gm then return end
    run_call(label, {}, function() return M[name]:call(gm) end)
end

-- Isolates "does the Guid resolve" from "does the popup draw": isExistGuid + message.get for the chosen Guid.
local function do_probe_guid()
    if not (M.msg_exist or M.msg_get) then return unavailable("msg_get") end
    local vt, why = guid_args()
    if not vt then add_event("call", { probe = "probe_guid", ok = false, error = why }); return end
    local shown = { guid = subst.guid, substituting = toggles.subst, substitute_text = subst.text }
    if M.msg_exist then
        run_call("message.isExistGuid(Guid)", shown, function() return M.msg_exist:call(nil, vt) end)
    end
    if M.msg_get then
        run_call("message.get(Guid)", shown, function() return M.msg_get:call(nil, vt) end)
    end
end

local function do_level_up()
    if not M.level_up then return unavailable("level_up") end
    local p = sample_pawn()
    if not p or p.id == MAIN_ID then
        add_event("call", { probe = "reqLevelUp", ok = false, error = "no hired party pawn selected (the main pawn is never a target)" })
        return
    end
    local gm = gm_or_log("reqLevelUp")
    if not gm then return end
    -- order verified in findings 0002 / 0003: reqLevelUp(id, oldLv, newLv); dispLevelUpUI is the reverse
    local old, new = to_int_or(num.lv_old, p.level or 26), to_int_or(num.lv_new, (p.level or 27))
    run_call("reqLevelUp(CharacterID,old,new)", { pawn_id = p.id, pawn = p.name, old = old, new = new },
        function() return M.level_up:call(gm, p.id, old, new) end)
end

local function pawn_game_object(p)
    local chara = find_party_chara(p.id)
    if not chara then return nil, "pawn not found in the party" end
    local go = chara:call("get_GameObject")
    if not go then return nil, "no GameObject" end
    return go
end

local function do_balloon(kind)
    local name = kind == "balloon" and "balloon" or "subtitle"
    if not M[name] then return unavailable(name) end
    local p = sample_pawn()
    if not p or p.id == MAIN_ID then
        add_event("call", { probe = name, ok = false, error = "no hired party pawn selected (the main pawn is never a target)" })
        return
    end
    local gm = gm_or_log(name)
    if not gm then return end
    local vt, why = guid_args()
    if not vt then add_event("call", { probe = name, ok = false, error = why }); return end
    local go, why_go = pawn_game_object(p)
    if not go then add_event("call", { probe = name, ok = false, error = why_go }); return end
    local text = set_subst_text(txt.speech)
    local unk = enum_value("via.gui.GenderType", "Unknown") or 0
    local secs = tonumber(num.balloon_s) or 4.0
    local shown = { pawn_id = p.id, pawn = p.name, guid = subst.guid, text = text, substituting = toggles.subst,
        gender_unknown = unk }
    if kind == "balloon" then
        shown.duration, shown.bool_a, shown.bool_b = secs, flags.balloon_a, flags.balloon_b
        run_call("setTalkBalloonMessage", shown, function()
            return M.balloon:call(gm, go, vt, unk, unk, flags.balloon_a, secs + 0.0, 0, nil, nil, nil, nil, flags.balloon_b)
        end)
    else
        shown.bool_b = flags.subtitle_b
        run_call("addTalkSubtitleMessage", shown, function()
            return M.subtitle:call(gm, go, vt, unk, unk, 0, nil, nil, nil, nil, flags.subtitle_b)
        end)
    end
end

-- ---------------------------------------------------------------------------------------------------------
-- Text-tree dump (the fallback for P3 / P4): every via.gui.Text under an object, by path

local function type_name_of(o)
    return try(function() return o:get_type_definition():get_full_name() end)
end

local function dump_text_tree(label, root, root_name)
    local d = { label = label, wall = wall(), texts = {}, objects = 0, truncated = false }
    local seen = {}
    local function addr_of(o) return try(function() return o:get_address() end) end
    local function add_text(path, t)
        if #d.texts >= DUMP_TEXT_CAP then d.truncated = true; return end
        local vis = try(function() return t:call("get_ActualVisible") end)
        d.texts[#d.texts + 1] = { path = path, name = try(function() return t:call("get_Name") end),
            message = clip(try(function() return t:call("get_Message") end), 160), visible = vis }
    end
    local function walk(node, path, depth)
        if d.objects >= DUMP_OBJECT_CAP then d.truncated = true; return end
        d.objects = d.objects + 1
        local nm = try(function() return node:call("get_Name") end)
        local here = path .. "/" .. tostring(nm)
        if type_name_of(node) == "via.gui.Text" then add_text(here, node) end
        if depth >= 12 then return end
        local child = try(function() return node:call("get_Child") end)
        local guard = 0
        while type(child) == "userdata" and guard < 200 do
            walk(child, here, depth + 1)
            child = try(function() return child:call("get_Next") end)
            guard = guard + 1
        end
    end
    local scan
    local function visit(v, path, depth)
        if type(v) ~= "userdata" then return end
        local tn = type_name_of(v)
        if type(tn) ~= "string" then return end
        local a = addr_of(v)
        if a ~= nil and not is_err(a) then
            if seen[a] then return end
            seen[a] = true
        end
        if tn == "via.gui.Text" then add_text(path, v)
        elseif tn:sub(1, 8) == "via.gui." and tn ~= "via.gui.Text" then
            if tn == "via.gui.Panel" or tn:find("Control", 1, true) then walk(v, path, 0) end
        elseif tn:sub(-2) == "[]" then
            for i, el in ipairs(elements(v, 8)) do visit(el, path .. "[" .. (i - 1) .. "]", depth) end
        elseif tn:sub(1, 4) == "app." and depth < 2 and d.objects < DUMP_OBJECT_CAP then
            scan(v, path, depth + 1)
        end
    end
    scan = function(obj, path, depth)
        d.objects = d.objects + 1
        local td = try(function() return obj:get_type_definition() end)
        local hops = 0
        while type(td) == "userdata" and hops < 6 do
            local fs = try(function() return td:get_fields() end)
            if type(fs) == "table" then
                for _, f in ipairs(fs) do
                    local fname = f:get_name()
                    if not f:is_static() and fname ~= "Parent" then
                        local v = try(function() return obj:get_field(fname) end)
                        visit(v, path .. "." .. fname, depth)
                    end
                end
            end
            td = try(function() return td:get_parent_type() end)
            hops = hops + 1
        end
    end
    local ok, err = pcall(function()
        if type(root) == "userdata" then
            local tn = type_name_of(root)
            if type(tn) == "string" and tn:sub(1, 8) == "via.gui." then visit(root, root_name or "root", 0)
            else scan(root, root_name or "root", 0) end
        end
    end)
    if not ok then d.error = tostring(err) end
    d.count = #d.texts
    if #run.text_dumps < DUMP_CAP then
        run.text_dumps[#run.text_dumps + 1] = sanitize(d)
        dirty = true
    end
    add_event("text_dump", { label = label, texts = d.count, objects = d.objects, truncated = d.truncated, error = d.error,
        sample = d.texts[1] and d.texts[1].path or nil })
    return d
end

-- Dump from a stored address (button path): refuses when the page was not seen recently, to avoid a dead pointer.
local function dump_from_addr(which, label)
    local addr, t = last_addr[which], last_addr[which .. "_t"]
    if not addr or not t or os.clock() - t > 300 then
        add_event("text_dump", { label = label, skipped = "page not seen in the last 300 s (open it, change tab / refresh the list)" })
        return
    end
    local obj = try(function() return sdk.to_managed_object(addr) end)
    if type(obj) ~= "userdata" then
        add_event("text_dump", { label = label, skipped = "could not wrap the page object" })
        return
    end
    dump_text_tree(label, obj, which)
end

-- ---------------------------------------------------------------------------------------------------------
-- Name marking (P3 / P4): idempotent prefix / suffix on a via.gui.Text

local function read_message(t)
    local m = try(function() return t:call("get_Message") end)
    if type(m) ~= "string" then m = str(m) end
    return m
end

-- True when the text was changed. Never stacks a second prefix / suffix.
local function mark_text(t, prefix, suffix)
    if type(t) ~= "userdata" then return false, "no widget" end
    local msg = read_message(t)
    if is_err(msg) or msg == "" or msg == "nil" then return false, msg end
    local out = msg
    if prefix ~= "" and out:sub(1, #prefix) ~= prefix then out = prefix .. out end
    if suffix ~= "" and out:sub(-#suffix) ~= suffix then out = out .. suffix end
    if out == msg then return false, msg end
    local ok, err = pcall(function() t:call("set_Message", out) end)
    if not ok then return false, "set_Message failed: " .. tostring(err) end
    return true, out
end

-- ---------------------------------------------------------------------------------------------------------
-- P2: talk-menu row

-- (brief table, current node object) of TalkEventManager.CurrentTalkInfo, or nil.
local function talk_info()
    local tm = singleton("app.TalkEventManager")
    local info = tm and tm:get_field("<CurrentTalkInfo>k__BackingField")
    if not info then return nil end
    local b = {}
    b.speaker = to_u32(field(info, "<Speaker>k__BackingField"))
    b.listener = to_u32(field(info, "<Listener>k__BackingField"))
    local node = try(function() return info:get_field("<CurrentNode>k__BackingField") end)
    if type(node) ~= "userdata" then node = nil end
    return b, node
end

local function talk_select()
    local gm = singleton("app.GuiManager")
    local w = gm and try(function() return gm:get_field("TalkSelect") end)
    if type(w) == "userdata" then return w end
    return nil
end

local function set_msg(item, text)
    local ok = pcall(function() item:set_field("Msg", sdk.create_managed_string(text)) end)
    if not ok then ok = pcall(function() item.Msg = text end) end
    return ok
end

-- What the list that reqDisp received is: the root menu of a hired party pawn (ShopChoiceNode _NodeId, or a Dismiss
-- entry), which hired pawn, and which display row is "Never mind". Entries are matched to the Guids newChoiceInfo
-- returned by object address, else by call order.
local function menu_context(list)
    local ctx = { entries = {} }
    local ti, node = talk_info()
    ctx.node_id = node and field(node, "_NodeId") or nil
    if ti then
        for _, id in ipairs({ ti.listener, ti.speaker }) do
            if is_hired_party_pawn(id) then ctx.pawn_id = id; break end
        end
    end
    local n = try(function() return list:call("get_Count") end)
    if type(n) ~= "number" then return ctx end
    ctx.count = n
    for i = 0, n - 1 do
        local e = { index = i }
        local item = try(function() return list:call("get_Item", i) end)
        if type(item) == "userdata" then
            e.msg = field(item, "Msg")
            e.decide = field(item, "_IsDecideEnable")
            local addr = try(function() return item:get_address() end)
            for _, r in ipairs(nci_recent) do
                if r.addr ~= nil and r.addr == addr then e.guid = r.guid; break end
            end
            if not e.guid then
                local r = nci_recent[#nci_recent - (n - 1 - i)]
                if r and (r.msg == nil or r.msg == e.msg) then e.guid = r.guid end
            end
        end
        if e.guid == NEVERMIND_GUID then ctx.nm_index = i end
        if type(e.guid) == "string" and e.guid:sub(1, 8) == DISMISS_GUID_PREFIX then ctx.has_dismiss = true end
        ctx.entries[#ctx.entries + 1] = e
    end
    ctx.root = ctx.node_id == ROOT_NODE_ID or ctx.has_dismiss == true
    return ctx
end

local function p2_append_row(list, ctx, f)
    local tmpl = list:call("get_Item", 0) -- the shop-choice entries carry no Listener: copy the first entry
    if tmpl == nil then error("empty list") end
    local disabled = toggles.p2_disabled
    local pawn = pawn_entry(ctx.pawn_id)
    local label = resolve(disabled and txt.p2_disabled or txt.p2_row, pawn and pawn.name, pawn and pawn.level)
    local newi = sdk.create_instance("app.ui021601.ListInfo")
    if newi == nil then error("create_instance(ListInfo) returned nil") end
    pcall(function() newi:add_ref() end)
    pcall(function() newi:call(".ctor") end)
    pcall(function() newi:set_field("Listener", tmpl:get_field("Listener")) end)
    newi:set_field("ListenerType", tmpl:get_field("ListenerType"))
    newi:set_field("SpeakerType", tmpl:get_field("SpeakerType"))
    newi:set_field("_IsDecideEnable", not disabled)
    set_msg(newi, label)
    local pos = list:call("get_Count")
    list:call("Add", newi)
    local nm = ctx.nm_index
    row_state = { gen = menu_gen, pos = pos, nm = nm or (pos - 1), nm_found = nm ~= nil, disabled = disabled, label = label,
        cursor_events = 0, pawn_id = ctx.pawn_id, t = os.clock() }
    f.row_appended_at, f.row_label, f.row_disabled, f.never_mind_row = pos, label, disabled, row_state.nm
    add_event("row_appended", { index = pos, label = label, disabled = disabled, never_mind_row = row_state.nm,
        never_mind_found_by_guid = nm ~= nil, count_after = list:call("get_Count"), pawn_id = ctx.pawn_id })
end

-- Cursor tracking and the pick of the appended row: once the widget reports its GUI ended with SelectedIndex on the
-- row, SelectedIndex is set to the Never-mind row before the game maps it to a node choice (TalkUI's verified path,
-- finding 0007 Q2). Called from the update callback, reqEnd pre and updateChoiceNode pre.
local function decide(where)
    local st = row_state
    if not st then return nil end
    if st.gen ~= menu_gen then row_state = nil; return nil end
    local w = talk_select()
    if not w then return nil end
    local sel = field(w, "SelectedIndex")
    local ended = try(function() return w:call("get_IsEndGUI") end)
    if sel ~= st.last_sel then
        st.last_sel = sel
        if st.cursor_events < 30 then
            st.cursor_events = st.cursor_events + 1
            add_event("cursor", { where = where, selected = sel, on_row = sel == st.pos, ended = ended, disabled = st.disabled })
        end
    end
    if ended ~= true or sel ~= st.pos then return nil end
    local ok = pcall(function() w:set_field("SelectedIndex", st.nm) end)
    add_event("row_picked", { where = where, selected = sel, set_to = st.nm, ok = ok, read_back = field(w, "SelectedIndex"),
        disabled = st.disabled, label = st.label, pawn_id = st.pawn_id })
    notice = { text = string.format("Status row picked (%s): ended like Never mind", st.disabled and "disabled row" or "row"),
        t = os.clock() }
    row_state = nil
    return { selected = sel, set_to = st.nm, ok = ok }
end

local function req_disp_pre(args, frame)
    local list = to_managed(args[3])
    local f = { list_count = list and try(function() return list:call("get_Count") end) or "nil" }
    if list == nil then return f end
    menu_gen = menu_gen + 1
    row_state = nil
    local ctx = menu_context(list)
    f.root, f.node_id, f.pawn_id, f.has_dismiss, f.never_mind_row = ctx.root, ctx.node_id, ctx.pawn_id, ctx.has_dismiss, ctx.nm_index
    if ctx.pawn_id then -- a menu of a hired party pawn: always logged, whatever the toggles
        local p = pawn_entry(ctx.pawn_id)
        p2_last = { wall = wall(), root = ctx.root, node_id = ctx.node_id, pawn = p and p.name or ctx.pawn_id,
            count = ctx.count, appended = false }
        add_event("pawn_menu", { root = ctx.root, node_id = ctx.node_id, pawn_id = ctx.pawn_id, entries = ctx.entries })
    end
    if toggles.p2_row and ctx.root and ctx.pawn_id and ctx.count and ctx.count > 0 then
        local ok, err = pcall(p2_append_row, list, ctx, f)
        if ok then
            if p2_last then p2_last.appended = true end
        else
            row_state = nil
            log_error("p2 append", err)
            f.row_error = tostring(err)
        end
    elseif toggles.p2_row then
        f.row_skipped = ctx.root and "no hired party pawn in the talk" or "not the root menu of a hired pawn"
    end
    return f
end

-- ---------------------------------------------------------------------------------------------------------
-- P3 / P4: hook bodies

-- app.GUIBase.CharaData -> plain table (CharaId, OfflineID, IsMainPawn, name).
local function decode_chara_data(cd)
    if cd == nil or type(cd) ~= "userdata" then return nil end
    local d = {}
    d.CharaId = to_u32(field(cd, "<CharaId>k__BackingField"))
    d.IsMainPawn = field(cd, "<IsMainPawn>k__BackingField")
    local owner = try(function() return cd:get_field("CopyOwner") end)
    if type(owner) == "userdata" then
        d.OfflineID = try(function() return guid_str(owner:get_field("_OfflineID")) end)
        d.owner_name = field(owner, "_Name")
    end
    d.hired = d.OfflineID ~= nil and not is_err(d.OfflineID) and not is_zero_guid(d.OfflineID)
    local nm = m_name_cdata and try(function() return m_name_cdata:call(nil, cd) end)
    if type(nm) == "userdata" then nm = str(nm) end
    d.name = nm
    return d
end

local function p3_suffix_for(d)
    local pe = d and pawn_entry(d.CharaId)
    return resolve(txt.p3_suffix, d and d.name, pe and pe.level)
end

local function status_candidates(page)
    local list = {}
    local pi = try(function() return page:get_field("PawnInfo") end)
    if type(pi) == "userdata" then list[#list + 1] = { "PawnInfo.TxtName", try(function() return pi:get_field("TxtName") end) } end
    local ct = try(function() return page:get_field("CharaTab") end)
    if type(ct) == "userdata" then list[#list + 1] = { "CharaTab.TxtName", try(function() return ct:get_field("TxtName") end) } end
    return list
end

local function setup_pawn_post(retval, frame)
    local page = to_managed(frame.this)
    local d = frame.chara
    local f = { chara = d }
    if page == nil then return f end
    last_addr.status, last_addr.status_t = frame.this, os.clock()
    status_last = { wall = wall(), name = d and d.name, id = d and d.CharaId, hired = d and d.hired, offline = d and d.OfflineID }
    local cands = status_candidates(page)
    f.names_before = {}
    for _, c in ipairs(cands) do f.names_before[c[1]] = type(c[2]) == "userdata" and read_message(c[2]) or "n/a" end
    if toggles.p3 and d and d.hired then
        f.marked = {}
        for _, c in ipairs(cands) do
            local changed, out = mark_text(c[2], "", p3_suffix_for(d))
            f.marked[c[1]] = { changed = changed, now = out }
        end
        status_last.marked = true
    end
    if armed.status then
        armed.status = false
        dump_text_tree("status page (setupPawn, " .. tostring(d and d.name) .. ")", page, "ui060601_01")
    end
    return f
end

-- PawnInfo2Ref.setup(CharaData) / CharaChangeRef.updateName(): the other places a name may be written after
-- setupPawn; the same mark is applied so a later rewrite of the text does not drop it.
local function name_ref_post(get_chara_data)
    return function(retval, frame)
        local this = to_managed(frame.this)
        local f = {}
        if this == nil then return f end
        local t = try(function() return this:get_field("TxtName") end)
        f.name_now = type(t) == "userdata" and read_message(t) or "n/a"
        if toggles.p3 then
            local d = get_chara_data(this, frame)
            f.chara_hired = d and d.hired
            if d and d.hired then
                local changed, out = mark_text(t, "", p3_suffix_for(d))
                f.marked = { changed = changed, now = out }
            end
        end
        return f
    end
end

local pawn_info_setup_post = name_ref_post(function(_, frame) return frame.chara end)
local chara_tab_update_post = name_ref_post(function(this)
    local cd = try(function() return this:call("get_SelectedCharaData") end)
    return type(cd) == "userdata" and decode_chara_data(cd) or nil
end)

local function rift_page_post(retval, frame)
    local page = to_managed(frame.this)
    local f = {}
    if page == nil then return f end
    last_addr.rift, last_addr.rift_t = frame.this, os.clock()
    local flow = field(page, "FlowNow")
    local pos = field(page, "SearchListPos")
    local info = try(function() return page:get_field("SearchInfo") end)
    f.FlowNow, f.FlowNowName = flow, enum_name("app.ui041401.FlowId", flow)
    f.MenuType, f.SearchListPos, f.TopListPos = field(page, "MenuType"), pos, field(page, "TopListPos")
    -- GUESS: SearchListPos indexes app.ui041401.SearchId (Hired, Rehire, Favorite, Friend, PawnId, Terms)
    f.SearchId_guess = enum_name("app.ui041401.SearchId", pos)
    if type(info) == "userdata" then f.SearchType = field(info, "SearchType") end
    rift_page = { wall = wall(), flow = f.FlowNowName or flow, search_id = f.SearchId_guess or pos }
    if armed.rift then
        armed.rift = false
        dump_text_tree("rift page (setupPawnList)", page, "ui041401")
    end
    return f
end

local function rift_item_pre(args, frame)
    frame.item = args[2]
    frame.info = to_managed(args[3])
    return nil
end

local function rift_item_post(retval, frame)
    local info = frame.info
    local item = to_managed(frame.item)
    if info == nil or item == nil then return nil end
    local e = {}
    local res = try(function() return info:get_field("Res") end)
    e.name = type(res) == "userdata" and try(function() return res:call("get_Name") end) or nil
    e.level = type(res) == "userdata" and field(res, "Level") or nil
    e.offline = try(function() return guid_str(info:get_field("OfflineId")) end)
    e.favorite, e.summoned, e.is_official = field(info, "IsFavorite"), field(info, "IsSummoned"), field(info, "IsOfficialList")
    local texts = elements(try(function() return item:get_field("TxtPawnName") end), 6)
    e.shown_names = {}
    for i, t in ipairs(texts) do e.shown_names[i] = read_message(t) end
    local f = { entry = e }
    if toggles.p4 then
        local filter = txt.p4_filter:gsub("%s+", ""):lower()
        local match = filter == "" or (type(e.offline) == "string" and e.offline == filter)
        f.match = match
        if match then
            local lv = tonumber(e.level) and math.tointeger(tonumber(e.level)) or nil
            local prefix = resolve(txt.p4_prefix, nil, lv)
            local suffix = resolve(txt.p4_suffix, nil, lv)
            f.marked = {}
            for i, t in ipairs(texts) do
                local msg = read_message(t)
                if msg ~= "" and msg ~= "nil" and not is_err(msg) then
                    local changed, out = mark_text(t, prefix, suffix)
                    f.marked[i] = { changed = changed, now = out }
                end
            end
        end
    end
    local key = type(e.offline) == "string" and e.offline or tostring(e.name)
    if rift_entries[key] ~= nil or rift_entry_count < RIFT_ENTRY_CAP then
        if rift_entries[key] == nil then rift_entry_count = rift_entry_count + 1 end
        rift_entries[key] = { name = e.name, level = e.level, offline = e.offline, favorite = e.favorite,
            summoned = e.summoned, official = e.is_official, shown_names = e.shown_names, wall = wall() }
    end
    if armed.rift_item then
        armed.rift_item = false
        dump_text_tree("rift list item (ResItem.updateDisp, " .. tostring(e.name) .. ")", item, "ResItem")
    end
    return f
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook specs. pre(args, frame) / post(retval, frame) return the fields to log (or nil) and do any mutation;
-- `frame.log` says whether the entry will be logged.

local TE = "app.TalkEventPlayer"
local UI6 = "app.ui060601_01"
local UI41 = "app.ui041401"

local function game_call_pre(kinds)
    return function(args, frame)
        local vals = {}
        for i, kind in ipairs(kinds) do
            local ok, v = pcall(function()
                local a = args[2 + i]
                if kind == "str" then return arg_string(a)
                elseif kind == "guid" then return arg_guid(a)
                elseif kind == "bool" then return arg_bool(a)
                elseif kind == "i32" then return arg_i32(a)
                elseif kind == "u32" then return arg_u32(a)
                elseif kind == "f32" then return arg_f32(a)
                elseif kind == "go" then
                    local o = to_managed(a)
                    return o and try(function() return o:call("get_Name") end) or "nil"
                else return arg_nonnull(a) end -- "obj": nil / non-nil
            end)
            vals[i] = ok and v or ("ERR: " .. tostring(v))
        end
        return { self_call = in_self_call or nil, args = vals }
    end
end

local function nci_pre(args, frame)
    frame.guid = arg_guid(args[3])
    return { guid = frame.guid }
end

local function nci_post(retval, frame)
    local f = { guid = frame.guid }
    local obj = to_managed(retval)
    if obj == nil then f.ret = "nil"; return f end
    f.ret_msg = field(obj, "Msg")
    if #nci_recent < 64 then
        nci_recent[#nci_recent + 1] = { guid = frame.guid, msg = f.ret_msg, addr = try(function() return obj:get_address() end) }
    end
    return f
end

local SPECS = {
    -- P2: the talk flow
    { key = "TalkEventPlayer.startNode", type = TE, sig = "startNode()", quiet = true,
      pre = function() nci_recent = {} end },
    { key = "TalkEventPlayer.newChoiceInfo(Guid,Boolean x4)", type = TE, use_post = true,
      sig = "newChoiceInfo(System.Guid, System.Boolean, System.Boolean, System.Boolean, System.Boolean)",
      pre = nci_pre, post = nci_post },
    { key = "TalkEventPlayer.newChoiceInfo(Guid,String,Boolean x3)", type = TE, use_post = true,
      sig = "newChoiceInfo(System.Guid, System.String, System.Boolean, System.Boolean, System.Boolean)",
      pre = nci_pre, post = nci_post },
    { key = "ui021601.reqDisp", type = "app.ui021601", important = true,
      sig = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
          .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)",
      pre = req_disp_pre },
    { key = "TalkEventPlayer.updateChoiceNode", type = TE, sig = "updateChoiceNode()", chatty = true,
      pre = function() return decide("updateChoiceNode") end },
    { key = "ui021601.reqEnd", type = "app.ui021601", sig = "reqEnd()",
      pre = function() return decide("reqEnd") end },

    -- P3: Status page
    { key = "ui060601_01.setupPawn", type = UI6, sig = "setupPawn(app.GUIBase.CharaData)", use_post = true, important = true,
      pre = function(args, frame)
          frame.this = args[2]
          frame.chara = decode_chara_data(to_managed(args[3]))
          return { chara_data = frame.chara or "nil" }
      end,
      post = setup_pawn_post },
    { key = "PawnInfo2Ref.setup", type = "app.GUIBase.PawnInfo2Ref", sig = "setup(app.GUIBase.CharaData)", use_post = true,
      pre = function(args, frame)
          frame.this = args[2]
          frame.chara = decode_chara_data(to_managed(args[3]))
          return { chara_data = frame.chara or "nil" }
      end,
      post = pawn_info_setup_post },
    { key = "CharaChangeRef.updateName", type = "app.GUIBase.CharaChangeRef", sig = "updateName()", use_post = true, chatty = true,
      pre = function(args, frame) frame.this = args[2] end,
      post = chara_tab_update_post },

    -- P4: Rift "previously hired" list
    { key = "ui041401.setupPawnList", type = UI41, sig = "setupPawnList()", use_post = true, important = true,
      pre = function(args, frame) frame.this = args[2] end,
      post = rift_page_post },
    { key = "ui041401.ResItem.updateDisp", type = "app.ui041401.ResItem", sig = "updateDisp(app.ui041401.ResInfo)",
      use_post = true, cap = 120, pre = rift_item_pre, post = rift_item_post },

    -- The game's own calls to the P1 methods, log-only: what it passes for the unknown UInt32 / Boolean arguments
    { key = "game: requestNoButtonDialog(String,UInt32)", type = GM, chatty = true,
      sig = "requestNoButtonDialog(System.String, System.UInt32)", pre = game_call_pre({ "str", "u32" }) },
    { key = "game: requestNoButtonDialog(Guid,UInt32)", type = GM, chatty = true,
      sig = "requestNoButtonDialog(System.Guid, System.UInt32)", pre = game_call_pre({ "guid", "u32" }) },
    { key = "game: requestDispPupUpMessage", type = GM, chatty = true,
      sig = "requestDispPupUpMessage(System.Guid, System.UInt32)", pre = game_call_pre({ "guid", "u32" }) },
    { key = "game: requestDispSystemPopupMessage", type = GM, chatty = true,
      sig = "requestDispSystemPopupMessage(System.Guid, System.Guid[])", pre = game_call_pre({ "guid", "obj" }) },
    { key = "game: requestHideDialog", type = GM, chatty = true, sig = "requestHideDialog()", pre = game_call_pre({}) },
    { key = "game: requestHidePopUpMessage", type = GM, chatty = true, sig = "requestHidePopUpMessage()",
      pre = game_call_pre({}) },
    { key = "game: requestHideSystemPopupMessage", type = GM, chatty = true, sig = "requestHideSystemPopupMessage()",
      pre = game_call_pre({}) },
    { key = "game: reqLevelUp", type = GM, chatty = true, sig = "reqLevelUp(app.CharacterID, System.Int32, System.Int32)",
      pre = game_call_pre({ "u32", "i32", "i32" }) },
    { key = "game: setTalkBalloonMessage", type = GM, chatty = true,
      method_key = "balloon",
      pre = game_call_pre({ "go", "guid", "i32", "i32", "bool", "f32", "u32", "obj", "obj", "obj", "obj", "bool" }) },
    { key = "game: addTalkSubtitleMessage(10 args)", type = GM, chatty = true, method_key = "subtitle",
      pre = game_call_pre({ "go", "guid", "i32", "i32", "u32", "obj", "obj", "obj", "obj", "bool" }) },
}

for _, spec in ipairs(SPECS) do
    spec.cap = spec.cap or (spec.chatty and CHATTY_SPEC_CAP) or (spec.important and 600) or DEFAULT_SPEC_CAP
end

local function pre_body(spec, args)
    local c = run.count_by_spec[spec.key]
    if not c then c = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = c end
    c.pre = c.pre + 1
    local frame = { spec = spec, seq = next_seq() }
    local n = logged_by_spec[spec.key] or 0
    if spec.quiet then
        frame.log = false
    elseif #calls >= CALL_CAP then
        run.dropped = run.dropped + 1
    elseif n >= spec.cap then
        run.dropped = run.dropped + 1
        run.dropped_by_spec[spec.key] = (run.dropped_by_spec[spec.key] or 0) + 1
    else
        frame.log = true
    end
    if spec.use_post then
        local st = frames[spec.key]
        if not st then st = {}; frames[spec.key] = st end
        if #st >= STACK_MAX then st = {}; frames[spec.key] = st; log_error("stack", spec.key) end
        st[#st + 1] = frame -- pushed first: post must find it even if the rest of this body throws
    end
    local fields
    if spec.pre then
        local ok, res = pcall(spec.pre, args, frame)
        if ok then fields = res else log_error("pre " .. spec.key, res) end
    end
    if frame.log then
        local e = { seq = frame.seq, t = os.clock(), method = spec.key, phase = "pre" }
        if type(fields) == "table" then
            for k, v in pairs(fields) do e[k] = v end
        end
        frame.logged = append_entry(spec, e) ~= nil
    end
end

local function post_body(spec, retval)
    local c = run.count_by_spec[spec.key]
    if not c then c = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = c end
    c.post = c.post + 1
    local st = frames[spec.key]
    local frame = st and st[#st]
    if not frame then return end
    st[#st] = nil
    if not spec.post then return end
    local ok, fields = pcall(spec.post, retval, frame)
    if not ok then
        log_error("post " .. spec.key, fields)
        return
    end
    if frame.logged and type(fields) == "table" then
        local e = { seq = next_seq(), t = os.clock(), method = spec.key, phase = "post", pre_seq = frame.seq }
        for k, v in pairs(fields) do e[k] = v end
        append_entry(spec, e)
    end
end

local function install_hooks()
    local installed, missing = {}, {}
    for _, spec in ipairs(SPECS) do
        local ok, err = pcall(function()
            local m = spec.method_key and M[spec.method_key]
            if m == nil then
                if spec.sig == nil then error("method not registered: " .. tostring(spec.method_key)) end
                local td = sdk.find_type_definition(spec.type)
                if not td then error("type not found: " .. spec.type) end
                m = find_method(td, spec.sig)
                if not m then error("method not found: " .. spec.sig) end
            end
            local post_fn = nil
            if spec.use_post then
                post_fn = function(retval)
                    local ok_post, e = pcall(post_body, spec, retval)
                    if not ok_post then log_error("post " .. spec.key, e) end
                    return retval
                end
            end
            sdk.hook(m,
                function(args)
                    local ok_pre, e = pcall(pre_body, spec, args)
                    if not ok_pre then log_error("pre " .. spec.key, e) end
                    return sdk.PreHookResult.CALL_ORIGINAL
                end,
                post_fn)
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
-- P5: the game's own dialog (TalkUI's verified Q3 path) and its answer

local function dialog_state_now()
    local gm = singleton("app.GuiManager")
    if not gm then return nil end
    local s = {}
    s.state = try(function() return gm:call("getDialogState") end)
    s.raw = try(function() return gm:call("getRawDialogState") end)
    s.disp = try(function() return gm:call("IsDispDialogGui") end)
    s.wait = try(function() return gm:call("isWaitDialogMessage") end)
    s.state_name = enum_name("app.ui010101.RetVal", s.state)
    s.raw_name = enum_name("app.ui010101.RetVal", s.raw)
    local w = try(function() return gm:get_field("Dialog") end)
    if type(w) == "userdata" then
        s.w_ret = field(w, "Ret")
        s.w_ret_name = enum_name("app.ui010101.RetVal", s.w_ret)
        s.w_raw = try(function() return w:call("getRawRetVal") end)
        s.w_raw_name = enum_name("app.ui010101.RetVal", s.w_raw)
    else
        s.w_ret = "no widget"
    end
    return s
end

local function dialog_key(s)
    return table.concat({ tostring(s.state), tostring(s.raw), tostring(s.disp), tostring(s.wait), tostring(s.w_ret),
        tostring(s.w_raw) }, "|")
end

local function end_poll(reason)
    local p = dialog_poll
    if not p or p.done then return end
    p.done = true
    add_event("dialog_poll_end", { reason = reason, elapsed = os.clock() - p.start, answer = p.answer, final = dialog_live })
end

local function start_poll()
    end_poll("replaced by a new dialog request")
    dialog_poll = { start = os.clock(), last_key = nil, saw_result = false, answer = nil, done = false }
    add_event("dialog_poll_start", {})
end

local function poll_dialog()
    local p = dialog_poll
    if not p or p.done then return end
    local s = dialog_state_now()
    if not s then return end
    dialog_live = s
    local k = dialog_key(s)
    if k ~= p.last_key then
        p.last_key = k
        add_event("dialog_state", { dt = os.clock() - p.start, state = s.state, state_name = s.state_name, raw = s.raw,
            raw_name = s.raw_name, disp = s.disp, wait = s.wait, w_ret = s.w_ret, w_ret_name = s.w_ret_name,
            w_raw = s.w_raw, w_raw_name = s.w_raw_name })
    end
    if (s.w_ret_name and s.w_ret_name ~= "None") or (s.state_name and s.state_name ~= "None") then
        p.saw_result = true
        if not p.answer then
            p.answer = s.w_ret_name ~= "None" and s.w_ret_name or s.state_name
            add_event("adopt_dialog_answer", { answer = p.answer, w_ret = s.w_ret, state = s.state })
        end
    end
    if p.saw_result and s.disp ~= true then
        end_poll("answer seen and dialog closed")
    elseif os.clock() - p.start >= DIALOG_POLL_SECONDS then
        end_poll("timeout")
    end
end

local function open_adopt_dialog()
    if not M.request_dialog then return unavailable("request_dialog") end
    local gm = gm_or_log("requestDialog")
    if not gm then return end
    local texts = { resolve(txt.p5_main), txt.p5_yes, txt.p5_no, "", "" }
    local ok_call = run_call("requestDialog(String x5, 16 neutral args)", { main = texts[1], sel0 = texts[2], sel1 = texts[3] },
        function()
            local a = {}
            for i = 1, 5 do a[i] = sdk.create_managed_string(texts[i]) end
            for i = 6, 21 do
                if DIALOG_KINDS[i] ~= "tex" then a[i] = DIALOG_GUESS[i] end
            end
            return M.request_dialog:call(gm, table.unpack(a, 1, 21))
        end)
    if ok_call then start_poll() end
end

-- ---------------------------------------------------------------------------------------------------------
-- Update-thread work: queued UI actions, once-a-second refresh, dialog poll, auto-hide, flush

local function refresh()
    local ok, err = pcall(function()
        local list = party_entries(false)
        party_cache = list
        if sel_id == nil or pawn_entry(sel_id) == nil then
            local hired = hired_entries()
            sel_id = hired[1] and hired[1].id or nil
        end
    end)
    if not ok then log_error("refresh", err) end
end

local function flush()
    last_flush = os.clock()
    local ok, err = pcall(function()
        local out = {}
        for k, v in pairs(run) do out[k] = type(v) == "table" and nz(v) or v end
        out.hooks = { installed = nz(run.hooks.installed), missing = nz(run.hooks.missing) }
        out.markers = nz(run.markers)
        out.probes_disabled = nz(probe_missing)
        out.settings_now = sanitize({ toggles = toggles, texts = txt, numbers = num, flags = flags,
            substitution = { guid = subst.guid, text = subst.text, hits = subst.hits }, text_hooks = text_hooks })
        out.party = sanitize(party_cache)
        out.rift_entries = sanitize(rift_entries)
        out.status_page_last = sanitize(status_last or "none")
        out.rift_page_last = sanitize(rift_page or "none")
        out.summary = {
            calls_logged = #calls, calls_dropped = run.dropped, events = #run.events, dropped_events = run.dropped_events,
            markers = #run.markers, errors = #run.errors, text_dumps = #run.text_dumps,
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
    if row_state then
        local ok, err = pcall(decide, "UpdateBehavior")
        if not ok then log_error("decide", err) end
    end
    if #work_queue > 0 then
        local q = work_queue
        work_queue = {}
        for _, fn in ipairs(q) do
            local ok, err = pcall(fn)
            if not ok then log_error("work", err) end
        end
    end
    if autohide_at and now >= autohide_at then
        autohide_at = nil
        local ok, err = pcall(do_hide_dialog, "auto-hide")
        if not ok then log_error("autohide", err) end
    end
    local ok, err = pcall(poll_dialog)
    if not ok then log_error("poll_dialog", err) end
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

local function fmt_entry(e)
    local parts = { string.format("#%d t=%.1f %s %s", e.seq, e.t, e.method, e.phase or "") }
    if e.self_call then parts[#parts + 1] = "(self)" end
    return table.concat(parts, " ")
end

-- One-of-many pick drawn as a checkbox (this REFramework build has no imgui.radio_button).
local function radio(lbl, current, value)
    local changed, v = imgui.checkbox(lbl, current == value)
    return changed and v == true and current ~= value
end

local function draw_toggle(key, text, on_change)
    local ch, v = imgui.checkbox(text, toggles[key])
    if ch then
        toggles[key] = v
        queue_work(function()
            add_event("toggle", { name = key, value = v })
            if on_change then on_change(v) end
        end)
    end
end

local function draw_text(key, label, tbl)
    tbl = tbl or txt
    local ch, v = imgui.input_text(label, tbl[key])
    if ch then tbl[key] = v end
end

local function draw_button(label, probe, fn)
    if probe and probe_missing[probe] then
        imgui.text(label .. "  [disabled: " .. clip(probe_missing[probe], 80) .. "]")
        return
    end
    if imgui.button(label) then queue_work(fn) end
end

local function draw_p1()
    imgui.text("P1 calls game methods that only draw UI. Text is replaced by the selected pawn's name / level.")
    draw_text("notice", "B1 text")
    draw_text("popup", "B2 popup text")
    draw_text("speech", "B4 speech text")
    imgui.text("-- B1 requestNoButtonDialog(String, UInt32)")
    draw_text("nb_arg", "UInt32 value", num)
    draw_text("nb_hide_s", "auto-hide after (s)", num)
    draw_toggle("autohide", "Auto-hide with requestHideDialog (0 s = never; safety, default on)")
    draw_button("B1: show with UInt32 = 0", "nb_str", function() do_nobutton(false) end)
    imgui.same_line()
    draw_button("B1: show with the UInt32 above", "nb_str", function() do_nobutton(true) end)
    draw_button("B1: requestHideDialog", "hide_dialog", function() do_hide_dialog("button") end)

    imgui.text("-- B2 popups and B4 speech need a message Guid; the lookup hooks return the text only for it.")
    local ch, v = imgui.input_text("Guid", subst.guid_input)
    if ch then
        subst.guid_input = v
        queue_work(function()
            if set_subst_guid(v) then add_event("guid_set", { guid = subst.guid }) end
        end)
    end
    imgui.text("active Guid: " .. subst.guid)
    if imgui.button("Use the script-owned Guid") then
        queue_work(function() set_subst_guid(OWN_GUID); add_event("guid_set", { guid = subst.guid, kind = "own" }) end)
    end
    imgui.same_line()
    if imgui.button("Use real game Guid (Never mind)") then
        queue_work(function() set_subst_guid(NEVERMIND_GUID); add_event("guid_set", { guid = subst.guid, kind = "real: Never mind" }) end)
    end
    imgui.same_line()
    if imgui.button("New random Guid") then
        queue_work(function()
            if not M.new_guid then return unavailable("new_guid") end
            local g = M.new_guid:call(nil)
            local s = guid_str(g)
            if parse_guid(s) then
                set_subst_guid(s)
                subst.vt, subst.vt_guid = g, subst.guid
            end
            add_event("guid_set", { guid = subst.guid, kind = "random" })
        end)
    end
    imgui.text("Real game Guid: while Substitute text is on, the game's own 'Never mind.' text changes too.")
    draw_toggle("subst", "Substitute text for this Guid (installs the text-lookup hooks on first use)",
        function(on)
            if on then
                install_text_hooks()
                if subst.text == "" then set_subst_text(txt.popup) end
            end
        end)
    imgui.text("text hooks: " .. text_hooks.status)
    local parts = {}
    for k, n in pairs(subst.hits) do parts[#parts + 1] = k .. "=" .. n end
    imgui.text("substitutions made: " .. (#parts > 0 and table.concat(parts, "  ") or "none yet"))
    draw_text("popup_arg", "UInt32 value (popup)", num)
    draw_button("B2: requestDispPupUpMessage", "popup", do_popup)
    draw_button("B2: requestDispSystemPopupMessage (params nil)", "syspopup", function() do_syspopup(false) end)
    imgui.same_line()
    draw_button("(params = empty Guid[])", "syspopup", function() do_syspopup(true) end)
    draw_button("B2: requestHidePopUpMessage", "hide_popup", function() do_hide("hide_popup", "requestHidePopUpMessage()") end)
    imgui.same_line()
    draw_button("requestHideSystemPopupMessage", "hide_syspopup", function() do_hide("hide_syspopup", "requestHideSystemPopupMessage()") end)
    draw_button("Probe Guid: isExistGuid + message.get", "msg_get", do_probe_guid)

    imgui.text("-- B3 GuiManager.reqLevelUp(CharacterID, oldLv, newLv): the level-up notice with the pawn's name")
    imgui.text("Findings 0002/0003: it is the UI call dispatchExp makes; a standalone call is NOT verified to be stat-free.")
    draw_text("lv_old", "old level", num)
    draw_text("lv_new", "new level", num)
    draw_button("B3: reqLevelUp for the selected pawn", "level_up", do_level_up)

    imgui.text("-- B4 speech over the selected pawn's head (uses the Guid + Substitute text above)")
    draw_text("balloon_s", "duration (s)", num)
    local c1, v1 = imgui.checkbox("balloon Boolean #5", flags.balloon_a)
    if c1 then flags.balloon_a = v1 end
    imgui.same_line()
    local c2, v2 = imgui.checkbox("balloon Boolean #12", flags.balloon_b)
    if c2 then flags.balloon_b = v2 end
    draw_button("B4: setTalkBalloonMessage", "balloon", function() do_balloon("balloon") end)
    local c3, v3 = imgui.checkbox("subtitle Boolean #10", flags.subtitle_b)
    if c3 then flags.subtitle_b = v3 end
    draw_button("B4b: addTalkSubtitleMessage", "subtitle", function() do_balloon("subtitle") end)
end

local function draw_p2()
    imgui.text("P2 edits the root talk menu of a hired party pawn only. Off at load. Save first.")
    draw_text("p2_row", "Row label")
    draw_toggle("p2_row", "Append a fifth row (picking it ends the talk like Never mind)")
    draw_text("p2_disabled", "Disabled-row label")
    draw_toggle("p2_disabled", "Make that row disabled (_IsDecideEnable = false; with the label above)")
    if p2_last then
        imgui.text(string.format("last hired-pawn menu (%s): pawn=%s root=%s node=%s entries=%s row appended=%s", p2_last.wall,
            tostring(p2_last.pawn), tostring(p2_last.root), tostring(p2_last.node_id and p2_last.node_id:sub(1, 8)),
            tostring(p2_last.count), tostring(p2_last.appended)))
    else
        imgui.text("No hired-pawn menu seen yet: talk to a hired party pawn.")
    end
end

local function draw_p3()
    imgui.text("P3 marks the name of a hired pawn's tab on the Status page. Off at load.")
    draw_text("p3_suffix", "Suffix")
    draw_toggle("p3", "Mark hired pawns on the Status page (CopyOwner._OfflineID non-zero)")
    if imgui.button("Arm text dump (next tab change)") then queue_work(function() armed.status = true; add_event("armed", { what = "status dump" }) end) end
    imgui.same_line()
    if imgui.button("Dump status page now (page must be open)") then queue_work(function() dump_from_addr("status", "status page (button)") end) end
    if status_last then
        imgui.text(string.format("last setupPawn (%s): %s id=%s hired=%s offline=%s marked=%s", status_last.wall,
            tostring(status_last.name), tostring(status_last.id), tostring(status_last.hired),
            tostring(status_last.offline and tostring(status_last.offline):sub(1, 8)), tostring(status_last.marked)))
    else
        imgui.text("No setupPawn seen yet: open pause > Status.")
    end
end

local function draw_p4()
    imgui.text("P4 marks entries of the Rift's pawn lists. Off at load. Also logs every listed pawn.")
    draw_text("p4_prefix", "Prefix")
    draw_text("p4_suffix", "Suffix ({lv} = the entry's level)")
    draw_text("p4_filter", "OfflineID filter (empty = every entry)")
    draw_toggle("p4", "Mark listed pawns")
    if imgui.button("Arm text dump (next list refresh + next item)") then
        queue_work(function() armed.rift = true; armed.rift_item = true; add_event("armed", { what = "rift dump" }) end)
    end
    imgui.same_line()
    if imgui.button("Dump rift page now (page must be open)") then queue_work(function() dump_from_addr("rift", "rift page (button)") end) end
    if rift_page then
        imgui.text(string.format("last list setup (%s): flow=%s search id (guess)=%s entries seen=%d", rift_page.wall,
            tostring(rift_page.flow), tostring(rift_page.search_id), rift_entry_count))
    else
        imgui.text("No list setup seen yet: open a Riftstone > previously hired.")
    end
    local shown = 0
    for _, e in pairs(rift_entries) do
        if shown >= 6 then break end
        shown = shown + 1
        imgui.text(string.format("  %s Lv %s offline=%s fav=%s summoned=%s", tostring(e.name), tostring(e.level),
            tostring(e.offline and tostring(e.offline):sub(1, 8)), tostring(e.favorite), tostring(e.summoned)))
    end
end

local function draw_p5()
    imgui.text("P5 opens the game's yes/no dialog (TalkUI's Q3 path) to see wrapping. Write \\n for a line break.")
    imgui.text("The A press that answers it can reach the player (a jump); answer from a safe spot.")
    draw_text("p5_main", "Main text")
    draw_text("p5_yes", "Button 1")
    draw_text("p5_no", "Button 2")
    draw_button("P5: open the adopt dialog", "request_dialog", open_adopt_dialog)
    local s = dialog_live
    if s then
        imgui.text(string.format("state=%s (%s)  displayed=%s  widget Ret=%s (%s)", tostring(s.state), tostring(s.state_name),
            tostring(s.disp), tostring(s.w_ret), tostring(s.w_ret_name)))
    end
    local p = dialog_poll
    if p then
        imgui.text(string.format("poll: %s  answer=%s", p.done and "finished" or
            string.format("running, %.0f s left", DIALOG_POLL_SECONDS - (os.clock() - p.start)), tostring(p.answer)))
    end
end

local function draw_body()
    imgui.text("THROWAWAY. Purely visual: writes no roster, backup, pawn data or save. Back up first.")
    imgui.text(hook_status)
    imgui.text("Run file: reframework/data/" .. RUN_FILE)
    local seen = 0
    for _, c in pairs(run.count_by_spec) do seen = seen + c.pre + c.post end
    imgui.text(string.format("Calls: %d logged, %d dropped, %d seen | events %d | markers %d | errors %d | dumps %d",
        #calls, run.dropped, seen, #run.events, #run.markers, #run.errors, #run.text_dumps))
    imgui.text(flush_status)
    if notice then imgui.text(string.format("%s  (%.0f s ago)", notice.text, os.clock() - notice.t)) end
    local missing = {}
    for k in pairs(probe_missing) do missing[#missing + 1] = k end
    if #missing > 0 then imgui.text("Probes disabled (method missing): " .. table.concat(missing, ", ")) end

    local ch, v = imgui.input_text("Marker", marker_text)
    if ch then marker_text = v end
    imgui.same_line()
    if imgui.button("Add marker") and marker_text ~= "" then
        local text = marker_text
        queue_work(function()
            if #run.markers >= MARKER_CAP then return end
            local mk = { t = os.clock(), wall = wall(), label = text }
            markers[#markers + 1] = mk
            run.markers[#run.markers + 1] = mk
            dirty = true
        end)
    end
    if #markers > 0 then imgui.text("last marker: " .. markers[#markers].label) end
    imgui.same_line()
    if imgui.button("Flush log now") then flush_requested = true end

    imgui.text("Sample pawn (name / level for the texts, target of B3 / B4):")
    local hired = hired_entries()
    if #hired == 0 then imgui.text("  no hired party pawn: texts use " .. FALLBACK_NAME .. " / " .. tostring(FALLBACK_LEVEL)) end
    for _, e in ipairs(hired) do
        if radio(string.format("slot %d: %s (%d) Lv %s##sel%d", e.slot, tostring(e.name or "?"), e.id, tostring(e.level or "?"), e.id),
            sel_id, e.id) then
            sel_id = e.id
            queue_work(function() add_event("sample_pawn", { id = e.id, name = e.name }) end)
        end
    end

    local trees = {
        { "P1 transient notices (B1-B4)", draw_p1 },
        { "P2 talk-menu status row", draw_p2 },
        { "P3 Status page mark", draw_p3 },
        { "P4 Rift previously hired mark", draw_p4 },
        { "P5 adopt confirmation + gear warning", draw_p5 },
    }
    for _, t in ipairs(trees) do
        if imgui.tree_node(t[1]) then
            local ok, err = pcall(t[2])
            if not ok then imgui.text("UI error: " .. tostring(err)) end
            imgui.tree_pop()
        end
    end
    if imgui.tree_node("Recent events") then
        for i = math.max(1, #run.events - LOG_LINES + 1), #run.events do
            local e = run.events[i]
            imgui.text(string.format("#%d t=%.1f %s %s", e.seq, e.t, e.kind,
                clip(tostring(e.probe or e.name or e.label or e.what or e.hook or e.reason or ""), 60)
                    .. (e.ok == false and (" FAILED: " .. clip(tostring(e.error), 80)) or "")))
        end
        imgui.tree_pop()
    end
    for i = math.max(1, #calls - 4), #calls do imgui.text(fmt_entry(calls[i])) end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Exp StatusUI") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
