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

-- On Midnight-era clients, reading auras while they're secret (in combat, encounters) doesn't
-- return secret values to addon code: the aura API raises "Auras cannot be accessed when secret
-- while tainted". So every read checks Locked() first, and is pcall'd as a backstop.
function Auras:Locked()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret then return true end
    end
    return InCombatLockdown and InCombatLockdown() or false
end

-- Raw aura by index, or nil, "locked" when auras can't be read right now.
function Auras:GetRawAuraByIndex(unit, index, filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) or self:Locked() then return nil, "locked" end
    local ok, raw = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter or "HELPFUL")
    if not ok then return nil, "locked" end
    return raw
end

-- Look up one of the player's buffs by spell ID. Returns nil, "locked" when auras are secret.
function Auras:GetPlayerAura(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    if self:Locked() then return nil, "locked" end
    local ok, raw = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return nil, "locked" end
    return sanitize(raw)
end

-- Iterate a unit's helpful auras. callback(auraCopy) returns true to stop early.
-- Returns "secret" if any aura was hidden, or "locked" if auras can't be read at all right
-- now, so callers can keep their last state or show a fallback.
function Auras:ForEachBuff(unit, callback, filter)
    local hidden
    for i = 1, 255 do
        local raw, why = self:GetRawAuraByIndex(unit, i, filter)
        if why then return why end
        if not raw then break end
        local aura, why2 = sanitize(raw)
        if aura then
            if callback(aura) then break end
        elseif why2 then
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
