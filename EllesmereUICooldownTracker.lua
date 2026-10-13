-- EllesmereUICooldownTracker, based on Forever Cooldown Tracker by Ugge Zen. Trackers: "cd" = icon row of spell cooldowns. "buff" = bars for player buffs (e.g. seals).
-- Saved variables load after this file runs: everything that touches DB is set up in Init() on ADDON_LOADED.
local ADDON_NAME, ns = ...
local DB = {}
local State = ns.Collection
ns.CLASS_BLESSING = { MAGE = "Blessing of Wisdom", WARLOCK = "Blessing of Wisdom", PRIEST = "Blessing of Wisdom",
    WARRIOR = "Blessing of Might", ROGUE = "Blessing of Might", PALADIN = "", DRUID = "", SHAMAN = "", HUNTER = "" }
ns.BLESSINGS = "Blessing of Might / Blessing of Wisdom / Blessing of Kings / Blessing of Salvation / Blessing of Light / Blessing of Sanctuary"
-- What a new character of each class starts with. Unlearned spells stay hidden until learned, so low levels see few icons.
-- cd: cooldown icons. buff: bars for your own timed buffs (a name matches any buff starting with it).
-- self / ally: buff reminders on you / on party members and a friendly target (" / " = any of these counts).
ns.CLASS_DEFAULTS = {
    PALADIN = { cd = { "Divine Protection", "Lay on Hands", "Hammer of Justice" }, buff = { "Seal of" },
        self = { ns.BLESSINGS }, ally = { ns.BLESSINGS } },
    WARRIOR = { cd = { "Bloodrage", "Berserker Rage", "Intercept", "Shield Wall", "Recklessness", "Retaliation" },
        buff = { "Battle Shout", "Enrage" }, self = { "Battle Shout" }, ally = {} },
    ROGUE = { cd = { "Kick", "Sprint", "Evasion", "Blind", "Vanish" }, buff = { "Slice and Dice", "Blade Flurry", "Adrenaline Rush" },
        self = {}, ally = {} },
    HUNTER = { cd = { "Rapid Fire", "Feign Death", "Freezing Trap", "Deterrence", "Bestial Wrath" }, buff = { "Rapid Fire", "Aspect of" },
        self = { "Aspect of the Hawk / Aspect of the Monkey / Aspect of the Cheetah / Aspect of the Pack / Aspect of the Wild / Aspect of the Beast", "Trueshot Aura" },
        ally = {} },
    PRIEST = { cd = { "Fade", "Psychic Scream", "Inner Focus", "Power Infusion" }, buff = { "Power Word: Shield", "Inner Fire" },
        self = { "Power Word: Fortitude / Prayer of Fortitude", "Inner Fire", "Divine Spirit / Prayer of Spirit" },
        ally = { "Power Word: Fortitude / Prayer of Fortitude", "Divine Spirit / Prayer of Spirit" } },
    SHAMAN = { cd = { "Earth Shock", "Grounding Totem", "Elemental Mastery", "Nature's Swiftness", "Mana Tide Totem", "Reincarnation" },
        buff = { "Lightning Shield" }, self = { "Lightning Shield" }, ally = {} },
    MAGE = { cd = { "Counterspell", "Blink", "Frost Nova", "Cone of Cold", "Evocation", "Ice Block" }, buff = { "Ice Barrier", "Mana Shield" },
        self = { "Arcane Intellect / Arcane Brilliance", "Frost Armor / Ice Armor / Mage Armor" },
        ally = { "Arcane Intellect / Arcane Brilliance" } },
    WARLOCK = { cd = { "Death Coil", "Howl of Terror", "Fel Domination", "Amplify Curse", "Shadowburn" }, buff = { "Shadow Ward" },
        self = { "Demon Skin / Demon Armor" }, ally = {} },
    DRUID = { cd = { "Barkskin", "Innervate", "Nature's Swiftness", "Bash", "Rebirth", "Tranquility" }, buff = { "Thorns" },
        self = { "Mark of the Wild / Gift of the Wild", "Thorns" }, ally = { "Mark of the Wild / Gift of the Wild" } },
}
for class, d in pairs(ns.CLASS_DEFAULTS) do
    if class == "WARLOCK" then table.insert(d.cd, "Spell Lock") end   -- the felhunter's
    table.insert(d.cd, "Healthstone")
    table.insert(d.cd, "Healing Potion")
    if class ~= "WARRIOR" and class ~= "ROGUE" then table.insert(d.cd, "Mana Potion") end
end
function ns.ClassDefaults()
    local ok, _, class = pcall(UnitClass, "player")
    return ns.CLASS_DEFAULTS[ok and type(class) == "string" and class or ""] or ns.CLASS_DEFAULTS.PALADIN
end
local function CdGrowth(c)
    if c.orientation == "vertical" then return c.growth == "up" and "up" or "down" end
    return c.growth == "left" and "left" or "right"
end

-- Let ForeverImmersion fade the trackers like any other element (plain data; see ForeverImmersion).
ForeverUI = ForeverUI or {}
ForeverUI.elements = ForeverUI.elements or {}
table.insert(ForeverUI.elements, { key = "ellesmere:euict", label = "Ellesmere cooldown tracker", frames = { "EUICT_CD", "EUICT_Buff" },
    visible = { combat = true, target = true, key = true } })
