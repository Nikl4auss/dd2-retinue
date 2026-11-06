local departure = require("Retinue.departure")

assert(departure.RETRY_SECONDS == 10)
assert(departure.WAIT == "wait" and departure.RESTORE == "restore" and departure.SKIP_GUARD == "skip_guard")
assert(departure.SKIP_NO_BACKUP == "skip_no_backup" and departure.TIMEOUT == "timeout")

-- step
do
    local step = departure.step
    local b = { level = 20 }
    -- not ready: wait, or timeout once expired
    for _, expired in ipairs({ false, true }) do
        local want = expired and departure.TIMEOUT or departure.WAIT
        assert(step{ in_party = false, game_level = nil, backup = b, expired = expired } == want)
        assert(step{ in_party = false, game_level = 20, backup = b, expired = expired } == want)
        assert(step{ in_party = true, game_level = nil, backup = b, expired = expired } == want)
        assert(step{ in_party = true, game_level = 0, backup = b, expired = expired } == want)
        assert(step{ in_party = true, game_level = 0.5, backup = nil, expired = expired } == want)
        assert(step{ in_party = false, game_level = nil, backup = nil, expired = expired } == want)
    end
    -- ready, no backup
    assert(step{ in_party = true, game_level = 5, backup = nil, expired = false } == departure.SKIP_NO_BACKUP)
    assert(step{ in_party = true, game_level = 1, backup = nil, expired = true } == departure.SKIP_NO_BACKUP)
    -- the guard: a game level above the backup's wins; equal and lower restore
    assert(step{ in_party = true, game_level = 21, backup = b, expired = false } == departure.SKIP_GUARD)
    assert(step{ in_party = true, game_level = 20, backup = b, expired = false } == departure.RESTORE)
    assert(step{ in_party = true, game_level = 20.0, backup = b, expired = false } == departure.RESTORE)
    assert(step{ in_party = true, game_level = 19, backup = b, expired = false } == departure.RESTORE)
    assert(step{ in_party = true, game_level = 1, backup = b, expired = false } == departure.RESTORE)
    -- ready on the last frame still restores
    assert(step{ in_party = true, game_level = 19, backup = b, expired = true } == departure.RESTORE)
    assert(step{ in_party = true, game_level = 21, backup = b, expired = true } == departure.SKIP_GUARD)
end

-- budget
do
    local A, B = "a", "b"
    local bud = departure.new_budget(10)
    bud:sync(1)
    assert(bud:note(A) == nil and not bud:closed(A))
    -- the first call starts the deadline
    assert(bud:expired(A, 100) == false)
    assert(bud:note(A) == "pending")
    assert(bud:expired(A, 109.9) == false)
    assert(bud:expired(A, 110) == true)
    assert(bud:expired(A, 500) == true)
    -- another id starts its own
    assert(bud:expired(B, 105) == false)
    assert(bud:expired(B, 114.9) == false)
    assert(bud:expired(B, 115) == true)
    -- close
    assert(not bud:closed(A))
    bud:close(A, "timed out")
    assert(bud:closed(A) and bud:note(A) == "timed out" and not bud:closed(B))
    -- forget
    bud:forget(A)
    assert(not bud:closed(A) and bud:note(A) == nil)
    assert(bud:expired(A, 200) == false) -- a fresh deadline
    -- a close without a start
    bud:close("c", "differs at level")
    assert(bud:closed("c") and bud:note("c") == "differs at level")
    -- same generation keeps entries; a new one drops them all
    bud:sync(1)
    assert(bud:closed("c") and bud:note(B) == "pending")
    bud:sync(2)
    assert(not bud:closed("c") and bud:note("c") == nil and bud:note(B) == nil and bud:note(A) == nil)
    assert(bud:expired(B, 1000) == false)
    assert(bud:expired(B, 1010) == true)
end

-- texts
do
    assert(departure.away_text("Ana", "present", "dismiss") == "Ana: present→away (dismiss)")
    assert(departure.away_text("Ana", "returning", "dismiss") == "Ana: returning→away (dismiss)")
    assert(departure.returning_text("Ana", 27) == "Ana: away→returning (backup Lv 27)")
    assert(departure.returning_text("Ana", 27.0) == "Ana: away→returning (backup Lv 27)")
    assert(departure.returning_text("Ana", nil) == "Ana: away→returning (no backup)")
    assert(departure.restored_text("Ana", 5, 27.0) == "Ana: returning→present restored Lv 5→27")
    assert(departure.restored_text("Ana", 5.0, 27) == "Ana: returning→present restored Lv 5→27")
    assert(departure.guard_text("Ana", 30.0, 27.0) == "Ana: returning→present skipped: guard (game Lv 30, backup Lv 27)")
    assert(departure.no_backup_text("Ana", "missing") == "Ana: returning→present skipped: no backup (missing)")
    assert(departure.no_backup_text("Ana", "damaged: not valid JSON")
        == "Ana: returning→present skipped: no backup (damaged: not valid JSON)")
    assert(departure.timeout_text("Ana") == "Ana: restore timed out, stays returning")
    assert(departure.mismatch_text("Ana", "culmative_exp[3]")
        == "Ana: restore read-back differs at culmative_exp[3], stays returning")
    assert(departure.recorded_text("Ana", { "current_job" }) == "Ana: restored, differs from its backup in current_job")
    assert(departure.recorded_text("Ana", { "current_job", "skills" })
        == "Ana: restored, differs from its backup in current_job, skills")
    assert(departure.still_here_text("Ana", "present") == "Ana: dismissed but still in the party, stays present")
    assert(departure.still_here_text("Ana", "returning") == "Ana: dismissed but still in the party, stays returning")
end

print("departure_test ok")
