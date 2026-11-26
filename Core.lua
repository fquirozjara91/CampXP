-- CampXP: avisos de buffs de XP (campamento, saco de dormir, comida)
local ADDON, ns = ...
_G.CampXP = ns -- for debugging: /dump CampXP.state
local L = ns.L

local GetTime, format, floor, max = GetTime, string.format, math.floor, math.max

-- Algunas funciones del juego devuelven valores "secretos" (p. ej. en instancias):
-- no se pueden evaluar como booleano. Esto los convierte en false sin romper nada.
local isSecret = issecretvalue or function() return false end
function ns.Bool(f, ...)
    if not f then return false end
    local ok, v = pcall(f, ...)
    if not ok or isSecret(v) then return false end
    return v and true or false
end
local Bool = ns.Bool

local function SK(name, fallback)
    return (SOUNDKIT and SOUNDKIT[name]) or fallback
end

-- Categorías -------------------------------------------------------------
ns.CATEGORIES = {
    { key = "campfire",    label = L["Campfire"],     icon = "Interface\\Icons\\Spell_Fire_Fire",    sound = SK("RAID_WARNING", 8959) },
    { key = "sleepingbag", label = L["Sleeping Bag"], icon = "Interface\\Icons\\Spell_Nature_Sleep", sound = SK("READY_CHECK", 8960),
      perStack = true, maxStacks = 3 }, -- Well-Rested: 1% por stack, máx 3
    { key = "food",        label = L["XP Food"],      icon = "Interface\\Icons\\INV_Misc_Food_15",   sound = SK("ALARM_CLOCK_WARNING_3", 12889) },
    -- solo en modo End Game: consumibles que el jugador elige vigilar (Endgame.lua)
    { key = "consumables", label = L["Consumables"],  icon = "Interface\\Icons\\INV_Potion_97",      sound = SK("RAID_WARNING", 8959),
      endgameOnly = true },
}
ns.CAT = {}
for i, c in ipairs(ns.CATEGORIES) do
    c.index = i
    ns.CAT[c.key] = c
end

-- Buffs conocidos de WoW Forever (vienen de fábrica, sin configurar nada)
-- useSpells: hechizo "Usar" del ítem cuando es distinto del aura que queda
-- (la comida XP se come con 1243969 y deja el aura 1248421).
ns.BUILTIN = {
    [1229741] = { cat = "campfire",    name = "Camp Benefits" },
    [429959]  = { cat = "sleepingbag", name = "Well-Rested" },
    [1248421] = { cat = "food",        name = "Well Fed", useSpells = { 1243969 } },
}
-- Variantes nuevas con el mismo nombre se clasifican solas (nombres por idioma en Locale.lua).
-- Ojo: no todo "Well Fed" da XP; eso lo decide el tooltip (ns.ParseXP).
local NAME_RULES = ns.LOC.auraNames
-- Tipos de alerta (cada uno se activa/desactiva por categoría en /cxp)
ns.ALERT_KINDS = {
    { key = "expiring",     label = L["About to expire"] },
    { key = "missing",      label = L["Missing (item in bags)"] },
    { key = "expired_none", label = L["Ran out, no items left"] },
    { key = "lowstock",     label = L["Low stock"] },
    { key = "maxstacks",    label = L["Max stacks reached"], perStackOnly = true },
}

function ns:AlertOn(catKey, kind)
    local t = self.cdb.alertTypes[catKey]
    return not (t and t[kind] == false)
end

function ns:SetAlertOn(catKey, kind, on)
    self.cdb.alertTypes[catKey] = self.cdb.alertTypes[catKey] or {}
    self.cdb.alertTypes[catKey][kind] = on and true or false
end

-- Bonus de XP de WoW Forever (solo lectura).
--   kill = % sobre XP por matar enemigos; all = % sobre toda la XP (misiones incluidas)
--   Comida: solo muertes; el % real se lee de su tooltip (5 por defecto).
--   Saco (Well-Rested): +1% por stack a TODA la XP (muertes, misiones, exploración), máx +3%.
--   Los bonos se suman sobre la XP base; la XP de descanso no recibe bonus.
ns.XP_RULES = {
    food        = { kill = 5 },
    sleepingbag = { all = 1 },
    campfire    = {},
}
ns.DEFAULT_BONUS = { food = 5, sleepingbag = 1, campfire = 0 } -- compatibilidad

function ns:BonusText(key)
    if key == "food" then return L["+5% kill XP (as stated by the food tooltip)"] end
    if key == "sleepingbag" then return L["+1% to all XP per stack (max +3% at 3 stacks)"] end
    return L["No XP bonus"]
end

-- Stacks a usar: los actuales si está activo, el máximo para "lo que pudiste tener"
local function Stacks(c, s, potential)
    if not c.perStack then return 1 end
    if potential then return c.maxStacks or 1 end
    return math.max(1, math.min(s.stacks or 1, c.maxStacks or 1))
end

-- % sobre XP de muertes y sobre XP de misiones/otras.
-- potential=false: lo que da ahora (0 si no está activo); true: lo que daría al máximo
function ns:XPBonus(key, potential)
    local c, s, r = self.CAT[key], self.state[key], self.XP_RULES[key] or {}
    if not potential and not s.active then return 0, 0 end
    local st = Stacks(c, s, potential)
    local kill = (r.kill or 0)
    if key == "food" and s.xpPct and not potential then kill = s.xpPct end
    local all = (r.all or 0)
    return (kill + all) * st, all * st
end

-- Compatibilidad: % sobre muertes (activo, potencial)
function ns:BonusPct(key)
    local a = self:XPBonus(key, false)
    local p = self:XPBonus(key, true)
    return a, p
end
local AUTO_WINDOW = 30 -- s: ítem usado justo antes de aplicarse/renovarse el buff (comer tarda 10+ s)

-- Bindings

-- Campamento (item IDs de wowhead: Camping Overview) ------------------------
-- Kits de fogata, del mejor al básico (primeros en la grilla)
-- Juguete que extiende Camp Benefits de 1 h a 2 h (Toy Box)
-- (solo en la grilla; Blizzard anunció que lo retirará, por eso no tiene aviso)
ns.CAMP_TOY = 289439 -- Pouch of Violet Dust

function ns:HasCampToy()
    return PlayerHasToy and PlayerHasToy(self.CAMP_TOY) and true or false
end

-- ¿El juguete está listo para usar? (sin cooldown)
function ns:CampToyReady()
    if not self:HasCampToy() then return false end
    local start, dur
    if C_Container and C_Container.GetItemCooldown then
        start, dur = C_Container.GetItemCooldown(self.CAMP_TOY)
    elseif GetItemCooldown then
        start, dur = GetItemCooldown(self.CAMP_TOY)
    end
    if not start or not dur or dur == 0 then return true end
    return start + dur <= GetTime()
end

ns.CAMP_KITS = {
    279974, -- Expert Campfire Kit
    279961, -- Journeyman Campfire Kit
    279981, -- Basic Campfire Kit
}
-- Sacos de dormir (Well-Rested): el clic en el icono del saco usa el primero que tengas
-- El saco solo se obtiene con la misión "This Must Be the Place" (nivel 14)
ns.SLEEPING_BAG_QUEST = 79976

-- ¿El personaje desbloqueó el saco? (misión completada, o ya lleva uno por si acaso)
function ns:SleepingBagUnlocked()
    if self.bagUnlocked then return true end
    local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        and C_QuestLog.IsQuestFlaggedCompleted(self.SLEEPING_BAG_QUEST)
    if not done and IsQuestFlaggedCompleted then done = IsQuestFlaggedCompleted(self.SLEEPING_BAG_QUEST) end
    if not done then
        for _, id in ipairs(self.SLEEPING_BAGS) do
            if ns.GetItemCount(id) > 0 then done = true break end
        end
    end
    if done then self.bagUnlocked = true end -- una vez desbloqueado no se vuelve a consultar
    return done and true or false
end

