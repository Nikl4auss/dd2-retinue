-- The menu's status line. Pure: no REFramework globals, so it runs under plain Lua in tests.
local M = {}

M.VOCATIONS = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief", [5] = "Warrior", [6] = "Sorcerer",
    [7] = "Mystic Spearhand", [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}

-- A number as text; integral floats print without ".0"; nil -> "?".
local function num(n)
    if n == nil then return "?" end
    local i = math.tointeger(n)
    if i then return tostring(i) end
    return tostring(n)
end

-- job: number or nil. Known -> its name; other number -> "Vocation <n>"; nil -> "?".
function M.vocation_name(job)
    if job == nil then return "?" end
    return M.VOCATIONS[job] or ("Vocation " .. num(job))
end

local function row_text(row)
    local name = row.name
    if name == nil or name == "" then name = "?" end
    return string.format("%s (Lv %s, %s R%s)", name, num(row.level), M.vocation_name(row.job), num(row.rank))
end

-- rows: nil when no save is loaded; otherwise an array (party order) of
--   { name = string|nil, level = number|nil, job = number|nil, rank = number|nil }.
function M.format(rows)
    if rows == nil then return "Load a save" end
    if #rows == 0 then return "No hired pawns in party" end
    local parts = {}
    for i, row in ipairs(rows) do parts[i] = row_text(row) end
    return "Applies to: " .. table.concat(parts, ", ")
end

return M
