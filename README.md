# Tumstock

Tumstock shows the approximate distance to your target, mouseover or focus in World of Warcraft: Forever (1.60.1), in brackets as fine as the game allows: `<5`, `5-8`, `8-9`, `9-10`, `10-15`, then 5-yard steps up to `40-45`, `45-100` and `100+`.

The name is Swedish for a folding ruler.

## Features

- **Text box**: the current bracket, for example `15-20`, with a letter for the unit it measures (T, M or F)
- **Distance bar**: 0-50 yards, vertical or horizontal, with an arrow that glides to the current distance and a highlight over the bracket the unit is in
- **Colors**: green in melee, white at mid range, orange and red far away. Smooth blend, hard bands or off
- **Nameplate readouts**: a small bracket above enemy and friendly nameplates
- **Unit priority**: target first, then mouseover, then focus (each can be turned off)
- **Settings window**: text box and/or bar, size, length, thickness, opacity per unit type, tick marks, labels, hide in combat or with no unit
- **Minimap button**: left-click for settings, right-click to lock or unlock the displays
- No library dependencies

## How it measures

The game does not tell addons the exact distance to enemies. Tumstock checks which items, spells and interactions are in range and narrows the distance down to a bracket. On WoW Forever the item checks give 5-yard steps; interact distances add 8 and 9 yards. Exact distance is only shown for group members.

## Installation

1. Download the latest file.
2. Extract the ZIP into `World of Warcraft/_forever_/Interface/AddOns`.
3. Make sure the `Tumstock` folder is directly inside `Interface/AddOns`.
4. Enable the addon on the character selection screen, or restart the game if it is running.

## Commands

| Command | What it does |
| --- | --- |
| `/tum` | Opens the settings |
| `/tum lock` / `/tum unlock` | Locks the displays, or unlocks them to drag them |
| `/tum bar` | Shows the bar in its default spot, unlocked |
| `/tum reset` | Moves the displays back to their default spots |
| `/tum minimap` | Shows or hides the minimap button |
| `/tum debug` | Test tools |

## Status

This is a beta. Enemy ranges are tested; friendly targets, nameplate readouts and the 8/9-yard interact distances are not fully verified yet.

## License

MIT, see [LICENSE](LICENSE). Item data comes from LibRangeCheck-3.0 (MIT).
