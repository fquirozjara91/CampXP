-- CampXP localization.
-- 1) Game texts CampXP must RECOGNIZE (aura names, tooltip keywords), per client language.
-- 2) Interface texts CampXP SHOWS: English is the key/default; other languages override.
-- To add a language: copy a GAME[...] block and a UI[...] block, translate and register it.
local ADDON, ns = ...

local current = GetLocale and GetLocale() or "enUS"
ns.locale = current

------------------------------------------------------------------------------
-- 1) Game texts to recognize
------------------------------------------------------------------------------
local GAME = {
    enUS = {
        -- Buff/item tooltip: "Experience gained from kills increased by 5%."
        xpKeywords = { "experience gained", "experience" },
        -- Aura names (fallback in case the server changes spell IDs)
        auraNames = {
            ["Well Fed"]      = "food",
            ["Camp Benefits"] = "campfire",
            ["Well-Rested"]   = "sleepingbag",
            ["Well Rested"]   = "sleepingbag",
        },
        -- "Eating/drinking" auras (not buffs)
        eatingNames = { "Food", "Drink", "Food & Drink", "Refreshment" },
    },
    esES = {
        -- "La experiencia obtenida por muertes aumenta un 5%."
        xpKeywords = { "experiencia obtenida", "experiencia" },
        auraNames = {
            ["Bien alimentado"] = "food",
            ["Descansado"]      = "sleepingbag", -- spell 429959 (esES)
            -- TODO: Camp Benefits (spell 1229741), detected by ID meanwhile
        },
        eatingNames = { "Comida", "Bebida", "Comida y bebida", "Refrigerio" },
    },
    esMX = {
        xpKeywords = { "experiencia obtenida", "experiencia" },
        auraNames = {
            ["Bien alimentado"]  = "food",
            ["Bien descansado"]  = "sleepingbag", -- spell 429959 (esMX)
            -- TODO: Camp Benefits (spell 1229741), detected by ID meanwhile
        },
        eatingNames = { "Comida", "Bebida", "Comida y bebida", "Refrigerio" },
    },
}
GAME.enGB = GAME.enUS

-- Client language + English as fallback
local function Build(field)
    local list, seen = {}, {}
    for _, loc in ipairs({ GAME[current] or GAME.enUS, GAME.enUS }) do
        local v = loc[field]
        if v then
            for k, val in pairs(v) do
                local key = type(k) == "number" and val or k
                if not seen[key] then
                    seen[key] = true
                    if type(k) == "number" then table.insert(list, val) else list[k] = val end
                end
            end
        end
    end
    return list
end

ns.LOC = {
    xpKeywords = Build("xpKeywords"),
    auraNames = Build("auraNames"),
    eatingNames = {},
}
for _, n in ipairs(Build("eatingNames")) do ns.LOC.eatingNames[n] = true end

-- Does the text mention experience? Returns true and the % (if present), or false.
function ns.ParseXP(text)
    if not text or text == "" then return false end
    local lower = text:lower()
    for _, kw in ipairs(ns.LOC.xpKeywords) do
        local pos = lower:find(kw, 1, true)
        if pos then
            local pct = lower:match("(%d+)%s*%%", pos)
            return true, tonumber(pct)
        end
    end
    return false
end

------------------------------------------------------------------------------
-- 2) Interface texts (English is the default)
------------------------------------------------------------------------------
local UI = {}

