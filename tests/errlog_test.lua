local errlog = require("Retinue.errlog")

local function new()
    local lines = {}
    return errlog.new(function(msg) lines[#lines + 1] = msg end), lines
end

-- same pair logged once, with the expected format
do
    local report, lines = new()
    report("pre checkLevelUp", "boom")
    report("pre checkLevelUp", "boom")
    assert(#lines == 1)
    assert(lines[1] == "[Retinue] pre checkLevelUp: boom")
end

-- different message or different where logs again
do
    local report, lines = new()
    report("a", "x")
    report("a", "y")
    report("b", "x")
    assert(#lines == 3)
end

-- non-string err
do
    local report, lines = new()
    report("a", 42)
    report("a", 42)
    report("a", nil)
    assert(#lines == 2)
    assert(lines[1] == "[Retinue] a: 42")
    assert(lines[2] == "[Retinue] a: nil")
end
