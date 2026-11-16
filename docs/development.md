# Development

How to get this project running on a machine that has never seen it, and how to work
on it afterwards.

Written to be followed by someone with no prior context. If a step does not work as
described, that is a bug in this document worth fixing.

---

## 1. What you need

| Requirement | Version | Notes |
|---|---|---|
| **Godot** | **4.7.2 stable** | The *standard* build, **not** the .NET/Mono build. See §2. |
| **git** | any recent | For the repository. |
| Nothing else | | No .NET SDK, no Node, no Python, no build system. |

**You do not need:**

- The .NET build of Godot — this project is GDScript (see decisions.md D1).
- The original Unity project — it is not in this repository and is not required. Every
  value extracted from it is written into [game-rules.md](game-rules.md).
- Steam, or a Steam developer account — not until Phase 6.
- An AI assistant.

### Why the version is exact

Do not substitute a different Godot 4.x release. GUT's compatibility is pinned to the
Godot minor version, and Godot 4.7 changed internals that break other addons. See
decisions.md D2.

---

## 2. Get Godot

Godot needs no installer — it is a single executable.

1. Download **Godot 4.7.2 stable**, standard (not .NET) build, for your platform,
   from <https://godotengine.org/download/archive/> (look under 4.7.2).
2. Extract the zip somewhere sensible. It contains two executables:
   - `Godot_v4.7.2-stable_<platform>` — the **GUI editor**.
   - `Godot_v4.7.2-stable_<platform>_console` — the **command-line** version, which
     prints to stdout. *This is the one you want for tests and scripts.*
3. Note where you put it. These docs call the console executable **`<godot>`**.

> **Watch out:** on Windows, extracting the zip may produce a *folder* whose name ends
> in `.exe`, with the real executables inside it. That is a quirk of the archive, not
> a problem — just be aware the path has an extra level.

### Optional: make `<godot>` a real command

Life is easier if you do not retype the path. On Windows PowerShell:

```powershell
Set-Alias godotc "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
```

On macOS or Linux:

```bash
alias godotc="/path/to/Godot_v4.7.2-stable_linux.x86_64"
```

Add it to your shell profile to make it permanent. Everywhere below, `<godot>` means
this executable.

### Paths on the original author's machine

Recorded only so existing notes make sense. **These are one machine's layout and will
not match yours.**

```
Engine:   C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\
          Godot_v4.7.2-stable_win64.exe           (editor)
          Godot_v4.7.2-stable_win64_console.exe   (CLI — this is <godot>)
Project:  C:\Users\murph\Desktop\dev-projects\Stalks-Godot-Port
Original
Unity src: C:\Users\murph\Desktop\Unity-gamedev-stuff\StalksStalksStalks  (not in git)
```

`CLAUDE.md` names the first two concretely because an automated assistant needs a
literal path. Every other document uses `<godot>`.

---

## 3. Get the code and run it

```bash
git clone https://github.com/FatRodzianko/Stalks-Godot-Port.git
cd Stalks-Godot-Port
```

**Import the assets first.** A fresh clone has no `.godot/` cache, and most commands
fail or behave oddly without it:

```
<godot> --headless --path . --import
```

**Then run the test suite.** If this passes, your setup is correct:

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

You should see roughly:

```
Totals
------
Scripts               5
Tests                67
Passing Tests        67
Asserts           12641
Time              2.4s

---- All tests passed! ----
```

That is the whole verification. There is no build step.

**To open the editor**, launch the GUI executable, click *Import*, select this
folder's `project.godot`, and click *Import & Edit*. First-time users should read
[godot-editor-guide.md](godot-editor-guide.md), which walks through the whole
interface.

---

## 4. The verification loop

Four commands cover everything. Learn these and you can work without the editor at
all.

| Purpose | Command |
|---|---|
| Import assets (first in a fresh clone; re-run after adding asset files) | `<godot> --headless --path . --import` |
| Parse and typecheck one script, without running it | `<godot> --headless --path . --check-only --script res://path/to/file.gd` |
| Run a one-off script headlessly | `<godot> --headless --path . --script res://path/to/file.gd` |
| Run the test suite | `<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd` |
| Run the game | `<godot> --path .` |

