-- Ellesmere tracker pages; callbacks always read current settings.
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI.RegisterPlugin) then return end
local Appearance = ns.EllesmereAppearance
local SourceBar, Color = Appearance.SourceBar, Appearance.Color
local textureNames, textureOrder = Appearance.textureNames, Appearance.textureOrder
local TrackingEditor = ns.EllesmereTrackingEditor
local EUI_CHANGE = { source = "ellesmere" }

-- Common widgets read the current character table on every access, including after loading a profile.
local function Controls(tracker, parent, y)
    local W, ui = EUI.Widgets, { y = y }
    function ui:section(text)
        local _, h = W:SectionHeader(parent, text, self.y)
        self.y = self.y - h
    end
    function ui:button(text, fn)
        local _, h = W:Button(parent, text, self.y, fn)
        self.y = self.y - h
    end
    function ui:get(key) return function() return ns.TrackerConfig(tracker)[key] end end
    function ui:set(key) return function(value) ns.SetConfig(tracker, key, value, EUI_CHANGE) end end
    function ui:toggle(text, key)
        local _, h = W:Toggle(parent, text, self.y, self:get(key), self:set(key))
        self.y = self.y - h
    end
    function ui:slider(text, key, low, high)
        local _, h = W:Slider(parent, text, self.y, low, high, 1, self:get(key), self:set(key))
        self.y = self.y - h
    end
    function ui:dropdown(text, key, values, order, tooltip)
        local _, h = W:Dropdown(parent, text, self.y, values, self:get(key), self:set(key), order, tooltip)
        self.y = self.y - h
    end
    function ui:swatch(text, key)
        local _, h = W:ColorPicker(parent, text, self.y, function() return Color(ns.TrackerConfig(tracker)[key]) end,
            function(r, g, b, a) ns.SetConfig(tracker, key, { r = r, g = g, b = b, a = a }, EUI_CHANGE) end, true)
        self.y = self.y - h
    end
    function ui:move()
        self:toggle("Lock position", "locked")
        self:button("Move in Unlock Mode", function() if EUI.OpenUnlockMode then EUI:OpenUnlockMode() end end)
    end
    function ui:inherit(tooltip)
        self:section("ACTION BAR APPEARANCE")
        local values, order = { none = "Custom" }, { "none" }
        for i = 1, 10 do
            local key = i == 1 and "MainBar" or "Bar" .. i
            values[key], order[#order + 1] = "Action Bar " .. i, key
        end
        self:dropdown("Inherit appearance", "inheritBar", values, order, tooltip)
    end
    function ui:direction()
        self:dropdown("Orientation", "orientation", { horizontal = "Horizontal", vertical = "Vertical" },
            { "horizontal", "vertical" })
        if ns.TrackerConfig(tracker).orientation == "vertical" then
            self:dropdown("Grow direction", "growth", { up = "Up", down = "Down" }, { "up", "down" })
        else
            self:dropdown("Grow direction", "growth", { right = "Right", left = "Left" }, { "right", "left" })
        end
    end
    function ui:appearance(timer)
        self:inherit("Follow the selected Ellesmere Action Bar's fonts, text colors and icon borders. Tracker layout stays independently configurable.")
        if not SourceBar(tracker) then
            self:section("BORDER AND TEXT")
            self:toggle("Show icon border", "borderEnabled")
            self:slider("Border thickness", "borderSize", 1, 8)
            self:swatch("Border color", "borderColor")
            self:slider(timer and "Countdown font size (0 = default)" or "Text font size (0 = default)", "fontSize", 0, 32)
            self:swatch("Text color", "textColor")
        end
    end
    return ui
end

local function BuildBuffPage(pageName, parent, y)
    local ui = Controls("buff", parent, y)
    if pageName == "Display" then
        ui:section("VISIBILITY")
        ui:toggle("Enable buff bars", "enabled")
        ui:dropdown("Show bars", "visibility", { always = "Always", combat = "In combat", target = "In combat or with an attackable target" },
            { "always", "combat", "target" })
        ui:move()
        ui:section("LAYOUT")
        ui:direction()
        ui:slider("Bar width", "width", 80, 600)
        ui:slider("Bar height", "height", 12, 64)
        ui:slider("Spacing", "gap", 0, 30)
        ui:toggle("Show spell icon", "showIcon")
        ui:toggle("Show buff name", "showName")
        ui:toggle("Show remaining time", "showTime")
    elseif pageName == "Appearance" then
        ui:inherit("Follow the selected Ellesmere Action Bar's border, fonts, text colors and enabled background. Buff fill and layout use the controls below.")
        ui:section("BUFF FILL")
        ui:dropdown("Bar texture", "texture", textureNames, textureOrder)
        ui:swatch("Buff color", "color")
        if not SourceBar() then
            ui:swatch("Background color", "background")
            ui:section("BORDER AND TEXT")
            ui:toggle("Show border", "borderEnabled")
            ui:slider("Border thickness", "borderSize", 1, 8)
            ui:swatch("Border color", "borderColor")
            ui:slider("Buff name font size", "fontSize", 8, 32)
            ui:slider("Timer font size", "timeFontSize", 8, 32)
            ui:swatch("Text color", "textColor")
        end
    else
        ui:section("TRACKED BUFFS — NAMES ALSO MATCH PREFIXES")
        ui.y = TrackingEditor(parent, ui.y, "buff", "spells", {
            inputLabel = "Buff name or prefix", addLabel = "Add buff",
            emptyText = "No tracked buffs. Add a buff name or prefix below.",
            hint = "Drag a row to reorder. Bars follow this order.",
            tooltip = "Matches any buff starting with this name.",
        })
    end
    return math.abs(ui.y)
end

local function Tracking(ui, tracker, parent, field, title, groups)
    ui:section(title)
    ui.y = TrackingEditor(parent, ui.y, tracker, field, {
        groups = groups, addLabel = "Add entry",
        inputLabel = groups and "Buffs (separate alternatives with /)" or "Spell or item name",
        emptyText = groups and "No tracked buffs. Add a buff or group of alternatives below."
            or "Nothing tracked. Add a spell or item name below.",
        tooltip = groups and "Any alternative separated by / satisfies this reminder."
            or "Tracks a spell cooldown or an item; item names also match partial names.",
    })
end

local function BuildCooldownPage(pageName, parent, y)
    local ui = Controls("cd", parent, y)
    if pageName == "Display" then
        ui:section("VISIBILITY")
        ui:toggle("Enable cooldown bar", "enabled")
        ui:dropdown("Show bars", "visibility", { always = "Always", combat = "In combat", target = "In combat or with an attackable target" },
            { "always", "combat", "target" })
        ui:move()
        ui:section("LAYOUT")
        ui:direction()
        ui:slider("Icon size", "size", 16, 80)
        ui:slider("Spacing", "gap", 0, 30)
        ui:toggle("Countdown numbers", "numbers")
        ui:toggle("Dim spells out of range", "rangeDim")
        ui:toggle("Glow when ready in combat", "readyGlow")
        ui:section("READY GLOW STYLE FOLLOWS ACTION BARS > BAR ANIMATIONS")
    elseif pageName == "Appearance" then
        ui:appearance(true)
    else
        Tracking(ui, "cd", parent, "spells", "SPELLS AND ITEMS — ITEM NAMES ALSO MATCH PARTIAL NAMES", false)
    end
    return math.abs(ui.y)
end
local function BuildRemindersPage(pageName, parent, y)
    local ui = Controls("remind", parent, y)
    if pageName == "Display" then
        ui:section("OUT OF COMBAT — MISSING BUFFS")
        ui:toggle("Enable reminders", "enabled")
        ui:toggle("Party members", "party")
        ui:toggle("Friendly target", "target")
        ui:move()
        ui:section("LAYOUT")
        ui:slider("Icon size", "size", 12, 64)
        ui:slider("Spacing", "gap", 0, 30)
    elseif pageName == "Appearance" then
        ui:appearance(false)
    elseif pageName == "Your Buffs" then
        Tracking(ui, "remind", parent, "self", "BUFFS YOU SHOULD HAVE — ANY ALTERNATIVE SATISFIES A REMINDER", true)
    elseif pageName == "Ally Buffs" then
        Tracking(ui, "remind", parent, "ally", "BUFFS YOU GIVE OTHERS — ONLY BUFFS YOU CAST COUNT", true)
    else
        ui:section("BLESSING EACH CLASS GETS FROM YOU")
        local values, order = { [""] = "Any" }, { "" }
        for name in ns.BLESSINGS:gmatch("[^/]+") do
            name = name:match("^%s*(.-)%s*$")
            values[name], order[#order + 1] = name, name
        end
        for _, class in ipairs(ns.BLESSING_CLASSES) do
            local _, h = EUI.Widgets:Dropdown(parent, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class,
                ui.y, values, function() return ns.TrackerConfig("remind").byClass[class] or "" end,
                function(v)
                    ns.TrackerConfig("remind").byClass[class] = v
                    ns.ConfigChanged("remind", "byClass", EUI_CHANGE)
                end, order)
            ui.y = ui.y - h
        end
    end
    return math.abs(ui.y)
end

ns.EllesmerePages = { buff = BuildBuffPage, cd = BuildCooldownPage, remind = BuildRemindersPage }
