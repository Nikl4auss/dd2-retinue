-- talk_menu.lua: which menu, which pawn, which row, which refusal.
local talk_menu = require("Retinue.talk_menu")
local roster = require("Retinue.roster")

local OTHER = "11111111-2222-3333-4444-555555555555"
local ID_A = "aaaaaaaa-0000-0000-0000-000000000001"
local ID_B = "bbbbbbbb-0000-0000-0000-000000000002"
local ID_C = "cccccccc-0000-0000-0000-000000000003"

-- is_root
do
    local ROOT, DISMISS, NM, TALK = talk_menu.ROOT_NODE, talk_menu.DISMISS, talk_menu.NEVER_MIND, talk_menu.TALK_CHOICE
    assert(talk_menu.is_root(ROOT, { TALK, DISMISS, NM }) == true) -- by node id
    assert(talk_menu.is_root(OTHER, { TALK, DISMISS, OTHER, NM }) == true) -- by Dismiss
    assert(talk_menu.is_root(ROOT, { TALK, NM }) == true)
    assert(talk_menu.is_root(OTHER, { TALK, OTHER, NM }) == false) -- a sub-menu: no Dismiss
    assert(talk_menu.is_root(OTHER, { TALK, OTHER }) == false)
    assert(talk_menu.is_root(ROOT, { TALK, OTHER, DISMISS }) == false) -- Never mind not last
    assert(talk_menu.is_root(ROOT, { NM, TALK }) == false)
    assert(talk_menu.is_root(OTHER, { DISMISS, NM, TALK }) == false)
    assert(talk_menu.is_root(ROOT, { OTHER, DISMISS, NM }) == false) -- Talk not first
    assert(talk_menu.is_root(OTHER, { DISMISS, TALK, NM }) == false)
    assert(talk_menu.is_root(ROOT, { NM }) == false)
    assert(talk_menu.is_root(ROOT, {}) == false)
    assert(talk_menu.is_root(ROOT, nil) == false)
    assert(talk_menu.is_root(nil, { TALK, DISMISS, NM }) == true)
end

-- is_talk_sub: by node id or by Cancel last, exactly 3 choices
do
    local SUB, CANCEL = talk_menu.TALK_SUB, talk_menu.CANCEL
    assert(talk_menu.is_talk_sub(SUB, { OTHER, OTHER, CANCEL }) == true)
    assert(talk_menu.is_talk_sub(SUB, { OTHER, OTHER, OTHER }) == true) -- by node id
    assert(talk_menu.is_talk_sub(OTHER, { OTHER, OTHER, CANCEL }) == true) -- by Cancel last
    assert(talk_menu.is_talk_sub(OTHER, { OTHER, OTHER, OTHER }) == false)
    assert(talk_menu.is_talk_sub(OTHER, { CANCEL, OTHER, OTHER }) == false)
    assert(talk_menu.is_talk_sub(SUB, { OTHER, CANCEL }) == false) -- another count
    assert(talk_menu.is_talk_sub(SUB, { OTHER, OTHER, OTHER, CANCEL }) == false)
    assert(talk_menu.is_talk_sub(SUB, {}) == false)
    assert(talk_menu.is_talk_sub(SUB, nil) == false)
    assert(talk_menu.is_talk_sub(nil, { OTHER, OTHER, CANCEL }) == true)
    -- the root menu is not the sub-menu
    assert(talk_menu.is_talk_sub(talk_menu.ROOT_NODE, { talk_menu.TALK_CHOICE, talk_menu.DISMISS, talk_menu.NEVER_MIND }) == false)
end

-- offer_pick: the root menu has count vanilla rows, ours at count - 1, Never mind shown at count
do
    local function same(a, kind, write) return a.kind == kind and a.write == write end
    assert(same(talk_menu.offer_pick(3, 4), "ours", 0))
    assert(same(talk_menu.offer_pick(4, 4), "never_mind", 3))
    assert(same(talk_menu.offer_pick(0, 4), "other", nil))
    assert(same(talk_menu.offer_pick(1, 4), "other", nil))
    assert(same(talk_menu.offer_pick(2, 4), "other", nil))
    assert(same(talk_menu.offer_pick(5, 4), "other", nil))
    assert(same(talk_menu.offer_pick(-1, 4), "other", nil))
    assert(same(talk_menu.offer_pick(nil, 4), "other", nil))
    assert(same(talk_menu.offer_pick(3.5, 4), "other", nil))
    assert(same(talk_menu.offer_pick(9, 10), "ours", 0)) -- 10 vanilla rows: ours is 9
    assert(same(talk_menu.offer_pick(10, 10), "never_mind", 9))
end

-- confirm_pick: row 0 confirms, anything else cancels; both write Cancel's index
do
    local c = talk_menu.confirm_pick(0)
    assert(c.kind == "confirm" and c.write == 2)
    for _, sel in ipairs({ 1, 2, 3, -1 }) do
        c = talk_menu.confirm_pick(sel)
        assert(c.kind == "cancel" and c.write == 2)
    end
end

