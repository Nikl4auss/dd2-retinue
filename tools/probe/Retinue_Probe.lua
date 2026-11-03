-- Retinue Probe: read-only inspector for party pawns (Dragon's Dogma 2, REFramework Lua).
-- Never writes to the game: no hooks, no setters. Only reads, and writes snapshots to
-- reframework/data/Retinue/probe/ when you press "Save snapshot".
-- Every API name below was checked against this game version's il2cpp_dump.json.

local SNAP_DIR = "Retinue/probe/"
local REFRESH_SECONDS = 1.0

local JOB_NAMES = {
    [1] = "Fighter", [2] = "Archer", [3] = "Mage", [4] = "Thief", [5] = "Warrior",
    [6] = "Sorcerer", [7] = "Mystic Spearhand", [8] = "Magick Archer", [9] = "Trickster", [10] = "Warfarer",
}

local td_pawn_util = sdk.find_type_definition("app.PawnUtil")
local m_is_sub = td_pawn_util:get_method("isSubPawn(app.CharacterID)")
local m_is_main = td_pawn_util:get_method("isMainPawn(app.CharacterID)")
local m_exp_is_sub = sdk.find_type_definition("app.ExpDispenser"):get_method("isSubPawn(app.CharacterID)")
local m_gui_name = sdk.find_type_definition("app.GUIBase"):get_method("getName(app.Character)")

local rows, saved_ids, last_refresh, status = {}, {}, -REFRESH_SECONDS, ""

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

-- ContextHolder.Contexts is Dictionary<System.Type, ContextInfoBase>.
local function holder_context(holder, type_name)
    local dict = holder:get_field("Contexts")
    local key = sdk.typeof(type_name)
    if not dict:call("ContainsKey", key) then return nil end
    return dict:call("get_Item", key):call("get_CurrentContext")
end

local function job_label(job)
    if type(job) ~= "number" then return str(job) end
    return string.format("%d (%s)", job, JOB_NAMES[job] or "?")
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
    r.util_is_sub = try(function() return m_is_sub:call(nil, id) end)
    r.util_is_main = try(function() return m_is_main:call(nil, id) end)
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
            r.owner_user_id = try(function() return str(owner:get_field("_UserId")) end)
            r.owner_slot_id = try(function() return str(owner:get_field("_SlotId")) end)
        else r.owner = owner == nil and "none" or owner end

        local sub = try(holder_context, holder, "app.SubPawnDataContext")
        if type(sub) == "userdata" then
            r.sub_hire_time = try(function() return sub:get_field("_HireTime") end)
            r.sub_rental_token = try(function() return str(sub:get_field("_RentalToken")) end)
            r.sub_changed_equip = try(function() return str(sub:get_field("ChangedEquipSlot")) end)
        else r.sub_ctx = sub == nil and "none" or sub end

        r.main_ctx_in_holder = try(function() return holder_context(holder, "app.MainPawnDataContext") ~= nil end)
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
        end
        local pd = human:call("get_PawnDataContext")
        if pd then
            r.data_name = try(function() return pd:get_field("_Name") end)
            r.data_nickname = try(function() return pd:get_field("_Nickname") end)
            r.data_first_job = try(function() return job_label(pd:get_field("_FirstJob")) end)
        end
    end
    return r
end

local function refresh()
    rows, saved_ids = {}, {}
    local pm = sdk.get_managed_singleton("app.PawnManager")
    if not pm then status = "PawnManager not available (load a save)"; return end
    local party = pm:get_field("_PartyPawnList")
    for i = 0, party:call("get_Count") - 1 do
        local pawn = party:call("get_Item", i)
        local ok, r = pcall(read_pawn, pawn)
        if not pawn then r = { error = "nil pawn" } elseif not ok then r = { error = tostring(r) } end
        rows[#rows + 1] = r
    end
    local saved = pm:get_field("_SavedPartyPawnList")
    for i = 0, saved:call("get_Count") - 1 do saved_ids[#saved_ids + 1] = saved:call("get_Item", i) end
    status = string.format("%d party pawns, %d saved IDs", #rows, #saved_ids)
end

local FIELD_ORDER = {
    "slot", "chara_id", "gui_name", "data_name", "data_nickname", "dead",
    "level", "exp", "job", "job_rank", "discipline", "data_first_job", "holder_level",
    "util_is_main", "util_is_sub", "exp_is_sub", "main_ctx_bound", "main_ctx_in_holder",
    "is_store", "is_restore", "uniq_id",
    "owner", "owner_name", "owner_level", "owner_job", "owner_offline_id", "owner_user_id", "owner_slot_id",
    "sub_ctx", "sub_hire_time", "sub_rental_token", "sub_changed_equip", "error",
}

re.on_draw_ui(function()
    if not imgui.tree_node("Retinue Probe (read-only)") then return end
    if os.clock() - last_refresh >= REFRESH_SECONDS then
        last_refresh = os.clock()
        local ok, err = pcall(refresh)
        if not ok then status = "refresh failed: " .. tostring(err) end
    end
    imgui.text(status)
    if imgui.button("Save snapshot") then
        local file = SNAP_DIR .. "probe_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
        json.dump_file(file, { time = os.date("%Y-%m-%d %H:%M:%S"), saved_ids = saved_ids, pawns = rows })
        status = "Saved reframework/data/" .. file
    end
    imgui.text("Saved party IDs: " .. table.concat(saved_ids, ", "))
    for i, r in ipairs(rows) do
        if imgui.tree_node(string.format("#%d  %s  (id %s)", i, str(r.gui_name), str(r.chara_id))) then
            for _, k in ipairs(FIELD_ORDER) do
                if r[k] ~= nil then imgui.text(k .. ": " .. str(r[k])) end
            end
            imgui.tree_pop()
        end
    end
    imgui.tree_pop()
end)
