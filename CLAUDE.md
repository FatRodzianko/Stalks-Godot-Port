# Stalks Stalks Stalks — Godot Port

A 2D, UI-only multiplayer stock-trading game. Players buy and sell "stalks" whose
prices move each in-game year via bull/bear modifiers and random special events.
Highest net worth after the final year wins. 1–10 players over Steam.

This is a **port**, not a translation. The original Unity project lives at
`C:\Users\murph\Desktop\Unity-gamedev-stuff\StalksStalksStalks` and is **read-only
reference for game rules and feel only**. Its code structure is explicitly not a
model to follow — it has 900-line god objects and heavy coupling. Reimplement
behaviour, not architecture.

The authoritative rules reference is `docs/game-rules.md` (create and keep current
as rules are confirmed).

---

## Engine & Commands

Godot **4.7.2 stable** (`4.7.2.stable.official.ed1daf0bf`). Pin this exact version;
do not assume a newer or older minor release behaves the same.

`godot` is **not on PATH**. The engine lives in an extracted folder next to this
project. The paths below are **this machine's setup** — for a fresh clone on another
computer, see `docs/development.md`:

- GUI editor:
  `C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe`
- CLI / headless (use this one — it prints to stdout):
  `C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`

Project root is this directory (`project.godot` sits next to this file), so the git
repo root and the Godot project root are the same path.

Common commands, run from the project root with the console exe as `<godot>`:

| Purpose | Command |
|---|---|
| Import assets (always first in a fresh checkout — no `.godot/` cache exists yet) | `<godot> --headless --import` |
| Parse/typecheck one script without running it | `<godot> --headless --check-only --script res://path/to/script.gd` |
| Run a headless script (one-off logic probes) | `<godot> --headless --script res://path/to/script.gd` |
| Run the game | `<godot> .` |
| Run a single scene | `<godot> res://path/to/scene.tscn` |
| Run tests | see **Testing** below |

Prefer `--headless` for anything that does not need a window. Re-run
`--headless --import` after adding new asset files.

---

## Working Agreement (read this first)

The project owner is **new to Godot**. Instructions that require clicking in the
editor must be written as explicit, numbered, click-by-click steps naming the exact
panel, menu, and button — never "just add a MultiplayerSpawner" or "set it up in the
Inspector".

**Prefer code and text files over editor actions.** Godot's project files are plain
text, so anything expressed as a script or a hand-written `.tscn`/`.tres` is
something Claude can author, diff, and verify directly. Anything done by clicking in
the editor is invisible in diffs and can only be done by the owner. Therefore:

- Build scenes as text (`.tscn`) where the node tree is simple and regular.
- Connect signals **in code** (`emitter.signal_name.connect(_on_thing_happened)`),
  not via the editor's Node → Signals panel, so connections show up in diffs.
- Configure autoloads, input maps, and display settings by editing `project.godot`
  directly, then tell the owner to reopen the project.
- Reserve editor hand-holding for genuinely visual work: theme authoring, fiddly
  container layout, and importing art/audio.

When an editor step is unavoidable, state **why** code could not do it.

After any change, say explicitly what was verified and how (which command ran, what
it output) and what was *not* verified. Do not report a scene as "working" on the
strength of a successful parse.

---

## Static Typing (enforced)

This is **mechanically enforced**, not just a convention:
`debug/gdscript/warnings/untyped_declaration=2` in `project.godot` turns an untyped
`var` or an untyped function signature into a hard **parse error**. A script that
breaks the rule will not load, and `--check-only` will fail on it.

Note the asymmetry when verifying work: `--check-only` reports warnings set to
level `2` and stays **silent** about level `1`. So anything that must actually be
enforced has to be set to `2`; level-1 warnings only ever show up in the editor.

Inferred types (`var price := 100`) satisfy the gate. Bare `var price = 100` does not.

- Every `var`, parameter, and return type is typed, explicitly
  (`var price: int = 100`) or inferred (`var price := 100`).
- Every function declares parameter and return types:
  `func apply_dividend(stalk: StalkDefinition, is_bull: bool) -> int:`
- `@export` always carries an explicit type: `@export var max_years: int = 10`
- Use `class_name` on anything referenced as a type from another script.
- Prefer typed collections (`Array[StalkState]`) over bare `Array`/`Dictionary`.

---

## Naming Conventions (official GDScript style guide)

