-- REFramework glue: the backups of the active save slot (uses log; file I/O is game/jsonfile, the pawn read is
-- game/pawn_state). The decisions (the file's shape, validation, "did anything change", the level guard, the poll
-- timing) live in Retinue/backup.lua.

local backup = require("Retinue.backup")
local jsonfile = require("Retinue.game.jsonfile")
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

-- Returns backups (read_pawn(view) -> snapshot | nil, why is game/pawn_state's read):
--   backups.last     { [offline_id] = backup }   this activation's view of each member's file (nil: none usable)
--   backups.problem  { [offline_id] = string }   backup.resolve's problem, or "write failed"; cleared on a good write
--   backups.activate(unit, r)   -- on every roster (re)load: clears both, then reads each member's file
--   backups.capture(unit, m, view, opts)  -- reads the pawn and writes its file when something changed (opts.force:
--                                            always write, never lowered)
--   backups.poll(retinue, in_world, now)  -- every frame: a pass over the present members about every POLL_SECONDS
--   backups.remove(unit, id) -> "removed" | "emptied" | nil, err
--   backups.level(id) -> the backup's level | nil;  backups.note(id) -> the problem text | nil
-- Away and returning members are never captured here: that is the freeze. Lines go to log.error with the [Retinue]
-- prefix; repeatable failures go through report.
function M.new(report, read_pawn)
    local backups = { last = {}, problem = {} }
    local poll = backup.new_poll(backup.POLL_SECONDS)

    function backups.activate(unit, r)
        backups.last, backups.problem = {}, {}
        if unit == nil or r == nil or r.mode == roster.LOCKED then return end
        local label = slot.label(unit)
        for _, m in ipairs(r.members) do
            local id = m.offline_id
            local ok, b, problem = pcall(function()
                local status, data = jsonfile.read(backup.path(unit, id), { strict = true })
                return backup.resolve(status, data, id)
            end)
            if not ok then
                report("backup read", m.name .. ": " .. tostring(b))
                b, problem = nil, "damaged: cannot be read"
            end
            if b then
                backups.last[id] = b
            else
                backups.problem[id] = problem
                log.error(string.format("[Retinue] %s backup of %s: %s", label, m.name, problem))
            end
        end
    end

    function backups.capture(unit, m, view, opts)
        local id = m.offline_id
        local ok, fresh, why = pcall(read_pawn, view)
        if not ok then
            report("backup read", m.name .. ": " .. tostring(fresh))
            return
        end
        if not fresh then
            report("backup read", m.name .. ": " .. tostring(why))
            return
        end
        local last = backups.last[id]
        fresh.name = m.name
        backup.carry_recorded(fresh, last)
        local lowered = false
        if not (opts and opts.force) then
            local decision = backup.decide(last, fresh)
            if decision == backup.NONE then return end
            lowered = decision == backup.LOWERED
        end
        local written, err = jsonfile.write(backup.path(unit, id), fresh,
            function(back) return backup.same(fresh, back) end)
        if not written then
            backups.problem[id] = "write failed"
            report("backup write", m.name .. ": " .. tostring(err))
            return
        end
        backups.last[id] = fresh
        backups.problem[id] = nil
        if lowered then log.error("[Retinue] " .. backup.lowered_text(m.name, fresh.level, last.level)) end
    end

    function backups.poll(retinue, in_world, now)
        if not poll:tick(now, in_world, retinue.generation) then return end
        local unit, r = retinue.unit, retinue.roster
        if unit == nil or not roster.writable(r) then return end
        for _, m in ipairs(r.members) do
            local view = m.status == roster.PRESENT and retinue.found[m.offline_id] or nil
            if view then
                local ok, err = pcall(backups.capture, unit, m, view)
                if not ok then report("backup", err) end
            end
        end
    end

    function backups.remove(unit, id)
        backups.last[id], backups.problem[id] = nil, nil
        return jsonfile.delete(backup.path(unit, id))
    end

    function backups.level(id)
        local b = backups.last[id]
        return b and b.level
    end

    function backups.note(id)
        return backups.problem[id]
    end

    return backups
end

return M
