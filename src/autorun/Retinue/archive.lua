-- Archive of a save slot's roster on a new playthrough. Pure: no REFramework globals, so it runs under plain Lua in
-- tests; game/archive_store.lua supplies the file operations (and the trigger, slot.lua's take_archive).
-- REFramework has no working os.remove or os.rename here, so an archive is a copy of every file of the slot
-- (roster.json and backups/*.json) into slots/<n>/archive-<yyyymmdd-hhmmss>/ plus emptying the originals (an empty
-- file reads as missing). The copy is raw text, never decoded.
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

-- filter(unit) -> the fs.glob regex for everything under slot.dir(unit): each "/" of the path becomes the class
-- [\\/] (backslash or slash; fs.glob lists paths with backslashes, and the filter must match the whole path), then
-- "[\\/].*". filter(1) is Retinue[\\/]slots[\\/]2[\\/].* (the Lua string holds two backslash characters per class).
function M.filter(unit)
    local path = slot.dir(unit):gsub("/", function() return "[\\\\/]" end)
    return path .. "[\\\\/].*"
end

-- The files to archive: the paths fs.glob listed under the slot (separators normalised to "/"), without the
-- archive-* folders, plus the roster, deduplicated and sorted. Returns an array of paths relative to the data folder.
local function collect(unit, listed)
    local base = slot.dir(unit) .. "/"
    local rpath = roster.path(unit)
    local seen, out = { [rpath] = true }, { rpath }
    if type(listed) == "table" then
        for _, p in ipairs(listed) do
            if type(p) == "string" then
                p = p:gsub("\\", "/")
                local rel = p:sub(1, #base) == base and p:sub(#base + 1) or nil
                if rel and rel ~= "" and not rel:match("^archive%-[^/]*") and not seen[p] then
                    seen[p] = true
                    out[#out + 1] = p
                end
            end
        end
    end
    table.sort(out)
    return out
end

-- run(unit, t, files) -> result. t is an os.date("*t") shaped table (the archive's name).
--   files.list(filter) -> array of paths (relative to reframework/data, either separator)
--   files.read(path)   -> text ("" = missing or empty), or nil when it cannot be read
--   files.write(path, text) -> anything; success is judged only by reading back
-- result: { status = "none" | "done" | "failed", dir = string|nil, copied = n, left = n, why = string|nil }
--   none    the roster is missing or empty: nothing was touched
--   done    every non-empty file was copied and read back, the roster was emptied; left = originals that stayed
--           non-empty (an orphan backup is ignored, and a re-adopt overwrites it)
--   failed  something went wrong before the roster was emptied (why says what): the old roster and all its
--           backups are still whole. dir is set once a copy was attempted; copied tells how far it went.
-- An unparseable, locked or newer-version roster is archived like any other: the copy keeps it as it was.
function M.run(unit, t, files)
    local result = { status = "failed", dir = nil, copied = 0, left = 0, why = nil }
    local rpath = roster.path(unit)
    local rtext = files.read(rpath)
    if rtext == nil then
        result.why = "roster unreadable"
        return result
    end
    if rtext == "" then
        result.status = "none"
        return result
    end

    local ok, listed = pcall(files.list, M.filter(unit))
    if not ok then listed = nil end
    local paths = collect(unit, listed)

    -- Read everything first, so an unreadable file stops the run before any copy exists.
    local base = slot.dir(unit) .. "/"
    local items = {}
    for _, p in ipairs(paths) do
        local text = p == rpath and rtext or files.read(p)
        if text == nil then
            result.why = "unreadable: " .. p:sub(#base + 1)
            return result
        end
        if text ~= "" then items[#items + 1] = { path = p, rel = p:sub(#base + 1), text = text } end
    end

    local dir = slot.archive_dir(unit, t)
    result.dir = dir
    for _, item in ipairs(items) do
        local dest = dir .. "/" .. item.rel
        files.write(dest, item.text)
        if files.read(dest) ~= item.text then
            result.why = "copy failed: " .. item.rel
            return result
        end
        result.copied = result.copied + 1
    end

    -- The roster first: if it stays, the old roster and all its backups are still whole.
    files.write(rpath, "")
    if files.read(rpath) ~= "" then
        result.why = "roster could not be emptied"
        return result
    end
    for _, item in ipairs(items) do
        if item.path ~= rpath then
            files.write(item.path, "")
            if files.read(item.path) ~= "" then result.left = result.left + 1 end
        end
    end
    result.status = "done"
    return result
end

-- text(result, unit) -> the log line (no prefix), or nil for "none".
function M.text(result, unit)
    if result.status == "done" then
        local line = string.format("%s: archived %d %s to %s; the slot starts empty", slot.label(unit), result.copied,
            result.copied == 1 and "file" or "files", result.dir)
        if result.left > 0 then line = line .. string.format(" (%d not emptied)", result.left) end
        return line
    elseif result.status == "failed" then
        return string.format("%s: could not archive the roster (%s); it stays in place", slot.label(unit),
            result.why or "unknown")
    end
    return nil
end

return M
