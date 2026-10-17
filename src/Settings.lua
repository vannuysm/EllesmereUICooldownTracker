-- Blizzard settings pages; all edits pass through Configuration.lua.
local _, ns = ...
local DB, Kit = ns.Database.character, ns.Kit
local Configuration, Database, Profiles = ns.Configuration, ns.Database, ns.Profiles
local Validation, Defaults = ns.ProfileValidation, ns.Defaults
local Growth = ns.TrackerFrames.Growth
local Preview = ns.TrackerPreview
local ResolveCd, ResolveBuff, ResolveSpell = Preview.ResolveCd, Preview.ResolveBuff, Preview.ResolveSpell
local Label = ns.Trackers.remind.Label
local SettingsUI = {}
ns.SettingsUI = SettingsUI

local function Opt(tracker, key) return function() return DB[tracker] and DB[tracker][key] end end
local function SetOpt(tracker, key) return function(value) Configuration.Set(tracker, key, value) end end
-- Slider bounds come from the profile schema, so every editor accepts the same values.
local function SliderAt(page, card, x, y, label, tracker, key, step, width)
    local low, high = Validation.Range(tracker, key)
    return page:SliderAt(card, x, y, label, low, high, step, Opt(tracker, key), SetOpt(tracker, key), width)
end

local VISIBILITY = { { "always", "Always" }, { "combat", "In combat" }, { "target", "In combat or with an attackable target" } }
local function LayoutControls(page, tracker, items)
    page:Section("Layout")
    page:Dropdown("Orientation", { { "horizontal", "Horizontal" }, { "vertical", "Vertical" } }, Opt(tracker, "orientation"),
        SetOpt(tracker, "orientation"), "Arrange " .. items .. " in a horizontal row or a vertical column.")
    page:Dropdown("Grow direction", function()
        if DB[tracker] and DB[tracker].orientation == "vertical" then return { { "up", "Up" }, { "down", "Down" } } end
        return { { "right", "Right" }, { "left", "Left" } }
    end, function() return Growth(DB[tracker] or {}) end, SetOpt(tracker, "growth"),
        "Right starts at the left edge; Left starts at the right edge. Up starts at the bottom; Down starts at the top.")
end

-- Pages
local main = Kit.NewPage("EllesmereUICooldownTracker")
local cdPage = Kit.NewPage("Cooldowns")
local buffPage = Kit.NewPage("Buff bars")
local remindPage = Kit.NewPage("Reminders")
local rankPage = Kit.NewPage("Spell ranks")
local profilePage = Kit.NewPage("Profiles")
local subs = { cd = cdPage, buff = buffPage, remind = remindPage, ranks = rankPage, profiles = profilePage }
local pages = { main = main, cd = cdPage, buff = buffPage, remind = remindPage, ranks = rankPage, profiles = profilePage }
SettingsUI.pages = pages

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
            local c = page:CheckAt(card, 0, 0, "Show", Opt(key, "enabled"), SetOpt(key, "enabled"))
            c:ClearAllPoints()
            c:SetPoint("RIGHT", open, "LEFT", -70, 0)
        end
    end)
end
main:Section("Other")
main:Button("Reset all settings", RESET or "Reset", function() Database.Reset(); ReloadUI() end, "Back to defaults. Reloads the UI.")

