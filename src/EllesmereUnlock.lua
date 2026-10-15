-- Optional Ellesmere Unlock Mode resizing, positions and discard handling.
local ADDON_NAME, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI.RegisterPlugin) then return end
local PLUGIN = ADDON_NAME

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
    ns.SetConfig(tracker, field, math.max(low, math.min(high, math.floor(value + 0.5))))
end

if EUI.RegisterUnlockElements and EUI.MakeUnlockElement then
    local elements = {}
    local definitions = {
        { "buff", "EUICT_Buff", "Buff Bars", -230 },
        { "cd", "EUICT_CD", "Cooldown Bar", -180 },
        { "remind", "EUICT_Remind", "Buff Reminders", -120 },
    }
    for i, info in ipairs(definitions) do
        local tracker, key, label, defaultY = unpack(info)
        elements[i] = EUI.MakeUnlockElement({
            key = key, label = label, group = "Cooldown Tracker", order = i,
            getFrame = function() return ns.TrackerRoot(tracker) end,
            getSize = function()
                local root, c = ns.TrackerRoot(tracker), ns.TrackerConfig(tracker)
                if root and c then
                    return math.max(c.size or c.width, root:GetWidth()), math.max(c.size or c.height, root:GetHeight())
                end
            end,
            setWidth = function(_, width) ResizeTracker(tracker, "width", width) end,
            setHeight = function(_, height) ResizeTracker(tracker, "height", height) end,
            linkedDimensions = tracker ~= "buff",
            isHidden = function()
                local c = ns.TrackerConfig(tracker)
                return not c or not c.enabled
            end,
            noAnchorTo = true, noAnchorTarget = true,
            savePos = function(_, point, relPoint, x, y) ns.SaveTrackerPosition(tracker, x, y) end,
            loadPos = function()
                local c = ns.TrackerConfig(tracker)
                if c then return { point = "CENTER", relPoint = "CENTER", x = c.x, y = c.y } end
            end,
            clearPos = function() ns.SaveTrackerPosition(tracker, 0, defaultY) end,
            applyPos = function()
                ns.Configuration.Apply({ [tracker] = { x = true, y = true } }, { position = true })
            end,
        })
    end
    EUI:RegisterUnlockElements(elements, PLUGIN)
end
if EUI.RegisterUnlockModeListener then
    local sizes
    EUI:RegisterUnlockModeListener(PLUGIN, function(active, closeAction)
        local changes = { cd = { editing = true }, buff = { editing = true }, remind = { editing = true } }
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
                    if c then
                        c.width, c.height, c.size = saved.width, saved.height, saved.size
                        changes[tracker].width, changes[tracker].height, changes[tracker].size = true, true, true
                    end
                end
            end
            sizes = nil
        end
        ns.euiBuffUnlock = active
        ns.euiUnlockMode = active
        ns.Configuration.Apply(changes)
    end)
end
