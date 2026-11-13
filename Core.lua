-- CampWise core: namespace, saved variables, event dispatch, module registry, slash command.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.version = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
ns.modules = {}

-- Defaults. Account-wide settings live in CampWiseDB, per-character state in CampWiseCharDB.
local DB_DEFAULTS = {
    schema = 2,
    timers = { enabled = true, warnSeconds = 300, locked = false, point = nil,
        style = { bgColor = { 0, 0, 0 }, bgAlpha = 0.75, border = true, borderColor = { 0.75, 0.75, 0.75 },
                  borderAlpha = 1, fontSize = 11, textColor = { 1, 1, 1 }, titleColor = { 1, 0.82, 0 },
                  progressBars = true } },
    bar = { enabled = true, locked = false, point = nil, scale = 1, onlyNearFire = true,
        style = { bgColor = { 0, 0, 0 }, bgAlpha = 0.75, border = true, borderColor = { 0.75, 0.75, 0.75 },
                  borderAlpha = 1, fontSize = 10, useColor = { 0.35, 0.85, 0.35 }, craftColor = { 1, 0.6, 0.2 } } },
    tooltips = { enabled = true },
    advisor = { enabled = true },
    -- Realm-wide sharing ("public") sends your name and exact spot to every CampWise user on
    -- the realm, so it's opt-in. Party/raid and guild sharing are on by default.
    share = { enabled = true, group = true, guild = true, public = false, receive = true,
              worldmap = true, minimap = true },
    theme = "native", -- "native" (Blizzard), "flat" or "rustic"; see Modules/Style.lua
    debug = false,
}
ns.DB_DEFAULTS = DB_DEFAULTS
ns.applyDefaults = nil -- set below
local CHAR_DEFAULTS = {
    schema = 2,
    barItems = {}, -- item IDs the player pinned to the camp bar, in order
    kitItems = {}, -- recipe spell ID -> crafted kit item ID, learned when the profession opens
}

-- Fill missing keys from defaults without overwriting the player's values.
local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            applyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end
ns.applyDefaults = applyDefaults

function ns:Print(...)
    print("|cffff9933CampWise|r:", ...)
end

-- Ctrl + left click on a box toggles its position lock.
function ns:ToggleLock(box, label)
    local cfg = self.db[box]
    cfg.locked = not cfg.locked
    self:Print(label, cfg.locked and "locked" or "unlocked: drag to move")
end

function ns:Debug(...)
    if self.db and self.db.debug then
        print("|cff888888CampWise debug|r:", ...)
    end
end

-- Module registry. A module is a table with optional OnInit (after saved vars load)
-- and OnEnable (at PLAYER_LOGIN) methods.
function ns:NewModule(name)
    local mod = { name = name }
    self.modules[#self.modules + 1] = mod
    self.modules[name] = mod
    return mod
end

-- Event dispatch: ns:RegisterEvent(event, handler) where handler(event, ...) is called.
local frame = CreateFrame("Frame")
local handlers = {}

function ns:RegisterEvent(event, handler)
    if not handlers[event] then
        handlers[event] = {}
        frame:RegisterEvent(event)
    end
    table.insert(handlers[event], handler)
end

-- Unit events get their own frame per unit filter, so two modules can watch different units.
local unitFrames = {}
function ns:RegisterUnitEvent(event, handler, ...)
    local key = event .. ":" .. table.concat({ ... }, ",")
    local f = unitFrames[key]
    if not f then
        f = CreateFrame("Frame")
        f.handlers = {}
        f:RegisterUnitEvent(event, ...)
        f:SetScript("OnEvent", function(self, ev, ...)
            for i = 1, #self.handlers do
                local ok, err = pcall(self.handlers[i], ev, ...)
                if not ok then geterrorhandler()(err) end
            end
        end)
        unitFrames[key] = f
    end
    table.insert(f.handlers, handler)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            geterrorhandler()(err)
        end
    end
end)

