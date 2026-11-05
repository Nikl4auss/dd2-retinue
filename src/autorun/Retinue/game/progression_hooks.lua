-- REFramework glue: the four progression hooks and the isSubPawn lookup (uses sdk).
-- The decisions live in Retinue/{progression,opencalls,hooks}.lua.

local hooks = require("Retinue.hooks")
local opencalls = require("Retinue.opencalls")
local progression = require("Retinue.progression")

local M = {}

-- state: the shared { enabled, available, targets } table (read by progression.rewrite_id).
-- Returns { available = bool, missing = {strings}, is_hired = function(id) -> bool | nil (nil when isSubPawn
--           is missing), clear_calls = function() }
function M.install(state, report)
    local calls = opencalls.new()

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

    local available, missing = hooks.install(entries, report)

    -- Party read: called, never hooked.
    local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
    local m_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")
    if not m_is_sub then
        -- Without it no pawn can be a target: say so instead of failing silently.
        available = false
        missing[#missing + 1] = "app.PawnUtil.isSubPawn(app.CharacterID)"
    end

    local function is_hired(id)
        local r = m_is_sub:call(nil, id)
        return r == true or r == 1
    end

    return {
        available = available,
        missing = missing,
        is_hired = m_is_sub and is_hired or nil,
        -- Clear the open-call stack at the start of each game update (wired by Retinue.lua).
        clear_calls = function() calls:clear() end,
    }
end

return M
