-- Modo End Game: cambio de modo, estadística de la comida y consumibles vigilados
local ADDON, ns = ...
local L = ns.L
local format = string.format

ns.MAX_LEVEL = 60
local CONSUMABLE_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Consumable) or 0
-- subclases de Consumible que entran en la grilla (fuera: 1 pociones, 5 comida/bebida, 7 vendas)
local CONS_SUBCLASS = { [0] = true, [2] = true, [3] = true, [4] = true, [6] = true, [8] = true }
local MIN_BUFF_MIN = 15 -- solo buffs de 15 min o más (fuera granadas, efectos cortos, etc.)
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
        { "strength", "Str" }, { "agility", "Agi" }, { "armor", "Arm" },
        { "haste", "Haste" }, { "dodge", "Dodge" }, { "defense", "Def" },
    },
    esES = {
        { "daño y sanación de hechizos", "SP" }, { "poder con hechizos", "SP" }, { "daño con hechizos", "SP" },
        { "poder de ataque", "AP" }, { "golpe crítico", "Crit" }, { "índice de golpe", "Hit" },
        { "maná cada 5", "MP5" }, { "salud cada 5", "HP5" }, { "sanación", "Heal" },
        { "intelecto", "Int" }, { "aguante", "Sta" }, { "espíritu", "Spi" },
        { "fuerza", "Str" }, { "agilidad", "Agi" }, { "armadura", "Arm" },
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
    local low = ns.CleanGameText(text):lower()
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
-- Aceites y piedras: no dejan aura, encantan el arma (GetWeaponEnchantInfo).
-- En WoW Forever no siempre vienen como subclase "Mejora de objeto": también se
-- reconocen por el texto "Usar" ("Increases sharp weapon damage...", "applied to target weapon...").
local WEAPON_WORDS = { "weapon", "arma" }
function ns.IsWeaponItem(id)
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    if classID == CONSUMABLE_CLASS and subClassID == ENHANCEMENT_SUBCLASS then return true end
    local use = ns.ItemUseText and ns.ItemUseText(id)
    if not use then return false end
    local low = use:lower()
    for _, w in ipairs(WEAPON_WORDS) do
        if low:find("%f[%a]" .. w .. "%f[%A]") then return true end
    end
    return false
end

-- Encantamientos temporales de las armas: { {slot, rem (s), enchant}, ... }
-- (mano principal, secundaria y a distancia; una imbuición de chamán o un veneno
-- también aparecen aquí, por eso cada piedra/aceite aprende su propio ID de encantamiento)
local SLOT_NAMES = { "main", "off", "ranged" }
local SLOT_IDS = { 16, 17, 18 }
local UNIT_SEC = { sec = 1, s = 1, seg = 1, min = 60, hour = 3600, hours = 3600, hr = 3600, hrs = 3600, h = 3600, hora = 3600, horas = 3600 }

-- Líneas temporales del tooltip del arma: "Sharpened +6 (27 min)", "Windfury 3 (23 min)".
-- El juego solo informa UN encantamiento temporal por arma en GetWeaponEnchantInfo,
-- pero el tooltip muestra todos (en WoW Forever la piedra y el Windfury conviven).
local function TooltipEnchants(slotId)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotId)
    if not ok or not data or not data.lines then return nil end
    local out = {}
    for _, l in ipairs(data.lines) do
        local t = l.leftText
        if t and not issecret(t) then
            t = ns.CleanGameText(t)
            local name, n, unit = t:match("^(.-)%s*%((%d+)%s*(%a+)%)%s*$")
            if name and name ~= "" and UNIT_SEC[unit:lower()] then
                out[#out + 1] = { text = name, rem = tonumber(n) * UNIT_SEC[unit:lower()] }
            end
        end
    end
    return out
end

-- Encantamientos temporales de las armas: { {slot, text, rem (s), enchant, key}, ... }
function ns.WeaponEnchants()
    local r = { GetWeaponEnchantInfo() }
    local list = {}
    for i = 0, 2 do
        local has, expMs, _, enchantId = r[i * 4 + 1], r[i * 4 + 2], r[i * 4 + 3], r[i * 4 + 4]
        local slot = SLOT_NAMES[i + 1]
        local tips = TooltipEnchants(SLOT_IDS[i + 1])
        if tips and #tips > 0 then
            for _, tl in ipairs(tips) do
                local e = { slot = slot, text = tl.text, rem = tl.rem, key = slot .. ":" .. tl.text }
                -- con una sola línea, el tiempo exacto y el ID vienen de la API
                if #tips == 1 and has then e.rem = (expMs or 0) / 1000; e.enchant = enchantId end
                list[#list + 1] = e
            end
        elseif has then
            list[#list + 1] = { slot = slot, rem = (expMs or 0) / 1000, enchant = enchantId,
                                key = slot .. ":#" .. tostring(enchantId) }
        end
    end
    return list
end

-- ¿Esta línea del arma es de este ítem? (sin aprender: "Sharpened" ↔ "sharp weapon damage")
local function EnchantLooksLike(e, id)
    if not e.text then return false end
    local use = ns.ItemUseText(id)
    if not use then return false end
    use = use:lower()
    for word in e.text:lower():gmatch("%a+") do
        if #word >= 5 and use:find(word:sub(1, 5), 1, true) then return true end
    end
    return false
end
ns.EnchantLooksLike = EnchantLooksLike

-- ¿Llevas un arma en la mano secundaria? (no escudo ni objeto de mano)
local WEAPON_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Weapon) or 2
function ns.HasOffhandWeapon()
    local id = GetInventoryItemID("player", 17)
    if not id then return false end
    local _, _, _, _, _, classID = ItemInstant(id)
    return classID == WEAPON_CLASS
end

-- Tiempo que le queda a ESTE ítem en cada mano (0 = no lo tiene)
function ns:WeaponSlotRemaining(id)
    local rem = { main = 0, off = 0 }
    local link = self:ItemLink(id)
    for _, e in ipairs(ns.WeaponEnchants()) do
        local mine = (link and link.wtext and e.text == link.wtext) or (not (link and link.wtext) and EnchantLooksLike(e, id))
        if mine and rem[e.slot] and e.rem > rem[e.slot] then rem[e.slot] = e.rem end
    end
    return rem
end

-- Mano para aplicar la piedra/aceite: con dos armas, la que no la tiene (o la que vence antes)
function ns:PickWeaponSlot(id)
    if not ns.HasOffhandWeapon() then return 16 end
    local rem = self:WeaponSlotRemaining(id)
    return (rem.off < rem.main) and 17 or 16
end

function ns:ConsumableKey(id)
    if ns.IsWeaponItem(id) then return "weapon", true end
    local name, spellId = UseSpell(id)
    -- en el registro: su categoría (todo lo de la categoría es un solo grupo)
    local cat = ns.CONS_BY_ITEM and ns.CONS_BY_ITEM[id]
    if cat then return "db:" .. cat.key, false, name, spellId, cat end
    if name and not issecret(name) then return "spell:" .. name, false, name, spellId end
    return "item:" .. id, false
end

-- Texto del juego "en crudo": "1 |4hour:hours;" (singular/plural) y espacios duros.
-- El chat los muestra bien ("1 hour"), pero los patrones necesitan el texto limpio.
function ns.CleanGameText(t)
    if not t then return t end
    t = t:gsub("|4([^:;]*):[^;]*;", "%1")
    t = t:gsub("\194\160", " ")
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return t
end

-- Línea "Use:" del tooltip del ítem (nil si aún no cargó)
local USE_PREFIX_C = (ITEM_SPELL_TRIGGER_ONUSE or "Use:"):lower()
function ns.ItemUseText(id)
    local ok, lines = pcall(ns.ItemTooltipLines, id)
    if not ok or not lines then return nil end
    for _, l in ipairs(lines) do
        local low = l:lower()
        if low:sub(1, #USE_PREFIX_C) == USE_PREFIX_C and #low > #USE_PREFIX_C + 5 then return ns.CleanGameText(l) end
    end
end

-- ¿El efecto deja un buff de 15 min o más ("for 30 min", "durante 1 h")?
-- Sin duración o más corto (granadas, pociones, efectos de segundos) no entra en la grilla.
-- { patrón, minutos por unidad }
local DURATION = {
    { "for (%d+) ?hours?", 60 }, { "for (%d+) ?hrs?", 60 }, { "for (%d+) ?min", 1 },
    { "durante (%d+) ?horas?", 60 }, { "durante (%d+) ?h%f[%A]", 60 }, { "durante (%d+) ?min", 1 },
}
local buffCache = {}
function ns.ItemLeavesBuff(id)
    if buffCache[id] ~= nil then return buffCache[id] end
    local use = ns.ItemUseText(id)
    if not use then return nil end
    local low = use:lower()
    local yes = false
    for _, d in ipairs(DURATION) do
        for n in low:gmatch(d[1]) do
            if tonumber(n) * d[2] >= MIN_BUFF_MIN then yes = true end
        end
    end
    buffCache[id] = yes
    return yes
end

-- Auras propias de CampXP (campamento, saco, comida): nunca son de un consumible
local function IsOurAura(name)
    return name and ns.LOC.auraNames[name] ~= nil
end

local function RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

-- true/false + motivo; nil = datos del ítem aún sin cargar (la grilla se reconstruye al llegar)
function ns.IsConsumableItem(id)
    -- en el registro: entra siempre que tenga efecto "Usar" (sin filtro de clase ni duración)
    if ns.CONS_BY_ITEM and ns.CONS_BY_ITEM[id] then
        if UseSpell(id) then return true, "registry" end
        RequestItem(id)
        return nil, "loading"
    end
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    if classID ~= CONSUMABLE_CLASS then return false, "class " .. tostring(classID) end
    if not CONS_SUBCLASS[subClassID] then return false, "subclass " .. tostring(subClassID) end
    if IsCampItem(id) then return false, "camp item" end
    -- el hechizo "Usar" y el tooltip pueden no estar cargados aún: no descartar todavía
    local use = ns.ItemUseText(id)
    if not UseSpell(id) and not use then RequestItem(id) return nil, "loading" end
    if ns.IsWeaponItem(id) then return true, "weapon" end -- aceites/piedras: siempre
    local buff = ns.ItemLeavesBuff(id)
    if buff == nil then RequestItem(id) return nil, "loading" end
    return buff, buff and "ok" or "no buff of 15+ min"
end

-- /cxp cons: por qué cada consumible de las bolsas entra o no en la grilla
function ns:DebugConsumables()
    self.Print(L["Consumables in bags (class 0):"])
    local n = 0
    for id in pairs(ns.GetBagSnapshot()) do
        local _, _, _, _, _, classID, subClassID = ItemInstant(id)
        if classID == CONSUMABLE_CLASS then
            n = n + 1
            local ok, why = ns.IsConsumableItem(id)
            local spellName, spellId = UseSpell(id)
            print(format("  %s%s|r (%d) sub %s · use: %s (%s) · %s",
                ok and "|cff40ff40" or (ok == nil and "|cffffd100" or "|cffff6060"),
                ns.GetItemName(id) or "?", id, tostring(subClassID),
                tostring(spellName), tostring(spellId), why or "?"))
            local text = ns.ItemUseText(id)
            if text then print("      " .. text) end
        end
    end
    if n == 0 then print("  -") end
    self.Print(L["Your buffs:"])
    for spellId, a in pairs(self.auras) do
        if not IsOurAura(a.name) then
            print(format("  %s (%d) %s · %s · sig %s", tostring(a.name), spellId,
                (a.duration or 0) > 0 and ns.FormatTime(math.max(0, a.expirationTime - GetTime())) or "-",
                a.own and "self" or "other", tostring(self:AuraStatSig(a))))
        end
    end
    -- el encantamiento temporal del arma no es un aura: se muestra aparte
    local enchants = ns.WeaponEnchants()
    if #enchants == 0 then print(format("  %s: -", L["Weapon enchant"])) end
    for _, e in ipairs(enchants) do
        -- ¿qué ítem aprendió este encantamiento?
        local who
        for iid, link in pairs(self.db.consLinks or {}) do
            if (e.text and link.wtext == e.text) then who = ns.GetItemName(iid) or iid end
        end
        if not who then
            for _, t in pairs(self.cdb.endgame.tracked) do
                if t.weapon then
                    for iid in pairs(t.items) do
                        if EnchantLooksLike(e, iid) then who = (ns.GetItemName(iid) or iid) .. " (~)" end
                    end
                end
            end
        end
        print(format("  %s (%s): %s · %s%s", L["Weapon enchant"], e.slot, ns.FormatTime(e.rem),
            e.text or ("enchant " .. tostring(e.enchant)), who and (" → " .. who) or " · " .. L["not from a tracked item"]))
    end
    self.Print(L["Tracked groups:"])
    for key, t in pairs(self.cdb.endgame.tracked) do
        local names = {}
        for id in pairs(t.items) do names[#names + 1] = (ns.GetItemName(id) or id) .. " [" .. tostring(ns.ItemStatSig(id)) .. "]" end
        print(format("  %s · sig %s · use %s (%s) · aura %s (%s)%s%s", key, tostring(t.sig), tostring(t.spellName),
            tostring(t.spellId), tostring(t.auraName), tostring(t.auraSpell), t.manual and " manual" or "",
            t.seen and " seen" or ""))
        print("      " .. table.concat(names, ", "))
        -- resultado actual: activo (cómo), cubierto por otro, o sin coincidencia
        for _, r in ipairs((self.state.consumables and self.state.consumables.list) or {}) do
            if r.key == key then
                print("      => " .. (r.coveredBy and ("covered by " .. r.coveredBy)
                    or (r.active and ("ACTIVE via " .. tostring(r.how) .. " (" .. tostring(r.auraName) .. ")") or "NO MATCH")))
            end
        end
        for id in pairs(t.items) do
            local link = self:ItemLink(id)
            if link then
                print(format("      %s → %s (%s)%s", ns.GetItemName(id) or id, tostring(link.name),
                    tostring(link.spell), link.exact and " EXACT" or " guessed"))
            end
        end
    end
end

function ns:IsTrackedItem(id)
    return self:TrackedFor(id) ~= nil
end

-- Firma de estadísticas: "Str", "Agi", "Int/Spi", "MP5"... (sin valores).
-- Dos consumibles con la misma firma dan el mismo tipo de buff y no se acumulan
-- (scroll de Fuerza + elixir de Fuerza: queda el mayor) → un solo grupo vigilado.
local function SigOf(st)
    if not st then return nil end
    local abbrs = {}
    for word in st:gmatch("[^%s/]+") do
        if not word:find("^%+?%d") and word ~= "?" then abbrs[#abbrs + 1] = word end
    end
    if #abbrs == 0 then return nil end
    table.sort(abbrs)
    return table.concat(abbrs, "/")
end
local function StatSig(text) return SigOf(text and ns.ParseStats(text)) end

local itemSigCache = {}
function ns.ItemStatSig(id)
    if itemSigCache[id] ~= nil then return itemSigCache[id] or nil end
    local use = ns.ItemUseText(id)
    if not use then return nil end
    -- solo el efecto: sin "Use:" ni la duración
    local body = use:gsub("^[^:]*:%s*", "")
    body = body:gsub("[Ll]asts for.*$", ""):gsub("[Dd]ura %d+.*$", "")
    local sig = StatSig(body)
    itemSigCache[id] = sig or false
    return sig
end

function ns:AuraStatSig(a)
    local txt = self:AuraStatText(a)
    return SigOf(txt)
end

-- Consumibles de las bolsas: { {id, count, tracked, weapon}, ... } vigilados primero
-- ¿El buff del grupo de este ítem ya está puesto (por él o por otro del grupo)?
function ns:ItemBuffReady(id)
    local _, key = self:TrackedFor(id)
    if not key then return false end
    for _, r in ipairs((self.state.consumables and self.state.consumables.list) or {}) do
        if r.key == key then return r.active == true end
    end
    return false
end

function ns:GetBagConsumables()
    local list = {}
    self.consPending = false
    for id, count in pairs(ns.GetBagSnapshot()) do
        local ok = ns.IsConsumableItem(id)
        if ok == nil then self.consPending = true end
        if ok then
            local _, weapon = self:ConsumableKey(id)
            table.insert(list, { id = id, count = count, tracked = self:IsTrackedItem(id), weapon = weapon,
                                 ready = self:ItemBuffReady(id) })
        end
    end
    table.sort(list, function(a, b)
        if a.tracked ~= b.tracked then return a.tracked end
        return (ns.GetItemName(a.id) or "") < (ns.GetItemName(b.id) or "")
    end)
    return list
end

-- Clic derecho en la grilla: vigilar / dejar de vigilar
-- Agrega un ítem a su grupo (lo crea si hace falta).
-- how = true (elegido por el jugador, se mantiene) o "auto" (desde las bolsas, se va si se acaba)
function ns:AddTrack(id, how, silent)
    local tracked = self.cdb.endgame.tracked
    local key, weapon, spellName, spellId, cat = self:ConsumableKey(id)
    local name = ns.GetItemName(id) or format(L["Item %d"], id)
    local t = self:TrackedFor(id)
    if t then
        if how == true then t.items[id] = true end -- pasa de auto a fijo
        return t
    end
    local sig = not weapon and ns.ItemStatSig(id) or nil
    -- fuera del registro: mismo tipo de estadística → mismo grupo (incluye las categorías del registro)
    if not cat and not tracked[key] and sig then
        for k, g in pairs(tracked) do
            -- solo con otros desconocidos: las reglas del registro mandan sobre la estadística
            if g.sig == sig and not g.cat then key = k break end
        end
    end
    t = tracked[key]
    if not t then
        t = { items = {}, weapon = weapon or nil, spellName = spellName, spellId = spellId, sig = sig,
              cat = cat and cat.key, label = cat and ns.CatLabel(cat, id) or (weapon and L["Weapon enchant"]) or (spellName or name) }
        tracked[key] = t
    end
    t.items[id] = how
    t.ids = t.ids or {}
    if spellId then t.ids[spellId] = true end
    local link = self:ItemLink(id)
    if link and not t.manual then
        t.auraSpell, t.auraName = t.auraSpell or link.spell, t.auraName or link.name
    end
    if not silent then
        local buff = self:LinkedBuffName(t)
        self.Print(buff and format(L["Tracking %s → buff: %s"], name, buff) or format(L["Tracking %s"], name))
    end
    return t
end

function ns:RemoveTrack(id)
    local t, key = self:TrackedFor(id)
    if not t then return end
    t.items[id] = nil
    if next(t.items) == nil then self.cdb.endgame.tracked[key] = nil end
end

-- Automático: todo consumible válido de las bolsas se vigila, salvo los que el jugador quitó.
-- Los automáticos que se acaban (y sin buff puesto) dejan de vigilarse solos.
function ns:AutoTrackBag()
    local eg = self.cdb.endgame
    if not eg.auto then return end
    eg.ignored = eg.ignored or {}
    local snap = ns.GetBagSnapshot()
    for id in pairs(snap) do
        if not eg.ignored[id] and not self:TrackedFor(id) and ns.IsConsumableItem(id) then
            self:AddTrack(id, "auto", true)
        end
    end
end

-- Clic derecho → "Vigilar este buff": quitar lo ignora (no vuelve en automático); marcar lo fija
function ns:ToggleTrack(id)
    local eg = self.cdb.endgame
    eg.ignored = eg.ignored or {}
    local name = ns.GetItemName(id) or format(L["Item %d"], id)
    if self:TrackedFor(id) then
        self:RemoveTrack(id)
        eg.ignored[id] = true
        self.Print(format(L["No longer tracking %s"], name))
    else
        eg.ignored[id] = nil
        self:AddTrack(id, true)
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
    for key, t in pairs(self.cdb.endgame.tracked) do
        if t.items[id] then return t, key end
    end
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
-- Uso detectado (grilla, bolsas o barra): el aura que empezó en ese momento es la suya
function ns:NoteConsumableUse(id, when)
    local t, key = self:TrackedFor(id)
    if not t or t.weapon then return end
    pendingUse = { key = key, id = id, t = when or GetTime() }
end


-- ¿Está puesto el buff de este vigilado? Devuelve activo, restante (s), aura
-- Nombre del buff vinculado a un vigilado (para mostrar)
function ns:LinkedBuffName(t)
    if t.weapon then return L["Weapon enchant"] end
    return t.auraName or t.spellName
end

-- ¿Este aura es el buff del vigilado?
--   vínculo manual: solo el aura elegida
--   automático: hechizo "Usar" del ítem (mismo ID o mismo nombre) o el aura aprendida al usarlo
-- BD local (cuenta): ítem → aura que deja, aprendida al verlo/usarlo o elegida a mano
function ns:ItemLink(id)
    return self.db.consLinks and self.db.consLinks[id]
end

-- exact = visto en el momento del uso (lanzamiento del hechizo del ítem → aura añadida)
function ns:SaveItemLink(id, spellId, name, exact)
    self.db.consLinks = self.db.consLinks or {}
    local old = self.db.consLinks[id]
    if old and old.exact and not exact then return end -- nunca pisar un vínculo exacto con uno deducido
    self.db.consLinks[id] = { spell = spellId, name = name, exact = exact or nil }
end

-- ¿Todos los ítems del grupo tienen vínculo exacto? Entonces no se adivina nada.
local function AllExact(self, t)
    for id in pairs(t.items) do
        local link = self:ItemLink(id)
        if not (link and link.exact) then return false end
    end
    return next(t.items) ~= nil
end

local function AuraMatches(self, t, spellId, a)
    -- solo buffs que te pusiste tú: el Arcane Intellect de un mago no es tu scroll
    if not a.own then return false end
    -- 0) aura propia con el MISMO ID que el efecto "Usar" de un ítem del grupo: siempre es suyo
    --    (ej. Elixir of Ogre Strength usa 3164 y deja Strength 3164). Va antes que todo,
    --    así un vínculo manual o guardado equivocado no puede ocultarlo.
    for id in pairs(t.items) do
        local _, useId = UseSpell(id)
        if useId and useId == spellId then return true, "use" end
    end
    if t.manual then
        return spellId == t.auraSpell or (a.name ~= nil and a.name == t.auraName)
    end
    -- 0b) registro: cualquier ítem de la categoría (el scroll III cuenta para el grupo con el elixir)
    local cat = t.cat and ns.CONS_BY_KEY[t.cat]
    if cat and ns.CatUseSpells(cat)[spellId] then return true, "db" end
    -- 1) vínculo exacto (visto al usar el ítem): solo ese ID de aura
    for id in pairs(t.items) do
        local link = self:ItemLink(id)
        if link and link.exact and spellId == link.spell then return true, "exact" end
    end
    if AllExact(self, t) then return false end
    -- grupo del registro: su lista de hechizos manda; solo si el juego aún no la cargó
    -- se acepta el nombre del hechizo "Usar" (nada de deducir por estadística)
    if cat then
        if not cat.useDone and a.name ~= nil and a.name == t.spellName then return true, "name" end
        return false
    end
    -- 2) deducción: mismo hechizo/nombre, BD aprendida o tipo de estadística
    if (t.spellId and spellId == t.spellId) or (t.ids and t.ids[spellId]) or (t.auraSpell and spellId == t.auraSpell)
        or (a.name ~= nil and (a.name == t.spellName or a.name == t.auraName)) then
        return true, "id"
    end
    for id in pairs(t.items) do
        local link = self:ItemLink(id)
        if link and (spellId == link.spell or a.name == link.name) then return true, "db" end
    end
    -- mismo tipo de estadística (aura propia con duración): "+13 Str" del scroll sirve para el grupo Fuerza
    if t.sig and (a.duration or 0) > 0 and not IsOurAura(a.name)
        and self:AuraStatSig(a) == t.sig then
        return true, "stat"
    end
    return false
