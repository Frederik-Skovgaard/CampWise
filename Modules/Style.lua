-- CampWise Style. Three themes for the timer box and camp bar:
--   native  - Blizzard native (default): tooltip-style panels, action-button rings
--   flat    - Clean flat: solid panels, 1px borders, square icons
--   rustic  - Rustic campfire: warm browns and amber, dialog borders, Morpheus title font
-- Each theme has a colour preset; picking a theme copies it into both boxes' style settings,
-- which the player can then fine-tune in /cw config.
local _, ns = ...
local Style = {}
ns.Style = Style

local FLAT = "Interface\\Buttons\\WHITE8x8"
Style.FLAT = FLAT
local TOOLTIP_BG = "Interface\\Tooltips\\UI-Tooltip-Background"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local BLIZZ_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local MORPHEUS = "Fonts\\MORPHEUS.TTF"

Style.ORDER = { "native", "flat", "rustic" }
Style.THEMES = {
    native = {
        label = "Blizzard native",
        panel = { bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE, tile = true, tileSize = 16, edgeSize = 12,
                  insets = { left = 3, right = 3, top = 3, bottom = 3 } },
        barTexture = BLIZZ_BAR, barAlpha = 0.55, barGood = { 0.25, 0.8, 0.25 },
        preset = { bgColor = { 0, 0, 0 }, bgAlpha = 0.75, borderColor = { 0.75, 0.75, 0.75 }, borderAlpha = 1,
                   titleColor = { 1, 0.82, 0 }, textColor = { 1, 1, 1 },
                   useColor = { 0.3, 0.85, 0.3 }, craftColor = { 1, 0.6, 0.2 } },
    },
    flat = {
        label = "Clean flat",
        panel = { bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } },
        barTexture = FLAT, barAlpha = 0.35, barGood = { 0.4, 1, 0.4 },
        preset = { bgColor = { 0.05, 0.05, 0.06 }, bgAlpha = 0.85, borderColor = { 0, 0, 0 }, borderAlpha = 1,
                   titleColor = { 1, 0.82, 0 }, textColor = { 1, 1, 1 },
                   useColor = { 0.35, 0.85, 0.35 }, craftColor = { 1, 0.6, 0.2 } },
    },
    rustic = {
        label = "Rustic campfire",
        panel = { bgFile = TOOLTIP_BG, edgeFile = DIALOG_EDGE, tile = true, tileSize = 16, edgeSize = 16,
                  insets = { left = 4, right = 4, top = 4, bottom = 4 } },
        barTexture = BLIZZ_BAR, barAlpha = 0.55, barGood = { 1, 0.6, 0.2 }, titleFont = MORPHEUS,
        preset = { bgColor = { 0.2, 0.11, 0.05 }, bgAlpha = 0.92, borderColor = { 1, 0.65, 0.3 }, borderAlpha = 1,
                   titleColor = { 1, 0.7, 0.3 }, textColor = { 1, 0.92, 0.8 },
                   useColor = { 0.85, 0.7, 0.35 }, craftColor = { 1, 0.45, 0.15 } },
    },
}

function Style:Theme()
    return self.THEMES[ns.db.theme] or self.THEMES.native
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- Switch theme and load its colour preset into both boxes (font size and other choices are kept).
function Style:SetTheme(name)
    if not self.THEMES[name] then return end
    ns.db.theme = name
    local preset = self.THEMES[name].preset
    for _, box in ipairs({ "timers", "bar" }) do
        for k, v in pairs(preset) do ns.db[box].style[k] = copy(v) end
    end
    ns.db.timers.style.barColor = nil -- follow the new theme's bar colour
end

function Style:ApplyBackdrop(frame, st)
    local panel = copy(self:Theme().panel)
    if not st.border then panel.edgeFile = nil end
    frame:SetBackdrop(panel)
    local c = st.bgColor
    frame:SetBackdropColor(c[1], c[2], c[3], st.bgAlpha)
    if st.border then
        local b = st.borderColor
        frame:SetBackdropBorderColor(b[1], b[2], b[3], st.borderAlpha or 1)
    end
end

