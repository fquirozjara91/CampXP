-- Generado desde CHANGELOG.md por tools/gen_changelog.py (no editar a mano)
local ADDON, ns = ...
ns.CHANGELOG = [[
## 1.4.0
- New Leveling / End Game mode (`/cxp mode`), offered when you reach level 60. End Game is in beta.
- End Game: Sleeping Bag and XP tracking hidden; food shows its Well Fed stat.
- New Consumables icon: tracks the elixirs, flasks, scrolls and weapon stones/oils in your bags, with reminders on dungeon/raid entry and ready check.
- Consumables registry: buffs that don't stack count as one, and class buffs (e.g. Arcane Intellect) cover their scroll.
- Settings window with tabs: General, Tooltip, Design, Notifications and Changelog.
- Icon text size option.

## 1.3.0
- Pouch of Violet Dust (toy) now shows in the camp grid when you own it.

## 1.2.3
- XP lost is now always counted when a buff is missing, even if you don't carry the item.

## 1.2.2
- The Sleeping Bag icon stays hidden until you complete "This Must Be the Place" (level 14).

## 1.2.1
- Fixed: XP food losses were also counted on quest XP (food only boosts kills).

## 1.2.0
- New icon styles: Round (default), Minimal and Classic (`/cxp style`).
- Grids follow the icon style; in Round they slide in and out from the icons.
- Tooltips now use your default tooltip position (Edit Mode).

## 1.1.1
- Food and camp items are used from your smallest stack first.

## 1.1.0
- New camp picker: Campfire Kits and camp features in a grid.
- One-click Sleeping Bag.
- Configurable grid position.
- Removed the "use next consumable" key binding.
- Fixed unrelated items showing on the Campfire / Sleeping Bag icons.

## 1.0.0
- Initial release: Camp Benefits, Well-Rested and XP food tracking, food picker, XP lost tracking, alerts and minimap button. English and Spanish.
]]
