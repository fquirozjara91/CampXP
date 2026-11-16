-- Ventana de configuración + botón del minimapa
local ADDON, ns = ...
local L = ns.L
local Config = {}
ns.Config = Config

local format = string.format
local CONTENT_W = 420
-- posiciones de las grillas respecto de los iconos
local SIDES = { "right", "left", "top", "bottom" }
-- estilos de iconos
local STYLES = { "round", "minimal", "classic" }
local STYLE_LABELS = { "Round", "Minimal", "Classic" }
local SIDE_LABELS = { "Right", "Left", "Above", "Below" }
local MODES = { "leveling", "endgame" }
local MODE_LABELS = { "Leveling", "End Game" }

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

-- Interruptor de dos posiciones con perilla deslizante: [ Leveling | End Game ]
local function Slide(parent, label, options, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CONTENT_W - 30, 26)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetPoint("LEFT")
    f.label:SetText(label)

    local track = CreateFrame("Button", nil, f)
    track:SetSize(190, 24)
    track:SetPoint("RIGHT")
    local bg = track:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    local edge = track:CreateTexture(nil, "BORDER")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.45, 0.4, 0.3, 0.8)
    bg:SetDrawLayer("BORDER", 1)

    local half = track:GetWidth() / 2
    local knob = track:CreateTexture(nil, "ARTWORK")
    knob:SetSize(half - 4, 20)
    knob:SetColorTexture(0.85, 0.62, 0.1, 0.9)
    f.knob = knob

    f.texts = {}
    for i, opt in ipairs(options) do
        local t = track:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("CENTER", track, "LEFT", half * (i - 0.5), 0)
        t:SetText(opt)
        f.texts[i] = t
    end

    -- la perilla se desliza hasta su lado (animación simple por OnUpdate)
    f.pos, f.target = nil, nil
    local function Place(x) knob:ClearAllPoints(); knob:SetPoint("LEFT", track, "LEFT", 2 + x, 0) end
    track:SetScript("OnUpdate", function()
        if not f.target or f.pos == f.target then return end
        local d = f.target - f.pos
        f.pos = (math.abs(d) < 1) and f.target or (f.pos + d * 0.3)
        Place(f.pos)
    end)
    track:SetScript("OnClick", function()
        set(get() == 1 and 2 or 1)
        ns:FullUpdate()
    end)
    track:SetScript("OnEnter", function() edge:SetColorTexture(1, 0.82, 0, 0.9) end)
    track:SetScript("OnLeave", function() edge:SetColorTexture(0.45, 0.4, 0.3, 0.8) end)

    f.Refresh = function()
        local v = get()
        f.target = (v - 1) * half
        if not f.pos then f.pos = f.target; Place(f.pos) end
        for i, t in ipairs(f.texts) do
            if i == v then t:SetTextColor(0.1, 0.07, 0) else t:SetTextColor(0.6, 0.6, 0.6) end
        end
    end
    return f
end

