-- Retinue Exp TalkUI: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- What it answers (M2, ticket 06 "How should adopt and release look and feel?"), the four probes Q1-Q4 of
-- docs/findings/research-m2-native-ui.md ("Experiments for ticket 06"):
--   Q1  What does the talk menu of a hired party pawn look like (node class, _RentType, choices, ListInfo entries),
--       in the field and at a Rift stone? Log-only, always on.
--   Q2  Can we relabel one entry ("Adopt"), catch the pick in nextNode, redirect it to "Never mind" so the
--       conversation just ends, and does a fifth ListInfo appended in requestTalkSelect show? Toggles, all OFF.
--   Q3  Can the mod menu open the game's own dialog box (GuiManager.requestDialog) and read the answer?
--   Q4  Does ui060601_01 (Status page) tell us which hired pawn a tab shows? Log-only, always on.
-- See tools/experiments/README.md for the procedure.
--
-- The hooks never change an argument or a return value UNLESS a Q2 toggle is on (all off at load, nothing is
-- persisted between sessions). The Q3 buttons CALL a game method. Q2 redirect / fifth entry can end a conversation
-- oddly: BACK UP FIRST (tools/saves.sh backup <label>), once per run. None of the hooked methods is hooked by the
-- mod, so this script can be linked TOGETHER with the mod (deploy.sh --talkui).
--
-- Output: reframework/data/Retinue/experiments/talkui_<timestamp>.json (one file per session, flushed every 2 s
-- when changed). Hooks cannot be removed in REFramework, so all of them are installed at load. Every hook body is
-- wrapped in pcall: a bug here must never break a game call. Conventions follow Retinue_Exp_Lifecycle.lua; API
-- names were checked against this game version's il2cpp_dump.json (not run in game: see the README).
--
-- Hook argument indexes: instance methods have args[2] = this and the first parameter at args[3].

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn: never a target
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "talkui_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 6000 -- shared cap of the `calls` list
-- Every hook has its own cap of logged entries (pre phase), so none can exhaust the shared CALL_CAP. Beyond its
-- cap a hook only increments the counters (run.count_by_spec, run.dropped_by_spec); mutations still run.
local DEFAULT_SPEC_CAP = 300
local IMPORTANT_SPEC_CAP = 1000
local CHATTY_SPEC_CAP = 5 -- updatePawnRentalNode: count only, log the first few
local MENU_CAP = 200 -- menu snapshots
local EVENT_CAP = 600 -- relabel / picked / toggle / dialog events
local ERROR_CAP = 200
local MARKER_CAP = 200
local CHOICES_MAX = 16 -- entries read from a node's _Choices / PawnDataList / a ListInfo list
local STACK_MAX = 32 -- in-flight frames per hook
local LOG_LINES = 12
local DIALOG_POLL_SECONDS = 60
local DEFAULT_LABEL = "Adopt"

-- Q3: positional parameter kinds of GuiManager.requestDialog(String overload, 21 args) and ui010101.reqDisp (24).
local DIALOG_KINDS = { "str", "str", "str", "str", "str", "bool", "i32", "bool", "u32", "i32", "i32", "tex",
    "bool", "bool", "bool", "bool", "bool", "f32", "bool", "bool", "bool" }
local REQDISP_KINDS = { "str", "str", "str", "str", "str", "bool", "i32", "bool", "u32", "i32", "i32", "tex",
    "bool", "bool", "bool", "bool", "bool", "bool", "bool", "f32", "bool", "bool", "bool", "bool" }
-- GUESS: values for requestDialog parameters 6..21 when no captured call is used. Their meaning is unknown (they
-- are not named in the dump); false / 0 / nil / 0.0 is the neutral choice. [12] is the texture holder (nil).
-- The "Open with captured args" button replaces this guess with what the game itself passed.
local DIALOG_GUESS = {
    [6] = false, [7] = 0, [8] = false, [9] = 0, [10] = 0, [11] = 0, [12] = nil,
    [13] = false, [14] = false, [15] = false, [16] = false, [17] = false, [18] = 0.0,
    [19] = false, [20] = false, [21] = false,
}
local DIALOG_DEFAULT_MAIN = "Release this pawn from your retinue?"

-- Session state (never persisted).
local toggles = { relabel_nci = false, relabel_rts = false, catch_pick = false, redirect = false, fifth = false,
    raise_dispmax = false }
local dispmax_text = "5" -- value written to TalkSelect.DispMax when "Raise DispMax" applies
local dispmax_state = nil -- { old, new, t, saw_disp }: DispMax was raised and must be restored
local label_text = DEFAULT_LABEL
local target = nil -- { index, guid, choice, msg }: the row to relabel / catch
local nevermind = nil -- { index, guid, choice, msg }: the row whose index a redirect jumps to
local markers, marker_text = {}, ""
local dlg = { main = DIALOG_DEFAULT_MAIN, sel0 = "Yes", sel1 = "No", sel2 = "", sel3 = "", use_tex = false }
local captured_dialog_args = nil -- { vals, wall, t }: the latest requestDialog the GAME made
local captured_tex = nil -- its texture holder object (only passed when dlg.use_tex)
local in_self_call = false -- true while this script itself calls requestDialog
local dialog_poll, dialog_live = nil, nil
local last_menu, menu_live, menu_gen = nil, false, 0
local fifth_state = nil -- { gen, pos }: a fifth entry was appended at index `pos` in menu generation `gen`
local notice = nil -- { text, t }
local status_pawn, status_page = nil, nil -- Q4 live data
local party_cache = {} -- { {id, name, slot} }: refreshed once a second, read by the panel
local hook_status, flush_status = "hooks not installed yet", ""
local flush_requested = false
local names = {} -- CharacterID -> last seen display name
local enum_cache = {}
local work_queue = {}

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    constants = {
        script = "Retinue_Exp_TalkUI",
        main_id = MAIN_ID,
        call_cap = CALL_CAP,
        default_spec_cap = DEFAULT_SPEC_CAP,
        important_spec_cap = IMPORTANT_SPEC_CAP,
        chatty_spec_cap = CHATTY_SPEC_CAP,
        menu_cap = MENU_CAP,
        event_cap = EVENT_CAP,
        dialog_kinds = DIALOG_KINDS,
        dialog_guess = DIALOG_GUESS,
        dialog_poll_seconds = DIALOG_POLL_SECONDS,
    },
    markers = {},
    menus = {},
    calls = {},
    events = {},
    errors = {},
    hooks = { installed = {}, missing = {} },
    dropped = 0, -- call entries lost to the shared cap or to a per-hook cap
    dropped_by_spec = {},
    dropped_menus = 0,
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

