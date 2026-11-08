-- The talk menu's extra row for a hired party pawn: which pawn, which row, whether the pick is refused, and what a pick
-- on the root menu or on the confirm (the Talk sub-menu) does. Pure: no REFramework globals, so it runs under plain Lua in
-- tests; game/talk_menu.lua reads the menu and acts on the pick.
local labels = require("Retinue.labels")
local roster = require("Retinue.roster")

local M = {}

-- The root menu of a hired pawn's talk: an app.ShopChoiceNode with 10 choices (findings 0007). GUIDs, lowercase.
M.ROOT_NODE = "4c4acb4e-1531-45ea-9f6a-e4152e473e2e"
M.DISMISS = "7d3962d3-10ca-4c11-805e-f2df655f1f10"
M.NEVER_MIND = "cde9623d-2e45-424a-b326-daa8c3b7078c"
M.TALK_CHOICE = "3a367899-f31c-46fc-b2e1-57f521e8ea0f" -- the root's first choice, Talk
-- The Talk sub-menu (a ShopChoiceNode of 3 choices: Matters of import, Small talk, Cancel); Cancel goes back to the root.
M.TALK_SUB = "44dcab9b-2a86-4ab0-bd52-24dde93cfe60"
M.CANCEL = "be249585-0fae-4db8-aa33-5113e5d98ea6"
M.CANCEL_INDEX = 2 -- Cancel's row (and choice index) in the Talk sub-menu

-- is_root(node_id, choice_ids) -> boolean. node_id: the current node's _NodeId, choice_ids: the _ChoiceId of each of its
-- _Choices in order (lowercase GUID strings). The node counts as the root menu by its id, or by holding Dismiss (the
-- id could change in an update); either way Never mind must be the last choice (our row goes before it, and a pick of the
-- last shown row is written back to it) and Talk the first (a pick on our row is redirected to row 0).
function M.is_root(node_id, choice_ids)
    if type(choice_ids) ~= "table" or choice_ids[#choice_ids] ~= M.NEVER_MIND then return false end
    if choice_ids[1] ~= M.TALK_CHOICE then return false end
    if node_id == M.ROOT_NODE then return true end
    for _, id in ipairs(choice_ids) do
        if id == M.DISMISS then return true end
    end
    return false
end

-- view_of(views, character_id) -> the hired pawn's view (party slot 1 or 2) with this CharacterID, or nil: the main
-- pawn (slot 0), an unknown id and a nil id give nil.
function M.view_of(views, character_id)
    if character_id == nil then return nil end
    for _, view in ipairs(views) do
        if (view.slot == 1 or view.slot == 2) and view.character_id == character_id then return view end
    end
    return nil
end

-- row(store, view, level) -> nil | { action = "adopt" | "release", label, offline_id, name }
-- store: roster_store's fields { roster, found, ambiguous }. A member in the party gets Release, a Rift pawn that is
-- not a member gets Adopt; everything else (an online pawn, an ambiguous id, a member that matches another view) gets
-- nothing. A nil, locked or read-only roster still gives the row: the pick says why it cannot be done.
function M.row(store, view, level)
    if view == nil then return nil end
    local id = roster.canonical_id(view.offline_id)
    if id == nil or store.ambiguous[id] then return nil end
    local member = roster.find(store.roster, id)
    if member then
        local found = store.found[id]
        if found == nil or found.character_id == nil or found.character_id ~= view.character_id then return nil end
        return { action = "release", label = labels.release_row(level), offline_id = id, name = member.name }
    end
    if roster.adoptable(view) == nil then return nil end
    local name = view.name
    if type(name) ~= "string" or name == "" then name = roster.UNKNOWN_NAME end
    return { action = "adopt", label = labels.adopt_row(), offline_id = id, name = name }
end

-- refusal(store, action) -> err | nil, checked when the row is picked, before the confirm (the same errors as roster.adopt / release).
function M.refusal(store, action)
    local r = store.roster
    if store.unit == nil or r == nil then return "no_slot" end
    if r.mode == roster.LOCKED then return "locked" end
    if r.mode == roster.READ_ONLY then return "read_only" end
    if action == "adopt" and #r.members >= roster.CAP then return "full" end
    return nil
end

-- is_talk_sub(node_id, choice_ids) -> boolean: the Talk sub-menu, by its node id or by Cancel as the last choice; exactly
-- 3 choices either way (the confirm relabels rows 0 and 1 and keeps row 2, Cancel).
function M.is_talk_sub(node_id, choice_ids)
    if type(choice_ids) ~= "table" or #choice_ids ~= 3 then return false end
    return node_id == M.TALK_SUB or choice_ids[3] == M.CANCEL
end

-- offer_pick(sel, count) -> { kind = "ours" | "never_mind" | "other", write = n | nil }: the pick on the root menu, whose
-- list holds count vanilla rows with our row inserted before Never mind (ours at count - 1, Never mind shown at count).
-- Ours is redirected to Talk (row 0), the shown Never mind to the game's (count - 1); anything else is left alone.
function M.offer_pick(sel, count)
    if math.type(sel) == "integer" and math.type(count) == "integer" then
        if sel == count - 1 then return { kind = "ours", write = 0 } end
        if sel == count then return { kind = "never_mind", write = count - 1 } end
    end
    return { kind = "other" }
end

-- confirm_pick(sel) -> { kind = "confirm" | "cancel", write = 2 }: the pick on the Talk sub-menu showing the confirm.
-- Row 0 is the confirmation; any other pick cancels. Both go back to the root through Cancel (row 2).
function M.confirm_pick(sel)
    return { kind = sel == 0 and "confirm" or "cancel", write = M.CANCEL_INDEX }
end

return M
