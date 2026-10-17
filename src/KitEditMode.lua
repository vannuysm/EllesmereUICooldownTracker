-- Blizzard Edit Mode overlays and per-layout positions.
local _, ns = ...
local Kit = ns.Kit

-- Edit Mode ------------------------------------------------------------------------------
-- Addon frames can't join Blizzard's Edit Mode itself (that code is protected), so while Edit Mode is open each
-- registered frame gets an overlay in Edit Mode's colours: blue box and name, brighter on hover. Drag it like a
-- Blizzard frame. Positions are also remembered per Edit Mode layout, so switching layouts moves ours too.
--
-- Kit.EditMode{ frame, label, key, db, get = fn() -> x, y, set = fn(x, y), onToggle = fn(active) }
--   Dragging reuses the frame's own OnDragStop (which saves its position); get/set read and write that saved
--   position for the per-layout copies, set must also re-place the frame. onToggle shows placeholders while open.
local editItems = {}
local editOpen = false
Kit.editMode = false

local function LayoutKey()
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if ok and type(info) == "table" and info.activeLayout then return "layout" .. info.activeLayout end
end

local function SaveForLayout(def)
    local lk = LayoutKey()
    if not (lk and def.db and def.get) then return end
    def.db.editLayouts = def.db.editLayouts or {}
    def.db.editLayouts[lk] = def.db.editLayouts[lk] or {}
    local x, y = def.get()
    def.db.editLayouts[lk][def.key] = { x, y }
end

-- Moving a tracker outside Blizzard Edit Mode must update its active layout too;
-- otherwise ApplyLayout restores an older position after /reload or entering the world.
function Kit.SaveEditModePosition(key)
    for _, def in ipairs(editItems) do
        if def.key == key then SaveForLayout(def); return end
    end
end

local function ApplyLayout()
    local lk = LayoutKey()
    if not lk then return end
    for _, def in ipairs(editItems) do
        local saved = def.db and def.db.editLayouts and def.db.editLayouts[lk] and def.db.editLayouts[lk][def.key]
        if saved and def.set then def.set(saved[1], saved[2]) end
    end
end

local function Overlay(def)
    local f = def.frame
    local o = CreateFrame("Button", nil, f)
    o:SetPoint("TOPLEFT", -4, 4)
    o:SetPoint("BOTTOMRIGHT", 4, -4)
    o:SetFrameStrata("DIALOG")
    o:Hide()
    o.fill = o:CreateTexture(nil, "BACKGROUND")
    o.fill:SetAllPoints()
    o.edges = {}
    for i, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 }, { "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
        local t = o:CreateTexture(nil, "BORDER")
        t:SetPoint(side[1]); t:SetPoint(side[2])
        if side[3] > 0 then t:SetWidth(side[3]) else t:SetHeight(side[4]) end
        o.edges[i] = t
    end
    o.label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    o.label:SetPoint("CENTER")
    o.label:SetText(def.label)
    local function Tint(hover)
        o.fill:SetColorTexture(0.25, 0.55, 1, hover and 0.35 or 0.22)
        for _, t in ipairs(o.edges) do t:SetColorTexture(0.35, 0.7, 1, hover and 1 or 0.8) end
    end
    Tint(false)
    o:SetScript("OnEnter", function() Tint(true) end)
    o:SetScript("OnLeave", function() Tint(false) end)
    o:RegisterForDrag("LeftButton")
    o:SetScript("OnDragStart", function()
        f:SetMovable(true)
        f:StartMoving()
    end)
    o:SetScript("OnDragStop", function()
        local stop = f:GetScript("OnDragStop")
        if stop then stop(f) else f:StopMovingOrSizing() end   -- the frame's own handler saves its position
        SaveForLayout(def)
    end)
    return o
end

local function SetEditMode(active)
    Kit.editMode = active
    for _, def in ipairs(editItems) do
        if def.onToggle then def.onToggle(active) end
        local show = active and (not def.enabled or def.enabled())
        def.overlay:SetShown(show)
        -- tiny or empty frames still get a box big enough to grab
        if show then
            local w, h = def.frame:GetSize()
            if (w or 0) < 60 or (h or 0) < 20 then def.frame:SetSize(math.max(w or 0, 160), math.max(h or 0, 24)) end
        end
    end
end

function Kit.EditMode(def)
    def.overlay = Overlay(def)
    editItems[#editItems + 1] = def
    if not editOpen then
        editOpen = true
        if EditModeManagerFrame then
            EditModeManagerFrame:HookScript("OnShow", function() SetEditMode(true) end)
            EditModeManagerFrame:HookScript("OnHide", function() SetEditMode(false) end)
        end
        local ev = CreateFrame("Frame")
        pcall(ev.RegisterEvent, ev, "EDIT_MODE_LAYOUTS_UPDATED")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:SetScript("OnEvent", function() C_Timer.After(0.5, ApplyLayout) end)
    end
    if Kit.editMode then SetEditMode(true) end
end
