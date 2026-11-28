# Stalks Stalks Stalks — Godot Port

A port of [Stalks Stalks Stalks](https://rodzianko.itch.io/stalksstalksstalks) from
Unity to **Godot 4.7.2**.

A 2D, UI-only multiplayer stock-trading game. Players buy and sell "stalks" whose
prices move each in-game year through bull/bear market swings and random special
events. Highest net worth after the final year wins. 1–10 players, over Steam or a
direct connection, or alone.

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
| [docs/porting-plan.md](docs/porting-plan.md) | The phases, and what is done |
| [docs/original-game-audit.md](docs/original-game-audit.md) | Everything the original did, marked ported, changed or missing |
| [docs/manual-testing.md](docs/manual-testing.md) | What has to be checked by hand, and what has passed |
| [docs/stalkleheads-design.md](docs/stalkleheads-design.md) | StalkleHeads, the second game mode |
| [docs/godot-editor-guide.md](docs/godot-editor-guide.md) | First-time Godot walkthrough for beginners |
| [docs/glossary.md](docs/glossary.md) | Terms used throughout |

The full index, including exporting, publishing and Steam, is
[docs/README.md](docs/README.md).

---

## Status

**The port is built and playable**, alone or with up to ten players over Steam or
a direct connection. Phases 0 to 7 of [the porting plan](docs/porting-plan.md) are
done, and so are the follow-ups asked for after them: public holdings, rejoining a
match, host migration and the rematch. All of it has been played on two machines
with two Steam accounts.

| | |
|---|---|
| Not done | Uploading the port to Steam. Two Phase 6 checks need that upload; see [publishing.md](docs/publishing.md) |
| In progress | **StalkleHeads**, a second game mode in which prices come from a simulated market of earnings, industries and traders. Built (phases S0 to S8); balance tuning (S9) is open. See [stalkleheads-design.md](docs/stalkleheads-design.md) |
| Also here | The **News Flow Chart**, a Godot editor tool for writing StalkleHeads news ([news-flow-chart.md](docs/news-flow-chart.md)) |
| Tests | Over 1,400, all passing. Coverage and what is still untested: [testing.md](docs/testing.md) |

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

The second command runs the test suite. If it ends with `All tests passed!`, your
setup is correct.

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
  net/        Sessions, the ENet and Steam transports, sync, host migration.
  audio/      The sound effects service, the one autoload.
  ui/         Screens and reusable widgets.
assets/       Themes, sprites, fonts, audio.
tests/
  unit/       Everything the test runner executes.
  fixtures/   Shared test helpers.
tools/        Scripts run by hand: balance, screenshots, network and Steam checks.
addons/
  gut/        The test framework, committed deliberately.
  godotsteam/ The Steam bindings.
  news_flow_chart/  The editor tool for StalkleHeads news.
docs/         All documentation.
```

**The one structural rule:** `src/sim` never depends on anything above it. The economy
has to be testable without a window, a scene, or a network peer. See
[decisions.md D3](docs/decisions.md) — this is what the whole project is built around.

---

## Contributing

Coding standards are in [CLAUDE.md](CLAUDE.md). It is addressed to an AI assistant,
but the standards apply to anyone working on this project — read it as the style
guide. It mentions a `CLAUDE.local.md`; that one is not committed and holds only one
machine's paths and one person's preferences, never a rule about the code.

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

---

## License

The code is licensed under the **GNU GPL, version 3 or later** ([LICENSE](LICENSE)),
with an added permission to link with Valve's Steamworks libraries. The game's name,
logo and sound effects are **not** covered. Details, and the licenses of the bundled
third-party components, are in [NOTICE.md](NOTICE.md).
