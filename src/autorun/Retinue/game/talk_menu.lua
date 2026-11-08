-- REFramework glue: the extra row of the talk menu of a hired party pawn ("Adopt" / "Release"), its Yes/No dialog and the
-- action (uses sdk and log). The decisions are Retinue/talk_menu.lua (menu, pawn, row, refusal) and Retinue/confirm.lua
-- (the answer), the texts Retinue/labels.lua, the dialog game/confirm_dialog.lua, the adopt and release game/roster_store.lua.
--
-- How it works (findings 0007): in the pre of ui021601.reqDisp, the widget that shows the talk's choice list, a ListInfo
-- appended to the list shows as a last row. When the player picks that row (the widget's GUI ended with SelectedIndex on it),
-- SelectedIndex is rewritten to the Never mind row, so the game ends the talk as for Never mind; then the Yes/No dialog opens
-- and its answer decides. Anything unknown, missing or thrown leaves the menu vanilla. All of it runs on the game thread:
-- the hook inside the game's call, tick() in Retinue.lua's UpdateBehavior callback.
local confirm = require("Retinue.confirm")
local hooks = require("Retinue.hooks")
local labels = require("Retinue.labels")
local roster = require("Retinue.roster")
local talk_menu = require("Retinue.talk_menu")

local M = {}

local GUI_MANAGER = "app.GuiManager"
local TALK_MANAGER = "app.TalkEventManager"
local TALK_SELECT = "app.ui021601"
local LIST_INFO = "app.ui021601.ListInfo"

local REQ_DISP_SIG = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
    .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)"

local CURRENT_TALK_INFO = "<CurrentTalkInfo>k__BackingField"
local CURRENT_NODE = "<CurrentNode>k__BackingField"
local SPEAKER = "<Speaker>k__BackingField"
local LISTENER = "<Listener>k__BackingField"
local CHOICES_MAX = 16 -- entries read from a node's _Choices

-- System.Guid (a value type) -> canonical lowercase "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx". Reads the raw 16 bytes, then
-- falls back to ToString; "unreadable" (matches nothing) otherwise. Never returns userdata.
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

-- A managed or Lua string as a Lua string, else nil.
local function as_string(v)
    if type(v) == "string" then return v end
    if v ~= nil then -- a managed object (userdata): its ToString
        local ok, str = pcall(function() return v:call("ToString") end)
        if ok and type(str) == "string" then return str end
    end
    return nil
end

-- A hook argument (a raw pointer-sized value) as a managed object, nil when null.
local function to_managed(a)
    if a == nil or sdk.to_int64(a) == 0 then return nil end
    return sdk.to_managed_object(a)
end

-- The elements of a managed array as a Lua array, at most CHOICES_MAX; nil when unreadable.
local function elements(arr)
    if arr == nil then return nil end
    local ok, elems = pcall(function() return arr:get_elements() end)
    if not (ok and type(elems) == "table") then return nil end
    local out = {}
    for i, v in ipairs(elems) do
        if i > CHOICES_MAX then break end
        out[i] = v
    end
    return out
end

