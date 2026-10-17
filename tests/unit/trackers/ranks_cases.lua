local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Prepare = H.Prepare

Test("rank application keeps markers, keep lists and combat deferral consistent", function()
    Prepare(); M.spells, M.oldRank, M.combat = true, true, true
    ActionButton1 = CreateFrame("Button", "ActionButton1", UIParent); ActionButton1.action = 1
    local swaps = 0
    C_Spell.PickupSpell = function(id) assert(id == 2); swaps = swaps + 1 end
    PlaceAction = function(slot) assert(slot == 1); M.oldRank = false end
    ClearCursor = function() end
    ns.Configuration.Set("ranks", "enabled", true); ns.Configuration.Set("ranks", "auto", true)
    local badge = ActionButton1.children[1]; assert(badge:IsShown() and swaps == 0)
    ns.Configuration.Set("ranks", "keep", { "Holy Light" }); assert(not badge:IsShown())
    ns.Configuration.Set("ranks", "keep", {}); assert(badge:IsShown() and swaps == 0)
    M.combat = false; M.Fire("PLAYER_REGEN_ENABLED")
    local timers = M.timers; M.timers = {}
    for _, timer in ipairs(timers) do timer[2]() end
    assert(swaps == 1)
    ns.Configuration.Set("ranks", "enabled", false); assert(not badge:IsShown())
    M.oldRank, M.spells = false, false
end)
