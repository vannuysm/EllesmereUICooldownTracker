-- Class presets for new characters and the reminder editors.
local _, ns = ...
local Defaults = {}
ns.Defaults = Defaults
Defaults.BLESSING_CLASSES = { "WARRIOR", "ROGUE", "HUNTER", "PALADIN", "SHAMAN", "DRUID", "PRIEST", "MAGE", "WARLOCK" }
Defaults.CLASS_BLESSING = { MAGE = "Blessing of Wisdom", WARLOCK = "Blessing of Wisdom", PRIEST = "Blessing of Wisdom",
    WARRIOR = "Blessing of Might", ROGUE = "Blessing of Might", PALADIN = "", DRUID = "", SHAMAN = "", HUNTER = "" }
Defaults.BLESSINGS = "Blessing of Might / Blessing of Wisdom / Blessing of Kings / Blessing of Salvation / Blessing of Light / Blessing of Sanctuary"
-- What a new character of each class starts with. Unlearned spells stay hidden until learned, so low levels see few icons.
-- cd: cooldown icons. buff: bars for your own timed buffs (a name matches any buff starting with it).
-- self / ally: buff reminders on you / on party members and a friendly target (" / " = any of these counts).
Defaults.CLASS_DEFAULTS = {
    PALADIN = { cd = { "Divine Protection", "Lay on Hands", "Hammer of Justice" }, buff = { "Seal of" },
        self = { Defaults.BLESSINGS }, ally = { Defaults.BLESSINGS } },
    WARRIOR = { cd = { "Bloodrage", "Berserker Rage", "Intercept", "Shield Wall", "Recklessness", "Retaliation" },
        buff = { "Battle Shout", "Enrage" }, self = { "Battle Shout" }, ally = {} },
    ROGUE = { cd = { "Kick", "Sprint", "Evasion", "Blind", "Vanish" }, buff = { "Slice and Dice", "Blade Flurry", "Adrenaline Rush" },
        self = {}, ally = {} },
    HUNTER = { cd = { "Rapid Fire", "Feign Death", "Freezing Trap", "Deterrence", "Bestial Wrath" }, buff = { "Rapid Fire", "Aspect of" },
        self = { "Aspect of the Hawk / Aspect of the Monkey / Aspect of the Cheetah / Aspect of the Pack / Aspect of the Wild / Aspect of the Beast", "Trueshot Aura" },
        ally = {} },
    PRIEST = { cd = { "Fade", "Psychic Scream", "Inner Focus", "Power Infusion" }, buff = { "Power Word: Shield", "Inner Fire" },
        self = { "Power Word: Fortitude / Prayer of Fortitude", "Inner Fire", "Divine Spirit / Prayer of Spirit" },
        ally = { "Power Word: Fortitude / Prayer of Fortitude", "Divine Spirit / Prayer of Spirit" } },
    SHAMAN = { cd = { "Earth Shock", "Grounding Totem", "Elemental Mastery", "Nature's Swiftness", "Mana Tide Totem", "Reincarnation" },
        buff = { "Lightning Shield" }, self = { "Lightning Shield" }, ally = {} },
    MAGE = { cd = { "Counterspell", "Blink", "Frost Nova", "Cone of Cold", "Evocation", "Ice Block" }, buff = { "Ice Barrier", "Mana Shield" },
        self = { "Arcane Intellect / Arcane Brilliance", "Frost Armor / Ice Armor / Mage Armor" },
        ally = { "Arcane Intellect / Arcane Brilliance" } },
    WARLOCK = { cd = { "Death Coil", "Howl of Terror", "Fel Domination", "Amplify Curse", "Shadowburn" }, buff = { "Shadow Ward" },
        self = { "Demon Skin / Demon Armor" }, ally = {} },
    DRUID = { cd = { "Barkskin", "Innervate", "Nature's Swiftness", "Bash", "Rebirth", "Tranquility" }, buff = { "Thorns" },
        self = { "Mark of the Wild / Gift of the Wild", "Thorns" }, ally = { "Mark of the Wild / Gift of the Wild" } },
}
for class, d in pairs(Defaults.CLASS_DEFAULTS) do
    if class == "WARLOCK" then table.insert(d.cd, "Spell Lock") end   -- the felhunter's
    table.insert(d.cd, "Healthstone")
    table.insert(d.cd, "Healing Potion")
    if class ~= "WARRIOR" and class ~= "ROGUE" then table.insert(d.cd, "Mana Potion") end
end
function Defaults.ForPlayer()
    local ok, _, class = pcall(UnitClass, "player")
    return Defaults.CLASS_DEFAULTS[ok and type(class) == "string" and class or ""] or Defaults.CLASS_DEFAULTS.PALADIN
end
