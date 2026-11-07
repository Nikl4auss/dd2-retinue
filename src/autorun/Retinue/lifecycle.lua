-- The Departure and Return driver. Pure: no REFramework globals, everything is injected, so
-- tests/lifecycle_test.lua drives it with fakes. It applies the hook events (a dismiss, a hire) to the roster,
-- runs the party diff (a present member missing from the party becomes away) and runs the restore attempts. After each
-- load it first reconciles the roster with the save (reconcile.lua), once the gate opens; until then all of those wait.
-- Decisions live in departure.lua, roster.lua and backup.lua; the game thread, the hooks and the writes are the
-- glue's (game/lifecycle_hooks.lua, game/pawn_state.lua).
local backup = require("Retinue.backup")
local departure = require("Retinue.departure")
local labels = require("Retinue.labels")
local reconcile = require("Retinue.reconcile")
local roster = require("Retinue.roster")

local M = {}

-- M.new{ retinue, backups, pawns, party, drain, log_line, notify, report, gate } -> flow
--   retinue:   .unit .generation .roster .found .ambiguous, retinue:mark_away(id) -> member, from | nil, err;
--              retinue:mark_returning(id) -> member | nil, err; retinue:mark_present(id, character_id) -> member | nil, err;
--              retinue:correct(corrections) -> count; retinue:settle() (the reconciliation is over)
--   backups:   .store(unit, m, snapshot), .capture(unit, m, view, opts), .get(id) -> backup | nil, .note(id) -> problem | nil
--   pawns:     .restore(view, b) -> "done" | "wait", why | "mismatch", field;  .read(view) -> snapshot | nil, why
--   party:     .failed, .has_main_pawn(), .all_read(), .level(view) -> number | nil
--   drain():   returns and empties the hook queue (array of events, oldest first):
--              { kind = "dismiss", id = <canonical>, generation = n, snapshot = table|nil }
--              { kind = "hire",    id = <canonical>, generation = n }
--   log_line(text): the [Retinue] prefix is the caller's.
--   notify(text):   the player-facing notice (labels.lua), queued by the caller; called for a restore and a guard skip only.
--   gate:      optional, reconcile.new_gate's object (.pending, :check(now, in_world, ready, generation)); the tests replace it.
function M.new(deps)
    local retinue, backups, pawns, party = deps.retinue, deps.backups, deps.pawns, deps.party
    local log_line, notify, report = deps.log_line, deps.notify, deps.report
    local gate = deps.gate or reconcile.new_gate(reconcile.SETTLE_SECONDS, reconcile.GRACE_SECONDS)
    local budget = departure.new_budget(departure.RETRY_SECONDS)
    local diff = departure.new_diff(departure.CHECK_SECONDS, departure.MISS_LIMIT)
    local fifo = {}
    local flow = {}

    -- rehired: a later hire of the same pawn is queued behind this dismiss, so it being back in the party is the
    -- Return, not a pawn that never left.
    local function apply_dismiss(e, m, rehired)
        local id = e.id
        -- Only while present: a snapshot behind a held hire must not touch the frozen backup.
        if e.snapshot and m.status == roster.PRESENT then
            local ok, err = pcall(backups.store, retinue.unit, m, e.snapshot)
            if not ok then report("backup", err) end
        end
        if retinue.ambiguous[id] or (retinue.found[id] and not rehired) then
            log_line(departure.still_here_text(m.name, m.status))
            return
        end
        local member, from = retinue:mark_away(id)
        if member == nil then return end -- already_away: nothing
        budget:forget(id)
        log_line(departure.away_text(m.name, from, "dismiss"))
    end

    local function apply_hire(e, m)
        local id = e.id
        if retinue.ambiguous[id] then return end
        -- A pawn in the party cannot be hired: a present member left unseen (a missed dismiss, a loss).
        if m.status == roster.PRESENT then
            local _, from = retinue:mark_away(id)
            log_line(departure.away_text(m.name, from, "hire"))
        end
        if retinue:mark_returning(id) == nil then return end -- returning: nothing
        budget:forget(id)
        local b = backups.get(id)
        log_line(departure.returning_text(m.name, b and b.level))
    end

    local function apply(e, rehired)
        if retinue.roster == nil then return end
        local m = roster.find(retinue.roster, e.id)
        if m == nil then return end
        if e.kind == "dismiss" then
            apply_dismiss(e, m, rehired)
        elseif e.kind == "hire" then
            apply_hire(e, m)
        end
    end

    -- The hook queue into the fifo, the events of an old generation dropped. Runs before the reconciliation, which has to
    -- see the queued dismisses.
    local function collect_events()
        for _, e in ipairs(deps.drain()) do fifo[#fifo + 1] = e end
        local kept = {}
        for _, e in ipairs(fifo) do
            if e.generation == retinue.generation then kept[#kept + 1] = e end
        end
        fifo = kept
    end

    local function apply_events()
        -- An empty party must not read as "the pawn left", and the old party's state is not the save's: the events wait.
        if gate.pending or party.failed or not party.has_main_pawn() then return end
        local todo = fifo
        fifo = {}
        for i, e in ipairs(todo) do
            local rehired = false
            if e.kind == "dismiss" then
                for j = i + 1, #todo do
                    if todo[j].kind == "hire" and todo[j].id == e.id then rehired = true end
                end
            end
            local ok, err = pcall(apply, e, rehired)
            if not ok then report("lifecycle", err) end
        end
    end

    -- Present members that are in no party slot and not ambiguous, in roster order.
    local function missing()
        local ids = {}
        for _, m in ipairs(retinue.roster.members) do
            local id = m.offline_id
            if m.status == roster.PRESENT and not retinue.found[id] and not retinue.ambiguous[id] then
                ids[#ids + 1] = id
            end
        end
        return ids
    end

    -- A member missing for MISS_LIMIT checks left unseen (a loss): away, whatever the progression toggle says. Its
    -- backup stays the last poll.
    local function absence(id)
        local m = roster.find(retinue.roster, id)
        if m == nil then return end
        local member, from = retinue:mark_away(id)
        if member == nil then return end
        log_line(departure.away_text(m.name, from, "absence"))
    end

    -- What the save says about a member in the party: the cached CharacterID from the view, and the progress and the hire
    -- time from a read. A read that fails is reported and leaves those unknown; the second result is true then.
    local function party_entry(m, view)
        local entry = { character_id = view.character_id }
        local ok, s, why = pcall(pawns.read, view)
        if not ok then s, why = nil, s end
        if s == nil then
            report("reconcile", m.name .. ": " .. tostring(why))
            return entry, true
        end
        entry.level, entry.exp, entry.discipline, entry.hire_time = s.level, s.exp, s.discipline, s.hire_time
        return entry, false
    end

    -- The reconciliation: the roster against the party the loaded save put in the world.
    local function reconcile_pass()
        local r = retinue.roster
        if r == nil or r.mode == roster.LOCKED then return end
        local seen = {}
        -- Ambiguous, plus a member whose read failed with the CharacterID it kept: nothing proves a rollback or a re-hire,
        -- and a false rollback lowers the backup. (A different CharacterID is evidence enough and goes through the plan.)
        local skip = {}
        for id in pairs(retinue.ambiguous) do skip[id] = true end
        -- A queued dismiss is applied after the pass and logs its own cause. Its snapshot goes: taken before the pass, it
        -- may be a save that predates a restore, and storing it would lower the backup for good.
        for _, e in ipairs(fifo) do
            if e.kind == "dismiss" then
                skip[e.id] = true
                e.snapshot = nil
            end
        end
        for _, m in ipairs(r.members) do
            local view = retinue.found[m.offline_id]
            if view ~= nil then
                local entry, failed = party_entry(m, view)
                seen[m.offline_id] = entry
                if failed and m.character_id ~= nil and view.character_id == m.character_id then
                    skip[m.offline_id] = true
                end
            end
        end
        local corrections = reconcile.plan(r, seen, skip, backups.get)
        if #corrections == 0 then return end
        retinue:correct(corrections)
        for _, c in ipairs(corrections) do log_line(c.text) end
    end

    -- on_frame, after retinue.update, before the backup poll: the reconciliation when its gate opens, the hook events,
    -- then the party diff (in the world only; a queued dismiss wins and logs its own cause). All of them wait for the
    -- reconciliation after a load.
    function flow.update(now, in_world)
        collect_events()
        local complete = not party.failed and party.has_main_pawn() and party.all_read()
        if gate:check(now, in_world, complete, retinue.generation) then
            local ok, err = pcall(reconcile_pass)
            if not ok then report("reconcile", err) end
            retinue:settle() -- a failed pass must not hold the session
        end
        apply_events()
        local r = retinue.roster
        local ready = in_world and r ~= nil and r.mode ~= roster.LOCKED and not party.failed and party.has_main_pawn()
            and party.all_read() and not gate.pending
        for _, id in ipairs(diff:check(now, ready, retinue.generation, missing)) do
            local ok, err = pcall(absence, id)
            if not ok then report("lifecycle", err) end
        end
    end

    -- true when the member is present now; a refusal (a roster that changed under us) is reported and the log line skipped.
    local function present(m, view)
        local member, err = retinue:mark_present(m.offline_id, view.character_id)
        if member == nil then
            report("restore", m.name .. ": " .. tostring(err))
            return false
        end
        budget:forget(m.offline_id)
        return true
    end

    local function time_out(m)
        budget:close(m.offline_id, "timed out")
        log_line(departure.timeout_text(m.name))
    end

    local function attempt(m, now)
        local id = m.offline_id
        local view = retinue.found[id]
        local game_level = view and party.level(view)
        local b = backups.get(id)
        local expired = budget:expired(id, now)
        local action = departure.step{ in_party = view ~= nil, game_level = game_level, backup = b, expired = expired }
        if action == departure.WAIT then return end
        if action == departure.TIMEOUT then
            time_out(m)
            return
        end
        if action == departure.SKIP_NO_BACKUP then
            if not present(m, view) then return end
            log_line(departure.no_backup_text(m.name, backups.note(id) or "missing"))
            return
        end
        if action == departure.SKIP_GUARD then
            if not present(m, view) then return end
            log_line(departure.guard_text(m.name, game_level, b.level))
            notify(labels.kept(m.name, game_level))
            return
        end
        -- RESTORE
        local result, detail = pawns.restore(view, b)
        if result == "done" then
            if not present(m, view) then return end
            -- A save at or below this level predates the restore (reconcile.rehired). Written now, with the new hire time:
            -- a load before the next poll must find both.
            b.restored_from = game_level
            log_line(departure.restored_text(m.name, game_level, b.level))
            notify(labels.returned(m.name, b.level))
            local ok_c, err_c = pcall(backups.capture, retinue.unit, m, view, { force = true })
            if not ok_c then report("backup", err_c) end
            local ok, err = pcall(function()
                local fresh, why = pawns.read(view)
                if fresh == nil then
                    report("restore", m.name .. ": " .. tostring(why))
                    return
                end
                local keys = backup.recorded_mismatch(b, fresh)
                if #keys > 0 then log_line(departure.recorded_text(m.name, keys)) end
            end)
            if not ok then report("restore", m.name .. ": " .. tostring(err)) end
        elseif result == "mismatch" then
            budget:close(id, "differs at " .. tostring(detail))
            log_line(departure.mismatch_text(m.name, tostring(detail)))
        else
            -- A ready pawn gets its attempt on the expiring frame; an attempt that does not finish then ends the wait.
            report("restore", m.name .. ": " .. tostring(detail))
            if expired then time_out(m) end
        end
    end

    -- UpdateBehavior, game thread: the restore attempts.
    function flow.tick(now, in_world)
        budget:sync(retinue.generation)
        if gate.pending then return end
        if not (in_world and roster.writable(retinue.roster)) then return end
        for _, m in ipairs(retinue.roster.members) do
            local id = m.offline_id
            if m.status == roster.RETURNING and not retinue.ambiguous[id] and not budget:closed(id) then
                local ok, err = pcall(attempt, m, now)
                if not ok then
                    report("restore", tostring(err))
                    if budget:expired(id, now) then time_out(m) end
                end
            end
        end
    end

    -- false from a load until its reconciliation ran: the backup poll waits too.
    function flow.settled() return not gate.pending end

    -- The menu's restore note.
    function flow.note(id) return budget:note(id) end

    return flow
end

return M
