-- confirm.lua: the answer of one open dialog, step by step.
local confirm = require("Retinue.confirm")

local TEXT = "Release Ana? Their progress will be lost."
local function w(over)
    local t = { shown = true, no_button = false, text = TEXT, ret = 0 }
    for k, v in pairs(over or {}) do t[k] = v end
    return t
end

assert(confirm.SHOW_SECONDS == 2)

-- yes and no: seen first (ret 0), then the pick
do
    local c = confirm.new(TEXT, 10)
    assert(c.text == TEXT and c.opened == 10 and c.seen == false)
    assert(c:step(10.1, w()) == nil and c.seen == true)
    assert(c:step(10.2, w()) == nil)
    assert(c:step(10.3, w{ ret = 1 }) == "yes")
    c = confirm.new(TEXT, 10)
    assert(c:step(10.1, w()) == nil)
    assert(c:step(10.2, w{ ret = 2 }) == "no")
end

-- the answer is read in the frame the dialog is still shown (and just as well once it is closed)
do
    local c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(0.2, w{ ret = 1, shown = true }) == "yes")
    c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(0.2, w{ ret = 2, shown = false }) == "no")
end

-- a 1 or 2 left by an older dialog never answers: the dialog must first be seen with ret 0
do
    local c = confirm.new(TEXT, 0)
    assert(c:step(0.1, w{ ret = 1 }) == nil and c.seen == false)
    assert(c:step(0.2, w{ ret = 2 }) == nil and c.seen == false)
    assert(c:step(0.3, w()) == nil and c.seen == true)
    assert(c:step(0.4, w{ ret = 2 }) == "no")
end

-- not ours (hidden, a no-button one, another text) is not seen
do
    for _, over in ipairs({ { shown = false }, { no_button = true }, { text = "other" }, { text = false } }) do
        local c = confirm.new(TEXT, 0)
        assert(c:step(0.1, w(over)) == nil and c.seen == false)
    end
    local c = confirm.new(TEXT, 0)
    assert(c:step(0.1, nil) == nil and c.seen == false)
end

-- never shown: 2 seconds without being seen
do
    local c = confirm.new(TEXT, 5)
    assert(c:step(6.9, nil) == nil)
    assert(c:step(6.9, w{ shown = false }) == nil)
    assert(c:step(7, w{ shown = false }) == "never_shown")
    c = confirm.new(TEXT, 5)
    assert(c:step(7.5, nil) == "never_shown")
    -- seen in time: no longer a candidate
    c = confirm.new(TEXT, 5)
    assert(c:step(6.9, w()) == nil)
    assert(c:step(9, w()) == nil)
end

-- gone: closed without an answer, or replaced by another text
do
    local c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(0.2, w{ shown = false }) == "gone")
    c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(0.2, w{ text = "Overwrite the save?", ret = 1 }) == "gone") -- another dialog's answer is not ours
    c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(0.2, w{ text = false }) == "gone")
end

-- unreadable once seen: keep waiting, however long
do
    local c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(1, nil) == nil)
    assert(c:step(5, nil) == nil)
    assert(c:step(10.9, nil) == nil) -- 9.9 s of nil
    assert(c:step(11, w{ ret = 1 }) == "yes")
    -- the total time is not capped: a readable dialog can sit for minutes
    c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    for t = 1, 300, 5 do assert(c:step(t, w()) == nil) end
    assert(c:step(400, w{ ret = 2 }) == "no")
end

-- unreadable for UNREADABLE_SECONDS in a row, once seen: gone; any readable read ends the run
do
    assert(confirm.UNREADABLE_SECONDS == 10)
    local c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(1, nil) == nil)
    assert(c:step(10.9, nil) == nil)
    assert(c:step(11, nil) == "gone")
    c = confirm.new(TEXT, 0)
    c:step(0.1, w())
    assert(c:step(1, nil) == nil)
    assert(c:step(9, nil) == nil)
    assert(c:step(9.5, w()) == nil) -- readable: the run ends
    assert(c:step(10, nil) == nil)
    assert(c:step(19.9, nil) == nil)
    assert(c:step(20, nil) == "gone")
end

print("confirm_test ok")
