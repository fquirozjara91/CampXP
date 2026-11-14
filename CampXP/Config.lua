-- Ventana de configuración + botón del minimapa
local ADDON, ns = ...
local L = ns.L
local Config = {}
ns.Config = Config

local format = string.format
local CONTENT_W = 380
-- posiciones de las grillas respecto de los iconos
local SIDES = { "right", "left", "top", "bottom" }
-- estilos de iconos
local STYLES = { "round", "minimal", "classic" }
local STYLE_LABELS = { "Round", "Minimal", "Classic" }
local SIDE_LABELS = { "Right", "Left", "Above", "Below" }

-- Helpers de UI -----------------------------------------------------------
local function Btn(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 60, h or 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Check(parent, label, get, set)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label)
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns:FullUpdate()
    end)
    cb.Refresh = function(self) self:SetChecked(get() and true or false) end
    return cb
end

local function Stepper(parent, label, get, set, step, minV, maxV, fmt)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CONTENT_W - 30, 22)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetPoint("LEFT")
    f.label:SetText(label)
    f.plus = Btn(f, "+", 24, 20, function()
        set(math.min(maxV, get() + step)); f:Refresh(); ns:FullUpdate()
    end)
    f.plus:SetPoint("RIGHT")
    f.value = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.value:SetPoint("RIGHT", f.plus, "LEFT", -4, 0)
    f.value:SetWidth(54)
    f.minus = Btn(f, "-", 24, 20, function()
        set(math.max(minV, get() - step)); f:Refresh(); ns:FullUpdate()
    end)
    f.minus:SetPoint("RIGHT", f.value, "LEFT", -4, 0)
    f.Refresh = function() f.value:SetText(fmt(get())) end
    return f
end