-- Cooldowns
cdPage:Text("Ready glows follow EllesmereUI Action Bars > Bar Animations > Custom Proc Glow and appear only in combat.", "GameFontHighlightSmall")
local cdPreview = cdPage:Preview(90, Preview.Cd, { modes = true })
cdPage:OnRefresh(function()
    cdPreview:GetParent():SetHeight(DB.cd and DB.cd.orientation == "vertical" and 240 or 90)
end)
cdPage:Card("Look", 98, function(card, p)
    p:CheckAt(card, 8, -28, "Show", Opt("cd", "enabled"), SetOpt("cd", "enabled"), "Turn the cooldown icons on or off.")
    p:CheckAt(card, 120, -28, "Countdown numbers", Opt("cd", "numbers"), SetOpt("cd", "numbers"), "Draw the remaining time on each icon.")
    p:CheckAt(card, 320, -28, "Locked", Opt("cd", "locked"), SetOpt("cd", "locked"), "Unlock to drag the cooldown tracker. A green box shows its area.")
    SliderAt(p, card, 14, -64, "Size", "cd", "size", 1, 140)
    SliderAt(p, card, 320, -64, "Spacing", "cd", "gap", 1, 120)
end)
cdPage:Dropdown("Show bars", VISIBILITY, Opt("cd", "visibility"), SetOpt("cd", "visibility"),
    "Choose when the cooldown icons are visible. Unlocking the tracker keeps it visible for positioning.")
cdPage:Check("Dim spells out of range", Opt("cd", "rangeDim"), SetOpt("cd", "rangeDim"),
    "Darken a spell's icon while your target is out of its range.")
cdPage:Check("Glow when ready in combat", Opt("cd", "readyGlow"), SetOpt("cd", "readyGlow"),
    "Outline a spell's icon in combat once its cooldown is over.")
LayoutControls(cdPage, "cd", "cooldown icons")
cdPage:Icons(Opt("cd", "spells"), { title = "Tracked", sources = { "spells", "items" }, resolve = ResolveCd, onChange = function() Configuration.Changed("cd", "spells") end,
    later = "Not learned yet, or not in your bags",
    laterHint = "These join the row by themselves once you learn them or carry one. Part of an item name is enough: \"Healthstone\" covers every healthstone." })

-- Buff bars
buffPage:Preview(40 + 3 * 30, Preview.Buff, { modes = true })
buffPage:Card("Look", 128, function(card, p)
    p:CheckAt(card, 8, -28, "Show", Opt("buff", "enabled"), SetOpt("buff", "enabled"), "Turn the buff bars on or off.")
    p:CheckAt(card, 120, -28, "Locked", Opt("buff", "locked"), SetOpt("buff", "locked"), "Unlock to drag the bars. Inactive bars show dimmed while unlocked.")
    SliderAt(p, card, 14, -64, "Width", "buff", "width", 5, 140)
    SliderAt(p, card, 320, -64, "Height", "buff", "height", 1, 120)
    SliderAt(p, card, 14, -96, "Spacing", "buff", "gap", 1, 140)
end)
buffPage:Dropdown("Show bars", VISIBILITY, Opt("buff", "visibility"), SetOpt("buff", "visibility"),
    "Choose when the buff bars are visible. Unlocking the tracker keeps it visible for positioning.")
buffPage:Check("Show spell icon", Opt("buff", "showIcon"), SetOpt("buff", "showIcon"))
buffPage:Check("Show buff name", Opt("buff", "showName"), SetOpt("buff", "showName"))
buffPage:Check("Show remaining time", Opt("buff", "showTime"), SetOpt("buff", "showTime"))
LayoutControls(buffPage, "buff", "buff bars")
buffPage:Icons(Opt("buff", "spells"), { title = "Tracked buffs", sources = { "spells" }, resolve = ResolveBuff, onChange = function() Configuration.Changed("buff", "spells") end,
    later = "Not learned yet", laterHint = "These get a bar once you learn them.",
    subtitle = "A name matches any buff starting with it: \"Seal of\" covers every seal" })

