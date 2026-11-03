local ids = require("Retinue.ids")
local progression = require("Retinue.progression")

local HIRED = 111

local function state(over)
    local s = { enabled = true, available = true, targets = { [HIRED] = true } }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

assert(progression.rewrite_id(HIRED, state()) == ids.MAIN_PAWN)
assert(progression.rewrite_id(HIRED, state({ enabled = false })) == nil)
assert(progression.rewrite_id(HIRED, state({ available = false })) == nil)
assert(progression.rewrite_id(222, state()) == nil)
-- main pawn: never a target, so never rewritten
assert(progression.rewrite_id(ids.MAIN_PAWN, state()) == nil)
