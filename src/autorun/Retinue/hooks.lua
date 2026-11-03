-- REFramework glue: resolves game methods and installs hooks all-or-nothing. Kept thin; the decisions
-- live in the pure modules. Uses sdk, so it cannot run under plain Lua.
local M = {}

-- The hooked methods. Entries passed to M.install add `pre` (and optionally `post`) to these fields.
-- id_arg is the index in args[] of the app.CharacterID. args[1] is the thread context; for static methods
-- (these ExpDispenser ones) the first parameter is args[2]. Instance methods have `this` at args[2] and the
-- first parameter at args[3] (e.g. GuiManager.reqJobRankUp: id_arg = 3).
M.SPECS = {
    { key = "checkLevelUp", type = "app.ExpDispenser",
      sig = "checkLevelUp(app.CharacterID, app.HumanStatusContext, app.Character.JobEnum, System.Boolean, app.DragonHermitContext)",
      id_arg = 2 },
    { key = "addJobPoint", type = "app.ExpDispenser",
      sig = "addJobPoint(app.CharacterID, app.JobContext, System.Int32, System.Boolean)",
      id_arg = 2 },
}

-- Hook argument decoding (args[n] are raw pointer-sized values).
function M.arg_u32(a) return sdk.to_int64(a) & 0xFFFFFFFF end

function M.to_u32(v)
    if type(v) == "number" then
        local i = math.tointeger(v)
        if i then return i & 0xFFFFFFFF end
    end
    return v
end

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

-- entries: array of { key, type, sig, pre = function(args), post = function(retval) -> retval|nil (optional) }.
-- Resolves every method first; if any type or method is missing, installs nothing and returns
-- false, missing (strings "<type>.<sig>", in order). Otherwise hooks each and returns true, {}.
-- Hooks cannot be removed in REFramework, so install at most once per load.
function M.install(entries, report)
    local resolved, missing = {}, {}
    for i, entry in ipairs(entries) do
        local ok, m = pcall(function()
            local td = sdk.find_type_definition(entry.type)
            return td and find_method(td, entry.sig)
        end)
        if ok and m then
            resolved[i] = m
        else
            if not ok then report("resolve " .. entry.key, m) end
            missing[#missing + 1] = entry.type .. "." .. entry.sig
        end
    end
    if #missing > 0 then return false, missing end

    for i, entry in ipairs(entries) do
        sdk.hook(resolved[i],
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
    end
    return true, {}
end

return M
