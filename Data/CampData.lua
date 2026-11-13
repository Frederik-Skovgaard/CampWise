-- CampWise camp data. Every ID here comes from community guides of the launch build
-- (wowforever.be, foreverwisp.com, Sep-Nov 2026) and must be confirmed in the client
-- with /cw auras or /dump C_Spell.GetSpellInfo(id). Entries marked verified = false are unconfirmed.
local _, ns = ...

local D = {}
ns.Data = D

-- Buffs the camp system puts on the player.
D.CampAuras = {
    CAMPFIRE_NEARBY    = { spellID = 1283391, name = "Campfire Nearby",    verified = true },
    WELCOMING_CAMPFIRE = { spellID = 1229739, name = "Welcoming Campfire", verified = true },  -- guides said 1289723; client shows 1229739. Short timer (~10s seen), turns into Camp Benefits
    CAMP_BENEFITS      = { spellID = 1229741, name = "Camp Benefits",      verified = true }, -- one buff holding every object's effect
    BOOSTED_REST       = { spellID = 1229451, name = "Boosted Rest",       verified = false }, -- DEBUFF: Camp Tent lockout, 1 hour (confirmed it's a debuff; ID unconfirmed, also matched by name)
    WELL_RESTED        = { spellID = 429959,  name = "Well-Rested",        verified = true }, -- Cozy Sleeping Bag
}

-- Well Fed has many spell IDs (one per food). Match by name or icon instead; filled in during step 2.
D.WellFedNames = { "Well Fed" }

-- Campfires (Cooking). slots = how many camp objects the fire allows.
D.Campfires = {
    { key = "BASIC",      name = "Basic Campfire",      spellID = 1229737, cooking = 1,   slots = 3,  woodItem = 4470 },
    { key = "JOURNEYMAN", name = "Journeyman Campfire", spellID = 1283400, cooking = 140, slots = 5,  woodItem = 11291, blueprintItem = 273087 },
    { key = "EXPERT",     name = "Expert Campfire",     spellID = 1291341, cooking = 220, slots = 10, woodItem = 272941, blueprintItem = 273101 },
}
D.FIRE_DURATION = 600        -- about 10 minutes
D.FIRE_COOLDOWN = 300        -- 5 minutes
D.OBJECT_COOLDOWN = 3600     -- shared 1 hour cooldown, one object per character
D.CAMP_BUFF_DURATION = 3600          -- 1 hour from a normal campfire
D.CAMP_BUFF_DURATION_BOOSTED = 7200  -- 2 hours and doubled effects from the purple campfire (Twitch drop item)
-- The purple campfire's buff. Matched by name (English client); its spell ID is learned
-- the first time it's seen and stored in CampWiseDB.violetSpellID.
D.VIOLET_FLAMES_NAME = "Violet Flames"

D.Items = {
    FLINT_AND_TINDER = 4471,
    SIMPLE_WOOD = 4470,
    STAR_WOOD = 11291,
    THICK_LOGS = 272941,
    CAMP_TENT = 279978,
    COZY_SLEEPING_BAG = 211527,
    SCARLET_BANNER = 278030,
}

-- Items shown on the camp bar when they're in your bags, in this order.
D.BarItems = { 4471, 279978, 211527, 278030 } -- Flint and Tinder, Camp Tent, Cozy Sleeping Bag, Scarlet Banner

-- Stat keys the advisor compares. A camp object "covers" one stat; the advisor
-- recommends objects whose stat nobody in the party already has.
D.Stats = {
    MP5 = "Mana regen", STR = "Strength", AP = "Attack Power", STA = "Stamina",
    INT = "Intellect", SPI = "Spirit", CRIT = "Crit", ALL = "All stats",
    ARMOR = "Armor and resistances", RESTED = "Rested XP", UTILITY = "Utility",
}

-- Camp objects. tier 1 = skill 20, tier 2 = 140, tier 3 = 300.
-- Higher tiers keep the tier 1 buff of the same profession and add a feature.
-- amount = the guide's "up to" value; nil when no guide shows it.
D.Objects = {
    -- Tier 1
    { spellID = 1230564, name = "Mana Well",        prof = "Alchemy",        tier = 1, stat = "MP5",    amount = 29 },
    { spellID = 1230171, name = "Sharpening Wheel", prof = "Blacksmithing",  tier = 1, stat = "STR",    amount = 34 }, -- confirmed Strength in game (showed +6 at low level),
    { spellID = 1230643, name = "Enchanted Lute",   prof = "Enchanting",     tier = 1, stat = "ARMOR" },
    { spellID = 1230117, name = "First Aid Kit",    prof = "First Aid",      tier = 1, stat = "STA",    amount = 56 },
    { spellID = 1229745, name = "Fish Bowl",        prof = "Fishing",        tier = 1, stat = "ALL",    amount = 8, percent = true },
    { spellID = 1229705, name = "Incense Candle",   prof = "Herbalism",      tier = 1, stat = "INT",    amount = 25 },
    { spellID = 1229432, name = "Camp Tent",        prof = "Leatherworking", tier = 1, stat = "RESTED", amount = 5, percent = true, item = 279978 },
    { spellID = 1230161, name = "Lodestone",        prof = "Mining",         tier = 1, stat = "AP",     amount = 90 },
    { spellID = 1229517, name = "Camp Chair",       prof = "Skinning",       tier = 1, stat = "CRIT",   amount = 2, percent = true },
    { spellID = 1263425, name = "Faction Banner",   prof = "Tailoring",      tier = 1, stat = "SPI",    amount = 32 },
    { spellID = 1230656, name = "Reagent Bot",      prof = "Engineering",    tier = 1, stat = "UTILITY" },
    -- Tier 2
    { spellID = 1263005, name = "Fermenter",        prof = "Alchemy",        tier = 2, stat = "MP5" },
    { spellID = 1263041, name = "Anvil",            prof = "Blacksmithing",  tier = 2, stat = "STR" },
    { spellID = 1262978, name = "Cookie's Feast",   prof = "Cooking",        tier = 2, stat = "STA" },
    { spellID = 1263056, name = "Arcane Salvager",  prof = "Enchanting",     tier = 2, stat = "ARMOR" },
    { spellID = 1263034, name = "Repair Bot",       prof = "Engineering",    tier = 2, stat = "UTILITY" },
    { spellID = 1262996, name = "Toxin Study",      prof = "First Aid",      tier = 2, stat = "STA" },
    { spellID = 1262990, name = "Fishing Rack",     prof = "Fishing",        tier = 2, stat = "ALL" },
    { spellID = 1262980, name = "Greenhouse",       prof = "Herbalism",      tier = 2, stat = "INT" },
    { spellID = 1263031, name = "Tanning Rack",     prof = "Leatherworking", tier = 2, stat = "RESTED" },
    { spellID = 1262975, name = "Rock Garden",      prof = "Mining",         tier = 2, stat = "STR" },
    { spellID = 1262985, name = "Field Guide",      prof = "Skinning",       tier = 2, stat = "CRIT" },
    { spellID = 1263032, name = "Spinning Wheel",   prof = "Tailoring",      tier = 2, stat = "SPI" },
    -- Tier 3
    { spellID = 1263078, name = "Alchemy Laboratory",        prof = "Alchemy",        tier = 3, stat = "MP5" },
    { spellID = 1263073, name = "Master Forge",              prof = "Blacksmithing",  tier = 3, stat = "STR" },
    { spellID = 1263067, name = "Iron Oven",                 prof = "Cooking",        tier = 3, stat = "UTILITY" },
    { spellID = 1263082, name = "Arcane Forge",              prof = "Enchanting",     tier = 3, stat = "ARMOR" },
    { spellID = 1263083, name = "Anarchist's Workbench",     prof = "Engineering",    tier = 3, stat = "UTILITY" },
    { spellID = 1263001, name = "Plague Doctor's Laboratory", prof = "First Aid",     tier = 3, stat = "STA" },
    { spellID = 1262998, name = "Fishing Hut",               prof = "Fishing",        tier = 3, stat = "ALL" },
    { spellID = 1263070, name = "Seed Hybridizer",           prof = "Herbalism",      tier = 3, stat = "INT" },
    { spellID = 1263079, name = "Sewing Machine",            prof = "Leatherworking", tier = 3, stat = "RESTED" },
    { spellID = 1263071, name = "Molten Foundry",            prof = "Mining",         tier = 3, stat = "STR" },
    { spellID = 1262982, name = "Trapper's Workbench",       prof = "Skinning",       tier = 3, stat = "CRIT" },
    { spellID = 1263080, name = "Loom",                      prof = "Tailoring",      tier = 3, stat = "SPI" },
}

-- Lookup tables built once.
D.ObjectBySpell, D.CampAuraBySpell = {}, {}
for _, obj in ipairs(D.Objects) do D.ObjectBySpell[obj.spellID] = obj end
for key, aura in pairs(D.CampAuras) do
    aura.key = key
    D.CampAuraBySpell[aura.spellID] = aura
end
