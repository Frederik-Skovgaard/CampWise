-- CampWise Camp. Works out which objects are at the current camp by reading the
-- Camp Benefits buff tooltip, which lists one "Object: effect" line per placed object.
-- Only objects whose benefit you've received are listed: objects placed after you sat
-- down show up the next time you sit.
local _, ns = ...
local Camp = ns:NewModule("Camp")
ns.Camp = Camp

local issecret = issecretvalue or function() return false end

-- Find Camp Benefits and return the tooltip lines and the aura, or nil.
local function campBenefitLines()
    if not (C_TooltipInfo and C_UnitAuras) then return nil end
    local benefitsID = ns.Data.CampAuras.CAMP_BENEFITS.spellID
    for i = 1, 255 do
        local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not a then return nil end
        if not issecret(a.spellId) and a.spellId == benefitsID then
            local data
            if C_TooltipInfo.GetUnitBuffByAuraInstanceID and a.auraInstanceID then
                data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", a.auraInstanceID)
            elseif C_TooltipInfo.GetUnitAura then
                data = C_TooltipInfo.GetUnitAura("player", i, "HELPFUL")
            end
            return data and data.lines, ns.Auras.Sanitize(a)
        end
    end
end

local objectByName
local function findObject(name)
    if not objectByName then
        objectByName = {}
        for _, o in ipairs(ns.Data.Objects) do objectByName[o.name] = o end
    end
    return objectByName[name]
end

-- Camp Benefits and the tent's Boosted Rest last an hour, so they follow you to the next
-- fire. A camp's contents only count if the aura was applied after you arrived at this
-- fire. Arrival = Campfire Nearby appearing; a short walk away (under LEAVE_GRACE) keeps it.
local SLACK, LEAVE_GRACE = 15, 60

function Camp:UpdateArrival()
    local char, now = ns.char, GetTime()
    if not char then return end
    local near = ns.Bar and ns.Bar:NearFire()
    -- arrivedAt is a GetTime() value, which restarts with the PC. arrivedEpoch is the same
    -- moment in real time; if the two no longer agree, the saved arrival is stale.
    if char.arrivedAt then
        local stale = char.arrivedAt > now or not char.arrivedEpoch
            or math.abs((time() - char.arrivedEpoch) - (now - char.arrivedAt)) > 30
        if stale then char.arrivedAt, char.arrivedEpoch, char.leftAt = nil, nil, nil end
    end
    if near then
        if not char.arrivedAt or (char.leftAt and now - char.leftAt > LEAVE_GRACE) then
            char.arrivedAt, char.arrivedEpoch = now, time()
            self.seen = {} -- new fire: forget objects hovered at the last one
        end
        char.leftAt = nil
    elseif char.arrivedAt and not char.leftAt then
        char.leftAt = now
    end
end

-- True if this aura (a sanitized copy) was applied since you arrived at the current fire.
function Camp:IsFromThisCamp(aura)
    local arrived = ns.char and ns.char.arrivedAt
    if not (aura and arrived) or ns.char.leftAt then return false end
    if not aura.duration or aura.duration <= 0 or not aura.expirationTime then return false end
    return aura.expirationTime - aura.duration >= arrived - SLACK
end

-- The Camp Tent's Boosted Rest debuff, if it was gained at this camp.
function Camp:TentHere()
    local data = ns.Data.CampAuras.BOOSTED_REST
    local tent = ns.Auras:GetPlayerAura(data.spellID)
    if not tent then
        ns.Auras:ForEachBuff("player", function(a)
            if a.name == data.name then tent = a return true end
        end, "HARMFUL")
    end
    return self:IsFromThisCamp(tent)
end

