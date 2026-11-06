local reconcile = require("Retinue.reconcile")
local roster = require("Retinue.roster")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

assert(reconcile.SETTLE_SECONDS == 3 and reconcile.GRACE_SECONDS == 20)

local function member(status, cid, id, name)
    return { offline_id = id or A, name = name or "Ana", status = status, character_id = cid }
end

local function ok_roster(members) return { mode = roster.OK, members = members, warnings = {} } end

-- first_hire_state
do
    local f = reconcile.first_hire_state
    local b = { level = 20, exp = 500, discipline = 30 }
    -- lower level
    assert(f({ level = 5, exp = 0, discipline = 0 }, b))
    assert(f({ level = 5, exp = 0, discipline = 0 }, { level = 20, exp = 0, discipline = 0 }))
    -- equal level: needs backup exp or discipline
    assert(f({ level = 20, exp = 0, discipline = 0 }, b))
    assert(f({ level = 20, exp = 0, discipline = 0 }, { level = 20, exp = 7, discipline = 0 }))
    assert(f({ level = 20, exp = 0, discipline = 0 }, { level = 20, exp = 0, discipline = 7 }))
    assert(not f({ level = 20, exp = 0, discipline = 0 }, { level = 20, exp = 0, discipline = 0 }))
    -- higher level
    assert(not f({ level = 21, exp = 0, discipline = 0 }, b))
    -- exp or discipline above 0 on the party side
    assert(not f({ level = 5, exp = 1, discipline = 0 }, b))
    assert(not f({ level = 5, exp = 0, discipline = 1 }, b))
    -- nil fields
    assert(not f({ level = nil, exp = 0, discipline = 0 }, b))
    assert(not f({ level = 5, exp = nil, discipline = 0 }, b))
    assert(not f({ level = 5, exp = 0, discipline = nil }, b))
    assert(not f({ level = 5, exp = 0, discipline = 0 }, nil))
    -- integral floats compare equal
    assert(f({ level = 20.0, exp = 0.0, discipline = 0.0 }, b))
end

-- rehired
do
    local re = reconcile.rehired
    local function p(extra)
        local t = { character_id = 1, level = 30, exp = 100, discipline = 10 }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local function b(extra)
        local t = { level = 30, exp = 100, discipline = 10 }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local P, AW, R = roster.PRESENT, roster.AWAY, roster.RETURNING
    -- hire times decide when both are known
    assert(re(member(AW, 1), p({ hire_time = 5 }), b({ hire_time = 5 })) == false)
    assert(re(member(AW, 1), p({ character_id = 2, hire_time = 5 }), b({ hire_time = 5 })) == false) -- different CharacterID, same hire
    assert(re(member(AW, 1), p({ hire_time = 6 }), b({ hire_time = 5 })) == true) -- same CharacterID, different hire
    assert(re(member(P, 1), p({ hire_time = 6 }), b({ hire_time = 5 })) == true)
    assert(re(member(AW, 1), p({ hire_time = 5.0 }), b({ hire_time = 5 })) == false)
    -- a hire time that is not an integer counts as unknown (to_int): the CharacterID rule, not a mismatch
    assert(re(member(AW, 1), p({ hire_time = 5.5 }), b({ hire_time = 5 })) == false)
    assert(re(member(AW, 1), p({ hire_time = 5 }), b({ hire_time = "x" })) == false)
    assert(re(member(AW, 1), p({ hire_time = "x" }), b({ hire_time = 5 })) == false)
    assert(re(member(AW, 1), p({ character_id = 2, hire_time = 5.5 }), b({ hire_time = 5 })) == true)
    -- a backup or a party entry without a hire time: the CharacterID rule
    assert(re(member(AW, 1), p({ hire_time = 5 }), b()) == false)
    assert(re(member(AW, 1), p(), b({ hire_time = 5 })) == false)
    assert(re(member(AW, 1), p({ character_id = 2, hire_time = 5 }), b()) == true)
    assert(re(member(AW, 1), p({ character_id = 2 }), b({ hire_time = 5 })) == true)
    assert(re(member(AW, 1), { level = 30, exp = 100, discipline = 10 }, b()) == true) -- party CharacterID unreadable
    -- no kept CharacterID
    assert(re(member(AW, nil), p(), b()) == true)
    assert(re(member(R, nil), p(), b()) == true)
    assert(re(member(P, nil), p(), b()) == false)
    -- the hire times come before the kept-CharacterID rule
    assert(re(member(P, nil), p({ hire_time = 6 }), b({ hire_time = 5 })) == true)
    assert(re(member(AW, nil), p({ hire_time = 5 }), b({ hire_time = 5 })) == false)
    -- same CharacterID: the first-hire signature
    assert(re(member(AW, 1), p({ level = 5, exp = 0, discipline = 0 }), b()) == true)
    assert(re(member(P, 1), p({ level = 30, exp = 0, discipline = 0 }), b()) == true)
    assert(re(member(AW, 1), p({ level = 5, exp = 3, discipline = 0 }), b()) == false)
    assert(re(member(AW, 1), p(), b()) == false)
    -- no backup
    assert(re(member(AW, 1), p({ level = 5, exp = 0, discipline = 0 }), nil) == false)
    assert(re(member(AW, 1), p({ hire_time = 5 }), nil) == false)
