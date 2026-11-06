-- REFramework glue: reads a party pawn's backup snapshot (uses sdk). The shape and the validity rules of the
-- snapshot live in Retinue/backup.lua. The readers are copied from tools/experiments (Retinue_Exp_Restore:
-- read_num_array, the equipment read; Retinue_Exp_Lifecycle: str, read_int_array for skills).

local backup = require("Retinue.backup")
local hooks = require("Retinue.hooks")
local party = require("Retinue.game.party")
local roster = require("Retinue.roster")
local slot = require("Retinue.slot")

local M = {}

local SKILL_CONTEXT = "app.HumanSkillContext"
local LIST_CAP = 64 -- same cap as the restore experiment's list reads

-- INCREASE_KEYS order -> the _IncreaseParams field of each
local INCREASE_FIELDS = {
    hit_point = "_HitPoint", stamina = "_Stamina", attack = "_Attack", defence = "_Defence",
    magic_attack = "_MagicAttack", magic_defence = "_MagicDefence", blow = "_Blow", weight = "_Weight",
}

local function str(v)
    if v == nil then return "nil" end
    if type(v) == "userdata" then
        local ok, s = pcall(function() return v:call("ToString") end)
        if ok and s then return tostring(s) end
    end
    return tostring(v)
end

-- Int32[] -> plain Lua integers. get_elements() hands back boxed elements (they come out as strings via str()), so
-- every element goes through tonumber(str(v)). An element that is not integral stays a number and fails backup.invalid.
local function read_num_array(arr)
    if arr == nil then return nil end
    local raw = {}
    local ok, elems = pcall(function() return arr:get_elements() end)
    if ok and type(elems) == "table" then
        for i, v in ipairs(elems) do raw[i] = v end
    else
        local n = arr:call("get_Length")
        for i = 0, n - 1 do raw[i + 1] = arr:call("GetValue", i) end
    end
    local out = {}
    for i, v in ipairs(raw) do
        local n = type(v) == "number" and v or tonumber(str(v))
        if n == nil then error("array element " .. i .. " is not a number: " .. str(v)) end
        out[i] = slot.to_int(n) or n
    end
    return out
end

-- An array of enum / Int32 values as numbers where the element is a number, else its ToString (a skill name).
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