-- Reminders
local function GroupLabel(names)
    if #names < 2 then return names[1] end
    local learned = {}
    for _, n in ipairs(names) do learned[#learned + 1] = { name = n } end
    return "Any: " .. Label(learned)
end
remindPage:Preview(40 + 2 * 32, Preview.Remind, { modes = true })
remindPage:Card("When", 98, function(card, p)
    p:CheckAt(card, 8, -28, "Show reminders", Opt("remind", "enabled"), SetOpt("remind", "enabled"), "Out of combat, show a reminder when a buff is missing.")
    p:CheckAt(card, 180, -28, "Party members", Opt("remind", "party"), SetOpt("remind", "party"), "Name who in your party is missing your buff, when they're in range.")
    p:CheckAt(card, 350, -28, "Friendly target", Opt("remind", "target"), SetOpt("remind", "target"), "Name the friendly player you target when they're missing your buff.")
    p:CheckAt(card, 8, -60, "Locked", Opt("remind", "locked"), SetOpt("remind", "locked"), "Unlock to drag the reminders. A sample line shows while unlocked.")
    SliderAt(p, card, 186, -64, "Icon size", "remind", "size", 1, 120)
end)
remindPage:IconGroups(Opt("remind", "self"), { title = "Buffs you should have", label = GroupLabel,
    onChange = function() Configuration.Changed("remind", "self") end })
remindPage:IconGroups(Opt("remind", "ally"), { title = "Buffs you give others", subtitle = "Only ones you cast count", label = GroupLabel,
    onChange = function() Configuration.Changed("remind", "ally") end })
remindPage:ClassPicks({
    title = "Blessing each class gets from you",
    subtitle = "Click a blessing to change it. Any: whichever of yours they're missing.",
    tooltip = "Click to choose the blessing this class should get from you.",
    classes = Defaults.BLESSING_CLASSES,
    choices = function()
        local out = { { "", "Any" } }
        for _, name in ipairs(Kit.Split(Defaults.BLESSINGS)) do out[#out + 1] = { name, name } end
        return out
    end,
    get = function(class) return DB.remind and DB.remind.byClass[class] end,
    set = function(class, value)
        DB.remind.byClass[class] = value
        Configuration.Changed("remind", "byClass")
    end,
    short = function(value) return (value:gsub("^Blessing of ", "")) end,
})

-- Spell ranks
-- The preview redraws ten times a second; scan the spellbook again only after it changes.
local rankExample, rankExampleRevision
local function RankExample()
    if rankExampleRevision ~= ns.Collection.spellRevision then
        rankExample, rankExampleRevision = nil, ns.Collection.spellRevision
        for _, e in ipairs(Kit.Spellbook()) do if e.rank and e.rank > 1 then rankExample = e; break end end
    end
    return rankExample
end
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
    local example = RankExample()
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
rankPage:Icons(Opt("ranks", "keep"), { title = "Keep on their rank", sources = { "spells" }, resolve = ResolveSpell,
    later = "Not learned yet",
    onChange = function() Configuration.Changed("ranks", "keep") end,
    subtitle = "Spells you keep low on purpose, e.g. a low rank for less mana" })

-- Profiles
Profiles.OnLibraryChanged(function() if profilePage.frame:IsShown() then profilePage:Refresh() end end)
profilePage:Profiles({ tag = "FCT1", store = Database.ProfileStore, snapshot = Profiles.Snapshot, apply = Profiles.Apply,
    import = Profiles.Import,
    onStoreChange = Profiles.LibraryChanged,
    onSave = Profiles.Associate,
    badge = function(data)
        local class = type(data) == "table" and data._class
        if not Validation.IsClass(class) then return nil end
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
        local mine = class == Database.PlayerClass()
        return { atlas = "classicon-" .. class:lower(), text = mine and name or (name .. " profile  ·  another class") }
    end })

main.category = Kit.Register(main)
for _, key in ipairs({ "cd", "buff", "remind", "ranks", "profiles" }) do subs[key].category = Kit.Register(subs[key], main.category) end

-- Configuration listener for the pages above.
function SettingsUI.Refresh(changes, options)
    if options.position then return end -- no settings page or preview displays screen coordinates
    for key, p in pairs(pages) do
        if (changes[key] or key == "main" or options.profile) and p.frame:IsShown() then p:Refresh() end
    end
end

-- Opens a tracker's or the profiles' settings in EllesmereUI when it is installed; no key opens the main page here.
function SettingsUI.Open(key)
    if key and ns.Ellesmere then return ns.Ellesmere.Open(key) end
    Kit.Open(key == "profiles" and profilePage or main)
end
