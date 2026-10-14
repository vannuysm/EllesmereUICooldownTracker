-- Shared test boundary: all paths are resolved from the checkout provided by Python.
return function(standalone)
    local function Path(relative) return TEST_REPO_ROOT .. "/" .. relative end
    local M = dofile(Path("tests/unit/support/wow_mocks.lua"))
    M.messages = {}
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        M.messages[#M.messages + 1] = table.concat(parts, " ")
    end
    local modules, widgets = {}, {}
    if standalone then EllesmereUI = nil else
        EllesmereUI.RegisterPlugin = function(_, spec)
            for _, module in ipairs(spec.modules) do modules[module.key] = module end
            return true
        end
        EllesmereUI.Widgets = setmetatable({}, { __index = function(_, kind)
            return function(_, parent, label, y, ...)
                widgets[label] = { kind = kind, args = { ... } }
                return CreateFrame("Frame", nil, parent), 30
            end
        end })
    end
    local ns = {}
    for line in io.lines(Path("EllesmereUICooldownTracker.toc")) do
        if line:match("%.lua$") then
            local file = line:gsub("\r$", "")
            assert(loadfile(Path(file)))("EllesmereUICooldownTracker", ns)
        end
    end
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(EUICT_CD, "tracker initialization did not run")
    for _, page in pairs(ns.settingsPages) do page.frame:Hide() end
    local cases = {}
    local function Test(name, run) cases[#cases + 1] = { name = name, run = run } end
    return { mocks = M, ns = ns, modules = modules, widgets = widgets, path = Path, cases = cases, Test = Test }
end
