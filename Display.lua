-- Iconos por categoría (son botones seguros: clic = usar el ítem)
local ADDON, ns = ...
local L = ns.L
local Display = {}
ns.Display = Display

local SIZE, GAP = 40, 8
local GetTime, format, max, min = GetTime, string.format, math.max, math.min

local PHASE_COLOR = {
    active       = { 0.20, 0.90, 0.30 },
    expiring     = { 1.00, 0.55, 0.10 },
    missing_have = { 1.00, 0.85, 0.10 },
    missing_none = { 0.35, 0.35, 0.35 },
    unconfigured = { 0.25, 0.25, 0.25 },
    disabled     = { 0, 0, 0 },
}

local function SavePos(frame, key)
    local p, _, rp, x, y = frame:GetPoint()
    ns.cdb.pos[key] = { p, rp, x, y }
end

function Display:RestorePos()
    local a = self.anchor
    if not a then return end
    local p = ns.cdb.pos.icons
    a:ClearAllPoints()
    if p then
        a:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        a:SetPoint("CENTER", UIParent, "CENTER", 0, -190)
    end
end

function Display:Create()
    local anchor = CreateFrame("Frame", "CampXPAnchor", UIParent)
    anchor:SetSize(#ns.CATEGORIES * (SIZE + GAP) - GAP, SIZE)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    self.anchor = anchor
    self:RestorePos()

    self.buttons = {}
    for i, c in ipairs(ns.CATEGORIES) do
        local b = CreateFrame("Button", "CampXPIcon_" .. c.key, anchor, "SecureActionButtonTemplate")
        b:SetSize(SIZE, SIZE)
        b:SetPoint("LEFT", anchor, "LEFT", (i - 1) * (SIZE + GAP), 0)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:RegisterForDrag("LeftButton")
        b:SetAttribute("shift-type1", "none") -- Shift+arrastrar mueve, no usa el ítem

        self:CreateIconVisual(b, c)

        b:SetScript("OnDragStart", function()
            if IsShiftKeyDown() and not ns.cdb.locked and not InCombatLockdown() then
                anchor:StartMoving()
            end
        end)
        b:SetScript("OnDragStop", function()
            anchor:StopMovingOrSizing()
            SavePos(anchor, "icons")
        end)
        b:SetScript("OnEnter", function(self) Display:ShowTooltip(self, c) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- comida, campamento y consumibles: el clic abre su grilla (el saco usa el ítem directo)
        local PICKER_MODE = { food = "food", campfire = "camp", consumables = "consumables" }
        if PICKER_MODE[c.key] then
            local mode = PICKER_MODE[c.key]
            b:HookScript("OnClick", function(_, _, down)
                if down or IsShiftKeyDown() then return end
                Display:TogglePicker(mode)
            end)
        end

        self.buttons[c.key] = b
    end
    self:CreateFoodPicker()
    self:ApplyStyle()
end

-- Partes visuales de un ícono (también se usan en la vista previa de Diseño)
function Display:CreateIconVisual(b, c)
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    b.border:SetColorTexture(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetTexture(c.icon)

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- brillo pulsante
    b.glowFrame = CreateFrame("Frame", nil, b)
    b.glowFrame:SetAllPoints()
    b.glowFrame:SetFrameLevel(b:GetFrameLevel() + 2)
    b.glow = b.glowFrame:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(SIZE * 1.85, SIZE * 1.85)
    b.glowFrame:SetAlpha(0)

    local ag = b.glowFrame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(0.15)
    anim:SetToAlpha(1)
    anim:SetDuration(0.6)
    b.pulse, b.pulseAnim = ag, anim

    -- textos en su propio marco: el del brillo queda en alpha 0 cuando no pulsa
    b.textFrame = CreateFrame("Frame", nil, b)
    b.textFrame:SetAllPoints()
    b.textFrame:SetFrameLevel(b:GetFrameLevel() + 3)

    b.timer = b.textFrame:CreateFontString(nil, "OVERLAY")
    b.timer:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    b.timer:SetPoint("TOP", b, "BOTTOM", 0, -3)

    b.count = b.textFrame:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)

    -- % de XP actual (ej. "+2%" con 2 stacks de Well-Rested)
    -- XP perdida en este nivel por no tener el buff (encima del icono)
    b.lost = b.textFrame:CreateFontString(nil, "OVERLAY")
    b.lost:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.lost:SetPoint("BOTTOM", b, "TOP", 0, 3)
    b.lost:SetTextColor(1, 0.3, 0.3)

    b.bonus = b.textFrame:CreateFontString(nil, "OVERLAY")
    b.bonus:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.bonus:SetPoint("TOPLEFT", 2, -2)
    b.bonus:SetTextColor(0.6, 0.85, 1)

    self:CreateMinimalParts(b)
end

-- Ícono de muestra (no seguro) para la vista previa de la pestaña Diseño
function Display:CreatePreviewIcon(parent, c)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    self:CreateIconVisual(b, c)
    self.previewButtons = self.previewButtons or {}
    table.insert(self.previewButtons, b)
    self:StyleButton(b)
    return b
end

-- Estilos modernos: minimal (cuadrado redondeado) y round (circular) ----------
-- Esquinas redondeadas (máscara), borde de 1 px que cambia de color, sombra suave
-- y un halo que "respira" cuando falta el buff y tienes el ítem.
local MEDIA = "Interface\\AddOns\\CampXP\\Media\\"
local CORE = 0.75 -- en Shadow/Glow (128 px) el cuadrado ocupa 96 px

-- Formas de los estilos modernos (minimal = cuadrado redondeado, round = círculo)
local SHAPES = {
    minimal = { mask = "Mask", border = "Border", shadow = "Shadow", glow = "Glow" },
    round   = { mask = "RoundMask", border = "RoundBorder", shadow = "RoundShadow", glow = "RoundGlow" },
}
-- true si el estilo actual es uno de los modernos (minimal o round)
local function Modern() return SHAPES[ns.cdb.iconStyle] ~= nil end
Display.IsModern = Modern

function Display:CreateMinimalParts(b)
    -- sombra detrás del icono
    b.mShadow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.mShadow:SetTexture(MEDIA .. "Shadow")
    b.mShadow:SetSize((SIZE + 6) / CORE, (SIZE + 6) / CORE)
    b.mShadow:SetPoint("CENTER", 0, -2)
    b.mShadow:SetVertexColor(0, 0, 0, 0.85)

    -- máscara de esquinas redondeadas (se aplica al icono solo en este estilo)
    b.mMask = b:CreateMaskTexture()
    b.mMask:SetTexture(MEDIA .. "Mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    b.mMask:SetAllPoints(b.icon)

    -- borde fino + halo, en un marco sobre el icono
    b.mDecor = CreateFrame("Frame", nil, b)
    b.mDecor:SetAllPoints()
    b.mDecor:SetFrameLevel(b:GetFrameLevel() + 1)
    b.mBorder = b.mDecor:CreateTexture(nil, "OVERLAY")
    b.mBorder:SetTexture(MEDIA .. "Border")
    b.mBorder:SetAllPoints()

    -- cápsulas oscuras detrás de los textos (se leen sobre arte claro)
    local function Capsule(parent, fs)
        local t = parent:CreateTexture(nil, "BACKGROUND")
        t:SetColorTexture(0, 0, 0, 0.6)
        t:SetPoint("CENTER", fs, "CENTER", 0, 0)
        t:Hide()
        return t
    end
    b.mCountBg = Capsule(b.textFrame, b.count)
    b.mBonusBg = Capsule(b.textFrame, b.bonus)
    b.mLostBg = Capsule(b.textFrame, b.lost)

    b.mGlowFrame = CreateFrame("Frame", nil, b)
    b.mGlowFrame:SetAllPoints()
    b.mGlowFrame:SetFrameLevel(b:GetFrameLevel())
    b.mGlow = b.mGlowFrame:CreateTexture(nil, "BACKGROUND", nil, -7)
    b.mGlow:SetTexture(MEDIA .. "Glow")
    b.mGlow:SetBlendMode("ADD")
    b.mGlow:SetSize((SIZE + 4) / CORE, (SIZE + 4) / CORE)
    b.mGlow:SetPoint("CENTER")
    b.mGlowFrame:SetAlpha(0)
    local ag = b.mGlowFrame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(0.25)
    anim:SetToAlpha(1)
    anim:SetDuration(1.1)
    anim:SetSmoothing("IN_OUT")
    b.mBreath, b.mBreathAnim = ag, anim
end

local function StyleFont(fs, size, minimal)
    if minimal then
        fs:SetFont(STANDARD_TEXT_FONT, size, "")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    else
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        fs:SetShadowOffset(0, 0)
    end
end

-- Aplica el estilo elegido (classic / minimal / round) a los iconos y a la grilla
function Display:ApplyStyle()
    if not self.buttons then return end
    if self.picker and self.picker:IsShown() and not InCombatLockdown() then
        self.applyGridStyle = true -- la grilla abierta se re-estiliza abajo
    end
    for _, b in pairs(self.buttons) do self:StyleButton(b) end
    for _, b in ipairs(self.previewButtons or {}) do self:StyleButton(b) end
    self:UpdateSecure()
end

-- Diseño elegido (pestaña Diseño)
function Display:Layout()
    local cdb = ns.cdb
    return {
        k = (cdb.iconSize or SIZE) / SIZE,
        gap = cdb.iconGap or GAP,
        vertical = cdb.vertical and true or false,
    }
end

-- Coloca una lista de íconos en su ancla según tamaño, espacio y orientación
function Display:PlaceIcons(anchor, list)
    local lay = self:Layout()
    local size = SIZE * lay.k
    local pos = 0
    for _, b in ipairs(list) do
        b:SetScale(lay.k)
        b:ClearAllPoints()
        -- desplazamientos en la escala del botón
        if lay.vertical then
            b:SetPoint("TOP", anchor, "TOP", 0, -pos / lay.k)
        else
            b:SetPoint("LEFT", anchor, "LEFT", pos / lay.k, 0)
        end
        pos = pos + size + lay.gap
    end
    local len = max(size, pos - lay.gap)
    if lay.vertical then anchor:SetSize(size, len) else anchor:SetSize(len, size) end
end

function Display:StyleButton(b)
    local minimal = Modern()
    local shape = SHAPES[ns.cdb.iconStyle] or SHAPES.minimal
    local round = ns.cdb.iconStyle == "round"
    local vertical = ns.cdb.vertical
    do
        if minimal then
            b.mShadow:SetTexture(MEDIA .. shape.shadow)
            b.mMask:SetTexture(MEDIA .. shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            b.mBorder:SetTexture(MEDIA .. shape.border)
            b.mGlow:SetTexture(MEDIA .. shape.glow)
        end
        b.border:SetShown(not minimal)
        b.mShadow:SetShown(minimal)
        b.mDecor:SetShown(minimal)
        b.mGlowFrame:SetShown(minimal)
        b.icon:ClearAllPoints()
        if minimal then
            -- hacia adentro: el arte queda dentro de la línea del borde (el círculo necesita más)
            local inset = round and 2 or 1
            b.icon:SetPoint("TOPLEFT", inset, -inset)
            b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        else
            b.icon:SetAllPoints()
        end
        b.mCountBg:Hide(); b.mBonusBg:Hide(); b.mLostBg:Hide() -- sin fondo detrás de los números
        if not minimal then
            b.lost:SetTextColor(1, 0.3, 0.3)
        else
            b.lost:SetTextColor(1, 0.5, 0.5) -- rojo menos saturado: dato, no error
        end
        if minimal then
            if not b.mMasked then b.icon:AddMaskTexture(b.mMask); b.mMasked = true end
            b:SetHighlightTexture(MEDIA .. shape.mask, "ADD")
            local hl = b:GetHighlightTexture()
            if hl then hl:SetVertexColor(1, 1, 1, 0.12) end
            -- el brillo cuadrado clásico no se usa
            if b.pulse:IsPlaying() then b.pulse:Stop() end
            b.glowFrame:SetAlpha(0)
        else
            if b.mMasked then b.icon:RemoveMaskTexture(b.mMask); b.mMasked = false end
            b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
            if b.mBreath:IsPlaying() then b.mBreath:Stop() end
            b.mGlowFrame:SetAlpha(0)
        end
        -- tamaño de textos elegido en Diseño (100% = el del estilo)
        local k = (ns.cdb.textScale or 100) / 100
        local function sz(n) return math.max(6, math.floor(n * k + 0.5)) end
        StyleFont(b.timer, sz(minimal and 11 or 12), minimal)
        StyleFont(b.count, sz(minimal and 10 or 12), minimal)
        StyleFont(b.bonus, sz((round and 10) or (minimal and 9) or 10), minimal)
        StyleFont(b.lost, sz(10), minimal)
        -- en minimal, los textos de esquina quedan más pegados al borde redondeado
        b.count:ClearAllPoints()
        b.bonus:ClearAllPoints()
        if round then
            -- cantidad pegada al borde del círculo; "+5%" arriba, donde va el "-N" (nunca coinciden)
            b.count:SetPoint("BOTTOMRIGHT", 3, 0)
            if vertical then b.bonus:SetPoint("RIGHT", b, "LEFT", -4, 0) else b.bonus:SetPoint("BOTTOM", b, "TOP", 0, 3) end
        elseif minimal then
            b.count:SetPoint("BOTTOMRIGHT", -3, 3)
            b.bonus:SetPoint("TOPLEFT", 3, -3)
        else
            b.count:SetPoint("BOTTOMRIGHT", -2, 2)
            b.bonus:SetPoint("TOPLEFT", 2, -2)
        end
        -- en vertical, timer a la derecha y "-N" a la izquierda (abajo/arriba chocan con el vecino)
        b.timer:ClearAllPoints()
        b.lost:ClearAllPoints()
        if vertical then
            b.timer:SetPoint("LEFT", b, "RIGHT", 4, 0)
            b.lost:SetPoint("RIGHT", b, "LEFT", -4, 0)
        else
            b.timer:SetPoint("TOP", b, "BOTTOM", 0, -3)
            b.lost:SetPoint("BOTTOM", b, "TOP", 0, 3)
        end
    end
end

-- Estado visual del estilo minimal (borde, halo, opacidad)
function Display:UpdateMinimal(b, c, s, now)
    local phase = s.phase
    local flashing = b.flashUntil and now < b.flashUntil
    -- borde
    if phase == "expiring" and ns.cdb.warnSec > 0 then
        local f = max(0, min(1, s.remaining / ns.cdb.warnSec))
        b.mBorder:SetVertexColor(1, 0.25 + 0.35 * f, 0.1, 0.95)
    elseif phase == "missing_have" or flashing then
        b.mBorder:SetVertexColor(1, 0.82, 0.25, 0.95)
    elseif phase == "active" then
        b.mBorder:SetVertexColor(1, 1, 1, ns.cdb.iconStyle == "round" and 0.35 or 0.18)
    else
        b.mBorder:SetVertexColor(1, 1, 1, 0)
    end
    -- halo que respira: falta con ítem (dorado) o últimos 30 s (naranja)
    local glowColor
    if phase == "missing_have" or flashing then glowColor = { 1, 0.75, 0.2 }
    elseif phase == "expiring" and s.remaining <= 30 then glowColor = { 1, 0.45, 0.1 } end
    if glowColor then
        b.mGlow:SetVertexColor(glowColor[1], glowColor[2], glowColor[3])
        local dur = (flashing or phase == "expiring") and 0.5 or 1.1
        if b.mBreathDur ~= dur then b.mBreathAnim:SetDuration(dur); b.mBreathDur = dur end
        if not b.mBreath:IsPlaying() then b.mGlowFrame:SetAlpha(1); b.mBreath:Play() end
    elseif b.mBreath:IsPlaying() then
        b.mBreath:Stop()
        b.mGlowFrame:SetAlpha(0)
    end
    -- sin buff: gris (con ítem lo distingue el borde/halo dorado); sin ítem además translúcido
    local ia = (ns.cdb.inactiveAlpha or 40) / 100
    local alpha = (phase == "missing_none" and ia) or (phase == "unconfigured" and ia * 0.75) or 1
    b.icon:SetAlpha(alpha)
    b.mShadow:SetAlpha(alpha)
    b.icon:SetDesaturated(not s.active)

end

-- Grillas (comida / campamento) -------------------------------------------
local PICK_SIZE, PICK_GAP, PICK_COLS = 36, 4, 5
-- tamaño y columnas elegidos en Diseño (los botones se escalan desde PICK_SIZE)
local function GridSize() return ns.cdb.gridSize or PICK_SIZE end
local function GridCols() return ns.cdb.gridCols or PICK_COLS end

-- Los botones seguros actúan en "down" o "up" según el CVar del cliente
local function ActsNow(down)
    return (down and true or false) == (GetCVarBool("ActionButtonUseKeyDown") and true or false)
end

-- Panel redondeado de 9 piezas (Media/Panel.tga): las esquinas no se deforman al estirarlo
local PANEL_C = 10 -- tamaño en pantalla de cada esquina
local function NineSlice(f)
    if f.nine then return f.nine end
    local n = {}
    local function piece(l, r, t, b)
        local x = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        x:SetTexture(MEDIA .. "Panel")
        x:SetTexCoord(l, r, t, b)
        table.insert(n, x)
        return x
    end
    local C = PANEL_C
    local tl = piece(0, .25, 0, .25);  tl:SetSize(C, C); tl:SetPoint("TOPLEFT")
    local tr = piece(.75, 1, 0, .25);  tr:SetSize(C, C); tr:SetPoint("TOPRIGHT")
    local bl = piece(0, .25, .75, 1);  bl:SetSize(C, C); bl:SetPoint("BOTTOMLEFT")
    local br = piece(.75, 1, .75, 1);  br:SetSize(C, C); br:SetPoint("BOTTOMRIGHT")
    local t = piece(.25, .75, 0, .25); t:SetPoint("TOPLEFT", tl, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bo = piece(.25, .75, .75, 1); bo:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bo:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local l = piece(0, .25, .25, .75); l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local r = piece(.75, 1, .25, .75); r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local c = piece(.25, .75, .25, .75); c:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); c:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    f.nine = n
    return n
end

-- Fondo de paneles según el estilo:
--   classic > marco de tooltip; minimal > panel redondeado; round > transparente
--   (allowTransparent=false: la confirmación siempre lleva fondo para leerse)
local function StylePanel(f, allowTransparent)
    local style = ns.cdb.iconStyle
    local nine = NineSlice(f)
    local showNine = false
    if style == "classic" then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
        f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    else
        f:SetBackdrop(nil)
        showNine = not (style == "round" and allowTransparent)
    end
    for _, x in ipairs(nine) do x:SetShown(showNine) end
end
local function MakeBackdrop(f) StylePanel(f, false) end

-- Botón de la grilla con el estilo actual; r,g,bl = color del borde (verde XP, dorado kit, tenue resto)
local StylePickButton
StylePickButton = function(b, r, g, bl, strong)
    local modern = Modern()
    local shape = SHAPES[ns.cdb.iconStyle] or SHAPES.minimal
    local round = ns.cdb.iconStyle == "round"
    b.border:SetShown(not modern)
    b.mShadow:SetShown(modern)
    b.mBorder:SetShown(modern)
    b.icon:ClearAllPoints()
    if modern then
        local inset = round and 2 or 1
        b.icon:SetPoint("TOPLEFT", inset, -inset)
        b.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
        b.mShadow:SetTexture(MEDIA .. shape.shadow)
        b.mMask:SetTexture(MEDIA .. shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        b.mBorder:SetTexture(MEDIA .. shape.border)
        b.mBorder:SetVertexColor(r, g, bl, strong and 0.95 or 0.25)
        if not b.mMasked then b.icon:AddMaskTexture(b.mMask); b.mMasked = true end
        b:SetHighlightTexture(MEDIA .. shape.mask, "ADD")
        local hl = b:GetHighlightTexture()
        if hl then hl:SetVertexColor(1, 1, 1, 0.15) end
    else
        b.icon:SetAllPoints()
        if b.mMasked then b.icon:RemoveMaskTexture(b.mMask); b.mMasked = false end
        b.border:SetColorTexture(r, g, bl, 1)
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    end
    -- tamaño y visibilidad de los textos de la grilla (pestaña Diseño)
    local k = (ns.cdb.gridTextScale or 100) / 100
    local function sz(n) return math.max(6, math.floor(n * k + 0.5)) end
    StyleFont(b.count, sz(modern and 10 or 11), modern)
    StyleFont(b.badge, sz(modern and 9 or 10), modern)
    b.count:SetShown(ns.cdb.gridShowCount ~= false)
    b.badge:SetShown(ns.cdb.gridShowBadge ~= false)
    b.count:ClearAllPoints()
    b.badge:ClearAllPoints()
    if round then
        b.count:SetPoint("BOTTOMRIGHT", 3, 0)
        b.badge:SetPoint("TOPLEFT", -2, 1)
    elseif modern then
        b.count:SetPoint("BOTTOMRIGHT", -3, 3)
        b.badge:SetPoint("TOPLEFT", 3, -3)
    else
        b.count:SetPoint("BOTTOMRIGHT", -2, 2)
        b.badge:SetPoint("TOPLEFT", 2, -2)
    end
end

-- re-estiliza la grilla si estaba abierta al cambiar el estilo
local origApply = Display.ApplyStyle
function Display:ApplyStyle()
    origApply(self)
    if self.applyGridStyle then
        self.applyGridStyle = nil
        StylePanel(self.picker, true)
        if self.confirm then StylePanel(self.confirm, false) end
        self:BuildPicker(true)
    end
end


Display.StylePickButton = function(...) return StylePickButton(...) end
Display.GridSize = function() return ns.cdb.gridSize or PICK_SIZE end
Display.PICK_SIZE, Display.PICK_GAP = PICK_SIZE, PICK_GAP

function Display:CreateFoodPicker()
    local p = CreateFrame("Frame", "CampXPFoodPicker", UIParent, "BackdropTemplate")
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    MakeBackdrop(p)
    p:Hide()
    tinsert(UISpecialFrames, "CampXPFoodPicker") -- Esc cierra
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", 8, -7)
    p.empty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.empty:SetPoint("TOPLEFT", 8, -24)
    p.buttons = {}
    self.picker = p

    -- clic fuera de la grilla: cerrar
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function()
        if not p:IsShown() or InCombatLockdown() then return end
        if p:IsMouseOver() then return end
        -- clic sobre un icono del addon: su propio clic abre/alterna la grilla
        for _, btn in pairs(Display.buttons or {}) do
            if btn:IsShown() and btn:IsMouseOver() then return end
        end
        if Display.confirm and Display.confirm:IsShown() and Display.confirm:IsMouseOver() then return end
        -- menú del clic derecho abierto: ese clic es para el menú
        if Display.menu and Display.menu:IsShown() then return end
        Display:HideFoodPicker()
    end)
    p:SetScript("OnShow", function()
        if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid("GLOBAL_MOUSE_DOWN") then
            watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end
    end)
    p:SetScript("OnHide", function() watcher:UnregisterAllEvents() end)

    -- Confirmación para comida sin XP: "Comer igual" es un botón seguro
    local d = CreateFrame("Frame", "CampXPFoodConfirm", UIParent, "BackdropTemplate")
    d:SetSize(280, 110)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetPoint("CENTER", 0, 120)
    MakeBackdrop(d)
    d:Hide()
    tinsert(UISpecialFrames, "CampXPFoodConfirm")
    d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    d.text:SetPoint("TOP", 0, -14)
    d.text:SetWidth(250)

    d.yes = CreateFrame("Button", "CampXPFoodConfirmYes", d, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    d.yes:SetSize(110, 22)
    d.yes:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -4, 32)
    d.yes:SetText(L["Eat anyway"])
    d.yes:RegisterForClicks("AnyUp", "AnyDown")
    d.yes:SetAttribute("type", "item")
    d.yes:SetScript("PreClick", function(self, _, down)
        if ActsNow(down) and self.itemId then ns.NoteItemUse(self.itemId) end
    end)
    d.yes:SetScript("PostClick", function(_, _, down)
        if not ActsNow(down) then return end
        d:Hide()
        p:Hide()
    end)

    d.no = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    d.no:SetSize(110, 22)
    d.no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 4, 32)
    d.no:SetText(L["No"])
    d.no:SetScript("OnClick", function() d:Hide() end)

    d.never = CreateFrame("CheckButton", nil, d, "UICheckButtonTemplate")
    d.never:SetSize(20, 20)
    d.never:SetPoint("BOTTOMLEFT", 14, 8)
    d.never.text = d.never:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.never.text:SetPoint("LEFT", d.never, "RIGHT", 2, 0)
    d.never.text:SetText(L["Don't ask again"])
    d.never:SetScript("OnClick", function(cb)
        ns.cdb.confirmNoXP = not cb:GetChecked()
        if ns.Config then ns.Config:Refresh() end
    end)
    self.confirm = d
end

function Display:ShowFoodConfirm(id, xp)
    local d = self.confirm
    local name = ns.GetItemName(id) or format(L["Item %d"], id)
    if xp == nil then
        d.text:SetText(format(L["Couldn't read the tooltip of\n|cffffd100%s|r.\nEat it anyway?"], name))
    else
        d.text:SetText(format(L["|cffffd100%s|r gives no experience.\nEat it anyway?"], name))
    end
    d.yes:SetAttribute("item", ns.SmallestStackRef(id)) -- fuera de combate: permitido
    d.yes.itemId = id
    d.never:SetChecked(false)
    d:Show()
end

-- Partes visuales de un botón de grilla (también los de la vista previa de Diseño)
function Display:CreatePickVisual(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetPoint("TOPLEFT", -2, 2)
    b.border:SetPoint("BOTTOMRIGHT", 2, -2)
    -- piezas de los estilos modernos
    b.mShadow = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    b.mShadow:SetSize((PICK_SIZE + 6) / CORE, (PICK_SIZE + 6) / CORE)
    b.mShadow:SetPoint("CENTER", 0, -2)
    b.mShadow:SetVertexColor(0, 0, 0, 0.85)
    b.mMask = b:CreateMaskTexture()
    b.mMask:SetAllPoints(b.icon)
    b.mBorder = b:CreateTexture(nil, "OVERLAY", nil, -1)
    b.mBorder:SetAllPoints()
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.badge = b:CreateFontString(nil, "OVERLAY")
    b.badge:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    b.badge:SetPoint("TOPLEFT", 2, -2)
    b.badge:SetJustifyH("LEFT") -- varias líneas (una por estadística)
    -- consumible vigilado (End Game)
    b.check = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.check:SetSize(14, 14)
    b.check:SetPoint("TOPRIGHT", 3, 3)
    b.check:Hide()
    -- favorito (estrella abajo a la izquierda)
    b.fav = b:CreateTexture(nil, "OVERLAY", nil, 3)
    b.fav:SetTexture("Interface\\Common\\FavoritesIcon")
    b.fav:SetSize(20, 20)
    b.fav:SetPoint("BOTTOMLEFT", -5, -5)
    b.fav:Hide()
end

-- Botón de grilla de muestra (no seguro) para la vista previa
function Display:CreatePreviewPick(parent, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(PICK_SIZE, PICK_SIZE)
    self:CreatePickVisual(b)
    b.icon:SetTexture(icon)
    return b
end

function Display:GetPickButton(i)
    local p = self.picker
    local b = p.buttons[i]
    if b then return b end
    b = CreateFrame("Button", "CampXPFoodPick" .. i, p, "SecureActionButtonTemplate")
    b:SetSize(PICK_SIZE, PICK_SIZE)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    Display:CreatePickVisual(b)

    -- entrada animada (round): aparece desplazado y se desliza a su lugar con un fundido
    local intro = b:CreateAnimationGroup()
    local jump = intro:CreateAnimation("Translation")
    jump:SetDuration(0); jump:SetOrder(1)
    local slide = intro:CreateAnimation("Translation")
    slide:SetDuration(0.18); slide:SetOrder(2); slide:SetSmoothing("OUT")
    local fade = intro:CreateAnimation("Alpha")
    fade:SetFromAlpha(0); fade:SetToAlpha(1); fade:SetDuration(0.18); fade:SetOrder(2)
    intro:SetToFinalAlpha(true)
    intro:SetScript("OnFinished", function() b:SetAlpha(1) end)
    b.intro, b.introJump, b.introSlide = intro, jump, slide

    -- salida animada (round): vuelve hacia los iconos desvaneciéndose
    local outro = b:CreateAnimationGroup()
    local back = outro:CreateAnimation("Translation")
    back:SetDuration(0.14); back:SetSmoothing("IN")
    local out = outro:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.14)
    outro:SetToFinalAlpha(true)
    b.outro, b.outroBack = outro, back

    -- Comida sin XP: bloquea el uso y pide confirmación (el campamento se usa directo)
    b:SetScript("PreClick", function(self, button, down)
        if InCombatLockdown() or not ActsNow(down) then return end
        if self.mode == "consumables" then
            self.blocked = nil
            if button ~= "RightButton" then
                -- piedra/aceite con dos armas: a la mano que no la tiene (Shift = secundaria, Ctrl = principal)
                if self.isWeapon then
                    self:SetAttribute("target-slot", ns:PickWeaponSlot(self.itemId))
                    local dual = ns.HasOffhandWeapon()
                    self:SetAttribute("shift-target-slot1", dual and 17 or nil)
                    self:SetAttribute("ctrl-target-slot1", dual and 16 or nil)
                end
                ns:NoteConsumableUse(self.itemId)
            end
        elseif self.mode ~= "food" or button == "RightButton" then
            self.blocked = nil
        elseif self.xp ~= true and ns.cdb.confirmNoXP and not ns:IsEndgame() then
            self:SetAttribute("type", nil)
            self.blocked = true
            Display:ShowFoodConfirm(self.itemId, self.xp)
        else
            self.blocked = nil
            if self.xp then ns.cdb.foodChoice = self.itemId end
            ns.NoteItemUse(self.itemId) -- evidencia de qué comida aplicará el Well Fed
        end
    end)
    b:SetScript("PostClick", function(self, button, down)
        if InCombatLockdown() or not ActsNow(down) then return end
        if self.mode == "consumables" then
            -- clic derecho: menú (vigilar + avisos); la grilla queda abierta para poner varios
            if button == "RightButton" then Display:ShowConsumableMenu(self, self.itemId) end
            return
        end
        if self.mode == "food" and button == "RightButton" then
            Display:ShowFoodMenu(self, self.itemId)
            return
        end
        if self.blocked then
            self:SetAttribute("type", "item")
            self.blocked = nil
        else
            Display:HideFoodPicker()
        end
    end)
    b:SetScript("OnEnter", function(self)
        -- posición estándar de tooltips del juego (Edit Mode)
        if GameTooltip_SetDefaultAnchor then
            GameTooltip_SetDefaultAnchor(GameTooltip, self)
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        end
        if self.isToy and GameTooltip.SetToyByItemID then
            GameTooltip:SetToyByItemID(self.itemId)
        else
            GameTooltip:SetItemByID(self.itemId)
        end
        if self.mode == "consumables" then
            GameTooltip:AddLine(" ")
            local t = ns:TrackedFor(self.itemId)
            if t then
                GameTooltip:AddLine(format(L["CampXP: tracked · buff: %s"], ns:LinkedBuffName(t) or "?")
                    .. (t.items[self.itemId] == "auto" and (" |cff888888" .. L["(auto)"] .. "|r") or ""), 0.3, 1, 0.3)
                if self.ready then GameTooltip:AddLine(L["CampXP: buff ready"], 0.3, 1, 0.3) end
            else
                local _, _, spellName = ns:ConsumableKey(self.itemId)
                if spellName then GameTooltip:AddLine(format(L["CampXP: buff %s"], spellName), 0.6, 0.8, 1) end
            end
            if self.isWeapon and ns.HasOffhandWeapon() then
                local slot = ns:PickWeaponSlot(self.itemId)
                GameTooltip:AddLine(format(L["Left-click: apply to %s"], slot == 17 and L["off-hand"] or L["main hand"]), 0.6, 0.8, 1)
                GameTooltip:AddLine(L["Shift-click: off-hand · Ctrl-click: main hand"], 0.6, 0.8, 1)
            else
                GameTooltip:AddLine(L["Left-click: use"], 0.6, 0.8, 1)
            end
            GameTooltip:AddLine(L["Right-click: track and alerts"], 0.6, 0.8, 1)
            GameTooltip:Show()
            return
        end
        if self.mode ~= "food" then GameTooltip:Show() return end
        GameTooltip:AddLine(" ")
        if ns:IsEndgame() then
            if self.stat then
                GameTooltip:AddLine(format(L["CampXP: Well Fed %s"], self.stat), 0.3, 1, 0.3)
            elseif self.xp then
                GameTooltip:AddLine(L["CampXP: gives Well Fed"], 0.3, 1, 0.3)
            elseif self.xp == false then
                GameTooltip:AddLine(L["CampXP: no Well Fed"], 1, 0.4, 0.4)
            else
                GameTooltip:AddLine(L["CampXP: loading item data..."], 0.7, 0.7, 0.7)
            end
        elseif self.xp then
            GameTooltip:AddLine(format(L["CampXP: gives +%d%% XP"], self.pct or 5), 0.3, 1, 0.3)
        elseif self.xp == false then
            GameTooltip:AddLine(L["CampXP: gives no experience"], 1, 0.4, 0.4)
        else
            GameTooltip:AddLine(L["CampXP: loading item data..."], 0.7, 0.7, 0.7)
        end
        if ns:IsFavorite(self.itemId) then GameTooltip:AddLine(L["CampXP: favorite"], 1, 0.82, 0) end
        GameTooltip:AddLine(L["Right-click: options"], 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.buttons[i] = b
    return b
end

-- Menú del clic derecho en la grilla de comida (Leveling y End Game)
function Display:ShowFoodMenu(owner, id)
    GameTooltip:Hide()
    local function Rebuild()
        if self.picker:IsShown() and not InCombatLockdown() then self:BuildPicker() end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        ns:ToggleFavorite(id) -- cliente sin menú moderno: el clic derecho solo marca favorito
        Rebuild()
        return
    end
    self.menu = MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.GetItemName(id) or format(L["Item %d"], id))
        -- qué detectó CampXP en esta comida
        local info
        if ns:IsEndgame() then
            local wf, stat = ns:FoodGivesWellFed(id)
            info = stat and format(L["CampXP: Well Fed %s"], stat)
                or (wf and L["CampXP: gives Well Fed"]) or (wf == false and L["CampXP: no Well Fed"]) or L["CampXP: loading item data..."]
        else
            local xp = ns:FoodGivesXP(id)
            info = (xp and L["CampXP: gives XP"]) or (xp == false and L["CampXP: gives no experience"]) or L["CampXP: loading item data..."]
        end
        root:CreateTitle("|cff99ccff" .. info .. "|r")
        root:CreateCheckbox(L["Favorite"], function() return ns:IsFavorite(id) end,
            function() ns:ToggleFavorite(id); Rebuild() end)
        root:CreateDivider()
        root:CreateButton(L["Report a problem..."], function() Display:ShowReport(id) end)
    end)
end

-- Menú del clic derecho en la grilla de consumibles: vigilar y qué avisar
function Display:ShowConsumableMenu(owner, id)
    GameTooltip:Hide()
    local function Rebuild()
        if self.picker:IsShown() and not InCombatLockdown() then self:BuildPicker() end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- cliente sin el menú moderno: el clic derecho solo vigila/deja de vigilar
        ns:ToggleTrack(id)
        Rebuild()
        return
    end
    self.menu = MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.GetItemName(id) or format(L["Item %d"], id))
        root:CreateCheckbox(L["Favorite"], function() return ns:IsFavorite(id) end,
            function() ns:ToggleFavorite(id); Rebuild() end)
        root:CreateCheckbox(L["Track this buff"],
            function() return ns:TrackedFor(id) ~= nil end,
            function() ns:ToggleTrack(id); Rebuild() end)
        local t = ns:TrackedFor(id)
        if t then
            -- buff vinculado: automático (efecto "Usar" del ítem / visto al usarlo) o manual
            local buff = ns:LinkedBuffName(t) or "?"
            local state = t.manual and L["manual"] or (t.exact and L["exact"]) or (t.seen and L["confirmed"] or L["not seen yet"])
            root:CreateTitle(format(L["Buff: %s (%s)"], buff, state))
            if not t.weapon then
                local sub = root:CreateButton(L["Link to an active buff"])
                local auras = ns:LinkableAuras()
                if #auras == 0 then
                    sub:CreateTitle(L["You have no buffs active"])
                end
                for _, e in ipairs(auras) do
                    local spellId, a = e.spellId, e.aura
                    sub:CreateButton(format("|T%s:14|t %s", a.icon or 134400, a.name), function()
                        ns:LinkTrackedToAura(id, spellId, a)
                    end)
                end
                if t.manual or t.seen then
                    root:CreateButton(L["Reset buff link"], function() ns:ClearTrackedLink(id) end)
                end
            else
                -- piedra/aceite: elegir cuál de los encantamientos del arma es el suyo
                local sub = root:CreateButton(L["Link to a weapon enchant"])
                local list = ns.WeaponEnchants()
                if #list == 0 then sub:CreateTitle(L["Your weapon has no temporary enchant"]) end
                for _, e in ipairs(list) do
                    sub:CreateButton(format("%s · %s (%s)", e.text or ("ID " .. tostring(e.enchant)), ns.FormatTime(e.rem), e.slot), function()
                        ns:LinkWeaponEnchant(id, e)
                    end)
                end
            end
            root:CreateDivider()
            root:CreateTitle(L["Alert when:"])
            for _, k in ipairs(ns.CONS_ALERTS) do
                local kind = k.key
                root:CreateCheckbox(k.label,
                    function() local tt = ns:TrackedFor(id) return tt ~= nil and ns:ConsAlertOn(tt, kind) end,
                    function()
                        local tt = ns:TrackedFor(id)
                        if tt then ns:SetConsAlert(tt, kind, not ns:ConsAlertOn(tt, kind)) end
                    end)
            end
        end
        root:CreateDivider()
        root:CreateButton(L["Report a problem..."], function() Display:ShowReport(id) end)
    end)
end

-- Ventana "Reportar un problema": link a CurseForge + mensaje sugerido para copiar.
-- Los addons no pueden escribir en el portapapeles: se deja el texto seleccionado
-- en un campo para que el usuario lo copie con Ctrl+C.
local function ReadOnlyBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(self.fixed or ""); self:HighlightText() end end)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); parent:Hide() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    function e:SetFixed(text) self.fixed = text; self:SetText(text); self:SetCursorPosition(0) end
    return e
