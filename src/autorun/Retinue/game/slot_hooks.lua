-- REFramework glue: tracks which save slot is loaded from the game's start and load requests (uses sdk and log).
-- The decisions live in Retinue/slot.lua. Read-only: the pre-hooks never change arguments.

local hooks = require("Retinue.hooks")
local slot = require("Retinue.slot")

local M = {}

local MFM = "app.MainFlowManager"
local START_TYPE = "app.MainFlowManager.StartType"
local PHASE_TYPE = "app.MainFlowManager.Phase"

-- Installs the two pre-hooks (hooks.install, all or nothing, own entries; does not touch hooks.SPECS):
--   app.MainFlowManager requestLoadGameData(System.Int32)               global slot at args[3] (instance method)
--   app.MainFlowManager requestStartType(app.MainFlowManager.StartType) enum value at args[3]
-- Returns a tracker: { available = bool, missing = {strings}, session = slot.new_session(),
--                      update(has_main_pawn) -- call every frame; the title phase is read in here
--                      unit() -> integer|nil,
--                      in_world(has_main_pawn) -> boolean }
-- When a hook method is missing the session is never fed, so the unit stays unknown (fail closed, no fallback).
function M.install(report)
    local session = slot.new_session()
    local tracker = { available = false, missing = {}, session = session }

    -- SLOT_PER_UNIT (internal save slots per unit) is read from the game, never assumed. Cached once valid.
    local per_unit_cache = nil
    local function per_unit()
        if per_unit_cache then return per_unit_cache end
        local ok, v = pcall(function()
            return sdk.find_type_definition("app.GameSystem"):get_field("SLOT_PER_UNIT"):get_data(nil)
        end)
        local n = ok and slot.to_int(v) or nil
        if n and n >= 1 then
            per_unit_cache = n
            return n
        end
        report("slot", "SLOT_PER_UNIT unreadable")
        return nil
    end

    -- StartType value -> member name, from the enum type's static fields. Built once it has any entry.
    local start_names = nil
    local function start_name(v)
        if start_names == nil then
            local map, n = {}, 0
            pcall(function()
                for _, f in ipairs(sdk.find_type_definition(START_TYPE):get_fields()) do
                    if f:is_static() then
                        local val = f:get_data(nil)
                        if type(val) == "number" then map[val] = f:get_name(); n = n + 1 end
                    end
                end
            end)
            if n > 0 then start_names = map else return nil end
        end
        return start_names[v]
    end

    local function call_on(singleton_name, method_name, ...)
        local o = sdk.get_managed_singleton(singleton_name)
        return o and o:call(method_name, ...)
    end

    -- One log line per change of unit or source (not per request or per frame). log.error, not warn: another
    -- mod may raise the log level and drop warnings, and these lines are how the in-game check is read.
    -- detail() is only called when the line is logged.
    local last_unit, last_source = nil, nil
    local function note(detail)
        if session.unit == last_unit and session.source == last_source then return end
        last_unit, last_source = session.unit, session.source
        log.error(string.format("[Retinue] slot: %s (%s)",
            session.unit and slot.label(session.unit) or "unknown", detail()))
    end

    local entries = {
        { key = "requestLoadGameData", type = MFM, sig = "requestLoadGameData(System.Int32)",
          pre = function(args)
              if not tracker.available then return end
              local global_slot = hooks.arg_i32(args[3])
              session:on_load_request(global_slot, per_unit())
              note(function() return "load request, global slot " .. global_slot end)
          end },
        { key = "requestStartType", type = MFM, sig = "requestStartType(app.MainFlowManager.StartType)",
          pre = function(args)
              if not tracker.available then return end
              local v = hooks.arg_i32(args[3])
              local name = start_name(v)
              if name == nil then report("slot", "StartType " .. v .. " has no name") end
              -- UnitNumber matters only for NewGame (no load request follows it).
              local unit_number = nil
              if name == "NewGame" then
                  local ok, un = pcall(call_on, "app.GameSystem", "get_UnitNumber")
                  if ok then unit_number = un else report("slot", un) end
              end
              session:on_start_request(name, unit_number)
              note(function()
                  if session.source == "new_game" then return "new game" end
                  return "start request " .. tostring(name or v)
              end)
          end },
    }

    local available, missing = hooks.install(entries, report)
    tracker.available = available
    tracker.missing = missing
    for _, method_name in ipairs(missing) do
        log.error("[Retinue] slot tracking unavailable: " .. method_name .. " not found")
    end

    -- Every frame. Only the fallback needs it: a mod loaded mid-session never saw the load request, so it
    -- trusts LastLoadedSlot only when UnitNumber agrees. In the world = main pawn in the party and not the title
    -- menu phase (unreadable counts as not in the world). Once any request was seen this does nothing.
    function tracker.update(has_main_pawn)
        if not tracker.available or session.seen or not has_main_pawn then return end
        local ok, err = pcall(function()
            if call_on(MFM, "get_IsTitleMenuPhase") ~= false then return end
            local last_loaded = call_on(MFM, "get_LastLoadedSlot")
            local unit_number = call_on("app.GameSystem", "get_UnitNumber")
            session:on_world(last_loaded, unit_number, per_unit())
            note(function()
                return string.format("fallback: LastLoadedSlot %s, UnitNumber %s",
                    tostring(last_loaded), tostring(unit_number))
            end)
        end)
        if not ok then report("slot", err) end
    end

    -- The value of Phase.InGame (static field of app.MainFlowManager.Phase), cached once read.
    local in_game_cache = nil
    local function in_game_value()
        if in_game_cache ~= nil then return in_game_cache end
        local ok, v = pcall(function()
            return sdk.find_type_definition(PHASE_TYPE):get_field("InGame"):get_data(nil)
        end)
        local n = ok and slot.to_int(v) or nil
        if n == nil then
            report("slot", "Phase.InGame unreadable")
            return nil
        end
        in_game_cache = n
        return n
    end

    -- "No load in progress" (spec, Terms): the main pawn is in the party, the game is not in the title menu phase and
    -- MainFlowManager.get_FlowPhase() is Phase.InGame. Any failure (or an unreadable InGame) is false: fail closed.
    -- One log line per change, naming the phase (unverified that InGame holds during normal play: the in-game check
    -- reads these lines).
    local last_world, phase = nil, nil
    function tracker.in_world(has_main_pawn)
        local ok, res = pcall(function()
            phase = nil
            phase = slot.to_int(call_on(MFM, "get_FlowPhase"))
            if not has_main_pawn then return false end
            if call_on(MFM, "get_IsTitleMenuPhase") ~= false then return false end
            local in_game = in_game_value()
            return in_game ~= nil and phase == in_game
        end)
        if not ok then
            report("slot", res)
            res = false
        end
        local world = res == true
        if world ~= last_world then
            last_world = world
            log.error(world and "[Retinue] in the world: yes"
                or string.format("[Retinue] in the world: no (phase %s)", tostring(phase)))
        end
        return world
    end

    function tracker.unit()
        return session.unit
    end

    return tracker
end

return M
