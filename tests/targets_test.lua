local ids = require("Retinue.ids")
local roster = require("Retinue.roster")
local targets = require("Retinue.targets")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
local HIRED, OTHER = 111, 222

local function view(slot_n, cid, offline_id)
    return { slot = slot_n, character_id = cid, owner = "CAPCOM", offline_id = offline_id, name = "P" .. slot_n }
end

local function roster_of(mode, members)
    return { mode = mode, members = members, warnings = {} }
end

local function member(id, status)
    return { offline_id = id, name = "M", status = status }
end

local function yes() return true end
local function hired_only(id) return id == HIRED end

local function empty(set) return next(set) == nil end

-- nil roster (slot unknown) and LOCKED -> nobody
do
    local views = { view(1, HIRED, A) }
    assert(empty(targets.build(views, nil, yes)))
    -- a LOCKED roster holding a matching member still yields nobody
    local locked_r = roster_of(roster.LOCKED, { { offline_id = A, name = "Ana", status = "present", character_id = 5 } })
    assert(empty(targets.build(views, locked_r, yes)))
end

-- a present member in the party is a target, keyed by CharacterID
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    local set = targets.build({ view(0, ids.MAIN_PAWN, nil), view(1, HIRED, A) }, r, hired_only)
    assert(set[HIRED] == true and set[ids.MAIN_PAWN] == nil)
end

-- offline ids are compared canonically
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    assert(targets.build({ view(1, HIRED, A:upper()) }, r, yes)[HIRED] == true)
end

-- away and returning members are never targets
do
    for _, status in ipairs({ roster.AWAY, roster.RETURNING }) do
        local r = roster_of(roster.OK, { member(A, status) })
        assert(empty(targets.build({ view(1, HIRED, A) }, r, yes)), status)
    end
end

-- a hired pawn that is not a member is not a target; a member not in the party is not either
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    local set = targets.build({ view(1, HIRED, A), view(2, OTHER, B) }, r, yes)
    assert(set[HIRED] == true and set[OTHER] == nil)
    assert(empty(targets.build({ view(2, OTHER, B) }, r, yes)))
    assert(empty(targets.build({}, r, yes)))
end

-- ambiguous (two party pawns share the offline id) -> neither is a target
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT), member(B, roster.PRESENT) })
    local set = targets.build({ view(1, HIRED, A), view(2, OTHER, A) }, r, yes)
    assert(empty(set))
    -- the other member is unaffected
    set = targets.build({ view(1, HIRED, A), view(2, OTHER, A), view(0, 333, B) }, r, yes)
    assert(set[333] == true and set[HIRED] == nil and set[OTHER] == nil)
end

-- the main pawn is excluded even if (artificially) matched, and is_hired is not called for it
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    local called = {}
    local set = targets.build({ view(0, ids.MAIN_PAWN, A) }, r, function(id) called[#called + 1] = id; return true end)
    assert(empty(set))
    assert(#called == 0)
end

-- is_hired is only called for matched present members' ids
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT), member(B, roster.AWAY) })
    local called = {}
    targets.build({ view(1, HIRED, A), view(2, OTHER, B), view(0, 333, nil) }, r,
        function(id) called[#called + 1] = id; return true end)
    assert(#called == 1 and called[1] == HIRED)
end

-- is_hired returning false, 1, "yes" or nil excludes
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    local views = { view(1, HIRED, A) }
    assert(empty(targets.build(views, r, function() return false end)))
    assert(empty(targets.build(views, r, function() return 1 end)))
    assert(empty(targets.build(views, r, function() return "yes" end)))
    assert(empty(targets.build(views, r, function() return nil end)))
end

-- a view without a usable character_id is skipped
do
    local r = roster_of(roster.OK, { member(A, roster.PRESENT) })
    assert(empty(targets.build({ view(1, nil, A) }, r, yes)))
    assert(empty(targets.build({ view(1, "x", A) }, r, yes)))
end

-- READ_ONLY: its present members are targets
do
    local r = roster_of(roster.READ_ONLY, { member(A, roster.PRESENT), member(B, roster.AWAY) })
    local set = targets.build({ view(1, HIRED, A), view(2, OTHER, B) }, r, yes)
    assert(set[HIRED] == true and set[OTHER] == nil)
end

-- empty party
assert(empty(targets.build({}, roster_of(roster.OK, {}), hired_only)))
