-- Registro de comidas conocidas en WoW Forever (comprobadas en el juego).
-- Solo es un respaldo: CampXP sigue leyendo el tooltip de cada comida. Sirve para
-- reconocer una comida de XP aunque su tooltip todavía no haya cargado del todo.
--
--   xp   = % de XP que da (solo comidas de XP)
--   wf   = da Well Fed
--   keys = estadísticas que da, en orden (las abreviaturas de ns.STAT_KEYS)
local ADDON, ns = ...

ns.FOOD_DB = {
    -- (generado por tools/import_discoveries.py: no editar a mano dentro del bloque)
    -- BEGIN DISCOVERED
    [4457] = { xp = 5, wf = true, keys = { "Int" } }, -- Barbecued Buzzard Wing
    [249870] = { xp = 5, wf = true, keys = { "Heal" } }, -- Sage's Tea (Wowhead)
    [250068] = { xp = 5, wf = true, keys = { "Sta" } }, -- Savory Turtle Stew (Wowhead)
    [250069] = { xp = 5, wf = true, keys = { "Agi" } }, -- Flank au Poivre (Wowhead)
    -- END DISCOVERED
}
