-- Per-class spell picks: a card per class whose icon button opens a menu of choices.
local _, ns = ...
local Kit = ns.Kit
local Page = Kit.Page
local QUESTION = 134400
local PAD = 16

-- opts = { title, subtitle, tooltip, classes, choices = fn() -> { { value, label } }, get = fn(class) -> value,
--          set = fn(class, value), short = fn(value) -> card text }. The value "" means any of the choices.
function Page:ClassPicks(opts)
    local b = self:AddBlock(40 + math.ceil(#opts.classes / 3) * 60, 12)
    local top = Kit.Heading(b, opts.title, opts.subtitle)
    local cards = {}
    for i, class in ipairs(opts.classes) do
        local card = Kit.Box(b, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.07 })
        card:SetHeight(52)
        card.ci = card:CreateTexture(nil, "ARTWORK")
        card.ci:SetSize(30, 30)
        card.ci:SetPoint("LEFT", 10, 0)
        if not pcall(card.ci.SetAtlas, card.ci, "classicon-" .. class:lower()) then card.ci:SetTexture(QUESTION) end
        card.name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        card.name:SetPoint("LEFT", card.ci, "RIGHT", 10, 7)
        card.name:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class)
        card.pick = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        card.pick:SetPoint("LEFT", card.ci, "RIGHT", 10, -9)
        card.slot = CreateFrame("Button", nil, card)
        card.slot:SetSize(36, 36)
        card.slot:SetPoint("RIGHT", -8, 0)
        local frame = Kit.Box(card.slot, { 0, 0, 0, 0.6 }, { 1, 0.82, 0, 0.5 })
        frame:SetAllPoints()
        card.icon = Kit.Icon(card.slot, 32, "OVERLAY")
        card.icon:SetPoint("CENTER")
        card.any = card.slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        card.any:SetPoint("CENTER")
        card.any:SetText("Any")
        card.slot:SetScript("OnClick", function(self)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, o in ipairs(opts.choices()) do
                    local info = o[1] ~= "" and Kit.SpellByName(o[1])
                    local text = (info and ("|T" .. info.iconID .. ":16|t ") or "") .. o[2]
                    root:CreateRadio(text, function() return opts.get(class) == o[1] end, function() opts.set(class, o[1]) end)
                end
            end)
        end)
        Kit.Tooltip(card.slot, card.name:GetText(), opts.tooltip)
        cards[i] = card
    end
    local function Place()
        local w = (b:GetWidth() > 0 and b:GetWidth() or 640) - 2 * PAD
        local cw = math.floor((w - 2 * 10) / 3)
        for i, card in ipairs(cards) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            card:ClearAllPoints()
            card:SetWidth(cw)
            card:SetPoint("TOPLEFT", PAD + col * (cw + 10), -top - row * 60)
            local pick = opts.get(opts.classes[i]) or ""
            local info = pick ~= "" and Kit.SpellByName(pick)
            card.pick:SetText(pick ~= "" and opts.short(pick) or "Any")
            card.icon:SetShown(info and true or false)
            if info then card.icon:SetTexture(info.iconID) end
            card.any:SetShown(not info)
            card.any:SetText(pick ~= "" and not info and "?" or "Any")
        end
    end
    b:SetScript("OnSizeChanged", Place)
    self:OnRefresh(Place)
    return b
end
