-- Optional Ellesmere plugin registration, page refreshes and preview headers.
local ADDON_NAME, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI.RegisterPlugin) then return end
local PLUGIN = ADDON_NAME
local Preview, ProfileUI = ns.TrackerPreview, ns.ProfileUI

local MODULES = { buff = "BuffBars", cd = "CooldownBar", remind = "Reminders", profiles = "Profiles" }
local function Rebuild(module, refresh)
    local key = EUI.GetPluginModuleKey(PLUGIN, MODULES[module])
    EUI:InvalidateModulePageCache(key)
    if refresh ~= false and EUI:GetActiveModule() == key then EUI:RefreshPage(true) end
end
local function RefreshProfiles(refresh)
    ProfileUI.UpdateHeader()
    Rebuild("profiles", refresh)
end
local function RefreshTrackers(changes, options)
    for _, tracker in ipairs({ "buff", "cd", "remind" }) do
        if not changes or changes[tracker] then
            local fields = changes and changes[tracker]
            local structural = fields and (fields.spells or fields.self or fields.ally or fields.byClass
                or fields.orientation or fields.inheritBar or fields.all)
            -- Keep an active slider/color picker alive while its own callback is running.
            local refresh = not (options and options.source == "ellesmere") or structural
            Rebuild(tracker, refresh and true or false)
        end
    end
end
ns.Configuration.Subscribe(function(changes, options)
    if options.position then return end -- no page or preview displays screen coordinates
    if options.profile then RefreshTrackers() else RefreshTrackers(changes, options) end
    RefreshProfiles()
end)
ns.Profiles.OnLibraryChanged(RefreshProfiles)

local function Header(tracker)
    return function(frame)
        if frame.euictProfileHeader then frame.euictProfileHeader:Hide() end
        frame.euictPreviews = frame.euictPreviews or {}
        local preview = tracker == "cd" and Preview.Cd or (tracker == "remind" and Preview.Remind or Preview.Buff)
        local mode = tracker == "remind" and "normal" or "combat"
        local height = tracker == "cd" and 240 or 120
        local stage = frame.euictPreviews[tracker]
        if not stage then
            stage = CreateFrame("Frame", nil, frame)
            stage:SetPoint("TOPLEFT", 12, -8)
            stage:SetPoint("TOPRIGHT", -12, -8)
            stage:SetHeight(height)
            stage.note = stage:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            stage.note:SetPoint("CENTER")
            local elapsed = 0
            stage:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed >= 0.1 then
                    elapsed = 0
                    preview(stage, mode)
                end
            end)
            frame.euictPreviews[tracker] = stage
        end
        for key, other in pairs(frame.euictPreviews) do other:SetShown(key == tracker) end
        preview(stage, mode)
        return height + 16
    end
end
local headers = { buff = Header("buff"), cd = Header("cd"), remind = Header("remind") }

local registered = EUI.RegisterPlugin(PLUGIN, {
    label = "Cooldown Tracker",
    modules = { {
        key = "BuffBars", title = "Buff Bars",
        description = "Player buff timers. Settings are saved with EllesmereUICooldownTracker profiles.",
        pages = { "Display", "Appearance", "Tracked Buffs" }, buildPage = ns.EllesmerePages.buff,
        getHeaderBuilder = function() return headers.buff end, searchPrebuild = false,
    }, {
        key = "CooldownBar", title = "Cooldown Bar",
        description = "Spell and item cooldowns. Ready glows follow Ellesmere Action Bars settings.",
        pages = { "Display", "Appearance", "Tracked" }, buildPage = ns.EllesmerePages.cd,
        getHeaderBuilder = function() return headers.cd end, searchPrebuild = false,
    }, {
        key = "Reminders", title = "Reminders",
        description = "Missing buff reminders for you, your party and a friendly target. Saved with EUICT profiles.",
        pages = { "Display", "Appearance", "Your Buffs", "Ally Buffs", "Class Blessings" }, buildPage = ns.EllesmerePages.remind,
        getHeaderBuilder = function() return headers.remind end, searchPrebuild = false,
    }, {
        key = "Profiles", title = "Manage Profiles",
        description = "Save, load, rename and delete account profiles, or import and export your setups.",
        pages = { "Profiles", "Import / Export" }, buildPage = ProfileUI.BuildPage, searchPrebuild = false,
        getHeaderBuilder = function() return ProfileUI.BuildHeader end,
        onModuleLeave = ProfileUI.Close,
    } },
})
if registered then
    -- key: "cd", "buff", "remind" or "profiles"; tab: an optional profiles page.
    local function Open(key, tab)
        if key == "profiles" then return EUI.OpenPlugin(PLUGIN, "Profiles", type(tab) == "string" and tab or "Profiles") end
        return EUI.OpenPlugin(PLUGIN, MODULES[key], "Display")
    end
    ns.Ellesmere = { Open = Open }
    local pages = ns.SettingsUI.pages
    pages.buff:Button("Ellesmere UI", "Open Buff Bars", function() Open("buff") end)
    pages.cd:Button("Ellesmere UI", "Open Cooldown Bar", function() Open("cd") end)
    pages.remind:Button("Ellesmere UI", "Open Reminders", function() Open("remind") end)
    pages.profiles:Button("Ellesmere UI", "Open Manage Profiles", function() Open("profiles") end)
end
