# Ash Witness: The Same Rain

An original 2D narrative stealth-adventure built in Godot 4.7.1 and adapted from the opening arc of the Evara novel planning bible.

You play Evan Hale, an anxious nineteen-year-old pulled from Earth into the rain-soaked frontier of Greyfen. A false signal, a sabotaged water gate, and powder beneath a refugee granary are about to turn fear into a massacre. Evan alone remembers the failed lines. Winning means learning that foreknowledge is not consent, survival is not cowardice, and a plan belongs to everyone who risks their life inside it.

## Play

Double-click **`builds/windows/Ash Witness - The Same Rain.exe`** for the standalone Windows build. Keep the companion `.pck` file in the same folder as the `.exe`.

You can also double-click **`PLAY_ASH_AT_GREYFEN.bat`**. It now prefers the standalone build and falls back to the bundled Godot runtime when a build is not present.

For development, run `Godot_v4.7.1-stable_win64.exe/Godot_v4.7.1-stable_win64.exe`, import this folder, and press **F6/F5**, or launch from PowerShell:

```powershell
& '..\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64.exe' --path .
```

## Controls

- Move: WASD or arrow keys
- Sprint: Shift
- Dodge: Space
- Interact / advance dialogue: E or Enter
- Brace / non-lethal shove: F or left mouse button
- Focus: Q
- Memory folio: Tab
- Pause: Escape

## Scope

This release tells **Arc 1: Ash at Greyfen** as a complete compact game: arrival, investigation across failed lines, the Ash Witness Compact, a collaborative final operation, tribunal, and departure for Lysford. It establishes systems and content structure that can support later arcs without pretending to compress all 217 planned chapters into one unfinished build.

See [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for the latest verified checkpoint.