end

local function TrackedAura(self, key, t, now)
    if t.weapon then
        local enchants = ns.WeaponEnchants()
        local withText = false
        for _, e in ipairs(enchants) do if e.text then withText = true end end
        local best
        for _, e in ipairs(enchants) do
            local mine = false
            for id in pairs(t.items) do
                local link = self:ItemLink(id)
                if link and link.wtext then
                    -- aprendido (al aplicarlo o a mano): esa línea exacta del arma
                    if e.text == link.wtext then mine = true end
                elseif EnchantLooksLike(e, id) then
                    mine = true
                elseif not withText and link and link.enchant and e.enchant == link.enchant then
                    mine = true -- sin tooltip: por ID
                end
            end
            -- sin tooltip ni nada aprendido: cualquier encantamiento (último recurso)
            if not withText and not mine then
                local learnedAny = false
                for id in pairs(t.items) do if self:ItemLink(id) then learnedAny = true end end
                mine = not learnedAny
            end
            if mine and (not best or e.rem > best.rem) then best = e end
        end
        if best then return true, best.rem end
        return false, 0
    end
    local best, bestRem
    for spellId, a in pairs(self.auras) do
        local match, how = AuraMatches(self, t, spellId, a)
        if match then
            local rem = (a.expirationTime and a.expirationTime > 0) and (a.expirationTime - now) or math.huge
            if rem > 0 and (not bestRem or rem > bestRem) then best, bestRem = a, rem; a.__id = spellId; a.__how = how end
        end
    end
    if best then
        -- confirmado: lo vimos activo
        if not t.seen then
            t.seen = true
            t.auraName = t.auraName or best.name
            if not t.manual then t.auraSpell = t.auraSpell or best.__id end
        end
        -- guarda en la BD de la cuenta para los ítems del grupo que aún no lo tengan
        -- (con un solo ítem es seguro; en grupos solo el ítem cuyo "Usar" es esta misma aura)
        local single = next(t.items) ~= nil and next(t.items, next(t.items)) == nil
        for id in pairs(t.items) do
            if not self:ItemLink(id) then
                local _, useId = UseSpell(id)
                if single or useId == best.__id then self:SaveItemLink(id, best.__id, best.name) end
            end
        end
        return true, bestRem, best
    end
    return false, 0