ns.SLEEPING_BAGS = {
    211527, -- Cozy Sleeping Bag
}
-- Objetos de campamento por profesión, tier 1 > 3
ns.CAMP_FEATURES = {
    279956, 279970, 279990, -- Alchemy: Mana Well, Fermenter, Alchemy Laboratory
    279944, 279988, 279955, -- Blacksmithing: Sharpening Wheel, Anvil, Master Forge
    279957,                 -- Cooking: Cookie's Feast
    279976, 279985, 279987, -- Enchanting: Enchanted Lute, Arcane Salvager, Arcane Forge
    279950, 279949, 279989, -- Engineering: Reagent Bot, Repair Bot, Anarchist's Workbench
    279968, 279940, 279951, -- First Aid: First Aid Kit, Toxin Study, Plague Doctor's Laboratory
    279967, 279965, 279966, -- Fishing: Fish Bowl, Fishing Rack, Fishing Hut
    279962, 279964, 279947, -- Herbalism: Incense Candle, Greenhouse, Seed Hybridizer
    279978, 279941, 279945, -- Leatherworking: Camp Tent, Tanning Rack, Sewing Machine
    279960, 279948, 279952, -- Mining: Lodestone, Rock Garden, Molten Foundry
    279979, 279969, 279938, -- Skinning: Camp Chair, Field Guide, Trapper's Workbench
    279972, 279943, 279959, -- Tailoring: Faction Banner, Spinning Wheel, Loom
}

-- Profesión de cada objeto de campamento (índice en PROFESSIONS, más abajo)
ns.CAMP_PROF = {}
for prof, ids in ipairs({
    { 279956, 279970, 279990 }, { 279944, 279988, 279955 }, { 279957 },
    { 279976, 279985, 279987 }, { 279950, 279949, 279989 }, { 279968, 279940, 279951 },
    { 279967, 279965, 279966 }, { 279962, 279964, 279947 }, { 279978, 279941, 279945 },
    { 279960, 279948, 279952 }, { 279979, 279969, 279938 }, { 279972, 279943, 279959 },
}) do
    for _, id in ipairs(ids) do ns.CAMP_PROF[id] = prof end
end

-- Saved variables ----------------------------------------------------------
local DEFAULTS = {
    version = 1,
    entries = {},    -- [spellId] = { cat, name, icon, enabled, items = { [itemId] = true } }
}

local CHAR_DEFAULTS = {
    enabled = { campfire = true, sleepingbag = true, food = true, consumables = true },
    mode = "leveling",     -- "leveling" o "endgame"
    endgameAsked = false,  -- ya se le preguntó al llegar a 60
    endgame = { tracked = {}, ignored = {}, auto = true, warnMin = 10, lowStock = 2, onInstance = true, onReadyCheck = true },
    warnSec = 120,
    remindMin = 5,
    lowStock = 3,
    sound = true,
    alerts = true,
    locked = false,
    suppress = { combat = true, resting = true, mounted = true, maxLevel = true,
                 dead = true, taxi = true, afk = false, instance = false },
    -- cómo avisar (pestaña Notificaciones)
    chatAlerts = true,     -- mensaje en el chat
    flashAlerts = true,    -- destello del ícono
    alertPos = "top",      -- texto grande: "top" o "center"
    alertSize = 100,       -- tamaño del texto grande (%)
    soundExpiring = "default", soundMissing = "default", soundConsumables = "default",
    minimap = { angle = 200, hide = false },
    xpSummary = true,     -- resumen de XP en el chat al subir de nivel
    showXPTooltip = true, -- líneas de CampXP en el tooltip de la barra de XP del juego
    showLostBadge = true, -- "-N" rojo sobre el icono del buff que te falta
    pos = {},
    auraSource = {}, -- [spellId] = { itemId, exp } qué ítem aplicó cada "Well Fed"
    alertTypes = {}, -- [cat][kind] = false para desactivar ese aviso
    pickerSide = "right", -- posición de las grillas: right, left, top, bottom
    iconStyle = "round", -- "round", "minimal" o "classic"
    textScale = 100,     -- tamaño de los textos de los iconos (%)
    iconSize = 40,       -- tamaño de los íconos (px)
    iconGap = 8,         -- espacio entre íconos (px)
    vertical = false,    -- íconos en columna
    inactiveAlpha = 40,  -- opacidad de un buff que falta sin ítem (%)
    showTimer = true, showCount = true, showBonus = true,
    gridCols = 5,        -- columnas de las grillas
    gridSize = 36,       -- tamaño de los botones de las grillas (px)
    gridAnim = true,     -- animación al abrir/cerrar grillas (estilo Redondo)
    gridTextScale = 100, -- textos de los botones de las grillas (%)
    gridShowCount = true, gridShowBadge = true, gridShowCheck = true,
    statColors = {},     -- [estadística] = { r, g, b } insignias de la grilla en End Game
    tooltip = {},        -- [sección] = "always" | "shift" | "off" (vacío = valores por defecto)
    confirmNoXP = true, -- preguntar antes de comer comida sin XP
    foodChoice = nil,   -- última comida XP elegida en la grilla
    foodPreferred = nil, -- comida fija del ícono (menú del clic derecho); nil = automática
    campMine = false,   -- grilla del campamento: solo los objetos de tus profesiones
    restBagReminder = true, -- avisar al empezar a descansar sin los 3 stacks del saco
    favorites = {},     -- [itemId] = true: comidas/consumibles favoritos (primero en la grilla)
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Restablecer configuración del personaje: vuelve a los valores por defecto,
-- pero conserva posiciones, modo, consumibles vigilados/ignorados y lo aprendido
function ns:ResetSettings()
    local old = CampXPCharDB or {}
    local keep = {
        pos = old.pos, mode = old.mode, endgameAsked = old.endgameAsked,
        auraSource = old.auraSource, foodChoice = old.foodChoice,
        tracked = old.endgame and old.endgame.tracked, ignored = old.endgame and old.endgame.ignored,
        minimapAngle = old.minimap and old.minimap.angle,
    }
    wipe(old)
    Merge(old, CHAR_DEFAULTS)
    old.pos, old.mode, old.endgameAsked = keep.pos or {}, keep.mode or "leveling", keep.endgameAsked or false
    old.auraSource, old.foodChoice = keep.auraSource or {}, keep.foodChoice
    old.endgame.tracked, old.endgame.ignored = keep.tracked or {}, keep.ignored or {}
    old.minimap.angle = keep.minimapAngle or old.minimap.angle
    CampXPCharDB = old
    self.cdb = old
    if self.Display then self.Display:ApplyStyle() end
    if self.ApplyModeLabels then self:ApplyModeLabels() end
    self:FullUpdate()
    self.Print(L["Settings reset to defaults."])
end

-- Utilidades ---------------------------------------------------------------
function ns.Print(msg)
    print("|cffff9933CampXP|r: " .. tostring(msg))
end

function ns.FormatTime(sec)
    if not sec or sec == math.huge then return "--" end
    sec = max(0, sec)
    if sec >= 3600 then return format("%dh%02d", floor(sec / 3600), floor(sec % 3600 / 60)) end
    if sec >= 600 then return format("%dm", floor(sec / 60)) end
    if sec >= 60 then return format("%d:%02d", floor(sec / 60), floor(sec % 60)) end
    return format("%ds", floor(sec))
end

function ns.FormatNumber(n)
    n = floor((n or 0) + 0.5)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

function ns.GetItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
    return (GetItemCount and GetItemCount(id)) or 0
end

function ns.GetItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id)
end

function ns.GetItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    return GetItemInfo and (GetItemInfo(id))
end

function ns.GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and (GetSpellInfo(id))
end

function ns.GetSpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellInfo then
        local _, _, icon = GetSpellInfo(id)
        return icon
    end
end

function ns:IsMaxLevel()
    local maxL = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or MAX_PLAYER_LEVEL or 60
    if IsXPUserDisabled and IsXPUserDisabled() then return true end
    return UnitLevel("player") >= maxL
end

-- Auras -------------------------------------------------------------------
ns.auras = {}

local function IterateHelpful(cb)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 255 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then break end
            cb(a.spellId, a.name, a.icon, a.duration, a.expirationTime, a.auraInstanceID, i, a.sourceUnit, a.applications)
        end
    elseif UnitAura then
        for i = 1, 40 do
            local name, icon, count, _, duration, expirationTime, source, _, _, spellId = UnitAura("player", i, "HELPFUL")
            if not name then break end
            cb(spellId, name, icon, duration, expirationTime, nil, i, source, count)
        end
    end
end

-- El cliente moderno vuelve "secretas" las auras en combate/contenido restringido
-- y los addons no pueden leerlas: en ese caso pausamos y usamos los últimos datos.
function ns.AurasLocked()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, locked = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and locked then return true end
    end
    return false
end

local issecret = issecretvalue or function() return false end