-- Re-read the camp. self.placed = list of { name, effect, obj } from your Camp Benefits buff.
-- self.here = the same list but only when that buff came from the fire you're at now,
-- self.byProf[prof] = entry in self.here.
function Camp:Scan()
    self:UpdateArrival()
    local placed, byProf = {}, {}
    local lines, aura = campBenefitLines()
    local fresh = self:IsFromThisCamp(aura)
    for _, line in ipairs(lines or {}) do
        local text = line.leftText
        if text and not issecret(text) then
            -- The description is one tooltip line with embedded newlines; check each piece.
            for piece in text:gmatch("[^\r\n]+") do
                local name, effect = piece:match("^%s*([^:]-)%s*:%s*(%S.*)$")
                -- Skip the "Gained the following camp benefits:" header and time lines like "51:00".
                if name and name ~= "" and not name:match("^%d") then
                    local entry = { name = name, effect = effect, obj = findObject(name) }
                    placed[#placed + 1] = entry
                    if entry.obj and fresh then byProf[entry.obj.prof] = entry end
                end
            end
        end
    end
    local function key(list)
        local names = {}
        for i, p in ipairs(list or {}) do names[i] = p.name end
        return table.concat(names, ",")
    end
    local here = {}
    if fresh then for i, p in ipairs(placed) do here[i] = p end end
    -- Objects you've hovered at this fire count too. That's how a Camp Tent shows up while
    -- your tent lockout from an earlier camp stops it giving you Boosted Rest.
    local have = {}
    for _, p in ipairs(here) do have[p.name] = true end
    for name in pairs(self.seen or {}) do
        if not have[name] then
            local entry = { name = name, effect = "seen here", obj = findObject(name) }
            here[#here + 1] = entry
            if entry.obj then byProf[entry.obj.prof] = entry end
        end
    end
    local changed = key(placed) ~= key(self.placed) or key(here) ~= key(self.here)
    self.placed, self.here, self.byProf, self.active = placed, here, byProf, lines ~= nil
    self.fresh = fresh
    if changed and ns.Bar then ns.Bar:Layout() end
end

-- Hovering a camp object in the world shows its name in GameTooltip; remember it for this fire.
-- Only world objects count: their tooltip is anchored to UIParent/WorldFrame and carries no
-- spell, item or unit. That skips your own Craft buttons (recipe tooltips share the object's
-- name), the Camp Tent in your bags, action bars and players.
local BLOCKED_TYPES
local function isWorldObjectTooltip(tt)
    local owner = tt.GetOwner and tt:GetOwner()
    if owner ~= UIParent and owner ~= WorldFrame then return false end
    if UnitExists and UnitExists("mouseover") then return false end -- a player or NPC
    if tt.GetSpell then
        local _, spellID = tt:GetSpell()
        if spellID then return false end
    end
    if tt.GetItem then
        local _, link = tt:GetItem()
        if link then return false end
    end
    if tt.GetTooltipData and Enum and Enum.TooltipDataType then
        local ok, data = pcall(tt.GetTooltipData, tt)
        if ok and data and data.type ~= nil and not issecret(data.type) then
            if not BLOCKED_TYPES then
                local T = Enum.TooltipDataType
                BLOCKED_TYPES = {}
                for _, k in ipairs({ "Spell", "Item", "Unit", "Macro", "Toy", "Mount", "Totem",
                                     "UnitAura", "Currency", "Achievement", "Quest" }) do
                    if T[k] ~= nil then BLOCKED_TYPES[T[k]] = true end
                end
            end
            if BLOCKED_TYPES[data.type] then return false end
        end
    end
    return true
end
Camp.IsWorldObjectTooltip = isWorldObjectTooltip

function Camp:OnTooltip(tt)
    if not (ns.Bar and ns.Bar:NearFire()) then return end
    if not isWorldObjectTooltip(tt) then return end
    local fs = _G[tt:GetName() .. "TextLeft1"]
    local text = fs and fs:GetText()
    if not text or issecret(text) then return end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local obj = findObject(text)
    if not obj then return end
    self.seen = self.seen or {}
    if not self.seen[obj.name] then
        self.seen[obj.name] = true
        self:Scan()
    end
end

function Camp:HasProfession(prof)
    return self.byProf and self.byProf[prof] ~= nil
end

-- Adds an "At this camp" list to a tooltip.
function Camp:AddToTooltip(tt)
    local near = ns.Bar and ns.Bar:NearFire()
    -- Near a fire, list only what that fire gave you; away from one, what your buff still carries.
    -- With nothing to list (no camp data yet), say nothing.
    local header = near and "At this camp" or "Your camp buff"
    local list = near and self.here or self.placed
    if #list == 0 then return end
    tt:AddLine(" ")
    tt:AddLine(("%s (%d):"):format(header, #list), 1, 0.82, 0)
    for _, p in ipairs(list) do
        tt:AddDoubleLine(p.name, p.obj and p.obj.prof or "", 1, 1, 1, 0.6, 0.6, 0.6)
    end
end

function Camp:Print()
    local near = ns.Bar and ns.Bar:NearFire()
    if near then
        local list = self.here
        if self.active and not self.fresh then
            ns:Print("your Camp Benefits buff is from an earlier camp, so it doesn't count here.")
        end
        if #list == 0 then ns:Print("no camp data for this fire yet. Sit down and it fills in once you get Camp Benefits.") return end
        ns:Print(("objects at this camp (%d):"):format(#list))
        for _, p in ipairs(list) do ns:Print(("  %s: %s"):format(p.name, p.effect)) end
        return
    end
    if not self.active then ns:Print("no Camp Benefits buff. Sit by a fire for a minute first.") return end
    if #self.placed == 0 then ns:Print("your camp buff lists no objects.") return end
    ns:Print(("your camp buff (not at a fire) (%d):"):format(#self.placed))
    for _, p in ipairs(self.placed) do ns:Print(("  %s: %s"):format(p.name, p.effect)) end
end

function Camp:OnInit()
    self.placed, self.here, self.byProf, self.active = {}, {}, {}, false
    self.seen = {}
end

function Camp:OnEnable()
    ns:OnAuraChanged(function() Camp:Scan() end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() Camp:Scan() end)
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function(tt) Camp:OnTooltip(tt) end)
    end
    self:Scan()
end
