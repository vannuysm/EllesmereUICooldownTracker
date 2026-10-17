-- Settings catalog: spellbook, bag contents and cursor entries.
local _, ns = ...
local Kit = ns.Kit
local Plain = Kit.Plain

-- Spells and items --------------------------------------------------------------------------------------------------
-- What an entry looks like: { name, icon, spellID, itemID, learned, count }. The game only finds learned spells by
-- name, so an icon seen once (added from search or the spellbook) is remembered in Kit.icons, which an addon may save.
Kit.icons = Kit.icons or {}
function Kit.SpellByName(name)
    local ok, info = pcall(C_Spell.GetSpellInfo, name)
    if ok and type(info) == "table" and Plain(info.spellID, "number") then return info end
end

-- Every spell in the spellbook, highest rank only, passives left out: { name, icon, spellID, rank }
function Kit.Spellbook()
    local out, seen = {}, {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return out end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local SPELL = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1
    local okN, lines = pcall(C_SpellBook.GetNumSpellBookSkillLines)
    for l = 1, okN and Plain(lines, "number") and lines or 0 do
        local okL, line = pcall(C_SpellBook.GetSpellBookSkillLineInfo, l)
        if okL and type(line) == "table" and not line.shouldHide then
            for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local ok, it = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
                if ok and type(it) == "table" and it.itemType == SPELL and not it.isPassive and Plain(it.name, "string") then
                    local rank = tonumber((Plain(it.subName, "string") and it.subName or ""):match("^%a+ (%d+)$") or "")
                    local prev = seen[it.name]
                    if not prev then
                        prev = { name = it.name, icon = it.iconID, spellID = it.spellID, rank = rank }
                        seen[it.name] = prev
                        out[#out + 1] = prev
                    elseif rank and (prev.rank or 0) < rank then
                        prev.icon, prev.spellID, prev.rank = it.iconID, it.spellID, rank
                    end
                    Kit.icons[it.name] = it.iconID
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Every item in your bags, one per name with the total count: { name, icon, itemID, count }
function Kit.Bags()
    local out, seen = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return out end
    for bag = 0, 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, ok and Plain(slots, "number") and slots or 0 do
            local ok2, it = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok2 and type(it) == "table" and Plain(it.itemName, "string") then
                local e = seen[it.itemName]
                if e then e.count = e.count + (it.stackCount or 1)
                else
                    e = { name = it.itemName, icon = it.iconFileID, itemID = it.itemID, count = it.stackCount or 1 }
                    seen[it.itemName] = e
                    out[#out + 1] = e
                end
                Kit.icons[it.itemName] = it.iconFileID
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- A spell or item from the cursor (dragged from the spellbook, an action button or your bags), as a name.
function Kit.CursorName()
    local ok, kind, a, b, c = pcall(GetCursorInfo)
    if not ok or not kind then return end
    if kind == "spell" or kind == "petaction" then
        -- the spell ID is the fourth value from the spellbook, the second from an action button; any may be missing
        for _, id in pairs({ [1] = c, [2] = a, [3] = b }) do
            local okS, name = pcall(C_Spell.GetSpellName, id)
            if type(id) == "number" and okS and Plain(name, "string") then
                local okI, icon = pcall(C_Spell.GetSpellTexture, id)
                if okI and icon then Kit.icons[name] = icon end
                return name
            end
        end
    elseif kind == "item" then
        local okI, name = pcall(C_Item.GetItemNameByID, a)
        if okI and Plain(name, "string") then
            ---@cast name string
            local okT, icon = pcall(C_Item.GetItemIconByID, a)
            if okT and icon then Kit.icons[name] = icon end
            return name
        end
    end
end
