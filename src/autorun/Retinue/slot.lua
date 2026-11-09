-- Save-slot decisions. Pure: no REFramework globals, so it runs under plain Lua in tests;
-- game/slot_hooks.lua feeds it the game's start, load and save requests.
--
-- The player's "save slot" (1-3) is the game's unit (0-2). A global slot is unit * SLOT_PER_UNIT + type,
-- which is what requestLoadGameData and LastLoadedSlot carry (findings 0010).
local M = {}

M.NEW_PLAYTHROUGH, M.NG_PLUS, M.LOAD = "new_playthrough", "ng_plus", "load"
M.ROOT = "Retinue/slots" -- relative to reframework/data, like config.PATH
M.CLEAR_TYPE = 3 -- save type of the copy a restart's conversion writes at the title (SAVE_SLOT_CLEAR, findings 0010)
M.RESTART_WAIT = 10 -- seconds (os.clock) a restart waits for the game's clear flag before it archives (decide_restart)

-- Integer view of a number: integral floats accepted (2.0 -> 2); anything else -> nil.
function M.to_int(n)
    if type(n) ~= "number" then return nil end
    return math.tointeger(n)
end

-- unit_of(global_slot, per_unit) -> integer unit >= 0, or nil when either is not an integer, per_unit < 1,
-- or global_slot < 0 (the system save is -1). Floor division: 9, 5 -> 1; 4, 5 -> 0.
function M.unit_of(global_slot, per_unit)
    local g, p = M.to_int(global_slot), M.to_int(per_unit)
    if g == nil or p == nil or p < 1 or g < 0 then return nil end
    return g // p
end

-- classify(start_name) -> NEW_PLAYTHROUGH for "NewGame" and "RedoNewGame", NG_PLUS for "RedoNewGameSkip",
-- LOAD for any other string, nil for a non-string (name unreadable). By name only: a "RedoNewGame" is also what
-- "Start from Beginning" over a cleared slot sends (the same playthrough, like NG+), so the session decides which it
-- is from the game's clear flag (Session:decide_restart).
function M.classify(start_name)
    if type(start_name) ~= "string" then return nil end
    if start_name == "NewGame" or start_name == "RedoNewGame" then return M.NEW_PLAYTHROUGH end
    if start_name == "RedoNewGameSkip" then return M.NG_PLUS end
    return M.LOAD
end

-- fallback(last_loaded_slot, unit_number, per_unit) -> unit_of(last_loaded_slot, per_unit) when that is non-nil
-- and equals unit_number (integer view), else nil. For a mod loaded mid-session: two game values must agree.
function M.fallback(last_loaded_slot, unit_number, per_unit)
    local u = M.unit_of(last_loaded_slot, per_unit)
    if u ~= nil and u == M.to_int(unit_number) then return u end
    return nil
end

-- dir(unit) -> "Retinue/slots/<unit + 1>"; archive_name(t) -> "archive-<yyyymmdd-hhmmss>" from an os.date("*t")
-- shaped table (zero-padded); archive_dir(unit, t) -> dir(unit) .. "/" .. archive_name(t).
function M.dir(unit)
    return string.format("%s/%d", M.ROOT, unit + 1)
end

function M.archive_name(t)
    return string.format("archive-%04d%02d%02d-%02d%02d%02d", t.year, t.month, t.day, t.hour, t.min, t.sec)
end

function M.archive_dir(unit, t)
    return M.dir(unit) .. "/" .. M.archive_name(t)
end

-- label(unit) -> "Slot <unit + 1>" or "Slot unknown" for nil.
function M.label(unit)
    if unit == nil then return "Slot unknown" end
    return string.format("Slot %d", unit + 1)
end

