-- Optional, public Ellesmere UI APIs only. Configuration remains in EUICT's character settings/profiles.
local ADDON_NAME, ns = ...
local EUI = EllesmereUI
local PLUGIN = ADDON_NAME
local DEFAULT_TEXTURE = "Interface/TargetingFrame/UI-StatusBar"
local textures, textureNames, textureOrder = {}, { default = "Blizzard" }, { "default" }
if EUI and EUI.BuildBarTextureTables then
    local paths, names, order = EUI.BuildBarTextureTables()
    for _, key in ipairs(order) do
        if paths[key] then
            textures[key], textureNames[key] = paths[key], names[key]
            textureOrder[#textureOrder + 1] = key
        end
    end
end

local function SourceBar(tracker)
    local c = tracker and ns.TrackerConfig(tracker) or ns.BuffConfig()
    if not c or c.inheritBar == "none" or not (EUI and EUI.Lite and EUI.Lite.GetAddon) then return end
    local addon = EUI.Lite.GetAddon("EllesmereUIActionBars", true)
    local profile = addon and addon.db and addon.db.profile
    return profile and profile.bars and profile.bars[c.inheritBar]
end
local function Color(c) return c.r, c.g, c.b, c.a or 1 end
local function Border(b)
    if b.buffBorder then return b.buffBorder end
    local f = CreateFrame("Frame", nil, b)
    f:SetAllPoints(b)
    f:SetFrameLevel(b.bar:GetFrameLevel() + 1)
    b.buffBorder = f
    return f
end

function ns.ApplyBuffAppearance(b, inverted)
    local c = ns.BuffConfig()
    local source = SourceBar()
    local texture = textures[c.texture] or DEFAULT_TEXTURE
    local fill, bg = c.color, c.background
    if source and source.bgEnabled and source.bgColor then bg = source.bgColor end
    b.bar:SetStatusBarTexture(texture)
    if inverted then
        b.bar:SetStatusBarColor(bg.r, bg.g, bg.b, math.max(bg.a or 1, 0.75))
        b.bar.bg:SetTexture(texture)
        b.bar.bg:SetVertexColor(Color(fill))
    else
        b.bar:SetStatusBarColor(Color(fill))
        b.bar.bg:SetColorTexture(Color(bg))
        b.bar.bg:SetVertexColor(1, 1, 1, 1)
    end
    b.icon:SetShown(c.showIcon)
    b.cd:SetShown(c.showIcon)
    b.bar:ClearAllPoints()
    if c.showIcon then b.bar:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 2, 0)
    else b.bar:SetPoint("TOPLEFT", b, "TOPLEFT") end
    b.bar:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT")
    b.name:SetShown(c.showName)
    b.time:SetShown(c.showTime)
    b.name:ClearAllPoints()
    b.name:SetPoint("LEFT", b.bar, "LEFT", 4, 0)
    if c.showTime then b.name:SetPoint("RIGHT", b.time, "LEFT", -4, 0)
    else b.name:SetPoint("RIGHT", b.bar, "RIGHT", -4, 0) end
    b.name:SetJustifyH("LEFT")
    if not b.buffOriginalFont then
        local font, size, flags = b.name:GetFont()
        local timeFont, timeSize, timeFlags = b.time:GetFont()
        b.buffOriginalFont = { font, size, flags, timeFont, timeSize, timeFlags }
    end
    if source and EUI.ApplyModuleFont then
        EUI.ApplyModuleFont(b.name, nil, source.macroFontSize or c.fontSize, "actionBars")
        EUI.ApplyModuleFont(b.time, nil, source.cooldownFontSize or c.timeFontSize, "actionBars")
    else
        local f = b.buffOriginalFont
        b.name:SetFont(f[1], c.fontSize, f[3])
        b.time:SetFont(f[4], c.timeFontSize, f[6])
        b.name:SetShadowColor(0, 0, 0, 1); b.name:SetShadowOffset(1, -1)
        b.time:SetShadowColor(0, 0, 0, 1); b.time:SetShadowOffset(1, -1)
    end
    b.name:SetTextColor(Color(source and source.macroFontColor or c.textColor))
    b.time:SetTextColor(Color(source and source.cooldownTextColor or c.textColor))
    local enabled = c.borderEnabled
    if source then enabled = source.borderEnabled end
    if enabled and EUI and EUI.ApplyBorderStyle then
        local color = source and source.borderColor or c.borderColor
        if source and source.borderClassColor then
            local _, class = UnitClass("player")
            color = EUI.GetClassColor and EUI.GetClassColor(class) or RAID_CLASS_COLORS[class] or color
        end
        local size, exact = c.borderSize
        if source then
            size = ({ none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 })[source.borderThickness or "thin"] or 1
            if EUI.BorderPx then exact = EUI.BorderPx(source.borderThicknessPx, size, source.borderTexture) end
        end
        EUI.ApplyBorderStyle(Border(b), size, color.r, color.g, color.b, color.a or 1,
            source and source.borderTexture or "solid", source and source.borderTextureOffset,
            source and source.borderTextureOffsetY, source and source.borderTextureShiftX,
            source and source.borderTextureShiftY, "actionbars", source and source.borderThickness,
            nil, exact)
    elseif b.buffBorder then b.buffBorder:Hide() end
