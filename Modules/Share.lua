-- CampWise Share (V2). Tells other CampWise users where your camp is and what's at it,
-- and keeps a list of camps others have reported.
--
-- When you sit at a fire (Welcoming Campfire appears) your position is saved as the camp's
-- location. While you stay near that fire, the camp is shared once a minute with your
-- party/raid and your guild, and, only if you turn it on, every CampWise user on the realm
-- through a hidden channel.
--
-- Message (version 2): C2|mapID|x|y|flags|spellID;spellID;...
--   x, y   = map position * 1000 (0-1000), flags = "v" for Violet Flames or "-"
--   Objects are sent as their recipe spell IDs from Data.Objects. Anything not in that list is
--   dropped, so received text is never shown. Version 1 (2.0.0, object names) is still read,
--   but only names found in Data.Objects are kept.
local _, ns = ...
local Share = ns:NewModule("Share")
ns.Share = Share

local PREFIX = "CampWise"
local CHANNEL_NAME = "CampWiseShare"
local SEND_EVERY = 60        -- seconds between broadcasts of your own camp
local CAMP_TTL = 600         -- a camp disappears 10 min after its last report (fires last ~10 min)
local MERGE_YARDS = 50       -- reports closer than this are the same camp
local MIN_SEND_GAP = 15       -- never send your own camp more often than this
local MIN_GAP_PER_SENDER = 10 -- receivers drop a sender's messages closer together than this
local MAX_CAMPS = 200
local MAX_NEW_PER_MINUTE = 20 -- new camps accepted from others per minute
local MAX_OBJECTS = 12

local issecret = issecretvalue or function() return false end

-- ---------------------------------------------------------------- position helpers

local function playerMapPos()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or issecret(mapID) then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x or issecret(x) or issecret(y) or (x == 0 and y == 0) then return nil end
    return mapID, x, y
end
Share.PlayerMapPos = playerMapPos

-- The zone a map belongs to: walks up from sub-zone, city and cave maps to the zone map,
-- so a camp reported from inside a town still counts as being in that zone.
local zoneCache = {}
local function zoneOf(mapID)
    if not mapID then return nil end
    if zoneCache[mapID] then return zoneCache[mapID] end
    local id = mapID
    if C_Map and C_Map.GetMapInfo then
        local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        for _ = 1, 10 do
            local info = C_Map.GetMapInfo(id)
            if not info or not info.mapType or info.mapType <= ZONE or not info.parentMapID or info.parentMapID == 0 then break end
            id = info.parentMapID
        end
    end
    zoneCache[mapID] = id
    return id
end
Share.ZoneOf = zoneOf

-- The zone you're in now, or nil if the game won't say.
function Share:PlayerZone()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or issecret(mapID) then return nil end
    return zoneOf(mapID)
end

