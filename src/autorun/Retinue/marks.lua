-- The decisions behind the marks on the game's own pages: who is marked, and the text a name widget gets. Pure: no
-- REFramework globals, so it runs under plain Lua in tests. The hooks and the widget writes are game/marks.lua, the texts
-- are labels.lua.
--
-- The text rules are idempotent and self-cleaning: every result starts from the shown text with our own mark stripped, so a
-- second run never stacks a mark, a changed level replaces the old one, and a widget reused for a non-member loses a stale
-- mark. nil means "write nothing" (also for text that is already right).
local labels = require("Retinue.labels")
local roster = require("Retinue.roster")

local M = {}

-- status_member(r, offline_id, is_main_pawn) -> boolean. The Status page marks a present member that is not the main pawn;
-- a nil roster or an unreadable id matches nobody.
function M.status_member(r, offline_id, is_main_pawn)
    if is_main_pawn then return false end
    local m = roster.find(r, offline_id)
    return m ~= nil and m.status == roster.PRESENT
end

-- rift_member(r, offline_id) -> member | nil. Previous Hires marks every member, whatever its status.
function M.rift_member(r, offline_id)
    return roster.find(r, offline_id)
end

local function ends_with(s, suffix)
    return #s >= #suffix and s:sub(-#suffix) == suffix
end

-- status_text(shown, member) -> text | nil. member: truthy for a member. The shown text without our trailing mark is the
-- base; a member gets the mark, anyone else the base.
function M.status_text(shown, member)
    if shown == nil or shown == "" then return nil end
    local base = shown
    if ends_with(base, labels.STATUS_MARK) then base = base:sub(1, #base - #labels.STATUS_MARK) end
    if base == "" then return nil end -- only our mark: no name to keep
    local out = member and labels.status_name(base) or base
    if out == shown then return nil end
    return out
end

-- rift_text(shown, member, level) -> text | nil. A text starting with the star is ours: the star and a trailing
-- " · Lv <digits>" are stripped to get the base. member: truthy for a member; level the backup's (nil: no level).
function M.rift_text(shown, member, level)
    if shown == nil or shown == "" then return nil end
    local base = shown
    local star = labels.RIFT_STAR
    if base:sub(1, #star) == star then
        base = base:sub(#star + 1)
        local cut = base:match("^(.-) \194\183 Lv %d+$")
        if cut then base = cut end
    end
    if base == "" then return nil end -- only our mark: no name to keep
    local out = member and labels.rift_name(base, level) or base
    if out == shown then return nil end
    return out
end

return M
