local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local modules, widgets = ctx.modules, ctx.widgets
local H = dofile(ctx.path("tests/unit/trackers/support.lua"))(ctx)
local Empty, Spell, Prepare, Aura, Calls = H.Empty, H.Spell, H.Prepare, H.Aura, H.Calls

Test("settings entry points share application and preserve section references", function()
    Empty()
    local db, section = EUICT_DBC, EUICT_DBC.cd
    local card = ns.SettingsUI.pages.cd.blocks[3]
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
    assert(ns.Profiles.Apply({ cd = { spells = {}, size = 45, locked = false }, ranks = { enabled = false } }))
    assert(EUICT_CD:GetHeight() == 45 and EUICT_CD.bg:IsShown() and EUICT_CD:IsMouseEnabled())
    assert(db == EUICT_DBC and section == db.cd)
    ns.Configuration.Set("cd", "locked", true)
    assert(not EUICT_CD.bg:IsShown() and not EUICT_CD:IsMouseEnabled())
end)
Test("appearance avoids unrelated collection and page invalidation", function()
    Empty()
    for _, page in pairs(ns.SettingsUI.pages) do page.frame:Hide() end
    local spells, auras = 0, 0
    local oldSpell, oldAura = C_Spell.GetSpellInfo, C_UnitAuras.GetBuffDataByIndex
    C_Spell.GetSpellInfo = function(...) spells = spells + 1; return oldSpell(...) end
    C_UnitAuras.GetBuffDataByIndex = function(...) auras = auras + 1; return oldAura(...) end
    local buffs = M.invalidated.BuffBars or 0
    ns.Configuration.Set("cd", "textColor", { r = 1, g = 0, b = 0 })
    assert(spells == 0 and auras == 0 and M.invalidated.BuffBars == buffs)
    C_Spell.GetSpellInfo, C_UnitAuras.GetBuffDataByIndex = oldSpell, oldAura
end)
Test("hidden trackers defer collection and reveal current data", function()
    Prepare(); Spell("Hidden", 301)
    ns.Configuration.Set("cd", "visibility", "combat"); ns.Configuration.Set("buff", "visibility", "combat")
    ns.Configuration.Set("cd", "spells", { "Hidden", "Potion" }); ns.Configuration.Set("buff", "spells", { "Hidden" })
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
    ns.Configuration.Set("cd", "spells", { "A", "Potion" }); ns.Configuration.Set("buff", "spells", { "A" })
    ns.Configuration.Set("remind", "self", { "A" })
    local profile = ns.Profiles.Snapshot(); profile.cd.textColor = { r = 0.2, g = 0.3, b = 0.4 }
    M.calls = {}; assert(ns.Profiles.Apply(profile))
    assert(Calls("spell") == 0 and Calls("known") == 0 and Calls("bagSlots") == 0 and Calls("aura") == 0 and Calls("cooldown") == 0)
    M.Fire("SPELL_UPDATE_COOLDOWN"); M.Flush()
    assert(Calls("spell") > 0 and Calls("bagSlots") == 5, "profile dependency invalidation is consumed on the next data refresh")
end)
Test("actual lock controls and dragging use the coordinator and active Edit Mode layout", function()
    Prepare(); Spell("Drag", 1401); ns.Configuration.Set("cd", "spells", { "Drag" })
    local label = assert(M.Find(ns.SettingsUI.pages.cd.frame, "FontString", "Locked"))
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
    local snapshot = ns.Profiles.Snapshot(); snapshot.cd.locked = false; snapshot.cd.x = 999
    assert(ns.Profiles.Apply(snapshot)); assert(EUICT_DBC.cd.x == 42 and EUICT_DBC.editLayouts.layout2.cd[1] == 42)
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

Test("late saved data reconciles without duplicating tracker roots or polling", function()
    Prepare(); Spell("Restored", 1501)
    local character = EUICT_DBC
    local roots = { EUICT_CD, EUICT_Buff, EUICT_Remind }
    local tickers, rankEvents = #M.tickers, #M.events.ACTIONBAR_SLOT_CHANGED
    local restored = assert(ns.Kit.Decode(ns.Kit.Encode(character)))
    restored._savedAt = 999999
    restored.cd.spells, restored.cd.size = { "Restored" }, 53
    EUICT_DBC = restored
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(EUICT_DBC == character and EUICT_DB.chars[character._owner] == character)
    assert(EUICT_CD == roots[1] and EUICT_Buff == roots[2] and EUICT_Remind == roots[3])
    assert(#M.tickers == tickers and #M.events.ACTIONBAR_SLOT_CHANGED == rankEvents)
    assert(EUICT_CD.items[1].spellID == 1501 and EUICT_CD:GetHeight() == 53)
end)

Test("row and card sliders round edits and refresh without writing settings", function()
    local page, current, writes = ns.Kit.NewPage("Slider regression"), 20, 0
    local function Get() return current end
    local function Set(value) current = value; writes = writes + 1 end
    local row = page:Slider("Row", 10, 80, 5, Get, Set)
    local card = page:SliderAt(page.content, 0, 0, "Card", 10, 80, 5, Get, Set)
    local event = MinimalSliderWithSteppersMixin.Event.OnValueChanged
    for _, slider in ipairs({ row.control, card }) do
        -- Native sliders may call the same listener for user edits and programmatic synchronization.
        slider.SetValue = function(self, value) self.scripts[event](self, value) end
        page:Refresh(); assert(writes == 0 and current == 20)
        slider.scripts[event](slider, 23); assert(current == 25 and writes == 1)
        current, writes = 35, 0
        page:Refresh(); assert(current == 35 and writes == 0)
        current = 20
    end
end)

Test("buff and icon borders inherit Action Bar settings and return to custom settings", function()
    Prepare(); Spell("Styled", 1601); M.auras.player = { Aura("Styled", 1601) }
    ns.Configuration.Set("cd", "spells", { "Styled" })
    ns.Configuration.Set("buff", "spells", { "Styled" })
    ns.Configuration.Set("remind", "self", { "Styled" })
    local applied = {}
    EllesmereUI.ApplyBorderStyle = function(frame, size, r, g, b, a, texture, ...)
        applied[frame] = { size, r, g, b, a, texture, ... }
        frame:Show()
    end
    EllesmereUI.BorderPx = function(pixels) return pixels end
    local source = { borderEnabled = true, borderThickness = "heavy", borderThicknessPx = 2.5,
        borderColor = { r = 0.2, g = 0.3, b = 0.4, a = 0.8 }, borderTexture = "test-border" }
    EllesmereUI.Lite = { GetAddon = function() return { db = { profile = { bars = { MainBar = source } } } } end }
    local stage = CreateFrame("Frame"); stage.note = stage:CreateFontString()
    ns.TrackerPreview.Remind(stage, "normal")
    local widgets = { EUICT_CD.items[1], EUICT_Buff.items[1], stage.root.items[1] }
    local stylers = { ns.TrackerAppearance.ApplyCooldown, ns.TrackerAppearance.ApplyBuff, ns.TrackerAppearance.ApplyReminder }
    for i, tracker in ipairs({ "cd", "buff", "remind" }) do
        ns.Configuration.Set(tracker, "inheritBar", "MainBar")
        stylers[i](widgets[i], false)
        local border = widgets[i].buffBorder or widgets[i].euictIconBorder
        local style = assert(applied[border])
        assert(style[1] == 3 and style[2] == 0.2 and style[5] == 0.8 and style[6] == "test-border")
        assert(style[14] == 2.5, "inherited pixel thickness reaches the border API")
        source.borderEnabled = false
        stylers[i](widgets[i], false); assert(not border:IsShown())
        source.borderEnabled = true
        ns.Configuration.Set(tracker, "borderEnabled", true)
        ns.Configuration.Set(tracker, "borderSize", 4)
        ns.Configuration.Set(tracker, "inheritBar", "none")
        stylers[i](widgets[i], false)
        assert(applied[border][1] == 4 and applied[border][6] == "solid")
    end
end)

local function Said(text)
    for _, message in ipairs(M.messages) do if message:find(text, 1, true) then return true end end
end

Test("both reset entry points return to defaults even while a profile is active", function()
    local entries = {
        function() SlashCmdList.EUICT("reset") end,
        function() M.Click(assert(M.Find(ns.SettingsUI.pages.main.frame, "Button", RESET or "Reset"))) end,
    }
    for i, reset in ipairs(entries) do
        Prepare()
        ns.Configuration.Set("cd", "size", 50)
        assert(ns.Profiles.Save("Raid " .. i))
        local reloads = 0
        ReloadUI = function() reloads = reloads + 1 end
        reset()
        assert(reloads == 1 and next(EUICT_DBC) == nil)
        M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
        assert(EUICT_DBC.cd.size == 36 and EUICT_DBC._activeProfile == nil and not ns.Profiles.Active())
        assert(EUICT_DB.profiles["Raid " .. i].cd.size == 50, "the saved profile itself is kept")
    end
    ReloadUI = nil
end)

Test("slash settings report invalid stored settings instead of raising", function()
    Prepare()
    local size = EUICT_DBC.cd.size
    EUICT_DBC.cd.gap = 99
    SlashCmdList.EUICT("cdsize 40")
    assert(EUICT_DBC.cd.size == size and Said("cd.gap"))
end)

Test("invalid saved fields are repaired on load and valid ones kept", function()
    Prepare()
    EUICT_DBC.cd.gap, EUICT_DBC.cd.size = 99, 50
    EUICT_DBC.buff.orientation, EUICT_DBC.buff.growth = "diagonal", "left"
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(EUICT_DBC.cd.gap == 4 and EUICT_DBC.cd.size == 50)
    assert(EUICT_DBC.buff.orientation == "vertical" and EUICT_DBC.buff.growth == "down")
    assert(Said("cd.gap") and Said("buff.orientation") and ns.Profiles.Snapshot())
end)

Test("standalone pages edit the core tracker fields and editors share schema ranges", function()
    Prepare()
    local function Toggle(page, label, tracker, key)
        local control = assert(M.Find(page.frame, "FontString", label), label).parent.control
        control:SetChecked(false); M.Click(control)
        assert(EUICT_DBC[tracker][key] == false, label)
    end
    Toggle(ns.SettingsUI.pages.cd, "Dim spells out of range", "cd", "rangeDim")
    Toggle(ns.SettingsUI.pages.cd, "Glow when ready in combat", "cd", "readyGlow")
    Toggle(ns.SettingsUI.pages.buff, "Show spell icon", "buff", "showIcon")
    Toggle(ns.SettingsUI.pages.buff, "Show buff name", "buff", "showName")
    Toggle(ns.SettingsUI.pages.buff, "Show remaining time", "buff", "showTime")
    for _, label in ipairs({ "Show bars", "Orientation", "Grow direction" }) do
        assert(M.Find(ns.SettingsUI.pages.buff.frame, "FontString", label), label)
    end
    modules.BuffBars.buildPage("Display", CreateFrame("Frame"), 0)
    for label, key in pairs({ ["Bar width"] = "width", ["Bar height"] = "height", Spacing = "gap" }) do
        local low, high = ns.ProfileValidation.Range("buff", key)
        assert(widgets[label].args[1] == low and widgets[label].args[2] == high, label)
    end
end)
