# Stalks Stalks Stalks — Godot Port

A port of [Stalks Stalks Stalks](https://rodzianko.itch.io/stalksstalksstalks) from
Unity to **Godot 4.7.2**.

A 2D, UI-only multiplayer stock-trading game. Players buy and sell "stalks" whose
prices move each in-game year through bull/bear market swings and random special
events. Highest net worth after the final year wins. 1–10 players.

---

## 📖 Documentation

**[Start at `docs/README.md`](docs/README.md)** — it routes you to the right document
for what you need.

The documentation is written to stand alone: you do not need the original Unity
project, access to anyone who worked on this, or an AI assistant to continue the work.

| | |
|---|---|
| [docs/game-rules.md](docs/game-rules.md) | The authoritative game spec — every rule, number and formula |
| [docs/architecture.md](docs/architecture.md) | How the code is organised |
| [docs/decisions.md](docs/decisions.md) | **Why** it is organised that way. Read before changing anything structural |
| [docs/development.md](docs/development.md) | Setup on a fresh machine, and how to work on it |
| [docs/testing.md](docs/testing.md) | Running and writing tests |
| [docs/porting-plan.md](docs/porting-plan.md) | The seven phases, and what is done |
| [docs/godot-editor-guide.md](docs/godot-editor-guide.md) | First-time Godot walkthrough for beginners |
| [docs/glossary.md](docs/glossary.md) | Terms used throughout |

---

## Status

**Phases 1–4 of 7 complete. The single-player game is finished and playable.** Press
F5: set up a match in the menu, buy and sell stalks, take a loan, watch prices move
through splits, bankruptcies and special events, and get a result screen with the
final standings.

| | |
|---|---|
| Tests | 214 tests, 13,524 asserts, about 3.3 seconds |
| Built | The economy, loans, the ten stalks with their ninety events, and the complete single-player game: menu, play, loans, result |
| Next | Multiplayer over ENet (Phase 5), then Steam (Phase 6), then sound and polish (Phase 7) |

The current `main_scene` is a throwaway smoke-test screen that proves the toolchain
works. It is deleted in Phase 4.

---

## Quick start

Requires **Godot 4.7.2 stable**, the standard build — *not* the .NET build. No other
dependencies, and no build step. Full instructions in
[docs/development.md](docs/development.md).

With `<godot>` being the Godot `_console` executable, from this folder:

```
<godot> --headless --path . --import
```

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

The second command runs the test suite. If it reports `67 passed`, your setup is
correct.

To open the editor, launch the Godot GUI executable, click *Import*, and select this
folder's `project.godot`. Never used Godot before?
[docs/godot-editor-guide.md](docs/godot-editor-guide.md) walks through the whole
interface.

---

## Layout

```
src/
  sim/        The entire economy. No nodes, no networking, no scene tree.
  data/       Authored content and settings (.tres resources).
  net/        (empty — Phase 5) Session and transport.
  autoload/   (empty) Global services.
  ui/         Screens and reusable widgets.
assets/       Themes, sprites, audio.
tests/
  unit/       Everything the test runner executes.
  fixtures/   Shared test helpers.
addons/gut/   The test framework, committed deliberately.
docs/         All documentation.
```

**The one structural rule:** `src/sim` never depends on anything above it. The economy
has to be testable without a window, a scene, or a network peer. See
[decisions.md D3](docs/decisions.md) — this is what the whole project is built around.

---

## Contributing

Coding standards are in [CLAUDE.md](CLAUDE.md). It is addressed to an AI assistant,
but the standards apply to anyone working on this project — read it as the style
guide.

Three that catch people out:

- **Everything is statically typed.** An untyped `var` is a *parse error*, not a
  warning.
- **All money is `int`**, never a float.
- **All randomness comes from an injected generator**, never global `randi()`.

A phase is not complete until its documentation is updated. The checklist is in
[docs/porting-plan.md](docs/porting-plan.md).

---

## Reference to the original

The original Unity project is **not** in this repository, and is not needed. Every
rule and value recovered from it is written into
[docs/game-rules.md](docs/game-rules.md), including six bugs it shipped with and what
was decided about each.

The port deliberately does **not** reproduce the original's code structure. It was the
author's first project, and this is a clean reimplementation of the behaviour, not a
translation of the code.
