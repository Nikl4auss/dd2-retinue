-- The player-facing texts (the native notices). Pure: no REFramework globals, so it runs under plain Lua in tests. The
-- log texts of the transitions stay in departure.lua; the notice queue is notices.lua, the game call game/notice_screen.lua.
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

-- A level as departure.lua prints it: an integral float without the ".0".
local function num(n) return tostring(slot.to_int(n) or n) end

function M.returned(name, level)
    return string.format("%s returned — Lv %s restored", name, num(level))
end

function M.kept(name, level)
    return string.format("%s returned — kept Lv %s, newer than the backup", name, num(level))
end

-- The talk menu's row and the confirm (game/talk_menu.lua). The same words as the mod menu's confirmations.
function M.adopt_row() return "Adopt" end

-- The member's row; the level when known ("\194\183" is U+00B7, as in the mod menu).
function M.release_row(level)
    if level == nil then return "Release (Retinue)" end
    return string.format("Release (Retinue \194\183 Lv %s)", num(level))
end

-- A full retinue's sub-menu row for an away member (the pick releases it and adopts the pawn talked to); the level is the
-- backup's, when known.
function M.release_away(name, level)
    if level == nil then return string.format("Release %s (away)", name) end
    return string.format("Release %s (away, Lv %s)", name, num(level))
end

-- The confirm replaces the Talk sub-menu's first row; Small talk is removed.
function M.confirm_adopt() return "Confirm adopt" end
function M.confirm_release() return "Confirm release" end

-- refused(action, name, err) -> text. action "adopt" | "release"; err one of roster.ERRORS' keys.
function M.refused(action, name, err)
    return string.format("Cannot %s %s: %s", action, name, roster.error_text(err))
end

-- roster_problem(r, unit) -> text | nil. r is the active roster (retinue.roster), unit the session's unit
-- (tracker.session.unit, not the roster unit). No roster with a unit set is a NewGame waiting for its first save:
-- nothing is wrong, so no text.
function M.roster_problem(r, unit)
    if r == nil then
        if unit == nil then return "Retinue is off: the save slot is unknown" end
        return nil
    end
    if r.mode == roster.LOCKED then
        return string.format("The Retinue roster is locked: %s\nSee the Retinue menu.", tostring(r.reason))
    elseif r.mode == roster.READ_ONLY then
        return string.format("The Retinue roster is read-only: written by a newer Retinue (%s)", tostring(r.reason))
    end
    return nil
end

return M
