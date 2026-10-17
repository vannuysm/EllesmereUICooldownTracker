-- Blizzard profile editor.
local _, ns = ...
local Kit = ns.Kit
local Make = Kit.Make
local Page = Kit.Page
local PAD = 16
local Heading = Kit.Heading

-- Profiles --------------------------------------------------------------------------------------------------------------
-- snapshot/apply return nil plus an error on failure. import(raw, choice) stores a decoded profile and announces the
-- store change itself; it returns the stored name, or nil, an error and the duplicate name when one collides.
-- opts = { tag = "FCT1", store = fn() -> table name -> data, snapshot, apply, import, onChange, onStoreChange, onSave }
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
        local validName, nameError = ns.ProfileValidation.ValidateName(name)
        if not validName then Say("Could not save: " .. nameError, 1, 0.5, 0.3) return end
        local candidate, err = opts.snapshot()
        if not candidate then Say("Could not save: " .. err, 1, 0.5, 0.3) return end
        opts.store()[name] = candidate
        if opts.onSave then opts.onSave(name) end
        nameBox:SetText("")
        nameBox:ClearFocus()
        Say("Saved \"" .. name .. "\".", 0.4, 1, 0.4)
        Update()
        if opts.onStoreChange then opts.onStoreChange() end
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

    local conflict = self:AddBlock(120, 8)
    local conflictTop = Heading(conflict, "Duplicate profile", "Overwrite replaces the saved profile. Keep both adds the import with a unique name.")
    conflict:SetHeight(conflictTop + 76)
    local conflictName = conflict:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    conflictName:SetPoint("TOPLEFT", PAD, -conflictTop)
    conflictName:SetPoint("TOPRIGHT", -PAD, -conflictTop)
    conflictName:SetJustifyH("LEFT")
    conflictName:SetWordWrap(true)
    local pendingImport
    local function CancelImport()
        pendingImport = nil
        conflict:Hide()
        page:Layout()
    end
    conflict:Hide()
    text:HookScript("OnTextChanged", function()
        if pendingImport and text:GetText() ~= pendingImport.raw then
            CancelImport()
            istatus:SetText("Import text changed. Click Import again.")
            istatus:SetTextColor(1, 1, 1)
        end
    end)

    local function Share(name)
        local validName, nameError = ns.ProfileValidation.ValidateName(name)
        if not validName then Say("Could not share: " .. nameError, 1, 0.5, 0.3) return end
        local candidate, err = ns.ProfileValidation.Validate(opts.store()[name])
        if not candidate then Say("Could not share: " .. err, 1, 0.5, 0.3) return end
        local raw = opts.tag .. ":" .. Kit.Encode({ name = name, data = candidate })
        if #raw > ns.ProfileValidation.Limits.input then
            Say("Could not share: profile text exceeds " .. ns.ProfileValidation.Limits.input .. " bytes.", 1, 0.5, 0.3) return
        end
        text:SetText(raw)
        text:SetFocus()
        text:HighlightText()
        istatus:SetText("Ctrl+C to copy")
        istatus:SetTextColor(0.4, 1, 0.4)
    end
    local function Import(choice)
        local raw = pendingImport and pendingImport.raw or (text:GetText() or "")
        local name, err, duplicate = opts.import(raw, choice)
        if duplicate then
            pendingImport = { raw = raw }
            conflictName:SetText('A profile named "' .. duplicate .. '" already exists. Choose what to do with this import:')
            conflict:Show()
            page:Layout()
            istatus:SetText("Choose Overwrite or Keep both below.")
            istatus:SetTextColor(1, 0.8, 0.3)
            return
        end
        if not name then
            istatus:SetText("Could not import: " .. err)
            istatus:SetTextColor(1, 0.5, 0.3)
            return
        end
        CancelImport()
        text:SetText("")
        text:ClearFocus()
        istatus:SetText("Added \"" .. name .. "\". Load it above.")
        istatus:SetTextColor(0.4, 1, 0.4)
        Update()
    end
    import:SetScript("OnClick", function() Import() end)
    for i, info in ipairs({ { "Overwrite", "overwrite" }, { "Keep both", "keep" }, { "Cancel" } }) do
        local button = Make("Button", conflict, "UIPanelButtonTemplate")
        button:SetSize(100, 22)
        button:SetPoint("BOTTOMLEFT", PAD + (i - 1) * 108, 4)
        button:SetText(info[1])
        local choice = info[2]
        button:SetScript("OnClick", function()
            if not pendingImport then return end
            if choice then Import(choice)
            else
                CancelImport()
                istatus:SetText("Import cancelled.")
                istatus:SetTextColor(1, 1, 1)
            end
        end)
    end

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
            local badge = opts.badge and opts.badge(opts.store()[name])
            r.badge:SetShown(badge and badge.atlas and pcall(r.badge.SetAtlas, r.badge, badge.atlas) or false)
            r.from:SetText(badge and badge.text or "")
            r.load:SetScript("OnClick", function()
                local ok, err = opts.apply(opts.store()[name], name)
                if not ok then Say("Could not load: " .. err, 1, 0.5, 0.3) return end
                Say("Loaded \"" .. name .. "\".", 0.4, 1, 0.4)
                if opts.onChange then opts.onChange() end
            end)
            r.share:SetScript("OnClick", function() Share(name) end)
            r.del:SetScript("OnClick", function()
                opts.store()[name] = nil
                Say("Deleted \"" .. name .. "\".")
                Update()
                if opts.onStoreChange then opts.onStoreChange() end
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
