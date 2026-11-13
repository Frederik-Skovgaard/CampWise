-- CampWise Timers. Step 2: camp buff and Well Fed timers.
-- Shows one row per tracked buff with time left, turns yellow/red as it runs low,
-- and prints a one-time warning when a buff drops below the warning threshold.
local _, ns = ...
local Timers = ns:NewModule("Timers")
ns.Timers = Timers

local ROW_HEIGHT, WIDTH = 18, 190
local issecretvalue_safe = issecretvalue or function() return false end
local UPDATE_INTERVAL = 0.5

-- Rows in display order. Keys match ns.Data.CampAuras, plus WELL_FED (matched by name).
local TRACKED = {
    { key = "CAMP_BENEFITS", label = "Camp Benefits" },
    { key = "WELL_FED",      label = "Well Fed" },
    { key = "BOOSTED_REST",  label = "Boosted Rest" },
    { key = "WELL_RESTED",   label = "Well-Rested" },
}

local function isWellFed(aura)
    for _, n in ipairs(ns.Data.WellFedNames) do
        if aura.name == n then return true end
    end
    return false
end

local function formatTime(sec)
    sec = math.floor(sec)
    if sec >= 3600 then return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
    if sec >= 60 then return ("%dm %02ds"):format(math.floor(sec / 60), sec % 60) end
    return ("%ds"):format(sec)
end

-- Scan the player's buffs once and store state[key] = aura copy.
function Timers:Scan()
    local state = {}
    local keyBySpell, keyByName = {}, {}
    for key, aura in pairs(ns.Data.CampAuras) do
        keyBySpell[aura.spellID] = key
        keyByName[aura.name] = key -- fallback if a guide's spell ID is wrong
    end
    local function check(a)
        local key = keyBySpell[a.spellID] or keyByName[a.name]
        if key then
            state[key] = a
        elseif isWellFed(a) then
            state.WELL_FED = a
        elseif ns.Auras:IsVioletFlames(a) then
            state.VIOLET = a
        end
    end
    local hidden = ns.Auras:ForEachBuff("player", check)
    -- Boosted Rest is a debuff (the Camp Tent's 1-hour lockout), so scan debuffs too.
    hidden = ns.Auras:ForEachBuff("player", check, "HARMFUL") or hidden
    self.state, self.hidden = state, hidden
    self:Refresh()
end

function Timers:CreateFrame()
    local f = CreateFrame("Button", "CampWiseTimersFrame", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, 26 + ROW_HEIGHT * #TRACKED)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not ns.db.timers.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.timers.point = { point, relPoint, x, y }
    end)

    -- Right-click opens /cw config. The box is a Button so the click arrives as a real OnClick
    -- (OnMouseUp on a plain frame didn't fire for right-clicks on the Forever client).
    f:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.Options:SafeToggle()
        elseif button == "LeftButton" and IsControlKeyDown() then
            ns:ToggleLock("timers", "timer box")
        elseif button == "LeftButton" and IsShiftKeyDown() then
            -- Shift + left click collapses the box to just its title, and back.
            ns.db.timers.collapsed = not ns.db.timers.collapsed
            Timers:ApplyStyle()
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("CampWise timers")
        GameTooltip:AddLine("Right click to open config", 0.4, 1, 0.4)
        GameTooltip:AddLine(ns.db.timers.collapsed and "Shift + left click to expand"
            or "Shift + left click to collapse", 0.4, 1, 0.4)
        GameTooltip:AddLine(ns.db.timers.locked and "Ctrl + left click to unlock" or "Ctrl + left click to lock", 0.4, 1, 0.4)
        if not ns.db.timers.locked then GameTooltip:AddLine("Left drag to move", 0.8, 0.8, 0.8) end
        ns.Camp:AddToTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local p = ns.db.timers.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 300, 150)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("CampWise")
    f.title = title

    f.rows = {}
    for i, t in ipairs(TRACKED) do
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(WIDTH - 16, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 8, -20 - (i - 1) * ROW_HEIGHT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon's built-in border
        -- Slim progress bar behind the text that drains as the buff runs out.
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 3, 0)
        row.bar:SetPoint("BOTTOMRIGHT")
        row.bar:SetStatusBarTexture(ns.Style.FLAT) -- replaced per theme in ApplyStyle
        row.bar:SetMinMaxValues(0, 1)
        row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
        row.bar.bg:SetAllPoints()
        row.bar.bg:SetColorTexture(1, 1, 1, 0.06)
        -- Text sits on a layer above the bar.
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints(row.bar)
        row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)
        row.label = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 4, 0)
        row.label:SetText(t.label)
        row.time = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("RIGHT", -4, 0)
        -- Name fills the space up to the time; when the box is too narrow the game
        -- shortens it with "..." instead of letting it run under the time.
        row.label:SetPoint("RIGHT", row.time, "LEFT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        if row.label.SetMaxLines then row.label:SetMaxLines(1) end
        row.def = t
        f.rows[i] = row
    end

    local elapsed = 0
    f:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= UPDATE_INTERVAL then
            elapsed = 0
            Timers:Refresh()
        end
    end)
    self.frame = f
    self:ApplyStyle()
end

