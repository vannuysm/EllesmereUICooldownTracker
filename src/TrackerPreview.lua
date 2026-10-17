-- Cached preview resolution and simulated tracker rendering.
local _, ns = ...
local DB = ns.Database.character
local Collection = ns.Collection
local Frames = ns.TrackerFrames
local Readable = Collection.Readable
local Kit = ns.Kit
local Cooldowns, Buffs, Reminders = ns.Trackers.cd, ns.Trackers.buff, ns.Trackers.remind
local Preview = {}
ns.TrackerPreview = Preview
local QUESTION = 134400
local KnownSpell, BagItem = Collection.KnownSpell, Collection.Item
local PositionCdButton, SetCdGlow, StyleBar = Cooldowns.PositionButton, Cooldowns.SetGlow, Buffs.StyleBar
local Learned, Label = Reminders.Learned, Reminders.Label
local SizeCdRoot, SizeBuffRoot, PositionBuffBar = Frames.SizeIcons, Frames.SizeBars, Frames.PositionBar

-- How a cooldown entry looks in the settings: learned spell, item in your bags, or greyed until then.
local previewCd, previewBuff, previewSpellRevision, previewBagRevision = {}, {}, -1, -1
local function PreviewDependencies()
    if previewSpellRevision ~= Collection.spellRevision then
        wipe(previewCd); wipe(previewBuff); previewSpellRevision = Collection.spellRevision
    end
    if previewBagRevision ~= Collection.bagRevision then wipe(previewCd); previewBagRevision = Collection.bagRevision end
end
local function ResolveCdUncached(name)
    local info = Collection.Spell(name)
    if info and KnownSpell(info.spellID) then
        Kit.icons[name] = info.iconID
        local ok, sub = pcall(C_Spell.GetSpellSubtext, info.spellID)
        return { icon = info.iconID, spellID = info.spellID, tag = ok and Readable(sub, "string") and sub ~= "" and sub or "Spell" }
    end
    local it = BagItem(name)
    if it then return { icon = it.icon, tag = ("Item  ·  %d in your bags"):format(it.count) } end
    return { icon = Kit.icons[name] or QUESTION, grey = true, tag = "Shows once you learn it, or carry it" }
end
local function ResolveBuffUncached(name)
    local info = Collection.Spell(name)
    if info then Kit.icons[name] = info.iconID; return { icon = info.iconID, tag = "Any buff starting with \"" .. name .. "\"" } end
    for _, e in ipairs(Kit.Spellbook()) do
        if e.name:lower():find(name:lower(), 1, true) == 1 then
            return { icon = e.icon, example = e.name, tag = "Any buff starting with \"" .. name .. "\", e.g. " .. e.name }
        end
    end
    return { icon = Kit.icons[name] or QUESTION, grey = true, tag = "Shows once learned" }
end
local function ResolveCd(name)
    PreviewDependencies()
    previewCd[name] = previewCd[name] or ResolveCdUncached(name)
    return previewCd[name]
end
local function ResolveBuff(name)
    PreviewDependencies()
    previewBuff[name] = previewBuff[name] or ResolveBuffUncached(name)
    return previewBuff[name]
end
local function ResolveSpell(name)
    local info = Kit.SpellByName(name)
    if info then Kit.icons[name] = info.iconID; return { icon = info.iconID, tag = "Kept on the rank you put on your bars" } end
    return { icon = Kit.icons[name] or QUESTION, grey = true, tag = "Not learned yet" }