end

-- plan: one test per row
do
    local function plan(status, party_entry, backup, cid)
        local r = ok_roster({ member(status, cid or 1) })
        local party = {}
        if party_entry then party[A] = party_entry end
        return reconcile.plan(r, party, {}, function() return backup end)
    end
    local b = { level = 30, exp = 100, discipline = 10, hire_time = 5 }
    local same = { character_id = 1, level = 28, exp = 50, discipline = 5, hire_time = 5 }
    local diff = { character_id = 1, level = 1, exp = 0, discipline = 0, hire_time = 9 }

    -- present, in party, not rehired: none
    assert(#plan(roster.PRESENT, same, b) == 0)

    -- present, in party, rehired: returning
    local c = plan(roster.PRESENT, diff, b)
    assert(#c == 1 and c[1].id == A and c[1].name == "Ana" and c[1].from == "present" and c[1].to == "returning")
    assert(c[1].text == "Ana: roster present, save has it Lv1 (backup Lv30) → returning, re-hired unseen", c[1].text)

    -- present, not in party: away
    c = plan(roster.PRESENT, nil, b)
    assert(#c == 1 and c[1].from == "present" and c[1].to == "away")
    assert(c[1].text == "Ana: roster present, not in the save's party (backup Lv30) → away, backup kept", c[1].text)

    -- away, in party, not rehired: present, save wins
    c = plan(roster.AWAY, same, b)
    assert(#c == 1 and c[1].from == "away" and c[1].to == "present")
    assert(c[1].text == "Ana: roster away, save has it Lv28 (backup Lv30) → present, save wins", c[1].text)

    -- away, in party, rehired: returning
    c = plan(roster.AWAY, diff, b)
    assert(#c == 1 and c[1].from == "away" and c[1].to == "returning")
    assert(c[1].text == "Ana: roster away, save has it Lv1 (backup Lv30) → returning, re-hired unseen", c[1].text)

    -- away, not in party: none
    assert(#plan(roster.AWAY, nil, b) == 0)

    -- returning, in party: none (either way)
    assert(#plan(roster.RETURNING, same, b) == 0)
    assert(#plan(roster.RETURNING, diff, b) == 0)

    -- returning, not in party: away
    c = plan(roster.RETURNING, nil, b)
    assert(#c == 1 and c[1].from == "returning" and c[1].to == "away")
    assert(c[1].text == "Ana: roster returning, not in the save's party (backup Lv30) → away, backup kept", c[1].text)

    -- text variants: no backup, unknown level, float level
    c = plan(roster.PRESENT, nil, nil)
    assert(c[1].text == "Ana: roster present, not in the save's party (no backup) → away, backup kept", c[1].text)
    c = plan(roster.AWAY, { character_id = 1 }, { level = 30.0, exp = 0, discipline = 0 })
    assert(c[1].to == "present" and c[1].text == "Ana: roster away, save has it Lv? (backup Lv30) → present, save wins", c[1].text)
    c = plan(roster.AWAY, { character_id = 1, level = 7.0 }, nil)
    assert(c[1].text == "Ana: roster away, save has it Lv7 (no backup) → present, save wins", c[1].text)
end

-- plan: roster order, ambiguous, nil and locked, read-only
do
    local r = ok_roster({ member(roster.PRESENT, 1, A, "Ana"), member(roster.PRESENT, 2, B, "Bea") })
    local function backup_of() end
    -- both absent: corrections come in roster order
    local c = reconcile.plan(r, {}, {}, backup_of)
    assert(#c == 2 and c[1].id == A and c[2].id == B and c[1].name == "Ana" and c[2].name == "Bea")
    -- ambiguous members get none
    c = reconcile.plan(r, {}, { [A] = true }, backup_of)
    assert(#c == 1 and c[1].id == B)
    c = reconcile.plan(r, {}, { [A] = true, [B] = true }, backup_of)
    assert(#c == 0)
    -- nil and locked
    c = reconcile.plan(nil, {}, {}, backup_of)
    assert(type(c) == "table" and #c == 0)
    local locked = { mode = roster.LOCKED, members = { member(roster.PRESENT, 1, A, "Ana") }, warnings = {} }
    c = reconcile.plan(locked, {}, {}, backup_of)
    assert(type(c) == "table" and #c == 0)
    -- read-only still plans
    r.mode = roster.READ_ONLY
    c = reconcile.plan(r, {}, {}, backup_of)
    assert(#c == 2)
    -- each member is judged against its own backup
    r = ok_roster({ member(roster.AWAY, 1, A, "Ana"), member(roster.AWAY, 2, B, "Bea") })
    local backups = { [A] = { level = 30, hire_time = 5 }, [B] = { level = 30, hire_time = 6 } }
    c = reconcile.plan(r, { [A] = { character_id = 1, hire_time = 5 }, [B] = { character_id = 2, hire_time = 5 } }, {},
        function(id) return backups[id] end)
    assert(#c == 2 and c[1].id == A and c[1].to == "present" and c[2].id == B and c[2].to == "returning")
    -- a mixed roster
    r = ok_roster({ member(roster.AWAY, 1, A, "Ana"), member(roster.RETURNING, 2, B, "Bea") })
    c = reconcile.plan(r, { [A] = { character_id = 1 } }, {}, backup_of)
    assert(#c == 2 and c[1].id == A and c[1].to == "present" and c[2].id == B and c[2].to == "away")
end

-- gate
do
    local function new() return reconcile.new_gate(3, 20) end

    -- a first generation out of the world: opens `settle` after entering
    local g = new()
    assert(g.pending == false)
    assert(g:check(0, false, false, 1) == false and g.pending == true)
    assert(g:check(10, false, false, 1) == false)
    assert(g:check(11, true, true, 1) == false)
    assert(g:check(13.9, true, true, 1) == false)
    assert(g:check(14, true, true, 1) == true and g.pending == false)
    -- once only
    assert(g:check(15, true, true, 1) == false)
    assert(g:check(100, true, true, 1) == false)

    -- a generation bumped in the world waits while the world stays on...
    g = new()
    -- (drive generation 1 open first, then bump in the world)
    assert(g:check(0, false, true, 1) == false)
    assert(g:check(1, true, true, 1) == false)
    assert(g:check(4, true, true, 1) == true)
    assert(g:check(5, true, true, 2) == false and g.pending == true) -- bump in the world
    assert(g:check(10, true, true, 2) == false)
    -- ...opens after leaving and re-entering
    assert(g:check(11, false, true, 2) == false)
    assert(g:check(12, true, true, 2) == false)
    assert(g:check(14.9, true, true, 2) == false)
    assert(g:check(15, true, true, 2) == true and g.pending == false)

    -- a bump on the world-entry frame after an idle gate left the world: previous frame was out, so it opens after settle
    g = new()
    g:check(0, false, true, 1)
    g:check(1, true, true, 1)
    assert(g:check(4, true, true, 1) == true)
    assert(g:check(5, false, true, 1) == false)
    assert(g:check(6, true, true, 2) == false)
    assert(g:check(9, true, true, 2) == true)

    -- the same, staying in the world: opens at born + grace + settle
    g = new()
    g:check(0, false, true, 1)
    g:check(1, true, true, 1)
    assert(g:check(4, true, true, 1) == true)
    assert(g:check(100, true, true, 2) == false)
    assert(g:check(119.9, true, true, 2) == false) -- within grace
    assert(g:check(120, true, true, 2) == false) -- grace over, settle starts
    assert(g:check(122.9, true, true, 2) == false)
    assert(g:check(123, true, true, 2) == true)

    -- leaving during the settle restarts it
    g = new()
    g:check(0, true, true, 1)
    assert(g:check(1, true, true, 1) == false) -- settle started at 0
    assert(g:check(2, false, true, 1) == false) -- left
    assert(g:check(3, true, true, 1) == false) -- settle restarts at 3
    assert(g:check(5.9, true, true, 1) == false)
    assert(g:check(6, true, true, 1) == true)

    -- party_ready false restarts it
    g = new()
    g:check(0, true, true, 1)
    assert(g:check(1, true, true, 1) == false)
    assert(g:check(3, true, false, 1) == false) -- not ready
    assert(g:check(4, true, true, 1) == false) -- restarts at 4
    assert(g:check(6.9, true, true, 1) == false)
    assert(g:check(7, true, true, 1) == true)
    -- not ready from the start only delays
    g = new()
    for t = 0, 30 do assert(g:check(t, true, false, 1) == false) end
    assert(g.pending == true)
    assert(g:check(31, true, true, 1) == false)
    assert(g:check(34, true, true, 1) == true)

    -- a second bump while pending restarts
    g = new()
    g:check(0, false, true, 1)
    g:check(1, true, true, 1)
    assert(g:check(3, true, true, 1) == false)
    assert(g:check(3.5, true, true, 2) == false and g.pending == true) -- bumped in the world, before opening
    assert(g:check(6, true, true, 2) == false) -- gen 1 would have opened at 4; gen 2 waits for grace
    assert(g:check(23.4, true, true, 2) == false)
    assert(g:check(24, true, true, 2) == false) -- 3.5 + 20 passed; settle starts
    assert(g:check(26.9, true, true, 2) == false)
    assert(g:check(27, true, true, 2) == true)

    -- a later generation pends again
    assert(g.pending == false)
    assert(g:check(30, false, true, 3) == false and g.pending == true)
    assert(g:check(31, true, true, 3) == false)
    assert(g:check(34, true, true, 3) == true and g.pending == false)
end

print("reconcile_test ok")