-- Set a font string's size; fancy = use the theme's title font when it has one.
function Style:SetFontSize(fs, size, fancy)
    local face, _, flags = fs:GetFont()
    if not fs.cwOrigFace then fs.cwOrigFace = face or STANDARD_TEXT_FONT end
    local themeFont = fancy and self:Theme().titleFont
    fs:SetFont(themeFont or fs.cwOrigFace, size, flags or "")
end

function Style:SkinStatusBar(bar)
    bar:SetStatusBarTexture(self:Theme().barTexture)
end

-- Bar button look. color = the button's group colour (Use or Craft).
function Style:SkinButton(b, color)
    local name = ns.db.theme
    if not b.ring then
        b.ring = b:CreateTexture(nil, "OVERLAY", nil, -1)
        b.ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        b.ring:SetPoint("CENTER")
    end
    local w = b:GetWidth() or 32
    b.icon:ClearAllPoints()
    b.hl:ClearAllPoints()
    if name == "flat" or name == "rustic" then
        local inset = name == "rustic" and 2 or 1
        b.ring:Hide()
        b.border:Show()
        local k = name == "rustic" and 0.85 or 1
        b.border:SetColorTexture(color[1] * k, color[2] * k, color[3] * k, name == "rustic" and 1 or 0.9)
        b.icon:SetPoint("TOPLEFT", inset, -inset)
        b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        b.hl:SetPoint("TOPLEFT", inset, -inset)
        b.hl:SetPoint("BOTTOMRIGHT", -inset, inset)
        b.hl:SetBlendMode("BLEND")
        if name == "rustic" then b.hl:SetColorTexture(1, 0.8, 0.4, 0.2) else b.hl:SetColorTexture(1, 1, 1, 0.18) end
    else
        -- Blizzard native: full icon with the standard action-button ring, tinted by group.
        b.border:Hide()
        b.ring:Show()
        b.ring:SetSize(w * 1.8, w * 1.8)
        b.ring:SetVertexColor(0.5 + color[1] * 0.5, 0.5 + color[2] * 0.5, 0.5 + color[3] * 0.5)
        b.icon:SetAllPoints()
        b.hl:SetAllPoints()
        b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        b.hl:SetBlendMode("ADD")
        b.hl:SetVertexColor(1, 1, 1, 1)
    end
end

-- The big Sit button.
function Style:SkinSit(sit)
    local name = ns.db.theme
    sit.hl:ClearAllPoints()
    if name == "flat" then
        sit:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        sit:SetBackdropColor(0.06, 0.05, 0.04, 0.95)
        sit:SetBackdropBorderColor(1, 0.7, 0.25, 1)
        sit.hl:SetPoint("TOPLEFT", 1, -1)
        sit.hl:SetPoint("BOTTOMRIGHT", -1, 1)
        sit.hl:SetBlendMode("BLEND")
        sit.hl:SetColorTexture(1, 0.8, 0.4, 0.15)
        self:SetFontSize(sit.text, 16, false)
        sit.text:SetTextColor(1, 0.82, 0)
    elseif name == "rustic" then
        sit:SetBackdrop({ bgFile = TOOLTIP_BG, edgeFile = DIALOG_EDGE, tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        sit:SetBackdropColor(0.07, 0.04, 0.02, 0.95)
        sit:SetBackdropBorderColor(1, 0.6, 0.25, 1)
        sit.hl:SetPoint("TOPLEFT", 3, -3)
        sit.hl:SetPoint("BOTTOMRIGHT", -3, 3)
        sit.hl:SetBlendMode("BLEND")
        sit.hl:SetColorTexture(1, 0.7, 0.3, 0.18)
        self:SetFontSize(sit.text, 17, true)
        sit.text:SetTextColor(1, 0.7, 0.3)
    else
        sit:SetBackdrop({ bgFile = TOOLTIP_BG, edgeFile = TOOLTIP_EDGE, tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        sit:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
        sit:SetBackdropBorderColor(1, 0.82, 0, 1)
        sit.hl:SetPoint("TOPLEFT", 3, -3)
        sit.hl:SetPoint("BOTTOMRIGHT", -3, 3)
        sit.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        sit.hl:SetBlendMode("ADD")
        self:SetFontSize(sit.text, 16, false)
        sit.text:SetTextColor(1, 0.82, 0)
    end
end
