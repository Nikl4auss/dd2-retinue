-- REFramework glue: reads and writes reframework/data/Retinue/config.json (uses log; file I/O is game/jsonfile).
-- The decisions (defaults, warnings, merge) live in Retinue/config.lua.

local config = require("Retinue.config")
local jsonfile = require("Retinue.game.jsonfile")

local M = {}

-- config.json is read once, here, and written only when the checkbox changes (never at load, never by
-- the config-save callback). Returns status, data for config.resolve; an empty file counts as missing (no
-- warning), and without fs.read an unparseable file reads as missing (see jsonfile.read).
local function read_config()
    return jsonfile.read(config.PATH)
end

-- report: errlog reporter. Reads config.json once, logs the warnings with log.error.
-- Returns a store: { settings = <config.resolve settings>, warnings = {...}, save_failed = false,
--                    save = function(self, value) ... end }
function M.open(report)
    local settings, warnings, base = config.resolve(read_config())
    -- Logged with log.error, not log.warn: another mod can raise the global log level to "error" (NickCore does),
    -- which drops warnings. They are also shown in the menu, which no other mod can hide.
    for _, w in ipairs(warnings) do log.error(w) end

    local store = {
        settings = settings,
        warnings = warnings,
        -- Set when the last config write failed; cleared by the next successful one.
        save_failed = false,
    }

    function store:save(value)
        local out = config.merge(base, { progression = value })
        local ok, err = jsonfile.write(config.PATH, out, function(back) return back.progression == value end)
        if ok then
            base = out
            self.save_failed = false
            self.warnings = {} -- the file now holds a clean rewrite
        else
            self.save_failed = true
            report("config write", err)
        end
    end

    return store
end

return M
