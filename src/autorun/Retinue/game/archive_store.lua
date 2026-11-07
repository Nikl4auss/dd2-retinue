-- REFramework glue: archives the roster of a slot that starts a new playthrough (uses fs and log). The decisions
-- (what to copy, where, the order of copy and emptying, the log texts) live in Retinue/archive.lua; the trigger is
-- the session's take_archive (Retinue/slot.lua).

local archive = require("Retinue.archive")

local M = {}

-- The fs operations archive.run expects, each under pcall and tolerant of a missing fs (the global may be absent).
local files = {
    list = function(filter)
        if not (fs and fs.glob) then return {} end
        local ok, res = pcall(fs.glob, filter)
        if ok and type(res) == "table" then return res end
        return {}
    end,
    read = function(path)
        if not (fs and fs.read) then return nil end
        local ok, text = pcall(fs.read, path)
        if ok and type(text) == "string" then return text end
        return nil
    end,
    write = function(path, text)
        if not (fs and fs.write) then return end
        pcall(fs.write, path, text)
    end,
}

-- run(session, report): call every frame, from the update loop (never inside a hook), after the slot tracker and
-- before the roster store. When the session has an archive pending (session:take_archive() -> unit) the unit's
-- roster and backups are archived once; the flag is taken once, so a failure is not retried. The result goes to
-- log.error with the [Retinue] prefix; a failure also goes through report("archive", why).
function M.run(session, report)
    local unit = session:take_archive()
    if unit == nil then return end
    local result = archive.run(unit, os.date("*t"), files)
    local text = archive.text(result, unit)
    if text then log.error("[Retinue] " .. text) end
    if result.status == "failed" then report("archive", result.why) end
end

return M
