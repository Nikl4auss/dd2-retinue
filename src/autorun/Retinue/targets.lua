-- Which party pawns Retinue lifts: only present adopted pawns (members of the slot's roster). Pure: no REFramework
-- globals, so it runs under plain Lua in tests.
local ids = require("Retinue.ids")
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

-- build(views, r, is_hired) -> { [character_id] = true }
-- A target is a party view whose canonical offline id is a PRESENT member in roster.match(r, views).found (so not
-- ambiguous), whose character_id is an integer and not ids.MAIN_PAWN, and for which is_hired(character_id) == true
-- (is_hired is only called for those; it wraps PawnUtil.isSubPawn in the glue). r nil (slot unknown) or LOCKED ->
-- {}. READ_ONLY -> its present members. Away and returning members are never targets.
function M.build(views, r, is_hired)
    local set = {}
    local found = roster.match(r, views)
    for _, view in ipairs(views) do
        local id = roster.canonical_id(view.offline_id)
        local member = id and found[id] == view and roster.find(r, id) or nil
        local cid = slot.to_int(view.character_id)
        if member and member.status == roster.PRESENT and cid ~= nil and cid ~= ids.MAIN_PAWN
            and is_hired(cid) == true then
            set[cid] = true
        end
    end
    return set
end

return M