end

function Display:ShowReport(id)
    local d = self.report
    if not d then
        d = CreateFrame("Frame", "CampXPReport", UIParent, "BackdropTemplate")
        d:SetSize(400, 196)
        d:SetPoint("CENTER", 0, 120)
        d:SetFrameStrata("FULLSCREEN_DIALOG")
        d:EnableMouse(true)
        d:SetMovable(true)
        d:RegisterForDrag("LeftButton")
        d:SetScript("OnDragStart", d.StartMoving)
        d:SetScript("OnDragStop", d.StopMovingOrSizing)
        MakeBackdrop(d)
        tinsert(UISpecialFrames, "CampXPReport")
        d.title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        d.title:SetPoint("TOP", 0, -14)
        d.title:SetText(L["Report a problem"])
        local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)

        d.step1 = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        d.step1:SetPoint("TOPLEFT", 18, -44)
        d.step1:SetText(L["1. Copy the link (Ctrl+C) and open it in your browser:"])
        d.url = ReadOnlyBox(d, 360)
        d.url:SetPoint("TOPLEFT", 24, -60)

        d.step2 = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        d.step2:SetPoint("TOPLEFT", 18, -92)
        d.step2:SetText(L["2. Copy the suggested message and paste it in a comment:"])
        d.btn = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        d.btn:SetSize(180, 22)
        d.btn:SetPoint("TOPLEFT", 18, -108)
        d.btn:SetText(L["Suggested message"])
        d.msg = ReadOnlyBox(d, 360)
        d.msg:SetPoint("TOPLEFT", 24, -138)
        d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        d.hint:SetPoint("TOPLEFT", 18, -164)
        d.hint:SetWidth(364)
        d.hint:SetJustifyH("LEFT")
        d.btn:SetScript("OnClick", function()
            d.msg:Show()
            d.msg:SetFixed(ns:BugReportText(d.itemId))
            d.msg:SetFocus()
            d.msg:HighlightText()
            d.hint:SetText(L["Selected: press Ctrl+C to copy it. Add what went wrong at the end."])
        end)
        self.report = d
    end
    StylePanel(d, false)
    d.itemId = id
    d.url:SetFixed(ns.REPORT_URL)
    d.msg:SetFixed("")
    d.msg:Hide()
    d.hint:SetText("")
    d:Show()
    d.url:SetFocus()
    d.url:HighlightText()
