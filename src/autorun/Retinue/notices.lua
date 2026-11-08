-- The queue behind the native notices. Pure: no REFramework globals, so it runs under plain Lua in tests; the texts are
-- labels.lua, the game call is game/notice_screen.lua. The notice is a modal that shares the game's dialog widget
-- (findings 0009 P6): it may only be shown with nothing else up, and only closed while it is still ours. So the queue
-- decides nothing about the game: its caller says whether showing is safe (can_show) and whether the notice on screen
-- is still ours (is_mine), both read in the same game update that acts on the answer.
local M = {}

M.HOLD_SECONDS = 3
M.SETTLE_SECONDS = 1

-- new(hold_seconds, settle_seconds) -> queue: one notice at a time, oldest first.
local Queue = {}
Queue.__index = Queue

function M.new(hold_seconds, settle_seconds)
    return setmetatable({
        hold = hold_seconds, settle = settle_seconds,
        generation = nil, waiting = {}, showing = nil, deadline = nil, since = nil,
    }, Queue)
end

function Queue:push(text)
    self.waiting[#self.waiting + 1] = text
end

-- The oldest waiting text, removed; nil when none. For the caller that cannot show (it logs them instead).
function Queue:pop()
    return table.remove(self.waiting, 1)
end

-- A new generation (a load) drops what waits. A notice on screen stays: it still gets closed.
function Queue:sync(generation)
    if generation == self.generation then return end
    self.generation = generation
    self.waiting = {}
    self.since = nil
end

-- step(now, can_show, is_mine) -> nil | "show", text | "hide", text
--   Showing: nothing before the deadline. At the deadline is_mine(text) -> true: showing ends, "hide", text (the caller
--   hides, and calls reopen when that failed); false: showing ends (the game closed or replaced the notice, and hiding
--   would close its dialog); nil (unreadable): it keeps showing and is asked again at the next step. Closing does not
--   depend on can_show.
--   Not showing: can_show false restarts the settle (it bridges the gap of about 0.5 s between two cutscenes, and fades).
--   Something waiting and can_show true for `settle` seconds without a break -> "show", text, and the deadline is now + hold.
--   The notice counts as showing from the moment "show" is returned, even if the call then threw: the panel may be up.
function Queue:step(now, can_show, is_mine)
    if self.showing ~= nil then
        if now < self.deadline then return nil end
        local text = self.showing
        local mine = is_mine(text)
        if mine == nil then return nil end
        self.showing, self.deadline = nil, nil
        if mine == true then return "hide", text end
        return nil
    end
    if not can_show or #self.waiting == 0 then
        self.since = nil
        return nil
    end
    self.since = self.since or now
    if now < self.since + self.settle then return nil end
    local text = table.remove(self.waiting, 1)
    self.showing, self.deadline, self.since = text, now + self.hold, nil
    return "show", text
end

-- reopen(text, now): the hide of a notice failed; it is showing again, due at once, so the next step retries.
function Queue:reopen(text, now)
    self.showing, self.deadline = text, now
end

-- drive(queue, screen, now, in_world) -> nil | "show", text | "hide", text | "gone", text: one UpdateBehavior tick of the
-- notices, the part of Retinue.lua that is not wiring. The result is for the log: "gone" is a notice that was due to close
-- but was proven not ours any more, so it was left alone.
--   screen: game/notice_screen's object (.resolved .available busy() is_mine(text) show(text) hide() -> boolean).
--   Texts that cannot be shown (the screen is not available) go to screen.show, which logs them. A notice that is up is
--   closed whether or not the screen is still available: it only needs the methods to exist.
function M.drive(queue, screen, now, in_world)
    if not screen.available then
        local text = queue:pop()
        while text ~= nil do
            screen.show(text)
            text = queue:pop()
        end
    end
    local can_show = screen.available and in_world and not screen.busy()
    local was = queue.showing
    local action, text = queue:step(now, can_show, screen.is_mine)
    if action == "show" then
        screen.show(text)
    elseif action == "hide" then
        if not screen.hide() then queue:reopen(text, now) end
    elseif was ~= nil and queue.showing == nil then
        return "gone", was
    end
    return action, text
end

-- new_once() -> once: due(generation, ready) is true on the first ready call of each generation.
local Once = {}
Once.__index = Once

function M.new_once()
    return setmetatable({ generation = nil }, Once)
end

function Once:due(generation, ready)
    if not ready or generation == self.generation then return false end
    self.generation = generation
    return true
end

return M
