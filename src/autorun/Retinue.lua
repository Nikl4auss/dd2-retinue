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
-- The decisions live in Retinue/{targets,progression,errlog,status,opencalls,config}.lua (pure, tested by
-- tests/run.sh); this file and Retinue/hooks.lua are the REFramework glue. Every hook body runs under pcall.

local config = require("Retinue.config")
local errlog = require("Retinue.errlog")
local hooks = require("Retinue.hooks")
local opencalls = require("Retinue.opencalls")
local progression = require("Retinue.progression")
local status = require("Retinue.status")
local targets = require("Retinue.targets")

local state = { enabled = true, available = false, targets = {} }
local missing = {}

local report = errlog.new(function(msg) log.error(msg) end)

local calls = opencalls.new()

-- config.json is read once, here, and written only when the checkbox changes (never at load, never by
-- the config-save callback). Returns status, data for config.resolve. fs.read returns "" for a missing and
-- for an empty file alike, so an empty file counts as missing (no warning).
local function read_config()
    if fs and fs.read then
        local ok, text = pcall(fs.read, config.PATH)
        if not ok or text == nil or text == "" then return "missing" end
        local okd, data = pcall(json.load_string, text)
        if not okd or data == nil then return "unparseable" end
        return "ok", data
    end
    -- Without fs.read, an unparseable file reads as missing (json.load_file returns nil for both).
    local ok, data = pcall(json.load_file, config.PATH)
    if not ok or data == nil then return "missing" end
    return "ok", data
end

local settings, config_warnings, config_base = config.resolve(read_config())
for _, w in ipairs(config_warnings) do log.warn(w) end
state.enabled = settings.progression

-- Set when the last config write failed; cleared by the next successful one.
local config_save_failed = false

-- json.dump_file returns true even when the file cannot be opened (read-only or locked), so read it back.
local function written(value)
    if not (fs and fs.read) then return true end
    local okr, text = pcall(fs.read, config.PATH)
    if not okr then return false end
    local okd, back = pcall(json.load_string, text)
    return okd and type(back) == "table" and back.progression == value
end

local function save_config(value)
    local out = config.merge(config_base, { progression = value })
    local ok, res = pcall(json.dump_file, config.PATH, out)
    if ok and res ~= false and written(value) then
        config_base = out
        config_save_failed = false
    else
        config_save_failed = true
        local err = res
        if ok then
            if res == false then
                err = "dump_file returned false"
            else
                err = "file unchanged after write (read-only or locked?)"
            end
        end
        report("config write", err)
    end
end

-- Core entries (checkLevelUp, addJobPoint) push a frame for every call, with real = nil unless they rewrote;
-- the swap entries (dispLevelUpUI, reqJobRankUp) look only at the top frame. The write is the last statement
-- and frame.real is set only after it succeeds, so an error leaves the args as passed and no renaming frame.
-- Booleans, exp and job points are never read or written.
local function make_entry(spec)
    if spec.role == "core" then
        return {
            key = spec.key, type = spec.type, sig = spec.sig,
            pre = function(args)
                local frame, overflowed = calls:push(spec.key)
                if overflowed then report("opencalls", "stack overflow, reset") end
                local id = hooks.arg_u32(args[spec.id_arg])
                local new = progression.rewrite_id(id, state)
                if new then
                    args[spec.id_arg] = sdk.to_ptr(new)
                    frame.real = id
                end
            end,
            post = function() calls:pop(spec.key) end,
        }
    end
    return {
        key = spec.key, type = spec.type, sig = spec.sig,
        pre = function(args)
            local real = calls:swap_id(hooks.arg_u32(args[spec.id_arg]))
            if real then args[spec.id_arg] = sdk.to_ptr(real) end
        end,
    }
end

local entries = {}
for i, spec in ipairs(hooks.SPECS) do entries[i] = make_entry(spec) end

state.available, missing = hooks.install(entries, report)

-- Party read: called, never hooked.
local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")
if not m_is_sub then
    -- Without it no pawn can be a target: say so instead of failing silently.
    state.available = false
    missing[#missing + 1] = "app.PawnUtil.isSubPawn(app.CharacterID)"
end

local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")

-- Set by refresh_targets each frame; read by draw. party_loaded: PawnManager and its party list exist.
-- target_charas: app.Character of each party pawn in state.targets, in party order.
local party_loaded = false
local target_charas = {}

local function is_hired(id)
    local r = m_is_sub:call(nil, id)
    return r == true or r == 1
end

local function refresh_targets()
    state.targets = {}
    party_loaded = false
    target_charas = {}
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then return end
    local party = pm:get_field("_PartyPawnList")
    if not party then return end
    party_loaded = true -- a save is loaded; without isSubPawn there are simply no targets
    if not m_is_sub then return end
    local party_ids, party_charas = {}, {}
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara then
            local id = hooks.to_u32(chara:call("get_CharaID"))
            if id ~= nil then
                local n = #party_ids + 1
                party_ids[n] = id
                party_charas[n] = chara
            end
        end
    end
    local set = targets.build(party_ids, is_hired)
    local charas = {}
    for i, id in ipairs(party_ids) do
        if set[id] then charas[#charas + 1] = party_charas[i] end
    end
    state.targets = set
    target_charas = charas
end

-- Clear the open-call stack at the start of each game update, on the game thread: re.on_frame may run on
-- the render thread, where a clear could fall between a rewritten core pre-hook and its notification.
re.on_pre_application_entry("UpdateBehavior", function()
    calls:clear()
end)

local refresh_failed = false

re.on_frame(function()
    local ok, err = pcall(refresh_targets)
    refresh_failed = not ok
    if not ok then
        state.targets = {}
        party_loaded = false
        target_charas = {}
        report("refresh", err)
    end
end)

-- One status-line row. Each field is read under its own pcall, so one failure shows "?" for that field only.
local function read_row(chara)
    local function try(fn)
        local ok, v = pcall(fn)
        if ok then return v end
        return nil
    end
    local human = try(function() return chara:call("get_Human") end)
    local st = human and try(function() return human:call("get_StatusContext") end)
    local jc = human and try(function() return human:call("get_JobContext") end)
    local job = jc and try(function() return jc:call("get_Job") end)
    local name = m_gui_name and try(function() return m_gui_name:call(nil, chara) end)
    return {
        name = name ~= nil and tostring(name) or nil,
        level = st and try(function() return st:call("get_Level") end) or nil,
        job = job,
        rank = jc and job and try(function() return jc:call("calcJobRank", job) end) or nil,
        discipline = jc and try(function() return jc:call("get_ConsumableExpProp") end) or nil,
    }
end

local function draw()
    local changed, value = imgui.checkbox("Hired pawns gain levels and vocation ranks", state.enabled)
    if changed then
        state.enabled = value -- takes effect even if the write below fails
        save_config(value)
    end
    if config_save_failed then imgui.text("Could not save config.json (see log)") end
    local rows = nil
    if party_loaded then
        rows = {}
        for i, chara in ipairs(target_charas) do rows[i] = read_row(chara) end
    end
    imgui.text(refresh_failed and "Status unavailable (see log)" or status.format(rows))
    for _, method_name in ipairs(missing) do
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
