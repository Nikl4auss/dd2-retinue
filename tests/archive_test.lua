local archive = require("Retinue.archive")

local T = { year = 2026, month = 11, day = 6, hour = 12, min = 0, sec = 0 }
local DIR = "Retinue/slots/2"
local ARCH = DIR .. "/archive-20261106-120000"
local ROSTER = DIR .. "/roster.json"
local BK_A = DIR .. "/backups/aaaa.json"
local BK_B = DIR .. "/backups/bbbb.json"

-- A fake in-memory fs. opts: sep = "\\" lists paths with backslashes; throw_list; no_write = { [path] = true } (a
-- write that does nothing, like a locked file); no_copy = true (writes under an archive folder do nothing);
-- unreadable = { [path] = true } (read returns nil). Returns files, store, writes (the log of write calls).
local function fake(initial, opts)
    opts = opts or {}
    local store, writes = {}, {}
    for k, v in pairs(initial) do store[k] = v end
    local files = {}
    function files.list(filter)
        if opts.throw_list then error("glob failed") end
        if opts.list_nil then return nil end
        local out = {}
        for path in pairs(store) do
            if store[path] ~= "" or opts.list_empty then
                out[#out + 1] = opts.sep and path:gsub("/", opts.sep) or path
            end
        end
        files.last_filter = filter
        return out
    end
    function files.read(path)
        if opts.unreadable and opts.unreadable[path] then return nil end
        return store[path] or ""
    end
    function files.write(path, text)
        writes[#writes + 1] = path
        if opts.no_write and opts.no_write[path] then return end
        if opts.no_copy and path:find("/archive-", 1, true) then return end
        store[path] = text
    end
    return files, store, writes
end

-- filter(1) is exactly Retinue[\\/]slots[\\/]2[\\/].* : two literal backslashes in each class
assert(archive.filter(1) == [==[Retinue[\\/]slots[\\/]2[\\/].*]==], archive.filter(1))
assert(select(2, archive.filter(1):gsub("\\", "")) == 6) -- six backslash characters in all
assert(archive.filter(0) == [==[Retinue[\\/]slots[\\/]1[\\/].*]==])

-- done: roster + backups; the backups subfolder; originals emptied; contents byte-exact
do
    local rtext = '{"version":1,\n "members":[]}\r\n\195\177'
    local files, store, writes = fake({ [ROSTER] = rtext, [BK_A] = "A\n", [BK_B] = "B\0b" })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.dir == ARCH and r.copied == 3 and r.left == 0 and r.why == nil)
    assert(store[ARCH .. "/roster.json"] == rtext)
    assert(store[ARCH .. "/backups/aaaa.json"] == "A\n" and store[ARCH .. "/backups/bbbb.json"] == "B\0b")
    assert(store[ROSTER] == "" and store[BK_A] == "" and store[BK_B] == "")
    assert(files.last_filter == archive.filter(1))
    -- the roster is emptied before any backup
    local first_empty
    for _, w in ipairs(writes) do
        if w == ROSTER or w == BK_A or w == BK_B then first_empty = first_empty or w end
    end
    assert(first_empty == ROSTER)
    assert(archive.text(r, 1) == "Slot 2: archived 3 files to Retinue/slots/2/archive-20261106-120000; the slot starts empty")
end

-- none: an empty or missing roster leaves every file and writes nothing
do
    local files, store, writes = fake({ [BK_A] = "A", [DIR .. "/other.txt"] = "x" })
    local r = archive.run(1, T, files)
    assert(r.status == "none" and r.dir == nil and r.copied == 0)
    assert(#writes == 0 and store[BK_A] == "A" and store[ROSTER] == nil)
    assert(archive.text(r, 1) == nil)
    local files2, _, writes2 = fake({ [ROSTER] = "", [BK_A] = "A" })
    assert(archive.run(1, T, files2).status == "none" and #writes2 == 0)
end

-- backslash listing (what fs.glob returns) archives the same files
do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A" }, { sep = "\\" })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 2)
    assert(store[ARCH .. "/backups/aaaa.json"] == "A" and store[BK_A] == "")
end

-- earlier archive-* folders are untouched and not archived again; other slots untouched
do
    local old = DIR .. "/archive-20260101-000000"
    local files, store = fake({
        [ROSTER] = "R", [BK_A] = "A",
        [old .. "/roster.json"] = "OLD", [old .. "/backups/x.json"] = "OLDB",
        ["Retinue/slots/1/roster.json"] = "S1", ["Retinue/slots/3/backups/c.json"] = "S3",
        ["Retinue/slots/22/roster.json"] = "S22", ["Retinue/config.json"] = "CFG",
    }, { sep = "\\" })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 2)
    assert(store[old .. "/roster.json"] == "OLD" and store[old .. "/backups/x.json"] == "OLDB")
    assert(store[ARCH .. "/archive-20260101-000000/roster.json"] == nil)
    assert(store["Retinue/slots/1/roster.json"] == "S1" and store["Retinue/slots/3/backups/c.json"] == "S3")
    assert(store["Retinue/slots/22/roster.json"] == "S22" and store["Retinue/config.json"] == "CFG")
end

-- empty files (an emptied backup) are skipped: not copied, not rewritten
do
    local files, store, writes = fake({ [ROSTER] = "R", [BK_A] = "", [BK_B] = "B" }, { list_empty = true })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 2)
    assert(store[ARCH .. "/backups/aaaa.json"] == nil)
    for _, w in ipairs(writes) do assert(w ~= BK_A) end
end

-- an unparseable roster is archived as it is
do
    local junk = "{not json \xff\xfe"
    local files, store = fake({ [ROSTER] = junk })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 1 and store[ARCH .. "/roster.json"] == junk and store[ROSTER] == "")
    assert(archive.text(r, 1):find("archived 1 file to ", 1, true))
