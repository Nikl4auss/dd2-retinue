-- REFramework glue: the extra row of the talk menu of a hired party pawn ("Adopt" / "Release"), its confirm inside the talk
-- and the action (uses sdk and log). The decisions are Retinue/talk_menu.lua (menu, pawn, row, picks, refusal), the texts
-- Retinue/labels.lua, the adopt and release game/roster_store.lua.
--
-- How it works (findings 0007): in the pre of ui021601.reqDisp, the widget that shows the talk's choice list, a ListInfo
-- inserted into the list before Never mind shows as a fourth row, so Never mind keeps the game's index. When the player picks
-- it (the widget's GUI ended with SelectedIndex on it), SelectedIndex is rewritten to Talk (row 0), so the talk goes on to the
-- Talk sub-menu; there its next reqDisp relabels the rows: "Confirm adopt" / "Confirm release" in place of Matters of
-- import, Small talk removed, Cancel untouched. Picking the confirm acts, any other pick cancels, and
-- both are rewritten to Cancel (row 2), which returns to the root menu. Two nextNode guards back up a failed rewrite: on the
-- root, after our pick, any choice but Talk becomes Never mind; on the Talk sub-menu, after the confirm pick, Matters of import
-- or Small talk becomes Cancel. A full retinue with an away member takes the same road, but its Talk sub-menu shows "Release
-- <name> (away, Lv N)" per away member (rows 0 and 1, Cancel last); picking one releases that member and adopts the pawn.
-- Anything unknown, missing or thrown leaves the menu vanilla. All of it runs on the game
-- thread: the hooks inside the game's calls, tick() in Retinue.lua's UpdateBehavior callback.
local hooks = require("Retinue.hooks")
local labels = require("Retinue.labels")
local roster = require("Retinue.roster")
local talk_menu = require("Retinue.talk_menu")

local M = {}

local GUI_MANAGER = "app.GuiManager"
local TALK_MANAGER = "app.TalkEventManager"
local TALK_SELECT = "app.ui021601"
local LIST_INFO = "app.ui021601.ListInfo"
local TALK_PLAYER = "app.TalkEventPlayer"

local REQ_DISP_SIG = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
    .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)"

local NEXT_NODE_SIG = "nextNode(System.Int32)"

local CURRENT_TALK_INFO = "<CurrentTalkInfo>k__BackingField"
local CURRENT_NODE = "<CurrentNode>k__BackingField"
local SPEAKER = "<Speaker>k__BackingField"
local LISTENER = "<Listener>k__BackingField"
local CHOICES_MAX = 16 -- entries read from a node's _Choices
local CONFIRM_SECONDS = 5 -- how long our pick on the root menu waits for the Talk sub-menu to show
local GUARD_SECONDS = 2 -- how long either nextNode guard (root after our pick, sub-menu after the confirm) waits for its nextNode

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

-- The elements of a managed array or List as a Lua array, at most CHOICES_MAX; nil when unreadable. get_elements() comes
-- first; ticket 24 run 2 saw it fail on a node's _Choices, so a List (get_Count / get_Item) and an array (get_Length /
-- GetValue, as the experiment read it) follow. A count above CHOICES_MAX is unreadable: is_root needs the last choice.
local function by_index(arr, count_method, item_method)
    local ok, n = pcall(function() return arr:call(count_method) end)
    if not (ok and math.type(n) == "integer") or n < 0 or n > CHOICES_MAX then return nil end
    local out = {}
    for i = 0, n - 1 do
        local oki, v = pcall(function() return arr:call(item_method, i) end)
        if not oki or v == nil then return nil end
        out[i + 1] = v
    end
    return out
end

local function elements(arr)
    if arr == nil then return nil end
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" and #elems > 0 and #elems <= CHOICES_MAX then return elems end
    return by_index(arr, "get_Count", "get_Item") or by_index(arr, "get_Length", "GetValue")
end

