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
-- The four progression hooks install all or nothing: if any hooked method cannot be found after a game update, no
-- hook is installed and the menu says so. The menu also shows the loaded save slot (Slot 1-3, or "Slot unknown"),
-- tracked from the game's start and load requests; the decisions live in Retinue/slot.lua.
--
-- Do NOT deploy tools/experiments/Retinue_Exp_Hooks.lua alongside this script: both would hook the same
-- methods and rewrite the same arguments.
--
-- Layout: this file is only wiring (requires, the shared state, the three REFramework callbacks and the menu).
-- The decisions live in Retinue/{targets,roster,progression,errlog,status,opencalls,config,slot}.lua (pure, tested
-- by tests/run.sh). The REFramework glue is Retinue/hooks.lua plus Retinue/game/: jsonfile (verified JSON file
-- reads and writes), config_store (config.json), roster_store (the active slot's roster.json), roster_menu (the
-- roster part of the menu), progression_hooks (the four hooks and the isSubPawn lookup), party (the party views
-- and status rows) and slot_hooks (the start/load request hooks behind the save slot).
-- Every hook body runs under pcall.

local errlog = require("Retinue.errlog")
local status = require("Retinue.status")
local config_store = require("Retinue.game.config_store")
local progression_hooks = require("Retinue.game.progression_hooks")
local party_reader = require("Retinue.game.party")
local roster_store = require("Retinue.game.roster_store")
local roster_menu = require("Retinue.game.roster_menu")
local targets = require("Retinue.targets")
local slot = require("Retinue.slot")
local slot_hooks = require("Retinue.game.slot_hooks")

local state = { enabled = true, available = false, targets = {} }

local report = errlog.new(function(msg) log.error(msg) end)

-- Order matters: the config is read (and its warnings logged) before the hooks are installed.
local store = config_store.open(report)
state.enabled = store.settings.progression

local prog_hooks = progression_hooks.install(state, report)
state.available = prog_hooks.available

local party = party_reader.new(report)

local tracker = slot_hooks.install(report)
local retinue = roster_store.new(report)
local menu = roster_menu.new()

-- Clear the open-call stack at the start of each game update, on the game thread: re.on_frame may run on
-- the render thread, where a clear could fall between a rewritten core pre-hook and its notification.
re.on_pre_application_entry("UpdateBehavior", function()
    prog_hooks.clear_calls()
end)

re.on_frame(function()
    party.refresh()
    local ok, err = pcall(tracker.update, party.has_main_pawn())
    if not ok then report("slot", err) end
    -- Fail closed: any failure below leaves nobody to progress.
    local ok_roster, err_roster = pcall(retinue.update, tracker.unit(), party)
    if not ok_roster then report("roster", err_roster) end
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
    menu:draw(retinue, party, slot.label(tracker.unit()))
    for _, method_name in ipairs(tracker.missing) do
        imgui.text("Slot tracking unavailable: " .. method_name .. " not found (game update?)")
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
