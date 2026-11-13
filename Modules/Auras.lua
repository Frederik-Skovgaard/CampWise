-- CampWise aura reading. All aura access goes through here so the secret-value
-- handling from Midnight-era restrictions lives in one place.
local _, ns = ...
local Auras = ns:NewModule("Auras")
ns.Auras = Auras

-- issecretvalue exists on Midnight-era clients. Fall back to "never secret" elsewhere.
local issecret = issecretvalue or function() return false end

-- Returns a plain copy of the fields we use, or nil if the aura is missing or any field is secret.
local function sanitize(aura)
    if not aura then return nil end
    local id, exp, dur, name = aura.spellId, aura.expirationTime, aura.duration, aura.name
    if issecret(id) or issecret(exp) or issecret(dur) or issecret(name) then
        return nil, "secret"
    end
    return { spellID = id, name = name, expirationTime = exp, duration = dur, icon = aura.icon }
end
Auras.Sanitize = sanitize

-- Look up one of the player's buffs by spell ID.
function Auras:GetPlayerAura(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    return sanitize(C_UnitAuras.GetPlayerAuraBySpellID(spellID))
end

-- Iterate a unit's helpful auras. callback(auraCopy) returns true to stop early.
-- Returns "secret" if any aura was hidden, so callers can show a fallback state.
function Auras:ForEachBuff(unit, callback, filter)
    local hidden
    for i = 1, 255 do
        local raw = C_UnitAuras.GetAuraDataByIndex(unit, i, filter or "HELPFUL")
        if not raw then break end
        local aura, why = sanitize(raw)
        if aura then
            if callback(aura) then break end
        elseif why then
            hidden = "secret"
        end
    end
    return hidden
end

-- True if this aura is the purple campfire's Violet Flames buff. Remembers its spell ID.
function Auras:IsVioletFlames(a)
    if ns.db.violetSpellID and a.spellID == ns.db.violetSpellID then return true end
    if a.name == ns.Data.VIOLET_FLAMES_NAME then
        ns.db.violetSpellID = a.spellID
        return true
    end
    return false
end

function Auras:HasVioletFlames()
    return self:GetVioletFlames() ~= nil
end

-- The Violet Flames aura (sanitized copy), or nil.
function Auras:GetVioletFlames()
    local found
    self:ForEachBuff("player", function(a)
        if self:IsVioletFlames(a) then found = a return true end
    end)
    return found
end

-- Debug helper for /cw auras: lists camp-related buffs and anything unknown that looks camp-like.
function Auras:DumpAllAuras(unit)
    local hidden = self:ForEachBuff(unit, function(a)
        ns:Print(("%s (spell %d)"):format(a.name or "?", a.spellID or 0))
    end)
    self:ForEachBuff(unit, function(a)
        ns:Print(("%s (spell %d, debuff)"):format(a.name or "?", a.spellID or 0))
    end, "HARMFUL")
    if hidden then ns:Print("some auras are hidden (secret values), probably combat") end
end

function Auras:DumpCampAuras(unit)
    local found = 0
    local hidden = self:ForEachBuff(unit, function(a)
        local known = ns.Data.CampAuraBySpell[a.spellID] or ns.Data.ObjectBySpell[a.spellID] or self:IsVioletFlames(a)
        local looksCamp = a.name and (a.name:find("Camp") or a.name:find("Well Fed") or a.name:find("Rest"))
        if known or looksCamp then
            found = found + 1
            local left = a.expirationTime and a.expirationTime > 0 and (a.expirationTime - GetTime()) or 0
            ns:Print(("%s (spell %d) %s, %s"):format(a.name or "?", a.spellID or 0,
                known and "known" or "|cffffff00NEW, add to CampData|r",
                left > 0 and ("%.0fs left"):format(left) or "no timer"))
        end
    end)
    if found == 0 then ns:Print("no camp buffs on", unit) end
    if hidden then ns:Print("some auras are hidden (secret values), probably combat") end
end