end

-- Buff de otro jugador que cubre lo mismo (Arcane Intellect ↔ scroll de Intelecto):
-- no se acumulan, así que usar el consumible no sirve → cuenta como cubierto, sin aviso.
local function CoveredByOther(self, t)
    if t.weapon then return nil end
    -- registro: buffs de clase de la misma categoría (Arcane Intellect ↔ scroll de Intelecto),
    -- tuyos o de otro (si eres mago, tu propio Arcane Intellect también lo cubre)
    local cat = t.cat and ns.CONS_BY_KEY[t.cat]
    if cat and cat.covers then
        local names = ns.CatCoverNames(cat)
        for spellId, a in pairs(self.auras) do
            if cat.coverSet[spellId] or (a.name and names[a.name]) then return a end
        end
    end
    for _, a in pairs(self.auras) do
        if not a.own and a.name and not IsOurAura(a.name) then
            if a.name == t.auraName or a.name == t.spellName
                or (t.sig and self:AuraStatSig(a) == t.sig) then
                return a
            end
        end
    end
end

-- Vínculo manual: el jugador elige el buff activo que corresponde a este consumible
function ns:LinkTrackedToAura(id, spellId, a)
    local t = self:TrackedFor(id)
    if not t then return end
    t.manual, t.auraSpell, t.auraName, t.seen = true, spellId, a.name, true
    t.label = a.name
    self:SaveItemLink(id, spellId, a.name)
    self.Print(format(L["Linked: %s → %s"], ns.GetItemName(id) or id, a.name))
    self:FullUpdate()
