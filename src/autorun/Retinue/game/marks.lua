-- REFramework glue: the Retinue marks on the game's own pages (uses sdk and log). The decisions (who is marked, the text a
-- name widget gets) are Retinue/marks.lua, the texts Retinue/labels.lua, the roster game/roster_store.lua, the levels
-- game/backup_store.lua.
--
-- Three surfaces, each its own hook group, looked up and installed all or nothing (findings 0009 P3, P4 and P7):
--   Status (pause > Status): in the post of ui060601_01.setupPawn, PawnInfo2Ref.setup and CharaChangeRef.updateName, the name
--     header of a present member (not the main pawn) is "<name> · Retinue", on both the page's PawnInfo.TxtName and
--     CharaTab.TxtName. The member is the CharaData's CopyOwner._OfflineID in the roster with status present.
--   Rift (Previous Hires): in the post of ui041401.ResItem.updateDisp, every roster member (any status) shows
--     "★ <name> · Lv N" (N the backup's level; "★ <name>" without one), matched by the ResInfo's OfflineId.
--   Status exp (pause > Status, Status and Vocation tabs): ui060601_01.setupStatus and setupJob show "-" for exp, discipline
--     and next level unless the CharaData's <IsMainPawn> is true (findings 0009 P7). For a present member the pre
--     sets that flag true and the post sets it back false, so only the call sees it and it is never left set. The Arisen,
--     the main pawn and a hired non-member are untouched (the same member rule as the Status header mark).
-- Every write starts from the shown text with our own mark stripped (marks.lua), so a refresh never stacks a mark and a reused
-- widget loses a stale one. A hook's pre keeps `this` and the argument on a stack for its post (the hook has no other way to
-- hand them over; the frame is pushed before it is filled, so a throwing read cannot leave the post with an older one). A missing type, method or field leaves that surface vanilla (menu line, one log line); an unreadable
-- widget or argument at run time writes nothing and is reported once. All of it runs on the game thread, inside the game's
-- calls.
local hooks = require("Retinue.hooks")
local marks_logic = require("Retinue.marks")

local M = {}

local UI_STATUS = "app.ui060601_01"
local PAWN_INFO = "app.GUIBase.PawnInfo2Ref"
local CHARA_TAB = "app.GUIBase.CharaChangeRef"
local CHARA_DATA = "app.GUIBase.CharaData"
local OWNER_CONTEXT = "app.PawnOwnerContext"
local RES_ITEM = "app.ui041401.ResItem"
local RES_INFO = "app.ui041401.ResInfo"
local GUI_TEXT = "via.gui.Text"

local SETUP_PAWN_SIG = "setupPawn(app.GUIBase.CharaData)"
local PAWN_INFO_SETUP_SIG = "setup(app.GUIBase.CharaData)"
local UPDATE_NAME_SIG = "updateName()"
local SELECTED_SIG = "get_SelectedCharaData()"
local SETUP_STATUS_SIG = "setupStatus(app.GUIBase.CharaData)"
local SETUP_JOB_SIG = "setupJob(app.GUIBase.CharaData)"
local UPDATE_DISP_SIG = "updateDisp(app.ui041401.ResInfo)"
local GET_MESSAGE_SIG = "get_Message()"
local SET_MESSAGE_SIG = "set_Message(System.String)"

local IS_MAIN_PAWN = "<IsMainPawn>k__BackingField"
local TEXTS_MAX = 6 -- TxtPawnName entries read from a list item
local STACK_MAX = 8 -- pending pre -> post frames per hook (a post that never came must not grow the stack for good)

