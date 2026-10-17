local ctx = ...
local M, ns, Test, widgets = ctx.mocks, ctx.ns, ctx.Test, ctx.widgets
local P, Kit = ns.Profiles, ns.Kit
local parent, header, tab
M.activeModule = "Profiles"
local function Build(page)
    if parent then parent:Hide() end
    tab = page or tab or "Profiles"
    parent = CreateFrame("Frame", nil, UIParent)
    header = header or CreateFrame("Frame", nil, UIParent)
    assert(ctx.modules.Profiles.buildPage(tab, parent, -10) > 0)
    assert(ctx.modules.Profiles.getHeaderBuilder(tab)(header, 600) > 0)
end
local function Find(root, kind, text)
    for _, child in ipairs(root.children) do
        if child:IsShown() then
            local label = child.profileLabel and child.profileLabel:GetText() or child:GetText()
            if child.kind == kind and (text == nil or label == text) then return child end
            local found = Find(child, kind, text)
            if found then return found end
        end
    end
end
local function Click(label, root)
    root = root or (EUICT_ProfileDialog and EUICT_ProfileDialog:IsShown() and EUICT_ProfileDialog)
        or (EUICT_ProfileMenu and EUICT_ProfileMenu:IsShown() and EUICT_ProfileMenu) or parent
    local button = assert(Find(root, "Button", label), label)
    assert(button:IsEnabled(), label .. " is disabled")
    M.Click(button)
end
local function Name(value)
    assert(EUICT_ProfileDialog:IsShown())
    Find(EUICT_ProfileDialog, "EditBox"):SetText(value)
    Click("Save")
end
local function Row(name) return assert(Find(parent, "FontString", name), name).parent end
local function HasText(fragment, root)
    root = root or parent
    for _, child in ipairs(root.children) do
        if child:IsShown() then
            if child.kind == "FontString" and child:GetText():find(fragment, 1, true) then return true end
            if HasText(fragment, child) then return true end
        end
    end
    return false
