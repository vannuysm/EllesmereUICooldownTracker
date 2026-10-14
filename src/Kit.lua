-- Forever settings kit: builds Blizzard-style option pages in Options > AddOns.
-- The same file ships in every Forever addon. Change it in one repo, then copy it to the others.
local _, ns = ...
local Kit = {}
ns.Kit = Kit

local LABEL_X, CONTROL_X, CONTROL_W, ROW_H = 24, 260, 220, 30

-- Blizzard templates first; older names as fallback so a missing template never breaks the page.
local function Make(kind, parent, ...)
    for i = 1, select("#", ...) do
        local ok, f = pcall(CreateFrame, kind, nil, parent, (select(i, ...)))
        if ok then return f end
    end
    return CreateFrame(kind, nil, parent)
end
Kit.Make = Make

local function Tooltip(frame, title, text)
    if not text then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end
Kit.Tooltip = Tooltip

local function Round(v, step)
    if not step or step <= 0 then return v end
    return math.floor(v / step + 0.5) * step
end

local function FormatNumber(v, step)
    if step and step >= 1 then return ("%d"):format(v) end
    if step and step >= 0.1 then return ("%.1f"):format(v) end
    return ("%.2f"):format(v)
end
Kit.FormatNumber = FormatNumber

-- Page ----------------------------------------------------------------------
local Page = {}
Page.__index = Page
Kit.Page = Page

-- title: shown at the top of the page and used as the category name.
function Kit.NewPage(title)
    local frame = CreateFrame("Frame")
    frame:Hide()
    local page = setmetatable({ frame = frame, title = title, blocks = {}, refreshers = {} }, Page)

    local header = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    header:SetPoint("TOPLEFT", 7, -22)
    header:SetText(title)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)

    local scroll = Make("ScrollFrame", frame, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -60)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(600, 1)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
    page.scroll, page.content = scroll, child

    frame:SetScript("OnShow", function() page:Refresh() end)
    -- Blizzard calls these on canvas pages; the kit keeps no pending state, so only refresh matters.
    frame.OnRefresh = function() page:Refresh() end
    frame.OnCommit = function() end
    frame.OnDefault = function() end
    return page
end

-- Blocks stack top to bottom. A block may change its own height; Layout() restacks.
function Page:AddBlock(height, gap)
    local b = CreateFrame("Frame", nil, self.content)
    b:SetHeight(height)
    b.gap = gap or 0
    self.blocks[#self.blocks + 1] = b
    return b
end

function Page:Layout()
    local y = 0
    for _, b in ipairs(self.blocks) do
        if b:IsShown() then
            y = y + b.gap
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 0, -y)
            b:SetPoint("RIGHT", self.content, "RIGHT")
            y = y + b:GetHeight()
        end
    end
    self.content:SetHeight(y + 20)
end

function Page:OnRefresh(fn) self.refreshers[#self.refreshers + 1] = fn end

function Page:Refresh()
    for _, fn in ipairs(self.refreshers) do fn() end
    self:Layout()
end

function Page:Section(title)
    local b = self:AddBlock(34, 14)
    local t = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    t:SetPoint("BOTTOMLEFT", LABEL_X - 8, 8)
    t:SetText(title)
    return b
end

-- A labelled row with hover highlight, like the rows in the Game tab.
function Page:Row(label, tooltip)
    local b = self:AddBlock(ROW_H, 0)
    local hl = b:CreateTexture(nil, "BACKGROUND")
    hl:SetPoint("TOPLEFT", LABEL_X - 10, 0)
    hl:SetPoint("BOTTOMRIGHT", -10, 0)
    hl:SetColorTexture(1, 1, 1, 0.05)
    hl:Hide()
    b:SetScript("OnEnter", function() hl:Show() end)
    b:SetScript("OnLeave", function() hl:Hide() end)
    b:SetMouseMotionEnabled(true)
    local t = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t:SetPoint("LEFT", LABEL_X, 0)
    t:SetPoint("RIGHT", b, "LEFT", CONTROL_X - 12, 0)
    t:SetJustifyH("LEFT")
    t:SetText(label)
    b.label = t
    Tooltip(b, label, tooltip)
    return b
end

-- Controls ------------------------------------------------------------------
function Page:Check(label, get, set, tooltip)
    local row = self:Row(label, tooltip)
    local c = Make("CheckButton", row, "SettingsCheckboxTemplate", "UICheckButtonTemplate")
    c:SetSize(30, 29)
    c:SetPoint("LEFT", CONTROL_X, 0)
    -- the template's own handlers expect a Blizzard setting object behind it
    c:SetScript("OnEnter", nil)
    c:SetScript("OnLeave", nil)
    c:SetScript("OnClick", function(btn)
        set(btn:GetChecked() and true or false)
        PlaySound(btn:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)
    Tooltip(c, label, tooltip)
    self:OnRefresh(function() c:SetChecked(get() and true or false) end)
    row.control = c
    return row
end

-- fmt: optional function(value) -> string for the value label.
function Page:Slider(label, minV, maxV, step, get, set, fmt, tooltip)
    local row = self:Row(label, tooltip)
    local s = Make("Frame", row, "MinimalSliderWithSteppersTemplate")
    s:SetSize(CONTROL_W - 30, 20)
    s:SetPoint("LEFT", CONTROL_X + 4, 0)
    local value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    local function Show(v) value:SetText(fmt and fmt(v) or FormatNumber(v, step)) end
    local syncing = false
    if s.Init then
        s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5), {})
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            v = Round(v, step)
            Show(v)
            if not syncing then set(v) end
        end, row)
    end
    self:OnRefresh(function()
        local v = get() or minV
        Show(v)
        if s.SetValue then syncing = true; s:SetValue(v); syncing = false end
    end)
    row.control = s
    return row