-- M.new(report, deps) -> marks
--   deps = { store = game/roster_store's (store.roster is read at each call), backups = game/backup_store's (optional: no level) }
--   marks.status_available, marks.rift_available, marks.exp_available  booleans: that group's lookups passed and its hooks are installed
--   marks.missing  { string }  "<type>.<member>" not found (or not hookable), for the menu's "unavailable" lines
function M.new(report, deps)
    local marks = { status_available = false, rift_available = false, exp_available = false, missing = {} }
    local store, backups = deps.store, deps.backups
    local seen = {} -- "<group> <text>" -> true: the written texts already logged

    -- Everything the hooks use, looked up now so that a game update shows as one report line, not as a throw per refresh.
    -- Each lookup group collects what it did not find; the shared list for the menu has every name once.
    local function lookups()
        local group = { missing = {} }
        local function lose(name) group.missing[#group.missing + 1] = name end
        function group.type_of(name)
            local ok, td = pcall(sdk.find_type_definition, name)
            if ok and td then return td end
            lose(name)
            return nil
        end
        function group.method_of(td, type_name, sig)
            if td == nil then return end
            local ok, m = pcall(hooks.find_method, td, sig)
            if not (ok and m) then lose(type_name .. "." .. sig) end
        end
        function group.field_of(td, type_name, name)
            if td == nil then return end
            local ok, f = pcall(function() return td:get_field(name) end)
            if not (ok and f) then lose(type_name .. "." .. name) end
        end
        return group
    end

    local function add_missing(list)
        for _, name in ipairs(list) do
            local known = false
            for _, have in ipairs(marks.missing) do
                if have == name then known = true; break end
            end
            if not known then marks.missing[#marks.missing + 1] = name end
        end
    end

    -- The group is available only when nothing is missing; then its hooks go in (hooks.install is all or nothing too).
    local function finish(what, group, entries)
        if #group.missing == 0 then
            local ok, lost = hooks.install(entries, report)
            if ok then return true end
            group.missing = lost
        end
        add_missing(group.missing)
        report(what, "unavailable, not found (game update?): " .. table.concat(group.missing, ", "))
        return false
    end

    local function new_stack()
        local stack = {}
        return {
            push = function(frame)
                stack[#stack + 1] = frame
                if #stack > STACK_MAX then table.remove(stack, 1) end
            end,
            pop = function()
                local n = #stack
                if n == 0 then return nil end
                local frame = stack[n]
                stack[n] = nil
                return frame
            end,
        }
    end

    -- A widget's shown message (nil when unreadable).
    local function read(text)
        local ok, msg = pcall(function() return hooks.as_string(text:call("get_Message")) end)
        if ok then return msg end
        return nil
    end

    -- Writes `new` (nil: nothing) to the widget; a throw is reported, never raised. The first time a written text is seen
    -- it goes to the log, so the in-game run can grep for it without a line per refresh.
    local function apply(kind, what, text, new)
        if new == nil then return end
        local ok, err = pcall(function() text:call("set_Message", new) end)
        if not ok then
            report(kind .. " marks", what .. " set_Message failed: " .. tostring(err))
            return
        end
        local key = kind .. " " .. new
        if not seen[key] then
            seen[key] = true
            log.error(string.format("[Retinue] marked (%s): %s", kind, new))
        end
    end

    -- The mark on one widget: `decide(shown)` is marks.status_text / rift_text bound to the member.
    local function mark(kind, what, text, decide)
        if text == nil then
            report(kind .. " marks", what .. " unreadable")
            return
        end
        local shown = read(text)
        if shown == nil then
            report(kind .. " marks", what .. " message unreadable")
            return
        end
        apply(kind, what, text, decide(shown))
    end

    -- ---- Status ----

    local status_lookups = lookups()
    do
        local g = status_lookups
        local td_ui, td_info, td_tab = g.type_of(UI_STATUS), g.type_of(PAWN_INFO), g.type_of(CHARA_TAB)
        local td_data, td_owner, td_text = g.type_of(CHARA_DATA), g.type_of(OWNER_CONTEXT), g.type_of(GUI_TEXT)
        g.field_of(td_ui, UI_STATUS, "PawnInfo")
        g.field_of(td_ui, UI_STATUS, "CharaTab")
        g.method_of(td_ui, UI_STATUS, SETUP_PAWN_SIG)
        g.field_of(td_info, PAWN_INFO, "TxtName")
        g.method_of(td_info, PAWN_INFO, PAWN_INFO_SETUP_SIG)
        g.field_of(td_tab, CHARA_TAB, "TxtName")
        g.method_of(td_tab, CHARA_TAB, UPDATE_NAME_SIG)
        g.method_of(td_tab, CHARA_TAB, SELECTED_SIG)
        g.field_of(td_data, CHARA_DATA, "CopyOwner")
        g.field_of(td_data, CHARA_DATA, IS_MAIN_PAWN)
        g.field_of(td_owner, OWNER_CONTEXT, "_OfflineID")
        g.method_of(td_text, GUI_TEXT, GET_MESSAGE_SIG)
        g.method_of(td_text, GUI_TEXT, SET_MESSAGE_SIG)
    end

    -- Is this CharaData a present member that is not the main pawn? nil when the CharaData is unreadable.
    local function status_member(cd)
        if cd == nil then return nil end
        local owner = cd:get_field("CopyOwner")
        local id = owner ~= nil and hooks.guid_str(owner:get_field("_OfflineID")) or nil
        local is_main = cd:get_field(IS_MAIN_PAWN) == true
        return marks_logic.status_member(store.roster, id, is_main)
    end

    -- The header text of one widget, for a CharaData (nil: unreadable, nothing written).
    local function mark_status(what, text, cd)
        if cd == nil then
            report("status marks", what .. ": CharaData unreadable")
            return
        end
        local member = status_member(cd)
        mark("status", what, text, function(shown) return marks_logic.status_text(shown, member) end)
    end

    local setup_pawn_stack, pawn_info_stack, update_name_stack = new_stack(), new_stack(), new_stack()

    local status_entries = {
        { key = "marks.setupPawn", type = UI_STATUS, sig = SETUP_PAWN_SIG,
          pre = function(args)
              if not marks.status_available then return end
              local frame = {}
              setup_pawn_stack.push(frame)
              frame.this = hooks.to_managed(args[2])
              frame.arg = hooks.to_managed(args[3])
          end,
          post = function()
              local frame = setup_pawn_stack.pop()
              if frame == nil then return end
              local page = frame.this
              if page == nil then
                  report("status marks", "status page unreadable")
                  return
              end
              -- Both refs are nil at this post in game (findings 0009's run, ticket 26 run 1): the PawnInfo2Ref.setup and
              -- updateName posts write the header then. A nil ref is skipped without a report; a ref that is there is marked.
              local info, tab = page:get_field("PawnInfo"), page:get_field("CharaTab")
              if info ~= nil then mark_status("PawnInfo.TxtName", info:get_field("TxtName"), frame.arg) end
              if tab ~= nil then mark_status("CharaTab.TxtName", tab:get_field("TxtName"), frame.arg) end
          end },
        { key = "marks.PawnInfo2Ref.setup", type = PAWN_INFO, sig = PAWN_INFO_SETUP_SIG,
          pre = function(args)
              if not marks.status_available then return end
              local frame = {}
              pawn_info_stack.push(frame)
              frame.this = hooks.to_managed(args[2])
              frame.arg = hooks.to_managed(args[3])
          end,
          post = function()
              local frame = pawn_info_stack.pop()
              if frame == nil then return end
              if frame.this == nil then
                  report("status marks", "PawnInfo2Ref unreadable")
                  return
              end
              mark_status("PawnInfo2Ref.TxtName", frame.this:get_field("TxtName"), frame.arg)
          end },
        { key = "marks.CharaChangeRef.updateName", type = CHARA_TAB, sig = UPDATE_NAME_SIG,
          pre = function(args)
              if not marks.status_available then return end
              local frame = {}
              update_name_stack.push(frame)
              frame.this = hooks.to_managed(args[2])
          end,
          post = function()
              local frame = update_name_stack.pop()
              if frame == nil then return end
              local this = frame.this
              if this == nil then
                  report("status marks", "CharaChangeRef unreadable")
                  return
              end
              mark_status("CharaChangeRef.TxtName", this:get_field("TxtName"), this:call("get_SelectedCharaData"))
          end },
    }

    marks.status_available = finish("status marks", status_lookups, status_entries)

    -- ---- Status exp (a member's exp and next level on the Status and Vocation tabs) ----

    local exp_lookups = lookups()
    do
        local g = exp_lookups
        local td_ui, td_data, td_owner = g.type_of(UI_STATUS), g.type_of(CHARA_DATA), g.type_of(OWNER_CONTEXT)
        g.method_of(td_ui, UI_STATUS, SETUP_STATUS_SIG)
        g.method_of(td_ui, UI_STATUS, SETUP_JOB_SIG)
        g.field_of(td_data, CHARA_DATA, "CopyOwner")
        g.field_of(td_data, CHARA_DATA, IS_MAIN_PAWN)
        g.field_of(td_owner, OWNER_CONTEXT, "_OfflineID")
    end

    -- The flag back to false on a CharaData whose frame set it (a throw is reported, never raised).
    local function restore_exp(frame)
        if not frame.flipped then return end
        local ok, err = pcall(function() frame.cd:set_field(IS_MAIN_PAWN, false) end)
        if not ok then report("status exp", "restore failed: " .. tostring(err)) end
    end

    -- One hook of the group. The pre sets IsMainPawn true on a present member's CharaData and the post puts it back, so the
    -- game's setup (which gates the numbers on that flag) sees it only for the call. status_member requires the flag false,
    -- so the flag is only ever written back on a CharaData we set.
    local function exp_entry(key, sig)
        local stack = new_stack()
        return { key = key, type = UI_STATUS, sig = sig,
          pre = function(args)
              if not marks.exp_available then return end
              -- a post that never came: put its flag back before this call's frame goes on
              local stale = stack.pop()
              if stale ~= nil then
                  while stale ~= nil do
                      restore_exp(stale)
                      stale = stack.pop()
                  end
                  report("status exp", "a post did not run; flag restored")
              end
              local frame = {}
              stack.push(frame)
              local step = "CharaData read"
              local ok, err = pcall(function()
                  frame.cd = hooks.to_managed(args[3])
                  if frame.cd ~= nil and status_member(frame.cd) == true then
                      step = "IsMainPawn set"
                      frame.cd:set_field(IS_MAIN_PAWN, true)
                      frame.flipped = true
                      step = "log"
                      local id = hooks.guid_str(frame.cd:get_field("CopyOwner"):get_field("_OfflineID"))
                      local seen_key = "exp " .. tostring(id)
                      if not seen[seen_key] then
                          seen[seen_key] = true
                          log.error(string.format("[Retinue] status exp: shown for member %s", tostring(id)))
                      end
                  end
              end)
              if not ok then report("status exp", step .. " failed: " .. tostring(err)) end
          end,
          post = function()
              local frame = stack.pop()
              if frame ~= nil then restore_exp(frame) end
          end }
    end

    marks.exp_available = finish("status exp", exp_lookups, {
        exp_entry("marks.setupStatus", SETUP_STATUS_SIG),
        exp_entry("marks.setupJob", SETUP_JOB_SIG),
    })

    -- ---- Rift (Previous Hires) ----

    local rift_lookups = lookups()
    do
        local g = rift_lookups
        local td_item, td_info, td_text = g.type_of(RES_ITEM), g.type_of(RES_INFO), g.type_of(GUI_TEXT)
        g.field_of(td_item, RES_ITEM, "TxtPawnName")
        g.method_of(td_item, RES_ITEM, UPDATE_DISP_SIG)
        g.field_of(td_info, RES_INFO, "OfflineId")
        g.method_of(td_text, GUI_TEXT, GET_MESSAGE_SIG)
        g.method_of(td_text, GUI_TEXT, SET_MESSAGE_SIG)
    end

    -- The backup's level of a member (nil when unknown or unreadable).
    local function level_of(id)
        if backups == nil then return nil end
        local ok, level = pcall(backups.level, id)
        if ok then return level end
        return nil
    end

    -- The widgets of a via.gui.Text[] (at most TEXTS_MAX), nil when unreadable. get_elements() fails on this array in game
    -- (ticket 26 run 1, as on a talk node's _Choices in ticket 24), so get_Length / GetValue follow, as the experiment read it.
    local function text_array(arr)
        local ok, elems = pcall(function() return arr:get_elements() end)
        if ok and type(elems) == "table" and #elems > 0 then return elems end
        local okn, n = pcall(function() return arr:call("get_Length") end)
        n = okn and type(n) == "number" and math.tointeger(n) or nil
        if n == nil or n < 0 then return nil end
        local out = {}
        for i = 0, math.min(n, TEXTS_MAX) - 1 do
            local oki, v = pcall(function() return arr:call("GetValue", i) end)
            if not oki or v == nil then return nil end
            out[i + 1] = v
        end
        return out
    end

    local update_disp_stack = new_stack()

    local rift_entries = {
        { key = "marks.ResItem.updateDisp", type = RES_ITEM, sig = UPDATE_DISP_SIG,
          pre = function(args)
              if not marks.rift_available then return end
              local frame = {}
              update_disp_stack.push(frame)
              frame.this = hooks.to_managed(args[2])
              frame.arg = hooks.to_managed(args[3])
          end,
          post = function()
              local frame = update_disp_stack.pop()
              if frame == nil then return end
              local item, info = frame.this, frame.arg
              if item == nil or info == nil then
                  report("rift marks", "list item or entry unreadable")
                  return
              end
              local member = marks_logic.rift_member(store.roster, hooks.guid_str(info:get_field("OfflineId")))
              local level = member and level_of(member.offline_id) or nil
              local arr = item:get_field("TxtPawnName")
              if arr == nil then
                  report("rift marks", "TxtPawnName unreadable")
                  return
              end
              local texts = text_array(arr)
              if texts == nil then
                  report("rift marks", "TxtPawnName elements unreadable")
                  return
              end
              for i = 1, math.min(#texts, TEXTS_MAX) do
                  mark("rift", "TxtPawnName[" .. i .. "]", texts[i], function(shown)
                      return marks_logic.rift_text(shown, member ~= nil, level)
                  end)
              end
          end },
    }

    marks.rift_available = finish("rift marks", rift_lookups, rift_entries)

    return marks
end

return M
