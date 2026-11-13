-- CampWise Options. /cw config opens a window to style the timer box and the camp bar:
-- background colour and opacity, border on/off and colour, font size and text colours.
local _, ns = ...
local Options = ns:NewModule("Options")
ns.Options = Options

local COL_W, ROW_H = 250, 46

local function copyColor(c) return { c[1], c[2], c[3] } end

-- Colour picker, supporting both the new (10.2.5+) and the old ColorPickerFrame API.
local function pickColor(color, onChange)
    local r, g, b = color[1], color[2], color[3]
    local function changed()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function cancelled() onChange(r, g, b) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = changed, cancelFunc = cancelled,
        })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = changed
        ColorPickerFrame.cancelFunc = cancelled
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ShowUIPanel(ColorPickerFrame)
    end
end

-- Control builders. Each returns the control; get/set read and write the saved setting.
local function makeLabel(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function makeSlider(parent, x, y, text, minV, maxV, step, fmt, get, set)
    makeLabel(parent, text, x, y)
    local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetSize(170, 16)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.value = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.value:SetPoint("LEFT", s, "RIGHT", 8, 0)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        self.value:SetText(fmt(v))
        if not self.loading then set(v) end
    end)
    s.Load = function(self)
        self.loading = true
        self:SetValue(get())
        self.value:SetText(fmt(get()))
        self.loading = false
    end
    return s
end

local function makeCheck(parent, x, y, text, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x - 4, y + 2)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.Load = function(self) self:SetChecked(get()) end
    return cb
end

local function makeSwatch(parent, x, y, text, getColor, setColor)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(20, 20)
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    btn.tex = btn:CreateTexture(nil, "ARTWORK")
    btn.tex:SetPoint("TOPLEFT", 3, -3)
    btn.tex:SetPoint("BOTTOMRIGHT", -3, 3)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", btn, "RIGHT", 6, 0)
    fs:SetText(text)
    btn.Load = function(self)
        local c = getColor()
        self.tex:SetColorTexture(c[1], c[2], c[3])
    end
    btn:SetScript("OnClick", function(self)
        pickColor(getColor(), function(r, g, b)
            setColor({ r, g, b })
            self:Load()
        end)
    end)
    return btn
end