end

-- a list failure (throw, nil, not a table) archives the roster alone
for _, o in ipairs({ { throw_list = true }, { list_nil = true } }) do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A" }, o)
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 1)
    assert(store[ARCH .. "/roster.json"] == "R" and store[ROSTER] == "" and store[BK_A] == "A")
end
do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A" })
    files.list = function() return "nope" end
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 1 and store[BK_A] == "A")
end

-- the listing may include the roster: it is copied once
do
    local files = fake({ [ROSTER] = "R" })
    files.list = function() return { ROSTER, ROSTER:gsub("/", "\\"), ROSTER } end
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.copied == 1)
end

-- copy failure empties nothing
do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A" }, { no_copy = true })
    local r = archive.run(1, T, files)
    assert(r.status == "failed" and r.dir == ARCH and r.copied == 0)
    assert(store[ROSTER] == "R" and store[BK_A] == "A")
    assert(archive.text(r, 1) == "Slot 2: could not archive the roster (" .. r.why .. "); it stays in place")
end
do -- the copy fails halfway (files go in sorted order): the first was copied, nothing is emptied
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A", [BK_B] = "B" }, { no_write = { [ARCH .. "/backups/bbbb.json"] = true } })
    local r = archive.run(1, T, files)
    assert(r.status == "failed" and r.copied == 1 and r.why:find("bbbb", 1, true))
    assert(store[ROSTER] == "R" and store[BK_A] == "A" and store[BK_B] == "B")
end
do -- a copy that reads back different
    local files, store = fake({ [ROSTER] = "R" })
    local write = files.write
    files.write = function(path, text) write(path, path:find("archive-", 1, true) and text .. "!" or text) end
    local r = archive.run(1, T, files)
    assert(r.status == "failed" and store[ROSTER] == "R")
end

-- a roster that cannot be emptied stops there: the backups stay whole
do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A" }, { no_write = { [ROSTER] = true } })
    local r = archive.run(1, T, files)
    assert(r.status == "failed" and r.why == "roster could not be emptied" and r.copied == 2 and r.dir == ARCH)
    assert(store[ROSTER] == "R" and store[BK_A] == "A")
    assert(archive.text(r, 1) == "Slot 2: could not archive the roster (roster could not be emptied); it stays in place")
end

-- a backup that cannot be emptied: done, counted in left
do
    local files, store = fake({ [ROSTER] = "R", [BK_A] = "A", [BK_B] = "B" }, { no_write = { [BK_A] = true } })
    local r = archive.run(1, T, files)
    assert(r.status == "done" and r.left == 1 and r.copied == 3)
    assert(store[ROSTER] == "" and store[BK_A] == "A" and store[BK_B] == "")
    assert(archive.text(r, 1) ==
        "Slot 2: archived 3 files to Retinue/slots/2/archive-20261106-120000; the slot starts empty (1 not emptied)")
end

-- read failure: the roster, then a backup; nothing is written
do
    local files, store, writes = fake({ [ROSTER] = "R" }, { unreadable = { [ROSTER] = true } })
    local r = archive.run(1, T, files)
    assert(r.status == "failed" and r.why == "roster unreadable" and r.dir == nil and #writes == 0)
    assert(archive.text(r, 1) == "Slot 2: could not archive the roster (roster unreadable); it stays in place")
    local files2, store2, writes2 = fake({ [ROSTER] = "R", [BK_A] = "A" }, { unreadable = { [BK_A] = true } })
    local r2 = archive.run(1, T, files2)
    assert(r2.status == "failed" and r2.copied == 0 and #writes2 == 0 and store2[ROSTER] == "R")
    assert(r2.why:find("backups/aaaa.json", 1, true))
end

-- text: slot label comes from the unit
assert(archive.text({ status = "done", dir = "d", copied = 2, left = 0 }, 0) == "Slot 1: archived 2 files to d; the slot starts empty")
assert(archive.text({ status = "failed" }, 2) == "Slot 3: could not archive the roster (unknown); it stays in place")
assert(archive.text({ status = "none" }, 0) == nil)
