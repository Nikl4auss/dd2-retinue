-- hooks.install under a stub `sdk` global: all-or-nothing, CALL_ORIGINAL on error, post passes retval,
-- and the u32 conversions.
local hooked = {}
local LEVELUP = "checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)"
local JOBPOINT = "addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)"
local DISP = "dispLevelUpUI(app.CharacterID, System.Int32, System.Int32)"
local RANKUP = "reqJobRankUp(app.CharacterID, app.Character.JobEnum, System.Int32, System.Int32)"
local have = {
    ["app.ExpDispenser"] = { [LEVELUP] = "M1", [DISP] = "M3" },
    ["app.GuiManager"] = { [RANKUP] = "M4" },
}
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
    assert(missing[1] == "app.ExpDispenser." .. JOBPOINT)
end

-- missing type: also unavailable
do
    local saved = have["app.ExpDispenser"]
    have["app.ExpDispenser"] = nil
    local ok, missing = hooks.install(entries, report)
    assert(ok == false and #hooked == 0 and #missing == 3)
    have["app.ExpDispenser"] = saved
end

-- only reqJobRankUp missing (with addJobPoint present): nothing installed, the notice names its type
do
    have["app.ExpDispenser"][JOBPOINT] = "M2"
    local saved = have["app.GuiManager"]
    have["app.GuiManager"] = nil
    local ok, missing = hooks.install(entries, report)
    assert(ok == false and #hooked == 0 and #missing == 1)
    assert(missing[1] == "app.GuiManager." .. RANKUP)
    have["app.GuiManager"] = saved
end

-- all present: all four hooked; a throwing pre still calls the original, logs, and the post passes retval
do
    local ok, missing = hooks.install(entries, report)
    assert(ok == true and #missing == 0)
    assert(#hooked == 4 and hooked[1].m == "M1" and hooked[2].m == "M2" and hooked[3].m == "M3" and hooked[4].m == "M4")
    assert(hooked[1].pre({}) == "CO")
    assert(#logs == 1 and logs[1]:find("pre checkLevelUp", 1, true))
    assert(hooked[1].post("RV") == "RV")
end

-- sdk.hook throwing mid-install: reported, install fails with that method, the caller stays unavailable
do
    local real_hook, n = sdk.hook, 0
    sdk.hook = function(m, pre, post)
        n = n + 1
        if n == 2 then error("hook refused") end
    end
    local before = #logs
    local ok, missing = hooks.install(entries, report)
    sdk.hook = real_hook
    assert(ok == false and #missing == 1)
    assert(missing[1] == "app.ExpDispenser.addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)")
    assert(#logs == before + 1 and logs[#logs]:find("install addJobPoint", 1, true))
end

-- SPECS pins roles and ID positions (instance method reqJobRankUp has the ID at args[3])
do
    local want = { { "checkLevelUp", "core", 2 }, { "addJobPoint", "core", 2 }, { "dispLevelUpUI", "swap", 2 },
                   { "reqJobRankUp", "swap", 3 } }
    assert(#hooks.SPECS == #want)
    for i, w in ipairs(want) do
        local s = hooks.SPECS[i]
        assert(s.key == w[1] and s.role == w[2] and s.id_arg == w[3], "SPECS[" .. i .. "]")
    end
end

-- u32 domain: a negative int32 view of the main pawn's ID maps to the same integer
do
    assert(hooks.arg_u32(-2011938949) == 2283028347)
    assert(hooks.to_u32(-2011938949) == 2283028347)
    assert(math.type(hooks.to_u32(2283028347.0)) == "integer")
end
