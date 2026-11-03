-- Retinue Exp Hooks: THROWAWAY EXPERIMENT (Dragon's Dogma 2, REFramework Lua). Not part of the mod.
--
-- Unlike the probe, this script DOES hook the game and can CHANGE game state: with a variant >= 1 the
-- hired pawns in your party are made to pass app.ExpDispenser's level-up path, so they may gain levels,
-- discipline and vocation rank, and those changes are saved. BACK UP FIRST (tools/saves.sh backup <label>)
-- and follow tools/experiments/README.md.
--
-- What it answers: does lifting the hired-pawn gate on app.ExpDispenser make hired pawns level up, earn
-- discipline and rank up, and what does each hooked call receive?
--
-- Variants (cumulative, chosen in the REFramework menu, always start at 0 = no overrides):
--   0  Off: hooks only log
--   1  ExpDispenser.isSubPawn returns false for hired pawns in the party
--   2  + checkLevelUp: CharacterID rewritten to the main pawn's (and the Boolean to false, optionally)
--   3  + addJobPoint: same rewrite
--
-- Everything is logged to reframework/data/Retinue/experiments/run_<timestamp>.json (one file per session).
-- Hooks cannot be removed in REFramework, so all of them are installed at load; behaviour is gated on the
-- Lua state below. Every hook body is wrapped in pcall: a bug here must never break a game call.
-- API names were checked against this game version's il2cpp_dump.json; conventions follow Arisen's Own.

local MAIN_ID = 2283028347 -- app.CharacterID ch100000_00, the main pawn
local RUN_DIR = "Retinue/experiments/"
local RUN_FILE = RUN_DIR .. "run_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
local REFRESH_SECONDS = 1.0
local FLUSH_SECONDS = 2.0
local CALL_CAP = 20000
local ERROR_CAP = 200
local STACK_MAX = 64
local LOG_LINES = 15

local JOB_NAMES = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief", [5] = "Warrior",
    [6] = "Sorcerer", [7] = "Mystic Spearhand", [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}

local VARIANT_ITEMS = { "0 Off (no overrides)", "1 isSubPawn", "2 + checkLevelUp ID rewrite", "3 + addJobPoint ID rewrite" }

-- Session state. Deliberately not persisted: every launch starts at variant 0.
local variant, rewrite_bool, log_calls = 0, true, true
local rewrite_id = true -- variants 2-3: rewrite the CharacterID to the main pawn's
local suppress_log = false -- true while the script itself calls hooked methods (snapshots)
local targets, names, party_rows = {}, {}, {} -- targets: hired party CharacterIDs -> true
local party_status, hook_status, flush_status = "no data yet", "hooks not installed yet", ""
local snap_label = ""

local run = {
    started = os.date("%Y-%m-%d %H:%M:%S"),
    started_clock = os.clock(),
    variant_events = {},
    lvup_params = {},
    snapshots = {},
    calls = {},
    dropped = 0,
    errors = {},
    hooks = { installed = {}, missing = {} },
}
local calls = run.calls
local seq, dirty = 0, true
local last_flush, last_refresh = -FLUSH_SECONDS, -REFRESH_SECONDS
local stack = {} -- frames of in-flight hooked calls (pre pushes, post pops)

local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_pu_is_sub = td_pawn_util and td_pawn_util:get_method("isSubPawn(app.CharacterID)")
local td_exp = sdk.find_type_definition("app.ExpDispenser")
local m_exp_is_sub = td_exp and td_exp:get_method("isSubPawn(app.CharacterID)")
local td_guibase = sdk.find_type_definition("app.GUIBase")
local m_gui_name = td_guibase and td_guibase:get_method("getName(app.Character)")

-- ---------------------------------------------------------------------------------------------------------
-- Small helpers

-- Returns the value, or "ERR: ..." so one broken read never hides the rest.
local function try(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
    return "ERR: " .. tostring(v)
end

local function str(v)
    if v == nil then return "nil" end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and s then return tostring(s) end
    end
    return tostring(v)
end

-- Makes a value safe for json.dump_file (no userdata/functions).
local function sanitize(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" or t == "nil" then return v end
    if t == "table" then
        local o = {}
        for k, x in pairs(v) do o[k] = sanitize(x) end
        return o
    end
    return str(v)
end

local function wall() return os.date("%H:%M:%S") end

local function log_error(where, err)
    if #run.errors < ERROR_CAP then
        run.errors[#run.errors + 1] = { t = os.clock(), where = where, err = tostring(err) }
        dirty = true
    end
end

local function to_u32(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return i & 0xFFFFFFFF end
    end
    return v
end

-- Hook argument decoding (args[n] are raw pointer-sized values).
local function arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end
local function arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end
local function arg_bool(a) return (sdk.to_int64(a) & 1) == 1 end
local function arg_nonnull(a) return sdk.to_int64(a) ~= 0 end

local function read_int_array(arr)
    if arr == nil then return nil end
    local out = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do out[i] = type(v) == "number" and v or str(v) end
        return out
    end
    local n = arr:call("get_Length")
    for i = 0, n - 1 do
        local v = arr:call("GetValue", i)
        out[i + 1] = type(v) == "number" and v or str(v)
    end
    return out
end

local function job_label(job)
    if type(job) ~= "number" then return str(job) end
    return string.format("%d (%s)", job, JOB_NAMES[job] or "?")
end

local function tag_of(id)
    if id == MAIN_ID then return "main" end
    if targets[id] then return "hired" end
    return "other"
end

-- HumanStatusContext numbers.
local function hs_numbers(hs)
    return {
        level = try(function() return hs:call("get_Level") end),
        exp = try(function() return hs:call("get_Exp") end),
    }
end

-- JobContext numbers. CulmativeExp is recorded whole: the index-to-vocation mapping is not assumed.
local function jc_numbers(jc, arg_job)
    local t = {}
    t.discipline = try(function() return jc:get_field("ConsumableExp") end)
    t.culmative_exp = try(function() return read_int_array(jc:get_field("CulmativeExp")) end)
    local cur = try(function() return jc:get_field("CurrentJob") end)
    if type(cur) ~= "number" then cur = try(function() return jc:call("get_Job") end) end
    t.current_job = cur
    if type(cur) == "number" then
        t.rank = try(function() return jc:call("calcJobRank", cur) end)
    end
    if type(arg_job) == "number" and arg_job ~= cur then
        t.arg_job = arg_job
        t.rank_arg_job = try(function() return jc:call("calcJobRank", arg_job) end)
    end
    return t
end

local function ctx_numbers(frame)
    local c = {}
    if frame.hs then c.hs = hs_numbers(frame.hs) end
    if frame.jc then c.jc = jc_numbers(frame.jc, frame.job) end
    if c.hs == nil and c.jc == nil then return nil end
    return c
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook specs. `base` is the args index of the first parameter (the CharacterID): static methods start at
-- args[2] (args[1] is the thread context); instance methods have `this` at args[2], parameters from args[3].
-- `params` lists the parameters after the CharacterID; parameter k sits at args[base + k].
-- `rewrite`: variant gate and the 1-based position (counting from the CharacterID as 0) of the Boolean.

local function P(name, kind) return { name, kind } end

local EXP = "app.ExpDispenser"
local SPECS = {
    { key = "isSubPawn", type = EXP, sig = "isSubPawn(app.CharacterID)", base = 2, params = {}, is_sub = true },
    { key = "addExpAndJobPoint[id,i,i]", type = EXP, base = 2,
      sig = "addExpAndJobPoint(app.CharacterID, System.Int32, System.Int32)",
      params = { P("i1", "i32"), P("i2", "i32") } },
    { key = "addExpAndJobPoint[id,i,chara,dmg]", type = EXP, base = 2,
      sig = "addExpAndJobPoint(app.CharacterID, System.Int32, app.Character, app.HitController.DamageInfo)",
      params = { P("i1", "i32"), P("chara", "chara"), P("damage_nonnull", "ptr") } },
    { key = "addExpAndJobPoint[id,i,i,chara]", type = EXP, base = 2,
      sig = "addExpAndJobPoint(app.CharacterID, System.Int32, System.Int32, app.Character)",
      params = { P("i1", "i32"), P("i2", "i32"), P("chara", "chara") } },
    { key = "addExpAndJobPoint[7arg]", type = EXP, base = 2, snap = true,
      sig = "addExpAndJobPoint(app.CharacterID, app.HumanStatusContext, app.JobContext, System.Int32, System.Int32, System.Boolean, app.DragonHermitContext)",
      params = { P("hs", "hs"), P("jc", "jc"), P("exp", "i32"), P("jobPoint", "i32"), P("flag", "bool"),
                 P("dragonHermit_nonnull", "ptr") } },
    { key = "addJobPoint", type = EXP, base = 2, snap = true,
      sig = "addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)",
      params = { P("jc", "jc"), P("jobPoint", "i32"), P("flag", "bool") },
      rewrite = { min_variant = 3, bool_param = 3 } },
    { key = "addJobPointInternal", type = EXP, base = 2, snap = true,
      sig = "addJobPointInternal(app.CharacterID, app.Character.JobEnum, app.JobContext, System.Int32, System.Boolean)",
      params = { P("job", "job"), P("jc", "jc"), P("jobPoint", "i32"), P("flag", "bool") } },
    { key = "checkLevelUp", type = EXP, base = 2, snap = true,
      sig = "checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)",
      params = { P("hs", "hs"), P("job", "job"), P("flag", "bool"), P("dragonHermit_nonnull", "ptr") },
      rewrite = { min_variant = 2, bool_param = 3 } },
    { key = "dispLevelUpUI", type = EXP, base = 2,
      sig = "dispLevelUpUI(app.CharacterID, System.Int32, System.Int32)",
      params = { P("prevLv", "i32"), P("nextLv", "i32") } },
    { key = "GuiManager.reqLevelUp", type = "app.GuiManager", base = 3,
      sig = "reqLevelUp(app.CharacterID, System.Int32, System.Int32)",
      params = { P("prevLv", "i32"), P("nextLv", "i32") } },
    { key = "GuiManager.reqJobRankUp", type = "app.GuiManager", base = 3,
      sig = "reqJobRankUp(app.CharacterID, app.Character.JobEnum, System.Int32, System.Int32)",
      params = { P("job", "job"), P("i1", "i32"), P("i2", "i32") } },
}
local SPEC_BY_KEY = {}
for _, s in ipairs(SPECS) do SPEC_BY_KEY[s.key] = s end

-- ---------------------------------------------------------------------------------------------------------
-- Logging

local function decode_args(spec, args, frame)
    local out = {}
    for k, p in ipairs(spec.params) do
        local name, kind, a = p[1], p[2], args[spec.base + k]
        local ok, v = pcall(function()
            if kind == "i32" then return arg_i32(a)
            elseif kind == "bool" then return arg_bool(a)
            elseif kind == "ptr" then return arg_nonnull(a)
            elseif kind == "job" then
                local j = arg_i32(a)
                frame.job = j
                out[name .. "_name"] = JOB_NAMES[j]
                return j
            elseif kind == "hs" then
                frame.hs = sdk.to_managed_object(a)
                return frame.hs ~= nil
            elseif kind == "jc" then
                frame.jc = sdk.to_managed_object(a)
                return frame.jc ~= nil
            elseif kind == "chara" then
                local o = sdk.to_managed_object(a)
                if o == nil then return "nil" end
                return str(try(function() return m_gui_name:call(nil, o) end))
            end
            return "?"
        end)
        out[name] = ok and v or ("ERR: " .. tostring(v))
    end
    return out
end

local function brief_ctx(c)
    if not c then return "" end
    local p = {}
    if c.hs then p[#p + 1] = string.format("L%s xp%s", str(c.hs.level), str(c.hs.exp)) end
    if c.jc then p[#p + 1] = string.format("disc%s rk%s", str(c.jc.discipline), str(c.jc.rank)) end
    return table.concat(p, " ")
end

local function fmt_entry(e)
    local spec = SPEC_BY_KEY[e.method]
    local parts = { string.format("#%d t=%.1f %s%s id=%s(%s)", e.seq, e.t, string.rep(">", e.depth), e.method,
        tostring(e.id), e.tag) }
    if spec then
        for _, p in ipairs(spec.params) do
            local v = e.args and e.args[p[1]]
            if v ~= nil and p[2] ~= "hs" and p[2] ~= "jc" then parts[#parts + 1] = p[1] .. "=" .. tostring(v) end
        end
    end
    if e.ret ~= nil then parts[#parts + 1] = "ret=" .. tostring(e.ret) end
    if e.count and e.count > 1 then parts[#parts + 1] = "x" .. e.count end
    if e.ctx_before then
        parts[#parts + 1] = "[" .. brief_ctx(e.ctx_before) .. (e.ctx_after and (" -> " .. brief_ctx(e.ctx_after)) or "") .. "]"
    end
    if e.override then parts[#parts + 1] = "OVERRIDE" end
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------------------------------------
-- Hook bodies

local function pre_body(spec, args)
    local depth = #stack
    if depth >= STACK_MAX then
        stack = {}
        depth = 0
        log_error("stack", "in-flight stack overflow, reset")
    end
    local frame = { key = spec.key, depth = depth }
    stack[depth + 1] = frame -- pushed first: post must find it even if the rest of this body throws
    seq = seq + 1

    local id = arg_u32(args[spec.base])
    frame.id = id

    local entry
    if log_calls and not suppress_log then
        if #calls >= CALL_CAP then
            run.dropped = run.dropped + 1
        else
            entry = {
                seq = seq, t = os.clock(), depth = depth, method = spec.key,
                id = id, tag = tag_of(id), name = names[id],
            }
            entry.args = decode_args(spec, args, frame)
            if spec.snap then entry.ctx_before = ctx_numbers(frame) end
        end
    end

    local rw = spec.rewrite
    if rw and variant >= rw.min_variant and targets[id] then
        local ov = { id_from = id, id_to = rewrite_id and MAIN_ID or id }
        local bi = spec.base + rw.bool_param
        if rewrite_bool then
            ov.bool_from = arg_bool(args[bi])
            ov.bool_to = false
        end
        -- Reads done: now write. Arisen's Own does the same (ID to the main pawn's, Boolean to 0).
        if rewrite_bool then args[bi] = sdk.to_ptr(0) end
        if rewrite_id then args[spec.base] = sdk.to_ptr(MAIN_ID) end
        if entry then entry.override = ov end
    end

    if entry then
        calls[#calls + 1] = entry
        frame.entry = entry
        dirty = true
    end
end

local function post_body(spec, retval)
    local frame
    for i = #stack, 1, -1 do
        if stack[i].key == spec.key then
            frame = stack[i]
            for j = #stack, i, -1 do stack[j] = nil end -- also drops frames whose post never ran
            break
        end
    end
    if not frame then return nil end

    local entry = frame.entry
    local result
    if spec.is_sub then
        local ret = arg_bool(retval)
        if variant >= 1 and ret and targets[frame.id] then
            result = sdk.to_ptr(0)
            if entry then entry.override = "isSubPawn true->false" end
        end
        if entry then
            entry.ret = ret
            entry.count = 1
            -- Collapse consecutive identical isSubPawn entries (same ID, result, override, depth).
            local n = #calls
            local prev = calls[n - 1]
            if calls[n] == entry and prev and prev.method == entry.method and prev.id == entry.id
                and prev.ret == entry.ret and prev.override == entry.override and prev.depth == entry.depth then
                prev.count = (prev.count or 1) + 1
                prev.last_seq, prev.last_t = entry.seq, entry.t
                calls[n] = nil
            end
        end
    elseif entry and spec.snap then
        entry.ctx_after = ctx_numbers(frame)
    end
    return result
end

local function install_hooks()
    local installed, missing = {}, {}

    -- Method lookup: the full signature string first, then name + parameter type names (last segment).
    local function find_method(td, sig)
        local m = td:get_method(sig)
        if m then return m end
        local name, plist = sig:match("^([^%(]+)%((.*)%)$")
        if not name then return nil end
        local want = {}
        for p in plist:gmatch("[^,%s]+") do want[#want + 1] = p:match("([^%.]+)$") end
        for _, cand in ipairs(td:get_methods()) do
            if cand:get_name() == name then
                local ok, types = pcall(function() return cand:get_param_types() end)
                if ok and type(types) == "table" and #types == #want then
                    local same = true
                    for i, t in ipairs(types) do
                        local full = t:get_full_name() or ""
                        if full:match("([^%.]+)$") ~= want[i] then same = false; break end
                    end
                    if same then return cand end
                end
            end
        end
        return nil
    end

    for _, spec in ipairs(SPECS) do
        local ok, err = pcall(function()
            local td = sdk.find_type_definition(spec.type)
            if not td then error("type not found: " .. spec.type) end
            local m = find_method(td, spec.sig)
            if not m then error("method not found: " .. spec.sig) end
            sdk.hook(m,
                function(args)
                    local ok_pre, e = pcall(pre_body, spec, args)
                    if not ok_pre then log_error("pre " .. spec.key, e) end
                    return sdk.PreHookResult.CALL_ORIGINAL
                end,
                function(retval)
                    local ok_post, res = pcall(post_body, spec, retval)
                    if not ok_post then
                        log_error("post " .. spec.key, res)
                        return retval
                    end
                    if res ~= nil then return res end
                    return retval
                end)
        end)
        if ok then installed[#installed + 1] = spec.key
        else
            missing[#missing + 1] = spec.key
            log_error("install " .. spec.key, err)
        end
    end

    run.hooks.installed, run.hooks.missing = installed, missing
    if #missing == 0 then
        hook_status = string.format("all %d hooks installed", #installed)
    else
        hook_status = string.format("%d/%d hooks installed; MISSING: %s", #installed, #SPECS, table.concat(missing, ", "))
    end
    dirty = true
end

-- ---------------------------------------------------------------------------------------------------------
-- Pawn reads (adapted from the probe)

-- ContextHolder.Contexts is Dictionary<System.Type, ContextInfoBase>.
local function holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

local function read_pawn(pawn)
    local r = {}
    local chara = pawn:call("get_CachedCharacter")
    r.slot = try(function() return pawn:call("get_PawnID") end)
    r.main_ctx_bound = try(function() return pawn:get_field("MainPawnDataContext") ~= nil end)
    if not chara then r.error = "no character"; return r end

    local id = chara:call("get_CharaID")
    r.chara_id = id
    r.dead = try(function() return chara:call("get_IsDead") end)
    r.gui_name = try(function() return m_gui_name:call(nil, chara) end)
    r.util_is_sub = try(function() return m_pu_is_sub:call(nil, id) end)
    -- Calls the hooked ExpDispenser.isSubPawn: shows the effect of variant >= 1 (log entry suppressed).
    r.exp_is_sub = try(function() return m_exp_is_sub:call(nil, id) end)

    local holder = chara:call("get_Context")
    if holder then
        r.is_store = try(function() return holder:call("get_IsStore") end)
        r.is_restore = try(function() return holder:call("get_IsRestore") end)
        r.uniq_id = try(function() return str(holder:call("get_UniqID")) end)
        r.holder_level = try(function() return holder:call("get_Level") end)

        local owner = try(holder_context, holder, "app.PawnOwnerContext")
        if type(owner) == "userdata" then
            r.owner_name = try(function() return owner:get_field("_Name") end)
            r.owner_level = try(function() return owner:get_field("_Level") end)
            r.owner_job = try(function() return job_label(owner:get_field("_Job")) end)
            r.owner_offline_id = try(function() return str(owner:get_field("_OfflineID")) end)
        else r.owner = owner == nil and "none" or owner end

        local sub = try(holder_context, holder, "app.SubPawnDataContext")
        if type(sub) == "userdata" then
            r.sub_hire_time = try(function() return sub:get_field("_HireTime") end)
        else r.sub_ctx = sub == nil and "none" or sub end
    end

    local human = chara:call("get_Human")
    if human then
        local st = human:call("get_StatusContext")
        if st then
            r.level = try(function() return st:call("get_Level") end)
            r.exp = try(function() return st:call("get_Exp") end)
        end
        local jc = human:call("get_JobContext")
        if jc then
            local job = jc:call("get_Job")
            r.job = job_label(job)
            r.job_rank = try(function() return jc:call("calcJobRank", job) end)
            r.discipline = try(function() return jc:call("get_ConsumableExpProp") end)
            r.consumable_exp = try(function() return jc:get_field("ConsumableExp") end)
            r.culmative_exp = try(function() return read_int_array(jc:get_field("CulmativeExp")) end)
        end
        local pd = human:call("get_PawnDataContext")
        if pd then
            r.data_name = try(function() return pd:get_field("_Name") end)
        end
    end
    return r
end

-- Light read for the live table.
local function read_progress(chara)
    local r = {}
    local human = chara:call("get_Human")
    if not human then return r end
    local st = human:call("get_StatusContext")
    if st then
        r.level = try(function() return st:call("get_Level") end)
        r.exp = try(function() return st:call("get_Exp") end)
    end
    local jc = human:call("get_JobContext")
    if jc then
        local job = jc:call("get_Job")
        r.job = job_label(job)
        r.rank = try(function() return jc:call("calcJobRank", job) end)
        r.discipline = try(function() return jc:call("get_ConsumableExpProp") end)
    end
    return r
end

local function take_snapshot(label)
    local ok, err = pcall(function()
        suppress_log = true
        local pawns = {}
        local pm = sdk.get_managed_singleton("app.PawnManager")
        if pm then
            local party = pm:get_field("_PartyPawnList")
            for i = 0, party:call("get_Count") - 1 do
                local pawn = party:call("get_Item", i)
                local ok_r, r = pcall(read_pawn, pawn)
                if not pawn then r = { error = "nil pawn" } elseif not ok_r then r = { error = tostring(r) } end
                pawns[#pawns + 1] = sanitize(r)
            end
        end
        run.snapshots[#run.snapshots + 1] = { label = label, time = wall(), t = os.clock(), pawns = pawns }
        dirty = true
    end)
    suppress_log = false
    if not ok then log_error("snapshot " .. tostring(label), err) end
end

-- ---------------------------------------------------------------------------------------------------------
-- Once-a-second refresh of the target set (never inside hooks; hooks only look the set up)

local auto_start_done, lvup_done, lvup_tries = false, false, 0

local function dump_lvup()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    if not cm then return false end
    local list = cm:call("get_HumanParam"):call("get_LVupInfo"):call("get_LVupParamsProp")
    local out = {}
    for i = 0, list:call("get_Count") - 1 do
        local it = list:call("get_Item", i)
        out[#out + 1] = {
            Level = try(function() return it:get_field("Level") end),
            RequiredEXP = try(function() return it:get_field("RequiredEXP") end),
        }
    end
    run.lvup_params = out
    dirty = true
    return true
end

local function refresh_party()
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then
        targets, names, party_rows = {}, {}, {}
        party_status = "PawnManager not available (load a save)"
        return
    end
    local party = pm:get_field("_PartyPawnList")
    local new_targets, new_names, rows = {}, {}, {}
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local chara = pawn and pawn:call("get_CachedCharacter")
        if chara then
            local id = to_u32(chara:call("get_CharaID"))
            local name = str(try(function() return m_gui_name:call(nil, chara) end))
            new_names[id] = name
            local is_hired = false
            if id ~= MAIN_ID then
                local sub = try(function() return m_pu_is_sub:call(nil, id) end)
                is_hired = (sub == true or sub == 1)
            end
            if is_hired then new_targets[id] = true end
            local row = try(read_progress, chara)
            if type(row) ~= "table" then row = { error = row } end
            row.id, row.name = id, name
            row.tag = (id == MAIN_ID) and "main" or (is_hired and "hired" or "other")
            rows[#rows + 1] = row
        end
    end
    targets, names, party_rows = new_targets, new_names, rows
    party_status = string.format("%d party pawns, %d hired targets", #rows, (function()
        local n = 0
        for _ in pairs(new_targets) do n = n + 1 end
        return n
    end)())
    if not auto_start_done and #rows > 0 then
        auto_start_done = true
        take_snapshot("auto:start")
    end
end

local function flush()
    last_flush = os.clock()
    local ok, err = pcall(function()
        -- Serialise a plain copy: the live tables are mutated by hooks.
        json.dump_file(RUN_FILE, run)
    end)
    if ok then
        dirty = false
        flush_status = "Flushed " .. wall()
    else
        flush_status = "Flush FAILED: " .. tostring(err)
    end
end

local function add_event(kind, extra)
    local ev = { kind = kind, t = os.clock(), wall = wall(), variant = variant, rewrite_bool = rewrite_bool, rewrite_id = rewrite_id, log_calls = log_calls }
    for k, v in pairs(extra or {}) do ev[k] = v end
    run.variant_events[#run.variant_events + 1] = ev
    dirty = true
end

local function set_variant(new)
    if new == variant then return end
    local old = variant
    variant = new
    add_event("variant", { from = old, to = new })
    take_snapshot("auto:variant->" .. new)
end

-- ---------------------------------------------------------------------------------------------------------
-- Wiring

install_hooks()
add_event("start")

re.on_frame(function()
    local now = os.clock()
    if now - last_refresh >= REFRESH_SECONDS then
        last_refresh = now
        local ok, err = pcall(refresh_party)
        if not ok then
            party_status = "refresh failed: " .. tostring(err)
            log_error("refresh_party", err)
        end
        if not lvup_done and lvup_tries < 5 then
            lvup_tries = lvup_tries + 1
            local ok_l, res = pcall(dump_lvup)
            if ok_l and res then lvup_done = true
            elseif not ok_l then log_error("dump_lvup", res) end
        end
    end
    if dirty and now - last_flush >= FLUSH_SECONDS then flush() end
end)

if re.on_script_reset then
    re.on_script_reset(function() pcall(flush) end)
end

local function draw_body()
    imgui.text("WARNING: variants >= 1 change game behaviour and saves. Back up first.")
    imgui.text(hook_status)
    imgui.text(party_status)

    local changed, idx = imgui.combo("Variant", variant + 1, VARIANT_ITEMS)
    if changed then set_variant(idx - 1) end
    local ch_id, rid = imgui.checkbox("Rewrite ID to the main pawn's (as Arisen's Own)", rewrite_id)
    if ch_id then
        rewrite_id = rid
        add_event("rewrite_id", { value = rid })
    end
    local ch_rw, rw = imgui.checkbox("Rewrite Boolean to false (as Arisen's Own)", rewrite_bool)
    if ch_rw then
        rewrite_bool = rw
        add_event("rewrite_bool", { value = rw })
    end
    local ch_log, lg = imgui.checkbox("Log calls", log_calls)
    if ch_log then
        log_calls = lg
        add_event("log_calls", { value = lg })
    end

    local tl = {}
    for id in pairs(targets) do tl[#tl + 1] = string.format("%d (%s)", id, names[id] or "?") end
    table.sort(tl)
    imgui.text("Targets (hired in party): " .. (#tl > 0 and table.concat(tl, ", ") or "none"))
    for _, r in ipairs(party_rows) do
        imgui.text(string.format("%-6s %s  Lv %s  Exp %s  Disc %s  Rank %s  %s", r.tag or "?", str(r.name),
            str(r.level), str(r.exp), str(r.discipline), str(r.rank), str(r.job)))
    end

    imgui.text(string.format("Calls seen: %d  logged entries: %d  dropped: %d  errors: %d", seq, #calls, run.dropped, #run.errors))
    for i = math.max(1, #calls - LOG_LINES + 1), #calls do
        imgui.text(fmt_entry(calls[i]))
    end

    imgui.text("Run file: reframework/data/" .. RUN_FILE)
    imgui.text(flush_status)
    local ch_l, lbl = imgui.input_text("Snapshot label", snap_label)
    if ch_l then snap_label = lbl end
    if imgui.button("Snapshot") then
        take_snapshot(snap_label ~= "" and snap_label or "manual")
    end
    imgui.same_line()
    if imgui.button("Flush log now") then flush() end
end

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Exp Hooks (EXPERIMENT)") then return end
    local ok, err = pcall(draw_body)
    if not ok then imgui.text("UI error: " .. tostring(err)) end
    imgui.tree_pop()
end)
