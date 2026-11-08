-- Retinue (Dragon's Dogma 2, REFramework Lua): adopted pawns level up.
--
-- Pre-hooks on app.ExpDispenser.checkLevelUp and app.ExpDispenser.addJobPoint replace the CharacterID of an
-- adopted pawn in your party with the main pawn's fixed ID, so the game's own level-up path runs for them and
-- they gain levels, discipline and vocation rank from any exp source. Only present adopted pawns progress: the
-- members of the save slot's roster (reframework/data/Retinue/slots/<n>/roster.json, one per slot, read when the
-- slot becomes active) that are in the party and whose Offline ID no other party pawn shares. Ordinary hired
-- pawns stay vanilla. Pre-hooks on app.ExpDispenser.dispLevelUpUI and app.GuiManager.reqJobRankUp put the real
-- ID back, so the level-up and rank-up notifications name the pawn. The REFramework menu has a "Retinue" section
-- with one checkbox (saved in reframework/data/Retinue/config.json, on when there is no file), a status line
-- naming the party pawns progression applies to (name, level, vocation, rank, discipline), read only while the
-- menu is drawn, and the roster: the slot and the roster state, one line per member with a Release button, and an
-- Adopt button per adoptable Rift pawn in your party (both ask for a confirmation).
-- Every present member in the party also has a backup (reframework/data/Retinue/slots/<n>/backups/<offline_id>.json):
-- written when you adopt it, then refreshed about every 10 seconds while you are in the world, only when a value
-- changed (whatever the checkbox says; nothing is written when the roster is locked or read-only, or the slot is
-- unknown). Release empties or deletes the file. A member below its backup lowers it (the save wins). The menu shows
-- the level of a member that is not in the party from its backup, and a note when its backup is missing or damaged.
-- Dismissing a member at the Rift (the pawn leaves the party) stores its last backup and marks it away. Hiring it again
-- marks it returning, and about a frame later, in the game's update, its progress is written back from the backup
-- (retried for about 10 seconds; the menu shows a note when that fails). Both run whatever the progression checkbox says.
-- A member that leaves any other way (lost) is noticed by a party check about every second in the world and marked away
-- after 3 misses; its backup is the last poll.
-- After each load, once the pawns are in the world again, the roster is reconciled with the save: a member's status
-- follows what the loaded party shows (a rollback, a member that left or was re-hired without the mod), one log line per
-- correction. Until then the hook events, the party check, the restores, the backup poll and the cache refresh wait.
-- Starting a new game or a restart (RedoNewGame) over a slot archives its roster and backups: from the update loop,
-- every file is copied to slots/<n>/archive-<yyyymmdd-hhmmss>/ and emptied, so the slot starts empty. A restart archives
-- at once, because the game has converted the old saves. A new game leaves them on disk until its first save, so it
-- archives then: until that save no roster is active, and a new game given up leaves the roster as it was. A new game
-- plus (RedoNewGameSkip) keeps the roster. If the copy fails the roster stays in place
-- (log line). Archives are never read or deleted by the mod.
-- The four progression hooks install all or nothing: if any hooked method cannot be found after a game update, no
-- hook is installed and the menu says so. The menu also shows the loaded save slot (Slot 1-3, or "Slot unknown"),
-- tracked from the game's start and load requests; the decisions live in Retinue/slot.lua.
-- Notices: a Return that restored a member ("<name> returned — Lv N restored") or kept the game's higher level, and a roster that is
-- locked, read-only or of an unknown slot (once per load), show in the game's centred dialog for 3 seconds
-- (GuiManager.requestNoButtonDialog, closed by the mod with requestHideDialog). That dialog is a modal that shares its
-- widget with the game's own dialogs, so a notice only shows after nothing else has been up for a second (no dialog, menu,
-- cutscene or talk; out of the world it waits), and only a dialog that is still ours is closed. All of it runs in the
-- UpdateBehavior callback, where the check and the call happen together (a script reset also closes a notice that is up).
-- If a needed game method is missing, the texts go to the log instead ("notice (not shown)").
-- Talk menu: talking to a hired party pawn shows a fourth row, "Adopt" (a Rift pawn that is not in the roster) or "Release (Retinue
-- · Lv N)" (a member in the party), inserted before Never mind in the pre of ui021601.reqDisp when the menu is the pawn's root
-- menu. Picking it opens the Talk sub-menu, whose rows are relabelled as the confirm ("Confirm adopt" / "Confirm release",
-- Cancel); the confirm row adopts or releases with the same rules as the Retinue menu, any other
-- pick cancels, and both return to the root menu (a refusal shows as a notice). Anything unrecognised or missing leaves the
-- menu vanilla (a missing one shows in the menu, an unrecognised root menu in the log).
-- Marks: a present member's name header on pause > Status (the page's PawnInfo and CharaTab texts) reads "<name> · Retinue", and the
-- Rift's Previous Hires lists every roster member as "★ <name> · Lv N" (N from the backup; no level: "★ <name>"), by Offline ID, from
-- the posts of ui060601_01.setupPawn, PawnInfo2Ref.setup, CharaChangeRef.updateName and ui041401.ResItem.updateDisp. A mark is
-- stripped and rewritten on every refresh, never stacked. The Status group and the Rift group each install all or nothing: a
-- missing method or field leaves that page vanilla (a menu line, one log line).
--
-- Do NOT deploy tools/experiments/Retinue_Exp_Hooks.lua alongside this script: both would hook the same
-- methods and rewrite the same arguments.
--
-- Layout: this file is only wiring (requires, the shared state, the REFramework callbacks and the menu).
-- The decisions live in Retinue/{targets,roster,progression,errlog,status,opencalls,config,slot,backup,departure,
-- lifecycle,reconcile,archive,labels,notices,talk_menu,marks}.lua (pure, tested by tests/run.sh). The REFramework glue is Retinue/hooks.lua plus
-- Retinue/game/: jsonfile (verified JSON file
-- reads and writes and deletes), config_store (config.json), roster_store (the active slot's roster.json),
-- backup_store and pawn_state (the member backups and the pawn read behind them), archive_store (the archive of a
-- slot's roster on a new playthrough), roster_menu (the roster part of
-- the menu), progression_hooks (the four hooks and the isSubPawn lookup), party (the party views and status rows),
-- slot_hooks (the start, load and save request hooks behind the save slot, and the in-the-world signal), lifecycle_hooks
-- (the dismiss and hire hooks; pawn_state also does the restore writes) and notice_screen (the notice dialog: show,
-- hide, and the reads that say when it is safe), talk_menu (the row in a hired pawn's talk menu, the confirm, the
-- pick and the action) and marks (the hooks and widget writes behind the Status and Previous Hires marks).
-- Every hook body runs under pcall.

local errlog = require("Retinue.errlog")
local status = require("Retinue.status")
local config_store = require("Retinue.game.config_store")
local progression_hooks = require("Retinue.game.progression_hooks")
local party_reader = require("Retinue.game.party")
local pawn_state = require("Retinue.game.pawn_state")
local backup_store = require("Retinue.game.backup_store")
local archive_store = require("Retinue.game.archive_store")
local roster_store = require("Retinue.game.roster_store")
local roster_menu = require("Retinue.game.roster_menu")
local targets = require("Retinue.targets")
local slot = require("Retinue.slot")
local slot_hooks = require("Retinue.game.slot_hooks")
local lifecycle_hooks = require("Retinue.game.lifecycle_hooks")
local lifecycle = require("Retinue.lifecycle")
local labels = require("Retinue.labels")
local notices = require("Retinue.notices")
local notice_screen = require("Retinue.game.notice_screen")
local talk_menu = require("Retinue.game.talk_menu")
local marks_glue = require("Retinue.game.marks")

local state = { enabled = true, available = false, targets = {}, in_world = false }

local report = errlog.new(function(msg) log.error(msg) end)

-- Order matters: the config is read (and its warnings logged) before the hooks are installed.
local store = config_store.open(report)
state.enabled = store.settings.progression

local prog_hooks = progression_hooks.install(state, report)
state.available = prog_hooks.available

local party = party_reader.new(report)

local tracker = slot_hooks.install(report)
local pawns = pawn_state.new(report)
local backups = backup_store.new(report, pawns.read)
local retinue = roster_store.new(report, backups)
local menu = roster_menu.new()
local screen = notice_screen.new(report)
local queue = notices.new(notices.HOLD_SECONDS, notices.SETTLE_SECONDS)
local once = notices.new_once()
local life_hooks = lifecycle_hooks.install(report, retinue, backups)
local flow = lifecycle.new{
    retinue = retinue, backups = backups, pawns = pawns, party = party, drain = life_hooks.drain,
    log_line = function(text) log.error("[Retinue] " .. text) end, notify = function(text) queue:push(text) end,
    report = report,
}
local talk = talk_menu.new(report, {
    store = retinue, party = party, backups = backups, notify = function(text) queue:push(text) end,
})
local marks = marks_glue.new(report, { store = retinue, backups = backups })

-- UpdateBehavior, game thread, after flow.tick: the queued notices. notices.drive reads busy() in this callback, the one
-- that shows, and is_mine(text) in the one that hides: a show or a hide over a game dialog softlocks the game (findings
-- 0009 P6).
local function tick_notices(now)
    queue:sync(retinue.generation)
    if once:due(retinue.generation, state.in_world and flow.settled()) then
        -- The session's unit, not the roster's: a new game waiting for its first save has no roster and nothing wrong.
        local text = labels.roster_problem(retinue.roster, tracker.session.unit)
        if text then queue:push(text) end
    end
    -- One log line per show, hide and drop, with the game's dialog state (kept from the ticket 23 rerun diagnostics).
    local action, text = notices.drive(queue, screen, now, state.in_world)
    if action then
        log.error("[Retinue] notice " .. action .. ": " .. text .. " | " .. screen.describe())
    end
end

-- Clear the open-call stack at the start of each game update, on the game thread: re.on_frame may run on
-- the render thread, where a clear could fall between a rewritten core pre-hook and its notification. The restore
-- writes run here for the same reason; they do not depend on the progression checkbox.
re.on_pre_application_entry("UpdateBehavior", function()
    prog_hooks.clear_calls()
    life_hooks.begin_update()
    local ok_t, err_t = pcall(talk.tick, os.clock())
    if not ok_t then report("talk menu", err_t) end
    local ok, err = pcall(flow.tick, os.clock(), state.in_world)
    if not ok then report("lifecycle", err) end
    local ok_n, err_n = pcall(tick_notices, os.clock())
    if not ok_n then report("notices", err_n) end
end)

re.on_frame(function()
    party.refresh()
    local ok, err = pcall(tracker.update, party.has_main_pawn())
    if not ok then report("slot", err) end
    -- Before the roster store reads the slot: a roster due for its archive is archived (and emptied) first.
    local ok_a, err_a = pcall(archive_store.run, tracker.session, report)
    if not ok_a then report("archive", err_a) end
    -- Fail closed: any failure below leaves nobody to progress.
    -- The archives term: a hook can land between take_archive and this call on another thread, so a roster read just
    -- before the archive would otherwise stay active and be written back over the emptied file. The count changes,
    -- and the roster is read again.
    local session = tracker.session
    local ok_roster, err_roster = pcall(retinue.update, tracker.unit(), party,
        session.starts + session.loads + session.archives)
    if not ok_roster then report("roster", err_roster) end
    -- The lifecycle events and the backup poll run whatever the progression toggle says; they only need the roster
    -- and the world.
    local world = false
    if ok_roster then
        world = tracker.in_world(party.has_main_pawn())
        local ok_l, err_l = pcall(flow.update, os.clock(), world)
        if not ok_l then report("lifecycle", err_l) end
        local ok_b, err_b = pcall(backups.poll, retinue, world and flow.settled(), os.clock())
        if not ok_b then report("backup", err_b) end
    end
    state.in_world = world
    local targets_set = {}
    if ok_roster and prog_hooks.is_hired then
        local ok_t, res = pcall(targets.build, party.views(), retinue.roster, prog_hooks.is_hired)
        if ok_t then targets_set = res else report("targets", res) end
    end
    state.targets = targets_set
end)

local function draw()
    local changed, value = imgui.checkbox("Adopted pawns gain levels and vocation ranks", state.enabled)
    if changed then
        state.enabled = value -- takes effect even if the write below fails
        store:save(value)
    end
    if store.save_failed then imgui.text("Could not save config.json (see log)") end
    for _, w in ipairs(store.warnings) do imgui.text((w:gsub("^%[Retinue%] ", ""))) end
    local rows = party.rows(state.targets)
    imgui.text(party.failed and "Status unavailable (see log)" or status.format(rows))
    menu:draw(retinue, party, slot.label(tracker.unit()), backups, flow)
    -- Escape hatch (ticket 23 rerun): a notice nobody closed blocks the game's input. Hides the shared dialog whatever is
    -- on it, so a game dialog up now would be closed too: only for a game that is stuck with nothing visible.
    if imgui.button("Close notice (game stuck)") then
        log.error("[Retinue] notice force-hide: " .. screen.describe())
        screen.hide()
    end
    for _, method_name in ipairs(tracker.missing) do
        imgui.text("Slot tracking unavailable: " .. method_name .. " not found (game update?)")
    end
    for _, method_name in ipairs(life_hooks.missing) do
        imgui.text("Departure tracking unavailable: " .. method_name .. " not found (game update?)")
    end
    for _, name in ipairs(talk.missing) do
        imgui.text("Talk menu unavailable: " .. name .. " not found (game update?)")
    end
    for _, name in ipairs(marks.missing) do
        imgui.text("Retinue marks unavailable: " .. name .. " not found (game update?)")
    end
    for _, method_name in ipairs(prog_hooks.missing) do
        imgui.text("Progression unavailable: " .. method_name .. " not found (game update?)")
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("Retinue") then
        local ok, err = pcall(draw)
        if not ok then imgui.text("UI error: " .. tostring(err)) end
        imgui.tree_pop()
    end
end)

-- A script reset (or the mod being unloaded) with a notice up: the one game call outside UpdateBehavior. A panel nobody
-- closes blocks the game's input for good, and a fresh script would not know it. Closed only while it is still ours.
re.on_script_reset(function()
    local ok, err = pcall(function()
        if queue.showing and screen.is_mine(queue.showing) == true then screen.hide() end
    end)
    if not ok then report("notices", err) end
end)
