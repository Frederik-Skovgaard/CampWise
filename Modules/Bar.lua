-- CampWise Bar. Step 3: one bar for campfires, your camp objects and camp items.
-- Buttons are secure (they cast spells / use items), so the layout only changes out of combat.
local _, ns = ...
local Bar = ns:NewModule("Bar")
ns.Bar = Bar

local MAX_BUTTONS, SIZE, GAP = 16, 32, 4
local GROUP_GAP, PAD = 17, 6
local SIT_W = 48
local CHAIR_TEXTURE = "Interface\\AddOns\\CampWise\\Media\\CampChair"
-- Group colours come from settings (Use = green, Craft = orange by default).
local function groupColor(group)
    local st = ns.db.bar.style
    return group == "craft" and st.craftColor or st.useColor
end
local issecret = issecretvalue or function() return false end

-- API helpers with fallbacks, since the Forever client mixes old and new APIs.
local function spellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    if IsPlayerSpell then return IsPlayerSpell(id) end
    return IsSpellKnown and IsSpellKnown(id)
end
local function spellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    return GetSpellTexture and GetSpellTexture(id)
end
local function itemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
    return GetItemCount and GetItemCount(id) or 0
end
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end
local function spellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = C_Spell.GetSpellCooldown(id)
        if cd then return cd.startTime, cd.duration end
    elseif GetSpellCooldown then
        return GetSpellCooldown(id)
    end
end
local function itemCooldown(id)
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
end

-- Build the list of things that belong on the bar right now.
-- Order: campfires (best first), your camp objects (highest tier per profession), then items.
-- Names of the professions this character has learned (primary and secondary), e.g. "Cooking".
-- Returns nil if the client gives us no way to tell, in which case nothing is filtered.
local function learnedProfessions()
    local set, any = {}, false
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            local name = idx and GetProfessionInfo(idx)
            if name then set[name] = true any = true end
        end
    end
    if GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, isHeader = GetSkillLineInfo(i)
            if name and not isHeader then set[name] = true any = true end
        end
    end
    return any and set or nil
end

-- A recipe goes on the Craft bar only if you know it AND have its profession.
local function canCraft(spellID, prof, profs)
    if not spellKnown(spellID) then return false end
    return profs == nil or profs[prof] == true
end

