-- Tracker styling, optionally inherited from an EllesmereUI Action Bar.
local _, ns = ...
local Appearance = {}
ns.TrackerAppearance = Appearance
local EUI = EllesmereUI
local TrackerConfig = ns.Database.TrackerConfig
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
    local c = TrackerConfig(tracker or "buff")
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

local BORDER_SIZES = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
local function BorderEnabled(config, source)
    if source then return source.borderEnabled end
    return config.borderEnabled
end

-- Buff frames and icon frames use the same Action Bar border settings.
local function ApplyBorder(frame, config, source)
    local color, size, exact = config.borderColor, config.borderSize
    if source then
        color = source.borderColor or color
        if source.borderClassColor then
            local _, class = UnitClass("player")
            color = EUI.GetClassColor and EUI.GetClassColor(class) or RAID_CLASS_COLORS[class] or color
        end
        size = BORDER_SIZES[source.borderThickness or "thin"] or 1
        if EUI.BorderPx then exact = EUI.BorderPx(source.borderThicknessPx, size, source.borderTexture) end
    end
    EUI.ApplyBorderStyle(frame, size, color.r, color.g, color.b, color.a or 1,
        source and source.borderTexture or "solid", source and source.borderTextureOffset,
        source and source.borderTextureOffsetY, source and source.borderTextureShiftX,
        source and source.borderTextureShiftY, "actionbars", source and source.borderThickness, nil, exact)
end

function Appearance.ApplyBuff(b, inverted)
    local c = TrackerConfig("buff")
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
    if BorderEnabled(c, source) and EUI and EUI.ApplyBorderStyle then
        ApplyBorder(Border(b), c, source)
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
    if not (BorderEnabled(c, source) and EUI and EUI.ApplyBorderStyle) then
        if b.euictIconBorder then b.euictIconBorder:Hide() end
        return
    end
    if not b.euictIconBorder then
        b.euictIconBorder = CreateFrame("Frame", nil, b)
        b.euictIconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT")
        b.euictIconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT")
        b.euictIconBorder:SetFrameLevel((b.cd or b):GetFrameLevel() + 1)
    end
    ApplyBorder(b.euictIconBorder, c, source)
end
function Appearance.ApplyCooldown(b)
    local c, source = TrackerConfig("cd"), SourceBar("cd")
    local fs = b.cd.GetCountdownFontString and b.cd:GetCountdownFontString()
    StyleText(fs, c, source, true)
    StyleIconBorder(b, c, source, b.icon)
end
function Appearance.ApplyReminder(b)
    local c, source = TrackerConfig("remind"), SourceBar("remind")
    StyleText(b.text, c, source, false)
    StyleIconBorder(b, c, source, b.icon)
end

Appearance.SourceBar, Appearance.Color = SourceBar, Color
Appearance.textureNames, Appearance.textureOrder = textureNames, textureOrder
