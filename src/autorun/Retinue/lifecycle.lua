-- The Departure and Return driver. Pure: no REFramework globals, everything is injected, so
-- tests/lifecycle_test.lua drives it with fakes. It applies the hook events (a dismiss, a hire) to the roster
-- and runs the restore attempts. Decisions live in departure.lua, roster.lua and backup.lua; the game thread,
-- the hooks and the writes are the glue's (game/lifecycle_hooks.lua, game/pawn_state.lua).
local backup = require("Retinue.backup")
local departure = require("Retinue.departure")
local roster = require("Retinue.roster")

local M = {}

-- M.new{ retinue, backups, pawns, party, drain, log_line, report } -> flow
--   retinue:   .unit .generation .roster .found .ambiguous, retinue:mark_away(id) -> member, from | nil, err;
--              retinue:mark_returning(id) -> member | nil, err; retinue:mark_present(id, character_id) -> member | nil, err
--   backups:   .store(unit, m, snapshot), .get(id) -> backup | nil, .note(id) -> problem | nil
--   pawns:     .restore(view, b) -> "done" | "wait", why | "mismatch", field;  .read(view) -> snapshot | nil, why
--   party:     .failed, .has_main_pawn(), .level(view) -> number | nil
--   drain():   returns and empties the hook queue (array of events, oldest first):
--              { kind = "dismiss", id = <canonical>, generation = n, snapshot = table|nil }
--              { kind = "hire",    id = <canonical>, generation = n }
--   log_line(text): the [Retinue] prefix is the caller's.
function M.new(deps)
    local retinue, backups, pawns, party = deps.retinue, deps.backups, deps.pawns, deps.party
    local log_line, report = deps.log_line, deps.report
    local budget = departure.new_budget(departure.RETRY_SECONDS)
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
        if retinue:mark_returning(id) == nil then return end -- any other status: nothing
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

    -- on_frame, after retinue.update, before the backup poll.
    function flow.update()
        for _, e in ipairs(deps.drain()) do fifo[#fifo + 1] = e end
        local kept = {}
        for _, e in ipairs(fifo) do
            if e.generation == retinue.generation then kept[#kept + 1] = e end
        end
        fifo = kept
        -- An empty party must not read as "the pawn left": the events wait.
        if party.failed or not party.has_main_pawn() then return end
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
            return
        end
        -- RESTORE
        local result, detail = pawns.restore(view, b)
        if result == "done" then
            if not present(m, view) then return end
            log_line(departure.restored_text(m.name, game_level, b.level))
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

    -- The menu's restore note.
    function flow.note(id) return budget:note(id) end

    return flow
end

return M