end

-- Desplazamiento "hacia los iconos" según dónde se abre la grilla
local function TowardIcons()
    local side = ns.cdb.pickerSide or "right"
    if side == "right" then return -14, 0
    elseif side == "left" then return 14, 0
    elseif side == "top" then return 0, -14 end
    return 0, 14
end

function Display:BuildPicker(animate)
    if InCombatLockdown() then return end
    local p = self.picker
    local mode = p.mode or "food"
    local round = ns.cdb.iconStyle == "round"
    -- round: sin título (grilla transparente); los ítems empiezan más arriba
    p.title:SetShown(not round)
    local top = round and 6 or 24
    local list
    if mode == "food" then list = ns:GetBagFoods()
    elseif mode == "consumables" then list = ns:GetBagConsumables()
    else list = ns:GetBagCampItems() end
    for _, b in ipairs(p.buttons) do b:Hide() end

    local TITLES = { food = L["Choose a food"], camp = L["Choose a camp item"],
                     consumables = L["Consumables (right-click: track)"] }
    local EMPTY = { food = L["You have no food in your bags."],
                    camp = L["You have no campfire kits or camp items in your bags."],
                    consumables = L["You have no consumables with a buff in your bags."] }
    p.title:SetText(TITLES[mode])
    p.empty:SetText(EMPTY[mode])

    for i, f in ipairs(list) do
        local b = self:GetPickButton(i)
        b.mode, b.itemId, b.blocked, b.isToy = mode, f.id, nil, f.toy
        b.tracked, b.stat, b.ready = f.tracked, f.stat, f.ready
        -- check verde = el buff de su grupo ya está puesto (por este ítem u otro que lo reemplaza)
        b.check:SetShown(f.ready == true and ns.cdb.gridShowCheck ~= false)
        -- clic derecho solo vigila en la grilla de consumibles; aceites/piedras van al arma
        -- clic derecho = menú en comida y consumibles (no usa el ítem)
        b:SetAttribute("type2", (mode == "consumables" or mode == "food") and "none" or nil)
        b.fav:SetShown((mode == "consumables" or mode == "food") and ns:IsFavorite(f.id))
        b.isWeapon = mode == "consumables" and f.weapon or nil
        b:SetAttribute("target-slot", b.isWeapon and ns:PickWeaponSlot(f.id) or nil)
        if not b.isWeapon then
            b:SetAttribute("shift-target-slot1", nil)
            b:SetAttribute("ctrl-target-slot1", nil)
        end
        if f.toy then
            -- juguete de la Toy Box: se usa como juguete, no como ítem de bolsa
            b:SetAttribute("type", "toy")
            b:SetAttribute("toy", f.id)
            b:SetAttribute("item", nil)
        else
            b:SetAttribute("type", "item")
            b:SetAttribute("toy", nil)
            b:SetAttribute("item", ns.SmallestStackRef(f.id)) -- consume primero el stack más chico
        end
        b.icon:SetTexture(ns.GetItemIcon(f.id))
        b.count:SetText((not f.toy and f.count > 1) and f.count or "")
        if mode == "food" then
            local _, pct = ns:FoodGivesXP(f.id)
            b.xp, b.pct = f.xp, pct
            if f.xp then
                if ns:IsEndgame() and f.statKeys and #f.statKeys > 0 then
                    -- una línea por estadística con su color (Clamlette Surprise: "Sta" y debajo "Spi")
                    b.badge:SetText(ns:StatBadge(f.statKeys))
                    b.badge:SetTextColor(1, 1, 1)
                else
                    b.badge:SetText(ns:IsEndgame() and "WF" or "XP")
                    b.badge:SetTextColor(0.3, 1, 0.3)
                end
                StylePickButton(b, 0.2, 0.9, 0.3, true)
                b.icon:SetDesaturated(false)
            else
                b.badge:SetText("")
                StylePickButton(b, 0.3, 0.3, 0.3, false)
                if Modern() then b.mBorder:SetVertexColor(1, 1, 1, 0.2) end
                b.icon:SetDesaturated(f.xp == false)
            end
        elseif mode == "consumables" then
            b.xp, b.pct = nil, nil
            b.badge:SetText("")
            b.icon:SetDesaturated(false)
            if f.tracked then
                StylePickButton(b, 0.3, 0.75, 1, true) -- vigilado: borde azul
            else
                StylePickButton(b, 0.3, 0.3, 0.3, false)
                if Modern() then b.mBorder:SetVertexColor(1, 1, 1, 0.2) end
            end
        else
            -- kits de fogata con borde dorado, el resto gris
            b.xp, b.pct = nil, nil
            b.badge:SetText("")
            b.icon:SetDesaturated(false)
            if f.kit then StylePickButton(b, 0.95, 0.75, 0.25, true)
            elseif f.toy then
                -- juguete: borde violeta; gris si está en cooldown
                StylePickButton(b, 0.7, 0.45, 1, true)
                b.icon:SetDesaturated(not ns:CampToyReady())
            else
                StylePickButton(b, 0.3, 0.3, 0.3, false)
                if Modern() then b.mBorder:SetVertexColor(1, 1, 1, 0.2) end
            end
        end
        local gs, gc = GridSize(), GridCols()
        local col, row = (i - 1) % gc, math.floor((i - 1) / gc)
        local gk = gs / PICK_SIZE
        b:SetScale(gk)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", p, "TOPLEFT", (8 + col * (gs + PICK_GAP)) / gk, (-top - row * (gs + PICK_GAP)) / gk)
        b:Show()
        if b.intro:IsPlaying() then b.intro:Stop() end
        b:SetAlpha(1)
        if animate and round and ns.cdb.gridAnim ~= false then
            -- sale desde el lado de los iconos, uno tras otro
            local dx, dy = TowardIcons()
            b.introJump:SetOffset(dx, dy)
            b.introSlide:SetOffset(-dx, -dy)
            b:SetAlpha(0)
            local btn = b
            C_Timer.After((i - 1) * 0.035, function()
                if btn:IsShown() then btn.intro:Play() end
            end)
        end
    end

    local n = #list
    -- comida con tooltip aún sin cargar: reconstruir en un momento
    self.pickerPending = (mode == "consumables" and ns.consPending) or false
    if mode == "food" then
        for _, f in ipairs(list) do
            if f.xp == nil then self.pickerPending = true end
        end
    end
    p.empty:SetShown(n == 0)
    p.empty:ClearAllPoints()
    p.empty:SetPoint("TOPLEFT", 8, -top)
    StyleFont(p.empty, 11, round) -- con sombra cuando no hay fondo
    local gs, gc = GridSize(), GridCols()
    local cols = math.max(1, math.min(n, gc))
    local rows = math.max(1, math.ceil(n / gc))
    p:SetSize(math.max(n == 0 and 230 or 150, 16 + cols * (gs + PICK_GAP) - PICK_GAP),
              top + 8 + rows * (gs + PICK_GAP) - PICK_GAP + (n == 0 and 4 or 0))
