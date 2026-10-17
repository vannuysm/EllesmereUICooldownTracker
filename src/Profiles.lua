-- Shared account profile operations. Both settings UIs use the same library and codec.
local _, ns = ...
local P = {}
ns.Profiles = P
local Database, Validation, Collection = ns.Database, ns.ProfileValidation, ns.Collection
local DB = Database.character
local PREFIX = "EllesmereUICooldownTracker: "

-- Library listeners receive refresh=false when a page should update without rebuilding an active widget.
local libraryListeners = {}
function P.OnLibraryChanged(listener) libraryListeners[#libraryListeners + 1] = listener end
local function LibraryChanged(refresh)
    for _, listener in ipairs(libraryListeners) do listener(refresh) end
end
P.LibraryChanged = LibraryChanged

function P.Active()
    local name = DB._activeProfile
    return name and Database.ProfileStore()[name] ~= nil and name or nil
end

function P.Associate(name)
    Database.AssignActiveProfile(name)
end

function P.Names()
    local names = {}
    for name in pairs(Database.ProfileStore()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function Name(name)
    if type(name) == "string" then name = name:match("^%s*(.-)%s*$") end
    return Validation.ValidateName(name)
end

local function Saved(name)
    local data = Database.ProfileStore()[name]
    if data == nil then return nil, "Select a saved profile first." end
    return data
end

-- Profiles contain only validated configurable fields; positions and storage stay with this character.
function P.Snapshot()
    return Validation.Snapshot(DB, Database.PlayerClass())
end

function P.Apply(data, profileName)
    local candidate, err = Validation.Validate(data)
    if not candidate then return nil, err end
    local changes = ns.Configuration.Changes(DB, candidate)
    changes.ranks = { all = true } -- profiles also reconcile markers on action buttons created since the last check
    Validation.Commit(DB, candidate)
    Database.AssignActiveProfile(profileName)
    Collection.InvalidateSpells(); Collection.InvalidateBags(); Collection.InvalidateAuras()
    ns.Configuration.Apply(changes, { profile = true })
    return true
end

function P.Save(name)
    local valid, err = Name(name)
    if not valid then return nil, err end
    if Database.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    local data
    data, err = P.Snapshot()
    if not data then return nil, err end
    Database.ProfileStore()[valid] = data
    P.Associate(valid)
    LibraryChanged(false)
    return valid
end

function P.Load(name)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    return P.Apply(data, name)
end

-- Save only edited configuration fields, preserving shared changes not yet applied to this character.
function P.AutoSave(changes)
    local name = P.Active()
    if not name then return end
    local relevant = {}
    for section, fields in pairs(changes) do
        if Validation.IsConfigSection(section) then
            for field in pairs(fields) do
                if field == "all" or Validation.IsConfigField(section, field) then
                    relevant[section] = relevant[section] or {}
                    relevant[section][field] = true
                end
            end
        end
    end
    if not next(relevant) then return end
    local current, err = P.Snapshot()
    if not current then return nil, err end
    local candidate
    candidate, err = Validation.Validate(Database.ProfileStore()[name])
    if not candidate then return nil, err end
    for section, fields in pairs(relevant) do
        if fields.orientation or fields.growth then fields.orientation, fields.growth = true, true end
        if fields.all then candidate[section] = current[section]
        else
            for field in pairs(fields) do candidate[section][field] = current[section][field] end
        end
    end
    candidate, err = Validation.Validate(candidate)
    if not candidate then return nil, err end
    -- Snapshot and validation are detached; neither live settings nor other characters share these tables.
    if next(ns.Configuration.Changes(Database.ProfileStore()[name], candidate)) == nil then return end
    Database.ProfileStore()[name] = candidate
    LibraryChanged(false)
    return name
end

-- Configuration listener: settings edits save to the active profile; loads, startup and positions never do.
function P.OnConfigurationChanged(changes, options)
    if options.profile or options.initialization or options.position then return end
    local _, err = P.AutoSave(changes)
    if err then print(PREFIX .. "Could not automatically save the active profile: " .. err) end
end

-- Startup owns tracker initialization. Restore validated settings before it creates/synchronizes frames.
function P.RestoreActive()
    local name = P.Active()
    if not name then return end
    local candidate, err = Validation.Validate(Database.ProfileStore()[name])
    if not candidate then return nil, err end
    Validation.Commit(DB, candidate)
    return name
end

function P.Duplicate(name, newName)
    local valid, err = Name(newName)
    if not valid then return nil, err end
    if Database.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    local data
    data, err = Saved(name)
    if data == nil then return nil, err end
    data, err = Validation.Validate(data)
    if not data then return nil, err end
    Database.ProfileStore()[valid] = data
    LibraryChanged(false)
    return valid
end

local function Relink(oldName, newName)
    local assignments = Database.ProfileAssignments()
    for key, name in pairs(assignments) do
        if name == oldName then assignments[key] = newName or false end
    end
    for _, character in pairs(Database.Characters()) do
        if type(character) == "table" and character._activeProfile == oldName then character._activeProfile = newName end
    end
    if DB._activeProfile == oldName then P.Associate(newName) end
end

function P.Rename(name, newName)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    local valid
    valid, err = Name(newName)
    if not valid then return nil, err end
    if valid == name then return valid end
    if Database.ProfileStore()[valid] ~= nil then return nil, "A profile with that name already exists. Choose another name." end
    Database.ProfileStore()[valid], Database.ProfileStore()[name] = data, nil
    Relink(name, valid)
    LibraryChanged(false)
    return valid
end

function P.Delete(name)
    local data, err = Saved(name)
    if data == nil then return nil, err end
    Database.ProfileStore()[name] = nil
    Relink(name, nil)
    LibraryChanged(false)
    return true
end

function P.Export(name, current)
    local valid, err = Name(name)
    if not valid then return nil, err end
    local data
    if current then data, err = P.Snapshot()
    else
        data, err = Saved(name)
        if data ~= nil then data, err = Validation.Validate(data) end
    end
    if not data then return nil, err end
    local ok, encoded = pcall(ns.Kit.Encode, { name = valid, data = data })
    if not ok then return nil, encoded end
    local raw = "FCT1:" .. encoded
    if #raw > Validation.Limits.input then return nil, "Profile text exceeds " .. Validation.Limits.input .. " bytes." end
    return raw
end

-- Both profile editors use the same validated import and collision policy.
-- Returns the stored name, or nil plus an error and, for a name collision without a choice, the duplicate name.
function P.Import(raw, choice)
    local candidate, err = ns.ProfileCodec.Decode(raw)
    if not candidate then return nil, err end
    if choice ~= nil and choice ~= "overwrite" and choice ~= "keep" then return nil, "Invalid duplicate import choice." end
    local store, name = Database.ProfileStore(), candidate.name
    if store[name] ~= nil then
        if not choice then return nil, "A profile with this name already exists.", name end
        if choice == "keep" then
            local base, n = name, 2
            repeat
                local suffix = " " .. n
                name = base:sub(1, Validation.Limits.name - #suffix) .. suffix
                n = n + 1
            until store[name] == nil
        end
    end
    store[name] = candidate.data
    LibraryChanged(false)
    return name
end
