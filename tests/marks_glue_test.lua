-- game/marks.lua against a fake sdk and log: the two hook groups' lookups (a missing member leaves only that group
-- uninstalled), the Status marks (setupPawn, PawnInfo2Ref.setup, CharaChangeRef.updateName), the Previous Hires marks
-- (ResItem.updateDisp), idempotence, and the failure paths (a throwing set_Message, an unreadable CharaData).
local logs, reports, hooked = {}, {}, {}
local world
local missing_name

local SETUP_PAWN = "setupPawn(app.GUIBase.CharaData)"
local PAWN_INFO_SETUP = "setup(app.GUIBase.CharaData)"
local UPDATE_NAME = "updateName()"
local SELECTED = "get_SelectedCharaData()"
local UPDATE_DISP = "updateDisp(app.ui041401.ResInfo)"
local GET_MESSAGE = "get_Message()"
local SET_MESSAGE = "set_Message(System.String)"
local IS_MAIN = "<IsMainPawn>k__BackingField"

-- type name -> { methods = {sig}, fields = {name} }
local TYPES = {
    ["app.ui060601_01"] = { methods = { SETUP_PAWN }, fields = { "PawnInfo", "CharaTab" } },
    ["app.GUIBase.PawnInfo2Ref"] = { methods = { PAWN_INFO_SETUP }, fields = { "TxtName" } },
    ["app.GUIBase.CharaChangeRef"] = { methods = { UPDATE_NAME, SELECTED }, fields = { "TxtName" } },
    ["app.GUIBase.CharaData"] = { methods = {}, fields = { "CopyOwner", IS_MAIN } },
    ["app.PawnOwnerContext"] = { methods = {}, fields = { "_OfflineID" } },
    ["app.ui041401.ResItem"] = { methods = { UPDATE_DISP }, fields = { "TxtPawnName" } },
    ["app.ui041401.ResInfo"] = { methods = {}, fields = { "OfflineId" } },
    ["via.gui.Text"] = { methods = { GET_MESSAGE, SET_MESSAGE }, fields = {} },
}
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

