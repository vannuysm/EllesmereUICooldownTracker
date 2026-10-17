local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Spell, Prepare, Aura, Calls = H.Spell, H.Prepare, H.Aura, H.Calls

Test("reminders share unit scans and preserve alternatives, ownership and ordering", function()
    Prepare(); Spell("Armor", 1001); Spell("Skin", 1002); Spell("Mark", 1003); Spell("Wisdom", 1004); Spell("Might", 1005)
    M.units, M.classes = { party1 = true, party2 = true, target = true }, { party1 = "MAGE", party2 = "WARRIOR" }
    M.friendly, M.targetInParty = true, true
    M.auras.player = { Aura("Skin", 1002) }
    M.auras.party1 = { Aura("Greater Wisdom", 1004, 60, "party1") }
    M.auras.party2 = { Aura("Might", 1005) }
    ns.Configuration.Set("remind", "self", { "Armor / Skin", "Mark" })
    ns.Configuration.Set("remind", "ally", { "Mark", "Wisdom" })
    ns.Configuration.Set("remind", "byClass", { MAGE = "Wisdom", WARRIOR = "Might" })
    ns.Configuration.Set("remind", "party", true); ns.Configuration.Set("remind", "target", true)
    assert(EUICT_Remind.items[1].text:GetText() == "Mark missing")
    assert(EUICT_Remind.items[2].text:GetText() == "Wisdom missing: party1")
    M.calls = {}; M.Tick(2)
    assert(Calls("aura:player") == 2 and Calls("aura:party1") == 2 and Calls("aura:party2") == 2 and Calls("aura:target") == 0)
    assert(Calls("spell") == 0 and Calls("known") == 0)
    M.calls = {}; M.Fire("PLAYER_TARGET_CHANGED"); M.Flush()
    assert(Calls("aura") == 0, "a duplicate friendly target does not reread player or party auras")
    M.outOfRange.party1 = true; M.Tick(2); assert(not EUICT_Remind.items[2]:IsShown())
end)
Test("unknown reminder names and ownership suppress false missing results", function()
    Prepare(); Spell("Mark", 1101); M.units.party1 = true
    ns.Configuration.Set("remind", "self", { "Mark" }); ns.Configuration.Set("remind", "ally", { "Mark" }); ns.Configuration.Set("remind", "party", true)
    M.unreadable.player, M.unreadable.party1 = true, true; M.Tick(2)
    assert(not EUICT_Remind:IsShown())
    M.unreadable = {}; M.auras.party1 = { Aura("Mark", 1101, 60, "secret-owner") }
    local old = issecretvalue; issecretvalue = function(v) return v == "secret-owner" or v == "secret-name" end
    M.auras.player = { Aura("secret-name", 1102) }; M.Tick(2)
    assert(not EUICT_Remind:IsShown())
    issecretvalue = old; M.auras = {}; M.Tick(2)
    assert(EUICT_Remind.items[1].text:GetText() == "Mark missing" and EUICT_Remind.items[2].text:GetText() == "Mark missing: party1")
end)
Test("reminder learned alternatives recompile and units deduplicate", function()
    Prepare(); Spell("Mark", 1201); Spell("Armor", 1202)
    M.units.party1, M.units.party2 = true, true; M.sameUnits.party2 = "party1"
    ns.Configuration.Set("remind", "ally", { "Mark", "Armor" }); ns.Configuration.Set("remind", "byClass", {}); ns.Configuration.Set("remind", "party", true)
    assert(EUICT_Remind.items[1].text:GetText() == "Mark missing: party1" and EUICT_Remind.items[2].text:GetText() == "Armor missing: party1")
    M.known[1201] = nil; M.Fire("SPELLS_CHANGED"); M.Flush()
    assert(EUICT_Remind.items[1].text:GetText() == "Armor missing: party1" and not EUICT_Remind.items[2]:IsShown())
    M.calls = {}; ns.Configuration.Set("remind", "textColor", { r = 0, g = 0, b = 1 })
    assert(Calls("aura") == 0 and Calls("spell") == 0 and Calls("known") == 0)
end)
