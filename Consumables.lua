-- Registro de consumibles: grupos de buffs que NO se acumulan entre sí.
-- Dentro de un grupo queda solo el mayor; grupos distintos sí se acumulan.
--
--   items     = IDs de ítems del grupo
--   covers    = IDs de buffs de clase que ocupan el mismo lugar (todos los rangos):
--               si los tienes, usar el consumible no sirve > no se avisa
--   confirmed = probado en WoW Forever (el resto viene de guías de Classic)
--   label     = nombre del grupo (si falta, se usa el nombre del ítem que tengas)
--   auras     = IDs del buff que deja (cuando no es el mismo que el hechizo "Usar")
--
-- Fuentes: guías de consumibles por clase (Icy Veins, Method, Wowhead Classic),
-- lista de consumibles de WoW Forever (Method) y pruebas en el juego.
-- Lo que no esté aquí (ítems nuevos de Forever) se sigue detectando solo.
-- /cxp db revisa este registro contra los datos del juego.
local ADDON, ns = ...
local L = ns.L

ns.CONS_DB = {
    ------------------------------------------------------------------ Scrolls
    -- Scroll + elixir menor del mismo buff: no se acumulan (Fuerza: confirmado)
    { key = "str", label = L["Strength"], confirmed = true,
      items = { 954, 2289, 4426, 10310,          -- Scroll of Strength I-IV
                2454, 3391 } },                  -- Elixir of Lion's Strength, Ogre's Strength
    { key = "agi", label = L["Agility"],
      items = { 3012, 1477, 4425, 10309,         -- Scroll of Agility I-IV
                2457, 3390, 8949 } },            -- Elixir of Minor / Lesser / Agility
    -- Scroll de Intelecto ↔ Arcane Intellect: confirmado (el mago no pudo poner uno menor)
    { key = "int", label = L["Intellect"], confirmed = true,
      items = { 955, 2290, 4419, 10308,          -- Scroll of Intellect I-IV
                3383 },                          -- Elixir of Wisdom
      covers = { 1459, 1460, 1461, 10156, 10157, 23028 } }, -- Arcane Intellect 1-5, Arcane Brilliance
    { key = "sta", label = L["Stamina"],
      items = { 1180, 1711, 4422, 10307 },       -- Scroll of Stamina I-IV
      covers = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 } }, -- PW: Fortitude 1-6, Prayer of Fortitude
    { key = "spi", label = L["Spirit"],
      items = { 1181, 1712, 4424, 10306 },       -- Scroll of Spirit I-IV
      covers = { 14752, 14818, 14819, 27841, 27681 } }, -- Divine Spirit 1-4, Prayer of Spirit
    { key = "prot", label = L["Armor (scroll)"],
      items = { 3013, 1478, 4421, 10305 } },     -- Scroll of Protection I-IV

    ------------------------------------------------------------------ Elixires de Classic
    { key = "giants", label = L["Strength (elixir)"],
      items = { 9206, 12451 } },                 -- Elixir of Giants, Juju Power (no se acumulan)
    { key = "agi2", label = L["Agility (elixir)"],
      items = { 9187, 13452 } },                 -- Greater Agility, Mongoose (no se acumulan)
    { key = "int2", confirmed = true, items = { 9179 } }, -- Elixir of Greater Intellect
    { key = "sages", items = { 13447 } },        -- Elixir of the Sages (Int + Spi)
    { key = "brute", items = { 13453 } },        -- Elixir of Brute Force (Str + Sta)
    { key = "ap", label = L["Attack power"],
      items = { 12460, 12820 } },                -- Juju Might, Winterfall Firewater (no se acumulan)
    { key = "def", label = L["Armor (elixir)"],
      items = { 5997, 3389, 8951, 13445 } },     -- Elixir of Minor / – / Greater / Superior Defense
    { key = "hp", label = L["Max health"],
      items = { 2458, 3825 } },                  -- Elixir of Minor Fortitude, Fortitude
    { key = "regen", items = { 20004 } },        -- Major Troll's Blood (salud cada 5 s)
    { key = "sp", label = L["Spell power"],
      items = { 9155, 13454 } },                 -- Arcane Elixir, Greater Arcane Elixir
    { key = "shadow", items = { 9264 } },        -- Elixir of Shadow Power
    { key = "fire", label = L["Fire power"],
      items = { 6373, 21546 } },                 -- Elixir of Firepower, Greater Firepower
    { key = "frost", items = { 17708 } },        -- Elixir of Frost Power
    { key = "arthas", items = { 9088 } },        -- Gift of Arthas

    ------------------------------------------------------------------ Flasks: uno a la vez
    { key = "flask", label = L["Flask"],
      items = { 13510, 13511, 13512, 13513, 13506, -- Titans, Distilled Wisdom, Supreme Power, Chromatic, Petrification
                274273, 274274, 274275, 274276 } }, -- Forever: Natural Accuracy / Aggression / Precision / Swiftness

    ------------------------------------------------------------------ Blasted Lands y Zanza (se acumulan con elixires)
    { key = "scorpok", items = { 8412 } },       -- Ground Scorpok Assay (Agi)
    { key = "roids", items = { 8410 } },         -- R.O.I.D.S. (Str)
    { key = "cortex", items = { 8423 } },        -- Cerebral Cortex Compound (Int)
    { key = "gizzard", items = { 8424 } },       -- Gizzard Gum (Spi)
    { key = "lung", items = { 8411 } },          -- Lung Juice Cocktail (Sta)
    { key = "zanza", items = { 20079 } },        -- Spirit of Zanza

    ------------------------------------------------------------------ WoW Forever
    { key = "mageblood", label = L["Mana regeneration"],
      items = { 250340, 20007, 250341 } },       -- Lesser Mageblood, Mageblood, Greater Mageblood
    { key = "cunning", items = { 250328 } },     -- Elixir of Cunning (Agi + Int)
    { key = "ferocity", items = { 250350 } },    -- Elixir of Ferocity (Str + Agi)
    { key = "grizzly", items = { 250351 } },     -- Elixir of the Grizzly (Str + crit)
    { key = "owl", items = { 250337 } },         -- Elixir of the Owl (Int + crit)
    { key = "whale", items = { 250348 } },       -- Elixir of the Whale (Spi + crit)
    { key = "sagesF", items = { 250338 } },      -- Elixir of Sages (Spi + crit)
    { key = "gspirit", items = { 250347 } },     -- Elixir of Greater Spirit
    { key = "ghp", items = { 250335 } },         -- Elixir of Greater Fortitude
    { key = "phalanx", items = { 250329 } },     -- Elixir of the Phalanx (salud + armadura)
    { key = "wicked", items = { 250336 } },      -- Elixir of Wicked Regeneration
    { key = "cleric", items = { 250333 } },      -- Greater Cleric's Elixir (sanación)
    { key = "nature", items = { 250343 } },      -- Elixir of Nature Power
    { key = "firewater", items = { 246948 } },   -- Distilled Firewater (AP)
    { key = "minorarc", items = { 247754 } },    -- Minor Arcane Elixir

    ------------------------------------------------------------------ Descubiertos en el juego
    -- (generado por tools/import_discoveries.py: no editar a mano dentro del bloque)
    -- BEGIN DISCOVERED
    { key = "d247755", confirmed = true, items = { 247755 } }, -- Elixir of Minor Force > Elixir of Minor Force (1245249, 30 min)
    -- END DISCOVERED
}

