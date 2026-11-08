-- REFramework glue: the native notice, GuiManager's centred no-button dialog (uses sdk and log). The queue is
-- Retinue/notices.lua, the texts Retinue/labels.lua. The dialog is a modal that shares its widget with the game's own
-- dialogs (findings 0009 P6): a show or a hide over a game dialog softlocks the game. So every call here is meant for the
-- game thread's UpdateBehavior callback (the one exception: Retinue.lua's script reset closes a notice that is up), and the
-- caller asks busy() in the same callback that shows and is_mine(text) in
-- the same one that hides. Unknown, nil or thrown states fail safe: busy() true, and is_mine() neither true nor false.
local hooks = require("Retinue.hooks")

local M = {}

local GUI_MANAGER = "app.GuiManager"
local DIALOG_WIDGET = "app.ui010101"
local TALK_MANAGER = "app.TalkEventManager"
local DEMO_MEDIATOR = "app.DemoMediator"

local NO_BUTTON_SIG = "requestNoButtonDialog(System.String, System.UInt32)"
local HIDE_SIG = "requestHideDialog()"

-- A managed or Lua string as a Lua string, else nil.
local function as_string(v)
    if type(v) == "string" then return v end
    if v ~= nil then -- a managed object (userdata): its ToString
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

-- M.new(report) -> screen:
--   resolved    boolean  every method and field below was found (fixed at load). When false the game is never called.
--   available   boolean  resolved, and no show or hide has thrown since: the notices may be shown. Closing a notice that is
--                        up needs only `resolved`: a panel nobody closes blocks the game's input for good.
--   busy()      -> boolean  true while a game dialog, a menu, a cutscene or a talk is up, or when that cannot be told
--   is_mine(text) -> true | false | nil  read in this call. true: the dialog is displayed, is a no-button one and carries this
--                        text. false: proven not ours (not displayed, not a no-button one, or another readable text).
--                        nil: a read failed, or a singleton or widget is nil (reported).
--   show(text)  the request call, under pcall; a throw is reported, the text is logged and available becomes false.
--               When not available it only logs "[Retinue] notice (not shown): <text>".
--   hide() -> boolean  the request call, under pcall; false on a throw (reported, available becomes false).
-- Not read, on purpose (findings 0009 P6): PauseManager.isPausedAny stays true for a whole Rift visit, where a Return
-- happens; TalkSelect.IsDisp sticks after the first talk.
function M.new(report)
    local screen = { available = false, resolved = false }
    local missing = {}
    local m_show, m_hide

    -- Everything the calls below use, looked up now so that a game update shows as one report line, not as a throw per frame.
    local function type_of(name)
        local ok, td = pcall(sdk.find_type_definition, name)
        if ok and td then return td end
        missing[#missing + 1] = name
        return nil
    end
    local function method_of(td, type_name, sig)
        if td == nil then return nil end
        local ok, m = pcall(hooks.find_method, td, sig)
        if ok and m then return m end
        missing[#missing + 1] = type_name .. "." .. sig
        return nil
    end
    local function field_of(td, type_name, name)
        if td == nil then return end
        local ok, f = pcall(function() return td:get_field(name) end)
        if not (ok and f) then missing[#missing + 1] = type_name .. "." .. name end
    end

    local td_gm, td_widget = type_of(GUI_MANAGER), type_of(DIALOG_WIDGET)
    local td_talk, td_demo = type_of(TALK_MANAGER), type_of(DEMO_MEDIATOR)
    m_show = method_of(td_gm, GUI_MANAGER, NO_BUTTON_SIG)
    m_hide = method_of(td_gm, GUI_MANAGER, HIDE_SIG)
    for _, sig in ipairs({ "IsDispDialogGui()", "IsOpenMainFlowUI()", "isDispMovieScreen()" }) do
        method_of(td_gm, GUI_MANAGER, sig)
    end
    field_of(td_gm, GUI_MANAGER, "Dialog")
    field_of(td_gm, GUI_MANAGER, "NetworkErrorDialog")
    method_of(td_widget, DIALOG_WIDGET, "get_IsDisp()")
    field_of(td_widget, DIALOG_WIDGET, "IsNoButton")
    field_of(td_widget, DIALOG_WIDGET, "MainText")
    field_of(td_talk, TALK_MANAGER, "_IsTalkingAny")
    method_of(td_demo, DEMO_MEDIATOR, "get_IsPlayingDemo()")

    if #missing == 0 then
        screen.resolved, screen.available = true, true
    else
        report("notices", "unavailable, not found (game update?): " .. table.concat(missing, ", "))
    end

    -- The reads below go by name on the object itself, not through the looked-up method.
    local function singleton(name)
        return sdk.get_managed_singleton(name)
    end

    -- Only an exact false clears a state: a nil, a number or anything else counts as busy.
    function screen.busy()
        if not screen.available then return true end
        local ok, res = pcall(function()
            local gm = singleton(GUI_MANAGER)
            if gm == nil then return true end
            if gm:call("IsDispDialogGui") ~= false then return true end
            if gm:call("IsOpenMainFlowUI") ~= false then return true end
            if gm:call("isDispMovieScreen") ~= false then return true end
            local net = gm:get_field("NetworkErrorDialog")
            if net == nil or net:call("get_IsDisp") ~= false then return true end
            local talk = singleton(TALK_MANAGER)
            if talk == nil or talk:get_field("_IsTalkingAny") ~= false then return true end
            local demo = singleton(DEMO_MEDIATOR)
            if demo == nil or demo:call("get_IsPlayingDemo") ~= false then return true end
            return false
        end)
        if not ok then
            report("notices", res)
            return true
        end
        return res ~= false
    end

    -- All three matter: MainText and IsNoButton keep their values after a hide, and a dialog that replaces ours leaves
    -- IsDisp true. Only a proven "not ours" is false; what could not be read is nil, and the caller asks again.
    local function unreadable(what)
        report("notices", what .. " unreadable")
        return nil
    end

    function screen.is_mine(text)
        if not screen.resolved then return false end
        local ok, res = pcall(function()
            local gm = singleton(GUI_MANAGER)
            if gm == nil then return unreadable("GuiManager") end
            local dialog = gm:get_field("Dialog")
            if dialog == nil then return unreadable("Dialog") end
            local shown = dialog:call("get_IsDisp")
            if shown == nil then return unreadable("Dialog.IsDisp") end
            if shown ~= true then return false end
            local no_button = dialog:get_field("IsNoButton")
            if no_button == nil then return unreadable("Dialog.IsNoButton") end
            if no_button ~= true then return false end
            local main = as_string(dialog:get_field("MainText"))
            if main == nil then return unreadable("Dialog.MainText") end
            return main == text
        end)
        if not ok then
            report("notices", res)
            return nil
        end
        return res
    end

    -- describe() -> string: every input of busy() and is_mine(), for the log. Diagnostics only; never decides anything.
    function screen.describe()
        if not screen.resolved then return "unresolved" end
        local function read(f)
            local ok, v = pcall(f)
            if not ok then return "err" end
            return tostring(v)
        end
        local gm = singleton(GUI_MANAGER)
        if gm == nil then return "GuiManager nil" end
        local dialog = gm:get_field("Dialog")
        local talk, demo = singleton(TALK_MANAGER), singleton(DEMO_MEDIATOR)
        return table.concat({
            "dialogGui=" .. read(function() return gm:call("IsDispDialogGui") end),
            "mainFlow=" .. read(function() return gm:call("IsOpenMainFlowUI") end),
            "movie=" .. read(function() return gm:call("isDispMovieScreen") end),
            "netErr=" .. read(function() return gm:get_field("NetworkErrorDialog"):call("get_IsDisp") end),
            "talk=" .. read(function() return talk:get_field("_IsTalkingAny") end),
            "demo=" .. read(function() return demo:call("get_IsPlayingDemo") end),
            "D.disp=" .. read(function() return dialog:call("get_IsDisp") end),
            "D.noButton=" .. read(function() return dialog:get_field("IsNoButton") end),
            "D.text=" .. read(function() return as_string(dialog:get_field("MainText")) end),
        }, " ")
    end

    function screen.show(text)
        if not screen.available then
            log.error("[Retinue] notice (not shown): " .. text)
            return
        end
        local ok, err = pcall(function()
            local gm = singleton(GUI_MANAGER)
            if gm == nil then error("GuiManager not available") end
            m_show:call(gm, sdk.create_managed_string(text), 0)
        end)
        if not ok then
            report("notices", err)
            screen.available = false
            log.error("[Retinue] notice (not shown): " .. text)
        end
    end

    function screen.hide()
        if not screen.resolved then return false end
        local ok, err = pcall(function()
            local gm = singleton(GUI_MANAGER)
            if gm == nil then error("GuiManager not available") end
            m_hide:call(gm)
        end)
        if not ok then
            report("notices", err)
            screen.available = false
        end
        return ok
    end

    return screen
end

return M