end
Display.BuildFoodPicker = Display.BuildPicker -- compatibilidad

-- Posición de la grilla respecto de los iconos (configurable)
function Display:AnchorPicker()
    local p, a = self.picker, self.anchor
    local side = ns.cdb.pickerSide or "right"
    p:ClearAllPoints()
    if side == "left" then
        p:SetPoint("RIGHT", a, "LEFT", -10, 0)
    elseif side == "top" then
        p:SetPoint("BOTTOM", a, "TOP", 0, 18)   -- deja espacio al "-N" rojo
    elseif side == "bottom" then
        p:SetPoint("TOP", a, "BOTTOM", 0, -20)  -- deja espacio al texto de tiempo
    else
        p:SetPoint("LEFT", a, "RIGHT", 10, 0)
    end
end

function Display:TogglePicker(mode)
    local p = self.picker
    if not p then return end
    if InCombatLockdown() then
        ns.Print(L["You can't use the grid in combat."])
        return
    end
    if p.closing then
        -- se estaba cerrando: cancelar y reabrir limpio
        p.closing = nil
        for _, b in ipairs(p.buttons) do
            if b.outro:IsPlaying() then b.outro:Stop() end
            b:SetAlpha(1)
        end
        if p.mode == mode then
            p:Hide()
            return
        end
    elseif p:IsShown() and p.mode == mode then
        self:HideFoodPicker()
        return
    end
    p.mode = mode
    StylePanel(p, true)
    if self.confirm then StylePanel(self.confirm, false) end
    self:BuildPicker(true) -- true: animar la entrada (estilo round)
    self:AnchorPicker()
    p:Show()
