# FFmarks

Fast raid target marks, world markers and pings from a pop-up menu.
Hold a key, point at an icon, release. Works in combat.

Clients: World of Warcraft: Forever (Interface 16001) and Retail (Interface 120105).

## Features

- **Four menus**, each with its own key or "base key + modifiers":
  - **Markers Units**: raid target icon on mouseover or target (`/tm`). If there is no unit, it can place a world marker under the cursor instead.
  - **Markers World**: world marker on the ground under the cursor (`/wm [@cursor]`).
  - **Ping**: ping on mouseover or target. If there is no unit, it can ping the ground instead.
  - **Ping World**: ping under the cursor.
- **Layouts**: ring, grid, horizontal row or vertical row. Anchor at the cursor or at a fixed screen position (drag to move while unlocked).
- **Selection**:
  - Point at an icon (hover).
  - Mouse wheel while the key is held, with an optional preselected start icon.
  - Toggle mode: press to open, press again or left click to apply, Escape to cancel.
- **Center region**:
  - Release in the center to cancel, clear the mark, or clear all world markers.
  - "Center release" icon.
  - Click-in-center bindings (mouse button + modifiers → icon).
- **Fast mark**:
  - A quick tap places a chosen icon without picking.
  - A double tap places a second icon.
  - Modes with no time limit.
  - A separate combat fast mark (no menu in combat).
- **Click to place**: click a world marker icon to get the green placement circle; click a ping icon, then click where it should go.
- **Look**: icon size, scale, alpha, highlight / region colors, mark-colored highlight, gradient, round ring, slice gap, pop, glow, open animation, center dot, fonts (LibSharedMedia fonts if available).
- **Unit info**: portrait in the center, the unit's current raid mark (on the portrait, as a lit region, or as an undimmed icon), unit label and name. If the hovered unit is lost before release, the label shows "Lost".
- **Sounds**: on apply and on highlight change, with a master switch and output channel.
- **Profiles** (AceDB): per character or shared, copy, reset.
- Show or hide single icons in each menu; empty slots can be kept.

## Usage

1. Open the options with `/ffm`.
2. Set a key in **Markers Units > General > Keybind**, or use **Esc > Options > Keybindings > AddOns > FFmarks**.
3. Hold the key, move the cursor toward an icon, release.

Default keys of the other menus:

- **Markers World**: Markers Units key + Ctrl.
- **Ping**: Markers Units key + Shift.
- **Ping World**: no key until you set one.

Each menu can use its own key instead.

## Slash commands

| Command       | Action                                  |
|---------------|-----------------------------------------|
| `/ffm`        | Toggle the options window               |
| `/ffm config` | Open the Blizzard options panel         |
| `/ffm debug`  | Toggle debug output in chat             |
| `/ffm help`   | List commands                           |

`/FFmarks` works as an alias for `/ffm`.

## License

Copyright (C) 2026 Ftkun.

FFmarks is free software, released under the GNU General Public License v2.0.
See [LICENSE](LICENSE).

Bundled libraries in `Libs/` keep their own licenses:

- Ace3 (AceConfig-3.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, CallbackHandler-1.0):
  Ace3 license (BSD-style), see [Libs/LICENSE-Ace3.txt](Libs/LICENSE-Ace3.txt).
- LibStub: public domain.

## Credits

Developed with help from Claude (Anthropic).
