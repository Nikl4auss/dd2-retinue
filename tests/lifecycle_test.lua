local backup = require("Retinue.backup")
local lifecycle = require("Retinue.lifecycle")
local roster = require("Retinue.roster")

local A = "11111111-2222-3333-4444-555555555555"
local B = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
local X = "01234567-89ab-cdef-0123-456789abcdef"

local function snapshot(level, extra)
    local b = {
        version = 1, offline_id = A, name = "Ana", level = level or 27, exp = 1, extra_status_boost = 0, discipline = 0,
        increase_params = {}, culmative_exp = { 1 }, current_job = 5,
    }
    for _, k in ipairs(backup.INCREASE_KEYS) do b.increase_params[k] = 1 end
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

-- statuses: { [id] = status }; the roster holds Ana (A) and Bo (B) in that order unless `only` limits it.
local function setup(statuses, opts)
    opts = opts or {}
    local t = { lines = {}, reports = {}, queue = {}, order = {}, stores = {}, restores = {}, party_levels = {} }
    local members = {}
    for _, spec in ipairs({ { A, "Ana", 11 }, { B, "Bo", 12 } }) do
        local st = statuses[spec[1]]
        if st then
            members[#members + 1] = { offline_id = spec[1], name = spec[2], status = st, character_id = spec[3] }
        end
    end
    local retinue = {
        unit = 0, generation = 1, found = {}, ambiguous = {},
        roster = { mode = opts.mode or roster.OK, members = members, warnings = {} },
    }
    function retinue:mark_away(id)
        t.order[#t.order + 1] = "mark_away"
        return roster.mark_away(self.roster, id)
    end
    function retinue:mark_returning(id)
        t.order[#t.order + 1] = "mark_returning"
        return roster.mark_returning(self.roster, id)
    end
    function retinue:mark_present(id, cid)
        t.order[#t.order + 1] = "mark_present"
        return roster.mark_present(self.roster, id, cid)
    end
    t.retinue = retinue

    t.backups_by_id = {}
    t.notes = {}
    t.store_throws = false
    local backups = {}
    function backups.store(unit, m, snap)
        t.order[#t.order + 1] = "store"
        t.stores[#t.stores + 1] = { unit = unit, m = m, snap = snap }
        if t.store_throws then error("disk full") end
    end
    function backups.get(id) return t.backups_by_id[id] end
    function backups.note(id) return t.notes[id] end

    t.restore_results = {} -- [id] = function(view, b) -> result, detail
    t.read_result = nil
    local pawns = {}
    function pawns.restore(view, b)
        t.restores[#t.restores + 1] = view.name
        local f = t.restore_results[view.offline_id]
        if f then return f(view, b) end
        return "done"
    end
    function pawns.read(view)
        if t.read_throws then error("read boom") end
        if t.read_nil then return nil, t.read_nil end
        return t.read_result or t.backups_by_id[view.offline_id]
    end

    t.party = { failed = false, main = true, all_read = true }
    local party = { }
    setmetatable(party, { __index = function(_, k)
        if k == "failed" then return t.party.failed end
    end })
    function party.has_main_pawn() return t.party.main end
    function party.all_read() return t.party.all_read end
    function party.level(view) return t.party_levels[view.offline_id] end

    t.flow = lifecycle.new{
        retinue = retinue, backups = backups, pawns = pawns, party = party,
        drain = function()
            local q = t.queue
            t.queue = {}
            return q
        end,
        log_line = function(text) t.lines[#t.lines + 1] = text end,
        report = function(what, err) t.reports[#t.reports + 1] = { what = what, err = tostring(err) } end,
    }
    function t.view(id, cid)
        local name = id == A and "Ana" or "Bo"
        retinue.found[id] = { offline_id = id, name = name, character_id = cid or 100 }
        t.party_levels[id] = t.party_levels[id] or 5
    end
    function t.status(id) return roster.find(retinue.roster, id).status end
    function t.member(id) return roster.find(retinue.roster, id) end
    function t.push(e) t.queue[#t.queue + 1] = e end
    return t
end

local function dismiss(id, snap, gen) return { kind = "dismiss", id = id, generation = gen or 1, snapshot = snap } end
local function hire(id, gen) return { kind = "hire", id = id, generation = gen or 1 } end

-- dismiss: the pawn left the party
do
    local t = setup{ [A] = roster.PRESENT }
    local snap = snapshot(30)
    t.push(dismiss(A, snap))
    t.flow.update()
    assert(t.status(A) == roster.AWAY and t.member(A).character_id == 11)
    assert(t.order[1] == "store" and t.order[2] == "mark_away" and #t.order == 2)
    assert(t.stores[1].snap == snap and t.stores[1].unit == 0 and t.stores[1].m == t.member(A))
    assert(#t.lines == 1 and t.lines[1] == "Ana: present→away (dismiss)")
    assert(#t.reports == 0)
    -- a second dismiss: already away, nothing logged, and nothing else
    t.push(dismiss(A, nil))
    t.flow.update()
    assert(#t.lines == 1 and t.status(A) == roster.AWAY)
end

-- dismiss without a snapshot still departs, and no store
do
    local t = setup{ [A] = roster.PRESENT }
    t.push(dismiss(A, nil))
    t.flow.update()
    assert(t.status(A) == roster.AWAY and #t.stores == 0)
end

-- dismiss with the pawn still in found: no transition, the snapshot still stored
do
    local t = setup{ [A] = roster.PRESENT }
    t.view(A)
    t.push(dismiss(A, snapshot()))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.stores == 1)
    assert(t.lines[1] == "Ana: dismissed but still in the party, stays present" and #t.lines == 1)
    assert(not table.concat(t.order, ","):find("mark_away"))
end

-- dismiss of an ambiguous pawn: also no transition
do
    local t = setup{ [A] = roster.PRESENT }
    t.retinue.ambiguous[A] = true
    t.push(dismiss(A, snapshot()))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.stores == 1 and #t.lines == 1)
end

-- a store that throws still transitions, and is reported
do
    local t = setup{ [A] = roster.PRESENT }
    t.store_throws = true
    t.push(dismiss(A, snapshot()))
    t.flow.update()
    assert(t.status(A) == roster.AWAY)
    assert(#t.reports == 1 and t.reports[1].what == "backup" and t.reports[1].err:find("disk full"))
end

-- a dismiss while returning -> away; the backup is untouched (no snapshot in the event)
do
    local t = setup{ [A] = roster.RETURNING }
    t.push(dismiss(A, nil))
    t.flow.update()
    assert(t.status(A) == roster.AWAY)
    assert(t.lines[1] == "Ana: returning→away (dismiss)")
end

-- events are held while party.failed or without a main pawn, then applied in order
do
    local t = setup{ [A] = roster.PRESENT }
    t.party.failed = true
    t.push(dismiss(A, snapshot()))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.lines == 0)
    t.party.failed = false
    t.party.main = false
    t.push(hire(A))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.lines == 0 and #t.stores == 0)
    t.party.main = true
    t.view(A) -- back in the party by the time they are applied
    t.flow.update()
    assert(t.status(A) == roster.RETURNING) -- dismiss, then hire
    assert(t.lines[1] == "Ana: present→away (dismiss)")
    assert(t.lines[2] == "Ana: away→returning (no backup)" and #t.lines == 2)
    -- applied once only
    t.flow.update()
    assert(#t.lines == 2 and #t.stores == 1)
end

-- stale generation: dropped on arrival and while held
do
    local t = setup{ [A] = roster.PRESENT }
    t.push(dismiss(A, snapshot(), 0))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.stores == 0 and #t.lines == 0)
    t.party.main = false
    t.push(dismiss(A, snapshot(), 1))
    t.flow.update()
    t.retinue.generation = 2
    t.party.main = true
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and #t.stores == 0 and #t.lines == 0)
    -- a roster that is nil drops the event
    t.push(dismiss(A, snapshot(), 2))
    t.retinue.roster = nil
    t.flow.update()
    assert(#t.stores == 0 and #t.lines == 0)
end

-- an unknown id is dropped
do
    local t = setup{ [A] = roster.PRESENT }
    t.push(dismiss(X, snapshot()))
    t.push(hire(X))
    t.flow.update()
    assert(#t.stores == 0 and #t.lines == 0 and #t.order == 0)
end

-- hire of a present member: it left unseen, so it is a Return, restored like any other
do
    local t = setup{ [A] = roster.PRESENT }
    t.backups_by_id[A] = snapshot(28)
    t.push(hire(A))
    t.flow.update()
    assert(t.status(A) == roster.RETURNING)
    assert(#t.lines == 2 and t.lines[1] == "Ana: present→away (hire)" and t.lines[2] == "Ana: away→returning (backup Lv 28)")
    t.view(A)
    t.flow.tick(0, true)
    assert(t.status(A) == roster.PRESENT and #t.restores == 1)

    -- a dismiss that found the pawn still there, then the hire in a later batch
    local u = setup{ [A] = roster.PRESENT }
    u.backups_by_id[A] = snapshot(28)
    u.view(A)
    u.push(dismiss(A, nil))
    u.flow.update()
    assert(u.status(A) == roster.PRESENT)
    u.push(hire(A))
    u.flow.update()
    assert(u.status(A) == roster.RETURNING)
end

-- hire: away -> returning; returning / unknown / ambiguous do nothing
do
    local t = setup{ [A] = roster.AWAY }
    t.backups_by_id[A] = snapshot(27.0)
    t.push(hire(A))
    t.push(hire(X))
    t.flow.update()
    assert(t.status(A) == roster.RETURNING)
    assert(#t.lines == 1 and t.lines[1] == "Ana: away→returning (backup Lv 27)")
    -- hire of a returning member: nothing more
    t.push(hire(A))
    t.flow.update()
    assert(#t.lines == 1)
    -- ambiguous
    local u = setup{ [A] = roster.AWAY }
    u.retinue.ambiguous[A] = true
    u.push(hire(A))
    u.flow.update()
    assert(u.status(A) == roster.AWAY and #u.lines == 0)
end

-- tick: not in the world, nothing runs and the budget does not start
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.flow.tick(0, false)
    assert(#t.restores == 0 and t.flow.note(A) == nil)
    t.flow.tick(1, true)
    assert(#t.restores == 1 and t.status(A) == roster.PRESENT)
end

-- tick: read-only runs nothing; locked and nil roster too
do
    local t = setup({ [A] = roster.RETURNING }, { mode = roster.READ_ONLY })
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.flow.tick(0, true)
    assert(#t.restores == 0 and t.status(A) == roster.RETURNING and t.flow.note(A) == nil)
    t.retinue.roster.mode = roster.LOCKED
    t.flow.tick(1, true)
    assert(#t.restores == 0)
    t.retinue.roster = nil
    t.flow.tick(2, true)
    assert(#t.restores == 0)
end

-- tick: ambiguous skipped; present and away members are not touched
do
    local t = setup{ [A] = roster.RETURNING, [B] = roster.AWAY }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.view(B)
    t.retinue.ambiguous[A] = true
    t.flow.tick(0, true)
    assert(#t.restores == 0 and t.status(A) == roster.RETURNING and t.status(B) == roster.AWAY)
    assert(t.flow.note(A) == nil)
end

-- hire, then the restore on the next tick; character_id set from the view
do
    local t = setup{ [A] = roster.AWAY }
    t.backups_by_id[A] = snapshot(27)
    t.push(hire(A))
    t.flow.update()
    assert(t.status(A) == roster.RETURNING)
    t.view(A, 4242)
    t.party_levels[A] = 3
    t.flow.tick(10, true)
    assert(t.status(A) == roster.PRESENT and t.member(A).character_id == 4242)
    assert(#t.restores == 1)
    assert(t.lines[#t.lines] == "Ana: returning→present restored Lv 3→27")
    assert(t.flow.note(A) == nil)
    -- nothing more once present
    t.flow.tick(11, true)
    assert(#t.restores == 1)
end

-- wait until ready, then done
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.flow.tick(0, true) -- not in the party
    assert(#t.restores == 0 and t.flow.note(A) == "pending")
    t.view(A, 77)
    t.party_levels[A] = nil -- level not readable yet
    t.flow.tick(1, true)
    assert(#t.restores == 0)
    t.party_levels[A] = 0
    t.flow.tick(2, true)
    assert(#t.restores == 0)
    t.party_levels[A] = 9
    -- the game says "wait" first: reported, retried
    local n = 0
    t.restore_results[A] = function()
        n = n + 1
        if n == 1 then return "wait", "no status context" end
        return "done"
    end
    t.flow.tick(3, true)
    assert(t.status(A) == roster.RETURNING and #t.reports == 1)
    assert(t.reports[1].what == "restore" and t.reports[1].err == "Ana: no status context")
    t.flow.tick(4, true)
    assert(t.status(A) == roster.PRESENT and t.member(A).character_id == 77)
    assert(t.lines[#t.lines] == "Ana: returning→present restored Lv 9→27" and #t.lines == 1)
end

-- timeout closes once with one line and no later attempts; a new generation retries
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.flow.tick(100, true)
    t.flow.tick(109, true)
    assert(#t.lines == 0 and t.flow.note(A) == "pending")
    t.flow.tick(110, true)
    assert(#t.lines == 1 and t.lines[1] == "Ana: restore timed out, stays returning")
    assert(t.flow.note(A) == "timed out" and t.status(A) == roster.RETURNING)
    t.view(A)
    t.flow.tick(111, true)
    t.flow.tick(500, true)
    assert(#t.restores == 0 and #t.lines == 1 and t.status(A) == roster.RETURNING)
    -- a new generation retries
    t.retinue.generation = 2
    t.flow.tick(501, true)
    assert(#t.restores == 1 and t.status(A) == roster.PRESENT)
    assert(t.lines[2] == "Ana: returning→present restored Lv 5→27")
end

-- ready at the deadline still restores
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.flow.tick(0, true)
    t.view(A)
    t.flow.tick(50, true)
    assert(t.status(A) == roster.PRESENT and #t.lines == 1 and t.lines[1]:find("restored"))
end

-- mismatch closes
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.restore_results[A] = function() return "mismatch", "culmative_exp[3]" end
    t.flow.tick(0, true)
    assert(t.status(A) == roster.RETURNING and #t.lines == 1)
    assert(t.lines[1] == "Ana: restore read-back differs at culmative_exp[3], stays returning")
    assert(t.flow.note(A) == "differs at culmative_exp[3]")
    t.flow.tick(1, true)
    t.flow.tick(2, true)
    assert(#t.restores == 1 and #t.lines == 1)
end

-- guard: the game's level is above the backup's
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A, 55)
    t.party_levels[A] = 30
    t.flow.tick(0, true)
    assert(#t.restores == 0 and t.status(A) == roster.PRESENT and t.member(A).character_id == 55)
    assert(t.lines[1] == "Ana: returning→present skipped: guard (game Lv 30, backup Lv 27)" and #t.lines == 1)
    assert(t.flow.note(A) == nil)
end

-- no backup
do
    local t = setup{ [A] = roster.RETURNING, [B] = roster.RETURNING }
    t.view(A, 55)
    t.view(B, 56)
    t.notes[B] = "damaged: not valid JSON"
    t.flow.tick(0, true)
    assert(#t.restores == 0 and t.status(A) == roster.PRESENT and t.status(B) == roster.PRESENT)
    assert(t.lines[1] == "Ana: returning→present skipped: no backup (missing)")
    assert(t.lines[2] == "Bo: returning→present skipped: no backup (damaged: not valid JSON)")
    assert(t.member(A).character_id == 55 and t.member(B).character_id == 56)
end

-- equal level restores
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.party_levels[A] = 27.0
    t.flow.tick(0, true)
    assert(#t.restores == 1 and t.status(A) == roster.PRESENT)
    assert(t.lines[1] == "Ana: returning→present restored Lv 27→27")
end

-- one member's throw leaves the other restored
do
    local t = setup{ [A] = roster.RETURNING, [B] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.backups_by_id[B] = snapshot(20, { offline_id = B, name = "Bo" })
    t.view(A)
    t.view(B)
    t.restore_results[A] = function() error("write blew up") end
    t.flow.tick(0, true)
    assert(t.status(A) == roster.RETURNING and t.status(B) == roster.PRESENT)
    assert(#t.reports == 1 and t.reports[1].what == "restore" and t.reports[1].err:find("write blew up"))
    -- Ana is retried on the next tick
    t.restore_results[A] = nil
    t.flow.tick(1, true)
    assert(t.status(A) == roster.PRESENT)
end

-- recorded mismatch logged after a restore; a failing read is reported and does not undo the restore
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.read_result = snapshot(27, { current_job = 6, item_ids = { 9 } })
    t.flow.tick(0, true)
    assert(t.status(A) == roster.PRESENT and #t.lines == 2)
    assert(t.lines[2] == "Ana: restored, differs from its backup in current_job")

    local u = setup{ [A] = roster.RETURNING }
    u.backups_by_id[A] = snapshot(27)
    u.view(A)
    u.read_result = snapshot(27)
    u.flow.tick(0, true)
    assert(#u.lines == 1)

    local w = setup{ [A] = roster.RETURNING }
    w.backups_by_id[A] = snapshot(27)
    w.view(A)
    w.read_throws = true
    w.flow.tick(0, true)
    assert(w.status(A) == roster.PRESENT and #w.lines == 1 and #w.reports == 1 and w.reports[1].what == "restore")
end

-- a nil, why read after a restore is reported
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.view(A)
    t.read_nil = "no human"
    t.flow.tick(0, true)
    assert(t.status(A) == roster.PRESENT and #t.lines == 1)
    assert(#t.reports == 1 and t.reports[1].what == "restore" and t.reports[1].err == "Ana: no human")
end

-- a restore that never finishes ends at the budget: "wait" every tick, or a throw every tick
do
    for _, mode in ipairs({ "wait", "throw" }) do
        local t = setup{ [A] = roster.RETURNING }
        t.backups_by_id[A] = snapshot(27)
        t.view(A)
        t.restore_results[A] = function()
            if mode == "throw" then error("boom") end
            return "wait", "not ready"
        end
        t.flow.tick(100, true)
        t.flow.tick(109, true)
        assert(#t.restores == 2 and #t.lines == 0 and t.flow.note(A) == "pending")
        t.flow.tick(110, true) -- the expiring frame still gets its attempt, then closes
        assert(#t.restores == 3 and #t.lines == 1 and t.lines[1] == "Ana: restore timed out, stays returning")
        assert(t.flow.note(A) == "timed out" and t.status(A) == roster.RETURNING)
        for i = 111, 130 do t.flow.tick(i, true) end
        assert(#t.restores == 3 and #t.lines == 1)
    end
end

-- a timed-out member that is dismissed and hired again restores (forget on both transitions)
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.flow.tick(0, true)
    t.flow.tick(10, true)
    assert(t.flow.note(A) == "timed out")
    t.push(dismiss(A, nil))
    t.flow.update()
    assert(t.status(A) == roster.AWAY and t.flow.note(A) == nil)
    t.push(hire(A))
    t.flow.update()
    assert(t.status(A) == roster.RETURNING and t.flow.note(A) == nil)
    t.view(A)
    t.flow.tick(11, true)
    assert(t.status(A) == roster.PRESENT and #t.restores == 1)
    -- forget on the dismiss alone: a timed-out member dismissed, then hired with no budget left over
    local u = setup{ [A] = roster.RETURNING }
    u.backups_by_id[A] = snapshot(27)
    u.flow.tick(0, true)
    u.flow.tick(10, true)
    u.push(dismiss(A, nil))
    u.flow.update()
    assert(u.flow.note(A) == nil)
end

-- a generation change on an out-of-world tick still drops the budget
do
    local t = setup{ [A] = roster.RETURNING }
    t.backups_by_id[A] = snapshot(27)
    t.flow.tick(0, true)
    t.flow.tick(10, true)
    assert(t.flow.note(A) == "timed out")
    t.retinue.generation = 2
    t.flow.tick(11, false)
    assert(t.flow.note(A) == nil)
end

-- held dismiss, hire, dismiss: the later snapshot never touches the frozen backup
do
    local t = setup{ [A] = roster.PRESENT }
    t.party.main = false
    t.push(dismiss(A, snapshot(27)))
    t.push(hire(A))
    t.push(dismiss(A, snapshot(3)))
    t.flow.update()
    t.party.main = true
    t.flow.update()
    assert(#t.stores == 1 and t.stores[1].snap.level == 27)
    assert(t.status(A) == roster.AWAY)
end

-- rehired needs a later hire of the same pawn
do
    -- another pawn's hire
    local t = setup{ [A] = roster.PRESENT, [B] = roster.AWAY }
    t.view(A)
    t.push(dismiss(A, nil))
    t.push(hire(B))
    t.flow.update()
    assert(t.status(A) == roster.PRESENT and t.status(B) == roster.RETURNING)

    -- a hire before the dismiss
    local u = setup{ [A] = roster.AWAY }
    u.view(A)
    u.push(hire(A))
    u.push(dismiss(A, nil))
    u.flow.update()
    assert(u.status(A) == roster.RETURNING)

    -- a later dismiss is not a hire
    local v = setup{ [A] = roster.PRESENT }
    v.view(A)
    v.push(dismiss(A, nil))
    v.push(dismiss(A, nil))
    v.flow.update()
    assert(v.status(A) == roster.PRESENT)

    -- ambiguous beats rehired
    local w = setup{ [A] = roster.PRESENT }
    w.retinue.ambiguous[A] = true
    w.push(dismiss(A, nil))
    w.push(hire(A))
    w.flow.update()
    assert(w.status(A) == roster.PRESENT and #w.lines == 1)
end

-- flow.update keeps going when an event throws
do
    local t = setup{ [A] = roster.PRESENT, [B] = roster.PRESENT }
    t.retinue.mark_away = function(self, id)
        if id == A then error("save failed") end
        return roster.mark_away(self.roster, id)
    end
    t.push(dismiss(A, nil))
    t.push(dismiss(B, nil))
    t.flow.update()
    assert(t.status(B) == roster.AWAY and #t.reports == 1 and t.reports[1].what == "lifecycle")
end

-- the party diff: a present member missing for 3 checks (a second apart, in the world) becomes away
-- ticks(t, from, to): flow.update(now, true) at each second from..to
local function ticks(t, from, to, in_world)
    if in_world == nil then in_world = true end
    for now = from, to do t.flow.update(now, in_world) end
end

do
    local t = setup{ [A] = roster.PRESENT }
    ticks(t, 0, 2) -- the first check is a second after entering the world
    assert(t.status(A) == roster.PRESENT and #t.lines == 0)
    ticks(t, 3, 3)
    assert(t.status(A) == roster.AWAY and t.member(A).character_id == 11)
    assert(#t.lines == 1 and t.lines[1] == "Ana: present→away (absence)")
    assert(table.concat(t.order, ",") == "mark_away" and #t.stores == 0 and #t.reports == 0)
    ticks(t, 4, 8) -- away members never go through it
    assert(#t.lines == 1 and #t.order == 1)
end

-- found again before the third check: stays present, and the count restarts
do
    local t = setup{ [A] = roster.PRESENT }
    ticks(t, 0, 2)
    t.view(A)
    ticks(t, 3, 3)
    t.retinue.found[A] = nil
    ticks(t, 4, 5)
    assert(t.status(A) == roster.PRESENT)
    ticks(t, 6, 6)
    assert(t.status(A) == roster.AWAY)
end

-- returning and away members never go through it
do
    local t = setup{ [A] = roster.RETURNING, [B] = roster.AWAY }
    ticks(t, 0, 6)
    assert(t.status(A) == roster.RETURNING and t.status(B) == roster.AWAY)
    assert(#t.order == 0 and #t.lines == 0)
end

-- ambiguous is never missing
do
    local t = setup{ [A] = roster.PRESENT }
    t.retinue.ambiguous[A] = true
    ticks(t, 0, 6)
    assert(t.status(A) == roster.PRESENT and #t.order == 0)
end

-- read-only: away in memory
do
    local t = setup({ [A] = roster.PRESENT }, { mode = roster.READ_ONLY })
    ticks(t, 0, 3)
    assert(t.status(A) == roster.AWAY and t.lines[1] == "Ana: present→away (absence)")
end

-- locked and no roster: no check
do
    local t = setup({ [A] = roster.PRESENT }, { mode = roster.LOCKED })
    ticks(t, 0, 6)
    assert(#t.order == 0 and #t.lines == 0)
    local u = setup{ [A] = roster.PRESENT }
    u.retinue.roster = nil
    ticks(u, 0, 6)
    assert(#u.order == 0 and #u.lines == 0 and #u.reports == 0)
end

-- no check without the world, with a failed party or without the main pawn; each drops the counts
do
    local cases = {
        function(t) ticks(t, 3, 3, false) end,
        function(t) t.party.failed = true; ticks(t, 3, 3) end,
        function(t) t.party.main = false; ticks(t, 3, 3) end,
    }
    for _, drop in ipairs(cases) do
        local t = setup{ [A] = roster.PRESENT }
        ticks(t, 0, 2)
        drop(t)
        t.party.failed, t.party.main = false, true
        ticks(t, 4, 6) -- re-armed at 4: the counts start over, checks at 5, 6, 7
        assert(t.status(A) == roster.PRESENT and #t.order == 0)
        ticks(t, 7, 7)
        assert(t.status(A) == roster.AWAY)
    end
    -- in_world nil (update() without arguments) is no check
    local t = setup{ [A] = roster.PRESENT }
    for _ = 1, 10 do t.flow.update() end
    assert(#t.order == 0)
end

-- an unreadable party holds the diff and drops the counts
do
    local t = setup{ [A] = roster.PRESENT }
    ticks(t, 0, 2) -- arm, two misses
    t.party.all_read = false
    ticks(t, 3, 3)
    t.party.all_read = true
    ticks(t, 4, 6) -- re-armed at 4: checks 5, 6 are misses 1, 2
    assert(t.status(A) == roster.PRESENT and #t.order == 0)
    ticks(t, 7, 7)
    assert(t.status(A) == roster.AWAY)
end

-- a new generation drops the counts
do
    local t = setup{ [A] = roster.PRESENT }
    ticks(t, 0, 2)
    t.retinue.generation = 2
    ticks(t, 3, 5)
    assert(t.status(A) == roster.PRESENT)
    ticks(t, 6, 6)
    assert(t.status(A) == roster.AWAY)
end

-- a queued dismiss in the same update wins: only (dismiss) is logged
do
    local t = setup{ [A] = roster.PRESENT }
    ticks(t, 0, 2)
    t.push(dismiss(A, nil))
    ticks(t, 3, 3)
    assert(t.status(A) == roster.AWAY and #t.lines == 1 and t.lines[1] == "Ana: present→away (dismiss)")
end

-- a throwing mark_away is reported and the other member still goes away
do
    local t = setup{ [A] = roster.PRESENT, [B] = roster.PRESENT }
    t.retinue.mark_away = function(self, id)
        if id == A then error("save failed") end
        return roster.mark_away(self.roster, id)
    end
    ticks(t, 0, 3)
    assert(t.status(A) == roster.PRESENT and t.status(B) == roster.AWAY)
    assert(#t.reports == 1 and t.reports[1].what == "lifecycle")
    assert(#t.lines == 1 and t.lines[1] == "Bo: present→away (absence)")
end

print("lifecycle_test ok")