- Files and functions: `snake_case` (`stalk_market.gd`, `func start_year():`)
- Classes and node names: `PascalCase` (`class_name StalkMarket`, node `StalkList`)
- Constants: `CONSTANT_CASE` (`const MIN_LOAN: int = 100`)
- Enums: `PascalCase` type, `CONSTANT_CASE` members (`enum MarketMood { BULL, BEAR }`)
- Signals: `snake_case`, **past tense**, named for what happened
  (`signal year_advanced`, not `signal advance_year`)
- Private members: single leading underscore (`_cash_on_hand`, `func _recalculate():`)
- Script order: `@tool`/`@icon` → `class_name` → `extends` → docstring → signals →
  enums → constants → `@export` vars → regular vars → `@onready` vars →
  `_init`/`_ready`/`_process` → public methods → private methods

---

## Architecture

### Separate the simulation from the scene tree

The economy is the heart of this game and must be testable without a window, a
scene, or a network peer.

- **Pure logic** (price movement, dividends, splits, bankruptcy, loan interest and
  penalties, net worth, win/tie resolution) lives in classes extending `RefCounted`
  or `Resource` with **zero** node dependencies: no `get_node`, no `$Path`, no
  autoload access, no signals to UI, no `await get_tree()`.
- **Nodes** (`Control`, `Node`) own presentation and input only. They read state
  from the simulation and push intent back into it.
- A node must never compute a game rule inline. If a number is derived, it is
  derived in the simulation layer.

This is the single most important rule in this file. If a change makes the economy
depend on a node, the change is wrong.

### Data as Resources

Stalk definitions (name, bull dividend, bear dividend, volatility) and special-event
definitions are `Resource` subclasses saved as `.tres`, not hardcoded arrays. New
content should be addable by creating a resource file, with no code change.

### Autoloads

Global services (game state, audio, settings, network session) are autoload
singletons registered in `project.godot` under `[autoload]` and referenced by their
singleton name. Never `get_node("/root/SomeManager")`.

Keep autoloads few and thin. An autoload is a service locator, not a place to put
game rules — rules belong in the simulation layer above.

### Node references

One `@onready` per referenced node, at the top of the script:

```gdscript
@onready var _price_label: Label = %PriceLabel
```

Use **scene-unique names** (`%Name`) in preference to `$Deep/Path/Chains`, so layout
changes don't break scripts. Never call `get_node()` inside `_process()` or a loop.

### One responsibility per scene

A scene either defines a reusable widget (a stalk row, a player ranking row) or
assembles a screen. Not both. Reusable widgets expose signals outward and know
nothing about the screen that holds them.

---

## Signals for Decoupling

- A node never reaches up to its parent or sideways to a sibling to call a method.
  It emits a signal; the listener decides what to do.
- Connect in code (see **Working Agreement**). Connect in `_ready()`, and prefer
  connecting from the parent that owns both ends.
- Callback naming: `_on_<emitter>_<signal>` (`_on_stalk_row_buy_requested`).
- Signals carry data, not node references, wherever possible — pass a stalk id, not
  the `StalkRow` that was clicked.
- Pure-logic classes may emit signals, but only about state changes, and must not
  know who listens.

---

## Money and Determinism

- **All currency is `int`.** Never `float` for cash, prices, dividends, loan
  balances, or net worth. The original game's rounding behaviour (minimum loan
  payments drifting by about ±1 per year) comes from integer maths and must be
  reproducible.
- Prices are whole numbers. Splits halve with integer division; document the
  rounding direction wherever it matters.
- **All randomness goes through an injected `RandomNumberGenerator`**, never global
  `randi()`/`randf()`. The simulation receives its RNG; it does not create one. This
  makes every market outcome reproducible from a seed, and is required for
  multiplayer.
- Seed the RNG once per match on the host and treat the seed as part of match state.

---

## Multiplayer

Host-authoritative. One peer (the host) owns the simulation; clients own only their
own input and their own view.

