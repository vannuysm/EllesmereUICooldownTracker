-- Slash commands and the named addon-compartment callback required by the TOC.
local _, ns = ...
local DB, Kit = ns.Database.character, ns.Kit

function EllesmereUICooldownTracker_OpenSettings() ns.OpenSettings() end

local function SlashSetting(section, field, text)
    local data = ns.SnapshotProfile()
    data[section][field] = tonumber(text)
    local candidate, err = ns.ProfileValidation.Validate(data)
    if candidate then ns.SetConfig(section, field, candidate[section][field])
    else print("EllesmereUICooldownTracker: " .. err) end
end
SLASH_EUICT1 = "/euict"
SLASH_EUICT2 = "/ellesmerecooldowns"
SlashCmdList.EUICT = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if cmd == "reset" then wipe(DB); ReloadUI()
    elseif cmd == "ranks" then ns.Ranks.Report()
    elseif cmd == "cdsize" and tonumber(arg) then SlashSetting("cd", "size", arg)
    elseif cmd == "barwidth" and tonumber(arg) then SlashSetting("buff", "width", arg)
    elseif cmd == "barheight" and tonumber(arg) then SlashSetting("buff", "height", arg)
    elseif cmd == "buff" and ns.OpenBuffSettings then ns.OpenBuffSettings()
    elseif cmd == "profiles" then
        if ns.OpenProfileSettings then ns.OpenProfileSettings() else Kit.Open(ns.settingsPages.profiles) end
    elseif (cmd == "cd" or cmd == "remind" or cmd == "reminders") and ns.OpenTrackerSettings then
        ns.OpenTrackerSettings(cmd == "cd" and "cd" or "remind")
    else ns.OpenSettings() end
end
