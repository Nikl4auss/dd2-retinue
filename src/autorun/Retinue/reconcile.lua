-- Reconciliation on load: what the roster should say once the loaded save is in the world. Pure: no REFramework
-- globals, so it runs under plain Lua in tests; lifecycle.lua drives it and game/ reads the party and writes the
-- roster. Here: the discriminator (was this member re-hired since its backup), the table of corrections, their log
-- texts, and the gate that runs the pass once per generation.
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

M.SETTLE_SECONDS = 3 -- in the world with a complete party, before the pass: the party diff's 3 checks
M.GRACE_SECONDS = 20 -- a generation that never leaves the world stops waiting for it

-- first_hire_state(p, b) -> boolean: p.exp == 0, p.discipline == 0, and p is behind b: p.level < b.level, or equal level
-- with b.exp > 0 or b.discipline > 0. Any of p.level, p.exp, p.discipline nil, or b nil -> false.
function M.first_hire_state(p, b)
    if b == nil then return false end
    local level, exp, discipline = p.level, p.exp, p.discipline
    if level == nil or exp == nil or discipline == nil or b.level == nil then return false end
    if exp ~= 0 or discipline ~= 0 then return false end
    if level < b.level then return true end
    return level == b.level and ((b.exp or 0) > 0 or (b.discipline or 0) > 0)
end

-- rehired(m, p, b) -> boolean. m member, p party entry, b backup|nil.
--   hire = slot.to_int(b and b.hire_time), seen = slot.to_int(p.hire_time). Both non-nil: hire ~= seen.
--   Otherwise: m.character_id nil -> m.status ~= roster.PRESENT. p.character_id ~= m.character_id -> true. Else first_hire_state(p, b).
function M.rehired(m, p, b)
    local hire = slot.to_int(b and b.hire_time)
    local seen = slot.to_int(p.hire_time)
    if hire ~= nil and seen ~= nil then return hire ~= seen end
    if m.character_id == nil then return m.status ~= roster.PRESENT end
    if p.character_id ~= m.character_id then return true end
    return M.first_hire_state(p, b)
end

-- Log texts, without the [Retinue] prefix. docs/testing.md reads these lines.
local function num(n) return tostring(slot.to_int(n) or n) end

local function level_text(n)
    if n == nil then return "Lv?" end
    return "Lv" .. num(n)
end

local function backup_text(b)
    if b == nil then return "no backup" end
    return "backup " .. level_text(b.level)
end

function M.rollback_text(name, p, b)
    return string.format("%s: roster away, save has it %s (%s) → present, save wins",
        name, level_text(p.level), backup_text(b))
end

function M.unseen_text(name, from, p, b)
    return string.format("%s: roster %s, save has it %s (%s) → returning, re-hired unseen",
        name, from, level_text(p.level), backup_text(b))
end

function M.absent_text(name, from, b)
    return string.format("%s: roster %s, not in the save's party (%s) → away, backup kept", name, from, backup_text(b))
end

-- plan(r, party, ambiguous, backup_of) -> corrections, in roster order
--   party:     { [offline_id] = { character_id = int|nil, level = int|nil, exp = int|nil, discipline = int|nil, hire_time = int|nil } }
--   ambiguous: { [offline_id] = true }
--   backup_of(id) -> backup | nil
--   correction: { id = <canonical>, name = string, from = status, to = status, text = string }
--   nil r or LOCKED -> {}. An ambiguous member -> none.
-- Rows (status / in party / rehired -> to): present, in, no -> none; present, in, yes -> returning; present, out -> away;
-- away, in, no -> present (the save wins); away, in, yes -> returning; away, out -> none; returning, in -> none
-- (flow.tick retries the restore); returning, out -> away.
function M.plan(r, party, ambiguous, backup_of)
    local out = {}
    if r == nil or r.mode == roster.LOCKED then return out end
    for _, m in ipairs(r.members) do
        local id = m.offline_id
        if not ambiguous[id] then
            local p = party[id]
            local b = backup_of(id)
            local to, text
            if p == nil then
                if m.status ~= roster.AWAY then
                    to, text = roster.AWAY, M.absent_text(m.name, m.status, b)
                end
            elseif m.status ~= roster.RETURNING then
                if M.rehired(m, p, b) then
                    to, text = roster.RETURNING, M.unseen_text(m.name, m.status, p, b)
                elseif m.status == roster.AWAY then
                    to, text = roster.PRESENT, M.rollback_text(m.name, p, b)
                end
            end
            if to ~= nil then
                out[#out + 1] = { id = id, name = m.name, from = m.status, to = to, text = text }
            end
        end
    end
    return out
end

-- new_gate(settle, grace) -> gate; one reconciliation per generation.
-- gate.pending: true from a new generation until check returns true.
-- gate:check(now, in_world, party_ready, generation) -> true on the one call that should run the pass
--   A new generation re-arms the gate. The pass waits for the game to leave the world after the bump (the old party
--   may still be there), or `grace` seconds when it never does, then for `settle` seconds in the world with a complete
--   party read; leaving the world or an incomplete read restarts the settle.
local Gate = {}
Gate.__index = Gate

function M.new_gate(settle, grace)
    return setmetatable({
        settle = settle, grace = grace,
        generation = nil, pending = false, left = false, born = nil, since = nil, was_world = false,
    }, Gate)
end

function Gate:check(now, in_world, party_ready, generation)
    if generation ~= self.generation then
        self.generation = generation
        self.pending = true
        self.left = not self.was_world
        self.born = now
        self.since = nil
    end
    self.was_world = in_world == true
    if not self.pending then return false end
    if not in_world then
        self.left = true
        self.since = nil
        return false
    end
    if not self.left and now < self.born + self.grace then return false end
    if not party_ready then
        self.since = nil
        return false
    end
    self.since = self.since or now
    if now < self.since + self.settle then return false end
    self.pending = false
    return true
end

return M