function ns:ScanAuras()
    if ns.AurasLocked() then
        self.dirtyAuras = true -- reintenta cuando se liberen
        return
    end
    local new = {}
    local ok = pcall(IterateHelpful, function(spellId, name, icon, duration, exp, instanceId, index, source, stacks)
        if issecret(spellId) or issecret(exp) then error("secret") end
        if spellId then
            new[spellId] = {
                spellId = spellId, name = name, icon = icon, duration = duration or 0, expirationTime = exp or 0,
                auraInstanceID = instanceId, index = index, stacks = stacks or 0,
                -- lanzado por otro jugador (bendiciones, intelecto arcano...)
                fromOther = source ~= nil and not isSecret(source) and not Bool(UnitIsUnit, source, "player"),
                -- puesto por ti mismo (consumibles): sin fuente conocida NO cuenta como propio
                own = source ~= nil and not isSecret(source) and Bool(UnitIsUnit, source, "player"),
            }
        end
    end)
    if not ok then
        self.dirtyAuras = true -- bloqueadas a mitad de lectura: conserva lo anterior
        return
    end
    if self.auraBaseline then
        for spellId, a in pairs(new) do
            local old = self.auras[spellId]
            local isNew = not old
            local refreshed = old and a.expirationTime > 0 and a.expirationTime > (old.expirationTime or 0) + 5
            if isNew or refreshed then
                local e = self.db.entries[spellId]
                local isFoodAura = (e and e.cat == "food") or (not e and NAME_RULES[a.name] == "food")
                if isFoodAura then
                    -- recuerda qué ítem dejó este "Well Fed" (comida XP o normal)
                    self:RecordFoodSource(spellId, a)
                    if not e and self:ClassifyFood(spellId, a) then
                        self:AddEntry("food", spellId, nil, a.name, a.icon)
                        self.Print(format(L["XP food detected: %s (%d)"], a.name, spellId))
                    end
                    -- (la comida no usa ítems asociados: los de XP salen de su tooltip)
                elseif e then
                    -- campamento/saco: solo se asocian ítems cuyo efecto "Usar" es este buff
                    -- (NO "el último ítem usado": Camp Benefits viene de estar junto al fuego)
                    self:AutoMatchItems()
                elseif isNew and a.name and NAME_RULES[a.name] then
                    self:AddEntry(NAME_RULES[a.name], spellId, nil, a.name, a.icon)
                    self:AutoMatchItems()
                    self.Print(format(L["Detected: %s (%d) > %s"], a.name, spellId, self.CAT[NAME_RULES[a.name]].label))
                end
            end
        end
    end
    self.auras = new

    -- ¿terminó de comer? (desaparece el aura "Food"/"Drink"): revisar Well Fed de nuevo
    local eating = false
    for _, a in pairs(new) do
        if a.name and ns.LOC.eatingNames[a.name] then eating = true break end
    end
    if self.wasEating and not eating then
        self:ResetFoodClass()
        for _, t in ipairs({ 1, 3 }) do
            C_Timer.After(t, function() ns:ResetFoodClass(); ns.dirtyAuras = true end)
        end
    end
    self.wasEating = eating
    self.auraBaseline = true
    self.tipScans = (self.tipScans or 0) + 1
    if self.tipScans > 500 then self.tipScans = 0; self:ClearTipCache() end
end

-- Uso de ítems (para el modo aprendizaje) ---------------------------------
local lastItemUse = { id = nil, t = 0 }
local lastFoodUse = { id = nil, t = 0 } -- última comida que da Well Fed (las bebidas no)

-- Ventanas donde clic derecho / bajar cantidad NO es "consumir" (vender, banco, correo...)
local interacting = {}
local INTERACT_EVENTS = {
    MERCHANT_SHOW = "merchant", MERCHANT_CLOSED = "merchant",
    BANKFRAME_OPENED = "bank", BANKFRAME_CLOSED = "bank",
    MAIL_SHOW = "mail", MAIL_CLOSED = "mail",
    TRADE_SHOW = "trade", TRADE_CLOSED = "trade",
    AUCTION_HOUSE_SHOW = "auction", AUCTION_HOUSE_CLOSED = "auction",
    GUILDBANKFRAME_OPENED = "gbank", GUILDBANKFRAME_CLOSED = "gbank",
}
local INTERACT_OPEN = {
    MERCHANT_SHOW = true, BANKFRAME_OPENED = true, MAIL_SHOW = true,
    TRADE_SHOW = true, AUCTION_HOUSE_SHOW = true, GUILDBANKFRAME_OPENED = true,
}
ns.interactionEnded = 0
function ns:OnInteraction(event)
    local key = INTERACT_EVENTS[event]
    if INTERACT_OPEN[event] then
        interacting[key] = true
    else
        interacting[key] = nil
        self.interactionEnded = GetTime()
    end
end
local function IsInteracting()
    -- margen de 2 s: las bolsas se actualizan justo después de cerrar
    return next(interacting) ~= nil or GetTime() - ns.interactionEnded < 2
end

-- Solo cuenta ítems con efecto "Usar" (la chatarra o los materiales no dan buffs)
local function ItemHasUse(id)
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return true end
    return fn(id) ~= nil
end

function ns.NoteItemUse(id)
    if not id or IsInteracting() or not ItemHasUse(id) then return end
    lastItemUse.id = id
    lastItemUse.t = GetTime()
    -- comer y luego beber: el Well Fed es de la comida, no del agua
    if ns.IsFoodItem(id) and ns.FoodGivesWellFed and ns:FoodGivesWellFed(id) ~= false then
        lastFoodUse.id, lastFoodUse.t = id, lastItemUse.t
    end
end


local function HookItemUse()
    if C_Container and C_Container.UseContainerItem then
        hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
            ns.NoteItemUse(C_Container.GetContainerItemID(bag, slot))
        end)
    end
    if type(UseContainerItem) == "function" and type(GetContainerItemID) == "function" then
        hooksecurefunc("UseContainerItem", function(bag, slot)
            ns.NoteItemUse(GetContainerItemID(bag, slot))
        end)
    end
    if type(UseAction) == "function" then
        hooksecurefunc("UseAction", function(slot)
            local t, id = GetActionInfo(slot)
            if t == "item" then ns.NoteItemUse(id) end
        end)
    end
    if type(UseItemByName) == "function" then
        hooksecurefunc("UseItemByName", function(name)
            local id = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(name)
            if not id and GetItemInfoInstant then id = GetItemInfoInstant(name) end
            ns.NoteItemUse(id)
        end)
    end
end

-- Foto de las bolsas: detecta consumibles que bajaron (respaldo del hook)
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local function CountBags()
    local t = {}
    local nb = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, nb do
        local slots = (GetNumSlots and GetNumSlots(bag)) or 0
        for slot = 1, slots do
            local id, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then id, count = info.itemID, info.stackCount end
            elseif GetContainerItemInfo then
                local _, c, _, _, _, _, _, _, _, iid = GetContainerItemInfo(bag, slot)
                id, count = iid, c
            end
            if id then t[id] = (t[id] or 0) + (count or 1) end
        end
    end
    return t
end
local bagSnapshot = {}
function ns.GetBagSnapshot() return bagSnapshot end

-- Posición del stack MÁS PEQUEÑO de un ítem, como "bolsa slot" para los botones seguros.
-- Usar por ID deja que el juego elija el stack y va alternando (20+20 > 16+16);
-- consumir siempre del más chico lo vacía primero y libera el espacio.
function ns.SmallestStackRef(itemId)
    local nb = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    local bestBag, bestSlot, bestCount
    for bag = 0, nb do
        local slots = (GetNumSlots and GetNumSlots(bag)) or 0
        for slot = 1, slots do
            local id, count
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info then id, count = info.itemID, info.stackCount end
            elseif GetContainerItemInfo then
                local _, c, _, _, _, _, _, _, _, iid = GetContainerItemInfo(bag, slot)
                id, count = iid, c
            end
            if id == itemId and (not bestCount or (count or 1) < bestCount) then
                bestBag, bestSlot, bestCount = bag, slot, count or 1
            end
        end
    end
    if bestBag then return bestBag .. " " .. bestSlot end
    return "item:" .. itemId -- respaldo: por ID
end

-- Busca en las bolsas un ítem cuyo efecto "Usar" coincida con el aura
local function GetItemSpell(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) end
    if GetItemSpell then return GetItemSpell(id) end
end

function ns:MatchItemForAura(spellId, name)
    local b = self.BUILTIN[spellId]
    local extra = {}
    if b and b.useSpells then
        for _, id in ipairs(b.useSpells) do extra[id] = true end
    end
    for itemId in pairs(bagSnapshot) do
        local sName, sId = GetItemSpell(itemId)
        if (sId and (sId == spellId or extra[sId])) or (name and sName == name)
            or (name and ns.GetItemName(itemId) == name) then
            return itemId
        end
    end
end


-- Comida XP vs comida normal ------------------------------------------------

