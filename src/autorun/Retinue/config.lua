-- config.json: reading and writing the saved settings. Pure: no REFramework globals, so it runs under plain
-- Lua in tests; Retinue.lua does the file I/O.
local M = {}

M.PATH = "Retinue/config.json" -- relative to reframework/data (the root for JSON and file access)
M.VERSION = 1
M.DEFAULTS = { progression = true }
M.TYPES = { progression = "boolean" }

local PREFIX = "[Retinue] config.json: "

-- Sorted so warnings come out in a stable order.
local function known_keys()
    local keys = {}
    for k in pairs(M.DEFAULTS) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

local function copy_defaults()
    local s = {}
    for k, v in pairs(M.DEFAULTS) do s[k] = v end
    return s
end

-- status: "missing" | "unparseable" | "ok"; data: the decoded value when status == "ok".
-- Returns settings, warnings, base:
--   settings: one entry per known key (the file's value if it has the right type, else the default)
--   warnings: strings for the log
--   base: the decoded object to keep unknown keys from on rewrite, or nil
function M.resolve(status, data)
    if status == "missing" then
        return copy_defaults(), {}, nil
    end
    if status ~= "ok" then
        return copy_defaults(), {
            PREFIX .. "not valid JSON; using defaults. The file is left as is until a setting is changed.",
        }, nil
    end
    if type(data) ~= "table" or #data > 0 then
        return copy_defaults(), {
            PREFIX .. "top level is not an object; using defaults. The file is left as is until a setting is changed.",
        }, nil
    end
    local settings, warnings = {}, {}
    for _, key in ipairs(known_keys()) do
        local v = data[key]
        if type(v) == M.TYPES[key] then
            settings[key] = v
        else
            settings[key] = M.DEFAULTS[key]
            warnings[#warnings + 1] = string.format("%s%s is missing or not a %s; using %s",
                PREFIX, key, M.TYPES[key], tostring(M.DEFAULTS[key]))
        end
    end
    return settings, warnings, data
end

-- A NEW table to write: a shallow copy of base (unknown keys kept; nil base -> {}) with every known key from
-- settings, and version = base.version if that is an integer above M.VERSION, else M.VERSION.
-- REFramework's json cannot round-trip some unknown keys: a JSON null decodes to nil and is dropped, and an
-- empty {} or [] is written back as null.
function M.merge(base, settings)
    local out = {}
    if base then
        for k, v in pairs(base) do out[k] = v end
    end
    for k in pairs(M.DEFAULTS) do out[k] = settings[k] end
    local v = base and base.version
    local iv = type(v) == "number" and math.tointeger(v) or nil
    if iv and iv > M.VERSION then
        out.version = iv
    else
        out.version = M.VERSION
    end
    return out
end

return M
