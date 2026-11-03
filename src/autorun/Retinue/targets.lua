-- Which party pawns Retinue lifts. Pure: no REFramework globals, so it runs under plain Lua in tests.
local ids = require("Retinue.ids")

local M = {}

-- The single target predicate. M2 replaces this function to narrow targets to the roster.
-- id: u32 CharacterID; is_hired: function(id) -> boolean (wraps PawnUtil.isSubPawn in the glue).
-- is_hired is only called for IDs that are not the main pawn's.
function M.is_target(id, is_hired)
    return id ~= ids.MAIN_PAWN and is_hired(id) == true
end

-- party_ids: array of u32 CharacterIDs currently in PawnManager._PartyPawnList.
-- Returns a set { [id] = true } of targets. M.is_target is looked up at call time, so a replaced
-- predicate takes effect.
function M.build(party_ids, is_hired)
    local set = {}
    for _, id in ipairs(party_ids) do
        if M.is_target(id, is_hired) then set[id] = true end
    end
    return set
end

return M