local scanTip
function ns:GetAuraTooltipLines(a)
    if ns.AurasLocked() then return {} end
    local ok, lines = pcall(self.ReadAuraTooltip, self, a)
    return ok and lines or {}
end

function ns:ReadAuraTooltip(a)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID and a.auraInstanceID then
        local data = C_TooltipInfo.GetUnitBuffByAuraInstanceID("player", a.auraInstanceID)
        if data and data.lines then
            for _, l in ipairs(data.lines) do
                if l.leftText and not issecret(l.leftText) and l.leftText ~= "" then table.insert(lines, l.leftText) end
            end
        end
        if #lines > 0 then return lines end
    end
    if a.index then
        scanTip = scanTip or CreateFrame("GameTooltip", "CampXPScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetUnitBuff("player", a.index)
        for i = 1, scanTip:NumLines() do
            local fs = _G["CampXPScanTipTextLeft" .. i]
            local t = fs and fs:GetText()
            if t and not issecret(t) and t ~= "" then table.insert(lines, t) end
        end
        scanTip:Hide()
    end
    return lines
end

-- Comidas de las bolsas ----------------------------------------------------
-- Consumible (clase 0) / Comida y bebida (subclase 5)
local FOOD_CLASS, FOOD_SUBCLASS = 0, 5
-- Una comida da XP solo si su tooltip menciona experiencia (hay "Well Fed" sin XP)
local foodXPCache, foodPctCache = {}, {}

local function ItemInstant(id)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(id) end
    if GetItemInfoInstant then return GetItemInfoInstant(id) end
end

function ns.IsFoodItem(id)
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    return classID == FOOD_CLASS and subClassID == FOOD_SUBCLASS
end

local ItemTooltipLines
function ns.ItemTooltipLines(id) return ItemTooltipLines(id) end
ItemTooltipLines = function(id)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local data = C_TooltipInfo.GetItemByID(id)
        if data and data.lines then
            for _, l in ipairs(data.lines) do
                if l.leftText and not issecret(l.leftText) and l.leftText ~= "" then
                    table.insert(lines, l.leftText)
                end
            end
        end
        if #lines > 0 then return lines end
    end
    scanTip = scanTip or CreateFrame("GameTooltip", "CampXPScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetItemByID(id)
    for i = 1, scanTip:NumLines() do
        local fs = _G["CampXPScanTipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and not issecret(t) and t ~= "" then table.insert(lines, t) end
    end
    scanTip:Hide()
    return lines
end

-- Línea "Use:" del tooltip (localizada por el cliente: "Use:", "Uso:"...)
local USE_PREFIX = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
local lastTry = {}
local noXPSince = {} -- primera vez que el tooltip del ítem no mostró XP

local function RequestData(id)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
    -- el texto "Use:" viene del hechizo del ítem, que se carga aparte
    local _, spellId = GetItemSpell(id)
    if spellId and C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(spellId) end
end

-- true/false según el tooltip del ítem; nil si el tooltip aún no está completo
function ns:FoodGivesXP(id)
    if foodXPCache[id] ~= nil then return foodXPCache[id], foodPctCache[id] end
    -- registro de comidas conocidas (Foods.lua): no hace falta esperar al tooltip
    local known = ns.FOOD_DB and ns.FOOD_DB[id]
    if known and known.xp then
        foodXPCache[id], foodPctCache[id] = true, known.xp
        return true, known.xp
    end
    local now = GetTime()
    if lastTry[id] and now - lastTry[id] < 1 then return nil end -- reintenta cada 1 s
    lastTry[id] = now

    local ok, lines = pcall(ItemTooltipLines, id)
    if not ok then RequestData(id) return nil end
    local useText
    for _, l in ipairs(lines) do
        local low = l:lower()
        if low:sub(1, #USE_PREFIX) == USE_PREFIX and #low > #USE_PREFIX + 10 then useText = l break end
    end
    local xp, pct = ns.ParseXP(table.concat(lines, " "))
    if xp then
        foodXPCache[id], foodPctCache[id] = true, pct
        return true, pct
    end
    if not useText then
        -- descripción aún sin cargar: no concluir nada todavía
        RequestData(id)
        return nil
    end
    -- "sin XP" solo se da por seguro tras dos lecturas separadas (la frase de XP
    -- puede cargar después del resto del texto la primera vez que se ve el ítem)
    local firstNo = noXPSince[id]
    if not firstNo then
        noXPSince[id] = now
        RequestData(id)
        return false
    end
    if now - firstNo >= 3 then foodXPCache[id] = false end
    return false
end

-- Resultado ya definitivo de FoodGivesXP (nil = aún no se sabe)
function ns.FoodXPKnown(id) return foodXPCache[id], foodPctCache[id] end

-- Comidas de las bolsas: { {id, count, xp, stat}, ... } con las buenas primero
-- (Leveling: xp = da XP; End Game: xp = da Well Fed y stat = su texto corto)
function ns:GetBagFoods()
    local list = {}
    local endgame = self:IsEndgame()
    for id, count in pairs(bagSnapshot) do
        if ns.IsFoodItem(id) then
            if endgame then
                local wf, stat, statKey, statKeys = self:FoodGivesWellFed(id)
                table.insert(list, { id = id, count = count, xp = wf, stat = stat, statKey = statKey, statKeys = statKeys })
            else
                table.insert(list, { id = id, count = count, xp = self:FoodGivesXP(id) })
            end
        end
    end
    -- predeterminado por spec (End Game): primero la comida de tu lista que tienes,
    -- luego la que te falta (gris) y después el resto
    local preset = endgame and self.PresetItems and self:PresetItems("food") or {}
    local set = {}
    for _, id in ipairs(preset) do set[id] = true end
    for _, f in ipairs(list) do f.inPreset = set[f.id] end
    for _, id in ipairs(preset) do
        if not bagSnapshot[id] then
            local wf, stat, statKey, statKeys = self:FoodGivesWellFed(id)
            table.insert(list, { id = id, count = 0, missing = true, inPreset = true,
                                 xp = wf, stat = stat, statKey = statKey, statKeys = statKeys })
        end
    end
    local function Rank(f)
        if #preset == 0 then return 1 end
        if f.missing then return 2 end
        return f.inPreset and 1 or 3
    end
    table.sort(list, function(a, b)
        local ra, rb = Rank(a), Rank(b)
        if ra ~= rb then return ra < rb end
        local fa, fb = ns:IsFavorite(a.id), ns:IsFavorite(b.id)
        if fa ~= fb then return fa end -- favoritos primero
        if (a.xp == true) ~= (b.xp == true) then return a.xp == true end
        return (ns.GetItemName(a.id) or "") < (ns.GetItemName(b.id) or "")
    end)
    return list
end

-- Favoritos (clic derecho en la grilla de comida o consumibles)
function ns:IsFavorite(id)
    return self.cdb.favorites ~= nil and self.cdb.favorites[id] == true
end

function ns:ToggleFavorite(id)
    self.cdb.favorites = self.cdb.favorites or {}
    local name = ns.GetItemName(id) or format(L["Item %d"], id)
    if self.cdb.favorites[id] then
        self.cdb.favorites[id] = nil
        self.Print(format(L["%s removed from favorites"], name))
    else
        self.cdb.favorites[id] = true
        self.Print(format(L["%s set as favorite"], name))
    end
    self:FullUpdate()
end

-- Kits y objetos de campamento que tengas, en el orden de la grilla
function ns:GetBagCampItems()
    local list = {}
    for _, id in ipairs(self.CAMP_KITS) do
        local n = ns.GetItemCount(id)
        if n > 0 then table.insert(list, { id = id, count = n, kit = true }) end
    end
    -- juguete de la Toy Box (no ocupa bolsa): después de los kits
    if self:HasCampToy() then
        table.insert(list, { id = self.CAMP_TOY, count = 1, toy = true })
    end
    local mine = self.cdb.campMine and self:PlayerProfessions()
    for _, id in ipairs(self.CAMP_FEATURES) do
        local n = ns.GetItemCount(id)
        if not mine then
            if n > 0 then table.insert(list, { id = id, count = n }) end
        elseif mine[ns.CAMP_PROF[id] or 0] then
            -- tus profesiones: todos sus objetos (todos los tiers); los que no tienes, en gris
            table.insert(list, { id = id, count = n, missing = n == 0 or nil })
        end
    end
    return list
end

-- Profesiones (mismo orden que CAMP_FEATURES), con su nombre en inglés y español
local PROFESSIONS = {
    { "Alchemy", "Alquimia" }, { "Blacksmithing", "Herrería" }, { "Cooking", "Cocina" },
    { "Enchanting", "Encantamiento" }, { "Engineering", "Ingeniería" }, { "First Aid", "Primeros auxilios" },
    { "Fishing", "Pesca" }, { "Herbalism", "Herboristería" }, { "Leatherworking", "Peletería" },
    { "Mining", "Minería" }, { "Skinning", "Desuello" }, { "Tailoring", "Sastrería" },
}

-- Hechizos de cada profesión (todos los rangos de Classic): sirven aunque el juego no liste la habilidad
local PROF_SPELLS = {
    { 2259, 3101, 3464, 11611 }, { 2018, 3100, 3538, 9785 }, { 2550, 3102, 3413, 18260 },
    { 7411, 7412, 7413, 13920 }, { 4036, 4037, 4038, 12656 }, { 3273, 3274, 7924, 10846 },
    { 7620, 7731, 7732, 18248 }, { 2366, 2368, 3570, 11993, 2383 }, { 2108, 3104, 3811, 10662 },
    { 2575, 2576, 3564, 10248, 2580, 2656 }, { 8613, 8617, 8618, 10768 }, { 3908, 3909, 3910, 12180 },
}

-- Profesiones del personaje: { [índice] = true }
function ns:PlayerProfessions()
    local have = {}
    local function Match(name)
        if not name or isSecret(name) then return end
        local low = name:lower()
        for idx, names in ipairs(PROFESSIONS) do
            if low == names[1]:lower() or low == names[2]:lower() then have[idx] = true end
        end
    end
    -- 1) ventana de habilidades; las categorías plegadas no listan sus habilidades: se despliegan un momento
    if GetNumSkillLines and GetSkillLineInfo then
        local collapsed = {}
        local i = 1
        while i <= GetNumSkillLines() and i < 200 do
            local name, isHeader, isExpanded = GetSkillLineInfo(i)
            if isHeader and not isExpanded and ExpandSkillHeader and not isSecret(name) then
                collapsed[#collapsed + 1] = name
                pcall(ExpandSkillHeader, i)
            end
            if not isHeader then Match(name) end
            i = i + 1
        end
        -- volver a plegar lo que estaba plegado
        if #collapsed > 0 and CollapseSkillHeader then
            for j = GetNumSkillLines(), 1, -1 do
                local name, isHeader = GetSkillLineInfo(j)
                if isHeader then
                    for _, c in ipairs(collapsed) do if c == name then pcall(CollapseSkillHeader, j) end end
                end
            end
        end
    end
    -- 2) hechizos de profesión conocidos
    local known = IsPlayerSpell or IsSpellKnown
    if known then
        for idx, spells in ipairs(PROF_SPELLS) do
            if not have[idx] then
                for _, sid in ipairs(spells) do
                    if Bool(known, sid) then have[idx] = true break end
                end
            end
        end
    end
    return have
end

-- /cxp prof: qué profesiones detecta CampXP
function ns:DebugProfessions()
    local have, names = self:PlayerProfessions(), {}
    for idx, n in ipairs(PROFESSIONS) do
        if have[idx] then names[#names + 1] = (ns.locale == "esES" or ns.locale == "esMX") and n[2] or n[1] end
    end
    self.Print(L["Professions detected: "] .. (#names > 0 and table.concat(names, ", ") or L["none"]))
end

-- ¿El tooltip del aura menciona experiencia? Devuelve xp (nil = sin texto), pct
local tipCache = {}
function ns:TooltipSaysXP(a)
    -- incluye la expiración: comer otra comida renueva el aura con otro texto
    local key = tostring(a.auraInstanceID or 0) .. ":" .. tostring(a.expirationTime)
    local hit = tipCache[key]
    -- un "sí" es definitivo; un "no" se vuelve a leer cada 2 s durante los primeros 15 s
    -- (recién comido, la descripción del buff puede llegar incompleta)
    if hit and (hit.xp or GetTime() - hit.t < 2 or GetTime() - hit.first > 15) then return hit.xp, hit.pct end
    local lines = self:GetAuraTooltipLines(a)
    if #lines == 0 then return nil end -- reintenta luego (p. ej. tras el combate)
    local xp, pct = ns.ParseXP(table.concat(lines, " "))
    -- sin descripción (solo nombre + tiempo restante) el texto aún no cargó: no concluir
    if not xp and #lines < 3 then return nil end
    if not xp and a.spellId and C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(a.spellId) end
    tipCache[key] = { xp = xp, pct = pct, t = GetTime(), first = hit and hit.first or GetTime() }
    return xp, pct
end

function ns:ClearTipCache() wipe(tipCache) end

-- ¿Este ítem es comida XP? Lo dice su tooltip
function ns:IsXPFoodItem(itemId)
    if not itemId then return false end
    return self:FoodGivesXP(itemId) == true
end

-- Hora absoluta de expiración (sobrevive a /reload y a reiniciar el cliente)
local function EpochExpiry(a)
    if not a.expirationTime or a.expirationTime <= 0 then return nil end
    return time() + (a.expirationTime - GetTime())
end

function ns:RecordFoodSource(spellId, a)
    local src = (lastFoodUse.id and GetTime() - lastFoodUse.t <= AUTO_WINDOW) and lastFoodUse or lastItemUse
    if not src.id or GetTime() - src.t > AUTO_WINDOW then return end
    local exp = EpochExpiry(a)
    if not exp then return end
    self.cdb.auraSource[spellId] = { itemId = src.id, exp = exp }
    if ns.DiscoverFoodEaten then pcall(ns.DiscoverFoodEaten, ns, src.id, spellId, a) end
end

-- Devuelve isXP, motivo, pct. Un "Well Fed" puede ser solo de estadísticas.
local lastClass = {} -- última clasificación conocida por aura (para cuando el tooltip está bloqueado)

-- Olvida lo concluido de los Well Fed (al terminar de comer se vuelve a revisar)
function ns:ResetFoodClass()
    wipe(lastClass)
    self:ClearTipCache()
end

function ns:ClassifyFood(spellId, a)
    -- 1) el texto del buff dice experiencia: "Experience gained from kills increased by 5%."
    local xp, pct = self:TooltipSaysXP(a)
    if xp then
        local r = { true, format(L["buff tooltip (+%d%% XP)"], pct or 5), pct }
        lastClass[spellId] = { exp = a.expirationTime, r = r }
        return r[1], r[2], r[3]
    end
    -- 2) sabemos qué comida aplicó este buff (p. ej. la elegida en la grilla).
    --    Va antes que un "no" del tooltip: recién comido, el tooltip puede venir incompleto.
    local src = self.cdb.auraSource[spellId]
    local exp = EpochExpiry(a)
    if src and exp and math.abs((src.exp or 0) - exp) <= 5 then
        local itemXP, itemPct = self:FoodGivesXP(src.itemId)
        local name = ns.GetItemName(src.itemId) or src.itemId
        if itemXP then return true, format(L["food %s"], name), itemPct end
        if itemXP == false and xp == false then return false, format(L["food without XP (%s)"], name) end
    end
    -- 3) el tooltip completo no menciona experiencia
    if xp == false then
        local r = { false, L["Well Fed without XP (stats only)"] }
        lastClass[spellId] = { exp = a.expirationTime, r = r }
        return false, r[2]
    end
    -- 4) tooltip no disponible (combate/cargando): lo último que se supo de este buff
    local last = lastClass[spellId]
    if last and last.exp == a.expirationTime then return last.r[1], last.r[2], last.r[3] end
    return false, L["checking..."]
end

-- /cxp food: muestra cómo se clasificó cada "Well Fed"
function ns:DebugFood()
    local any = false
    for spellId, a in pairs(self.auras) do
        local e = self.db.entries[spellId]
        if NAME_RULES[a.name] == "food" or (e and e.cat == "food") then
            any = true
            local isXP, why = self:ClassifyFood(spellId, a)
            self.Print(format("%s (%d): %s · %s", a.name or "?", spellId,
                isXP and ("|cff40ff40" .. L["XP FOOD"] .. "|r") or ("|cffff4040" .. L["NORMAL"] .. "|r"), why))
            for _, l in ipairs(self:GetAuraTooltipLines(a)) do
                print("    |cffaaaaaa" .. l .. "|r")
            end
        end
    end
    if not any then self.Print(L["You have no food buff active."]) end
end

-- Buffs sin ítem: intenta encontrarlo en las bolsas por su efecto "Usar"
function ns:AutoMatchItems()
    for spellId, e in pairs(self.db.entries) do
        e.items = e.items or {}
        if e.cat == "sleepingbag" and not next(e.items) then
            local id = self:MatchItemForAura(spellId, e.name)
            if id then e.items[id] = true end
        end
    end
end

function ns:ApplyBuiltins()
    -- la opción de quitar buffs ya no existe en la interfaz: los de fábrica siempre van
    self.db.removed = {}
    -- dev builds registered the "eating" spell as the food aura
    self.db.entries[1243969] = nil
    for spellId, b in pairs(self.BUILTIN) do
        if not self.db.entries[spellId] and not self.db.removed[spellId] then
            self.db.entries[spellId] = { cat = b.cat, name = b.name, enabled = true, items = {}, builtin = true }
        end
    end
    -- 1.0.1: versiones anteriores asociaban "el último ítem usado" al campamento/saco
    -- (p. ej. comer junto a la fogata). Se borran una vez; vuelven solo los que coincidan.
    if (self.db.itemsFix or 0) < 1 then
        for _, e in pairs(self.db.entries) do
            if e.cat == "campfire" or e.cat == "sleepingbag" then e.items = {} end
        end
        self.db.itemsFix = 1
    end
end

function ns:AddEntry(catKey, spellId, itemId, name, icon)
    if not self.CAT[catKey] or not spellId then return end
    local e = self.db.entries[spellId] or { items = {} }
    e.items = e.items or {}
    e.cat = catKey
    e.enabled = true
    e.name = name or e.name or ns.GetSpellName(spellId) or tostring(spellId)
    e.icon = icon or e.icon or ns.GetSpellIcon(spellId)
    if itemId then e.items[itemId] = true end
    self.db.entries[spellId] = e
    self:FullUpdate()
end

-- Estado por categoría ----------------------------------------------------
-- fases: active, expiring, missing_have, missing_none, unconfigured, disabled
ns.state = {}
for _, c in ipairs(ns.CATEGORIES) do
    ns.state[c.key] = { phase = "unconfigured", count = 0, remaining = 0, items = {} }
end

function ns:ComputeState()
    local now = GetTime()
    for _, c in ipairs(self.CATEGORIES) do
        local s = self.state[c.key]
        s.active, s.expires, s.duration, s.auraIcon, s.auraName = false, 0, 0, nil, nil
        s.count, s.itemId, s.hasEntries, s.foodReason, s.stacks = 0, nil, false, nil, 0
        s.xpPct, s.aura, s.statText = nil, nil, nil
        wipe(s.items)
    end

    for spellId, e in pairs(self.db.entries) do
        local s = self.state[e.cat]
        if s and e.enabled ~= false then
            s.hasEntries = true
            local a = self.auras[spellId]
            -- con auras bloqueadas los datos pueden ser viejos: descarta lo ya expirado
            if a and a.expirationTime > 0 and a.expirationTime < now then a = nil end
            if a and e.cat == "food" then
                if self:IsEndgame() then
                    -- End Game: cuenta cualquier Well Fed; se muestra la estadística que da
                    s.statText = self:AuraStatText(a) or s.statText
                else
                    -- Leveling: un "Well Fed" de comida normal no cuenta como buff de XP
                    local isXP, why, pct = self:ClassifyFood(spellId, a)
                    s.foodReason = why
                    if isXP then s.xpPct = pct or s.xpPct else a = nil end
                end
            end
            if a then
                s.active = true
                local exp = (a.expirationTime and a.expirationTime > 0) and a.expirationTime or math.huge
                if exp > s.expires then
                    s.expires, s.duration, s.auraIcon, s.auraName = exp, a.duration, a.icon, a.name
                    s.stacks = a.stacks or 0
                    s.aura = a
                end
            end
            -- la comida no usa ítems asociados: sale del tooltip (abajo)
            if e.items and e.cat ~= "food" then
                for itemId in pairs(e.items) do s.items[itemId] = true end
            end
        end
    end

    -- saco: los sacos de dormir conocidos (además de los detectados por su "Use:")
    for _, id in ipairs(self.SLEEPING_BAGS) do self.state.sleepingbag.items[id] = true end

    -- campamento: lo que lo arma son los kits de fogata
    local camp = self.state.campfire
    wipe(camp.items)
    for _, id in ipairs(self.CAMP_KITS) do camp.items[id] = true end

    -- comida: en Leveling las que dan XP; en End Game las que dan Well Fed
    local food = self.state.food
    local endgame = self:IsEndgame()
    for id in pairs(bagSnapshot) do
        if ns.IsFoodItem(id) then
            if endgame then
                if self:FoodGivesWellFed(id) then food.items[id] = true end
            elseif self:FoodGivesXP(id) then
                food.items[id] = true
            end
        end
    end

    -- saco (y otros): el % real sale del tooltip del buff; de ahí también los stacks
    for _, c in ipairs(self.CATEGORIES) do
        local s = self.state[c.key]
        if s.aura and c.key ~= "food" then
            local xp, pct = self:TooltipSaysXP(s.aura)
            if xp and pct then s.xpPct = pct end
        end
        if c.perStack and s.active and (s.stacks or 0) == 0 and s.xpPct then
            local per = (self.XP_RULES[c.key] and self.XP_RULES[c.key].all) or 1
            s.stacks = math.floor(s.xpPct / per + 0.5)
        end
    end

    local warn = self.cdb.warnSec
    for _, c in ipairs(self.CATEGORIES) do
        local s = self.state[c.key]
        local best, bestN = nil, 0
        for itemId in pairs(s.items) do
            local n = ns.GetItemCount(itemId)
            s.count = s.count + n
            if n > bestN then best, bestN = itemId, n end
        end
        s.itemId = best
        -- comida: la última que elegiste en la grilla, si aún te queda; la favorita manda
        if c.key == "food" and self.cdb.foodChoice and s.items[self.cdb.foodChoice]
            and ns.GetItemCount(self.cdb.foodChoice) > 0 then
            s.itemId = self.cdb.foodChoice
        end
        if c.key == "food" then
            for itemId in pairs(s.items) do
                if self:IsFavorite(itemId) and ns.GetItemCount(itemId) > 0 then s.itemId = itemId break end
            end
            -- comida preferida (menú del ícono): manda sobre todo lo demás mientras te quede
            local pref = self.cdb.foodPreferred
            if pref and ns.GetItemCount(pref) > 0 then s.itemId = pref end
        end
        s.remaining = s.active and (s.expires - now) or 0

        -- saco: bloqueado sin su misión y oculto en End Game (solo da XP);
        -- consumibles: solo existen en End Game
        if c.key == "sleepingbag" then
            s.locked = endgame or not self:SleepingBagUnlocked()
        elseif c.endgameOnly then
            s.locked = not endgame
        else
            s.locked = false
        end
        if not self.cdb.enabled[c.key] or s.locked then
            s.phase = "disabled" -- desactivado por el usuario o aún bloqueado (saco sin misión)
        elseif not s.hasEntries then
            s.phase = "unconfigured"
        elseif s.active then
            s.phase = (s.remaining <= warn) and "expiring" or "active"
        elseif s.count > 0 then
            s.phase = "missing_have"
        else
            s.phase = "missing_none"
        end
    end

    -- consumibles vigilados: estado propio (Endgame.lua)
    local cons = self.state.consumables
    if cons.phase ~= "disabled" then self:ComputeConsumables(cons, now) end
end

-- Avisos ------------------------------------------------------------------
-- Sonidos para elegir (el primero = el propio de cada buff)
ns.SOUNDS = {
    { key = "default", label = "Buff's own sound" },
    { key = "raid",    label = "Raid Warning",   id = SK("RAID_WARNING", 8959) },
    { key = "ready",   label = "Ready Check",    id = SK("READY_CHECK", 8960) },
    { key = "alarm",   label = "Alarm Clock",    id = SK("ALARM_CLOCK_WARNING_3", 12889) },
    { key = "levelup", label = "Level Up",       id = SK("LEVELUP", 888) },
    { key = "quest",   label = "Quest Complete", id = SK("IG_QUEST_LIST_COMPLETE", 878) },
    { key = "ping",    label = "Map Ping",       id = SK("MAP_PING", 3175) },
    { key = "whisper", label = "Whisper",        id = SK("TELL_MESSAGE", 3081) },
}

-- Sonido de un aviso: "por expirar", "consumibles" o el resto (falta, se acabó...)
function ns:SoundFor(kind, c)
    local key
    if kind == "expiring" then key = self.cdb.soundExpiring
    elseif kind == "consumables" then key = self.cdb.soundConsumables
    else key = self.cdb.soundMissing end
    for _, snd in ipairs(ns.SOUNDS) do
        if snd.key == key and snd.id then return snd.id end
    end
    return c and c.sound
end

-- Texto grande propio (posición y tamaño configurables); hasta 3 líneas que se desvanecen
local alertFrame
function ns:ShowBigAlert(msg, r, g, b)
    if not alertFrame then
        alertFrame = CreateFrame("Frame", "CampXPAlert", UIParent)
        alertFrame:SetSize(900, 110)
        alertFrame:SetFrameStrata("HIGH")
        alertFrame.lines = {}
        for i = 1, 3 do
            local fs = alertFrame:CreateFontString(nil, "OVERLAY")
            fs:SetFont(STANDARD_TEXT_FONT, 22, "THICKOUTLINE")
            fs:SetPoint("TOP", 0, -(i - 1) * 32)
            fs:SetWidth(900)
            fs:SetAlpha(0)
            alertFrame.lines[i] = { fs = fs, t = 0 }
        end
        alertFrame:SetScript("OnUpdate", function(self)
            local now = GetTime()
            for _, l in ipairs(self.lines) do
                local age = now - l.t
                l.fs:SetAlpha(age < 3 and 1 or math.max(0, 1 - (age - 3)))
            end
        end)
    end
    local f = alertFrame
    f:ClearAllPoints()
    if self.cdb.alertPos == "center" then
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    end
    f:SetScale((self.cdb.alertSize or 100) / 100)
    -- el nuevo arriba; los anteriores bajan una línea
    for i = 3, 2, -1 do
        local a, bb = f.lines[i], f.lines[i - 1]
        a.fs:SetText(bb.fs:GetText() or "")
        a.fs:SetTextColor(bb.fs:GetTextColor())
        a.t = bb.t
    end
    f.lines[1].fs:SetText(msg)
    f.lines[1].fs:SetTextColor(r or 1, g or 0.82, b or 0)
    f.lines[1].t = GetTime()
    f:Show()
end

-- Entrega un aviso por los canales elegidos
function ns:Notify(msg, sound, flashKey, color, big)
    local cdb = self.cdb
    color = color or { 1, 0.82, 0 }
    if cdb.alerts and big ~= false then self:ShowBigAlert(msg, color[1], color[2], color[3]) end
    if cdb.chatAlerts ~= false then self.Print(msg) end
    if cdb.sound and sound then PlaySound(sound, "Master") end
    if cdb.flashAlerts ~= false and flashKey and self.Display then self.Display:Flash(flashKey) end
end

function ns:SuppressReason()
    local sp = self.cdb.suppress
    if sp.dead ~= false and Bool(UnitIsDeadOrGhost, "player") then return "dead" end
    if sp.taxi ~= false and Bool(UnitOnTaxi, "player") then return "taxi" end
    if sp.afk and Bool(UnitIsAFK, "player") then return "afk" end
    if sp.instance and not self:IsEndgame() and Bool(IsInInstance) then return "instance" end
    if sp.combat and (Bool(InCombatLockdown) or Bool(UnitAffectingCombat, "player")) then return "combat" end
    if sp.resting and Bool(IsResting) then return "resting" end
    if sp.mounted and Bool(IsMounted) then return "mounted" end
end

local function BuildMsg(c, s, kind)
    if kind == "expiring" then
        return format(L["%s ends in %s"], c.label, ns.FormatTime(s.remaining))
    elseif kind == "missing" then
        return format(L["%s missing: you have %d in your bags (click the icon)"], c.label, s.count)
    elseif kind == "expired_none" then
        return format(L["%s ran out and you have none left"], c.label)
    elseif kind == "lowstock" then
        return format(L["%s: only %d left"], c.label, s.count)
    elseif kind == "maxstacks" then
        local kill, quest = ns:XPBonus(c.key, false)
        return format(L["%s: max stacks (+%d%% kills, +%d%% quests), you can get up now"], c.label, kill, quest)
    end
    return format(L["%s: test alert"], c.label)
end

-- s opcional: estado de ejemplo (botones de prueba)
function ns:Alert(c, kind, s)
    s = s or self.state[c.key]
    local msg = BuildMsg(c, s, kind)
    local color = (kind == "expiring") and { 1, 0.55, 0.15 } or { 1, 0.82, 0 }
    self:Notify(msg, self:SoundFor(kind, c), c.key, color)
end

function ns:ProcessAlerts(silent)
    local now = GetTime()
    local reason = self:SuppressReason()
    local phaseChanged = false

    for _, c in ipairs(self.CATEGORIES) do
        local s = self.state[c.key]
        local phase, last = s.phase, s.lastPhase

        if silent then
            s.lastPhase, s.lastRemind, s.prevCount, s.pending = phase, now, s.count, nil
            s.prevStacks = s.stacks
        else
            -- saco: llegó al máximo de stacks
            if c.perStack and s.active and (s.stacks or 0) >= c.maxStacks
                and (s.prevStacks or 0) < c.maxStacks then
                s.pending = s.pending or "maxstacks"
            end
            s.prevStacks = s.stacks


            if phase ~= last then
                phaseChanged = true
                if phase == "expiring" then
                    s.pending = "expiring"
                elseif phase == "missing_have" then
                    s.pending = "missing"
                    s.lastRemind = now
                elseif phase == "missing_none" and (last == "active" or last == "expiring") then
                    s.pending = "expired_none"
                else
                    s.pending = nil
                end
                s.lastPhase = phase
            elseif phase == "missing_have" and self.cdb.remindMin > 0
                and now - (s.lastRemind or now) >= self.cdb.remindMin * 60 then
                s.pending = "missing"
                s.lastRemind = now
            end

            -- stock bajo
            if s.prevCount and s.count < s.prevCount and s.count > 0
                and s.count <= self.cdb.lowStock and phase ~= "disabled" then
                s.pending = s.pending or "lowstock"
            end
            s.prevCount = s.count

            -- se dispara cuando no hay combate/ciudad/montura; si no, queda en espera
            if c.key == "consumables" then s.pending = nil end -- avisa en instancia/ready check
            if s.pending and not self:AlertOn(c.key, s.pending) then
                s.pending = nil -- desactivado en /cxp
            end
            -- "stacks completos" no espera: estás quieto sobre el saco
            local now_ok = not reason or s.pending == "maxstacks"
            if s.pending and now_ok then
                self:Alert(c, s.pending)
                s.pending = nil
            end
        end
    end

    if phaseChanged and self.Display then self.Display:UpdateSecure() end
end

function ns:Summary(header, onlyIfActionable)
    local parts, actionable = {}, false
    for _, c in ipairs(self.CATEGORIES) do
        local s = self.state[c.key]
        if s.phase ~= "disabled" and s.phase ~= "unconfigured" and c.key ~= "consumables" then
            local st
            if s.active then
                st = "|cff40ff40" .. ns.FormatTime(s.remaining) .. "|r"
            else
                st = "|cffff4040" .. L["no buff"] .. "|r"
            end
            if s.phase == "missing_have" then actionable = true end
            table.insert(parts, format(L["%s: %s (%d in bags)"], c.label, st, s.count))
        end
    end
    if onlyIfActionable and not actionable then return end
    if #parts == 0 then
        self.Print(L["No buffs tracked."])
        return
    end
    self.Print((header or "") .. table.concat(parts, " · "))
end

function ns:TestAlerts()
    local i = 0
    for _, c in ipairs(self.CATEGORIES) do
        if not c.endgameOnly then
            C_Timer.After(i * 1.5, function() ns:Alert(c, "test") end)
            i = i + 1
        end
    end
end

-- Probar un tipo de aviso concreto (pestaña Notificaciones), con datos de ejemplo
function ns:TestAlert(kind)
    if kind == "consumables" then
        self:Notify(L["Consumables"] .. ": |cffff4040" .. L["Missing: "] .. "|r" .. L["Flask"] .. " · |cffff9933"
            .. L["Expiring: "] .. "|r" .. L["Strength"] .. " (4m)", self:SoundFor("consumables", self.CAT.consumables),
            "consumables", { 1, 0.6, 0.1 })
        return
    end
    local c = self.CAT[kind == "maxstacks" and "sleepingbag" or "food"]
    local sample = { remaining = 95, count = (kind == "lowstock") and 2 or 8, stacks = 3, active = true }
    self:Alert(c, kind, sample)
end

function ns:FullUpdate()
    self:ComputeState()
    if self.Display then self.Display:UpdateSecure(); self.Display:Update() end
    if self.XPBar then self.XPBar:Update(true) end
    if self.Config then self.Config:Refresh(); self.Config:UpdateMinimap() end
end

function ns:Tick()
    -- red de seguridad: relee las auras cada 5 s aunque el juego no avise cambios
    local now = GetTime()
    if now - (self.lastFullScan or 0) >= 5 then
        self.lastFullScan = now
        self.dirtyAuras = true
    end
    if self.dirtyAuras then
        self.dirtyAuras = false
        self:ScanAuras()
    end
    self:ComputeState()
    self:ProcessAlerts()
    if self.Display then self.Display:Update() end
    if self.XPBar then self.XPBar:Update() end
    if self.Config then self.Config:UpdateMinimap() end
end

-- Eventos -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, ...)
    local fn = ns[event]
    if fn then fn(ns, ...) end
end)

