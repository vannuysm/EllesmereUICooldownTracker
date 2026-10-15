-- Blizzard settings pages; all edits pass through Configuration.lua.
local _, ns = ...
local DB, Kit = ns.Database.character, ns.Kit
local QUESTION = 134400
local CdGrowth = ns.TrackerFrames.Growth
local Preview = ns.TrackerPreview
local ResolveCd, ResolveBuff, ResolveSpell = Preview.ResolveCd, Preview.ResolveBuff, Preview.ResolveSpell
local PreviewCd, PreviewBuff, PreviewRemind = ns.PreviewCd, ns.PreviewBuff, ns.PreviewRemind
local Label = ns.Trackers.remind.Label

local function SetLocked(key, value) ns.SetConfig(key, "locked", value) end
local function Opt(tracker, key) return function() return DB[tracker] and DB[tracker][key] end end
local function SetOpt(tracker, key) return function(value) ns.SetConfig(tracker, key, value) end end
local List = Opt

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
local CLASSES = ns.BLESSING_CLASSES
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

function ns.ProfileLibraryChanged(refresh)
    if profilePage.frame:IsShown() then profilePage:Refresh() end
    if ns.RefreshProfileSettings then ns.RefreshProfileSettings(refresh) end
end
profilePage:Profiles({ tag = "FCT1", store = function() return ns.ProfileStore() end, snapshot = ns.SnapshotProfile, apply = ns.ApplyProfile,
    decode = ns.DecodeProfile,
    onStoreChange = ns.ProfileLibraryChanged,
    onSave = function(name) ns.Profiles.Associate(name) end,
    badge = function(data)
        local class = type(data) == "table" and data._class
        if not ns.ProfileValidation.IsClass(class) then return nil end
        local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
        local mine = class == ns.Database.PlayerClass()
        return { atlas = "classicon-" .. class:lower(), text = mine and name or (name .. " profile  Â·  another class") }
    end })

main.category = Kit.Register(main)
for _, key in ipairs({ "cd", "buff", "remind", "ranks", "profiles" }) do subs[key].category = Kit.Register(subs[key], main.category) end

function ns.RefreshConfigurationPages(changes, options)
    if options.position then return end -- no settings page or preview displays screen coordinates
    for key, p in pairs(ns.settingsPages) do
        if (changes[key] or key == "main" or options.profile) and p.frame:IsShown() then p:Refresh() end
    end
    if ns.RefreshTrackerSettings then
        if options.profile then ns.RefreshTrackerSettings() else ns.RefreshTrackerSettings(changes, options) end
    end
    if ns.RefreshProfileSettings then ns.RefreshProfileSettings() end
end

function ns.OpenSettings() Kit.Open(main) end
