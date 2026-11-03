-- Error reporting that logs each distinct failure once. Pure: the sink is injected.
local M = {}

-- Returns report(where, err): calls sink(string.format("[Retinue] %s: %s", where, tostring(err)))
-- only the first time a given (where, tostring(err)) pair is seen.
function M.new(sink)
    local seen = {}
    return function(where, err)
        local msg = tostring(err)
        local by_where = seen[where]
        if not by_where then
            by_where = {}
            seen[where] = by_where
        end
        if by_where[msg] then return end
        by_where[msg] = true
        sink(string.format("[Retinue] %s: %s", where, msg))
    end
end

return M
