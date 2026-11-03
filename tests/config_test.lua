local config = require("Retinue.config")

local PREFIX = "[Retinue] config.json: "

local function check_prefixed(warnings)
    for _, w in ipairs(warnings) do assert(w:sub(1, #PREFIX) == PREFIX, w) end
end

assert(config.PATH == "Retinue/config.json")
assert(config.VERSION == 1)
assert(config.DEFAULTS.progression == true)
assert(config.TYPES.progression == "boolean")

-- missing: defaults, no warnings, no base
do
    local s, w, base = config.resolve("missing")
    assert(s.progression == true and #w == 0 and base == nil)
end

-- valid
do
    local data = { version = 1, progression = false }
    local s, w, base = config.resolve("ok", data)
    assert(s.progression == false and #w == 0 and base == data)
    s, w = config.resolve("ok", { version = 1, progression = true })
    assert(s.progression == true and #w == 0)
end

-- wrong type: default plus one warning naming the key
do
    local data = { version = 1, progression = "yes" }
    local s, w, base = config.resolve("ok", data)
    assert(s.progression == true and #w == 1 and base == data)
    assert(w[1]:find("progression", 1, true))
    check_prefixed(w)
end

-- missing key
do
    local s, w, base = config.resolve("ok", { version = 1 })
    assert(s.progression == true and #w == 1 and base ~= nil)
    assert(w[1]:find("progression", 1, true))
    check_prefixed(w)
end

-- unparseable
do
    local s, w, base = config.resolve("unparseable")
    assert(s.progression == true and #w == 1 and base == nil)
    check_prefixed(w)
end

-- non-object top level
for _, data in ipairs({ "x", 42, true, { 1, 2 } }) do
    local s, w, base = config.resolve("ok", data)
    assert(s.progression == true and #w == 1 and base == nil, tostring(data))
    check_prefixed(w)
end

-- an empty table is an (empty) object: missing key warning, base kept
do
    local data = {}
    local s, w, base = config.resolve("ok", data)
    assert(s.progression == true and #w == 1 and base == data)
end

-- higher version: read for known keys, never lowered on merge
do
    local data = { version = 3, progression = false }
    local s, w, base = config.resolve("ok", data)
    assert(s.progression == false and #w == 0)
    local out = config.merge(base, { progression = true })
    assert(out.version == 3 and out.progression == true)
end

-- unknown keys kept
do
    local base = { version = 1, progression = "yes", extra = 1 }
    local out = config.merge(base, { progression = false })
    assert(out.version == 1 and out.progression == false and out.extra == 1)
    local n = 0
    for _ in pairs(out) do n = n + 1 end
    assert(n == 3)
end

-- nil base
do
    local out = config.merge(nil, { progression = true })
    assert(out.version == 1 and out.progression == true)
    local n = 0
    for _ in pairs(out) do n = n + 1 end
    assert(n == 2)
end

-- merge does not mutate base and returns a new table
do
    local base = { version = 2, progression = true, extra = "x" }
    local out = config.merge(base, { progression = false })
    assert(out ~= base)
    assert(base.version == 2 and base.progression == true and base.extra == "x")
end

-- version that is not an integer above 1 is written as 1
for _, v in ipairs({ 0, "2", 1.5, -4, 1, "x", true }) do
    local out = config.merge({ version = v }, { progression = true })
    assert(out.version == 1, tostring(v))
end
assert(config.merge({}, { progression = true }).version == 1)
-- an integral float above 1 counts as an integer
assert(config.merge({ version = 2.0 }, { progression = true }).version == 2)

print("config_test: ok")
