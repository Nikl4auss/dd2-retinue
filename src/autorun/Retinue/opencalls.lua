-- Open core calls (checkLevelUp / addJobPoint) for the notification swap-back. Pure: no REFramework globals.
--
-- One frame per core call, pushed by its pre-hook whether or not it rewrote; `real` is the hired pawn's ID
-- and is set only when it did. The swap looks only at the top frame, so a main-pawn or toggle-off call (real =
-- nil) always shadows any stale rewritten frame below it.
local ids = require("Retinue.ids")

local M = {}
M.MAX_DEPTH = 64

local Stack = {}
Stack.__index = Stack

-- Returns frame, overflowed. At MAX_DEPTH the stack is cleared first (defensive) and overflowed is true.
function Stack:push(key)
    local overflowed = false
    if #self.frames >= M.MAX_DEPTH then
        self.frames = {}
        overflowed = true
    end
    local frame = { key = key, real = nil }
    self.frames[#self.frames + 1] = frame
    return frame, overflowed
end

-- Removes the innermost frame with this key and every frame above it (stale frames whose post never ran).
function Stack:pop(key)
    for i = #self.frames, 1, -1 do
        if self.frames[i].key == key then
            for j = #self.frames, i, -1 do self.frames[j] = nil end
            return
        end
    end
end

function Stack:clear() self.frames = {} end

function Stack:depth() return #self.frames end

-- The top frame's real ID iff id is the main pawn's; else nil.
function Stack:swap_id(id)
    if id ~= ids.MAIN_PAWN then return nil end
    local top = self.frames[#self.frames]
    return top and top.real or nil
end

function M.new()
    return setmetatable({ frames = {} }, Stack)
end

return M
