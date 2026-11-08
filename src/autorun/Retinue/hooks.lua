-- REFramework glue: resolves game methods and installs hooks all-or-nothing. Kept thin; the decisions
-- live in the pure modules. Uses sdk, so it cannot run under plain Lua.
local M = {}

-- The hooked methods. Entries passed to M.install add `pre` (and optionally `post`) to these fields.
-- id_arg is the index in args[] of the app.CharacterID. args[1] is the thread context; for static methods
-- (these ExpDispenser ones) the first parameter is args[2]. Instance methods have `this` at args[2] and the
-- first parameter at args[3] (e.g. GuiManager.reqJobRankUp: id_arg = 3).
-- role: "core" rewrites an adopted pawn's ID and pushes an open-call frame; "swap" puts the real ID back for the
-- notification (game/progression_hooks.lua).
M.SPECS = {
    { key = "checkLevelUp", role = "core", type = "app.ExpDispenser",
      sig = "checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)",
      id_arg = 2 },
    { key = "addJobPoint", role = "core", type = "app.ExpDispenser",
      sig = "addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)",
      id_arg = 2 },
    { key = "dispLevelUpUI", role = "swap", type = "app.ExpDispenser",
      sig = "dispLevelUpUI(app.CharacterID, System.Int32, System.Int32)",
      id_arg = 2 },
    { key = "reqJobRankUp", role = "swap", type = "app.GuiManager",
      sig = "reqJobRankUp(app.CharacterID, app.Character.JobEnum, System.Int32, System.Int32)",
      id_arg = 3 },
}

-- Hook argument decoding (args[n] are raw pointer-sized values).
function M.arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end

-- Signed 32-bit view (System.Int32 and enum arguments).
function M.arg_i32(a)
    local v = sdk.to_int64(a) & 0xFFFFFFFF
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end

function M.to_u32(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return i & 0xFFFFFFFF end
    end
    return v
end

-- System.Guid (a value type) -> canonical lowercase "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx". Reads the raw 16 bytes, then
-- falls back to ToString; "unreadable" (matches nothing) otherwise. Never returns userdata.
function M.guid_str(v)
    if v == nil then return nil end
    if type(v) == "string" then return v:lower() end
    if type(v) ~= "userdata" then return tostring(v) end
    local ok, s = pcall(function()
        local lo, hi = v:read_qword(0), v:read_qword(8)
        return string.format("%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            lo & 0xFFFFFFFF, (lo >> 32) & 0xFFFF, (lo >> 48) & 0xFFFF,
            hi & 0xFF, (hi >> 8) & 0xFF, (hi >> 16) & 0xFF, (hi >> 24) & 0xFF,
            (hi >> 32) & 0xFF, (hi >> 40) & 0xFF, (hi >> 48) & 0xFF, (hi >> 56) & 0xFF)
    end)
    if ok and s then return s end
    local ok2, s2 = pcall(function() return v:call("ToString") end)
    if ok2 and type(s2) == "string" and s2:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then return s2:lower() end
    return "unreadable"
end

-- A managed or Lua string as a Lua string, else nil.
function M.as_string(v)
    if type(v) == "string" then return v end
    if v ~= nil then -- a managed object (userdata): its ToString
        local ok, str = pcall(function() return v:call("ToString") end)
        if ok and type(str) == "string" then return str end
    end
    return nil
end

-- A hook argument (a raw pointer-sized value) as a managed object, nil when null.
function M.to_managed(a)
    if a == nil or sdk.to_int64(a) == 0 then return nil end
    return sdk.to_managed_object(a)
end

-- Method lookup: the full signature string first, then name + parameter type names (last segment).
function M.find_method(td, sig)
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

-- entries: array of { key, type, sig, pre = function(args), post = function(retval) -> retval|nil (optional) }.
-- Resolves every method first; if any type or method is missing, installs nothing and returns
-- false, missing (strings "<type>.<sig>", in order). Otherwise hooks each and returns true, {}.
-- Hooks cannot be removed in REFramework, so install at most once per load.
function M.install(entries, report)
    local resolved, missing = {}, {}
    for i, entry in ipairs(entries) do
        local ok, m = pcall(function()
            local td = sdk.find_type_definition(entry.type)
            return td and M.find_method(td, entry.sig)
        end)
        if ok and m then
            resolved[i] = m
        else
            if not ok then report("resolve " .. entry.key, m) end
            missing[#missing + 1] = entry.type .. "." .. entry.sig
        end
    end
    if #missing > 0 then return false, missing end

    -- Each sdk.hook under pcall: a throw leaves earlier hooks installed, but they do nothing while the caller
    -- keeps progression unavailable, and the script still registers its menu.
    for i, entry in ipairs(entries) do
        local okh, err = pcall(sdk.hook, resolved[i],
            function(args)
                local ok, e = pcall(entry.pre, args)
                if not ok then report("pre " .. entry.key, e) end
                return sdk.PreHookResult.CALL_ORIGINAL
            end,
            function(retval)
                if not entry.post then return retval end
                local ok, res = pcall(entry.post, retval)
                if not ok then
                    report("post " .. entry.key, res)
                    return retval
                end
                if res ~= nil then return res end
                return retval
            end)
        if not okh then
            report("install " .. entry.key, err)
            return false, { entry.type .. "." .. entry.sig }
        end
    end
    return true, {}
end

return M
