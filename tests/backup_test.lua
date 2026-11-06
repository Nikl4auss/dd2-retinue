local backup = require("Retinue.backup")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

local function params()
    local p = {}
    for i, k in ipairs(backup.INCREASE_KEYS) do p[k] = i * 10 end
    return p
end

local NIL = {} -- in good(extra): remove the field

local function good(extra)
    local b = {
        version = 1, offline_id = A, name = "Ana",
        level = 27, exp = 1000, increase_params = params(), extra_status_boost = 3, discipline = 500,
        culmative_exp = { 10, 20, 30 },
        current_job = 5, qualified_job_bits = 63, changed_job_bits = 1,
        item_ids = { 7, 8 }, skills = { { "Job01_BlinkStrike", "None" }, { 1, 2 } },
    }
    for k, v in pairs(extra or {}) do
        if v == NIL then b[k] = nil else b[k] = v end
    end
    return b
end

-- constants and path
assert(backup.VERSION == 1 and backup.POLL_SECONDS == 10)
assert(backup.EQUAL == "equal" and backup.LOWER == "lower" and backup.HIGHER == "higher")
assert(backup.NONE == "none" and backup.WRITE == "write" and backup.LOWERED == "lowered")
assert(#backup.INCREASE_KEYS == 8 and #backup.RECORDED_KEYS == 6)
assert(backup.path(0, A) == "Retinue/slots/1/backups/" .. A .. ".json")
assert(backup.path(2, B) == "Retinue/slots/3/backups/" .. B .. ".json")

-- invalid
do
    assert(backup.invalid(good()) == nil)
    assert(backup.invalid(good({ level = 27.0 })) == nil)
    assert(backup.invalid(good({ level = 1 })) == nil)
    assert(backup.invalid(good({ level = 0 })) == "level is missing or invalid")
    assert(backup.invalid(good({ level = 1.5 })) == "level is missing or invalid")
    assert(backup.invalid(good({ level = "27" })) == "level is missing or invalid")
    assert(backup.invalid(nil) ~= nil and backup.invalid("x") ~= nil)
    assert(backup.invalid(good({ offline_id = "nope" })) == "offline_id is missing or invalid")
    assert(backup.invalid(good({ offline_id = B:upper() })) == nil)
    assert(backup.invalid(good({ hire_time = "x" })) == nil)
    assert(backup.invalid(good({ hire_time = -1.5 })) == nil)
    -- recorded fields are not checked
    local b = good()
    for _, k in ipairs(backup.RECORDED_KEYS) do b[k] = nil end
    assert(backup.invalid(b) == nil)
    assert(backup.invalid(good({ item_ids = "junk", current_job = "x" })) == nil)
    -- every restored field, absent
    for _, k in ipairs({ "offline_id", "level", "exp", "increase_params", "extra_status_boost", "discipline", "culmative_exp" }) do
        local c = good()
        c[k] = nil
        assert(backup.invalid(c) ~= nil, k)
    end
    for _, k in ipairs(backup.INCREASE_KEYS) do
        local c = good()
        c.increase_params[k] = nil
        assert(backup.invalid(c) == "increase_params." .. k .. " is missing or invalid", k)
        c.increase_params[k] = 1.5
        assert(backup.invalid(c) ~= nil, k)
    end
    assert(backup.invalid(good({ culmative_exp = {} })) ~= nil)
    assert(backup.invalid(good({ culmative_exp = { 1, "x" } })) ~= nil)
    assert(backup.invalid(good({ culmative_exp = { 1, nil, 3 } })) ~= nil)
    assert(backup.invalid(good({ culmative_exp = { [2] = 5 } })) ~= nil)
    assert(backup.invalid(good({ culmative_exp = { 1.0, 2.0 } })) == nil)
end

-- resolve
do
    local function problem(status, data, id)
        local b, p = backup.resolve(status, data, id or A)
        assert(b == nil, "expected a problem")
        return p
    end
    assert(problem("missing") == "missing")
    assert(problem("unparseable") == "damaged: not valid JSON")
    assert(problem("unreadable") == "damaged: cannot be read")
    assert(problem("weird") == "damaged: cannot be read")
    assert(problem("ok", "text") == "damaged: not an object")
    assert(problem("ok", nil) == "damaged: not an object")
    assert(problem("ok", good({ version = NIL })) == "damaged: version is missing or invalid")
    assert(problem("ok", good({ version = 0 })) == "damaged: version is missing or invalid")
    assert(problem("ok", good({ version = 1.5 })) == "damaged: version is missing or invalid")
    assert(problem("ok", good({ version = "1" })) == "damaged: version is missing or invalid")
    assert(problem("ok", good({ version = 2 })) == "newer version 2")
    assert(problem("ok", good({ version = 7, level = NIL })) == "newer version 7")
    assert(problem("ok", good({ level = NIL })) == "damaged: level is missing or invalid")
    assert(problem("ok", good({ level = 0 })) == "damaged: level is missing or invalid")
    for _, k in ipairs({ "exp", "increase_params", "extra_status_boost", "discipline", "culmative_exp" }) do
        local c = good()
        c[k] = nil
        assert(problem("ok", c) == "damaged: " .. k .. " is missing or invalid", k)
    end
    assert(problem("ok", good({ offline_id = NIL })) == "damaged: offline_id is missing or invalid")
    assert(problem("ok", good({ offline_id = B })) == "damaged: belongs to another pawn")
    -- success returns data itself
    local data = good()
    assert(backup.resolve("ok", data, A) == data)
    local b, p = backup.resolve("ok", data, A)
    assert(b == data and p == nil)
    -- case-insensitive id match; recorded fields absent
    local d2 = good({ offline_id = B:upper(), item_ids = NIL, skills = NIL, current_job = NIL })
    assert(backup.resolve("ok", d2, B) == d2)
    local d3 = good({ offline_id = B })
    assert(backup.resolve("ok", d3, B:upper()) == d3)
    assert(backup.resolve("ok", good({ version = 1.0 }), A) ~= nil)
end

-- same
do
    assert(backup.same(good(), good()))
    assert(backup.same(nil, nil))
    assert(not backup.same(good(), good({ level = 28 })))
    assert(not backup.same(good(), good({ name = "Bo" })))
    local p = params()
    p.stamina = 99
    assert(not backup.same(good(), good({ increase_params = p })))
    assert(not backup.same(good(), good({ culmative_exp = { 10, 20, 31 } })))
    assert(not backup.same(good(), good({ skills = { { "Job01_BlinkStrike", "None" }, { 1, 3 } } })))
    assert(not backup.same(good(), good({ item_ids = { 7, 8, 9 } })))
    assert(not backup.same(good(), good({ culmative_exp = { 10, 20 } })))
    -- nil vs {} at top and nested
    assert(backup.same(good({ item_ids = {} }), good({ item_ids = NIL })))
    assert(backup.same(good({ item_ids = NIL }), good({ item_ids = {} })))
    assert(backup.same({ skills = { {}, {} } }, { skills = {} }))
    assert(backup.same({ skills = { {}, { "a" } } }, { skills = { [2] = { "a" } } }))
    assert(backup.same({ a = { b = {} } }, { a = {} }))
    assert(not backup.same({ a = { b = {} } }, {}))
    assert(backup.same({ a = {} }, { a = nil }))
    assert(not backup.same(good({ item_ids = { 1 } }), good({ item_ids = NIL })))
    assert(not backup.same(nil, { 1 }))
    assert(backup.same(nil, {}))
    -- 1 vs 1.0
    assert(backup.same(good({ level = 1 }), good({ level = 1.0 })))
    assert(backup.same({ 1, 2 }, { 1.0, 2.0 }))
    assert(not backup.same(1, 2))
    -- different types
    assert(not backup.same(1, "1"))
    assert(not backup.same({ 1 }, 1))
    assert(not backup.same("a", { "a" }))
    assert(not backup.same(0, nil))
    -- a list of different length
    assert(not backup.same({ 1, 2, 3 }, { 1, 2 }))
    assert(not backup.same({ 1, 2 }, { 1, 2, 3 }))
    assert(not backup.same({ "a" }, {}))
end

-- carry_recorded
do
    local last = good()
    local fresh = good({ current_job = NIL, item_ids = NIL, skills = NIL })
    assert(backup.carry_recorded(fresh, last) == fresh)
    assert(fresh.current_job == 5 and fresh.item_ids == last.item_ids and fresh.skills == last.skills)
    -- a real value is left alone
    local f2 = good({ current_job = 9, qualified_job_bits = NIL })
    backup.carry_recorded(f2, last)
    assert(f2.current_job == 9 and f2.qualified_job_bits == 63)
    -- an empty item_ids is not replaced
    local f3 = good({ item_ids = {} })
    backup.carry_recorded(f3, last)
    assert(next(f3.item_ids) == nil)
    -- a nil last changes nothing
    local f4 = good({ current_job = NIL })
    assert(backup.carry_recorded(f4, nil) == f4 and f4.current_job == nil)
    -- hire_time is carried when a read failed
    local f6 = good({ hire_time = NIL })
    backup.carry_recorded(f6, good({ hire_time = 37991999 }))
    assert(f6.hire_time == 37991999)
    local f7 = good({ hire_time = 5 })
    backup.carry_recorded(f7, good({ hire_time = 37991999 }))
    assert(f7.hire_time == 5)
    -- restored keys are never carried
    local f5 = good({ level = NIL })
    backup.carry_recorded(f5, last)
    assert(f5.level == nil)
end

-- guard
assert(backup.guard(10, 10) == backup.EQUAL)
assert(backup.guard(9, 10) == backup.LOWER)
assert(backup.guard(11, 10) == backup.HIGHER)
assert(backup.guard(10.0, 10) == backup.EQUAL)

-- decide
do
    local last = good()
    assert(backup.decide(nil, good()) == backup.WRITE)
    assert(backup.decide(last, good()) == backup.NONE)
    assert(backup.decide(last, good({ level = 28 })) == backup.WRITE)
    assert(backup.decide(last, good({ level = 26 })) == backup.LOWERED)
    assert(backup.decide(last, good({ exp = 5 })) == backup.WRITE) -- exp lower at the same level
    assert(backup.decide(last, good({ level = 26, exp = 5000 })) == backup.LOWERED)
    assert(backup.decide(good({ item_ids = {} }), good({ item_ids = NIL })) == backup.NONE)
    -- hire_time alone: an older backup gains it, a re-hire changes it
    assert(backup.decide(good({ hire_time = 100 }), good({ hire_time = 200 })) == backup.WRITE)
    assert(backup.decide(good(), good({ hire_time = 200 })) == backup.WRITE)
    assert(backup.decide(good({ hire_time = 100 }), good({ hire_time = 100 })) == backup.NONE)
    assert(backup.decide(good({ hire_time = 100 }), good({ hire_time = 100.0 })) == backup.NONE)
end

-- lowered_text
assert(backup.lowered_text("Ana", 20.0, 27.0) == "Ana: save has Lv 20, backup had Lv 27 -> backup lowered, save wins")
assert(backup.lowered_text("Ana", 20, 27) == "Ana: save has Lv 20, backup had Lv 27 -> backup lowered, save wins")

-- poll
do
    local poll = backup.new_poll(10)
    assert(poll:tick(100, true, 1) == false) -- first in-world tick arms
    assert(poll:tick(105, true, 1) == false)
    assert(poll:tick(110, true, 1) == true)
    assert(poll:tick(111, true, 1) == false) -- until the next interval
    assert(poll:tick(119.9, true, 1) == false)
    assert(poll:tick(120, true, 1) == true)
    -- leaving the world and coming back re-arms
    assert(poll:tick(125, false, 1) == false)
    assert(poll:tick(200, false, 1) == false)
    assert(poll:tick(205, true, 1) == false)
    assert(poll:tick(214, true, 1) == false)
    assert(poll:tick(215, true, 1) == true)
    -- a generation change re-arms
    assert(poll:tick(224, true, 1) == false)
    assert(poll:tick(226, true, 2) == false)
    assert(poll:tick(235, true, 2) == false)
    assert(poll:tick(236, true, 2) == true)
    -- not in the world on the very first call
    local p2 = backup.new_poll(10)
    assert(p2:tick(0, false, 1) == false)
    assert(p2:tick(1000, true, 1) == false)
    assert(p2:tick(1010, true, 1) == true)
end

-- restored_mismatch
do
    local b = good()
    assert(backup.restored_mismatch(b, good()) == nil)
    assert(backup.restored_mismatch(b, good({ level = 27.0, exp = 1000.0 })) == nil) -- 1 vs 1.0
    assert(backup.restored_mismatch(b, good({ level = 28 })) == "level")
    assert(backup.restored_mismatch(b, good({ exp = 999 })) == "exp")
    assert(backup.restored_mismatch(b, good({ extra_status_boost = 0 })) == "extra_status_boost")
    assert(backup.restored_mismatch(b, good({ discipline = 501 })) == "discipline")
    assert(backup.restored_mismatch(b, good({ level = NIL })) == "level")
    for _, key in ipairs(backup.INCREASE_KEYS) do
        local back = good()
        back.increase_params[key] = back.increase_params[key] + 1
        assert(backup.restored_mismatch(b, back) == "increase_params." .. key, key)
    end
    local back = good()
    back.increase_params.attack = back.increase_params.attack + 0.0 -- 30.0 equals 30
    assert(backup.restored_mismatch(b, back) == nil)
    assert(backup.restored_mismatch(b, good({ increase_params = NIL })) == "increase_params.hit_point")
    assert(backup.restored_mismatch(b, good({ culmative_exp = { 10, 20, 31 } })) == "culmative_exp[3]")
    assert(backup.restored_mismatch(b, good({ culmative_exp = { 10.0, 20.0, 30.0 } })) == nil)
    assert(backup.restored_mismatch(b, good({ culmative_exp = { 10, 20 } })) == "culmative_exp length")
    assert(backup.restored_mismatch(b, good({ culmative_exp = { 10, 20, 30, 40 } })) == "culmative_exp length")
    assert(backup.restored_mismatch(b, good({ culmative_exp = NIL })) == "culmative_exp length")
    -- the first difference in the documented order
    assert(backup.restored_mismatch(b, good({ level = 1, exp = 1 })) == "level")
    -- recorded fields and the name are not compared
    assert(backup.restored_mismatch(b, good({ current_job = 9, name = "Bo", item_ids = { 1 } })) == nil)
end

-- recorded_mismatch
do
    local b = good()
    local function eq(got, want)
        assert(#got == #want, table.concat(got, ","))
        for i, k in ipairs(want) do assert(got[i] == k, k) end
    end
    eq(backup.recorded_mismatch(b, good()), {})
    eq(backup.recorded_mismatch(b, good({ current_job = 6 })), { "current_job" })
    eq(backup.recorded_mismatch(b, good({ qualified_job_bits = 1 })), { "qualified_job_bits" })
    eq(backup.recorded_mismatch(b, good({ changed_job_bits = 0 })), { "changed_job_bits" })
    eq(backup.recorded_mismatch(b, good({ skills = { { "x" } } })), { "skills" })
    eq(backup.recorded_mismatch(b, good({ current_job = 6.0 })), { "current_job" })
    eq(backup.recorded_mismatch(b, good({ current_job = 5.0 })), {})
    -- several, in order
    eq(backup.recorded_mismatch(b, good({ skills = { { "x" } }, current_job = 6, changed_job_bits = 0 })),
        { "current_job", "changed_job_bits", "skills" })
    -- nil on either side is ignored
    eq(backup.recorded_mismatch(b, good({ current_job = NIL, skills = NIL })), {})
    eq(backup.recorded_mismatch(good({ current_job = NIL, qualified_job_bits = NIL }), good({ current_job = 1, qualified_job_bits = 2 })), {})
    -- item_ids are ignored
    eq(backup.recorded_mismatch(b, good({ item_ids = { 99 } })), {})
    eq(backup.recorded_mismatch(b, good({ item_ids = NIL })), {})
    -- hire_time is not compared
    eq(backup.recorded_mismatch(good({ hire_time = 1 }), good({ hire_time = 2 })), {})
end

print("backup_test ok")
