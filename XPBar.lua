-- Registro de XP (sin interfaz): cuánta XP ganaste gracias a los buffs y cuánta
-- perdiste por no tenerlos puestos (lleves o no el consumible).
--   XP por muertes: le aplican comida y saco (ns:XPBonus devuelve el % de muertes).
--   XP de misiones/otras: solo le aplica el saco (efecto "Quests too").
--   La XP de descanso (rested) se excluye: no viene de estos buffs.
local ADDON, ns = ...
local L = ns.L
local XP = {}
ns.XPBar = XP -- nombre histórico; ya no hay barra

local GetTime, format = GetTime, string.format
local KILL_WINDOW = 1.5 -- s entre el mensaje de muerte y la subida de XP

XP.session = { earned = 0, missed = 0 }
XP.level = { earned = 0, missed = 0 }
XP.lostByCat = {}      -- sesión
XP.levelLostByCat = {} -- nivel actual (lo que muestra el icono)
XP.lastKill = { t = 0, rested = 0 }

-- "Wolf dies, you gain 120 experience. (+60 exp Rested bonus)" → 60
local function ParseRested(msg)
    local r = msg and msg:match("%(%+?(%d+)")
    return tonumber(r) or 0
end

-- El canal CHAT_MSG_COMBAT_XP_GAIN trae TANTO muertes ("X dies, you gain N experience.")
-- como XP de misiones/exploración ("You gain N experience."). Solo las primeras son muertes.
-- Las plantillas vienen del cliente (COMBATLOG_XPGAIN_*), así funciona en cualquier idioma.
local KILL_PATTERNS

-- Convierte una plantilla de formato ("%s dies, you gain %d experience.") en un patrón Lua
local function ToPattern(fmt)
    local out, i = {}, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local whole, spec = fmt:match("^(%%%d*%$?([sd]))", i) -- %s, %d, %1$s, %2$d
            if whole then
                table.insert(out, spec == "s" and ".+" or "%d+")
                i = i + #whole
            else
                table.insert(out, "%%")
                i = i + 1
            end
        elseif c:find("[%(%)%.%+%-%*%?%[%]%^%$]") then
            table.insert(out, "%" .. c)
            i = i + 1
        else
            table.insert(out, c)
            i = i + 1
        end
    end
    return "^" .. table.concat(out)
end

local function BuildKillPatterns()
    KILL_PATTERNS = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "string" and k:find("^COMBATLOG_XPGAIN_")
            and not k:find("UNNAMED") and not k:find("QUEST")
            and v:find("%%%d*%$?s") then -- las de muerte llevan el nombre del enemigo
            table.insert(KILL_PATTERNS, ToPattern(v))
        end
    end
end

local function IsKillMessage(msg)
    if not msg then return false end
    if not KILL_PATTERNS then BuildKillPatterns() end
    if #KILL_PATTERNS == 0 then
        return msg:find(" dies") ~= nil -- respaldo si el cliente no expone las plantillas
    end
    for _, pat in ipairs(KILL_PATTERNS) do
        if msg:find(pat) then return true end
    end
    return false
end
XP.IsKillMessage = IsKillMessage

function XP:Create()
    self.prevXP, self.prevMax = UnitXP("player"), UnitXPMax("player")
    pcall(self.HookNativeBar, self)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
    ev:RegisterEvent("QUEST_TURNED_IN")
    ev:SetScript("OnEvent", function(_, event, msg)
        if event == "QUEST_TURNED_IN" then
            XP.lastQuest = GetTime() -- la XP que llegue ahora es de misión, no de muerte
        elseif IsKillMessage(msg) then
            XP.lastKill.t = GetTime()
            XP.lastKill.rested = XP.lastKill.rested + ParseRested(msg)
        end
    end)
end

-- Reparte una ganancia de XP entre base, bonus ganado y bonus perdido
local function Apply(self, delta, isKill, rested)
    if ns:IsEndgame() then return end -- End Game: sin seguimiento de XP
    local B, M = 0, 0 -- % activo y % perdido (con ítem en bolsas)
    local missByCat = {}
    for _, c in ipairs(ns.CATEGORIES) do
        if ns.cdb.enabled[c.key] and not ns.state[c.key].locked then
            local s = ns.state[c.key]
            local aKill, aQuest = ns:XPBonus(c.key, false)
            local pKill, pQuest = ns:XPBonus(c.key, true)
            local active = isKill and aKill or aQuest
            local potential = isKill and pKill or pQuest
            if s.active then
                B = B + active
            elseif potential > 0 then -- se cuenta siempre, lleves o no el consumible
                M = M + potential
                missByCat[c.key] = potential
            end
        end
    end

    local affected = math.max(0, delta - (rested or 0))
    local base = affected * 100 / (100 + B)
    local earned = affected - base
    local missed = base * M / 100

    self.level.earned = self.level.earned + earned
    self.level.missed = self.level.missed + missed
    self.session.earned = self.session.earned + earned
    self.session.missed = self.session.missed + missed
    for key, pct in pairs(missByCat) do
        local lost = base * pct / 100
        self.lostByCat[key] = (self.lostByCat[key] or 0) + lost
        self.levelLostByCat[key] = (self.levelLostByCat[key] or 0) + lost
    end
end

