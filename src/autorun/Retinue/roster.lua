-- roster.json: the adopted pawns (the roster) of one save slot. Pure: no REFramework globals, so it runs under
-- plain Lua in tests; game/ does the file I/O and reads the party. Decisions live here: reading a file into a
-- roster (validation, locked, read-only, soft corrections), what to write back, adopt / release / cache refresh,
-- the adoptable rule, ambiguity, and the menu texts.
local slot = require("Retinue.slot")

local M = {}

M.CAP = 2 -- the only place the cap appears
M.VERSION = 1
M.PRESENT, M.AWAY, M.RETURNING = "present", "away", "returning"
M.OK, M.LOCKED, M.READ_ONLY = "ok", "locked", "read_only" -- roster.mode
M.UNKNOWN_NAME = "(unknown)"
M.OWNER = "CAPCOM" -- _Name of the owner context of Rift pawns

-- Party slots (not the cap) whose pawns can be adopted: the main pawn is slot 0.
local HIRED_SLOTS = { [1] = true, [2] = true }

local VALID_STATUS = { [M.PRESENT] = true, [M.AWAY] = true, [M.RETURNING] = true }

function M.path(unit) return slot.dir(unit) .. "/roster.json" end

-- Canonical Offline ID: v is a string of the form 8-4-4-4-12 hex digits (either case), not all zeros -> lowercase
-- copy; anything else (nil, non-string, wrong shape, zero GUID) -> nil.
function M.canonical_id(v)
    if type(v) ~= "string" then return nil end
    if not v:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return nil end
    if (v:gsub("[0%-]", "")) == "" then return nil end
    return v:lower()
end

-- CharacterID cache value: an integer view (slot.to_int) in 0..0xFFFFFFFF -> that integer; else nil.
function M.valid_character_id(v)
    local i = slot.to_int(v)
    if i == nil or i < 0 or i > 0xFFFFFFFF then return nil end
    return i
end

-- Party view (built by the glue, one per party pawn; also the shape the tests use):
--   { slot = 0|1|2, character_id = integer|nil, owner = string|nil, offline_id = string|nil (raw or canonical),
--     name = string|nil }
-- adoptable(view) -> canonical offline id when view.slot is 1 or 2, view.owner == M.OWNER and
-- canonical_id(view.offline_id) is non-nil; else nil.
function M.adoptable(view)
    if type(view) ~= "table" then return nil end
    if not HIRED_SLOTS[view.slot] or view.owner ~= M.OWNER then return nil end
    return M.canonical_id(view.offline_id)
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function nonempty_string(v) return type(v) == "string" and v ~= "" end

-- true when t is a table whose keys are exactly the integers 1..n (an empty table counts).
local function is_sequence(t)
    if type(t) ~= "table" then return false end
    local n = 0
    for k in pairs(t) do
        if math.type(k) ~= "integer" or k < 1 then return false end
        n = n + 1
    end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true
end

local function locked(reason)
    return { mode = M.LOCKED, reason = reason, members = {}, base = nil, warnings = {} }
end

-- Structural check of members[i] given the ids already seen. Returns nil when valid, else the locked-reason and the
-- skip-reason (the read-only path skips instead of locking).
local function structural_error(entry, i, seen)
    if type(entry) ~= "table" then
        return string.format("member %d is not an object", i), "not an object"
    end
    local id = M.canonical_id(entry.offline_id)
    if id == nil then
        return string.format("member %d has no valid offline_id", i), "no valid offline_id"
    end
    if seen[id] then
        local why = "duplicate offline_id " .. id
        return why, why
    end
    return nil
end

