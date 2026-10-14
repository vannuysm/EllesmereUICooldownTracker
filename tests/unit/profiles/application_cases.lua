local ctx = ...
local M, ns, Test = ctx.mocks, ctx.ns, ctx.Test
local H = dofile(ctx.path("tests/unit/profiles/support.lua"))(ctx)
local V, Kit, Equal, Copy, Read = H.V, H.Kit, H.Equal, H.Copy, H.Read
local ErrorContains, Bad, BadText = H.ErrorContains, H.Bad, H.BadText

local profilePage = ns.settingsPages.profiles
local libraryBlock, importBlock = profilePage.blocks[1], profilePage.blocks[2]
local function HasText(root, fragment)
    for _, child in ipairs(root.children) do
        if child.kind == "FontString" and child:GetText():find(fragment, 1, true) then return true end
        if HasText(child, fragment) then return true end
    end
    return false
end
Test("UI failed import leaves text, settings and library unchanged", function()
    local text, button = M.Find(importBlock, "EditBox"), M.Find(importBlock, "Button", "Import")
    local raw = 'FCT1:{name="Broken",data={cd={spells=1}}}'
    text:SetText(raw)
    local settings, library = Kit.Encode(EUICT_DBC), Kit.Encode(EUICT_DB.profiles)
    M.Click(button)
    assert(text:GetText() == raw and HasText(importBlock, "cd.spells"))
    assert(Kit.Encode(EUICT_DBC) == settings and Kit.Encode(EUICT_DB.profiles) == library)
end)
Test("UI successful import stores a detached normalized profile without applying it", function()
    local text, button = M.Find(importBlock, "EditBox"), M.Find(importBlock, "Button", "Import")
    local settings = Kit.Encode(EUICT_DBC)
    text:SetText('FCT1:{name="Imported UI",data={_class="HUNTER",cd={spells={},future=true},_owner="other"}}')
    M.Click(button)
    local candidate = EUICT_DB.profiles["Imported UI"]
    assert(candidate and candidate.cd.spells and next(candidate.cd.spells) == nil and candidate._owner == nil and candidate.cd.future == nil)
    assert(candidate._class == "HUNTER" and text:GetText() == "" and Kit.Encode(EUICT_DBC) == settings)
    text:SetText('FCT1:{name="Imported UI",data={}}'); M.Click(button)
    assert(EUICT_DB.profiles["Imported UI 2"])
end)
for _, value in ipairs({ { cd = { spells = 1 } }, "broken" }) do
    Test("UI invalid saved-profile load reports failure and keeps the library entry (" .. type(value) .. ")", function()
        EUICT_DB.profiles["Broken saved"] = value
        profilePage:Refresh()
        local row = assert(M.Find(libraryBlock, "FontString", "Broken saved")).parent
        local settings, library = Kit.Encode(EUICT_DBC), Kit.Encode(EUICT_DB.profiles)
        M.Click(row.load)
        assert(HasText(libraryBlock, "Could not load:") and not HasText(libraryBlock, 'Loaded "Broken saved"'))
        assert(EUICT_DB.profiles["Broken saved"] == value and Kit.Encode(EUICT_DBC) == settings and Kit.Encode(EUICT_DB.profiles) == library)
    end)
end
Test("successful application updates locks, content, rank markers and page caches while preserving storage references", function()
    local db, account, profiles, icons = EUICT_DBC, EUICT_DB, EUICT_DB.profiles, EUICT_DB.icons
    local cd, buff, remind, ranks = db.cd, db.buff, db.remind, db.ranks
    db.editLayouts = { layout1 = { cd = { 21, 42 } } }; db._savedAt = 123
    local layouts = db.editLayouts
    M.spells, M.oldRank = true, true
    ActionButton1 = CreateFrame("Button", "ActionButton1", UIParent); ActionButton1.action = 1
    ns.settingsPages.cd.frame:Show()
    local refreshes = 0; ns.settingsPages.cd:OnRefresh(function() refreshes = refreshes + 1 end)
    local invalidations = M.invalidated.CooldownBar or 0
    local data = { cd = { spells = { "Holy Light" }, locked = false, visibility = "always", orientation = "vertical", growth = "up", size = 40 },
        buff = { spells = {}, locked = false }, remind = { self = {}, ally = {}, locked = false }, ranks = { enabled = true, auto = false } }
    assert(ns.ApplyProfile(data))
    assert(#ns.Ranks.Outdated() == 1, "mock old action must resolve to an outdated rank")
    local badge = assert(ActionButton1.children[1]); assert(badge:IsShown())
    for _, key in ipairs({ "cd", "buff", "remind" }) do
        local root = ns.TrackerRoot(key); assert(root:IsMouseEnabled() and root.bg:IsShown())
    end
    assert(EUICT_CD.items[1]:IsShown() and EUICT_CD.items[1].spellID == 2 and EUICT_CD:GetWidth() == 40)
    assert(refreshes > 0 and M.invalidated.CooldownBar == invalidations + 1 and M.invalidated.BuffBars and M.invalidated.Reminders and M.pageRefreshes > 0)
    data.cd.spells[1] = "changed by caller"; assert(db.cd.spells[1] == "Holy Light")
    assert(ns.ApplyProfile({ cd = { spells = {}, locked = true }, buff = { locked = true }, remind = { locked = true }, ranks = { enabled = false } }))
    assert(not badge:IsShown() and not EUICT_CD.items[1]:IsShown())
    for _, key in ipairs({ "cd", "buff", "remind" }) do
        local root = ns.TrackerRoot(key); assert(not root:IsMouseEnabled() and not root.bg:IsShown())
    end
    assert(EUICT_DBC == db and EUICT_DB == account and account.chars["test-character"] == db)
    assert(db.cd == cd and db.buff == buff and db.remind == remind and db.ranks == ranks)
    assert(db.editLayouts == layouts and db._savedAt == 123 and db._owner == "test-character")
    assert(account.profiles == profiles and account.icons == icons)
end)
Test("UI successful saved-profile load reports success", function()
    EUICT_DB.profiles["Good saved"] = { cd = { spells = {}, locked = false }, ranks = { enabled = false } }
    profilePage:Refresh()
    local row = assert(M.Find(libraryBlock, "FontString", "Good saved")).parent
    M.Click(row.load)
    assert(HasText(libraryBlock, 'Loaded "Good saved"') and EUICT_CD:IsMouseEnabled())
end)
Test("maximum-length import name collisions remain exportable", function()
    local name = string.rep("N", V.Limits.name)
    local text, button = M.Find(importBlock, "EditBox"), M.Find(importBlock, "Button", "Import")
    local raw = 'FCT1:' .. Kit.Encode({ name = name, data = {} })
    text:SetText(raw); M.Click(button)
    text:SetText(raw); M.Click(button)
    local second = name:sub(1, V.Limits.name - 2) .. " 2"
    local row = assert(M.Find(libraryBlock, "FontString", second)).parent
    M.Click(row.share)
    assert(ns.DecodeProfile(text:GetText()).name == second)
end)
