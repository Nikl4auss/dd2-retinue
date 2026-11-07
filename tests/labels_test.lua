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

print("labels_test ok")
