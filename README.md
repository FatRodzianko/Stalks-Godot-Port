# Stalks Stalks Stalks — Godot Port

A port of [Stalks Stalks Stalks](https://rodzianko.itch.io/stalksstalksstalks) from
Unity to Godot 4.7.2.

A 2D, UI-only multiplayer stock-trading game. Players buy and sell "stalks" whose
prices move each in-game year via bull/bear modifiers and random special events.
Highest net worth after the final year wins. 1–10 players.

## Status

Scaffolding. No gameplay implemented yet. The current `main_scene` is a throwaway
smoke-test screen that proves the toolchain works.

## Requirements

- **Godot 4.7.2 stable** — the standard build, not the .NET build.
  Not on `PATH`; see `CLAUDE.md` for the exact paths on this machine.
- No other dependencies yet. Steam integration is deliberately deferred — see
  `docs/` when that work starts.

## Running it

Open the project folder in the Godot editor and press F5, or from a terminal:

```
<path-to>/Godot_v4.7.2-stable_win64_console.exe --path . 
```

On a fresh clone, import assets first:

```
<path-to>/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

## Layout

```
src/
  sim/        Pure game logic. No nodes, no scene tree, no networking.
  data/       Resource definitions (stalks, special events) saved as .tres.
  net/        Network session abstraction. Transport-agnostic.
  autoload/   Global singletons, registered in project.godot.
  ui/
    screens/  One folder per screen; scene and script live together.
    widgets/  Reusable UI pieces (stalk row, ranking row, lobby member).
assets/
  themes/     Shared Theme resources. All colours and fonts live here.
  sprites/
  audio/
tests/
  unit/       Tests for src/sim. Must run headless with no scene.
docs/         Game rules and design notes.
```

The hard rule: **`src/sim` never imports a node.** The economy has to be testable
without a window, a scene, or a network peer. See `CLAUDE.md`.

## Reference material

The original Unity project is at
`C:\Users\murph\Desktop\Unity-gamedev-stuff\StalksStalksStalks`. It is read-only
reference for **game rules and feel only** — not for code structure.
