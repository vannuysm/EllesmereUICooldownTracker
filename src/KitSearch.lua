-- Shared search popup for adding spell and item entries.
local _, ns = ...
local Kit = ns.Kit
local Make = Kit.Make
local QUESTION = 134400

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

    -- The spellbook and bags are scanned once per opening, not on every keystroke.
    function f:Catalog(source)
        self.catalog[source] = self.catalog[source] or (source == "spells" and Kit.Spellbook() or Kit.Bags())
        return self.catalog[source]
    end
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
            if src == "spells" then scan(self:Catalog("spells"), "FROM YOUR SPELLBOOK", function(e) return e.rank and ("Rank " .. e.rank) or "" end, "spells")
            elseif src == "items" then scan(self:Catalog("items"), "FROM YOUR BAGS", function(e) return e.count .. " in bags" end, "items") end
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
    search.catalog = {}
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
