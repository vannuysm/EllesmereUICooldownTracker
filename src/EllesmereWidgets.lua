-- Ordered tracking lists and the shared add-entry editor.
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI.RegisterPlugin) then return end
local EUI_CHANGE = { source = "ellesmere" }

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
    local function List() return ns.Database.TrackerConfig(tracker)[field] end
    local function Changed()
        ns.Configuration.Changed(tracker, field, EUI_CHANGE)
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

ns.EllesmereWidgets = { TrackingEditor = TrackingEditor }
