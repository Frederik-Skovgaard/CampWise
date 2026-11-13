-- CampWise Advisor. Step 4: "what to place next".
-- Scores each camp object you can craft by how many people in your group it helps,
-- skipping professions already at the camp and stats a class buff in the group already covers
-- (camp buffs don't stack with those). The winner's craft button gets a gold glow.
local _, ns = ...
local Advisor = ns:NewModule("Advisor")
ns.Advisor = Advisor

local issecret = issecretvalue or function() return false end

-- Who benefits from each stat.
local MANA_CLASSES = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true, PALADIN = true, HUNTER = true }
local PHYSICAL_CLASSES = { WARRIOR = true, ROGUE = true, PALADIN = true, SHAMAN = true, DRUID = true, HUNTER = true }
local STAT_USERS = {
    INT = MANA_CLASSES, MP5 = MANA_CLASSES, SPI = MANA_CLASSES,
    STR = PHYSICAL_CLASSES, AP = PHYSICAL_CLASSES,
}
-- Extra weight for stats that are worth more than a flat bonus.
local STAT_WEIGHT = { ALL = 1.5, CRIT = 1.2 }

-- Class buffs that cover a camp stat (by English name). Arcane Intellect and Fortitude
-- come from the guides; Divine Spirit is an assumption until checked in game.
local COVERED_BY = {
    ["Arcane Intellect"] = "INT", ["Arcane Brilliance"] = "INT",
    ["Power Word: Fortitude"] = "STA", ["Prayer of Fortitude"] = "STA",
    ["Divine Spirit"] = "SPI", ["Prayer of Spirit"] = "SPI",
}

local function groupUnits()
    local units = { "player" }
    if IsInRaid and IsInRaid() then
        units = {}
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do
            if UnitExists("party" .. i) then units[#units + 1] = "party" .. i end
        end
    end
    return units
end

-- Stats already covered by a class buff on anyone in the group.
local function coveredStats(units)
    local covered = {}
    for _, unit in ipairs(units) do
        ns.Auras:ForEachBuff(unit, function(a)
            local stat = COVERED_BY[a.name]
            if stat then covered[stat] = a.name end
        end)
    end
    return covered
end

local function benefits(stat, units)
    if stat == "UTILITY" then return 0 end
    if stat == "RESTED" then
        local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
        local n = 0
        for _, u in ipairs(units) do if (UnitLevel(u) or maxLevel) < maxLevel then n = n + 1 end end
        return n
    end
    local users = STAT_USERS[stat]
    if not users then return #units end
    local n = 0
    for _, u in ipairs(units) do
        local _, class = UnitClass(u)
        if class and not issecret(class) and users[class] then n = n + 1 end
    end
    return n
end

-- Work out the suggestion from the craft entries on the bar.
-- Returns { [spellID] = { score, reason } } and the best spell ID (or nil).
function Advisor:Evaluate(craftIDs)
    local units = groupUnits()
    local covered = coveredStats(units)
    local results, best, bestScore = {}, nil, 0
    for _, id in ipairs(craftIDs) do
        local obj = ns.Data.ObjectBySpell[id]
        if obj then
            local r = {}
            if ns.Camp:HasProfession(obj.prof) then
                r.score, r.reason = 0, "already at this camp"
            elseif covered[obj.stat] then
                r.score, r.reason = 0, ("%s already covers this"):format(covered[obj.stat])
            else
                local n = benefits(obj.stat, units)
                r.score = n * (STAT_WEIGHT[obj.stat] or 1)
                if obj.stat == "UTILITY" then
                    r.reason = "no stat buff"
                else
                    r.reason = ("helps %d of %d in your group"):format(n, #units)
                end
            end
            results[id] = r
            if r.score > bestScore then best, bestScore = id, r.score end
        end
    end
    return results, best
end

-- Called by the bar after each layout: glow the suggested button.
function Advisor:Apply(buttons)
    if not ns.db.advisor.enabled then
        for _, b in ipairs(buttons) do if b.suggestGlow then b.suggestGlow:Hide() end end
        self.best, self.results = nil, {}
        return
    end
    local ids = {}
    for _, b in ipairs(buttons) do
        if b.entry and b.entry.kind == "craft" and b:IsShown() then ids[#ids + 1] = b.entry.id end
    end
    self.results, self.best = self:Evaluate(ids)
    for _, b in ipairs(buttons) do
        if not b.suggestGlow then
            local g = b:CreateTexture(nil, "OVERLAY", nil, 3)
            g:SetPoint("TOPLEFT", -6, 6)
            g:SetPoint("BOTTOMRIGHT", 6, -6)
            g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            g:SetBlendMode("ADD")
            g:SetVertexColor(1, 0.85, 0.2)
            b.suggestGlow = g
        end
        b.suggestGlow:SetShown(b:IsShown() and b.entry and b.entry.kind == "craft" and b.entry.id == self.best or false)
    end
end

-- Tooltip line for a craft button.
function Advisor:AddToTooltip(tt, spellID)
    local r = self.results and self.results[spellID]
    if not r then return end
    if spellID == self.best then
        tt:AddLine("CampWise suggests placing this: " .. r.reason, 1, 0.85, 0.2, true)
    else
        tt:AddLine("Not suggested: " .. r.reason, 0.7, 0.7, 0.7, true)
    end
end

function Advisor:Print()
    if not self.results then ns:Print("no suggestion yet. Get near a campfire first.") return end
    if not self.best then ns:Print("nothing to suggest: everything you can craft is already here or covered.") return end
    local obj = ns.Data.ObjectBySpell[self.best]
    ns:Print(("place next: %s (%s)"):format(obj.name, self.results[self.best].reason))
end

function Advisor:OnEnable()
    local refresh = function() if ns.Bar then ns.Bar:Layout() end end
    ns:RegisterEvent("GROUP_ROSTER_UPDATE", refresh)
    -- Party members' class buffs change without a player UNIT_AURA; re-check every few seconds.
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(5, function()
            if ns.Bar and ns.Bar.frame and ns.Bar.frame:IsShown() and not InCombatLockdown() then
                Advisor:Apply(ns.Bar.frame.buttons)
            end
        end)
    end
end