function XP:OnXP()
    local xp, mx = UnitXP("player"), UnitXPMax("player")
    local delta
    if xp >= (self.prevXP or xp) then
        delta = xp - (self.prevXP or xp)
    else -- subió de nivel
        delta = ((self.prevMax or 0) - (self.prevXP or 0)) + xp
    end
    self.prevXP, self.prevMax = xp, mx
    if delta <= 0 then return end

    -- el mensaje de muerte puede llegar justo antes o justo después: decidir en un instante
    C_Timer.After(0.1, function()
        local now = GetTime()
        local isKill = now - XP.lastKill.t <= KILL_WINDOW
            and not (XP.lastQuest and now - XP.lastQuest <= KILL_WINDOW)
        local rested = isKill and XP.lastKill.rested or 0
        XP.lastKill.rested = 0
        Apply(XP, delta, isKill, rested)
    end)
end

function XP:OnLevelUp(newLevel)
    -- esperar a que se registre la XP que causó la subida
    C_Timer.After(0.5, function()
        local e, m = XP.level.earned, XP.level.missed
        if ns.cdb.xpSummary and (e >= 1 or m >= 1) then
            ns.Print(format(L["Level %d: |cffffcc1a+%s XP|r from buffs · |cffff4040-%s XP|r lost without buffs"],
                newLevel or UnitLevel("player"), ns.FormatNumber(e), ns.FormatNumber(m)))
        end
        XP.level.earned, XP.level.missed = 0, 0
        wipe(XP.levelLostByCat)
    end)
end

function XP:PrintReport()
    ns.Print(format(L["Session: |cffffcc1a+%s XP|r from buffs · |cffff4040-%s XP|r lost without buffs"],
        ns.FormatNumber(self.session.earned), ns.FormatNumber(self.session.missed)))
    for _, c in ipairs(ns.CATEGORIES) do
        local lost = self.lostByCat[c.key] or 0
        if lost >= 1 then print(format("   %s: -%s XP", c.label, ns.FormatNumber(lost))) end
    end
    ns.Print(format(L["This level: +%s / -%s"], ns.FormatNumber(self.level.earned), ns.FormatNumber(self.level.missed)))
end

-- Líneas para el tooltip del minimapa
function XP:AddTooltipLines(tt)
    if ns:IsEndgame() then return end
    tt:AddLine(" ")
    tt:AddDoubleLine(L["XP from buffs (session)"], "+" .. ns.FormatNumber(self.session.earned), 1, 1, 1, 1, 0.8, 0.1)
    tt:AddDoubleLine(L["XP lost without buffs (session)"], "-" .. ns.FormatNumber(self.session.missed), 1, 1, 1, 1, 0.3, 0.3)
end

-- Tooltip de la barra de experiencia del juego --------------------------------
function XP:AddNativeTooltipLines(tt)
    if not ns.cdb or not ns.cdb.showXPTooltip or ns:IsMaxLevel() or ns:IsEndgame() then return end
    local e, m = self.level.earned, self.level.missed
    tt:AddLine(" ")
    tt:AddLine(L["CampXP (this level)"], 1, 0.82, 0)
    tt:AddDoubleLine(L["Gained from buffs"], "+" .. ns.FormatNumber(e), 1, 1, 1, 1, 0.8, 0.1)
    if m >= 1 then
        tt:AddDoubleLine(L["Lost without buffs"], "-" .. ns.FormatNumber(m), 1, 1, 1, 1, 0.3, 0.3)
        for _, c in ipairs(ns.CATEGORIES) do
            local lost = self.levelLostByCat[c.key] or 0
            if lost >= 1 then
                tt:AddDoubleLine("   " .. c.label, "-" .. ns.FormatNumber(lost), 0.7, 0.7, 0.7, 1, 0.45, 0.45)
            end
        end
    end
end

-- Se engancha a la barra de XP de Blizzard (clásica o moderna) sin crear nada nuevo
function XP:HookNativeBar()
    local function add()
        local owner = GameTooltip:GetOwner()
        if owner and owner.campXPHooked and GameTooltip:IsShown() then
            XP:AddNativeTooltipLines(GameTooltip)
            GameTooltip:Show()
        end
    end
    local function hookFrame(f)
        if f and f.HookScript and not f.campXPHooked then
            f.campXPHooked = true
            f:HookScript("OnEnter", function(self)
                -- algunos clientes no abren tooltip propio en la barra: abrirlo
                if not GameTooltip:IsOwned(self) then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:ClearLines()
                    GameTooltip:AddLine(format("XP: %s / %s", ns.FormatNumber(UnitXP("player")), ns.FormatNumber(UnitXPMax("player"))), 1, 1, 1)
                    GameTooltip:Show()
                end
                add()
            end)
            f:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    -- cliente clásico
    hookFrame(_G.MainMenuExpBar)
    -- cliente moderno: barras dentro de los contenedores de seguimiento
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local cont = _G[name]
        if cont and cont.bars then
            for _, bar in pairs(cont.bars) do
                if ExpBarMixin and bar.OnLoad == ExpBarMixin.OnLoad then hookFrame(bar) end
            end
        end
    end
    if StatusTrackingBarManager and StatusTrackingBarManager.bars then
        for _, bar in pairs(StatusTrackingBarManager.bars) do
            if ExpBarMixin and bar.OnLoad == ExpBarMixin.OnLoad then hookFrame(bar) end
        end
    end
end

-- Compatibilidad con llamadas existentes (ya no hay barra)
function XP:Update() end
function XP:RestorePos() end
