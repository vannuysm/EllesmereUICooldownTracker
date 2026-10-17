-- Player aura assignments, native duration bars, and synthetic recast timers.
local _, ns = ...
local DB = ns.Database.character
local Collection = ns.Collection
local Frames = ns.TrackerFrames
local Appearance = ns.TrackerAppearance
local Readable = Collection.Readable
local Buffs = {}
ns.Trackers.buff = Buffs
local buffRoot
local SizeBuffRoot, PositionBuffBar = Frames.SizeBars, Frames.PositionBar
local IsOwnSpell = Collection.IsOwnSpell

-- Present in the live API (LuaDurationObjectAPIDocumentation) but missing from the bundled annotations.
---@class DurationObject
---@field IsActive fun(self: DurationObject, modifier?: Enum.DurationTimeModifier): boolean

local function BuffEditing()
    return ns.Kit.editMode or (ns.euiBuffUnlock and not InCombatLockdown())
end
local function BuffVisible(c)
    if not c.enabled then return false end
    if BuffEditing() or not c.locked then return true end
    if c.visibility == "combat" then return InCombatLockdown() end
    if c.visibility == "target" then
        local ok, attackable = pcall(UnitCanAttack, "player", "target")
        return InCombatLockdown() or (ok and Readable(attackable, "boolean") and attackable)
    end
    return true
end
-- A bar without tracker callbacks.
local function NewBar(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT")
    b.icon:SetPoint("BOTTOMLEFT")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetPoint("TOPLEFT", b.icon)
    b.cd:SetPoint("BOTTOMRIGHT", b.icon)
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 2, 0)
    b.bar:SetPoint("BOTTOMRIGHT")
    b.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    b.bar:SetStatusBarColor(0.2, 0.5, 0.9)
    b.bar.bg = b.bar:CreateTexture(nil, "BACKGROUND")
    b.bar.bg:SetAllPoints()
    b.bar.bg:SetColorTexture(0, 0, 0, 0.6)
    b.name = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.name:SetPoint("LEFT", 4, 0)
    b.time = b.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.time:SetPoint("RIGHT", -4, 0)
    return b
end
local function BuffBar(i)
    if buffRoot.items[i] then return buffRoot.items[i] end
    local b = NewBar(buffRoot)
    Frames.AttachMouse(b, buffRoot, "buff")
    buffRoot.items[i] = b
    return b
end

-- Aura fields may be secret or unreadable in combat: read them through pcall(Field, aura, key).
local function Field(aura, key) return aura and aura[key] end
-- Only readable names can be matched. prefix is lower case.
local function Matches(a, prefix)
    local ok, name = pcall(Field, a, "name")
    return ok and Readable(name, "string") and name:lower():find(prefix, 1, true) == 1
end

-- inverted: the bar fills as time passes, so the appearance swaps the fill and background colours.
local function StyleBar(b, inverted)
    b.inverted = inverted
    b.bar:SetReverseFill(inverted)
    Appearance.ApplyBuff(b, inverted)
end

-- Frames are pooled by index, but remembered aura/timer state belongs to the configured entry.
-- An unchanged entry keeps its last readable duration for combat fallback and synthetic recasts.
local function StopBuffTimer(b)
    if b.bar.SetTimerDuration and C_DurationUtil and C_DurationUtil.CreateDuration then
        pcall(b.bar.SetTimerDuration, b.bar, C_DurationUtil.CreateDuration())
    end
end
local function ResetBuffBar(b, entry)
    if b.entry == entry then return false end
    b.entry = entry
    b.entryInfo, b.infoRevision = nil, nil
    b.lastTimeText = nil
    b.lastTimeMinutes, b.nextTimerCheck = nil, nil
    b.readableDuration, b.readableExpiration = nil, nil
    b.aura, b.auraID, b.lastDuration, b.endsAt, b.synthetic, b.timerObject = nil, nil, nil, nil, nil, nil
    -- SetTimerDuration requires an object, not nil. Replace the old timer with a stopped, zero-duration one.
    StopBuffTimer(b)
    b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0)
    b.cd:Clear()
    b.icon:SetTexture(nil); b.name:SetText(""); b.time:SetText("")
    StyleBar(b, false)
    b:SetAlpha(1)
    b:Hide()
    return true
end

