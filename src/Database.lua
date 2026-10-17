-- Saved-variable reconciliation and the live settings storage boundary.
local _, ns = ...
local Database = { character = {}, DEFAULT_Y = { cd = -180, buff = -230, remind = -120 } }
ns.Database = Database
-- Keep this table's identity: controllers and settings pages retain it across late saved-data loads.
local DB = Database.character
local Validation = ns.ProfileValidation
local PREFIX = "EllesmereUICooldownTracker: "
-- Settings are per character, keyed by GUID (never by name: characters can share one). Each character's settings live
-- in its own file (EUICT_DBC, tagged with its GUID) and again in the account file under EUICT_DB.chars[GUID], so the
-- account copy alone can restore every character; the newest copy wins (see KitStorage.lua). Profiles and
-- remembered icons are account-wide, in EUICT_DB.
local ACCOUNT = { profiles = {}, icons = {}, chars = {} }
local function CharKey()
    local ok, guid = pcall(UnitGUID, "player")
    if ok and type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then return guid end
end
-- Up to 2.0 one copy was shared by every character: whoever logged out last wrote it.
local function Legacy(t) return type(t) == "table" and t._owner == nil and type(t.cd) == "table" end
local function PlayerClass()
    local ok, _, class = pcall(UnitClass, "player")
    return ok and type(class) == "string" and class or nil
end

-- Returns the account table and any pre-2.0 shared copy it replaced.
local function LoadAccount()
    local acct = type(EUICT_DB) == "table" and EUICT_DB or ACCOUNT
    local legacy
    if Legacy(acct) then
        legacy = acct
        acct = { profiles = acct.profiles, icons = acct.icons }
    end
    acct.chars = acct.chars or {}
    acct.profiles = acct.profiles or {}
    acct.icons = acct.icons or {}
    acct.profileAssignments = acct.profileAssignments or {}
    ACCOUNT = acct
    return acct, legacy
end

-- The newest of this character's own copies: its file (if it's really its own) and its entry in the account file.
local function PickCharacterCopy(acct, key, legacy)
    local file, mine = EUICT_DBC, nil
    if type(file) == "table" and next(file) ~= nil then
        if Legacy(file) then legacy = ns.Kit.PickSaved(nil, legacy, file)
        elseif file._owner == key or not key then mine = file end
    end
    local src = ns.Kit.PickSaved(DB, mine, key and acct.chars[key])
    if src or not legacy or next(DB) ~= nil then return src end
    -- before 2.0 only paladins used the tracker, so old settings are a paladin's: a paladin keeps them, any other
    -- class starts from its own defaults and only keeps where things were on screen
    for name, data in pairs(type(legacy.profiles) == "table" and legacy.profiles or {}) do
        if acct.profiles[name] == nil then acct.profiles[name] = data end
    end
    if PlayerClass() == "PALADIN" then return legacy end
    src = {}
    for _, k in ipairs({ "cd", "buff", "remind" }) do
        local t = legacy[k]
        if type(t) == "table" and t.x then src[k] = { x = t.x, y = t.y } end
    end
    return src
end

local function FillDefaults()
    for section, fields in pairs(Validation.Defaults()) do
        DB[section] = DB[section] or {}
        for field, value in pairs(fields) do if DB[section][field] == nil then DB[section][field] = value end end
    end
    for section, y in pairs(Database.DEFAULT_Y) do
        if DB[section].x == nil then DB[section].x = 0 end
        if DB[section].y == nil then DB[section].y = y end
    end
    -- the blessing each class should get from you; "" = any of the ally list (hybrids by default)
    for class, blessing in pairs(ns.Defaults.CLASS_BLESSING) do
        if DB.remind.byClass[class] == nil then DB.remind.byClass[class] = blessing end
    end
end

-- 2.0.0 added items (and the warlock's pet ability) to the defaults: give them once to settings saved before,
-- at the end of the list. Items only show while carried, and anyone who removes one keeps it removed.
local function MigrateItems()
    if DB.cd.items2 then return end
    DB.cd.items2 = true
    for _, name in ipairs(ns.Defaults.ForPlayer().cd) do
        if name == "Healthstone" or name == "Healing Potion" or name == "Mana Potion" or name == "Spell Lock" then
            local has = false
            for _, v in ipairs(DB.cd.spells) do if v:lower() == name:lower() then has = true end end
            if not has then table.insert(DB.cd.spells, name) end
        end
    end
end

-- icons seen once (account-wide), for spells not learned yet
local function ShareIcons()
    for k, v in pairs(ns.Kit.icons) do if ACCOUNT.icons[k] == nil then ACCOUNT.icons[k] = v end end
    ns.Kit.icons = ACCOUNT.icons
end

function Database.Init()
    local key = CharKey()
    local acct, legacy = LoadAccount()
    local src = PickCharacterCopy(acct, key, legacy)
    if src and src ~= DB then Mixin(DB, src) end
    -- Account profile assignments also reconcile renames/deletions while this character was offline.
    if key and acct.profileAssignments[key] ~= nil then DB._activeProfile = acct.profileAssignments[key] or nil end
    DB.profiles, DB.icons, DB._owner = nil, nil, key or DB._owner
    EUICT_DB, EUICT_DBC = acct, DB
    if key then acct.chars[key] = DB end
    FillDefaults()
    local repaired = Validation.Repair(DB)
    if #repaired > 0 then print(PREFIX .. "Reset invalid saved settings to defaults: " .. table.concat(repaired, ", ")) end
    DB.cd.growth = Validation.Growth(DB.cd)
    DB.buff.growth = Validation.Growth(DB.buff)
    MigrateItems()
    ShareIcons()
end

-- Back to defaults on the next load: this character's settings and its active-profile assignment.
function Database.Reset()
    Database.AssignActiveProfile(nil)
    wipe(DB)
end

function Database.TrackerConfig(key) return DB[key] end
-- Keep the original profile format for explicit imports; saved variables remain separate.
function Database.ProfileStore() return ACCOUNT.profiles end
function Database.Characters() return ACCOUNT.chars end
function Database.ProfileAssignments() return ACCOUNT.profileAssignments end
function Database.AssignActiveProfile(name)
    DB._activeProfile = name
    local key = CharKey()
    if key then ACCOUNT.profileAssignments[key] = name or false end
end
Database.PlayerClass = PlayerClass

ns.Kit.StampOnLogout(function() return DB end)
