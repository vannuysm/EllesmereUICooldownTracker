local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
Test("standalone controls, cooldowns, buffs and reminders", function()
local info = { name = "Standalone Buff", spellID = 1, iconID = 123 }
M.spellInfo[info.name], M.spellInfo[1], M.known[1] = info, info, true
M.auras.player = { { name = info.name, auraInstanceID = 1, duration = 30, expirationTime = 130, icon = 123, sourceUnit = "player" } }
assert(ns.Profiles.Apply({ cd = { visibility = "always", spells = { info.name }, locked = false },
    buff = { spells = { info.name } }, remind = { self = { info.name }, ally = {} }, ranks = { enabled = false } }))
assert(EUICT_CD.items[1].spellID == 1 and EUICT_Buff.items[1].auraID == 1 and not EUICT_Remind:IsShown())
ns.Configuration.Set("cd", "locked", true); assert(not EUICT_CD.bg:IsShown() and not EUICT_CD:IsMouseEnabled())
SlashCmdList.EUICT("cdsize 41"); assert(EUICT_CD:GetHeight() == 41)
M.auras.player = {}; M.Fire("UNIT_AURA", "player", { removedAuraInstanceIDs = { 1 } }); M.Flush()
assert(not EUICT_Buff.items[1]:IsShown() and EUICT_Remind.items[1].text:GetText() == "Standalone Buff missing")
end)
