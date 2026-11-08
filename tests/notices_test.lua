local notices = require("Retinue.notices")

assert(notices.HOLD_SECONDS == 3 and notices.SETTLE_SECONDS == 1)

local function mine() return true end
local function not_mine() return false end

local function new() return notices.new(3, 1) end

-- nothing queued: nothing, however long
do
    local q = new()
    q:sync(1)
    assert(q:step(0, true, mine) == nil and q:step(100, true, mine) == nil)
end

-- the settle: a notice shows after can_show held for 1 s; the deadline is now + 3
do
    local q = new()
    q:sync(1)
    q:push("one")
    assert(q:step(0, true, mine) == nil)
    assert(q:step(0.9, true, mine) == nil)
    local a, text = q:step(1, true, mine)
    assert(a == "show" and text == "one")
    assert(q:step(3.9, true, mine) == nil) -- before the deadline (1 + 3)
    assert(select(1, q:step(4, true, mine)) == "hide")
    assert(q:step(5, true, mine) == nil)
end

-- deferred while can_show is false (it never shows, however long)
do
    local q = new()
    q:sync(1)
    q:push("one")
    for now = 0, 20 do assert(q:step(now, false, mine) == nil) end
    assert(q:step(21, true, mine) == nil) -- the settle starts when it turns true
    assert(q:step(22, true, mine) == "show")
end

-- a 0.5 s gap in can_show does not show; a break restarts the settle
do
    local q = new()
    q:sync(1)
    q:push("one")
    assert(q:step(0, true, mine) == nil)
    assert(q:step(0.8, true, mine) == nil)
    assert(q:step(0.9, false, mine) == nil) -- the break
    assert(q:step(1.4, true, mine) == nil) -- 0.5 s later: back, settle restarts here
    assert(q:step(2.3, true, mine) == nil)
    local a = q:step(2.4, true, mine)
    assert(a == "show")
end

-- one at a time, oldest first; the next one gets its own settle after the hide
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:push("two")
    q:step(0, true, mine)
    local a, t = q:step(1, true, mine)
    assert(a == "show" and t == "one")
    assert(q:step(2, true, mine) == nil and q:step(3.9, true, mine) == nil) -- two waits while one shows
    assert(select(1, q:step(4, true, mine)) == "hide")
    assert(q:step(4.5, true, mine) == nil)
    assert(q:step(5.4, true, mine) == nil)
    a, t = q:step(5.5, true, mine)
    assert(a == "show" and t == "two")
    assert(select(1, q:step(8.5, true, mine)) == "hide")
end

-- closing does not depend on can_show
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:step(0, true, mine)
    q:step(1, true, mine)
    assert(q:step(2, false, mine) == nil)
    assert(select(1, q:step(4, false, mine)) == "hide")
end

