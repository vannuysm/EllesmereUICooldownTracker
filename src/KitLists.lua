-- Reorderable icon tiles and groups of buff alternatives.
local _, ns = ...
local Kit = ns.Kit
local Make, Tooltip = Kit.Make, Kit.Tooltip
local Page = Kit.Page
local QUESTION = 134400
local PAD = 16
local Heading = Kit.Heading

-- Icon tiles ------------------------------------------------------------------------------------------------------------
-- A list of names (spells or items) as icon tiles. Drag a tile onto another to move it, right-click to remove,
-- drop a spell or item from the cursor to add it, or use the + tile to search.
-- opts = { title, resolve = fn(name) -> { icon, grey, tag }, sources = { "spells", "items" }, onChange = fn() }
local TILE, TILE_W, TILE_H = 40, 82, 84
function Page:Icons(list, opts)
    local page = self
    local b = self:AddBlock(TILE_H + 30, 12)
    local top = Heading(b, opts.title, opts.subtitle or "Drag to reorder  ·  right-click to remove  ·  drop a spell or item here")
    local grid = CreateFrame("Frame", nil, b)
    grid:SetPoint("TOPLEFT", PAD, -top)
    grid:SetPoint("BOTTOMRIGHT", -PAD, 0)
    local tiles, dragging = {}, nil
    local Update

    local function Changed() if opts.onChange then opts.onChange() end; Update() end
    local function Insert(name, at)
        if not name or name == "" then return end
        for _, v in ipairs(list()) do if v:lower() == name:lower() then return end end
        table.insert(list(), at or (#list() + 1), name)
        Changed()
    end
    local function Dropped(at)
        local name = Kit.CursorName()
        if name then ClearCursor(); Insert(name, at) return true end
    end
    local function Search(anchor)
        Kit.OpenSearch(anchor, {
            sources = opts.sources,
            exists = function(name) for _, v in ipairs(list()) do if v:lower() == name:lower() then return true end end end,
            onPick = function(name) Insert(name) end,
        })
    end

    local function Tile(i)
        if tiles[i] then return tiles[i] end
        local t = CreateFrame("Button", nil, grid)
        t:SetSize(TILE_W, TILE_H)
        t.frame = Kit.Box(t, { 0, 0, 0, 0.6 }, { 1, 0.82, 0, 0.45 })
        t.frame:SetSize(TILE + 4, TILE + 4)
        t.frame:SetPoint("TOP", 0, -2)
        t.icon = Kit.Icon(t.frame, TILE)
        t.icon:SetPoint("CENTER")
        t.plus = t.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        t.plus:SetPoint("CENTER")
        t.plus:SetText("+")
        t.label = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t.label:SetPoint("TOP", t.frame, "BOTTOM", 0, -4)
        t.label:SetWidth(TILE_W - 6)
        t.label:SetWordWrap(true)
        if t.label.SetMaxLines then t.label:SetMaxLines(2) end
        t.label:SetJustifyH("CENTER")
        t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        t:RegisterForDrag("LeftButton")
        t:SetScript("OnEnter", function(self)
            if self.add then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Add")
                GameTooltip:AddLine("Search your spellbook" .. ((opts.sources and opts.sources[2]) and " and bags" or "") .. ", or drop a spell or item here.", nil, nil, nil, true)
                GameTooltip:Show()
                return
            end
            local name = list()[self.index]
            local r = opts.resolve(name)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(name, 1, 1, 1)
            if r.tag and r.tag ~= "" then GameTooltip:AddLine(r.tag, nil, nil, nil, true) end
            GameTooltip:AddLine("Drag to move  ·  Right-click to remove", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", GameTooltip_Hide)
        t:SetScript("OnClick", function(self, button)
            if Dropped(self.add and nil or self.index) then return end
            if self.add then Search(self) return end
            if button == "RightButton" then
                table.remove(list(), self.index)
                GameTooltip_Hide()
                Changed()
            end
        end)
        t:SetScript("OnReceiveDrag", function(self) Dropped(not self.add and self.index or nil) end)
        t:SetScript("OnDragStart", function(self)
            if self.add then return end
            dragging = self.index
            self:SetAlpha(0.35)
        end)
        t:SetScript("OnDragStop", function(self)
            self:SetAlpha(1)
            local from = dragging
            dragging = nil
            if not from then return end
            local to
            for j, other in ipairs(tiles) do
                if other:IsShown() and other:IsMouseOver() then to = other.add and #list() or other.index; break end
            end
            if to and to ~= from then
                local name = table.remove(list(), from)
                table.insert(list(), math.min(to, #list() + 1), name)
                Changed()
            end
        end)
        tiles[i] = t
        return t
    end

    local later = grid:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    later:SetJustifyH("LEFT")
    local laterHint = grid:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    laterHint:SetJustifyH("LEFT")
    Update = function()
        local items = list() or {}
        local cols = math.max(1, math.floor((grid:GetWidth() > 0 and grid:GetWidth() or 560) / TILE_W))
        -- the order on screen: what's available now, the + tile, then (in their own section) what isn't yet
        local now, notYet = {}, {}
        for i, name in ipairs(items) do
            local r = opts.resolve(name) or {}
            if r.grey and opts.later then notYet[#notYet + 1] = i else now[#now + 1] = i end
        end
        local order = {}
        for _, i in ipairs(now) do order[#order + 1] = i end
        order[#order + 1] = "add"
        local split = #order
        for _, i in ipairs(notYet) do order[#order + 1] = i end
        local n = #order
        local rowsNow = math.ceil(split / cols)
        local laterY = rowsNow * TILE_H + 6
        later:SetShown(#notYet > 0)
        laterHint:SetShown(#notYet > 0)
        if #notYet > 0 then
            later:ClearAllPoints(); later:SetPoint("TOPLEFT", 4, -laterY); later:SetText(opts.later)
            laterHint:ClearAllPoints(); laterHint:SetPoint("TOPLEFT", 4, -laterY - 17); laterHint:SetText(opts.laterHint or "")
        end
        for k = 1, n do
            local i = order[k]
            local t = Tile(k)
            t:ClearAllPoints()
            if k <= split then
                t:SetPoint("TOPLEFT", ((k - 1) % cols) * TILE_W, -math.floor((k - 1) / cols) * TILE_H)
            else
                local j = k - split - 1
                t:SetPoint("TOPLEFT", (j % cols) * TILE_W, -laterY - 36 - math.floor(j / cols) * TILE_H)
            end
            t.add = i == "add"
            t.index = t.add and #items + 1 or i
            if t.add then
                t.icon:Hide()
                t.plus:Show()
                t.label:SetText("Add")
                t.label:SetTextColor(1, 0.82, 0)
                t.frame.bg:SetColorTexture(1, 1, 1, 0.03)
            else
                local r = opts.resolve(items[i]) or {}
                i = t.index
                t.icon:Show()
                t.plus:Hide()
                t.icon:SetTexture(r.icon or Kit.icons[items[i]] or QUESTION)
                t.icon:SetDesaturated(r.grey or false)
                t.icon:SetAlpha(r.grey and 0.55 or 1)
                t.label:SetText(items[i])
                t.label:SetTextColor(r.grey and 0.55 or 1, r.grey and 0.55 or 1, r.grey and 0.55 or 1)
                t.frame.bg:SetColorTexture(0, 0, 0, 0.6)
            end
            t:Show()
        end
        for k = n + 1, #tiles do tiles[k]:Hide() end
        local h = rowsNow * TILE_H
        if #notYet > 0 then h = laterY + 36 + math.ceil(#notYet / cols) * TILE_H end
        b:SetHeight(top + h + 4)
    end
    grid:SetScript("OnSizeChanged", function() if list() then Update(); page:Layout() end end)
    grid:EnableMouse(true)
    grid:SetScript("OnReceiveDrag", function() Dropped() end)
    grid:SetScript("OnMouseUp", function() Dropped() end)
    self:OnRefresh(function() if list() then Update() end end)
    b.Update = Update
    return b
end

-- Icon groups -------------------------------------------------------------------------------------------------------
-- A list whose entries are " / "-separated alternatives ("Arcane Intellect / Arcane Brilliance"), drawn as chips:
-- the icons of each alternative and a label. + in a chip adds an alternative, ✕ removes the chip, right-click an icon
-- removes that one alternative. opts = { title, subtitle, label = fn(names) -> text, onChange }
local function Split(entry)
    local out = {}
    for name in entry:gmatch("[^/]+") do
        name = name:match("^%s*(.-)%s*$")
        if name ~= "" then out[#out + 1] = name end
    end
    return out
end
Kit.Split = Split
local function IconOf(name)
    local info = Kit.SpellByName(name)
    if info then Kit.icons[name] = info.iconID; return info.iconID, true end
    return Kit.icons[name] or QUESTION, false
end

function Page:IconGroups(list, opts)
    local page = self
    local b = self:AddBlock(60, 12)
    local top = Heading(b, opts.title, opts.subtitle or "Any icon in a group counts  ·  + adds another  ·  right-click an icon to remove it")
    local area = CreateFrame("Frame", nil, b)
    area:SetPoint("TOPLEFT", PAD, -top)
    area:SetPoint("BOTTOMRIGHT", -PAD, 0)
    local chips, icons = {}, {}
    local addBtn
    local Update
    local function Changed() if opts.onChange then opts.onChange() end; Update() end
    local function Exists(name)
        for _, e in ipairs(list()) do for _, n in ipairs(Split(e)) do if n:lower() == name:lower() then return true end end end
    end

    local function Chip(i)
        if chips[i] then return chips[i] end
        local c = Kit.Box(area, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.09 })
        c:SetHeight(36)
        c.icons = {}
        c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.add = CreateFrame("Button", nil, c)
        c.add:SetSize(20, 20)
        c.add.text = c.add:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        c.add.text:SetPoint("CENTER")
        c.add.text:SetText("+")
        c.add:SetScript("OnClick", function(self)
            Kit.OpenSearch(self, { sources = { "spells" }, exists = Exists, onPick = function(name)
                list()[c.index] = list()[c.index] .. " / " .. name
                Changed()
            end })
        end)
        Tooltip(c.add, "Add an alternative", "Another buff that counts for this reminder.")
        c.del = Make("Button", c, "UIPanelCloseButtonNoScripts", "UIPanelCloseButton")
        c.del:SetSize(20, 20)
        c.del:SetPoint("RIGHT", -4, 0)
        c.del:SetScript("OnClick", function() table.remove(list(), c.index); Changed() end)
        chips[i] = c
        return c
    end
    local function ChipIcon(c, j)
        if c.icons[j] then return c.icons[j] end
        local ib = CreateFrame("Button", nil, c)
        ib:SetSize(24, 24)
        ib.tex = Kit.Icon(ib, 24)
        ib.tex:SetAllPoints()
        ib:RegisterForClicks("RightButtonUp")
        ib:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.name, 1, 1, 1)
            if not self.learned then GameTooltip:AddLine("Not learned yet", 0.6, 0.6, 0.6) end
            GameTooltip:AddLine("Right-click to remove", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        ib:SetScript("OnLeave", GameTooltip_Hide)
        ib:SetScript("OnClick", function(self)
            local names = Split(list()[c.index])
            table.remove(names, self.j)
            if #names == 0 then table.remove(list(), c.index) else list()[c.index] = table.concat(names, " / ") end
            GameTooltip_Hide()
            Changed()
        end)
        c.icons[j] = ib
        return ib
    end

    Update = function()
        local entries = list() or {}
        local width = area:GetWidth() > 0 and area:GetWidth() or 560
        local x, y = 0, 0
        for i, entry in ipairs(entries) do
            local c = Chip(i)
            c.index = i
            local names = Split(entry)
            for j, name in ipairs(names) do
                local ib = ChipIcon(c, j)
                local icon, learned = IconOf(name)
                ib.tex:SetTexture(icon)
                ib.tex:SetDesaturated(not learned)
                ib.name, ib.learned, ib.j = name, learned, j
                ib:ClearAllPoints()
                ib:SetPoint("LEFT", 6 + (j - 1) * 27, 0)
                ib:Show()
            end
            for j = #names + 1, #c.icons do c.icons[j]:Hide() end
            c.label:SetText(opts.label and opts.label(names) or names[1])
            c.label:ClearAllPoints()
            c.label:SetPoint("LEFT", 12 + #names * 27, 0)
            c.add:ClearAllPoints()
            c.add:SetPoint("LEFT", c.label, "RIGHT", 6, 0)
            local w = 12 + #names * 27 + c.label:GetStringWidth() + 6 + 20 + 30
            c:SetWidth(w)
            if x > 0 and x + w > width then x, y = 0, y + 44 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", x, -y)
            x = x + w + 8
            c:Show()
        end
        for i = #entries + 1, #chips do chips[i]:Hide() end
        if not addBtn then
            addBtn = Make("Button", area, "UIPanelButtonTemplate")
            addBtn:SetSize(80, 24)
            addBtn:SetText("+ Add")
            addBtn:SetScript("OnClick", function(self)
                Kit.OpenSearch(self, { sources = { "spells" }, exists = Exists, onPick = function(name)
                    table.insert(list(), name)
                    Changed()
                end })
            end)
            Tooltip(addBtn, "Add a reminder", "Search your spellbook. Add more alternatives to it afterwards with + in its box.")
        end
        if x > 0 and x + 80 > width then x, y = 0, y + 44 end
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", x, -y - 6)
        b:SetHeight(top + y + 40)
    end
    area:SetScript("OnSizeChanged", function() if list() then Update(); page:Layout() end end)
    self:OnRefresh(function() if list() then Update() end end)
    b.Update = Update
    return b
end
