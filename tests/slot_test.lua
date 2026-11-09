local slot = require("Retinue.slot")

-- unit_of: global slot -> unit by floor division
do
    local want = { [0] = 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2 }
    for g = 0, 14 do assert(slot.unit_of(g, 5) == want[g], "unit_of " .. g) end
    assert(slot.unit_of(9, 5) == 1 and slot.unit_of(8, 5) == 1 and slot.unit_of(3, 5) == 0)
    assert(slot.unit_of(-1, 5) == nil)
    assert(slot.unit_of(nil, 5) == nil and slot.unit_of("9", 5) == nil and slot.unit_of({}, 5) == nil)
    assert(slot.unit_of(9.5, 5) == nil and slot.unit_of(0 / 0, 5) == nil and slot.unit_of(math.huge, 5) == nil)
    assert(slot.unit_of(9.0, 5) == 1 and math.type(slot.unit_of(9.0, 5)) == "integer")
    assert(slot.unit_of(9, 5.0) == 1)
    assert(slot.unit_of(9, 0) == nil and slot.unit_of(9, nil) == nil and slot.unit_of(9, -5) == nil)
    assert(slot.unit_of(9, 5.5) == nil and slot.unit_of(9, "5") == nil)
end

-- classify
do
    assert(slot.classify("NewGame") == slot.NEW_PLAYTHROUGH)
    assert(slot.classify("RedoNewGame") == slot.NEW_PLAYTHROUGH)
    assert(slot.classify("RedoNewGameSkip") == slot.NG_PLUS)
    for _, n in ipairs({ "Latest", "Base", "SystemMenuSave", "ExitGame" }) do
        assert(slot.classify(n) == slot.LOAD, n)
    end
    assert(slot.classify(nil) == nil and slot.classify(3) == nil)
end

-- fallback: LastLoadedSlot and UnitNumber must agree
do
    assert(slot.fallback(4, 0, 5) == 0)
    assert(slot.fallback(9, 1, 5) == 1)
    assert(slot.fallback(9, 1.0, 5) == 1)
    assert(slot.fallback(4, 1, 5) == nil)
    assert(slot.fallback(0, 0, 5) == 0)
    assert(slot.fallback(nil, 0, 5) == nil and slot.fallback(4, nil, 5) == nil and slot.fallback(4, 0, nil) == nil)
    assert(slot.fallback(-1, 0, 5) == nil and slot.fallback(4, -1, 5) == nil)
    assert(slot.fallback(4, 0, 0) == nil)
end

-- dir, archive_name, archive_dir
do
    assert(slot.dir(0) == "Retinue/slots/1" and slot.dir(2) == "Retinue/slots/3")
    local t = { year = 2026, month = 1, day = 5, hour = 3, min = 4, sec = 9 }
    assert(slot.archive_name(t) == "archive-20260105-030409")
    assert(slot.archive_dir(1, t) == "Retinue/slots/2/archive-20260105-030409")
    assert(slot.archive_name({ year = 2026, month = 11, day = 25, hour = 13, min = 14, sec = 59 }) == "archive-20261125-131459")
end

-- label
do
    assert(slot.label(0) == "Slot 1" and slot.label(2) == "Slot 3")
    assert(slot.label(nil) == "Slot unknown")
end

