-- hooks.install under a stub `sdk` global: all-or-nothing, CALL_ORIGINAL on error, post passes retval,
-- and the u32 conversions.
local hooked = {}
local have = { ["app.ExpDispenser"] = {
    ["checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)"] = "M1",
} }
sdk = {
    PreHookResult = { CALL_ORIGINAL = "CO" },
    find_type_definition = function(t)
        local m = have[t]
        if not m then return nil end
        return { get_method = function(_, s) return m[s] end, get_methods = function() return {} end }
    end,
    hook = function(m, pre, post) hooked[#hooked + 1] = { m = m, pre = pre, post = post } end,
    to_int64 = function(a) return a end,
    to_ptr = function(v) return v end,
}

local hooks = require("Retinue.hooks")
local logs = {}
local function report(w, e) logs[#logs + 1] = w .. ": " .. tostring(e) end
local entries = {}
for i, s in ipairs(hooks.SPECS) do
    entries[i] = { key = s.key, type = s.type, sig = s.sig, pre = function() error("boom") end }
end

-- one method missing: nothing installed, missing listed as "<type>.<sig>"
do
    local ok, missing = hooks.install(entries, report)
    assert(ok == false)
    assert(#hooked == 0)
    assert(#missing == 1)
    assert(missing[1] == "app.ExpDispenser.addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)")
end

-- missing type: also unavailable
do
    local saved = have["app.ExpDispenser"]
    have["app.ExpDispenser"] = nil
    local ok, missing = hooks.install(entries, report)
    assert(ok == false and #hooked == 0 and #missing == 2)
    have["app.ExpDispenser"] = saved
end

-- all present: both hooked; a throwing pre still calls the original, logs, and the post passes retval
do
    have["app.ExpDispenser"]["addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)"] = "M2"
    local ok, missing = hooks.install(entries, report)
    assert(ok == true and #missing == 0)
    assert(#hooked == 2 and hooked[1].m == "M1" and hooked[2].m == "M2")
    assert(hooked[1].pre({}) == "CO")
    assert(#logs == 1 and logs[1]:find("pre checkLevelUp", 1, true))
    assert(hooked[1].post("RV") == "RV")
end

-- u32 domain: a negative int32 view of the main pawn's ID maps to the same integer
do
    assert(hooks.arg_u32(-2011938949) == 2283028347)
    assert(hooks.to_u32(-2011938949) == 2283028347)
    assert(math.type(hooks.to_u32(2283028347.0)) == "integer")
end
