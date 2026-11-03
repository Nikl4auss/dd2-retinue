-- Decides the CharacterID rewrite for the ExpDispenser hooks. Pure: no REFramework globals.
local ids = require("Retinue.ids")

local M = {}

-- Returns the ID to write into the CharacterID argument, or nil to leave the args as passed.
-- state = { enabled = bool, available = bool, targets = { [id] = true } }
function M.rewrite_id(id, state)
    if state.enabled and state.available and state.targets[id] then
        return ids.MAIN_PAWN
    end
    return nil
end

return M
