-- Cooldown resolution, icon pools, sweeps, range and ready glows.
local _, ns = ...
local DB = ns.Database.character
local Collection = ns.Collection
local Frames = ns.TrackerFrames
local Appearance = ns.TrackerAppearance
local Readable = Collection.Readable
local Cooldowns = {}
ns.Trackers.cd = Cooldowns
local cdRoot, QueueUpdate
local OutOfRange = Collection.OutOfRange

-- Sets a cooldown sweep without erroring on secret values. Returns true if a sweep was set.
-- The duration object comes first: it is not secret in combat, so the widget gets its sweep and countdown numbers there
-- too; GetSpellCooldown's start and duration are secret in combat and the widget refuses them from addon code.
local function SafeCooldown(cdFrame, start, duration, modRate, spellID, durationObject)
    if durationObject and cdFrame.SetCooldownFromDurationObject then
        if pcall(cdFrame.SetCooldownFromDurationObject, cdFrame, durationObject) then return true end
    end
    if spellID and cdFrame.SetCooldownFromSpellID and pcall(cdFrame.SetCooldownFromSpellID, cdFrame, spellID) then return true end
    if pcall(cdFrame.SetCooldown, cdFrame, start, duration, modRate) then return true end
    return false
end

-- Cooldown row --------------------------------------------------------------
-- The game sends SPELL_UPDATE_COOLDOWN when a cooldown starts, not when it ends: an icon re-checks when its sweep
-- runs out, and while any icon is grey a ticker re-checks too (in combat the timings are secret and there is no sweep).
local UpdateCd, AnchorCdButton
local cdLayoutDirty, cdStateDirty = true, true
local cdAppearanceDirty = true
local cdWaiting = false
local function CdVisible()
    local c = DB.cd
    if not c.enabled then return false end
    if ns.Kit.editMode or not c.locked or (ns.euiUnlockMode and not InCombatLockdown()) then return true end
    if c.visibility == "always" then return true end
    if c.visibility == "combat" then return InCombatLockdown() end
    if InCombatLockdown() then return true end
    local ok, attackable = pcall(UnitCanAttack, "player", "target")
    return ok and Readable(attackable, "boolean") and attackable
end
local CD_GLOW_EXCLUDES = { [4] = true } -- Shape Glow requires a custom-shaped button.
local function ActionBarGlowProfile()
    local lite = EllesmereUI and EllesmereUI.Lite
    local addon = lite and lite.GetAddon and lite.GetAddon("EllesmereUIActionBars", true)
    return addon and addon.db and addon.db.profile
end
local function CdGlowSpec(glow, engine, profile)
    local spec = glow.spec or {}
    glow.spec = spec
    spec.style = profile and profile.procGlowType or 1
    spec.excludes = CD_GLOW_EXCLUDES
    local color = profile and profile.procGlowColor
    local mode = profile and (profile.procGlowUseClassColor and "class"
        or (profile.procGlowColorMode == "default" and "default" or "custom")) or "default"
    spec.r, spec.g, spec.b = engine.ResolveColor(mode, color and color.r, color and color.g, color and color.b,
        1, 0.776, 0.376)
    spec.lines = profile and profile.procGlowLines
    spec.thickness = profile and profile.procGlowThickness
    spec.speed = profile and profile.procGlowSpeed
    spec.bg = profile and profile.procGlowBackground
    local background = profile and profile.procGlowBackgroundColor
    spec.bgR, spec.bgG, spec.bgB = background and background.r, background and background.g, background and background.b
    return spec
