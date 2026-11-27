# SkillsBars

Draggable bars showing your weapon skills, Defense and any other skill you pick — for **World of Warcraft: Forever**.

SkillsBars puts all the skills you care about in one compact, movable block. Equipped weapons are tracked automatically, so you always know how far your current weapon skill is from the cap, and you can add Defense, professions or any other skill line from the minimap menu.

## Features

- **Equipped weapons, automatically**: main hand, off hand and ranged weapon skills are shown as soon as you equip them (Unarmed when the main hand is empty). Can be turned off.
- **Pick any skill**: Defense, weapon skills, professions, secondary skills — everything from your skill window, grouped by category. Languages and 1/1 proficiencies are left out.
- **Per-character selection**: each character keeps its own list of skills; layout settings are shared.
- **Color-coded progress**: the bar color tells you at a glance how close you are to the cap (see below).
- **Skill-up swipe**: a light band slides across the bar every time a skill goes up.
- **Weapon tooltips**: weapon tooltips show your current skill / max for that weapon type, or "Not learned".
- **Detailed bar tooltips**: level, bonus from gear/talents and points remaining. Weapon skills also show the same details as the Skills window: hit and crit chance against an equal-level enemy and against raid bosses, plus glancing blows.
- **Movable and resizable**: drag the block anywhere, resize it from the bottom-right corner, change the scale, or lock it in place.
- **Hide maxed skills**: optionally hide bars that are already at the cap for your level.
- **Minimap button**: left-click for the menu, right-click to show/hide the panel, drag to move it around the minimap.

## Color code

| Progress | Color |
| --- | --- |
| Below 1/3 of max | Red |
| From 1/3 to 2/3 of max | Yellow |
| Above 2/3 of max | Blue (same as skill messages in chat) |
| Maxed for your level | Green |

Inside each band the color gets brighter as the value grows. Bonuses from gear or talents are shown in green next to the value (e.g. `245/300 +5`).

## Commands

Use `/sb` or `/skillsbars`.

| Command | Description |
| --- | --- |
| `/sb menu` | Open the menu (pick skills here) |
| `/sb show` / `hide` / `toggle` | Show or hide the panel |
| `/sb minimap` | Show or hide the minimap button |
| `/sb lock` / `unlock` | Lock or unlock dragging and resizing |
| `/sb reset` | Move the block back to the default position |
| `/sb scale <0.5–2>` | Set the scale |
| `/sb width <80–500>` | Set the block width |
| `/sb height <10–40>` | Set the height of a single bar |
| `/sb hidemax` | Hide skills that are already maxed |
| `/sb test` | Preview the skill-up swipe |

## Installation

1. Download the latest release, or clone this repository.
2. Put the `SkillsBars` folder in `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game or type `/reload`.

## Author

EclipsedPal