end
-- The previews draw their own copy of each tracker with the same pieces and your settings (the real ones may be hidden
-- by ForeverImmersion, and show only what's happening right now). "Simulate combat" uses the icons in turn: grey,
-- sweep and countdown, and the buff bars run down, so size and numbers can be judged as they look in a fight.
local function PreviewRoot(stage)
    if stage.root then return stage.root end
    local r = CreateFrame("Frame", nil, stage)
    r.items = {}
    stage.root = r
    return r
end
local function Pooled(root, i, make)
    root.items[i] = root.items[i] or make(root)
    return root.items[i]
end
local function PreviewButton(root)
    local b = Cooldowns.NewButton(root)
    b.panelGlow = true
    b.cd:SetScript("OnCooldownDone", function()
        b.icon:SetDesaturated(false)
        b.ready = true
        SetCdGlow(b, b.previewCombat and b.previewSpell)
    end)
    return b
end
local function Fit(stage, root, w, h, minScale)
    local sw, sh = (stage:GetWidth() or 0) - 24, (stage:GetHeight() or 0) - 12
    local scale = 1
    if w > 0 and sw > 0 and w > sw then scale = sw / w end
    if h > 0 and sh > 0 and h * scale > sh then scale = sh / h end
    root:SetScale(math.max(minScale or 0.3, scale))
end
local SIM_CD = { 8, 15, 30, 12, 45, 20 }
local function PreviewCd(stage, mode)
    local c, root = DB.cd, PreviewRoot(stage)
    local shown = {}
    for _, name in ipairs(c.spells) do local r = ResolveCd(name); if not r.grey then shown[#shown + 1] = r end end
    local n, now = #shown, GetTime()
    SizeCdRoot(root, c, n)
    root:ClearAllPoints()
    if c.orientation == "vertical" then root:SetPoint("CENTER", stage, "CENTER", 0, -2)
    else root:SetPoint("LEFT", stage, "LEFT", 12, -2) end
    for i, r in ipairs(shown) do
        local b = Pooled(root, i, PreviewButton)
        PositionCdButton(b, root, c, i)
        b.previewSpell = r.spellID ~= nil
        b.previewCombat = mode == "combat"
        b.cd:SetHideCountdownNumbers(not c.numbers)
        if b.tex ~= r.icon then b.icon:SetTexture(r.icon); b.tex = r.icon end
        if mode == "combat" then
            -- one after another: use it, wait out its cooldown, keep it ready a moment, use it again
            b.simNext = b.simNext or (now + (i - 1) * 0.9)
            if now >= b.simNext then
                local dur = SIM_CD[(i - 1) % #SIM_CD + 1]
                b.cd:SetCooldown(now, dur)
                b.icon:SetDesaturated(true)
                b.ready = false
                b.simNext = now + dur + 2 + (i % 3)
            end
        elseif b.simNext then
            b.simNext = nil
            b.cd:Clear()
            b.icon:SetDesaturated(false)
        end
        b:Show()
        SetCdGlow(b, b.previewCombat and b.previewSpell and b.ready)
    end
    for i = n + 1, #root.items do root.items[i]:Hide() end
    Fit(stage, root, root:GetWidth(), root:GetHeight(), 0.01)
    stage.note:SetText(n == 0 and "Nothing learned or carried from the list below yet" or "")
    root:SetAlpha(c.enabled and 1 or 0.4)
end
local SIM_BUFF = { 30, 120, 300 }
local function Clock(left)
    if left >= 60 then return ("%d:%02d"):format(left / 60, left % 60) end
    return ("%d"):format(math.max(0, left))
end
local function PreviewBuff(stage, mode)
    local c, root = DB.buff, PreviewRoot(stage)
    local n, now = 0, GetTime()
    for _, name in ipairs(c.spells) do
        local r = ResolveBuff(name)
        if n < 3 and not r.grey then
            n = n + 1
            local b = Pooled(root, n, Buffs.NewBar)
            PositionBuffBar(b, root, c, n)
            b.icon:SetTexture(r.icon)
            b.name:SetText(r.example or name)
            StyleBar(b, false)
            local dur = SIM_BUFF[n]
            b.bar:SetMinMaxValues(0, dur)
            if mode == "combat" then
                -- the bars run down and are recast when they run out
                if not b.simEnd or now >= b.simEnd then b.simEnd = now + dur * (0.35 + 0.2 * n) end
                local left = b.simEnd - now
                b.bar:SetValue(left)
                b.time:SetText(Clock(left))
            else
                b.simEnd = nil
                b.bar:SetValue(dur * 0.8)
                b.time:SetText(Clock(dur * 0.8))
            end
            b:SetAlpha(1)
            b:Show()
        end
    end
    for i = n + 1, #root.items do root.items[i]:Hide() end
    SizeBuffRoot(root, c, n)
    root:ClearAllPoints()
    root:SetPoint("TOP", stage, "TOP", 0, -6)
    Fit(stage, root, root:GetWidth(), root:GetHeight(), 0.01)
    stage.note:SetText(n == 0 and "Nothing learned from the list below yet" or "")
    root:SetAlpha(c.enabled and 1 or 0.4)
end
local function PreviewRemind(stage, mode)
    local c, root = DB.remind, PreviewRoot(stage)
    local lines = {}
    if mode ~= "combat" then
        local first = c.self[1] and Learned(c.self[1])
        if first and #first > 0 then lines[#lines + 1] = { first[1].iconID, Label(first) .. " missing" } end
        if c.party or c.target then
            local pick = c.byClass.WARRIOR
            local wanted = pick and pick ~= "" and Learned(pick) or (c.ally[1] and Learned(c.ally[1])) or {}
            if #wanted > 0 then lines[#lines + 1] = { wanted[1].iconID, Label(wanted) .. " missing: John Morten" } end
        end
    end
    local width = Reminders.Render(root, lines, Reminders.NewLine)
    root:ClearAllPoints()
    root:SetPoint("TOP", stage, "TOP", 0, -6)
    Fit(stage, root, width, root:GetHeight())
    stage.note:SetText(mode == "combat" and "Hidden in combat: reminders only show out of combat"
        or (#lines == 0 and "Nothing to remind you of: add a buff you've learned below" or ""))
    root:SetAlpha(c.enabled and 1 or 0.4)
end

function Preview.Invalidate(tracker)
    if tracker == "cd" then wipe(previewCd)
    elseif tracker == "buff" then wipe(previewBuff) end
end

Preview.ResolveCd = ResolveCd
Preview.ResolveBuff = ResolveBuff
Preview.ResolveSpell = ResolveSpell
Preview.Cd, Preview.Buff, Preview.Remind = PreviewCd, PreviewBuff, PreviewRemind
