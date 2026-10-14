-- Minimal WoW boundary for executing the real addon, settings callbacks and rank marker code.
-- No timers or game events run implicitly. This is not an in-game simulation.
local M = { objects = {}, events = {}, invalidated = {}, pageRefreshes = 0, timers = {}, tickers = {},
    calls = {}, now = 100, auras = {}, unreadable = {}, spellInfo = {}, known = {}, petKnown = {}, bags = {} }
function M.Count(key) M.calls[key] = (M.calls[key] or 0) + 1 end
local methods = {}
local function Noop() end
local function Object(kind, parent, name)
    local o = { kind = kind, parent = parent, children = {}, scripts = {}, shown = true, width = 600, height = 20 }
    setmetatable(o, { __index = function(_, key)
        if methods[key] then return methods[key] end
        if key:match("^[A-Z]") then return Noop end
    end })
    if parent then parent.children[#parent.children + 1] = o end
    M.objects[#M.objects + 1] = o
    if name then _G[name] = o end
    return o
end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:RegisterCallback(event, callback) self.scripts[event] = callback end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event, callback)
    local old = self.scripts[event]
    self.scripts[event] = function(...) if old then old(...) end; callback(...) end
end
function methods:RegisterEvent(event) M.events[event] = M.events[event] or {}; table.insert(M.events[event], self) end
function methods:RegisterUnitEvent(event, ...)
    self.unitEvents = self.unitEvents or {}
    self.unitEvents[event] = { ... }
    self:RegisterEvent(event)
end
function methods:CreateTexture() return Object("Texture", self) end
function methods:CreateFontString() return Object("FontString", self) end
function methods:GetParent() return self.parent end
function methods:SetText(text) M.Count("text"); self.textValue = text; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
function methods:GetText() return self.textValue or "" end
function methods:SetTextColor(...) self.textColor = { ... } end
function methods:GetStringWidth() return #self:GetText() * 6 end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:GetSize() return self.width, self.height end
function methods:SetWidth(w) self.width = w end
function methods:GetWidth() return self.width end
function methods:SetHeight(h) self.height = h end
function methods:GetHeight() return self.height end
function methods:GetFrameLevel() return 1 end
function methods:SetPoint(...) M.Count("layout"); self.point = { ... } end
function methods:ClearAllPoints() self.point, self.rectUnavailable = nil, nil end
function methods:GetNumPoints() return self.point and 1 or 0 end
function methods:GetPoint() return unpack(self.point or {}) end
-- Model missing native bounds despite a recorded anchor; screen coordinates are not simulated.
function methods:GetRect()
    if self.rectUnavailable or not self.point then return end
    return 0, 0, self.width, self.height
end
function methods:SetTexture(value) self.textureValue = value end
function methods:GetCenter() return self.centerX or 0, self.centerY or 0 end
function methods:StartMoving() M.Count("drag"); self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end
function methods:GetEffectiveScale() return 1 end
function methods:SetShown(value) self.shown = value end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:EnableMouse(value) self.mouseEnabled = value end
function methods:IsMouseEnabled() return self.mouseEnabled end
function methods:GetCountdownFontString() return nil end
function methods:GetFont() return "test-font", 12, "" end
function methods:GetScale() return 1 end
function methods:GetValue() return 0 end
function methods:SetTimerDuration(duration) self.timerDuration = duration end
function methods:SetValue(value) self.value = value end
function methods:Clear() self.cooldownCleared = true end
function methods:SetCooldown(start, duration) self.cooldownCleared = false; self.cooldownStart, self.cooldownDuration = start, duration end
function methods:SetCooldownFromDurationObject(duration) M.Count("durationBinding"); self.cooldownObject = duration end
function methods:SetVertexColor(...) self.vertexColor = { ... } end
function methods:SetDesaturated(value) self.desaturated = value end
function CreateFrame(kind, name, parent) return Object(kind, parent, name) end
UIParent = CreateFrame("Frame")
function wipe(t) for key in pairs(t) do t[key] = nil end; return t end
function Mixin(dst, src) for key, value in pairs(src) do dst[key] = value end; return dst end
function UnitClass(unit) return "Paladin", M.classes and M.classes[unit] or "PALADIN" end
function UnitGUID() return "test-character" end
function GetTime() return M.now end
function InCombatLockdown() return M.combat or false end
function UnitIsDeadOrGhost() return false end
function UnitOnTaxi() return false end
function UnitExists(unit) return M.units and M.units[unit] or false end
function UnitCanAttack() return M.attackable or false end
function UnitIsPlayer(unit) return UnitExists(unit) end
function UnitIsConnected() return true end
function UnitIsFriend() return M.friendly or false end
function UnitIsUnit(a, b) return a == b or (M.sameUnits and M.sameUnits[a] == b) or false end
function UnitInParty(unit) return M.targetInParty or false end
function UnitName(unit) return unit end
function GetRealmName() return "TestRealm" end
function IsPlayerSpell(id) return M.known[id] or M.spells or false end
function GetActionInfo(slot) if M.oldRank and slot == 1 then return "spell", 1 end end
function GetCursorInfo() return nil end
function issecretvalue() return false end
function GameTooltip_Hide() end
function PlaySound() end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
SlashCmdList = {}
MinimalSliderWithSteppersMixin = { Event = { OnValueChanged = 1 } }
C_Timer = {
    NewTicker = function(delay, callback) M.tickers[#M.tickers + 1] = { delay, callback } end,
    NewTimer = function(delay, callback) M.timers[#M.timers + 1] = { delay, callback } end,
    After = function(delay, callback) M.timers[#M.timers + 1] = { delay, callback } end,
}
function M.Flush()
    local ready, later = {}, {}
    for _, timer in ipairs(M.timers) do
        if timer[1] <= 0.05 then ready[#ready + 1] = timer else later[#later + 1] = timer end
    end
    M.timers = later
    for _, timer in ipairs(ready) do timer[2]() end
end
function M.Tick(delay)
    for _, ticker in ipairs(M.tickers) do if ticker[1] == delay then ticker[2]() end end
    M.Flush()
end
C_UnitAuras = {
    GetBuffDataByIndex = function(unit, index)
        M.Count("aura"); M.Count("aura:" .. unit)
        if M.unreadable[unit] then error("unreadable") end
        return (M.auras[unit] or {})[index]
    end,
    GetAuraDataByAuraInstanceID = function(unit, id)
        M.Count("instance")
        if M.unreadable[unit] then error("unreadable") end
        for _, aura in ipairs(M.auras[unit] or {}) do if aura.auraInstanceID == id then return aura end end
    end,
    GetPlayerAuraBySpellID = function(id)
        if M.unreadable.player then error("unreadable") end
        for _, aura in ipairs(M.auras.player or {}) do if aura.spellId == id then return aura end end
    end,
}
C_Container = {
    GetContainerNumSlots = function(bag) M.Count("bagSlots"); return #(M.bags[bag] or {}) end,
    GetContainerItemInfo = function(bag, slot) M.Count("bagItem"); return M.bags[bag][slot] end,
}
C_Item = { GetItemCooldown = function(id) M.Count("itemCooldown"); return 0, 0 end }
Enum = { SpellBookSpellBank = { Pet = 1 } }
C_SpellBook = { IsSpellKnown = function(id, bank)
    M.Count("known")
    if bank == 1 then return M.petKnown[id] or false end
    return M.known[id] or M.spells or false
end }
C_Spell = {
    GetSpellInfo = function(name)
        M.Count("spell")
        if M.spellInfo[name] then return M.spellInfo[name] end
        if M.spells and (name == "Holy Light" or name == 1 or name == 2) then
            return { spellID = name == 1 and 1 or 2, name = "Holy Light", iconID = 123 }
        end
    end,
    GetSpellName = function(id) if M.spells and (id == 1 or id == 2) then return "Holy Light" end end,
    GetSpellSubtext = function(id) return id == 1 and "Rank 1" or "Rank 2" end,
    GetSpellCooldown = function(id) M.Count("cooldown"); return M.cooldowns and M.cooldowns[id] or { isActive = false, isOnGCD = false } end,
    IsSpellInRange = function(id, unit) return not (M.outOfRange and M.outOfRange[unit]) end,
}
EllesmereUI = {
    RegisterPlugin = Noop,
    GetPluginModuleKey = function(_, module) return module end,
    InvalidateModulePageCache = function(_, key) M.invalidated[key] = (M.invalidated[key] or 0) + 1 end,
    GetActiveModule = function() return "CooldownBar" end,
    RefreshPage = function() M.pageRefreshes = M.pageRefreshes + 1 end,
    RegisterPluginModule = Noop,
}
function M.Fire(event, ...)
    -- Event registration during a callback must not extend the current dispatch.
    local frames = {}
    for i, frame in ipairs(M.events[event] or {}) do frames[i] = frame end
    local unit = (...)
    for _, frame in ipairs(frames) do
        local allowed = not (frame.unitEvents and frame.unitEvents[event])
        for _, filter in ipairs(frame.unitEvents and frame.unitEvents[event] or {}) do if filter == unit then allowed = true end end
        if allowed and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end
function M.Find(root, kind, text)
    for _, child in ipairs(root.children) do
        if child.kind == kind and (text == nil or child:GetText() == text) then return child end
        local found = M.Find(child, kind, text)
        if found then return found end
    end
end
function M.Click(button) assert(button and button.scripts.OnClick, "missing button"); button.scripts.OnClick(button) end
return M
