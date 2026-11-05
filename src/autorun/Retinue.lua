-- Retinue (Dragon's Dogma 2, REFramework Lua): hired pawns level up.
--
-- Pre-hooks on app.ExpDispenser.checkLevelUp and app.ExpDispenser.addJobPoint replace the CharacterID of a
-- hired pawn in your party with the main pawn's fixed ID, so the game's own level-up path runs for them and
-- they gain levels, discipline and vocation rank from any exp source. Pre-hooks on
-- app.ExpDispenser.dispLevelUpUI and app.GuiManager.reqJobRankUp put the real ID back, so the level-up and
-- rank-up notifications name the hired pawn. The REFramework menu has a "Retinue" section with one checkbox
-- (saved in reframework/data/Retinue/config.json, on when there is no file) and a status line naming the
-- party pawns progression applies to (name, level, vocation, rank, discipline), read only while the menu is drawn. The
-- four hooks install all or nothing: if any hooked method cannot be found after a game update, no hook is
-- installed and the menu says so.
--
-- Do NOT deploy tools/experiments/Retinue_Exp_Hooks.lua alongside this script: both would hook the same
-- methods and rewrite the same arguments.
--
-- Layout: this file is only wiring (requires, the shared state, the three REFramework callbacks and the menu).
-- The decisions live in Retinue/{targets,progression,errlog,status,opencalls,config}.lua (pure, tested by
-- tests/run.sh). The REFramework glue is Retinue/hooks.lua plus Retinue/game/: config_store (config.json),
-- progression_hooks (the four hooks and the isSubPawn lookup) and party (the party read and status rows).
-- Every hook body runs under pcall.

local errlog = require("Retinue.errlog")
local status = require("Retinue.status")
local config_store = require("Retinue.game.config_store")
local progression_hooks = require("Retinue.game.progression_hooks")
local party_reader = require("Retinue.game.party")

local state = { enabled = true, available = false, targets = {} }

local report = errlog.new(function(msg) log.error(msg) end)

-- Order matters: the config is read (and its warnings logged) before the hooks are installed.
local store = config_store.open(report)
state.enabled = store.settings.progression

local prog_hooks = progression_hooks.install(state, report)
state.available = prog_hooks.available

local party = party_reader.new(state, prog_hooks.is_hired, report)

-- Clear the open-call stack at the start of each game update, on the game thread: re.on_frame may run on
-- the render thread, where a clear could fall between a rewritten core pre-hook and its notification.
re.on_pre_application_entry("UpdateBehavior", function()
    prog_hooks.clear_calls()
end)

re.on_frame(function()
    party.refresh()
end)

local function draw()
    local changed, value = imgui.checkbox("Hired pawns gain levels and vocation ranks", state.enabled)
    if changed then
        state.enabled = value -- takes effect even if the write below fails
        store:save(value)
    end
    if store.save_failed then imgui.text("Could not save config.json (see log)") end
    for _, w in ipairs(store.warnings) do imgui.text((w:gsub("^%[Retinue%] ", ""))) end
    local rows = party.rows()
    imgui.text(party.failed and "Status unavailable (see log)" or status.format(rows))
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