-- session: the experiment's real sequences
do
    local s = slot.new_session()
    assert(s.unit == nil and s.source == nil and s.seen == false and s.last_start == nil and s.starts == 0)

    -- system-menu load: start SystemMenuSave, then load 9 -> Slot 2
    s:on_start_request("SystemMenuSave", 0)
    assert(s.seen and s.unit == nil and s.last_start.name == "SystemMenuSave" and s.last_start.kind == slot.LOAD)
    s:on_load_request(9, 5)
    assert(s.unit == 1 and s.source == "load")

    -- continue: Latest + load 0 -> unit 0 (a switch never shows the previous unit in between)
    s:on_start_request("Latest", 1)
    assert(s.unit == nil and s.source == nil)
    s:on_load_request(0, 5)
    assert(s.unit == 0 and s.source == "load" and s.last_start.kind == slot.LOAD)

    -- death reload: load without a start
    s:on_load_request(0, 5)
    assert(s.unit == 0 and s.source == "load" and s.starts == 2)

    -- new game: unit from UnitNumber
    s:on_start_request("NewGame", 2)
    assert(s.unit == 2 and s.source == "new_game" and s.last_start.kind == slot.NEW_PLAYTHROUGH)

    -- redo new game: unit from the load that follows
    s:on_start_request("RedoNewGame", 2)
    assert(s.unit == nil and s.last_start.kind == slot.NEW_PLAYTHROUGH)
    s:on_load_request(8, 5)
    assert(s.unit == 1 and s.source == "load")

    -- NG+
    s:on_start_request("RedoNewGameSkip", 0)
    assert(s.last_start.kind == slot.NG_PLUS)
    s:on_load_request(3, 5)
    assert(s.unit == 0 and s.source == "load")

    assert(s.starts == 5)
end

-- NewGame with a bad UnitNumber leaves the unit unknown
do
    local s = slot.new_session()
    s:on_start_request("NewGame", nil)
    assert(s.unit == nil and s.source == nil and s.last_start.kind == slot.NEW_PLAYTHROUGH)
    s:on_start_request("NewGame", -1)
    assert(s.unit == nil and s.source == nil)
    s:on_start_request("NewGame", 0)
    assert(s.unit == 0 and s.source == "new_game")
end

-- a start alone (not NewGame) clears a previous unit
do
    local s = slot.new_session()
    s:on_load_request(9, 5)
    assert(s.unit == 1)
    s:on_start_request("ExitGame", 1)
    assert(s.unit == nil and s.source == nil and s.last_start.kind == slot.LOAD)
end

-- load with an unreadable SLOT_PER_UNIT or global slot -> unknown
do
    local s = slot.new_session()
    s:on_load_request(9, nil)
    assert(s.unit == nil and s.source == nil and s.seen)
    s:on_load_request(9, 5)
    assert(s.unit == 1)
    s:on_load_request(nil, 5)
    assert(s.unit == nil and s.source == nil)
end

-- unreadable start name: unit nil, kind nil, still counted
do
    local s = slot.new_session()
    s:on_load_request(9, 5)
    s:on_start_request(nil, 1)
    assert(s.unit == nil and s.source == nil and s.starts == 1)
    assert(s.last_start.name == nil and s.last_start.kind == nil)
end

-- on_world: fallback only before any request, and only when the values agree
do
    local s = slot.new_session()
    s:on_world(4, 0, 5)
    assert(s.unit == 0 and s.source == "fallback" and s.seen == false)
    s:on_world(9, 1, 5)
    assert(s.unit == 1 and s.source == "fallback")
    s:on_world(9, 0, 5) -- disagree: unknown again
    assert(s.unit == nil and s.source == nil)
    s:on_world(nil, nil, nil)
    assert(s.unit == nil and s.source == nil)

    -- after any request the fallback is off for good
    s:on_world(4, 0, 5)
    assert(s.unit == 0)
    s:on_load_request(9, 5)
    s:on_world(4, 0, 5)
    assert(s.unit == 1 and s.source == "load")

    local s2 = slot.new_session()
    s2:on_start_request("Latest", 0)
    s2:on_world(4, 0, 5)
    assert(s2.unit == nil and s2.source == nil)
end

-- starts counts start requests only
do
    local s = slot.new_session()
    s:on_load_request(0, 5)
    assert(s.starts == 0)
    s:on_start_request("Latest", 0)
    s:on_start_request("Latest", 0)
    assert(s.starts == 2)
end

-- loads counts load requests only; a death reload (load without start) of the same unit still counts
do
    local s = slot.new_session()
    assert(s.loads == 0)
    s:on_start_request("Latest", 0)
    assert(s.loads == 0)
    s:on_load_request(0, 5)
    s:on_load_request(0, 5)
    assert(s.loads == 2 and s.unit == 0 and s.source == "load")
end