-- Camps in your current zone. Camps elsewhere are kept (they show again when you get
-- there, if still fresh) but aren't drawn or listed, so they don't clutter your map.
function Share:CampsInZone()
    local zone, list = self:PlayerZone(), {}
    if not zone then return list end
    for _, c in ipairs(self.camps) do
        if zoneOf(c.mapID) == zone then list[#list + 1] = c end
    end
    return list
end

-- Distance in yards between two points on the same map, or nil if the map size is unknown.
local function yardsBetween(mapID, x1, y1, x2, y2)
    if not (C_Map and C_Map.GetMapWorldSize) then return nil end
    local w, h = C_Map.GetMapWorldSize(mapID)
    if not w or w == 0 then return nil end
    local dx, dy = (x2 - x1) * w, (y2 - y1) * h
    return math.sqrt(dx * dx + dy * dy)
end
Share.YardsBetween = yardsBetween

-- ---------------------------------------------------------------- encoding

local objectBySpell, objectByName
local function lookups()
    if not objectBySpell then
        objectBySpell, objectByName = {}, {}
        for _, o in ipairs(ns.Data.Objects) do
            objectBySpell[o.spellID] = o
            objectByName[o.name] = o
        end
    end
    return objectBySpell, objectByName
end

function Share:Encode(camp)
    local _, byName = lookups()
    local ids, seen = {}, {}
    for _, name in ipairs(camp.objects or {}) do
        local o = byName[name]
        if o and not seen[o.spellID] and #ids < MAX_OBJECTS then
            seen[o.spellID] = true
            ids[#ids + 1] = tostring(o.spellID)
        end
    end
    return ("C2|%d|%d|%d|%s|%s"):format(camp.mapID, math.floor(camp.x * 1000 + 0.5),
        math.floor(camp.y * 1000 + 0.5), camp.violet and "v" or "-", table.concat(ids, ";"))
end

-- Returns a camp table or nil for anything malformed. Object names always come from
-- Data.Objects, never from the message.
function Share:Decode(msg)
    if type(msg) ~= "string" or #msg > 255 then return nil end
    local ver, mapID, x, y, flags, objs = msg:match("^C(%d+)|(%d+)|(%d+)|(%d+)|([v%-])|(.*)$")
    if ver ~= "1" and ver ~= "2" then return nil end
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if not mapID or x > 1000 or y > 1000 then return nil end
    if C_Map and C_Map.GetMapInfo and not C_Map.GetMapInfo(mapID) then return nil end
    local bySpell, byName = lookups()
    local objects, seen = {}, {}
    for token in objs:gmatch("[^;]+") do
        local o
        if ver == "2" then o = bySpell[tonumber(token:match("^%d+$") or "")]
        else o = byName[token] end
        if o and not seen[o.name] and #objects < MAX_OBJECTS then
            seen[o.name] = true
            objects[#objects + 1] = o.name
        end
    end
    return { mapID = mapID, x = x / 1000, y = y / 1000, violet = flags == "v", objects = objects }
end

-- ---------------------------------------------------------------- camp list

-- Add or refresh a camp. Same map and within MERGE_YARDS = same camp.
-- Your own camp is only ever changed by your own reports; others can't rewrite it.
function Share:AddReport(camp, sender, now)
    now = now or GetTime()
    if camp.own then
        -- Only one "Your camp": the previous fire stops being yours.
        for _, c in ipairs(self.camps) do c.own = nil end
    end
    for _, c in ipairs(self.camps) do
        if c.mapID == camp.mapID then
            local d = yardsBetween(c.mapID, c.x, c.y, camp.x, camp.y)
            local same = d and d <= MERGE_YARDS or (not d and math.abs(c.x - camp.x) < 0.01 and math.abs(c.y - camp.y) < 0.01)
            if same then
                c.lastSeen = now
                if camp.own then
                    -- Your own report always carries the most exact spot and your own data.
                    c.x, c.y, c.own, c.sender = camp.x, camp.y, true, sender
                    if #camp.objects > 0 then c.objects = camp.objects end
                    c.violet = camp.violet
                elseif not c.own then
                    c.sender = sender
                    -- A report without objects means "no data yet", not "empty", so it never
                    -- wipes the list; anyone at the fire with camp data fills it in.
                    if #camp.objects > 0 and #camp.objects >= #c.objects then c.objects = camp.objects end
                    -- The newest report decides, so one wrong "purple" report doesn't stick.
                    c.violet = camp.violet
                end
                c.reports = (c.reports or 1) + 1
                self:Changed()
                return c
            end
        end
    end
    if not camp.own then
        -- Cap how many new camps others can add per minute.
        if not self.newWindow or now - self.newWindow >= 60 then self.newWindow, self.newCount = now, 0 end
        if self.newCount >= MAX_NEW_PER_MINUTE then return nil end
        self.newCount = self.newCount + 1
    end
    camp.firstSeen, camp.lastSeen, camp.sender, camp.reports = now, now, sender, 1
    table.insert(self.camps, camp)
    if #self.camps > MAX_CAMPS then
        -- Drop the least recently reported camp that isn't yours.
        local oldest
        for i, c in ipairs(self.camps) do
            if not c.own and (not oldest or c.lastSeen < self.camps[oldest].lastSeen) then oldest = i end
        end
        if oldest then table.remove(self.camps, oldest) end
    end
    self:Changed()
    return camp
end

function Share:Prune(now)
    now = now or GetTime()
    local removed = false
    for i = #self.camps, 1, -1 do
        if now - self.camps[i].lastSeen > CAMP_TTL then
            table.remove(self.camps, i)
            removed = true
        end
    end
    for sender, t in pairs(self.lastFrom) do
        if now - t > MIN_GAP_PER_SENDER then self.lastFrom[sender] = nil end
    end
    if removed then self:Changed() end
end

function Share:Changed()
    if ns.Pins then ns.Pins:Refresh() end
end

-- ---------------------------------------------------------------- receiving

function Share:OnMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX or not ns.db.share.receive then return end
    if issecret(msg) or issecret(sender) then return end
    if sender == self:MyFullName() or sender == UnitName("player") then return end
    local short = Ambiguate and Ambiguate(sender, "short") or sender
    -- Simple flood guard: one message per sender every few seconds.
    local now = GetTime()
    if self.lastFrom[sender] and now - self.lastFrom[sender] < MIN_GAP_PER_SENDER then return end
    self.lastFrom[sender] = now
    local camp = self:Decode(msg)
    if camp then
        camp.channel = channel
        self:AddReport(camp, short, now)
    end
end

-- ---------------------------------------------------------------- sending

-- "Name-Realm", the form CHAT_MSG_ADDON uses for senders.
function Share:MyFullName()
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    name = name or UnitName("player")
    if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- The hidden channel is only needed while realm-wide sharing is on.
function Share:WantsPublic()
    local s = ns.db.share
    return s.enabled and s.public
end

function Share:PublicChannelID()
    if not GetChannelName then return nil end
    local id = GetChannelName(CHANNEL_NAME)
    if id and id > 0 then return id end
end

-- Join the hidden public channel and keep it out of the chat windows.
function Share:JoinPublic()
    if not self:WantsPublic() or self:PublicChannelID() or not JoinTemporaryChannel then return end
    JoinTemporaryChannel(CHANNEL_NAME)
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            for i = 1, (NUM_CHAT_WINDOWS or 10) do
                local cf = _G["ChatFrame" .. i]
                if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, CHANNEL_NAME) end
            end
        end)
    end
end

function Share:LeavePublic()
    if self:PublicChannelID() and LeaveChannelByName then LeaveChannelByName(CHANNEL_NAME) end
end

-- Join or leave the hidden channel to match the settings.
function Share:SyncChannel()
    if self:WantsPublic() then self:JoinPublic() else self:LeavePublic() end
end

-- Returns false if the client refused or throttled the message.
local function send(msg, channel, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return true end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, channel, target)
    if not ok or result == false then return false end
    -- Newer clients return Enum.SendAddonMessageResult; 0 = Success.
    if type(result) == "number" and result ~= 0 then return false end
    return true
end

function Share:AddOwnPin(camp)
    self:AddReport({ mapID = camp.mapID, x = camp.x, y = camp.y, violet = camp.violet,
        objects = camp.objects or {}, own = true }, UnitName("player"))
end

function Share:Broadcast(camp)
    local s = ns.db.share
    if not s.enabled then return end
    local msg = self:Encode(camp)
    local allOk = true
    if s.group then
        if IsInRaid and IsInRaid() then allOk = send(msg, "RAID") and allOk
        elseif IsInGroup and IsInGroup() then allOk = send(msg, "PARTY") and allOk end
    end
    if s.guild and IsInGuild and IsInGuild() then allOk = send(msg, "GUILD") and allOk end
    if self:WantsPublic() then
        local id = self:PublicChannelID()
        if id then allOk = send(msg, "CHANNEL", id) and allOk else self:JoinPublic() end
    end
    self.lastSent = GetTime()
    -- Throttled: try again after the minimum gap instead of waiting a full minute.
    self.dirty = not allOk
    -- Your own camp goes on your map too, so you can see what others see.
    self:AddOwnPin(camp)
    ns:Debug("shared camp", msg)
end

-- Your own camp: located where you sat down, kept while you're near the fire.
-- Expects Camp:Scan to have run first (it runs before this on aura changes and in Tick).
function Share:UpdateOwnCamp()
    local near = ns.Bar and ns.Bar:NearFire()
    if not near then self.own = nil return end
    -- Only Welcoming Campfire proves you're sitting right at the fire. Camp Benefits can be
    -- left over from an earlier camp and Campfire Nearby reaches ~100 yards, so neither is
    -- used for the location. Each time you sit, the spot is refreshed.
    local sitting = ns.Auras:GetPlayerAura(ns.Data.CampAuras.WELCOMING_CAMPFIRE.spellID)
    if sitting then
        local mapID, x, y = playerMapPos()
        if mapID then
            local moved = not self.own or self.own.mapID ~= mapID
                or (yardsBetween(mapID, self.own.x, self.own.y, x, y) or 999) > 3
            if moved then
                self.own = self.own or {}
                self.own.mapID, self.own.x, self.own.y = mapID, x, y
                self.dirty = true -- share the corrected spot soon
            end
        end
    end
    if self.own then
        local objects = {}
        -- Only what this fire gave you: Camp Benefits and the tent debuff can be left over
        -- from an earlier camp.
        -- Only objects CampWise knows can be shared, so only those go on your own pin too.
        for _, p in ipairs(ns.Camp.here or {}) do
            if p.obj then objects[#objects + 1] = p.obj.name end
        end
        local hasTent = false
        for _, name in ipairs(objects) do if name == "Camp Tent" then hasTent = true end end
        if not hasTent and ns.Camp:TentHere() then
            objects[#objects + 1] = "Camp Tent"
        end
        -- Purple campfire: Violet Flames counts if it has no timer (only while at the fire)
        -- or was gained at this fire, so a leftover one doesn't mark the wrong camp.
        local vf = ns.Auras:GetVioletFlames()
        local violet = vf ~= nil and ((vf.duration or 0) <= 0 or ns.Camp:IsFromThisCamp(vf))
        local key = table.concat(objects, ";") .. (violet and "v" or "")
        if self.own.key and self.own.key ~= key then
            self.dirty = true -- contents changed: share again soon, not in a minute
        end
        local changed = self.dirty or self.own.key ~= key
        self.own.key = key
        self.own.objects = objects
        self.own.violet = violet
        -- Your own pin shows changes right away; sending to others waits for the send gap.
        if changed and self.lastSent then self:AddOwnPin(self.own) end
    end
end

-- Send your camp if it's due: every SEND_EVERY seconds, or sooner after a change, but never
-- within MIN_SEND_GAP of the last send. A change inside the gap is sent when the gap ends.
function Share:MaybeSend()
    if not self.own then return end
    local now = GetTime()
    local since = self.lastSent and now - self.lastSent
    if not since or since >= SEND_EVERY or (self.dirty and since >= MIN_SEND_GAP) then
        self.dirty = false
        self:Broadcast(self.own)
    elseif self.dirty and not self.sendQueued and C_Timer and C_Timer.After then
        self.sendQueued = true
        C_Timer.After(MIN_SEND_GAP - since + 0.1, function()
            Share.sendQueued = false
            Share:MaybeSend()
        end)
    end
end

function Share:Tick()
    self:Prune()
    ns.Camp:Scan()
    self:UpdateOwnCamp()
    self:MaybeSend()
end

-- ---------------------------------------------------------------- setup

function Share:OnInit()
    self.camps, self.lastFrom = {}, {}
end

function Share:OnEnable()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    ns:RegisterEvent("CHAT_MSG_ADDON", function(_, ...) Share:OnMessage(...) end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if C_Timer and C_Timer.After then C_Timer.After(5, function() Share:JoinPublic() end) end
    end)
    -- Sitting down starts sharing straight away instead of waiting for the next tick.
    -- Runs after Camp:Scan in the same batched aura update.
    ns:OnAuraChanged(function()
        Share:UpdateOwnCamp()
        Share:MaybeSend()
    end)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(10, function() Share:Tick() end)
    end
end

function Share:Print()
    self:Prune()
    local camps = self:CampsInZone()
    if #camps == 0 then ns:Print("no shared camps in this zone right now.") return end
    ns:Print(("shared camps in this zone (%d):"):format(#camps))
    for _, c in ipairs(camps) do
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(c.mapID)
        ns:Print(("  %s %.1f, %.1f by %s, %d min ago: %s%s"):format(info and info.name or c.mapID,
            c.x * 100, c.y * 100, c.sender or "?", math.floor((GetTime() - c.lastSeen) / 60),
            #c.objects > 0 and table.concat(c.objects, ", ") or "no objects known yet", c.violet and " (purple campfire)" or ""))
    end
end
