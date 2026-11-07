-- Save-slot decisions. Pure: no REFramework globals, so it runs under plain Lua in tests;
-- game/slot_hooks.lua feeds it the game's start and load requests.
--
-- The player's "save slot" (1-3) is the game's unit (0-2). A global slot is unit * SLOT_PER_UNIT + type,
-- which is what requestLoadGameData and LastLoadedSlot carry (findings 0010).
local M = {}

M.NEW_PLAYTHROUGH, M.NG_PLUS, M.LOAD = "new_playthrough", "ng_plus", "load"
M.ROOT = "Retinue/slots" -- relative to reframework/data, like config.PATH

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
-- LOAD for any other string, nil for a non-string (name unreadable).
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
--   archive_pending  boolean  the last start request began a new playthrough whose slot's roster is to be archived
--               (see on_start_request and take_archive)
--   archives    integer  count of take_archive results (the roster store's request count includes it: see Retinue.lua)
local Session = {}
Session.__index = Session

function M.new_session()
    return setmetatable({
        unit = nil, source = nil, seen = false, last_start = nil, starts = 0, loads = 0,
        archive_pending = false, archives = 0,
    }, Session)
end

-- requestLoadGameData pre: seen = true; loads += 1; unit = unit_of(global_slot, per_unit); source = unit and
-- "load" or nil.
function Session:on_load_request(global_slot, per_unit)
    self.seen = true
    self.loads = self.loads + 1
    self.unit = M.unit_of(global_slot, per_unit)
    self.source = self.unit and "load" or nil
end

-- requestStartType pre: seen = true; starts += 1; last_start = { name, kind }. If name == "NewGame": unit =
-- unit_number's integer view if >= 0 else nil, source = unit and "new_game" or nil. Any other name (including
-- nil): unit = nil, source = nil (the load request that follows sets it). archive_pending = the start is a new
-- playthrough ("NewGame", "RedoNewGame") and, for "NewGame", its unit is known (no load request follows a NewGame,
-- so without a unit nothing could ever name the slot). Every other start clears it, so a restart whose load never
-- came cannot archive a slot loaded later.
function Session:on_start_request(name, unit_number)
    self.seen = true
    self.starts = self.starts + 1
    self.last_start = { name = name, kind = M.classify(name) }
    local unit = nil
    if name == "NewGame" then
        unit = M.to_int(unit_number)
        if unit ~= nil and unit < 0 then unit = nil end
    end
    self.unit = unit
    self.source = unit and "new_game" or nil
    -- Assigned last: re.on_frame may run on the render thread, and a reader that sees the flag must also see the
    -- new unit (with the previous unit it would archive the wrong slot).
    self.archive_pending = M.classify(name) == M.NEW_PLAYTHROUGH and (name ~= "NewGame" or unit ~= nil)
end

-- take_archive() -> unit | nil. When an archive is pending and the unit is known: clears the flag, archives += 1 and
-- returns the unit, once. Otherwise nil and the flag stays (the load request that follows a RedoNewGame sets the unit).
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