ForeverUI.revision = (ForeverUI.revision or 0) + 1
-- Settings are per character, keyed by GUID (never by name: characters can share one). Each character's settings live
-- in its own file (EUICT_DBC, tagged with its GUID) and again in the account file under EUICT_DB.chars[GUID], so the
-- account copy alone can restore every character; the newest copy wins (see Kit.lua, Saved data). Profiles and
-- remembered icons are account-wide, in EUICT_DB.
local ACCOUNT = { profiles = {}, icons = {}, chars = {} }
local function CharKey()
    local ok, guid = pcall(UnitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then return guid end
end
-- Up to 2.0 one copy was shared by every character: whoever logged out last wrote it.
local function Legacy(t) return type(t) == "table" and t._owner == nil and type(t.cd) == "table" end
local function PlayerClass()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and type(class) == "string" and class or nil
end
local function InitDB()
    local key = CharKey()
    local acct = type(EUICT_DB) == "table" and EUICT_DB or ACCOUNT
    local legacy
    if Legacy(acct) then
        legacy = acct
        acct = { profiles = acct.profiles, icons = acct.icons }
    end
    acct.chars = acct.chars or {}
    acct.profiles = acct.profiles or {}
    acct.icons = acct.icons or {}
    ACCOUNT = acct
    -- this character's own copies: its file (if it's really its own) and its entry in the account file
    local file, mine = EUICT_DBC, nil
    if type(file) == "table" and next(file) ~= nil then
        if Legacy(file) then legacy = ns.Kit.PickSaved(nil, legacy, file)
        elseif file._owner == key or not key then mine = file end
    end
    local src = ns.Kit.PickSaved(DB, mine, key and acct.chars[key])
    if not src and legacy and next(DB) == nil then
        -- before 2.0 only paladins used the tracker, so old settings are a paladin's: a paladin keeps them, any other
        -- class starts from its own defaults and only keeps where things were on screen
        if PlayerClass() == "PALADIN" then src = legacy
        else
            src = {}
            for _, k in ipairs({ "cd", "buff", "remind" }) do
                local t = legacy[k]
                if type(t) == "table" and t.x then src[k] = { x = t.x, y = t.y } end
            end
        end
        for name, data in pairs(type(legacy.profiles) == "table" and legacy.profiles or {}) do
            if acct.profiles[name] == nil then acct.profiles[name] = data end
        end
    end
    if src and src ~= DB then Mixin(DB, src) end
    DB.profiles, DB.icons, DB._owner = nil, nil, key or DB._owner
    EUICT_DB, EUICT_DBC = acct, DB
    if key then acct.chars[key] = DB end
    local def = ns.ClassDefaults()
    for section, fields in pairs(ns.ProfileValidation.Defaults()) do
        DB[section] = DB[section] or {}
        for field, value in pairs(fields) do if DB[section][field] == nil then DB[section][field] = value end end
    end
    for section, y in pairs({ cd = -180, buff = -230, remind = -120 }) do
        if DB[section].x == nil then DB[section].x = 0 end
        if DB[section].y == nil then DB[section].y = y end
    end
    DB.cd.orientation = DB.cd.orientation == "vertical" and "vertical" or "horizontal"
    DB.cd.growth = CdGrowth(DB.cd)
    DB.buff.growth = CdGrowth(DB.buff)
    -- 2.0.0 added items (and the warlock's pet ability) to the defaults: give them once to settings saved before,
    -- at the end of the list. Items only show while carried, and anyone who removes one keeps it removed.
    if not DB.cd.items2 then
        DB.cd.items2 = true
        for _, name in ipairs(def.cd) do
            if name == "Healthstone" or name == "Healing Potion" or name == "Mana Potion" or name == "Spell Lock" then
                local has = false
                for _, v in ipairs(DB.cd.spells) do if v:lower() == name:lower() then has = true end end
                if not has then table.insert(DB.cd.spells, name) end
            end
        end
    end
    -- icons seen once (account-wide), for spells not learned yet
    for k, v in pairs(ns.Kit.icons) do if ACCOUNT.icons[k] == nil then ACCOUNT.icons[k] = v end end
    ns.Kit.icons = ACCOUNT.icons
    -- the blessing each class should get from you; "" = any of the ally list (hybrids by default)
    local r = DB.remind
    for class, blessing in pairs(ns.CLASS_BLESSING) do
        if r.byClass[class] == nil then r.byClass[class] = blessing end
    end
end

-- key: "cd" or "buff". Settings are looked up through DB each time; the table is replaced when saved variables arrive late.
ns.Kit.StampOnLogout(function() return DB end)

local function MakeRoot(name, key)
    local cfg = DB[key]
    local f = CreateFrame("Frame", "EUICT_" .. name, UIParent)
    f:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    f:SetMovable(true)
    f:EnableMouse(not cfg.locked)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- after a drag the game anchors the frame by the nearest screen corner (BOTTOMLEFT near the bottom, ...), so its
        -- offsets aren't from the centre: measure the frame's centre against the screen's instead
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local s = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        x, y = math.floor(x * s - ux + 0.5), math.floor(y * s - uy + 0.5)
        ns.SaveTrackerPosition(key, x, y)
    end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 1, 0, 0.3)
    f.bg:SetShown(not cfg.locked)
    f.items = {}
    return f
end
local cdRoot, buffRoot
local ToggleConfig

-- Items take the mouse: right-click opens settings, left-drag moves the root when unlocked.
local function AttachMouse(item, root, key)
    item:EnableMouse(true)
    item:RegisterForDrag("LeftButton")
    item:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            if ns.OpenTrackerSettings then ns.OpenTrackerSettings(key) else ToggleConfig() end
        end
    end)
    item:SetScript("OnDragStart", function() if not DB[key].locked then root:StartMoving() end end)
    item:SetScript("OnDragStop", function() if not DB[key].locked then root:GetScript("OnDragStop")(root) end end)
end

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
local UpdateCd, QueueCd
local cdLayoutDirty, cdStateDirty = true, true
local cdAppearanceDirty = true
local cdWaiting = false
local Readable = State.Readable
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
-- Only a definite out-of-range result dims an icon; no target, no range, or secret results leave it unchanged.
local function OutOfRange(spellID, unit)
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
    return ok and Readable(inRange, "boolean") and not inRange
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
            b.previewCombat ~= nil and engine.PANEL_EXTRA or nil)
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
    for _, b in ipairs(cdRoot.items) do
        if b:IsShown() then
            local brightness = DB.cd.rangeDim ~= false and b.spellID and OutOfRange(b.spellID, "target") and 0.35 or 1
            b.icon:SetVertexColor(brightness, brightness, brightness)
            SetCdGlow(b, InCombatLockdown() and b.ready)
        end
    end
end
-- The first item in your bags whose name contains this text: { id, icon }
local BagItem = State.Item
local knownSpells, knownRevision = {}, -1
local function QueryKnownSpell(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and type(known) == "boolean" and not (issecretvalue and issecretvalue(known)) then
            if known then return true end
            -- your pet's abilities are in the pet spellbook
            local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
            local okP, petKnown = pcall(C_SpellBook.IsSpellKnown, spellID, pet)
            return pet ~= nil and okP and Readable(petKnown, "boolean") and petKnown
        end
    end
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, spellID)
        return ok and Readable(known, "boolean") and known
    end
    return true
end
local function KnownSpell(spellID)
    if knownRevision ~= State.spellRevision then wipe(knownSpells); knownRevision = State.spellRevision end
    if knownSpells[spellID] == nil then knownSpells[spellID] = QueryKnownSpell(spellID) == true end
    return knownSpells[spellID]
end
-- root: the tracker or a settings preview; only the real tracker takes the mouse and re-checks when a sweep ends
local CD_ANCHORS = {
    right = { "LEFT", 1, 0 }, left = { "RIGHT", -1, 0 },
    up = { "BOTTOM", 0, 1 }, down = { "TOP", 0, -1 },
}
local function SizeCdRoot(root, c, n)
    local length = math.max(1, n * c.size + (n - 1) * c.gap)
    if c.orientation == "vertical" then root:SetSize(c.size, length) else root:SetSize(length, c.size) end
end
local function PositionCdButton(b, root, c, i)
    local anchor = CD_ANCHORS[CdGrowth(c)]
    local offset = (i - 1) * (c.size + c.gap)
    b:SetSize(c.size, c.size)
    b:ClearAllPoints()
    b:SetPoint(anchor[1], root, anchor[1], offset * anchor[2], offset * anchor[3])
    if ns.ApplyCooldownAppearance then ns.ApplyCooldownAppearance(b) end
end
local function CdButton(i, root)
    root = root or cdRoot
    if root.items[i] then return root.items[i] end
    local b = CreateFrame("Frame", nil, root)
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
    if root == cdRoot then
        b.cd:SetScript("OnCooldownDone", function() QueueCd(b.spellID and "spell" or "item", b.spellID) end)
        AttachMouse(b, cdRoot, "cd")
    else
        b.cd:SetScript("OnCooldownDone", function()
            b.icon:SetDesaturated(false)
            b.ready = true
            SetCdGlow(b, b.previewCombat and b.previewSpell)
        end)
    end
    root.items[i] = b
    return b
end