-- System.Guid (a value type) -> canonical lowercase "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx". Reads the raw 16
-- bytes (read_qword, as Guild Contracts does, because it found ToString-based reading unreliable), then falls
-- back to ToString and to the _a.._k fields. Never returns userdata.
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
    local ok2, s2 = pcall(function() return v:call("ToString") end)
    if ok2 and type(s2) == "string" and s2:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then return s2:lower() end
    return "unreadable"
end

local function is_guid(s) return type(s) == "string" and s:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil end

-- Reads a System.Guid passed by value (hidden pointer) in a hook.
local function arg_guid(a)
    if sdk.to_valuetype then
        local ok, v = pcall(sdk.to_valuetype, a, "System.Guid")
        if ok and v ~= nil then return guid_str(v) end
    end
    local ok2, o = pcall(sdk.to_managed_object, a)
    if ok2 and o ~= nil then return guid_str(o) end
    return "unreadable"
end

-- Name of enum value `v` of `type_name` (static fields of the enum type), cached; nil when unknown.
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

-- Elements of a managed array as a Lua table (1-based), capped.
local function elements(arr)
    if arr == nil or type(arr) ~= "userdata" then return {} end
    local out = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do
            if i > CHOICES_MAX then break end
            out[i] = v
        end
        return out
    end
    local n = try(function() return arr:call("get_Length") end)
    if type(n) == "number" then
        for i = 0, math.min(n, CHOICES_MAX) - 1 do out[i + 1] = arr:call("GetValue", i) end
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

local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_name_id = td_guibase and td_guibase:get_method("getName(app.CharacterID)")
local m_name_chara = td_guibase and td_guibase:get_method("getName(app.Character)")
local m_name_cdata = td_guibase and find_method(td_guibase, "getName(app.GUIBase.CharaData)")
local td_gui = sdk.find_type_definition("app.GuiManager")
local m_request_dialog = td_gui and find_method(td_gui, "requestDialog(System.String, System.String, System.String, "
    .. "System.String, System.String, System.Boolean, System.Int32, System.Boolean, System.UInt32, System.Int32, "
    .. "System.Int32, via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, "
    .. "System.Boolean, System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)")

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