-- hide only when mine: is_mine is asked at the deadline with the text; step returns "hide", text
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:step(0, true, mine)
    q:step(1, true, mine)
    local calls = {}
    local function probe(text) calls[#calls + 1] = text; return false end
    assert(q:step(2, true, probe) == nil and #calls == 0) -- before the deadline: not asked
    assert(q:step(4, true, probe) == nil and #calls == 1 and calls[1] == "one") -- proven not ours: showing ends
    assert(q:step(5, true, probe) == nil and #calls == 1) -- not asked again
    q:push("two")
    q:step(5, true, mine)
    q:step(6, true, mine) -- shows at once, deadline 9
    local a, t = q:step(9, true, mine)
    assert(a == "hide" and t == "two")
end

-- an unreadable is_mine (nil) keeps showing and asks again; hide still needs true
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:push("two")
    q:step(0, true, mine)
    q:step(1, true, mine)
    local reads = { nil, nil, true }
    local n = 0
    local function flaky() n = n + 1; return reads[n] end
    assert(q:step(4, true, flaky) == nil and n == 1)
    assert(q:step(4.5, true, flaky) == nil and n == 2)
    local a, t = q:step(5, true, flaky) -- true
    assert(a == "hide" and t == "one" and n == 3)
end

-- reopen: a failed hide is retried at the next step
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:step(0, true, mine)
    q:step(1, true, mine)
    local a, t = q:step(4, true, mine)
    assert(a == "hide" and t == "one")
    q:reopen(t, 4)
    a, t = q:step(4.1, false, mine) -- closing does not depend on can_show
    assert(a == "hide" and t == "one")
    assert(q:step(4.2, true, mine) == nil)
end

-- a notice the game closed makes room for the next
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:push("two")
    q:step(0, true, mine)
    q:step(1, true, mine)
    assert(q:step(4, true, not_mine) == nil)
    q:step(4.5, true, mine)
    local a, t = q:step(5.5, true, mine)
    assert(a == "show" and t == "two")
end

-- sync: a new generation drops what waits, a notice on screen stays and keeps its deadline
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:push("two")
    q:step(0, true, mine)
    q:step(1, true, mine) -- one shows, deadline 4
    q:sync(1)
    q:push("three")
    q:sync(2) -- drops two and three
    assert(q:step(3.9, true, mine) == nil)
    assert(select(1, q:step(4, true, mine)) == "hide")
    assert(q:step(10, true, mine) == nil and q:step(20, true, mine) == nil)
    q:push("four") -- pushed in the new generation
    q:step(21, true, mine)
    local a, t = q:step(22, true, mine)
    assert(a == "show" and t == "four")
end

-- sync restarts a settle in progress
do
    local q = new()
    q:sync(1)
    q:push("one")
    q:step(0, true, mine)
    q:sync(2)
    q:push("two")
    assert(q:step(1, true, mine) == nil)
    local a, t = q:step(2, true, mine)
    assert(a == "show" and t == "two")
end

-- pop: oldest first, nil when empty
do
    local q = new()
    q:push("one")
    q:push("two")
    assert(q:pop() == "one" and q:pop() == "two" and q:pop() == nil)
end

-- once: the first ready call of each generation
do
    local o = notices.new_once()
    assert(o:due(1, false) == false)
    assert(o:due(1, true) == true)
    assert(o:due(1, true) == false)
    assert(o:due(1, false) == false)
    assert(o:due(2, false) == false)
    assert(o:due(2, true) == true)
    assert(o:due(2, true) == false)
    assert(o:due(3, true) == true)
end

-- drive: a fake screen records the game calls
local function fake_screen(opts)
    opts = opts or {}
    local sc = { resolved = true, available = true, calls = {}, logged = {}, busy_now = false, mine = true }
    function sc.busy() sc.calls[#sc.calls + 1] = "busy"; return sc.busy_now end
    function sc.is_mine(text) sc.calls[#sc.calls + 1] = "is_mine"; return sc.mine end
    function sc.show(text)
        if not sc.available then sc.logged[#sc.logged + 1] = text; return end
        sc.calls[#sc.calls + 1] = "show:" .. text
        if sc.show_throws then sc.available = false end -- as the glue does; the panel may be up
    end
    function sc.hide()
        sc.calls[#sc.calls + 1] = "hide"
        if sc.hide_fails > 0 then sc.hide_fails = sc.hide_fails - 1; return false end
        return true
    end
    sc.hide_fails = 0
    return sc
end

-- drive: show after the settle, hide at the deadline, only in the world and when not busy
do
    local q, sc = new(), fake_screen()
    q:sync(1)
    q:push("one")
    notices.drive(q, sc, 0, false) -- out of the world: busy is not even asked
    assert(#sc.calls == 0)
    notices.drive(q, sc, 1, true)
    sc.busy_now = true
    notices.drive(q, sc, 2.5, true)
    assert(q.showing == nil)
    sc.busy_now = false
    notices.drive(q, sc, 3, true)
    assert(q.showing == nil)
    notices.drive(q, sc, 4, true)
    assert(sc.calls[#sc.calls] == "show:one")
    local shows = 0
    for _, c in ipairs(sc.calls) do if c == "show:one" then shows = shows + 1 end end
    assert(shows == 1)
    notices.drive(q, sc, 7, true)
    assert(sc.calls[#sc.calls] == "hide")
end

-- drive: a screen that cannot show only logs the texts, oldest first, and never calls the game
do
    local q, sc = new(), fake_screen()
    sc.resolved, sc.available = false, false
    q:sync(1)
    q:push("one")
    q:push("two")
    notices.drive(q, sc, 0, true)
    assert(#sc.calls == 0 and #sc.logged == 2 and sc.logged[1] == "one" and sc.logged[2] == "two")
    notices.drive(q, sc, 100, true)
    assert(#sc.calls == 0 and #sc.logged == 2)
end

-- drive: a hide that failed is retried at the next tick until it works
do
    local q, sc = new(), fake_screen()
    sc.hide_fails = 2
    q:sync(1)
    q:push("one")
    notices.drive(q, sc, 0, true)
    notices.drive(q, sc, 1, true) -- shows, deadline 4
    notices.drive(q, sc, 4, true)
    notices.drive(q, sc, 4.1, true)
    notices.drive(q, sc, 4.2, true)
    local hides = 0
    for _, c in ipairs(sc.calls) do if c == "hide" then hides = hides + 1 end end
    assert(hides == 3)
    notices.drive(q, sc, 4.3, true)
    for _, c in ipairs(sc.calls) do if c == "hide" then hides = hides - 1 end end
    assert(hides == 0 and q.showing == nil) -- no fourth hide
end

-- drive: a show that threw (the screen is not available any more) still closes the panel, and logs later texts
do
    local q, sc = new(), fake_screen()
    sc.show_throws = true
    q:sync(1)
    q:push("one")
    q:push("two")
    notices.drive(q, sc, 0, true)
    notices.drive(q, sc, 1, true) -- show:one throws, available false
    assert(not sc.available and q.showing == "one")
    notices.drive(q, sc, 2, true) -- "two" is logged, not shown
    assert(#sc.logged == 1 and sc.logged[1] == "two")
    notices.drive(q, sc, 4, true)
    assert(sc.calls[#sc.calls] == "hide" and q.showing == nil)
end

-- drive: the notice is still closed when is_mine cannot tell for a while
do
    local q, sc = new(), fake_screen()
    q:sync(1)
    q:push("one")
    notices.drive(q, sc, 0, true)
    notices.drive(q, sc, 1, true)
    sc.mine = nil
    notices.drive(q, sc, 4, true)
    notices.drive(q, sc, 10, true)
    assert(q.showing == "one" and sc.calls[#sc.calls] == "is_mine")
    sc.mine = true
    notices.drive(q, sc, 11, true)
    assert(sc.calls[#sc.calls] == "hide")
end

print("notices_test ok")

-- drive: its result names what happened, for the log; a notice proven not ours at the deadline is "gone", not hidden
do
    local q, sc = new(), fake_screen()
    q:sync(1)
    q:push("one")
    assert(notices.drive(q, sc, 0, true) == nil)
    local a, t = notices.drive(q, sc, 1, true)
    assert(a == "show" and t == "one")
    assert(notices.drive(q, sc, 2, true) == nil)
    sc.mine = false
    a, t = notices.drive(q, sc, 4, true)
    assert(a == "gone" and t == "one" and sc.calls[#sc.calls] == "is_mine")
    assert(notices.drive(q, sc, 5, true) == nil)
    q:push("two")
    sc.mine = true
    notices.drive(q, sc, 5, true)
    notices.drive(q, sc, 6, true)
    a, t = notices.drive(q, sc, 9, true)
    assert(a == "hide" and t == "two")
end
