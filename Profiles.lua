-- Shared account profile operations. Both settings UIs use the same library and codec.
local _, ns = ...
local P = {}
ns.Profiles = P

function P.Active()
    local name = ns.ProfileCharacter()._activeProfile
    return name and ns.ProfileStore()[name] ~= nil and name or nil
end

function P.Associate(name)
    ns.AssignActiveProfile(name)
end

function P.Names()
    local names = {}
    for name in pairs(ns.ProfileStore()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function Name(name)
    if type(name) == "string" then name = name:match("^%s*(.-)%s*$") end
    return ns.ProfileValidation.ValidateName(name)
end

local function Saved(name)
    local data = ns.ProfileStore()[name]
    if data == nil then return nil, "Select a saved profile first." end
    return data
end

function P.Save(name)
    local valid, err = Name(name)
    if not valid then return nil, err end
    if ns.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    local data
    data, err = ns.SnapshotProfile()
    if not data then return nil, err end
    ns.ProfileStore()[valid] = data
    P.Associate(valid)
    ns.ProfileLibraryChanged(false)
    return valid
end

function P.Load(name)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    return ns.ApplyProfile(data, name)
end

-- Save only edited configuration fields, preserving shared changes not yet applied to this character.
function P.AutoSave(changes)
    local name = P.Active()
    if not name then return end
    local relevant = {}
    for section, fields in pairs(changes) do
        if ns.ProfileValidation.IsConfigSection(section) then
            for field in pairs(fields) do
                if field == "all" or ns.ProfileValidation.IsConfigField(section, field) then
                    relevant[section] = relevant[section] or {}
                    relevant[section][field] = true
                end
            end
        end
    end
    if not next(relevant) then return end
    local current, err = ns.SnapshotProfile()
    if not current then return nil, err end
    local candidate
    candidate, err = ns.ProfileValidation.Validate(ns.ProfileStore()[name])
    if not candidate then return nil, err end
    for section, fields in pairs(relevant) do
        if fields.orientation or fields.growth then fields.orientation, fields.growth = true, true end
        if fields.all then candidate[section] = current[section]
        else
            for field in pairs(fields) do candidate[section][field] = current[section][field] end
        end
    end
    candidate, err = ns.ProfileValidation.Validate(candidate)
    if not candidate then return nil, err end
    -- Snapshot and validation are detached; neither live settings nor other characters share these tables.
    if next(ns.Configuration.Changes(ns.ProfileStore()[name], candidate)) == nil then return end
    ns.ProfileStore()[name] = candidate
    ns.ProfileLibraryChanged(false)
    return name
end

-- Startup owns tracker initialization. Restore validated settings before it creates/synchronizes frames.
function P.RestoreActive()
    local name = P.Active()
    if not name then return end
    local candidate, err = ns.ProfileValidation.Validate(ns.ProfileStore()[name])
    if not candidate then return nil, err end
    ns.ProfileValidation.Commit(ns.ProfileCharacter(), candidate)
    return name
end

function P.Duplicate(name, newName)
    local valid, err = Name(newName)
    if not valid then return nil, err end
    if ns.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    local data
    data, err = Saved(name)
    if data == nil then return nil, err end
    data, err = ns.ProfileValidation.Validate(data)
    if not data then return nil, err end
    ns.ProfileStore()[valid] = data
    ns.ProfileLibraryChanged(false)
    return valid
end

local function Relink(oldName, newName)
    for key, name in pairs(ns.ProfileAssignments()) do
        if name == oldName then ns.ProfileAssignments()[key] = newName or false end
    end
    for _, character in pairs(ns.ProfileCharacters()) do
        if type(character) == "table" and character._activeProfile == oldName then character._activeProfile = newName end
    end
    if ns.ProfileCharacter()._activeProfile == oldName then P.Associate(newName) end
end

function P.Rename(name, newName)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    local valid
    valid, err = Name(newName)
    if not valid then return nil, err end
    if valid == name then return valid end
    if ns.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    ns.ProfileStore()[valid], ns.ProfileStore()[name] = data, nil
    Relink(name, valid)
    ns.ProfileLibraryChanged(false)
    return valid
end

function P.Delete(name)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    ns.ProfileStore()[name] = nil
    Relink(name, nil)
    ns.ProfileLibraryChanged(false)
    return true
end

function P.Export(name, current)
    local valid, err = Name(name)
    if not valid then return nil, err end
    local data
    if current then data, err = ns.SnapshotProfile()
    else
        data, err = Saved(name)
        if data ~= nil then data, err = ns.ProfileValidation.Validate(data) end
    end
    if not data then return nil, err end
    local ok, encoded = pcall(ns.Kit.Encode, { name = valid, data = data })
    if not ok then return nil, encoded end
    local raw = "FCT1:" .. encoded
    if #raw > ns.ProfileValidation.Limits.input then return nil, "Profile text exceeds " .. ns.ProfileValidation.Limits.input .. " bytes." end
    return raw
end

function P.Import(raw, choice)
    local name, err, duplicate = ns.Kit.ImportProfile({ store = ns.ProfileStore, decode = ns.DecodeProfile }, raw, choice)
    if name then ns.ProfileLibraryChanged(false) end
    return name, err, duplicate
end