-- take_archive: a due archive hands out its unit once; archives counts takes
do
    local s = slot.new_session()
    assert(s.archive_pending == false and s.archives == 0 and s:take_archive() == nil)

    -- NewGame with a unit: after its first save
    s:on_start_request("NewGame", 1)
    assert(s.archive_pending == false)
    s:on_save_request(5, 5)
    assert(s.archive_pending == true)
    assert(s:take_archive() == 1 and s.archives == 1)
    assert(s.archive_pending == false and s:take_archive() == nil and s.archives == 1)

    -- RedoNewGame: nothing is due until decide_restart says so, and nothing to hand out until the load names the unit
    s:on_start_request("RedoNewGame", 0)
    assert(s.archive_pending == false and s.restart_pending == true and s.unit == nil)
    assert(s:take_archive() == nil and s.archives == 1)
    s:on_load_request(9, 5)
    assert(s:take_archive() == nil and s.archives == 1)
    assert(s:decide_restart(false, true, 0) == "archived")
    assert(s:take_archive() == 1 and s.archives == 2)
    assert(s:take_archive() == nil and s.archives == 2)
end

-- NewGame without a unit: flag false, and a later load gives nothing
do
    local s = slot.new_session()
    s:on_start_request("NewGame", nil)
    assert(s.archive_pending == false)
    s:on_start_request("NewGame", -1)
    assert(s.archive_pending == false and s.first_save_pending == false)
    s:on_load_request(4, 5)
    assert(s:take_archive() == nil and s.archives == 0)
end

-- no archive for NG+, a plain load, a base start, an unreadable name
do
    for _, name in ipairs({ "RedoNewGameSkip", "Latest", "Base", "SystemMenuSave" }) do
        local s = slot.new_session()
        s:on_start_request(name, 0)
        assert(s.archive_pending == false, name)
        s:on_load_request(4, 5)
        assert(s:take_archive() == nil and s.archives == 0, name)
    end
    local s = slot.new_session()
    s:on_start_request(nil, 0)
    s:on_load_request(4, 5)
    assert(s.archive_pending == false and s:take_archive() == nil)
end

-- a later start clears a pending archive: a restart whose load never came cannot archive a slot loaded afterwards
do
    local s = slot.new_session()
    s:on_start_request("RedoNewGame", 0)
    s:on_start_request("Latest", 0)
    assert(s.archive_pending == false and s.restart_pending == false)
    s:on_load_request(9, 5)
    assert(s:take_archive() == nil and s.archives == 0)
    assert(s:decide_restart(false, true, 0) == nil)

    -- a load alone (death reload) does not set it either
    s:on_load_request(9, 5)
    assert(s:take_archive() == nil)
end

-- NewGame: nothing until the first save of its unit, and no roster active meanwhile
do
    local s = slot.new_session()
    s:on_load_request(9, 5)
    assert(s:roster_unit() == 1)
    s:on_start_request("NewGame", 1)
    assert(s.first_save_pending and not s.archive_pending)
    assert(s.unit == 1 and s:roster_unit() == nil and s:take_archive() == nil and s.archives == 0)
    -- the system save and another unit's save are not it
    assert(s:on_save_request(-1, 5) == false and s:on_save_request(0, 5) == false and s:on_save_request(9, nil) == false)
    assert(s.first_save_pending and s:take_archive() == nil)
    -- nor is the copy a conversion writes at the title (a save of the unit, with no start or load before it)
    assert(s:on_save_request(8, 5) == false and s.first_save_pending and s:take_archive() == nil)
    -- every other type of the unit counts: the first save wrote 6, 9, 5 here
    assert(s:on_save_request(6, 5) == true)
    assert(s.archive_pending and not s.first_save_pending and s:roster_unit() == 1)
    assert(s:take_archive() == 1 and s.archives == 1 and s:take_archive() == nil)
    -- later saves do nothing
    assert(s:on_save_request(9, 5) == false and s:take_archive() == nil and s.archives == 1)
end