local cdShown, cdSpellRevision, cdBagRevision = {}, -1, -1
local cdResolutionDirty = true
local function ResolveCooldowns()
    if not cdResolutionDirty and cdSpellRevision == State.spellRevision and cdBagRevision == State.bagRevision then return cdShown end
    wipe(cdShown)
    for _, name in ipairs(DB.cd.spells) do
        local info = State.Spell(name)
        if info and KnownSpell(info.spellID) then cdShown[#cdShown + 1] = { spell = info }
        else
            local item = BagItem(name)
            if item then cdShown[#cdShown + 1] = { item = item } end
        end
    end
    cdResolutionDirty, cdLayoutDirty, cdStateDirty = false, true, true
    cdSpellRevision, cdBagRevision = State.spellRevision, State.bagRevision
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
    SizeCdRoot(cdRoot, c, n)
    for i = 1, n do
        local entry, b = entries[i], CdButton(i)
        PositionCdButton(b, cdRoot, c, i)
        b.spellID = entry and entry.spell and entry.spell.spellID or nil
        b.icon:SetTexture(entry and (entry.spell and entry.spell.iconID or entry.item.icon) or "Interface/Icons/INV_Misc_QuestionMark")
        b.cd:SetHideCountdownNumbers(not c.numbers)
        if ns.ApplyCooldownAppearance then ns.ApplyCooldownAppearance(b) end
        if not entry then b.cd:Clear(); b.ready = false; b.icon:SetDesaturated(false) end
        b:Show()
    end
    for i = n + 1, #cdRoot.items do ReleaseCd(cdRoot.items[i]) end
    cdLayoutDirty, cdAppearanceDirty = false, false
end
local function RenderCooldownAppearance()
    for _, b in ipairs(cdRoot.items) do
        if b:IsShown() then
            b.cd:SetHideCountdownNumbers(not DB.cd.numbers)
            if ns.ApplyCooldownAppearance then ns.ApplyCooldownAppearance(b) end
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
        State.Cooldowns(entries, kind, ids)
        RenderCooldownState(entries)
        cdStateDirty = false
    end
    UpdateCdRange()
end

-- Buff bars -----------------------------------------------------------------
local function SizeBuffRoot(root, c, n)
    n = math.max(1, n)
    if c.orientation == "horizontal" then root:SetSize(n * c.width + (n - 1) * c.gap, c.height)
    else root:SetSize(c.width, n * c.height + (n - 1) * c.gap) end
end
local function PositionBuffBar(b, root, c, index)
    local a = CD_ANCHORS[CdGrowth(c)]
    local step = (c.orientation == "horizontal" and c.width or c.height) + c.gap
    b:SetSize(c.width, c.height)
    b.icon:SetWidth(c.height)
    b:ClearAllPoints()
    b:SetPoint(a[1], root, a[1], (index - 1) * step * a[2], (index - 1) * step * a[3])
end
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
local function BuffBar(i, root)
    root = root or buffRoot
    if root.items[i] then return root.items[i] end
    local b = CreateFrame("Frame", nil, root)
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
    if root == buffRoot then AttachMouse(b, buffRoot, "buff") end
    root.items[i] = b
    return b
end

-- A value we can do arithmetic or string work on. In 12.x type() reports a secret as the type it hides, so a type
-- check alone lets secrets through and the comparison after it errors.

-- returns aura, hadError; secret auras throw in combat, so skip them and report it
local function Matches(a, pattern)
    local ok, name = pcall(function() return a.name end)
    return ok and Readable(name, "string") and name:lower():find(pattern:lower(), 1, true) == 1
end

-- One look for every bar: textured blue for time remaining, dark for time gone.
-- inverted: the bar fills as time passes, so draw the blue underneath and the dark part on top.
local BAR_TEXTURE, BLUE = "Interface/TargetingFrame/UI-StatusBar", { 0.2, 0.5, 0.9 }
local function StyleBar(b, inverted)
    b.inverted = inverted
    b.bar:SetReverseFill(inverted)
    if ns.ApplyBuffAppearance then ns.ApplyBuffAppearance(b, inverted); return end
    if inverted then
        b.bar:SetStatusBarColor(0, 0, 0, 0.75)
        b.bar.bg:SetTexture(BAR_TEXTURE)
        b.bar.bg:SetVertexColor(BLUE[1], BLUE[2], BLUE[3], 1)
    else
        b.bar:SetStatusBarColor(BLUE[1], BLUE[2], BLUE[3])
        b.bar.bg:SetColorTexture(0, 0, 0, 0.6)
        b.bar.bg:SetVertexColor(1, 1, 1, 1)
    end
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
    -- an aura the game still lists but whose time is up counts as gone
    if a then
        local ok, x, dur = pcall(function() return a.expirationTime, a.duration end)
        if ok and Readable(x, "number") and Readable(dur, "number") and dur > 0 and x <= GetTime() then a = nil end
    end
    b.aura = a
    b.synthetic = nil
    b.nextTimerCheck = nil
    if not a then b.lastTimeText = nil end
    b.auraID = a and a.auraInstanceID
    local okD, d = pcall(function() return a and a.duration end)
    local okE, e = pcall(function() return a and a.expirationTime end)
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
    local okIcon, icon = pcall(function() return a.icon end)
    if okIcon and icon then b.icon:SetTexture(icon) end
    local okName, name = pcall(function() return a.name end)
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
    local duration = ok and State.AuraDuration("player", id, durations)
    ApplyAura(b, aura, duration)
end

local buffLayoutDirty, buffDataDirty = true, true
local buffAppearanceDirty = true
local hiddenCasts, SyntheticAura = {}, nil
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
    for _, aura in ipairs(delta.added) do if Matches(aura, name) then RefreshAura(b, aura, delta.durations) end end
    if Readable(b.auraID, "number") and delta.updated[b.auraID] then
        local ok, aura = State.AuraInstance(delta, b.auraID)
        if ok then
            -- A refresh invalidates the old end time; an unreadable query keeps the last known state.
            if aura then b.endsAt = nil end
            RefreshAura(b, aura, delta.durations)
        end
    end
end
local function CollectBuffs(updateInfo)
    local snapshot, delta, durations = nil, State.AuraDelta(updateInfo), {}
    for i, name in ipairs(DB.buff.spells) do
        local b = BuffBar(i)
        local changed = ResetBuffBar(b, name)
        if b.infoRevision ~= State.spellRevision then
            b.entryInfo, b.infoRevision = State.Spell(name), State.spellRevision
        end
        local wasActive = b.aura ~= nil
        local readableID = type(b.auraID) == "nil" or Readable(b.auraID, "number")
        local handled = not changed and delta ~= nil and readableID
        if handled then ApplyAuraDelta(b, name, delta) end
        if not handled then
            snapshot = snapshot or State.Auras("player")
            local a, unknown = State.FindBuff(snapshot, name)
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
local function UpdateBuffs(updateInfo, renderOnly)
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
            local left = b.synthetic.start + b.synthetic.duration - GetTime()
            b.bar:SetMinMaxValues(0, b.synthetic.duration); b.bar:SetValue(math.max(0, left))
            if updateText then TimeText(b, left) end
        elseif b:IsShown() and a then
            local dur, exp = b.readableDuration, b.readableExpiration
            if dur and exp and dur > 0 then
                local left = exp - GetTime()
                if not b.timerObject then b.bar:SetMinMaxValues(0, dur); b.bar:SetValue(left) end
                if updateText then TimeText(b, left) end
            elseif updateText and DB.buff.showTime and b.lastTimeText ~= "" then
                b.time:SetText(""); b.lastTimeText = ""
            end
        end
    end
end

-- Procs fire UNIT_SPELLCAST_SUCCEEDED too, often under the seal's own name (Seal of Command's melee hit).
-- Only spells the player can actually cast count as a recast.
local function IsOwnSpell(spellID)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and Readable(known, "boolean") then return known end
    end
    local ok, known = pcall(IsPlayerSpell, spellID)
    return ok and Readable(known, "boolean") and known
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
    local info = Readable(spellID, "number") and State.Spell(spellID)
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
                local applied = auraOK and aura and pcall(RefreshAura, b, aura, durations)
                if not applied and duration then SyntheticAura(b, info, GetTime(), duration); applied = true end
                handled = handled or applied
            end
        end
    end
    if handled then RenderBuffs() end
    return handled
end

-- Buff reminders ------------------------------------------------------------
-- Out of combat, a line for each buff that's missing: on you, and (opt-in) your buff on party members or a friendly
-- target. One list entry is one reminder; " / " separates buffs that each satisfy it. Only buffs the character has
-- learned count, so it never asks for a spell you can't cast, and a class with nothing learned from the list sees nothing.
-- Not registered with ForeverImmersion on purpose: it shows exactly when Immersion would fade things out.
local remindRoot

local learnedEntries, learnedRevision = {}, -1
local function Learned(entry)
    if learnedRevision ~= State.spellRevision then wipe(learnedEntries); learnedRevision = State.spellRevision end
    if learnedEntries[entry] then return learnedEntries[entry] end
    local out = {}
    for name in entry:gmatch("[^/]+") do
        name = name:match("^%s*(.-)%s*$")
        local info = name ~= "" and State.Spell(name)
        if info and IsOwnSpell(info.spellID) then out[#out + 1] = info end
    end
    learnedEntries[entry] = out
    return out
end

-- What to call a reminder: the shared leading words ("Blessing of Might", "Blessing of Kings" -> "Blessing").
local function Label(learned)
    if learned.label then return learned.label end
    local words = {}
    for w in learned[1].name:gmatch("%S+") do words[#words + 1] = w end
    local n = #words
    for i = 2, #learned do
        local j = 0
        for w in learned[i].name:gmatch("%S+") do
            if j >= n or words[j + 1] ~= w then break end
            j = j + 1
        end
        n = j
    end
    if n > 0 and (words[n] == "of" or words[n] == "the") then n = n - 1 end
    learned.label = n > 0 and table.concat(words, " ", 1, n) or learned[1].name
    return learned.label
end

-- true or false; nil when the unit's auras can't be read (secret), so it never reminds on a guess.
-- mine: only buffs the player cast count (another paladin's Kings doesn't replace your Might).
local function HasBuff(unit, learned, mine)
    return State.HasBuff(State.Auras(unit), learned, mine)
end

-- A test that may come back secret: only a readable true counts.
local function Yes(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and Readable(v, "boolean") and v
end

local function AllyUnits()
    local c, out = DB.remind, {}
    local function add(u)
        if not Yes(UnitExists, u) or not Yes(UnitIsPlayer, u) or Yes(UnitIsDeadOrGhost, u) then return end
        if UnitIsConnected and not Yes(UnitIsConnected, u) then return end
        for _, existing in ipairs(out) do if Yes(UnitIsUnit, u, existing) then return end end
        out[#out + 1] = u
    end
    if c.party then for i = 1, 4 do add("party" .. i) end end
    if c.target and Yes(UnitIsFriend, "player", "target") and not Yes(UnitIsUnit, "target", "player")
        and not (c.party and Yes(UnitInParty, "target")) then
        add("target")
    end
    return out
end

-- Forever gives characters a first and a last name: UnitName returns the surname where retail puts a realm.
local function UnitLabel(u)
    local ok, name, last = pcall(UnitName, u)
    name = ok and Readable(name, "string") and name ~= "" and name or nil
    if not name then return u == "target" and TARGET or "party member" end
    last = Readable(last, "string") and last ~= "" and last or nil
    local realm = GetRealmName and GetRealmName()
    realm = Readable(realm, "string") and realm or ""
    if last and last ~= realm and last ~= realm:gsub("%s", "") then return name .. " " .. last end
    return name
end

local function RemindLine(i)
    if remindRoot.items[i] then return remindRoot.items[i] end
    local l = CreateFrame("Frame", nil, remindRoot)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetPoint("LEFT")
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
    AttachMouse(l, remindRoot, "remind")
    remindRoot.items[i] = l
    return l
end

local reminderLines = {}
local function CollectReminders()
    local c = DB.remind
    if not remindRoot then return end
    local lines = {}
    if c.enabled and not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player") then
        for _, entry in ipairs(c.self) do
            local learned = Learned(entry)
            if #learned > 0 and HasBuff("player", learned, false) == false then
                lines[#lines + 1] = { learned[1].iconID, Label(learned) .. " missing" }
            end
        end
        -- one line per missing buff, naming everyone who lacks it, in the order first seen
        local missing = {}
        local function miss(learned, u)
            local label = Label(learned) .. " missing"
            if not missing[label] then
                missing[label] = { learned[1].iconID, {} }
                missing[#missing + 1] = label
            end
            local who = missing[label][2]
            who[#who + 1] = UnitLabel(u)
        end
        for _, u in ipairs((c.party or c.target) and AllyUnits() or {}) do
            -- a class with its own blessing (Wisdom for casters, Might for melee) is reminded of that one
            local ok, _, class = pcall(UnitClass, u)
            local pick = ok and Readable(class, "string") and c.byClass[class]
            local wanted = pick and pick ~= "" and Learned(pick)
            if wanted and #wanted > 0 then
                if HasBuff(u, wanted, true) == false and not OutOfRange(wanted[1].spellID, u) then miss(wanted, u) end
            else
                for _, entry in ipairs(c.ally) do
                    local learned = Learned(entry)
                    if #learned > 0 and HasBuff(u, learned, true) == false and not OutOfRange(learned[1].spellID, u) then miss(learned, u) end
                end
            end
        end
        for _, label in ipairs(missing) do
            lines[#lines + 1] = { missing[label][1], label .. ": " .. table.concat(missing[label][2], ", ") }
        end
    end
    -- a sample line while unlocked or in Edit Mode, so there's something to place
    if #lines == 0 and c.enabled and (not c.locked or ns.Kit.editMode or (ns.euiUnlockMode and not InCombatLockdown())) then
        lines[1] = { "Interface/Icons/Spell_Holy_FistOfJustice", "Buff reminder" }
    end
    return lines
end
local function RenderReminders(lines)
    local c = DB.remind
    local width = 1
    for i, line in ipairs(lines) do
        local l = RemindLine(i)
        l:SetSize(c.size, c.size)
        l.icon:SetSize(c.size, c.size)
        l.icon:SetTexture(line[1])
        l.text:SetText(line[2])
        if ns.ApplyReminderAppearance then ns.ApplyReminderAppearance(l) end
        l:SetWidth(c.size + 6 + l.text:GetStringWidth())
        l:ClearAllPoints()
        l:SetPoint("TOP", 0, -(i - 1) * (c.size + c.gap))
        l:Show()
        width = math.max(width, l:GetWidth())
    end
    for i = #lines + 1, #remindRoot.items do
        local line = remindRoot.items[i]
        line:Hide(); line.text:SetText(""); line.icon:SetTexture(nil)
    end
    remindRoot:SetSize(width, math.max(1, #lines * (c.size + c.gap) - c.gap))
    remindRoot:SetShown(#lines > 0)
end

local function UpdateRemind(renderOnly)
    if not remindRoot then return end
    if not renderOnly then reminderLines = CollectReminders() end
    RenderReminders(reminderLines)
end
-- Coalesce bursts at the next frame. Unknown/legacy cooldown payloads request a full state refresh.
local pending = { ids = {} }
local queued = false
local function FlushUpdates()
    queued = false
    local cd, buff, remind = pending.cd, pending.buff, pending.remind
    pending.cd, pending.buff, pending.remind = nil, nil, nil
    if cd then UpdateCd(false, cd ~= "all" and cd or nil, cd == "spell" and next(pending.ids) and pending.ids or nil) end
    wipe(pending.ids)
    if buff then UpdateBuffs() end
    if remind then UpdateRemind() end
end
local function QueueUpdate(key)
    pending[key] = true
    if not queued then queued = true; C_Timer.NewTimer(0, FlushUpdates) end
end
function QueueCd(kind, id)
    if pending.cd ~= kind then pending.cd = pending.cd and "all" or kind end
    if kind == "spell" then
        if Readable(id, "number") then pending.ids[id] = true else pending.cd = "all" end
    end
    if not queued then queued = true; C_Timer.NewTimer(0, FlushUpdates) end
end
local function UpdateAll() UpdateCd(); UpdateBuffs(); UpdateRemind() end

local function Init()
    InitDB()
    cdRoot, buffRoot, remindRoot = MakeRoot("CD", "cd"), MakeRoot("Buff", "buff"), MakeRoot("Remind", "remind")
    buffRoot:SetScript("OnUpdate", BuffOnUpdate)
    C_Timer.NewTicker(2, function()
        -- Two-second safety net for missed aura events and ally range changes, only for visible/enabled consumers.
        State.InvalidateAuras()
        UpdateBuffs(); UpdateRemind()
        if State.bagsUnknown and cdRoot:IsShown() then State.InvalidateBags(); QueueCd("all") end
        if ns.ApplyCooldownAppearance then
            if cdRoot:IsShown() then
                for _, b in ipairs(cdRoot.items) do if b:IsShown() then ns.ApplyCooldownAppearance(b) end end
            end
        end
    end)
    C_Timer.NewTicker(0.5, function() if cdWaiting and cdRoot:IsShown() then QueueCd("all") end end)
    C_Timer.NewTicker(0.2, UpdateCdRange)
    -- Blizzard's Edit Mode: both trackers get Edit Mode's overlay and can be dragged there, per layout.
    for _, t in ipairs({ { cdRoot, "cd", "Cooldown icons" }, { buffRoot, "buff", "Buff bars" }, { remindRoot, "remind", "Buff reminders" } }) do
        local root, key = t[1], t[2]
        ns.Kit.EditMode({
            frame = root, label = t[3], key = key, db = DB,
            get = function() return DB[key].x, DB[key].y end,
            set = function(x, y)
                ns.SaveTrackerPosition(key, x, y)
            end,
            enabled = function() return DB[key].enabled end,
            onToggle = function() ns.ConfigChanged(key, "editing") end,
        })
    end
    ns.Ranks.Init(function() return DB.ranks or {} end)
    UpdateAll()
end

local SPELL_DEPENDENCY_EVENTS = {
    SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true, UNIT_PET = true, PET_BAR_UPDATE = true,
    UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true, SPELL_UPDATE_ICON = true,
    PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
}
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") -- seal recast doesn't always fire UNIT_AURA here
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
for event in pairs(SPELL_DEPENDENCY_EVENTS) do
    if event ~= "SPELLS_CHANGED" and event ~= "UNIT_PET" then pcall(ev.RegisterEvent, ev, event) end
end
ev:RegisterEvent("UNIT_PET")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, eventArg, info, ...)
    if event == "ADDON_LOADED" then if eventArg == ADDON_NAME then Init() end
    elseif event == "PLAYER_LOGIN" then
        do
            InitDB()
            State.InvalidateSpells(); State.InvalidateBags(); State.InvalidateAuras()
            ns.Configuration.Apply({ cd = { all = true }, buff = { all = true }, remind = { all = true }, ranks = { all = true } })
        end
    elseif event == "UNIT_AURA" then
        State.InvalidateAuras("player")
        UpdateBuffs(type(info) == "table" and info or nil)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        State.InvalidateAuras("player")
        if not OnCast((...)) then QueueUpdate("buff") end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local category, recovery, itemID = ...
        -- Shared categories, GCDs and item use may change other icons too.
        if type(category) ~= "nil" or type(recovery) ~= "nil" or type(itemID) ~= "nil" then QueueCd("all")
        else
            QueueCd("spell", eventArg)
            if Readable(info, "number") then pending.ids[info] = true end -- base ID of an override
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then QueueCd("item")
    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        State.InvalidateBags(); QueueCd("all")
    elseif SPELL_DEPENDENCY_EVENTS[event] then
        if (event == "UNIT_PET" or event == "PLAYER_SPECIALIZATION_CHANGED") and eventArg ~= "player" then return end
        State.InvalidateSpells(); buffLayoutDirty = true
        QueueCd("all"); QueueUpdate("buff"); QueueUpdate("remind")
    elseif event == "PLAYER_ENTERING_WORLD" then
        State.InvalidateSpells(); State.InvalidateBags(); State.InvalidateAuras()
        QueueCd("all"); QueueUpdate("buff"); QueueUpdate("remind")
    else
        UpdateCd(true); UpdateBuffs(nil, true)
    end
end)

-- Reminders watch party and target auras too, and go away the moment combat starts.
local rev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_AURA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "UNIT_CONNECTION", "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE" }) do rev:RegisterEvent(e) end
rev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and not (unit == "player" or unit == "target" or (type(unit) == "string" and unit:find("^party%d$"))) then return end
    if event == "UNIT_AURA" then
        if unit ~= "player" then State.InvalidateAuras(unit) end -- the player handler owns this shared snapshot
    elseif event == "GROUP_ROSTER_UPDATE" then
        for i = 1, 4 do State.InvalidateAuras("party" .. i) end
        State.InvalidateAuras("target")
    elseif event == "PLAYER_TARGET_CHANGED" then State.InvalidateAuras("target")
    elseif event == "UNIT_CONNECTION" then State.InvalidateAuras(unit)
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then State.InvalidateAuras("player") end
    if event == "PLAYER_REGEN_DISABLED" then UpdateRemind() else QueueUpdate("remind") end
end)

-- Settings (Options > AddOns) ------------------------------------------------------
-- A main page with an overview, and a sub-page per tracker: live preview at the top, the look in a card, then what to
-- track as icons. Profiles save the whole setup, and share it as text.
local Kit = ns.Kit
local QUESTION = 134400

local function SetLocked(key, value) ns.SetConfig(key, "locked", value) end
local function Opt(tracker, key) return function() return DB[tracker] and DB[tracker][key] end end
local function SetOpt(tracker, key) return function(value) ns.SetConfig(tracker, key, value) end end
local function List(tracker, key) return function() return DB[tracker] and DB[tracker][key] end end

-- How a cooldown entry looks in the settings: learned spell, item in your bags, or greyed until then.
local previewCd, previewBuff, previewSpellRevision, previewBagRevision = {}, {}, -1, -1
local function PreviewDependencies()
    if previewSpellRevision ~= State.spellRevision then
        wipe(previewCd); wipe(previewBuff); previewSpellRevision = State.spellRevision
    end
    if previewBagRevision ~= State.bagRevision then wipe(previewCd); previewBagRevision = State.bagRevision end
end
local function ResolveCdUncached(name)
    local info = State.Spell(name)
    if info and KnownSpell(info.spellID) then
        Kit.icons[name] = info.iconID
        local ok, sub = pcall(C_Spell.GetSpellSubtext, info.spellID)
        return { icon = info.iconID, spellID = info.spellID, tag = ok and Readable(sub, "string") and sub ~= "" and sub or "Spell" }
    end
    local it = BagItem(name)
    if it then return { icon = it.icon, tag = ("Item  Â·  %d in your bags"):format(it.count) } end
    return { icon = Kit.icons[name] or QUESTION, grey = true, tag = "Shows once you learn it, or carry it" }
end
local function ResolveBuffUncached(name)
    local info = State.Spell(name)
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

-- Pools of preview pieces, made once per stage.
local function Pool(stage, key, make)
    stage[key] = stage[key] or {}
    local pool = stage[key]
    return function(i) pool[i] = pool[i] or make(); return pool[i] end, pool
end
local function HideFrom(pool, n) for i = n + 1, #pool do pool[i]:Hide() end end

-- Pages
local main = Kit.NewPage("EllesmereUICooldownTracker")
local cdPage = Kit.NewPage("Cooldowns")
local buffPage = Kit.NewPage("Buff bars")
local remindPage = Kit.NewPage("Reminders")
local rankPage = Kit.NewPage("Spell ranks")
local profilePage = Kit.NewPage("Profiles")
local subs = { cd = cdPage, buff = buffPage, remind = remindPage, ranks = rankPage, profiles = profilePage }
ns.settingsPages = { main = main, cd = cdPage, buff = buffPage, remind = remindPage, ranks = rankPage, profiles = profilePage }

-- Main page: what each part does, on or off, and the way in.
main:Text("Right-click any icon or bar to open these settings. Unlock a tracker, or use Edit Mode, to move it.", "GameFontHighlightSmall")
local OVERVIEW = {
    { "cd", 135954, "Cooldowns", "Icons for cooldowns, healthstones and potions. Spells dim out of range and glow when ready in combat." },
    { "buff", 135924, "Buff bars", "Timers for your own buffs, such as your seal." },
    { "remind", 135906, "Reminders", "Out of combat: a line for each missing buff, on you and (if you like) your party." },
    { "ranks", 135920, "Spell ranks", "Marks action buttons that hold an older rank than one you know." },
    { "profiles", 134331, "Profiles", "Save your setup, load it on another character, or share it with a friend." },
}
for _, o in ipairs(OVERVIEW) do
    local key = o[1]
    main:Card(nil, 58, function(card, page)
        local icon = Kit.Icon(card, 36)
        icon:SetPoint("LEFT", 12, 0)
        icon:SetTexture(o[2])
        local t = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        t:SetPoint("TOPLEFT", 60, -10)
        t:SetText(o[3])
        local d = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        d:SetPoint("TOPLEFT", 60, -32)
        d:SetPoint("RIGHT", card, "RIGHT", -230, 0)
        d:SetJustifyH("LEFT")
        d:SetText(o[4])
        local open = Kit.Make("Button", card, "UIPanelButtonTemplate")
        open:SetSize(90, 22)
        open:SetPoint("RIGHT", -12, 0)
        open:SetText("Settings")
        open:SetScript("OnClick", function() if subs[key].category then Settings.OpenToCategory(subs[key].category:GetID()) end end)
        if key ~= "profiles" then
            local c = page:CheckAt(card, 0, 0, "Show", function() return DB[key] and DB[key].enabled end, function(v)
                ns.SetConfig(key, "enabled", v)
            end)
            c:ClearAllPoints()
            c:SetPoint("RIGHT", open, "LEFT", -70, 0)
        end
    end)
end
main:Section("Other")
main:Button("Reset all settings", RESET or "Reset", function() wipe(DB); ReloadUI() end, "Back to defaults. Reloads the UI.")

-- The previews draw their own copy of each tracker with the same pieces and your settings (the real ones may be hidden
-- by ForeverImmersion, and show only what's happening right now). "Simulate combat" uses the icons in turn: grey,
-- sweep and countdown, and the buff bars run down, so size and numbers can be judged as they look in a fight.
local function PreviewRoot(stage, key)
    if stage.root then return stage.root end
    local r = CreateFrame("Frame", nil, stage)
    r.items = {}
    stage.root = r
    return r
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
        local b = CdButton(i, root)
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
            local b = BuffBar(n, root)
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
    local width = 1
    for i, l in ipairs(lines) do
        root.items[i] = root.items[i] or (function()
            local f = CreateFrame("Frame", nil, root)
            f.icon = Kit.Icon(f, 24)
            f.icon:SetPoint("LEFT")
            f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.text:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
            return f
        end)()
        local f = root.items[i]
        f.icon:SetSize(c.size, c.size)
        f.icon:SetTexture(l[1])
        f.text:SetText(l[2])
        if ns.ApplyReminderAppearance then ns.ApplyReminderAppearance(f) end
        f:SetSize(c.size + 6 + f.text:GetStringWidth(), c.size)
        f:ClearAllPoints()
        f:SetPoint("TOP", 0, -(i - 1) * (c.size + c.gap))
        f:Show()
        width = math.max(width, f:GetWidth())
    end
    for i = #lines + 1, #root.items do root.items[i]:Hide() end
    root:SetSize(width, math.max(1, #lines * (c.size + c.gap) - c.gap))
    root:ClearAllPoints()
    root:SetPoint("TOP", stage, "TOP", 0, -6)
    Fit(stage, root, width, root:GetHeight())
    stage.note:SetText(mode == "combat" and "Hidden in combat: reminders only show out of combat"
        or (#lines == 0 and "Nothing to remind you of: add a buff you've learned below" or ""))
    root:SetAlpha(c.enabled and 1 or 0.4)
end

-- Cooldowns
cdPage:Text("Ready glows follow EllesmereUI Action Bars > Bar Animations > Custom Proc Glow and appear only in combat.", "GameFontHighlightSmall")
local cdPreview = cdPage:Preview(90, PreviewCd, { modes = true })
cdPage:OnRefresh(function()
    cdPreview:GetParent():SetHeight(DB.cd and DB.cd.orientation == "vertical" and 240 or 90)
end)
cdPage:Card("Look", 98, function(card, p)
    p:CheckAt(card, 8, -28, "Show", Opt("cd", "enabled"), SetOpt("cd", "enabled"), "Turn the cooldown icons on or off.")
    p:CheckAt(card, 120, -28, "Countdown numbers", Opt("cd", "numbers"), SetOpt("cd", "numbers"), "Draw the remaining time on each icon.")
    p:CheckAt(card, 320, -28, "Locked", Opt("cd", "locked"), function(v) SetLocked("cd", v) end, "Unlock to drag the cooldown tracker. A green box shows its area.")
    p:SliderAt(card, 14, -64, "Size", 16, 80, 1, Opt("cd", "size"), SetOpt("cd", "size"), 140)
    p:SliderAt(card, 320, -64, "Spacing", 0, 20, 1, Opt("cd", "gap"), SetOpt("cd", "gap"), 120)
end)
cdPage:Dropdown("Show bars", { { "always", "Always" }, { "combat", "In combat" },
    { "target", "In combat or with an attackable target" } }, Opt("cd", "visibility"), SetOpt("cd", "visibility"),
    "Choose when the cooldown icons are visible. Unlocking the tracker keeps it visible for positioning.")
cdPage:Section("Layout")
cdPage:Dropdown("Orientation", { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }, Opt("cd", "orientation"), function(v)
    ns.SetConfig("cd", "orientation", v)
end, "Arrange cooldown icons in a horizontal row or a vertical column.")
cdPage:Dropdown("Grow direction", function()
    if DB.cd and DB.cd.orientation == "vertical" then return { { "up", "Up" }, { "down", "Down" } } end
    return { { "right", "Right" }, { "left", "Left" } }
end, function() return CdGrowth(DB.cd or {}) end, function(v)
    ns.SetConfig("cd", "growth", v)
end, "Right starts at the left edge; Left starts at the right edge. Up starts at the bottom; Down starts at the top.")
cdPage:Icons(List("cd", "spells"), { title = "Tracked", sources = { "spells", "items" }, resolve = ResolveCd, onChange = function() ns.ConfigChanged("cd", "spells") end,
    later = "Not learned yet, or not in your bags",
    laterHint = "These join the row by themselves once you learn them or carry one. Part of an item name is enough: \"Healthstone\" covers every healthstone." })

-- Buff bars
buffPage:Preview(40 + 3 * 30, PreviewBuff, { modes = true })
buffPage:Card("Look", 128, function(card, p)
    p:CheckAt(card, 8, -28, "Show", Opt("buff", "enabled"), SetOpt("buff", "enabled"), "Turn the buff bars on or off.")
    p:CheckAt(card, 120, -28, "Locked", Opt("buff", "locked"), function(v) SetLocked("buff", v) end, "Unlock to drag the bars. Inactive bars show dimmed while unlocked.")
    p:SliderAt(card, 14, -64, "Width", 80, 400, 5, Opt("buff", "width"), SetOpt("buff", "width"), 140)
    p:SliderAt(card, 320, -64, "Height", 12, 48, 1, Opt("buff", "height"), SetOpt("buff", "height"), 120)
    p:SliderAt(card, 14, -96, "Spacing", 0, 20, 1, Opt("buff", "gap"), SetOpt("buff", "gap"), 140)
end)
buffPage:Icons(List("buff", "spells"), { title = "Tracked buffs", sources = { "spells" }, resolve = ResolveBuff, onChange = function() ns.ConfigChanged("buff", "spells") end,
    later = "Not learned yet", laterHint = "These get a bar once you learn them.",
    subtitle = "A name matches any buff starting with it: \"Seal of\" covers every seal" })

-- Reminders
local CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID", "PRIEST", "MAGE", "WARLOCK" }
remindPage:Preview(40 + 2 * 32, PreviewRemind, { modes = true })
remindPage:Card("When", 98, function(card, p)
    p:CheckAt(card, 8, -28, "Show reminders", Opt("remind", "enabled"), SetOpt("remind", "enabled"), "Out of combat, show a reminder when a buff is missing.")
    p:CheckAt(card, 180, -28, "Party members", Opt("remind", "party"), SetOpt("remind", "party"), "Name who in your party is missing your buff, when they're in range.")
    p:CheckAt(card, 350, -28, "Friendly target", Opt("remind", "target"), SetOpt("remind", "target"), "Name the friendly player you target when they're missing your buff.")
    p:CheckAt(card, 8, -60, "Locked", Opt("remind", "locked"), function(v) SetLocked("remind", v) end, "Unlock to drag the reminders. A sample line shows while unlocked.")
    p:SliderAt(card, 186, -64, "Icon size", 12, 48, 1, Opt("remind", "size"), SetOpt("remind", "size"), 120)
end)
remindPage:IconGroups(List("remind", "self"), { title = "Buffs you should have", label = function(names)
    local learned = {}
    for _, n in ipairs(names) do learned[#learned + 1] = { name = n } end
    return #names > 1 and ("Any: " .. Label(learned)) or names[1]
end, onChange = function() ns.ConfigChanged("remind", "self") end })
remindPage:IconGroups(List("remind", "ally"), { title = "Buffs you give others", subtitle = "Only ones you cast count",
    label = function(names) local l = {}; for _, n in ipairs(names) do l[#l + 1] = { name = n } end; return #names > 1 and ("Any: " .. Label(l)) or names[1] end,
    onChange = function() ns.ConfigChanged("remind", "ally") end })

-- The blessing each class gets from you: a card per class, the blessing as a button that opens a menu with icons.
do
    local b = remindPage:AddBlock(40 + 3 * 60, 12)
    local top = Kit.Heading(b, "Blessing each class gets from you", "Click a blessing to change it. Any: whichever of yours they're missing.")
    local cards = {}
    local function Choices()
        local out = { { "", "Any" } }
        for _, name in ipairs(Kit.Split(ns.BLESSINGS)) do out[#out + 1] = { name, name } end
        return out
    end
    for i, class in ipairs(CLASSES) do
        local card = Kit.Box(b, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.07 })
        card:SetHeight(52)
        card.ci = card:CreateTexture(nil, "ARTWORK")
        card.ci:SetSize(30, 30)
        card.ci:SetPoint("LEFT", 10, 0)
        if not pcall(card.ci.SetAtlas, card.ci, "classicon-" .. class:lower()) then card.ci:SetTexture(QUESTION) end
        card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.name:SetPoint("LEFT", card.ci, "RIGHT", 10, 7)
        card.name:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class)
        card.pick = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.pick:SetPoint("LEFT", card.ci, "RIGHT", 10, -9)
        card.slot = CreateFrame("Button", nil, card)
        card.slot:SetSize(36, 36)
        card.slot:SetPoint("RIGHT", -8, 0)
        local frame = Kit.Box(card.slot, { 0, 0, 0, 0.6 }, { 1, 0.82, 0, 0.5 })
        frame:SetAllPoints()
        card.icon = Kit.Icon(card.slot, 32, "OVERLAY")
        card.icon:SetPoint("CENTER")
        card.any = card.slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.any:SetPoint("CENTER")
        card.any:SetText("Any")
        card.slot:SetScript("OnClick", function(self)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, o in ipairs(Choices()) do
                    local info = o[1] ~= "" and Kit.SpellByName(o[1])
                    local text = (info and ("|T" .. info.iconID .. ":16|t ") or "") .. o[2]
                    root:CreateRadio(text, function() return DB.remind.byClass[class] == o[1] end, function()
                        DB.remind.byClass[class] = o[1]
                        ns.ConfigChanged("remind", "byClass")
                    end)
                end
            end)
        end)
        Kit.Tooltip(card.slot, card.name:GetText(), "Click to choose the blessing this class should get from you.")
        cards[i] = card
    end
    local function Place()
        local w = (b:GetWidth() > 0 and b:GetWidth() or 640) - 32
        local cw = math.floor((w - 2 * 10) / 3)
        for i, card in ipairs(cards) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            card:ClearAllPoints()
            card:SetWidth(cw)
            card:SetPoint("TOPLEFT", 16 + col * (cw + 10), -top - row * 60)
            local pick = DB.remind and DB.remind.byClass[CLASSES[i]] or ""
            local info = pick ~= "" and Kit.SpellByName(pick)
            card.pick:SetText(pick ~= "" and pick:gsub("^Blessing of ", "") or "Any")
            card.icon:SetShown(info and true or false)
            if info then card.icon:SetTexture(info.iconID) end
            card.any:SetShown(not info)
            if pick ~= "" and not info then card.any:SetText("?") else card.any:SetText("Any") end
        end
    end
    b:SetScript("OnSizeChanged", Place)
    remindPage:OnRefresh(Place)
end

-- Spell ranks
rankPage:Preview(84, function(stage)
    if not stage.button then
        local f = CreateFrame("Frame", nil, stage)
        f:SetSize(40, 40)
        f:SetPoint("LEFT", 16, -4)
        f.icon = Kit.Icon(f, 40)
        f.icon:SetAllPoints()
        f.arrow = f:CreateTexture(nil, "OVERLAY")
        f.arrow:SetSize(14, 14)
        f.arrow:SetPoint("TOPLEFT", 1, -1)
        pcall(f.arrow.SetAtlas, f.arrow, "bags-greenarrow")
        f.rank = f:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        f.rank:SetPoint("BOTTOMLEFT", 2, 2)
        f.rank:SetTextColor(1, 0.5, 0.1)
        f.rank:SetText("R1")
        f.text = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("LEFT", f, "RIGHT", 12, 0)
        stage.button = f
    end
    local f = stage.button
    local example
    for _, e in ipairs(Kit.Spellbook()) do if e.rank and e.rank > 1 then example = e; break end end
    f.icon:SetTexture(example and example.icon or 135920)
    local name = example and example.name or "Holy Light"
    f.text:SetText(DB.ranks.auto and (name .. ": an old rank on your bars is swapped for the newest, out of combat")
        or (name .. " on your bars is Rank 1, you know Rank " .. (example and example.rank or 3)))
    f:SetAlpha(DB.ranks.enabled and 1 or 0.35)
end)
rankPage:Card(nil, 70, function(card, p)
    p:CheckAt(card, 8, -6, "Mark old ranks", Opt("ranks", "enabled"), SetOpt("ranks", "enabled"),
        "A green arrow on action buttons holding a lower rank than one you know, and a line in chat.")
    p:CheckAt(card, 8, -36, "Update to the newest rank by itself", Opt("ranks", "auto"), SetOpt("ranks", "auto"),
        "Swap old ranks on your action bars for the newest one you know, as soon as you're out of combat.")
end)
rankPage:Icons(List("ranks", "keep"), { title = "Keep on their rank", sources = { "spells" }, resolve = ResolveSpell,
    later = "Not learned yet",
    onChange = function() ns.ConfigChanged("ranks", "keep") end,
    subtitle = "Spells you keep low on purpose, e.g. a low rank for less mana" })

-- Profiles contain only validated configurable fields; positions and storage stay with this character.
function ns.SnapshotProfile()
    return ns.ProfileValidation.Snapshot(DB, PlayerClass())
end
function ns.ApplyProfile(data)
    local candidate, err = ns.ProfileValidation.Validate(data)
    if not candidate then return nil, err end
    local changes = ns.Configuration.Changes(DB, candidate)
    changes.ranks = { all = true } -- profiles also reconcile markers on action buttons created since the last check
    ns.ProfileValidation.Commit(DB, candidate)
    State.InvalidateSpells(); State.InvalidateBags(); State.InvalidateAuras()
    ns.Configuration.Apply(changes, { profile = true })
    return true
end
-- Keep the original profile format for explicit imports; saved variables remain separate.
profilePage:Profiles({ tag = "FCT1", store = function() return ACCOUNT.profiles end, snapshot = ns.SnapshotProfile, apply = ns.ApplyProfile,
    decode = ns.DecodeProfile,
    badge = function(data)
        local class = type(data) == "table" and data._class
        if not ns.ProfileValidation.IsClass(class) then return nil end
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
        local mine = class == PlayerClass()
        return { atlas = "classicon-" .. class:lower(), text = mine and name or (name .. " profile  Â·  another class") }
    end })

main.category = Kit.Register(main)
for _, key in ipairs({ "cd", "buff", "remind", "ranks", "profiles" }) do subs[key].category = Kit.Register(subs[key], main.category) end
local page = main


function ToggleConfig() Kit.Open(page) end
function EllesmereUICooldownTracker_OpenSettings() Kit.Open(page) end

-- The optional Ellesmere UI adapter uses these callbacks instead of owning saved data or aura timers.
function ns.SaveTrackerPosition(key, x, y)
    local cfg = DB[key]
    if not cfg or type(x) ~= "number" or type(y) ~= "number" then return end
    cfg.x, cfg.y = x, y
    ns.Configuration.Apply({ [key] = { x = true, y = true } }, { position = true })
    ns.Kit.SaveEditModePosition(key)
end
function ns.TrackerConfig(key) return DB[key] end
function ns.TrackerRoot(key)
    if key == "cd" then return cdRoot elseif key == "buff" then return buffRoot elseif key == "remind" then return remindRoot end
end
function ns.ApplyTrackerConfiguration(key, effects, options)
    local root, cfg = ns.TrackerRoot(key), DB[key]
    if not root or not cfg then return end
    if effects.position then
        root:ClearAllPoints(); root:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    end
    if effects.visibility then
        root:EnableMouse(not cfg.locked); root.bg:SetShown(not cfg.locked)
    end
    if effects.position and not (effects.data or effects.layout or effects.appearance or effects.visibility) then return end
    if effects.data then
        if key == "cd" then
            cdResolutionDirty = true; wipe(previewCd)
            for _, b in ipairs(cdRoot.items) do ReleaseCd(b) end
        elseif key == "buff" then buffDataDirty = true; wipe(previewBuff); wipe(hiddenCasts)
        elseif key == "remind" then wipe(learnedEntries) end
    end
    if key == "cd" then
        if effects.layout or effects.visibility then cdLayoutDirty = true end
        if effects.appearance then cdAppearanceDirty = true end
        UpdateCd(not effects.data)
    elseif key == "buff" then
        if effects.layout or effects.visibility or effects.data then buffLayoutDirty = true end
        if effects.appearance then buffAppearanceDirty = true end
        UpdateBuffs(nil, not effects.data)
    elseif key == "remind" then UpdateRemind(not (effects.data or effects.visibility)) end
end
function ns.RefreshConfigurationPages(changes, options)
    if options.position then return end -- no settings page or preview displays screen coordinates
    for key, p in pairs(ns.settingsPages) do
        if (changes[key] or key == "main" or options.profile) and p.frame:IsShown() then p:Refresh() end
    end
    if ns.RefreshTrackerSettings then
        if options.profile then ns.RefreshTrackerSettings() else ns.RefreshTrackerSettings(changes, options) end
    end
end
function ns.RefreshTrackers()
    ns.Configuration.Apply({ cd = { all = true }, buff = { all = true }, remind = { all = true } })
end
function ns.BuffConfig() return DB.buff end
function ns.BuffRoot() return buffRoot end
function ns.RefreshBuffs() ns.ConfigChanged("buff", "all") end
ns.PreviewBuff = PreviewBuff
ns.PreviewCd = PreviewCd
ns.PreviewRemind = PreviewRemind

local function SlashSetting(section, field, text)
    local data = ns.SnapshotProfile()
    data[section][field] = tonumber(text)
    local candidate, err = ns.ProfileValidation.Validate(data)
    if candidate then ns.SetConfig(section, field, candidate[section][field])
    else print("EllesmereUICooldownTracker: " .. err) end
end
SLASH_EUICT1 = "/euict"
SLASH_EUICT2 = "/ellesmerecooldowns"
SlashCmdList.EUICT = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if cmd == "reset" then wipe(DB); ReloadUI()
    elseif cmd == "ranks" then ns.Ranks.Report()
    elseif cmd == "cdsize" and tonumber(arg) then SlashSetting("cd", "size", arg)
    elseif cmd == "barwidth" and tonumber(arg) then SlashSetting("buff", "width", arg)
    elseif cmd == "barheight" and tonumber(arg) then SlashSetting("buff", "height", arg)
    elseif cmd == "buff" and ns.OpenBuffSettings then ns.OpenBuffSettings()
    elseif (cmd == "cd" or cmd == "remind" or cmd == "reminders") and ns.OpenTrackerSettings then
        ns.OpenTrackerSettings(cmd == "cd" and "cd" or "remind")
    else ToggleConfig() end
end
