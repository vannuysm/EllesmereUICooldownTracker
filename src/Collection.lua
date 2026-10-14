-- Game queries and dependency caches. No frames or saved variables are owned here.
local _, ns = ...
local S = { spellRevision = 0, bagRevision = 0 }
ns.Collection = S
local spells, bags, matches, auras
spells, matches, auras = {}, {}, {}

function S.Readable(value, kind)
    return type(value) == kind and not (issecretvalue and issecretvalue(value))
end
local Plain = S.Readable
local function AuraFields(aura) return aura.name, aura.sourceUnit end

function S.InvalidateSpells()
    wipe(spells)
    S.spellRevision = S.spellRevision + 1
end
function S.InvalidateBags()
    bags = nil; wipe(matches)
    S.bagsUnknown = false
    S.bagRevision = S.bagRevision + 1
end
function S.Spell(name)
    if spells[name] == nil then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        spells[name] = ok and type(info) == "table" and Plain(info.spellID, "number") and Plain(info.name, "string") and info or false
    end
    return spells[name] or nil
end

function S.Bags()
    if bags then return bags end
    bags = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return bags end
    for bag = 0, 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        if not ok or not Plain(slots, "number") then S.bagsUnknown = true end
        for slot = 1, ok and Plain(slots, "number") and slots or 0 do
            local found, item = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if found and type(item) == "table" and Plain(item.itemName, "string") and Plain(item.itemID, "number") then
                bags[#bags + 1] = { id = item.itemID, icon = item.iconFileID, name = item.itemName:lower(),
                    count = Plain(item.stackCount, "number") and item.stackCount or 1 }
            elseif not found or type(item) == "table" then S.bagsUnknown = true
            end
        end
    end
    return bags
end
function S.Item(text)
    local key = text:lower()
    if matches[key] == nil then
        local first, count = nil, 0
        for _, item in ipairs(S.Bags()) do
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
function S.InvalidateAuras(unit)
    if unit then
        if auras[unit] then auras[unit].valid = false end
    else for _, snapshot in pairs(auras) do snapshot.valid = false end end
end
function S.Auras(unit)
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
function S.FindBuff(snapshot, prefix)
    local want = prefix:lower()
    for _, entry in ipairs(snapshot) do
        if entry and entry.name:lower():find(want, 1, true) == 1 then return entry.aura, false end
    end
    return nil, snapshot.unknown
end
function S.HasBuff(snapshot, learned, mine)
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
function S.AuraDelta(info)
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
function S.AuraInstance(delta, id)
    local record = delta.instances[id]
    if not record then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
        record = { ok, aura }; delta.instances[id] = record
    end
    return record[1], record[2]
end
function S.AuraDuration(unit, id, cache)
    if not C_UnitAuras.GetAuraDuration or type(id) == "nil" then return nil end
    local key = Plain(id, "number") and id
    if key and cache and cache[key] ~= nil then return cache[key] or nil end
    local ok, duration = pcall(C_UnitAuras.GetAuraDuration, unit, id)
    if key and cache then cache[key] = ok and duration or false end
    return ok and duration or nil
end

-- Reuse resolution entries as state records; collect first, then hand them to the renderer.
function S.Cooldowns(entries, kind, ids)
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
