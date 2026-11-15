# CampXP — Plan de diseño: modos Leveling / End Game

Estado: borrador para revisión · Versión objetivo: 1.4.0 (modo) y 1.5.0 (consumibles)

## 1. Objetivo

Al llegar al nivel máximo, la XP deja de importar y lo que importa es entrar a dungeons y raids con los consumibles puestos. CampXP pasa a tener dos modos:

| | **Leveling** (actual) | **End Game** |
|---|---|---|
| Campamento | Igual | Igual (sigue dando beneficios) |
| Saco de dormir | Visible | **Oculto** (solo da XP) |
| Comida | "+5%" de XP | **Estadística que da**, abreviada (ej. "+6 SP") |
| XP perdida / barra de XP / resumen al subir | Activo | **Desactivado** (ya no hay XP) |
| Consumibles elegidos | — | **Nuevo**: ícono + grilla + recordatorios |

## 2. Cambio de modo

- **Automático con confirmación:** al llegar a nivel 60 (o al entrar con un personaje de nivel 60 que nunca respondió) aparece una ventana:
  > "Llegaste al nivel 60. ¿Activar el modo End Game de CampXP?" · [Activar] [Ahora no]
  - "Ahora no" no vuelve a preguntar en ese personaje.
- **Manual:** selector en `/cxp` → **Modo: Leveling / End Game**, y comando `/cxp mode`.
- Se guarda **por personaje** (`CampXPCharDB.mode`).
- Reemplaza la opción actual "Estoy en nivel máximo (oculta todo)": en nivel máximo ya no se oculta todo; manda el modo.

## 3. Íconos en End Game

- **Campamento:** sin cambios (grilla, avisos, juguete).
- **Saco:** oculto, sin avisos ni cálculos.
- **Comida:** sigue la grilla y la detección de Well Fed, pero en vez de "+5%" muestra lo que da el Well Fed activo, leído de su tooltip:
  - "Your Intellect is increased by 1" → **+1 Int**
  - "Stamina and Spirit increased by 6" → **+6 Sta/Spi**
  - "spell power" → **SP**, "attack power" → **AP**, "critical strike" → **Crit**, etc.
  - La tabla de abreviaturas va en `Locale.lua` (inglés y español).
  - En la grilla de comida, en End Game se marcan las comidas por estadística en vez de por XP (insignia con la abreviatura).

## 4. Consumibles (núcleo del modo End Game)

### 4.1 Elegir qué vigilar (interactivo)

Como los consumibles del nivel máximo de WoW Forever todavía no se conocen, **no hay lista fija**: el jugador elige entre lo que tiene.

- Nuevo ícono **"Consumables"** en la fila (cuarto ícono, solo en End Game).
- Clic → grilla (mismo estilo y animación que las demás) con **todos los consumibles de las bolsas** que dan un buff: elixires, flasks, pergaminos y similares (clase Consumible; se excluyen comida/bebida, que ya tiene su ícono).
- **Dos usos en la grilla:**
  - **Clic:** usa el consumible (igual que la comida).
  - **Shift+clic (o clic derecho):** marca/desmarca para **vigilarlo** (estrella en la esquina). Lo marcado se guarda por personaje.
- Los vigilados aparecen primero y con borde de color.

### 4.2 Saber qué buff da cada consumible

Para poder avisar, cada consumible vigilado se asocia a su aura:

1. Efecto "Use:" del ítem (`GetItemSpell`) cuyo hechizo o nombre coincide con un aura → asociación inmediata.
2. Si no coincide: la primera vez que lo usas desde la grilla, el aura nueva que aparece en los segundos siguientes queda asociada (seguro, porque lo eligió el jugador y lo usó desde el addon).
3. Hasta tener la asociación, se muestra "sin verificar" en el tooltip.

### 4.3 Recordatorios

Se revisan los consumibles vigilados en dos momentos:

- **Al entrar a una dungeon o raid** (`PLAYER_ENTERING_WORLD` con `IsInInstance()` = party/raid).
- **En el ready check** (`READY_CHECK`).

Un consumible genera aviso si:
- su buff **no está activo**, o
- le queda **menos de X minutos** (configurable, por defecto 10).

El aviso es uno solo, con la lista: "Missing: Flask of X, Elixir of Y · Expiring: Z (4m)". El ícono Consumables destella y la grilla se puede abrir desde ahí para ponerlos.

Además, **stock bajo**: si de un consumible vigilado quedan ≤ N (configurable), se avisa al entrar a la instancia.

### 4.4 Ícono "Consumables"

- Activo (a color) si **todos** los vigilados están puestos; borde naranja si alguno expira pronto; gris con halo dorado si falta alguno y lo tienes; gris translúcido si falta y no te queda.
- Esquina: "2/3" = vigilados activos / total.

## 5. Configuración (`/cxp`)

- **Modo:** Leveling / End Game.
- Sección **End Game** (visible en ese modo):
  - Minutos restantes para avisar (por defecto 10).
  - Stock bajo (por defecto 2).
  - Avisar al entrar a dungeon/raid (sí/no) · Avisar en ready check (sí/no).
  - Lista de vigilados con botón para quitar.

## 6. Notas técnicas

- **Auras protegidas en combate:** ready check y entrada a instancia ocurren fuera de combate; si las auras están bloqueadas, se revisa al salir de combate.
- **Botones seguros:** la grilla de consumibles no se puede abrir en combate (igual que las otras).
- **Datos nuevos por personaje:** `mode`, `endgameAsked`, `endgame = { tracked = {[itemId]=true}, auraFor = {[itemId]=spellId}, warnMin, lowStock, onInstance, onReadyCheck }`.
- **Sin cambios para quien sigue en Leveling.**

## 7. Fases

| Versión | Contenido |
|---|---|
| **1.4.0** | Modo Leveling/End Game, ventana al nivel 60, saco oculto, comida con estadística abreviada, XP desactivada en End Game |
| **1.5.0** | Ícono y grilla de Consumables, marcar vigilados, asociación ítem → aura, recordatorios al entrar a instancia y en ready check |
| Después | Aceites/piedras de arma (no son auras: `GetWeaponEnchantInfo`), si hacen falta |

## 8. Preguntas abiertas

1. ¿El nivel máximo de WoW Forever es 60 en todas las fases, o conviene leerlo del juego?
2. ¿Los aceites y piedras de afilar del arma entran en la primera versión de consumibles?
3. ¿Las pociones (efecto instantáneo, sin buff) se excluyen de la grilla?
4. Flasks y elixires suelen ser excluyentes entre sí: ¿avisar solo si falta "alguno" de un grupo, o cada uno por separado?
5. ¿Shift+clic para marcar es cómodo, o prefieres clic derecho?
