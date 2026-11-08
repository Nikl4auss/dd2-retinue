local labels = require("Retinue.labels")
local roster = require("Retinue.roster")

-- returned / kept: exact texts, integral floats without ".0"
assert(labels.returned("Ana", 27) == "Ana returned — Lv 27 restored")
assert(labels.returned("Ana", 27.0) == "Ana returned — Lv 27 restored")
assert(labels.kept("Ana", 30) == "Ana returned — kept Lv 30, newer than the backup")
assert(labels.kept("Ana", 30.0) == "Ana returned — kept Lv 30, newer than the backup")

-- roster_problem
do
    local p = labels.roster_problem
    -- no roster: an unknown slot is a problem, a unit set (a new game waiting for its first save) is not
    assert(p(nil, nil) == "Retinue is off: the save slot is unknown")
    assert(p(nil, 0) == nil)
    assert(p(nil, 2) == nil)
    -- locked and read-only name their reason
    assert(p({ mode = roster.LOCKED, reason = "members[2] has no offline_id", members = {} }, 0)
        == "The Retinue roster is locked: members[2] has no offline_id\nSee the Retinue menu.")
    assert(p({ mode = roster.READ_ONLY, reason = "version 9", members = {} }, 1)
        == "The Retinue roster is read-only: written by a newer Retinue (version 9)")
    -- ok: nothing
    assert(p({ mode = roster.OK, members = {} }, 0) == nil)
end

-- the talk menu's row, its dialog and the refusals: exact texts
do
    assert(labels.YES == "Yes" and labels.NO == "No")
    assert(labels.adopt_row() == "Adopt")
    assert(labels.release_row(27) == "Release (Retinue \u{B7} Lv 27)")
    assert(labels.release_row(27.0) == "Release (Retinue \u{B7} Lv 27)")
    assert(labels.release_row(nil) == "Release (Retinue)")
    assert(labels.ask_adopt("Ana") == "Adopt Ana into your retinue?\nGear you give them is lost if they're dismissed or lost.")
    assert(labels.ask_release("Ana") == "Release Ana? Their progress will be lost.")
    assert(labels.refused("adopt", "Ana", "locked") == "Cannot adopt Ana: the roster is locked (see the menu)")
    assert(labels.refused("release", "Ana", "not_in_party") == "Cannot release Ana: no longer in the party")
    assert(labels.refused("adopt", "Ana", "full") == "Cannot adopt Ana: the retinue is full (2 members)")
end

print("labels_test ok")
