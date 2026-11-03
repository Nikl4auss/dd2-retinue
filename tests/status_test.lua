local status = require("Retinue.status")

assert(status.format(nil) == "Load a save")
assert(status.format({}) == "No hired pawns in party")

-- one row
assert(status.format({ { name = "Ana", level = 12, job = 1, rank = 3 } }) == "Applies to: Ana (Lv 12, Fighter R3, Disc ?)")

-- two rows, joined in order
assert(status.format({
    { name = "Ana", level = 12, job = 1, rank = 3 },
    { name = "Bo", level = 5, job = 3, rank = 1 },
}) == "Applies to: Ana (Lv 12, Fighter R3, Disc ?), Bo (Lv 5, Mage R1, Disc ?)")

-- unknown and missing vocation
assert(status.format({ { name = "Ana", level = 1, job = 11, rank = 1 } }) == "Applies to: Ana (Lv 1, Vocation 11 R1, Disc ?)")
assert(status.format({ { name = "Ana", level = 1, job = nil, rank = 1 } }) == "Applies to: Ana (Lv 1, ? R1, Disc ?)")

-- missing name, level, rank
assert(status.format({ { name = nil, level = 1, job = 2, rank = 1 } }) == "Applies to: ? (Lv 1, Archer R1, Disc ?)")
assert(status.format({ { name = "", level = 1, job = 2, rank = 1 } }) == "Applies to: ? (Lv 1, Archer R1, Disc ?)")
assert(status.format({ { name = "Ana", level = nil, job = 2, rank = 1 } }) == "Applies to: Ana (Lv ?, Archer R1, Disc ?)")
assert(status.format({ { name = "Ana", level = 1, job = 2, rank = nil } }) == "Applies to: Ana (Lv 1, Archer R?, Disc ?)")
assert(status.format({ {} }) == "Applies to: ? (Lv ?, ? R?, Disc ?)")

-- integral floats print without ".0"
assert(status.format({ { name = "Ana", level = 12.0, job = 1.0, rank = 3.0 } }) == "Applies to: Ana (Lv 12, Fighter R3, Disc ?)")
assert(status.format({ { name = "Ana", level = 1, job = 11.0, rank = 1 } }) == "Applies to: Ana (Lv 1, Vocation 11 R1, Disc ?)")

-- glossary vocation names (CONTEXT.md § Progression)
do
    local expected = { "Fighter", "Archer", "Mage", "Thief", "Warrior", "Sorcerer",
                       "Mystic Spearhand", "Magick Archer", "Trickster", "Warfarer" }
    for i, name in ipairs(expected) do
        assert(status.vocation_name(i) == name, name)
        assert(status.VOCATIONS[i] == name, name)
    end
    local n = 0
    for _ in pairs(status.VOCATIONS) do n = n + 1 end
    assert(n == 10)
end

-- discipline
assert(status.format({ { name = "Ana", level = 12, job = 1, rank = 3, discipline = 450 } })
    == "Applies to: Ana (Lv 12, Fighter R3, Disc 450)")
assert(status.format({ { name = "Ana", level = 12, job = 1, rank = 3, discipline = 0 } })
    == "Applies to: Ana (Lv 12, Fighter R3, Disc 0)")
assert(status.format({ { name = "Ana", level = 12, job = 1, rank = 3, discipline = 450.0 } })
    == "Applies to: Ana (Lv 12, Fighter R3, Disc 450)")