end
-- Follow the active Ellesmere Action Bars glow settings; the shared engine handles change detection.
local function SetCdGlow(b, shown)
    if DB.cd.readyGlow == false then shown = false end
    local glow = b.glow
    local profile = shown and ActionBarGlowProfile()
    if profile and (not profile.procGlowEnabled or profile.procGlowType == 0) then shown = false end
    if not shown then
        if glow.engine then glow.engine.StopGlow(glow); glow.engine = nil end
        glow:Hide()
        return
    end
    local engine = EllesmereUI and EllesmereUI.Glows
    local size = b:GetWidth() + 4
    if engine and engine.StartSpecGlow and engine.ResolveColor and engine.StopGlow then
        if glow.engine and glow.engine ~= engine then glow.engine.StopGlow(glow) end
        if glow.edges then for _, edge in ipairs(glow.edges) do edge:Hide() end end
        glow:Show()
        engine.StartSpecGlow(glow, CdGlowSpec(glow, engine, profile), size, size, "icon",
            b.panelGlow and engine.PANEL_EXTRA or nil)
        glow.engine = engine
    else
        -- Standalone fallback: four outer edge strips, leaving the icon's centre untouched.
        if not glow.edges then
            glow.edges = {}
            for _, points in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
                { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
                local edge = glow:CreateTexture(nil, "OVERLAY")
                edge:SetPoint(points[1]); edge:SetPoint(points[2])
                if #glow.edges < 2 then edge:SetHeight(2) else edge:SetWidth(2) end
                edge:SetColorTexture(1, 0.788, 0.137, 1)
                glow.edges[#glow.edges + 1] = edge
            end
        end
        glow:Show()
    end
end
local function UpdateCdRange()
    if not cdRoot or not DB.cd.enabled then return end
    local visible = CdVisible()
    if visible and not cdRoot:IsShown() then UpdateCd(); return end
    cdRoot:SetShown(visible)
    if not visible then cdStateDirty = true; return end
    for i, b in ipairs(cdRoot.items) do
        if b:IsShown() then
            -- A settings rebuild can leave a recorded anchor without drawable bounds.
            -- Reapply it after the native layout has settled, as a manual reanchor does.
            if not b:GetRect() then AnchorCdButton(b, cdRoot, DB.cd, i) end
            local brightness = DB.cd.rangeDim ~= false and b.spellID and OutOfRange(b.spellID, "target") and 0.35 or 1
            b.icon:SetVertexColor(brightness, brightness, brightness)
            SetCdGlow(b, InCombatLockdown() and b.ready)
        end
    end
end

local BagItem, KnownSpell = Collection.Item, Collection.KnownSpell

local SizeCdRoot = Frames.SizeIcons

function AnchorCdButton(button, root, config, index)
    Frames.Anchor(button, root, config, index, config.size + config.gap)
end

local function PositionCdButton(b, root, c, i)
    b:SetSize(c.size, c.size)
    AnchorCdButton(b, root, c, i)
    Appearance.ApplyCooldown(b)
end
-- A button without tracker callbacks. Set panelGlow on buttons shown inside a settings panel.
local function NewButton(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.glow = CreateFrame("Frame", nil, b)
    b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.glow:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.glow:EnableMouse(false)
    b.glow:Hide()
    b:SetScript("OnHide", function(self) SetCdGlow(self, false) end)
    return b
end
local function CdButton(i)
    if cdRoot.items[i] then return cdRoot.items[i] end
    local b = NewButton(cdRoot)
    b.cd:SetScript("OnCooldownDone", function() QueueUpdate(b.spellID and "spell" or "item", b.spellID) end)
    Frames.AttachMouse(b, cdRoot, "cd")
    cdRoot.items[i] = b
    return b
end

local cdShown, cdSpellRevision, cdBagRevision = {}, -1, -1
local cdResolutionDirty = true
local function ResolveCooldowns()
    if not cdResolutionDirty and cdSpellRevision == Collection.spellRevision and cdBagRevision == Collection.bagRevision then return cdShown end
    wipe(cdShown)
    for _, name in ipairs(DB.cd.spells) do
        local info = Collection.Spell(name)
        if info and KnownSpell(info.spellID) then cdShown[#cdShown + 1] = { spell = info }
        else
            local item = BagItem(name)
            if item then cdShown[#cdShown + 1] = { item = item } end
        end
    end
    cdResolutionDirty, cdLayoutDirty, cdStateDirty = false, true, true
    cdSpellRevision, cdBagRevision = Collection.spellRevision, Collection.bagRevision
    return cdShown
end
local function ReleaseCd(b)
    b:Hide(); SetCdGlow(b, false); b.cd:Clear()
    b.icon:SetTexture(nil)
    b.spellID, b.ready = nil, false
    b.waiting = false
end
local function RenderCooldownLayout(entries)
    local c = DB.cd
    local sample = #entries == 0 and ns.euiUnlockMode and not InCombatLockdown()
    local n = sample and 1 or #entries
    for i = n + 1, #cdRoot.items do ReleaseCd(cdRoot.items[i]) end
    SizeCdRoot(cdRoot, c, n)
    for i = 1, n do
        local entry, b = entries[i], CdButton(i)
        b.spellID = entry and entry.spell and entry.spell.spellID or nil
        b.icon:SetTexture(entry and (entry.spell and entry.spell.iconID or entry.item.icon) or "Interface/Icons/INV_Misc_QuestionMark")
        b.cd:SetHideCountdownNumbers(not c.numbers)
        if not entry then b.cd:Clear(); b.ready = false; b.icon:SetDesaturated(false) end
        b:Show()
        PositionCdButton(b, cdRoot, c, i)
    end
    cdLayoutDirty, cdAppearanceDirty = false, false
end
local function RenderCooldownAppearance()
    for _, b in ipairs(cdRoot.items) do
        if b:IsShown() then
            b.cd:SetHideCountdownNumbers(not DB.cd.numbers)
            Appearance.ApplyCooldown(b)
        end
    end
    cdAppearanceDirty = false
end
local function RenderCooldownEntry(b, entry)
    local info = entry.spell
    b.ready, b.waiting = false, false
    if info then
        local cd = entry.cooldown
        if entry.active then
            if not SafeCooldown(b.cd, cd.startTime, cd.duration, cd.modRate, info.spellID, entry.durationObject) then b.cd:Clear() end
            b.icon:SetDesaturated(true); b.waiting = true
        else
            b.cd:Clear(); b.icon:SetDesaturated(false)
            b.ready = entry.ready
        end
        return
    end
    if entry.active and pcall(b.cd.SetCooldown, b.cd, entry.start, entry.duration) then
        b.icon:SetDesaturated(true); b.waiting = true
    else b.cd:Clear(); b.icon:SetDesaturated(false) end
end
local function RenderCooldownState(entries)
    cdWaiting = false
    for i, entry in ipairs(entries) do
        local b = cdRoot.items[i]
        if entry.updated then RenderCooldownEntry(b, entry) end
        cdWaiting = cdWaiting or b.waiting
    end
end
function UpdateCd(renderOnly, kind, ids)
    if not cdRoot then return end
    local wasVisible, visible = cdRoot:IsShown(), CdVisible()
    cdRoot:SetShown(visible)
    if not visible then cdStateDirty = true; return end
    if not wasVisible then cdLayoutDirty, cdStateDirty = true, true end
    local entries = renderOnly and not cdResolutionDirty and cdShown or ResolveCooldowns()
    if cdStateDirty then kind, ids, renderOnly = nil, nil, false end
    if cdLayoutDirty then RenderCooldownLayout(entries) end
    if cdAppearanceDirty then RenderCooldownAppearance() end
    if not renderOnly then
        Collection.Cooldowns(entries, kind, ids)
        RenderCooldownState(entries)
        cdStateDirty = false
    end
    UpdateCdRange()
end

-- queueUpdate(kind, spellID) coalesces cooldown refreshes; kind is "spell", "item" or "all".
function Cooldowns.Init(queueUpdate)
    if cdRoot then return end
    QueueUpdate = queueUpdate
    cdRoot = Frames.MakeRoot("CD", "cd")
    C_Timer.NewTicker(0.5, function()
        if cdWaiting and cdRoot:IsShown() then QueueUpdate("all") end
    end)
    C_Timer.NewTicker(0.2, UpdateCdRange)
end

function Cooldowns.ApplyConfiguration(effects)
    if effects.data then cdResolutionDirty = true end
    if effects.layout or effects.visibility then cdLayoutDirty = true end
    if effects.appearance then cdAppearanceDirty = true end
    UpdateCd(not effects.data)
end

function Cooldowns.RefreshAppearance()
    if cdRoot and cdRoot:IsShown() then
        for _, button in ipairs(cdRoot.items) do
            if button:IsShown() then Appearance.ApplyCooldown(button) end
        end
    end
end

function Cooldowns.Root() return cdRoot end
Cooldowns.Update = UpdateCd
-- Previews reuse the widget construction and styling without live tracker callbacks.
Cooldowns.NewButton = NewButton
Cooldowns.PositionButton = PositionCdButton
Cooldowns.SetGlow = SetCdGlow