-- M.new(report, deps) -> talk
--   deps = { store = game/roster_store's, party = game/party's, notify = function(text), clock = function() -> seconds (optional),
--            backups = game/backup_store's (optional: the away members' levels) }
--   talk.available   boolean  everything below was found and the hooks are installed
--   talk.missing     { string }  what was not found, for the menu's "unavailable" lines
--   talk.tick(now)   -- once per UpdateBehavior, on the game thread: the picks on our row and on the confirm, the action
function M.new(report, deps)
    local talk = { available = false, missing = {} }
    local missing = talk.missing
    local store, party, notify = deps.store, deps.party, deps.notify
    local backups = deps.backups
    local clock = deps.clock or os.clock -- the hooks have no tick's `now`

    -- the menu we changed: { mode = "offer" | "confirm" | "full", widget, row, generation, count (offer: vanilla rows),
    -- full (full: the away members shown), label (confirm, full: row 0's text) }
    local menu = nil
    -- our pick on the root menu, waiting for the Talk sub-menu: { row, generation, deadline, full (the away members, when the retinue is full) }
    local armed = nil
    local guard = nil -- the confirm pick's rewrite to Cancel, waiting for its nextNode on the Talk sub-menu: { deadline }
    local root_guard = nil -- our pick's rewrite to Talk, waiting for its nextNode on the root menu: { deadline }

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
    local td_select, td_item, td_player = type_of(TALK_SELECT), type_of(LIST_INFO), type_of(TALK_PLAYER)
    method_of(td_select, TALK_SELECT, REQ_DISP_SIG)
    method_of(td_select, TALK_SELECT, "get_IsEndGUI()")
    method_of(td_player, TALK_PLAYER, NEXT_NODE_SIG)
    field_of(td_select, TALK_SELECT, "SelectedIndex")
    for _, name in ipairs({ "Msg", "_IsDecideEnable", "ListenerType", "SpeakerType", "Listener" }) do
        field_of(td_item, LIST_INFO, name)
    end
    field_of(td_gm, GUI_MANAGER, "TalkSelect")
    field_of(td_tm, TALK_MANAGER, CURRENT_TALK_INFO)

    -- A node's id and its choice ids in order (lowercase GUID strings). nil when the node or its id is unreadable; choice_ids
    -- nil when _Choices is unreadable (is_root and is_talk_sub are then false).
    local function decode_node(node)
        if node == nil then return nil end
        local node_id = guid_str(node:get_field("_NodeId"))
        local choices = elements(node:get_field("_Choices"))
        if node_id == nil then return nil end
        local choice_ids = nil
        if choices ~= nil then
            choice_ids = {}
            for i, choice in ipairs(choices) do choice_ids[i] = guid_str(choice:get_field("_ChoiceId")) end
        end
        return node_id, choice_ids
    end

    local function talk_info()
        local tm = sdk.get_managed_singleton(TALK_MANAGER)
        return tm and tm:get_field(CURRENT_TALK_INFO)
    end

    -- The current talk's node (see decode_node), then the speaker and the listener (CharacterIDs; nil when unreadable).
    local function read_talk()
        local info = talk_info()
        local node = info and info:get_field(CURRENT_NODE)
        local node_id, choice_ids = decode_node(node)
        if node_id == nil then return nil end
        return node_id, choice_ids, hooks.to_u32(info:get_field(SPEAKER)), hooks.to_u32(info:get_field(LISTENER))
    end

    -- The pick is read on GuiManager.TalkSelect, so the widget showing a list must be that one.
    local function talk_select()
        local gm = sdk.get_managed_singleton(GUI_MANAGER)
        return gm and gm:get_field("TalkSelect")
    end

    local function is_talk_select(widget)
        local select = talk_select()
        if select == nil or select:get_address() ~= widget then
            report("talk menu", "reqDisp widget is not GuiManager.TalkSelect")
            return false
        end
        return true
    end

    local function line(action, name, result)
        log.error(string.format("[Retinue] talk menu: %s %s: %s", action, name, result))
    end

    -- The backup's level of a member (nil when unknown or unreadable).
    local function level_of(id)
        if backups == nil then return nil end
        local ok, level = pcall(backups.level, id)
        if ok then return level end
        return nil
    end

    -- The Talk sub-menu showing after our pick: row 0 relabelled as the confirm, row 1 (Small talk) removed, Cancel as the game
    -- has it, now shown second. Every pick is written to the game's Cancel (index 2); a missed write on the shown Cancel would
    -- run Small talk, which the nextNode guard turns into Cancel. No warning row: the user found a disabled row still takes the
    -- cursor, and the gear question waits for M4 (2026-11-08).
    local function show_confirm(list, widget, c)
        local count = list:call("get_Count")
        if count ~= 3 then
            report("talk menu", "Talk sub-menu list has " .. tostring(count) .. " rows")
            return
        end
        local adopt = c.row.action == "adopt"
        local confirm_row = list:call("get_Item", 0)
        if confirm_row == nil then return end
        if c.full then
            -- The sub-menu has two rows before Cancel: more away members (a higher CAP) would put a member on Cancel's index.
            if #c.full > 2 then
                report("talk menu", "more than 2 away members")
                return
            end
            -- A full retinue: one row per away member in place of Matters of import and Small talk (a second row kept only
            -- for a second member), Cancel as the game has it.
            local second = c.full[2] and list:call("get_Item", 1)
            if c.full[2] and second == nil then return end
            local label = labels.release_away(c.full[1].name, c.full[1].level)
            confirm_row:set_field("Msg", sdk.create_managed_string(label))
            confirm_row:set_field("_IsDecideEnable", true)
            if second then
                second:set_field("Msg", sdk.create_managed_string(labels.release_away(c.full[2].name, c.full[2].level)))
                second:set_field("_IsDecideEnable", true)
            else
                list:call("RemoveAt", 1)
            end
            menu = { mode = "full", widget = widget, row = c.row, generation = c.generation, full = c.full, label = label }
            return
        end
        local confirm_label = adopt and labels.confirm_adopt() or labels.confirm_release()
        confirm_row:set_field("Msg", sdk.create_managed_string(confirm_label))
        confirm_row:set_field("_IsDecideEnable", true)
        list:call("RemoveAt", 1)
        menu = { mode = "confirm", widget = widget, row = c.row, generation = c.generation, label = confirm_label }
    end

    -- The root menu of a hired pawn: our row before Never mind.
    local function offer_row(list, widget, node_id, choice_ids, speaker, listener)
        if not talk_menu.is_root(node_id, choice_ids) then
            -- The root node's id with choices that do not qualify (unreadable, or Talk not first, or Never mind not last): after
            -- a game update the row would vanish without a word (ticket 24 runs 1-2). Logged once per distinct case.
            if node_id == talk_menu.ROOT_NODE then
                report("talk menu", string.format("root menu not recognised: %s choices, first %s, last %s",
                    choice_ids and #choice_ids or "unreadable", choice_ids and tostring(choice_ids[1]) or "-",
                    choice_ids and tostring(choice_ids[#choice_ids]) or "-"))
            end
            return
        end
        local views = party.views()
        local view = talk_menu.view_of(views, speaker) or talk_menu.view_of(views, listener)
        local row = view and talk_menu.row(store, view, party.level(view))
        if row == nil then return end
        -- Checked after the row is known, so the line names a row that was withheld, not any menu of the game.
        if not is_talk_select(widget) then return end
        local count = list:call("get_Count")
        if type(count) ~= "number" or count < 1 then return end
        -- The same list handed to reqDisp twice (never seen): our row is already before its last, Never mind. No second row,
        -- but the pick is watched again, so the row on screen never takes the game's unknown end path.
        local before = count >= 2 and list:call("get_Item", count - 2)
        if before and as_string(before:get_field("Msg")) == row.label then
            menu = { mode = "offer", widget = widget, count = count - 1, row = row, generation = store.generation }
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
        list:call("Insert", count - 1, item) -- Never mind stays last, and keeps the game's index among the game's rows
        menu = { mode = "offer", widget = widget, count = count, row = row, generation = store.generation }
    end

    -- The pre of reqDisp (args[2] the widget, args[3] the list): the confirm after our pick, or our row on a hired pawn's
    -- root menu. Any failure leaves the list alone.
    local function on_req_disp(args)
        if not talk.available then return end
        -- A new menu: the guards belong to the one before it (each guarded nextNode comes before the next reqDisp), so a
        -- late watcher's guard never touches the root of another talk.
        root_guard, guard = nil, nil
        local prev = menu
        menu = nil
        local widget = sdk.to_int64(args[2])
        local list = to_managed(args[3])
        if widget == nil or widget == 0 or list == nil then return end
        local node_id, choice_ids, speaker, listener = read_talk()
        if armed then
            local c = armed
            armed = nil -- one shot: this menu, or it is dropped
            if node_id ~= nil and clock() < c.deadline and talk_menu.is_talk_sub(node_id, choice_ids) then
                if is_talk_select(widget) then show_confirm(list, widget, c) end
                return
            end
            line(c.row.action, c.row.name, "dropped (another menu came first)")
        end
        -- The same Talk sub-menu list handed to reqDisp twice (never seen): its first row already reads as the confirm. Watched
        -- again, so a pick there is still ours and not the game's Matters of import.
        if prev and (prev.mode == "confirm" or prev.mode == "full") and node_id ~= nil and talk_menu.is_talk_sub(node_id, choice_ids)
            and is_talk_select(widget) then
            local first = list:call("get_Item", 0)
            if first and as_string(first:get_field("Msg")) == prev.label then
                prev.widget = widget
                menu = prev
                return
            end
        end
        if node_id == nil then return end
        offer_row(list, widget, node_id, choice_ids, speaker, listener)
    end

    -- The node a nextNode call leaves: the player's _CurrentNode, else the talk info's.
    local function current_node(args)
        local player = to_managed(args[2])
        local node = nil
        if player then
            local ok, n = pcall(function() return player:get_field("_CurrentNode") end)
            if ok then node = n end
        end
        if node == nil then
            local info = talk_info()
            node = info and info:get_field(CURRENT_NODE)
        end
        return node
    end

    -- The pre of TalkEventPlayer.nextNode (args[3] the index). Two rewrites back up a failed SelectedIndex write:
    -- after our pick, the first nextNode on the root menu must be Talk (row 0 may not be Talk's choice after a game update;
    -- anything else becomes Never mind, the last choice); after the confirm pick, the first nextNode on the Talk sub-menu
    -- must be Cancel, never Matters of import or Small talk.
    local function on_next_node(args)
        if not talk.available then return end
        if guard == nil and root_guard == nil then return end
        local node_id, choice_ids = decode_node(current_node(args))
        if node_id == nil then return end
        local idx = hooks.arg_i32(args[3])
        if root_guard and talk_menu.is_root(node_id, choice_ids) then
            local g = root_guard
            root_guard = nil -- consumed by this call
            if clock() < g.deadline and idx ~= 0 and idx ~= #choice_ids - 1 then
                args[3] = sdk.to_ptr(#choice_ids - 1)
                armed = nil
                report("talk menu", string.format("nextNode(%d) on the root menu rewritten to Never mind", idx))
            end
        elseif guard and talk_menu.is_talk_sub(node_id, choice_ids) then
            local g = guard
            guard = nil
            if clock() < g.deadline and idx ~= talk_menu.CANCEL_INDEX then
                args[3] = sdk.to_ptr(talk_menu.CANCEL_INDEX)
                report("talk menu", string.format("nextNode(%d) on the Talk sub-menu rewritten to Cancel", idx))
            end
        end
    end

    if #missing == 0 then
        local ok, not_installed = hooks.install({
            { key = "ui021601.reqDisp", type = TALK_SELECT, sig = REQ_DISP_SIG, pre = on_req_disp },
            { key = "TalkEventPlayer.nextNode", type = TALK_PLAYER, sig = NEXT_NODE_SIG, pre = on_next_node },
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

    -- The full retinue's pick: release the away member, then adopt the pawn talked to. The pawn must still be in the party
    -- and the member still away before anything is released; a failed release adopts nothing.
    local function act_full(row, member)
        local current = roster.find(store.roster, member.offline_id)
        if current == nil or current.status ~= roster.AWAY then
            line("release", member.name, "refused (not_adopted)")
            notify(labels.refused("release", member.name, "not_adopted"))
            return
        end
        local view = view_by_id(row.offline_id)
        if view == nil then
            line(row.action, row.name, "refused (not_in_party)")
            notify(labels.refused("adopt", row.name, "not_in_party"))
            return
        end
        local ok, err = store:release(member.offline_id)
        if not ok then
            line("release", member.name, "refused (" .. tostring(err) .. ")")
            notify(labels.refused("release", member.name, err))
            return
        end
        line("release", member.name, "done")
        ok, err = store:adopt(view)
        if ok then
            line(row.action, row.name, "done")
        else
            line(row.action, row.name, "refused (" .. tostring(err) .. ")")
            notify(labels.refused("adopt", row.name, err))
        end
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

    -- SelectedIndex := n, read back; true when it stuck.
    local function write_index(w, n)
        w:set_field("SelectedIndex", n)
        local back = w:get_field("SelectedIndex")
        return type(back) == "number" and math.tointeger(back) == n
    end

    -- The pick on the root menu. Our row goes to Talk and arms the confirm; a refusal writes nothing, so the game runs
    -- Never mind (our row's index is Never mind's own) and the talk ends; the shown Never mind is written back.
    local function watch_offer(w, m, now)
        local selected = w:get_field("SelectedIndex")
        local p = talk_menu.offer_pick(type(selected) == "number" and math.tointeger(selected) or nil, m.count)
        menu = nil
        if p.kind == "other" then return end -- another row, or unreadable
        if p.kind == "never_mind" then
            if not write_index(w, p.write) then report("talk menu", "SelectedIndex could not be redirected to Never mind") end
            return
        end
        local row = m.row
        if store.generation ~= m.generation then
            line(row.action, row.name, "dropped (the roster changed)")
            return
        end
        local err, away = talk_menu.refusal(store, row.action, level_of)
        if err then
            line(row.action, row.name, "refused (" .. err .. ")")
            notify(labels.refused(row.action, row.name, err))
            return
        end
        if not write_index(w, p.write) then
            report("talk menu", "SelectedIndex could not be redirected to Talk") -- it stays on our row: Never mind runs
            return
        end
        line(row.action, row.name, away and string.format("picked (full: %d away)", #away) or "picked")
        armed = { row = row, generation = m.generation, deadline = now + CONFIRM_SECONDS, full = away }
        root_guard = { deadline = now + GUARD_SECONDS }
    end

    -- The pick on the confirm: the first row acts, anything else cancels; both go back through Cancel.
    local function watch_confirm(w, m, now)
        local selected = w:get_field("SelectedIndex")
        guard = { deadline = now + GUARD_SECONDS } -- first: whatever the pick, the talk goes on through Cancel
        if type(selected) ~= "number" or math.tointeger(selected) == nil then
            menu = nil
            return
        end
        local p = talk_menu.confirm_pick(math.tointeger(selected))
        menu = nil
        local row = m.row
        if p.kind == "confirm" then
            if store.generation ~= m.generation then
                line(row.action, row.name, "dropped (the roster changed)")
            else
                line(row.action, row.name, "confirmed")
                local ok, err = pcall(act, row)
                if not ok then report("talk menu", err) end
            end
        else
            line(row.action, row.name, "cancelled")
        end
        if not write_index(w, p.write) then
            report("talk menu", "SelectedIndex could not be redirected to Cancel") -- the nextNode guard follows
        end
    end

    -- The pick on the full retinue's sub-menu: a member row releases it and adopts the pawn, anything else cancels; both go
    -- back through Cancel.
    local function watch_full(w, m, now)
        local selected = w:get_field("SelectedIndex")
        guard = { deadline = now + GUARD_SECONDS } -- first: whatever the pick, the talk goes on through Cancel
        if type(selected) ~= "number" or math.tointeger(selected) == nil then
            menu = nil
            return
        end
        local p = talk_menu.full_pick(math.tointeger(selected), #m.full)
        menu = nil
        local row = m.row
        if p.kind == "release" then
            local member = m.full[p.index]
            if store.generation ~= m.generation then
                line(row.action, row.name, "dropped (the roster changed)")
            else
                line(row.action, row.name, "confirmed (release " .. member.name .. ")")
                local ok, err = pcall(act_full, row, member)
                if not ok then report("talk menu", err) end
            end
        else
            line(row.action, row.name, "cancelled")
        end
        if not write_index(w, p.write) then
            report("talk menu", "SelectedIndex could not be redirected to Cancel") -- the nextNode guard follows
        end
    end

    -- The widget's state, then the rewrite of a pick. Only an exact match acts: anything unread waits for the next frame.
    local function watch_menu(now)
        local w = talk_select()
        if w == nil or w:get_address() ~= menu.widget then return end
        if w:call("get_IsEndGUI") ~= true then return end
        local m = menu
        if m.mode == "offer" then
            watch_offer(w, m, now)
        elseif m.mode == "full" then
            watch_full(w, m, now)
        else
            watch_confirm(w, m, now)
        end
    end

    function talk.tick(now)
        if not talk.available then return end
        if armed and now >= armed.deadline then
            line(armed.row.action, armed.row.name, "dropped (the Talk sub-menu did not show)")
            armed = nil
        end
        if guard and now >= guard.deadline then guard = nil end
        if root_guard and now >= root_guard.deadline then root_guard = nil end
        if menu then
            local ok, err = pcall(watch_menu, now)
            if not ok then
                report("talk menu", err)
                menu = nil -- never repeat a half-done rewrite
            end
        end
    end

    return talk
end

return M
