# Changelog

## 1.4.3
- End Game: when dual wielding, clicking a weapon stone, oil or poison in the Consumables grid now lets you choose the weapon: main hand on the left, off-hand on the right, each with its current enchant and time left. With one weapon it is applied directly, as before.
- Improved consumable detection data.

## 1.4.2
- End Game: foods that give movement speed (e.g. Sweetpaw Jam) now show "Mov" instead of "WF", with its own color in Design.
- Improved consumable and food detection: CampXP now ships with a registry of known foods and verified data for consumables (new Forever elixirs, Mageblood and Fortitude ranks), so they are recognized right away.
- Fixed: eating and then drinking credited the Well Fed to the drink.
- Fixed: weapon stones and oils are now linked to their enchant reliably the first time you apply them.
- Flask of Petrification is no longer listed as a consumable (it only lasts 1 minute).

## 1.4.1
- New CampXP logo on the minimap button and in the AddOns list.
- Favorites: right-click a food or consumable in the grid to mark it; favorites show a star, come first and are the item the icon uses.
- Food grid: right-click opens a menu (favorite, what CampXP detected, report a problem) instead of eating.
- End Game: foods with several stats show one badge line per stat in its own color (e.g. Sta / Spi).

## 1.4.0
- New Leveling / End Game mode (`/cxp mode`), offered when you reach level 60. End Game is in beta.
- End Game: Sleeping Bag and XP tracking hidden; food shows its Well Fed stat (e.g. "+6 Sta/Spi").
- New Consumables icon: tracks the elixirs, flasks, scrolls and weapon stones/oils in your bags, with reminders on dungeon/raid entry and ready check.
- Consumables registry: buffs that don't stack count as one, and class buffs (e.g. Arcane Intellect) cover their scroll.
- New settings window with tabs: General, Tooltip, Design, Notifications and Changelog.
- Tooltip: choose per icon which lines show always, only with Shift, or never, with a live preview.
- Design: icon size, spacing, orientation, text sizes, grid columns/size, and stat colors in the grid (End Game), with a live preview.
- Notifications: big text position/size, chat and flash toggles, sounds per alert, more "don't alert when" options and test buttons.

## 1.3.1
- Fixed: XP food eaten for the first time (e.g. Seasoned Wolf Kabob) was sometimes not recognized until eaten again.
- Thanks to the Sioul clan for the feedback!

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
