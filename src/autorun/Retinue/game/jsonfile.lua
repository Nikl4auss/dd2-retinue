-- REFramework glue: JSON file reads and verified writes under reframework/data (uses fs and json).
-- Shared by config_store (config.json) and roster_store (roster.json); the decisions live in the pure modules.

local M = {}

-- read(path, opts) -> status, data. status "missing" | "unparseable" | "ok" (data: the decoded value when "ok").
-- fs.read returns "" for a missing and for an empty file alike, so an empty file counts as missing.
-- Without fs.read, json.load_file cannot tell a missing file from a damaged one (it returns nil for both): by
-- default that reads as "missing"; with opts.strict it returns "unreadable" instead of guessing (a caller that
-- must never overwrite a damaged file fails closed). With opts.strict an fs.read that throws or returns a non-string
-- is status "error" (a read failure, not a missing file; roster.resolve locks on any unknown status).
function M.read(path, opts)
    local strict = opts and opts.strict
    if fs and fs.read then
        local ok, text = pcall(fs.read, path)
        if strict and (not ok or type(text) ~= "string") then return "error" end
        if not ok then return "missing" end
        if text == nil or text == "" then return "missing" end
        local okd, data = pcall(json.load_string, text)
        if not okd or data == nil then return "unparseable" end
        return "ok", data
    end
    if strict then return "unreadable" end
    local ok, data = pcall(json.load_file, path)
    if not ok or data == nil then return "missing" end
    return "ok", data
end

-- write(path, data, check) -> true | false, err. json.dump_file returns true even when the file cannot be opened
-- (read-only or locked), so when fs.read exists the file is read back, decoded, and check(back) must hold.
-- Without fs.read a successful dump counts as written.
function M.write(path, data, check)
    local ok, res = pcall(json.dump_file, path, data)
    if not ok then return false, res end
    if res == false then return false, "dump_file returned false" end
    if fs and fs.read then
        local unchanged = "file unchanged after write (read-only or locked?)"
        local okr, text = pcall(fs.read, path)
        if not okr then return false, unchanged end
        local okd, back = pcall(json.load_string, text)
        if not (okd and type(back) == "table") then return false, unchanged end
        local okc, matched = pcall(check, back)
        if not (okc and matched) then return false, unchanged end
    end
    return true
end

return M