local function Header(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Note(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetWidth(CONTENT_W - 10)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

-- Ventana -----------------------------------------------------------------
function Config:Create()
    local f = CreateFrame("Frame", "CampXPConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(440, 560)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:Hide()
    tinsert(UISpecialFrames, "CampXPConfig") -- Esc cierra

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText(L["CampXP - XP Buffs"])

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "CampXPConfigScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -46)
    scroll:SetPoint("BOTTOMRIGHT", -38, 18)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1000)
    scroll:SetScrollChild(content)

    self.frame, self.content = f, content
    f:SetScript("OnShow", function() Config:Refresh() end)

    local cdb = ns.cdb
    -- Categorías
    self.hBuffs = Header(content, L["Tracked buffs"])
    self.catCheck, self.catBonus = {}, {}
    for _, c in ipairs(ns.CATEGORIES) do
        local key = c.key
        self.catCheck[key] = Check(content, format("|T%s:16|t %s", c.icon, c.label),
            function() return cdb.enabled[key] end,
            function(v) cdb.enabled[key] = v end)
        -- bonus de XP: solo lectura, lo define el addon
        local bonus = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        bonus:SetTextColor(0.6, 0.85, 1)
        bonus:SetText(ns:BonusText(key))
        self.catBonus[key] = bonus
        self.catSummary = self.catSummary or {}
        self.catSummary[key] = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        self.catSummary[key]:SetWidth(CONTENT_W - 40)
        self.catSummary[key]:SetJustifyH("LEFT")

        -- casillas de avisos, en 2 columnas
        local box = CreateFrame("Frame", nil, content)
        box.checks = {}
        local n = 0
        for _, k in ipairs(ns.ALERT_KINDS) do
            if not k.perStackOnly or c.perStack then
                local kind = k.key
                local cb = Check(box, k.label,
                    function() return ns:AlertOn(key, kind) end,
                    function(v) ns:SetAlertOn(key, kind, v) end)
                cb:SetSize(20, 20)
                cb.label:SetFontObject("GameFontHighlightSmall")
                local col, row = n % 2, math.floor(n / 2)
                cb:SetPoint("TOPLEFT", box, "TOPLEFT", col * 170, -row * 20)
                table.insert(box.checks, cb)
                n = n + 1
            end
        end
        box:SetSize(CONTENT_W - 30, math.ceil(n / 2) * 20)
        box.title = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        self.catAlerts = self.catAlerts or {}
        self.catAlerts[key] = box
        self.catAlertsLabel = self.catAlertsLabel or {}
        self.catAlertsLabel[key] = Note(content, L["Alert when:"])
    end

    -- Opciones
    self.hOpts = Header(content, L["Options"])
    self.opts = {
        Check(content, L["Confirm before eating food without XP"], function() return cdb.confirmNoXP end, function(v) cdb.confirmNoXP = v end),
        Check(content, L["Alert sound"], function() return cdb.sound end, function(v) cdb.sound = v end),
        Check(content, L["Big on-screen alert"], function() return cdb.alerts end, function(v) cdb.alerts = v end),
        Check(content, L["XP gained/lost in the XP bar tooltip"], function() return cdb.showXPTooltip end, function(v) cdb.showXPTooltip = v end),
        Check(content, L["Show XP lost above the buff icon"], function() return cdb.showLostBadge end, function(v) cdb.showLostBadge = v end),
        Check(content, L["XP gained/lost summary on level up"], function() return cdb.xpSummary end, function(v) cdb.xpSummary = v end),
        Check(content, L["Lock frames"], function() return cdb.locked end, function(v) cdb.locked = v end),
        Check(content, L["Hide minimap button"], function() return cdb.minimap.hide end, function(v) cdb.minimap.hide = v end),
    }
    self.hSupp = Header(content, L["Don't alert when..."])
    self.supp = {
        Check(content, L["I'm in combat (alerts after)"], function() return cdb.suppress.combat end, function(v) cdb.suppress.combat = v end),
        Check(content, L["I'm in a city / inn"], function() return cdb.suppress.resting end, function(v) cdb.suppress.resting = v end),
        Check(content, L["I'm mounted"], function() return cdb.suppress.mounted end, function(v) cdb.suppress.mounted = v end),
        Check(content, L["I'm max level (hides everything)"], function() return cdb.suppress.maxLevel end, function(v) cdb.suppress.maxLevel = v end),
    }
    self.steppers = {
        Stepper(content, L["Warn before expiring"], function() return cdb.warnSec end, function(v) cdb.warnSec = v end,
            30, 30, 900, function(v) return ns.FormatTime(v) end),
        Stepper(content, L["Remind if missing (min)"], function() return cdb.remindMin end, function(v) cdb.remindMin = v end,
            1, 0, 30, function(v) return v == 0 and L["off"] or format(L["%d min"], v) end),
        Stepper(content, L["Icon style"],
            function()
                for i, st in ipairs(STYLES) do if st == (cdb.iconStyle or "round") then return i end end
                return 1
            end,
            function(v)
                cdb.iconStyle = STYLES[v]
                if ns.Display then ns.Display:ApplyStyle() end
            end,
            1, 1, #STYLES, function(v) return L[STYLE_LABELS[v]] end),
        Stepper(content, L["Grid position"],
            function()
                for i, side in ipairs(SIDES) do if side == (cdb.pickerSide or "right") then return i end end
                return 1
            end,
            function(v)
                cdb.pickerSide = SIDES[v]
                if ns.Display and ns.Display.picker and ns.Display.picker:IsShown() then ns.Display:AnchorPicker() end
            end,
            1, 1, #SIDES, function(v) return L[SIDE_LABELS[v]] end),
        Stepper(content, L["Low stock alert"], function() return cdb.lowStock end, function(v) cdb.lowStock = v end,
            1, 0, 20, function(v) return v == 0 and L["off"] or ("<= " .. v) end),
    }
    self.btnRow = CreateFrame("Frame", nil, content)
    self.btnRow:SetSize(CONTENT_W, 24)
    local b1 = Btn(self.btnRow, L["Test alerts"], 120, 22, function() ns:TestAlerts() end)
    b1:SetPoint("LEFT")
    local b2 = Btn(self.btnRow, L["Reset positions"], 150, 22, function() SlashCmdList.CAMPXP("reset") end)
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
end

function Config:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    local c = self.content
    local y = -4
    local function place(w, h, x)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", c, "TOPLEFT", x or 0, y)
        w:Show()
        y = y - (h or w:GetHeight()) - 4
    end


    place(self.hBuffs, 20)
    for _, cat in ipairs(ns.CATEGORIES) do
        local key = cat.key
        self.catCheck[key]:Refresh()
        place(self.catCheck[key], 24)
        place(self.catBonus[key], 14, 28)
        local list = {}
        for spellId, e in pairs(ns.db.entries) do
            if e.cat == key then table.insert(list, spellId) end
        end
        table.sort(list, function(a, b)
            return (ns.db.entries[a].name or "") < (ns.db.entries[b].name or "")
        end)
        -- un resumen por categoría (las variantes del buff no le importan al usuario)
        local line = self.catSummary[key]
        local st = ns.state[key]
        if #list == 0 then
            line:SetText("|cffff6060" .. L["Buff not registered"] .. "|r")
        elseif key == "food" then
            line:SetText(st.count > 0 and format(L["In bags: |cffffffff%d|r foods that give XP"], st.count)
                or ("|cffff6060" .. L["In bags: no food that gives XP"] .. "|r"))
        else
            local names = {}
            for itemId in pairs(st.items) do
                table.insert(names, format("%s x%d", ns.GetItemName(itemId) or format(L["Item %d"], itemId), ns.GetItemCount(itemId)))
            end
            table.sort(names)
            line:SetText(#names > 0 and (L["In bags: "] .. "|cffffffff" .. table.concat(names, ", ") .. "|r")
                or ("|cffff6060" .. L["In bags: none (detected when used)"] .. "|r"))
            if st.locked then
                line:SetText("|cffaaaaaa" .. L["Unlocks with the level 14 quest \"This Must Be the Place\"."] .. "|r")
            end
        end
        place(line, 14, 28)
        place(self.catAlertsLabel[key], 12, 28)
        for _, cb in ipairs(self.catAlerts[key].checks) do cb:Refresh() end
        place(self.catAlerts[key], self.catAlerts[key]:GetHeight(), 28)
        y = y - 6
    end

    y = y - 6
    place(self.hOpts, 20)
    for _, w in ipairs(self.opts) do w:Refresh(); place(w, 24) end
    y = y - 4
    place(self.hSupp, 20)
    for _, w in ipairs(self.supp) do w:Refresh(); place(w, 24) end
    y = y - 4
    for _, w in ipairs(self.steppers) do w:Refresh(); place(w, 22) end
    y = y - 6
    place(self.btnRow, 24)

    c:SetHeight(-y + 10)
end

function Config:Toggle()
    if not self.frame then self:Create() end
    if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

-- Botón del minimapa ------------------------------------------------------
local function UpdateMinimapPos(btn)
    local angle = math.rad(ns.cdb.minimap.angle or 200)
    local r = (Minimap:GetWidth() / 2) + 10
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

function Config:CreateMinimapButton()
    local b = CreateFrame("Button", "CampXPMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(17, 17)
    b.icon:SetTexture("Interface\\Icons\\Spell_Fire_Fire")
    b.icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b.alert = b:CreateFontString(nil, "OVERLAY")
    b.alert:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    b.alert:SetPoint("TOPRIGHT", -2, -2)
    b.alert:SetTextColor(1, 0.85, 0.1)

    b:SetScript("OnClick", function(_, button)
        Config:Toggle()
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            px, py = px / s, py / s
            ns.cdb.minimap.angle = math.deg(math.atan2(py - my, px - mx))
            UpdateMinimapPos(self)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("CampXP", 1, 0.82, 0)
        for _, c in ipairs(ns.CATEGORIES) do
            local s = ns.state[c.key]
            local txt, r, g, bl
            if s.phase == "active" or s.phase == "expiring" then
                txt = (s.expires == math.huge) and L["active"] or ns.FormatTime(s.remaining)
                r, g, bl = 0.3, 1, 0.3
            elseif s.phase == "missing_have" then
                txt, r, g, bl = format(L["Use! (%d)"], s.count), 1, 0.85, 0.1
            elseif s.phase == "missing_none" then
                txt, r, g, bl = L["no items"], 0.6, 0.6, 0.6
            elseif s.phase == "unconfigured" then
                txt, r, g, bl = L["not detected"], 0.5, 0.5, 0.5
            elseif s.locked then
                txt, r, g, bl = L["locked (lvl 14 quest)"], 0.5, 0.5, 0.5
            else
                txt, r, g, bl = L["disabled"], 0.4, 0.4, 0.4
            end
            GameTooltip:AddDoubleLine(c.label, txt, 1, 1, 1, r, g, bl)
        end
        if ns.XPBar and ns.XPBar.AddTooltipLines then ns.XPBar:AddTooltipLines(GameTooltip) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: settings · Drag: move"], 0.5, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = b
    UpdateMinimapPos(b)
    self:UpdateMinimap()
end

function Config:UpdateMinimap()
    local b = self.minimapButton
    if not b then return end
    if ns.cdb.minimap.hide then b:Hide() return end
    b:Show()
    local actionable, anyActive = false, false
    for _, c in ipairs(ns.CATEGORIES) do
        local s = ns.state[c.key]
        if s.phase == "missing_have" or s.phase == "expiring" then actionable = true end
        if s.active then anyActive = true end
    end
    b.alert:SetText(actionable and "!" or "")
    b.icon:SetDesaturated(not anyActive and not actionable)
end