- The **host is authoritative over all economy state.** Clients never compute a
  price, dividend, or net worth and send it; they request actions ("buy 5 shares of
  X") and receive results.
- Validate every client request on the host (sufficient cash, loan eligibility,
  whether buying is allowed this phase). Never trust a client-supplied amount or
  price.
- Keep networking behind a thin interface so the simulation has no knowledge of
  transport. The economy layer must run in a single-player test with no peer at all.
- Build and test against Godot's built-in `ENetMultiplayerPeer` first. Steam is a
  transport swap, not a rewrite — see `docs/steam-integration.md` when that starts.
- Use `@rpc` with explicit modes (`@rpc("any_peer", "call_remote", "reliable")`) —
  always state the mode, never rely on defaults. Economy RPCs are `reliable`.
- Authority checks go at the top of every `any_peer` RPC.

---

## UI

The entire game is `Control` nodes. Layout correctness matters more than anything
visual here.

- Lay out with containers (`VBoxContainer`, `GridContainer`, `MarginContainer`,
  `ScrollContainer`), anchors and size flags. Never position UI by hardcoded pixel
  coordinates.
- Repeated rows (stalk listings, owned holdings, player rankings, lobby members) are
  one reusable scene instantiated into a container — not duplicated nodes.
- All colours, fonts and styleboxes come from a shared `Theme` resource. No per-node
  colour overrides in scene files.
- Format currency and numbers in one shared helper, not ad hoc per label.

---

## Testing

Framework: **GUT 9.7.1**, installed at `addons/gut/`. Do not also install gdUnit4 —
one framework only. Full detail in `docs/testing.md`.

Run the suite (config is in `.gutconfig.json`, so no flags needed):

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

GUT version compatibility is strict: **9.7.1 is the Godot 4.7.x release**, while
GUT's `main` branch targets 4.6.x. Do not "upgrade to latest" without checking the
table in GUT's README.

Tests live in `tests/unit/` (scanned by GUT) with shared helpers in
`tests/fixtures/` (not scanned).

- Pure simulation logic gets real unit tests: price movement, splits above 150,
  bankruptcy at 0, dividend payout per mood, loan interest, missed-payment penalties
  (10% / 15% / seizure), the max-loan 25% rule, net worth, tie-breaking.
- Seed the RNG explicitly in every test involving randomness. A test that depends on
  unseeded randomness is a bug.
- Scene-dependent behaviour is tested through GUT's scene-tree tests, not asserted
  from a script running outside the tree.
- Cold checkout order: `--headless --import` first, then the GUT CLI runner.
- Add a regression test for every rule bug found during the port.

---

## Documentation (a release gate, not an afterthought)

**The bar: this project must survive losing everyone who worked on it.** Someone who
has never seen the codebase, has no access to the original Unity source, and is
working **without any AI assistance** must be able to read `docs/`, understand both
the game and the code, and continue the work. Documentation that only makes sense to
someone who can ask follow-up questions does not meet the bar.

Practical consequences:

- **Write down the "why", not just the "what".** A successor who does not know why a
  decision was made will undo it. Every non-obvious choice goes in
  `docs/decisions.md` with its reasoning and what it rules out.
- **No machine-specific paths** in documentation meant for a reader, except in
  `docs/development.md`, where they are clearly labelled as one machine's setup.
  Anything else must work on a fresh clone on an unfamiliar computer.
- **No external dependency for understanding.** The original Unity project is *not*
  in this repository and a successor will not have it. Every value extracted from it
  is already written into `docs/game-rules.md`; keep it that way, so the docs stand
  alone.
- **Explain domain terms.** "Stalk", "mood", "the bag", "a static stalk", "yeehaw"
  mean nothing to a newcomer. They belong in `docs/glossary.md`.
- **Prefer prose that explains to comments that label.** A file header saying what a
  file is *for* and pointing at the relevant rules section is worth more than a
  comment on every line.

### The per-phase gate

**A phase in `docs/porting-plan.md` is not complete until its documentation is
updated.** Treat this as part of the phase, in the same way tests are. At minimum,
each phase completion updates:

1. `docs/porting-plan.md` — mark the phase done, record what was actually delivered,
   and note anything that changed scope.
2. `docs/architecture.md` — any new layer, system, or seam, and how it connects.
3. `docs/decisions.md` — every decision taken during the phase, with reasoning.
4. `docs/game-rules.md` — any rule confirmed, changed, or still open.
5. `docs/testing.md` — the new coverage, and what is still untested.
6. `docs/glossary.md` — any new term.
7. `docs/README.md` — the index, if documents were added or reorganised.

A visual code map (the kind published as a shareable page) is also worth refreshing
at each phase boundary, but the markdown in `docs/` is the authoritative copy — it is
what lives and versions with the code.

## Git Hygiene

- `.godot/` is generated import cache — never committed.
- The Steamworks SDK is **not redistributable**; it stays gitignored and is never
  committed, even to a private repo.
- Build output and export artifacts are gitignored.
- `export_presets.cfg` may contain local paths and signing details — review before
  committing.
- Do not commit or push unless asked.

---

## Out of Scope

This project has **no tilemaps, no physics, no 3D, no character movement, and no
sprite animation beyond simple UI feedback.** Guidance about `TileMapLayer`,
`CharacterBody2D`, navigation, or collision layers does not apply here. If a
proposed solution reaches for those, it is the wrong solution.
