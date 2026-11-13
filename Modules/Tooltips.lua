-- CampWise Tooltips. Step 3: adds a short "what this does at camp" line to camp spells and items.
local _, ns = ...
local Tooltips = ns:NewModule("Tooltips")
ns.Tooltips = Tooltips

local issecret = issecretvalue or function() return false end
local HEADER_COLOR = { 1, 0.6, 0.2 }
local TEXT_COLOR = { 0.9, 0.9, 0.9 }

local TIER_SKILL = { 20, 140, 300 }

-- Text for one camp object, e.g. "+34 Strength for everyone at the camp".
local function objectLines(obj)
    local D = ns.Data
    local lines = {}
    local stat = D.Stats[obj.stat] or obj.stat
    local base = obj
    -- Higher tiers keep the tier 1 buff of the same profession; borrow its amount.
    if obj.tier > 1 and not obj.amount then
        for _, o in ipairs(D.Objects) do
            if o.prof == obj.prof and o.tier == 1 then base = o break end
        end
    end
    if obj.stat == "UTILITY" then
        lines[#lines + 1] = "No camp buff. Adds a service or workstation."
    elseif obj.stat == "RESTED" then
        lines[#lines + 1] = ("Rested XP, up to %d%% of a level"):format(base.amount or 5)
    elseif base.amount then
        lines[#lines + 1] = ("Camp buff: %s%d%s %s"):format("+", base.amount, base.percent and "%" or "", stat)
    else
        lines[#lines + 1] = ("Camp buff: %s"):format(stat)
    end
    if obj.tier > 1 then
        lines[#lines + 1] = "Keeps the tier 1 buff and adds a feature."
    end
    lines[#lines + 1] = ("%s, tier %d (skill %d)"):format(obj.prof, obj.tier, TIER_SKILL[obj.tier] or 0)
    if base.note then lines[#lines + 1] = "Note: " .. base.note end
    return lines
end

local function fireLines(fire)
    return {
        ("Fire holds %d camp objects and lasts about %d min."):format(fire.slots, ns.Data.FIRE_DURATION / 60),
        ("Needs Cooking %d."):format(fire.cooking),
    }
end

local function addLines(tooltip, lines)
    tooltip:AddLine(" ")
    tooltip:AddLine("CampWise", unpack(HEADER_COLOR))
    for _, l in ipairs(lines) do
        tooltip:AddLine(l, TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3], true)
    end
end

local fireBySpell, objectByItem
local function buildLookups()
    fireBySpell, objectByItem = {}, {}
    for _, f in ipairs(ns.Data.Campfires) do fireBySpell[f.spellID] = f end
    for _, o in ipairs(ns.Data.Objects) do
        if o.item then objectByItem[o.item] = o end
    end
end

local function linesForSpell(id)
    local obj = ns.Data.ObjectBySpell[id]
    if obj then return objectLines(obj) end
    local fire = fireBySpell[id]
    if fire then return fireLines(fire) end
    local aura = ns.Data.CampAuraBySpell[id]
    if aura and aura.key == "CAMP_BENEFITS" then
        return { "Every object at the camp in one buff. Lasts 1 hour, or 2 hours with doubled effects from a purple campfire." }
    end
end

local function linesForItem(id)
    local obj = objectByItem[id]
    if obj then return objectLines(obj) end
    -- Kits we've learned from the profession window: show what their recipe makes.
    for recipeID, itemID in pairs(ns.char.kitItems) do
        if itemID == id then return linesForSpell(recipeID) end
    end
    local I = ns.Data.Items
    if id == I.FLINT_AND_TINDER then return { "Lights a campfire." } end
    if id == I.SIMPLE_WOOD then return { "Fuel for a Basic Campfire." } end
    if id == I.STAR_WOOD then return { "Fuel for a Journeyman Campfire." } end
    if id == I.THICK_LOGS then return { "Fuel for an Expert Campfire." } end
end

local function onSpell(tooltip, data)
    if not ns.db.tooltips.enabled or not data or issecret(data.id) then return end
    local lines = linesForSpell(data.id)
    if lines then addLines(tooltip, lines) end
end

local function onItem(tooltip, data)
    if not ns.db.tooltips.enabled or not data or issecret(data.id) then return end
    local lines = linesForItem(data.id)
    if lines then addLines(tooltip, lines) end
end

-- Buff tooltips. Camp Benefits already explains itself in the game's own text, so it gets
-- nothing extra.
local function onAura(tooltip, data)
    if not ns.db.tooltips.enabled or not data or issecret(data.id) then return end
    local aura = ns.Data.CampAuraBySpell[data.id]
    if aura and aura.key == "CAMP_BENEFITS" then return end
    local lines = linesForSpell(data.id)
    if lines then addLines(tooltip, lines) end
end

function Tooltips:OnEnable()
    buildLookups()
    if TooltipDataProcessor and Enum.TooltipDataType then
        local T = Enum.TooltipDataType
        TooltipDataProcessor.AddTooltipPostCall(T.Spell, onSpell)
        TooltipDataProcessor.AddTooltipPostCall(T.Item, onItem)
        if T.UnitAura then TooltipDataProcessor.AddTooltipPostCall(T.UnitAura, onAura) end
    else
        -- Older tooltip API.
        GameTooltip:HookScript("OnTooltipSetSpell", function(tt)
            local _, id = tt:GetSpell()
            if id then onSpell(tt, { id = id }) end
        end)
        GameTooltip:HookScript("OnTooltipSetItem", function(tt)
            local _, link = tt:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then onItem(tt, { id = id }) end
        end)
    end
end
