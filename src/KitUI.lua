-- Shared UI primitives, cards, embedded controls and preview stages.
local _, ns = ...
local Kit = ns.Kit
local Make, Tooltip = Kit.Make, Kit.Tooltip
local Page = Kit.Page

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
Kit.Plain = Plain

-- A box: a background and 1px edges.
function Kit.Box(parent, bg, edge)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    edge = edge or { 1, 1, 1, 0.08 }
    for _, s in ipairs({ { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false }, { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(edge[1], edge[2], edge[3], edge[4])
        t:SetPoint(s[1]); t:SetPoint(s[2])
        if s[3] then t:SetWidth(1) else t:SetHeight(1) end
    end
    return f
end

-- An icon texture with the game's border trimmed off.
function Kit.Icon(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return t
end

-- Page pieces ---------------------------------------------------------------------------------------------------------
local PAD = 16

-- A title with an optional grey line under it, at the top of block b. Returns where the content starts.
local function Heading(b, title, subtitle)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", PAD + 4, 0)
    t:SetText(title or "")
    if not subtitle or subtitle == "" then return 22 end
    local h = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", PAD + 4, -17)
    h:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
    h:SetJustifyH("LEFT")
    h:SetText(subtitle)
    return 36
end
Kit.Heading = Heading

-- A titled card. build(card, page) places controls in it with the card helpers below; height in px.
function Page:Card(title, height, build)
    local b = self:AddBlock(height, 12)
    local card = Kit.Box(b, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.07 })
    card:SetPoint("TOPLEFT", PAD, 0)
    card:SetPoint("BOTTOMRIGHT", -PAD, 0)
    card.page = self
    if title then
        local t = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", 12, -10)
        t:SetText(title)
    end
    if build then build(card, self) end
    return card
end

-- A checkbox with its label to the right, at x, y inside parent.
function Page:CheckAt(parent, x, y, label, get, set, tooltip)
    local c = Make("CheckButton", parent, "SettingsCheckboxTemplate", "UICheckButtonTemplate")
    c:SetSize(30, 29)
    c:SetPoint("TOPLEFT", x, y)
    c:SetScript("OnEnter", nil)
    c:SetScript("OnLeave", nil)
    c:SetScript("OnClick", function(btn)
        set(btn:GetChecked() and true or false)
        PlaySound(btn:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("LEFT", c, "RIGHT", 2, 0)
    t:SetText(label)
    Tooltip(c, label, tooltip)
    self:OnRefresh(function() c:SetChecked(get() and true or false) end)
    return c
end

-- A labelled slider with its value, at x, y inside parent.
function Page:SliderAt(parent, x, y, label, minV, maxV, step, get, set, width)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", x, y - 4)
    t:SetText(label)
    local s = Make("Frame", parent, "MinimalSliderWithSteppersTemplate")
    s:SetSize(width or 150, 20)
    s:SetPoint("TOPLEFT", x + 80, y)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    Kit.BindSlider(self, s, minV, maxV, step, get, set, function(v)
        value:SetText(Kit.FormatNumber(v, step))
    end)
    return s
end

-- A dark box drawing the thing as it will look. draw(stage, mode) runs on every refresh and ten times a second while
-- visible, so dragging a slider shows at once. opts.modes adds a switch: "normal" (nothing happening) and "combat"
-- (things being used: cooldowns, timers), for judging sizes and numbers as they look in a fight.
function Page:Preview(height, draw, opts)
    opts = opts or {}
    local b = self:AddBlock(height, 10)
    local box = Kit.Box(b, { 0, 0, 0, 0.45 }, { 1, 1, 1, 0.08 })
    box:SetPoint("TOPLEFT", PAD, 0)
    box:SetPoint("BOTTOMRIGHT", -PAD, 0)
    local t = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("TOPLEFT", 10, -8)
    t:SetText("Preview")
    local stage = CreateFrame("Frame", nil, box)
    stage:SetPoint("TOPLEFT", 0, -24)
    stage:SetPoint("BOTTOMRIGHT")
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    stage.note = stage:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    stage.note:SetPoint("CENTER")
    box.stage = stage
    local mode = "normal"
    if opts.modes then
        -- two small tabs in the corner: the chosen one gold on a light fill, the other grey
        local tabs = {}
        local function Paint()
            for key, tab in pairs(tabs) do
                local on = key == mode
                tab.fill:SetShown(on)
                tab.text:SetTextColor(on and 1 or 0.6, on and 0.82 or 0.6, on and 0 or 0.6)
            end
        end
        local x = -8
        for _, m in ipairs({ { "combat", "Simulate combat" }, { "normal", "Normal" } }) do
            local tab = CreateFrame("Button", nil, box)
            tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            tab.text:SetPoint("CENTER")
            tab.text:SetText(m[2])
            tab:SetSize(tab.text:GetStringWidth() + 18, 18)
            tab:SetPoint("TOPRIGHT", x, -5)
            x = x - tab:GetWidth() - 4
            tab.fill = tab:CreateTexture(nil, "BACKGROUND")
            tab.fill:SetAllPoints()
            tab.fill:SetColorTexture(1, 0.82, 0, 0.14)
            tab:SetScript("OnClick", function()
                mode = m[1]
                Paint()
                pcall(draw, stage, mode)
                PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            end)
            tabs[m[1]] = tab
        end
        Paint()
        box.SetMode = function(_, m) mode = m; Paint(); pcall(draw, stage, mode) end
    end
    local elapsed = 0
    box:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed > 0.1 then elapsed = 0; pcall(draw, stage, mode) end
    end)
    self:OnRefresh(function() pcall(draw, stage, mode) end)
    self.preview = box
    return box
end

-- Help text in the small grey font, indented like the cards.
function Page:Hint(text)
    local b = self:Text(text, "GameFontDisableSmall")
    b.text:SetPoint("TOPLEFT", PAD + 4, 0)
    return b
end
