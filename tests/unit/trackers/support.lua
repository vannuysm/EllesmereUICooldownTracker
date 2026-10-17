return function(ctx)
local M, ns = ctx.mocks, ctx.ns
local function Empty()
    assert(ns.Profiles.Apply({ cd = { spells = {}, visibility = "always" }, buff = { spells = {} }, remind = { self = {}, ally = {} }, ranks = { enabled = false } }))
end
local function Spell(name, id, pet)
    local info = { name = name, spellID = id, iconID = id + 1000 }
    M.spellInfo[name], M.spellInfo[id] = info, info
    if pet then M.petKnown[id] = true else M.known[id] = true end
    return info
end
local function Prepare()
    M.Flush()
    M.combat, M.spells, M.attackable, M.friendly = false, false, false, false
    M.auras, M.unreadable, M.spellInfo, M.known, M.petKnown, M.bags = {}, {}, {}, {}, {}, {}
    M.units, M.classes, M.sameUnits, M.outOfRange, M.cooldowns = {}, {}, {}, {}, {}
    M.targetInParty, M.now = false, 100
    ns.euiUnlockMode, ns.euiBuffUnlock = false, false
    M.timers = {}
    Empty()
    M.calls = {}
end
local function Aura(name, id, duration, source)
    return { name = name, auraInstanceID = id, spellId = id, duration = duration or 30,
        expirationTime = M.now + (duration or 30), icon = id + 1000, sourceUnit = source or "player" }
end
local function Calls(key) return M.calls[key] or 0 end
return { Empty = Empty, Spell = Spell, Prepare = Prepare, Aura = Aura, Calls = Calls }
end
