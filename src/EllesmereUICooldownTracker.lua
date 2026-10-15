-- Addon composition: startup, event coalescing, and configuration routing.
local ADDON_NAME, ns = ...
local DB = ns.Database.character
local State = ns.Collection
local Readable = State.Readable
local UpdateCd, UpdateBuffs, UpdateRemind = ns.Trackers.cd.Update, ns.Trackers.buff.Update, ns.Trackers.remind.Update
local OnCast = ns.Trackers.buff.OnCast

-- Let ForeverImmersion fade the trackers like any other element (plain data; see ForeverImmersion).
ForeverUI = ForeverUI or {}
ForeverUI.elements = ForeverUI.elements or {}
table.insert(ForeverUI.elements, { key = "ellesmere:euict", label = "Ellesmere cooldown tracker", frames = { "EUICT_CD", "EUICT_Buff" },
    visible = { combat = true, target = true, key = true } })
ForeverUI.revision = (ForeverUI.revision or 0) + 1

-- Coalesce bursts at the next frame. Unknown/legacy cooldown payloads request a full state refresh.
local pending = { ids = {} }
local queued = false
local function FlushUpdates()
    queued = false
    local cd, buff, remind = pending.cd, pending.buff, pending.remind
    pending.cd, pending.buff, pending.remind = nil, nil, nil
    if cd then UpdateCd(false, cd ~= "all" and cd or nil, cd == "spell" and next(pending.ids) and pending.ids or nil) end
    wipe(pending.ids)
    if buff then UpdateBuffs() end
    if remind then UpdateRemind() end
end
local function QueueUpdate(key)
    pending[key] = true
    if not queued then queued = true; C_Timer.NewTimer(0, FlushUpdates) end
end
local function QueueCd(kind, id)
    if pending.cd ~= kind then pending.cd = pending.cd and "all" or kind end
    if kind == "spell" then
        if Readable(id, "number") then pending.ids[id] = true else pending.cd = "all" end
    end
    if not queued then queued = true; C_Timer.NewTimer(0, FlushUpdates) end
end
ns.QueueCooldownUpdate = QueueCd

local function UpdateAll() UpdateCd(); UpdateBuffs(); UpdateRemind() end

local function ReconcileConfiguration()
    State.InvalidateSpells(); State.InvalidateBags(); State.InvalidateAuras()
    ns.Configuration.Apply({ cd = { all = true }, buff = { all = true }, remind = { all = true }, ranks = { all = true } },
        { initialization = true })
end

local initialized = false
local function Init()
    ns.Database.Init()
    if initialized then
        ReconcileConfiguration()
        return
    end
    initialized = true
    for _, key in ipairs({ "cd", "buff", "remind" }) do ns.Trackers[key].Init() end
    C_Timer.NewTicker(2, function()
        -- Safety net for missed aura events and ally range changes.
        State.InvalidateAuras()
        UpdateBuffs(); UpdateRemind()
        local root = ns.Trackers.cd.Root()
        if State.bagsUnknown and root:IsShown() then State.InvalidateBags(); QueueCd("all") end
        ns.Trackers.cd.RefreshAppearance()
    end)
    for _, info in ipairs({ { "cd", "Cooldown icons" }, { "buff", "Buff bars" }, { "remind", "Buff reminders" } }) do
        local key = info[1]
        ns.Kit.EditMode({
            frame = ns.Trackers[key].Root(), label = info[2], key = key, db = DB,
            get = function() return DB[key].x, DB[key].y end,
            set = function(x, y) ns.SaveTrackerPosition(key, x, y) end,
            enabled = function() return DB[key].enabled end,
            onToggle = function() ns.ConfigChanged(key, "editing") end,
        })
    end
    ns.Ranks.Init(function() return DB.ranks or {} end)
    UpdateAll()
end

local SPELL_DEPENDENCY_EVENTS = {
    SPELLS_CHANGED = true, LEARNED_SPELL_IN_SKILL_LINE = true, UNIT_PET = true, PET_BAR_UPDATE = true,
    UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true, SPELL_UPDATE_ICON = true,
    PLAYER_SPECIALIZATION_CHANGED = true, TRAIT_CONFIG_UPDATED = true,
}
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player") -- seal recast doesn't always fire UNIT_AURA here
ev:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("BAG_UPDATE_COOLDOWN")
pcall(ev.RegisterEvent, ev, "GET_ITEM_INFO_RECEIVED")
for event in pairs(SPELL_DEPENDENCY_EVENTS) do
    if event ~= "SPELLS_CHANGED" and event ~= "UNIT_PET" then pcall(ev.RegisterEvent, ev, event) end