function ns:ADDON_LOADED(name)
    if name ~= ADDON then return end
    CampXPDB = Merge(CampXPDB or {}, DEFAULTS)
    CampXPCharDB = Merge(CampXPCharDB or {}, CHAR_DEFAULTS)
    self.db, self.cdb = CampXPDB, CampXPCharDB
    -- settings left over from development builds
    self.cdb.learn, self.cdb.bonus, self.db.candidates, self.db.ignored = nil, nil, nil, nil
    self:ApplyBuiltins()
    for id, src in pairs(self.cdb.auraSource) do
        if (src.exp or 0) < time() then self.cdb.auraSource[id] = nil end
    end
    ev:UnregisterEvent("ADDON_LOADED")
    ev:RegisterEvent("PLAYER_LOGIN")
end

function ns:PLAYER_LOGIN()
    HookItemUse()
    bagSnapshot = CountBags()
    self:AutoMatchItems()
    self:ScanAuras()
    -- buffs ya activos al loguear con un nombre conocido (otra variante de Well Fed, etc.)
    for spellId, a in pairs(self.auras) do
        local cat = a.name and NAME_RULES[a.name]
        if cat and not self.db.entries[spellId] then
            self:AddEntry(cat, spellId, nil, a.name, a.icon)
        end
    end

    if self.Display then self.Display:Create() end
    if self.XPBar then self.XPBar:Create() end
    if self.Config then self.Config:CreateMinimapButton() end

    self:ComputeState()
    self:ProcessAlerts(true) -- inicializa fases sin avisar
    self:FullUpdate()

    ev:RegisterUnitEvent("UNIT_AURA", "player")
    ev:RegisterEvent("BAG_UPDATE_DELAYED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("QUEST_TURNED_IN")
    ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    ev:RegisterEvent("PLAYER_XP_UPDATE")
    ev:RegisterEvent("PLAYER_UPDATE_RESTING")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    for event in pairs(INTERACT_EVENTS) do
        if C_EventUtils == nil or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(event) then
            ev:RegisterEvent(event)
            ns[event] = function(self) self:OnInteraction(event) end
        end
    end

    C_Timer.NewTicker(0.2, function() ns:Tick() end)
end

function ns:UNIT_AURA()
    self.dirtyAuras = true
end

function ns:BAG_UPDATE_DELAYED()
    local now = CountBags()
    for id, old in pairs(bagSnapshot) do
        if (now[id] or 0) < old and GetTime() - lastItemUse.t > 1 then
            ns.NoteItemUse(id)
        end
    end
    bagSnapshot = now
    self:ComputeState()
    if self.Display then self.Display:UpdateSecure() end
    if self.Config then self.Config:Refresh() end
    -- grilla abierta: recalcular posiciones de stacks (la bolsa cambió)
    local D = self.Display
    if D and D.picker and D.picker:IsShown() and not InCombatLockdown() then D:BuildPicker() end
end

-- misión del saco entregada: mostrar su icono
function ns:QUEST_TURNED_IN(questId)
    if questId == self.SLEEPING_BAG_QUEST then
        self.bagUnlocked = true
        C_Timer.After(0.5, function() ns:FullUpdate() end)
    end
end

function ns:PLAYER_REGEN_DISABLED()
    -- la grilla tiene botones seguros: se cierra antes de que empiece el bloqueo
    if self.Display then self.Display:HideFoodPicker(true) end
end

function ns:PLAYER_REGEN_ENABLED()
    self.dirtyAuras = true -- relee auras al salir de combate
    if self.Display then self.Display:UpdateSecure() end
end

-- tooltip de un ítem que no estaba en caché: refresca grilla y estado
function ns:GET_ITEM_INFO_RECEIVED()
    if self.Display and self.Display.picker and self.Display.picker:IsShown() and not InCombatLockdown() then
        self.Display:BuildFoodPicker()
    end
end

function ns:PLAYER_XP_UPDATE()
    if self.XPBar then self.XPBar:OnXP() end
end

function ns:PLAYER_LEVEL_UP(level)
    if self.XPBar then self.XPBar:OnLevelUp(level) end
    C_Timer.After(0.5, function() ns:FullUpdate() end)
end

function ns:PLAYER_UPDATE_RESTING()
    if Bool(IsResting) then
        -- empezaste a descansar sin los 3 stacks del saco: avisar (Leveling, con saco desbloqueado)
        C_Timer.After(2, function() ns:CheckRestBag() end)
    end
    if not Bool(IsResting) then
        C_Timer.After(1, function()
            ns:ComputeState()
            ns:Summary(L["Heading out: "], true)
        end)
    end
end

function ns:CheckRestBag()
    if not self.cdb.restBagReminder or self:IsEndgame() or not Bool(IsResting) then return end
    if not self.cdb.enabled.sleepingbag or not self:SleepingBagUnlocked() then return end
    self:ComputeState()
    local s = self.state.sleepingbag
    if not s or s.count == 0 then return end
    local stacks = s.active and (s.stacks or 0) or 0
    if stacks >= 3 then return end
    self:Notify(format(L["You're resting with %d/3 Well-Rested: use your Sleeping Bag"], stacks), nil, "sleepingbag")
end

function ns:PLAYER_ENTERING_WORLD(isLogin, isReload)
    -- tras login/reload/cambio de zona las auras llegan con retraso: releer varias veces
    self.dirtyAuras = true
    for _, t in ipairs({ 1, 3, 6 }) do
        C_Timer.After(t, function() ns.dirtyAuras = true end)
    end
    if isLogin then
        C_Timer.After(6, function()
            ns:ComputeState()
            ns:Summary(L["Summary: "])
        end)
    end
end

-- Slash commands -----------------------------------------------------------
SLASH_CAMPXP1 = "/campxp"
SLASH_CAMPXP2 = "/cxp"
SlashCmdList.CAMPXP = function(msg)
    local cmd = strsplit(" ", strtrim(msg or ""):lower())
    if cmd == "" or cmd == "config" then
        if ns.Config then ns.Config:Toggle() end
    elseif cmd == "style" then
        local nextStyle = { round = "minimal", minimal = "classic", classic = "round" }
        ns.cdb.iconStyle = nextStyle[ns.cdb.iconStyle] or "round"
        if ns.Display then ns.Display:ApplyStyle(); ns.Display:Update() end
        if ns.Config then ns.Config:Refresh() end
        local names = { round = L["Round"], minimal = L["Minimal"], classic = L["Classic"] }
        ns.Print(format(L["Icon style: %s"], names[ns.cdb.iconStyle]))
    elseif cmd == "xp" then
        if ns.XPBar then ns.XPBar:PrintReport() end
    elseif cmd == "food" then
        ns:DebugFood()
    elseif cmd == "status" then
        ns:ComputeState()
        ns:Summary(L["Status: "])
    elseif cmd == "test" then
        ns:TestAlerts()
    elseif cmd == "cons" then
        ns:DebugConsumables()
    elseif cmd == "db" then
        ns:DebugConsDB()
    elseif cmd == "prof" then
        ns:DebugProfessions()
    elseif cmd == "dev" then
        ns:DevCommand(select(2, strsplit(" ", strtrim(msg or ""):lower())))
    elseif cmd == "mode" then
        ns:SetMode(ns:IsEndgame() and "leveling" or "endgame")
    elseif cmd == "lock" then
        ns.cdb.locked = not ns.cdb.locked
        ns.Print(ns.cdb.locked and L["Frames locked"] or L["Frames unlocked"])
        ns:FullUpdate()
    elseif cmd == "reset" then
        if InCombatLockdown() then ns.Print(L["Not available in combat."]) return end
        wipe(ns.cdb.pos)
        if ns.Display then ns.Display:RestorePos() end
        if ns.XPBar then ns.XPBar:RestorePos() end
        ns.Print(L["Positions reset."])
    else
        ns.Print(L["Commands: /cxp (settings) · mode · style · xp · food · status · test · lock · reset"])
    end
end
