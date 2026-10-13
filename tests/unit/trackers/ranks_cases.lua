local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local modules, widgets = ctx.modules, ctx.widgets
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Empty, Spell, Prepare, Aura, Calls = H.Empty, H.Spell, H.Prepare, H.Aura, H.Calls

Test("rank application keeps markers, keep lists and combat deferral consistent", function()
    Prepare(); M.spells, M.oldRank, M.combat = true, true, true
    ActionButton1 = CreateFrame("Button", "ActionButton1", UIParent); ActionButton1.action = 1
    local swaps = 0
    C_Spell.PickupSpell = function(id) assert(id == 2); swaps = swaps + 1 end
    PlaceAction = function(slot) assert(slot == 1); M.oldRank = false end
    ClearCursor = function() end
    ns.SetConfig("ranks", "enabled", true); ns.SetConfig("ranks", "auto", true)
    local badge = ActionButton1.children[1]; assert(badge:IsShown() and swaps == 0)
    ns.SetConfig("ranks", "keep", { "Holy Light" }); assert(not badge:IsShown())
    ns.SetConfig("ranks", "keep", {}); assert(badge:IsShown() and swaps == 0)
    M.combat = false; M.Fire("PLAYER_REGEN_ENABLED")
    local timers = M.timers; M.timers = {}
    for _, timer in ipairs(timers) do timer[2]() end
    assert(swaps == 1)
    ns.SetConfig("ranks", "enabled", false); assert(not badge:IsShown())
    M.oldRank, M.spells = false, false
end)
