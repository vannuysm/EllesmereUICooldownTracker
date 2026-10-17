-- Missing-buff collection, learned alternatives and pooled reminder rows.
local _, ns = ...
local DB = ns.Database.character
local Collection = ns.Collection
local Frames = ns.TrackerFrames
local Appearance = ns.TrackerAppearance
local Readable = Collection.Readable
local Reminders = {}
ns.Trackers.remind = Reminders
local IsOwnSpell, OutOfRange = Collection.IsOwnSpell, Collection.OutOfRange

-- Buff reminders ------------------------------------------------------------
-- Out of combat, a line for each buff that's missing: on you, and (opt-in) your buff on party members or a friendly
-- target. One list entry is one reminder; " / " separates buffs that each satisfy it. Only buffs the character has
-- learned count, so it never asks for a spell you can't cast, and a class with nothing learned from the list sees nothing.
-- Not registered with ForeverImmersion on purpose: it shows exactly when Immersion would fade things out.
local remindRoot

local learnedEntries, learnedRevision = {}, -1
local function Learned(entry)
    if learnedRevision ~= Collection.spellRevision then wipe(learnedEntries); learnedRevision = Collection.spellRevision end
    if learnedEntries[entry] then return learnedEntries[entry] end
    local out = {}
    for name in entry:gmatch("[^/]+") do
        name = name:match("^%s*(.-)%s*$")
        local info = name ~= "" and Collection.Spell(name)
        if info and IsOwnSpell(info.spellID) then out[#out + 1] = info end
    end
    learnedEntries[entry] = out
    return out
end

-- What to call a reminder: the shared leading words ("Blessing of Might", "Blessing of Kings" -> "Blessing").
local function Label(learned)
    if learned.label then return learned.label end
    local words = {}
    for w in learned[1].name:gmatch("%S+") do words[#words + 1] = w end
    local n = #words
    for i = 2, #learned do
        local j = 0
        for w in learned[i].name:gmatch("%S+") do
            if j >= n or words[j + 1] ~= w then break end
            j = j + 1
        end
        n = j
    end
    if n > 0 and (words[n] == "of" or words[n] == "the") then n = n - 1 end
    learned.label = n > 0 and table.concat(words, " ", 1, n) or learned[1].name
    return learned.label
end

-- true or false; nil when the unit's auras can't be read (secret), so it never reminds on a guess.
-- mine: only buffs the player cast count (another paladin's Kings doesn't replace your Might).
local function HasBuff(unit, learned, mine)
    return Collection.HasBuff(Collection.Auras(unit), learned, mine)
end

-- A test that may come back secret: only a readable true counts.
local function Yes(fn, ...)
    local ok, v = pcall(fn, ...)
    return ok and Readable(v, "boolean") and v
end

local function AllyUnits()
    local c, out = DB.remind, {}
    local function add(u)
        if not Yes(UnitExists, u) or not Yes(UnitIsPlayer, u) or Yes(UnitIsDeadOrGhost, u) then return end
        if UnitIsConnected and not Yes(UnitIsConnected, u) then return end
        for _, existing in ipairs(out) do if Yes(UnitIsUnit, u, existing) then return end end
        out[#out + 1] = u
    end
    if c.party then for i = 1, 4 do add("party" .. i) end end
    if c.target and Yes(UnitIsFriend, "player", "target") and not Yes(UnitIsUnit, "target", "player")
        and not (c.party and Yes(UnitInParty, "target")) then
        add("target")
    end
    return out
end

-- Forever gives characters a first and a last name: UnitName returns the surname where retail puts a realm.
local function UnitLabel(u)
    local ok, first, surname = pcall(UnitName, u)
    local name = ok and Readable(first, "string") and first ~= "" and first or nil
    if not name then return u == "target" and TARGET or "party member" end
    local last = Readable(surname, "string") and surname ~= "" and surname or nil
    local realm = GetRealmName and GetRealmName()
    realm = Readable(realm, "string") and realm or ""
    if last and last ~= realm and last ~= realm:gsub("%s", "") then return name .. " " .. last end
    return name
end

-- A line without tracker callbacks.
local function NewLine(parent)
    local l = CreateFrame("Frame", nil, parent)
    l.icon = l:CreateTexture(nil, "ARTWORK")
    l.icon:SetPoint("LEFT")
    l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    l.text = l:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    l.text:SetPoint("LEFT", l.icon, "RIGHT", 6, 0)
    return l
end
local function TrackerLine(root)
    local l = NewLine(root)
    Frames.AttachMouse(l, root, "remind")
    return l
end

local reminderLines = {}
local function CollectReminders()
    local c = DB.remind
    local lines = {}
    if c.enabled and not InCombatLockdown() and not UnitIsDeadOrGhost("player") and not UnitOnTaxi("player") then
        for _, entry in ipairs(c.self) do
            local learned = Learned(entry)
            if #learned > 0 and HasBuff("player", learned, false) == false then
                lines[#lines + 1] = { learned[1].iconID, Label(learned) .. " missing" }
            end
        end
        -- one line per missing buff, naming everyone who lacks it, in the order first seen
        local missing = {}
        local function miss(learned, u)
            local label = Label(learned) .. " missing"
            if not missing[label] then
                missing[label] = { learned[1].iconID, {} }
                missing[#missing + 1] = label
            end
            local who = missing[label][2]
            who[#who + 1] = UnitLabel(u)
        end
        for _, u in ipairs((c.party or c.target) and AllyUnits() or {}) do
            -- a class with its own blessing (Wisdom for casters, Might for melee) is reminded of that one
            local ok, _, class = pcall(UnitClass, u)
            local pick = ok and Readable(class, "string") and c.byClass[class]
            local wanted = pick and pick ~= "" and Learned(pick)
            if wanted and #wanted > 0 then
                if HasBuff(u, wanted, true) == false and not OutOfRange(wanted[1].spellID, u) then miss(wanted, u) end
            else
                for _, entry in ipairs(c.ally) do
                    local learned = Learned(entry)
                    if #learned > 0 and HasBuff(u, learned, true) == false and not OutOfRange(learned[1].spellID, u) then miss(learned, u) end
                end
            end
        end
        for _, label in ipairs(missing) do
            lines[#lines + 1] = { missing[label][1], label .. ": " .. table.concat(missing[label][2], ", ") }
        end
    end
    -- a sample line while unlocked or in Edit Mode, so there's something to place
    if #lines == 0 and c.enabled and (not c.locked or ns.Kit.editMode or (ns.euiUnlockMode and not InCombatLockdown())) then
        lines[1] = { "Interface/Icons/Spell_Holy_FistOfJustice", "Buff reminder" }
    end
    return lines
end
-- Stacks { icon, text } lines in root's pool, building missing ones with make(root). Returns the widest line's width.
local function Render(root, lines, make)
    local c = DB.remind
    local width = 1
    for i, line in ipairs(lines) do
        local l = root.items[i] or make(root)
        root.items[i] = l
        l:SetSize(c.size, c.size)
        l.icon:SetSize(c.size, c.size)
        l.icon:SetTexture(line[1])
        l.text:SetText(line[2])
        Appearance.ApplyReminder(l)
        l:SetWidth(c.size + 6 + l.text:GetStringWidth())
        l:ClearAllPoints()
        l:SetPoint("TOP", 0, -(i - 1) * (c.size + c.gap))
        l:Show()
        width = math.max(width, l:GetWidth())
    end
    for i = #lines + 1, #root.items do
        local line = root.items[i]
        line:Hide(); line.text:SetText(""); line.icon:SetTexture(nil)
    end
    root:SetSize(width, math.max(1, #lines * (c.size + c.gap) - c.gap))
    return width
end

local function UpdateRemind(renderOnly)
    if not remindRoot then return end
    if not renderOnly then reminderLines = CollectReminders() end
    Render(remindRoot, reminderLines, TrackerLine)
    remindRoot:SetShown(#reminderLines > 0)
end

function Reminders.Init()
    if remindRoot then return end
    remindRoot = Frames.MakeRoot("Remind", "remind")
end

function Reminders.ApplyConfiguration(effects)
    if effects.data then wipe(learnedEntries) end
    UpdateRemind(not (effects.data or effects.visibility))
end

function Reminders.Root() return remindRoot end
Reminders.Update = UpdateRemind
Reminders.Learned = Learned
Reminders.Label = Label
Reminders.NewLine = NewLine
Reminders.Render = Render