function Bar:Collect()
    local profs = learnedProfessions()
    local list = {}
    local D = ns.Data
    for i = #D.Campfires, 1, -1 do
        local fire = D.Campfires[i]
        if canCraft(fire.spellID, "Cooking", profs) then
            -- Campfires are Cooking recipes that make a kit, like camp objects.
            list[#list + 1] = { kind = "craft", id = fire.spellID }
            local kit = ns.char.kitItems[fire.spellID]
            if kit and itemCount(kit) > 0 then list[#list + 1] = { kind = "item", id = kit } end
            break -- only the best fire you know
        end
    end
    local bestByProf = {}
    for _, obj in ipairs(D.Objects) do
        if canCraft(obj.spellID, obj.prof, profs) then
            local cur = bestByProf[obj.prof]
            if not cur or obj.tier > cur.tier then bestByProf[obj.prof] = obj end
        end
    end
    -- Camp object spells are profession recipes: they can't be cast from a button,
    -- so they become "craft" buttons. The crafted kit item (once we've seen it) gets its own button.
    local seenItem = {}
    for _, obj in ipairs(D.Objects) do
        if bestByProf[obj.prof] == obj then
            list[#list + 1] = { kind = "craft", id = obj.spellID }
        end
    end
    for _, obj in ipairs(D.Objects) do
        if bestByProf[obj.prof] == obj then
            local kit = ns.char.kitItems[obj.spellID] or obj.item
            if kit and itemCount(kit) > 0 then
                list[#list + 1] = { kind = "item", id = kit }
                seenItem[kit] = true
            end
        end
    end
    for _, itemID in ipairs(D.BarItems) do
        if not seenItem[itemID] and itemCount(itemID) > 0 then list[#list + 1] = { kind = "item", id = itemID } end
    end
    return list
end

-- Remember which item a recipe makes, so the kit can sit on the bar next to its craft button.
local function cacheKitItem(recipeID)
    local T = C_TradeSkillUI
    if not T then return end
    local itemID
    if T.GetRecipeSchematic then
        local ok, sch = pcall(T.GetRecipeSchematic, recipeID, false)
        if ok and sch then itemID = sch.outputItemID end
    end
    if not itemID and T.GetRecipeOutputItemData then
        local ok, out = pcall(T.GetRecipeOutputItemData, recipeID)
        if ok and out then itemID = out.itemID end
    end
    if itemID and itemID ~= ns.char.kitItems[recipeID] then
        ns.char.kitItems[recipeID] = itemID
        ns:Debug("kit for recipe", recipeID, "is item", itemID)
        Bar:Layout()
    end
end

local function professionOpen()
    return (ProfessionsFrame and ProfessionsFrame:IsShown()) or (TradeSkillFrame and TradeSkillFrame:IsShown())
end

-- First click opens the profession on this recipe; a click while it's open crafts one.
local function craftClick(recipeID)
    local T = C_TradeSkillUI
    if not T then
        ns:Print("this client has no C_TradeSkillUI; craft from your profession window.")
        return
    end
    cacheKitItem(recipeID)
    local info = professionOpen() and T.GetRecipeInfo and T.GetRecipeInfo(recipeID)
    if info and T.CraftRecipe then
        if info.craftable == false then
            ns:Print("missing reagents for", info.name or "this object")
            return
        end
        T.CraftRecipe(recipeID, 1)
        return
    end
    if T.OpenRecipe then
        T.OpenRecipe(recipeID)
        ns:Print("recipe opened. Click the button again (or Create) to craft it.")
    elseif T.OpenTradeSkill then
        ns:Print("open your profession and craft it there; this client can't jump to the recipe.")
    end
    ns:Debug("craft APIs:", "OpenRecipe", T.OpenRecipe ~= nil, "CraftRecipe", T.CraftRecipe ~= nil,
        "GetRecipeInfo", T.GetRecipeInfo ~= nil)
end

local function createButton(parent, i)
    local b = CreateFrame("Button", "CampWiseBarButton" .. i, parent, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    -- Flat look: 1px coloured border, trimmed icon, soft white hover, dark press.
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT") -- look set per theme by Style:SkinButton
    local pushed = b:CreateTexture(nil, "OVERLAY")
    pushed:SetAllPoints(b.icon)
    pushed:SetColorTexture(0, 0, 0, 0.35)
    b:SetPushedTexture(pushed)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        if not self.entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.entry.kind ~= "item" then GameTooltip:SetSpellByID(self.entry.id)
        else GameTooltip:SetItemByID(self.entry.id) end
        if self.entry.kind == "craft" then
            GameTooltip:AddLine("Click: open recipe. Click again: craft.", 0.4, 1, 0.4)
            local obj = ns.Data.ObjectBySpell[self.entry.id]
            if obj and ns.Camp:HasProfession(obj.prof) then
                GameTooltip:AddLine("Already at this camp: " .. ns.Camp.byProf[obj.prof].name, 1, 0.5, 0.5)
            end
            if ns.Advisor then ns.Advisor:AddToTooltip(GameTooltip, self.entry.id) end
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Craft buttons have no secure action; their click runs here instead.
    b:SetScript("PostClick", function(self, _, down)
        if down then return end
        if self.entry and self.entry.kind == "craft" then craftClick(self.entry.id) end
    end)
    b.craftMark = b:CreateTexture(nil, "OVERLAY")
    b.craftMark:SetSize(12, 12)
    b.craftMark:SetPoint("TOPLEFT", 1, -1)
    b.craftMark:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    -- Tick shown on a craft button when that profession's object is already at the camp.
    b.placedMark = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.placedMark:SetSize(18, 18)
    b.placedMark:SetPoint("BOTTOMRIGHT", 2, -2)
    b.placedMark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.placedMark:Hide()
    return b
end

function Bar:CreateFrame()
    local f = CreateFrame("Button", "CampWiseBarFrame", UIParent, "BackdropTemplate")
    f:SetSize(SIZE + 2 * PAD, SIZE + 14 + 2 * PAD)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not ns.db.bar.locked and not InCombatLockdown() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.bar.point = { point, relPoint, x, y }
    end)
    -- Right-click opens /cw config. The box is a Button so the click arrives as a real OnClick
    -- (OnMouseUp on a plain frame didn't fire for right-clicks on the Forever client).
    f:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    f:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.Options:SafeToggle()
        elseif button == "LeftButton" and IsControlKeyDown() then
            ns:ToggleLock("bar", "camp bar")
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("CampWise camp bar")
        GameTooltip:AddLine("Right click to open config", 0.4, 1, 0.4)
        GameTooltip:AddLine(ns.db.bar.locked and "Ctrl + left click to unlock" or "Ctrl + left click to lock", 0.4, 1, 0.4)
        if not ns.db.bar.locked then GameTooltip:AddLine("Left drag to move", 0.8, 0.8, 0.8) end
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local p = ns.db.bar.point
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else f:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end
    f:SetScale(ns.db.bar.scale or 1)

    f.buttons = {}
    for i = 1, MAX_BUTTONS do
        local b = createButton(f, i)
        b:Hide()
        f.buttons[i] = b
    end
    -- Group labels and the divider between Use and Craft.
    -- Big Sit button on the left. It runs /sit through a secure macro, so it works in combat too.
    local sit = CreateFrame("Button", "CampWiseSitButton", f, "SecureActionButtonTemplate, BackdropTemplate")
    sit:SetWidth(SIT_W)
    sit:RegisterForClicks("AnyUp", "AnyDown")
    sit:SetAttribute("type", "macro")
    sit:SetAttribute("macrotext", "/sit")
    -- Backdrop, highlight and font are set per theme by Style:SkinSit.
    -- The picture is CampWise's own drawing of a wooden chair (Media\\CampChair.tga, MIT like the code).
    sit.icon = sit:CreateTexture(nil, "ARTWORK")
    sit.icon:SetPoint("TOPLEFT", 4, -4)
    sit.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    sit.icon:SetTexture(CHAIR_TEXTURE)
    sit.icon:SetTexCoord(1, 0, 0, 1) -- mirrored left-right so the chair faces the other way
    sit.text = sit:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge") -- kept for themes; no label shown
    sit.text:SetText("")
    sit.hl = sit:CreateTexture(nil, "HIGHLIGHT") -- look set per theme by Style:SkinSit
    sit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Sit down")
        GameTooltip:AddLine("Sit by the fire for 1 minute to get Camp Benefits.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.sit = sit

    f.labels = {}
    for key, text in pairs({ use = "Use", craft = "Craft" }) do
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetText(text)
        f.labels[key] = l
    end
    f.divider = f:CreateTexture(nil, "ARTWORK")
    f.divider:SetColorTexture(1, 1, 1, 0.25)
    f.divider:SetWidth(1)
    self.frame = f
end

-- True while the player has the Campfire Nearby buff.
function Bar:NearFire()
    return ns.Auras:GetPlayerAura(ns.Data.CampAuras.CAMPFIRE_NEARBY.spellID) ~= nil
end

-- Rebuild buttons. Secure attributes can't change in combat, so defer until combat ends.
function Bar:Layout()
    if not self.frame then return end
    if InCombatLockdown() then self.pending = true return end
    self.pending = false
    local f = self.frame
    if not ns.db.bar.enabled then f:Hide() return end
    if ns.db.bar.onlyNearFire and not self:NearFire() then f:Hide() return end

    -- Split into the Use group (fire, kits, items) and the Craft group (recipes).
    local use, craft = {}, {}
    for _, e in ipairs(self:Collect()) do
        if e.kind == "craft" then craft[#craft + 1] = e else use[#use + 1] = e end
    end
    local list = {}
    for _, e in ipairs(use) do e.group = "use"; list[#list + 1] = e end
    for _, e in ipairs(craft) do e.group = "craft"; list[#list + 1] = e end
    local n = math.min(#list, MAX_BUTTONS)

    local x, lastGroup, groupStart = PAD + SIT_W + GROUP_GAP, nil, {}
    for i, b in ipairs(f.buttons) do
        local e = list[i]
        if i <= n then
            if lastGroup and e.group ~= lastGroup then
                x = x + GROUP_GAP - GAP -- wider gap where the groups meet
            end
            if not groupStart[e.group] then groupStart[e.group] = x end
            lastGroup = e.group
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, PAD)
            x = x + SIZE + GAP
            b.entry = e
            local c = groupColor(e.group)
            ns.Style:SkinButton(b, c)
            b.craftMark:SetShown(e.kind == "craft")
            local obj = e.kind == "craft" and ns.Data.ObjectBySpell[e.id]
            local atCamp = obj and ns.Camp:HasProfession(obj.prof)
            b.placedMark:SetShown(atCamp and true or false)
            b.icon:SetDesaturated(atCamp and true or false)
            if e.kind == "craft" then
                b:SetAttribute("type", nil)
                b:SetAttribute("spell", nil)
                b:SetAttribute("item", nil)
                b.icon:SetTexture(spellIcon(e.id))
            elseif e.kind == "spell" then
                b:SetAttribute("type", "spell")
                b:SetAttribute("spell", e.id)
                b:SetAttribute("item", nil)
                b.icon:SetTexture(spellIcon(e.id))
            else
                b:SetAttribute("type", "item")
                b:SetAttribute("item", "item:" .. e.id)
                b:SetAttribute("spell", nil)
                b.icon:SetTexture(itemIcon(e.id))
            end
            b:Show()
        else
            b.entry = nil
            b:SetAttribute("type", nil)
            b:Hide()
        end
    end
    -- With no recipes or items the bar still shows, holding just the Sit button.

    local st = ns.db.bar.style
    ns.Style:ApplyBackdrop(f, st)
    local labelH = st.fontSize + 4
    f:SetHeight(SIZE + labelH + 2 * PAD)
    f.sit:ClearAllPoints()
    f.sit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    f.sit:SetHeight(SIZE + labelH)
    ns.Style:SkinSit(f.sit)
    f.sit:Show()
    for key, l in pairs(f.labels) do
        ns.Style:SetFontSize(l, st.fontSize)
        l:SetTextColor(unpack(groupColor(key)))
        l:ClearAllPoints()
        if groupStart[key] then
            l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", groupStart[key] + 1, PAD + SIZE + 2)
            l:Show()
        else
            l:Hide()
        end
    end
    f.divider:ClearAllPoints()
    if groupStart.use and groupStart.craft then
        local mid = groupStart.craft - GROUP_GAP / 2
        f.divider:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", mid, PAD - 2)
        f.divider:SetHeight(SIZE + labelH + 2)
        f.divider:Show()
    else
        f.divider:Hide()
    end
    f:SetWidth(n > 0 and (x - GAP + PAD) or (SIT_W + 2 * PAD))
    f:Show()
    self:UpdateState()
    if ns.Advisor then ns.Advisor:Apply(f.buttons) end
end

-- Counts and cooldowns. Safe in combat (no secure attributes touched).
function Bar:UpdateState()
    if not (self.frame and self.frame:IsShown()) then return end
    for _, b in ipairs(self.frame.buttons) do
        local e = b.entry
        if e then
            local start, dur
            if e.kind ~= "item" then
                start, dur = spellCooldown(e.id)
                b.count:SetText("")
            else
                start, dur = itemCooldown(e.id)
                local c = itemCount(e.id)
                b.count:SetText(c > 1 and c or "")
                b.icon:SetDesaturated(c == 0)
            end
            if start and dur and not issecret(start) and not issecret(dur) and dur > 1.5 then
                b.cooldown:SetCooldown(start, dur)
            else
                b.cooldown:Clear()
            end
        end
    end
end

function Bar:OnEnable()
    self:CreateFrame()
    local relayout = function() Bar:Layout() end
    ns:RegisterEvent("SPELLS_CHANGED", relayout)
    ns:RegisterEvent("SKILL_LINES_CHANGED", relayout)
    ns:RegisterEvent("BAG_UPDATE_DELAYED", relayout)
    ns:RegisterEvent("PLAYER_ENTERING_WORLD", relayout)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", function() if Bar.pending then Bar:Layout() end end)
    -- When a profession window opens, learn which kit item each known camp recipe makes.
    ns:RegisterEvent("TRADE_SKILL_SHOW", function()
        for _, obj in ipairs(ns.Data.Objects) do
            if spellKnown(obj.spellID) then cacheKitItem(obj.spellID) end
        end
        for _, fire in ipairs(ns.Data.Campfires) do
            if spellKnown(fire.spellID) then cacheKitItem(fire.spellID) end
        end
    end)
    -- Show/hide the bar as the Campfire Nearby buff comes and goes (deferred if in combat).
    ns:OnAuraChanged(function()
        local near = Bar:NearFire()
        if near ~= Bar.wasNear then
            Bar.wasNear = near
            Bar:Layout()
        end
    end)
    local update = function() Bar:UpdateState() end
    ns:RegisterEvent("SPELL_UPDATE_COOLDOWN", update)
    ns:RegisterEvent("BAG_UPDATE_COOLDOWN", update)
    self:Layout()
end

-- /cw bar <arg>
function Bar:HandleCommand(arg)
    local b = ns.db.bar
    if arg == "lock" then
        b.locked = not b.locked
        ns:Print("bar", b.locked and "locked" or "unlocked")
    elseif arg == "show" or arg == "hide" or arg == "" then
        if arg == "" then b.enabled = not b.enabled else b.enabled = (arg == "show") end
        self:Layout()
    elseif arg == "reset" then
        if InCombatLockdown() then ns:Print("can't move the bar in combat") return end
        b.point = nil
        self.frame:ClearAllPoints()
        self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    elseif arg:match("^scale") then
        local s = tonumber(arg:match("^scale%s+([%d%.]+)"))
        if s and s >= 0.5 and s <= 2 and not InCombatLockdown() then
            b.scale = s
            self.frame:SetScale(s)
        else
            ns:Print("/cw bar scale 0.5 - 2 (out of combat)")
        end
    else
        ns:Print("/cw bar [show | hide | lock | reset | scale <n>]")
    end
end

-- Called by /cw config after an appearance change. Layout re-applies the style (deferred in combat).
function Bar:ApplyStyle()
    self:Layout()
end