-- The player's auras change many times a second in combat. Modules register here instead
-- of on UNIT_AURA, and all of them run once, shortly after the last change, in register order.
local auraHandlers, auraPending = {}, false
local AURA_DELAY = 0.1
function ns:OnAuraChanged(handler)
    auraHandlers[#auraHandlers + 1] = handler
end
local function runAuraHandlers()
    auraPending = false
    for i = 1, #auraHandlers do
        local ok, err = pcall(auraHandlers[i])
        if not ok then geterrorhandler()(err) end
    end
end
ns.RunAuraHandlers = runAuraHandlers
ns:RegisterUnitEvent("UNIT_AURA", function()
    if auraPending then return end
    auraPending = true
    if C_Timer and C_Timer.After then C_Timer.After(AURA_DELAY, runAuraHandlers) else runAuraHandlers() end
end, "player")

local function forEachModule(method)
    for _, mod in ipairs(ns.modules) do
        if mod[method] then
            local ok, err = pcall(mod[method], mod)
            if not ok then geterrorhandler()(err) end
        end
    end
end

ns:RegisterEvent("ADDON_LOADED", function(_, loaded)
    if loaded ~= ADDON_NAME then return end
    -- One-time move of settings saved under the old name (Campwise, lower-case w).
    if CampWiseDB == nil and CampwiseDB ~= nil then CampWiseDB = CampwiseDB end
    if CampWiseCharDB == nil and CampwiseCharDB ~= nil then CampWiseCharDB = CampwiseCharDB end
    CampwiseDB, CampwiseCharDB = nil, nil
    CampWiseDB = CampWiseDB or {}
    -- Schema 2 (2.0.1): realm-wide sharing became opt-in. Turn it off once for everyone who
    -- got it from the old default; they can turn it back on in /cw config.
    if (CampWiseDB.schema or 1) < 2 then
        if CampWiseDB.share then CampWiseDB.share.public = false end
        CampWiseDB.schema = 2
    end
    CampWiseDB = applyDefaults(CampWiseDB, DB_DEFAULTS)
    CampWiseCharDB = applyDefaults(CampWiseCharDB or {}, CHAR_DEFAULTS)
    ns.db = CampWiseDB
    -- First load with themes: start everyone on the Blizzard native colours.
    if not ns.db.themeApplied then
        ns.Style:SetTheme(ns.db.theme or "native")
        ns.db.themeApplied = true
    end
    ns.char = CampWiseCharDB
    forEachModule("OnInit")
end)

ns:RegisterEvent("PLAYER_LOGIN", function()
    forEachModule("OnEnable")
end)

-- Slash command: /campwise or /cw
SLASH_CAMPWISE1 = "/campwise"
SLASH_CAMPWISE2 = "/cw"
SlashCmdList.CAMPWISE = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("debug", ns.db.debug and "on" or "off")
    elseif cmd == "camps" then
        ns.Share:Print()
    elseif cmd == "share" then
        ns.db.share.enabled = not ns.db.share.enabled
        ns.Share:SyncChannel()
        ns:Print("sharing your camp", ns.db.share.enabled and "on" or "off")
    elseif cmd == "next" then
        ns.Advisor:Print()
    elseif cmd == "advisor" then
        ns.db.advisor.enabled = not ns.db.advisor.enabled
        ns:Print("suggestions", ns.db.advisor.enabled and "on" or "off")
        ns.Bar:Layout()
    elseif cmd == "camp" then
        ns.Camp:Print()
    elseif cmd == "auras all" then
        ns.Auras:DumpAllAuras("player")
    elseif cmd == "auras" then
        ns.Auras:DumpCampAuras("player")
    elseif cmd == "version" then
        ns:Print("version", ns.version)
    elseif cmd == "config" or cmd == "options" or cmd == "settings" then
        ns.Options:SafeToggle()
    elseif cmd:match("^bar") then
        ns.Bar:HandleCommand(strtrim(cmd:sub(4)))
    elseif cmd == "tooltips" then
        ns.db.tooltips.enabled = not ns.db.tooltips.enabled
        ns:Print("tooltips", ns.db.tooltips.enabled and "on" or "off")
    elseif cmd:match("^timers") then
        ns.Timers:HandleCommand(strtrim(cmd:sub(7)))
    else
        ns:Print("commands: /cw config, /cw timers, /cw bar, /cw camps, /cw share, /cw next, /cw camp, /cw advisor, /cw tooltips, /cw auras, /cw debug, /cw version")
    end
end