end


-- Cierra la grilla. En round los ítems vuelven hacia los iconos en orden inverso.
-- immediate=true (p. ej. al entrar en combate): cierra al instante.
function Display:HideFoodPicker(immediate)
    local p = self.picker
    if self.confirm then self.confirm:Hide() end
    if not p or not p:IsShown() then return end
    if InCombatLockdown() then return end

    local visible = {}
    for _, b in ipairs(p.buttons) do
        if b:IsShown() then table.insert(visible, b) end
    end
    if immediate or ns.cdb.iconStyle ~= "round" or ns.cdb.gridAnim == false or #visible == 0 then
        p.closing = nil
        p:Hide()
        return
    end
    if p.closing then return end
    p.closing = true

    local dx, dy = TowardIcons()
    local STEP, DUR = 0.025, 0.14
    for k = #visible, 1, -1 do
        local b = visible[k]
        if b.intro:IsPlaying() then b.intro:Stop() end
        b.outroBack:SetOffset(dx, dy)
        C_Timer.After((#visible - k) * STEP, function()
            if p.closing and b:IsShown() then b.outro:Play() end
        end)
    end
    C_Timer.After((#visible - 1) * STEP + DUR + 0.02, function()
        if not p.closing then return end -- se volvió a abrir mientras cerraba
        p.closing = nil
        if InCombatLockdown() then return end
        p:Hide()
        for _, b in ipairs(p.buttons) do b:SetAlpha(1) end
    end)
end

function Display:Flash(key)
    local b = self.buttons and self.buttons[key]
    if b then b.flashUntil = GetTime() + 3 end
end

-- Atributos seguros: solo fuera de combate
function Display:UpdateSecure()
    if not self.buttons then return end
    if InCombatLockdown() then
        self.secureDirty = true
        return
    end
    self.secureDirty = false

    local shown = {}
    for _, c in ipairs(ns.CATEGORIES) do
        local b, s = self.buttons[c.key], (ns.state and ns.state[c.key]) or {}
        if ns.cdb.enabled[c.key] and not s.locked then
            shown[#shown + 1] = b
            b:Show()
        else
            b:Hide()
        end
        if c.key == "food" or c.key == "campfire" or c.key == "consumables" then
            b:SetAttribute("type", nil) -- comida, campamento y consumibles se eligen en su grilla
            b:SetAttribute("item", nil)
        elseif s.itemId and s.count > 0 then
            b:SetAttribute("type", "item")
            b:SetAttribute("item", ns.SmallestStackRef(s.itemId))
        else
            b:SetAttribute("type", nil)
            b:SetAttribute("item", nil)
        end
    end
    self:PlaceIcons(self.anchor, shown)
end

function Display:Update()
    if not self.buttons then return end
    local now = GetTime()
    if self.pickerPending and self.picker:IsShown() and not InCombatLockdown()
        and now - (self.lastPickerBuild or 0) > 1 then
        self.lastPickerBuild = now
        self:BuildPicker()
    end
    local endgame = ns:IsEndgame()

    for _, c in ipairs(ns.CATEGORIES) do
        self:PaintButton(self.buttons[c.key], c, ns.state[c.key], now)
    end

    if self.secureDirty and not InCombatLockdown() then self:UpdateSecure() end
end

-- Dibuja el estado de un ícono (también los de la vista previa: s.previewLost / s.previewBonus)
function Display:PaintButton(b, c, s, now)
    local endgame = ns:IsEndgame()
    local phase = s.phase
    local col = PHASE_COLOR[phase] or PHASE_COLOR.missing_none
    local minimal = Modern()

    -- en "expira" el borde va de naranjo a rojo
    if minimal then
        -- (el estilo minimal maneja borde/halo/opacidad aparte)
    elseif phase == "expiring" and ns.cdb.warnSec > 0 then
        local f = max(0, min(1, s.remaining / ns.cdb.warnSec))
        b.border:SetColorTexture(1, 0.15 + 0.4 * f, 0.1, 1)
    else
        b.border:SetColorTexture(col[1], col[2], col[3], 1)
    end

    b.icon:SetTexture(s.auraIcon or (s.itemId and ns.GetItemIcon(s.itemId)) or c.icon)
    b.icon:SetDesaturated(not s.active)

    -- "fogata apagándose": el icono se oscurece a medida que se acaba
    if s.active and s.duration and s.duration > 0 and s.expires ~= math.huge then
        local floor = minimal and 0.6 or 0.35
        local v = floor + (1 - floor) * max(0, min(1, s.remaining / s.duration))
        b.icon:SetVertexColor(v, v, v)
    else
        b.icon:SetVertexColor(1, 1, 1)
    end

    if not minimal then
        local alpha = 1
        local ia = (ns.cdb.inactiveAlpha or 40) / 100
        if phase == "missing_none" then alpha = ia
        elseif phase == "unconfigured" then alpha = ia * 0.75 end
        b.icon:SetAlpha(alpha)
        b.border:SetAlpha(alpha)
    end

    if phase == "active" or phase == "expiring" then
        if s.expires == math.huge then
            b.timer:SetText(L["ON"])
        else
            b.timer:SetText(ns.FormatTime(s.remaining))
        end
        if phase == "expiring" then b.timer:SetTextColor(1, 0.5, 0.1) else b.timer:SetTextColor(1, 1, 1) end
    elseif phase == "missing_have" then
        -- en minimal el halo dorado ya dice "actúa aquí"
        b.timer:SetText(minimal and "" or L["Use!"])
        b.timer:SetTextColor(1, 0.85, 0.1)
    elseif phase == "missing_none" then
        b.timer:SetText("-")
        b.timer:SetTextColor(0.6, 0.6, 0.6)
    elseif phase == "unconfigured" then
        b.timer:SetText("?")
        b.timer:SetTextColor(0.6, 0.6, 0.6)
    else
        b.timer:SetText("")
    end

    if c.key == "consumables" then
        -- vigilados activos / total
        b.count:SetText((s.trackedCount or 0) > 0 and (s.activeCount .. "/" .. s.trackedCount) or "")
        if s.active then b.count:SetTextColor(0.3, 1, 0.3) else b.count:SetTextColor(1, 0.85, 0.1) end
    elseif c.perStack and s.active then
        -- saco activo: stacks en vez de cantidad en bolsas
        local st = math.max(1, math.min(s.stacks or 1, c.maxStacks))
        b.count:SetText(st .. "/" .. c.maxStacks)
        if st >= c.maxStacks then b.count:SetTextColor(0.3, 1, 0.3) else b.count:SetTextColor(0.6, 0.85, 1) end
    else
        b.count:SetText((s.count and s.count > 0) and s.count or "")
        b.count:SetTextColor(1, 1, 1)
    end
    local lostXP = s.previewLost or (ns.XPBar and ns.XPBar.levelLostByCat and ns.XPBar.levelLostByCat[c.key]) or 0
    if ns.cdb.showLostBadge and not endgame and not s.active and lostXP >= 1 then
        b.lost:SetText("-" .. ns.FormatNumber(lostXP))
    else
        b.lost:SetText("")
    end
    if endgame then
        -- End Game: la comida muestra la estadística del Well Fed ("+6 Sta/Spi")
        b.bonus:SetText((c.key == "food" and s.active and s.statText) or "")
    else
        local active = s.previewBonus or ns:BonusPct(c.key)
        b.bonus:SetText(active > 0 and ("+" .. active .. "%") or "")
    end

    if minimal then self:UpdateMinimal(b, c, s, now) end

    local flashing = b.flashUntil and now < b.flashUntil
    local shouldPulse = not minimal and (phase == "expiring" or phase == "missing_have" or flashing)
    if shouldPulse then
        local fast = flashing or (phase == "expiring" and s.remaining <= 30)
        local dur = fast and 0.3 or 0.6
        if b.pulseDur ~= dur then
            b.pulseAnim:SetDuration(dur)
            b.pulseDur = dur
        end
        if not b.pulse:IsPlaying() then
            b.glowFrame:SetAlpha(1)
            b.pulse:Play()
        end
        local gc = flashing and PHASE_COLOR.missing_have or col
        b.glow:SetVertexColor(gc[1], gc[2], gc[3])
    elseif b.pulse:IsPlaying() then
        b.pulse:Stop()
        b.glowFrame:SetAlpha(0)
    end
    -- textos que el usuario ocultó en Diseño
    b.timer:SetShown(ns.cdb.showTimer ~= false)
    b.count:SetShown(ns.cdb.showCount ~= false)
    b.bonus:SetShown(ns.cdb.showBonus ~= false)
end

function Display:ShowConsumablesTooltip(s)
    GameTooltip:AddLine(L["Consumables"], 1, 0.82, 0)
    if s.nextLabel and s.remaining and s.remaining > 0 and s.expires ~= math.huge then
        GameTooltip:AddLine(format(L["Timer: %s (%s)"], s.nextLabel, ns.FormatTime(s.remaining)), 0.7, 0.7, 0.7)
    end
    if (s.trackedCount or 0) == 0 then
        GameTooltip:AddLine(L["Nothing tracked yet. Click to open the grid and right-click a consumable to track it."], 0.7, 0.7, 0.7, true)
    else
        for _, r in ipairs(s.list or {}) do
            local txt, cr, cg, cb
            if r.coveredBy then
                -- cubierto por el buff de otro jugador (no se acumulan)
                txt, cr, cg, cb = format(L["by %s"], r.coveredBy), 0.4, 0.8, 1
            elseif r.active then
                txt = (r.remaining == math.huge) and L["active"] or ns.FormatTime(r.remaining)
                if r.expiring then cr, cg, cb = 1, 0.6, 0.1 else cr, cg, cb = 0.3, 1, 0.3 end
            elseif r.outOfStock then
                txt, cr, cg, cb = L["out of stock"], 0.5, 0.5, 0.5
            else
                txt, cr, cg, cb = L["missing"], 1, 0.3, 0.3
            end
            local label = format("%s |cffaaaaaa(%d)|r", r.label, r.count)
            if not r.verified then label = label .. " |cff888888" .. L["(not seen yet)"] .. "|r" end
            GameTooltip:AddDoubleLine(label, txt, 1, 1, 1, cr, cg, cb)
        end
    end
    GameTooltip:AddLine(L["Click: consumables grid · Shift+drag: move"], 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

-- Líneas del tooltip de un ícono, agrupadas por sección (para mostrarlas
-- siempre, solo con Shift o nunca: pestaña Tooltip). s puede ser un estado de
-- ejemplo (vista previa) con sampleItems / sampleLost / sampleLostLevel.
-- Cada línea: { sec, left, right, r,g,b, r2,g2,b2, wrap }
ns.TOOLTIP_SECTIONS = {
    { key = "time",      label = "Buff and time left",     default = "always" },
    { key = "stacks",    label = "Stacks",                 default = "always", only = { sleepingbag = true } },
    { key = "bonus",     label = "XP bonus / food stat",   default = "always" },
    { key = "items",     label = "Items in bags",          default = "always" },
    { key = "lost",      label = "XP lost (session)",      default = "always" },
    { key = "lostLevel", label = "XP lost (this level)",   default = "shift" },
    { key = "detect",    label = "Detection details",      default = "off", only = { food = true } },
    { key = "hint",      label = "Click help",             default = "always" },
}

-- Configuración por ícono: cdb.tooltip[categoría][sección]
function ns:TooltipMode(sec, cat)
    local all = self.cdb.tooltip or {}
    local t = cat and all[cat]
    if type(t) == "table" and t[sec] then return t[sec] end
    for _, d in ipairs(ns.TOOLTIP_SECTIONS) do if d.key == sec then return d.default end end
    return "always"
end

function ns:BuildIconTooltip(c, s)
    local lines = {}
    local function add(sec, left, right, r, g, b, r2, g2, b2, wrap)
        lines[#lines + 1] = { sec = sec, left = left, right = right, r = r, g = g, b = b, r2 = r2, g2 = g2, b2 = b2, wrap = wrap }
    end
    local endgame = ns:IsEndgame()
    -- tiempo
    if s.active then
        local t = (s.expires == math.huge) and L["active"] or ns.FormatTime(s.remaining or 0)
        add("time", s.auraName or "Buff", t, 1, 1, 1, 0.3, 1, 0.3)
    elseif s.phase ~= "unconfigured" then
        add("time", L["No buff"], nil, 1, 0.3, 0.3)
    end
    -- bonus / estadística
    if endgame then
        if c.key == "food" and s.statText then add("bonus", s.statText, nil, 0.6, 0.8, 1) end
    else
        local kill, quest = ns:XPBonus(c.key, false)
        local pKill, pQuest = ns:XPBonus(c.key, true)
        if pKill <= 0 and pQuest <= 0 then
            add("bonus", L["No XP bonus"], nil, 0.6, 0.6, 0.6)
        else
            local k, q = kill, quest
            if not s.active then k, q = pKill, pQuest end
            add("bonus", s.active and L["Bonus on kills"] or L["Would give on kills"], "+" .. k .. "%", 0.6, 0.8, 1, 0.6, 0.8, 1)
            if q > 0 or (c.key ~= "food" and pQuest > 0) then
                add("bonus", s.active and L["Bonus on quests/other"] or L["Would give on quests/other"], "+" .. q .. "%", 0.6, 0.8, 1, 0.6, 0.8, 1)
            end
        end
    end
    -- stacks (saco)
    if c.perStack and s.active and not endgame then
        local st = math.max(1, math.min(s.stacks or 1, c.maxStacks))
        add("stacks", format(L["%d/%d stacks"], st, c.maxStacks), nil, 0.6, 0.8, 1)
        if st < c.maxStacks then
            local pKill = ns:XPBonus(c.key, true)
            add("stacks", format(L["Sleep %d more min on the bag for +%d%% on kills"], c.maxStacks - st, pKill), nil, 0.8, 0.8, 0.5, nil, nil, nil, true)
        end
    end
    -- detección (depuración)
    if c.key == "food" and s.foodReason and not endgame then
        add("detect", L["Detection: "] .. s.foodReason, nil, 0.6, 0.8, 1, nil, nil, nil, true)
    end
    -- ítems en las bolsas
    if s.sampleItems then
        for _, it in ipairs(s.sampleItems) do add("items", it[1], tostring(it[2]), 0.8, 0.8, 0.8, 1, 1, 1) end
    else
        for itemId in pairs(s.items or {}) do
            add("items", ns.GetItemName(itemId) or format(L["Item %d"], itemId), tostring(ns.GetItemCount(itemId)), 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    -- XP perdida
    if not endgame then
        local X = ns.XPBar
        local lost = s.sampleLost or (X and X.lostByCat and X.lostByCat[c.key]) or 0
        if lost > 0 then
            add("lost", format(L["XP lost without this buff (session): |cffff4040-%s|r"], ns.FormatNumber(lost)), nil, 1, 1, 1)
        end
        local lvl = s.sampleLostLevel or (X and X.levelLostByCat and X.levelLostByCat[c.key]) or 0
        if lvl > 0 then
            add("lostLevel", format(L["XP lost without this buff (this level): |cffff4040-%s|r"], ns.FormatNumber(lvl)), nil, 1, 1, 1)
        end
    end
    if s.phase == "unconfigured" then
        add("detect", L["This buff is not registered in the addon."], nil, 0.7, 0.7, 0.7, nil, nil, nil, true)
    end
    -- ayuda de clics
    if c.key == "food" then
        add("hint", L["Click: choose food · Shift+drag: move"], nil, 0.5, 0.5, 0.5)
    elseif c.key == "campfire" then
        add("hint", L["Click: choose camp item · Shift+drag: move"], nil, 0.5, 0.5, 0.5)
    else
        add("hint", L["Click: use item · Shift+drag: move"], nil, 0.5, 0.5, 0.5)
    end
    return lines
end

-- Vuelca las líneas en un tooltip según la configuración (shift = simular Shift apretado)
function ns:FillIconTooltip(tip, c, s, shift)
    tip:AddLine(c.label, 1, 0.82, 0)
    local hidden = false
    for _, l in ipairs(self:BuildIconTooltip(c, s)) do
        local mode = self:TooltipMode(l.sec, c.key)
        local show = mode == "always" or (mode == "shift" and shift)
        if mode == "shift" and not shift then hidden = true end
        if show then
            if l.right then
                tip:AddDoubleLine(l.left, l.right, l.r, l.g, l.b, l.r2, l.g2, l.b2)
            else
                tip:AddLine(l.left, l.r, l.g, l.b, l.wrap)
            end
        end
    end
    if hidden then tip:AddLine(L["Hold Shift for more info"], 0.45, 0.45, 0.45) end
    tip:Show()
end

function Display:ShowTooltip(owner, c)
    local s = ns.state[c.key]
    -- posición estándar de tooltips del juego (la que el usuario fija en Edit Mode)
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, owner)
    else
        GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    end
    self.tipOwner, self.tipCat = owner, c
    if c.key == "consumables" then return self:ShowConsumablesTooltip(s) end
    ns:FillIconTooltip(GameTooltip, c, s, IsShiftKeyDown())
end

-- Apretar o soltar Shift con el tooltip abierto: se redibuja
do
    local mod = CreateFrame("Frame")
    mod:RegisterEvent("MODIFIER_STATE_CHANGED")
    mod:SetScript("OnEvent", function()
        local o, c = Display.tipOwner, Display.tipCat
        if o and c and GameTooltip:IsOwned(o) and o:IsMouseOver() then
            GameTooltip:ClearLines()
            Display:ShowTooltip(o, c)
        end
    end)
end
