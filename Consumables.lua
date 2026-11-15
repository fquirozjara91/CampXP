-- Registro de consumibles: categorías de buffs que NO se acumulan entre sí.
-- Dentro de una categoría queda solo el mayor (scroll de Fuerza vs elixir de Fuerza,
-- scroll de Intelecto vs Arcane Intellect: confirmado en WoW Forever).
--
--   items  = IDs de ítems que dan el buff de la categoría
--   covers = IDs de hechizos de clase que ocupan el mismo lugar (todos sus rangos):
--            si los tienes puestos, usar el consumible no sirve → no se avisa
--
-- Ítems que no estén aquí (p. ej. propios de WoW Forever) se siguen detectando solos.
-- /cxp db revisa este registro contra los datos del juego.
local ADDON, ns = ...
local L = ns.L

ns.CONS_DB = {
    { key = "str", label = L["Strength"],
      items = { 954, 2289, 4426, 10310,          -- Scroll of Strength I-IV
                2454, 3391, 9206, 13453 } },     -- Lion's Strength, Ogre's Strength, Giants, Brute Force
    { key = "agi", label = L["Agility"],
      items = { 3012, 1477, 4425, 10309,         -- Scroll of Agility I-IV
                2457, 3390, 8949, 9187, 13452 } }, -- Minor/Lesser/–/Greater Agility, Mongoose
    { key = "int", label = L["Intellect"],
      items = { 955, 2290, 4419, 10308,          -- Scroll of Intellect I-IV
                3383, 9179, 13447 },             -- Wisdom, Greater Intellect, Sages
      covers = { 1459, 1460, 1461, 10156, 10157, -- Arcane Intellect 1-5
                 23028 } },                      -- Arcane Brilliance
    { key = "sta", label = L["Stamina"],
      items = { 1180, 1711, 4422, 10307 },       -- Scroll of Stamina I-IV
      covers = { 1243, 1244, 1245, 2791, 10937, 10938, -- Power Word: Fortitude 1-6
                 21562, 21564 } },               -- Prayer of Fortitude
    { key = "spi", label = L["Spirit"],
      items = { 1181, 1712, 4424, 10306 },       -- Scroll of Spirit I-IV
      covers = { 14752, 14818, 14819, 27841,     -- Divine Spirit 1-4
                 27681 } },                      -- Prayer of Spirit
    { key = "armor", label = L["Armor"],
      items = { 3013, 1478, 4421, 10305,         -- Scroll of Protection I-IV
                5997, 3389, 8951, 13445 } },     -- Minor/–/Greater/Superior Defense
    { key = "sp", label = L["Spell power"],
      items = { 9155, 13454 } },                 -- Arcane Elixir, Greater Arcane Elixir
    { key = "shadow", label = L["Shadow power"],
      items = { 9264 } },                        -- Elixir of Shadow Power
    { key = "fire", label = L["Fire power"],
      items = { 6373, 21546 } },                 -- Elixir of Firepower, Greater Firepower
    { key = "frost", label = L["Frost power"],
      items = { 17708 } },                       -- Elixir of Frost Power
    { key = "flask", label = L["Flask"],
      items = { 13510, 13511, 13512, 13513, 13506 } }, -- Titans, Distilled Wisdom, Supreme Power, Chromatic Resistance, Petrification
}

-- Índices: ítem → categoría, clave → categoría
ns.CONS_BY_ITEM, ns.CONS_BY_KEY = {}, {}
for _, c in ipairs(ns.CONS_DB) do
    ns.CONS_BY_KEY[c.key] = c
    c.coverSet = {}
    for _, sid in ipairs(c.covers or {}) do c.coverSet[sid] = true end
    for _, id in ipairs(c.items) do ns.CONS_BY_ITEM[id] = c end
end

local GetItemSpellFn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetSpellNameFn = (C_Spell and C_Spell.GetSpellName) or function(id) return (GetSpellInfo(id)) end

-- IDs de aura de la categoría: el hechizo "Usar" de cada ítem (se completa a medida que el juego lo carga)
function ns.CatUseSpells(c)
    if c.useDone then return c.useSet end
    c.useSet = c.useSet or {}
    local done = true
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

-- Nombres de los buffs de clase que cubren la categoría (por si hay rangos que no están en la lista)
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
    local GetName = function(id) return ns.GetItemName(id) end
    self.Print(L["Consumables registry check:"])
    for _, c in ipairs(ns.CONS_DB) do
        local line = {}
        for _, id in ipairs(c.items) do
            local name = GetName(id)
            local spell, sid = GetItemSpellFn(id)
            local sig = ns.ItemStatSig and ns.ItemStatSig(id)
            if not name then
                line[#line + 1] = "|cffffd100" .. id .. "?|r"
                if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
            elseif not sid then
                line[#line + 1] = "|cffff6060" .. name .. " (no use)|r"
            else
                line[#line + 1] = format("%s|cffaaaaaa(%d→%d %s)|r", name, id, sid, tostring(sig))
            end
        end
        print(format("|cffffffff%s|r: %s", c.label, table.concat(line, ", ")))
        if c.covers then
            local cv = {}
            for _, sid in ipairs(c.covers) do cv[#cv + 1] = (GetSpellNameFn(sid) or "?") .. "(" .. sid .. ")" end
            print("   " .. L["covered by: "] .. table.concat(cv, ", "))
        end
    end
    print(L["Yellow = still loading (run again) · red = item has no Use effect."])
end