end

function ns:ClearTrackedLink(id)
    local t = self:TrackedFor(id)
    if not t then return end
    t.manual, t.auraSpell, t.auraName, t.seen, t.exact = nil, nil, nil, nil, nil
    t.label = t.spellName or t.label
    for iid in pairs(t.items) do
        if self.db.consLinks then self.db.consLinks[iid] = nil end
    end
    self.Print(format(L["Link reset: %s"], ns.GetItemName(id) or id))
    self:FullUpdate()
end

-- Buffs propios activos para el submenú de vínculo (sin los de CampXP ni los de otros jugadores)
function ns:LinkableAuras()
    local list = {}
    for spellId, a in pairs(self.auras) do
        if a.name and a.own and not IsOurAura(a.name) then
            table.insert(list, { spellId = spellId, aura = a })
        end
    end
    table.sort(list, function(x, y) return x.aura.name < y.aura.name end)
    return list
end

-- Asociación aprendida: el aura nueva que apareció tras usarlo desde la grilla
local function LearnAura(self, now)
    if not pendingUse or now - pendingUse.t > LEARN_WINDOW then pendingUse = nil return end
    local t = self.cdb.endgame.tracked[pendingUse.key]
    if not t then pendingUse = nil return end
    if t.manual or TrackedAura(self, pendingUse.key, t, now) then pendingUse = nil return end
    -- aura propia cuyo inicio (expira - duración) coincide con el uso (±3 s)
    local bestId, bestA, bestDiff
    for spellId, a in pairs(self.auras) do
        if a.own and not IsOurAura(a.name) and (a.duration or 0) > 0 and a.expirationTime then
            local diff = math.abs((a.expirationTime - a.duration) - pendingUse.t)
            if diff <= 3 and (not bestDiff or diff < bestDiff) then bestId, bestA, bestDiff = spellId, a, diff end
        end
    end
    if bestA then
        t.auraName, t.auraSpell, t.seen = bestA.name, bestId, true
        ns:SaveItemLink(pendingUse.id, bestId, bestA.name)
        ns.Print(format(L["Linked: %s → %s"], ns.GetItemName(pendingUse.id) or t.label or "?", bestA.name))
        pendingUse = nil
    end