end

-- Cooldown countdowns and reminder labels share the same optional Action Bar font/border source.
local function StyleText(fs, c, source, timer)
    if not fs then return end
    if not fs.euictOriginalFont then
        local path, size, flags = fs:GetFont()
        if not path then return end -- a cooldown countdown can initialize its font later
        fs.euictOriginalFont = { path, size, flags, shadow = { fs:GetShadowColor() }, offset = { fs:GetShadowOffset() } }
    end
    local original = fs.euictOriginalFont
    local size = c.fontSize > 0 and c.fontSize or original[2]
    if source and EUI.ApplyModuleFont then
        size = (timer and source.cooldownFontSize or source.macroFontSize) or size
        EUI.ApplyModuleFont(fs, nil, size, "actionBars")
    else
        fs:SetFont(original[1], size, original[3])
        if original.shadow[1] then fs:SetShadowColor(unpack(original.shadow)) end
        if original.offset[1] then fs:SetShadowOffset(unpack(original.offset)) end
    end
    local color = source and (timer and source.cooldownTextColor or source.macroFontColor) or c.textColor
    fs:SetTextColor(Color(color or c.textColor))
end
local function StyleIconBorder(b, c, source, icon)
    local enabled = c.borderEnabled
    if source then enabled = source.borderEnabled end
    if not (enabled and EUI and EUI.ApplyBorderStyle) then
        if b.euictIconBorder then b.euictIconBorder:Hide() end
        return
    end
    if not b.euictIconBorder then
        b.euictIconBorder = CreateFrame("Frame", nil, b)
        b.euictIconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT")
        b.euictIconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
        b.euictIconBorder:SetFrameLevel((b.cd or b):GetFrameLevel() + 1)
    end
    local color, size, exact = c.borderColor, c.borderSize
    if source then
        color = source.borderColor or color
        if source.borderClassColor then
            local _, class = UnitClass("player")
            color = EUI.GetClassColor and EUI.GetClassColor(class) or RAID_CLASS_COLORS[class] or color
        end
        size = ({ none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 })[source.borderThickness or "thin"] or 1
        if EUI.BorderPx then exact = EUI.BorderPx(source.borderThicknessPx, size, source.borderTexture) end
    end
    EUI.ApplyBorderStyle(b.euictIconBorder, size, color.r, color.g, color.b, color.a or 1,
        source and source.borderTexture or "solid", source and source.borderTextureOffset,
        source and source.borderTextureOffsetY, source and source.borderTextureShiftX,
        source and source.borderTextureShiftY, "actionbars", source and source.borderThickness, nil, exact)
end
function ns.ApplyCooldownAppearance(b)
    local c, source = ns.TrackerConfig("cd"), SourceBar("cd")
    local fs = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
    StyleText(fs, c, source, true)
    StyleIconBorder(b, c, source, b.icon)
end
function ns.ApplyReminderAppearance(b)
    local c, source = ns.TrackerConfig("remind"), SourceBar("remind")
    StyleText(b.text, c, source, false)
    StyleIconBorder(b, c, source, b.icon)
end

if not (EUI and EUI.RegisterPlugin) then return end

local MODULES = { buff = "BuffBars", cd = "CooldownBar", remind = "Reminders" }
local function Rebuild(tracker)
    local key = EUI.GetPluginModuleKey(PLUGIN, MODULES[tracker or "buff"])
    EUI:InvalidateModulePageCache(key)
    if EUI:GetActiveModule() == key then EUI:RefreshPage(true) end
