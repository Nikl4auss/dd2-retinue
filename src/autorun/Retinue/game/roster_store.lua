-- REFramework glue: the roster of the active save slot (uses log; file I/O is game/jsonfile; the member backups are
-- game/backup_store). The decisions (reading a file into a roster, adopt / release, cache refresh, ambiguity) live in
-- Retinue/roster.lua.

local jsonfile = require("Retinue.game.jsonfile")
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

-- backups is game/backup_store's object: re-activated on every roster (re)load, a backup captured on adopt and the
-- file removed on release.
-- Returns a store:
--   unit          integer|nil   the unit whose roster is active (nil = unknown slot: no roster, nothing read or written)
--   roster        roster|nil    roster.resolve result for unit; nil when unit is nil
--   ambiguous     { [offline_id] = true }  from the last update
--   found         { [offline_id] = view }  from the last update
--   save_failed   boolean       last write failed (cleared by the next successful one)
--   generation    integer       incremented on every unit switch or reload (the menu drops its pending confirm)
--   update(unit, party, requests) -- plain call, every frame, after party.refresh and the slot tracker; requests:
--                                    the tracker's start + load request count (a change means a new load)
--   store:adopt(view) -> true | nil, err      -- err: roster's errors, plus "no_slot"
--   store:release(offline_id) -> true | nil, err
--   store:mark_away(id) -> member, previous_status | nil, err;  store:mark_returning(id) -> member | nil, err;
--   store:mark_present(id, character_id) -> member | nil, err
--                      -- the roster.mark_* transitions, saved on success (no file in read-only); "no_slot" without a roster
-- roster.json is read when the active unit changes or a new start/load request was seen (a reload of the same
-- unit: the frame loop may never see the unit go nil in between, so the unit alone would miss it). It is written
-- only by save(), only while the roster is writable.
-- Lines go to log.error (another mod may raise the log level and drop warnings), with the [Retinue] prefix.
function M.new(report, backups)
    local store = { unit = nil, requests = nil, roster = nil, ambiguous = {}, found = {}, save_failed = false, generation = 0 }
    local warned = {} -- offline_id -> true: ambiguity already logged for it

    local function save()
        local r, unit = store.roster, store.unit
        if unit == nil or not roster.writable(r) then return end
        local ok, err = jsonfile.write(roster.path(unit), roster.serialize(r),
            function(back) return roster.matches(r, back) end)
        store.save_failed = not ok
        if ok then
            r.warnings = {} -- the file now holds a clean rewrite (the warnings stay in the log)
        else
            report("roster write", err)
        end
    end

    local function member_name(id)
        local m = roster.find(store.roster, id)
        return m and m.name or roster.UNKNOWN_NAME
    end

    function store.update(unit, party, requests)
        local forced = false
        if unit ~= store.unit or requests ~= store.requests then
            local r = nil
            if unit ~= nil then r = roster.resolve(jsonfile.read(roster.path(unit), { strict = true })) end
            -- Assigned together after the read, so a throw above leaves the previous (consistent) state.
            store.unit, store.requests, store.roster = unit, requests, r
            store.ambiguous, store.found, warned = {}, {}, {}
            store.save_failed = false
            store.generation = store.generation + 1
            forced = true
            if r then
                local label = slot.label(unit)
                log.error(string.format("[Retinue] %s: %s", label, roster.state_text(r)))
                for _, w in ipairs(r.warnings) do
                    log.error(string.format("[Retinue] %s roster.json: %s", label, w))
                end
            end
            backups.activate(unit, r)
        end
        local r = store.roster
        if not r then return end
        local views = party.views()
        store.found, store.ambiguous = roster.match(r, views)
        for id in pairs(store.ambiguous) do
            if not warned[id] then
                warned[id] = true
                log.error(string.format("[Retinue] %s: two party pawns share its Offline ID; excluded", member_name(id)))
            end
        end
        for id in pairs(warned) do
            if not store.ambiguous[id] then warned[id] = nil end
        end
        if forced or party.changed() then
            if roster.refresh_cache(r, views) then save() end
        end
    end

    function store:adopt(view)
        if self.unit == nil then return nil, "no_slot" end
        local m, err = roster.adopt(self.roster, view)
        if not m then return nil, err end
        save()
        -- The first backup; an orphan file of a re-adopted pawn is overwritten. Never fails the adopt.
        local okb, errb = pcall(backups.capture, self.unit, m, view, { force = true })
        if not okb then report("backup", errb) end
        log.error(string.format("[Retinue] %s: adopted %s (%s)", slot.label(self.unit), m.name, m.offline_id))
        return true
    end

    function store:release(offline_id)
        if self.unit == nil then return nil, "no_slot" end
        local m, err = roster.release(self.roster, offline_id)
        if not m then return nil, err end
        save()
        -- An orphan backup is ignored, so a failed removal leaves the release done.
        local okd, how, derr = pcall(backups.remove, self.unit, m.offline_id)
        if not okd then how, derr = nil, how end
        local result = how or "left in place"
        if not how then report("backup delete", derr) end
        log.error(string.format("[Retinue] %s: released %s (backup %s)", slot.label(self.unit), m.name, result))
        return true
    end

    -- A transition of Departure and Return: roster.mark_* on the active roster, saved on success; the roster
    -- function's results pass through unchanged.
    local function transition(fn)
        return function(self, ...)
            if self.roster == nil then return nil, "no_slot" end
            local a, b = fn(self.roster, ...)
            if a == nil then return nil, b end
            save()
            return a, b
        end
    end
    store.mark_away = transition(roster.mark_away)
    store.mark_returning = transition(roster.mark_returning)
    store.mark_present = transition(roster.mark_present)

    return store
end

return M
