-- game/talk_menu.lua against a fake sdk and log: the lookups (a missing method or field installs no hook and never calls
-- the game), the row inserted before Never mind, our pick to Talk, the confirm in the Talk sub-menu, its pick, and the
-- nextNode guard.
local calls, logs, reports, hooked = {}, {}, {}, {}
local world
local missing_name

local function obj(name, props)
    local o = { name = name, sets = {} }
    function o:call(method, ...)
        calls[#calls + 1] = name .. ":" .. method
        local v = props[method]
        if type(v) == "function" then return v(o, ...) end
        return v
    end
    function o:get_field(field)
        calls[#calls + 1] = name .. "." .. field
        return props[field]
    end
    function o:set_field(field, value)
        calls[#calls + 1] = name .. "!" .. field
        o.sets[field] = value
        props[field] = value
    end
    function o:get_address() return props.addr end
    function o:add_ref() end
    function o:get_elements() return props.get_elements() end
    function o:read_qword() error("not a guid") end
    return o
end

local REQ_DISP = "reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, "
    .. "via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)"
local NEXT_NODE = "nextNode(System.Int32)"

-- type name -> { methods = {sig}, fields = {name} }
local TYPES = {
    ["app.GuiManager"] = { methods = {}, fields = { "TalkSelect" } },
    ["app.ui021601"] = { methods = { REQ_DISP, "get_IsEndGUI()" }, fields = { "SelectedIndex" } },
    ["app.ui021601.ListInfo"] = { methods = {}, fields = { "Msg", "_IsDecideEnable", "ListenerType", "SpeakerType", "Listener" } },
    ["app.TalkEventManager"] = { methods = {}, fields = { "<CurrentTalkInfo>k__BackingField" } },
    ["app.TalkEventPlayer"] = { methods = { NEXT_NODE }, fields = {} },
}
local function set(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end

sdk = {
    PreHookResult = { CALL_ORIGINAL = "CO" },
    find_type_definition = function(name)
        local t = TYPES[name]
        if not t or name == missing_name then return nil end
        local methods, fields = set(t.methods), set(t.fields)
        return {
            get_method = function(_, sig)
                if sig == missing_name or not methods[sig] then return nil end
                return { sig = sig }
            end,
            get_methods = function() return {} end,
            get_field = function(_, field)
                if field == missing_name or not fields[field] then return nil end
                return {}
            end,
        }
    end,
    hook = function(m, pre, post)
        if world and world.hook_fail_at == #hooked + 1 then error("hook boom") end
        hooked[#hooked + 1] = { m = m, pre = pre, post = post }
    end,
    get_managed_singleton = function(name)
        world.singleton_reads = (world.singleton_reads or 0) + 1
        return world.singletons[name]
    end,
    create_managed_string = function(s) return s end,
    create_instance = function() return world.new_item() end,
    to_int64 = function(a) return a end,
    to_ptr = function(n) return n end,
    to_managed_object = function(a) return world.by_addr[a] end,
}
log = { error = function(text) logs[#logs + 1] = text end }

local talk_menu = require("Retinue.game.talk_menu")
local roster = require("Retinue.roster")
local R = require("Retinue.talk_menu")
local function report(where, err) reports[#reports + 1] = where .. ": " .. tostring(err) end

local OFFLINE = "aaaaaaaa-0000-0000-0000-000000000001"
local OTHER = "11111111-0000-0000-0000-000000000001"

local function reset()
    calls, logs, reports, hooked = {}, {}, {}, {}
    local gm_props = {}
    local gm = obj("gm", gm_props)
    world = { gm_props = gm_props, gm = gm, singletons = { ["app.GuiManager"] = gm }, by_addr = {}, now = 0 }
end

local function has_log(text)
    for _, l in ipairs(logs) do if l:find(text, 1, true) then return true end end
    return false
end

-- The lookups: every type, method and field in turn missing.
local cases = {}
for type_name, t in pairs(TYPES) do
    cases[#cases + 1] = type_name
    for _, sig in ipairs(t.methods) do cases[#cases + 1] = sig end
    for _, f in ipairs(t.fields) do cases[#cases + 1] = f end
end
assert(#cases == 2 + 4 + 6 + 2 + 2)

local function deps_for()
    return { store = { generation = 1, roster = nil, found = {}, ambiguous = {} }, party = { views = function() return {} end },
        notify = function() error("no notice expected") end, clock = function() return world.now end }
end

for _, name in ipairs(cases) do
    reset()
    missing_name = name
    local talk = talk_menu.new(report, deps_for())
    missing_name = nil
    assert(talk.available == false, name)
    assert(#hooked == 0, name)
    assert(#talk.missing >= 1, name)
    assert(#reports >= 1, name)
    calls = {}
    talk.tick(0)
    assert(#calls == 0, name)
    local named = false
    for _, m in ipairs(talk.missing) do
        if m:find(name, 1, true) then named = true end
    end
    assert(named, name)
end

-- everything present: available, two hooks (reqDisp, nextNode), nothing reported
do
    reset()
    local talk = talk_menu.new(report, deps_for())
    assert(talk.available and #talk.missing == 0 and #hooked == 2 and #reports == 0)
    assert(hooked[1].m.sig == REQ_DISP and hooked[2].m.sig == NEXT_NODE)
end

-- nextNode cannot be hooked after reqDisp was: not available, and the installed reqDisp hook adds no row
do
    reset()
    world.hook_fail_at = 2
    local talk = talk_menu.new(report, deps_for())
    assert(talk.available == false and #hooked == 1 and #talk.missing == 1 and talk.missing[1]:find("nextNode", 1, true))
    world.by_addr[2000] = obj("list", {})
    calls, world.singleton_reads = {}, 0
    hooked[1].pre({ [2] = 1000, [3] = 2000 })
    assert(#calls == 0 and world.singleton_reads == 0, "an unavailable talk menu reads nothing")
    world.hook_fail_at = nil
end

-- The scenario: the game's menus as fake objects, the row, the picks, the confirm and the guard.
do
    reset()
    local ROOT_ADDR, SUB_ADDR, PLAYER_ADDR, WIDGET = 2000, 2001, 3000, 1000

    -- A node with its choice ids.
    local function node_of(node_id, ids)
        local choices = {}
        for i, id in ipairs(ids) do choices[i] = obj("choice" .. i, { _ChoiceId = id }) end
        return obj("node", { _NodeId = node_id, _Choices = obj("arr", { get_elements = function() return choices end }) })
    end
    local root_node = node_of(R.ROOT_NODE, { R.TALK_CHOICE, R.DISMISS, OTHER, R.NEVER_MIND })
    local sub_node = node_of(R.TALK_SUB, { "388007d1-0000-0000-0000-000000000000", "ee458b93-0000-0000-0000-000000000000", R.CANCEL })

    local info = obj("info", { ["<CurrentNode>k__BackingField"] = root_node, ["<Speaker>k__BackingField"] = 202,
        ["<Listener>k__BackingField"] = 100 })
    world.singletons["app.TalkEventManager"] = obj("tm", { ["<CurrentTalkInfo>k__BackingField"] = info })
    local player_props = { _CurrentNode = sub_node }
    world.by_addr[PLAYER_ADDR] = obj("player", player_props)

    -- A list the way the game builds it (a fresh one for every reqDisp), with its Insert.
    local list_items
    local list = obj("list", {
        get_Count = function() return #list_items end,
        get_Item = function(_, i) return list_items[i + 1] end,
        Insert = function(_, i, item) table.insert(list_items, i + 1, item) end,
    })
    world.by_addr[ROOT_ADDR], world.by_addr[SUB_ADDR] = list, list
    local vanilla -- the game's own row objects of the current list
    local function fresh_root()
        vanilla = {}
        for i = 1, 4 do vanilla[i] = obj("row" .. i, { Listener = "L", ListenerType = 1, SpeakerType = 2 }) end
        list_items = { vanilla[1], vanilla[2], vanilla[3], vanilla[4] }
    end
    local function fresh_sub()
        vanilla = {}
        for i = 1, 3 do vanilla[i] = obj("sub" .. i, {}) end
        list_items = { vanilla[1], vanilla[2], vanilla[3] }
    end
    world.new_item = function() return obj("new_item", { add_ref = true, [".ctor"] = true }) end
    local select_props = { addr = WIDGET, get_IsEndGUI = false, SelectedIndex = -1 }
    local select = obj("select", select_props)
    world.gm_props.TalkSelect = select

    local view = { slot = 2, character_id = 202, owner = roster.OWNER, offline_id = OFFLINE, name = "Ana", chara = {} }
    local adopted, released
    local adopt_result = { true }
    local adopt_throws = false
    local store = { generation = 1, found = {}, ambiguous = {}, unit = 0,
        roster = { mode = roster.OK, members = {}, warnings = {} },
        adopt = function(self, v)
            if adopt_throws then error("adopt boom") end
            adopted = v
            return table.unpack(adopt_result)
        end,
        release = function(self, id) released = id; return true end }
    local pushed = {}
    local talk = talk_menu.new(report, {
        store = store, notify = function(t) pushed[#pushed + 1] = t end, clock = function() return world.now end,
        party = { views = function() return { { slot = 0, character_id = 100 }, view } end, level = function() return 30 end },
    })
    assert(talk.available and #hooked == 2)
    local req_disp, next_node = hooked[1].pre, hooked[2].pre

    local function show_root(addr)
        fresh_root()
        req_disp({ [2] = WIDGET, [3] = addr or ROOT_ADDR })
    end
    local function show_sub()
        info:set_field("<CurrentNode>k__BackingField", sub_node)
        fresh_sub()
        req_disp({ [2] = WIDGET, [3] = SUB_ADDR })
    end
    local function to_root_node() info:set_field("<CurrentNode>k__BackingField", root_node) end
    local function pick(sel, now)
        select_props.get_IsEndGUI, select_props.SelectedIndex = true, sel
        world.now = now
        talk.tick(now)
        select_props.get_IsEndGUI = false
    end
    local function written() return select.sets.SelectedIndex end
    local function clear_writes() select.sets.SelectedIndex = nil end

    -- the root menu: the row goes in before Never mind, which keeps its place last
    show_root()
    assert(#list_items == 5 and #reports == 0, table.concat(reports, "; "))
    assert(list_items[5] == vanilla[4] and list_items[4] ~= vanilla[3] and list_items[3] == vanilla[3])
    local ours = list_items[4]
    assert(ours.sets.Msg == "Adopt" and ours.sets._IsDecideEnable == true and ours.sets.Listener == "L"
        and ours.sets.ListenerType == 1 and ours.sets.SpeakerType == 2)
    -- no pick yet
    talk.tick(1)
    assert(written() == nil)

    -- our pick: written to Talk, and armed
    pick(3, 2)
    assert(written() == 0 and has_log("adopt Ana: picked") and #pushed == 0)
    -- the Talk sub-menu: rows 0 and 1 relabelled, row 1 disabled, row 2 as the game has it
    show_sub()
    assert(vanilla[1].sets.Msg == "Confirm adopt" and vanilla[1].sets._IsDecideEnable == true)
    assert(vanilla[2].sets.Msg == "Gear you give them is lost if they're dismissed or lost." and vanilla[2].sets._IsDecideEnable == false)
    assert(next(vanilla[3].sets) == nil and #list_items == 3)
    -- the confirm pick: acts, then Cancel
    clear_writes()
    pick(0, 3)
    assert(adopted == view and written() == 2 and #pushed == 0 and #reports == 0)
    assert(has_log("adopt Ana: confirmed") and has_log("adopt Ana: done"), table.concat(logs, "; "))
    -- the picked sub-menu is done: no second act
    adopted = nil
    pick(0, 3.1)
    assert(adopted == nil)
    -- the guard is set by the confirm pick: the game's nextNode(2) goes through, and consumes it
    local args = { [2] = PLAYER_ADDR, [3] = 2 }
    next_node(args)
    assert(args[3] == 2 and #reports == 0)
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0, "guard consumed by the first nextNode")

    -- a cancel: any other row of the confirm writes Cancel and acts on nothing
    to_root_node()
    show_root()
    pick(3, 4)
    show_sub()
    clear_writes()
    pick(1, 5)
    assert(adopted == nil and written() == 2 and has_log("adopt Ana: cancelled"))
    to_root_node(); show_root(); pick(3, 6); show_sub(); clear_writes()
    pick(2, 7) -- Cancel itself
    assert(adopted == nil and written() == 2)

    -- Never mind shown last: written to the game's Never mind
    to_root_node(); show_root(); clear_writes()
    pick(4, 8)
    assert(written() == 3)
    -- another row (Dismiss): nothing written, and the menu is dropped
    show_root(); clear_writes()
    pick(1, 9)
    assert(written() == nil)
    pick(3, 9.1)
    assert(written() == nil, "menu was dropped")

    -- the nextNode guard: a failed write on the confirm pick must not run Matters of import or Small talk
    to_root_node(); show_root(); pick(3, 10); show_sub()
    local real_set = select.set_field
    select.set_field = function() end
    reports = {}
    pick(0, 11)
    select.set_field = real_set
    assert(adopted == view and #reports == 1 and reports[1]:find("could not be redirected to Cancel", 1, true))
    reports = {}
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 2 and #reports == 1 and reports[1]:find("nextNode(0)", 1, true))
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0, "once")
    -- Small talk (1) too
    to_root_node(); show_root(); pick(3, 12); show_sub()
    select.set_field = function() end
    pick(1, 13)
    select.set_field = real_set
    args = { [2] = PLAYER_ADDR, [3] = 1 }
    next_node(args)
    assert(args[3] == 2)
    -- while guarded, on another node (the root, here): left alone, and the guard is not spent by it
    to_root_node(); show_root(); pick(3, 14); show_sub()
    pick(1, 15)
    player_props._CurrentNode = root_node
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0)
    player_props._CurrentNode = sub_node
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 2, "still guarded after a nextNode of another node")
    -- the player's node is unreadable: the talk info's node counts
    to_root_node(); show_root(); pick(3, 16); show_sub(); pick(1, 17)
    player_props._CurrentNode = nil
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 2)
    player_props._CurrentNode = sub_node
    -- the guard expires after 2 s
    to_root_node(); show_root(); pick(3, 18); show_sub(); pick(1, 19)
    world.now = 21.5
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0)
    -- no guard: nothing is rewritten
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0)

    -- the root guard: our write to Talk is backed up on the root menu's nextNode (anything but Talk becomes Never mind)
    to_root_node(); show_root(); pick(3, 200)
    player_props._CurrentNode = root_node
    reports = {}
    args = { [2] = PLAYER_ADDR, [3] = 1 }
    next_node(args)
    assert(args[3] == 3 and #reports == 1 and reports[1]:find("rewritten to Never mind", 1, true), tostring(args[3]))
    show_sub()
    assert(next(vanilla[1].sets) == nil, "the armed confirm was dropped")
    -- Talk itself goes through, and consumes it
    to_root_node(); show_root(); pick(3, 201)
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0)
    args = { [2] = PLAYER_ADDR, [3] = 1 }
    next_node(args)
    assert(args[3] == 1)
    -- expired after 2 s
    to_root_node(); show_root(); pick(3, 202)
    world.now = 205
    args = { [2] = PLAYER_ADDR, [3] = 1 }
    next_node(args)
    assert(args[3] == 1)
    -- a late watcher: the next menu's reqDisp ends the guard, so another talk's Dismiss is left alone
    to_root_node(); show_root(); pick(3, 204)
    show_root()
    player_props._CurrentNode = root_node
    reports = {}
    args = { [2] = PLAYER_ADDR, [3] = 6 }
    next_node(args)
    assert(args[3] == 6 and #reports == 0)
    -- Never mind itself is not rewritten nor reported
    to_root_node(); show_root(); pick(3, 204.5)
    player_props._CurrentNode = root_node
    reports = {}
    args = { [2] = PLAYER_ADDR, [3] = 3 }
    next_node(args)
    assert(args[3] == 3 and #reports == 0)
    -- not on the Talk sub-menu's node
    to_root_node(); show_root(); pick(3, 203)
    player_props._CurrentNode = sub_node
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 0)
    world.now = 210 -- the guard of the pick above is gone

    -- the same Talk sub-menu list handed to reqDisp twice: the pick is still watched
    to_root_node(); show_root(); pick(3, 211); show_sub()
    req_disp({ [2] = WIDGET, [3] = SUB_ADDR })
    assert(vanilla[1].sets.Msg == "Confirm adopt" and #list_items == 3)
    adopted = nil; clear_writes()
    pick(0, 212)
    assert(adopted == view and written() == 2)
    -- a root menu after the sub-menu: the confirm is not carried over
    to_root_node(); show_root(); pick(3, 213); show_sub()
    to_root_node(); show_root()
    adopted = nil; clear_writes()
    pick(0, 214)
    assert(adopted == nil and written() == nil)

    -- an unreadable SelectedIndex on the confirm: nothing written, but the guard stands
    to_root_node(); show_root(); pick(3, 220); show_sub()
    clear_writes()
    pick("?", 221)
    assert(written() == nil)
    player_props._CurrentNode = sub_node
    args = { [2] = PLAYER_ADDR, [3] = 0 }
    next_node(args)
    assert(args[3] == 2)

    -- a refusal (locked): nothing written (the game runs Never mind), a notice, and no confirm after
    store.roster.mode = roster.LOCKED
    pushed, logs = {}, {}
    to_root_node(); show_root(); clear_writes()
    pick(3, 30)
    assert(written() == nil and #pushed == 1 and pushed[1] == "Cannot adopt Ana: the roster is locked (see the menu)")
    show_sub()
    assert(next(vanilla[1].sets) == nil)
    store.roster.mode = roster.OK

    -- the roster changed between the row and the pick: nothing written, no notice
    to_root_node(); show_root(); clear_writes()
    pushed = {}
    store.generation = 2
    pick(3, 31)
    assert(written() == nil and #pushed == 0)
    store.generation = 1

    -- the roster changed between our pick and the confirm: not acted on, but written to Cancel
    to_root_node(); show_root(); pick(3, 32); show_sub()
    store.generation = 3
    adopted = nil; clear_writes()
    pick(0, 33)
    assert(adopted == nil and written() == 2)
    store.generation = 1

    -- an error at the action: a notice
    adopt_result = { false, "full" }
    pushed = {}
    to_root_node(); show_root(); pick(3, 34); show_sub(); clear_writes(); pick(0, 35)
    assert(#pushed == 1 and pushed[1] == "Cannot adopt Ana: the retinue is full (2 members)" and written() == 2)
    adopt_result = { true }
    -- the action throws: reported, Cancel is still written
    adopt_throws = true
    to_root_node(); show_root(); pick(3, 36); show_sub(); clear_writes()
    reports = {}
    pick(0, 37)
    adopt_throws = false
    assert(#reports == 1 and reports[1]:find("adopt boom", 1, true) and written() == 2)

    -- another menu comes first: the armed confirm is dropped
    to_root_node(); show_root(); pick(3, 40)
    to_root_node(); show_root() -- the root again, not the Talk sub-menu
    assert(has_log("dropped (another menu came first)"))
    show_sub()
    assert(next(vanilla[1].sets) == nil, "dropped: the sub-menu is vanilla")

    -- the deadline (5 s) drops it, in tick and in the hook
    to_root_node(); show_root(); pick(3, 50)
    world.now = 55.5
    show_sub()
    assert(next(vanilla[1].sets) == nil)
    to_root_node(); show_root(); pick(3, 60)
    logs = {}
    talk.tick(65.5)
    assert(has_log("dropped (the Talk sub-menu did not show)"))
    world.now = 65.6
    show_sub()
    assert(next(vanilla[1].sets) == nil)

    -- our write to Talk does not stick: reported, not armed
    to_root_node(); show_root()
    select.set_field = function() end
    reports = {}
    pick(3, 70)
    select.set_field = real_set
    assert(#reports == 1 and reports[1]:find("could not be redirected to Talk", 1, true))
    show_sub()
    assert(next(vanilla[1].sets) == nil)
    -- the write to Never mind does not stick: reported
    to_root_node(); show_root()
    select.set_field = function() end
    reports = {}
    pick(4, 71)
    select.set_field = real_set
    assert(#reports == 1 and reports[1]:find("could not be redirected to Never mind", 1, true))

    -- the same list handed to reqDisp twice: no second row, the pick is watched against the vanilla count
    to_root_node(); fresh_root()
    req_disp({ [2] = WIDGET, [3] = ROOT_ADDR })
    req_disp({ [2] = WIDGET, [3] = ROOT_ADDR })
    assert(#list_items == 5)
    clear_writes()
    pick(3, 80)
    assert(written() == 0)
    show_sub()
    pick(0, 81)

    -- args[2] is not GuiManager.TalkSelect: no row, one report line
    to_root_node(); fresh_root()
    reports = {}
    req_disp({ [2] = 1111, [3] = ROOT_ADDR })
    assert(#list_items == 4 and #reports == 1 and reports[1]:find("not GuiManager.TalkSelect", 1, true))
    world.gm_props.TalkSelect = nil
    req_disp({ [2] = WIDGET, [3] = ROOT_ADDR })
    assert(#list_items == 4 and #reports == 2)
    world.gm_props.TalkSelect = select
    -- and for the confirm
    to_root_node(); show_root(); pick(3, 90)
    info:set_field("<CurrentNode>k__BackingField", sub_node)
    fresh_sub()
    reports = {}
    req_disp({ [2] = 1111, [3] = SUB_ADDR })
    assert(next(vanilla[1].sets) == nil and #reports == 1)

    -- a menu that is not the root: left alone, and a root node with unqualifying choices is reported
    to_root_node()
    local not_talk_first = node_of(R.ROOT_NODE, { OTHER, R.DISMISS, OTHER, R.NEVER_MIND })
    info:set_field("<CurrentNode>k__BackingField", not_talk_first)
    fresh_root()
    reports = {}
    req_disp({ [2] = WIDGET, [3] = ROOT_ADDR })
    assert(#list_items == 4)
    assert(#reports == 1 and reports[1]:find("root menu not recognised: 4 choices, first " .. OTHER .. ", last " .. R.NEVER_MIND, 1, true), reports[1])
    local bad_last = node_of(R.ROOT_NODE, { R.TALK_CHOICE, R.DISMISS, OTHER, "ffffffff-0000-0000-0000-000000000000" })
    info:set_field("<CurrentNode>k__BackingField", bad_last)
    fresh_root()
    reports = {}
    req_disp({ [2] = WIDGET, [3] = ROOT_ADDR })
    assert(#list_items == 4 and #reports == 1 and reports[1]:find("last ffffffff-0000-0000-0000-000000000000", 1, true))
    -- the Talk sub-menu itself is no root
    to_root_node(); show_sub(); reports = {}
    assert(#list_items == 3 and #reports == 0)

    -- a talk with the main pawn (or nobody in the party) gets no row
    to_root_node()
    info:set_field("<Speaker>k__BackingField", 100)
    show_root()
    assert(#list_items == 4)
    info:set_field("<Speaker>k__BackingField", 202)

    -- a release: the member's row, the confirm, the release
    to_root_node()
    store.roster.members = { { offline_id = OFFLINE, name = "Ana", status = roster.PRESENT, character_id = 202 } }
    store.found[OFFLINE] = view
    show_root()
    assert(#list_items == 5 and list_items[4].sets.Msg == "Release (Retinue \u{B7} Lv 30)")
    pick(3, 100)
    show_sub()
    assert(vanilla[1].sets.Msg == "Confirm release" and vanilla[2].sets.Msg == "Their progress will be lost."
        and vanilla[2].sets._IsDecideEnable == false)
    pick(0, 101)
    assert(released == OFFLINE and has_log("release Ana: done"))
    store.roster.members, store.found = {}, {}

    -- _Choices whose get_elements fails (ticket 24 run 2): read as a List, then as an array
    local choices = {}
    for i, id in ipairs({ R.TALK_CHOICE, R.DISMISS, OTHER, R.NEVER_MIND }) do choices[i] = obj("choice" .. i, { _ChoiceId = id }) end
    for _, shape in ipairs({
        { get_elements = function() return {} end, get_Count = function() return #choices end,
          get_Item = function(_, i) return choices[i + 1] end },
        { get_elements = function() error("no elements") end, get_Count = function() return #choices end,
          get_Item = function(_, i) return choices[i + 1] end },
        { get_elements = function() error("no elements") end, get_Count = function() error("not a List") end,
          get_Length = function() return #choices end, GetValue = function(_, i) return choices[i + 1] end },
    }) do
        info:set_field("<CurrentNode>k__BackingField", obj("node", { _NodeId = R.ROOT_NODE, _Choices = obj("arr", shape) }))
        show_root()
        assert(#list_items == 5, "row inserted through the fallback")
    end
    -- more choices than the cap: unreadable, no row
    local many = {}
    for i = 1, 17 do many[i] = choices[4] end
    info:set_field("<CurrentNode>k__BackingField", obj("node", { _NodeId = R.ROOT_NODE, _Choices = obj("arr", {
        get_elements = function() return many end, get_Count = function() return #many end,
        get_Item = function(_, i) return many[i + 1] end }) }))
    reports = {}
    show_root()
    assert(#list_items == 4)
    assert(#reports == 1 and reports[1]:find("root menu not recognised: unreadable choices", 1, true), reports[1])
end

print("talk_menu_glue_test ok")
