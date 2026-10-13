-- Spell ranks on the action bars: tells you when a button still holds an older rank than one you know, and can
-- swap it for the newest rank out of combat. Self-contained (settings come in through Ranks.Init), so it can also
-- ship on its own.
local _, ns = ...
local Ranks = {}
ns.Ranks = Ranks

local PREFIX = "|cffffd100EllesmereUICooldownTracker:|r "
local SLOTS = 180
local settings = function() return {} end
local told = {}       -- "slot:spellID" -> true, so each outdated button is mentioned once per session
local pending = false -- an update waits for combat to end

local function Plain(v, kind) return type(v) == kind and not (issecretvalue and issecretvalue(v)) end
local function Known(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and Plain(known, "boolean") then return known end
    end
    return IsPlayerSpell and IsPlayerSpell(id) or false
end
-- "Rank 5" -> 5; nil for spells without ranks, so those are never touched
function Ranks.RankOf(id)
    local ok, sub = pcall(C_Spell.GetSpellSubtext, id)
    if not ok or not Plain(sub, "string") then return nil end
    return tonumber(sub:match("(%d+)"))
end
function Ranks.NameOf(id)
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and Plain(name, "string") and name or nil
end
-- The highest rank you know of the spell with this ID, if it's higher than this one.
function Ranks.Newer(id)
    local name, rank = Ranks.NameOf(id), Ranks.RankOf(id)
    if not name or not rank then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    local newID = ok and type(info) == "table" and Plain(info.spellID, "number") and info.spellID or nil
    if not newID or newID == id or not Known(newID) then return nil end
    local newRank = Ranks.RankOf(newID)
    if newRank and newRank > rank then return newID, rank, newRank end
end

function Ranks.Where(slot) return ("bar %d, button %d"):format(math.floor((slot - 1) / 12) + 1, (slot - 1) % 12 + 1) end

-- Every action button holding an older rank: { slot, id, newID, rank, newRank, name }
function Ranks.Outdated()
    local out, skip = {}, settings().keep or {}
    for slot = 1, SLOTS do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" and Plain(id, "number") then
            local newID, rank, newRank = Ranks.Newer(id)
            local name = newID and Ranks.NameOf(id)
            local kept = false
            for _, k in ipairs(skip) do if name and k:lower() == name:lower() then kept = true end end
            if newID and not kept then
                out[#out + 1] = { slot = slot, id = id, newID = newID, rank = rank, newRank = newRank, name = name }
            end
        end
    end
    return out
end

local function Swap(o)
    if GetCursorInfo and GetCursorInfo() then return false end -- you're dragging something: leave it alone
    C_Spell.PickupSpell(o.newID)
    PlaceAction(o.slot)
    ClearCursor() -- PlaceAction hands back the old rank on the cursor
    return true
end

-- A marker on each outdated button: a green arrow and the old rank in the corner. Buttons are found by name and read
-- their slot from .action, so paged and extra bars follow along.
local BUTTONS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
local badges = {}
local function Badge(btn)
    if badges[btn] then return badges[btn] end
    local b = CreateFrame("Frame", nil, btn)
    b:SetAllPoints()
    b:SetFrameLevel(btn:GetFrameLevel() + 5)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetSize(14, 14)
    b.arrow:SetPoint("TOPLEFT", 1, -1)
    if not (b.arrow.SetAtlas and pcall(b.arrow.SetAtlas, b.arrow, "bags-greenarrow")) then b.arrow:Hide() end
    b.text = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.text:SetPoint("BOTTOMLEFT", 2, 2)
    b.text:SetTextColor(1, 0.5, 0.1)
    badges[btn] = b
    return b
end
function Ranks.Mark(outdated)
    local s = settings()
    local bySlot = {}
    if s.enabled then for _, o in ipairs(outdated or Ranks.Outdated()) do bySlot[o.slot] = o end end
    for _, prefix in ipairs(BUTTONS) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            local slot = btn and Plain(btn.action, "number") and btn.action
            local o = slot and bySlot[slot]
            if o then
                local b = Badge(btn)
                b.text:SetText("R" .. o.rank)
                b:Show()
            elseif btn and badges[btn] then
                badges[btn]:Hide()
            end
        end
    end
end

function Ranks.Check()
    local s = settings()
    local outdated = s.enabled and Ranks.Outdated() or {}
    pcall(Ranks.Mark, outdated)
    if not s.enabled then return end
    for _, o in ipairs(outdated) do
        local key = o.slot .. ":" .. o.id
        if s.auto then
            if InCombatLockdown() then pending = true
            elseif Swap(o) then
                print(PREFIX .. ("%s on %s updated to Rank %d."):format(o.name, Ranks.Where(o.slot), o.newRank))
            end
        elseif not told[key] then
            told[key] = true
            print(PREFIX .. ("%s on %s is Rank %d, you know Rank %d."):format(o.name, Ranks.Where(o.slot), o.rank, o.newRank))
        end
    end
end

-- /euict ranks: what the addon sees, for checking a client it hasn't met yet
function Ranks.Report()
    local n = 0
    for slot = 1, SLOTS do
        local ok, kind, id = pcall(GetActionInfo, slot)
        if ok and kind == "spell" and Plain(id, "number") then
            local ok2, sub = pcall(C_Spell.GetSpellSubtext, id)
            local newID, _, newRank = Ranks.Newer(id)
            n = n + 1
            print(PREFIX .. ("%s: %s #%d \"%s\"%s"):format(Ranks.Where(slot), Ranks.NameOf(id) or "?", id,
                ok2 and Plain(sub, "string") and sub or "-", newID and (" -> Rank %d #%d"):format(newRank, newID) or ""))
        end
    end
    if n == 0 then print(PREFIX .. "no spells found on your action bars.") end
end

local timer
local function Soon() -- a burst of events (learning a spell fires several) checks once
    if timer then return end
    timer = C_Timer.NewTimer(0.5, function() timer = nil; pcall(Ranks.Check) end)
end

function Ranks.Init(getSettings)
    settings = getSettings
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "PLAYER_REGEN_ENABLED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not pending then return end
        pending = false
        Soon()
    end)
end

function Ranks.ResetTold() wipe(told) end
