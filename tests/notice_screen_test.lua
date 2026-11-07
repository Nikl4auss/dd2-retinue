-- game/notice_screen.lua against a fake sdk and log: the lookups, the busy and is_mine reads, and that a missing method
-- never reaches the game.
local calls, logs, reports = {}, {}, {}
local world

local function obj(name, props)
    local o = { name = name }
    function o:call(method, ...)
        calls[#calls + 1] = name .. ":" .. method
        local v = props[method]
        if type(v) == "function" then return v(...) end
        return v
    end
    function o:get_field(field)
        calls[#calls + 1] = name .. "." .. field
        return props[field]
    end
    return o
end

-- the type definitions the module looks up: type name -> { methods = {sig}, fields = {name} }
local TYPES = {
    ["app.GuiManager"] = {
        methods = { "requestNoButtonDialog(System.String, System.UInt32)", "requestHideDialog()", "IsDispDialogGui()",
                    "IsOpenMainFlowUI()", "isDispMovieScreen()" },
        fields = { "Dialog", "NetworkErrorDialog" },
    },
    ["app.ui010101"] = { methods = { "get_IsDisp()" }, fields = { "IsNoButton", "MainText" } },
    ["app.TalkEventManager"] = { methods = {}, fields = { "_IsTalkingAny" } },
    ["app.DemoMediator"] = { methods = { "get_IsPlayingDemo()" }, fields = {} },
}

local missing_sig, missing_type
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

sdk = {
    find_type_definition = function(name)
        if name == missing_type then return nil end
        local t = TYPES[name]
        if not t then return nil end
        local methods, fields = set(t.methods), set(t.fields)
        return {
            get_method = function(_, sig)
                if sig == missing_sig or not methods[sig] then return nil end
                return { sig = sig, call = function(_, _, ...)
                    calls[#calls + 1] = "method:" .. sig
                    world.last_args = { ... }
                    if world.method_throws == sig then error("method boom") end
                end }
            end,
            get_methods = function() return {} end,
            get_field = function(_, field)
                if field == missing_sig or not fields[field] then return nil end
                return {}
            end,
        }
    end,
    get_managed_singleton = function(name) return world.singletons[name] end,
    create_managed_string = function(s) return s end,
}
log = { error = function(text) logs[#logs + 1] = text end }

local screen_mod = require("Retinue.game.notice_screen")
local function report(where, err) reports[#reports + 1] = where .. ": " .. tostring(err) end

-- The world with every state false; `flip` names one of gm / net / talk / demo and `key` the property to read true.
local function reset(flip, key)
    calls, logs, reports = {}, {}, {}
    local function props(name, base)
        if flip == name then base[key] = true end
        return base
    end
    local dialog = obj("dialog", { get_IsDisp = false, IsNoButton = false, MainText = "" })
    local net = obj("net", props("net", { get_IsDisp = false }))
    local gm = obj("gm", props("gm", {
        IsDispDialogGui = false, IsOpenMainFlowUI = false, isDispMovieScreen = false,
        Dialog = dialog, NetworkErrorDialog = net,
    }))
    world = {
        dialog = dialog, net = net, gm = gm,
        talk = obj("talk", props("talk", { _IsTalkingAny = false })),
        demo = obj("demo", props("demo", { get_IsPlayingDemo = false })),
    }
    world.singletons = {
        ["app.GuiManager"] = gm, ["app.TalkEventManager"] = world.talk, ["app.DemoMediator"] = world.demo,
    }
end

-- all present: available, nothing reported, not busy
do
    reset()
    local s = screen_mod.new(report)
    assert(s.available and #reports == 0)
    assert(s.busy() == false)
end

-- each state alone makes it busy
for _, case in ipairs({
    { "gm", "IsDispDialogGui" }, { "gm", "IsOpenMainFlowUI" }, { "gm", "isDispMovieScreen" },
    { "net", "get_IsDisp" }, { "talk", "_IsTalkingAny" }, { "demo", "get_IsPlayingDemo" },
}) do
    reset(case[1], case[2])
    local s = screen_mod.new(report)
    assert(s.busy() == true, case[2])
end

-- a nil singleton or a nil read counts as busy; a throw is busy and reported
do
    for _, name in ipairs({ "app.GuiManager", "app.TalkEventManager", "app.DemoMediator" }) do
        reset()
        local s = screen_mod.new(report)
        world.singletons[name] = nil
        assert(s.busy() == true, name)
    end
    reset()
    local s = screen_mod.new(report)
    world.singletons["app.GuiManager"] = { call = function() error("boom") end }
    assert(s.busy() == true and #reports == 1 and reports[1]:find("boom"))
    reset()
    s = screen_mod.new(report)
    world.talk = obj("talk", {}) -- _IsTalkingAny reads nil
    world.singletons["app.TalkEventManager"] = world.talk
    assert(s.busy() == true)
end

-- is_mine: displayed, no-button and the text; each alone is not enough. Only a proven "not ours" is false.
do
    reset()
    local s = screen_mod.new(report)
    local function dialog(props)
        world.gm = obj("gm", { Dialog = obj("d", props) })
        world.singletons["app.GuiManager"] = world.gm
    end
    dialog{ get_IsDisp = true, IsNoButton = true, MainText = "hello" }
    assert(s.is_mine("hello") == true)
    assert(s.is_mine("other") == false)
    dialog{ get_IsDisp = false, IsNoButton = true, MainText = "hello" } -- hidden: the fields keep their values
    assert(s.is_mine("hello") == false)
    dialog{ get_IsDisp = true, IsNoButton = false, MainText = "hello" } -- a game dialog replaced ours
    assert(s.is_mine("hello") == false)
    assert(#reports == 0)
    -- IsDisp or IsNoButton unreadable: nil, not "not ours"
    dialog{ get_IsDisp = nil, IsNoButton = true, MainText = "hello" }
    assert(s.is_mine("hello") == nil)
    dialog{ get_IsDisp = true, IsNoButton = nil, MainText = "hello" }
    assert(s.is_mine("hello") == nil)
    assert(#reports == 2 and reports[1]:find("Dialog.IsDisp", 1, true) and reports[2]:find("Dialog.IsNoButton", 1, true))
    -- a managed string
    dialog{ get_IsDisp = true, IsNoButton = true, MainText = obj("str", { ToString = "hello" }) }
    assert(s.is_mine("hello") == true)
    -- unreadable: nil, and reported
    dialog{ get_IsDisp = true, IsNoButton = true, MainText = nil }
    assert(s.is_mine("hello") == nil and #reports == 3)
    -- no widget, no singleton, a throw: nil
    dialog{ get_IsDisp = true, IsNoButton = true, MainText = "hello" }
    world.gm = obj("gm", {})
    world.singletons["app.GuiManager"] = world.gm
    assert(s.is_mine("hello") == nil)
    world.singletons["app.GuiManager"] = nil
    assert(s.is_mine("hello") == nil)
    world.singletons["app.GuiManager"] = { get_field = function() error("boom") end }
    assert(s.is_mine("hello") == nil and #reports == 6)
end

-- show and hide call the game's methods with the text and 0
do
    reset()
    local s = screen_mod.new(report)
    calls = {}
    s.show("hi")
    assert(table.concat(calls, ",") == "method:requestNoButtonDialog(System.String, System.UInt32)")
    assert(world.last_args[1] == "hi" and world.last_args[2] == 0 and #world.last_args == 2)
    calls = {}
    assert(s.hide() == true)
    assert(table.concat(calls, ",") == "method:requestHideDialog()" and #world.last_args == 0)
    assert(s.available and s.resolved and #logs == 0 and #reports == 0)
end

-- a show that throws: reported, the text logged, no longer available; the panel may be up, so hide and is_mine still work
do
    reset()
    local s = screen_mod.new(report)
    world.method_throws = "requestNoButtonDialog(System.String, System.UInt32)"
    s.show("hi")
    assert(s.available == false and s.resolved == true and #reports == 1 and reports[1]:find("method boom"))
    assert(#logs == 1 and logs[1] == "[Retinue] notice (not shown): hi")
    calls = {}
    assert(s.hide() == true)
    assert(calls[1] == "method:requestHideDialog()")
    world.gm = obj("gm", { Dialog = obj("d", { get_IsDisp = true, IsNoButton = true, MainText = "hi" }) })
    world.singletons["app.GuiManager"] = world.gm
    assert(s.is_mine("hi") == true) -- a thrown show leaves the close working
    s.show("later") -- not available: only the log
    assert(#logs == 2 and logs[2] == "[Retinue] notice (not shown): later")
end

-- a hide that throws: false, reported, and it can be tried again
do
    reset()
    local s = screen_mod.new(report)
    world.method_throws = "requestHideDialog()"
    assert(s.hide() == false and #reports == 1 and reports[1]:find("method boom"))
    assert(s.available == false and s.resolved == true)
    world.method_throws = nil
    assert(s.hide() == true)
    world.singletons["app.GuiManager"] = nil
    assert(s.hide() == false)
end

-- a missing type, method or field, each in turn: unresolved, one report line naming it, and the game is never called
local cases = {}
for type_name, t in pairs(TYPES) do
    cases[#cases + 1] = { type = type_name }
    for _, sig in ipairs(t.methods) do cases[#cases + 1] = { sig = sig } end
    for _, f in ipairs(t.fields) do cases[#cases + 1] = { sig = f } end
end
assert(#cases == 4 + 7 + 5)
for _, case in ipairs(cases) do
    reset()
    missing_sig, missing_type = case.sig, case.type
    local s = screen_mod.new(report)
    missing_sig, missing_type = nil, nil
    local what = case.sig or case.type
    assert(s.available == false and s.resolved == false, what)
    assert(#reports == 1 and reports[1]:find(what, 1, true), what)
    calls = {}
    assert(s.busy() == true)
    assert(s.is_mine("x") == false)
    s.show("The Retinue roster is locked: x\nSee the Retinue menu.")
    assert(s.hide() == false)
    assert(#calls == 0, what)
    assert(#logs == 1 and logs[1] == "[Retinue] notice (not shown): The Retinue roster is locked: x\nSee the Retinue menu.")
end

print("notice_screen_test ok")