-- missing_name hides a type, a method signature or a field name (a name shared by two types hides in both)
sdk = {
    PreHookResult = { CALL_ORIGINAL = "CO" },
    find_type_definition = function(name)
        local t = TYPES[name]
        if not t or name == missing_name then return nil end
        local methods, fields = set(t.methods), set(t.fields)
        return {
            get_method = function(_, sig)
                if sig == missing_name or not methods[sig] then return nil end
                return { sig = sig }
            end,
            get_methods = function() return {} end,
            get_field = function(_, field)
                if field == missing_name or not fields[field] then return nil end
                return {}
            end,
        }
    end,
    hook = function(m, pre, post) hooked[#hooked + 1] = { m = m, pre = pre, post = post } end,
    to_int64 = function(a) return a end,
    to_managed_object = function(a) return world.by_addr[a] end,
}
log = { error = function(text) logs[#logs + 1] = text end }

local marks_glue = require("Retinue.game.marks")
local roster = require("Retinue.roster")
-- the real errlog (new at each reset): a distinct failure is logged once
local errlog = require("Retinue.errlog")
local report

local PRESENT_ID = "aaaaaaaa-0000-0000-0000-000000000001"
local AWAY_ID = "bbbbbbbb-0000-0000-0000-000000000002"
local OTHER_ID = "cccccccc-0000-0000-0000-000000000003"
local ROSTER = { mode = roster.OK, warnings = {}, members = {
    { offline_id = PRESENT_ID, name = "Ana", status = roster.PRESENT },
    { offline_id = AWAY_ID, name = "Bo", status = roster.AWAY },
} }

local function obj(props)
    local o = {}
    function o:get_field(name) return props[name] end
    function o:call(method, ...)
        local v = props[method]
        if type(v) == "function" then return v(o, ...) end
        return v
    end
    function o:get_elements() return props.elements end
    return o
end

-- A via.gui.Text: get_Message / set_Message over `msg`; writes counts the set_Message calls, fail makes them throw.
local function text(msg)
    local t = { msg = msg, writes = 0, fail = false }
    t.widget = obj({
        get_Message = function() return t.msg end,
        set_Message = function(_, v)
            if t.fail then error("set boom") end
            t.msg = v
            t.writes = t.writes + 1
        end,
    })
    return t
end

local function chara_data(offline_id, is_main)
    return obj({ CopyOwner = obj({ _OfflineID = offline_id }), [IS_MAIN] = is_main })
end

-- addresses: 100 = status page, 101 = PawnInfo2Ref, 102 = CharaChangeRef, 103 = CharaData, 104 = ResItem, 105 = ResInfo
-- reset(): the roster above; reset("none"): a store with no roster (roster = nil)
local function reset(which)
    logs, reports, hooked = {}, {}, {}
    report = errlog.new(function(msg) reports[#reports + 1] = msg end)
    world = { by_addr = {}, store = { roster = (which ~= "none") and ROSTER or nil } }
end

local function hook_for(sig)
    for _, h in ipairs(hooked) do if h.m.sig == sig then return h end end
    error("no hook for " .. sig)
end

local function fire(sig, ...)
    local h = hook_for(sig)
    h.pre({ 0, ... })
    h.post(nil)
end

local function has_log(s)
    for _, l in ipairs(logs) do if l:find(s, 1, true) then return true end end
    return false
end

local function count_log(s)
    local n = 0
    for _, l in ipairs(logs) do if l:find(s, 1, true) then n = n + 1 end end
    return n
end

local function make(backups)
    return marks_glue.new(function(...) return report(...) end, { store = world.store, backups = backups })
end

-- The Status scene: a page with PawnInfo and CharaTab, each with its TxtName.
local function status_scene(msg)
    local info_text, tab_text = text(msg), text(msg)
    world.by_addr[100] = obj({ PawnInfo = obj({ TxtName = info_text.widget }), CharaTab = obj({ TxtName = tab_text.widget }) })
    world.by_addr[101] = obj({ TxtName = info_text.widget })
    return info_text, tab_text
end

-- everything present: both groups available, four hooks, nothing reported
do
    reset()
    local m = make()
    assert(m.status_available and m.rift_available and #m.missing == 0 and #hooked == 4 and #reports == 0)
end

-- the lookups: every type, method and field in turn missing
do
    local status_types = { ["app.ui060601_01"] = true, ["app.GUIBase.PawnInfo2Ref"] = true, ["app.GUIBase.CharaChangeRef"] = true,
        ["app.GUIBase.CharaData"] = true, ["app.PawnOwnerContext"] = true }
    local rift_types = { ["app.ui041401.ResItem"] = true, ["app.ui041401.ResInfo"] = true }
    local cases = {}
    for type_name, t in pairs(TYPES) do
        cases[#cases + 1] = { name = type_name, type = type_name }
        for _, sig in ipairs(t.methods) do cases[#cases + 1] = { name = sig, type = type_name } end
        for _, f in ipairs(t.fields) do cases[#cases + 1] = { name = f, type = type_name } end
    end
    assert(#cases == 8 + 7 + 9) -- 8 types, 7 methods, 9 fields
    for _, c in ipairs(cases) do
        reset()
        missing_name = c.name
        local m = make()
        missing_name = nil
        local shared = c.type == "via.gui.Text"
        local status_hit = shared or status_types[c.type]
        local rift_hit = shared or rift_types[c.type]
        assert(m.status_available == not status_hit, c.name)
        assert(m.rift_available == not rift_hit, c.name)
        assert(#hooked == (status_hit and 0 or 3) + (rift_hit and 0 or 1), c.name)
        assert(#m.missing >= 1, c.name)
        local named = false
        for _, n in ipairs(m.missing) do if n:find(c.name, 1, true) then named = true end end
        assert(named, c.name)
        for i, n in ipairs(m.missing) do -- every name once
            for j = i + 1, #m.missing do assert(m.missing[j] ~= n, c.name) end
        end
        local reported = 0
        for _, r in ipairs(reports) do
            if r:find("unavailable, not found (game update?)", 1, true) then reported = reported + 1 end
        end
        assert(reported == (status_hit and 1 or 0) + (rift_hit and 1 or 0), c.name)
    end
end

-- a hook that cannot be installed leaves its group unavailable and listed
do
    reset()
    local real = sdk.hook
    local n = 0
    sdk.hook = function(...) n = n + 1; if n == 2 then error("hook boom") end return real(...) end
    local m = make()
    sdk.hook = real
    assert(not m.status_available and #m.missing >= 1)
end

-- A hook that is live although its group is unavailable (sdk.hook throwing after earlier hooks went in) does nothing
do
    reset()
    local real = sdk.hook
    local n = 0
    sdk.hook = function(...) n = n + 1; if n == 2 then error("hook boom") end return real(...) end
    local m = make()
    sdk.hook = real
    assert(not m.status_available and hook_for(SETUP_PAWN))
    local info_text, tab_text = status_scene("Ana")
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.writes == 0 and tab_text.writes == 0 and #logs == 0)
end

-- Status: setupPawn marks both TxtName of a present member
do
    reset()
    local m = make()
    local info_text, tab_text = status_scene("Ana")
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.msg == "Ana \u{B7} Retinue" and tab_text.msg == "Ana \u{B7} Retinue")
    assert(count_log("marked (status): Ana \u{B7} Retinue") == 1, "logged once for the pair")
    -- a second identical call writes nothing
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.writes == 1 and tab_text.writes == 1)
    assert(count_log("marked (status)") == 1)
    assert(#reports == 0)
    assert(m.status_available)
end

-- Status: an away member, the main pawn and a non-member stay plain
for _, case in ipairs({ { AWAY_ID, false }, { PRESENT_ID, true }, { OTHER_ID, false } }) do
    reset()
    make()
    local info_text, tab_text = status_scene("Ana")
    world.by_addr[103] = chara_data(case[1], case[2])
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.msg == "Ana" and tab_text.msg == "Ana" and info_text.writes == 0 and tab_text.writes == 0, case[1])
    assert(#logs == 0 and #reports == 0)
end

-- Status: the Arisen (no owner) and an unreadable id are not members; a stale mark on them is stripped
do
    reset()
    make()
    local info_text, tab_text = status_scene("Arisen \u{B7} Retinue")
    world.by_addr[103] = obj({ CopyOwner = nil, [IS_MAIN] = true })
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.msg == "Arisen" and tab_text.msg == "Arisen")
end

-- Status: a no-roster scene marks nobody
do
    reset("none")
    make()
    local info_text = status_scene("Ana")
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.msg == "Ana" and info_text.writes == 0)
    assert(#reports == 0 and #logs == 0)
end

-- Status: PawnInfo2Ref.setup and CharaChangeRef.updateName mark; the roster is read at each call
do
    reset()
    make()
    local info_text = status_scene("Ana")
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(PAWN_INFO_SETUP, 101, 103)
    assert(info_text.msg == "Ana \u{B7} Retinue")
    -- the text is rewritten by the game; updateName marks the selected CharaData's name
    local tab_text = text("Ana")
    world.by_addr[102] = obj({ TxtName = tab_text.widget, get_SelectedCharaData = world.by_addr[103] })
    fire(UPDATE_NAME, 102)
    assert(tab_text.msg == "Ana \u{B7} Retinue" and tab_text.writes == 1)
    fire(UPDATE_NAME, 102)
    assert(tab_text.writes == 1)
    -- the member leaves the roster: the next refresh strips the mark
    world.store.roster = { mode = roster.OK, warnings = {}, members = {} }
    tab_text.msg = "Ana \u{B7} Retinue"
    fire(UPDATE_NAME, 102)
    assert(tab_text.msg == "Ana")
    assert(#reports == 0)
end

-- Status: a nil CharaData writes nothing (setupPawn with a null argument; updateName with no selection)
do
    reset()
    make()
    local info_text, tab_text = status_scene("Ana")
    fire(SETUP_PAWN, 100, 0)
    assert(info_text.writes == 0 and tab_text.writes == 0 and info_text.msg == "Ana")
    assert(#reports >= 1)
    reports = {}
    world.by_addr[102] = obj({ TxtName = tab_text.widget, get_SelectedCharaData = nil })
    fire(UPDATE_NAME, 102)
    assert(tab_text.writes == 0 and #reports == 1)
    fire(UPDATE_NAME, 102)
    assert(#reports == 1, "the same failure is reported once")
end

-- Status: set_Message throwing is reported, nothing escapes
do
    reset()
    make()
    local info_text, tab_text = status_scene("Ana")
    info_text.fail, tab_text.fail = true, true
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(SETUP_PAWN, 100, 103)
    assert(info_text.msg == "Ana" and #logs == 0)
    assert(#reports == 2)
    assert(reports[1]:find("set_Message failed", 1, true))
end

-- Status: an unreadable page or widget is reported, writes nothing
do
    reset()
    make()
    local tab_text = text("Ana")
    world.by_addr[100] = obj({ PawnInfo = nil, CharaTab = obj({ TxtName = tab_text.widget }) })
    world.by_addr[103] = chara_data(PRESENT_ID, false)
    fire(SETUP_PAWN, 100, 103)
    assert(tab_text.msg == "Ana \u{B7} Retinue") -- the readable widget still marks
    assert(#reports == 1 and reports[1]:find("PawnInfo.TxtName unreadable", 1, true))
    reports = {}
    fire(SETUP_PAWN, 999, 103) -- no page
    assert(#reports == 1 and reports[1]:find("status page unreadable", 1, true))
end

-- A post with an empty stack does nothing
do
    reset()
    make()
    hook_for(SETUP_PAWN).post(nil)
    hook_for(UPDATE_DISP).post(nil)
    assert(#reports == 0 and #logs == 0)
end

-- Rift: updateDisp
local function rift_scene(shown, offline_id)
    local texts = {}
    for i, s in ipairs(shown) do texts[i] = text(s) end
    local widgets = {}
    for i, t in ipairs(texts) do widgets[i] = t.widget end
    world.by_addr[104] = obj({ TxtPawnName = obj({ elements = widgets }) })
    world.by_addr[105] = obj({ OfflineId = offline_id })
    return texts
end

do
    -- a member with the backup's level, both widgets
    reset()
    local m = make({ level = function(id) assert(id == PRESENT_ID); return 28 end })
    local texts = rift_scene({ "Ana", "Ana" }, PRESENT_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "\u{2605} Ana \u{B7} Lv 28" and texts[2].msg == "\u{2605} Ana \u{B7} Lv 28")
    assert(count_log("marked (rift): \u{2605} Ana \u{B7} Lv 28") == 1)
    fire(UPDATE_DISP, 104, 105) -- identical: nothing written
    assert(texts[1].writes == 1 and texts[2].writes == 1)
    assert(#reports == 0)
end

do
    -- an away member is marked too; a changed level replaces the old one
    reset()
    local level = 20
    make({ level = function() return level end })
    local texts = rift_scene({ "Bo" }, AWAY_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "\u{2605} Bo \u{B7} Lv 20")
    level = 21
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "\u{2605} Bo \u{B7} Lv 21")
end

do
    -- no backups object, and a backups object that throws: "★ <name>"
    reset()
    make(nil)
    local texts = rift_scene({ "Ana" }, PRESENT_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "\u{2605} Ana")
    reset()
    make({ level = function() error("boom") end })
    texts = rift_scene({ "Ana" }, PRESENT_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "\u{2605} Ana")
end

do
    -- a non-member is untouched (a stale mark on a reused widget is stripped)
    reset()
    make({ level = function() return 5 end })
    local texts = rift_scene({ "Zed" }, OTHER_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "Zed" and texts[1].writes == 0 and #logs == 0)
    texts = rift_scene({ "\u{2605} Zed \u{B7} Lv 5" }, OTHER_ID)
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "Zed")
end

do
    -- set_Message throwing: reported (once per distinct message), nothing escapes
    reset()
    make()
    local texts = rift_scene({ "Ana" }, PRESENT_ID)
    texts[1].fail = true
    fire(UPDATE_DISP, 104, 105)
    assert(texts[1].msg == "Ana" and #reports == 1 and reports[1]:find("rift marks", 1, true))
end

do
    -- unreadable list item, entry or widget array: reported, nothing written
    reset()
    make()
    rift_scene({ "Ana" }, PRESENT_ID)
    fire(UPDATE_DISP, 104, 999)
    assert(#reports == 1 and reports[1]:find("list item or entry unreadable", 1, true))
    reports = {}
    world.by_addr[104] = obj({ TxtPawnName = nil })
    fire(UPDATE_DISP, 104, 105)
    assert(#reports == 1 and reports[1]:find("TxtPawnName unreadable", 1, true))
end

do
    -- at most six widgets
    reset()
    make()
    local texts = rift_scene({ "Ana", "Ana", "Ana", "Ana", "Ana", "Ana", "Ana", "Ana" }, PRESENT_ID)
    fire(UPDATE_DISP, 104, 105)
    for i = 1, 6 do assert(texts[i].msg == "\u{2605} Ana", i) end
    assert(texts[7].msg == "Ana" and texts[8].msg == "Ana")
end

do
    -- a nested call of the same method does not cross wires
    reset()
    make()
    local outer = rift_scene({ "Ana" }, PRESENT_ID)
    local h = hook_for(UPDATE_DISP)
    h.pre({ 0, 104, 105 })
    local inner_widget = text("Zed")
    world.by_addr[106] = obj({ TxtPawnName = obj({ elements = { inner_widget.widget } }) })
    world.by_addr[107] = obj({ OfflineId = OTHER_ID })
    h.pre({ 0, 106, 107 })
    h.post(nil)
    h.post(nil)
    assert(inner_widget.msg == "Zed" and outer[1].msg == "\u{2605} Ana")
end

print("marks_glue_test ok")