-- Lista desplegable (menú moderno del cliente); si no existe, vuelve al selector +/-
local function Dropdown(parent, label, labels, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CONTENT_W - 30, 26)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetPoint("LEFT")
    f.label:SetText(label)
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if not ok or not dd or not dd.SetupMenu then
        if ok and dd then dd:Hide() end
        f:Hide()
        return Stepper(parent, label, get, set, 1, 1, #labels, function(v) return labels[v] end)
    end
    dd:SetWidth(150)
    dd:SetPoint("RIGHT")
    dd:SetupMenu(function(_, root)
        for i, text in ipairs(labels) do
            root:CreateRadio(text, function() return get() == i end, function()
                set(i)
                ns:FullUpdate()
            end)
        end
    end)
    f.dd = dd
    f.Refresh = function() if dd.GenerateMenu then dd:GenerateMenu() end end
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

-- Ventana con pestañas -----------------------------------------------------
local WIN_W, WIN_H = 480, 600
local TABS = {
    { key = "general", label = "General" },
    { key = "tooltip", label = "Tooltip" },
    { key = "design",  label = "Design" },
    { key = "notif",   label = "Notifications" },
    { key = "changelog", label = "Changelog" },
}

local function SetTabLook(b, active)
    if active then
        b.bg:SetColorTexture(0.85, 0.62, 0.1, 0.9)
        b.text:SetTextColor(0.1, 0.07, 0)
    else
        b.bg:SetColorTexture(0, 0, 0, 0.5)
        b.text:SetTextColor(0.75, 0.75, 0.75)
    end
end

local function TabButton(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetSize(math.max(64, b.text:GetStringWidth() + 20), 22)
    b.edge = b:CreateTexture(nil, "BACKGROUND")
    b.edge:SetPoint("TOPLEFT", -1, 1)
    b.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    b.edge:SetColorTexture(0.45, 0.4, 0.3, 0.8)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetAllPoints()
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function() b.edge:SetColorTexture(1, 0.82, 0, 0.9) end)
    b:SetScript("OnLeave", function() b.edge:SetColorTexture(0.45, 0.4, 0.3, 0.8) end)
    -- punto "nuevo" (changelog tras actualizar)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetSize(8, 8)
    b.dot:SetPoint("TOPRIGHT", 2, 2)
    b.dot:SetColorTexture(1, 0.25, 0.2, 1)
    b.dot:Hide()
    return b
end

-- Cada pestaña: su propio scroll y contenido
local function Panel(f)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -76)
    scroll:SetPoint("BOTTOMRIGHT", -38, 18)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 1000)
    scroll:SetScrollChild(content)
    scroll:Hide()
    return { scroll = scroll, content = content }
end