end

-- options: list of { value, label } or a function returning one.
function Page:Dropdown(label, options, get, set, tooltip)
    local row = self:Row(label, tooltip)
    local d = Make("DropdownButton", row, "WowStyle1DropdownTemplate")
    d:SetWidth(CONTROL_W)
    d:SetPoint("LEFT", CONTROL_X, 0)
    if d.SetupMenu then
        d:SetupMenu(function(_, root)
            for _, o in ipairs(type(options) == "function" and options() or options) do
                root:CreateRadio(o[2], function() return get() == o[1] end, function() set(o[1]) end)
            end
        end)
    end
    self:OnRefresh(function() if d.GenerateMenu then d:GenerateMenu() end end)
    row.control = d
    return row
end

function Page:Button(label, text, onClick, tooltip)
    local row = self:Row(label, tooltip)
    local b = Make("Button", row, "UIPanelButtonTemplate")
    b:SetSize(CONTROL_W, 24)
    b:SetPoint("LEFT", CONTROL_X, 0)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    row.control = b
    return row
end

-- Wrapped help text. text may be a function; it is re-read on every refresh.
function Page:Text(text, font)
    local b = self:AddBlock(20, 4)
    local t = b:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    t:SetPoint("TOPLEFT", LABEL_X, 0)
    t:SetPoint("RIGHT", -24, 0)
    t:SetJustifyH("LEFT")
    t:SetSpacing(2)
    local function Update()
        t:SetText(type(text) == "function" and text() or text)
        b:SetHeight(math.max(14, t:GetStringHeight()) + 4)
        b:SetShown((t:GetText() or "") ~= "")
    end
    Update()
    self:OnRefresh(Update)
    b.text = t
    return b
end

