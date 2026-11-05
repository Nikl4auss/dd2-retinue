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