local function Layout(content, scroll)
    local y = -4
    local Lo = {}
    function Lo.place(w, h, x)
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", content, "TOPLEFT", x or 0, y)
        w:Show()
        y = y - (h or w:GetHeight()) - 4
    end
    function Lo.gap(n) y = y - (n or 6) end
    function Lo.finish()
        content:SetHeight(-y + 10)
        -- barra de scroll solo si hace falta
        local bar = scroll and (scroll.ScrollBar or (scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"]))
        if type(bar) == "table" and bar.SetShown then
            local need = (-y + 10) > (scroll:GetHeight() or 0) + 2
            bar:SetShown(need)
            if not need then scroll:SetVerticalScroll(0) end
        end
    end
    return Lo
end

local function Version()
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return meta and meta(ADDON, "Version") or "?"
end

function Config:Create()
    local f = CreateFrame("Frame", "CampXPConfig", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(WIN_W, WIN_H)
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
    local ver = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
    ver:SetText("v" .. Version())

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    self.frame = f
    self.panels, self.tabButtons = {}, {}
    local x = 22
    for _, t in ipairs(TABS) do
        local key = t.key
        local b = TabButton(f, L[t.label], function() Config:SelectTab(key) end)
        b:SetPoint("TOPLEFT", x, -44)
        x = x + b:GetWidth() + 6
        self.tabButtons[key] = b
        self.panels[key] = Panel(f)
    end
    f:SetScript("OnShow", function() Config:SelectTab(ns.db.configTab or "general") end)

    self:BuildGeneral(self.panels.general.content)
    self:BuildTooltip(self.panels.tooltip.content)
    self:BuildDesign(self.panels.design.content)
    self:BuildNotif(self.panels.notif.content)
    self:BuildChangelog(self.panels.changelog.content)

    -- la tabla de General se actualiza sola (timers)
    local acc = 0
    self.panels.general.scroll:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc >= 1 then acc = 0; Config:RefreshTable() end
    end)
end

function Config:SelectTab(key)
    if not self.panels[key] then key = "general" end
    self.tab = key
    ns.db.configTab = key
    if key == "changelog" then ns.db.seenChangelog = Version() end
    for k, p in pairs(self.panels) do p.scroll:SetShown(k == key) end
    for k, b in pairs(self.tabButtons) do SetTabLook(b, k == key) end
    self:Refresh()
end

------------------------------------------------------------------ General
local STATUS_COLS = { check = 0, name = 26, status = 178, bags = 268, bonus = 322 }

function Config:BuildGeneral(c)
    local cdb = ns.cdb
    self.g = {}
    local g = self.g
    g.modeStep = Slide(c, L["Mode"], { L["Leveling"], L["End Game"] },
        function() return ns.cdb.mode == "endgame" and 2 or 1 end,
        function(v) ns:SetMode(MODES[v]) end)
    g.modeNote = Note(c, "")
    -- aviso de beta del modo End Game
    local beta = CreateFrame("Frame", nil, c)
    beta:SetSize(CONTENT_W - 20, 40)
    local bbg = beta:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.9, 0.5, 0.05, 0.15)
    local bar = beta:CreateTexture(nil, "BORDER")
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT"); bar:SetWidth(3)
    bar:SetColorTexture(1, 0.6, 0.1, 0.9)
    local icon = beta:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("LEFT", 9, 0)
    icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    beta.text = beta:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    beta.text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    beta.text:SetPoint("RIGHT", -8, 0)
    beta.text:SetJustifyH("LEFT")
    beta.text:SetText("|cffffa020" .. L["BETA"] .. "|r  " .. L["End Game mode is in beta: consumable detection is still being tuned. If something is detected wrong, right-click it in the Consumables grid > Report a problem."])
    g.beta = beta

    -- Tabla de buffs vigilados
    g.hBuffs = Header(c, L["Tracked buffs"])
    local tbl = CreateFrame("Frame", nil, c)
    tbl:SetSize(CONTENT_W - 10, 20)
    local head = CreateFrame("Frame", nil, tbl)
    head:SetSize(CONTENT_W - 10, 18)
    head:SetPoint("TOPLEFT")
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.85, 0.62, 0.1, 0.25)
    for col, text in pairs({ name = L["Buff"], status = L["Status"], bags = L["Bags"], bonus = L["Bonus"] }) do
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", STATUS_COLS[col] + 4, 0)
        fs:SetText(text)
    end
    tbl.rows = {}
    for i, cat in ipairs(ns.CATEGORIES) do
        local key = cat.key
        local row = CreateFrame("Frame", nil, tbl)
        row:SetSize(CONTENT_W - 10, 26)
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.check = Check(row, "",
            function() return ns.cdb.enabled[key] end,
            function(v) ns.cdb.enabled[key] = v end)
        row.check:SetPoint("LEFT", STATUS_COLS.check, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", STATUS_COLS.name, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(STATUS_COLS.status - STATUS_COLS.name - 28)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        for _, col in ipairs({ "status", "bags", "bonus" }) do
            row[col] = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row[col]:SetPoint("LEFT", STATUS_COLS[col] + 4, 0)
            row[col]:SetJustifyH("LEFT")
        end
        row.key = key
        -- detalle al pasar el mouse: qué hay en las bolsas y qué da
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(cat.label, 1, 0.82, 0)
            if self.detail then GameTooltip:AddLine(self.detail, 1, 1, 1, true) end
            if self.bonusText then GameTooltip:AddLine(self.bonusText, 0.6, 0.85, 1, true) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        tbl.rows[i] = row
    end
    g.table = tbl
    g.autoTrack = Check(c, L["Track consumables in my bags automatically"],
        function() return ns.cdb.endgame.auto end, function(v) ns.cdb.endgame.auto = v end)

    -- Comportamiento
    g.hBehav = Header(c, L["Behavior"])
    g.behav = {
        Check(c, L["Confirm before eating food without XP"], function() return ns.cdb.confirmNoXP end, function(v) ns.cdb.confirmNoXP = v end),
        Check(c, L["Lock frames"], function() return ns.cdb.locked end, function(v) ns.cdb.locked = v end),
        Check(c, L["Hide minimap button"], function() return ns.cdb.minimap.hide end, function(v) ns.cdb.minimap.hide = v end),
    }
    g.btnRow = CreateFrame("Frame", nil, c)
    g.btnRow:SetSize(CONTENT_W, 24)
    local b1 = Btn(g.btnRow, L["Reset positions"], 150, 22, function() SlashCmdList.CAMPXP("reset") end)
    b1:SetPoint("LEFT")
    local b2 = Btn(g.btnRow, L["Reset settings"], 150, 22, function() StaticPopup_Show("CAMPXP_RESET_SETTINGS") end)
    b2:SetPoint("LEFT", b1, "RIGHT", 8, 0)
    g.help = Note(c, L["Commands: /cxp (settings) · mode · style · xp · food · status · test · lock · reset"])
end

-- Contenido de una fila de la tabla
local function RowData(key)
    local cat, st = ns.CAT[key], ns.state[key]
    local endgame = ns:IsEndgame()
    local status, bags, bonus, detail, bonusText
    -- Estado
    if not ns.cdb.enabled[key] then
        status = "|cff888888" .. L["disabled"] .. "|r"
    elseif st.locked then
        status = "|cff888888" .. L["locked"] .. "|r"
    elseif key == "consumables" then
        local n = st.trackedCount or 0
        status = n == 0 and ("|cff888888" .. L["nothing tracked"] .. "|r")
            or format("%s%d/%d|r", st.active and "|cff40ff40" or "|cffffd100", st.activeCount or 0, n)
    elseif st.phase == "active" or st.phase == "expiring" then
        local col = st.phase == "expiring" and "|cffff9933" or "|cff40ff40"
        status = col .. ((st.expires == math.huge or not st.remaining) and L["active"] or ns.FormatTime(st.remaining)) .. "|r"
    elseif st.phase == "missing_have" then
        status = "|cffffd100" .. L["missing"] .. "|r"
    elseif st.phase == "missing_none" then
        status = "|cffff6060" .. L["missing"] .. "|r"
    else
        status = "|cff888888-|r"
    end
    -- Bolsas
    local n = 0
    local names = {}
    for itemId in pairs(st.items or {}) do
        local cnt = ns.GetItemCount(itemId) or 0
        n = n + cnt
        names[#names + 1] = format("%s x%d", ns.GetItemName(itemId) or format(L["Item %d"], itemId), cnt)
    end
    table.sort(names)
    if key == "consumables" then
        bags = "-"
        detail = L["Right-click an item in the Consumables grid to stop tracking it, fix its buff or choose its alerts."]
    else
        bags = n > 0 and ("|cffffffff" .. n .. "|r") or "|cffff60600|r"
        detail = #names > 0 and (L["In bags: "] .. table.concat(names, ", ")) or L["In bags: none (detected when used)"]
        if st.locked then detail = L["Unlocks with the level 14 quest \"This Must Be the Place\"."] end
    end
    -- Bonus
    if endgame then
        bonus = (key == "food" and st.statText) or "-"
        bonusText = key == "food" and L["Shows the stat of your Well Fed"] or nil
    else
        local kill, quest = ns:XPBonus(key, true)
        if kill <= 0 and quest <= 0 then bonus = "-"
        elseif kill == quest then bonus = format("+%d%%", kill)
        else bonus = format("+%d%% %s", kill, L["kills"]) end
        bonusText = ns:BonusText(key)
    end
    return status, bags, bonus, detail, bonusText
end

function Config:RefreshTable()
    if not self.frame or not self.frame:IsShown() or self.tab ~= "general" then return end
    local tbl = self.g.table
    local endgame = ns:IsEndgame()
    local yy, i = -20, 0
    for _, row in ipairs(tbl.rows) do
        local key = row.key
        local cat = ns.CAT[key]
        local hidden = (key == "sleepingbag" and endgame) or (cat.endgameOnly and not endgame)
        if hidden then
            row:Hide()
        else
            i = i + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tbl, "TOPLEFT", 0, yy)
            yy = yy - 26
            row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
            row.icon:SetTexture(cat.icon)
            row.name:SetText(cat.label)
            row.check:Refresh()
            local status, bags, bonus, detail, bonusText = RowData(key)
            row.status:SetText(status)
            row.bags:SetText(bags)
            row.bonus:SetText(bonus)
            row.detail, row.bonusText = detail, bonusText
            row:Show()
        end
    end
    tbl:SetHeight(-yy)
end

function Config:RefreshGeneral(Lo)
    local g = self.g
    local endgame = ns:IsEndgame()
    g.modeStep:Refresh()
    Lo.place(g.modeStep, 26)
    g.modeNote:SetText(endgame and L["End Game: Sleeping Bag and XP tracking hidden, food shows its stats, Consumables icon."]
        or L["Leveling: XP buffs and XP lost."])
    Lo.place(g.modeNote, g.modeNote:GetStringHeight(), 4)
    if endgame then
        g.beta:SetHeight(g.beta.text:GetStringHeight() + 14)
        Lo.place(g.beta, g.beta:GetHeight(), 4)
    else
        g.beta:Hide()
    end
    Lo.gap(8)
    Lo.place(g.hBuffs, 20)
    self:RefreshTable()
    Lo.place(g.table, g.table:GetHeight())
    if endgame then
        g.autoTrack:Refresh()
        Lo.place(g.autoTrack, 24)
    else
        g.autoTrack:Hide()
    end
    Lo.gap(8)
    Lo.place(g.hBehav, 20)
    for _, w in ipairs(g.behav) do w:Refresh(); Lo.place(w, 24) end
    Lo.gap(6)
    Lo.place(g.btnRow, 24)
    Lo.gap(4)
    Lo.place(g.help, g.help:GetStringHeight())
end

------------------------------------------------------------------ Tooltip
function Config:BuildTooltip(c)
    self.t = {}
    local t = self.t
    t.hXP = Header(c, L["XP information"])
    t.opts = {
        Check(c, L["XP gained/lost in the XP bar tooltip"], function() return ns.cdb.showXPTooltip end, function(v) ns.cdb.showXPTooltip = v end),
        Check(c, L["XP gained/lost summary on level up"], function() return ns.cdb.xpSummary end, function(v) ns.cdb.xpSummary = v end),
    }
end

function Config:RefreshTooltip(Lo)
    local t = self.t
    Lo.place(t.hXP, 20)
    for _, w in ipairs(t.opts) do w:Refresh(); Lo.place(w, 24) end
end

------------------------------------------------------------------ Diseño
function Config:BuildDesign(c)
    self.d = {}
    local d = self.d
    d.hIcons = Header(c, L["Icons"])
    d.opts = {
        Dropdown(c, L["Icon style"], { L["Round"], L["Minimal"], L["Classic"] },
            function()
                for i, st in ipairs(STYLES) do if st == (ns.cdb.iconStyle or "round") then return i end end
                return 1
            end,
            function(v)
                ns.cdb.iconStyle = STYLES[v]
                if ns.Display then ns.Display:ApplyStyle() end
            end),
        Stepper(c, L["Icon text size"], function() return ns.cdb.textScale or 100 end,
            function(v)
                ns.cdb.textScale = v
                if ns.Display then ns.Display:ApplyStyle() end
            end,
            10, 60, 200, function(v) return v .. "%" end),
        Check(c, L["Show XP lost above the buff icon"], function() return ns.cdb.showLostBadge end, function(v) ns.cdb.showLostBadge = v end),
    }
    d.hGrid = Header(c, L["Grids"])
    d.grid = {
        Dropdown(c, L["Grid position"], { L["Right"], L["Left"], L["Above"], L["Below"] },
            function()
                for i, side in ipairs(SIDES) do if side == (ns.cdb.pickerSide or "right") then return i end end
                return 1
            end,
            function(v)
                ns.cdb.pickerSide = SIDES[v]
                if ns.Display and ns.Display.picker and ns.Display.picker:IsShown() then ns.Display:AnchorPicker() end
            end),
    }
end

function Config:RefreshDesign(Lo)
    local d = self.d
    Lo.place(d.hIcons, 20)
    for _, w in ipairs(d.opts) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    Lo.gap(8)
    Lo.place(d.hGrid, 20)
    for _, w in ipairs(d.grid) do w:Refresh(); Lo.place(w, w:GetHeight()) end
end

------------------------------------------------------------------ Notificaciones
function Config:BuildNotif(c)
    self.n = {}
    local n = self.n
    n.hHow = Header(c, L["How to alert"])
    n.how = {
        Check(c, L["Alert sound"], function() return ns.cdb.sound end, function(v) ns.cdb.sound = v end),
        Check(c, L["Big on-screen alert"], function() return ns.cdb.alerts end, function(v) ns.cdb.alerts = v end),
    }
    n.steppers = {
        Stepper(c, L["Warn before expiring"], function() return ns.cdb.warnSec end, function(v) ns.cdb.warnSec = v end,
            30, 30, 900, function(v) return ns.FormatTime(v) end),
        Stepper(c, L["Remind if missing (min)"], function() return ns.cdb.remindMin end, function(v) ns.cdb.remindMin = v end,
            1, 0, 30, function(v) return v == 0 and L["off"] or format(L["%d min"], v) end),
        Stepper(c, L["Low stock alert"], function() return ns.cdb.lowStock end, function(v) ns.cdb.lowStock = v end,
            1, 0, 20, function(v) return v == 0 and L["off"] or ("<= " .. v) end),
    }
    -- Avisos por buff
    n.hCats = Header(c, L["Alerts per buff"])
    n.cats = {}
    for _, cat in ipairs(ns.CATEGORIES) do
        if not cat.endgameOnly then
            local key = cat.key
            local box = CreateFrame("Frame", nil, c)
            box.title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            box.title:SetPoint("TOPLEFT")
            box.title:SetText(format("|T%s:14|t %s", cat.icon, cat.label))
            box.checks = {}
            local k = 0
            for _, kind in ipairs(ns.ALERT_KINDS) do
                if not kind.perStackOnly or cat.perStack then
                    local kk = kind.key
                    local cb = Check(box, kind.label,
                        function() return ns:AlertOn(key, kk) end,
                        function(v) ns:SetAlertOn(key, kk, v) end)
                    cb:SetSize(20, 20)
                    cb.label:SetFontObject("GameFontHighlightSmall")
                    cb:SetPoint("TOPLEFT", box, "TOPLEFT", 10 + (k % 2) * 190, -18 - math.floor(k / 2) * 20)
                    box.checks[#box.checks + 1] = cb
                    k = k + 1
                end
            end
            box:SetSize(CONTENT_W - 10, 20 + math.ceil(k / 2) * 20)
            box.key = key
            n.cats[#n.cats + 1] = box
        end
    end
    n.hSupp = Header(c, L["Don't alert when..."])
    n.supp = {
        Check(c, L["I'm in combat (alerts after)"], function() return ns.cdb.suppress.combat end, function(v) ns.cdb.suppress.combat = v end),
        Check(c, L["I'm in a city / inn"], function() return ns.cdb.suppress.resting end, function(v) ns.cdb.suppress.resting = v end),
        Check(c, L["I'm mounted"], function() return ns.cdb.suppress.mounted end, function(v) ns.cdb.suppress.mounted = v end),
    }
    -- End Game
    local eg = function() return ns.cdb.endgame end
    n.hEnd = Header(c, L["Consumables (End Game)"])
    n.endOpts = {
        Check(c, L["Check consumables when entering a dungeon/raid"], function() return eg().onInstance end, function(v) eg().onInstance = v end),
        Check(c, L["Check consumables on ready check"], function() return eg().onReadyCheck end, function(v) eg().onReadyCheck = v end),
        Stepper(c, L["Warn if less than (min)"], function() return eg().warnMin end, function(v) eg().warnMin = v end,
            5, 0, 60, function(v) return v == 0 and L["off"] or format(L["%d min"], v) end),
        Stepper(c, L["Consumables low stock"], function() return eg().lowStock end, function(v) eg().lowStock = v end,
            1, 0, 20, function(v) return v == 0 and L["off"] or ("<= " .. v) end),
    }
    n.btnRow = CreateFrame("Frame", nil, c)
    n.btnRow:SetSize(CONTENT_W, 24)
    local b1 = Btn(n.btnRow, L["Test alerts"], 140, 22, function() ns:TestAlerts() end)
    b1:SetPoint("LEFT")
end

function Config:RefreshNotif(Lo)
    local n = self.n
    local endgame = ns:IsEndgame()
    Lo.place(n.hHow, 20)
    for _, w in ipairs(n.how) do w:Refresh(); Lo.place(w, 24) end
    for _, w in ipairs(n.steppers) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    Lo.gap(8)
    Lo.place(n.hCats, 20)
    for _, box in ipairs(n.cats) do
        local cat = ns.CAT[box.key]
        if (box.key == "sleepingbag" and endgame) then
            box:Hide()
        else
            box.title:SetText(format("|T%s:14|t %s", cat.icon, cat.label))
            for _, cb in ipairs(box.checks) do cb:Refresh() end
            Lo.place(box, box:GetHeight())
        end
    end
    Lo.gap(8)
    Lo.place(n.hSupp, 20)
    for _, w in ipairs(n.supp) do w:Refresh(); Lo.place(w, 24) end
    if endgame then
        Lo.gap(8)
        Lo.place(n.hEnd, 20)
        for _, w in ipairs(n.endOpts) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    else
        n.hEnd:Hide()
        for _, w in ipairs(n.endOpts) do w:Hide() end
    end
    Lo.gap(8)
    Lo.place(n.btnRow, 24)
end

------------------------------------------------------------------ Changelog
function Config:BuildChangelog(c)
    self.cl = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    self.cl:SetWidth(CONTENT_W - 10)
    self.cl:SetJustifyH("LEFT")
    self.cl:SetSpacing(3)
    -- "## 1.4.0" → título; "- texto" → viñeta
    local out = {}
    for line in ((ns.CHANGELOG or "") .. "\n"):gmatch("([^\n]*)\n") do
        local ver = line:match("^##%s*(.+)$")
        local item = line:match("^%-%s*(.+)$")
        if ver then
            out[#out + 1] = (#out > 0 and "\n" or "") .. "|cffffd100" .. ver .. "|r"
        elseif item then
            item = item:gsub("`([^`]+)`", "|cff80c0ff%1|r")
            out[#out + 1] = "  • " .. item
        end
    end
    self.cl:SetText(table.concat(out, "\n"))
end

function Config:RefreshChangelog(Lo)
    Lo.place(self.cl, self.cl:GetStringHeight())
end

------------------------------------------------------------------ Refresco
function Config:Refresh()
    if not self.frame or not self.frame:IsShown() then return end
    -- punto rojo en Changelog si hay versión nueva sin ver
    self.tabButtons.changelog.dot:SetShown(ns.db.seenChangelog ~= Version())
    local key = self.tab or "general"
    local Lo = Layout(self.panels[key].content, self.panels[key].scroll)
    if key == "general" then self:RefreshGeneral(Lo)
    elseif key == "tooltip" then self:RefreshTooltip(Lo)
    elseif key == "design" then self:RefreshDesign(Lo)
    elseif key == "notif" then self:RefreshNotif(Lo)
    elseif key == "changelog" then self:RefreshChangelog(Lo) end
    Lo.finish()
end

-- Restablecer configuración (conserva posiciones, modo, lo vigilado y lo aprendido)
StaticPopupDialogs["CAMPXP_RESET_SETTINGS"] = {
    text = L["Reset all CampXP settings for this character to their defaults?\n\nPositions, mode and tracked consumables are kept."],
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() ns:ResetSettings() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

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
            local hide = (c.key == "sleepingbag" and ns:IsEndgame()) or (c.endgameOnly and not ns:IsEndgame())
            if hide then
                -- fuera de su modo
            elseif c.key == "consumables" and (s.trackedCount or 0) > 0 then
                txt = s.activeCount .. "/" .. s.trackedCount
                if s.active then r, g, bl = 0.3, 1, 0.3 else r, g, bl = 1, 0.85, 0.1 end
            elseif c.key == "consumables" then
                txt, r, g, bl = L["nothing tracked"], 0.5, 0.5, 0.5
            elseif s.phase == "active" or s.phase == "expiring" then
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
            if txt then GameTooltip:AddDoubleLine(c.label, txt, 1, 1, 1, r, g, bl) end
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