`--check-only` is the fastest feedback available — under a second — and because of
decisions.md D18 it catches untyped declarations as hard errors, not warnings.

A one-off script must extend `SceneTree` and do its work in `_initialize()`, calling
`quit()` when finished. Useful for probing a formula before committing to it.

More test-running options are in [testing.md](testing.md).

---

## 5. Project layout

```
addons/gut/      The test framework. Committed deliberately (decisions.md D17).
assets/
  themes/        Shared Theme resources. All colours and fonts belong here.
  sprites/
  audio/
docs/            All documentation. Start at docs/README.md.
src/
  data/          Authored content and settings. Resource classes, saved as .tres.
  sim/           The entire economy. No nodes, no networking. See architecture.md.
  net/            (empty — Phase 5) Session and transport.
  autoload/       (empty) Global services, registered in project.godot.
  ui/
    screens/     One folder per screen, scene and script together.
    widgets/     Reusable UI pieces.
tests/
  fixtures/      Shared test helpers. Not scanned for tests.
  unit/          Everything GUT runs.
project.godot    Engine configuration. Edited directly; see decisions.md D19.
.gutconfig.json  Test runner configuration.
CLAUDE.md        Coding standards. Addressed to an AI, but applies to everyone.
```

The single most important structural rule: **`src/sim` never depends on anything above
it.** No nodes, no scene tree, no network. See decisions.md D3 — this is not a
preference, it is what makes the game testable.

---

## 6. How to do common things

### Add a new stalk

A stalk and all its events are **one file**, so this is a single-file change
(decisions.md D29). The easiest route is to copy an existing one.

1. Copy any file in `src/data/stalks/` — `mafia.tres` is a good, ordinary example —
   and rename it.
2. Open it in the Godot editor (double-click it) and edit it in the Inspector, or
   edit the text directly; `.tres` is plain text.
3. Set a unique **`id`** (a `StringName`, never the display name — decisions.md D9)
   and a `display_name`.
4. Set `starting_price` (100 for every shipped stalk), `bear_change`, `bull_change`,
   and the two dividends. `bear_change` and `bull_change` are `(min, max)` magnitudes
   and are **always stored positive** — the bear one is applied negatively. The
   shipped values for all ten existing stalks are in
   [game-rules.md §3](game-rules.md).
5. Under **Special Events**, fill in `bull_events` and `bear_events`. Each entry is a
   `SpecialEventDefinition` with a unique `id`, a `target_stalk_id` **matching this
   stalk's id**, the matching `mood`, `flavour_text`, and a non-zero `price_change`
   (positive in the bull list, negative in the bear list by convention, though a
   negative bull event is legal).
6. For a static-price instrument like BERRY BONDS, set `is_price_static` and leave
   both event lists empty — it cannot be moved by anything.
7. Run the suite. `ContentLibrary` validates the whole directory and will name
   anything wrong.

No code change is needed. If you find yourself writing one, something has been
hardcoded that should be data.

**The validator is your friend here.** It catches the mistake that is otherwise
invisible: an event whose `target_stalk_id` has a typo will never fire, and without
validation nothing would tell you. It reports every problem in one run rather than
stopping at the first, so you can fix a new stalk in one pass. See decisions.md D31
for the full list of checks.

### Where the shipped content came from

The ten stalks and ninety events were imported from the original Unity source by a
one-off script that parsed `StalkManager.CreateSpecialEvents()` and wrote the `.tres`
files via `ResourceSaver`, rather than being retyped. That importer has been deleted:
the `.tres` files are the source of truth now. If you ever need to re-derive them,
the method is in the git history for the Phase 3 commit.

### Add a test

1. Put it in `tests/unit/`, in the file matching the unit under test, named
   `test_<what_it_checks>`.
2. Extend `GutTest`.
3. Use `StalksFixture` for content and state, and `FixedPriceModelStub` when you need
   prices to hold still so you can isolate one rule.
4. **Seed every generator** via `StalksFixture.rng(seed)`. A test that depends on
   unseeded randomness is a bug (decisions.md D5).

Conventions and current coverage are in [testing.md](testing.md).

### Add a rule to the year pipeline