-- Re-apply appearance settings; called on creation and whenever /cw config changes something.
function Timers:ApplyStyle()
    local f = self.frame
    if not f then return end
    local st = ns.db.timers.style
    ns.Style:ApplyBackdrop(f, st)
    ns.Style:SetFontSize(f.title, st.fontSize + (ns.Style:Theme().titleFont and 3 or 1), true)
    f.title:SetTextColor(unpack(st.titleColor))
    local rowH = math.max(ROW_HEIGHT + 2, st.fontSize + 9)
    for i, row in ipairs(f.rows) do
        ns.Style:SetFontSize(row.label, st.fontSize)
        ns.Style:SetFontSize(row.time, st.fontSize)
        row:SetHeight(rowH)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, -(st.fontSize + 10) - (i - 1) * (rowH + 2))
        row.icon:SetSize(rowH, rowH)
        row.bar:SetShown(st.progressBars ~= false)
        ns.Style:SkinStatusBar(row.bar)
    end
    -- Width: the player's slider value, or a default that grows with the font size.
    local width = st.width or (WIDTH + 20 + (st.fontSize - 11) * 8)
    local collapsed = ns.db.timers.collapsed
    for _, row in ipairs(f.rows) do row:SetShown(not collapsed) end
    f:SetSize(width, collapsed and (st.fontSize + 14) or (st.fontSize + 14 + (rowH + 2) * #f.rows))
    for _, row in ipairs(f.rows) do row:SetWidth(f:GetWidth() - 12) end
    self:Refresh()
end

function Timers:Refresh()
    local f = self.frame
    if not f then return end
    if not ns.db.timers.enabled then f:Hide() return end
    f:Show()

    local now, warnAt = GetTime(), ns.db.timers.warnSeconds
    local state = self.state or {}
    for _, row in ipairs(f.rows) do
        local key = row.def.key
        local a = state[key]
        if a then
            row.icon:SetTexture(a.icon)
            row.icon:SetDesaturated(false)
            -- Remember the icon so the row keeps it (greyed) when the buff is gone.
            ns.db.timers.icons = ns.db.timers.icons or {}
            if a.icon and not issecretvalue_safe(a.icon) then ns.db.timers.icons[key] = a.icon end
            -- Purple campfire: Camp Benefits is doubled and lasts 2 hours.
            if key == "CAMP_BENEFITS" and state.VIOLET then
                row.label:SetText(row.def.label .. " (2x)")
                row.label:SetTextColor(0.75, 0.5, 1)
            else
                row.label:SetText(row.def.label)
                row.label:SetTextColor(unpack(ns.db.timers.style.textColor))
            end
            local theme = ns.Style:Theme()
            local r, g, b = unpack(ns.db.timers.style.barColor or theme.barGood)
            if a.expirationTime and a.expirationTime > 0 then
                local left = math.max(0, a.expirationTime - now)
                row.time:SetText(formatTime(left))
                if left <= 60 then
                    r, g, b = 1, 0.25, 0.25
                elseif left <= warnAt then
                    r, g, b = 1, 0.85, 0.1
                end
                local dur = (a.duration and a.duration > 0) and a.duration or left
                row.bar:SetMinMaxValues(0, math.max(dur, 1))
                row.bar:SetValue(left)
                self:MaybeWarn(key, row.def.label, left)
            else
                row.time:SetText("active")
                row.bar:SetMinMaxValues(0, 1)
                row.bar:SetValue(1)
            end
            row.time:SetTextColor(r, g, b)
            if key == "CAMP_BENEFITS" and state.VIOLET then r, g, b = 0.6, 0.35, 1 end
            row.bar:SetStatusBarColor(r, g, b, theme.barAlpha)
        else
            row.icon:SetTexture(self:MissingIcon(key))
            row.icon:SetDesaturated(true)
            row.label:SetTextColor(0.5, 0.5, 0.5)
            row.time:SetText(self.hidden and "hidden" or "missing")
            row.bar:SetValue(0)
            row.time:SetTextColor(0.5, 0.5, 0.5)
            self.warned[key] = nil -- re-arm for the next time the buff appears
        end
    end
end

-- Icon for a buff you don't have: the last icon we saw for it, else the spell's own icon.
local FALLBACK_ICON = { WELL_FED = "Interface\\Icons\\Spell_Misc_Food" }
function Timers:MissingIcon(key)
    local seen = ns.db.timers.icons and ns.db.timers.icons[key]
    if seen then return seen end
    local aura = ns.Data.CampAuras[key]
    local tex = aura and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(aura.spellID)
    return tex or FALLBACK_ICON[key] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- One chat warning per buff application, when it drops below the threshold.
function Timers:MaybeWarn(key, label, left)
    local warnAt = ns.db.timers.warnSeconds
    if left > warnAt then
        self.warned[key] = nil -- buff was refreshed, re-arm
        return
    end
    if left <= 0 or self.warned[key] then return end
    self.warned[key] = true
    ns:Print(("%s runs out in %s."):format(label, formatTime(left)))
end

function Timers:OnInit()
    self.warned = {}
    self.state = {}
end

function Timers:OnEnable()
    self:CreateFrame()
    ns:OnAuraChanged(function() Timers:Scan() end)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", function() Timers:Scan() end)
    -- Re-scan after combat, since auras may have been hidden while fighting.
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() Timers:Scan() end)
    self:Scan()
end

-- /cw timers <arg>
function Timers:HandleCommand(arg)
    local t = ns.db.timers
    if arg == "lock" then
        t.locked = not t.locked
        ns:Print("timers", t.locked and "locked" or "unlocked")
    elseif arg == "show" or arg == "hide" or arg == "" then
        if arg == "" then t.enabled = not t.enabled else t.enabled = (arg == "show") end
        self:Refresh()
    elseif arg == "reset" then
        t.point = nil
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 300, 150)
    elseif tonumber(arg) then
        t.warnSeconds = math.max(0, tonumber(arg) * 60)
        ns:Print(("warning at %d min left"):format(t.warnSeconds / 60))
    else
        ns:Print("/cw timers [show | hide | lock | reset | <minutes before warning>]")
    end
end
