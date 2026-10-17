-- Ellesmere profile library and transfer pages. Saved state belongs to Profiles.lua.
local _, ns = ...
local EUI = EllesmereUI
if not (EUI and EUI.RegisterPlugin) then return end
local P = ns.Profiles
local ProfileUI = {}
ns.ProfileUI = ProfileUI
local state = { importRaw = "", exportRaw = "", exportSource = 0 }
local dialog, menu
local function Refresh() P.LibraryChanged() end
local function Font(parent, size, text)
    local label = EUI.MakeFont(parent, size, nil, 1, 1, 1, 0.9)
    label:SetText(text or "")
    return label
end
local function Button(parent, text, callback, width)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 140, 28)
    local _, _, label = EUI.MakeStyledButton(button, text, 12, EUI.RB_COLOURS, callback)
    button.profileLabel = label
    return button
end
local function CloseDialog() if dialog then dialog:Hide() end end
local function CloseMenu() if menu then menu:Hide() end end
function ProfileUI.Close() CloseDialog(); CloseMenu() end

local function Overlay(name)
    local overlay = CreateFrame("Frame", name, UIParent)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG"); overlay:SetFrameLevel(190)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function(self) self:Hide() end)
    overlay:SetScript("OnUpdate", function(self)
        if state.host and not state.host:IsShown() then self:Hide() end
    end)
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = name
    overlay:Hide()
    return overlay
end

