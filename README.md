# CampXP

**Never level without your XP buffs again.** CampXP tracks the three WoW Forever XP buffs — **Camp Benefits**, **Well-Rested** (Cozy Sleeping Bag) and **XP food** — and tells you how much experience you're losing when one of them is missing.

## Features

- **Three buff icons** with a countdown, a border that turns orange when a buff is about to expire, and a gentle glowing halo when it's missing and you have the item in your bags.
- **Icon styles:** Round (default), Minimal (rounded squares) or Classic — pick one in `/cxp` or with `/cxp style`.
- **One-click Sleeping Bag:** click its icon to use it.
- **Camp picker:** click the Campfire icon to open a grid with your Campfire Kits (Expert → Journeyman → Basic) followed by every camp feature you carry (Mana Well, Camp Chair, Fish Bowl…), sorted by profession and tier. Click one to place it. If you own the Pouch of Violet Dust toy, it shows right after the kits.
- **Food picker:** click the XP Food icon to open a grid with every food in your bags. Foods that give XP are marked and sorted first. If you pick one that gives no XP, CampXP asks before eating it (optional).
- **Accurate XP food detection:** not every *Well Fed* gives XP. CampXP reads the item and buff tooltips ("Experience gained from kills increased by 5%") so only real XP food counts.
- **Sleeping Bag stacks:** the icon shows 1/3, 2/3, 3/3 and alerts you when you reach max stacks.
- **XP lost tracking:**
  - Extra lines in the default XP bar tooltip: XP gained from buffs and XP lost without them this level, per buff (counted whether or not you carry the item).
  - A small red **-N** above the icon of the buff you're missing.
  - A summary in chat when you level up.
- **Correct math:** food only boosts kill XP; Well-Rested boosts all XP (+1% per stack). Bonuses are additive and rested XP is excluded.
- **Smart alerts:** about to expire, missing with the item in your bags, ran out, low stock, max stacks. Each alert can be toggled per buff. Alerts wait while you're in combat, in a city or mounted.
- **Grid position:** both grids can open to the right, left, above or below the icons.
- **Minimap button** with a quick status tooltip.
- **English and Spanish** (esES/esMX).

## Commands

| Command | Description |
|---|---|
| `/cxp` | Open settings |
| `/cxp style` | Switch icon style (Round → Minimal → Classic) |
| `/cxp xp` | XP gained/lost this session and level |
| `/cxp status` | Current state of your buffs |
| `/cxp food` | How your current Well Fed was classified |
| `/cxp test` | Test the alerts |
| `/cxp lock` | Lock/unlock frames |
| `/cxp reset` | Reset frame positions |

Move the icons with **Shift + drag**.

## Notes

- During combat the game hides aura data from addons; CampXP keeps showing the last known state and refreshes when combat ends.
- Food picker buttons can't be used in combat (Blizzard restriction).

---

# CampXP (Español)

**No vuelvas a subir de nivel sin tus buffs de XP.** CampXP vigila los tres buffs de XP de WoW Forever (**Camp Benefits**, **Well-Rested** del saco de dormir y la **comida con XP**) y te dice cuánta experiencia pierdes cuando te falta alguno.

- Iconos con cuenta regresiva, aviso al expirar y pulso cuando falta el buff y tienes el ítem.
- Clic en el saco para usarlo; clic en el campamento para elegir kit de fogata u objeto de campamento; clic en la comida para elegir en una grilla (las de XP van primero y marcadas). La posición de las grillas es configurable.
- Detección real de comida XP leyendo los tooltips.
- Stacks del saco (1/3, 2/3, 3/3) y aviso al completarlos.
- XP perdida: en el tooltip de la barra de XP del juego, sobre el icono y en el chat al subir de nivel.
- Avisos configurables por buff; esperan si estás en combate, en ciudad o montado.
- Estilos de iconos: Redondo (por defecto), Minimalista o Clásico.
- Comandos: `/cxp`, `/cxp style`, `/cxp xp`, `/cxp status`, `/cxp food`, `/cxp test`, `/cxp lock`, `/cxp reset`.