-- Drive the bar from a duration object so secret timings still animate. Returns "remaining" when the client
-- can count down on its own (normal look), "elapsed" when it can only fill up (inverted look), nil on failure.
local function SetTimer(bar, dur)
    local E = Enum
    if E and E.StatusBarTimerDirection and E.StatusBarInterpolation
        and pcall(bar.SetTimerDuration, bar, dur, E.StatusBarInterpolation.Immediate, E.StatusBarTimerDirection.RemainingTime) then
        return "remaining"
    end
    if pcall(bar.SetTimerDuration, bar, dur) then return "elapsed" end
end

-- Drive a bar from an aura instance. Uses the client's duration objects so secret timings still animate.
local function ApplyAura(b, a, durationObject)
    local okD, d = pcall(Field, a, "duration")
    local okE, e = pcall(Field, a, "expirationTime")
    -- an aura the game still lists but whose time is up counts as gone
    if a and okD and okE and Readable(d, "number") and Readable(e, "number") and d > 0 and e <= GetTime() then
        a, d, e = nil, nil, nil
    end
    b.aura = a
    b.synthetic = nil
    b.nextTimerCheck = nil
    if not a then b.lastTimeText = nil end
    b.auraID = a and a.auraInstanceID
    b.readableDuration = okD and Readable(d, "number") and d or nil
    b.readableExpiration = okE and Readable(e, "number") and e or nil
    if okD and Readable(d, "number") and d > 0 then b.lastDuration = d end
    -- when it runs out, if we can tell: in combat the game may not say when an aura ends, so the bar ends it itself
    -- (in combat the timings come back secret: then keep the end time we already know)
    if not a then b.endsAt = nil
    elseif okD and okE and Readable(d, "number") and Readable(e, "number") then b.endsAt = d > 0 and e or nil end
    if not a then
        b.timerObject = nil
        StopBuffTimer(b)
        b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(0); b.time:SetText(""); b.cd:Clear()
        return
    end
    local okIcon, icon = pcall(Field, a, "icon")
    if okIcon and icon then b.icon:SetTexture(icon) end
    local okName, name = pcall(Field, a, "name")
    b.name:SetText(okName and type(name) == "string" and name or "")
    local mode
    if durationObject and b.bar.SetTimerDuration then mode = SetTimer(b.bar, durationObject) end
    b.timerObject = mode ~= nil
    if b.inverted ~= (mode == "elapsed") then StyleBar(b, mode == "elapsed") end
    if not mode then b.bar:SetMinMaxValues(0, 1); b.bar:SetValue(1) end
    b.cd:Clear()
end
local function AuraID(aura) return aura and aura.auraInstanceID end
local function RefreshAura(b, aura, durations)
    local ok, id = pcall(AuraID, aura)
    local duration = ok and Collection.AuraDuration("player", id, durations)
    ApplyAura(b, aura, duration)
end

