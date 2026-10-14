local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local modules, widgets = ctx.modules, ctx.widgets
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Empty, Spell, Prepare, Aura, Calls = H.Empty, H.Spell, H.Prepare, H.Aura, H.Calls

Test("cooldown events use cached resolution and coalesce a burst", function()
    Prepare(); Spell("One", 101); Spell("Two", 102)
    M.bags[0] = { { itemName = "Major Healthstone", itemID = 901, iconFileID = 9, stackCount = 2 },
        { itemName = "Healing Potion", itemID = 902, iconFileID = 10, stackCount = 3 } }
    ns.SetConfig("cd", "spells", { "One", "Two", "Healthstone", "Potion" })
    assert(Calls("bagSlots") == 5 and Calls("bagItem") == 2)
    M.calls = {}
    for _ = 1, 20 do M.Fire("SPELL_UPDATE_COOLDOWN", 101) end
    M.Flush()
    assert(Calls("spell") == 0 and Calls("known") == 0 and Calls("bagSlots") == 0 and Calls("cooldown") == 1)
    assert(Calls("layout") == 0 and Calls("itemCooldown") == 0)
    M.Fire("SPELL_UPDATE_COOLDOWN", 101, 102); M.Flush()
    assert(Calls("cooldown") == 3, "override and base IDs both refresh")
    M.Fire("SPELL_UPDATE_COOLDOWN", 101, nil, 5); M.Flush()
    assert(Calls("cooldown") == 5 and Calls("itemCooldown") == 2, "shared categories refresh all state")
end)
Test("bag, spellbook, pet, configuration and profile dependencies invalidate", function()
    Prepare(); Spell("Pet Bite", 201, true)
    ns.SetConfig("cd", "spells", { "Pet Bite", "Healthstone" })
    assert(EUICT_CD.items[1].spellID == 201)
    M.petKnown[201] = nil; M.Fire("UNIT_PET", "player"); M.Flush()
    assert(not EUICT_CD.items[1]:IsShown())
    M.bags[0] = { { itemName = "Healthstone", itemID = 903, iconFileID = 33 } }
    M.Fire("BAG_UPDATE_DELAYED"); M.Flush(); assert(EUICT_CD.items[1].icon.textureValue == 33)
    M.bags[0] = {}; M.Fire("BAG_UPDATE_DELAYED"); M.Flush(); assert(not EUICT_CD.items[1]:IsShown())
    Spell("New Spell", 202); ns.SetConfig("cd", "spells", { "New Spell" })
    assert(EUICT_CD.items[1].spellID == 202)
    M.known[202] = nil; M.Fire("SPELLS_CHANGED"); M.Flush(); assert(not EUICT_CD.items[1]:IsShown())
    M.known[202] = true; M.Fire("LEARNED_SPELL_IN_SKILL_LINE", 202); M.Flush(); assert(EUICT_CD.items[1]:IsShown())
    M.spellInfo["New Spell"] = { name = "New Spell", spellID = 203, iconID = 2030 }; M.known[203] = true
    local profile = ns.SnapshotProfile(); assert(ns.ApplyProfile(profile))
    M.Fire("SPELL_UPDATE_COOLDOWN"); M.Flush(); assert(EUICT_CD.items[1].spellID == 203)
end)
Test("range dimming, readiness and completion survive appearance changes", function()
    Prepare(); Spell("Ready", 401); M.combat = true
    M.cooldowns[401] = { isActive = true, isOnGCD = false, startTime = 100, duration = 10 }
    ns.SetConfig("cd", "spells", { "Ready" })
    local b = EUICT_CD.items[1]; assert(b.icon.desaturated and not b.ready)
    M.outOfRange.target = true; M.Tick(0.2); assert(b.icon.vertexColor[1] == 0.35)
    M.cooldowns[401] = { isActive = false, isOnGCD = false }
    b.cd.scripts.OnCooldownDone(); M.Flush()
    assert(b.ready and b.glow:IsShown() and not b.icon.desaturated)
    M.calls = {}; ns.SetConfig("cd", "textColor", { r = 0, g = 1, b = 0 })
    assert(b.ready and Calls("cooldown") == 0 and Calls("aura") == 0 and Calls("bagSlots") == 0)
    ns.SetConfig("cd", "readyGlow", false); assert(not b.glow:IsShown())
    ns.SetConfig("cd", "rangeDim", false); assert(b.icon.vertexColor[1] == 1)
end)
Test("form/override and pet-bar dependencies update cached spell identities", function()
    Prepare(); Spell("Form Spell", 1501); ns.SetConfig("cd", "spells", { "Form Spell" })
    M.spellInfo["Form Spell"] = { name = "Form Spell", spellID = 1502, iconID = 15020 }; M.known[1502] = true
    M.Fire("UPDATE_SHAPESHIFT_FORM"); M.Flush(); assert(EUICT_CD.items[1].spellID == 1502)
    M.spellInfo["Form Spell"] = { name = "Form Spell", spellID = 1503, iconID = 15030 }; M.known[1503] = true
    M.Fire("SPELL_UPDATE_ICON", 1501); M.Flush(); assert(EUICT_CD.items[1].spellID == 1503)
    M.known[1503] = nil; M.petKnown[1503] = true; M.Fire("PET_BAR_UPDATE"); M.Flush()
    assert(EUICT_CD.items[1].spellID == 1503)
end)
Test("temporary unreadable bag data retries through narrowly scoped safety polling", function()
    Prepare()
    local query = C_Container.GetContainerItemInfo
    M.bags[0] = { { itemName = "Potion", itemID = 2001, iconFileID = 123 } }
    C_Container.GetContainerItemInfo = function() error("unreadable bag") end
    ns.SetConfig("cd", "spells", { "Potion" }); assert(ns.Collection.bagsUnknown)
    C_Container.GetContainerItemInfo = query
    M.Tick(2); assert(EUICT_CD.items[1]:IsShown() and EUICT_CD.items[1].icon.textureValue == 123)
    M.calls = {}; M.Tick(2); assert(Calls("bagSlots") == 0 and Calls("bagItem") == 0)
end)
Test("native cooldown duration collection and rendering remain targeted", function()
    Prepare(); Spell("A", 1601); Spell("B", 1602)
    M.cooldowns[1601] = { isActive = true, isOnGCD = false, startTime = 100, duration = 30 }
    M.cooldowns[1602] = M.cooldowns[1601]
    C_Spell.GetSpellCooldownDuration = function(id) M.Count("durationQuery"); return { id = id } end
    ns.SetConfig("cd", "spells", { "A", "B" })
    assert(Calls("durationQuery") == 2 and Calls("durationBinding") == 2)
    local object = EUICT_CD.items[2].cd.cooldownObject
    M.calls = {}; M.Fire("SPELL_UPDATE_COOLDOWN", 1601); M.Flush()
    assert(Calls("durationQuery") == 1 and Calls("durationBinding") == 1 and EUICT_CD.items[2].cd.cooldownObject == object)
    M.calls = {}; ns.SetConfig("cd", "textColor", { r = 1, g = 0, b = 0 })
    assert(Calls("durationQuery") == 0 and Calls("durationBinding") == 0)
    C_Spell.GetSpellCooldownDuration = nil
    local query = C_Spell.GetSpellCooldown
    C_Spell.GetSpellCooldown = function() error("unreadable cooldown") end
    M.Fire("SPELL_UPDATE_COOLDOWN", 1601); M.Flush(); assert(not EUICT_CD.items[1].ready)
    C_Spell.GetSpellCooldown = query
end)
