local ids = require("Retinue.ids")
local targets = require("Retinue.targets")

local HIRED, OTHER = 111, 222

local function hired_only(id) return id == HIRED end

-- main pawn excluded, and is_hired is not called for it
do
    local called_with = {}
    local set = targets.build({ ids.MAIN_PAWN }, function(id) called_with[#called_with + 1] = id; return true end)
    assert(next(set) == nil)
    assert(#called_with == 0)
end

-- hired included, non-hired excluded
do
    local set = targets.build({ ids.MAIN_PAWN, HIRED, OTHER }, hired_only)
    assert(set[HIRED] == true)
    assert(set[OTHER] == nil)
    assert(set[ids.MAIN_PAWN] == nil)
end

-- is_hired returning 1 or a non-true value excludes
do
    assert(next(targets.build({ HIRED }, function() return 1 end)) == nil)
    assert(next(targets.build({ HIRED }, function() return "yes" end)) == nil)
    assert(next(targets.build({ HIRED }, function() return nil end)) == nil)
end

-- empty party
assert(next(targets.build({}, hired_only)) == nil)

-- replacing the predicate changes build's result
do
    local original = targets.is_target
    targets.is_target = function(id) return id == OTHER end
    local set = targets.build({ HIRED, OTHER }, hired_only)
    targets.is_target = original
    assert(set[OTHER] == true)
    assert(set[HIRED] == nil)
end
