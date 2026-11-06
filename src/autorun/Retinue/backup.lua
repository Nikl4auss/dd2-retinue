-- backups/<offline_id>.json: the per-pawn backup of one save slot. Pure: no REFramework globals, so it runs under
-- plain Lua in tests; game/ reads the pawn and does the file I/O. Decisions live here: the file's shape, validating
-- a file read from disk, "did anything change", the level guard (the game's save wins over a higher backup), and
-- the poll timing.
local slot = require("Retinue.slot")
local roster = require("Retinue.roster")

local M = {}

M.VERSION = 1
M.POLL_SECONDS = 10
M.EQUAL, M.LOWER, M.HIGHER = "equal", "lower", "higher"
M.NONE, M.WRITE, M.LOWERED = "none", "write", "lowered"
M.INCREASE_KEYS = { "hit_point", "stamina", "attack", "defence", "magic_attack", "magic_defence", "blow", "weight" }
M.RECORDED_KEYS = { "current_job", "qualified_job_bits", "changed_job_bits", "item_ids", "skills", "hire_time", "restored_from" }

-- The backup / snapshot (one flat table; also the file's content):
--   { version = 1, offline_id = <canonical>, name = string,
--     -- restored
--     level = int, exp = int, increase_params = { <M.INCREASE_KEYS> = int }, extra_status_boost = int,
--     discipline = int, culmative_exp = { int, ... },
--     -- recorded, never restored (any may be nil)
--     current_job = int, qualified_job_bits = int, changed_job_bits = int,
--     item_ids = { int, ... }, skills = { { string|int, ... }, ... },   -- skills: one list per EquipedSkills entry
--     hire_time = int,    -- SubPawnDataContext._HireTime in ms; marks one hire
--     restored_from = int }   -- the game's level the last restore started from; a save at or below it predates that restore

function M.path(unit, offline_id)
    return slot.dir(unit) .. "/backups/" .. offline_id .. ".json"
end

-- true when t is a non-empty table whose keys are exactly the integers 1..n and whose values are all integers.
local function integer_sequence(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k, v in pairs(t) do
        if math.type(k) ~= "integer" or k < 1 or slot.to_int(v) == nil then return false end
        n = n + 1
    end
    if n == 0 then return false end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

-- invalid(b) -> nil when b is a usable backup, else a short phrase naming the first bad field. Recorded fields are
-- not checked (they are never restored).
function M.invalid(b)
    if type(b) ~= "table" then return "not an object" end
    if roster.canonical_id(b.offline_id) == nil then return "offline_id is missing or invalid" end
    local level = slot.to_int(b.level)
    if level == nil or level < 1 then return "level is missing or invalid" end
    if slot.to_int(b.exp) == nil then return "exp is missing or invalid" end
    if type(b.increase_params) ~= "table" then return "increase_params is missing or invalid" end
    for _, key in ipairs(M.INCREASE_KEYS) do
        if slot.to_int(b.increase_params[key]) == nil then
            return "increase_params." .. key .. " is missing or invalid"
        end
    end
    if slot.to_int(b.extra_status_boost) == nil then return "extra_status_boost is missing or invalid" end
    if slot.to_int(b.discipline) == nil then return "discipline is missing or invalid" end
    if not integer_sequence(b.culmative_exp) then return "culmative_exp is missing or invalid" end
    return nil
end

-- resolve(status, data, offline_id) -> backup | nil, problem. status / data as jsonfile.read returns them.
function M.resolve(status, data, offline_id)
    if status == "missing" then return nil, "missing" end
    if status == "unparseable" then return nil, "damaged: not valid JSON" end
    if status ~= "ok" then return nil, "damaged: cannot be read" end
    if type(data) ~= "table" then return nil, "damaged: not an object" end
    local version = slot.to_int(data.version)
    if version == nil or version < 1 then return nil, "damaged: version is missing or invalid" end
    if version > M.VERSION then return nil, "newer version " .. version end
    local why = M.invalid(data)
    if why then return nil, "damaged: " .. why end
    if roster.canonical_id(data.offline_id) ~= roster.canonical_id(offline_id) then
        return nil, "damaged: belongs to another pawn"
    end
    return data
end

local function empty_table(v) return type(v) == "table" and next(v) == nil end

-- same(a, b) -> boolean. Deep comparison: numbers by == (1 and 1.0 are equal), tables over the union of keys, and
-- nil equals an empty table at any depth (REFramework's json writes an empty table as null, which reads back nil).
function M.same(a, b)
    if a == nil then return b == nil or empty_table(b) end
    if b == nil then return empty_table(a) end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not M.same(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if not M.same(a[k], v) then return false end
    end
    return true
end

-- restored_mismatch(b, back) -> nil | field. Compares what a restore writes (level, exp, each increase_params key,
-- extra_status_boost, discipline, culmative_exp: length, then elements) between the backup b and the values read
-- back from the pawn; numbers by ==. field names the first difference: "level", "increase_params.attack",
-- "culmative_exp[3]", "culmative_exp length".
function M.restored_mismatch(b, back)
    for _, key in ipairs({ "level", "exp" }) do
        if b[key] ~= back[key] then return key end
    end
    local ip = back.increase_params or {}
    for _, key in ipairs(M.INCREASE_KEYS) do
        if b.increase_params[key] ~= ip[key] then return "increase_params." .. key end
    end
    for _, key in ipairs({ "extra_status_boost", "discipline" }) do
        if b[key] ~= back[key] then return key end
    end
    local a, c = b.culmative_exp, back.culmative_exp or {}
    if #a ~= #c then return "culmative_exp length" end
    for i = 1, #a do
        if a[i] ~= c[i] then return "culmative_exp[" .. i .. "]" end
    end
    return nil
end

-- recorded_mismatch(b, fresh) -> { key, ... }: the keys among current_job, qualified_job_bits, changed_job_bits and
-- skills that are non-nil on both sides and not same, in that order; empty when none. item_ids are not compared
-- (the game regenerates them on every hire).
function M.recorded_mismatch(b, fresh)
    local out = {}
    for _, key in ipairs({ "current_job", "qualified_job_bits", "changed_job_bits", "skills" }) do
        if b[key] ~= nil and fresh[key] ~= nil and not M.same(b[key], fresh[key]) then out[#out + 1] = key end
    end
    return out
end

-- carry_recorded(fresh, last): each recorded key that is nil in fresh is copied from last (last nil: unchanged).
-- Mutates and returns fresh.
function M.carry_recorded(fresh, last)
    if last == nil then return fresh end
    for _, key in ipairs(M.RECORDED_KEYS) do
        if fresh[key] == nil then fresh[key] = last[key] end
    end
    return fresh
end

-- guard(game_level, backup_level) -> the game's level relative to the backup's.
function M.guard(game_level, backup_level)
    if game_level < backup_level then return M.LOWER end
    if game_level > backup_level then return M.HIGHER end
    return M.EQUAL
end

-- decide(last, fresh) -> NONE (nothing changed) | LOWERED (the game is below the backup: write, with a warning) |
-- WRITE. A nil last is WRITE.
function M.decide(last, fresh)
    if M.same(last, fresh) then return M.NONE end
    if last ~= nil and M.guard(fresh.level, last.level) == M.LOWER then return M.LOWERED end
    return M.WRITE
end

function M.lowered_text(name, game_level, backup_level)
    return string.format("%s: save has Lv %s, backup had Lv %s -> backup lowered, save wins",
        name, tostring(slot.to_int(game_level) or game_level), tostring(slot.to_int(backup_level) or backup_level))
end

-- new_poll(interval) -> poll; poll:tick(now, in_world, generation) -> true when a backup pass is due. The timer
-- re-arms (a full interval to wait) on a new generation (roster reload) and on entering the world.
local Poll = {}
Poll.__index = Poll

function M.new_poll(interval)
    return setmetatable({ interval = interval, generation = nil, deadline = nil }, Poll)
end

function Poll:tick(now, in_world, generation)
    if generation ~= self.generation then
        self.generation = generation
        self.deadline = nil
    end
    if not in_world then
        self.deadline = nil
        return false
    end
    if self.deadline == nil then
        self.deadline = now + self.interval
        return false
    end
    if now >= self.deadline then
        self.deadline = now + self.interval
        return true
    end
    return false
end

return M
