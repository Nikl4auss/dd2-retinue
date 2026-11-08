-- REFramework glue: the game's Yes/No dialog, GuiManager.requestDialog (uses sdk). The answer logic is
-- Retinue/confirm.lua, the texts Retinue/labels.lua. The dialog is the shared widget (GuiManager.Dialog, app.ui010101) that
-- notice_screen also uses (findings 0009 P6, 0007 Q3), so ask() only opens it when nothing else is up, and read() only
-- looks. Both are meant for the game thread's UpdateBehavior callback, where Retinue.lua's talk menu calls them.
local hooks = require("Retinue.hooks")
local labels = require("Retinue.labels")

local M = {}

local GUI_MANAGER = "app.GuiManager"
local DIALOG_WIDGET = "app.ui010101"

local REQUEST_SIG = "requestDialog(System.String, System.String, System.String, System.String, System.String, "
    .. "System.Boolean, System.Int32, System.Boolean, System.UInt32, System.Int32, System.Int32, "
    .. "via.render.TextureResourceHolder, System.Boolean, System.Boolean, System.Boolean, System.Boolean, "
    .. "System.Boolean, System.Single, System.Boolean, System.Boolean, System.Boolean)"

-- A managed or Lua string as a Lua string, else nil.
local function as_string(v)
    if type(v) == "string" then return v end
    if v ~= nil then -- a managed object (userdata): its ToString
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and type(s) == "string" then return s end
    end
    return nil
end

-- M.new(report) -> dialog:
--   available   boolean  every method and field below was found (fixed at load), and no ask has thrown since
--   missing     { string }  what was not found, "<type>.<member>"
--   ask(text) -> boolean  open the Yes/No dialog with this main text. false when not available, when a dialog is up
--                         (IsDispDialogGui must read exactly false), or when the call threw (reported; available becomes false)
--   read() -> nil | { shown, no_button, text, ret }  the widget's state now (confirm.lua's input), nil when anything could not
--                         be read. ret is getRawRetVal(), never getRetVal (it may consume the answer): 0 while open, 1 Yes, 2 No.
function M.new(report)
    local dialog = { available = false, missing = {} }
    local missing = dialog.missing
    local m_request

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
    m_request = method_of(td_gm, GUI_MANAGER, REQUEST_SIG)
    method_of(td_gm, GUI_MANAGER, "IsDispDialogGui()")
    field_of(td_gm, GUI_MANAGER, "Dialog")
    method_of(td_widget, DIALOG_WIDGET, "get_IsDisp()")
    method_of(td_widget, DIALOG_WIDGET, "getRawRetVal()")
    field_of(td_widget, DIALOG_WIDGET, "IsNoButton")
    field_of(td_widget, DIALOG_WIDGET, "MainText")

    if #missing == 0 then
        dialog.available = true
    else
        report("confirm dialog", "unavailable, not found (game update?): " .. table.concat(missing, ", "))
    end

    function dialog.ask(text)
        if not dialog.available then return false end
        local ok, res = pcall(function()
            local gm = sdk.get_managed_singleton(GUI_MANAGER)
            if gm == nil then return false end
            if gm:call("IsDispDialogGui") ~= false then return false end -- a dialog is up: never over it
            -- Parameters 6 to 21 are neutral values (their meaning is not in the dump; findings 0007 Q3): false / 0 / nil / 0.0.
            m_request:call(gm, sdk.create_managed_string(text), sdk.create_managed_string(labels.YES),
                sdk.create_managed_string(labels.NO), sdk.create_managed_string(""), sdk.create_managed_string(""),
                false, 0, false, 0, 0, 0, nil, false, false, false, false, false, 0.0, false, false, false)
            return true
        end)
        if not ok then
            report("confirm dialog", res)
            dialog.available = false
            return false
        end
        return res == true
    end

    function dialog.read()
        if not dialog.available then return nil end
        local ok, res = pcall(function()
            local gm = sdk.get_managed_singleton(GUI_MANAGER)
            local widget = gm and gm:get_field("Dialog")
            if widget == nil then return nil end
            local shown = widget:call("get_IsDisp")
            local no_button = widget:get_field("IsNoButton")
            local text = as_string(widget:get_field("MainText"))
            local ret = widget:call("getRawRetVal")
            if type(ret) == "number" then ret = math.tointeger(ret) else ret = nil end
            if type(shown) ~= "boolean" or type(no_button) ~= "boolean" or text == nil or ret == nil then return nil end
            return { shown = shown, no_button = no_button, text = text, ret = ret }
        end)
        if not ok then
            report("confirm dialog", res)
            return nil
        end
        return res
    end

    return dialog
end

return M