Rules go in `YearResolver.advance_year()`, in the correct position in the ordered
sequence. **The order is load-bearing** — see [game-rules.md §4.1](game-rules.md) and
the two order traps described there. Record the new step in `YearResult` so the UI and
the tests can see it happened.

### Change how prices move

Write a new `PriceModel` subclass rather than editing `RandomRangePriceModel`. That is
what the interface is for (decisions.md D6).

### Change a game rule

1. Update [game-rules.md](game-rules.md) first, including *why*.
2. Add an entry to [decisions.md](decisions.md) if it is a divergence or a reversal.
3. Change the code.
4. Add or update a test that pins the new behaviour.

---

## 6a. Playing a networked match yourself

Multiplayer needs two copies of the game running. **You do not need to export a
build for this** — the editor can launch several instances at once, and that is
the fastest loop by a wide margin.

In the Godot editor:

1. In the top menu bar, click **Debug**.
2. Choose **Customize Run Instances...** (on Godot versions before 4.2 this is
   **Run Multiple Instances** with a submenu instead).
3. Tick **Enable Multiple Instances** and set the number to **2**.
4. Click **OK**.
5. Press **F5** (or the play button, top right). Two windows open.

Then, in one window click **HOST LOCALLY**; in the other click **JOIN GAME** and
**JOIN** and **Join**. The address and port are pre-filled for the same machine,
so neither needs typing.

### Skipping the menu with flags

Clicking through the menu in two windows gets old fast, so the game reads a few
command-line flags and goes straight into a match. In the **Customize Run
Instances** dialog each instance has its own arguments field:

- instance 1: `--host`
- instance 2: `--join`

Press **F5** and you are in a lobby with two players, nothing typed. The host is
named "Host" and the joiner "Guest" so the windows are told apart at a glance.

| Flag | Meaning |
|---|---|
| `--host` | Open a local lobby immediately |
| `--join` | Join `127.0.0.1` immediately |
| `--join=<address>` | Join a specific host |
| `--port=<n>` | Listen on, or connect to, this port (default 42420) |
| `--name=<name>` | Play under this name |
| `--seed=<n>` | Host with a fixed match seed, to reproduce a bug |
| `--ready` | Ready up as soon as the lobby is joined |
| `--autostart` | Host: start the match as soon as everybody is ready |

They work from a terminal too, in either form:

```
<godot> --path . --host
```

```
<godot> --path . -- --join --name=Murph
```

`--autostart` with `--ready` on the other instance takes two windows from launch
to a running match with no input at all:

```
<godot> --path . --host --autostart --port=44701
```

```
<godot> --path . --join --ready --port=44701
```

Worth knowing about: this is how the "client didn't load anything" bug was found.
The suite could not reach it, because two `Main` instances cannot coexist in one
process, and reproducing it by hand meant clicking through two windows every
attempt. With these flags it is two commands and a log file.

A flag-launched host turns **loans on** and uses a ten-year match. That is
deliberately not the same as `GameSettings`' own defaults: these flags exist for
testing the game, and the loan panel is part of it.

If the auto-host or auto-join fails — a busy port, no host to connect to — the
game falls back to the menu with the reason on it rather than sitting on a blank
screen.

**These are debug-build only.** `LaunchArgs.from_command_line()` returns "show
the menu" in an exported release build, so a shipped game cannot be made to
auto-host by a stray argument. The parsing itself is pure and always works, which
is what makes it testable — see `tests/unit/test_launch_args.gd`.

### Without the editor

Run the project twice from a terminal, from the project root:

```
<godot> --path .
```

Use the **console** executable so you see `print` output. Running one instance
this way and one from the editor works too, which is handy when you want the
editor's debugger attached to only one side.

### Why not an exported build?

You can, but exporting needs the **export templates** for your exact Godot
version — a separate download of several hundred megabytes, matched to
4.7.2.stable. Worth doing when you want to test the real shipped artifact, and a
waste of time for everyday multiplayer work. See Phase 7 in
[porting-plan.md](porting-plan.md) for when export presets get set up properly.

### What the automated tests can and cannot cover