-- Copy of a valid entry with the known fields corrected; appends one warning per correction.
local function correct(entry, i, warnings)
    local m = copy(entry)
    m.offline_id = M.canonical_id(entry.offline_id)
    if not nonempty_string(m.name) then
        m.name = M.UNKNOWN_NAME
        warnings[#warnings + 1] = string.format("member %d: name is missing or invalid; using %s", i, M.UNKNOWN_NAME)
    end
    if m.character_id ~= nil then
        local cid = M.valid_character_id(m.character_id)
        if cid == nil then
            warnings[#warnings + 1] = string.format("member %d: character_id is invalid; ignored", i)
        end
        m.character_id = cid
    end
    if not VALID_STATUS[m.status] then
        m.status = M.AWAY
        warnings[#warnings + 1] = string.format("member %d: status is missing or invalid; using away", i)
    end
    return m
end

-- status: "missing" | "unparseable" | "unreadable" | "ok"; data: the decoded value when "ok".
-- ("unreadable": the glue could not tell missing from damaged, because fs.read is unavailable.)
-- Returns a roster:
--   { mode = OK | LOCKED | READ_ONLY,
--     reason = string|nil,        -- LOCKED: why; READ_ONLY: "version <n>"; OK: nil
--     members = { member, ... },  -- adoption order; always {} when LOCKED
--     base = table|nil,           -- decoded top level (unknown keys kept on rewrite); nil when missing or LOCKED
--     warnings = { string, ... } }
-- member = { offline_id = <canonical>, name = string, status = PRESENT|AWAY|RETURNING,
--            character_id = integer|nil, <unknown keys as read> }
function M.resolve(status, data)
    if status == "missing" then
        return { mode = M.OK, members = {}, warnings = {} }
    end
    if status == "unparseable" then return locked("not valid JSON") end
    if status == "unreadable" then return locked("cannot be read safely (fs.read unavailable)") end
    if status ~= "ok" then return locked("cannot be read") end
    if type(data) ~= "table" or #data > 0 then return locked("top level is not an object") end

    local warnings = {}
    local version = slot.to_int(data.version)
    local read_only = false
    if version == nil or version < 1 then
        warnings[#warnings + 1] = "version is missing or invalid; read as 1"
    elseif version > M.VERSION then
        read_only = true
        warnings[#warnings + 1] = string.format("written by a newer Retinue (version %d); read-only", version)
    end

    -- members: nil is an empty roster (REFramework's json writes an empty list as null).
    local entries = data.members
    if entries == nil then entries = {} end
    local sequence = is_sequence(entries)
    if not sequence and not read_only then return locked("members is not an array") end

    local valid = {} -- { entry, i }
    if sequence then
        local seen = {}
        for i, entry in ipairs(entries) do
            local locked_why, skip_why = structural_error(entry, i, seen)
            if locked_why then
                if not read_only then return locked(locked_why) end
                warnings[#warnings + 1] = string.format("member %d skipped: %s", i, skip_why)
            else
                seen[M.canonical_id(entry.offline_id)] = true
                valid[#valid + 1] = { entry = entry, i = i }
            end
        end
        if #valid > M.CAP then
            if not read_only then return locked(string.format("more than %d members", M.CAP)) end
            for j = #valid, M.CAP + 1, -1 do valid[j] = nil end
            warnings[#warnings + 1] = string.format("members past %d ignored", M.CAP)
        end
    end

    local members = {}
    for _, v in ipairs(valid) do members[#members + 1] = correct(v.entry, v.i, warnings) end

    local r = { mode = M.OK, members = members, base = data, warnings = warnings }
    if read_only then
        r.mode = M.READ_ONLY
        r.reason = "version " .. version
    end
    return r
end

function M.writable(r) return r ~= nil and r.mode == M.OK end

-- A NEW table to write (only meaningful when writable): a shallow copy of r.base (unknown top-level keys kept; nil
-- base -> {}) with version = M.VERSION and members = an array of shallow copies of r.members (a nil character_id is
-- simply absent). REFramework's json cannot round-trip some unknown keys (a JSON null decodes to nil and is
-- dropped), and it writes an empty {} or [] as null: an empty members list is written as "members": null, which
-- resolve reads back as an empty roster.
function M.serialize(r)
    local out = r.base and copy(r.base) or {}
    out.version = M.VERSION
    local members = {}
    for i, m in ipairs(r.members) do members[i] = copy(m) end
    out.members = members
    return out
end

-- Read-back check for the glue: back is a table whose members (nil = empty) list the same canonical offline_ids in
-- the same order as r.members, each with the same name, status and character_id (so a cache-only change that did
-- not reach the file is caught too).
function M.matches(r, back)
    if type(back) ~= "table" then return false end
    local members = back.members
    if members == nil then members = {} end
    if not is_sequence(members) or #members ~= #r.members then return false end
    for i, m in ipairs(r.members) do
        local e = members[i]
        if type(e) ~= "table" or M.canonical_id(e.offline_id) ~= m.offline_id or e.name ~= m.name
            or e.status ~= m.status or slot.to_int(e.character_id) ~= m.character_id then
            return false
        end
    end
    return true
end

-- match(r, views) -> found, ambiguous
--   found:     { [offline_id] = view }  members of r whose id appears in exactly one view
--   ambiguous: { [offline_id] = true }  members of r whose id appears in two or more views
-- Views are compared by canonical_id(view.offline_id); views without one are ignored. Any slot counts (a duplicate
-- anywhere in the party is ambiguous). A LOCKED or nil r -> {}, {}.
function M.match(r, views)
    local found, ambiguous = {}, {}
    if r == nil or r.mode == M.LOCKED then return found, ambiguous end
    local by_id, count = {}, {}
    for _, view in ipairs(views) do
        local id = M.canonical_id(view.offline_id)
        if id then
            by_id[id] = view
            count[id] = (count[id] or 0) + 1
        end
    end
    for _, m in ipairs(r.members) do
        local n = count[m.offline_id]
        if n == 1 then
            found[m.offline_id] = by_id[m.offline_id]
        elseif n and n >= 2 then
            ambiguous[m.offline_id] = true
        end
    end
    return found, ambiguous
end

-- The member with this canonical id (the input is canonicalised) or nil.
function M.find(r, offline_id)
    local id = M.canonical_id(offline_id)
    if id == nil or r == nil then return nil end
    for _, m in ipairs(r.members) do
        if m.offline_id == id then return m end
    end
    return nil
end

-- adopt(r, view) -> member | nil, err. Mutates r in place; never touches files. Checks in this order: LOCKED ->
-- "locked"; READ_ONLY -> "read_only"; not adoptable -> "no_offline_id"; already a member (any status) ->
-- "already_adopted"; #r.members >= M.CAP -> "full".
function M.adopt(r, view)
    if r.mode == M.LOCKED then return nil, "locked" end
    if r.mode == M.READ_ONLY then return nil, "read_only" end
    local id = M.adoptable(view)
    if id == nil then return nil, "no_offline_id" end
    if M.find(r, id) then return nil, "already_adopted" end
    if #r.members >= M.CAP then return nil, "full" end
    local m = {
        offline_id = id,
        name = nonempty_string(view.name) and view.name or M.UNKNOWN_NAME,
        status = M.PRESENT,
        character_id = M.valid_character_id(view.character_id),
    }
    r.members[#r.members + 1] = m
    return m
end

-- release(r, offline_id) -> removed member | nil, err. LOCKED -> "locked"; READ_ONLY -> "read_only"; not a member
-- -> "not_adopted". Removes the whole member table (its unknown keys go with it).
function M.release(r, offline_id)
    if r.mode == M.LOCKED then return nil, "locked" end
    if r.mode == M.READ_ONLY then return nil, "read_only" end
    local id = M.canonical_id(offline_id)
    for i, m in ipairs(r.members) do
        if m.offline_id == id then
            table.remove(r.members, i)
            return m
        end
    end
    return nil, "not_adopted"
end

-- refresh_cache(r, views) -> changed (boolean). For each PRESENT member in match(r, views).found (so never an
-- ambiguous one): set character_id = valid_character_id(view.character_id) when non-nil and different, and name =
-- view.name when a non-empty string and different. Away and returning members are left alone (an away member keeps
-- its last CharacterID). LOCKED -> false. Works in memory for READ_ONLY too (the glue never writes it).
function M.refresh_cache(r, views)
    if r == nil or r.mode == M.LOCKED then return false end
    local found = M.match(r, views)
    local changed = false
    for _, m in ipairs(r.members) do
        local view = found[m.offline_id]
        if m.status == M.PRESENT and view then
            local cid = M.valid_character_id(view.character_id)
            if cid ~= nil and cid ~= m.character_id then
                m.character_id = cid
                changed = true
            end
            if nonempty_string(view.name) and view.name ~= m.name then
                m.name = view.name
                changed = true
            end
        end
    end
    return changed
end

M.ERRORS = {
    full = "the retinue is full (" .. M.CAP .. " members)",
    already_adopted = "already in the retinue",
    locked = "the roster is locked (see the menu)",
    read_only = "the roster is read-only (written by a newer Retinue)",
    no_offline_id = "not a Rift pawn with an Offline ID",
    not_adopted = "not in the retinue",
    no_slot = "the save slot is unknown", -- produced by the glue
    not_in_party = "no longer in the party", -- produced by the glue
    write_failed = "could not save roster.json (see log)", -- not an operation error; used by the menu
}

function M.error_text(err) return M.ERRORS[err] or tostring(err) end

-- nil r -> "no roster (slot unknown)"; OK -> "roster ok (<n>/<CAP>)"; LOCKED and READ_ONLY name the reason.
function M.state_text(r)
    if r == nil then return "no roster (slot unknown)" end
    if r.mode == M.OK then
        return string.format("roster ok (%d/%d)", #r.members, M.CAP)
    elseif r.mode == M.LOCKED then
        return string.format("roster locked: %s (fix roster.json by hand, then Reset scripts)", r.reason)
    end
    return string.format("roster read-only: written by a newer Retinue (%s)", r.reason)
end

-- A number as text; integral floats print without ".0" (like status.lua).
local function num(n)
    local i = math.tointeger(n)
    if i then return tostring(i) end
    return tostring(n)
end

-- member_text(m, info) -> "<name>: <status>[, Lv <level>][, <note>]"
--   info = { level = number|nil, in_party = boolean, ambiguous = boolean }
function M.member_text(m, info)
    local text = m.name .. ": " .. m.status
    if info.level ~= nil then text = text .. ", Lv " .. num(info.level) end
    if info.ambiguous then
        text = text .. ", ambiguous: two party pawns share its Offline ID, excluded"
    elseif m.status == M.PRESENT and not info.in_party then
        text = text .. ", not in party"
    end
    return text
end

return M
