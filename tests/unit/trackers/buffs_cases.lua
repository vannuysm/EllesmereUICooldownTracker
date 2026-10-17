local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local modules, widgets = ctx.modules, ctx.widgets
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Empty, Spell, Prepare, Aura, Calls = H.Empty, H.Spell, H.Prepare, H.Aura, H.Calls

Test("buffs share a full aura scan and preserve incremental prefix updates", function()
    Prepare(); Spell("Seal One", 501); Spell("Second", 502)
    M.auras.player = { Aura("Seal One", 501), Aura("Second", 502) }
    ns.Configuration.Set("buff", "spells", { "Seal", "Seal One", "Second" })
    assert(Calls("aura") == 3, "two auras and one terminator, once for all bars")
    M.calls = {}; M.auras.player[1].expirationTime = 200
    M.Fire("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 501 } })
    assert(Calls("aura") == 0 and Calls("instance") == 1 and Calls("layout") == 0)
    assert(EUICT_Buff.items[1].endsAt == 200 and EUICT_Buff.items[2].endsAt == 200)
    M.Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 501 } })
    assert(not EUICT_Buff.items[1]:IsShown() and not EUICT_Buff.items[2]:IsShown())
    local added = Aura("Seal New", 503)
    M.Fire("UNIT_AURA", "player", { addedAuras = { added } })
    assert(EUICT_Buff.items[1].auraID == 503 and EUICT_Buff.items[1]:IsShown())
end)
Test("buff reorder/removal clears assigned state including native timers", function()
    Prepare(); Spell("A", 601); Spell("B", 602)
    C_DurationUtil = { CreateDuration = function() return { stopped = true } end }
    C_UnitAuras.GetAuraDuration = function() M.Count("auraDuration"); return { IsActive = function() return true end } end
    M.auras.player = { Aura("A", 601, 40) }
    ns.Configuration.Set("buff", "spells", { "A", "B" })
    local b = EUICT_Buff.items[1]; assert(b.timerObject and b.lastDuration == 40)
    M.calls = {}; ns.Configuration.Set("buff", "spells", { "A", "A" })
    assert(Calls("auraDuration") == 1 and EUICT_Buff.items[2].timerObject, "shared duration object collected once")
    ns.Configuration.Set("buff", "spells", { "B", "A" })
    assert(not b.aura and not b.lastDuration and not b.synthetic and not b.timerObject and b.bar.timerDuration.stopped)
    assert(EUICT_Buff.items[2].auraID == 601)
    ns.Configuration.Set("buff", "enabled", false); ns.Configuration.Set("buff", "spells", {})
    for _, bar in ipairs(EUICT_Buff.items) do assert(not bar.entry and not bar.auraID and not bar.endsAt and not bar.lastDuration) end
    C_DurationUtil, C_UnitAuras.GetAuraDuration = nil, nil
end)
Test("unreadable auras keep state, synthetic recasts reset, replacements do not inherit", function()
    Prepare(); Spell("A", 701); Spell("B", 702)
    M.auras.player = { Aura("A", 701, 40) }
    ns.Configuration.Set("buff", "spells", { "A" })
    local b = EUICT_Buff.items[1]; M.unreadable.player = true
    M.Fire("UNIT_AURA", "player", { isFullUpdate = true }); assert(b.auraID == 701 and b.lastDuration == 40)
    M.now = 110; M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 701)
    assert(b.synthetic and b.synthetic.start == 110 and b.endsAt == 150)
    M.now = 120; M.Tick(2); assert(b.synthetic and b.endsAt == 150)
    ns.Configuration.Set("buff", "spells", { "B" }); M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 702); M.Flush()
    assert(not b.synthetic and not b.lastDuration and not b.endsAt)
    M.unreadable.player = nil; M.auras.player = {}; M.Fire("UNIT_AURA", "player", { isFullUpdate = true })
    assert(not b.aura and not b:IsShown())
end)
Test("ground-effect timers survive refreshes, hidden casts and local expiration", function()
    Prepare(); Spell("Consecration", 801)
    ns.Configuration.Set("buff", "spells", { "Consecration" })
    M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 801)
    local b = EUICT_Buff.items[1]; assert(b.synthetic and b.endsAt == 108)
    M.now = 102; M.Tick(2); assert(b.synthetic and b.endsAt == 108)
    M.now = 109; M.calls = {}; EUICT_Buff.scripts.OnUpdate()
    assert(not b.synthetic and not b:IsShown() and Calls("aura") == 0)
    ns.Configuration.Set("buff", "visibility", "combat")
    M.now = 110; M.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 801); M.Flush()
    M.now = 112; M.combat = true; M.Fire("PLAYER_REGEN_DISABLED")
    assert(b.synthetic and b.endsAt == 118)
end)
Test("buff appearance and countdown text avoid collection and hidden formatting", function()
    Prepare(); Spell("A", 901); M.auras.player = { Aura("A", 901, 300) }
    ns.Configuration.Set("buff", "spells", { "A" }); M.calls = {}
    ns.Configuration.Set("buff", "showTime", false); M.calls = {}
    for _ = 1, 100 do M.now = M.now + 0.01; EUICT_Buff.scripts.OnUpdate() end
    assert(Calls("text") == 0 and Calls("aura") == 0)
    ns.Configuration.Set("buff", "showTime", true); M.calls = {}
    for _ = 1, 100 do M.now = M.now + 0.01; EUICT_Buff.scripts.OnUpdate() end
    assert(Calls("text") <= 2 and Calls("aura") == 0)
    ns.Configuration.Set("buff", "textColor", { r = 1, g = 0, b = 0 }); assert(Calls("aura") == 0)
end)
