-- game/confirm_dialog.lua and game/talk_menu.lua against a fake sdk and log: the lookups (a missing method or field
-- installs no hook and never calls the game), ask() refusing over another dialog, and one pick from start to finish.
local calls, logs, reports, hooked = {}, {}, {}, {}
local world
local missing_name

local function obj(name, props)
    local o = { name = name, sets = {} }
    function o:call(method, ...)
        calls[#calls + 1] = name .. ":" .. method
        local v = props[method]
        if type(v) == "function" then return v(o, ...) end
        return v
    end
    function o:get_field(field)
        calls[#calls + 1] = name .. "." .. field
        return props[field]
    end
    function o:set_field(field, value)
        calls[#calls + 1] = name .. "!" .. field
        o.sets[field] = value
        props[field] = value
    end
    function o:get_address() return props.addr end
    function o:add_ref() end
    function o:get_elements() return props.get_elements() end
    function o:read_qword() error("not a guid") end
    return o
end

local REQ_DISP = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
    .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)"
local REQUEST = "requestDialog(System.String, System.String, System.String, System.String, System.String, System.Boolean, "
    .. "System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, via.render.TextureResourceHolder, "
    .. "System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Single, System.Boolean, "
    .. "System.Boolean, System.Boolean)"

-- type name -> { methods = {sig}, fields = {name} }
local TYPES = {
    ["app.GuiManager"] = { methods = { REQUEST, "IsDispDialogGui()" }, fields = { "Dialog", "TalkSelect" } },
    ["app.ui010101"] = { methods = { "get_IsDisp()", "getRawRetVal()" }, fields = { "IsNoButton", "MainText" } },
    ["app.ui021601"] = { methods = { REQ_DISP, "get_IsEndGUI()" }, fields = { "SelectedIndex" } },
    ["app.ui021601.ListInfo"] = { methods = {}, fields = { "Msg", "_IsDecideEnable", "ListenerType", "SpeakerType", "Listener" } },
    ["app.TalkEventManager"] = { methods = {}, fields = { "<CurrentTalkInfo>k__BackingField" } },
}
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

sdk = {
    PreHookResult = { CALL_ORIGINAL = "CO" },
    find_type_definition = function(name)
        local t = TYPES[name]
        if not t or name == missing_name then return nil end
        local methods, fields = set(t.methods), set(t.fields)
        return {
            get_method = function(_, sig)
                if sig == missing_name or not methods[sig] then return nil end
                return { sig = sig, call = function(_, _, ...)
                    calls[#calls + 1] = "method:" .. sig
                    world.last_args = table.pack(...)
                    if world.method_throws == sig then error("method boom") end
                end }
            end,
            get_methods = function() return {} end,
            get_field = function(_, field)
                if field == missing_name or not fields[field] then return nil end
                return {}
            end,
        }
    end,
    hook = function(m, pre, post) hooked[#hooked + 1] = { m = m, pre = pre, post = post } end,
    get_managed_singleton = function(name) return world.singletons[name] end,
    create_managed_string = function(s) return s end,
    create_instance = function() return world.new_item() end,
    to_int64 = function(a) return a end,
    to_managed_object = function(a) return world.by_addr[a] end,
}
log = { error = function(text) logs[#logs + 1] = text end }

local confirm_dialog = require("Retinue.game.confirm_dialog")
local talk_menu = require("Retinue.game.talk_menu")
local roster = require("Retinue.roster")
local talk_logic = require("Retinue.talk_menu")
local function report(where, err) reports[#reports + 1] = where .. ": " .. tostring(err) end

local OFFLINE = "aaaaaaaa-0000-0000-0000-000000000001"

local function reset()
    calls, logs, reports, hooked = {}, {}, {}, {}
    local dialog_props = { get_IsDisp = false, IsNoButton = false, MainText = "", getRawRetVal = 0 }
    local dialog = obj("dialog", dialog_props)
    local gm_props = { IsDispDialogGui = false, Dialog = dialog }
    local gm = obj("gm", gm_props)
    world = { dialog_props = dialog_props, gm_props = gm_props, gm = gm, singletons = { ["app.GuiManager"] = gm }, by_addr = {} }
end

-- The notice-style lookups: every type, method and field in turn missing.
local cases = {}
for type_name, t in pairs(TYPES) do
    cases[#cases + 1] = type_name
    for _, sig in ipairs(t.methods) do cases[#cases + 1] = sig end
    for _, f in ipairs(t.fields) do cases[#cases + 1] = f end
end
assert(#cases == 5 + 6 + 11)

local function deps_for(dialog)
    return { store = { generation = 1, roster = nil, found = {}, ambiguous = {} }, party = { views = function() return {} end },
        dialog = dialog, notify = function() error("no notice expected") end }
end

for _, name in ipairs(cases) do
    reset()
    missing_name = name
    local dialog = confirm_dialog.new(report)
    local talk = talk_menu.new(report, deps_for(dialog))
    missing_name = nil
    assert(talk.available == false, name)
    assert(#hooked == 0, name)
    assert(#talk.missing >= 1, name)
    assert(#reports >= 1, name)
    calls = {}
    talk.tick(0)
    assert(talk.confirming() == false and #calls == 0, name)
    local named = false
    for _, m in ipairs(talk.missing) do
        if m:find(name, 1, true) or m == "confirm dialog" then named = true end
    end
    assert(named, name)
    -- the confirm dialog's own members make it unavailable; the game is not called through it
    if not dialog.available then
        assert(dialog.ask("x") == false and dialog.read() == nil)
        assert(#calls == 0, name)
    end
end

-- everything present: available, one hook, nothing reported
do
    reset()
    local dialog = confirm_dialog.new(report)
    assert(dialog.available and #dialog.missing == 0 and #reports == 0)
    local talk = talk_menu.new(report, deps_for(dialog))
    assert(talk.available and #talk.missing == 0 and #hooked == 1 and #reports == 0)
end

-- ask: only over nothing; exactly false opens it, anything else refuses
do
    reset()
    local dialog = confirm_dialog.new(report)
    calls = {}
    world.gm_props.IsDispDialogGui = true
    assert(dialog.ask("Release Ana?") == false)
    world.gm_props.IsDispDialogGui = nil
    assert(dialog.ask("Release Ana?") == false)
    world.singletons["app.GuiManager"] = nil
    assert(dialog.ask("Release Ana?") == false)
    for _, c in ipairs(calls) do assert(not c:find("^method:"), c) end
    assert(#reports == 0 and dialog.available)
    world.singletons["app.GuiManager"] = world.gm
    world.gm_props.IsDispDialogGui = false
    assert(dialog.ask("Release Ana?") == true)
    local a = world.last_args
    assert(a.n == 21 and a[1] == "Release Ana?" and a[2] == "Yes" and a[3] == "No" and a[4] == "" and a[5] == "")
    assert(a[6] == false and a[7] == 0 and a[8] == false and a[9] == 0 and a[10] == 0 and a[11] == 0 and a[12] == nil)
    assert(a[13] == false and a[17] == false and a[18] == 0.0 and a[19] == false and a[21] == false)
    -- a throw: reported, no longer available
    world.method_throws = REQUEST
    assert(dialog.ask("again") == false and dialog.available == false and #reports == 1 and reports[1]:find("method boom"))
    world.method_throws = nil
    calls = {}
    assert(dialog.ask("again") == false and #calls == 0)
end

-- read: the widget's state as plain data; anything unreadable is nil
do
    reset()
    local dialog = confirm_dialog.new(report)
    world.dialog_props.get_IsDisp, world.dialog_props.MainText, world.dialog_props.getRawRetVal = true, "hi", 1
    local r = dialog.read()
    assert(r.shown == true and r.no_button == false and r.text == "hi" and r.ret == 1)
    world.dialog_props.MainText = obj("str", { ToString = "managed" })
    assert(dialog.read().text == "managed")
    world.dialog_props.getRawRetVal = nil
    assert(dialog.read() == nil)
    world.dialog_props.getRawRetVal = 0
    world.dialog_props.IsNoButton = nil
    assert(dialog.read() == nil)
    world.dialog_props.IsNoButton = false
    world.gm_props.Dialog = nil
    assert(dialog.read() == nil)
    world.singletons["app.GuiManager"] = nil
    assert(dialog.read() == nil)
end

-- One pick from start to finish: the row is appended, the pick is redirected, the dialog opens, Yes adopts.
do
    reset()
    local R = talk_logic
    local list_items = {}
    local first = obj("first", { Listener = "L", ListenerType = 1, SpeakerType = 2 })
    list_items[1], list_items[2], list_items[3] = first, first, first
    local list = obj("list", {
        get_Count = function() return #list_items end,
        get_Item = function(_, i) return list_items[i + 1] end,
        Add = function(_, item) list_items[#list_items + 1] = item end,
    })
    world.by_addr[2000] = list
    -- every reqDisp gets a fresh list in the game: the vanilla three rows
    local function fresh() list_items = { first, first, first } end
    local choices = {}
    for i, id in ipairs({ "11111111-0000-0000-0000-000000000001", R.DISMISS, R.NEVER_MIND }) do
        choices[i] = obj("choice" .. i, { _ChoiceId = id })
    end
    local arr = obj("arr", { get_elements = function() return choices end })
    local node = obj("node", { _NodeId = R.ROOT_NODE, _Choices = arr })
    local info = obj("info", { ["<CurrentNode>k__BackingField"] = node, ["<Speaker>k__BackingField"] = 202, ["<Listener>k__BackingField"] = 100 })
    world.singletons["app.TalkEventManager"] = obj("tm", { ["<CurrentTalkInfo>k__BackingField"] = info })
    world.new_item = function() return obj("new_item", { add_ref = true, [".ctor"] = true }) end
    local select_props = { addr = 1000, get_IsEndGUI = false, SelectedIndex = -1 }
    local select = obj("select", select_props)
    world.gm_props.TalkSelect = select

    local view = { slot = 2, character_id = 202, owner = roster.OWNER, offline_id = OFFLINE, name = "Ana", chara = {} }
    local adopted
    local store = { generation = 1, found = {}, ambiguous = {}, unit = 0,
        roster = { mode = roster.OK, members = {}, warnings = {} },
        adopt = function(self, v) adopted = v; return true end }
    local notices_pushed = {}
    local dialog = confirm_dialog.new(report)
    local talk = talk_menu.new(report, {
        store = store, dialog = dialog, notify = function(t) notices_pushed[#notices_pushed + 1] = t end,
        party = { views = function() return { { slot = 0, character_id = 100 }, view } end, level = function() return 30 end },
    })
    assert(talk.available and #hooked == 1)
    -- the menu is shown
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 4, "row appended " .. table.concat(reports, "; "))
    assert(list_items[4].sets.Msg == "Adopt" and list_items[4].sets._IsDecideEnable == true and list_items[4].sets.Listener == "L")

    -- nothing picked yet: waiting
    talk.tick(1)
    assert(select.sets.SelectedIndex == nil and not talk.confirming())
    -- the player picks our row (index 3)
    select_props.get_IsEndGUI, select_props.SelectedIndex = true, 3
    talk.tick(2)
    assert(select.sets.SelectedIndex == 2, "redirected to Never mind (the last original row)")
    assert(world.last_args.n == 21 and world.last_args[1]:find("^Adopt Ana into your retinue%?"))
    assert(talk.confirming() == true)
    -- the dialog is up, then Yes
    world.dialog_props.get_IsDisp, world.dialog_props.MainText = true, world.last_args[1]
    talk.tick(2.1)
    assert(talk.confirming())
    world.dialog_props.getRawRetVal = 1
    talk.tick(2.2)
    assert(not talk.confirming() and adopted == view and #notices_pushed == 0)

    -- a refusal (locked) shows a notice and opens no dialog
    store.roster.mode = roster.LOCKED
    fresh()
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    select_props.SelectedIndex = 3
    calls = {}
    talk.tick(3)
    assert(#notices_pushed == 1 and notices_pushed[1] == "Cannot adopt Ana: the roster is locked (see the menu)")
    for _, c in ipairs(calls) do assert(c ~= "method:" .. REQUEST) end
    assert(not talk.confirming())

    -- another row picked: the menu is dropped, nothing else happens
    store.roster.mode = roster.OK
    fresh()
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    select.sets.SelectedIndex = nil
    select_props.SelectedIndex = 1
    talk.tick(4)
    assert(select.sets.SelectedIndex == nil and #notices_pushed == 1)
    select_props.SelectedIndex = 3
    talk.tick(5)
    assert(select.sets.SelectedIndex == nil, "menu was dropped")

    local function no_dialog_calls()
        for _, c in ipairs(calls) do assert(c ~= "method:" .. REQUEST, c) end
    end
    local function arm()
        store.roster.mode = roster.OK
        fresh()
        hooked[1].pre({ [2] = 1000, [3] = 2000 })
        assert(#list_items == 4)
        select.sets.SelectedIndex = nil
    end

    -- the same list handed to reqDisp twice: no second row, and the redirect is armed again on the row already there
    reports = {}
    arm()
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 4 and #reports == 0)
    select_props.get_IsEndGUI, select_props.SelectedIndex = true, 3
    calls = {}
    talk.tick(6)
    assert(select.sets.SelectedIndex == 2, "redirected to Never mind")
    assert(talk.confirming())
    world.dialog_props.get_IsDisp, world.dialog_props.MainText, world.dialog_props.getRawRetVal = true, world.dialog_props.MainText, 2
    talk.tick(6.1) -- not seen with ret 0 first: no answer yet
    world.dialog_props.get_IsDisp = false
    talk.tick(9) -- never shown as ours: given up after 2 s
    assert(not talk.confirming())
    world.dialog_props.getRawRetVal = 0

    -- args[2] is not GuiManager.TalkSelect: no row, one report line
    fresh()
    reports = {}
    hooked[1].pre({ [2] = 1111, [3] = 2000 })
    assert(#list_items == 3 and #reports == 1 and reports[1]:find("not GuiManager.TalkSelect", 1, true))
    world.gm_props.TalkSelect = nil
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 3 and #reports == 2)
    world.gm_props.TalkSelect = select

    -- a non-root menu leaves the list alone, and disarms the menu of the root before it
    arm()
    local saved = choices[3]
    choices[3] = obj("c3", { _ChoiceId = "ffffffff-0000-0000-0000-000000000000" })
    fresh()
    reports = {}
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 3)
    assert(#reports == 1 and reports[1]:find("root menu not recognised: 3 choices, last ffffffff-0000-0000-0000-000000000000", 1, true), reports[1])
    choices[3] = saved
    select_props.get_IsEndGUI, select_props.SelectedIndex = true, 3
    calls = {}
    talk.tick(7)
    assert(select.sets.SelectedIndex == nil and not talk.confirming())
    no_dialog_calls()

    -- a talk with the main pawn (or nobody in the party) gets no row
    info:set_field("<Speaker>k__BackingField", 100)
    fresh()
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 3)
    info:set_field("<Speaker>k__BackingField", 202)

    -- the redirect does not stick: reported, no dialog, the menu is dropped
    arm()
    select_props.get_IsEndGUI, select_props.SelectedIndex = true, 3
    local real_set = select.set_field
    select.set_field = function() end
    reports, calls = {}, {}
    talk.tick(8)
    select.set_field = real_set
    assert(#reports == 1 and reports[1]:find("could not be redirected", 1, true))
    assert(not talk.confirming())
    no_dialog_calls()
    talk.tick(9)
    assert(#reports == 1 and select.sets.SelectedIndex == nil)

    -- the dialog call has failed for good: no row
    fresh()
    dialog.available = false
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 3)

    -- _Choices whose get_elements fails (ticket 24 run 2): read as a List, then as an array
    dialog.available = true
    talk = talk_menu.new(report, {
        store = store, dialog = dialog, notify = function() end,
        party = { views = function() return { { slot = 0, character_id = 100 }, view } end, level = function() return 30 end },
    })
    local hook = hooked[#hooked]
    store.roster.mode, store.roster.members = roster.OK, {}
    for _, shape in ipairs({
        { get_elements = function() return {} end, get_Count = function() return #choices end,
          get_Item = function(_, i) return choices[i + 1] end },
        { get_elements = function() error("no elements") end, get_Count = function() return #choices end,
          get_Item = function(_, i) return choices[i + 1] end },
        { get_elements = function() error("no elements") end, get_Count = function() error("not a List") end,
          get_Length = function() return #choices end, GetValue = function(_, i) return choices[i + 1] end },
    }) do
        node = obj("node", { _NodeId = R.ROOT_NODE, _Choices = obj("arr", shape) })
        info = obj("info", { ["<CurrentNode>k__BackingField"] = node, ["<Speaker>k__BackingField"] = 202, ["<Listener>k__BackingField"] = 100 })
        world.singletons["app.TalkEventManager"] = obj("tm", { ["<CurrentTalkInfo>k__BackingField"] = info })
        fresh()
        hook.pre({ [2] = 1000, [3] = 2000 })
        assert(#list_items == 4, "row appended through the fallback")
    end
    -- more choices than the cap: unreadable, no row
    local many = {}
    for i = 1, 17 do many[i] = choices[3] end
    node = obj("node", { _NodeId = R.ROOT_NODE, _Choices = obj("arr", { get_elements = function() return many end,
        get_Count = function() return #many end, get_Item = function(_, i) return many[i + 1] end }) })
    info = obj("info", { ["<CurrentNode>k__BackingField"] = node, ["<Speaker>k__BackingField"] = 202, ["<Listener>k__BackingField"] = 100 })
    world.singletons["app.TalkEventManager"] = obj("tm", { ["<CurrentTalkInfo>k__BackingField"] = info })
    fresh()
    reports = {}
    hook.pre({ [2] = 1000, [3] = 2000 })
    assert(#list_items == 3)
    assert(#reports == 1 and reports[1]:find("root menu not recognised: unreadable choices", 1, true), reports[1])
end

print("talk_menu_glue_test ok")
