local roster = require("Retinue.roster")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
local C = "01234567-89ab-cdef-0123-456789abcdef"
local ZERO = "00000000-0000-0000-0000-000000000000"

local function has_warning(r, text)
    for _, w in ipairs(r.warnings) do
        if w == text then return true end
    end
    return false
end

local function n_ids(n)
    local out = {}
    for i = 1, n do out[i] = string.format("%08x-0000-0000-0000-000000000001", i) end
    return out
end

local function view(slot_n, offline_id, extra)
    local v = { slot = slot_n, character_id = 1601809365, owner = "CAPCOM", offline_id = offline_id, name = "Ana" }
    for k, x in pairs(extra or {}) do v[k] = x end
    return v
end

local function ok_roster(members)
    return { mode = roster.OK, members = members or {}, warnings = {} }
end

local function locked_with(status, data, reason)
    local r = roster.resolve(status, data)
    assert(r.mode == roster.LOCKED, tostring(reason))
    assert(r.reason == reason, tostring(r.reason))
    assert(#r.members == 0 and r.base == nil)
    return r
end

-- constants and path
assert(roster.CAP == 2 and roster.VERSION == 1)
assert(roster.path(0) == "Retinue/slots/1/roster.json")
assert(roster.path(2) == "Retinue/slots/3/roster.json")

-- canonical_id
assert(roster.canonical_id(A) == A)
assert(roster.canonical_id(B:upper()) == B)
assert(roster.canonical_id("AbCdEf01-2345-6789-aBcD-eF0123456789") == "abcdef01-2345-6789-abcd-ef0123456789")
assert(roster.canonical_id(ZERO) == nil)
assert(roster.canonical_id("11111111-2222-3333-4444-55555555555") == nil)
assert(roster.canonical_id("11111111-2222-3333-4444-5555555555555") == nil)
assert(roster.canonical_id("1111111122223333444455555555555") == nil)
assert(roster.canonical_id("1111111g-2222-3333-4444-555555555555") == nil)
assert(roster.canonical_id(" " .. A) == nil)
assert(roster.canonical_id(A .. "\n") == nil)
assert(roster.canonical_id(nil) == nil)
assert(roster.canonical_id(42) == nil)
assert(roster.canonical_id({}) == nil)

-- valid_character_id
assert(roster.valid_character_id(0) == 0)
assert(roster.valid_character_id(0xFFFFFFFF) == 0xFFFFFFFF)
assert(roster.valid_character_id(1601809365.0) == 1601809365 and math.type(roster.valid_character_id(1601809365.0)) == "integer")
assert(roster.valid_character_id(-1) == nil)
assert(roster.valid_character_id(2 ^ 32) == nil)
assert(roster.valid_character_id(1.5) == nil)
assert(roster.valid_character_id("1") == nil)
assert(roster.valid_character_id(nil) == nil)
assert(roster.valid_character_id(0 / 0) == nil)

-- adoptable
assert(roster.adoptable(view(1, A)) == A)
assert(roster.adoptable(view(2, B:upper())) == B)
assert(roster.adoptable(view(0, A)) == nil)
assert(roster.adoptable(view(3, A)) == nil)
assert(roster.adoptable(view(nil, A)) == nil)
assert(roster.adoptable(view(1, A, { owner = "Someone" })) == nil)
assert(roster.adoptable(view(1, A, { owner = false })) == nil)
assert(roster.adoptable(view(1, ZERO)) == nil)
assert(roster.adoptable(view(1, nil)) == nil)
assert(roster.adoptable(nil) == nil)

-- resolve: missing -> empty OK, no base
do
    local r = roster.resolve("missing")
    assert(r.mode == roster.OK and #r.members == 0 and r.base == nil and #r.warnings == 0 and r.reason == nil)
    assert(roster.writable(r))
end

-- resolve: unparseable / unreadable / other status -> LOCKED
locked_with("unparseable", nil, "not valid JSON")
locked_with("unreadable", nil, "cannot be read safely (fs.read unavailable)")
locked_with("weird", nil, "cannot be read")
assert(not roster.writable(roster.resolve("unparseable")))

-- resolve: top level
for _, data in ipairs({ "x", 42, true, { 1, 2 }, { { offline_id = A } } }) do
    locked_with("ok", data, "top level is not an object")
end
locked_with("ok", nil, "top level is not an object")

-- resolve: members nil -> empty OK (the json null caveat)
do
    local data = { version = 1 }
    local r = roster.resolve("ok", data)
    assert(r.mode == roster.OK and #r.members == 0 and #r.warnings == 0 and r.base == data)
    r = roster.resolve("ok", { version = 1, members = {} })
    assert(r.mode == roster.OK and #r.members == 0 and #r.warnings == 0)
end

-- resolve: members not an array
locked_with("ok", { version = 1, members = "x" }, "members is not an array")
locked_with("ok", { version = 1, members = 5 }, "members is not an array")
locked_with("ok", { version = 1, members = { a = {} } }, "members is not an array")
locked_with("ok", { version = 1, members = { [1] = { offline_id = A }, [3] = { offline_id = B } } }, "members is not an array")

-- resolve: structural member errors
locked_with("ok", { version = 1, members = { "x" } }, "member 1 is not an object")
locked_with("ok", { version = 1, members = { { offline_id = A }, 7 } }, "member 2 is not an object")
locked_with("ok", { version = 1, members = { {} } }, "member 1 has no valid offline_id")
locked_with("ok", { version = 1, members = { { offline_id = "nope" } } }, "member 1 has no valid offline_id")
locked_with("ok", { version = 1, members = { { offline_id = ZERO } } }, "member 1 has no valid offline_id")
locked_with("ok", { version = 1, members = { { offline_id = A }, { offline_id = 5 } } }, "member 2 has no valid offline_id")
locked_with("ok", { version = 1, members = { { offline_id = A }, { offline_id = A } } }, "duplicate offline_id " .. A)
locked_with("ok", { version = 1, members = { { offline_id = A }, { offline_id = A:upper() } } }, "duplicate offline_id " .. A)
-- the first structural error wins, and the cap is checked last
do
    local ids = n_ids(roster.CAP + 1)
    local members = {}
    for i, id in ipairs(ids) do members[i] = { offline_id = id } end
    locked_with("ok", { version = 1, members = members }, "more than " .. roster.CAP .. " members")
    members[#members + 1] = "bad"
    locked_with("ok", { version = 1, members = members }, "member " .. #members .. " is not an object")
end

-- resolve: a valid roster, full of fields
do
    local data = {
        version = 1,
        members = {
            { offline_id = A:upper(), name = "Ana", status = "present", character_id = 1601809365.0, extra = "keep" },
            { offline_id = B, name = "Bo", status = "returning", character_id = 7 },
        },
    }
    local r = roster.resolve("ok", data)
    assert(r.mode == roster.OK and #r.members == 2 and #r.warnings == 0 and r.base == data)
    local m1, m2 = r.members[1], r.members[2]
    assert(m1.offline_id == A and m1.name == "Ana" and m1.status == "present")
    assert(m1.character_id == 1601809365 and math.type(m1.character_id) == "integer" and m1.extra == "keep")
    assert(m2.offline_id == B and m2.status == "returning" and m2.character_id == 7)
    -- shallow copies: the input entries are untouched
    assert(m1 ~= data.members[1])
    assert(data.members[1].offline_id == A:upper())
end

-- resolve: soft corrections
do
    local r = roster.resolve("ok", { version = 1, members = { { offline_id = A } } })
    local m = r.members[1]
    assert(r.mode == roster.OK and m.name == roster.UNKNOWN_NAME and m.status == roster.AWAY and m.character_id == nil)
    assert(#r.warnings == 2)
    assert(r.warnings[1] == "member 1: name is missing or invalid; using (unknown)")
    assert(r.warnings[2] == "member 1: status is missing or invalid; using away")

    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "", status = "present" } } })
    assert(r.members[1].name == roster.UNKNOWN_NAME and #r.warnings == 1)
    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = 5, status = "present" } } })
    assert(r.members[1].name == roster.UNKNOWN_NAME and #r.warnings == 1)

    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "Ana", status = "present", character_id = -3 } } })
    assert(r.members[1].character_id == nil and #r.warnings == 1)
    assert(r.warnings[1] == "member 1: character_id is invalid; ignored")
    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "Ana", status = "present", character_id = "x" } } })
    assert(r.members[1].character_id == nil and #r.warnings == 1)

    -- absent character_id: no warning
    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "Ana", status = "present" } } })
    assert(#r.warnings == 0)

    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "Ana", status = "gone" } } })
    assert(r.members[1].status == roster.AWAY and #r.warnings == 1)

    -- warnings name the 1-based member index
    r = roster.resolve("ok", { version = 1, members = {
        { offline_id = A, name = "Ana", status = "present" },
        { offline_id = B, name = "Bo", status = "bogus" },
    } })
    assert(#r.warnings == 1 and r.warnings[1] == "member 2: status is missing or invalid; using away")
end

-- resolve: version
do
    local r = roster.resolve("ok", { members = {} })
    assert(r.mode == roster.OK and #r.warnings == 1 and r.warnings[1] == "version is missing or invalid; read as 1")
    for _, v in ipairs({ "1", 0, -1, 1.5, true }) do
        r = roster.resolve("ok", { version = v })
        assert(r.mode == roster.OK and has_warning(r, "version is missing or invalid; read as 1"), tostring(v))
    end
    r = roster.resolve("ok", { version = 1.0 })
    assert(r.mode == roster.OK and #r.warnings == 0)
end

-- resolve: read-only (newer version)
do
    local data = {
        version = 2,
        extra = true,
        members = {
            { offline_id = A, name = "Ana", status = "present" },
            { offline_id = B, name = "Bo", status = "away", future = 1 },
        },
    }
    local r = roster.resolve("ok", data)
    assert(r.mode == roster.READ_ONLY and r.reason == "version 2" and r.base == data)
    assert(#r.members == 2 and r.members[2].future == 1)
    assert(#r.warnings == 1 and r.warnings[1] == "written by a newer Retinue (version 2); read-only")
    assert(not roster.writable(r))
    assert(roster.resolve("ok", { version = 3.0, members = {} }).reason == "version 3")

    -- bad members are skipped, never LOCKED
    r = roster.resolve("ok", { version = 2, members = {
        "x", {}, { offline_id = A }, { offline_id = A }, { offline_id = ZERO }, { offline_id = B, name = "Bo", status = "away" },
    } })
    assert(r.mode == roster.READ_ONLY and #r.members == 2)
    assert(r.members[1].offline_id == A and r.members[2].offline_id == B)
    assert(has_warning(r, "member 1 skipped: not an object"))
    assert(has_warning(r, "member 2 skipped: no valid offline_id"))
    assert(has_warning(r, "member 4 skipped: duplicate offline_id " .. A))
    assert(has_warning(r, "member 5 skipped: no valid offline_id"))
    assert(has_warning(r, "member 3: name is missing or invalid; using (unknown)"))

    -- members past the cap are ignored
    local ids = n_ids(roster.CAP + 2)
    local members = {}
    for i, id in ipairs(ids) do members[i] = { offline_id = id, name = "N" .. i, status = "away" } end
    r = roster.resolve("ok", { version = 2, members = members })
    assert(r.mode == roster.READ_ONLY and #r.members == roster.CAP)
    assert(has_warning(r, "members past " .. roster.CAP .. " ignored"))
    assert(r.members[roster.CAP].offline_id == ids[roster.CAP])

    -- members that are not an array: no members, no lock
    r = roster.resolve("ok", { version = 2, members = "x" })
    assert(r.mode == roster.READ_ONLY and #r.members == 0)
    r = roster.resolve("ok", { version = 2, members = { a = 1 } })
    assert(r.mode == roster.READ_ONLY and #r.members == 0)
    r = roster.resolve("ok", { version = 2 })
    assert(r.mode == roster.READ_ONLY and #r.members == 0)

    -- a non-object top level is still locked
    locked_with("ok", "x", "top level is not an object")
end

-- serialize
do
    local data = {
        version = 1,
        top_extra = { 1, 2 },
        members = {
            { offline_id = A, name = "Ana", status = "present", character_id = 5, member_extra = "k" },
            { offline_id = B, name = "Bo", status = "away" },
        },
    }
    local r = roster.resolve("ok", data)
    local out = roster.serialize(r)
    assert(out ~= data and out.version == 1 and out.top_extra == data.top_extra)
    assert(#out.members == 2)
    assert(out.members[1].member_extra == "k" and out.members[1].character_id == 5)
    assert(out.members[2].character_id == nil and out.members[2].offline_id == B)
    -- no aliasing
    assert(out.members ~= r.members and out.members[1] ~= r.members[1] and out.members[2] ~= r.members[2])
    out.members[1].name = "changed"
    out.top_extra = nil
    assert(r.members[1].name == "Ana" and r.base.top_extra ~= nil)

    -- version is forced to the current one
    r = roster.resolve("ok", { members = {} })
    assert(roster.serialize(r).version == 1)

    -- no base -> fresh table; adopted member shows up; empty roster has an (empty) members table
    r = roster.resolve("missing")
    out = roster.serialize(r)
    assert(out.version == 1 and type(out.members) == "table" and #out.members == 0)
    roster.adopt(r, view(1, A))
    out = roster.serialize(r)
    assert(#out.members == 1 and out.members[1].offline_id == A and out.members[1].status == roster.PRESENT)
    assert(out.members[1] ~= r.members[1])
    assert(r.base == nil)

    -- a member's cached character_id that was removed is simply absent
    r = roster.resolve("ok", { version = 1, members = { { offline_id = A, name = "Ana", status = "away", character_id = -1 } } })
    assert(roster.serialize(r).members[1].character_id == nil)
end

-- matches
do
    local r = ok_roster({ { offline_id = A }, { offline_id = B } })
    assert(roster.matches(r, { members = { { offline_id = A }, { offline_id = B } } }))
    assert(roster.matches(r, { members = { { offline_id = A:upper() }, { offline_id = B } } }))
    assert(not roster.matches(r, { members = { { offline_id = B }, { offline_id = A } } })) -- order
    assert(not roster.matches(r, { members = { { offline_id = A } } })) -- count
    assert(not roster.matches(r, { members = { { offline_id = A }, { offline_id = B }, { offline_id = C } } }))
    assert(not roster.matches(r, { members = { { offline_id = A }, { offline_id = C } } }))
    assert(not roster.matches(r, { members = { { offline_id = A }, "x" } }))
    assert(not roster.matches(r, { members = "x" }))
    assert(not roster.matches(r, { members = { a = { offline_id = A }, b = { offline_id = B } } })) -- not a sequence
    assert(not roster.matches(r, {})) -- nil members is an empty list
    assert(not roster.matches(r, nil))
    assert(not roster.matches(r, "x"))
    -- nil members vs an empty roster
    local empty = ok_roster({})
    assert(roster.matches(empty, {}))
    assert(roster.matches(empty, { members = {} }))
    assert(not roster.matches(empty, { members = { { offline_id = A } } }))
end

-- matches: name, status and character_id are compared too
do
    local function mem(extra)
        local m = { offline_id = A, name = "Ana", status = "present", character_id = 5 }
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    local r = ok_roster({ mem() })
    assert(roster.matches(r, { members = { mem() } }))
    assert(roster.matches(r, { members = { mem({ character_id = 5.0 }) } }))
    assert(not roster.matches(r, { members = { mem({ name = "Anna" }) } }))
    assert(not roster.matches(r, { members = { mem({ name = false }) } }))
    assert(not roster.matches(r, { members = { mem({ status = "away" }) } }))
    assert(not roster.matches(r, { members = { mem({ status = false }) } }))
    assert(not roster.matches(r, { members = { mem({ character_id = 6 }) } }))
    assert(not roster.matches(r, { members = { mem({ character_id = false }) } }))
    -- a member without a cached character_id matches only a file without one
    local r2 = ok_roster({ mem({ character_id = false }) })
    r2.members[1].character_id = nil
    assert(roster.matches(r2, { members = { mem({ character_id = false }) } }))
    assert(not roster.matches(r2, { members = { mem() } }))
end

-- match
do
    local r = ok_roster({ { offline_id = A, status = "present" }, { offline_id = B, status = "away" } })
    local va, vb = view(1, A), view(2, B)
    local found, amb = roster.match(r, { view(0, nil), va, vb })
    assert(found[A] == va and found[B] == vb and next(amb) == nil)

    -- case-insensitive; views without a valid id ignored
    local vup = view(1, A:upper())
    found, amb = roster.match(r, { vup, view(2, "garbage"), view(0, ZERO) })
    assert(found[A] == vup and found[B] == nil and next(amb) == nil)

    -- ambiguous: two views share the id (any slots, including the main pawn)
    local v0 = view(0, B)
    found, amb = roster.match(r, { va, vb, v0 })
    assert(found[A] == va and found[B] == nil and amb[B] == true and amb[A] == nil)
    found, amb = roster.match(r, { va, view(2, A:upper()) })
    assert(found[A] == nil and amb[A] == true)

    -- non-members are not reported
    found, amb = roster.match(r, { view(1, C) })
    assert(next(found) == nil and next(amb) == nil)

    -- LOCKED / nil -> empty
    local locked_match = { mode = roster.LOCKED, members = { { offline_id = A, name = "Ana", status = "present", character_id = 5 } } }
    found, amb = roster.match(locked_match, { va })
    assert(next(found) == nil and next(amb) == nil)
    found, amb = roster.match(nil, { va })
    assert(next(found) == nil and next(amb) == nil)

    -- READ_ONLY matches
    local ro = { mode = roster.READ_ONLY, members = { { offline_id = A, status = "present" } } }
    found = roster.match(ro, { va })
    assert(found[A] == va)
end

-- find
do
    local m = { offline_id = A }
    local r = ok_roster({ m })
    assert(roster.find(r, A) == m)
    assert(roster.find(r, A:upper()) == m)
    assert(roster.find(r, B) == nil)
    assert(roster.find(r, "garbage") == nil)
    assert(roster.find(r, nil) == nil)
end

-- adopt: success
do
    local r = ok_roster()
    local m, err = roster.adopt(r, view(1, A:upper(), { name = "Ana", character_id = 1601809365.0 }))
    assert(m and err == nil)
    assert(#r.members == 1 and r.members[1] == m)
    assert(m.offline_id == A and m.name == "Ana" and m.status == roster.PRESENT)
    assert(m.character_id == 1601809365 and math.type(m.character_id) == "integer")

    -- name fallback and a bad character_id
    m = roster.adopt(r, view(2, B, { name = "", character_id = -1 }))
    assert(m.name == roster.UNKNOWN_NAME and m.character_id == nil and #r.members == 2)
    r = ok_roster()
    m = roster.adopt(r, view(1, A, { name = false }))
    assert(m.name == roster.UNKNOWN_NAME)
end

-- adopt: errors, in order of precedence
do
    local locked_r = { mode = roster.LOCKED, members = {}, warnings = {} }
    local ro_r = { mode = roster.READ_ONLY, members = {}, warnings = {} }
    local m, err = roster.adopt(locked_r, view(0, nil))
    assert(m == nil and err == "locked" and #locked_r.members == 0)
    m, err = roster.adopt(ro_r, view(0, nil))
    assert(m == nil and err == "read_only" and #ro_r.members == 0)

    local r = ok_roster()
    m, err = roster.adopt(r, view(0, A))
    assert(m == nil and err == "no_offline_id")
    m, err = roster.adopt(r, view(1, A, { owner = "Someone" }))
    assert(err == "no_offline_id")
    m, err = roster.adopt(r, view(1, ZERO))
    assert(err == "no_offline_id")
    assert(#r.members == 0)

    -- no_offline_id wins over already_adopted / full
    r = ok_roster({ { offline_id = A, status = "away" }, { offline_id = B, status = "away" } })
    assert(select(2, roster.adopt(r, view(0, A))) == "no_offline_id")

    -- already_adopted (any status, any case) wins over full
    assert(select(2, roster.adopt(r, view(1, A:upper()))) == "already_adopted")
    assert(#r.members == 2)

    -- full
    local ids = n_ids(roster.CAP)
    local members = {}
    for i, id in ipairs(ids) do members[i] = { offline_id = id, status = "present", name = "N" } end
    r = ok_roster(members)
    assert(select(2, roster.adopt(r, view(1, C))) == "full")
    assert(#r.members == roster.CAP)
    -- one below the cap still works
    r = ok_roster({ members[1] })
    assert(roster.adopt(r, view(1, C)) and #r.members == roster.CAP)
end

-- release
do
    local r = ok_roster({
        { offline_id = A, name = "Ana", status = "present", extra = 1 },
        { offline_id = B, name = "Bo", status = "away" },
    })
    local a = r.members[1]
    local m, err = roster.release(r, A:upper())
    assert(m == a and err == nil and m.extra == 1)
    assert(#r.members == 1 and r.members[1].offline_id == B)

    m, err = roster.release(r, A)
    assert(m == nil and err == "not_adopted")
    m, err = roster.release(r, "garbage")
    assert(m == nil and err == "not_adopted")
    m, err = roster.release(r, nil)
    assert(m == nil and err == "not_adopted")

    -- order of the remaining members is kept
    local ids = n_ids(roster.CAP)
    local members = {}
    for i, id in ipairs(ids) do members[i] = { offline_id = id, status = "away", name = "N" } end
    r = ok_roster(members)
    roster.release(r, ids[1])
    assert(#r.members == roster.CAP - 1 and r.members[1].offline_id == ids[2])

    -- release from the middle keeps the order of the rest (an artificial roster above the cap)
    r = ok_roster({
        { offline_id = A, name = "Ana", status = "present" },
        { offline_id = B, name = "Bo", status = "present" },
        { offline_id = C, name = "Cy", status = "present" },
    })
    assert(roster.release(r, B))
    assert(#r.members == 2 and r.members[1].offline_id == A and r.members[2].offline_id == C)

    local locked_r = { mode = roster.LOCKED, members = {}, warnings = {} }
    local ro_r = { mode = roster.READ_ONLY, members = { { offline_id = A } }, warnings = {} }
    assert(select(2, roster.release(locked_r, A)) == "locked")
    assert(select(2, roster.release(ro_r, A)) == "read_only")
    assert(select(2, roster.release(ro_r, C)) == "read_only") -- a non-member too
    assert(#ro_r.members == 1)
end

-- refresh_cache
do
    local function fresh()
        return ok_roster({
            { offline_id = A, name = "Ana", status = "present", character_id = 5 },
            { offline_id = B, name = "Bo", status = "away", character_id = 6 },
        })
    end
    local r = fresh()
    assert(roster.refresh_cache(r, { view(1, A, { name = "Ana", character_id = 5 }) }) == false)

    -- present member updated: id and name
    assert(roster.refresh_cache(r, { view(1, A, { name = "Anna", character_id = 9 }) }) == true)
    assert(r.members[1].name == "Anna" and r.members[1].character_id == 9)

    -- only the id changes / only the name changes
    r = fresh()
    assert(roster.refresh_cache(r, { view(1, A, { name = "Ana", character_id = 9 }) }) == true)
    assert(r.members[1].character_id == 9 and r.members[1].name == "Ana")
    r = fresh()
    assert(roster.refresh_cache(r, { view(1, A, { name = "Zed", character_id = 5 }) }) == true)
    assert(r.members[1].name == "Zed")

    -- nil / invalid view values do not erase the cache
    r = fresh()
    assert(roster.refresh_cache(r, { { slot = 1, owner = "CAPCOM", offline_id = A } }) == false)
    assert(roster.refresh_cache(r, { view(1, A, { name = "", character_id = -4 }) }) == false)
    assert(r.members[1].name == "Ana" and r.members[1].character_id == 5)

    -- a member without a cached id gets one
    r = ok_roster({ { offline_id = A, name = "Ana", status = "present" } })
    assert(roster.refresh_cache(r, { view(1, A, { character_id = 77 }) }) == true)
    assert(r.members[1].character_id == 77)

    -- away and returning members are untouched
    for _, status in ipairs({ roster.AWAY, roster.RETURNING }) do
        r = ok_roster({ { offline_id = A, name = "Ana", status = status, character_id = 5 } })
        assert(roster.refresh_cache(r, { view(1, A, { name = "Other", character_id = 9 }) }) == false)
        assert(r.members[1].name == "Ana" and r.members[1].character_id == 5)
    end

    -- ambiguous members are untouched
    r = fresh()
    assert(roster.refresh_cache(r, { view(1, A, { name = "X", character_id = 9 }), view(2, A, { name = "Y", character_id = 10 }) }) == false)
    assert(r.members[1].name == "Ana" and r.members[1].character_id == 5)

    -- a member not in the party is untouched
    r = fresh()
    assert(roster.refresh_cache(r, {}) == false)

    -- LOCKED -> false, nothing changes
    local locked_r = { mode = roster.LOCKED, warnings = {},
        members = { { offline_id = A, name = "Ana", status = "present", character_id = 5 } } }
    assert(roster.refresh_cache(locked_r, { view(1, A, { name = "Anna", character_id = 9 }) }) == false)
    assert(locked_r.members[1].name == "Ana" and locked_r.members[1].character_id == 5)
    assert(roster.refresh_cache(nil, { view(1, A) }) == false)

    -- READ_ONLY works in memory
    local ro_r = { mode = roster.READ_ONLY, members = { { offline_id = A, name = "Ana", status = "present", character_id = 5 } }, warnings = {} }
    assert(roster.refresh_cache(ro_r, { view(1, A, { character_id = 8 }) }) == true)
    assert(ro_r.members[1].character_id == 8)
end

-- error_text
do
    assert(roster.ERRORS.full == "the retinue is full (" .. roster.CAP .. " members)")
    assert(roster.error_text("full") == roster.ERRORS.full)
    assert(roster.error_text("already_adopted") == "already in the retinue")
    assert(roster.error_text("locked") == "the roster is locked (see the menu)")
    assert(roster.error_text("read_only") == "the roster is read-only (written by a newer Retinue)")
    assert(roster.error_text("no_offline_id") == "not a Rift pawn with an Offline ID")
    assert(roster.error_text("not_adopted") == "not in the retinue")
    assert(roster.error_text("no_slot") == "the save slot is unknown")
    assert(roster.error_text("not_in_party") == "no longer in the party")
    assert(roster.error_text("mystery") == "mystery")
    assert(roster.error_text(nil) == "nil")
end

-- state_text
do
    assert(roster.state_text(nil) == "no roster (slot unknown)")
    assert(roster.state_text(ok_roster({})) == "roster ok (0/" .. roster.CAP .. ")")
    assert(roster.state_text(ok_roster({ { offline_id = A } })) == "roster ok (1/" .. roster.CAP .. ")")
    assert(roster.state_text(roster.resolve("unparseable"))
        == "roster locked: not valid JSON (fix roster.json by hand, then Reset scripts)")
    assert(roster.state_text(roster.resolve("ok", { version = 2 }))
        == "roster read-only: written by a newer Retinue (version 2)")
end

-- member_text
do
    local m = { name = "Ana", status = roster.PRESENT }
    assert(roster.member_text(m, { in_party = true, ambiguous = false }) == "Ana: present")
    assert(roster.member_text(m, { level = 12, in_party = true, ambiguous = false }) == "Ana: present, Lv 12")
    assert(roster.member_text(m, { level = 12.0, in_party = true, ambiguous = false }) == "Ana: present, Lv 12")
    assert(roster.member_text(m, { level = 12.5, in_party = true, ambiguous = false }) == "Ana: present, Lv 12.5")
    assert(roster.member_text(m, { in_party = false, ambiguous = false }) == "Ana: present, not in party")
    assert(roster.member_text(m, { level = 3, in_party = false, ambiguous = false }) == "Ana: present, Lv 3, not in party")
    assert(roster.member_text(m, { level = 3, in_party = false, ambiguous = true })
        == "Ana: present, Lv 3, ambiguous: two party pawns share its Offline ID, excluded")
    assert(roster.member_text(m, { in_party = true, ambiguous = true })
        == "Ana: present, ambiguous: two party pawns share its Offline ID, excluded")
    local away = { name = "Bo", status = roster.AWAY }
    assert(roster.member_text(away, { in_party = false, ambiguous = false }) == "Bo: away")
    assert(roster.member_text({ name = "Cy", status = roster.RETURNING }, { in_party = true, ambiguous = false }) == "Cy: returning")
    -- backup_note goes last
    assert(roster.member_text(m, { in_party = true, ambiguous = false, backup_note = "missing" }) == "Ana: present, backup missing")
    assert(roster.member_text(m, { level = 12, in_party = true, ambiguous = false, backup_note = "damaged: level is missing or invalid" })
        == "Ana: present, Lv 12, backup damaged: level is missing or invalid")
    assert(roster.member_text(m, { level = 3, in_party = false, ambiguous = false, backup_note = "missing" })
        == "Ana: present, Lv 3, not in party, backup missing")
    assert(roster.member_text(m, { level = 3, in_party = false, ambiguous = true, backup_note = "missing" })
        == "Ana: present, Lv 3, ambiguous: two party pawns share its Offline ID, excluded, backup missing")
end

-- pawn_text: party pawn line before adoption
assert(roster.pawn_text("Folken", 12) == "Folken (Lv 12)")
assert(roster.pawn_text("Folken", 12.0) == "Folken (Lv 12)")
assert(roster.pawn_text("Folken", nil) == "Folken")

-- member_text: restore_note
do
    local m = { name = "Cy", status = roster.RETURNING }
    assert(roster.member_text(m, { in_party = true, ambiguous = false, restore_note = "pending" }) == "Cy: returning, restore pending")
    assert(roster.member_text(m, { level = 4, in_party = true, ambiguous = false, restore_note = "timed out" })
        == "Cy: returning, Lv 4, restore timed out")
    assert(roster.member_text(m, { in_party = true, ambiguous = false, restore_note = "pending", backup_note = "missing" })
        == "Cy: returning, restore pending, backup missing")
    assert(roster.member_text({ name = "Ana", status = roster.PRESENT },
        { level = 3, in_party = false, ambiguous = true, restore_note = "pending", backup_note = "missing" })
        == "Ana: present, Lv 3, ambiguous: two party pawns share its Offline ID, excluded, restore pending, backup missing")
end

-- mark_away / mark_returning / mark_present
do
    local function with(status, cid)
        return ok_roster({ { offline_id = A, name = "Ana", status = status, character_id = cid or 7 } })
    end
    -- mark_away
    local r = with(roster.PRESENT)
    local m, from = roster.mark_away(r, A)
    assert(m == r.members[1] and m.status == roster.AWAY and from == roster.PRESENT and m.character_id == 7)
    r = with(roster.RETURNING)
    m, from = roster.mark_away(r, A:upper())
    assert(m and m.status == roster.AWAY and from == roster.RETURNING and m.character_id == 7)
    r = with(roster.AWAY)
    local none, err = roster.mark_away(r, A)
    assert(none == nil and err == "already_away" and r.members[1].status == roster.AWAY)
    -- mark_returning
    r = with(roster.AWAY)
    m = roster.mark_returning(r, A)
    assert(m == r.members[1] and m.status == roster.RETURNING and m.character_id == 7)
    for _, st in ipairs({ roster.PRESENT, roster.RETURNING }) do
        r = with(st)
        none, err = roster.mark_returning(r, A)
        assert(none == nil and err == "not_away" and r.members[1].status == st)
    end
    -- mark_present
    r = with(roster.RETURNING)
    m = roster.mark_present(r, A, 99)
    assert(m == r.members[1] and m.status == roster.PRESENT and m.character_id == 99)
    r = with(roster.RETURNING)
    assert(roster.mark_present(r, A, nil).character_id == 7)
    r = with(roster.RETURNING)
    assert(roster.mark_present(r, A, "junk").character_id == 7)
    r = with(roster.RETURNING)
    assert(roster.mark_present(r, A, -5).character_id == 7)
    r = with(roster.RETURNING)
    assert(roster.mark_present(r, A, 99.0).character_id == 99)
    for _, st in ipairs({ roster.PRESENT, roster.AWAY }) do
        r = with(st)
        none, err = roster.mark_present(r, A, 99)
        assert(none == nil and err == "not_returning" and r.members[1].status == st and r.members[1].character_id == 7)
    end
    -- unknown id, locked, read-only
    r = with(roster.PRESENT)
    for _, id in ipairs({ B, "nope", ZERO }) do
        assert(select(2, roster.mark_away(r, id)) == "not_adopted")
        assert(select(2, roster.mark_returning(r, id)) == "not_adopted")
        assert(select(2, roster.mark_present(r, id, 1)) == "not_adopted")
    end
    local lk = roster.resolve("unparseable")
    assert(select(2, roster.mark_away(lk, A)) == "locked")
    assert(select(2, roster.mark_returning(lk, A)) == "locked")
    assert(select(2, roster.mark_present(lk, A, 1)) == "locked")
    -- read-only works in memory
    local ro = with(roster.PRESENT)
    ro.mode = roster.READ_ONLY
    assert(select(2, roster.mark_away(ro, A)) == roster.PRESENT and ro.members[1].status == roster.AWAY)
    assert(roster.mark_returning(ro, A).status == roster.RETURNING)
    assert(roster.mark_present(ro, A, 5).status == roster.PRESENT)
end
