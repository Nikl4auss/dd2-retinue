-- marks.lua: who is marked and the text a name widget gets (pure).
local marks = require("Retinue.marks")
local roster = require("Retinue.roster")
local labels = require("Retinue.labels")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
local C = "01234567-89ab-cdef-0123-456789abcdef"
local D = "99999999-2222-3333-4444-555555555555"

local r = { mode = roster.OK, warnings = {}, members = {
    { offline_id = A, name = "Ana", status = roster.PRESENT },
    { offline_id = B, name = "Bo", status = roster.AWAY },
    { offline_id = C, name = "Cy", status = roster.RETURNING },
} }

-- status_member: present only, never the main pawn
assert(marks.status_member(r, A, false) == true)
assert(marks.status_member(r, A:upper(), false) == true)
assert(marks.status_member(r, B, false) == false)
assert(marks.status_member(r, C, false) == false)
assert(marks.status_member(r, D, false) == false)
assert(marks.status_member(r, A, true) == false)
assert(marks.status_member(nil, A, false) == false)
assert(marks.status_member(r, nil, false) == false)
assert(marks.status_member(r, "unreadable", false) == false)

-- rift_member: any status
assert(marks.rift_member(r, A).name == "Ana")
assert(marks.rift_member(r, B).name == "Bo")
assert(marks.rift_member(r, C).name == "Cy")
assert(marks.rift_member(r, D) == nil)
assert(marks.rift_member(nil, A) == nil)
assert(marks.rift_member(r, nil) == nil)
assert(marks.rift_member(r, "unreadable") == nil)

-- status_text
do
    local t = marks.status_text
    assert(t("Folken", true) == "Folken \u{B7} Retinue")
    assert(t("Folken \u{B7} Retinue", true) == nil) -- already marked
    assert(t("Folken \u{B7} Retinue", false) == "Folken") -- stale mark stripped
    assert(t("Folken", false) == nil) -- non-member plain
    assert(t(nil, true) == nil and t("", true) == nil and t(nil, false) == nil and t("", false) == nil)
    assert(t(labels.STATUS_MARK, true) == nil and t(labels.STATUS_MARK, false) == nil) -- only our mark
    -- a mark in the middle is the game's own text, not ours
    assert(t("A \u{B7} Retinue B", true) == "A \u{B7} Retinue B \u{B7} Retinue")
end

-- rift_text
do
    local t = marks.rift_text
    assert(t("Folken", true, 28) == "\u{2605} Folken \u{B7} Lv 28")
    assert(t("Folken", true, 28.0) == "\u{2605} Folken \u{B7} Lv 28")
    assert(t("Folken", true, nil) == "\u{2605} Folken")
    assert(t("\u{2605} Folken \u{B7} Lv 20", true, 28) == "\u{2605} Folken \u{B7} Lv 28") -- level change replaces
    assert(t("\u{2605} Folken \u{B7} Lv 28", true, 28) == nil) -- already right
    assert(t("\u{2605} Folken", true, nil) == nil)
    assert(t("\u{2605} Folken \u{B7} Lv 28", true, nil) == "\u{2605} Folken") -- backup level gone
    assert(t("\u{2605} Folken", true, 28) == "\u{2605} Folken \u{B7} Lv 28")
    assert(t("\u{2605} Folken \u{B7} Lv 28", false, nil) == "Folken") -- stale mark stripped
    assert(t("Folken", false, nil) == nil) -- non-member plain
    assert(t("Folken", false, 28) == nil)
    assert(t(nil, true, 1) == nil and t("", true, 1) == nil)
    assert(t(labels.RIFT_STAR, true, 5) == nil and t(labels.RIFT_STAR, false, 5) == nil) -- only our mark
    -- Lv text without our star is the game's own
    assert(t("Folken \u{B7} Lv 5", true, 7) == "\u{2605} Folken \u{B7} Lv 5 \u{B7} Lv 7")
end

print("marks_test ok")
