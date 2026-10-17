-- Game queries and dependency caches. No frames or saved variables are owned here.
local _, ns = ...
local Collection = { spellRevision = 0, bagRevision = 0 }
ns.Collection = Collection
local spells, matches, auras, bags = {}, {}, {}, nil

function Collection.Readable(value, kind)
    -- Secret values report their underlying type; a type check alone is insufficient for Lua operations.
    return type(value) == kind and not (issecretvalue and issecretvalue(value))
end
local Plain = Collection.Readable
local function AuraFields(aura) return aura.name, aura.sourceUnit end

function Collection.InvalidateSpells()
    wipe(spells)
    Collection.spellRevision = Collection.spellRevision + 1
end
function Collection.InvalidateBags()
    bags = nil; wipe(matches)
    Collection.bagsUnknown = false
    Collection.bagRevision = Collection.bagRevision + 1
end
function Collection.Spell(name)
    if spells[name] == nil then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        spells[name] = ok and type(info) == "table" and Plain(info.spellID, "number") and Plain(info.name, "string") and info or false
    end
    return spells[name] or nil
end

function Collection.Bags()
    if bags then return bags end
    bags = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return bags end
    for bag = 0, 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if not ok or not Plain(slots, "number") then Collection.bagsUnknown = true end
        for slot = 1, ok and Plain(slots, "number") and slots or 0 do
            local found, item = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if found and type(item) == "table" and Plain(item.itemName, "string") and Plain(item.itemID, "number") then
                bags[#bags + 1] = { id = item.itemID, icon = item.iconFileID, name = item.itemName:lower(),
                    count = Plain(item.stackCount, "number") and item.stackCount or 1 }
            elseif not found or type(item) == "table" then Collection.bagsUnknown = true
            end
        end
    end
    return bags
end
function Collection.Item(text)
    local key = text:lower()
    if matches[key] == nil then
        local first, count = nil, 0
        for _, item in ipairs(Collection.Bags()) do
            if item.name:find(key, 1, true) then
                first = first or item
                count = count + item.count
            end
        end
        matches[key] = first and { id = first.id, icon = first.icon, count = count } or false
    end
    return matches[key] or nil
end

-- Preserve unreadable positions in the scan: a reminder must not interpret them as an absent buff.
function Collection.InvalidateAuras(unit)
    if unit then
        if auras[unit] then auras[unit].valid = false end
    else for _, snapshot in pairs(auras) do snapshot.valid = false end end
end
function Collection.Auras(unit)
    if auras[unit] and auras[unit].valid then return auras[unit] end
    local snapshot, count = auras[unit] or {}, 0
    snapshot.unknown = false
    for index = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetBuffDataByIndex, unit, index)
        if ok and type(aura) == "nil" then break end
        count = index
        local readable, name, source = pcall(AuraFields, aura)
        if ok and readable and Plain(name, "string") then
            local entry = snapshot[index] or {}
            entry.aura, entry.name, entry.source = aura, name, source
            snapshot[index] = entry
        else
            snapshot[index] = false
            snapshot.unknown = true
        end
    end
    for index = count + 1, #snapshot do snapshot[index] = nil end
    snapshot.valid = true
    auras[unit] = snapshot
    return snapshot
end
function Collection.FindBuff(snapshot, prefix)
    local want = prefix:lower()
    for _, entry in ipairs(snapshot) do
        if entry and entry.name:lower():find(want, 1, true) == 1 then return entry.aura, false end
    end
    return nil, snapshot.unknown
end
function Collection.HasBuff(snapshot, learned, mine)
    for _, entry in ipairs(snapshot) do
        if not entry then return nil end
        for _, info in ipairs(learned) do
            if entry.name:find(info.name, 1, true) then
                if not mine then return true end
                if issecretvalue and issecretvalue(entry.source) then return nil end
                if entry.source == "player" then return true end
            end
        end
    end
    return false
end