-- A List<Int32> as plain integers (capped).
local function read_list_numbers(list)
    if list == nil then return nil end
    local n = list:call("get_Count")
    local out = {}
    for i = 0, math.min(n, LIST_CAP) - 1 do
        local v = list:call("get_Item", i)
        local num = type(v) == "number" and v or tonumber(str(v))
        if num == nil then error("list element " .. i .. " is not a number: " .. str(v)) end
        out[#out + 1] = slot.to_int(num) or num
    end
    return out
end

-- A number read from a field as an integer; anything else stays as it is (backup.invalid or the recorded read's
-- caller decides).
local function int(v)
    if type(v) == "number" then return slot.to_int(v) or v end
    return v
end

-- Returns { read = function(view) -> snapshot | nil, why,
--           restore = function(view, b) -> "done" | "wait", why | "mismatch", field   (game thread only) }.
-- The snapshot is backup.lua's table of a live party pawn
-- (view as party.views() builds it; name is view.name, the store overrides it with the roster's). nil + why when a
-- restored field cannot be read or the snapshot is not usable (backup.invalid). A recorded field that cannot be read
-- (the three job fields, items, skills) stays nil and is reported through report("backup <key>", err).
function M.new(report)
    local td_im = sdk.find_type_definition("app.ItemManager")
    local m_get_equip = nil
    local equip_resolved = false

    local function equip_method()
        if not equip_resolved then
            equip_resolved = true
            m_get_equip = td_im and hooks.find_method(td_im, "getEquipData(app.CharacterID)") or nil
        end
        return m_get_equip
    end

    -- The equipped item IDs; {} when the character has no equipment data.
    local function read_equip(id)
        local im = sdk.get_managed_singleton("app.ItemManager")
        if im:call("hasEquipData", id) ~= true then return {} end
        local method = equip_method()
        if not method then error("getEquipData not found") end
        local red = method:call(im, id)
        if red == nil then return {} end
        return read_list_numbers(red:call("getItemIds")) or {}
    end

    local function read_skills(chara)
        local ctx = party.holder_context(chara:call("get_Context"), SKILL_CONTEXT)
        if ctx == nil then return nil end
        local out = {}
        local arr = ctx:get_field("EquipedSkills"):get_elements()
        for i, e in ipairs(arr) do out[i] = read_int_array(e:get_field("Skills")) or {} end
        return out
    end

    -- The restored fields into b; throws when one cannot be read. Returns the job context for the recorded reads.
    local function read_restored(chara, b)
        local human = chara:call("get_Human")
        if not human then error("no Human") end
        local st = human:call("get_StatusContext")
        if not st then error("no HumanStatusContext") end
        local jc = human:call("get_JobContext")
        if not jc then error("no JobContext") end
        b.level = int(st:call("get_Level"))
        b.exp = int(st:call("get_Exp"))
        local ip = st:get_field("_IncreaseParams")
        if ip == nil then error("_IncreaseParams is nil") end
        b.increase_params = {}
        for _, key in ipairs(backup.INCREASE_KEYS) do
            b.increase_params[key] = int(ip:get_field(INCREASE_FIELDS[key]))
        end
        b.extra_status_boost = int(st:get_field("_AcquiredExtraStatusBoost"))
        b.discipline = int(jc:get_field("ConsumableExp"))
        b.culmative_exp = read_num_array(jc:get_field("CulmativeExp"))
        return jc
    end

    local reader = {}

    function reader.read(view)
        local chara = view.chara
        local b = {
            version = backup.VERSION,
            offline_id = roster.canonical_id(view.offline_id),
            name = view.name,
        }
        local ok, jc = pcall(read_restored, chara, b)
        if not ok then return nil, tostring(jc) end

        local function recorded(key, fn)
            local okr, v = pcall(fn)
            if okr then b[key] = v else report("backup " .. key, v) end
        end
        local function job_number(field)
            local v = jc:get_field(field)
            if type(v) ~= "number" then error(field .. " is not a number: " .. str(v)) end
            return int(v)
        end
        recorded("current_job", function() return job_number("CurrentJob") end)
        recorded("qualified_job_bits", function() return job_number("QualifiedJobBits") end)
        recorded("changed_job_bits", function() return job_number("ChangedJobBits") end)
        recorded("item_ids", function() return read_equip(view.character_id) end)
        recorded("skills", function() return read_skills(chara) end)

        local why = backup.invalid(b)
        if why then return nil, why end
        return b
    end

    -- The contexts a restore writes into; throws when one is missing.
    local function restore_targets(chara)
        local human = chara:call("get_Human")
        if not human then error("no Human") end
        local st = human:call("get_StatusContext")
        if not st then error("no HumanStatusContext") end
        local jc = human:call("get_JobContext")
        if not jc then error("no JobContext") end
        local ip = st:get_field("_IncreaseParams")
        if ip == nil then error("_IncreaseParams is nil") end
        local arr = jc:get_field("CulmativeExp")
        if arr == nil then error("CulmativeExp is nil") end
        return st, jc, ip, arr
    end

    local function need_int(v, what)
        local n = slot.to_int(v)
        if n == nil then error("backup value is not an integer: " .. what .. "=" .. str(v)) end
        return n
    end

    -- Writes the backup into the live pawn, game thread only (findings 0008): level, exp, the increase params, the
    -- extra status boost, the discipline and the per-vocation exp; then reads them back and compares.
    -- "done" | "wait", why (a context missing or a write threw: nothing proven, retry; every write is idempotent) |
    -- "mismatch", field (the read-back differs: retrying would not help).
    function reader.restore(view, b)
        local chara = view.chara
        local okt, st, jc, ip, arr = pcall(restore_targets, chara)
        if not okt then return "wait", tostring(st) end
        local okl, len = pcall(function() return arr:call("get_Length") end)
        local n = okl and slot.to_int(len) or nil
        if n == nil then return "wait", "CulmativeExp length unreadable: " .. str(len) end
        if n ~= #b.culmative_exp then return "mismatch", "culmative_exp length" end

        local okw, errw = pcall(function()
            st:call("set_Level", need_int(b.level, "level"))
            st:call("set_Exp", need_int(b.exp, "exp"))

            -- ReadOnly is put back even when a field write throws.
            local was_ro = ip:get_field("ReadOnly") == true
            if was_ro then ip:call("setReadOnly", false) end
            local oki, erri = pcall(function()
                for _, key in ipairs(backup.INCREASE_KEYS) do
                    ip:set_field(INCREASE_FIELDS[key], need_int(b.increase_params[key], "increase_params." .. key))
                end
            end)
            if was_ro then ip:call("setReadOnly", true) end
            if not oki then error(erri, 0) end

            -- setExtraStatusBoost is proven only with 0 and set_ConsumableExpProp may touch other state: read back and
            -- fall back to the field write when the method did not leave the value.
            local boost = need_int(b.extra_status_boost, "extra_status_boost")
            st:call("setExtraStatusBoost", boost)
            if int(st:get_field("_AcquiredExtraStatusBoost")) ~= boost then
                st:set_field("_AcquiredExtraStatusBoost", boost)
            end
            local discipline = need_int(b.discipline, "discipline")
            jc:call("set_ConsumableExpProp", discipline)
            if int(jc:get_field("ConsumableExp")) ~= discipline then
                jc:set_field("ConsumableExp", discipline)
            end

            -- Index assignment, 0-based: arr:call("SetValue", ...) silently does nothing.
            for i = 0, n - 1 do arr[i] = need_int(b.culmative_exp[i + 1], "culmative_exp[" .. (i + 1) .. "]") end
        end)
        if not okw then return "wait", tostring(errw) end

        local back = {}
        local okr, errr = pcall(read_restored, chara, back)
        if not okr then return "wait", tostring(errr) end
        local field = backup.restored_mismatch(b, back)
        if field then return "mismatch", field end
        return "done"
    end

    return reader
end

return M
