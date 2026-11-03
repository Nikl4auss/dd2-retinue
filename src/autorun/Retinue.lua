-- Retinue (Dragon's Dogma 2, REFramework Lua): hired pawns level up.
--
-- At this stage the mod does one thing: pre-hooks on app.ExpDispenser.checkLevelUp and
-- app.ExpDispenser.addJobPoint replace the CharacterID of a hired pawn in your party with the main pawn's
-- fixed ID, so the game's own level-up path runs for them and they gain levels, discipline and vocation
-- rank from any exp source. Notifications still name the main pawn. The REFramework menu has a
-- "Retinue" section with one checkbox (in memory only, on at load). If a hooked method cannot be found
-- after a game update, no hook is installed and the menu says so.
--
-- Do NOT deploy tools/experiments/Retinue_Exp_Hooks.lua alongside this script: both would hook the same
-- methods and rewrite the same arguments.
--
-- The decisions live in Retinue/{targets,progression,errlog}.lua (pure, tested by tests/run.sh); this file
-- and Retinue/hooks.lua are the REFramework glue. Every hook body runs under pcall.

local errlog = require("Retinue.errlog")
local hooks = require("Retinue.hooks")
local progression = require("Retinue.progression")
local targets = require("Retinue.targets")

local state = { enabled = true, available = false, targets = {} }
local missing = {}

local report = errlog.new(function(msg) log.error(msg) end)

-- Core pre body, shared by both hooks. The write is the last statement, so an error leaves the args as
-- passed. Booleans, exp and job points are never read or written.
local function make_entry(spec)
    return {
        key = spec.key, type = spec.type, sig = spec.sig,
        pre = function(args)
            local id = hooks.arg_u32(args[spec.id_arg])
            local new = progression.rewrite_id(id, state)
            if new then args[spec.id_arg] = sdk.to_ptr(new) end
        end,
    }
end

local entries = {}
for i, spec in ipairs(hooks.SPECS) do entries[i] = make_entry(spec) end

state.available, missing = hooks.install(entries, report)

-- Party read: called, never hooked.
local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")

local function is_hired(id)
    local r = m_is_sub:call(nil, id)
    return r == true or r == 1
end

local function refresh_targets()
    if not m_is_sub then
        state.targets = {}
        return
    end
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then
        state.targets = {}
        return
    end
    local party = pm:get_field("_PartyPawnList")
    if not party then
        state.targets = {}
        return
    end
    local party_ids = {}
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara then
            party_ids[#party_ids + 1] = hooks.to_u32(chara:call("get_CharaID"))
        end
    end
    state.targets = targets.build(party_ids, is_hired)
end

re.on_frame(function()
    local ok, err = pcall(refresh_targets)
    if not ok then
        state.targets = {}
        report("refresh", err)
    end
end)

local function draw()
    local changed, value = imgui.checkbox("Hired pawns gain levels and vocation ranks", state.enabled)
    if changed then state.enabled = value end
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
