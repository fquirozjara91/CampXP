# CampXP

**Your buffs, always up — from level 1 to raid night.**

CampXP watches the buffs that matter in WoW Forever and tells you when one is missing, about to run out, or when you're running low on the item that gives it. While leveling it tracks your **XP buffs** and shows exactly how much experience you lose without them. At level 60 it switches to **End Game mode** and keeps your **consumables** in check before every dungeon and raid.

---

## Leveling mode

Three icons for the three WoW Forever XP buffs:

- **Camp Benefits** — click the icon to open a grid with your Campfire Kits (Expert → Journeyman → Basic) and every camp feature you carry, sorted by profession. Click one to place it.
- **Well-Rested** (Cozy Sleeping Bag) — click to use it. The icon shows your stacks (1/3, 2/3, 3/3) and tells you when you can get up.
- **XP food** — click to open a grid with the food in your bags. XP foods are marked and sorted first, and CampXP asks before you eat one that gives no XP (optional).

**Accurate detection:** not every *Well Fed* gives XP. CampXP reads the buff and item tooltips, so only real XP food counts.

**XP lost tracking:**
- Extra lines in the default XP bar tooltip: XP gained thanks to each buff and XP lost without it, this level.
- A small red **-N** above the icon of the buff you're missing.
- A summary in chat when you level up.
- Correct math: food only boosts kill XP, Well-Rested boosts all XP (+1% per stack), bonuses add up and rested XP is excluded.

## End Game mode (beta)

When you reach level 60, CampXP offers to switch (or use `/cxp mode` anytime):

- The Sleeping Bag and XP tracking are hidden.
- The food icon shows the stat of your **Well Fed** ("+6 Sta/Spi"), and the food grid marks each food with its stat — in the colors you choose.
- A new **Consumables** icon tracks the elixirs, flasks, scrolls and weapon stones/oils in your bags, **automatically**:
  - Shows how many are up ("3/4") and the time of the one that expires first.
  - **Reminders when you enter a dungeon/raid and on ready check**: what's missing, what's about to expire, and what's running low.
  - Buffs that **don't stack count as one** (Scroll of Strength and Elixir of Ogre's Strength: the stronger one wins).
  - **Class buffs cover their scroll**: if a mage gives you Arcane Intellect, CampXP won't ask you to use your Scroll of Intellect.
  - **Weapon stones, oils and poisons**, even with Windfury on the same weapon. When dual wielding, clicking one shows your two weapons (main hand left, off-hand right) with their current enchant, so you choose where it goes.
  - The green check in the grid means that buff is already up.
  - Learns exactly which buff each item gives the moment you use it. Right-click any item to stop tracking it, link it to a buff by hand, choose its alerts or **report a problem**.

*End Game mode is in beta: consumable detection is still being tuned. Reports are very welcome.*

## Settings (`/cxp`)

- **General** — mode switch, a live table of your tracked buffs (status, time, items in bags, bonus) and behavior options.
- **Tooltip** — for each icon, choose which lines show **always, only while holding Shift, or never**, with a live preview.
- **Design** — icon style (Round, Minimal, Classic), size, spacing, horizontal/vertical layout, text sizes, what text to show, grid position/columns/button size, and stat colors in the grid. Live preview included.
- **Notifications** — big on-screen text (position and size), chat message, icon flash, sounds for each type of alert (with a play button), reminder timing, a per-buff alert table, "don't alert when…" (combat, city, mounted, dead, flying, AFK, in a dungeon) and test buttons.
- **Changelog** — what's new, right in the game.

## Commands

| Command | Description |
|---|---|
| `/cxp` | Open settings |
| `/cxp mode` | Switch between Leveling and End Game |
| `/cxp style` | Switch icon style (Round → Minimal → Classic) |
| `/cxp xp` | XP gained/lost this session and level |
| `/cxp status` | Current state of your buffs |
| `/cxp food` | How your current Well Fed was classified |
| `/cxp cons` | Consumables in your bags and how they are detected |
| `/cxp test` | Test the alerts |
| `/cxp lock` | Lock/unlock frames |
| `/cxp reset` | Reset frame positions |

Move the icons with **Shift + drag**. A **minimap button** gives you a quick status and opens the settings.

## Notes

- During combat the game hides aura data from addons; CampXP keeps showing the last known state and refreshes when combat ends.
- Grid buttons can't be used in combat (Blizzard restriction).
- English and Spanish (esES/esMX).

---

# CampXP (Español)

**Tus buffs siempre activos, del nivel 1 a la noche de raid.**

CampXP vigila los buffs que importan en WoW Forever y te avisa cuando falta uno, cuando está por acabarse o cuando te queda poco del ítem que lo da. Mientras subes de nivel controla tus **buffs de XP** y te muestra cuánta experiencia pierdes sin ellos. Al nivel 60 pasa al **modo End Game** y cuida tus **consumibles** antes de cada dungeon y raid.

## Modo Leveling

- **Camp Benefits:** clic en el ícono para elegir kit de fogata u objeto de campamento en una grilla.
- **Well-Rested** (saco de dormir): clic para usarlo; muestra los stacks (1/3, 2/3, 3/3) y avisa cuando ya puedes levantarte.
- **Comida con XP:** clic para elegir en una grilla; las de XP van primero y marcadas, y pregunta antes de comer una sin XP (opcional).
- Detección real de comida con XP leyendo los tooltips.
- **XP perdida:** en el tooltip de la barra de XP, sobre el ícono (**-N**) y en el chat al subir de nivel, con el cálculo correcto de cada bonus.

## Modo End Game (beta)

- Se ofrece al llegar al nivel 60 (o con `/cxp mode`). Oculta el saco y la XP.
- La comida muestra la estadística de tu **Bien alimentado** y la grilla la marca con el color que elijas.
- Ícono de **Consumibles** que vigila **automáticamente** elixires, frascos, pergaminos y piedras/aceites de tus bolsas:
  - Avisos **al entrar a dungeon/raid y en el ready check**: qué falta, qué está por expirar y qué te queda poco.
  - Los buffs que **no se acumulan cuentan como uno** (gana el mayor) y los **buffs de clase cubren su pergamino** (con Arcane Intellect no te pide el pergamino de Intelecto).
  - **Piedras, aceites y venenos** de arma, incluso con Windfury. Con dos armas, al hacer clic eliges en cuál aplicarlo (principal a la izquierda, secundaria a la derecha).
  - Check verde en la grilla = ese buff ya está puesto. Clic derecho para dejar de vigilar, vincular a mano, elegir avisos o **reportar un problema**.

*El modo End Game está en beta: la detección de consumibles aún se está ajustando. Los reportes son bienvenidos.*

## Configuración (`/cxp`)

- **General:** modo, tabla en vivo de tus buffs y comportamiento.
- **Tooltip:** por cada ícono, qué líneas se ven siempre, solo con Shift o nunca, con vista previa.
- **Diseño:** estilo, tamaño, espacio, orientación, textos, grilla y colores de estadísticas, con vista previa.
- **Notificaciones:** texto grande (posición y tamaño), chat, destello, sonidos por tipo de aviso, tiempos, tabla de avisos por buff, "no avisar cuando…" y botones de prueba.
- **Novedades:** el changelog dentro del juego.

Comandos: `/cxp`, `/cxp mode`, `/cxp style`, `/cxp xp`, `/cxp status`, `/cxp food`, `/cxp cons`, `/cxp test`, `/cxp lock`, `/cxp reset`. Mueve los íconos con **Shift + arrastrar**.