-- a NewGame given up: a load or another start ends the wait, nothing archived, the roster is active again
do
    local s = slot.new_session()
    s:on_start_request("NewGame", 1)
    s:on_load_request(9, 5)
    assert(not s.first_save_pending and s:roster_unit() == 1 and s:take_archive() == nil)
    assert(s:on_save_request(9, 5) == false and s:take_archive() == nil and s.archives == 0)

    s:on_start_request("NewGame", 1)
    s:on_start_request("Latest", 1)
    assert(not s.first_save_pending)
    s:on_load_request(9, 5)
    assert(s:on_save_request(9, 5) == false and s:take_archive() == nil)

    -- the next session sees nothing of it: a new session has no wait
    assert(slot.new_session():on_save_request(9, 5) == false)
end

-- RedoNewGame does not wait for a save, and NG+ never archives on one
do
    local s = slot.new_session()
    s:on_start_request("RedoNewGame", 1)
    s:on_load_request(8, 5)
    assert(not s.first_save_pending and s:roster_unit() == nil and s:take_archive() == nil)
    assert(s:decide_restart(false, true, 0) == "archived")
    assert(not s.first_save_pending and s:roster_unit() == 1 and s:take_archive() == 1)

    s = slot.new_session()
    s:on_start_request("RedoNewGameSkip", 0)
    s:on_load_request(3, 5)
    assert(s:on_save_request(1, 5) == false and s:take_archive() == nil and s:roster_unit() == 0)
end