end

-- Estado del ícono Consumables (llamado desde ComputeState)
-- Grupos creados antes del registro: mover sus ítems a la categoría que les toca
local function MigrateToRegistry(self)
    local tracked = self.cdb.endgame.tracked
    local moves = {}
    for key, t in pairs(tracked) do
        for id, how in pairs(t.items) do
            local cat = ns.CONS_BY_ITEM[id]
            -- al registro, o al grupo del arma si es aceite/piedra
            local want = (cat and "db:" .. cat.key) or (ns.IsWeaponItem(id) and "weapon") or nil
            if want and key ~= want then moves[#moves + 1] = { id = id, how = how, from = key, t = t } end
        end
    end
    for _, m in ipairs(moves) do
        m.t.items[m.id] = nil
        if next(m.t.items) == nil then tracked[m.from] = nil end
        local g = self:AddTrack(m.id, m.how, true)
        -- conserva los avisos elegidos
        if m.t.alerts and not g.alerts then g.alerts = m.t.alerts end
    end
end

function ns:ComputeConsumables(s, now)
    MigrateToRegistry(self)
    self:AutoTrackBag()
    LearnAura(self, now)
    local eg = self.cdb.endgame
    -- automáticos que se acabaron y sin su buff puesto: dejan de vigilarse
    for key, t in pairs(eg.tracked) do
        local gone = false
        for id, how in pairs(t.items) do
            if how == "auto" and (ns.GetItemCount(id) or 0) == 0 then gone = true end
        end
        if gone and not TrackedAura(self, key, t, now) then
            for id, how in pairs(t.items) do
                if how == "auto" and (ns.GetItemCount(id) or 0) == 0 then t.items[id] = nil end
            end
            if next(t.items) == nil then eg.tracked[key] = nil end
        end
    end
    local warn = (eg.warnMin or 10) * 60
    s.trackedCount, s.activeCount, s.nextLabel = 0, 0, nil
    s.list = {}
    local minRem, anyHave, expiring = math.huge, false, false
    for key, t in pairs(eg.tracked) do
        -- grupos creados antes de 1.4.0-final: completar su firma de estadística
        if t.sig == nil and not t.weapon then
            for id in pairs(t.items) do
                local sig = ns.ItemStatSig(id)
                if sig then t.sig = sig break end
            end
        end
        local count, best, bestN = 0, nil, 0
        for id in pairs(t.items) do
            local n = ns.GetItemCount(id)
            count = count + n
            if n > bestN then best, bestN = id, n end
        end
        local active, rem, aura = TrackedAura(self, key, t, now)
        local covered = not active and CoveredByOther(self, t) or nil
        if covered then
            active = true
            rem = (covered.expirationTime and covered.expirationTime > 0) and (covered.expirationTime - now) or math.huge
        end
        local row = { key = key, t = t, label = t.label or key, active = active, remaining = rem, count = count,
                      itemId = best or next(t.items), buff = self:LinkedBuffName(t),
                      verified = t.weapon or t.seen or aura ~= nil, coveredBy = covered and covered.name,
                      how = aura and (aura.__how or "manual") or (t.weapon and "weapon"), auraName = aura and aura.name }
        if aura and not t.auraName then t.auraName = aura.name end -- coincidencia directa: queda verificado
        -- sin el buff y sin el ítem en las bolsas: no hay nada que hacer → fuera del contador
        -- (queda en el tooltip como "sin stock")
        row.outOfStock = not active and count == 0
        if row.outOfStock then
            table.insert(s.list, row)
        else
        s.trackedCount = s.trackedCount + 1
        if active then
            s.activeCount = s.activeCount + 1
            -- el timer del ícono = el que vence primero (los de otros jugadores no cuentan)
            if rem < minRem and not covered then minRem = rem; s.nextLabel = row.label end
            -- lo de otro jugador no "expira" para ti: no hay nada que reponer
            if rem <= warn and not covered then expiring = true; row.expiring = true end
        elseif count > 0 then
            anyHave = true
        end
        table.insert(s.list, row)
        end
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
-- Reportar un problema con un consumible (texto para pegar en CurseForge)
------------------------------------------------------------------------------
ns.REPORT_URL = "https://www.curseforge.com/wow/addons/campxp/comments" -- confirmado

function ns:BugReportText(id)
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ver = meta and meta(ADDON, "Version") or "?"
    local build = GetBuildInfo and select(1, GetBuildInfo()) or "?"
    local _, _, _, _, _, classID, subClassID = ItemInstant(id)
    local spellName, spellId = UseSpell(id)
    local t, key = self:TrackedFor(id)
    local use = ns.ItemUseText(id) or "?"
    local parts = {
        format("CampXP %s (%s, %s)", ver, ns.locale or "?", build),
        format("lvl %d %s", UnitLevel("player") or 0, self.cdb.mode or "?"),
        format("item: %s (%d) class %s/%s", ns.GetItemName(id) or "?", id, tostring(classID), tostring(subClassID)),
        format("use: %s (%s)", tostring(spellName), tostring(spellId)),
        format("tracked: %s, aura: %s", t and key or "no", t and format("%s%s (%s)", t.auraName or t.spellName or "?", t.manual and " manual" or "", t.seen and "seen" or "not seen") or "-"),
        "text: " .. use,
        "problem: ",
    }
    return table.concat(parts, " | ")
end

------------------------------------------------------------------------------
-- Detección exacta: lanzas el hechizo "Usar" de un consumible (UNIT_SPELLCAST_SUCCEEDED)
-- y en el mismo instante el juego añade/renueva un aura tuya (UNIT_AURA) → ese es su buff.
------------------------------------------------------------------------------
local pendingCast -- { spell, t, items = {id,...} }
local CAST_WINDOW = 1.5

-- ítems de las bolsas cuyo efecto "Usar" es este hechizo
local function ItemsForSpell(spellId)
    local list = {}
    for id in pairs(ns.GetBagSnapshot()) do
        local _, useId = UseSpell(id)
        if useId == spellId and ns.IsConsumableItem(id) then list[#list + 1] = id end
    end
    -- el último de la pila ya no está en las bolsas: buscar también entre los vigilados
    if #list == 0 then
        for _, t in pairs(ns.cdb.endgame.tracked) do
            for id in pairs(t.items) do
                local _, useId = UseSpell(id)
                if useId == spellId then list[#list + 1] = id end
            end
        end
    end
    return list
end

local pendingWeapon -- { items, t, before = {slot → enchant}, dur }
-- foto de los encantamientos tomada antes (cada 2 s): al terminar de aplicar la piedra
-- el encantamiento nuevo ya puede estar puesto, así que no sirve leerlos en ese instante
local lastEnchants = {}
local function SnapEnchants()
    local snap = {}
    for _, e in ipairs(ns.WeaponEnchants()) do snap[e.key] = e end
    return snap
end

-- duración del efecto del ítem en segundos ("for 30 minutes" → 1800)
local function ItemDurationSec(id)
    local use = ns.ItemUseText(id)
    if not use then return nil end
    local low = use:lower()
    local n = low:match("for (%d+) ?min") or low:match("durante (%d+) ?min")
    if n then return tonumber(n) * 60 end
    n = low:match("for (%d+) ?hours?") or low:match("for (%d+) ?hrs?") or low:match("durante (%d+) ?h")
    if n then return tonumber(n) * 3600 end
end

-- vínculo manual: este ítem corresponde al encantamiento de ese espacio
function ns:LinkWeaponEnchant(id, e)
    self.db.consLinks = self.db.consLinks or {}
    self.db.consLinks[id] = { wtext = e.text, enchant = e.enchant, exact = true, manual = true }
    self.Print(format(L["Linked: %s → %s"], ns.GetItemName(id) or id, e.text or (L["Weapon enchant"] .. " " .. tostring(e.enchant))))
    self:FullUpdate()
end

function ns:OnPlayerCast(spellId)
    if issecret(spellId) or not spellId then return end
    local items = ItemsForSpell(spellId)
    if #items == 0 then return end
    if ns.IsWeaponItem(items[1]) then
        pendingWeapon = { items = items, t = GetTime(), before = lastEnchants, dur = ItemDurationSec(items[1]) }
        return
    end
    pendingCast = { spell = spellId, t = GetTime(), items = items }
end

-- Tras aplicar una piedra/aceite: el espacio cuyo encantamiento cambió (o se renovó) es el suyo
function ns:CheckWeaponLearn()
    local pw = pendingWeapon
    if not pw then lastEnchants = SnapEnchants() return end
    if GetTime() - pw.t > 8 then pendingWeapon = nil; lastEnchants = SnapEnchants() return end
    for _, e in ipairs(ns.WeaponEnchants()) do
        local b = pw.before[e.key]
        -- línea nueva o renovada respecto de la foto anterior; o recién puesta con la duración del ítem
        -- (el tooltip redondea a minutos: margen de 60 s)
        local fresh = pw.dur and math.abs(e.rem - pw.dur) <= 60
        if not b or e.rem > b.rem + 30 or fresh then
            pendingWeapon = nil
            for _, id in ipairs(pw.items) do
                local old = self:ItemLink(id)
                self.db.consLinks = self.db.consLinks or {}
                self.db.consLinks[id] = { wtext = e.text, enchant = e.enchant, exact = true }
                if not (old and old.wtext == e.text) then
                    self.Print(format(L["Linked: %s → %s"], ns.GetItemName(id) or id, e.text or tostring(e.enchant)))
                end
            end
            self:FullUpdate()
            return
        end
    end
end

local function ApplyExactLink(self, aura)
    local pc = pendingCast
    pendingCast = nil
    for _, id in ipairs(pc.items) do
        local old = self:ItemLink(id)
        self:SaveItemLink(id, aura.spellId, aura.name, true)
        local t = self:TrackedFor(id)
        if t and not t.manual then
            t.auraSpell, t.auraName, t.seen, t.exact = aura.spellId, aura.name, true, true
            if t.label == nil or t.label == t.spellName then t.label = aura.name end
        end
        if not (old and old.exact and old.spell == aura.spellId) and t then
            self.Print(format(L["Linked (exact): %s → %s (%d)"], ns.GetItemName(id) or id, aura.name, aura.spellId))
        end
    end
    self:FullUpdate()
end

local function GoodAura(a)
    if not a or issecret(a.spellId) or issecret(a.sourceUnit) then return false end
    if a.isHelpful == false or not a.name or IsOurAura(a.name) then return false end
    return a.sourceUnit ~= nil and UnitIsUnit(a.sourceUnit, "player")
end

function ns:OnPlayerAura(info)
    local pc = pendingCast
    if not pc then return end
    if GetTime() - pc.t > CAST_WINDOW then pendingCast = nil return end
    if not info or info.isFullUpdate then return end
    local cands = {}
    for _, a in ipairs(info.addedAuras or {}) do
        if GoodAura(a) then cands[#cands + 1] = a end
    end
    -- volver a tomarlo con el buff puesto lo renueva (no lo añade)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        for _, iid in ipairs(info.updatedAuraInstanceIDs or {}) do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", iid)
            -- renovado ahora mismo: termina ~duración desde ya
            if ok and GoodAura(a) and (a.duration or 0) > 0
                and math.abs((a.expirationTime - a.duration) - GetTime()) < CAST_WINDOW then
                cands[#cands + 1] = a
            end
        end
    end
    if #cands == 0 then return end
    -- preferir el aura con el mismo ID que el hechizo usado
    local pick
    for _, a in ipairs(cands) do if a.spellId == pc.spell then pick = a end end
    if not pick and #cands == 1 then pick = cands[1] end
    if not pick then
        -- varias a la vez: la de mayor duración (el buff largo del consumible)
        for _, a in ipairs(cands) do
            if (a.duration or 0) > 0 and (not pick or a.duration > pick.duration) then pick = a end
        end
    end
    if pick then ApplyExactLink(self, pick) end
end

------------------------------------------------------------------------------
-- Recordatorios: al entrar a dungeon/raid y en el ready check
------------------------------------------------------------------------------
local pendingCheck, lastInstance
local lastCounts = {}

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
        if r.outOfStock then
            -- sin ítem y sin buff: solo entra como stock bajo (0)
        elseif not r.active then
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
        ev:RegisterEvent("BAG_UPDATE_DELAYED")
        ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        ev:RegisterUnitEvent("UNIT_AURA", "player")
        ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        C_Timer.After(8, function() ns:OfferEndgame() end)
        C_Timer.NewTicker(2, function()
            pcall(ns.CheckWeaponLearn, ns)
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
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellId = ...
        pcall(ns.OnPlayerCast, ns, spellId)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        pcall(ns.CheckWeaponLearn, ns)
    elseif event == "UNIT_AURA" then
        local _, info = ...
        if pendingCast then pcall(ns.OnPlayerAura, ns, info) end
    elseif event == "BAG_UPDATE_DELAYED" then
        -- bajó la cantidad de un vigilado = lo usaste (desde bolsas, barra o macro)
        local when = GetTime()
        C_Timer.After(0.3, function()
            if not ns:IsEndgame() then return end
            local snap = ns.GetBagSnapshot()
            for key, t in pairs(ns.cdb.endgame.tracked) do
                for id in pairs(t.items) do
                    local n = snap[id] or 0
                    if lastCounts[id] and n < lastCounts[id] then ns:NoteConsumableUse(id, when) end
                    lastCounts[id] = n
                end
            end
        end)
    elseif event == "READY_CHECK" then
        if ns.cdb.endgame.onReadyCheck then ns:CheckConsumables("readycheck") end
    end
end)
