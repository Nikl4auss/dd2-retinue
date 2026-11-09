-- Throwaway spike for M2 ticket 29: the Status page's exp panel (app.ui060601_01) for the main pawn vs a hired pawn.
-- Log only in mode 0. F9 cycles the mode: 0 log only, 1 = (a) skip hideExp for a hired pawn, 2 = (b) after setupPawn/
-- setupStatus/setupJob post for a hired pawn, call setupExp then setExp with the main pawn's last StSelData (or getSelInfo).
-- 3 = (c) IsMainPawn:=true on a hired pawn's CharaData during setupStatus/setupJob; 4 = (d) its CopyOwner._OfflineID:=0 then.
-- Every line starts with "[T29]".
local UI = "app.ui060601_01"
local SEL = "app.GUIBase.StSelData"
local mode = 0
local current -- last CharaData seen in a setup* pre
local main_sel -- fields of the last StSelData given to setExp while the current CharaData was the main pawn
local busy = false
local seq = 0

local function L(s) log.error("[T29] " .. s) end
local function p(f) local ok, v = pcall(f); if ok then return v end; return "err" end
local function str(v) if v == nil then return "nil" end; if type(v) == "userdata" then local ok, s = pcall(function() return v:call("ToString") end); if ok then return tostring(s) end end; return tostring(v) end

local function guid(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function()
        local lo, hi = v:read_qword(0), v:read_qword(8)
        if lo == 0 and hi == 0 then return "0" end
        return string.format("%016x%016x", lo, hi)
    end)
    if ok then return s end
    return str(v)
end

local function to_obj(a) if a == nil or sdk.to_int64(a) == 0 then return nil end; return sdk.to_managed_object(a) end

local function chara(cd)
    if cd == nil then return "CharaData nil" end
    local name = p(function() local pd = cd:get_field("CopyPawn"); return pd and pd:call("get_Name") or "noCopyPawn" end)
    local id = p(function() return cd:get_field("<CharaId>k__BackingField") end)
    local main = p(function() return cd:get_field("<IsMainPawn>k__BackingField") end)
    local off = p(function() local o = cd:get_field("CopyOwner"); return o and guid(o:get_field("_OfflineID")) or "noOwner" end)
    local exp = p(function() return cd:get_field("CopyStatus"):call("get_Exp") end)
    local lv = p(function() return cd:get_field("CopyStatus"):call("get_Level") end)
    local job = p(function() return cd:get_field("CopyJob"):get_field("CurrentJob") end)
    local cons = p(function() return cd:get_field("CopyJob"):get_field("ConsumableExp") end)
    local cul = p(function() return cd:get_field("CopyJob"):call("get_NowJobCulmativeExpProp") end)
    return string.format("name=%s id=%s main=%s off=%s exp=%s lv=%s job=%s jobConsumable=%s jobCulm=%s",
        str(name), str(id), str(main), str(off), str(exp), str(lv), str(job), str(cons), str(cul))
end

local function hired(cd)
    if cd == nil then return false end
    local ok, r = pcall(function()
        if cd:get_field("<IsMainPawn>k__BackingField") == true then return false end
        local o = cd:get_field("CopyOwner"); if o == nil then return false end
        local g = guid(o:get_field("_OfflineID"))
        return g ~= "0" and g ~= "nil" and g ~= "err"
    end)
    return ok and r
end

local function is_main(cd) return cd ~= nil and p(function() return cd:get_field("<IsMainPawn>k__BackingField") end) == true end

local function sel_fields(vt)
    if vt == nil then return nil end
    local f = {}
    f.value = p(function() return vt:get_field("<Value>k__BackingField") end)
    f.job = p(function() return vt:get_field("Job") end)
    f.msg = p(function() return vt:get_field("DetailMsg") end)
    f.title = p(function() return guid(vt:get_field("TitleId")) end)
    f.detail = p(function() return guid(vt:get_field("DetailId")) end)
    return f
end
local function sel_str(f)
    if f == nil then return "StSelData nil" end
    return string.format("Value=%s Job=%s DetailMsg=%s TitleId=%s DetailId=%s", str(f.value), str(f.job), str(f.msg), str(f.title), str(f.detail))
end

local function page_state(this)
    if this == nil then return "this nil" end
    local function t(name) return str(p(function() local x = this:get_field(name); return x and x:call("get_Message") or "nilwidget" end)) end
    local pn = p(function() return this:get_field("PnlExp") end)
    local vis = pn ~= "err" and pn ~= nil and string.format("PnlExp Visible=%s ActualVisible=%s ForceInvisible=%s PlayState=%s",
        str(p(function() return pn:call("get_Visible") end)), str(p(function() return pn:call("get_ActualVisible") end)),
        str(p(function() return pn:call("get_ForceInvisible") end)), str(p(function() return pn:call("get_PlayState") end))) or ("PnlExp " .. str(pn))
    return string.format("%s | TabNow=%s IsPawn=%s IsStray=%s | ExpName=%q ExpDetail=%q Next=%q NextJp=%q TotalJp=%q",
        vis, str(p(function() return this:get_field("TabNow") end)), str(p(function() return this:get_field("IsPawn") end)),
        str(p(function() return this:get_field("IsStrayPawn") end)),
        t("TxtExpName"), t("TxtExpDetail"), t("TxtNext"), t("TxtNextJp"), t("TxtTotalJp"))