-- the wait is assigned before the unit, the archive flag last
do
    local s, order = slot.new_session(), {}
    local spy = setmetatable({}, { __index = s, __newindex = function(_, k, v)
        order[#order + 1] = k
        s[k] = v
    end })
    spy:on_start_request("NewGame", 1)
    local at = {}
    for i, k in ipairs(order) do at[k] = i end
    assert(at.first_save_pending < at.unit and at.unit < at.archive_pending)
    order = {}
    getmetatable(spy).__newindex = function(_, k, v) order[#order + 1] = k; s[k] = v end
    assert(spy:on_save_request(9, 5) == true)
    assert(order[1] == "archive_pending" and order[2] == "first_save_pending")
    -- a load: the wait ends after the unit
    s = slot.new_session()
    s:on_start_request("NewGame", 1)
    order = {}
    spy = setmetatable({}, { __index = s, __newindex = function(_, k, v) order[#order + 1] = k; s[k] = v end })
    spy:on_load_request(9, 5)
    assert(order[#order] == "first_save_pending")
end

-- NewGame over a cleared slot, then a conversion at the title and NG+: the conversion's copy does not archive
do
    local s = slot.new_session()
    s:on_start_request("NewGame", 0)
    assert(s:on_save_request(3, 5) == false)
    s:on_start_request("RedoNewGameSkip", 0)
    s:on_load_request(3, 5)
    assert(s:take_archive() == nil and s.archives == 0 and s:roster_unit() == 0)
end

-- the flag is assigned last: the frame loop must never see it set with the previous unit
do
    local s, order = slot.new_session(), {}
    local spy = setmetatable({}, { __index = s, __newindex = function(_, k, v)
        order[#order + 1] = k
        s[k] = v
    end })
    spy:on_start_request("RedoNewGame", 0)
    assert(order[#order] == "archive_pending")

    -- the restart flag too: after the unit and the source, before the archive flag
    s, order = slot.new_session(), {}
    spy = setmetatable({}, { __index = s, __newindex = function(_, k, v)
        order[#order + 1] = k
        s[k] = v
    end })
    spy:on_start_request("RedoNewGame", 0)
    local at = {}
    for i, k in ipairs(order) do at[k] = i end
    assert(at.unit < at.restart_pending and at.source < at.restart_pending and at.restart_pending < at.archive_pending)

    -- a decision flags the archive before it ends the wait
    s = slot.new_session()
    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(9, 5)
    order = {}
    spy = setmetatable({}, { __index = s, __newindex = function(_, k, v)
        order[#order + 1] = k
        s[k] = v
    end })
    assert(spy:decide_restart(false, true, 0) == "archived")
    assert(order[#order - 1] == "archive_pending" and order[#order] == "restart_pending")
end

-- decide_restart: a restart over a cleared slot keeps the roster (NG+), over a slot not cleared it archives once
do
    local s = slot.new_session()
    s:on_load_request(4, 5)
    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(4, 5)
    assert(s.restart_pending and s:roster_unit() == nil and s:take_archive() == nil)
    assert(s:decide_restart(true, true, 100) == "kept")
    assert(not s.restart_pending and not s.archive_pending and s:roster_unit() == 0)
    assert(s:take_archive() == nil and s.archives == 0)
    assert(s:decide_restart(true, true, 101) == nil) -- nothing pending any more

    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(9, 5)
    assert(s:roster_unit() == nil)
    assert(s:decide_restart(false, true, 100) == "archived")
    assert(not s.restart_pending and s:roster_unit() == 1)
    assert(s:take_archive() == 1 and s.archives == 1 and s:take_archive() == nil)

    -- restart data true and a clear flag that is not a boolean: fail closed
    for _, bad in ipairs({ "nil", "number" }) do
        s = slot.new_session()
        s:on_start_request("RedoNewGame", 0)
        s:on_load_request(4, 5)
        local clear = nil
        if bad == "number" then clear = 1 end
        assert(s:decide_restart(clear, true, 0) == "archived")
        assert(s:take_archive() == 0 and s.archives == 1, bad)
    end
end

-- decide_restart: no load request yet (unit nil) -> nil, no timer, however late
do
    local s = slot.new_session()
    s:on_start_request("RedoNewGame", 0)
    assert(s:decide_restart(true, true, 0) == nil and s.restart_since == nil)
    assert(s:decide_restart(nil, nil, 1000) == nil and s.restart_since == nil)
    assert(s.restart_pending and not s.archive_pending and s:roster_unit() == nil)
    s:on_load_request(4, 5)
    assert(s:decide_restart(nil, nil, 1001) == nil and s.restart_since == 1001) -- the timer starts with the unit
    assert(s:decide_restart(true, true, 1002) == "kept")
end

-- decide_restart: without the restart flag the wait ends in RESTART_WAIT seconds with an archive
do
    assert(slot.RESTART_WAIT == 10)
    for _, rd in ipairs({ "nil", "false" }) do
        local s = slot.new_session()
        s:on_start_request("RedoNewGame", 0)
        s:on_load_request(4, 5)
        local restart_data = nil
        if rd == "false" then restart_data = false end
        assert(s:decide_restart(true, restart_data, 50) == nil and s.restart_since == 50)
        assert(s:decide_restart(true, restart_data, 59.9) == nil)
        assert(s.restart_pending and not s.archive_pending and s:roster_unit() == nil and s:take_archive() == nil)
        assert(s:decide_restart(true, restart_data, 60) == "timeout")
        assert(not s.restart_pending and s:roster_unit() == 0)
        assert(s:take_archive() == 0 and s.archives == 1 and s:take_archive() == nil, rd)
        assert(s:decide_restart(true, restart_data, 61) == nil)
    end
    -- the flags can arrive late, before the limit
    local s = slot.new_session()
    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(4, 5)
    assert(s:decide_restart(nil, nil, 0) == nil and s:decide_restart(true, true, 9) == "kept")
end

-- a later start or a new restart cancels the wait: nothing archived, the timer starts over
do
    local s = slot.new_session()
    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(4, 5)
    assert(s:decide_restart(nil, nil, 0) == nil)
    s:on_start_request("Latest", 0)
    s:on_load_request(4, 5)
    assert(not s.restart_pending and s:roster_unit() == 0)
    assert(s:decide_restart(nil, nil, 100) == nil and s:take_archive() == nil and s.archives == 0)

    s:on_start_request("RedoNewGame", 0)
    s:on_load_request(4, 5)
    assert(s:decide_restart(nil, nil, 100) == nil)
    s:on_start_request("RedoNewGame", 0)
    assert(s.restart_since == nil)
    s:on_load_request(4, 5)
    assert(s:decide_restart(nil, nil, 105) == nil and s.restart_since == 105)
    assert(s:decide_restart(nil, nil, 114.9) == nil and s:decide_restart(nil, nil, 115) == "timeout")
end

-- to_int: integral floats become integers, anything else nil
assert(math.type(slot.to_int(2.0)) == "integer" and slot.to_int(2.0) == 2)
assert(slot.to_int(2.5) == nil and slot.to_int("2") == nil and slot.to_int(nil) == nil)