end
local function Input(index)
    local inputs = {}
    local function Walk(root)
        for _, child in ipairs(root.children) do
            if child.kind == "EditBox" then inputs[#inputs + 1] = child end
            Walk(child)
        end
    end
    Walk(parent)
    return assert(inputs[index])
end
local function Import(raw, choice)
    Build("Import / Export"); Input(2):SetText(raw)
    Click("Preview import"); Click("Import")
    if choice then Click(choice) end
    Build()
end

Test("library shows Active with automatic saving and no manual-save controls", function()
    Build()
    assert(not Find(parent, "EditBox") and HasText("No saved profiles"))
    assert(HasText("no saved profile", header) and not Find(header, "Button", "Save changes"))
    Click("New profile"); Name("Raid"); Build()
    assert(P.Active() == "Raid" and HasText("Active profile: Raid", header))
    assert(not Find(Row("Raid"), "Button", "Use"):IsEnabled())
    ns.Configuration.Set("cd", "size", 55); Build()
    assert(EUICT_DB.profiles.Raid.cd.size == 55 and HasText("Active", Row("Raid")))
    assert(not HasText("Modified") and not Find(header, "Button", "Save changes"))
    Click("Save as...", header); Name("Solo"); Build()
    ns.Configuration.Set("cd", "size", 60)
    assert(P.Active() == "Solo" and EUICT_DB.profiles.Solo.cd.size == 60 and EUICT_DB.profiles.Raid.cd.size == 55)
end)

Test("active identity survives reload and positions are excluded from modification and exports", function()
    assert(P.Save("Raid")); ns.TrackerFrames.SavePosition("cd", 80, 90)
    assert(EUICT_DB.profiles.Raid.cd.x == nil)
    local account, character = Kit.Encode(EUICT_DB), Kit.Encode(EUICT_DBC)
    EUICT_DB, EUICT_DBC = assert(Kit.Decode(account)), assert(Kit.Decode(character))
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(P.Active() == "Raid" and EUICT_DBC.cd.x == 80)
    local decoded = assert(ns.ProfileCodec.Decode(assert(P.Export("Raid"))))
    assert(decoded.data._activeProfile == nil and decoded.data.cd.x == nil)
end)
Test("account assignments reconcile stale character files after profile rename and deletion", function()
    assert(P.Save("Raid"))
    local previous = Kit.Encode(EUICT_DBC)
    assert(P.Rename("Raid", "Healing"))
    EUICT_DBC = assert(Kit.Decode(previous)); EUICT_DBC._savedAt = 999999
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(P.Active() == "Healing")
    assert(P.Delete("Healing"))
    EUICT_DBC = assert(Kit.Decode(previous)); EUICT_DBC._savedAt = 999999
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker")
    assert(P.Active() == nil and EUICT_DBC._activeProfile == nil)
end)
Test("using a profile switches immediately while edits remain saved to the previous profile", function()
    assert(P.Save("Raid")); assert(P.Save("Solo")); ns.Configuration.Set("cd", "size", 45)
    assert(P.Load("Raid")); ns.Configuration.Set("cd", "size", 60)
    Build(); Click("Use", Row("Solo")); Build()
    assert(not EUICT_ProfileDialog or not EUICT_ProfileDialog:IsShown())
    assert(P.Active() == "Solo" and EUICT_DBC.cd.size == 45 and EUICT_DB.profiles.Raid.cd.size == 60)
    ns.Configuration.Set("cd", "size", 62); Click("Use", Row("Raid")); Build()
    assert(P.Active() == "Raid" and EUICT_DBC.cd.size == 60 and EUICT_DB.profiles.Solo.cd.size == 62)
end)

Test("unnamed settings persist per character without creating or updating a profile", function()
    ns.Configuration.Set("cd", "size", 63)
    assert(next(EUICT_DB.profiles) == nil and P.Active() == nil)
    M.Fire("PLAYER_LOGIN"); assert(EUICT_DBC.cd.size == 63)
    assert(P.Save("Destination")); P.Associate(nil); ns.Configuration.Set("cd", "size", 60)
    assert(EUICT_DB.profiles.Destination.cd.size == 63 and EUICT_DBC.cd.size == 60)
    Build(); Click("Use", Row("Destination")); Build()
    assert(P.Active() == "Destination" and EUICT_DBC.cd.size == 63)
    assert(not EUICT_ProfileDialog or not EUICT_ProfileDialog:IsShown())
end)

Test("invalid destinations leave the current setup profile and assignment unchanged", function()
    assert(P.Save("Raid")); ns.Configuration.Set("cd", "size", 63)
    EUICT_DB.profiles.Broken = { cd = { size = 0 } }
    local library, current = Kit.Encode(EUICT_DB.profiles), Kit.Encode(EUICT_DBC)
    assert(not P.Load("Broken"))
    assert(Kit.Encode(EUICT_DB.profiles) == library and Kit.Encode(EUICT_DBC) == current and P.Active() == "Raid")
end)
Test("scalar color list mapping and rank edits automatically save detached profile data", function()
    assert(P.Save("Raid"))
    ns.Configuration.Set("cd", "orientation", "vertical")
    assert(EUICT_DB.profiles.Raid.cd.orientation == "vertical" and EUICT_DB.profiles.Raid.cd.growth == "down")
    ns.Configuration.Set("buff", "color", { r = 0.2, g = 0.3, b = 0.4, a = 0.8 })
    assert(EUICT_DB.profiles.Raid.buff.color ~= EUICT_DBC.buff.color and EUICT_DB.profiles.Raid.buff.color.r == 0.2)
    EUICT_DBC.cd.spells = { "One", "Two" }; ns.Configuration.Changed("cd", "spells")
    assert(EUICT_DB.profiles.Raid.cd.spells ~= EUICT_DBC.cd.spells and EUICT_DB.profiles.Raid.cd.spells[1] == "One")
    EUICT_DBC.cd.spells[1], EUICT_DBC.cd.spells[2] = "Two", "One"; ns.Configuration.Changed("cd", "spells")
    assert(EUICT_DB.profiles.Raid.cd.spells[1] == "Two")
    EUICT_DBC.remind.byClass.MAGE = "Blessing of Kings"; ns.Configuration.Changed("remind", "byClass")
    EUICT_DBC.ranks.keep = { "Holy Light" }; ns.Configuration.Changed("ranks", "keep")
    assert(EUICT_DB.profiles.Raid.remind.byClass.MAGE == "Blessing of Kings")
    assert(EUICT_DB.profiles.Raid.ranks.keep[1] == "Holy Light" and EUICT_DB.profiles.Raid.ranks.keep ~= EUICT_DBC.ranks.keep)
end)
Test("positions runtime events refreshes and temporary editing do not overwrite a shared profile", function()
    assert(P.Save("Raid"))
    assert(P.Import('FCT1:{name="Raid",data={cd={size=60,visibility="always"}}}', "overwrite"))
    local saved = EUICT_DB.profiles.Raid
    ns.TrackerFrames.SavePosition("cd", 80, 90)
    ns.Configuration.Changed("cd", "editing")
    M.Fire("UNIT_AURA", "player", { isFullUpdate = true })
    M.Fire("SPELL_UPDATE_COOLDOWN"); M.Flush()
    assert(EUICT_DB.profiles.Raid == saved and saved.cd.x == nil and saved.cd.size == 60)
    assert(EUICT_DBC.cd.size ~= 60)
    M.Fire("PLAYER_LOGIN")
    assert(EUICT_DB.profiles.Raid == saved and EUICT_DBC.cd.size == 60 and EUICT_DBC.cd.x == 80)
    assert(EUICT_CD:GetHeight() == 60)
end)
Test("automatic saving preserves unapplied imported fields and coherent orientation growth", function()
    assert(P.Save("Raid"))
    assert(P.Import('FCT1:{name="Raid",data={_class="HUNTER",cd={size=60,orientation="vertical",growth="up"},buff={spells={"Shared buff"}}}}', "overwrite"))
    ns.Configuration.Set("cd", "gap", 6)
    local saved = EUICT_DB.profiles.Raid
    assert(saved.cd.gap == 6 and saved.cd.size == 60 and saved.cd.orientation == "vertical")
    assert(saved.buff.spells[1] == "Shared buff" and saved._class == "HUNTER")
    ns.Configuration.Set("cd", "growth", "left")
    saved = EUICT_DB.profiles.Raid
    assert(saved.cd.orientation == "horizontal" and saved.cd.growth == "left")
    assert(saved.cd.size == 60 and saved.buff.spells[1] == "Shared buff" and saved._class == "HUNTER")
    assert(ns.ProfileValidation.Validate(saved))
end)
Test("another character loads the latest shared setup on login while retaining personal positions", function()
    assert(P.Save("Raid"))
    local other = assert(Kit.Decode(Kit.Encode(EUICT_DBC)))
    other._owner, other._savedAt, other.cd.size, other.cd.x, other.cd.y = "other-character", 999999, 42, 125, 250
    EUICT_DB.chars["other-character"] = other
    ns.Database.ProfileAssignments()["other-character"] = "Raid"
    ns.Configuration.Set("cd", "size", 60)
    assert(other.cd.size == 42)
    local account, character = Kit.Encode(EUICT_DB), Kit.Encode(other)
    EUICT_DB, EUICT_DBC = assert(Kit.Decode(account)), assert(Kit.Decode(character))
    UnitGUID = function() return "other-character" end
    M.Fire("ADDON_LOADED", "EllesmereUICooldownTracker"); M.Fire("PLAYER_LOGIN")
    assert(P.Active() == "Raid" and EUICT_DBC.cd.size == 60 and EUICT_DBC.cd.x == 125 and EUICT_DBC.cd.y == 250)
    assert(EUICT_DB.chars["test-character"] ~= EUICT_DBC)
    ns.Configuration.Set("cd", "gap", 10)
    assert(EUICT_DB.profiles.Raid.cd.gap == 10 and EUICT_DB.chars["test-character"].cd.gap ~= 10)
end)
Test("invalid automatic saves and invalid login profiles retain saved data and current settings", function()
    assert(P.Save("Raid")); local saved = EUICT_DB.profiles.Raid
    EUICT_DBC.cd.size = 0; ns.Configuration.Changed("cd", "size")
    assert(EUICT_DB.profiles.Raid == saved and M.messages[#M.messages]:find("Could not automatically save", 1, true))
    ns.Configuration.Set("cd", "size", 48)
    assert(EUICT_DB.profiles.Raid.cd.size == 48)
    EUICT_DB.profiles.Raid = { cd = { size = 0 } }; saved = EUICT_DB.profiles.Raid
    M.Fire("PLAYER_LOGIN")
    assert(EUICT_DB.profiles.Raid == saved and EUICT_DBC.cd.size == 48)
    assert(M.messages[#M.messages]:find("Could not restore", 1, true))
end)
Test("discarding unlock resizing restores both character and automatically saved dimensions", function()
    assert(P.Save("Raid")); local size = EUICT_DBC.cd.size
    M.unlockListener(true)
    ns.Configuration.Set("cd", "size", 60)
    assert(EUICT_DB.profiles.Raid.cd.size == 60)
    M.unlockListener(false, "discard")
    assert(EUICT_DBC.cd.size == size and EUICT_DB.profiles.Raid.cd.size == size)
end)
Test("automatic saves from Ellesmere controls and slash commands preserve continuous widgets", function()
    assert(P.Save("Raid")); M.activeModule = "CooldownBar"
    ctx.modules.CooldownBar.buildPage("Display", CreateFrame("Frame"), 0)
    local before = M.pageRefreshes
    widgets["Icon size"].args[5](47)
    assert(EUICT_DB.profiles.Raid.cd.size == 47 and M.pageRefreshes == before)
    widgets.Orientation.args[3]("vertical")
    assert(EUICT_DB.profiles.Raid.cd.orientation == "vertical" and EUICT_DB.profiles.Raid.cd.growth == "down")
    assert(M.pageRefreshes == before + 1)
    SlashCmdList.EUICT("cdsize 48"); assert(EUICT_DB.profiles.Raid.cd.size == 48)
    SlashCmdList.EUICT("cdsize 999"); assert(EUICT_DB.profiles.Raid.cd.size == 48)
end)

Test("row menus duplicate rename export and delete without changing other characters settings", function()
    assert(P.Save("Raid")); Build()
    Click("...", Row("Raid")); Click("Duplicate"); Name("Copy"); Build()
    assert(P.Active() == "Raid" and EUICT_DB.profiles.Copy.cd ~= EUICT_DB.profiles.Raid.cd)
    EUICT_DB.chars.other = { _activeProfile = "Raid", cd = { size = 42 } }
    Click("...", Row("Raid")); Click("Rename"); Name("Healing"); Build()
    assert(P.Active() == "Healing" and EUICT_DB.chars.other._activeProfile == "Healing")
    local opened
    EllesmereUI.OpenPlugin = function(_, module, page) opened = { module, page }; return true end
    Click("...", Row("Copy")); Click("Export")
    assert(opened[2] == "Import / Export")
    Build("Import / Export"); assert(widgets["Profile"].args[2]() == "Copy")
    assert(ns.ProfileCodec.Decode(Input(1):GetText()).name == "Copy")
    Build("Profiles"); local before = EUICT_DBC.cd.size
    Click("...", Row("Healing")); Click("Delete"); Click("Cancel"); assert(P.Active() == "Healing")
    Click("...", Row("Healing")); Click("Delete"); Click("Delete"); Build()
    assert(not P.Active() and not EUICT_DB.profiles.Healing and EUICT_DBC.cd.size == before)
    assert(EUICT_DB.chars.other._activeProfile == nil and EUICT_DB.chars.other.cd.size == 42)
end)
Test("name collisions leave the name dialog open and active identity unchanged", function()
    assert(P.Save("Raid")); assert(P.Save("Solo")); Build()
    Click("Save as...", header); Name("Raid")
    assert(EUICT_ProfileDialog:IsShown() and P.Active() == "Solo" and HasText("already exists", EUICT_ProfileDialog))
    Name("New"); Build(); assert(P.Active() == "New")
    assert(not P.Rename("New", "Solo") and not P.Duplicate("New", "Solo") and not P.Rename("New", "\n"))
end)
Test("export distinguishes current setup from an inactive saved profile", function()
    assert(P.Save("Raid")); local savedSize = EUICT_DB.profiles.Raid.cd.size
    assert(P.Save("Solo")); ns.Configuration.Set("cd", "size", 63)
    Build("Import / Export")
    local output = Input(1); local decoded = assert(ns.ProfileCodec.Decode(output:GetText()))
    assert(decoded.name == "Solo" and decoded.data.cd.size == 63 and not output.focused and HasText("Ctrl+C"))
    widgets["Profile"].args[3]("Raid")
    decoded = assert(ns.ProfileCodec.Decode(Input(1):GetText()))
    assert(decoded.data.cd.size == savedSize and output.focused and output.highlighted)
    Build(); assert(ns.ProfileCodec.Decode(Input(1):GetText()))
end)

Test("selecting an export profile fills text immediately without rebuilding or disturbing the import draft", function()
    assert(P.Save("Raid"))
    Build("Import / Export")
    assert(widgets["Profile"] and not Find(parent, "Button", "Generate export"))
    local output, input, refreshes = Input(1), Input(2), M.pageRefreshes
    input:SetText("unfinished import")
    ns.Configuration.Set("cd", "size", 63)
    refreshes = M.pageRefreshes
    widgets["Profile"].args[3]("Raid")
    assert(Input(1) == output and M.pageRefreshes == refreshes and input:GetText() == "unfinished import")
    assert(ns.ProfileCodec.Decode(output:GetText()).data.cd.size == EUICT_DB.profiles.Raid.cd.size)
    assert(output.focused and output.highlighted)
    widgets["Profile"].args[3](0)
    assert(ns.ProfileCodec.Decode(output:GetText()).data.cd.size == 63)
    output.highlighted = false; output.scripts.OnMouseUp(output)
    assert(output.focused and output.highlighted)
end)
Test("invalid export selection clears old text and deleted selection falls back to current settings", function()
    assert(P.Save("Raid"))
    Build("Import / Export")
    widgets["Profile"].args[3]("Raid")
    assert(ns.ProfileCodec.Decode(Input(1):GetText()).name == "Raid")
    EUICT_DB.profiles.Broken = { cd = { spells = 1 } }
    widgets["Profile"].args[3]("Broken")
    assert(Input(1):GetText() == "" and not Input(1).focused and HasText("Could not export:"))
    widgets["Profile"].args[3]("Raid")
    assert(not HasText("Could not export:") and ns.ProfileCodec.Decode(Input(1):GetText()).name == "Raid")
    assert(P.Delete("Raid")); Build()
    assert(widgets["Profile"].args[2]() == 0)
    assert(ns.ProfileCodec.Decode(Input(1):GetText()).name == "Current settings")
end)
Test("import preview shows name class and counts before writing and activation is optional", function()
    assert(P.Save("Current")); local current = Kit.Encode(EUICT_DBC)
    LOCALIZED_CLASS_NAMES_MALE = { HUNTER = "Hunter" }
    local raw = 'FCT1:{name="Hunter",data={_class="HUNTER",cd={spells={"One","Two"},size=60},buff={spells={}},remind={self={},ally={}}}}'
    Build("Import / Export"); Input(2):SetText(raw); Click("Preview import")
    assert(not EUICT_DB.profiles.Hunter and HasText("Name: Hunter", EUICT_ProfileDialog))
    assert(HasText("Class: Hunter", EUICT_ProfileDialog))
    assert(HasText("Tracked: 2 cooldowns, 0 buffs, 0 reminders", EUICT_ProfileDialog))
    Click("Cancel"); assert(Input(2):GetText() == raw)
    Click("Preview import"); Click("Import"); Build()
    assert(EUICT_DB.profiles.Hunter and Kit.Encode(EUICT_DBC) == current and Input(2):GetText() == "")
    Click("Use now"); Build(); assert(P.Active() == "Hunter" and EUICT_DBC.cd.size == 60)
end)
Test("duplicate imports preserve current settings for overwrite keep both and cancel", function()
    assert(P.Save("Raid")); local original = EUICT_DB.profiles.Raid
    local raw = 'FCT1:{name="Raid",data={cd={size=60}}}'
    Import(raw); assert(EUICT_DB.profiles.Raid == original and HasText("already exists", EUICT_ProfileDialog))
    Click("Cancel"); assert(Input(2):GetText() == raw)
    Import(raw, "Keep both"); assert(EUICT_DB.profiles.Raid == original and EUICT_DB.profiles["Raid 2"].cd.size == 60)
    local current = Kit.Encode(EUICT_DBC)
    Import(raw, "Overwrite")
    assert(EUICT_DB.profiles.Raid ~= original and EUICT_DB.profiles.Raid.cd.size == 60)
    assert(Kit.Encode(EUICT_DBC) == current and P.Active() == "Raid")
end)
Test("invalid import and oversized export preserve the input draft and data", function()
    assert(P.Save("Current"))
    local raw = 'FCT1:{name="Broken",data={cd={spells=1}}}'
    Build("Import / Export"); Input(2):SetText(raw)
    local library, current = Kit.Encode(EUICT_DB.profiles), Kit.Encode(EUICT_DBC)
    Click("Preview import"); Build()
    assert(Input(2):GetText() == raw and HasText("cd.spells"))
    assert(Kit.Encode(EUICT_DB.profiles) == library and Kit.Encode(EUICT_DBC) == current)
    local data = { cd = { spells = {} } }
    for i = 1, 130 do data.cd.spells[i] = string.rep("x", 1006) end
    EUICT_DB.profiles.Large = data
    widgets["Profile"].args[3]("Large"); Build(); Build()
    assert(HasText("Could not export") and Input(2):GetText() == raw and EUICT_DB.profiles.Large == data)
end)
Test("maximum names and occupied suffixes stay exportable after keep both", function()
    local name = string.rep("N", ns.ProfileValidation.Limits.name)
    local raw = "FCT1:" .. Kit.Encode({ name = name, data = {} })
    assert(P.Import(raw) == name)
    local imported, err, conflict = P.Import(raw); assert(not imported and err and conflict == name)
    local duplicate = assert(P.Import(raw, "keep"))
    assert(#duplicate == #name and ns.ProfileCodec.Decode(assert(P.Export(duplicate))).name == duplicate)
    assert(P.Import(raw, "keep"):sub(-2) == " 3" and not P.Import(raw, "unexpected"))
end)
Test("overwriting an active profile stays unapplied until optional Use now", function()
    assert(P.Save("Raid")); local size = EUICT_DBC.cd.size
    EUICT_DB.chars.other = { _activeProfile = "Raid", cd = { size = 42 } }
    Import('FCT1:{name="Raid",data={cd={size=60}}}', "Overwrite")
    assert(EUICT_DBC.cd.size == size and P.Active() == "Raid")
    Build("Profiles"); assert(not Find(Row("Raid"), "Button", "Use"):IsEnabled() and HasText("Active", Row("Raid")))
    Build("Import / Export"); Click("Use now"); Build()
    assert(P.Active() == "Raid" and EUICT_DBC.cd.size == 60 and EUICT_DB.chars.other.cd.size == 42)
end)

Test("standalone actions synchronize active identity and integrated library caches", function()
    local page = ns.SettingsUI.pages.profiles
    local library, import, conflict = page.blocks[1], page.blocks[2], page.blocks[3]
    local before = M.invalidated.Profiles or 0
    local input = M.Find(import, "EditBox")
    input:SetText('FCT1:{name="Standalone",data={}}'); M.Click(M.Find(import, "Button", "Import"))
    assert(M.invalidated.Profiles == before + 1)
    Build(); assert(Row("Standalone"))
    local row = M.Find(library, "FontString", "Standalone").parent
    M.Click(row.load); assert(P.Active() == "Standalone")
    input:SetText('FCT1:{name="Standalone",data={cd={size=60}}}'); M.Click(M.Find(import, "Button", "Import"))
    M.Click(M.Find(conflict, "Button", "Cancel")); assert(EUICT_DB.profiles.Standalone.cd.size ~= 60)
    M.Click(M.Find(import, "Button", "Import")); M.Click(M.Find(conflict, "Button", "Overwrite"))
    assert(P.Active() == "Standalone" and EUICT_DB.profiles.Standalone.cd.size == 60)
end)
Test("two registered tabs and slash shortcut open the library and dialogs close on module leave", function()
    local module, opened = ctx.modules.Profiles
    assert(module.pages[1] == "Profiles" and module.pages[2] == "Import / Export")
    EllesmereUI.OpenPlugin = function(...) opened = { ... }; return true end
    SlashCmdList.EUICT("profiles"); assert(opened[2] == "Profiles" and opened[3] == "Profiles")
    M.Click(M.Find(ns.SettingsUI.pages.profiles.frame, "Button", "Open Manage Profiles")); assert(opened[3] == "Profiles")
    ns.Ellesmere.Open("profiles", "Import / Export"); assert(opened[3] == "Import / Export")
    Build(); Click("New profile"); module.onModuleLeave(); assert(not EUICT_ProfileDialog:IsShown())
    Click("New profile"); parent:Hide(); EUICT_ProfileDialog.scripts.OnUpdate(EUICT_ProfileDialog)
    assert(not EUICT_ProfileDialog:IsShown())
end)
Test("profile actions show their results in rows without changing header guidance or announcing success", function()
    Build()
    local guidance = header.euictProfileHeader.note:GetText()
    Click("New profile"); Name("Raid"); Build()
    assert(Row("Raid") and HasText("Active", Row("Raid")))
    assert(header.euictProfileHeader.note:GetText() == guidance and not HasText('Saved "'))
    Click("Save as...", header); Name("Solo"); Build()
    Click("Use", Row("Raid")); Build()
    assert(P.Active() == "Raid" and HasText("Active", Row("Raid")) and not HasText("Now using"))
    Click("...", Row("Solo")); Click("Rename"); Name("Renamed"); Build()
    assert(Row("Renamed") and not HasText('Saved "'))
    Click("...", Row("Renamed")); Click("Delete"); Click("Delete"); Build()
    assert(not EUICT_DB.profiles.Renamed and not HasText('Deleted "'))
    assert(header.euictProfileHeader.note:GetText() == guidance)
end)
Test("export and import errors remain beside their controls and do not follow the user to the library", function()
    EUICT_DB.profiles.Broken = { cd = { spells = 1 } }
    Build("Import / Export")
    local guidance = header.euictProfileHeader.note:GetText()
    widgets["Profile"].args[3]("Broken"); Build()
    local _, err = P.Export("Broken")
    local error = assert(Find(parent, "FontString", "Could not export: " .. err))
    assert(error.point[3] < Input(1):GetParent():GetParent().point[3])
    Input(2):SetText('FCT1:{name="Bad",data={cd={spells=1}}}')
    Click("Preview import")
    local _, importError = ns.ProfileCodec.Decode(Input(2):GetText())
    error = assert(Find(parent, "FontString", "Could not import: " .. importError))
    assert(error.point[3] < Find(parent, "Button", "Preview import").point[3])
    assert(header.euictProfileHeader.note:GetText() == guidance)
    Input(2):SetText('FCT1:{name="Valid",data={}}')
    assert(not HasText("Could not import:"))
    Build("Profiles")
    assert(not HasText("Could not import:") and not HasText("Could not export:"))
    Build("Import / Export")
    widgets["Profile"].args[3](0); Build()
    assert(not HasText("Could not export:") and header.euictProfileHeader.note:GetText() == guidance)
end)
