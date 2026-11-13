-- CampWise Pins (V2). Shows shared camps on the world map and the minimap.
-- Pins are plain frames placed on the map canvas, so no XML templates are needed.
local _, ns = ...
local Pins = ns:NewModule("Pins")
ns.Pins = Pins

local FIRE_ICON = "Interface\\Icons\\Spell_Fire_Fire"
local VIOLET = { 0.75, 0.5, 1 }
local NORMAL = { 1, 0.65, 0.2 }

-- Minimap view diameter in yards for each zoom level.
local MINIMAP_SIZE = {
    indoor = { [0] = 300, 240, 180, 120, 80, 50 },
    outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 },
}

-- ---------------------------------------------------------------- shared pin look

local function makePin(parent, size)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(size, size)
    p.ring = p:CreateTexture(nil, "BACKGROUND")
    p.ring:SetPoint("CENTER")
    p.ring:SetSize(size + 6, size + 6)
    p.ring:SetTexture("Interface\\Buttons\\WHITE8x8")
    p.ringMask = p:CreateMaskTexture()
    p.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.ringMask:SetAllPoints(p.ring)
    p.ring:AddMaskTexture(p.ringMask)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetAllPoints()
    p.icon:SetTexture(FIRE_ICON)
    p.iconMask = p:CreateMaskTexture()
    p.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    p.iconMask:SetAllPoints(p.icon)
    p.icon:AddMaskTexture(p.iconMask)
    p:EnableMouse(true)
    p:SetScript("OnEnter", function(self) Pins:ShowTooltip(self) end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return p
end

local function colorPin(p, camp)
    local c = camp.violet and VIOLET or NORMAL
    p.ring:SetVertexColor(c[1], c[2], c[3], 1)
    p.camp = camp
end

local function fillTooltip(tt, c)
    tt:SetText(c.own and "Your camp" or "Shared camp", 1, 0.82, 0)
    if c.violet then
        tt:AddLine("Purple campfire (Violet Flames)", VIOLET[1], VIOLET[2], VIOLET[3])
        tt:AddLine("Doubled camp effects, lasting 2 hours", VIOLET[1], VIOLET[2], VIOLET[3])
    end
    -- No objects yet means nobody has camp data for this fire yet, so say nothing.
    for _, name in ipairs(c.objects or {}) do tt:AddLine("  " .. tostring(name), 1, 1, 1) end
    local ago = math.floor((GetTime() - (tonumber(c.lastSeen) or GetTime())) / 60)
    local who = (type(c.sender) == "string" and not (issecretvalue and issecretvalue(c.sender))) and c.sender or "?"
    tt:AddLine("Reported by " .. who .. ", " .. (ago < 1 and "just now" or (ago .. " min ago")), 0.6, 0.6, 0.6)
    tt:AddLine("Location is where the player sat, within a few yards.", 0.5, 0.5, 0.5, true)
end

local reported = false
function Pins:ShowTooltip(pin)
    local c = pin.camp
    if not c then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    local ok, err = pcall(fillTooltip, GameTooltip, c)
    if not ok and not reported then
        reported = true -- once per session, so hovering doesn't spam chat
        ns:Print("|cffff4444pin tooltip error (please report):|r " .. tostring(err))
    end
    -- Always finish with Show, which sizes the box to all the lines added.
    GameTooltip:Show()
end

-- Position of a camp on another map (for zone/continent views), or nil.
local function campPosOnMap(camp, mapID)
    if camp.mapID == mapID then return camp.x, camp.y end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local continentID, worldPos = C_Map.GetWorldPosFromMapPos(camp.mapID, CreateVector2D(camp.x, camp.y))
    if not continentID then return nil end
    local _, mapPos = C_Map.GetMapPosFromWorldPos(continentID, worldPos, mapID)
    if not mapPos then return nil end
    local x, y = mapPos:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return x, y
end

-- Hide pins from index `from` on. Pins still in use are never hidden and re-shown, so a
-- pin under the mouse keeps its tooltip instead of flickering every redraw.
local function hideFrom(pins, from)
    for i = from, #pins do
        if pins[i]:IsShown() then
            if GameTooltip:GetOwner() == pins[i] then GameTooltip:Hide() end
            pins[i]:Hide()
        end
    end
end

-- If the mouse is over a pin, rebuild its tooltip (the camp's contents may have changed).
local function refreshHoveredTooltip()
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.camp and owner.ring and owner:IsShown() then Pins:ShowTooltip(owner) end
end

-- ---------------------------------------------------------------- world map

function Pins:RefreshWorldMap()
    local wm = WorldMapFrame
    if not (wm and wm:IsShown() and wm.ScrollContainer) then return end
    local canvas = wm.ScrollContainer.Child or (wm.GetCanvas and wm:GetCanvas())
    if not canvas then return end
    self.worldPins = self.worldPins or {}
    self.worldShown = false
    if not ns.db.share.worldmap then hideFrom(self.worldPins, 1) return end
    local mapID = wm:GetMapID()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = wm.ScrollContainer.GetCanvasScale and wm.ScrollContainer:GetCanvasScale() or 1
    local n = 0
    for _, camp in ipairs(ns.Share:CampsInZone()) do
        local x, y = campPosOnMap(camp, mapID)
        if x then
            n = n + 1
            local p = self.worldPins[n]
            if not p then
                p = makePin(canvas, 20)
                p:SetFrameStrata("HIGH")
                self.worldPins[n] = p
            end
            p:SetParent(canvas)
            p:SetScale(1 / scale)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", x * w * scale, -y * h * scale)
            colorPin(p, camp)
            p:Show()
            self.worldShown = true
        end
    end
    hideFrom(self.worldPins, n + 1)
end

-- ---------------------------------------------------------------- minimap

function Pins:RefreshMinimap()
    self.miniPins = self.miniPins or {}
    if #ns.Share.camps == 0 and not self.miniShown then return end -- nothing to draw or clear
    self.miniShown = false
    local function clear() hideFrom(self.miniPins, 1) end
    if #ns.Share.camps == 0 then return clear() end
    if not (ns.db.share.minimap and Minimap and Minimap:IsShown()) then return clear() end
    local mapID, px, py = ns.Share.PlayerMapPos()
    if not mapID or not (C_Map and C_Map.GetMapWorldSize) then return clear() end
    local mw, mh = C_Map.GetMapWorldSize(mapID)
    if not mw or mw == 0 then return clear() end
    local sizes = (IsIndoors and IsIndoors()) and MINIMAP_SIZE.indoor or MINIMAP_SIZE.outdoor
    local radiusYards = (sizes[Minimap:GetZoom()] or sizes[0]) / 2
    local radiusPx = Minimap:GetWidth() / 2
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = rotate and GetPlayerFacing and GetPlayerFacing() or 0
    if issecretvalue and issecretvalue(facing) then facing = 0 end
    local n = 0
    for _, camp in ipairs(ns.Share:CampsInZone()) do
        local cx, cy = campPosOnMap(camp, mapID)
        if cx then
            local east, south = (cx - px) * mw, (cy - py) * mh
            if rotate and facing then
                local s, c = math.sin(facing), math.cos(facing)
                east, south = east * c - south * s, east * s + south * c
            end
            local dist = math.sqrt(east * east + south * south)
            if dist <= radiusYards * 0.95 then
                n = n + 1
                local p = self.miniPins[n]
                if not p then
                    p = makePin(Minimap, 14)
                    p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
                    self.miniPins[n] = p
                end
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", east / radiusYards * radiusPx, -south / radiusYards * radiusPx)
                colorPin(p, camp)
                p:Show()
                self.miniShown = true
            end
        end
    end
    hideFrom(self.miniPins, n + 1)
end

-- ---------------------------------------------------------------- refresh

function Pins:Refresh()
    self.worldKey = nil
    self:RefreshWorldMap()
    self:RefreshMinimap()
    refreshHoveredTooltip()
end

function Pins:OnEnable()
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnShow", function() Pins:RefreshWorldMap() end)
        if WorldMapFrame.OnMapChanged then
            hooksecurefunc(WorldMapFrame, "OnMapChanged", function() Pins:RefreshWorldMap() end)
        end
        -- Pins sit on the canvas, so panning moves them for free. Re-place them only when the
        -- map, the zoom or the canvas size changes (checked cheaply a few times a second).
        local t = 0
        WorldMapFrame:HookScript("OnUpdate", function(wm, dt)
            t = t + dt
            if t < 0.2 then return end
            t = 0
            if #ns.Share.camps == 0 and not Pins.worldShown then return end
            local sc = wm.ScrollContainer
            local canvas = sc and (sc.Child or (wm.GetCanvas and wm:GetCanvas()))
            if not canvas then return end
            local key = ("%s:%.4f:%.1f:%.1f"):format(tostring(wm:GetMapID()),
                sc.GetCanvasScale and sc:GetCanvasScale() or 1, canvas:GetWidth(), canvas:GetHeight())
            if key ~= Pins.worldKey then
                Pins.worldKey = key
                Pins:RefreshWorldMap()
            end
        end)
    end
    -- Only camps in your current zone are drawn, so redraw when you change zone.
    ns:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Pins:Refresh() end)
    -- Minimap pins move as you move, so update them often.
    local mt = 0
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        mt = mt + dt
        if mt > 0.25 then mt = 0 Pins:RefreshMinimap() end
    end)
end