end
ns.RefreshBuffSettings = Rebuild
function ns.RefreshTrackerSettings() for _, tracker in ipairs({ "buff", "cd", "remind" }) do Rebuild(tracker) end end
local function Get(key) return function() return ns.BuffConfig()[key] end end
local function Set(key, rebuild)
    return function(value)
        local c = ns.BuffConfig()
        c[key] = value
        if key == "orientation" then
            if value == "vertical" then c.growth = c.growth == "up" and "up" or "down"
            else c.growth = c.growth == "left" and "left" or "right" end
        end
        ns.RefreshBuffs()
        if rebuild then Rebuild() end
    end
end
-- Keep the saved order visible; dragging only commits when released inside the list.
local function OrderedList(parent, y, getList, onChange, options)
    local items = getList()
    local ROW_HEIGHT, HINT_HEIGHT = 40, 24
    local pad = EUI.CONTENT_PAD or 45
    local list = CreateFrame("Frame", nil, parent)
    list:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    list:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
    local height = HINT_HEIGHT + math.max(1, #items) * ROW_HEIGHT + 8
    list:SetHeight(height)
    local hint = EUI.MakeFont(list, 11, nil, 1, 1, 1, 0.6)
    hint:SetPoint("TOPLEFT", 8, -2)
    hint:SetText(options.hint or "Drag a row to reorder. Trackers follow this order.")

    local area = CreateFrame("Frame", nil, list)
    area:SetPoint("TOPLEFT", 0, -HINT_HEIGHT)
    area:SetPoint("TOPRIGHT", 0, -HINT_HEIGHT)
    area:SetHeight(math.max(1, #items) * ROW_HEIGHT)
    if #items == 0 then
        local empty = EUI.MakeFont(area, 13, nil, 1, 1, 1, 0.5)
        empty:SetPoint("LEFT", 8, 0)
        empty:SetText(options.emptyText)
        return height
    end

    local scroll = parent
    while scroll and not scroll:IsObjectType("ScrollFrame") do scroll = scroll:GetParent() end
    local rows, snapshot = {}, {}
    local dragging, slot
    local r, g, b = 0.3, 0.8, 0.6
    if EUI.GetAccentColor then r, g, b = EUI.GetAccentColor() end
    local indicator = CreateFrame("Frame", nil, area)
    indicator:SetHeight(2)
    indicator:SetFrameLevel(area:GetFrameLevel() + 5)
    indicator:EnableMouse(false)
    local line = indicator:CreateTexture(nil, "OVERLAY")
    line:SetAllPoints()
    line:SetColorTexture(r, g, b, 1)
    indicator:Hide()

    local ghost = CreateFrame("Frame", nil, list)
    ghost:SetSize(300, 32)
    ghost:SetFrameLevel(area:GetFrameLevel() + 10)
    ghost:EnableMouse(false)
    local background = ghost:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.08, 0.08, 0.08, 0.95)
    local label = EUI.MakeFont(ghost, 13, nil, 1, 1, 1)
    label:SetPoint("LEFT", 10, 0)
    label:SetPoint("RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    ghost:Hide()

    local function Current()
        if getList() ~= items or #items ~= #snapshot then return false end
        for i, name in ipairs(snapshot) do if items[i] ~= name then return false end end
        return true
    end
    local function Cancel()
        if dragging then rows[dragging]:SetAlpha(1) end
        dragging, slot = nil, nil
        list:SetScript("OnUpdate", nil)
        indicator:Hide()
        ghost:Hide()
    end
    local function UpdateDrag()
        slot = nil
        indicator:Hide()
        if not dragging or not Current() then Cancel(); return end
        local x, cursorY = GetCursorPosition()
        local scale = area:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 16, cursorY / scale + 16)
        if not area:IsMouseOver() or (scroll and not scroll:IsMouseOver()) then return end
        local top = area:GetTop()
        if not top then return end
        slot = math.min(#items + 1, math.max(1, math.floor((top - cursorY / scale) / ROW_HEIGHT + 0.5) + 1))
        indicator:ClearAllPoints()
        indicator:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -(slot - 1) * ROW_HEIGHT + 2)
        indicator:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -(slot - 1) * ROW_HEIGHT + 2)
        indicator:Show()
    end
    list:SetScript("OnHide", Cancel)
    for i, name in ipairs(items) do
        local index = i
        snapshot[index] = name
        local row = CreateFrame("Button", nil, area)
        rows[index] = row
        row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetHeight(ROW_HEIGHT - 4)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, index % 2 == 0 and 0.2 or 0.1)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(r, g, b, 0.12)
        -- Six dots give the row a recognizable drag grip without a font-specific glyph.
        for dot = 0, 5 do
            local grip = row:CreateTexture(nil, "ARTWORK")
            grip:SetSize(2, 2)
            grip:SetPoint("LEFT", 10 + (dot % 2) * 4, 5 - math.floor(dot / 2) * 5)
            grip:SetColorTexture(1, 1, 1, 0.45)
        end
        local number = EUI.MakeFont(row, 12, nil, 1, 1, 1, 0.5)
        number:SetPoint("LEFT", 26, 0)
        number:SetWidth(32)
        number:SetJustifyH("RIGHT")
        number:SetText(index .. ".")
        local remove = CreateFrame("Button", nil, row)
        remove:SetSize(76, 26)
        remove:SetPoint("RIGHT", -8, 0)
        EUI.MakeStyledButton(remove, "Remove", 12, EUI.RB_COLOURS, function()
            if dragging or not Current() then return end
            GameTooltip_Hide()
            table.remove(items, index)
            onChange()
        end)
        local text = EUI.MakeFont(row, 13, nil, 1, 1, 1)
        text:SetPoint("LEFT", 68, 0)
        text:SetPoint("RIGHT", remove, "LEFT", -12, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        text:SetText(name)
        row:SetScript("OnEnter", function(self)
            if dragging then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 1, 1)
            GameTooltip:AddLine(options.tooltip, 0.7, 0.7, 0.7, true)
            GameTooltip:AddLine("Drag to change its position in the list.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self)
            if not Current() then return end
            Cancel()
            GameTooltip_Hide()
            dragging = index
            self:SetAlpha(0.35)
            ghost:SetWidth(math.min(300, list:GetWidth()))
            label:SetText(name)
            ghost:Show()
            list:SetScript("OnUpdate", UpdateDrag)
            UpdateDrag()
        end)
        row:SetScript("OnDragStop", function()
            UpdateDrag()
            local from, to = dragging, slot
            Cancel()
            if not from or not to then return end
            if to > from then to = to - 1 end
            if to == from then return end
            table.insert(items, to, table.remove(items, from))
            onChange()
        end)
    end
    return height
end

-- Shared tracking editor: ordered rows plus a flexible input and compact add button.
-- Always fetch the current settings table, including after a profile is loaded.
local function TrackingEditor(parent, y, tracker, field, options)
    local function List() return ns.TrackerConfig(tracker)[field] end
    local function Changed()
        if tracker == "buff" then ns.RefreshBuffs() else ns.RefreshTrackers() end
        Rebuild(tracker)
    end
    y = y - OrderedList(parent, y, List, Changed, options)
    local pending = ""
    -- Reserve only the button's measured width and padding; the input stretches.
    local pad, inputHeight = EUI.CONTENT_PAD or 45, 50
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -pad, y)
    row:SetHeight(inputHeight)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.1)
    local label = EUI.MakeFont(row, 14, nil, 1, 1, 1)
    label:SetPoint("LEFT", 20, 0)
    label:SetText(options.inputLabel)
    local input = CreateFrame("EditBox", nil, row)
    input:SetHeight(28)
    input:SetAutoFocus(false)
    input:SetFont(EUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
    input:SetTextColor(1, 1, 1, 0.9)
    input:SetJustifyH("LEFT")
    input:SetTextInsets(10, 10, 0, 0)
    local inputBg = input:CreateTexture(nil, "BACKGROUND")
    inputBg:SetAllPoints()
    inputBg:SetColorTexture(0, 0, 0, 0.5)
    EUI.MakeBorder(input, 1, 1, 1, 0.2, EUI.PanelPP)
    input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEditFocusLost", function(self) pending = self:GetText() end)
    input:SetScript("OnEscapePressed", function(self) self:SetText(pending); self:ClearFocus() end)
    local add = CreateFrame("Button", nil, row)
    add:SetHeight(26)
    add:SetPoint("RIGHT", -8, 0) -- same right edge as the Remove buttons
    local _, _, buttonLabel = EUI.MakeStyledButton(add, options.addLabel, 12, EUI.RB_COLOURS, function()
        local name = input:GetText():match("^%s*(.-)%s*$")
        if options.groups then
            local names = {}
            for part in name:gmatch("[^/]+") do
                part = part:match("^%s*(.-)%s*$")
                if part ~= "" then names[#names + 1] = part end
            end
            name = table.concat(names, " / ")
        end
        if name == "" then return end
        local items = List()
        for _, existing in ipairs(items) do if existing:lower() == name:lower() then return end end
        input:ClearFocus()
        items[#items + 1] = name
        Changed()
    end)
    add:SetWidth(math.ceil(buttonLabel:GetStringWidth()) + 20)
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.05)
    divider:SetWidth(1)
    divider:SetPoint("TOPRIGHT", add, "TOPLEFT", -12, (inputHeight - 26) / 2)
    divider:SetPoint("BOTTOMRIGHT", add, "BOTTOMLEFT", -12, -(inputHeight - 26) / 2)
    input:SetPoint("LEFT", label, "RIGHT", 12, 0)
    input:SetPoint("RIGHT", divider, "LEFT", -12, 0)
    return y - inputHeight
end

local function BuildPage(pageName, parent, y)
    local W = EUI.Widgets
    local function Section(text) local _, h = W:SectionHeader(parent, text, y); y = y - h end
    local function Toggle(text, key) local _, h = W:Toggle(parent, text, y, Get(key), Set(key)); y = y - h end
    local function Slider(text, key, low, high)
        local _, h = W:Slider(parent, text, y, low, high, 1, Get(key), Set(key)); y = y - h
    end
    local function Dropdown(text, key, values, order, rebuild, tooltip)
        local _, h = W:Dropdown(parent, text, y, values, Get(key), Set(key, rebuild), order, tooltip); y = y - h
    end
    local function Swatch(text, key)
        local _, h = W:ColorPicker(parent, text, y, function() return Color(ns.BuffConfig()[key]) end,
            function(r, g, b, a) ns.BuffConfig()[key] = { r = r, g = g, b = b, a = a }; ns.RefreshBuffs() end, true)
        y = y - h
    end
    local function Button(text, fn) local _, h = W:Button(parent, text, y, fn); y = y - h end
    if pageName == "Display" then
        Section("VISIBILITY")
        Toggle("Enable buff bars", "enabled")
        Dropdown("Show bars", "visibility", { always = "Always", combat = "In combat", target = "In combat or with an attackable target" },
            { "always", "combat", "target" })
        Toggle("Lock position", "locked")
        Button("Move in Unlock Mode", function() if EUI.OpenUnlockMode then EUI:OpenUnlockMode() end end)
        Section("LAYOUT")
        Dropdown("Orientation", "orientation", { horizontal = "Horizontal", vertical = "Vertical" }, { "horizontal", "vertical" }, true)
        if ns.BuffConfig().orientation == "vertical" then
            Dropdown("Grow direction", "growth", { up = "Up", down = "Down" }, { "up", "down" })
        else Dropdown("Grow direction", "growth", { right = "Right", left = "Left" }, { "right", "left" }) end
        Slider("Bar width", "width", 80, 600)
        Slider("Bar height", "height", 12, 64)
        Slider("Spacing", "gap", 0, 30)
        Toggle("Show spell icon", "showIcon")
        Toggle("Show buff name", "showName")
        Toggle("Show remaining time", "showTime")
    elseif pageName == "Appearance" then
        Section("ACTION BAR APPEARANCE")
        local values, order = { none = "Custom" }, { "none" }
        for i = 1, 10 do
            local key = i == 1 and "MainBar" or "Bar" .. i
            values[key], order[#order + 1] = "Action Bar " .. i, key
        end
        Dropdown("Inherit appearance", "inheritBar", values, order, true,
            "Follow the selected Ellesmere Action Bar's border, fonts, text colors and enabled background. Buff fill and layout use the controls below.")
        Section("BUFF FILL")
        Dropdown("Bar texture", "texture", textureNames, textureOrder)
        Swatch("Buff color", "color")
        if not SourceBar() then
            Swatch("Background color", "background")
            Section("BORDER AND TEXT")
            Toggle("Show border", "borderEnabled")
            Slider("Border thickness", "borderSize", 1, 8)
            Swatch("Border color", "borderColor")
            Slider("Buff name font size", "fontSize", 8, 32)
            Slider("Timer font size", "timeFontSize", 8, 32)
            Swatch("Text color", "textColor")
        end
    else
        Section("TRACKED BUFFS — NAMES ALSO MATCH PREFIXES")
        y = TrackingEditor(parent, y, "buff", "spells", {
            inputLabel = "Buff name or prefix", addLabel = "Add buff",
            emptyText = "No tracked buffs. Add a buff name or prefix below.",
            hint = "Drag a row to reorder. Bars follow this order.",
            tooltip = "Matches any buff starting with this name.",
        })
    end
    return math.abs(y)
end

-- Common widgets read the current character table on every access, including after loading a profile.
local function Controls(tracker, parent, y)
    local W, ui = EUI.Widgets, { y = y }
    function ui:section(text) local _, h = W:SectionHeader(parent, text, self.y); self.y = self.y - h end
    function ui:button(text, fn) local _, h = W:Button(parent, text, self.y, fn); self.y = self.y - h end
    function ui:get(key) return function() return ns.TrackerConfig(tracker)[key] end end
    function ui:set(key, rebuild)
        return function(value)
            local c = ns.TrackerConfig(tracker)
            c[key] = value
            if key == "orientation" then
                if value == "vertical" then c.growth = c.growth == "up" and "up" or "down"
                else c.growth = c.growth == "left" and "left" or "right" end
            end
            ns.RefreshTrackers()
            if rebuild then Rebuild(tracker) end
        end
    end
    function ui:toggle(text, key) local _, h = W:Toggle(parent, text, self.y, self:get(key), self:set(key)); self.y = self.y - h end
    function ui:slider(text, key, low, high)
        local _, h = W:Slider(parent, text, self.y, low, high, 1, self:get(key), self:set(key)); self.y = self.y - h
    end
    function ui:dropdown(text, key, values, order, rebuild, tooltip)
        local _, h = W:Dropdown(parent, text, self.y, values, self:get(key), self:set(key, rebuild), order, tooltip)
        self.y = self.y - h
    end
    function ui:swatch(text, key)
        local _, h = W:ColorPicker(parent, text, self.y, function() return Color(ns.TrackerConfig(tracker)[key]) end,
            function(r,g,b,a) ns.TrackerConfig(tracker)[key] = {r=r,g=g,b=b,a=a}; ns.RefreshTrackers() end, true)
        self.y = self.y - h
    end
    function ui:move()
        self:toggle("Lock position", "locked")
        self:button("Move in Unlock Mode", function() if EUI.OpenUnlockMode then EUI:OpenUnlockMode() end end)
    end
    function ui:appearance(timer)
        self:section("ACTION BAR APPEARANCE")
        local values, order = { none = "Custom" }, { "none" }
        for i=1,10 do local key = i==1 and "MainBar" or "Bar"..i; values[key],order[#order+1]="Action Bar "..i,key end
        self:dropdown("Inherit appearance", "inheritBar", values, order, true,
            "Follow the selected Ellesmere Action Bar's fonts, text colors and icon borders. Tracker layout stays independently configurable.")
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

local function BuildCooldownPage(pageName,parent,y)
    local ui=Controls("cd",parent,y)
    if pageName=="Display" then
        ui:section("VISIBILITY")
        ui:toggle("Enable cooldown bar","enabled")
        ui:dropdown("Show bars", "visibility", { always = "Always", combat = "In combat", target = "In combat or with an attackable target" },
            { "always", "combat", "target" })
        ui:move()
        ui:section("LAYOUT")
        ui:dropdown("Orientation","orientation",{horizontal="Horizontal",vertical="Vertical"},{"horizontal","vertical"},true)
        if ns.TrackerConfig("cd").orientation=="vertical" then
            ui:dropdown("Grow direction","growth",{up="Up",down="Down"},{"up","down"})
        else ui:dropdown("Grow direction","growth",{right="Right",left="Left"},{"right","left"}) end
        ui:slider("Icon size","size",16,80)
        ui:slider("Spacing","gap",0,30)
        ui:toggle("Countdown numbers","numbers")
        ui:toggle("Dim spells out of range","rangeDim")
        ui:toggle("Glow when ready in combat","readyGlow")
        ui:section("READY GLOW STYLE FOLLOWS ACTION BARS > BAR ANIMATIONS")
    elseif pageName=="Appearance" then ui:appearance(true)
    else Tracking(ui,"cd",parent,"spells","SPELLS AND ITEMS — ITEM NAMES ALSO MATCH PARTIAL NAMES",false) end
    return math.abs(ui.y)
end
local function BuildRemindersPage(pageName,parent,y)
    local ui=Controls("remind",parent,y)
    if pageName=="Display" then
        ui:section("OUT OF COMBAT — MISSING BUFFS")
        ui:toggle("Enable reminders","enabled")
        ui:toggle("Party members","party")
        ui:toggle("Friendly target","target")
        ui:move()
        ui:section("LAYOUT")
        ui:slider("Icon size","size",12,64)
        ui:slider("Spacing","gap",0,30)
    elseif pageName=="Appearance" then ui:appearance(false)
    elseif pageName=="Your Buffs" then Tracking(ui,"remind",parent,"self","BUFFS YOU SHOULD HAVE — ANY ALTERNATIVE SATISFIES A REMINDER",true)
    elseif pageName=="Ally Buffs" then Tracking(ui,"remind",parent,"ally","BUFFS YOU GIVE OTHERS — ONLY BUFFS YOU CAST COUNT",true)
    else
        ui:section("BLESSING EACH CLASS GETS FROM YOU")
        local values,order={ [""]="Any" },{ "" }
        for name in ns.BLESSINGS:gmatch("[^/]+") do
            name=name:match("^%s*(.-)%s*$"); values[name],order[#order+1]=name,name
        end
        for _,class in ipairs({"WARRIOR","ROGUE","HUNTER","PALADIN","SHAMAN","DRUID","PRIEST","MAGE","WARLOCK"}) do
            local _, h = EUI.Widgets:Dropdown(parent, LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class,
                ui.y, values, function() return ns.TrackerConfig("remind").byClass[class] or "" end,
                function(v) ns.TrackerConfig("remind").byClass[class]=v; ns.RefreshTrackers() end, order)
            ui.y=ui.y-h
        end
    end
    return math.abs(ui.y)
end

local function Header(tracker)
    return function(frame,width)
        frame.euictPreviews=frame.euictPreviews or {}
        local preview = tracker=="cd" and ns.PreviewCd or (tracker=="remind" and ns.PreviewRemind or ns.PreviewBuff)
        local mode = tracker=="remind" and "normal" or "combat"
        local height = tracker=="cd" and 240 or 120
        local stage=frame.euictPreviews[tracker]
        if not stage then
            stage=CreateFrame("Frame",nil,frame)
            stage:SetPoint("TOPLEFT",12,-8); stage:SetPoint("TOPRIGHT",-12,-8)
            stage:SetHeight(height)
            stage.note=stage:CreateFontString(nil,"OVERLAY","GameFontHighlight"); stage.note:SetPoint("CENTER")
            local elapsed=0
            stage:SetScript("OnUpdate",function(_,dt)
                elapsed=elapsed+dt
                if elapsed>=0.1 then elapsed=0; preview(stage,mode) end
            end)
            frame.euictPreviews[tracker]=stage
        end
        for key,other in pairs(frame.euictPreviews) do other:SetShown(key==tracker) end
        preview(stage,mode)
        return height+16
    end
end
local headers={buff=Header("buff"),cd=Header("cd"),remind=Header("remind")}

local registered = EUI.RegisterPlugin(PLUGIN, {
    label = "Cooldown Tracker",
    modules = { {
        key = "BuffBars", title = "Buff Bars",
        description = "Player buff timers. Settings are saved with EllesmereUICooldownTracker profiles.",
        pages = { "Display", "Appearance", "Tracked Buffs" }, buildPage = BuildPage,
        getHeaderBuilder = function() return headers.buff end, searchPrebuild = false,
    }, {
        key="CooldownBar",title="Cooldown Bar",description="Spell and item cooldowns. Ready glows follow Ellesmere Action Bars settings.",
        pages={"Display","Appearance","Tracked"},buildPage=BuildCooldownPage,
        getHeaderBuilder=function() return headers.cd end,searchPrebuild=false,
    }, {
        key="Reminders",title="Reminders",description="Missing buff reminders for you, your party and a friendly target. Saved with EUICT profiles.",
        pages={"Display","Appearance","Your Buffs","Ally Buffs","Class Blessings"},buildPage=BuildRemindersPage,
        getHeaderBuilder=function() return headers.remind end,searchPrebuild=false,
    } },
})
if registered then
    function ns.OpenTrackerSettings(tracker) return EUI.OpenPlugin(PLUGIN, MODULES[tracker], "Display") end
    function ns.OpenBuffSettings() return ns.OpenTrackerSettings("buff") end
    ns.settingsPages.buff:Button("Ellesmere UI", "Open Buff Bars", ns.OpenBuffSettings)
    ns.settingsPages.cd:Button("Ellesmere UI","Open Cooldown Bar",function() ns.OpenTrackerSettings("cd") end)
    ns.settingsPages.remind:Button("Ellesmere UI","Open Reminders",function() ns.OpenTrackerSettings("remind") end)
end

-- Unlock Mode edits the whole tracker's dimensions; translate them to bar/icon settings.
local function ResizeTracker(tracker, axis, value)
    local root, c = ns.TrackerRoot(tracker), ns.TrackerConfig(tracker)
    if not root or not c or type(value) ~= "number" then return end
    local count = 0
    for _, item in ipairs(root.items) do if item:IsShown() then count = count + 1 end end
    count = math.max(1, count)
    local field, low, high
    if tracker == "buff" then
        -- Buff roots reserve space for every tracked entry, including inactive bars.
        count = math.max(1, #c.spells)
        field, low, high = axis, axis == "width" and 80 or 12, axis == "width" and 600 or 64
        if (axis == "width" and c.orientation == "horizontal") or (axis == "height" and c.orientation ~= "horizontal") then
            value = (value - (count - 1) * c.gap) / count
        end
    else
        field, low, high = "size", tracker == "cd" and 16 or 12, tracker == "cd" and 80 or 64
        if tracker == "remind" and axis == "width" then
            -- The reminder width includes the icon, spacing and its text.
            value = value - math.max(0, root:GetWidth() - c.size)
        elseif (tracker == "cd" and axis == "width" and c.orientation ~= "vertical")
            or (axis == "height" and (tracker == "remind" or c.orientation == "vertical")) then
            value = (value - (count - 1) * c.gap) / count
        end
    end
    c[field] = math.max(low, math.min(high, math.floor(value + 0.5)))
    ns.RefreshTrackers()
    Rebuild(tracker)
end

if EUI.RegisterUnlockElements and EUI.MakeUnlockElement then
    local elements={}
    for i,info in ipairs({{"buff","EUICT_Buff","Buff Bars",-230},{"cd","EUICT_CD","Cooldown Bar",-180},
        {"remind","EUICT_Remind","Buff Reminders",-120}}) do
        local tracker,key,label,defaultY=unpack(info)
        elements[i]=EUI.MakeUnlockElement({
            key=key,label=label,group="Cooldown Tracker",order=i,
            getFrame=function() return ns.TrackerRoot(tracker) end,
            getSize=function()
                local root,c=ns.TrackerRoot(tracker),ns.TrackerConfig(tracker)
                if root and c then return math.max(c.size or c.width,root:GetWidth()),math.max(c.size or c.height,root:GetHeight()) end
            end,
            setWidth=function(_,width) ResizeTracker(tracker,"width",width) end,
            setHeight=function(_,height) ResizeTracker(tracker,"height",height) end,
            linkedDimensions=tracker~="buff",
            isHidden=function() local c=ns.TrackerConfig(tracker); return not c or not c.enabled end,
            noAnchorTo=true,noAnchorTarget=true,
            savePos=function(_,point,relPoint,x,y) ns.SaveTrackerPosition(tracker,x,y) end,
            loadPos=function()
                local c=ns.TrackerConfig(tracker)
                if c then return {point="CENTER",relPoint="CENTER",x=c.x,y=c.y} end
            end,
            clearPos=function() ns.SaveTrackerPosition(tracker,0,defaultY) end,
            applyPos=function()
                local root,c=ns.TrackerRoot(tracker),ns.TrackerConfig(tracker)
                if root and c then root:ClearAllPoints(); root:SetPoint("CENTER",UIParent,"CENTER",c.x,c.y) end
            end,
        })
        local moduleKey = registered and EUI.GetPluginModuleKey(PLUGIN, MODULES[tracker])
        if moduleKey then
            -- The standard cog menu resolves Element Options through this shared map.
            EUI._ELEMENT_SETTINGS_MAP = EUI._ELEMENT_SETTINGS_MAP or {}
            EUI._ELEMENT_SETTINGS_MAP[key] = { module = moduleKey, page = "Display" }
        end
    end
    EUI:RegisterUnlockElements(elements,PLUGIN)
end
if EUI.RegisterUnlockModeListener then
    local sizes
    EUI:RegisterUnlockModeListener(PLUGIN, function(active, closeAction)
        if active then
            sizes = {}
            for _, tracker in ipairs({ "buff", "cd", "remind" }) do
                local c = ns.TrackerConfig(tracker)
                if c then sizes[tracker] = { width = c.width, height = c.height, size = c.size } end
            end
        else
            -- Icon/row counts may change during Unlock Mode, so restore the settings
            -- themselves rather than deriving them from the old total dimensions.
            if closeAction == "discard" and sizes then
                for tracker, saved in pairs(sizes) do
                    local c = ns.TrackerConfig(tracker)
                    if c then c.width, c.height, c.size = saved.width, saved.height, saved.size end
                end
            end
            sizes = nil
        end
        ns.euiBuffUnlock = active
        ns.euiUnlockMode = active
        ns.RefreshTrackers()
        if not active then ns.RefreshTrackerSettings() end
    end)
end
