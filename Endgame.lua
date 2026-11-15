-- Modo End Game: cambio de modo, estadística de la comida y consumibles vigilados
local ADDON, ns = ...
local L = ns.L
local format = string.format

ns.MAX_LEVEL = 60
local CONSUMABLE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
-- subclases de Consumible que entran en la grilla (fuera: 5 comida/bebida, 7 vendas)
local CONS_SUBCLASS = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true, [8] = true }
local ENHANCEMENT_SUBCLASS = 6 -- aceites y piedras de arma (encantamiento temporal)
local MAIN_HAND_SLOT = 16
local LEARN_WINDOW = 10        -- s tras usar un consumible para asociar el aura nueva

local issecret = issecretvalue or function() return false end
local ItemInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemSpellFn = (C_Item and C_Item.GetItemSpell) or GetItemSpell

------------------------------------------------------------------------------
-- Modo
------------------------------------------------------------------------------
function ns:IsEndgame()
    return self.cdb ~= nil and self.cdb.mode == "endgame"
end

-- En End Game la comida ya no es "Comida XP"
function ns:ApplyModeLabels()
    self.CAT.food.label = self:IsEndgame() and L["Food"] or L["XP Food"]
end

function ns:SetMode(mode)
    if mode ~= "endgame" then mode = "leveling" end
    self.cdb.mode = mode
    self.cdb.endgameAsked = true
    self:ApplyModeLabels()
    if self.Display and not InCombatLockdown() then self.Display:HideFoodPicker(true) end
    self:FullUpdate()
    self.Print(mode == "endgame" and L["Mode: End Game"] or L["Mode: Leveling"])
end