-- Session state. Fields read by the glue and later tickets:
--   unit        integer | nil  the loaded unit
--   source      "load" | "new_game" | "fallback" | nil  how unit was set
--   seen        boolean  a start or load request was seen this session (disables the fallback for good)
--   last_start  nil | { name = string|nil, kind = classify(name) }  the last start request
--   starts      integer  count of start requests seen (later tickets detect a new start by comparing it)
--   loads       integer  count of load requests seen (later tickets detect a new load, e.g. a death reload of the
--               same unit, by comparing it)
--   first_save_pending  boolean  a NewGame waits for its first save: the old saves are still on disk until then, so
--               the slot's roster is neither active nor archived (see roster_unit and on_save_request)
--   restart_pending  boolean  a "RedoNewGame" waits for the game's clear flag (see decide_restart): a restart over a
--               cleared slot keeps the roster (NG+), over a slot not cleared it archives. No roster is active meanwhile
--   restart_since  number | nil  the clock (os.clock) at the first decide_restart with a unit; the wait is timed from it
--   archive_pending  boolean  the slot's roster is to be archived now (see on_start_request, on_save_request,
--               decide_restart and take_archive)
--   archives    integer  count of take_archive results (the roster store's request count includes it: see Retinue.lua)
local Session = {}
Session.__index = Session

function M.new_session()
    return setmetatable({
        unit = nil, source = nil, seen = false, last_start = nil, starts = 0, loads = 0,
        first_save_pending = false, restart_pending = false, restart_since = nil, archive_pending = false, archives = 0,
    }, Session)
end

-- requestLoadGameData pre: seen = true; loads += 1; unit = unit_of(global_slot, per_unit); source = unit and
-- "load" or nil. A load ends the wait for a NewGame's first save: that game was given up, the old roster stays.
function Session:on_load_request(global_slot, per_unit)
    self.seen = true
    self.loads = self.loads + 1
    self.unit = M.unit_of(global_slot, per_unit)
    self.source = self.unit and "load" or nil
    self.first_save_pending = false -- after the unit: the frame loop must not activate the previous unit's roster
end

-- requestStartType pre: seen = true; starts += 1; last_start = { name, kind }. If name == "NewGame": unit =
-- unit_number's integer view if >= 0 else nil, source = unit and "new_game" or nil. Any other name (including
-- nil): unit = nil, source = nil (the load request that follows sets it). Every start replaces the three flags:
-- first_save_pending = a "NewGame" with a known unit; restart_pending = a "RedoNewGame" (decide_restart settles it);
-- archive_pending = false. So a restart whose load never came cannot archive a slot loaded later.
function Session:on_start_request(name, unit_number)
    self.seen = true
    self.starts = self.starts + 1
    self.last_start = { name = name, kind = M.classify(name) }
    local unit = nil
    if name == "NewGame" then
        unit = M.to_int(unit_number)
        if unit ~= nil and unit < 0 then unit = nil end
    end
    -- Before the unit: re.on_frame may run on the render thread, and a NewGame's unit must not read as active.
    self.first_save_pending = name == "NewGame" and unit ~= nil
    self.unit = unit
    self.source = unit and "new_game" or nil
    -- Assigned last: a reader that sees a flag must also see the new unit (with the previous unit it would archive the
    -- wrong slot). A RedoNewGame has already converted the old saves, but whether it archives depends on the clear flag,
    -- which the game sets a frame or so later: decide_restart. A NewGame leaves the saves on disk until its first save.
    self.restart_since = nil
    self.restart_pending = name == "RedoNewGame"
    self.archive_pending = false
end

-- SaveDataManager.requestSaveSlot pre -> true when this is the first save of a NewGame: a save of its unit while
-- first_save_pending, except the system save (-1, no unit) and a conversion's copy (CLEAR_TYPE: written at the title with
-- no start or load before it, and the restart it belongs to has its own start). Any start or load ends the wait, so
-- what is left can only be the new game's. The archive flag is set before the wait ends.
function Session:on_save_request(global_slot, per_unit)
    if not self.first_save_pending or self.unit == nil then return false end
    if M.unit_of(global_slot, per_unit) ~= self.unit then return false end
    if M.to_int(global_slot) % M.to_int(per_unit) == M.CLEAR_TYPE then return false end
    self.archive_pending = true
    self.first_save_pending = false
    return true
end

-- roster_unit() -> the unit whose roster is active: nil while a NewGame waits for its first save (nothing of the old
-- roster is shown, used or written, and giving the game up leaves it as it was) or a restart waits for the clear flag,
-- else unit.
function Session:roster_unit()
    if self.first_save_pending or self.restart_pending then return nil end
    return self.unit
end

-- decide_restart(clear, restart_data, now) -> nil | "kept" | "archived" | "timeout". Called by the glue every game update
-- with the game's flags (GuiManager._IsGameClearData, _IsRestartData; nil = unreadable) and the clock. Nothing pending, or
-- the restart's load request not seen yet (unit nil): nil, nothing changes. The first call with a unit starts the timer.
--   restart_data true, clear true      -> "kept": the slot is cleared, the same playthrough (NG+); the roster stays
--   restart_data true, clear false     -> "archived" (archive_pending set)
--   restart_data true, clear not a boolean -> "archived" (fail closed)
--   restart_data not true              -> nil (wait), or "timeout" (archive_pending set) after RESTART_WAIT seconds
-- A decision sets archive_pending before it ends the wait, so the old roster is never active with no archive flagged.
function Session:decide_restart(clear, restart_data, now)
    if not self.restart_pending then return nil end
    if self.unit == nil then return nil end
    if self.restart_since == nil then self.restart_since = now end
    if restart_data == true then
        if clear == true then
            self.restart_pending = false
            return "kept"
        end
        self.archive_pending = true
        self.restart_pending = false
        return "archived"
    end
    if now - self.restart_since >= M.RESTART_WAIT then
        self.archive_pending = true
        self.restart_pending = false
        return "timeout"
    end
    return nil
end

-- take_archive() -> unit | nil. When an archive is pending and the unit is known: clears the flag, archives += 1 and
-- returns the unit, once. Otherwise nil and the flag stays.
function Session:take_archive()
    if not self.archive_pending then return nil end
    local unit = self.unit -- one read: a hook may change it on another thread
    if unit == nil then return nil end
    self.archive_pending = false
    self.archives = self.archives + 1
    return unit
end

-- Called by the glue every frame while in the world. Does nothing once seen. Otherwise unit = fallback(...),
-- source = unit and "fallback" or nil.
function Session:on_world(last_loaded_slot, unit_number, per_unit)
    if self.seen then return end
    self.unit = M.fallback(last_loaded_slot, unit_number, per_unit)
    self.source = self.unit and "fallback" or nil
end

return M