-- Ítems del registro que entran en la grilla aunque su buff dure menos de 15 min
-- (Juju Might dura 10 min y es de uso normal en raids)
ns.CONS_ANY_DURATION = { [12460] = true }

-- Índices: ítem > grupo, clave > grupo
ns.CONS_BY_ITEM, ns.CONS_BY_KEY = {}, {}
for _, c in ipairs(ns.CONS_DB) do
    ns.CONS_BY_KEY[c.key] = c
    c.coverSet = {}
    for _, sid in ipairs(c.covers or {}) do c.coverSet[sid] = true end
    for _, id in ipairs(c.items) do ns.CONS_BY_ITEM[id] = c end
end

local GetItemSpellFn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetSpellNameFn = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end

-- Nombre del grupo: el suyo, o el del ítem (en el idioma del cliente)
function ns.CatLabel(c, itemId)
    if c.label then return c.label end
    return ns.GetItemName(itemId or c.items[1]) or c.key
end

-- IDs de aura del grupo: el hechizo "Usar" de cada ítem (se completa a medida que el juego lo carga)
function ns.CatUseSpells(c)
    if c.useDone then return c.useSet end
    c.useSet = c.useSet or {}
    local done = true
    for _, sid in ipairs(c.auras or {}) do c.useSet[sid] = true end
    for _, id in ipairs(c.items) do
        local _, sid = GetItemSpellFn(id)
        if sid then
            c.useSet[sid] = true
        else
            done = false
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
    end
    c.useDone = done
    return c.useSet
end

-- Nombres de los buffs de clase que cubren el grupo (por si hay rangos que no están en la lista)
function ns.CatCoverNames(c)
    if c.coverNames then return c.coverNames end
    local names = {}
    for sid in pairs(c.coverSet) do
        local n = GetSpellNameFn(sid)
        if n then names[n] = true end
    end
    c.coverNames = names
    return names
end

-- /cxp db: revisa el registro contra el juego (nombre, hechizo "Usar", tipo de estadística)
function ns:DebugConsDB()
    self.Print(L["Consumables registry check:"])
    local missing = 0
    for _, c in ipairs(ns.CONS_DB) do
        local line = {}
        for _, id in ipairs(c.items) do
            local name = ns.GetItemName(id)
            local _, sid = GetItemSpellFn(id)
            local sig = ns.ItemStatSig and ns.ItemStatSig(id)
            if not name then
                missing = missing + 1
                line[#line + 1] = "|cffffd100" .. id .. "?|r"
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            elseif not sid then
                line[#line + 1] = "|cffff6060" .. name .. " (" .. id .. ", no use)|r"
            else
                line[#line + 1] = format("%s|cffaaaaaa(%d>%d %s)|r", name, id, sid, tostring(sig))
            end
        end
        print(format("|cffffffff%s|r%s: %s", ns.CatLabel(c), c.confirmed and " |cff40ff40✓|r" or "",
            table.concat(line, ", ")))
        if c.covers then
            local cv = {}
            for _, sid in ipairs(c.covers) do cv[#cv + 1] = (GetSpellNameFn(sid) or "?") .. "(" .. sid .. ")" end
            print("   " .. L["covered by: "] .. table.concat(cv, ", "))
        end
    end
    print(L["Yellow = still loading (run again) · red = item has no Use effect."])
end
