-- Departure and Return decisions. Pure: no REFramework globals, so it runs under plain Lua in tests; lifecycle.lua
-- drives it and game/ does the hooks and the writes. Here: what a restore attempt does next, the retry budget of
-- a Return, the miss counts of the party diff (a member that left unseen), and the log texts of the transitions.
local backup = require("Retinue.backup")
local slot = require("Retinue.slot")

local M = {}

M.RETRY_SECONDS = 10
M.CHECK_SECONDS = 1
M.MISS_LIMIT = 3
M.WAIT, M.RESTORE, M.SKIP_GUARD, M.SKIP_NO_BACKUP, M.TIMEOUT = "wait", "restore", "skip_guard", "skip_no_backup", "timeout"

-- step{ in_party = boolean, game_level = number|nil, backup = table|nil, expired = boolean } -> action
--   not in_party, or game_level nil or < 1 -> TIMEOUT when expired, else WAIT
--   backup nil -> SKIP_NO_BACKUP
--   backup.guard(game_level, backup.level) == HIGHER -> SKIP_GUARD; else RESTORE
-- (expired only ends the wait: a pawn that is ready on the last frame still restores.)
function M.step(s)
    if not s.in_party or s.game_level == nil or s.game_level < 1 then
        if s.expired then return M.TIMEOUT end
        return M.WAIT
    end
    if s.backup == nil then return M.SKIP_NO_BACKUP end
    if backup.guard(s.game_level, s.backup.level) == backup.HIGHER then return M.SKIP_GUARD end
    return M.RESTORE
end

-- new_budget(seconds) -> budget: one entry per member, all of them dropped when the generation changes.
local Budget = {}
Budget.__index = Budget

function M.new_budget(seconds)
    return setmetatable({ seconds = seconds, generation = nil, entries = {} }, Budget)
end

-- budget:sync(generation): a new generation drops every entry.
function Budget:sync(generation)
    if generation ~= self.generation then
        self.generation = generation
        self.entries = {}
    end
end

-- budget:expired(id, now) -> boolean. The first call for an id starts its deadline; true once now >= deadline.
function Budget:expired(id, now)
    local e = self.entries[id]
    if e == nil then
        e = {}
        self.entries[id] = e
    end
    if e.deadline == nil then e.deadline = now + self.seconds end
    return now >= e.deadline
end

-- budget:close(id, note): no more attempts this generation; note says why.
function Budget:close(id, note)
    local e = self.entries[id]
    if e == nil then
        e = {}
        self.entries[id] = e
    end
    e.closed = note
end

function Budget:closed(id)
    local e = self.entries[id]
    return e ~= nil and e.closed ~= nil
end

-- budget:forget(id): drops the entry.
function Budget:forget(id) self.entries[id] = nil end

-- budget:note(id) -> nil (never started) | "pending" | the close note.
function Budget:note(id)
    local e = self.entries[id]
    if e == nil then return nil end
    return e.closed or "pending"
end

-- new_diff(interval, limit) -> diff; the counts of the party diff, per member.
-- diff:check(now, in_world, generation, missing) -> ids that just became absent, in missing's order (usually {})
--   missing() -> array of ids missing right now; called only when a check is due.
--   A check is due every `interval` in the world (backup.new_poll: re-armed on entering the world and on a new generation).
--   Each id in missing gains 1; an id not in it loses its count (a reappearance resets); an id reaching `limit` is returned
--   and loses its count. Not in the world, or a new generation: every count is dropped.
local Diff = {}
Diff.__index = Diff

function M.new_diff(interval, limit)
    return setmetatable({ poll = backup.new_poll(interval), limit = limit, generation = nil, counts = {} }, Diff)
end

function Diff:check(now, in_world, generation, missing)
    if generation ~= self.generation or not in_world then
        self.generation = generation
        self.counts = {}
    end
    if not self.poll:tick(now, in_world, generation) then return {} end
    local counts, gone = {}, {}
    for _, id in ipairs(missing()) do
        local n = (self.counts[id] or 0) + 1
        if n >= self.limit then
            gone[#gone + 1] = id
        else
            counts[id] = n
        end
    end
    self.counts = counts
    return gone
end

-- Log texts, without the [Retinue] prefix. docs/testing.md reads these lines.
local function num(n) return tostring(slot.to_int(n) or n) end

function M.away_text(name, from, cause)
    return string.format("%s: %s→away (%s)", name, from, cause)
end

function M.returning_text(name, level)
    local what = level == nil and "no backup" or ("backup Lv " .. num(level))
    return string.format("%s: away→returning (%s)", name, what)
end

function M.restored_text(name, a, b)
    return string.format("%s: returning→present restored Lv %s→%s", name, num(a), num(b))
end

function M.guard_text(name, game, backup_level)
    return string.format("%s: returning→present skipped: guard (game Lv %s, backup Lv %s)",
        name, num(game), num(backup_level))
end

function M.no_backup_text(name, problem)
    return string.format("%s: returning→present skipped: no backup (%s)", name, problem)
end

function M.timeout_text(name)
    return string.format("%s: restore timed out, stays returning", name)
end

function M.mismatch_text(name, field)
    return string.format("%s: restore read-back differs at %s, stays returning", name, field)
end

function M.recorded_text(name, keys)
    return string.format("%s: restored, differs from its backup in %s", name, table.concat(keys, ", "))
end

function M.still_here_text(name, status)
    return string.format("%s: dismissed but still in the party, stays %s", name, status)
end

return M