-- Small number box. Empty text calls set(nil) so callers can use "blank = default".
function Kit.NumberBox(parent, width, get, set, placeholder)
    local e = Make("EditBox", parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    e:SetJustifyH("CENTER")
    local hint = e:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("CENTER")
    local function Sync()
        local v = get()
        e:SetText(v and FormatNumber(v, 0.01):gsub("%.?0+$", "") or "")
        local ph = placeholder and placeholder()
        hint:SetText(ph or "")
        hint:SetShown(e:GetText() == "" and not e:HasFocus())
    end
    local function Save()
        local txt = e:GetText():gsub(",", "."):match("^%s*(.-)%s*$")
        set(tonumber(txt))
        e:ClearFocus()
        Sync()
    end
    e:SetScript("OnEnterPressed", Save)
    e:SetScript("OnEditFocusLost", Save)
    e:SetScript("OnEditFocusGained", function() hint:Hide() end)
    e:SetScript("OnEscapePressed", function() e:ClearFocus(); Sync() end)
    e.Sync = Sync
    Sync()
    return e
end

-- Editable list of strings with remove buttons and an add box (used for spell and frame lists).
-- list: function returning the live table. onChange: called after any add/remove.
function Page:List(list, onChange, placeholder, validate)
    local b = self:AddBlock(40, 4)
    local rows = {}
    local edit = Make("EditBox", b, "InputBoxTemplate")
    edit:SetSize(CONTROL_W + 60, 22)
    edit:SetAutoFocus(false)
    local hint = edit:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText(placeholder or "")
    local add = Make("Button", b, "UIPanelButtonTemplate")
    add:SetSize(70, 22)
    add:SetPoint("LEFT", edit, "RIGHT", 8, 0)
    add:SetText(ADD or "Add")

    local Update
    local function Add()
        local v = edit:GetText():match("^%s*(.-)%s*$")
        if v == "" then return end
        if validate then
            local err = validate(v)
            if err then print(err); return end
        end
        for _, existing in ipairs(list()) do if existing == v then edit:SetText(""); return end end
        table.insert(list(), v)
        edit:SetText("")
        onChange()
        Update()
    end
    add:SetScript("OnClick", Add)
    edit:SetScript("OnEnterPressed", Add)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)
    edit:HookScript("OnTextChanged", function() hint:SetShown(edit:GetText() == "") end)

    Update = function()
        local items = list() or {}
        local y = 0
        for i, name in ipairs(items) do
            local r = rows[i]
            if not r then
                r = CreateFrame("Frame", nil, b)
                r:SetWidth(CONTROL_W + 60)
                local bg = r:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.06)
                r.text = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                r.text:SetPoint("LEFT", 8, 0)
                r.text:SetPoint("RIGHT", -28, 0)   -- long entries wrap clear of the remove button
                r.text:SetJustifyH("LEFT")
                r.text:SetWordWrap(true)
                r.del = Make("Button", r, "UIPanelCloseButtonNoScripts", "UIPanelCloseButton")
                r.del:SetSize(22, 22)
                r.del:SetPoint("RIGHT", -1, 0)
                r.del:SetScript("OnClick", function()
                    table.remove(list(), i)
                    onChange()
                    Update()
                end)
                rows[i] = r
            end
            r.text:SetText(name)
            local h = math.max(24, math.ceil(r.text:GetStringHeight()) + 8)
            r:SetHeight(h)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", LABEL_X + 6, -y)
            y = y + h
            r:Show()
        end
        for i = #items + 1, #rows do rows[i]:Hide() end
        edit:ClearAllPoints()
        edit:SetPoint("TOPLEFT", LABEL_X + 12, -y - 8)
        b:SetHeight(y + 38)
        if b:GetParent() and self.content then self:Layout() end
    end
    -- values may not exist yet (saved variables load after this file); the first refresh fills the list
    self:OnRefresh(Update)
    return b
end

-- Registration --------------------------------------------------------------
-- parent: a category returned by an earlier Register call, to make this page a subcategory.
function Kit.Register(page, parent)
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local cat
    if parent then
        cat = Settings.RegisterCanvasLayoutSubcategory(parent, page.frame, page.title)
    else
        cat = Settings.RegisterCanvasLayoutCategory(page.frame, page.title)
        Settings.RegisterAddOnCategory(cat)
    end
    page.category = cat
    return cat
end

-- Saved data ---------------------------------------------------------------------------
-- The Forever beta can fail to load SavedVariables when the game starts. A copy of the data may then come
-- from the account file, the per-character file, or an existing !ForeverData folder (which loads the
-- same files as plain addon files). Every copy is stamped when the game writes it at logout; the newest wins.
-- Returns the newest non-empty table among the candidates, ignoring own (the addon's live table).
function Kit.PickSaved(own, ...)
    local best
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if type(t) == "table" and t ~= own and next(t) ~= nil
            and (not best or (tonumber(t._savedAt) or 0) > (tonumber(best._savedAt) or 0)) then
            best = t
        end
    end
    return best
end

-- getter: returns the table to stamp (tables can be replaced during a session, so look them up at logout).
local stamped = {}
local stamper = CreateFrame("Frame")
stamper:RegisterEvent("PLAYER_LOGOUT")   -- also fires on /reload, just before the game writes
stamper:SetScript("OnEvent", function()
    local now = time()
    for _, get in ipairs(stamped) do
        local t = get()
        if type(t) == "table" then t._savedAt = now end
    end
end)
function Kit.StampOnLogout(getter) stamped[#stamped + 1] = getter end

-- A settings-page line saying whether the startup fallback is in place.
function Page:SaveStatus()
    self:Section("Saved settings")
    self:Text(function()
        if ForeverData and ForeverData.active then
            return "|cff60ff60Protected.|r Forever Data Protect loads settings from disk, so they survive a restart "
                .. "even while the Forever beta fails to load them itself."
        end
        return "|cffffd100Not protected.|r The Forever beta currently forgets addon settings when the game restarts. "
            .. "To keep them, install and configure Forever Data Protect using its installation instructions."
    end, "GameFontHighlightSmall")
end

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

function Kit.Open(page)
    if not (page and page.category) then return end
    if SettingsPanel and SettingsPanel:IsShown() and page.frame:IsVisible() then
        HideUIPanel(SettingsPanel)
        return
    end
    Settings.OpenToCategory(page.category:GetID())
end