end
ev:RegisterEvent("UNIT_PET")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, eventArg, info, ...)
    if event == "ADDON_LOADED" then if eventArg == ADDON_NAME then Init() end
    elseif event == "PLAYER_LOGIN" then
        ns.Database.Init()
        ReconcileConfiguration()
    elseif event == "UNIT_AURA" then
        State.InvalidateAuras("player")
        UpdateBuffs(type(info) == "table" and info or nil)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        State.InvalidateAuras("player")
        if not OnCast((...)) then QueueUpdate("buff") end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        local category, recovery, itemID = ...
        -- Shared categories, GCDs and item use may change other icons too.
        if type(category) ~= "nil" or type(recovery) ~= "nil" or type(itemID) ~= "nil" then QueueCd("all")
        else
            QueueCd("spell", eventArg)
            if Readable(info, "number") then pending.ids[info] = true end -- base ID of an override
        end
    elseif event == "BAG_UPDATE_COOLDOWN" then QueueCd("item")
    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        State.InvalidateBags(); QueueCd("all")
    elseif SPELL_DEPENDENCY_EVENTS[event] then
        if (event == "UNIT_PET" or event == "PLAYER_SPECIALIZATION_CHANGED") and eventArg ~= "player" then return end
        State.InvalidateSpells(); ns.Trackers.buff.InvalidateLayout()
        QueueCd("all"); QueueUpdate("buff"); QueueUpdate("remind")
    elseif event == "PLAYER_ENTERING_WORLD" then
        State.InvalidateSpells(); State.InvalidateBags(); State.InvalidateAuras()
        QueueCd("all"); QueueUpdate("buff"); QueueUpdate("remind")
    else
        UpdateCd(true); UpdateBuffs(nil, true)
    end
end)

-- Reminders watch party and target auras too, and go away the moment combat starts.
local rev = CreateFrame("Frame")
for _, e in ipairs({ "UNIT_AURA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
    "UNIT_CONNECTION", "PLAYER_DEAD", "PLAYER_UNGHOST", "PLAYER_ALIVE" }) do rev:RegisterEvent(e) end
rev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" and not (unit == "player" or unit == "target" or (type(unit) == "string" and unit:find("^party%d$"))) then return end
    if event == "UNIT_AURA" then
        if unit ~= "player" then State.InvalidateAuras(unit) end -- the player handler owns this shared snapshot
    elseif event == "GROUP_ROSTER_UPDATE" then
        for i = 1, 4 do State.InvalidateAuras("party" .. i) end
        State.InvalidateAuras("target")
    elseif event == "PLAYER_TARGET_CHANGED" then State.InvalidateAuras("target")
    elseif event == "UNIT_CONNECTION" then State.InvalidateAuras(unit)
    elseif event == "PLAYER_DEAD" or event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then State.InvalidateAuras("player") end
    if event == "PLAYER_REGEN_DISABLED" then UpdateRemind() else QueueUpdate("remind") end
end)

function ns.SaveTrackerPosition(key, x, y)
    local cfg = DB[key]
    if not cfg or type(x) ~= "number" or type(y) ~= "number" then return end
    cfg.x, cfg.y = x, y
    ns.Configuration.Apply({ [key] = { x = true, y = true } }, { position = true })
    ns.Kit.SaveEditModePosition(key)
end

function ns.TrackerRoot(key)
    local tracker = ns.Trackers[key]
    return tracker and tracker.Root()
end

function ns.ApplyTrackerConfiguration(key, effects)
    local tracker, config = ns.Trackers[key], ns.TrackerConfig(key)
    local root = tracker and tracker.Root()
    if not root or not config then return end
    if effects.position then
        root:ClearAllPoints()
        root:SetPoint("CENTER", UIParent, "CENTER", config.x, config.y)
    end
    if effects.visibility then
        root:EnableMouse(not config.locked)
        root.bg:SetShown(not config.locked)
    end
    if effects.position and not (effects.data or effects.layout or effects.appearance or effects.visibility) then return end
    if effects.data then ns.TrackerPreview.Invalidate(key) end
    tracker.ApplyConfiguration(effects)
end

function ns.RefreshTrackers()
    ns.Configuration.Apply({ cd = { all = true }, buff = { all = true }, remind = { all = true } }, { refresh = true })
end
function ns.BuffRoot() return ns.TrackerRoot("buff") end
function ns.RefreshBuffs() ns.ConfigChanged("buff", "all", { refresh = true }) end