-- ---------------------------------------------------------------------------------------------------------
-- Pawns and names

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
                local nm = try(function() return m_name_chara:call(nil, chara) end)
                if type(nm) == "userdata" then nm = str(nm) end
                if type(nm) == "string" and not is_err(nm) then names[id] = nm end
                out[#out + 1] = { id = id, slot = i + 1, name = names[id] }
            end
        end
    end
    return out
end

-- True when `id` is a non-main pawn in the current party (a hired pawn).
local function is_hired_party_pawn(id)
    if type(id) ~= "number" or id == MAIN_ID or id == 0 then return false end
    local ok, found = pcall(function()
        for _, e in ipairs(party_entries()) do
            if e.id == id then return true end
        end
        return false
    end)
    return ok and found == true
end

local function name_of(id)
    if type(id) ~= "number" then return nil end
    if names[id] then return names[id] end
    local nm = try(function() return m_name_id:call(nil, id) end)
    if type(nm) == "userdata" then nm = str(nm) end
    if type(nm) == "string" and not is_err(nm) and nm ~= "" then
        names[id] = nm
        return nm
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------------------
-- Talk state decoders

-- (brief table, current node object) of TalkEventManager.CurrentTalkInfo, or nil.
local function talk_info()
    local tm = singleton("app.TalkEventManager")
    local info = tm and tm:get_field("<CurrentTalkInfo>k__BackingField")
    if not info then return nil end
    local b = {}
    b.speaker = to_u32(field(info, "<Speaker>k__BackingField"))
    b.listener = to_u32(field(info, "<Listener>k__BackingField"))
    b.speaker_name, b.listener_name = name_of(b.speaker), name_of(b.listener)
    local et = field(info, "<EventType>k__BackingField")
    b.event_type, b.event_type_name = et, enum_name("app.TalkEventDefine.EventType", et)
    local node = try(function() return info:get_field("<CurrentNode>k__BackingField") end)
    if type(node) ~= "userdata" then node = nil end
    return b, node
end

local function rift_context()
    local fm = singleton("app.FacilityManager")
    if not fm then return nil end
    local st = field(fm, "<DismissStateNow>k__BackingField")
    return {
        dismiss_state = st,
        dismiss_state_name = enum_name("app.FacilityManager.DismissState", st),
        dismiss_pawn = to_u32(field(fm, "<DismissPawnCharaId>k__BackingField")),
    }
end

-- GuiManager.TalkSelect (app.ui021601, the choice-list widget) or nil.
local function talk_select()
    local gm = singleton("app.GuiManager")
    local w = gm and try(function() return gm:get_field("TalkSelect") end)
    if type(w) == "userdata" then return w end
    return nil
end

local function dispmax_of(w)
    if w == nil then return nil end
    return to_u32(field(w, "DispMax"))
end

local function decode_choices(arr)
    local out = {}
    for i, ch in ipairs(elements(arr)) do
        local c = { index = i - 1 }
        local ok, err = pcall(function()
            c.ChoiceId = guid_str(ch:get_field("_ChoiceId"))
            c.Choice = field(ch, "_Choice")
            local cands = elements(try(function() return ch:get_field("_NextNodeCandidateOnSelect") end))
            c.next_count = #cands
            if cands[1] then
                c.next = {
                    id = field(cands[1], "_NextNodeId"), name = field(cands[1], "_NextNodeName"),
                    hash = field(cands[1], "_NextNodeNameHash"),
                }
            end
        end)
        if not ok then c.err = tostring(err) end
        out[#out + 1] = c
    end
    return out
end

local function decode_node(node)
    if node == nil then return nil end
    local r = {}
    r.class = try(function() return node:get_type_definition():get_full_name() end)
    r.NodeId, r.NodeName, r.NodeNameHash = field(node, "_NodeId"), field(node, "_NodeName"), field(node, "_NodeNameHash")
    r.NodeType = field(node, "_NodeType")
    r.NodeTypeName = enum_name("app.TalkEventSegmentNodeType", r.NodeType)
    if type(r.class) == "string" and r.class:find("PawnRentalNode", 1, true) then
        r.is_pawn_rental = true
        r.RentType = field(node, "_RentType")
        r.RentTypeName = enum_name("app.PawnRentalNode.DisplayType", r.RentType)
        local ts = try(function() return node:get_field("_RentType"):call("ToString") end)
        if type(ts) == "string" and not is_err(ts) then r.RentTypeToString = ts end
    end
    -- _Choices exists on PawnRentalNode and ChoiceSegmentNode; other classes just yield nothing.
    local arr = try(function() return node:get_field("_Choices") end)
    if type(arr) == "userdata" then r.choices = decode_choices(arr) end
    return r
end

local function decode_list(list)
    if list == nil then return nil, 0 end
    local n = try(function() return list:call("get_Count") end)
    if type(n) ~= "number" then return nil, 0 end
    local out = {}
    for i = 0, math.min(n, CHOICES_MAX) - 1 do
        local e = { index = i }
        local ok, err = pcall(function()
            local item = list:call("get_Item", i)
            if item == nil then e.nil_item = true; return end
            e.Msg = field(item, "Msg")
            e.IsDecideEnable = field(item, "_IsDecideEnable")
            local l = try(function() return item:get_field("Listener") end)
            if type(l) == "userdata" then
                e.listener_id = to_u32(try(function() return l:call("get_CharaId") end))
                e.listener_name = name_of(e.listener_id)
                e.listener_level = try(function() return l:call("get_Level") end)
                e.listener_official = try(function() return l:call("get_IsOfficialPawn") end)
                e.listener_slot = try(function() return guid_str(l:call("get_SlotId")) end)
            end
        end)
        if not ok then e.err = tostring(err) end
        out[#out + 1] = e
    end
    return out, n
end

local function brief_node(n)
    if not n then return nil end
    return { class = n.class, NodeName = n.NodeName, NodeId = n.NodeId, RentTypeName = n.RentTypeName,
        choices = n.choices and #n.choices or nil }
end

-- Menu snapshot. opts: { player = TalkEventPlayer object or nil, list = List<ListInfo> or nil }.
local function record_menu(source, opts)
    local m = { source = source, t = os.clock(), wall = wall(), seq = seq }
    local ti, ti_node = talk_info()
    m.talk = ti
    local node = opts.player and try(function() return opts.player:get_field("_CurrentNode") end)
    if type(node) ~= "userdata" then node = ti_node end
    m.node = decode_node(node)
    m.rift = rift_context()
    m.disp_max = dispmax_of(talk_select())
    m.marker = markers[#markers] and markers[#markers].label or nil
    m.list, m.list_count = nil, 0
    if opts.list then m.list, m.list_count = decode_list(opts.list) end
    for _, e in ipairs(m.list or {}) do
        if e.listener_id and is_hired_party_pawn(e.listener_id) then
            m.pawn_id, m.pawn_name = e.listener_id, e.listener_name
            break
        end
    end
    if ti then
        for _, id in ipairs({ ti.listener, ti.speaker }) do
            if is_hired_party_pawn(id) then m.pawn_from_talk = id; break end
        end
    end
    m.pawn_ctx = m.pawn_id ~= nil or (m.node ~= nil and m.node.is_pawn_rental == true)
    if #run.menus < MENU_CAP then
        run.menus[#run.menus + 1] = sanitize(m)
        m.idx = #run.menus
        dirty = true
    else
        run.dropped_menus = run.dropped_menus + 1
    end
    return m
end

-- ---------------------------------------------------------------------------------------------------------
-- Q2 mutations (every one fails closed: if anything is missing, the call is left alone)

local function set_msg(item, text)
    local ok = pcall(function() item:set_field("Msg", sdk.create_managed_string(text)) end)
    if not ok then ok = pcall(function() item.Msg = text end) end
    return ok
end

local function pick_pawn(idx)
    local m = last_menu
    local l = m and m.list and m.list[idx + 1]
    if l and l.listener_id and is_hired_party_pawn(l.listener_id) then return l.listener_id end
    local ti = talk_info()
    if ti then
        for _, id in ipairs({ ti.listener, ti.speaker }) do
            if is_hired_party_pawn(id) then return id end
        end
    end
    return m and (m.pawn_id or m.pawn_from_talk) or nil
end

-- Index a redirect to "Never mind" may use: set, not the picked one, and inside the known menu.
local function valid_nevermind(range, from_idx)
    if not nevermind or type(nevermind.index) ~= "number" then return nil end
    if nevermind.index < 0 or nevermind.index >= range or nevermind.index == from_idx then return nil end
    return nevermind.index
end

local function mutate_talk_select(list, m, fields)
    if toggles.relabel_rts and target and type(target.index) == "number" and m.pawn_ctx and target.index < m.list_count then
        local ok, err = pcall(function()
            local item = list:call("get_Item", target.index)
            local old = field(item, "Msg")
            local done = set_msg(item, label_text)
            add_event("relabel", { path = "requestTalkSelect", index = target.index, old = old, new = label_text,
                ok = done, pawn_id = m.pawn_id })
            fields.relabeled_rts = done
        end)
        if not ok then log_error("relabel_rts", err) end
    end
    if toggles.fifth and m.pawn_id and m.list_count > 0 then
        local ok, err = pcall(function()
            local tmpl
            for i = 0, m.list_count - 1 do
                local item = list:call("get_Item", i)
                if item ~= nil and type(try(function() return item:get_field("Listener") end)) == "userdata" then
                    tmpl = item
                    break
                end
            end
            if tmpl == nil then return end
            local newi = sdk.create_instance("app.ui021601.ListInfo")
            if newi == nil then return end
            pcall(function() newi:add_ref() end)
            pcall(function() newi:call(".ctor") end)
            newi:set_field("Listener", tmpl:get_field("Listener"))
            newi:set_field("ListenerType", tmpl:get_field("ListenerType"))
            newi:set_field("SpeakerType", tmpl:get_field("SpeakerType"))
            newi:set_field("_IsDecideEnable", true)
            set_msg(newi, label_text .. " (5th)")
            local pos = list:call("get_Count")
            list:call("Add", newi)
            fifth_state = { gen = menu_gen, pos = pos }
            m.appended_index = pos
            add_event("fifth_appended", { index = pos, count_after = list:call("get_Count"), pawn_id = m.pawn_id })
            fields.fifth_appended_at = pos
            if toggles.raise_dispmax then
                local want = math.tointeger(tonumber(dispmax_text))
                local w = talk_select()
                if want and w and not dispmax_state then
                    local old = dispmax_of(w)
                    w:set_field("DispMax", want)
                    dispmax_state = { old = old, new = want, t = os.clock(), saw_disp = false }
                    add_event("dispmax_raised", { old = old, new = want, read_back = dispmax_of(w) })
                elseif not w then
                    add_event("dispmax_skipped", { reason = "GuiManager.TalkSelect is nil at requestTalkSelect pre" })
                end
            end
        end)
        if not ok then
            fifth_state = nil
            log_error("fifth", err)
        end
    end
end

-- Does pick `idx` hit the Target row? Guid of the node's choice when both are known, else the index.
local function matches_target(idx, node)
    if not target then return false end
    local ch = node and node.choices and node.choices[idx + 1]
    if target.guid and ch and is_guid(ch.ChoiceId) then return ch.ChoiceId == target.guid end
    return target.index == idx
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook specs. pre(args, frame) / post(retval, frame) return the fields to log (or nil) and do any mutation;
-- `frame.log` says whether the entry will be logged, so a pre can skip expensive decoding.

local TE = "app.TalkEventPlayer"
local GM = "app.GuiManager"
local UI6 = "app.ui060601_01"

local function node_menu_post(source)
    return function(_, frame)
        local m = record_menu(source, { player = frame.player })
        local fields = { menu_index = m.idx, node = brief_node(m.node) }
        if menu_gen ~= frame.gen then
            fields.kept_last_menu = true -- a requestTalkSelect ran inside this call; its list is the better menu
        elseif m.node and m.node.choices and #m.node.choices > 0 then
            last_menu, menu_live = m, false
        end
        return fields
    end
end

local function nci_pre(has_string)
    return function(args, frame)
        frame.guid = arg_guid(args[3])
        local f = { guid = frame.guid }
        if frame.log then
            if has_string then
                f.string_arg = arg_string(args[4])
                f.flags = { arg_bool(args[5]), arg_bool(args[6]), arg_bool(args[7]) }
            else
                f.flags = { arg_bool(args[4]), arg_bool(args[5]), arg_bool(args[6]), arg_bool(args[7]) }
            end
        end
        return f
    end
end

local function nci_post(retval, frame)
    local f = { guid = frame.guid }
    local obj = to_managed(retval)
    if obj == nil then
        f.ret = "nil"
        return f
    end
    f.ret_msg = field(obj, "Msg")
    local l = try(function() return obj:get_field("Listener") end)
    if type(l) == "userdata" then f.ret_listener_id = to_u32(try(function() return l:call("get_CharaId") end)) end
    if toggles.relabel_nci and target and target.guid and is_guid(frame.guid) and frame.guid == target.guid
        and f.ret_listener_id ~= MAIN_ID then
        local old = f.ret_msg
        local ok = set_msg(obj, label_text)
        f.relabeled = ok
        add_event("relabel", { path = "newChoiceInfo", guid = frame.guid, old = old, new = label_text, ok = ok,
            listener_id = f.ret_listener_id })
    end
    return f
end

local function dialog_pre(kinds)
    return function(args, frame)
        local vals = {}
        for i, kind in ipairs(kinds) do
            local ok, v = pcall(function()
                local a = args[2 + i]
                if kind == "str" then return arg_string(a)
                elseif kind == "bool" then return arg_bool(a)
                elseif kind == "i32" then return arg_i32(a)
                elseif kind == "u32" then return arg_u32(a)
                elseif kind == "f32" then return arg_f32(a)
                else return arg_nonnull(a) end -- "tex": nil / non-nil
            end)
            vals[i] = ok and v or ("ERR: " .. tostring(v))
        end
        return vals
    end
end

local decode_dialog = dialog_pre(DIALOG_KINDS)
local decode_reqdisp = dialog_pre(REQDISP_KINDS)

-- app.GUIBase.CharaData -> plain table.
local function decode_chara_data(cd)
    if cd == nil or type(cd) ~= "userdata" then return nil end
    local d = {}
    d.CharaId = to_u32(field(cd, "<CharaId>k__BackingField"))
    d.IsMainPawn = field(cd, "<IsMainPawn>k__BackingField")
    d.IsOnline = field(cd, "<IsOnline>k__BackingField")
    d.IsOwner = field(cd, "<IsOwner>k__BackingField")
    local owner = try(function() return cd:get_field("CopyOwner") end)
    if type(owner) == "userdata" then
        d.OfflineID = try(function() return guid_str(owner:get_field("_OfflineID")) end)
        d.owner_name = field(owner, "_Name")
    end
    local nm = try(function() return m_name_cdata:call(nil, cd) end)
    if type(nm) == "userdata" then nm = str(nm) end
    d.name = nm
    if type(nm) == "string" and not is_err(nm) and type(d.CharaId) == "number" then names[d.CharaId] = nm end
    d.has_chara = type(try(function() return cd:get_field("_Chara") end)) == "userdata"
    d.hired_party_pawn = is_hired_party_pawn(d.CharaId)
    return d
end

-- State of a ui060601_01 page object: TabNow, IsPawn, IsStrayPawn and every PawnDataList entry.
local function read_status_page(page)
    local f = {}
    if page == nil then return f end
    f.TabNow = field(page, "TabNow")
    f.TabNowName = enum_name("app.ui060601_01.TabId", f.TabNow)
    f.IsPawn, f.IsStrayPawn = field(page, "IsPawn"), field(page, "IsStrayPawn")
    local list = {}
    for _, cd in ipairs(elements(try(function() return page:get_field("PawnDataList") end))) do
        list[#list + 1] = decode_chara_data(cd) or "nil"
    end
    f.PawnDataList = list
    status_page = { t = os.clock(), wall = wall(), TabNow = f.TabNow, TabNowName = f.TabNowName, IsPawn = f.IsPawn,
        IsStrayPawn = f.IsStrayPawn, list = list }
    return f
end

local SPECS = {
    -- Q1/Q2: the talk flow
    { key = "TalkEventPlayer.startNode", type = TE, sig = "startNode()", use_post = true,
      pre = function(args, frame) frame.gen, frame.player = menu_gen, to_managed(args[2]) end,
      post = node_menu_post("startNode") },
    { key = "TalkEventPlayer.startPawnRentalNode", type = TE, sig = "startPawnRentalNode()", use_post = true,
      pre = function(args, frame) frame.gen, frame.player = menu_gen, to_managed(args[2]) end,
      post = node_menu_post("startPawnRentalNode") },
    { key = "TalkEventPlayer.updatePawnRentalNode", type = TE, sig = "updatePawnRentalNode()", chatty = true },
    { key = "TalkEventPlayer.startChoiceNode", type = TE, sig = "startChoiceNode()", use_post = true,
      pre = function(args, frame) frame.player = to_managed(args[2]) end,
      post = function(_, frame)
          if not frame.log then return nil end
          local _, node = talk_info()
          local n = frame.player and try(function() return frame.player:get_field("_CurrentNode") end)
          if type(n) ~= "userdata" then n = node end
          return { node = brief_node(decode_node(n)) }
      end },
    { key = "TalkEventPlayer.nextNode(Int32)", type = TE, sig = "nextNode(System.Int32)",
      pre = function(args, frame)
          local idx = arg_i32(args[3])
          local f = { index = idx }
          local player = to_managed(args[2])
          local _, ti_node = talk_info()
          local node_obj = player and try(function() return player:get_field("_CurrentNode") end)
          if type(node_obj) ~= "userdata" then node_obj = ti_node end
          local node = decode_node(node_obj)
          local choice = node and node.choices and node.choices[idx + 1]
          local lm = last_menu
          local entry = lm and lm.list and lm.list[idx + 1]
          if frame.log then
              f.node = brief_node(node)
              f.choice = choice
              f.menu = lm and { idx = lm.idx, source = lm.source, live = menu_live, list_count = lm.list_count,
                  list_entry = entry } or nil
              f.fifth = fifth_state and { gen = fifth_state.gen, pos = fifth_state.pos, current_gen = menu_gen } or nil
          end
          local new_idx, why
          -- fifth entry: its index must never reach the game; send it to Never mind, else the last original entry
          if fifth_state and fifth_state.gen == menu_gen and idx >= fifth_state.pos then
              local nm = valid_nevermind(fifth_state.pos, idx)
              new_idx, why = nm or (fifth_state.pos - 1), "picked_fifth"
              add_event("picked_fifth", { index = idx, redirect_to = new_idx, never_mind_set = nm ~= nil })
          elseif toggles.catch_pick or toggles.redirect then
              if matches_target(idx, node) then
                  local pid = pick_pawn(idx)
                  local pname = name_of(pid)
                  if toggles.catch_pick then
                      add_event("picked", { index = idx, pawn_id = pid, pawn_name = pname, choice = choice and choice.Choice,
                          choice_id = choice and choice.ChoiceId, msg = entry and entry.Msg,
                          node_class = node and node.class, redirect_on = toggles.redirect })
                      notice = { text = string.format("%s picked for %s %s", string.upper(label_text),
                          tostring(pname or "?"), tostring(pid or "?")), t = os.clock() }
                  end
                  if toggles.redirect then
                      local range = math.max(node and node.choices and #node.choices or 0,
                          (menu_live and lm and lm.list_count) or 0)
                      local pawn_ctx = (node and node.is_pawn_rental) or (menu_live and lm and lm.pawn_id ~= nil)
                      local nm = valid_nevermind(range, idx)
                      if nm and pawn_ctx and pid ~= MAIN_ID then
                          new_idx, why = nm, "target_to_nevermind"
                      else
                          add_event("redirect_skipped", { index = idx, never_mind = nevermind and nevermind.index,
                              range = range, pawn_ctx = pawn_ctx and true or false })
                      end
                  end
              end
          end
          if new_idx and new_idx ~= idx then
              args[3] = sdk.to_ptr(new_idx)
              add_event("redirect", { reason = why, original = idx, new = new_idx })
              f.override = { original = idx, new = new_idx, reason = why }
          end
          -- the menu is consumed by this pick. fifth_state is kept until the next menu (gen check) unless this call
          -- was the fifth pick: an unrelated nextNode(0) between the menu and the real pick must not clear it, or the
          -- appended index would reach the game.
          menu_live = false
          if why == "picked_fifth" then fifth_state = nil end
          return f
      end },
    { key = "TalkEventPlayer.checkNextCandidate(Int32)", type = TE, sig = "checkNextCandidate(System.Int32)", use_post = true,
      pre = function(args, frame)
          local idx = arg_i32(args[3])
          local f = { index = idx }
          -- a preview of the appended fifth index would read past _Choices: keep it vanilla
          if fifth_state and fifth_state.gen == menu_gen and idx >= fifth_state.pos then
              local new_idx = valid_nevermind(fifth_state.pos, idx) or (fifth_state.pos - 1)
              args[3] = sdk.to_ptr(new_idx)
              f.override = { original = idx, new = new_idx, reason = "fifth_preview" }
          end
          return f
      end,
      post = function(retval, frame)
          if not frame.log then return nil end
          local c = to_managed(retval)
          if c == nil then return { ret = "nil" } end
          return { ret = { id = field(c, "_NextNodeId"), name = field(c, "_NextNodeName"),
              hash = field(c, "_NextNodeNameHash") } }
      end },
    { key = "TalkEventPlayer.newChoiceInfo(Guid,Boolean x4)", type = TE,
      sig = "newChoiceInfo(System.Guid, System.Boolean, System.Boolean, System.Boolean, System.Boolean)",
      use_post = true, pre = nci_pre(false), post = nci_post },
    { key = "TalkEventPlayer.newChoiceInfo(Guid,String,Boolean x3)", type = TE,
      sig = "newChoiceInfo(System.Guid, System.String, System.Boolean, System.Boolean, System.Boolean)",
      use_post = true, pre = nci_pre(true), post = nci_post },
    { key = "GuiManager.requestTalkSelect", type = GM,
      sig = "requestTalkSelect(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, "
          .. "via.gui.GenderType, via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)",
      pre = function(args, frame)
          local list = to_managed(args[3])
          local f = {}
          if frame.log then
              f.flags = { arg_bool(args[4]), arg_bool(args[7]), arg_bool(args[8]) }
              f.gender = { arg_i32(args[5]), arg_i32(args[6]) }
              f.int_arg = arg_i32(args[9])
          end
          -- the snapshot is taken BEFORE any mutation, so it shows what vanilla built
          local m = record_menu("requestTalkSelect", { list = list, player = nil })
          menu_gen = menu_gen + 1
          last_menu, menu_live, fifth_state = m, true, nil
          f.menu_index = m.idx
          f.list_count = m.list_count
          f.pawn_id = m.pawn_id
          if list ~= nil then mutate_talk_select(list, m, f) end
          return f
      end },
    { key = "ui021601.reqDisp", type = "app.ui021601",
      sig = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
          .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)",
      pre = function(args, frame)
          if not frame.log then return nil end
          local list = to_managed(args[3])
          local n = list and try(function() return list:call("get_Count") end) or "nil"
          return { list_count = n, disp_max = dispmax_of(to_managed(args[2])), dispmax_raised = dispmax_state ~= nil }
      end },
    { key = "FacilityManager.startDismiss", type = "app.FacilityManager", sig = "startDismiss(via.GameObject)",
      pre = function(args, frame)
          local f = { rift = rift_context() }
          local go = to_managed(args[3])
          f.game_object = go and try(function() return go:call("get_Name") end) or "nil"
          return f
      end },

    -- Q3: native dialog (log-only)
    { key = "GuiManager.requestDialog(String)", type = GM,
      sig = "requestDialog(System.String, System.String, System.String, System.String, System.String, System.Boolean, "
          .. "System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, "
          .. "via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, System.Boolean, "
          .. "System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)",
      pre = function(args, frame)
          local vals = decode_dialog(args)
          if not in_self_call then
              captured_dialog_args = { vals = vals, wall = wall(), t = os.clock() }
              captured_tex = nil
              if vals[12] == true then captured_tex = try(function() return to_managed(args[14]) end) end
          end
          return { self_call = in_self_call or nil, args = vals }
      end },
    { key = "ui010101.reqDisp", type = "app.ui010101",
      sig = "reqDisp(System.String, System.String, System.String, System.String, System.String, System.Boolean, "
          .. "System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, "
          .. "via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, System.Boolean, "
          .. "System.Boolean, System.Boolean, System.Boolean, System.Single, System.Boolean, System.Boolean, "
          .. "System.Boolean, System.Boolean)",
      pre = function(args, frame)
          if not frame.log then return nil end
          return { self_call = in_self_call or nil, args = decode_reqdisp(args) }
      end },

    -- Q4: Status page (log-only)
    { key = "ui060601_01.setupPawn", type = UI6, sig = "setupPawn(app.GUIBase.CharaData)",
      pre = function(args, frame)
          local d = decode_chara_data(to_managed(args[3]))
          if d then
              status_pawn = { id = d.CharaId, name = d.name, hired = d.hired_party_pawn, is_main = d.IsMainPawn,
                  t = os.clock(), wall = wall() }
          end
          return { chara_data = d or "nil" }
      end },
    { key = "ui060601_01.setPawnData", type = UI6, sig = "setPawnData(app.GUIBase.CharaData[])",
      pre = function(args, frame)
          if not frame.log then return nil end
          local list = {}
          for _, cd in ipairs(elements(to_managed(args[3]))) do list[#list + 1] = decode_chara_data(cd) or "nil" end
          return { pawn_data = list }
      end },
    { key = "ui060601_01.partyListCtrlSelectionChangedIsPC", type = UI6, sig = "partyListCtrlSelectionChangedIsPC()",
      use_post = true,
      pre = function(args, frame)
          frame.page = to_managed(args[2])
          return read_status_page(frame.page)
      end,
      post = function(_, frame) return read_status_page(frame.page) end },
    { key = "ui060601_01.setTabId", type = UI6, sig = "setTabId(app.ui060601_01.TabId, System.Boolean)", use_post = true,
      pre = function(args, frame)
          frame.page = to_managed(args[2])
          local tab = arg_i32(args[3])
          local f = read_status_page(frame.page)
          f.arg_tab, f.arg_tab_name, f.arg_flag = tab, enum_name("app.ui060601_01.TabId", tab), arg_bool(args[4])
          return f
      end,
      post = function(_, frame) return read_status_page(frame.page) end },
}

-- Caps: the talk-menu hooks and the dialog hooks are the ones that matter most.
local IMPORTANT = {
    ["TalkEventPlayer.startPawnRentalNode"] = true, ["TalkEventPlayer.startChoiceNode"] = true,
    ["TalkEventPlayer.nextNode(Int32)"] = true, ["GuiManager.requestTalkSelect"] = true,
    ["ui021601.reqDisp"] = true,
    ["TalkEventPlayer.newChoiceInfo(Guid,Boolean x4)"] = true,
    ["TalkEventPlayer.newChoiceInfo(Guid,String,Boolean x3)"] = true,
    ["GuiManager.requestDialog(String)"] = true, ["FacilityManager.startDismiss"] = true,
    ["ui060601_01.setupPawn"] = true, ["ui060601_01.setTabId"] = true,
    ["ui060601_01.partyListCtrlSelectionChangedIsPC"] = true,
}
for _, spec in ipairs(SPECS) do
    spec.cap = spec.chatty and CHATTY_SPEC_CAP or (IMPORTANT[spec.key] and IMPORTANT_SPEC_CAP or DEFAULT_SPEC_CAP)
end

local function pre_body(spec, args)
    local c = run.count_by_spec[spec.key]
    if not c then c = { pre = 0, post = 0 }; run.count_by_spec[spec.key] = c end
    c.pre = c.pre + 1
    local frame = { spec = spec, seq = next_seq() }
    local n = logged_by_spec[spec.key] or 0
    if #calls >= CALL_CAP then
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
            local td = sdk.find_type_definition(spec.type)
            if not td then error("type not found: " .. spec.type) end
            local m = find_method(td, spec.sig)
            if not m then error("method not found: " .. spec.sig) end
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
-- Q3: open the native dialog (queued by the UI, run in the update callback) and poll its answer

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
    return s
end

local function dialog_key(s) return table.concat({ tostring(s.state), tostring(s.raw), tostring(s.disp), tostring(s.wait) }, "|") end

local function end_poll(reason)
    local p = dialog_poll
    if not p or p.done then return end
    p.done = true
    add_event("dialog_poll_end", { reason = reason, elapsed = os.clock() - p.start, final = dialog_live })
end

local function start_poll(mode)
    end_poll("replaced by a new dialog request")
    dialog_poll = { start = os.clock(), mode = mode, last_key = nil, saw_result = false, saw_disp = false, done = false }
    add_event("dialog_poll_start", { mode = mode })
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
            raw_name = s.raw_name, disp = s.disp, wait = s.wait })
    end
    if s.disp == true then p.saw_disp = true end
    if s.state_name and s.state_name ~= "None" then p.saw_result = true end
    if p.saw_result and s.disp ~= true then
        end_poll("answer seen and dialog closed")
    elseif os.clock() - p.start >= DIALOG_POLL_SECONDS then
        end_poll("timeout")
    end
end

local function open_dialog(mode)
    local entry = { mode = mode, kind = "open_dialog" }
    local ok, err = pcall(function()
        local gm = singleton("app.GuiManager")
        if not gm then error("GuiManager not available") end
        if not m_request_dialog then error("requestDialog(String ...) not found") end
        local cap = captured_dialog_args and captured_dialog_args.vals
        if mode == "captured" and not cap then error("no captured requestDialog call yet") end
        local a, shown = {}, {}
        local texts = { dlg.main, dlg.sel0, dlg.sel1, dlg.sel2, dlg.sel3 }
        for i = 1, 5 do
            a[i] = sdk.create_managed_string(texts[i])
            shown[i] = texts[i]
        end
        for i = 6, 21 do
            local v
            if DIALOG_KINDS[i] == "tex" then
                if mode == "captured" and dlg.use_tex then v = captured_tex end
            elseif mode == "captured" and cap[i] ~= nil and not is_err(cap[i]) then
                v = cap[i]
            else
                v = DIALOG_GUESS[i]
            end
            a[i] = v
            shown[i] = v == nil and "nil" or (type(v) == "userdata" and "<object>" or v)
        end
        entry.args = shown
        in_self_call = true
        local ok_call, res = pcall(function() return m_request_dialog:call(gm, table.unpack(a, 1, 21)) end)
        in_self_call = false
        if not ok_call then error(res) end
        entry.result = (res == nil or type(res) == "userdata") and "void" or str(res)
    end)
    in_self_call = false
    entry.ok = ok
    if not ok then entry.error = tostring(err) end
    add_event("dialog_open", entry)
    if ok then start_poll(mode) end
end

-- ---------------------------------------------------------------------------------------------------------
-- Update-thread work: queued UI actions, once-a-second refresh, dialog poll, flush

-- Puts DispMax back once the talk select has been shown and is over (or after 30 s without ever showing).
local function restore_dispmax(reason)
    local st = dispmax_state
    if not st then return end
    dispmax_state = nil
    local ok, err = pcall(function()
        local w = talk_select()
        if w and st.old ~= nil and type(st.old) == "number" then
            w:set_field("DispMax", st.old)
            add_event("dispmax_restored", { reason = reason, value = st.old, read_back = dispmax_of(w) })
        else
            add_event("dispmax_restore_failed", { reason = reason, widget = w ~= nil, old = st.old })
        end
    end)
    if not ok then log_error("restore_dispmax", err) end
end

local function check_dispmax()
    local st = dispmax_state
    if not st then return end
    local gm = singleton("app.GuiManager")
    if not gm then return end
    local disp = try(function() return gm:call("isDispTalkSelect") end)
    local ended = try(function() return gm:call("isEndTalkSelect") end)
    if disp == true then st.saw_disp = true end
    if st.saw_disp and (ended == true or disp == false) then
        restore_dispmax("talk select over")
    elseif os.clock() - st.t > 30 then
        restore_dispmax("timeout, never seen displayed")
    end
end

local function refresh()
    local ok, err = pcall(function()
        local list = party_entries()
        party_cache = list
        if status_pawn and status_pawn.id then status_pawn.in_party_now = is_hired_party_pawn(status_pawn.id) end
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
        out.settings_now = sanitize({ toggles = toggles, label = label_text, target = target or "none",
            never_mind = nevermind or "none" })
        out.captured_dialog_args = sanitize(captured_dialog_args or "none")
        out.status_page_last = sanitize(status_page or "none")
        out.summary = {
            calls_logged = #calls, calls_dropped = run.dropped, menus = #run.menus, dropped_menus = run.dropped_menus,
            events = #run.events, dropped_events = run.dropped_events, markers = #run.markers, errors = #run.errors,
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
    local ok, err = pcall(poll_dialog)
    if not ok then log_error("poll_dialog", err) end
    ok, err = pcall(check_dispmax)
    if not ok then log_error("check_dispmax", err) end
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
    re.on_script_reset(function()
        pcall(restore_dispmax, "script reset")
        pcall(flush)
    end)
end

-- ---------------------------------------------------------------------------------------------------------
-- UI (draws cached data and sets flags / queues work; makes no game calls)

local function fmt_entry(e)
    local parts = { string.format("#%d t=%.1f %s %s", e.seq, e.t, e.method, e.phase or "") }
    if e.args and e.args[1] ~= nil and type(e.args[1]) == "string" then parts[#parts + 1] = "a1=" .. e.args[1]:sub(1, 40) end
    if e.index ~= nil then parts[#parts + 1] = "index=" .. tostring(e.index) end
    if e.override then parts[#parts + 1] = "OVERRIDE" end
    return table.concat(parts, " ")
end

-- imgui.radio_button(label, current, value) -> changed, new (REFramework); tolerate a single-return variant.
local function radio(lbl, current, value)
    local r1, r2 = imgui.radio_button(lbl, current, value)
    if r1 == true then return true end
    if type(r1) == "number" and r1 == value and current ~= value then return true end
    return false
end

local function menu_rows(m)
    local rows = {}
    if not m then return rows end
    local choices = m.node and type(m.node.choices) == "table" and m.node.choices or {}
    local list = type(m.list) == "table" and m.list or {}
    for i = 1, math.max(#choices, #list) do
        local c, l = choices[i], list[i]
        rows[i] = { index = i - 1, guid = c and is_guid(c.ChoiceId) and c.ChoiceId or nil, choice = c and c.Choice,
            msg = l and l.Msg, listener_id = l and l.listener_id, listener_name = l and l.listener_name,
            next_name = c and c.next and c.next.name }
    end
    return rows
end

local function draw_toggle(key, text)
    local ch, v = imgui.checkbox(text, toggles[key])
    if ch then
        toggles[key] = v
        queue_work(function() add_event("toggle", { name = key, value = v }) end)
    end
end

local function row_ref(row)
    return { index = row.index, guid = row.guid, choice = row.choice, msg = row.msg }
end

local function draw_menu_table()
    local m = last_menu
    if not m then
        imgui.text("No menu seen yet: talk to a hired party pawn.")
        return
    end
    local n = m.node
    imgui.text(string.format("last menu: %s at %s%s  node=%s %s [%s]  rent=%s  pawn=%s", m.source, m.wall,
        m.marker and (" marker=" .. tostring(m.marker)) or "", tostring(n and n.class), tostring(n and n.NodeName),
        tostring(n and n.NodeTypeName), tostring(n and (n.RentTypeName or n.RentType)),
        tostring(m.pawn_id or m.pawn_from_talk or "none")))
    if m.rift then
        imgui.text(string.format("DispMax at snapshot: %s", tostring(m.disp_max)))
        imgui.text(string.format("rift: dismiss state=%s pawn=%s   talk: speaker=%s listener=%s event=%s",
            tostring(m.rift.dismiss_state_name or m.rift.dismiss_state), tostring(m.rift.dismiss_pawn),
            m.talk and tostring(m.talk.speaker) or "?", m.talk and tostring(m.talk.listener) or "?",
            m.talk and tostring(m.talk.event_type_name or m.talk.event_type) or "?"))
    end
    local rows = menu_rows(m)
    if #rows == 0 then imgui.text("(the menu has no choices and no list entries)") end
    local t_idx, n_idx = target and target.index or -1, nevermind and nevermind.index or -1
    for _, row in ipairs(rows) do
        if radio("Target##t" .. row.index, t_idx, row.index) then
            local ref = row_ref(row)
            target = ref
            queue_work(function() add_event("set_target", ref) end)
        end
        imgui.same_line()
        if radio("Never-mind##n" .. row.index, n_idx, row.index) then
            local ref = row_ref(row)
            nevermind = ref
            queue_work(function() add_event("set_nevermind", ref) end)
        end
        imgui.same_line()
        imgui.text(string.format("%d  msg=%s  choice=%s  id=%s  next=%s  pawn=%s", row.index, tostring(row.msg),
            tostring(row.choice), tostring(row.guid and row.guid:sub(1, 8) or "-"), tostring(row.next_name),
            tostring(row.listener_id and (tostring(row.listener_name or "?") .. " " .. row.listener_id) or "-")))
    end
    imgui.text(string.format("Target: %s   Never-mind: %s",
        target and string.format("index %s, id %s", tostring(target.index), tostring(target.guid or "none")) or "none",
        nevermind and string.format("index %s", tostring(nevermind.index)) or "none"))
end

local function draw_q2()
    imgui.text("Q2 mutates the talk menu. All off at load. Back up first; redirect / fifth entry can end a talk oddly.")
    local ch, v = imgui.input_text("Label", label_text)
    if ch then
        label_text = v
        queue_work(function() add_event("label", { label = v }) end)
    end
    draw_toggle("relabel_nci", "Relabel (newChoiceInfo, by Guid)")
    draw_toggle("relabel_rts", "Relabel (requestTalkSelect, by index)")
    draw_toggle("catch_pick", "Catch pick (nextNode)")
    draw_toggle("redirect", "Redirect target pick to Never-mind")
    draw_toggle("fifth", "Append fifth entry (requestTalkSelect)")
    draw_toggle("raise_dispmax", "Raise DispMax (with the fifth entry; restored when the talk select ends)")
    local cd, vd = imgui.input_text("DispMax value", dispmax_text)
    if cd then dispmax_text = vd end
    if dispmax_state then
        imgui.text(string.format("DispMax raised: %s -> %s (restored when the talk select ends)",
            tostring(dispmax_state.old), tostring(dispmax_state.new)))
    end
    draw_menu_table()
end

local function draw_q3()
    imgui.text("Q3 calls GuiManager.requestDialog from here. Trigger any yes/no game dialog first to capture its args.")
    local c1, v1 = imgui.input_text("Main text", dlg.main)
    if c1 then dlg.main = v1 end
    local c2, v2 = imgui.input_text("sel0", dlg.sel0)
    if c2 then dlg.sel0 = v2 end
    local c3, v3 = imgui.input_text("sel1", dlg.sel1)
    if c3 then dlg.sel1 = v3 end
    local c4, v4 = imgui.input_text("sel2", dlg.sel2)
    if c4 then dlg.sel2 = v4 end
    local c5, v5 = imgui.input_text("sel3", dlg.sel3)
    if c5 then dlg.sel3 = v5 end
    if imgui.button("Open test dialog (defaults)") then queue_work(function() open_dialog("defaults") end) end
    if captured_dialog_args then
        imgui.text("Captured a game requestDialog at " .. captured_dialog_args.wall)
        local cu, vu = imgui.checkbox("Pass the captured texture holder object", dlg.use_tex)
        if cu then dlg.use_tex = vu end
        if imgui.button("Open with captured args") then queue_work(function() open_dialog("captured") end) end
    else
        imgui.text("Open with captured args: disabled until a game requestDialog is captured (e.g. Return to Title).")
    end
    local s = dialog_live
    if s then
        imgui.text(string.format("state=%s (%s)  raw=%s (%s)  displayed=%s  waiting=%s", tostring(s.state),
            tostring(s.state_name), tostring(s.raw), tostring(s.raw_name), tostring(s.disp), tostring(s.wait)))
    end
    local p = dialog_poll
    if p then
        imgui.text(string.format("poll (%s): %s", p.mode, p.done and "finished" or
            string.format("running, %.0f s left", DIALOG_POLL_SECONDS - (os.clock() - p.start))))
    end
end

local function draw_q4()
    if status_pawn then
        imgui.text(string.format("current Status pawn (last setupPawn): %s  id=%s  hired party pawn=%s  main=%s  (%s)",
            tostring(status_pawn.name), tostring(status_pawn.id), tostring(status_pawn.hired),
            tostring(status_pawn.is_main), status_pawn.wall))
    else
        imgui.text("No setupPawn seen yet: open pause > Status.")
    end
    if status_page then
        imgui.text(string.format("last page read (%s): TabNow=%s IsPawn=%s IsStrayPawn=%s PawnDataList=%d entries",
            status_page.wall, tostring(status_page.TabNowName or status_page.TabNow), tostring(status_page.IsPawn),
            tostring(status_page.IsStrayPawn), #status_page.list))
        for i, d in ipairs(status_page.list) do
            if type(d) == "table" then
                imgui.text(string.format("  [%d] %s id=%s main=%s online=%s owner=%s hired=%s", i - 1, tostring(d.name),
                    tostring(d.CharaId), tostring(d.IsMainPawn), tostring(d.IsOnline), tostring(d.IsOwner),
                    tostring(d.hired_party_pawn)))
            end
        end
    end
end

local function draw_body()
    imgui.text("Hooks log the talk menu, dialogs and the Status page. Q2 toggles and Q3 buttons change game state.")
    imgui.text(hook_status)
    imgui.text("Run file: reframework/data/" .. RUN_FILE)
    local seen = 0
    for _, c in pairs(run.count_by_spec) do seen = seen + c.pre + c.post end
    imgui.text(string.format("Calls: %d logged, %d dropped, %d seen | menus %d | events %d | markers %d | errors %d",
        #calls, run.dropped, seen, #run.menus, #run.events, #run.markers, #run.errors))
    imgui.text(flush_status)
    if notice then imgui.text(string.format("%s  (%.0f s ago)", notice.text, os.clock() - notice.t)) end

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

    if #party_cache > 0 then
        local parts = {}
        for _, e in ipairs(party_cache) do parts[#parts + 1] = string.format("%d:%s(%s)", e.slot, tostring(e.name or "?"), e.id) end
        imgui.text("Party: " .. table.concat(parts, "  "))
    end

    if imgui.tree_node("Q1/Q2 talk menu") then
        local ok, err = pcall(draw_q2)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Q3 native dialog") then
        local ok, err = pcall(draw_q3)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Q4 Status page") then
        local ok, err = pcall(draw_q4)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
    if imgui.tree_node("Recent events") then
        for i = math.max(1, #run.events - 7), #run.events do
            local e = run.events[i]
            imgui.text(string.format("#%d t=%.1f %s %s", e.seq, e.t, e.kind, tostring(e.path or e.reason or e.name or e.index or "")))
        end
        imgui.tree_pop()
    end

    for i = math.max(1, #calls - LOG_LINES + 1), #calls do imgui.text(fmt_entry(calls[i])) end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Talk UI (EXPERIMENT)") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