StaticPopupDialogs["CAMPXP_ENDGAME"] = {
    text = L["CampXP: you reached level %d.\nSwitch to End Game mode?\n\n|cffaaaaaaHides the Sleeping Bag and XP tracking, shows food stats and adds a Consumables icon.|r"],
    button1 = L["Enable"],
    button2 = L["Not now"],
    OnAccept = function() ns:SetMode("endgame") end,
    OnCancel = function()
        ns.cdb.endgameAsked = true
        ns.Print(L["You can switch modes anytime in /cxp or with /cxp mode."])
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns:OfferEndgame(level)
    level = level or UnitLevel("player")
    if self:IsEndgame() or self.cdb.endgameAsked or level < self.MAX_LEVEL then return end
    StaticPopup_Show("CAMPXP_ENDGAME", level)
end

------------------------------------------------------------------------------
-- Estadísticas del Well Fed → texto corto ("+6 Sta/Spi")
------------------------------------------------------------------------------
-- Orden importa: las frases largas primero; lo ya reconocido se borra del texto
local STAT_WORDS = {
    enUS = {
        { "spell damage and healing", "SP" }, { "spell power", "SP" }, { "spell damage", "SP" },
        { "attack power", "AP" }, { "critical strike", "Crit" }, { "hit rating", "Hit" },
        { "chance to hit", "Hit" }, { "mana every 5", "MP5" }, { "mana per 5", "MP5" },
        { "health every 5", "HP5" }, { "health per 5", "HP5" }, { "healing", "Heal" },
        { "intellect", "Int" }, { "stamina", "Sta" }, { "spirit", "Spi" },
        { "strength", "Str" }, { "agility", "Agi" }, { "armor", "Armor" },
        { "haste", "Haste" }, { "dodge", "Dodge" }, { "defense", "Def" },
    },
    esES = {
        { "daño y sanación de hechizos", "SP" }, { "poder con hechizos", "SP" }, { "daño con hechizos", "SP" },
        { "poder de ataque", "AP" }, { "golpe crítico", "Crit" }, { "índice de golpe", "Hit" },
        { "maná cada 5", "MP5" }, { "salud cada 5", "HP5" }, { "sanación", "Heal" },
        { "intelecto", "Int" }, { "aguante", "Sta" }, { "espíritu", "Spi" },
        { "fuerza", "Str" }, { "agilidad", "Agi" }, { "armadura", "Armor" },
        { "celeridad", "Haste" }, { "esquivar", "Dodge" }, { "defensa", "Def" },
    },
}
STAT_WORDS.enGB = STAT_WORDS.enUS
STAT_WORDS.esMX = STAT_WORDS.esES
local STATS = {}
for _, loc in ipairs({ STAT_WORDS[ns.locale] or STAT_WORDS.enUS, STAT_WORDS.enUS }) do
    for _, w in ipairs(loc) do table.insert(STATS, w) end
    if loc == STAT_WORDS.enUS then break end
end
local WELL_FED_WORDS = { "well fed", "bien alimentado" }

-- Números que no son el valor de la estadística: duraciones y "cada 5 s"
local function IsNoise(text, s, e)
    local before = text:sub(math.max(1, s - 7), s - 1)
    if before:find("every%s*$") or before:find("cada%s*$") or before:find("per%s*$") then return true end
    local after = text:sub(e + 1, e + 8)
    return after:find("^%s*min") or after:find("^%s*sec") or after:find("^%s*seg")
        or after:find("^%s*hour") or after:find("^%s*hora") or after:find("^%s*s%f[%A]")
end

-- Valor más cercano a la estadística: primero detrás ("Stamina by 6"), si no delante ("+6 Stamina")
local function NumberNear(text, ks, ke)
    local pos = ke + 1
    while true do
        local s, e, n = text:find("(%d+%%?)", pos)
        if not s or s - ke > 28 then break end
        if not IsNoise(text, s, e) then return n end
        pos = e + 1
    end
    local best
    pos = math.max(1, ks - 18)
    while true do
        local s, e, n = text:find("(%d+%%?)", pos)
        if not s or s >= ks then break end
        if not IsNoise(text, s, e) then best = n end
        pos = e + 1
    end
    return best
end

-- "Increases Stamina and Spirit by 6 for 15 min." → "+6 Sta/Spi"
function ns.ParseStats(text)
    if not text or text == "" then return nil end
    local low = text:lower()
    local found = {}
    for _, w in ipairs(STATS) do
        local s, e = low:find(w[1], 1, true)
        while s do
            -- palabra completa ("hit" no debe coincidir dentro de otra palabra)
            local okL = s == 1 or not low:sub(s - 1, s - 1):find("%a")
            local okR = not low:sub(e + 1, e + 1):find("%a")
            if okL and okR then
                table.insert(found, { pos = s, abbr = L[w[2]], n = NumberNear(low, s, e) })
                low = low:sub(1, s - 1) .. string.rep(" ", e - s + 1) .. low:sub(e + 1)
            end
            s, e = low:find(w[1], e + 1, true)
        end
    end
    if #found == 0 then return nil end
    table.sort(found, function(a, b) return a.pos < b.pos end)
    -- agrupa por valor: "+6 Sta/Spi", "+8 AP +4 Crit"
    local groups, order = {}, {}
    for _, f in ipairs(found) do
        local k = f.n or "?"
        if not groups[k] then groups[k] = {}; table.insert(order, k) end
        local dup = false
        for _, a in ipairs(groups[k]) do if a == f.abbr then dup = true end end
        if not dup then table.insert(groups[k], f.abbr) end
    end
    local parts = {}
    for _, k in ipairs(order) do
        local names = table.concat(groups[k], "/")
        table.insert(parts, k == "?" and names or ("+" .. k .. " " .. names))
    end
    return table.concat(parts, " ")
end

-- Texto de estadísticas del aura activa (sin la frase de XP)
local auraStatCache = {}
local function StripXP(lines)
    local keep = {}
    for i, l in ipairs(lines) do
        -- la 1ª línea es el nombre del aura; las de XP no son estadística
        if i > 1 and not ns.ParseXP(l) then table.insert(keep, l) end
    end
    return table.concat(keep, " ")
end

function ns:AuraStatText(a)
    local key = tostring(a.auraInstanceID or 0) .. ":" .. tostring(a.expirationTime)
    if auraStatCache[key] ~= nil then return auraStatCache[key] or nil end
    local lines = self:GetAuraTooltipLines(a)
    if #lines < 2 then return nil end -- aún sin descripción
    local txt = ns.ParseStats(StripXP(lines))
    auraStatCache[key] = txt or false
    return txt
end

-- Comida: ¿da Well Fed? (true/false, nil = tooltip aún sin cargar) y su texto corto
local wfCache, wfStat = {}, {}
local USE_PREFIX = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
function ns:FoodGivesWellFed(id)
    if wfCache[id] ~= nil then return wfCache[id], wfStat[id] end
    local ok, lines = pcall(ns.ItemTooltipLines, id)
    if not ok or not lines then return nil end
    local useText
    for _, l in ipairs(lines) do
        local low = l:lower()
        if low:sub(1, #USE_PREFIX) == USE_PREFIX and #low > #USE_PREFIX + 10 then useText = l break end
    end
    if not useText then return nil end
    local low = useText:lower()
    local wf = false
    for _, w in ipairs(WELL_FED_WORDS) do
        if low:find(w, 1, true) then wf = true end
    end
    -- la frase del Use: suele ser "...you will become well fed and gain 6 Stamina..."
    local parts = {}
    for sentence in (useText .. "."):gmatch("([^%.]+)%.") do
        if not ns.ParseXP(sentence) then table.insert(parts, sentence) end
    end
    local stat = ns.ParseStats(table.concat(parts, ". "))
    if stat then wf = true end
    wfCache[id], wfStat[id] = wf, stat
    return wf, stat
end

------------------------------------------------------------------------------
-- Consumibles
------------------------------------------------------------------------------
local function UseSpell(id)
    if not GetItemSpellFn then return nil end
    local name, spellId = GetItemSpellFn(id)
    return name, spellId
end

local function IsCampItem(id)
    for _, list in ipairs({ ns.CAMP_KITS, ns.CAMP_FEATURES, ns.SLEEPING_BAGS }) do
        for _, x in ipairs(list or {}) do if x == id then return true end end
    end
    return false
end

-- Clave de vigilancia de un ítem: "weapon" para aceites/piedras, "spell:<nombre>" para el resto
function ns:ConsumableKey(id)
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    if classID == CONSUMABLE_CLASS and subClassID == ENHANCEMENT_SUBCLASS then return "weapon", true end
    local name, spellId = UseSpell(id)
    if name and not issecret(name) then return "spell:" .. name, false, name, spellId end
    return "item:" .. id, false
end

function ns.IsConsumableItem(id)
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    if classID ~= CONSUMABLE_CLASS or not CONS_SUBCLASS[subClassID] then return false end
    if IsCampItem(id) then return false end
    return UseSpell(id) ~= nil
end

function ns:IsTrackedItem(id)
    local key = self:ConsumableKey(id)
    local t = self.cdb.endgame.tracked[key]
    return t ~= nil and t.items[id] == true
end

-- Consumibles de las bolsas: { {id, count, tracked, weapon}, ... } vigilados primero
function ns:GetBagConsumables()
    local list = {}
    for id, count in pairs(ns.GetBagSnapshot()) do
        if ns.IsConsumableItem(id) then
            local _, weapon = self:ConsumableKey(id)
            table.insert(list, { id = id, count = count, tracked = self:IsTrackedItem(id), weapon = weapon })
        end
    end
    table.sort(list, function(a, b)
        if a.tracked ~= b.tracked then return a.tracked end
        return (ns.GetItemName(a.id) or "") < (ns.GetItemName(b.id) or "")
    end)
    return list
end

-- Clic derecho en la grilla: vigilar / dejar de vigilar
function ns:ToggleTrack(id)
    local tracked = self.cdb.endgame.tracked
    local key, weapon, spellName, spellId = self:ConsumableKey(id)
    local t = tracked[key]
    local name = ns.GetItemName(id) or format(L["Item %d"], id)
    if t and t.items[id] then
        t.items[id] = nil
        if next(t.items) == nil then tracked[key] = nil end
        self.Print(format(L["No longer tracking %s"], name))
    else
        if not t then
            t = { items = {}, weapon = weapon or nil, spellName = spellName, spellId = spellId,
                  label = weapon and L["Weapon enchant"] or (spellName or name) }
            tracked[key] = t
        end
        t.items[id] = true
        self.Print(format(L["Tracking %s"], name))
    end
    self:FullUpdate()
end

-- Avisos por buff vigilado (menú del clic derecho): missing / expiring / lowstock
ns.CONS_ALERTS = {
    { key = "missing",  label = L["Buff missing"] },
    { key = "expiring", label = L["Little time left"] },
    { key = "lowstock", label = L["Low stock"] },
}

function ns:TrackedFor(id)
    local key = self:ConsumableKey(id)
    local t = self.cdb.endgame.tracked[key]
    if t and t.items[id] then return t, key end
end

function ns:ConsAlertOn(t, kind)
    return not (t.alerts and t.alerts[kind] == false)
end

function ns:SetConsAlert(t, kind, on)
    t.alerts = t.alerts or {}
    t.alerts[kind] = on and true or false
end

-- Al usar desde la grilla: recordar qué auras ya había para asociar la nueva
local pendingUse
function ns:NoteConsumableUse(id)
    local key, weapon = self:ConsumableKey(id)
    if weapon then return end
    local before = {}
    for _, a in pairs(self.auras) do
        if a.auraInstanceID then before[a.auraInstanceID] = true end
    end
    pendingUse = { key = key, t = GetTime(), before = before }
end

local function IsOurAura(name)
    return name and ns.LOC.auraNames[name] ~= nil
end

-- ¿Está puesto el buff de este vigilado? Devuelve activo, restante (s), aura
local function TrackedAura(self, key, t, now)
    if t.weapon then
        local has, expMs = GetWeaponEnchantInfo()
        if has then return true, (expMs or 0) / 1000 end
        return false, 0
    end
    local best, bestRem
    for spellId, a in pairs(self.auras) do
        local match = (t.spellId and spellId == t.spellId) or (t.auraSpell and spellId == t.auraSpell)
            or (a.name and (a.name == t.spellName or a.name == t.auraName))
        if match then
            local rem = (a.expirationTime and a.expirationTime > 0) and (a.expirationTime - now) or math.huge
            if rem > 0 and (not bestRem or rem > bestRem) then best, bestRem = a, rem end
        end
    end
    if best then return true, bestRem, best end
    return false, 0
end

-- Asociación aprendida: el aura nueva que apareció tras usarlo desde la grilla
local function LearnAura(self, now)
    if not pendingUse or now - pendingUse.t > LEARN_WINDOW then pendingUse = nil return end
    local t = self.cdb.endgame.tracked[pendingUse.key]
    if not t then pendingUse = nil return end
    if TrackedAura(self, pendingUse.key, t, now) then pendingUse = nil return end
    for spellId, a in pairs(self.auras) do
        if a.auraInstanceID and not pendingUse.before[a.auraInstanceID] and not a.fromOther
            and not IsOurAura(a.name) then
            t.auraName, t.auraSpell = a.name, spellId
            pendingUse = nil
            return
        end
    end
end

-- Estado del ícono Consumables (llamado desde ComputeState)
function ns:ComputeConsumables(s, now)
    LearnAura(self, now)
    local eg = self.cdb.endgame
    local warn = (eg.warnMin or 10) * 60
    s.trackedCount, s.activeCount = 0, 0
    s.list = {}
    local minRem, anyHave, expiring = math.huge, false, false
    for key, t in pairs(eg.tracked) do
        local count, best, bestN = 0, nil, 0
        for id in pairs(t.items) do
            local n = ns.GetItemCount(id)
            count = count + n
            if n > bestN then best, bestN = id, n end
        end
        local active, rem, aura = TrackedAura(self, key, t, now)
        local row = { key = key, t = t, label = t.label or key, active = active, remaining = rem, count = count,
                      itemId = best or next(t.items), verified = t.weapon or t.auraName ~= nil or aura ~= nil }
        if aura and not t.auraName then t.auraName = aura.name end -- coincidencia directa: queda verificado
        s.trackedCount = s.trackedCount + 1
        if active then
            s.activeCount = s.activeCount + 1
            if rem < minRem then minRem = rem end
            if rem <= warn then expiring = true; row.expiring = true end
        elseif count > 0 then
            anyHave = true
        end
        table.insert(s.list, row)
    end
    table.sort(s.list, function(a, b) return a.label < b.label end)
    s.count = s.activeCount
    s.active = s.trackedCount > 0 and s.activeCount == s.trackedCount
    s.remaining = (minRem < math.huge) and minRem or 0
    s.expires = (minRem < math.huge) and (now + minRem) or math.huge
    s.duration = nil
    if s.trackedCount == 0 then
        s.phase = "unconfigured"
    elseif s.active then
        s.phase = expiring and "expiring" or "active"
    elseif anyHave then
        s.phase = "missing_have"
    else
        s.phase = "missing_none"
    end
end

------------------------------------------------------------------------------
-- Recordatorios: al entrar a dungeon/raid y en el ready check
------------------------------------------------------------------------------
local pendingCheck, lastInstance

function ns:CheckConsumables(reason, force)
    if not self:IsEndgame() or not self.cdb.enabled.consumables then return end
    local eg = self.cdb.endgame
    if not next(eg.tracked) then return end
    -- auras protegidas: esperar a que se liberen (máx. 20 s; luego con lo último leído)
    if (ns.AurasLocked() or InCombatLockdown()) and not force then
        pendingCheck = pendingCheck or { reason = reason, t = GetTime() }
        return
    end
    pendingCheck = nil
    self:ScanAuras()
    self:ComputeState()
    local s = self.state.consumables
    local missing, expiring, low = {}, {}, {}
    for _, r in ipairs(s.list or {}) do
        if not r.active then
            if self:ConsAlertOn(r.t, "missing") then table.insert(missing, r.label) end
        elseif r.expiring then
            if self:ConsAlertOn(r.t, "expiring") then
                table.insert(expiring, format("%s (%s)", r.label, ns.FormatTime(r.remaining)))
            end
        end
        if eg.lowStock > 0 and r.count <= eg.lowStock and self:ConsAlertOn(r.t, "lowstock") then
            table.insert(low, format("%s (%d)", ns.GetItemName(r.itemId) or r.label, r.count))
        end
    end
    local parts = {}
    if #missing > 0 then table.insert(parts, "|cffff4040" .. L["Missing: "] .. "|r" .. table.concat(missing, ", ")) end
    if #expiring > 0 then table.insert(parts, "|cffff9933" .. L["Expiring: "] .. "|r" .. table.concat(expiring, ", ")) end
    if reason == "instance" and #low > 0 then
        table.insert(parts, "|cffffd100" .. L["Low stock: "] .. "|r" .. table.concat(low, ", "))
    end
    if #parts == 0 then return end
    local msg = table.concat(parts, " · ")
    local c = self.CAT.consumables
    if self.cdb.alerts and RaidNotice_AddMessage and RaidWarningFrame and (#missing + #expiring) > 0 then
        local color = (ChatTypeInfo and ChatTypeInfo["RAID_WARNING"]) or { r = 1, g = 0.8, b = 0 }
        RaidNotice_AddMessage(RaidWarningFrame, L["Consumables"] .. ": " .. msg, color)
    end
    self.Print(L["Consumables"] .. ": " .. msg)
    if self.cdb.sound and c.sound then PlaySound(c.sound, "Master") end
    if self.Display then self.Display:Flash("consumables") end
end

local function InstanceCheck()
    local inInstance, kind = IsInInstance()
    if not inInstance or (kind ~= "party" and kind ~= "raid") then
        lastInstance = nil
        return
    end
    local name, _, _, _, _, _, _, instanceId = GetInstanceInfo()
    local id = tostring(instanceId or name)
    if id == lastInstance then return end -- mismo lugar (p. ej. tras morir o /reload)
    lastInstance = id
    if ns.cdb.endgame.onInstance then ns:CheckConsumables("instance") end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ns:ApplyModeLabels()
        ev:RegisterEvent("PLAYER_LEVEL_UP")
        ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        ev:RegisterEvent("READY_CHECK")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        C_Timer.After(8, function() ns:OfferEndgame() end)
        C_Timer.NewTicker(2, function()
            -- revisión pendiente (auras protegidas o combate)
            if pendingCheck then
                local timedOut = GetTime() - pendingCheck.t > 20
                if (not ns.AurasLocked() and not InCombatLockdown()) or (timedOut and not InCombatLockdown()) then
                    ns:CheckConsumables(pendingCheck.reason, true)
                end
            end
        end)
    elseif event == "PLAYER_LEVEL_UP" then
        local level = ...
        C_Timer.After(2, function() ns:OfferEndgame(level) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(4, InstanceCheck)
    elseif event == "READY_CHECK" then
        if ns.cdb.endgame.onReadyCheck then ns:CheckConsumables("readycheck") end
    end
end)