end

local td = sdk.find_type_definition(UI)
local stacks = {}

local function read_sel(a)
    local ok, vt = pcall(sdk.to_valuetype, a, SEL)
    if ok and vt then return sel_fields(vt) end
    return { value = "to_valuetype failed: " .. str(vt) }
end

-- the B variant: after a setup* post for a hired pawn, show the panel with the main pawn's selection data
local function try_b(this, where)
    if mode ~= 2 or busy or not hired(current) then return end
    busy = true
    local ok1, e1 = pcall(function() this:call("setupExp") end)
    L("B " .. where .. ": setupExp " .. (ok1 and "ok" or ("err " .. str(e1))))
    local vt, src
    if main_sel then
        local ok, v = pcall(function()
            local x = ValueType.new(sdk.find_type_definition(SEL))
            x:set_field("<Value>k__BackingField", main_sel.value)
            x:set_field("Job", main_sel.job)
            return x
        end)
        if ok then vt, src = v, "main pawn copy (Value, Job)" else L("B ValueType.new failed: " .. str(v)) end
    end
    if vt == nil then
        local ok, v = pcall(function() return this:call("getSelInfo") end)
        if ok then vt, src = v, "getSelInfo" else L("B getSelInfo failed: " .. str(v)) end
    end
    if vt ~= nil then
        L("B setExp with " .. src .. ": " .. sel_str(sel_fields(vt)))
        local ok2, e2 = pcall(function() this:call("setExp(app.GUIBase.StSelData)", vt) end)
        L("B setExp " .. (ok2 and "ok" or ("err " .. str(e2))))
    end
    busy = false
    L("B after | " .. page_state(this))
end

local function hook(sig, kind)
    local m = td and td:get_method(sig)
    if not m then L("missing " .. UI .. "." .. sig); return end
    stacks[sig] = {}
    sdk.hook(m, function(args)
        seq = seq + 1
        local this = to_obj(args[2])
        local frame = { this = this, n = seq }
        local extra = ""
        if kind == "chara" then
            local cd = to_obj(args[3]); current = cd
            extra = " " .. chara(cd)
            if (mode == 3 or mode == 4) and hired(cd) and (sig:find("setupStatus") or sig:find("setupJob")) then
                if mode == 3 then
                    local ok, e = pcall(function() cd:set_field("<IsMainPawn>k__BackingField", true) end)
                    frame.undo = function() cd:set_field("<IsMainPawn>k__BackingField", false) end
                    extra = extra .. " | C: IsMainPawn:=true " .. (ok and "ok" or ("err " .. str(e)))
                else
                    local ok, e = pcall(function()
                        local o = cd:get_field("CopyOwner")
                        local off = o:get_type_definition():get_field("_OfflineID"):get_offset_from_base()
                        local lo, hi = o:read_qword(off), o:read_qword(off + 8)
                        o:write_qword(off, 0); o:write_qword(off + 8, 0)
                        frame.undo = function() o:write_qword(off, lo); o:write_qword(off + 8, hi) end
                    end)
                    extra = extra .. " | D: OfflineID:=0 " .. (ok and "ok" or ("err " .. str(e)))
                end
            end
        elseif kind == "sel" then
            local f = read_sel(args[3])
            frame.sel = f
            extra = " " .. sel_str(f) .. " | current: " .. chara(current)
            if is_main(current) and f and f.value ~= nil then main_sel = f end
        elseif kind == "tab" then
            extra = " tab=" .. tostring(sdk.to_int64(args[3]) & 0xffffffff)
        else
            extra = " | current: " .. chara(current)
        end
        table.insert(stacks[sig], frame)
        L(string.format("#%d pre %s%s", seq, sig, extra))
        if kind == "hide" and mode == 1 and hired(current) then
            L(string.format("#%d A: skip hideExp for hired %s", seq, chara(current)))
            frame.skipped = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(ret)
        local st = stacks[sig]; local frame = table.remove(st) or {}
        if frame.undo then local ok, e = pcall(frame.undo); L("undo " .. (ok and "ok" or ("err " .. str(e)))) end
        L(string.format("#%s post %s%s | %s", tostring(frame.n), sig, frame.skipped and " (skipped)" or "", page_state(frame.this)))
        if kind == "chara" and frame.this then try_b(frame.this, sig) end
        return ret
    end)
end

hook("setupExp()", "plain")
hook("setExp(app.GUIBase.StSelData)", "sel")
hook("hideExp()", "hide")
hook("setupPawn(app.GUIBase.CharaData)", "chara")
hook("setupJob(app.GUIBase.CharaData)", "chara")
hook("setupStatus(app.GUIBase.CharaData)", "chara")
hook("setupChara()", "plain")
hook("setupCharaTab()", "plain")
hook("setupProfile()", "plain")
hook("setTabId(app.ui060601_01.TabId, System.Boolean)", "tab")

local was = false
re.on_frame(function()
    local down = reframework:is_key_down(0x78) -- F9
    if down and not was then mode = (mode + 1) % 5; L("mode " .. mode) end
    was = down
end)
L("spike loaded, mode 0")