local function ShowDialog(title, message, buttons, initialName)
    CloseMenu()
    if not dialog then
        dialog = Overlay("EUICT_ProfileDialog")
        local shade = dialog:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, 0.45)
        local box = ns.Kit.Box(dialog, { 0.08, 0.08, 0.08, 1 }, { 1, 1, 1, 0.2 })
        box:SetPoint("CENTER"); box:SetWidth(500); box:EnableMouse(true)
        box:SetFrameLevel(191)
        dialog.box = box
        dialog.title = Font(box, 16); dialog.title:SetPoint("TOPLEFT", 16, -16)
        dialog.body = Font(box, 12)
        dialog.body:SetPoint("TOPLEFT", 16, -44); dialog.body:SetPoint("TOPRIGHT", -16, -44)
        dialog.body:SetHeight(76); dialog.body:SetJustifyH("LEFT"); dialog.body:SetJustifyV("TOP")
        dialog.body:SetWordWrap(true)
        local input = CreateFrame("EditBox", nil, box)
        input:SetPoint("TOPLEFT", 16, -128); input:SetPoint("TOPRIGHT", -16, -128); input:SetHeight(28)
        input:SetAutoFocus(false); input:SetFont(EUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, "")
        input:SetTextInsets(8, 8, 0, 0); input:SetMaxLetters(ns.ProfileValidation.Limits.name)
        EUI.MakeBorder(input, 1, 1, 1, 0.2, EUI.PanelPP)
        local bg = input:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.5)
        input:SetScript("OnEscapePressed", CloseDialog)
        input:SetScript("OnEnterPressed", function() if dialog.accept then dialog.accept(input:GetText()) end end)
        dialog.input = input
        dialog.error = Font(box, 12)
        dialog.error:SetPoint("TOPLEFT", 16, -164); dialog.error:SetPoint("TOPRIGHT", -16, -164)
        dialog.error:SetHeight(44); dialog.error:SetJustifyH("LEFT"); dialog.error:SetWordWrap(true)
        dialog.error:SetTextColor(1, 0.5, 0.3)
        dialog.buttons = {}
        dialog:SetScript("OnHide", function() input:ClearFocus(); dialog.accept = nil end)
    end
    dialog.box:SetHeight(initialName ~= nil and 260 or 224)
    dialog.error:ClearAllPoints()
    dialog.error:SetPoint("TOPLEFT", 16, initialName ~= nil and -164 or -128)
    dialog.error:SetPoint("TOPRIGHT", -16, initialName ~= nil and -164 or -128)
    dialog.title:SetText(title); dialog.body:SetText(message); dialog.error:SetText("")
    dialog.input:SetShown(initialName ~= nil)
    if initialName ~= nil then dialog.input:SetText(initialName) end
    for i, spec in ipairs(buttons) do
        local button = dialog.buttons[i]
        if not button then button = Button(dialog.box, "", function() end); dialog.buttons[i] = button end
        local callback = function() spec[2](dialog.input:GetText()) end
        button.profileLabel:SetText(spec[1]); button:SetScript("OnClick", callback)
        local width = (468 - (#buttons - 1) * 8) / #buttons
        button:ClearAllPoints(); button:SetWidth(width)
        button:SetPoint("BOTTOMLEFT", 16 + (i - 1) * (width + 8), 16); button:Show()
        if i == 1 then dialog.accept = initialName ~= nil and callback or nil end
    end
    for i = #buttons + 1, #dialog.buttons do dialog.buttons[i]:Hide() end
    dialog:Show()
    if initialName ~= nil then dialog.input:SetFocus(); dialog.input:HighlightText() end
end

local function NameDialog(title, message, initial, commit)
    ShowDialog(title, message, {
        { "Save", function(name)
            local saved, err = commit(name)
            if not saved then dialog.error:SetText(err); return end
            CloseDialog(); Refresh()
        end }, { "Cancel", CloseDialog },
    }, initial)
end
local function SaveAs()
    NameDialog("Save as profile", "Save your current settings as a new account profile and make it active on this character.", "", P.Save)
end

local function Use(name)
    local ok, err = P.Load(name)
    if ok then CloseDialog(); Refresh(); return end
    if dialog and dialog:IsShown() then dialog.error:SetText(err)
    else ShowDialog("Could not use profile", err, { { "Close", CloseDialog } }) end
end

local function ExportProfile(name)
    CloseMenu()
    state.exportSource, state.exportRaw, state.exportError = name, "", nil
    ns.Ellesmere.Open("profiles", "Import / Export")
end
local function ShowMenu(anchor, name)
    if not menu then
        menu = Overlay("EUICT_ProfileMenu")
        menu.box = ns.Kit.Box(menu, { 0.08, 0.08, 0.08, 1 }, { 1, 1, 1, 0.2 })
        menu.box:SetSize(170, 152); menu.box:SetFrameLevel(191); menu.box:EnableMouse(true)
        menu.box:SetClampedToScreen(true)
        menu.buttons = {}
    end
    menu.box:ClearAllPoints(); menu.box:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    local actions = {
        { "Rename", function()
            CloseMenu()
            NameDialog("Rename profile", 'Choose a new name for "' .. name .. '".', name, function(newName) return P.Rename(name, newName) end)
        end },
        { "Duplicate", function()
            CloseMenu()
            NameDialog("Duplicate profile", 'Create a separate copy of "' .. name .. '". Your active profile stays the same.', "", function(newName) return P.Duplicate(name, newName) end)
        end },
        { "Export", function() ExportProfile(name) end },
        { "Delete", function()
            CloseMenu()
            ShowDialog("Delete profile", 'Delete "' .. name .. '" from the account library? Characters using it will keep their current settings.', {
                { "Delete", function()
                    local ok, err = P.Delete(name)
                    if not ok then dialog.error:SetText(err); return end
                    CloseDialog(); Refresh()
                end }, { "Cancel", CloseDialog },
            })
        end },
    }
    for i, action in ipairs(actions) do
        if not menu.buttons[i] then menu.buttons[i] = Button(menu.box, "", function() end, 154) end
        local button = menu.buttons[i]
        button.profileLabel:SetText(action[1]); button:SetScript("OnClick", action[2])
        button:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 36)
    end
    menu:Show()
end

function ProfileUI.UpdateHeader()
    local banner = state.banner
    if not banner or not banner:IsShown() then return end
    local active = P.Active()
    banner.title:SetText(active and ('Active profile: ' .. active) or "Current settings - no saved profile")
    banner.note:SetText("Settings changes automatically save to the active profile.")
end

function ProfileUI.BuildHeader(frame)
    for _, preview in pairs(frame.euictPreviews or {}) do preview:Hide() end
    local banner = frame.euictProfileHeader
    if not banner then
        banner = CreateFrame("Frame", nil, frame); frame.euictProfileHeader = banner
        banner:SetPoint("TOPLEFT", 16, -8); banner:SetPoint("TOPRIGHT", -16, -8); banner:SetHeight(92)
        banner.title = Font(banner, 15)
        banner.title:SetPoint("TOPLEFT", 0, 0); banner.title:SetPoint("TOPRIGHT", 0, 0)
        banner.title:SetJustifyH("LEFT"); banner.title:SetWordWrap(false)
        banner.note = Font(banner, 11); banner.note:SetPoint("TOPLEFT", 0, -24)
        banner.saveAs = Button(banner, "Save as...", function() SaveAs() end)
        banner.saveAs:SetPoint("BOTTOMLEFT", 0, 4)
    end
    state.banner = banner
    banner:Show()
    ProfileUI.UpdateHeader()
    return 108
end

function ProfileUI.BuildPage(pageName, parent, y)
    state.host = parent
    local pad, W = EUI.CONTENT_PAD or 45, EUI.Widgets
    local function Note(text, height)
        local label = Font(parent, 12, text)
        label:SetPoint("TOPLEFT", pad, y - 6); label:SetPoint("TOPRIGHT", -pad, y - 6)
        label:SetHeight(height - 12); label:SetJustifyH("LEFT"); label:SetJustifyV("TOP"); label:SetWordWrap(true)
        y = y - height
        return label
    end
    local function Section(text) local _, h = W:SectionHeader(parent, text, y); y = y - h end
    local function Buttons(specs)
        local width = math.max(100, (parent:GetWidth() - 2 * pad - (#specs - 1) * 8) / #specs)
        for i, spec in ipairs(specs) do
            local button = Button(parent, spec[1], spec[2], width)
            button:SetPoint("TOPLEFT", pad + (i - 1) * (width + 8), y)
        end
        y = y - 40
    end
    local function Input(field, height, editable)
        local box = ns.Kit.Box(parent, { 0, 0, 0, 0.5 }, { 1, 1, 1, 0.2 })
        box:SetPoint("TOPLEFT", pad, y); box:SetPoint("TOPRIGHT", -pad, y); box:SetHeight(height)
        local scroll = ns.Kit.Make("ScrollFrame", box, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
        local input = CreateFrame("EditBox", nil, scroll)
        input:SetMultiLine(true); input:SetAutoFocus(false); input:SetFont(EUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, "")
        input:SetWidth(400); scroll:SetScrollChild(input)
        local function FocusInput(_, button)
            if button == "LeftButton" then
                input:SetFocus()
                if not editable then input:HighlightText() end
            end
        end
        box:EnableMouse(true); box:SetScript("OnMouseDown", FocusInput)
        scroll:EnableMouse(true); scroll:SetScript("OnMouseDown", FocusInput)
        scroll:SetScript("OnSizeChanged", function(_, width) if width and width > 0 then input:SetWidth(width) end end)
        input:SetText(state[field]); input:SetScript("OnEscapePressed", input.ClearFocus)
        if not editable then
            input:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
            input:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
        end
        input:SetScript("OnTextChanged", function(self, userInput)
            if editable then
                state[field] = self:GetText()
                state.importError = nil
                if state.importFeedback then state.importFeedback:SetText("") end
            elseif userInput then self:SetText(state[field]) end
        end)
        y = y - height - 8
        return input
    end
    if pageName == "Profiles" then
        Section("SAVED PROFILES")
        Buttons({ { "New profile", function() SaveAs() end } })
        local names, active = P.Names(), P.Active()
        if #names == 0 then Note("No saved profiles yet. Save your current settings or import a profile on the Import / Export tab.", 54) end
        for _, name in ipairs(names) do
            local row = ns.Kit.Box(parent, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 })
            row:SetPoint("TOPLEFT", pad, y); row:SetPoint("TOPRIGHT", -pad, y); row:SetHeight(44)
            local more = Button(row, "...", function() end, 30); more:SetPoint("RIGHT", -8, 0)
            more:SetScript("OnClick", function() ShowMenu(more, name) end)
            local use = Button(row, "Use", function() Use(name) end, 60)
            use:SetPoint("RIGHT", more, "LEFT", -8, 0); use:SetEnabled(name ~= active)
            use:SetAlpha(name == active and 0.4 or 1)
            local status = Font(row, 11, name == active and "Active" or "")
            status:SetPoint("RIGHT", use, "LEFT", -8, 0); status:SetWidth(64)
            local data = ns.Database.ProfileStore()[name]
            local class = type(data) == "table" and data._class
            local className = ns.ProfileValidation.IsClass(class) and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class) or ""
            local badge = Font(row, 11, className); badge:SetPoint("RIGHT", status, "LEFT", -8, 0); badge:SetWidth(86)
            local label = Font(row, 13, name)
            label:SetPoint("LEFT", 10, 0); label:SetPoint("RIGHT", badge, "LEFT", -12, 0)
            label:SetJustifyH("LEFT"); label:SetWordWrap(false)
            ns.Kit.Tooltip(row, name, className ~= "" and className or "Saved account profile")
            row:SetMouseMotionEnabled(true)
            row:HookScript("OnHide", CloseMenu)
            y = y - 48
        end
        Note("Settings changes automatically save to your active profile. Other characters pick up shared changes when they log in or use the profile again. Screen positions stay with each character.", 68)
    else
        Section("EXPORT")
        local values, order = { [0] = "Current settings" }, { 0 }
        for _, name in ipairs(P.Names()) do values[name], order[#order + 1] = name, name end
        if state.exportSource ~= 0 and ns.Database.ProfileStore()[state.exportSource] == nil then
            state.exportSource, state.exportRaw, state.exportError = 0, "", nil
        end
        local output, exportFeedback
        local exportHelp = "Select a profile, then press Ctrl+C to copy. Click the text to select it again.\n"
            .. "Current settings exports this character's setup. Choose a saved profile to export its shared setup."
        local function UpdateExportFeedback()
            if not exportFeedback then return end
            exportFeedback:SetText(state.exportError or exportHelp)
            if state.exportError then exportFeedback:SetTextColor(1, 0.5, 0.3)
            else exportFeedback:SetTextColor(1, 1, 1, 0.9) end
        end
        local function Export(source, selectText)
            state.exportSource = source
            local current = state.exportSource == 0
            local name = current and (P.Active() or "Current settings") or state.exportSource
            local raw, err = P.Export(name, current)
            state.exportRaw = raw or ""
            state.exportError = not raw and ("Could not export: " .. err) or nil
            if output then
                output:SetText(state.exportRaw)
                output:GetParent():SetVerticalScroll(0)
                if raw and selectText then output:SetFocus(); output:HighlightText()
                elseif not raw then output:ClearFocus() end
            end
            UpdateExportFeedback()
        end
        Export(state.exportSource)
        local _, h = W:Dropdown(parent, "Profile", y, values, function() return state.exportSource end,
            function(source) Export(source, true) end, order)
        y = y - h
        output = Input("exportRaw", 100, false)
        exportFeedback = Note("", 60)
        UpdateExportFeedback()
        Section("IMPORT")
        Note("Compatible with profiles exported by Forever Cooldown Tracker (FCPT). Paste a profile to preview its name, class and tracked entries before importing.", 46)
        local input = Input("importRaw", 140, true)
        local importFeedback
        local function Import(raw, choice)
            local name, err, duplicate = P.Import(raw, choice)
            if name then
                state.importRaw, state.lastImported = "", name
                state.importError = nil
                CloseDialog(); Refresh()
            elseif duplicate then
                ShowDialog("Duplicate profile", 'A profile named "' .. duplicate .. '" already exists. Overwrite replaces it; Keep both creates a unique name.', {
                    { "Overwrite", function() Import(raw, "overwrite") end },
                    { "Keep both", function() Import(raw, "keep") end }, { "Cancel", CloseDialog },
                })
            elseif dialog and dialog:IsShown() then dialog.error:SetText(err)
            else
                state.importError = "Could not import: " .. err
                importFeedback:SetText(state.importError)
            end
        end
        Buttons({ { "Preview import", function()
            local raw = input:GetText()
            local candidate, err = ns.ProfileCodec.Decode(raw)
            if not candidate then
                state.importError = "Could not import: " .. err
                importFeedback:SetText(state.importError)
                return
            end
            state.importError = nil; importFeedback:SetText("")
            local data, class = candidate.data, candidate.data._class
            local className = ns.ProfileValidation.IsClass(class) and (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class) or "Not specified"
            local summary = ('Name: %s\nClass: %s\nTracked: %d cooldowns, %d buffs, %d reminders\nImporting adds this profile to the library.'):format(candidate.name, className, #data.cd.spells, #data.buff.spells, #data.remind.self + #data.remind.ally)
            ShowDialog("Import profile", summary, { { "Import", function() Import(raw) end }, { "Cancel", CloseDialog } })
        end }, { "Clear", function() state.importRaw, state.importError = "", nil; Refresh() end } })
        importFeedback = Note(state.importError or "", 46)
        importFeedback:SetTextColor(1, 0.5, 0.3)
        state.importFeedback = importFeedback
        if state.lastImported and ns.Database.ProfileStore()[state.lastImported] ~= nil then
            Note('Last imported: "' .. state.lastImported .. '".', 46)
            Buttons({ { "Use now", function() Use(state.lastImported) end } })
        end
    end
    return math.abs(y)
end
