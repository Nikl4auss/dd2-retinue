-- REFramework glue: the four Departure and Return hooks (uses sdk and log). The decisions live in Retinue/{lifecycle,
-- departure,roster}.lua. The hooks only read the game: they never change an argument or a return value, and they do
-- no file I/O. They feed a queue that Retinue/lifecycle.lua drains from the frame loop.

local hooks = require("Retinue.hooks")
local party = require("Retinue.game.party")
local roster = require("Retinue.roster")

local M = {}

local PM = "app.PawnManager"

-- Installs (hooks.install, all or nothing, own entries; does not touch hooks.SPECS):
--   app.PawnManager dismissPawn(app.CharacterID | app.Character | app.Pawn)   instance methods: the argument is args[3]
--   app.PawnManager hirePawn(app.Character, System.Boolean) : bool            fires only on a hire
-- One dismiss fires the CharacterID overload and, nested inside it, the Pawn one; the pre of the outermost call reads
-- the full state (the pawn still in the party). Events are queued from post, so on_frame never sees a pawn that is
-- still in the party as gone.
-- Returns { available = bool, missing = {strings},
--           begin_update() -- at the start of each game update, game thread: forgets a pre whose post never came,
--           drain() -> array of events, oldest first (and starts a new queue):
--             { kind = "dismiss", id = <canonical offline id>, generation = n, snapshot = table|nil }
--             { kind = "hire",    id = <canonical offline id>, generation = n } }
-- retinue is game/roster_store's object, backups game/backup_store's (eligible, read).
function M.install(report, retinue, backups)
    local life = { available = false, missing = {} }
    local dismissing = nil -- the event of the dismiss in progress (a table), nil outside one
    local hiring = nil -- the Character argument of the hire in progress
    local queue = {}

    -- The member of retinue.roster whose pawn has this CharacterID and is in the party: id, view, member | nil.
    local function member_of(character_id)
        if retinue.roster == nil then return nil end
        for id, view in pairs(retinue.found) do
            if view.character_id == character_id then
                local m = roster.find(retinue.roster, id)
                if m then return id, view, m end
            end
        end
        return nil
    end

    local function dismiss_pre(character_id)
        if character_id == nil then return end
        local id, _, m = member_of(character_id)
        if id == nil or m.status == roster.AWAY then return end
        -- Set before the read: a read that fails still departs.
        dismissing = { kind = "dismiss", id = id, generation = retinue.generation }
        local eligible = backups.eligible(retinue, m)
        if eligible then dismissing.snapshot = backups.read(m, eligible) end
    end

    local function dismiss_post()
        if not life.available then return end
        if dismissing then
            queue[#queue + 1] = dismissing
            dismissing = nil
        end
    end

    local function chara_id(chara)
        return hooks.to_u32(chara:call("get_CharaID"))
    end

    local function dismiss_entry(key, sig, character_id_of)
        return {
            key = key, type = PM, sig = sig,
            pre = function(args)
                -- Not while a dismiss is in progress: that is its nested overload.
                if not life.available or dismissing then return end
                dismiss_pre(character_id_of(args[3]))
            end,
            post = function() dismiss_post() end,
        }
    end

    local entries = {
        dismiss_entry("dismissPawn(CharacterID)", "dismissPawn(app.CharacterID)", function(a)
            return hooks.arg_u32(a)
        end),
        dismiss_entry("dismissPawn(Character)", "dismissPawn(app.Character)", function(a)
            local chara = sdk.to_managed_object(a)
            return chara and chara_id(chara)
        end),
        dismiss_entry("dismissPawn(Pawn)", "dismissPawn(app.Pawn)", function(a)
            local pawn = sdk.to_managed_object(a)
            local chara = pawn and pawn:call("get_CachedCharacter")
            return chara and chara_id(chara)
        end),
        { key = "hirePawn", type = PM, sig = "hirePawn(app.Character, System.Boolean)",
          pre = function(args)
              if not life.available then return end
              hiring = sdk.to_managed_object(args[3])
          end,
          post = function(retval)
              local chara = hiring
              hiring = nil
              if not life.available or chara == nil then return end
              if sdk.to_int64(retval) & 1 ~= 1 then return end
              local id = party.offline_id(chara)
              if id and roster.find(retinue.roster, id) then
                  queue[#queue + 1] = { kind = "hire", id = id, generation = retinue.generation }
              end
          end },
    }

    local available, missing = hooks.install(entries, report)
    life.available = available
    life.missing = missing
    for _, method_name in ipairs(missing) do
        log.error("[Retinue] departure tracking unavailable: " .. method_name .. " not found")
    end

    -- A game exception skips a post; the next pre would then be taken for a nested one.
    function life.begin_update()
        dismissing, hiring = nil, nil
    end

    function life.drain()
        local out = queue
        queue = {}
        return out
    end

    return life
end

return M
