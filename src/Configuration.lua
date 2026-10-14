-- Configuration notifications only. Runtime events never go through this coordinator.
local _, ns = ...
local C = {}
ns.Configuration = C

local data = { spells = true, self = true, ally = true, byClass = true }
local layout = { size = true, width = true, height = true, gap = true, orientation = true, growth = true }
local visibility = { enabled = true, locked = true, visibility = true, party = true, target = true, editing = true }

function C.Effects(fields)
    local effects = {}
    for field in pairs(fields) do
        if field == "all" then
            effects.data, effects.layout, effects.appearance, effects.visibility, effects.position = true, true, true, true, true
        elseif data[field] then effects.data, effects.layout = true, true
        elseif layout[field] then effects.layout = true
        elseif visibility[field] then effects.visibility = true
        elseif field == "x" or field == "y" then effects.position = true
        else effects.appearance = true end
    end
    return effects
end

local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
function C.Changes(db, candidate)
    local changes = {}
    for section, fields in pairs(candidate) do
        if type(fields) == "table" then
            for field, value in pairs(fields) do
                if not Equal(db[section] and db[section][field], value) then
                    changes[section] = changes[section] or {}
                    changes[section][field] = true
                end
            end
        end
    end
    return changes
end

-- Call after a validated profile commit or an editor's valid, in-place list mutation.
function C.Apply(changes, options)
    options = options or {}
    if ns.Profiles and not (options.profile or options.initialization or options.refresh or options.position) then
        local _, err = ns.Profiles.AutoSave(changes)
        if err then print("EllesmereUICooldownTracker: Could not automatically save the active profile: " .. err) end
    end
    for section, fields in pairs(changes) do
        if section == "ranks" then
            if fields.enabled or fields.keep or fields.all then ns.Ranks.ResetTold() end
            ns.Ranks.Check() -- owns combat deferral and automatic rank upgrades
        else
            ns.ApplyTrackerConfiguration(section, C.Effects(fields), options)
        end
    end
    if ns.RefreshConfigurationPages then ns.RefreshConfigurationPages(changes, options) end
end

function ns.SetConfig(section, field, value, options)
    local cfg = ns.TrackerConfig(section)
    cfg[field] = value
    local fields = { [field] = true }
    if field == "orientation" then
        cfg.growth = value == "vertical" and (cfg.growth == "up" and "up" or "down")
            or (cfg.growth == "left" and "left" or "right")
        fields.growth = true
    end
    C.Apply({ [section] = fields }, options)
end

function ns.ConfigChanged(section, field, options)
    C.Apply({ [section] = { [field] = true } }, options)
end