UI.esES = {
    -- Categories
    ["Campfire"] = "Campamento",
    ["Sleeping Bag"] = "Saco de dormir",
    ["XP Food"] = "Comida XP",
    -- Alert kinds
    ["About to expire"] = "Por expirar",
    ["Missing (item in bags)"] = "Falta (tengo ítem)",
    ["Ran out, no items left"] = "Se acabó sin ítems",
    ["Low stock"] = "Stock bajo",
    ["Max stacks reached"] = "Stacks completos",
    -- Bonus texts
    ["+5% kill XP (as stated by the food tooltip)"] = "+5% XP de muertes (según el tooltip de la comida)",
    ["+1% to all XP per stack (max +3% at 3 stacks)"] = "+1% a toda la XP por stack (máx +3% con 3 stacks)",
    ["No XP bonus"] = "Sin bonus de XP",
    -- Key binding
    -- Alerts
    ["%s ends in %s"] = "%s se acaba en %s",
    ["%s missing: you have %d in your bags (click the icon)"] = "%s sin buff: tienes %d en bolsas (clic en el icono)",
    ["%s ran out and you have none left"] = "%s se acabó y no te quedan",
    ["%s: only %d left"] = "%s: quedan solo %d",
    ["%s: max stacks (+%d%% kills, +%d%% quests), you can get up now"] = "%s: stacks completos (+%d%% muertes, +%d%% misiones), ya puedes levantarte",
    ["%s: test alert"] = "%s: aviso de prueba",
    -- Summary
    ["no buff"] = "sin buff",
    ["%s: %s (%d in bags)"] = "%s: %s (%d en bolsas)",
    ["Summary: "] = "Resumen: ",
    ["Status: "] = "Estado: ",
    ["Heading out: "] = "Saliendo a explorar: ",
    ["No buffs tracked."] = "No hay buffs vigilados.",
    -- Food detection
    ["buff tooltip (+%d%% XP)"] = "tooltip del buff (+%d%% XP)",
    ["food %s"] = "comida %s",
    ["food without XP (%s)"] = "comida sin XP (%s)",
    ["Well Fed without XP (stats only)"] = "Well Fed sin XP (solo estadísticas)",
    ["checking..."] = "verificando...",
    ["XP food detected: %s (%d)"] = "Comida XP detectada: %s (%d)",
    ["Detected: %s (%d) → %s"] = "Detectado: %s (%d) → %s",
    ["Item %s linked to %s"] = "Ítem %s asociado a %s",
    ["XP FOOD"] = "COMIDA XP",
    ["NORMAL"] = "NORMAL",
    ["You have no food buff active."] = "No tienes ningún buff de comida activo.",
    -- Commands
    ["Not available in combat."] = "No disponible en combate.",
    ["Positions reset."] = "Posiciones restablecidas.",
    ["Frames locked"] = "Marcos bloqueados",
    ["Frames unlocked"] = "Marcos desbloqueados",
    -- Icons
    ["ON"] = "ON",
    ["Use!"] = "¡Usar!",
    ["active"] = "activo",
    ["No buff"] = "Sin buff",
    ["Detection: "] = "Detección: ",
    ["Item %d"] = "Ítem %d",
    ["Bonus on kills"] = "Bonus por muertes",
    ["Bonus on quests/other"] = "Bonus en misiones/otras",
    ["Would give on kills"] = "Daría por muertes",
    ["Would give on quests/other"] = "Daría en misiones/otras",
    ["%d/%d stacks"] = "%d/%d stacks",
    ["Sleep %d more min on the bag for +%d%% on kills"] = "Duerme %d min más sobre el saco para +%d%% en muertes",
    ["XP lost without this buff (session): |cffff4040-%s|r"] = "XP perdida sin este buff (sesión): |cffff4040-%s|r",
    ["This buff is not registered in the addon."] = "Este buff no está registrado en el addon.",
    ["Click: choose food · Shift+drag: move"] = "Clic: elegir comida · Shift+arrastrar: mover",
    ["Click: use item · Shift+drag: move"] = "Clic: usar ítem · Shift+arrastrar: mover",
    -- Food picker
    ["Choose a food"] = "Elige una comida",
    ["You have no food in your bags."] = "No tienes comida en las bolsas.",
    ["Eat anyway"] = "Comer igual",
    ["No"] = "No",
    ["Don't ask again"] = "No volver a preguntar",
    ["Couldn't read the tooltip of\n|cffffd100%s|r.\nEat it anyway?"] = "No pude leer el tooltip de\n|cffffd100%s|r.\n¿Comerla igual?",
    ["|cffffd100%s|r gives no experience.\nEat it anyway?"] = "|cffffd100%s|r no da experiencia.\n¿Comerla igual?",
    ["CampXP: gives +%d%% XP"] = "CampXP: da +%d%% XP",
    ["CampXP: gives no experience"] = "CampXP: no da experiencia",
    ["CampXP: loading item data..."] = "CampXP: cargando datos del ítem...",
    ["You can't use the grid in combat."] = "No puedes usar la grilla en combate.",
    ["Choose a camp item"] = "Elige un objeto de campamento",
    ["You have no campfire kits or camp items in your bags."] = "No tienes kits de fogata ni objetos de campamento en las bolsas.",
    ["Click: choose camp item · Shift+drag: move"] = "Clic: elegir objeto de campamento · Shift+arrastrar: mover",
    ["Grid position"] = "Posición de las grillas",
    ["Icon style: %s"] = "Estilo de iconos: %s",
    ["Icon style"] = "Estilo de iconos",
    ["locked (lvl 14 quest)"] = "bloqueado (misión nivel 14)",
    ["Unlocks with the level 14 quest \"This Must Be the Place\"."] = "Se desbloquea con la misión de nivel 14 \"This Must Be the Place\".",
    ["Round"] = "Redondo",
    ["Minimal"] = "Minimalista",
    ["Classic"] = "Clásico",
    ["Right"] = "Derecha",
    ["Left"] = "Izquierda",
    ["Above"] = "Arriba",
    ["Below"] = "Abajo",
    -- Settings
    ["CampXP - XP Buffs"] = "CampXP - Buffs de XP",
    ["Tracked buffs"] = "Buffs a vigilar",
    ["Alert when:"] = "Avisar cuando:",
    ["Options"] = "Opciones",
    ["Confirm before eating food without XP"] = "Confirmar antes de comer comida sin XP",
    ["Alert sound"] = "Sonido en los avisos",
    ["Big on-screen alert"] = "Aviso grande en pantalla",
    ["XP gained/lost in the XP bar tooltip"] = "XP ganada/perdida en el tooltip de la barra de XP",
    ["Show XP lost above the buff icon"] = "Mostrar XP perdida sobre el icono del buff",
    ["XP gained/lost summary on level up"] = "Resumen de XP ganada/perdida al subir de nivel",
    ["Lock frames"] = "Bloquear marcos",
    ["Hide minimap button"] = "Ocultar botón del minimapa",
    ["Don't alert when..."] = "No avisar cuando...",
    ["I'm in combat (alerts after)"] = "Estoy en combate (avisa al salir)",
    ["I'm in a city / inn"] = "Estoy en ciudad / posada",
    ["I'm mounted"] = "Voy montado",
    ["I'm max level (hides everything)"] = "Estoy en nivel máximo (oculta todo)",
    ["Warn before expiring"] = "Avisar antes de expirar",
    ["Remind if missing (min)"] = "Recordar si falta (min)",
    ["Low stock alert"] = "Aviso de stock bajo",
    ["off"] = "off",
    ["%d min"] = "%d min",
    ["Test alerts"] = "Probar avisos",
    ["Reset positions"] = "Resetear posiciones",
    ["Buff not registered"] = "Buff no registrado",
    ["In bags: |cffffffff%d|r foods that give XP"] = "En bolsas: |cffffffff%d|r comidas que dan XP",
    ["In bags: no food that gives XP"] = "En bolsas: ninguna comida que dé XP",
    ["In bags: "] = "En bolsas: ",
    ["In bags: none (detected when used)"] = "En bolsas: ninguno (se detecta al usarlo)",
    -- Minimap
    ["Use! (%d)"] = "¡Usar! (%d)",
    ["no items"] = "sin ítems",
    ["not detected"] = "no detectado",
    ["disabled"] = "desactivado",
    ["Click: settings · Drag: move"] = "Clic: configuración · Arrastrar: mover",
    -- XP tracking
    ["Level %d: |cffffcc1a+%s XP|r from buffs · |cffff4040-%s XP|r lost without buffs"] = "Nivel %d: |cffffcc1a+%s XP|r gracias a buffs · |cffff4040-%s XP|r perdida sin buffs",
    ["Session: |cffffcc1a+%s XP|r from buffs · |cffff4040-%s XP|r lost without buffs"] = "Sesión: |cffffcc1a+%s XP|r gracias a buffs · |cffff4040-%s XP|r perdida sin buffs",
    ["This level: +%s / -%s"] = "Este nivel: +%s / -%s",
    ["XP from buffs (session)"] = "XP por buffs (sesión)",
    ["XP lost without buffs (session)"] = "XP perdida sin buffs (sesión)",
    ["CampXP (this level)"] = "CampXP (este nivel)",
    ["Gained from buffs"] = "Ganada gracias a buffs",
    ["Lost without buffs"] = "Perdida sin buffs",
    -- End Game / consumables
    ["Tracked groups:"] = "Grupos vigilados:",
    ["Your buffs:"] = "Tus buffs:",
    ["Tracking %s → buff: %s"] = "Vigilando %s → buff: %s",
    ["Linked: %s → %s"] = "Vinculado: %s → %s",
    ["Link reset: %s"] = "Vínculo reiniciado: %s",
    ["(not seen yet)"] = "(aún no visto)",
    ["manual"] = "manual",
    ["confirmed"] = "confirmado",
    ["not seen yet"] = "aún no visto",
    ["Buff: %s (%s)"] = "Buff: %s (%s)",
    ["Link to an active buff"] = "Vincular a un buff activo",
    ["You have no buffs active"] = "No tienes buffs activos",
    ["Reset buff link"] = "Reiniciar vínculo",
    ["CampXP: tracked · buff: %s"] = "CampXP: vigilado · buff: %s",
    ["CampXP: buff %s"] = "CampXP: buff %s",
    ["Consumables in bags (class 0):"] = "Consumibles en bolsas (clase 0):",
    ["Report a problem..."] = "Reportar un problema...",
    ["Report a problem"] = "Reportar un problema",
    ["1. Copy the link (Ctrl+C) and open it in your browser:"] = "1. Copia el link (Ctrl+C) y ábrelo en tu navegador:",
    ["2. Copy the suggested message and paste it in a comment:"] = "2. Copia el mensaje sugerido y pégalo en un comentario:",
    ["Suggested message"] = "Mensaje sugerido",
    ["Selected: press Ctrl+C to copy it. Add what went wrong at the end."] = "Seleccionado: presiona Ctrl+C para copiarlo. Agrega al final qué falló.",
    ["Food"] = "Comida",
    ["(unverified)"] = "(sin verificar)",
    ["Buff missing"] = "Falta el buff",
    ["CampXP: Well Fed %s"] = "CampXP: Bien alimentado %s",
    ["CampXP: gives Well Fed"] = "CampXP: da Bien alimentado",
    ["CampXP: no Well Fed"] = "CampXP: no da Bien alimentado",
    ["CampXP: tracked"] = "CampXP: vigilado",
    ["CampXP: you reached level %d.\nSwitch to End Game mode?\n\n|cffaaaaaaHides the Sleeping Bag and XP tracking, shows food stats and adds a Consumables icon.|r"] = "CampXP: llegaste al nivel %d.\n¿Activar el modo End Game?\n\n|cffaaaaaaOculta el saco y el seguimiento de XP, muestra las estadísticas de la comida y agrega el icono de Consumibles.|r",
    ["Check consumables on ready check"] = "Revisar consumibles en el ready check",
    ["Check consumables when entering a dungeon/raid"] = "Revisar consumibles al entrar a dungeon/raid",
    ["Click: consumables grid · Shift+drag: move"] = "Clic: grilla de consumibles · Shift+arrastrar: mover",
    ["Commands: /cxp (settings) · mode · style · xp · food · status · test · lock · reset"] = "Comandos: /cxp (configuración) · mode · style · xp · food · status · test · lock · reset",
    ["Consumables"] = "Consumibles",
    ["Consumables (right-click: track)"] = "Consumibles (clic derecho: vigilar)",
    ["Consumables low stock"] = "Stock bajo de consumibles",
    ["Enable"] = "Activar",
    ["End Game"] = "End Game",
    ["Leveling"] = "Leveling",
    ["End Game: Sleeping Bag and XP tracking hidden, food shows its stats, Consumables icon."] = "End Game: saco y seguimiento de XP ocultos, la comida muestra su estadística, icono de Consumibles.",
    ["Expiring: "] = "Por expirar: ",
    ["In bags: no food that gives Well Fed"] = "En bolsas: ninguna comida que dé Bien alimentado",
    ["In bags: |cffffffff%d|r foods that give Well Fed"] = "En bolsas: |cffffffff%d|r comidas que dan Bien alimentado",
    ["Left-click: use"] = "Clic izquierdo: usar",
    ["Leveling: XP buffs and XP lost."] = "Leveling: buffs de XP y XP perdida.",
    ["Little time left"] = "Queda poco tiempo",
    ["Low stock: "] = "Stock bajo: ",
    ["Missing: "] = "Faltan: ",
    ["Mode"] = "Modo",
    ["Mode: End Game"] = "Modo: End Game",
    ["Mode: Leveling"] = "Modo: Leveling",
    ["No longer tracking %s"] = "Ya no se vigila %s",
    ["Not now"] = "Ahora no",
    ["Nothing tracked yet."] = "Nada vigilado todavía.",
    ["Nothing tracked yet. Click to open the grid and right-click a consumable to track it."] = "Nada vigilado todavía. Clic para abrir la grilla y clic derecho en un consumible para vigilarlo.",
    ["Open the Consumables grid and right-click an item to track it and choose its alerts."] = "Abre la grilla de Consumibles y haz clic derecho en un ítem para vigilarlo y elegir sus avisos.",
    ["Right-click: track and alerts"] = "Clic derecho: vigilar y avisos",
    ["Shows the stat of your Well Fed"] = "Muestra la estadística de tu Bien alimentado",
    ["Track this buff"] = "Vigilar este buff",
    ["Tracked: |cffffffff%d|r · active: |cffffffff%d|r"] = "Vigilados: |cffffffff%d|r · activos: |cffffffff%d|r",
    ["Tracking %s"] = "Vigilando %s",
    ["Warn if less than (min)"] = "Avisar si quedan menos de (min)",
    ["Weapon enchant"] = "Encantamiento de arma",
    ["You can switch modes anytime in /cxp or with /cxp mode."] = "Puedes cambiar de modo cuando quieras en /cxp o con /cxp mode.",
    ["You have no consumables with a buff in your bags."] = "No tienes consumibles con buff en tus bolsas.",
    ["missing"] = "falta",
    ["nothing tracked"] = "nada vigilado",
    ["SP"] = "PH",
    ["AP"] = "PA",
    ["Crit"] = "Crít",
    ["Hit"] = "Golpe",
    ["Heal"] = "Sana",
    ["Sta"] = "Agu",
    ["Spi"] = "Esp",
    ["Str"] = "Fue",
    ["Armor"] = "Arm",
    ["Haste"] = "Cel",
    ["Dodge"] = "Esq",
}
UI.esMX = UI.esES

-- L["English text"] → text in the client language (or the English one)
ns.L = setmetatable(UI[current] or {}, { __index = function(_, k) return k end })
