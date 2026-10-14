local ctx = ...
local M, ns = ctx.mocks, ctx.ns
for _, page in pairs(ns.settingsPages) do page.frame:Hide() end
local function Spell(name, id)
    local info = { name = name, spellID = id, iconID = id + 1000 }
    M.spellInfo[name], M.spellInfo[id], M.known[id] = info, info, true
end
local cds, buffs, reminders = {}, {}, {}
for i = 1, 8 do Spell("S" .. i, i); cds[i] = "S" .. i end
for i = 1, 6 do Spell("B" .. i, i + 20); buffs[i] = "B" .. i end
for i = 1, 8 do Spell("R" .. i, i + 40); reminders[i] = "R" .. i end
for _, name in ipairs({ "Healthstone", "Potion", "Mana" }) do cds[#cds + 1] = name end
M.bags[0] = {}
for i = 1, 60 do M.bags[0][i] = { itemName = "Junk " .. i, itemID = 1000 + i, iconFileID = 100, stackCount = 1 } end
M.bags[0][58].itemName, M.bags[0][59].itemName, M.bags[0][60].itemName = "Healthstone", "Potion", "Mana"
for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    M.units = M.units or {}; M.units[unit] = true
    M.auras[unit] = {}
    for i = 1, 20 do
        local name = i >= 15 and buffs[i - 14] or ("Untracked " .. i)
        M.auras[unit][i] = { name = name, auraInstanceID = i, duration = 300, expirationTime = 400, icon = 100, sourceUnit = "player" }
    end
end
assert(ns.ApplyProfile({ cd = { visibility = "always", spells = cds }, buff = { spells = buffs },
    remind = { self = reminders, ally = reminders, byClass = {}, party = true }, ranks = { enabled = false } }))
M.Flush()
local stage = CreateFrame("Frame"); stage.note = stage:CreateFontString()
ns.PreviewCd(stage, "normal") -- warm the preview pool/cache before measuring

local iterations = 100
local scenarios = {
    { "cooldown refresh", function() M.Fire("SPELL_UPDATE_COOLDOWN"); M.Flush() end },
    { "20-event cooldown burst", function() for _ = 1, 20 do M.Fire("SPELL_UPDATE_COOLDOWN", 1) end; M.Flush() end },
    { "player full aura event", function() M.Fire("UNIT_AURA", "player", { isFullUpdate = true }); M.Flush() end },
    { "two-second safety refresh", function() M.Tick(2) end },
    { "cooldown text color", function(i)
        local color = { r = (i % 10) / 10, g = 0, b = 0 }
        ns.SetConfig("cd", "textColor", color)
    end },
    { "cooldown preview draw", function() ns.PreviewCd(stage, "normal") end },
}
return function(scenarioIndex)
    local scenario = assert(scenarios[scenarioIndex])
    scenario[2](0); M.Flush()
    M.calls = {}
    collectgarbage("collect"); collectgarbage("stop")
    local before, started = collectgarbage("count"), os.clock()
    for i = 1, iterations do scenario[2](i) end
    local elapsed, allocated = os.clock() - started, collectgarbage("count") - before
    collectgarbage("restart")
    return { name = scenario[1], calls = M.calls, allocated_kib = allocated, seconds = elapsed, iterations = iterations }
end
