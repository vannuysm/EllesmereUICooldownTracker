-- Slash commands and the named addon-compartment callback required by the TOC.
local _, ns = ...
local SettingsUI = ns.SettingsUI
local PREFIX = "EllesmereUICooldownTracker: "

function EllesmereUICooldownTracker_OpenSettings() SettingsUI.Open() end

local function SlashSetting(section, field, text)
    local data, err = ns.Profiles.Snapshot()
    if not data then print(PREFIX .. err) return end
    data[section][field] = tonumber(text)
    local candidate
    candidate, err = ns.ProfileValidation.Validate(data)
    if candidate then ns.Configuration.Set(section, field, candidate[section][field])
    else print(PREFIX .. err) end
end
local OPEN = { buff = "buff", profiles = "profiles", cd = "cd", remind = "remind", reminders = "remind" }
SLASH_EUICT1 = "/euict"
SLASH_EUICT2 = "/ellesmerecooldowns"
SlashCmdList.EUICT = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if cmd == "reset" then ns.Database.Reset(); ReloadUI()
    elseif cmd == "ranks" then ns.Ranks.Report()
    elseif cmd == "cdsize" and tonumber(arg) then SlashSetting("cd", "size", arg)
    elseif cmd == "barwidth" and tonumber(arg) then SlashSetting("buff", "width", arg)
    elseif cmd == "barheight" and tonumber(arg) then SlashSetting("buff", "height", arg)
    else SettingsUI.Open(OPEN[cmd]) end
end