-- Build one column of controls for a box ("timers" or "bar").
local function buildColumn(win, key, title, x, apply)
    local controls = {}
    local function st() return ns.db[key].style end
    local function add(c) controls[#controls + 1] = c return c end
    local y = -84
    local header = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText(title)
    y = y - 28

    if key == "timers" then
        add(makeCheck(win, x, y, "Progress bars",
            function() return st().progressBars ~= false end,
            function(v) st().progressBars = v apply() end))
        y = y - 28
    end
    add(makeSwatch(win, x, y, "Background colour",
        function() return st().bgColor end, function(c) st().bgColor = c apply() end))
    y = y - 30
    add(makeSlider(win, x, y, "Background opacity", 0, 1, 0.05,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end,
        function() return st().bgAlpha end, function(v) st().bgAlpha = v apply() end))
    y = y - ROW_H
    add(makeCheck(win, x, y, "Show border",
        function() return st().border end, function(v) st().border = v apply() end))
    y = y - 28
    add(makeSwatch(win, x, y, "Border colour",
        function() return st().borderColor end, function(c) st().borderColor = c apply() end))
    y = y - 30
    add(makeSlider(win, x, y, "Font size", 8, 18, 1,
        function(v) return ("%d"):format(math.floor(v + 0.5)) end,
        function() return st().fontSize end, function(v) st().fontSize = v apply() end))
    y = y - ROW_H

    if key == "timers" then
        add(makeSlider(win, x, y, "Width", 140, 400, 5,
            function(v) return ("%d"):format(math.floor(v + 0.5)) end,
            function() return st().width or (ns.Timers.frame and math.floor(ns.Timers.frame:GetWidth() + 0.5)) or 210 end,
            function(v) st().width = v apply() end))
        y = y - ROW_H
        add(makeSwatch(win, x, y, "Title colour",
            function() return st().titleColor end, function(c) st().titleColor = c apply() end))
        y = y - 30
        add(makeSwatch(win, x, y, "Text colour",
            function() return st().textColor end, function(c) st().textColor = c apply() end))
        y = y - 30
        add(makeSwatch(win, x, y, "Timer bar colour",
            function() return st().barColor or ns.Style:Theme().barGood end,
            function(c) st().barColor = c apply() end))
        y = y - 30
    else
        add(makeSwatch(win, x, y, "Use group colour",
            function() return st().useColor end, function(c) st().useColor = c apply() end))
        y = y - 30
        add(makeSwatch(win, x, y, "Craft group colour",
            function() return st().craftColor end, function(c) st().craftColor = c apply() end))
        y = y - 30
        add(makeSlider(win, x, y, "Bar scale", 0.5, 2, 0.05,
            function(v) return ("%.2f"):format(v) end,
            function() return ns.db.bar.scale or 1 end,
            function(v)
                if InCombatLockdown() then return end
                ns.db.bar.scale = v
                ns.Bar.frame:SetScale(v)
            end))
        y = y - ROW_H
    end

    if key == "bar" then
        add(makeCheck(win, x, y, "Only show near a campfire",
            function() return ns.db.bar.onlyNearFire end,
            function(v) ns.db.bar.onlyNearFire = v ns.Bar:Layout() end))
        y = y - 28
    end
    add(makeCheck(win, x, y, "Lock position",
        function() return ns.db[key].locked end, function(v) ns.db[key].locked = v end))
    y = y - 34

    local reset = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    reset:SetSize(120, 22)
    reset:SetPoint("TOPLEFT", x, y)
    reset:SetText("Reset look")
    reset:SetScript("OnClick", function()
        ns.db[key].style = {}
        ns.applyDefaults(ns.db[key].style, ns.DB_DEFAULTS[key].style)
        for k, v in pairs(ns.Style:Theme().preset) do
            ns.db[key].style[k] = type(v) == "table" and { v[1], v[2], v[3] } or v
        end
        apply()
        for _, c in ipairs(controls) do c:Load() end
    end)
    return controls, -y + 40
end

-- Third column: V2 camp sharing.
local function buildShareColumn(win, x)
    local controls = {}
    local function sh() return ns.db.share end
    local function add(c) controls[#controls + 1] = c return c end
    local y = -84
    local header = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", x, y)
    header:SetText("Camp sharing")
    y = y - 28
    local function check(text, key, after)
        add(makeCheck(win, x, y, text, function() return sh()[key] end,
            function(v) sh()[key] = v if after then after(v) end ns.Pins:Refresh() end))
        y = y - 26
    end
    local sync = function() ns.Share:SyncChannel() end
    check("Share my camp", "enabled", sync)
    check("  with party / raid", "group")
    check("  with guild", "guild")
    check("  with everyone on the realm", "public", sync)
    y = y - 8
    check("Show other players' camps", "receive")
    check("  on the world map", "worldmap")
    check("  on the minimap", "minimap")
    y = y - 8
    local note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", x, y)
    note:SetWidth(COL_W - 30)
    note:SetJustifyH("LEFT")
    note:SetText("Sharing sends your name, map position and camp objects when you sit at a fire. \"Everyone on the realm\" reaches every CampWise user on your realm. Camps vanish 10 minutes after their last report.")
    return controls, -y + 80
end

function Options:Build()
    local win = CreateFrame("Frame", "CampWiseOptions", UIParent, "BackdropTemplate")
    win:SetFrameStrata("DIALOG")
    win:SetPoint("CENTER")
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "CampWiseOptions") -- Esc closes it

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("CampWise settings")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Theme picker across the top: one button per theme; the current one is shown pressed.
    local themeLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", 24, -48)
    themeLabel:SetText("Theme:")
    self.themeButtons = {}
    local prev
    for _, key in ipairs(ns.Style.ORDER) do
        local tb = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        tb:SetSize(140, 22)
        if prev then tb:SetPoint("LEFT", prev, "RIGHT", 6, 0) else tb:SetPoint("LEFT", themeLabel, "RIGHT", 10, 0) end
        tb:SetText(ns.Style.THEMES[key].label)
        tb:SetScript("OnClick", function()
            ns.Style:SetTheme(key)
            ns.Timers:ApplyStyle()
            ns.Bar:ApplyStyle()
            for _, c in ipairs(Options.controls) do c:Load() end
            Options:UpdateThemeButtons()
        end)
        tb.themeKey = key
        self.themeButtons[#self.themeButtons + 1] = tb
        prev = tb
    end

    local c1, h1 = buildColumn(win, "timers", "Timer box", 24, function() ns.Timers:ApplyStyle() end)
    local c2, h2 = buildColumn(win, "bar", "Camp bar", 24 + COL_W, function() ns.Bar:ApplyStyle() end)
    local c3, h3 = buildShareColumn(win, 24 + COL_W * 2)
    win:SetSize(COL_W * 3 + 30, math.max(h1, h2, h3) + 10)

    self.controls = {}
    for _, c in ipairs(c1) do self.controls[#self.controls + 1] = c end
    for _, c in ipairs(c2) do self.controls[#self.controls + 1] = c end
    for _, c in ipairs(c3) do self.controls[#self.controls + 1] = c end
    win:SetScript("OnShow", function()
        Options:UpdateThemeButtons()
        for _, c in ipairs(Options.controls) do c:Load() end
    end)
    win:Hide()
    self.window = win
end

-- The current theme's button is disabled (shown greyed) so it reads as "selected".
function Options:UpdateThemeButtons()
    for _, tb in ipairs(self.themeButtons or {}) do
        tb:SetEnabled(tb.themeKey ~= (ns.db.theme or "native"))
    end
end

-- Toggle, but report any error in chat (Lua errors are hidden by default in the game).
function Options:SafeToggle()
    local ok, err = pcall(self.Toggle, self)
    if not ok then
        self.window = nil -- let the next try rebuild from scratch
        ns:Print("|cffff4444settings window failed:|r " .. tostring(err))
    end
end

function Options:Toggle()
    if not self.window then self:Build() end
    self.window:SetShown(not self.window:IsShown())
end

-- Also list CampWise in the game's AddOns settings, with a button that opens this window.
function Options:OnEnable()
    local panel = CreateFrame("Frame")
    panel.name = "CampWise"
    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(200, 26)
    btn:SetPoint("TOPLEFT", 16, -16)
    btn:SetText("Open CampWise settings")
    btn:SetScript("OnClick", function()
        -- Opens on top of the game's settings instead of closing them: hiding Blizzard's
        -- settings panel from addon code can taint it.
        if not Options.window then Options:Build() end
        Options.window:SetFrameStrata("FULLSCREEN_DIALOG")
        Options.window:Show()
        Options.window:Raise()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "CampWise")
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end
