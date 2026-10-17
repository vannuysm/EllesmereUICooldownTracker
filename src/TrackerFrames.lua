-- Shared tracker roots, dragging, and directional layout. No game-state collection.
local _, ns = ...
local Frames = {}
ns.TrackerFrames = Frames
ns.Trackers = {}
local DB = ns.Database.character

Frames.Growth = ns.ProfileValidation.Growth

function Frames.Root(key)
    local tracker = ns.Trackers[key]
    return tracker and tracker.Root()
end

function Frames.SavePosition(key, x, y)
    local cfg = DB[key]
    if not cfg or type(x) ~= "number" or type(y) ~= "number" then return end
    cfg.x, cfg.y = x, y
    ns.Configuration.Apply({ [key] = { x = true, y = true } }, { position = true })
    ns.Kit.SaveEditModePosition(key)
end

function Frames.MakeRoot(name, key)
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
        Frames.SavePosition(key, x, y)
    end)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0, 1, 0, 0.3)
    f.bg:SetShown(not cfg.locked)
    f.items = {}
    return f
end

-- Items take the mouse: right-click opens settings, left-drag moves the root when unlocked.
function Frames.AttachMouse(item, root, key)
    item:EnableMouse(true)
    item:RegisterForDrag("LeftButton")
    item:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ns.SettingsUI.Open(key)
        end
    end)
    item:SetScript("OnDragStart", function() if not DB[key].locked then root:StartMoving() end end)
    item:SetScript("OnDragStop", function() if not DB[key].locked then root:GetScript("OnDragStop")(root) end end)
end

local ANCHORS = {
    right = { "LEFT", 1, 0 }, left = { "RIGHT", -1, 0 },
    up = { "BOTTOM", 0, 1 }, down = { "TOP", 0, -1 },
}

function Frames.Anchor(item, root, config, index, step)
    local anchor = ANCHORS[Frames.Growth(config)]
    local offset = (index - 1) * step
    item:ClearAllPoints()
    item:SetPoint(anchor[1], root, anchor[1], offset * anchor[2], offset * anchor[3])
end

function Frames.SizeIcons(root, config, count)
    local length = math.max(1, count * config.size + (count - 1) * config.gap)
    if config.orientation == "vertical" then root:SetSize(config.size, length)
    else root:SetSize(length, config.size) end
end

function Frames.SizeBars(root, config, count)
    count = math.max(1, count)
    if config.orientation == "horizontal" then
        root:SetSize(count * config.width + (count - 1) * config.gap, config.height)
    else
        root:SetSize(config.width, count * config.height + (count - 1) * config.gap)
    end
end

function Frames.PositionBar(bar, root, config, index)
    local step = (config.orientation == "horizontal" and config.width or config.height) + config.gap
    bar:SetSize(config.width, config.height)
    bar.icon:SetWidth(config.height)
    Frames.Anchor(bar, root, config, index, step)
end
