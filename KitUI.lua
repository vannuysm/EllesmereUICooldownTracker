-- Forever settings kit, part two: the icon-first pieces of a settings page. Cards, a live preview, spells and items as
-- icon tiles (drag to reorder, drop from the spellbook or bags), search-to-add with icons, icon groups for "any of
-- these" lists, and profiles that can be shared as text. Ships next to Kit.lua in every Forever addon; change it in one
-- repo, then copy it to the others.
local _, ns = ...
local Kit = ns.Kit
local Make, Tooltip = Kit.Make, Kit.Tooltip
local Page = Kit.Page

local GOLD = { 1, 0.82, 0 }
local QUESTION = 134400   -- the question-mark icon

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

-- Spells and items --------------------------------------------------------------------------------------------------
-- What an entry looks like: { name, icon, spellID, itemID, learned, count }. The game only finds learned spells by
-- name, so an icon seen once (added from search or the spellbook) is remembered in Kit.icons, which an addon may save.
Kit.icons = Kit.icons or {}
function Kit.SpellByName(name)
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and Plain(info.spellID, "number") then return info end
end

-- Every spell in the spellbook, highest rank only, passives left out: { name, icon, spellID, rank }
function Kit.Spellbook()
    local out, seen = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
    local okN, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    for l = 1, okN and Plain(lines, "number") and lines or 0 do
        local okL, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, l)
        if okL and type(line) == "table" and not line.shouldHide then
            for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local ok, it = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                if ok and type(it) == "table" and it.itemType == SPELL and not it.isPassive and Plain(it.name, "string") then
                    local rank = tonumber((Plain(it.subName, "string") and it.subName or ""):match("^%a+ (%d+)$") or "")
                    local prev = seen[it.name]
                    if not prev then
                        prev = { name = it.name, icon = it.iconID, spellID = it.spellID, rank = rank }
                        seen[it.name] = prev
                        out[#out + 1] = prev
                    elseif rank and (prev.rank or 0) < rank then
                        prev.icon, prev.spellID, prev.rank = it.iconID, it.spellID, rank
                    end
                    Kit.icons[it.name] = it.iconID
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Every item in your bags, one per name with the total count: { name, icon, itemID, count }
function Kit.Bags()
    local out, seen = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for bag = 0, 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, ok and Plain(slots, "number") and slots or 0 do
            local ok2, it = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok2 and type(it) == "table" and Plain(it.itemName, "string") then
                local e = seen[it.itemName]
                if e then e.count = e.count + (it.stackCount or 1)
                else
                    e = { name = it.itemName, icon = it.iconFileID, itemID = it.itemID, count = it.stackCount or 1 }
                    seen[it.itemName] = e
                    out[#out + 1] = e
                end
                Kit.icons[it.itemName] = it.iconFileID
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- A spell or item from the cursor (dragged from the spellbook, an action button or your bags), as a name.
function Kit.CursorName()
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or not kind then return end
    if kind == "spell" or kind == "petaction" then
        -- the spell ID is the fourth value from the spellbook, the second from an action button; any may be missing
        for _, id in pairs({ [1] = c, [2] = a, [3] = b }) do
            local okS, name = pcall(C_Spell.GetSpellName, id)
            if type(id) == "number" and okS and Plain(name, "string") then
                local okI, icon = pcall(C_Spell.GetSpellTexture, id)
                if okI and icon then Kit.icons[name] = icon end
                return name
            end
        end
    elseif kind == "item" then
        local okI, name = pcall(C_Item.GetItemNameByID, a)
        if okI and Plain(name, "string") then
            local okT, icon = pcall(C_Item.GetItemIconByID, a)
            if okT and icon then Kit.icons[name] = icon end
            return name
        end
    end
end

-- Search-to-add -----------------------------------------------------------------------------------------------------
-- One popup for every page: a search box and up to eight results with icons, grouped by where they come from.
-- opts = { sources = { "spells", "items" }, exists = fn(name) -> bool, onPick = fn(name), allowTyped = true }
local search
local function BuildSearch()
    local f = Kit.Box(UIParent, { 0.03, 0.03, 0.03, 0.97 }, { 1, 0.82, 0, 0.35 })
    f:SetSize(380, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()
    local box = Make("EditBox", f, "SearchBoxTemplate", "InputBoxTemplate")
    box:SetSize(350, 22)
    box:SetPoint("TOPLEFT", 18, -10)
    box:SetAutoFocus(false)
    if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end
    f.box = box
    f.rows = {}
    f.hot = 1
    for i = 1, 9 do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(368, 28)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.82, 0, 0.14)
        r.icon = Kit.Icon(r, 22)
        r.icon:SetPoint("LEFT", 6, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.name:SetJustifyH("LEFT")
        r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.tag:SetPoint("RIGHT", -8, 0)
        r.group = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r:SetScript("OnEnter", function() f.hot = i; f:Paint() end)
        r:SetScript("OnClick", function() f:Pick(i) end)
        f.rows[i] = r
    end
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 12, 8)
    f.foot:SetText("Enter adds the highlighted one  ·  Esc closes")

    function f:Results()
        local o, text = self.opts, (box:GetText() or ""):lower():match("^%s*(.-)%s*$")
        local out = {}
        local function scan(list, group, tag, what)
            local n, total = 0, 0
            for _, e in ipairs(list) do
                if text == "" or e.name:lower():find(text, 1, true) then
                    total = total + 1
                    if n < 4 then
                        n = n + 1
                        local taken = o.exists and o.exists(e.name)
                        out[#out + 1] = { name = e.name, icon = e.icon, group = n == 1 and group or nil,
                            tag = taken and "already added" or tag(e), taken = taken }
                    end
                end
            end
            -- only the first few show: say there are more, so it doesn't look like that's all there is
            if total > n then
                out[#out].more = text == "" and ("Showing %d of %d %s  ·  type to search them all"):format(n, total, what)
                    or ("%d more match  ·  type more to narrow it down"):format(total - n)
            end
        end
        for _, src in ipairs(o.sources or { "spells" }) do
            if src == "spells" then scan(Kit.Spellbook(), "FROM YOUR SPELLBOOK", function(e) return e.rank and ("Rank " .. e.rank) or "" end, "spells")
            elseif src == "items" then scan(Kit.Bags(), "FROM YOUR BAGS", function(e) return e.count .. " in bags" end, "items") end
        end
        local typed = (box:GetText() or ""):match("^%s*(.-)%s*$")
        local exact = false
        for _, r in ipairs(out) do if r.name:lower() == text then exact = true end end
        if o.allowTyped ~= false and typed ~= "" and not exact and #out < 9 then
            out[#out + 1] = { name = typed, icon = Kit.icons[typed] or QUESTION, group = "ADD BY NAME",
                tag = "shows once learned or carried", typed = true }
        end
        return out
    end
    function f:Paint()
        local res, y = self.results or {}, -40
        if self.hot > #res then self.hot = #res end
        if self.hot < 1 then self.hot = 1 end
        for i, r in ipairs(self.rows) do
            local e = res[i]
            r.group:Hide()
            r.more:Hide()
            if e then
                if e.group then
                    if i > 1 then y = y - 6 end
                    r.group:ClearAllPoints()
                    r.group:SetPoint("TOPLEFT", 12, y - 2)
                    r.group:SetText(e.group)
                    r.group:Show()
                    y = y - 16
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", 6, y)
                y = y - 28
                r.icon:SetTexture(e.icon or QUESTION)
                r.icon:SetDesaturated(e.taken or false)
                r.name:SetText(e.typed and ("Add \"" .. e.name .. "\"") or e.name)
                r.name:SetTextColor(e.taken and 0.5 or 1, e.taken and 0.5 or 1, e.taken and 0.5 or 1)
                r.tag:SetText(e.tag or "")
                r.hl:SetShown(i == self.hot and not e.taken)
                r:Show()
                r.more:SetShown(e.more ~= nil)
                if e.more then
                    r.more:ClearAllPoints()
                    r.more:SetPoint("TOPLEFT", 40, y - 1)
                    r.more:SetText(e.more)
                    y = y - 16
                end
            else
                r:Hide()
            end
        end
        if #res == 0 then
            self.foot:SetText("Nothing found. Type a name to add it anyway.")
        else
            self.foot:SetText("Enter adds the highlighted one  ·  Esc closes")
        end
        self:SetHeight(-y + 30)
    end
    function f:Refresh() self.results = self:Results(); self:Paint() end
    function f:Pick(i)
        local e = (self.results or {})[i]
        if not e or e.taken then return end
        if e.icon and e.icon ~= QUESTION then Kit.icons[e.name] = e.icon end
        local o = self.opts
        self:Hide()
        o.onPick(e.name)
    end
    box:HookScript("OnTextChanged", function() f.hot = 1; f:Refresh() end)
    box:SetScript("OnEnterPressed", function() f:Pick(f.hot) end)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    box:SetScript("OnArrowPressed", function(_, key)
        local step = key == "UP" and -1 or key == "DOWN" and 1 or 0
        local res = f.results or {}
        local i = f.hot
        repeat i = i + step until i < 1 or i > #res or not res[i].taken
        if i >= 1 and i <= #res then f.hot = i end
        f:Paint()
    end)
    f:SetScript("OnHide", function() box:ClearFocus() end)
    -- it belongs to the page it opened from: it closes when that page closes, or on a click anywhere else
    f:SetScript("OnUpdate", function(self) if not (self.anchor and self.anchor:IsVisible()) then self:Hide() end end)
    pcall(f.RegisterEvent, f, "GLOBAL_MOUSE_DOWN")
    f:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then self:Hide() end
    end)
    return f
end

-- anchor: the frame the popup opens under.
function Kit.OpenSearch(anchor, opts)
    search = search or BuildSearch()
    search.opts = opts
    search.anchor = anchor
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    search.box:SetText("")
    search.hot = 1
    search:Show()
    search:Refresh()
    search.box:SetFocus()
    return search
end
function Kit.Search() return search end

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
    local syncing = false
    if s.Init then
        s:Init(get() or minV, minV, maxV, math.floor((maxV - minV) / step + 0.5), {})
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            v = math.floor(v / step + 0.5) * step
            value:SetText(Kit.FormatNumber(v, step))
            if not syncing then set(v) end
        end, s)
    end
    self:OnRefresh(function()
        local v = get() or minV
        value:SetText(Kit.FormatNumber(v, step))
        if s.SetValue then syncing = true; s:SetValue(v); syncing = false end
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

-- Profiles --------------------------------------------------------------------------------------------------------------
-- Settings as text that can be pasted into chat or Discord and back: "<tag>:" followed by a Lua-like table literal.
-- Read back with a small parser (never loadstring), so a pasted string can only ever produce plain data.
local function Encode(v)
    local t = type(v)
    if t == "string" then return (("%q"):format(v):gsub("\\\n", "\\n")) end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = Encode(v[i]) end
    local keys = {}
    for k in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. Encode(k) .. "]")
        parts[#parts + 1] = key .. "=" .. Encode(v[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
Kit.Encode = Encode

function Kit.Decode(s)
    local pos = 1
    local function ws() pos = s:find("[^%s]", pos) or #s + 1 end
    local value
    local function str()
        local q = s:sub(pos, pos)
        pos = pos + 1
        local out = {}
        while pos <= #s do
            local ch = s:sub(pos, pos)
            if ch == q then pos = pos + 1; return table.concat(out) end
            if ch == "\\" then
                local nx = s:sub(pos + 1, pos + 1)
                local d = s:match("^%d%d?%d?", pos + 1)
                if d then out[#out + 1] = string.char(tonumber(d) % 256); pos = pos + 1 + #d
                else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r" })[nx] or nx; pos = pos + 2 end
            else out[#out + 1] = ch; pos = pos + 1 end
        end
        error("unfinished text")
    end
    function value(depth)
        if depth > 20 then error("too deep") end
        ws()
        local ch = s:sub(pos, pos)
        if ch == "{" then
            pos = pos + 1
            local t, i = {}, 1
            while true do
                ws()
                if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
                local key
                if s:sub(pos, pos) == "[" then
                    pos = pos + 1; key = value(depth + 1); ws()
                    if s:sub(pos, pos) ~= "]" then error("expected ]") end
                    pos = pos + 1; ws()
                    if s:sub(pos, pos) ~= "=" then error("expected =") end
                    pos = pos + 1
                else
                    local name = s:match("^[%a_][%w_]*", pos)
                    if name and name ~= "true" and name ~= "false" and s:match("^%s*=", pos + #name) then
                        key = name
                        pos = s:find("=", pos + #name, true) + 1
                    end
                end
                local v = value(depth + 1)
                if key == nil then t[i] = v; i = i + 1 else t[key] = v end
                ws()
                local sep = s:sub(pos, pos)
                if sep == "," or sep == ";" then pos = pos + 1
                elseif sep ~= "}" then error("expected , or }") end
            end
        elseif ch == "\"" or ch == "'" then return str()
        elseif s:match("^true", pos) then pos = pos + 4; return true
        elseif s:match("^false", pos) then pos = pos + 5; return false
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
            if num and num ~= "" and tonumber(num) then pos = pos + #num; return tonumber(num) end
            error("unexpected " .. (ch ~= "" and ch or "end"))
        end
    end
    local ok, v = pcall(value, 0)
    if not ok then return nil, v end
    return v
end

-- opts = { tag = "FCT1", store = fn() -> table name -> data, snapshot = fn() -> data, apply = fn(data), onChange }
function Page:Profiles(opts)
    local page = self
    -- saved profiles: one row each with Load and Delete
    local b = self:AddBlock(40, 12)
    local top = Heading(b, "Your profiles", "Shared by every character on this account. Loading one never moves anything on your screen.")
    local rows = {}
    local status = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local nameBox = Make("EditBox", b, "InputBoxTemplate")
    nameBox:SetSize(200, 22)
    nameBox:SetAutoFocus(false)
    local hint = nameBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 2, 0)
    hint:SetText("Name, e.g. Raid healing")
    nameBox:HookScript("OnTextChanged", function() hint:SetShown(nameBox:GetText() == "") end)
    local save = Make("Button", b, "UIPanelButtonTemplate")
    save:SetSize(150, 22)
    save:SetText("Save current as")
    local function Say(text, r, g, bl) status:SetText(text); status:SetTextColor(r or 1, g or 1, bl or 1) end
    local Update
    local function Save()
        local name = nameBox:GetText():match("^%s*(.-)%s*$")
        if name == "" then Say("Give the profile a name first.", 1, 0.5, 0.3) return end
        opts.store()[name] = opts.snapshot()
        nameBox:SetText("")
        nameBox:ClearFocus()
        Say("Saved \"" .. name .. "\".", 0.4, 1, 0.4)
        Update()
    end
    save:SetScript("OnClick", Save)
    nameBox:SetScript("OnEnterPressed", Save)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

    local function Row(i)
        if rows[i] then return rows[i] end
        local r = Kit.Box(b, { 1, 1, 1, i % 2 == 0 and 0.03 or 0.055 }, { 0, 0, 0, 0 })
        r:SetHeight(30)
        r:SetPoint("LEFT", PAD, 0)
        r:SetPoint("RIGHT", -PAD, 0)
        -- who made it: a class icon and name, so a mage profile is easy to tell apart on a paladin
        r.badge = r:CreateTexture(nil, "ARTWORK")
        r.badge:SetSize(20, 20)
        r.badge:SetPoint("LEFT", 8, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.name:SetPoint("LEFT", r.badge, "RIGHT", 8, 0)
        r.from = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        r.from:SetPoint("LEFT", r.name, "RIGHT", 10, 0)
        r.del = Make("Button", r, "UIPanelButtonTemplate")
        r.del:SetSize(80, 22)
        r.del:SetPoint("RIGHT", -6, 0)
        r.del:SetText(DELETE or "Delete")
        r.share = Make("Button", r, "UIPanelButtonTemplate")
        r.share:SetSize(80, 22)
        r.share:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
        r.share:SetText("Share")
        r.load = Make("Button", r, "UIPanelButtonTemplate")
        r.load:SetSize(80, 22)
        r.load:SetPoint("RIGHT", r.share, "LEFT", -6, 0)
        r.load:SetText("Load")
        rows[i] = r
        return r
    end

    -- sharing: a text box holding the profile as text, selected so Ctrl+C copies it; paste one in to import
    local sb = self:AddBlock(150, 16)
    local stop = Heading(sb, "Share and import", "Share puts a profile here as text: press Ctrl+C and paste it to a friend. To import, paste their text and press Import.")
    sb:SetHeight(150 + stop - 22)
    local box = Kit.Box(sb, { 0, 0, 0, 0.5 }, { 1, 1, 1, 0.12 })
    box:SetPoint("TOPLEFT", PAD, -stop)
    box:SetPoint("BOTTOMRIGHT", -PAD - 100, 0)
    local scroll = Make("ScrollFrame", box, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local text = CreateFrame("EditBox", nil, scroll)
    text:SetMultiLine(true)
    text:SetAutoFocus(false)
    text:SetFontObject("ChatFontNormal")
    text:SetWidth(400)
    text:SetScript("OnEscapePressed", text.ClearFocus)
    scroll:SetScrollChild(text)
    scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then text:SetWidth(w) end end)
    local import = Make("Button", sb, "UIPanelButtonTemplate")
    import:SetSize(90, 22)
    import:SetPoint("TOPRIGHT", -PAD, -stop)
    import:SetText("Import")
    local clear = Make("Button", sb, "UIPanelButtonTemplate")
    clear:SetSize(90, 22)
    clear:SetPoint("TOPRIGHT", import, "BOTTOMRIGHT", 0, -6)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() text:SetText(""); text:SetFocus() end)
    local istatus = sb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    istatus:SetPoint("TOPRIGHT", clear, "BOTTOMRIGHT", 0, -8)
    istatus:SetWidth(96)
    istatus:SetJustifyH("RIGHT")

    local function Share(name)
        text:SetText(opts.tag .. ":" .. Encode({ name = name, data = opts.store()[name] }))
        text:SetFocus()
        text:HighlightText()
        istatus:SetText("Ctrl+C to copy")
        istatus:SetTextColor(0.4, 1, 0.4)
    end
    import:SetScript("OnClick", function()
        local raw = (text:GetText() or ""):gsub("%s+$", ""):gsub("^%s+", "")
        local body = raw:match("^" .. opts.tag .. ":(.*)$")
        local v = body and Kit.Decode(body)
        if type(v) ~= "table" or type(v.data) ~= "table" then
            istatus:SetText("That isn't a profile from this addon.")
            istatus:SetTextColor(1, 0.5, 0.3)
            return
        end
        local name = type(v.name) == "string" and v.name ~= "" and v.name or "Imported"
        local base, n = name, 2
        while opts.store()[name] do name = base .. " " .. n; n = n + 1 end
        opts.store()[name] = v.data
        text:SetText("")
        text:ClearFocus()
        istatus:SetText("Added \"" .. name .. "\". Load it above.")
        istatus:SetTextColor(0.4, 1, 0.4)
        Update()
    end)

    Update = function()
        local names = {}
        for name in pairs(opts.store() or {}) do names[#names + 1] = name end
        table.sort(names)
        for i, name in ipairs(names) do
            local r = Row(i)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", PAD, -top - (i - 1) * 30)
            r:SetPoint("RIGHT", -PAD, 0)
            r.name:SetText(name)
            local b = opts.badge and opts.badge(opts.store()[name])
            r.badge:SetShown(b and b.atlas and pcall(r.badge.SetAtlas, r.badge, b.atlas) or false)
            r.from:SetText(b and b.text or "")
            r.load:SetScript("OnClick", function()
                opts.apply(opts.store()[name])
                Say("Loaded \"" .. name .. "\".", 0.4, 1, 0.4)
                if opts.onChange then opts.onChange() end
            end)
            r.share:SetScript("OnClick", function() Share(name) end)
            r.del:SetScript("OnClick", function()
                opts.store()[name] = nil
                Say("Deleted \"" .. name .. "\".")
                Update()
            end)
            r:Show()
        end
        for i = #names + 1, #rows do rows[i]:Hide() end
        local y = -top - #names * 30
        if #names == 0 then
            Say("No profiles yet. Save your current settings to make one.", 0.6, 0.6, 0.6)
            y = y - 4
        end
        nameBox:ClearAllPoints()
        nameBox:SetPoint("TOPLEFT", PAD + 8, y - 22)
        save:ClearAllPoints()
        save:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
        status:ClearAllPoints()
        if #names == 0 then status:SetPoint("TOPLEFT", PAD + 4, -top) else status:SetPoint("LEFT", save, "RIGHT", 12, 0) end
        b:SetHeight(-y + 50)
        page:Layout()
    end
    self:OnRefresh(function() if opts.store() then Update() end end)
    return b
end
