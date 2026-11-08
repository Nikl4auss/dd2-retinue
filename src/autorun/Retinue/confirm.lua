-- The answer of one open Yes/No dialog, read frame by frame. Pure: the dialog's state comes in as a table, so it runs
-- under plain Lua in tests; game/confirm_dialog.lua reads it from the game.
local M = {}

-- How long the dialog may take to show before the confirm is given up.
M.SHOW_SECONDS = 2
-- How long the dialog may stay unreadable, once seen, before the confirm is given up. The total time is not capped: the
-- player may sit on the dialog for minutes.
M.UNREADABLE_SECONDS = 10

local Confirm = {}
Confirm.__index = Confirm

-- new(text, now) -> c. text: the main text the dialog was opened with; now: os.clock() at the request.
function M.new(text, now)
    return setmetatable({ text = text, opened = now, seen = false, unreadable_since = nil }, Confirm)
end

-- c:step(now, w) -> nil | "yes" | "no" | "gone" | "never_shown"
-- w: nil (unreadable) or { shown = bool, no_button = bool, text = string|nil, ret = integer|nil }, read in this callback.
-- nil asks again next frame (an unreadable dialog for UNREADABLE_SECONDS in a row, once seen, is "gone"); any other result ends the confirm.
function Confirm:step(now, w)
    if not self.seen then
        -- Ours is the one that is shown, with two buttons, our text and nothing answered yet. The widget keeps its text and
        -- its answer after a close, so ret must be 0 first: a 1 or 2 left by an older dialog never answers.
        if w and w.shown and not w.no_button and w.text == self.text and w.ret == 0 then
            self.seen = true
            return nil
        end
        if now - self.opened >= M.SHOW_SECONDS then return "never_shown" end
        return nil
    end
    if w == nil then
        -- Reads that stay nil would hold the confirm (and every notice) for good: a run of them gives it up.
        self.unreadable_since = self.unreadable_since or now
        if now - self.unreadable_since >= M.UNREADABLE_SECONDS then return "gone" end
        return nil
    end
    self.unreadable_since = nil
    if w.text ~= self.text then return "gone" end -- another dialog replaced ours
    -- The answer arrives before the close, so it is read before `shown`.
    if w.ret == 1 then return "yes" end
    if w.ret == 2 then return "no" end
    if not w.shown then return "gone" end
    return nil
end

return M
