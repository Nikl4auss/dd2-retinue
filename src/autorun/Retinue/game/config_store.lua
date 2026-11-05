-- REFramework glue: reads and writes reframework/data/Retinue/config.json (uses fs, json and log).
-- The decisions (defaults, warnings, merge) live in Retinue/config.lua.

local config = require("Retinue.config")

local M = {}

-- config.json is read once, here, and written only when the checkbox changes (never at load, never by
-- the config-save callback). Returns status, data for config.resolve. fs.read returns "" for a missing and
-- for an empty file alike, so an empty file counts as missing (no warning).
local function read_config()
    if fs and fs.read then
        local ok, text = pcall(fs.read, config.PATH)
        if not ok or text == nil or text == "" then return "missing" end
        local okd, data = pcall(json.load_string, text)
        if not okd or data == nil then return "unparseable" end
        return "ok", data
    end
    -- Without fs.read, an unparseable file reads as missing (json.load_file returns nil for both).
    local ok, data = pcall(json.load_file, config.PATH)
    if not ok or data == nil then return "missing" end
    return "ok", data
end

-- json.dump_file returns true even when the file cannot be opened (read-only or locked), so read it back.
local function written(value)
    if not (fs and fs.read) then return true end
    local okr, text = pcall(fs.read, config.PATH)
    if not okr then return false end
    local okd, back = pcall(json.load_string, text)
    return okd and type(back) == "table" and back.progression == value
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
        local ok, res = pcall(json.dump_file, config.PATH, out)
        if ok and res ~= false and written(value) then
            base = out
            self.save_failed = false
            self.warnings = {} -- the file now holds a clean rewrite
        else
            self.save_failed = true
            local err = res
            if ok then
                if res == false then
                    err = "dump_file returned false"
                else
                    err = "file unchanged after write (read-only or locked?)"
                end
            end
            report("config write", err)
        end
    end

    return store
end

return M