-- view_of: hired slots only
do
    local views = {
        { slot = 0, character_id = 100 }, { slot = 1, character_id = 200 }, { slot = 2, character_id = 300 },
    }
    assert(talk_menu.view_of(views, 200) == views[2])
    assert(talk_menu.view_of(views, 300) == views[3])
    assert(talk_menu.view_of(views, 100) == nil) -- the main pawn
    assert(talk_menu.view_of(views, 999) == nil)
    assert(talk_menu.view_of(views, nil) == nil)
    assert(talk_menu.view_of({}, 200) == nil)
end

local function view(slot, id, over)
    local v = { slot = slot, character_id = 200 + slot, owner = roster.OWNER, offline_id = id, name = "Ana", chara = {} }
    for k, x in pairs(over or {}) do v[k] = x end
    return v
end
local function member(id, name) return { offline_id = id, name = name, status = roster.PRESENT, character_id = 201 } end
local function store(members, over)
    local r = { mode = roster.OK, members = members or {}, warnings = {} }
    local s = { roster = r, found = {}, ambiguous = {}, unit = 0 }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end
-- a store without a roster or without a unit (store() can't take nil overrides)
local function bare(field)
    local s = store()
    s[field] = nil
    return s
end

-- row: adopt
do
    local s = store()
    local v = view(1, ID_A)
    local row = talk_menu.row(s, v, 12)
    assert(row.action == "adopt" and row.label == "Adopt" and row.offline_id == ID_A and row.name == "Ana")
    -- an unnamed pawn
    row = talk_menu.row(s, view(1, ID_A, { name = false }), 12)
    assert(row.name == roster.UNKNOWN_NAME)
    -- the id is canonicalised
    row = talk_menu.row(s, view(1, ID_A:upper()), 12)
    assert(row.offline_id == ID_A)
    -- an online pawn (not CAPCOM-owned), the main pawn's slot, no offline id
    assert(talk_menu.row(s, view(1, ID_A, { owner = "someone" }), 12) == nil)
    assert(talk_menu.row(s, view(0, ID_A), 12) == nil)
    assert(talk_menu.row(s, view(1, nil), 12) == nil)
    assert(talk_menu.row(s, nil, 12) == nil)
end

-- row: release, with the level and U+00B7
do
    local v = view(2, ID_B)
    local s = store({ member(ID_B, "Bea") })
    s.found[ID_B] = v
    local row = talk_menu.row(s, v, 27)
    assert(row.action == "release" and row.offline_id == ID_B and row.name == "Bea")
    assert(row.label == "Release (Retinue \u{B7} Lv 27)")
    assert(talk_menu.row(s, v, nil).label == "Release (Retinue)")
    -- found as another view object with the same CharacterID still counts
    s.found[ID_B] = view(2, ID_B)
    assert(talk_menu.row(s, v, 27).action == "release")
end

-- row: nil for ambiguous, a member found as another view, a member not found
do
    local v = view(1, ID_B)
    local s = store({ member(ID_B, "Bea") })
    s.found[ID_B] = v
    s.ambiguous[ID_B] = true
    assert(talk_menu.row(s, v, 5) == nil)
    s = store({ member(ID_B, "Bea") })
    s.found[ID_B] = view(2, ID_B, { character_id = 999 }) -- the member is another party pawn
    assert(talk_menu.row(s, v, 5) == nil)
    s.found = {} -- an away member: not found in the party
    assert(talk_menu.row(s, v, 5) == nil)
end

-- row: a nil, locked or read-only roster still gives the row
do
    local v = view(1, ID_A)
    assert(talk_menu.row(bare("roster"), v, 5).action == "adopt")
    local s = store()
    s.roster.mode = roster.LOCKED
    assert(talk_menu.row(s, v, 5).action == "adopt")
    s.roster.mode = roster.READ_ONLY
    assert(talk_menu.row(s, v, 5).action == "adopt")
    -- a read-only roster's member in the party: release
    s = store({ member(ID_A, "Ana") })
    s.roster.mode = roster.READ_ONLY
    s.found[ID_A] = v
    assert(talk_menu.row(s, v, 5).action == "release")
end

-- refusal
do
    local r = talk_menu.refusal
    assert(r(store(), "adopt") == nil and r(store(), "release") == nil)
    assert(r(bare("roster"), "adopt") == "no_slot")
    assert(r(bare("unit"), "release") == "no_slot")
    local s = store()
    s.roster.mode = roster.LOCKED
    assert(r(s, "adopt") == "locked" and r(s, "release") == "locked")
    s.roster.mode = roster.READ_ONLY
    assert(r(s, "adopt") == "read_only" and r(s, "release") == "read_only")
    s = store({ member(ID_A, "A"), member(ID_B, "B") })
    assert(r(s, "adopt") == "full" and r(s, "release") == nil)
    s = store({ member(ID_A, "A") })
    assert(r(s, "adopt") == nil)
    s.roster.mode = roster.LOCKED -- locked wins over full
    s.roster.members[2] = member(ID_C, "C")
    assert(r(s, "adopt") == "locked")
end

print("talk_menu_test ok")