-- Validate the payload once; unreadable/full updates use the snapshot path instead.
function Collection.AuraDelta(info)
    if not info then return nil end
    local ok, delta = pcall(function()
        if info.isFullUpdate then return nil end
        local out = { removed = {}, updated = {}, instances = {}, added = info.addedAuras or {} }
        for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
            if not Plain(id, "number") then error("unreadable aura ID") end
            out.removed[id] = true
        end
        for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
            if not Plain(id, "number") then error("unreadable aura ID") end
            out.updated[id] = true
        end
        -- Ensure added aura fields can be inspected before applying a partial update.
        for _, aura in ipairs(out.added) do
            if not Plain(aura.name, "string") then error("unreadable aura name") end
        end
        return out
    end)
    return ok and delta or nil
end
function Collection.AuraInstance(delta, id)
    local record = delta.instances[id]
    if not record then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
        record = { ok, aura }; delta.instances[id] = record
    end
    return record[1], record[2]
end
function Collection.AuraDuration(unit, id, cache)
    if not C_UnitAuras.GetAuraDuration or type(id) == "nil" then return nil end
    local key = Plain(id, "number") and id
    if key and cache and cache[key] ~= nil then return cache[key] or nil end
    local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
    if key and cache then cache[key] = ok and duration or false end
    return ok and duration or nil
end

-- Reuse resolution entries as state records; collect first, then hand them to the renderer.
function Collection.Cooldowns(entries, kind, ids)
    for _, entry in ipairs(entries) do
        if entry.spell and (not kind or kind == "spell") and (not ids or ids[entry.spell.spellID]) then
            local ok, cooldown = pcall(C_Spell.GetSpellCooldown, entry.spell.spellID)
            cooldown = ok and cooldown or nil
            entry.cooldown = cooldown
            entry.updated, entry.durationObject = true, nil
            local active = cooldown and (not Plain(cooldown.isActive, "boolean") or cooldown.isActive)
            local gcd = cooldown and Plain(cooldown.isOnGCD, "boolean") and cooldown.isOnGCD
            entry.active = active and not gcd
            entry.ready = cooldown ~= nil and Plain(cooldown.isActive, "boolean") and (not cooldown.isActive or gcd)
            if entry.active and C_Spell.GetSpellCooldownDuration then
                local hasDuration, duration = pcall(C_Spell.GetSpellCooldownDuration, entry.spell.spellID, true)
                if hasDuration then entry.durationObject = duration end
            end
        elseif entry.item and (not kind or kind == "item") then
            local ok, start, duration = pcall(C_Item.GetItemCooldown, entry.item.id)
            entry.itemOK, entry.start, entry.duration = ok, start, duration
            entry.active = ok and Plain(start, "number") and Plain(duration, "number") and duration > 1.5
            entry.updated = true
        else
            entry.updated = false
        end
    end
end

-- true or false from the spellbook, or nil when it can't answer readably. Pass a spell bank to ask about another book.
local function SpellBookKnows(...)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return nil end
    local ok, known = pcall(C_SpellBook.IsSpellKnown, ...)
    if ok and Plain(known, "boolean") then return known end
end
local function PlayerSpellKnown(spellID)
    local ok, known = pcall(IsPlayerSpell, spellID)
    return ok and Plain(known, "boolean") and known
end

local knownSpells, knownRevision = {}, -1
local function QueryKnownSpell(spellID)
    local known = SpellBookKnows(spellID)
    if known ~= nil then
        if known then return true end
        -- your pet's abilities are in the pet spellbook
        local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
        return pet ~= nil and SpellBookKnows(spellID, pet) == true
    end
    if not IsPlayerSpell then return true end
    return PlayerSpellKnown(spellID)
end
function Collection.KnownSpell(spellID)
    if knownRevision ~= Collection.spellRevision then wipe(knownSpells); knownRevision = Collection.spellRevision end
    if knownSpells[spellID] == nil then knownSpells[spellID] = QueryKnownSpell(spellID) == true end
    return knownSpells[spellID]
end

-- Procs fire UNIT_SPELLCAST_SUCCEEDED too, often under the seal's own name (Seal of Command's melee hit).
-- Only spells the player can actually cast count as a recast.
function Collection.IsOwnSpell(spellID)
    local known = SpellBookKnows(spellID)
    if known ~= nil then return known end
    return PlayerSpellKnown(spellID)
end

-- Only a definite out-of-range result dims an icon; no target, no range, or secret results leave it unchanged.
function Collection.OutOfRange(spellID, unit)
    local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
    return ok and Plain(inRange, "boolean") and not inRange
end
