-- Ventana de configuración + botón del minimapa
local ADDON, ns = ...
local L = ns.L
local Config = {}
ns.Config = Config

local format = string.format
local CONTENT_W = 642 -- ancho útil de cada pestaña (ventana de 700 px, igual en todas)
local ROW_W = 390     -- filas de opción (etiqueta + control): más anchas se leen mal
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
    f:SetSize(ROW_W, 22)
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
    f:SetSize(ROW_W, 26)
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
local function Dropdown(parent, label, labels, get, set, rowW, ddW)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(rowW or ROW_W, 26)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    f.label:SetPoint("LEFT")
    f.label:SetText(label)
    local ok, dd = pcall(CreateFrame, "DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    if not ok or not dd or not dd.SetupMenu then
        if ok and dd then dd:Hide() end
        f:Hide()
        return Stepper(parent, label, get, set, 1, 1, #labels, function(v) return labels[v] end)
    end
    dd:SetWidth(ddW or 150)
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
local WIN_W, WIN_H = 700, 600
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
    -- la pestaña Tooltip necesita espacio para la vista previa
    if self.d and self.d.preview and key ~= "design" then self.d.preview:Hide() end
    if key ~= "tooltip" and self.t and self.t.preview then self.t.preview.tip:Hide() end
    for k, b in pairs(self.tabButtons) do SetTabLook(b, k == key) end
    self:Refresh()
end

------------------------------------------------------------------ General
local STATUS_COLS = { check = 0, name = 26, status = 240, bags = 380, bonus = 460 }

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
local TIP_MODES = { "always", "shift", "off" }
local LEFT_W = 320 -- columna de opciones; a la derecha, la vista previa

-- Estados de ejemplo para la vista previa (si no tienes el buff puesto)
local function SampleState(key)
    local real = ns.state[key]
    if real and real.active then
        local s = setmetatable({}, { __index = real })
        if key == "food" then s.foodReason = s.foodReason or L["tooltip says XP"] end
        return s
    end
    local now = GetTime()
    local s = { active = true, phase = "active", remaining = 1500, expires = now + 1500, stacks = 2,
                sampleLost = 1240, sampleLostLevel = 3875 }
    if key == "campfire" then
        s.auraName = L["Camp Benefits"]
        s.sampleItems = { { L["Campfire Kit"], 3 } }
    elseif key == "sleepingbag" then
        s.auraName = L["Well-Rested"]
        s.sampleItems = { { L["Sleeping Bag"], 1 } }
    else
        s.auraName = L["Well Fed"]
        s.foodReason = L["tooltip says XP"]
        s.statText = "+6 Sta/Spi"
        s.sampleItems = { { L["Sweet Nectar"], 12 }, { L["Spiced Wolf Meat"], 8 } }
    end
    return s
end

function Config:BuildTooltip(c)
    self.t = {}
    local t = self.t
    t.hIcons = Header(c, L["Icon tooltips"])
    t.note = Note(c, L["Choose when each line of this icon's tooltip shows: always, only while holding Shift, or never."])
    t.note:SetWidth(LEFT_W)
    -- ícono a configurar: sus opciones son solo suyas
    t.catRow = CreateFrame("Frame", nil, c)
    t.catRow:SetSize(LEFT_W, 30)
    t.catLabel = t.catRow:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    t.catLabel:SetPoint("LEFT")
    t.catLabel:SetText(L["Icon"])
    t.cats = {}
    local px = 70
    for _, cat in ipairs(ns.CATEGORIES) do
        if not cat.endgameOnly then
            local key = cat.key
            local b = TabButton(t.catRow, "", function() Config.previewCat = key; Config:Refresh() end)
            b:SetSize(28, 28)
            b.text:Hide()
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3)
            b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            b.icon:SetTexture(cat.icon)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b:SetPoint("LEFT", px, 0)
            px = px + 34
            b.key = key
            t.cats[#t.cats + 1] = b
        end
    end
    t.catName = t.catRow:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    t.catName:SetPoint("LEFT", px + 4, 0)
    t.rows = {}
    local labels = { L["Always"], L["With Shift"], L["Never"] }
    for _, sec in ipairs(ns.TOOLTIP_SECTIONS) do
        local key = sec.key
        local row = Dropdown(c, L[sec.label], labels,
            function()
                local m = ns:TooltipMode(key, Config:TipCat())
                for i, v in ipairs(TIP_MODES) do if v == m then return i end end
                return 1
            end,
            function(v)
                local cat = Config:TipCat()
                ns.cdb.tooltip = ns.cdb.tooltip or {}
                if type(ns.cdb.tooltip[cat]) ~= "table" then ns.cdb.tooltip[cat] = {} end
                ns.cdb.tooltip[cat][key] = TIP_MODES[v]
                Config:UpdatePreview()
            end, LEFT_W, 110)
        t.rows[#t.rows + 1] = row
        t.rowOnly = t.rowOnly or {}
        t.rowOnly[#t.rows] = sec.only or false
    end
    t.hXP = Header(c, L["XP information"])
    t.opts = {
        Check(c, L["XP gained/lost in the XP bar tooltip"], function() return ns.cdb.showXPTooltip end, function(v) ns.cdb.showXPTooltip = v end),
        Check(c, L["XP gained/lost summary on level up"], function() return ns.cdb.xpSummary end, function(v) ns.cdb.xpSummary = v end),
    }

    -- Vista previa
    local pv = CreateFrame("Frame", nil, c)
    pv:SetSize(250, 400)
    pv.title = pv:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pv.title:SetPoint("TOPLEFT")
    pv.title:SetText(L["Preview"])
    pv.shift = Check(pv, L["Simulate Shift"], function() return Config.previewShift end,
        function(v) Config.previewShift = v; Config:UpdatePreview() end)
    pv.shift:SetPoint("TOPLEFT", 0, -20)
    -- hijo de la ventana (no del scroll): así no se recorta al crecer
    local tip = CreateFrame("GameTooltip", "CampXPPreviewTip", self.frame, "GameTooltipTemplate")
    tip:SetFrameStrata("DIALOG")
    tip:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 20)
    pv.tip = tip
    t.preview = pv
end

-- ícono elegido en la pestaña Tooltip (el saco no existe en End Game)
function Config:TipCat()
    local key = self.previewCat or "food"
    if ns:IsEndgame() and key == "sleepingbag" then key = "food" end
    return key
end

function Config:UpdatePreview()
    local pv = self.t and self.t.preview
    if not pv or self.tab ~= "tooltip" then return end
    local key = self:TipCat()
    pv.shift:Refresh()
    local tip = pv.tip
    tip:SetOwner(self.frame, "ANCHOR_NONE")
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", pv, "TOPLEFT", 0, -50)
    tip:ClearLines()
    ns:FillIconTooltip(tip, ns.CAT[key], SampleState(key), self.previewShift)
end

function Config:RefreshTooltip(Lo)
    local t = self.t
    Lo.place(t.hIcons, 20)
    Lo.place(t.note, t.note:GetStringHeight())
    local key = self:TipCat()
    for _, b in ipairs(t.cats) do
        SetTabLook(b, b.key == key)
        b:SetShown(not (ns:IsEndgame() and b.key == "sleepingbag"))
    end
    t.catName:SetText(ns.CAT[key].label)
    Lo.place(t.catRow, 30)
    for i, w in ipairs(t.rows) do
        -- solo las líneas que existen en este ícono (stacks: saco; detección: comida)
        local only = t.rowOnly[i]
        if only and not only[key] then
            w:Hide()
        else
            w:Refresh(); Lo.place(w, w:GetHeight())
        end
    end
    Lo.gap(8)
    Lo.place(t.hXP, 20)
    for _, w in ipairs(t.opts) do w:Refresh(); Lo.place(w, 24) end
    -- la vista previa va a la derecha, fija arriba
    t.preview:ClearAllPoints()
    t.preview:SetPoint("TOPLEFT", self.panels.tooltip.content, "TOPLEFT", LEFT_W + 24, -4)
    t.preview:Show()
    self:UpdatePreview()
end

------------------------------------------------------------------ Diseño
-- Selector de color del juego (API nueva o antigua)
local function PickColor(r, g, b, onChange)
    local prev = { r, g, b }
    local function apply()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onChange(nr, ng, nb)
    end
    local function cancel() onChange(prev[1], prev[2], prev[3]) end
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = apply, cancelFunc = cancel })
    else
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

local function Restyle()
    if ns.Display then ns.Display:ApplyStyle() end
end

function Config:BuildDesign(c)
    self.d = {}
    local d = self.d
    d.hIcons = Header(c, L["Main icons"])
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
        Stepper(c, L["Icon size"], function() return ns.cdb.iconSize or 40 end,
            function(v) ns.cdb.iconSize = v; Restyle() end, 4, 24, 72, function(v) return v .. " px" end),
        Stepper(c, L["Space between icons"], function() return ns.cdb.iconGap or 8 end,
            function(v) ns.cdb.iconGap = v; Restyle() end, 2, 0, 40, function(v) return v .. " px" end),
        Dropdown(c, L["Orientation"], { L["Horizontal"], L["Vertical"] },
            function() return ns.cdb.vertical and 2 or 1 end,
            function(v) ns.cdb.vertical = (v == 2); Restyle() end),
        Stepper(c, L["Missing buff opacity"], function() return ns.cdb.inactiveAlpha or 40 end,
            function(v) ns.cdb.inactiveAlpha = v end, 10, 10, 100, function(v) return v .. "%" end),
    }
    d.hText = Header(c, L["Icon texts"])
    d.texts = {
        Stepper(c, L["Text size"], function() return ns.cdb.textScale or 100 end,
            function(v) ns.cdb.textScale = v; Restyle() end, 10, 60, 200, function(v) return v .. "%" end),
        Check(c, L["Timer"], function() return ns.cdb.showTimer ~= false end, function(v) ns.cdb.showTimer = v end),
        Check(c, L["Count (bags / stacks)"], function() return ns.cdb.showCount ~= false end, function(v) ns.cdb.showCount = v end),
        Check(c, L["Bonus / food stat"], function() return ns.cdb.showBonus ~= false end, function(v) ns.cdb.showBonus = v end),
        Check(c, L["Show XP lost above the buff icon"], function() return ns.cdb.showLostBadge end, function(v) ns.cdb.showLostBadge = v end),
    }
    d.hGrid = Header(c, L["Grid icons"])
    d.grid = {
        Dropdown(c, L["Position"], { L["Right"], L["Left"], L["Above"], L["Below"] },
            function()
                for i, side in ipairs(SIDES) do if side == (ns.cdb.pickerSide or "right") then return i end end
                return 1
            end,
            function(v)
                ns.cdb.pickerSide = SIDES[v]
                if ns.Display and ns.Display.picker and ns.Display.picker:IsShown() then ns.Display:AnchorPicker() end
            end),
        Stepper(c, L["Columns"], function() return ns.cdb.gridCols or 5 end,
            function(v) ns.cdb.gridCols = v; Config:RebuildGrid() end, 1, 1, 10, function(v) return tostring(v) end),
        Stepper(c, L["Button size"], function() return ns.cdb.gridSize or 36 end,
            function(v) ns.cdb.gridSize = v; Config:RebuildGrid() end, 4, 24, 60, function(v) return v .. " px" end),
        Check(c, L["Open/close animation"], function() return ns.cdb.gridAnim ~= false end, function(v) ns.cdb.gridAnim = v end),
    }
    -- textos de los botones de la grilla
    d.hGridText = Header(c, L["Grid buttons"])
    d.gridText = {
        Stepper(c, L["Text size"], function() return ns.cdb.gridTextScale or 100 end,
            function(v) ns.cdb.gridTextScale = v; Config:RebuildGrid() end, 10, 60, 200, function(v) return v .. "%" end),
        Check(c, L["Count in bags"], function() return ns.cdb.gridShowCount ~= false end,
            function(v) ns.cdb.gridShowCount = v; Config:RebuildGrid() end),
        Check(c, L["XP / stat badge (XP, Sta, SP...)"], function() return ns.cdb.gridShowBadge ~= false end,
            function(v) ns.cdb.gridShowBadge = v; Config:RebuildGrid() end),
        Check(c, L["Buff ready check (consumables)"], function() return ns.cdb.gridShowCheck ~= false end,
            function(v) ns.cdb.gridShowCheck = v; Config:RebuildGrid() end),
    }

    -- Colores de las estadísticas en la grilla (solo End Game)
    d.hColors = Note(c, L["Stat colors in the grid (End Game)"])
    d.hColors:SetFontObject("GameFontNormal")
    local box = CreateFrame("Frame", nil, c)
    local COLS, CW = 4, 96
    box:SetSize(COLS * CW, math.ceil(#ns.STAT_KEYS / COLS) * 22)
    box.swatches = {}
    for i, key in ipairs(ns.STAT_KEYS) do
        local sw = CreateFrame("Button", nil, box)
        sw:SetSize(CW - 6, 20)
        sw:SetPoint("TOPLEFT", ((i - 1) % COLS) * CW, -math.floor((i - 1) / COLS) * 22)
        sw.edge = sw:CreateTexture(nil, "BACKGROUND")
        sw.edge:SetSize(16, 16)
        sw.edge:SetPoint("LEFT")
        sw.edge:SetColorTexture(0, 0, 0, 1)
        sw.color = sw:CreateTexture(nil, "ARTWORK")
        sw.color:SetPoint("TOPLEFT", sw.edge, "TOPLEFT", 2, -2)
        sw.color:SetPoint("BOTTOMRIGHT", sw.edge, "BOTTOMRIGHT", -2, 2)
        sw.text = sw:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        sw.text:SetPoint("LEFT", sw.edge, "RIGHT", 5, 0)
        sw.key = key
        sw:SetScript("OnClick", function()
            local r, g, b = ns:StatColor(key)
            PickColor(r, g, b, function(nr, ng, nb)
                ns.cdb.statColors = ns.cdb.statColors or {}
                ns.cdb.statColors[key] = { nr, ng, nb }
                Config:RefreshColors()
                Config:RebuildGrid()
                Config:UpdateDesignPreview()
            end)
        end)
        sw:SetScript("OnEnter", function(self) self.edge:SetColorTexture(1, 0.82, 0, 1) end)
        sw:SetScript("OnLeave", function(self) self.edge:SetColorTexture(0, 0, 0, 1) end)
        box.swatches[i] = sw
    end
    d.colors = box
    d.colorReset = CreateFrame("Frame", nil, c)
    d.colorReset:SetSize(ROW_W, 24)
    local rb = Btn(d.colorReset, L["Default colors"], 140, 22, function()
        ns.cdb.statColors = {}
        Config:RefreshColors()
        Config:RebuildGrid()
        Config:UpdateDesignPreview()
    end)
    rb:SetPoint("LEFT")

    -- Vista previa: íconos de muestra (activo, por expirar, falta con ítem), hijos de la ventana
    local pv = CreateFrame("Frame", nil, self.frame)
    pv:SetSize(240, 300)
    pv:SetFrameLevel((self.frame:GetFrameLevel() or 1) + 10)
    pv.title = pv:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pv.title:SetPoint("TOPLEFT")
    pv.title:SetText(L["Preview"])
    pv.anchor = CreateFrame("Frame", nil, pv)
    pv.anchor:SetSize(10, 10)
    pv.icons = {}
    if ns.Display then
        for _, key in ipairs({ "campfire", "sleepingbag", "food" }) do
            local b = ns.Display:CreatePreviewIcon(pv.anchor, ns.CAT[key])
            b.key = key
            pv.icons[#pv.icons + 1] = b
        end
    end
    pv.note = pv:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    pv.note:SetWidth(230)
    pv.note:SetJustifyH("LEFT")
    pv.note:SetText(L["Active · expiring · missing (item in bags)"])
    -- grilla de muestra: comida con XP, comida sin XP, kit de fogata, consumible listo
    pv.gridTitle = pv:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pv.gridTitle:SetText(L["Grid"])
    pv.grid = CreateFrame("Frame", nil, pv)
    pv.grid:SetSize(10, 10)
    pv.picks = {}
    if ns.Display and ns.Display.CreatePreviewPick then
        local samples = {
            { icon = "Interface\\Icons\\INV_Misc_Food_15", count = 12, xp = true },
            { icon = "Interface\\Icons\\INV_Misc_Food_19", count = 5, xp = false, food2 = true },
            { icon = ns.CAT.campfire.icon, count = 3, kit = true },
            { icon = "Interface\\Icons\\INV_Potion_97", count = 4, ready = true },
        }
        for _, smp in ipairs(samples) do
            local b = ns.Display:CreatePreviewPick(pv.grid, smp.icon)
            b.sample = smp
            pv.picks[#pv.picks + 1] = b
        end
    end
    pv:Hide()
    d.preview = pv
end

-- Si la grilla está abierta, se rearma con el nuevo tamaño/columnas
function Config:RebuildGrid()
    local D = ns.Display
    if D and D.picker and D.picker:IsShown() and not InCombatLockdown() then D:BuildPicker(); D:AnchorPicker() end
end

local function PreviewStates()
    local now = GetTime()
    return {
        campfire = { active = true, phase = "active", remaining = 1500, duration = 3600, expires = now + 1500, count = 3, items = {}, previewBonus = 0 },
        sleepingbag = { active = true, phase = "expiring", remaining = 45, duration = 600, expires = now + 45, stacks = 2, count = 1,
                        items = {}, previewBonus = 2 },
        food = { active = false, phase = "missing_have", count = 12, items = {}, previewLost = 1240, previewBonus = 0, statText = "+6 Sta/Spi" },
    }
end

function Config:RefreshColors()
    if not (self.d and self.d.colors) then return end
    for _, sw in ipairs(self.d.colors.swatches) do
        local r, g, b = ns:StatColor(sw.key)
        sw.color:SetColorTexture(r, g, b, 1)
        sw.text:SetText(L[sw.key])
        sw.text:SetTextColor(r, g, b)
    end
end

function Config:UpdateDesignPreview()
    local pv = self.d and self.d.preview
    if not pv or not ns.Display or #pv.icons == 0 then return end
    ns.Display:PlaceIcons(pv.anchor, pv.icons)
    local lay = ns.Display:Layout()
    pv.anchor:ClearAllPoints()
    -- margen para los textos de los lados/arriba
    pv.anchor:SetPoint("TOPLEFT", pv, "TOPLEFT", lay.vertical and 60 or 10, -40)
    local states, now = PreviewStates(), GetTime()
    for _, b in ipairs(pv.icons) do
        ns.Display:PaintButton(b, ns.CAT[b.key], states[b.key], now)
    end
    pv.note:ClearAllPoints()
    pv.note:SetPoint("TOPLEFT", pv.anchor, "BOTTOMLEFT", lay.vertical and -50 or 0, -24)

    -- grilla de muestra con el tamaño, columnas y textos elegidos
    pv.gridTitle:ClearAllPoints()
    pv.gridTitle:SetPoint("TOPLEFT", pv.note, "BOTTOMLEFT", 0, -14)
    pv.grid:ClearAllPoints()
    pv.grid:SetPoint("TOPLEFT", pv.gridTitle, "BOTTOMLEFT", 0, -8)
    local D = ns.Display
    local gs, gap = D.GridSize(), D.PICK_GAP
    local cols = math.max(1, math.min(#pv.picks, ns.cdb.gridCols or 5))
    local gk = gs / D.PICK_SIZE
    local endgame = ns:IsEndgame()
    for i, b in ipairs(pv.picks) do
        local smp = b.sample
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:SetScale(gk)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", pv.grid, "TOPLEFT", col * (gs + gap) / gk, -row * (gs + gap) / gk)
        if smp.xp or (endgame and smp.food2) then
            -- End Game: insignia con el color de su estadística (Aguante / Fuerza de ejemplo)
            D.StylePickButton(b, 0.3, 1, 0.3, true)
            local key = smp.food2 and "Str" or "Sta"
            b.badge:SetText(endgame and L[key] or "XP")
            if endgame then b.badge:SetTextColor(ns:StatColor(key)) else b.badge:SetTextColor(0.3, 1, 0.3) end
            b.icon:SetDesaturated(false)
        elseif smp.kit then
            D.StylePickButton(b, 1, 0.82, 0, true)
            b.badge:SetText("")
        elseif smp.ready then
            D.StylePickButton(b, 0.3, 0.75, 1, true)
            b.badge:SetText("")
        else
            D.StylePickButton(b, 0.4, 0.4, 0.4, false)
            b.badge:SetText("")
            b.icon:SetDesaturated(not endgame)
        end
        b.count:SetText(smp.count)
        b.check:SetShown(smp.ready == true and ns.cdb.gridShowCheck ~= false)
    end
end

function Config:RefreshDesign(Lo)
    local d = self.d
    -- Íconos principales: forma, tamaño y textos
    Lo.place(d.hIcons, 20)
    for _, w in ipairs(d.opts) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    for _, w in ipairs(d.texts) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    d.hText:Hide(); d.hGridText:Hide()
    Lo.gap(10)
    -- Íconos de la grilla: posición, tamaño, textos y animación (la animación al final)
    Lo.place(d.hGrid, 20)
    local anim = d.grid[#d.grid]
    for i = 1, #d.grid - 1 do local w = d.grid[i]; w:Refresh(); Lo.place(w, w:GetHeight()) end
    for _, w in ipairs(d.gridText) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    anim:Refresh(); Lo.place(anim, anim:GetHeight())
    if ns:IsEndgame() then
        Lo.gap(6)
        Lo.place(d.hColors, 16)
        self:RefreshColors()
        Lo.place(d.colors, d.colors:GetHeight(), 4)
        Lo.place(d.colorReset, 24)
    else
        d.hColors:Hide(); d.colors:Hide(); d.colorReset:Hide()
    end
    d.preview:ClearAllPoints()
    d.preview:SetPoint("TOPLEFT", self.panels.design.scroll, "TOPLEFT", ROW_W + 30, -4)
    d.preview:Show()
    self:UpdateDesignPreview()
end

------------------------------------------------------------------ Notificaciones
-- Desplegable de sonido + botón ▶ para escucharlo
local function SoundRow(c, label, field, kind)
    local labels = {}
    for i, snd in ipairs(ns.SOUNDS) do labels[i] = L[snd.label] end
    local row = Dropdown(c, label, labels,
        function()
            for i, snd in ipairs(ns.SOUNDS) do if snd.key == ns.cdb[field] then return i end end
            return 1
        end,
        function(v) ns.cdb[field] = ns.SOUNDS[v].key end)
    local play = Btn(row, ">", 24, 20, function()
        local catKey = (kind == "consumables") and "consumables" or "food"
        local id = ns:SoundFor(kind, ns.CAT[catKey])
        if id then PlaySound(id, "Master") end
    end)
    play:SetPoint("LEFT", row, "RIGHT", 6, 0)
    return row
end

local NOTIF_KINDS = { -- columnas de la tabla de avisos por buff
    { key = "expiring",     label = "Expiring" },
    { key = "missing",      label = "Missing" },
    { key = "expired_none", label = "Ran out" },
    { key = "lowstock",     label = "Low stock" },
    { key = "maxstacks",    label = "Max stacks", perStackOnly = true },
}
local NCOL0, NCOLW = 170, 88

function Config:BuildNotif(c)
    self.n = {}
    local n = self.n
    -- Cómo avisar
    n.hHow = Header(c, L["How to alert"])
    n.how = {
        Check(c, L["Big on-screen text"], function() return ns.cdb.alerts end, function(v) ns.cdb.alerts = v end),
        Dropdown(c, L["Text position"], { L["Top"], L["Center"] },
            function() return ns.cdb.alertPos == "center" and 2 or 1 end,
            function(v) ns.cdb.alertPos = (v == 2) and "center" or "top" end),
        Stepper(c, L["Text size"], function() return ns.cdb.alertSize or 100 end,
            function(v) ns.cdb.alertSize = v end, 10, 60, 200, function(v) return v .. "%" end),
        Check(c, L["Chat message"], function() return ns.cdb.chatAlerts ~= false end, function(v) ns.cdb.chatAlerts = v end),
        Check(c, L["Flash the icon"], function() return ns.cdb.flashAlerts ~= false end, function(v) ns.cdb.flashAlerts = v end),
        Check(c, L["Alert sound"], function() return ns.cdb.sound end, function(v) ns.cdb.sound = v end),
        SoundRow(c, L["Sound: about to expire"], "soundExpiring", "expiring"),
        SoundRow(c, L["Sound: missing / ran out"], "soundMissing", "missing"),
    }
    -- Tiempos
    n.hTimes = Header(c, L["Timing"])
    n.times = {
        Stepper(c, L["Warn before expiring"], function() return ns.cdb.warnSec end, function(v) ns.cdb.warnSec = v end,
            30, 30, 900, function(v) return ns.FormatTime(v) end),
        Stepper(c, L["Repeat reminder every"], function() return ns.cdb.remindMin end, function(v) ns.cdb.remindMin = v end,
            1, 0, 30, function(v) return v == 0 and L["only once"] or format(L["%d min"], v) end),
        Stepper(c, L["Low stock alert"], function() return ns.cdb.lowStock end, function(v) ns.cdb.lowStock = v end,
            1, 0, 20, function(v) return v == 0 and L["off"] or ("<= " .. v) end),
    }
    -- Tabla: avisos por buff
    n.hCats = Header(c, L["Alerts per buff"])
    local tbl = CreateFrame("Frame", nil, c)
    tbl:SetSize(CONTENT_W - 10, 20)
    local head = CreateFrame("Frame", nil, tbl)
    head:SetSize(CONTENT_W - 10, 18)
    head:SetPoint("TOPLEFT")
    local hbg = head:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.85, 0.62, 0.1, 0.25)
    local h0 = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h0:SetPoint("LEFT", 30, 0)
    h0:SetText(L["Buff"])
    for i, k in ipairs(NOTIF_KINDS) do
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", head, "LEFT", NCOL0 + (i - 0.5) * NCOLW, 0)
        fs:SetText(L[k.label])
    end
    tbl.rows = {}
    for _, cat in ipairs(ns.CATEGORIES) do
        if not cat.endgameOnly then
            local key = cat.key
            local row = CreateFrame("Frame", nil, tbl)
            row:SetSize(CONTENT_W - 10, 24)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 6, 0)
            row.icon:SetTexture(cat.icon)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.checks = {}
            for i, k in ipairs(NOTIF_KINDS) do
                local x = NCOL0 + (i - 0.5) * NCOLW
                if k.perStackOnly and not cat.perStack then
                    local dash = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                    dash:SetPoint("CENTER", row, "LEFT", x, 0)
                    dash:SetText("-")
                else
                    local kind = k.key
                    local cb = Check(row, "", function() return ns:AlertOn(key, kind) end,
                        function(v) ns:SetAlertOn(key, kind, v) end)
                    cb:SetSize(22, 22)
                    cb:SetPoint("CENTER", row, "LEFT", x, 0)
                    row.checks[#row.checks + 1] = cb
                end
            end
            row.key = key
            tbl.rows[#tbl.rows + 1] = row
        end
    end
    n.table = tbl
    -- No avisar cuando…
    n.hSupp = Header(c, L["Don't alert when..."])
    local sp = function() return ns.cdb.suppress end
    n.supp = {
        Check(c, L["I'm in combat (alerts after)"], function() return sp().combat end, function(v) sp().combat = v end),
        Check(c, L["I'm in a city / inn"], function() return sp().resting end, function(v) sp().resting = v end),
        Check(c, L["I'm mounted"], function() return sp().mounted end, function(v) sp().mounted = v end),
        Check(c, L["I'm dead or a ghost"], function() return sp().dead ~= false end, function(v) sp().dead = v end),
        Check(c, L["I'm on a flight path"], function() return sp().taxi ~= false end, function(v) sp().taxi = v end),
        Check(c, L["I'm AFK"], function() return sp().afk end, function(v) sp().afk = v end),
    }
    n.suppInstance = Check(c, L["I'm in a dungeon/raid (Leveling)"], function() return sp().instance end, function(v) sp().instance = v end)
    -- Consumibles (End Game)
    local eg = function() return ns.cdb.endgame end
    n.hEnd = Header(c, L["Consumables (End Game)"])
    n.endOpts = {
        Check(c, L["Check consumables when entering a dungeon/raid"], function() return eg().onInstance end, function(v) eg().onInstance = v end),
        Check(c, L["Check consumables on ready check"], function() return eg().onReadyCheck end, function(v) eg().onReadyCheck = v end),
        Stepper(c, L["Warn if less than (min)"], function() return eg().warnMin end, function(v) eg().warnMin = v end,
            5, 0, 60, function(v) return v == 0 and L["off"] or format(L["%d min"], v) end),
        Stepper(c, L["Consumables low stock"], function() return eg().lowStock end, function(v) eg().lowStock = v end,
            1, 0, 20, function(v) return v == 0 and L["off"] or ("<= " .. v) end),
        SoundRow(c, L["Sound: consumables"], "soundConsumables", "consumables"),
    }
    -- Probar
    n.hTest = Header(c, L["Try them"])
    n.testRow = CreateFrame("Frame", nil, c)
    n.testRow:SetSize(CONTENT_W, 50)
    n.testBtns = {}
    local tests = {
        { "expiring", L["Expiring"] }, { "missing", L["Missing"] }, { "expired_none", L["Ran out"] },
        { "lowstock", L["Low stock"] }, { "maxstacks", L["Max stacks"] }, { "consumables", L["Consumables"] },
    }
    for i, t in ipairs(tests) do
        local kind = t[1]
        local b = Btn(n.testRow, t[2], 100, 22, function() ns:TestAlert(kind) end)
        b:SetPoint("TOPLEFT", ((i - 1) % 5) * 106, -math.floor((i - 1) / 5) * 26)
        b.kind = kind
        n.testBtns[i] = b
    end
    n.testAll = Btn(n.testRow, L["Test alerts"], 140, 22, function() ns:TestAlerts() end)
end

function Config:RefreshNotif(Lo)
    local n = self.n
    local endgame = ns:IsEndgame()
    Lo.place(n.hHow, 20)
    for _, w in ipairs(n.how) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    Lo.gap(8)
    Lo.place(n.hTimes, 20)
    for _, w in ipairs(n.times) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    Lo.gap(8)
    Lo.place(n.hCats, 20)
    local tbl, yy, i = n.table, -20, 0
    for _, row in ipairs(tbl.rows) do
        if row.key == "sleepingbag" and endgame then
            row:Hide()
        else
            i = i + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", tbl, "TOPLEFT", 0, yy)
            yy = yy - 24
            row.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
            row.name:SetText(ns.CAT[row.key].label)
            for _, cb in ipairs(row.checks) do cb:Refresh() end
            row:Show()
        end
    end
    tbl:SetHeight(-yy)
    Lo.place(tbl, tbl:GetHeight())
    Lo.gap(8)
    Lo.place(n.hSupp, 20)
    for _, w in ipairs(n.supp) do w:Refresh(); Lo.place(w, 24) end
    if endgame then
        n.suppInstance:Hide()
    else
        n.suppInstance:Refresh(); Lo.place(n.suppInstance, 24)
    end
    if endgame then
        Lo.gap(8)
        Lo.place(n.hEnd, 20)
        for _, w in ipairs(n.endOpts) do w:Refresh(); Lo.place(w, w:GetHeight()) end
    else
        n.hEnd:Hide()
        for _, w in ipairs(n.endOpts) do w:Hide() end
    end
    Lo.gap(8)
    Lo.place(n.hTest, 20)
    -- en Leveling no hay prueba de consumibles; en End Game no hay saco (stacks)
    local x, rowN = 0, 0
    local shown = 0
    for _, b in ipairs(n.testBtns) do
        local hide = (b.kind == "consumables" and not endgame) or (b.kind == "maxstacks" and endgame)
        b:SetShown(not hide)
        if not hide then
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (shown % 5) * 106, -math.floor(shown / 5) * 26)
            shown = shown + 1
        end
    end
    n.testAll:ClearAllPoints()
    n.testAll:SetPoint("TOPLEFT", 0, -(math.floor((shown - 1) / 5) + 1) * 26 - 4)
    n.testRow:SetHeight((math.floor((shown - 1) / 5) + 2) * 26 + 4)
    Lo.place(n.testRow, n.testRow:GetHeight())
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