-- M.new(report, deps) -> talk
--   deps = { store = game/roster_store's, party = game/party's, dialog = game/confirm_dialog's, notify = function(text) }
--   talk.available   boolean  everything below was found and the hook is installed
--   talk.missing     { string }  what was not found, for the menu's "unavailable" lines
--   talk.tick(now)   -- once per UpdateBehavior, on the game thread: the pick on our row, the dialog's answer, the action
--   talk.confirming() -- true while our Yes/No dialog is open or being waited for
function M.new(report, deps)
    local talk = { available = false, missing = {} }
    local missing = talk.missing
    local store, party, dialog, notify = deps.store, deps.party, deps.dialog, deps.notify

    local menu = nil -- the menu we added a row to: { widget, pos, never_mind, row, generation }
    local pending = nil -- the open confirm: { c, row, generation }

    -- Everything the calls below use, looked up now so that a game update shows as one report line, not as a throw per frame.
    local function type_of(name)
        local ok, td = pcall(sdk.find_type_definition, name)
        if ok and td then return td end
        missing[#missing + 1] = name
        return nil
    end
    local function method_of(td, type_name, sig)
        if td == nil then return end
        local ok, m = pcall(hooks.find_method, td, sig)
        if not (ok and m) then missing[#missing + 1] = type_name .. "." .. sig end
    end
    local function field_of(td, type_name, name)
        if td == nil then return end
        local ok, f = pcall(function() return td:get_field(name) end)
        if not (ok and f) then missing[#missing + 1] = type_name .. "." .. name end
    end

    local td_gm, td_tm = type_of(GUI_MANAGER), type_of(TALK_MANAGER)
    local td_select, td_item = type_of(TALK_SELECT), type_of(LIST_INFO)
    method_of(td_select, TALK_SELECT, REQ_DISP_SIG)
    method_of(td_select, TALK_SELECT, "get_IsEndGUI()")
    field_of(td_select, TALK_SELECT, "SelectedIndex")
    for _, name in ipairs({ "Msg", "_IsDecideEnable", "ListenerType", "SpeakerType", "Listener" }) do
        field_of(td_item, LIST_INFO, name)
    end
    field_of(td_gm, GUI_MANAGER, "TalkSelect")
    field_of(td_tm, TALK_MANAGER, CURRENT_TALK_INFO)
    if not dialog.available then missing[#missing + 1] = "confirm dialog" end

    local function line(action, name, result)
        log.error(string.format("[Retinue] talk menu: %s %s: %s", action, name, result))
    end

    -- The current talk's node: node id, the choice ids in order, the speaker and the listener (CharacterIDs). nil when
    -- anything is unreadable.
    local function read_talk()
        local tm = sdk.get_managed_singleton(TALK_MANAGER)
        local info = tm and tm:get_field(CURRENT_TALK_INFO)
        local node = info and info:get_field(CURRENT_NODE)
        if node == nil then return nil end
        local node_id = guid_str(node:get_field("_NodeId"))
        local choices = elements(node:get_field("_Choices"))
        if node_id == nil or choices == nil then return nil end
        local choice_ids = {}
        for i, choice in ipairs(choices) do choice_ids[i] = guid_str(choice:get_field("_ChoiceId")) end
        return node_id, choice_ids, hooks.to_u32(info:get_field(SPEAKER)), hooks.to_u32(info:get_field(LISTENER))
    end

    -- The pre of reqDisp (args[2] the widget, args[3] the list): appends our row when this is the root menu of a hired pawn.
    local function on_req_disp(args)
        menu = nil
        if not dialog.available then return end -- the dialog call failed: a row would lead nowhere
        local widget = sdk.to_int64(args[2])
        local list = to_managed(args[3])
        if widget == nil or widget == 0 or list == nil then return end
        local node_id, choice_ids, speaker, listener = read_talk()
        if node_id == nil or not talk_menu.is_root(node_id, choice_ids) then return end
        local views = party.views()
        local view = talk_menu.view_of(views, speaker) or talk_menu.view_of(views, listener)
        local row = view and talk_menu.row(store, view, party.level(view))
        if row == nil then return end
        -- The pick is read on GuiManager.TalkSelect, so the widget showing this list must be that one. Checked after the row
        -- is known, so the line names a row that was withheld, not any menu of the game.
        local gm = sdk.get_managed_singleton(GUI_MANAGER)
        local select = gm and gm:get_field("TalkSelect")
        if select == nil or select:get_address() ~= widget then
            report("talk menu", "reqDisp widget is not GuiManager.TalkSelect")
            return
        end
        local count = list:call("get_Count")
        if type(count) ~= "number" or count < 1 then return end
        -- The same list handed to reqDisp twice (never seen): our row is already its last, and Never mind the one before it.
        -- No second row, but the redirect is armed again, so the row on screen never takes the game's unknown end path.
        local last = list:call("get_Item", count - 1)
        if last ~= nil and as_string(last:get_field("Msg")) == row.label then
            if count >= 2 then
                menu = { widget = widget, pos = count - 1, never_mind = count - 2, row = row, generation = store.generation }
            end
            return
        end
        -- The shop-choice entries carry no Listener of their own: copy the first entry's.
        local first = list:call("get_Item", 0)
        local item = first and sdk.create_instance(LIST_INFO)
        if item == nil then return end
        pcall(function() item:add_ref() end)
        pcall(function() item:call(".ctor") end)
        pcall(function() item:set_field("Listener", first:get_field("Listener")) end) -- nil on this menu
        item:set_field("ListenerType", first:get_field("ListenerType"))
        item:set_field("SpeakerType", first:get_field("SpeakerType"))
        item:set_field("_IsDecideEnable", true)
        item:set_field("Msg", sdk.create_managed_string(row.label))
        list:call("Add", item)
        menu = { widget = widget, pos = count, never_mind = count - 1, row = row, generation = store.generation }
    end

    if #missing == 0 then
        local ok, not_installed = hooks.install({
            { key = "ui021601.reqDisp", type = TALK_SELECT, sig = REQ_DISP_SIG, pre = on_req_disp },
        }, report)
        if ok then
            talk.available = true
        else
            for _, name in ipairs(not_installed) do missing[#missing + 1] = name end
        end
    end
    if #missing > 0 then
        report("talk menu", "unavailable, not found (game update?): " .. table.concat(missing, ", "))
    end

    -- The view in the party for this canonical Offline ID, nil when it left.
    local function view_by_id(id)
        for _, view in ipairs(party.views()) do
            if roster.canonical_id(view.offline_id) == id then return view end
        end
        return nil
    end

    local function act(row)
        local ok, err
        if row.action == "adopt" then
            local view = view_by_id(row.offline_id)
            if view then ok, err = store:adopt(view) else err = "not_in_party" end
        else
            ok, err = store:release(row.offline_id)
        end
        if ok then
            line(row.action, row.name, "done")
        else
            line(row.action, row.name, "refused (" .. tostring(err) .. ")")
            notify(labels.refused(row.action, row.name, err))
        end
    end

    -- The player picked our row: refuse at once, or ask.
    local function pick(row, generation, now)
        if store.generation ~= generation then return end
        local err = talk_menu.refusal(store, row.action)
        if err then
            line(row.action, row.name, "refused (" .. err .. ")")
            notify(labels.refused(row.action, row.name, err))
            return
        end
        local text = row.action == "adopt" and labels.ask_adopt(row.name) or labels.ask_release(row.name)
        if dialog.ask(text) then
            line(row.action, row.name, "asked")
            pending = { c = confirm.new(text, now), row = row, generation = generation }
        else
            log.error("[Retinue] talk menu: the confirm dialog did not open")
        end
    end

    -- The widget's state, then the redirect of a pick on our row to Never mind. Only an exact match acts: anything unread
    -- waits for the next frame.
    local function watch_menu(now)
        local gm = sdk.get_managed_singleton(GUI_MANAGER)
        local w = gm and gm:get_field("TalkSelect")
        if w == nil or w:get_address() ~= menu.widget then return end
        if w:call("get_IsEndGUI") ~= true then return end
        local selected = w:get_field("SelectedIndex")
        if type(selected) ~= "number" or math.tointeger(selected) ~= menu.pos then
            menu = nil -- another row was picked
            return
        end
        local m = menu
        w:set_field("SelectedIndex", m.never_mind)
        local back = w:get_field("SelectedIndex")
        menu = nil
        if type(back) ~= "number" or math.tointeger(back) ~= m.never_mind then
            report("talk menu", "SelectedIndex could not be redirected to Never mind")
            return
        end
        line(m.row.action, m.row.name, "picked")
        pick(m.row, m.generation, now)
    end

    local function watch_confirm(now)
        local res = pending.c:step(now, dialog.read())
        if res == nil then return end
        local p = pending
        pending = nil
        if store.generation ~= p.generation then
            line(p.row.action, p.row.name, "dropped (the roster changed)")
        elseif res == "yes" then
            act(p.row)
        elseif res == "no" then
            line(p.row.action, p.row.name, "no")
        else
            line(p.row.action, p.row.name, "confirm " .. res)
        end
    end

    function talk.tick(now)
        if not talk.available then return end
        if menu then
            local ok, err = pcall(watch_menu, now)
            if not ok then
                report("talk menu", err)
                menu = nil -- never repeat a half-done redirect
            end
        end
        if pending then
            local ok, err = pcall(watch_confirm, now)
            if not ok then
                report("talk menu", err)
                pending = nil
            end
        end
    end

    function talk.confirming()
        return pending ~= nil
    end

    return talk
end

return M
