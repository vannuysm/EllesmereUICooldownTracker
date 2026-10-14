local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local modules, widgets = ctx.modules, ctx.widgets
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Empty, Spell, Prepare, Aura, Calls = H.Empty, H.Spell, H.Prepare, H.Aura, H.Calls

Test("settings entry points share application and preserve section references", function()
    Empty()
    local db, section = EUICT_DBC, EUICT_DBC.cd
    local card = ns.settingsPages.cd.blocks[3]
    -- Find the actual standalone slider setter through its callback upvalues.
    local standalone
    for _, object in ipairs(M.objects) do
        for _, callback in pairs(object.scripts) do
            for i = 1, 15 do
                local name, value = debug.getupvalue(callback, i)
                if name == "set" and type(value) == "function" then
                    local tracker, key
                    for j = 1, 5 do
                        local field, v = debug.getupvalue(value, j)
                        if field == "tracker" then tracker = v elseif field == "key" then key = v end
                    end
                    if tracker == "cd" and key == "size" then standalone = value end
                end
            end
        end
    end
    assert(standalone, "standalone size callback")
    standalone(42); assert(EUICT_CD:GetHeight() == 42)
    modules.CooldownBar.buildPage("Display", CreateFrame("Frame"), 0)
    widgets["Icon size"].args[5](43); assert(EUICT_CD:GetHeight() == 43)
    SlashCmdList.EUICT("cdsize 44"); assert(EUICT_CD:GetHeight() == 44)
    assert(ns.ApplyProfile({ cd = { spells = {}, size = 45, locked = false }, ranks = { enabled = false } }))
    assert(EUICT_CD:GetHeight() == 45 and EUICT_CD.bg:IsShown() and EUICT_CD:IsMouseEnabled())
    assert(db == EUICT_DBC and section == db.cd)
    ns.SetConfig("cd", "locked", true)
    assert(not EUICT_CD.bg:IsShown() and not EUICT_CD:IsMouseEnabled())
end)
Test("appearance avoids unrelated collection and page invalidation", function()
    Empty()
    for _, page in pairs(ns.settingsPages) do page.frame:Hide() end
    local spells, auras = 0, 0
    local oldSpell, oldAura = C_Spell.GetSpellInfo, C_UnitAuras.GetBuffDataByIndex
    C_Spell.GetSpellInfo = function(...) spells = spells + 1; return oldSpell(...) end
    C_UnitAuras.GetBuffDataByIndex = function(...) auras = auras + 1; return oldAura(...) end
    local buffs = M.invalidated.BuffBars or 0
    ns.SetConfig("cd", "textColor", { r = 1, g = 0, b = 0 })
    assert(spells == 0 and auras == 0 and M.invalidated.BuffBars == buffs)
    C_Spell.GetSpellInfo, C_UnitAuras.GetBuffDataByIndex = oldSpell, oldAura
end)
Test("hidden trackers defer collection and reveal current data", function()
    Prepare(); Spell("Hidden", 301)
    ns.SetConfig("cd", "visibility", "combat"); ns.SetConfig("buff", "visibility", "combat")
    ns.SetConfig("cd", "spells", { "Hidden", "Potion" }); ns.SetConfig("buff", "spells", { "Hidden" })
    M.calls = {}
    M.bags[0] = { { itemName = "Potion", itemID = 904, iconFileID = 44 } }
    M.auras.player = { Aura("Hidden", 301) }
    M.Fire("BAG_UPDATE_DELAYED"); M.Fire("UNIT_AURA", "player", { isFullUpdate = true }); M.Flush()
    assert(Calls("bagSlots") == 0 and Calls("aura") == 0 and Calls("cooldown") == 0)
    M.combat = true; M.Fire("PLAYER_REGEN_DISABLED"); M.Flush()
    assert(EUICT_CD.items[1].spellID == 301 and EUICT_CD.items[2].icon.textureValue == 44)
    assert(EUICT_Buff.items[1].auraID == 301 and EUICT_Buff.items[1]:IsShown())
end)
Test("profile appearance changes do not collect unrelated state", function()
    Prepare(); Spell("A", 1301); M.auras.player = { Aura("A", 1301) }
    ns.SetConfig("cd", "spells", { "A", "Potion" }); ns.SetConfig("buff", "spells", { "A" })
    ns.SetConfig("remind", "self", { "A" })
    local profile = ns.SnapshotProfile(); profile.cd.textColor = { r = 0.2, g = 0.3, b = 0.4 }
    M.calls = {}; assert(ns.ApplyProfile(profile))
    assert(Calls("spell") == 0 and Calls("known") == 0 and Calls("bagSlots") == 0 and Calls("aura") == 0 and Calls("cooldown") == 0)
    M.Fire("SPELL_UPDATE_COOLDOWN"); M.Flush()
    assert(Calls("spell") > 0 and Calls("bagSlots") == 5, "profile dependency invalidation is consumed on the next data refresh")
end)
Test("actual lock controls and dragging use the coordinator and active Edit Mode layout", function()
    Prepare(); Spell("Drag", 1401); ns.SetConfig("cd", "spells", { "Drag" })
    local label = assert(M.Find(ns.settingsPages.cd.frame, "FontString", "Locked"))
    local checkbox
    for _, child in ipairs(label.parent.children) do
        if child.kind == "CheckButton" and child.point[2] == 320 then checkbox = child end
    end
    assert(checkbox); checkbox:SetChecked(false); M.Click(checkbox)
    assert(EUICT_CD.bg:IsShown() and EUICT_CD:IsMouseEnabled())
    local b = EUICT_CD.items[1]
    b.scripts.OnDragStart(); assert(EUICT_CD.moving)
    C_EditMode = { GetLayouts = function() return { activeLayout = 2 } end }
    EUICT_CD.centerX, EUICT_CD.centerY = 42, 84
    b.scripts.OnDragStop()
    assert(EUICT_DBC.cd.x == 42 and EUICT_DBC.cd.y == 84 and not EUICT_CD.moving)
    assert(EUICT_DBC.editLayouts.layout2.cd[1] == 42 and EUICT_DBC.editLayouts.layout2.cd[2] == 84)
    modules.CooldownBar.buildPage("Display", CreateFrame("Frame"), 0)
    widgets["Lock position"].args[2](true)
    assert(not EUICT_CD.bg:IsShown() and not EUICT_CD:IsMouseEnabled())
    b.scripts.OnDragStart(); assert(not EUICT_CD.moving)
    local snapshot = ns.SnapshotProfile(); snapshot.cd.locked = false; snapshot.cd.x = 999
    assert(ns.ApplyProfile(snapshot)); assert(EUICT_DBC.cd.x == 42 and EUICT_DBC.editLayouts.layout2.cd[1] == 42)
    C_EditMode = nil; EUICT_CD.centerX, EUICT_CD.centerY = nil, nil
end)
Test("Ellesmere continuous controls retain active widgets; structural changes rebuild", function()
    Prepare()
    modules.CooldownBar.buildPage("Display", CreateFrame("Frame"), 0)
    local before = M.pageRefreshes
    widgets["Icon size"].args[5](47)
    assert(M.pageRefreshes == before and EUICT_CD:GetHeight() == 47)
    widgets.Orientation.args[3]("vertical")
    assert(M.pageRefreshes == before + 1 and EUICT_DBC.cd.growth == "down")
    SlashCmdList.EUICT("cdsize 48")
    assert(M.pageRefreshes == before + 2 and EUICT_CD:GetWidth() == 48)
    SlashCmdList.EUICT("cdsize 999"); assert(EUICT_DBC.cd.size == 48)
end)