local buffLayoutDirty, buffDataDirty = true, true
local buffAppearanceDirty = true
local hiddenCasts = {}
local SyntheticAura
local function RenderBuffs()
    local c, shown = DB.buff, 0
    SizeBuffRoot(buffRoot, c, #c.spells)
    for i, name in ipairs(c.spells) do
        local b = BuffBar(i)
        -- inactive buffs are hidden; shown dimmed only while unlocked so you can place the frame
        if not b.aura and c.locked and not BuffEditing() then b:Hide() else
            shown = shown + 1
            PositionBuffBar(b, buffRoot, c, shown)
            StyleBar(b, b.inverted or false)
            b:Show()
            if not b.aura then
                local info = b.entryInfo
                b.icon:SetTexture(info and info.iconID or "Interface/Icons/INV_Misc_QuestionMark")
                b.name:SetText(name)
                b:SetAlpha(0.5)
            else
                b:SetAlpha(1)
            end
        end
    end
    buffLayoutDirty, buffAppearanceDirty = false, false
end
local function RenderBuffAppearance()
    for _, b in ipairs(buffRoot.items) do if b:IsShown() then StyleBar(b, b.inverted or false) end end
    buffAppearanceDirty = false
end
local function ApplyAuraDelta(b, name, delta)
    if Readable(b.auraID, "number") and delta.removed[b.auraID] then ApplyAura(b, nil) end
    delta.durations = delta.durations or {}
    local prefix = name:lower()
    for _, aura in ipairs(delta.added) do if Matches(aura, prefix) then RefreshAura(b, aura, delta.durations) end end
    if Readable(b.auraID, "number") and delta.updated[b.auraID] then
        local ok, aura = Collection.AuraInstance(delta, b.auraID)
        if ok then
            -- A refresh invalidates the old end time; an unreadable query keeps the last known state.
            if aura then b.endsAt = nil end
            RefreshAura(b, aura, delta.durations)
        end
    end
end
local function CollectBuffs(updateInfo)
    local snapshot, delta, durations = nil, Collection.AuraDelta(updateInfo), {}
    for i, name in ipairs(DB.buff.spells) do
        local b = BuffBar(i)
        local changed = ResetBuffBar(b, name)
        if b.infoRevision ~= Collection.spellRevision then
            b.entryInfo, b.infoRevision = Collection.Spell(name), Collection.spellRevision
        end
        local wasActive = b.aura ~= nil
        local readableID = type(b.auraID) == "nil" or Readable(b.auraID, "number")
        local handled = not changed and delta ~= nil and readableID
        if handled then ApplyAuraDelta(b, name, delta) end
        if not handled then
            snapshot = snapshot or Collection.Auras("player")
            local a, unknown = Collection.FindBuff(snapshot, name)
            local keep = false
            if not a and unknown and b.auraID then
                -- scan is blind in combat; ask about the instance we already track (nil = gone, error = keep as is)
                local ok, r = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", b.auraID)
                if ok then a = r else keep = true end
            end
            if not a and unknown and not b.auraID then keep = true end
            if not a and b.synthetic and b.endsAt and GetTime() < b.endsAt and (unknown or not b.auraID) then keep = true end
            local cast = hiddenCasts[name]
            if not a and cast and GetTime() < cast.start + cast.duration then
                SyntheticAura(b, cast.info, cast.start, cast.duration); keep = true
            end
            hiddenCasts[name] = nil
            if not keep then RefreshAura(b, a, durations) end
        end
        if changed or wasActive ~= (b.aura ~= nil) then buffLayoutDirty = true end
    end
end
local function UpdateBuffs(renderOnly, updateInfo)
    if not buffRoot then return end
    local c, wasVisible = DB.buff, buffRoot:IsShown()
    -- Reset existing assignments even while hidden or disabled; never create hidden frames.
    for i, b in ipairs(buffRoot.items) do
        if ResetBuffBar(b, c.spells[i]) then buffLayoutDirty = true; buffDataDirty = true end
        if i > #c.spells then b:Hide() end
    end
    local visible = BuffVisible(c)
    buffRoot:SetShown(visible)
    if not visible then buffDataDirty = true; return end
    if not wasVisible then buffDataDirty, buffLayoutDirty = true, true end
    if buffDataDirty then updateInfo, renderOnly = nil, false end
    if not renderOnly then CollectBuffs(updateInfo); buffDataDirty = false end
    if buffLayoutDirty then RenderBuffs() end
    if buffAppearanceDirty then RenderBuffAppearance() end
end

-- Fallback animation and countdown text for readable (non-secret) timings.
-- Is the aura behind a bar still running? Its duration object answers even in combat (a refresh by someone else shows
-- up there too). true or false, or nil when it can't tell.
local function StillRunning(b)
    if not (b.auraID and C_UnitAuras.GetAuraDuration) then return nil end
    local ok, d = pcall(C_UnitAuras.GetAuraDuration, "player", b.auraID)
    if not ok then return nil end
    if not d then return false end
    local okA, active = pcall(d.IsActive, d)
    if not (okA and Readable(active, "boolean")) then return nil end
    if active then
        local okR, left = pcall(d.GetRemainingDuration, d)
        if okR and Readable(left, "number") then b.endsAt = GetTime() + left end
    end
    return active
end

local nextBuffText = 0
local function TimeText(b, left)
    if not DB.buff.showTime or not b.time:IsShown() then return end
    local minutes = left >= 60
    local bucket = math.floor(math.max(0, left) / (minutes and 60 or 1))
    if b.lastTimeText == bucket and b.lastTimeMinutes == minutes then return end
    b.time:SetText(left >= 60 and ("%dm"):format(left / 60) or ("%d"):format(math.max(0, left)))
    b.lastTimeText, b.lastTimeMinutes = bucket, minutes
end
local function BuffOnUpdate()
    if not buffRoot:IsShown() then return end
    -- a bar whose time is up goes at once, without waiting for the game to report the aura gone (in combat it may not)
    local now, expired = GetTime(), false
    for _, b in ipairs(buffRoot.items) do
        if b.endsAt and now >= b.endsAt + 0.2 and (b.aura or b.synthetic)
            and (not b.nextTimerCheck or now >= b.nextTimerCheck) then
            b.nextTimerCheck = now + 0.2
            if b.synthetic or StillRunning(b) ~= true then
                b.endsAt = nil
                ApplyAura(b, nil)
                expired = true
            end
        end
    end
    if expired then RenderBuffs() end
    local updateText = now >= nextBuffText
    if updateText then nextBuffText = now + 0.1 end
    for _, b in ipairs(buffRoot.items) do
        local a = b.aura
        if b:IsShown() and b.synthetic then
            local left = b.synthetic.start + b.synthetic.duration - now
            b.bar:SetMinMaxValues(0, b.synthetic.duration); b.bar:SetValue(math.max(0, left))
            if updateText then TimeText(b, left) end
        elseif b:IsShown() and a then
            local dur, exp = b.readableDuration, b.readableExpiration
            if dur and exp and dur > 0 then
                local left = exp - now
                if not b.timerObject then b.bar:SetMinMaxValues(0, dur); b.bar:SetValue(left) end
                if updateText then TimeText(b, left) end
            elseif updateText and DB.buff.showTime and b.lastTimeText ~= "" then
                b.time:SetText(""); b.lastTimeText = ""
            end
        end
    end
end

-- Ground effects and totems leave no aura on the player, so their length has to be known up front.
local KNOWN_DURATION = { ["consecration"] = 8 }
function SyntheticAura(b, info, start, duration)
    b.aura = b.aura or { name = info.name, icon = info.iconID }
    b.icon:SetTexture(info.iconID); b.name:SetText(info.name)
    b.timerObject, b.lastTimeText = false, nil
    b.nextTimerCheck = nil
    StopBuffTimer(b)
    b.synthetic = { start = start, duration = duration }
    b.endsAt = start + duration
    StyleBar(b, false); b.cd:Clear()
end

-- A successful cast is visible even in combat. Refresh the matching bar from it; if the client hides the
-- aura, run a synthetic timer from the last known duration so the bar still resets on recast.
local function OnCast(spellID)
    local info = Readable(spellID, "number") and Collection.Spell(spellID)
    if not info or not Readable(info.name, "string") or not buffRoot or not DB.buff.enabled or not IsOwnSpell(spellID) then return end
    local handled, visible, durations = false, BuffVisible(DB.buff), {}
    local auraOK, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    for i, name in ipairs(DB.buff.spells) do
        if info.name:lower():find(name:lower(), 1, true) == 1 then
            local b = buffRoot.items[i]
            local duration = b and b.entry == name and b.lastDuration or KNOWN_DURATION[info.name:lower()]
            if not visible then
                if not aura and duration then hiddenCasts[name] = { info = info, start = GetTime(), duration = duration } end
                buffDataDirty = true
            else
                b = BuffBar(i); ResetBuffBar(b, name)
                local applied = auraOK and aura ~= nil and pcall(RefreshAura, b, aura, durations)
                if not applied and duration then SyntheticAura(b, info, GetTime(), duration); applied = true end
                handled = handled or applied
            end
        end
    end
    if handled then RenderBuffs() end
    return handled
end

function Buffs.Init()
    if buffRoot then return end
    buffRoot = Frames.MakeRoot("Buff", "buff")
    buffRoot:SetScript("OnUpdate", BuffOnUpdate)
end

function Buffs.ApplyConfiguration(effects)
    if effects.data then buffDataDirty = true; wipe(hiddenCasts) end
    if effects.layout or effects.visibility or effects.data then buffLayoutDirty = true end
    if effects.appearance then buffAppearanceDirty = true end
    UpdateBuffs(not effects.data)
end

function Buffs.InvalidateLayout() buffLayoutDirty = true end
function Buffs.Root() return buffRoot end
Buffs.Update = UpdateBuffs
Buffs.OnCast = OnCast
Buffs.NewBar = NewBar
Buffs.StyleBar = StyleBar
