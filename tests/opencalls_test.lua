local opencalls = require("Retinue.opencalls")
local MAIN = require("Retinue.ids").MAIN_PAWN

local function new() return opencalls.new() end

-- rewritten call open: main-pawn ID swaps back to the real one
do
    local s = new()
    s:push("checkLevelUp").real = 1
    assert(s:swap_id(MAIN) == 1)
    s:pop("checkLevelUp")
    assert(s:depth() == 0 and s:swap_id(MAIN) == nil)
end

-- none open
assert(new():swap_id(MAIN) == nil)

-- non-main ID is never swapped, even with a rewritten frame on top
do
    local s = new()
    s:push("checkLevelUp").real = 1
    assert(s:swap_id(MAIN + 1) == nil)
    assert(s:swap_id(1) == nil)
end

-- nested: rewritten outer, non-rewritten inner
do
    local s = new()
    s:push("checkLevelUp").real = 1
    s:push("addJobPoint")
    assert(s:swap_id(MAIN) == nil)
    s:pop("addJobPoint")
    assert(s:swap_id(MAIN) == 1)
end

-- two nested rewritten calls: innermost wins, then the outer again
do
    local s = new()
    s:push("checkLevelUp").real = 1
    s:push("addJobPoint").real = 2
    assert(s:swap_id(MAIN) == 2)
    s:pop("addJobPoint")
    assert(s:swap_id(MAIN) == 1)
end

-- stale frames dropped by an outer pop
do
    local s = new()
    s:push("A").real = 1
    s:push("B").real = 2
    s:pop("A")
    assert(s:depth() == 0 and s:swap_id(MAIN) == nil)
end

-- stale frame in the same game frame: a later main-pawn call (real nil) on top renames nothing
do
    local s = new()
    s:push("A").real = 1
    s:push("C")
    assert(s:swap_id(MAIN) == nil)
end

-- clear
do
    local s = new()
    s:push("A").real = 1
    s:clear()
    assert(s:depth() == 0 and s:swap_id(MAIN) == nil)
end

-- pop picks the innermost frame with the key
do
    local s = new()
    s:push("A").real = 1
    s:push("A").real = 2
    s:pop("A")
    assert(s:depth() == 1 and s:swap_id(MAIN) == 1)
end

-- pop of an absent key is a no-op
do
    local s = new()
    s:push("A").real = 1
    s:pop("Z")
    assert(s:depth() == 1 and s:swap_id(MAIN) == 1)
    new():pop("A")
end

-- overflow: pushing past MAX_DEPTH clears and reports it
do
    local s = new()
    for _ = 1, opencalls.MAX_DEPTH do
        local _, overflowed = s:push("A")
        assert(not overflowed)
    end
    assert(s:depth() == opencalls.MAX_DEPTH)
    local frame, overflowed = s:push("A")
    assert(overflowed == true and s:depth() == 1 and frame.real == nil)
end

-- a frame whose real was never set (error path) renames nothing
do
    local s = new()
    s:push("A")
    assert(s:swap_id(MAIN) == nil)
end