The suite runs a real host and client over real ENet in a single process, so the
handshake, the economy and the disconnect behaviour are all tested without any of
this (see [testing.md](testing.md)). What it cannot test is two *processes*:
`Main` uses the scene tree's single default `MultiplayerAPI`, so two `Main`
instances in one process overwrite each other's peer. Anything about the real
two-window experience has to be checked by hand, the way described above.

---

## 6b. Playing across two machines, without Steam

Direct connection is the **fast path for testing**, and it stays that way after
Steam exists. No accounts, no store, no second Steam install, and it is what
the automated suite uses. Save Steam for testing Steam.

On the machine that will host, find the address to give out:

```
<godot> --headless --script res://tools/lan_check.gd
```

It prints the best candidate and the alternatives. More than one is normal: a
developer machine is usually on several networks and most of them are virtual.
On the machine this was written on, Godot reported nine addresses and the real
one was eighth — WSL, Hyper-V and VirtualBox all offer plausible-looking
addresses no other computer can reach.

Then:

1. On the host machine: **CREATE GAME** — **HOST LOCALLY**. The lobby names the
   address, which is the same one the tool printed.
2. On the other machine: **JOIN**, type that address, **Join**.

The port is 42420 on both by default. The host listens on every network
interface, so there is nothing to configure beyond the address.

If they cannot see each other, it is nearly always the wrong address of the
several, or Windows Firewall quietly refusing — see
[exporting.md section 5](exporting.md).

Running a build rather than the editor on the far machine is covered in
[exporting.md](exporting.md), but note you do not need one: Godot and a copy of
the project work just as well for testing gameplay.

---

## 7. Conventions

Full detail in [../CLAUDE.md](../CLAUDE.md). The ones that bite most often:

- **Everything is typed.** Untyped declarations are a *parse error*, not a warning.
  `var x := 5` (inferred) is fine; `var x = 5` will not load.
- **All money is `int`.** Never a float for cash, prices, dividends or balances.
- **Randomness is injected**, never global `randi()`. `Array.shuffle()` is banned in
  `src/sim` for the same reason.
- **`snake_case`** files and functions, **`PascalCase`** classes and nodes,
  **`CONSTANT_CASE`** constants, **past-tense** signal names (`year_advanced`, not
  `advance_year`).
- **Connect signals in code**, not in the editor's Signal panel, so connections appear
  in diffs.
- **Nodes never reach into parents or siblings.** They emit; listeners decide.
- **No per-node colour overrides.** Colours live in the shared `Theme`.

---

## 8. Committing

- Run the suite before committing. It takes two seconds.
- `.godot/` is generated and gitignored. Never commit it.
- The Steamworks SDK is **not redistributable** and must never be committed, even to
  a private repository. `.gitignore` already blocks the usual paths.
- `.uid` files next to scripts are generated by Godot 4.4+ and *should* be committed —
  they keep resource references stable.
- Opening the project in the editor rewrites `project.godot`: it reorders keys and
  **deletes any comments you put in it**. That is Godot tidying its own file, not a
  problem — but it means **`project.godot` cannot hold documentation**. Reasoning for
  a setting belongs in [decisions.md](decisions.md), which is exactly why
  `untyped_declaration=2` is explained there (D18) and not in a comment beside the
  setting. The same applies to `export_presets.cfg`.
- A phase is not complete until its documentation is updated (decisions.md D20). The
  checklist is in `CLAUDE.md`.

---

## 9. Troubleshooting

**"Tests fail immediately" / "GUT doesn't know where to find the tests"**
You are probably missing `--path .` or running from the wrong directory. GUT reads
`.gutconfig.json` from the project root.

**Scripts fail to load with "has no static type"**
That is decisions.md D18 working as intended. Add the type annotation.

**No GUT tab in the editor**
*Project → Project Settings → Plugins* and tick *Gut*, then restart Godot. The plugin
is already enabled in `project.godot`, so this is rarely needed.

**Weird import errors, or classes not found**
Delete the `.godot/` folder and re-run `--headless --path . --import`. It is a cache
and is safe to discard.

**`godot` not recognised**
It is not on PATH by design. Use the full path to the console executable, or set up
the alias in §2.

**A test passes locally but behaves oddly in the editor**
The editor's GUT panel and the CLI use the same runner, but the editor keeps scripts
loaded between runs. Restart the editor if results look stale.
