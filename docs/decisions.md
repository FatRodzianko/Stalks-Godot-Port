# Decision Log

Every significant decision, why it was made, and what it rules out.

**Read this before changing anything structural.** The purpose of this file is to
stop a future maintainer — possibly you, in a year — from quietly undoing a
deliberate choice because the reason for it was never written down.

If you reverse a decision here, do not delete the entry. Mark it **Superseded**, say
what replaced it, and add a new entry. The history of why something changed is as
useful as the decision itself.

Format: each entry states the decision, the reasoning, what it forecloses, where it
lives in the code, and what would justify revisiting it.

---

## Foundation

### D1 — GDScript, not C#
**2026-11-14 · Accepted**

Write the project in GDScript rather than Godot's C# support.

**Why.** The author had prior Unity/C# experience, so C# was the intuitive choice, but
the language is not the hard part of learning Godot — the engine model is (nodes,
scenes, `Control` layout, autoloads, resources), and that is identical in both
languages. Choosing C# would have skipped the easy learning and left all the hard
learning in place. Beyond that: C# requires a *separate* .NET build of the Godot
editor plus the .NET SDK; virtually all Godot documentation, tutorials and forum
answers are GDScript, which matters enormously for a first engine; the addon
ecosystem including GUT is GDScript-first; and GDScript hot-reloads while C# needs a
build step on every change, which compounds badly for a UI-heavy game.

**Rules out.** Reusing the original C# source directly (explicitly not wanted — this
is a clean reimplementation). Also rules out C# libraries, and the stronger
compile-time guarantees and refactoring tools that Rider or Visual Studio give C#.
That last cost is real and partly bought back by D18.

**Revisit if.** The project grows large enough that GDScript's weaker cross-file
safety becomes a genuine maintenance drag, or a needed library exists only for .NET.
Performance will never be the reason: the game does integer arithmetic on ten stalks
and ten players, once a year.

### D2 — Pin Godot 4.7.2 exactly
**2026-11-14 · Accepted**

Target `4.7.2.stable.official`, not "4.x" or "latest".

**Why.** Godot minor releases change behaviour and break addon compatibility. GUT's
compatibility is pinned to a specific Godot minor (see D17), and Godot 4.7 renamed an
internal header that broke existing GodotSteam builds. "4.3+" in a style guide is not
specific enough to reproduce a working environment.

**Rules out.** Casually upgrading the engine. An upgrade is a deliberate task: check
GUT compatibility, check GodotSteam compatibility, re-run the suite.

**Lives in.** `project.godot` (`config/features`), `CLAUDE.md`, `docs/development.md`.

### D3 — Separate the simulation from the scene tree
**2026-11-14 · Accepted**

All game rules live in `src/sim/` as plain `RefCounted`/`Resource` classes with zero
node dependencies: no `get_node`, no `$Path`, no autoload access, no `await
get_tree()`.

**Why.** This is the single most important decision in the project, and everything
else follows from it. The game *is* its arithmetic — it is a random number generator
with a scoreboard. If the economy can only be exercised by clicking buttons in a
window with two Steam clients running, it will never be properly tested, and subtle
rule bugs will survive the port. The original shipped with six such bugs (see
game-rules.md §14) precisely because nothing could be checked in isolation. It also
directly serves the stated goal of avoiding the original's tight coupling.

**Rules out.** Any convenience that makes a rule depend on a node. If a change makes
`src/sim` reference a node, the change is wrong, however small.

**Lives in.** The whole of `src/sim/`. Enforced by convention and by the tests, which
load no scenes at all.

### D4 — All money is `int`, never `float`
**2026-11-14 · Accepted**

Cash, prices, dividends, loan balances and net worth are integers throughout.

**Why.** The original's observable behaviour depends on integer truncation — minimum
loan payments drift by about ±1 a year purely because of it, and the split rounding
rule is an integer operation. Floats would make those outcomes irreproducible and
introduce accumulating error over a 99-year match. Reproducibility is required by D5.

**Rules out.** Fractional currency, percentage-based money arithmetic that is not
explicitly truncated, and any "just use a float for now" shortcut.

**Lives in.** Every money field in `src/sim/` and `src/data/`. Rounding directions are
specified per rule in game-rules.md, not left incidental.

### D5 — All randomness comes from an injected generator
**2026-11-14 · Accepted**

The simulation receives a `RandomNumberGenerator` as an argument. Nothing in
`src/sim/` ever calls global `randi()`/`randf()` or `Array.shuffle()`.

**Why.** For a game built entirely on randomness, this is what makes testing possible
at all. The same settings, seed and player actions must produce an identical match, so
a bug can be reproduced and a rule can be asserted. It is also required for
multiplayer: the host seeds once and that seed is part of match state.

**Rules out.** Convenience calls to global random functions anywhere in the
simulation, including in helpers. `Array.shuffle()` is specifically banned — the event
bag implements Fisher-Yates against the injected generator for this reason.

**Lives in.** `YearResolver.advance_year(state, rng)`, `PriceModel.next_change(...,
rng)`, `EventPool._shuffle(items, rng)`, `GameSettings.rng_seed`.

---

## Architecture

### D6 — Price movement is a swappable strategy
**2026-11-14 · Accepted**

`PriceModel` is an abstract class; `RandomRangePriceModel` is the faithful port.

**Why.** The author's plans include a "StalkleHeads" mode where prices come from
simulated earnings reports, company statistics, industry performance and momentum
across years, rather than a random range. Introducing the interface while there is
only one implementation costs almost nothing; retrofitting it after prices are
threaded through the UI and the network layer would mean pulling the project apart.

**Rules out.** Putting price arithmetic inline in the year pipeline, and any price
rule that cannot be expressed as "given a stalk and the market, return a delta".

**Lives in.** `src/sim/price_model.gd`, `src/sim/random_range_price_model.gd`.

### D7 — The price model receives the whole market
**2026-11-14 · Accepted**

`next_change()` takes the entire `GameState`, not just the one stalk being priced.

**Why.** A planned feature makes *My Mutuals and Me Inc.* behave as a genuine index of
the other stalks, which is impossible for a model that can only see its own stalk. The
signature costs nothing now and enables that later.

**Rules out.** Nothing practical. The current model simply ignores most of what it is
given.

### D8 — Record the year history from Year 0
**2026-11-14 · Accepted**

`GameState.history` accumulates every `YearResult`.

**Why.** This information cannot be reconstructed after the fact — a finished match's
final state says nothing about what a stalk cost in year 3. Planned features (price
charts, year-over-year figures, P/E history, replays) all need it. The cost is one
array append per year.

**Rules out.** Nothing. Note the implication: never "optimise" this away.

### D9 — Content is keyed by `id`, not display name
**2026-11-14 · Accepted**

`StalkDefinition.id` is a `StringName` key; the display name is separate.

**Why.** The original matched stalks by comparing display strings. That is why it
needed a hardcoded `stalkName != "BERRY BONDS FROM DIE HARD"` check, and why an event
could silently fail to find its target. Ids make renaming safe, make validation
possible, and are a precondition for the planned JSON-authored custom stalks.

**Rules out.** Any logic branching on a display name. Behaviour that varies per stalk
is a flag on the definition (see `is_price_static`).

### D10 — Behaviour comes from data flags, not special cases
**2026-11-14 · Accepted**

`is_price_static` marks BERRY BONDS as immovable, rather than a name check.

**Why.** Same reasoning as D9, and it makes the rule authorable: a second bond could be
added as content with no code change.

### D11 — `YearResult` as an immutable record
**2026-11-14 · Accepted**

A year advance returns a complete record of what it did.

**Why.** It serves four consumers at once, which is why it earns its weight: the UI
animates from it without re-deriving anything; the host broadcasts one object instead
of a stream of deltas; a test can assert a whole year's outcome as a single value; and
the list of them is the match history (D8). Without it, each of those four would
reinvent the same bookkeeping.

**Lives in.** `src/sim/year_result.gd`, `src/sim/stalk_year_change.gd`.

### D12 — Host-authoritative, with transport kept separate
**2026-11-14 · Accepted**

One peer owns the simulation and decides every number. What carries the messages
(ENet now, Steam later) is a separate concern behind `MultiplayerPeer`.

**Why.** Authority on the host is the only defensible model for a game with money in
it — a client must never be able to assert its own cash. Keeping transport separate
means Steam integration is a swap plus a lobby UI rather than a rewrite, which is what
allows it to be deferred to a late phase (D15).

**Rules out.** Trusting any client-supplied amount or price. Every `any_peer` RPC
re-validates server-side, including that the caller owns the player it claims to act
as.

### D13 — Responsiveness without prediction
**2026-11-14 · Accepted**

Buy and sell feel instant through immediate *input acknowledgement* and a local
pre-check — not through optimistic state mutation with server reconciliation.

**Why.** The requirement was that a player clicking Buy never feels ignored. That is a
UI-feedback problem, not a netcode problem. This game is turn-based with no latency
pressure, so full prediction would buy nothing while adding a rollback path,
reconciliation code, and a class of bug where a client briefly believes it owns shares
it does not. An earlier draft of the architecture specified full prediction and was
deliberately simplified.

**Rules out.** The client ever being a second source of truth. The local pre-check is
presentation that happens to be eager; it calls the *same* `TradeRules` function the
host calls for enforcement, so the two cannot disagree.

**Revisit if.** A future mode introduces real-time pressure, which nothing planned
does.

### D14 — A true single-player mode with no Steam dependency
**2026-11-14 · Accepted**

`LocalSession` runs a complete game in-process with no peer and no Steam.

**Why.** The original could only run through a Steam lobby, so it could not be played
or tested without Steam running. Offline play is a genuine new feature, and it makes
the whole game testable without network variables.

---

## Process and phasing

### D15 — Economy first, UI second, Steam last
**2026-11-14 · Accepted**

Phase order: simulation → loans → content → single-player UI → ENet multiplayer →
Steam → polish. See porting-plan.md.

**Why.** Each boundary is chosen, not incidental. The economy comes first because its
bugs are the invisible kind and headless tests catch them cheaply. Content comes after
the logic because authoring 90 events is only safe once a validator exists to catch
typos. Single-player UI precedes multiplayer so the screens can be shaped without
network variables. ENet precedes Steam because it proves the authority model with no
external dependencies, no accounts and two windows on one machine. Steam is last
because it is the most environment-dependent and least automatable part, and by D12 it
is a transport swap.

**Rules out.** Building screens early to have something to look at. This is a real
cost — there is nothing to play for several phases — and it was accepted knowingly.

### D16 — GUT 9.7.1, pinned to the Godot minor
**2026-11-14 · Accepted**

Use GUT, installed from the release zip at version 9.7.1. Do not also install
gdUnit4.

**Why.** GUT is GDScript-native and the de facto standard for Godot 4. Version 9.7.1
is specifically the `godot_4_7` branch release; GUT's `main` branch targets 4.6.x, so
"install the latest" would have produced a version built for the wrong engine. Two
frameworks in one project means two conventions and two runners for no benefit.

**Rules out.** gdUnit4. Also rules out upgrading GUT without checking its
compatibility table.

### D17 — Commit the GUT addon to the repository
**2026-11-14 · Accepted**

`addons/gut/` (259 files, ~3 MB) is committed rather than gitignored.

**Why.** Standard practice for Godot addons, and it makes a fresh clone immediately
runnable with no install step — which directly serves the "someone else can pick this
up" requirement. The size cost is modest and one-off.

### D18 — Untyped declarations are a hard error
**2026-11-14 · Accepted**

`debug/gdscript/warnings/untyped_declaration=2` in `project.godot`, so an untyped
`var` or function signature fails to parse.

**Why.** GDScript's typing is optional, so a style rule in a document drifts. Making
it a parse error means it cannot. This partly buys back the compile-time safety given
up in D1. Inferred types (`var x := 5`) satisfy it.

**Note the asymmetry that motivated the level:** `--check-only` reports warnings set
to level `2` and stays *silent* about level `1`, so anything meant to be enforced must
be level 2. The `unsafe_*` warnings are left at level 1 deliberately — useful in the
editor, too noisy as errors because many engine APIs legitimately return `Variant`.

### D19 — Prefer code and text files over editor actions
**2026-11-14 · Accepted**

Scenes are hand-written as `.tscn` where the node tree is regular; signals are
connected in code; autoloads and settings are edited directly in `project.godot`.

**Why.** Godot's project files are plain text, so anything expressed as a file can be
diffed and reviewed. Work done by clicking in the editor is invisible in a diff and
reproducible only by whoever clicked. This also substantially reduces how much Godot
UI the author has to learn. Editor work is reserved for genuinely visual tasks: theme
authoring, fiddly container layout, importing art and audio.

**Rules out.** Using the editor's Signal panel for anything dynamic.

### D20 — Documentation is a release gate
**2026-11-14 · Accepted**

A phase is not complete until its documentation is updated. The docs must be usable
by someone with no access to the original authors, no copy of the Unity source, and
no AI assistance.

**Why.** Explicit project requirement. It changes what has to be written down: not
just *what* the code does but *why* (hence this file), domain vocabulary (hence the
glossary), machine-independent setup (hence development.md), and a routing entry point
(hence docs/README.md). Documentation that assumes a reader who can ask follow-up
questions does not meet the bar.

**Lives in.** `CLAUDE.md` under "Documentation", repeated as a gate in
porting-plan.md.

---

## Rule divergences from the original

These are places where the port deliberately does *not* match the original game.
Full detail in game-rules.md §14.

### D21 — Range endpoints are inclusive
**2026-11-14 · Accepted**

A stalk's stated price range includes both ends.

**Why.** The original used C# `Random.Next(min, max)`, which excludes `max`, so its
own stat blocks were wrong: *strYker!!!* could never actually gain 42 in a bull year
despite the board saying 42. Godot's `randi_range()` is inclusive, so a naive port
would have changed the maths silently in one direction or the other. The displayed
numbers clearly *intend* inclusive ranges, so the port is inclusive — but as a
documented, tested choice rather than an accident.

**Lives in.** `RandomRangePriceModel.next_change()`, with endpoint-reachability tests.

### D22 — Splits round up
**2026-11-14 · Accepted**

An odd price halves upward: 153 becomes 77.

**Why.** This is what the original's *live* code path does. A second, dead
`SplitStalks()` function in the original rounds down; it is commented out of the call
chain. The live behaviour is what players experienced, and it matches the author's
stated preference.

### D23 — Special events do not repeat
**2026-11-14 · Accepted**

Events are drawn without replacement from a shuffled bag per mood, refilled and
reshuffled only once empty.

**Why.** The original never removed a drawn event from its pool, so events could fire
in consecutive years. A defined exhaustion policy is genuinely needed: a 99-year match
has roughly 58 bull years against only 45 bull events.

### D24 — Events targeting a bankrupt stalk are skipped, not consumed
**2026-11-14 · Accepted**

A drawn event whose target has already failed is passed over and left in the bag; if
no candidate is viable, the year simply has no event.

**Why.** In the current model an event affects exactly one stalk, so a dead target
makes it a no-op — announcing a price change that does not happen is worse than
announcing nothing.

**Important forward note.** This decision lives inside the event-selection strategy
(`EventPool`), *not* in the year pipeline, specifically so that StalkleHeads mode can
choose differently. Once an event also moves an industry or the wider market, firing
it despite a dead target may be the right call. Keep that boundary.

### D25 — Fix the original's event off-by-one
**2026-11-14 · Accepted**

The original drew with `rng.Next(Count - 1)`, making the last event in each pool
unreachable. Two of its ninety events could never fire. The port draws from the whole
pool.

### D26 — Failed purchases must say why
**2026-11-14 · Accepted**

Validation returns a player-facing reason; the UI must show it.

**Why.** The original failed silently when a purchase exceeded available cash, showing
only the maximum affordable as placeholder text in the input field. Silent failure is
the single most confusing thing a UI can do.

**Lives in.** `TradeRules.validate_buy()` / `validate_sell()`, which return an empty
string for "allowed" or a reason string.

---

## Phase 2 — loans

These reproduce surprising original behaviour rather than diverging from it. They are
recorded because each one looks like a bug and a future maintainer would otherwise
"fix" it.

### D27 — One loan per player for the whole game
**2026-11-14 · Accepted**

A player who has taken a loan can never take another, even after paying it off in
full.

**Why.** This is what the original does. `doesPlayerHaveLoan` is set `true` when a
loan is issued and is **never** set back to `false` — the only line that would reset
it is commented out, and the UI gates the borrow button on `!doesPlayerHaveLoan`.
Verified across every assignment to that flag.

It looks like an oversight rather than a design choice. It is reproduced anyway,
because the port's job is to ship the game that existed, and changing it would alter
the strategy of a long match substantially: a player could otherwise borrow, repay,
and borrow again at a higher net worth, compounding leverage.

**Rules out.** Treating a settled loan as freeing the slot. In the port the presence
of a `LoanState` on a player means "has ever borrowed", so `PlayerState.owes()`
exists separately to answer "currently owes money".

**Status: kept for the faithful port, with the review deferred.** The owner's
decision (2026-11-14) is to keep this behaviour as it shipped and to decide whether
to change it **when the advanced "StalkleHeads" mode is designed** — not before. So
this is not an open question for the port; it is a settled choice with a scheduled
review point.

When that review happens, the things to weigh:

- Allowing repeat borrowing lets a player borrow, repay, and borrow again against a
  higher net worth, compounding leverage across a long match. That is a real strategic
  change, not a tidy-up.
- The advanced mode already intends more financial depth (earnings, industries,
  indices), so repeat borrowing may fit it better than it fits the faithful port.
- If both behaviours are wanted, it belongs in `GameSettings` as a toggle rather than
  a code change, so the original mode stays faithful.

The change itself is one condition in `LoanRules.validate_take_loan` — the
`player.loan != null` check. Everything else already distinguishes "has borrowed"
from "owes money", so nothing downstream assumes a single loan.

### D28 — Term counter starts at 11, and the first year is interest-only
**2026-11-14 · Accepted**

A new loan is created with `years_remaining = 11` while its opening minimum payment
is amortised over **10** years, and with `paid_this_year = true`.

**Why.** Both are the original's values. The year-end pass decrements the counter
before assessing anything, so the extra year is consumed immediately; and the
already-paid flag is how "your first payment is next year" avoids counting an instant
miss. Together they produce the clean result that the advertised ten-year term really
is ten payments, landing exactly on zero — see game-rules.md §9.2.1.

**Why it is recorded.** Starting the counter at 10 looks obviously correct and is
wrong: every payment figure comes out different, and the schedule stops landing on
zero. An earlier draft of game-rules.md documented a trace built that way, and the
error was only caught when the implementation was traced against the real source.

**Rules out.** Any "tidying" of these two initial values without re-deriving the whole
schedule and updating the test fixture.

---

## Phase 3 — content

### D29 — A stalk and its events are one authorable unit
**2026-11-14 · Accepted**

`StalkDefinition` carries `bull_events` and `bear_events` directly, so one `.tres`
per stalk holds the stalk and all ten of its special events. There are no separate
event-pool files.

**Why.** The planned custom-stalk feature is explicitly described as "a template for
a new stalk… would also contain the special events related to the stalk, if the user
wants any", loaded from JSON. Bundling matches that shape exactly: adding a stalk is
adding one file, and nothing else needs editing. It also keeps the file count at ten
instead of ninety-plus, and makes a stalk removable without leaving orphaned events
behind.

The alternative — separate `bull_events.tres` / `bear_events.tres` collections —
would have scattered a stalk's definition across three files and made the future JSON
importer awkward.

**Rules out.** Events that are not attached to a stalk. An event always names a target
(`target_stalk_id`), which is now redundant with where it lives — deliberately, so
the validator can catch a mismatch rather than the game silently firing an event that
can never apply. See D31.

**Lives in.** `src/data/stalk_definition.gd`, `src/data/stalks/*.tres`.

### D30 — Content load order is sorted, not directory order
**2026-11-14 · Accepted**

`ContentLibrary` sorts loaded stalks by `id`.

**Why.** `DirAccess.get_files()` order is not guaranteed across platforms or
filesystems, and stalk order affects iteration inside the simulation. The determinism
contract (D5, architecture.md §8) requires that the same seed produce the same match
on any machine, which it would not if content loaded in a different order on Linux
than on Windows.

**Note.** This is load order, not display order. How the board is arranged on screen
is a UI concern for Phase 4, and will likely want an explicit field rather than
alphabetical ids.

### D31 — The content validator refuses to vouch for bad content
**2026-11-14 · Accepted**

`ContentLibrary.load_from()` always returns a library; callers check `is_valid()`.
Validation collects *every* problem rather than stopping at the first.

**Why.** Content is the easiest part of this project to get quietly wrong: ninety
events referencing ten stalks by id, where a single typo in a target id produces an
event that can never fire and reports nothing. The original had exactly that class of
bug — its event draw silently excluded the last event of each pool. Validation at
load turns a silent content bug into a loud one.

Collecting all errors rather than failing fast is for the author's benefit: someone
adding a stalk sees everything wrong with it in one run.

**What it checks.** Duplicate stalk and event ids, missing ids, missing display names,
non-positive starting prices, inverted or negative ranges, events whose target does
not match the stalk they live on, events in the wrong mood list, zero-change events,
missing flavour text, and events attached to a static-price stalk.

---

## Phase 4 — the user interface

### D32 — `GameSession` is a Node, not a RefCounted
**2026-11-14 · Accepted** (supersedes the shape sketched in architecture.md §5)

The session base class extends `Node` and lives in the scene tree.

**Why.** The later `HostSession` and `ClientSession` must issue `@rpc` calls, which
requires being a Node with a `MultiplayerAPI`. An earlier draft of architecture.md
described `GameSession` as a `RefCounted`, which would have forced a change to the
UI's contract the moment multiplayer arrived. Making it a Node now costs nothing —
`LocalSession` simply ignores the tree — and means the screens do not change in
Phase 5.

**Rules out.** Nothing practical. Note that `src/sim` is still node-free; this is the
layer above, where nodes are allowed.

### D33 — Loans stay off until the loan panel exists
**2026-11-14 · Accepted**

The default solo game sets `loans_enabled = false`.

**Why.** Loans are fully implemented and tested, but there is no UI to take one,
make a payment, or see the minimum due. A player given a game with loans enabled and
no way to interact with them would simply accumulate missed payments and be
bankrupted by a mechanic they never saw — the exact kind of thing the owner called
out in the rules: the game must never penalise a player for something it hid from
them (game-rules.md §9.5).

Better absent than present and unreachable. Flipping the flag is a one-line change
once the panel exists.

### D34 — The playing screen is the main scene, for now
**2026-11-14 · Accepted**

`run/main_scene` points at `gameplay_screen.tscn`, which builds a default solo game
if nothing injects a session.

**Why.** It makes the game runnable and playable at the end of increment 1 rather
than waiting for a menu. The screen taking an injected session *or* building its own
is also what lets the scene tests drive it with a fixed seed.

**Revisit when.** The main menu lands in increment 2 and becomes the main scene.
`GameplayScreen.setup()` already exists for the menu to call.

### D35 — Screens are container-rooted, with no anchors anywhere
**2026-11-14 · Accepted** (supersedes part of D34)

Every screen's root node is a `MarginContainer`, not an anchored `Control`. The only
anchored nodes left in the project are inside the loan panel's full-screen overlay.

**Why.** The first version of the playing screen anchored a `Control` and nested an
anchored `MarginContainer` inside it, and produced dead space at the top and bottom of
the window. A container root is laid out by Godot against the viewport automatically,
so there are no anchors, offsets or `layout_mode` values to get wrong. Verified by
measuring the computed layout at 1024×600, 1280×720 and 1920×1080 — all three now fill
exactly.

**Rules out.** Free-positioned UI. Everything on screen is placed by a container,
which is also what makes the layout survive window resizing.

### D36 — A board's column header IS the row widget
**2026-11-14 · Accepted**

`StalkRow.configure_as_header()` and `HoldingRow.configure_as_header()` turn a row
into the header above its list, instead of a separately built header.

**Why.** The hand-built header had six children where the row had seven, so the row
lost 10px more to separations and **every column sat 20px out of alignment**. Sharing
the scene makes that class of bug impossible: the columns cannot drift because they
are literally the same columns.

A second cause had to be handled too. The header sits *outside* the scroll container
so it stays put while the list scrolls, which means it is not narrowed by the
scrollbar the list reserves — producing an 8px offset whenever a scrollbar was
present, and none when it was not. Both scrolls therefore show their vertical bar
permanently and each header is inset by exactly that width.

**Lives in.** `src/ui/widgets/stalk_row.gd`, `holding_row.gd`,
`gameplay_screen.gd::_inset_header_for_scrollbar()`. A scene test asserts the
alignment so neither cause can regress.

### D37 — The year panel always holds its space
**2026-11-14 · Accepted**

The special-event panel is always visible, with a placeholder when no event fired.

**Why.** Showing and hiding it reflowed the whole screen, so everything below jumped
down whenever an event occurred. Reserving the space costs one line of text and the
layout becomes stable. It also gave somewhere to put the year summary — dividends,
splits and bankruptcies — which previously happened invisibly and made a doubled
share count look like a bug.

### D38 — "Play again" is a new market, not a replay
**2026-11-14 · Accepted**

The result screen's *Play again* reuses the chosen settings but clears the seed.

**Why.** Replaying an identical market is a debugging feature, not a game. Someone who
typed a seed to reproduce something can type it again from the menu; someone pressing
*Play again* wants another go. The finished seed stays on the result screen so it can
be noted first.

### D39 — Follow the original's layout, not its construction
**2026-11-14 · Accepted**

The port copies the original's *layout decisions* — what information exists, how it
is grouped, what sits next to what — and rebuilds *how* it is made.

**Why.** Those two were conflated for several rounds, at real cost. Where things go
came from designing and playing the game, and reinventing it solved a problem that
did not exist. How it was built — managers reaching into text fields, prefabs wired
by dragging, UI state duplicated from game state — is exactly what the port exists to
avoid.

`docs/ui-reference.md` records the original's structure, read out of its scenes and
prefabs, and is the answer to "what goes where". Consult it instead of guessing.

Three places deliberately diverge: the layout is container-driven so it survives
resizing, rejected actions always say why, and the UI holds no state of its own.

### D40 — A 640×360 pixel grid with Terminus
**2026-11-14 · Accepted**

Reference resolution **640×360**, `stretch/mode = viewport`, `scale_mode = integer`,
and **Terminus TTF** at size 12 giving an exact 6×12 cell.

**Why 640×360.** It scales by whole numbers to every common 16:9 resolution (×2 to
720p, ×3 to 1080p, ×4 to 1440p, ×6 to 4K), so pixels are never resampled. The
previously used 768×432 only lands cleanly on 4K — at 1080p it needs ×2.5.

**Why Terminus.** It is monospace, it is OFL 1.1 so it can live in the repository, it
is pixel-exact at size 12 (6×12) and 24 (12×24), and it ships box-drawing glyphs and
arrows, which a terminal UI wants for panel rules and direction indicators.

**Why a grid at all.** The target is a pixel-art Bloomberg terminal. A character grid
turns every layout question into "how many characters", which is what makes the thing
buildable; a proportional layout at arbitrary pixel widths is what made the earlier
attempts churn.

**Rules out.** Fractional sizes anywhere in the UI, and proportional fonts. Godot
needs no addon for any of this — `scale_mode = integer` plus nearest-neighbour
filtering and the font import settings (antialiasing, hinting and subpixel
positioning all off) is the whole setup.

**Note on the earlier font.** Quadlet was considered and rejected on licence grounds:
it forbids placing the font files in a public repository. Terminus has no such
restriction.

---

## Still open

Not yet decided. Resolve one by replacing it with an entry above.

- **Steam App ID** — reuse the original game's ID or register a new one.
- **Achievement thresholds** — 25 achievement IDs exist; only two trigger conditions
  are confirmed. See game-rules.md §13.
- **Long-game softening tunability** — currently exposed in `GameSettings`; whether
  those thresholds should be player-visible options is undecided.
- **GodotSteam vs Foundation for Steamworks** — two viable GDExtensions for Steam
  integration. Decide in Phase 6.

---

### D41 — Nothing but built-in types crosses the wire
**2026-11-14 · Accepted**

Every network payload is a `Dictionary` of ints, bools, strings and arrays,
encoded field by field in `StateSync`. No `Resource`, no `RefCounted`, no
`StalkState`.

**Why.** Godot *can* send script objects over RPC, but only with object decoding
enabled on the `MultiplayerAPI` — and that lets a remote peer instantiate
arbitrary classes in this process, which is a remote code execution primitive. It
stays off. Hand-written encoding is the price.

**What it rules out.** Adding a field to `PlayerState` or `YearResult` no longer
replicates it automatically; `StateSync` has to list it. That is a real
maintenance cost, paid deliberately. `test_state_sync.gd` walks the whole payload
asserting nothing in it is an `Object`, so a forgotten object field fails a test
rather than being silently dropped at runtime.

---

### D42 — Replicate whole snapshots, not deltas
**2026-11-14 · Accepted**

After any authoritative change, each client is sent a complete (redacted)
snapshot of the match, rather than a description of what changed.

**Why.** Ten players, ten stalks, and state that changes when somebody clicks a
button: a snapshot is well under a kilobyte and arrives a handful of times per
year of play. Delta encoding would save nothing measurable and introduces the one
failure mode this design most wants to avoid — a client whose state has silently
drifted from the host's, which is invisible until it affects a decision.

**What it rules out.** This would be the wrong choice for anything real-time or
with large state. If the game ever grows a per-tick element, revisit it. Note the
snapshot deliberately excludes match history: each `YearResult` is broadcast once
as it happens and clients accumulate their own, so history costs nothing per
snapshot. The cost is that **joining a match in progress is not supported** — a
late joiner would have no history. The original did not support it either.

---

### D43 — The rules moved out of the session into `MatchAuthority`
**2026-11-14 · Accepted**

`LocalSession` used to validate and apply actions itself. That logic now lives in
`MatchAuthority` (`src/sim`, a `RefCounted`), and both `LocalSession` and
`HostSession` own one.

**Why two reasons, either sufficient.** First, `LocalSession` is a `Node`, so the
old arrangement broke the rule in `CLAUDE.md` that the economy must not depend on
the scene tree. Second, and more practically: the host needs exactly the same
validate-and-apply logic. Duplicating it would mean offline and hosted play could
drift apart, and such a drift would be invisible in single-player testing —
precisely the bug class that is worst to find late.

**What it rules out.** `MatchAuthority` may never emit a signal or touch a node;
it returns a rejection reason and the session decides how to say it. The
refactor was verified by the existing `LocalSession` tests passing unchanged,
since the public interface did not move.

---

### D44 — Both networked sides share one script for every `@rpc`
**2026-11-14 · Accepted**

`NetworkedSession` declares every remote method once. `HostSession` and
`ClientSession` override ordinary, non-`@rpc` handler methods instead.

**Why.** Godot routes an RPC by node path and method name: a call on the host's
`Session` node invokes the method of that name on the client's `Session` node. The
two ends must therefore agree exactly on the set of remote methods and their
modes. Declaring them in one place makes that agreement structural. Declaring them
separately on each side would make a typo or a mismatched transfer mode into a
silent "the call just never arrives", which is miserable to debug.

It also side-steps the question of whether `@rpc` configuration survives being
overridden in a subclass — nothing is overridden.

**What it rules out.** The handler indirection (`_rpc_buy` calls
`_on_buy_requested`) is one extra hop per call, and every RPC exists as a method
on both sides even though only one ever receives it. The unused side is a no-op
rather than an error, so a stray packet arriving during shutdown is harmless.

---

### D45 — A client-to-host RPC carries no player id
**2026-11-14 · Accepted**

Requests from a client name the stalk, the amount, the receiver of a yeehaw —
never who is acting. The host derives that from
`multiplayer.get_remote_sender_id()`.

**Why.** The usual advice is "validate that the caller owns the player they claim
to be". Not sending the claim at all is strictly better: there is no field to
forge, so the check cannot be forgotten at a new entry point added later. The
authority property holds by construction rather than by review.

**What it rules out.** The host cannot act on behalf of a client (there is no way
to express it), which is fine — nothing in the game needs that. It also means the
peer-to-player map on the host is load-bearing: a peer with no slot has its
packets dropped rather than being treated as some default player.

---

### D46 — A disconnected player keeps their slot in the match
**2026-11-14 · Superseded by D47, the same day**

When a peer drops, its `PlayerState` stays in the match with its cash and
holdings, and the slot becomes reclaimable.

**Why it was chosen.** Removing the player would change the economy for everyone
still playing: net worth comparisons, dividend payouts and the all-players-ready
gate all count players, so a disconnect would silently rewrite the match. Leaving
the slot looked like the conservative option.

**Why it was wrong.** It was conservative about the wrong thing. The ready gate
counts every player, so a dropped player **deadlocked the year** — the remaining
players could ready up forever and nothing would happen. Protecting the standings
at the cost of the match being unplayable is the wrong trade, and the owner called
it straight away. Kept here because the reasoning is still the reasoning behind
*retaining the portfolio* in D47; only the roster part was mistaken.

---

### D47 — A dropped player leaves the roster but keeps their portfolio
**2026-11-14 · Accepted** (supersedes D46)

When a peer drops, its player is removed from `state.players` — out of the ready
gate, the rankings, dividends and net worth comparisons. The `PlayerState` object
itself stays alive in the host's `_roster`, holding its cash and holdings, and the
slot can be reclaimed to resume it.

**Why.** Two separate questions were conflated in D46, and they have different
answers:

- *Should they still block the year?* No. A match that cannot continue is worse
  than a match whose standings changed. This is what fixes the deadlock.
- *Should their position be destroyed?* No. Removal from the roster and
  destruction of the portfolio are not the same act, and keeping the position
  costs one array.

So the player is set aside rather than deleted. That distinction is what makes
both planned successors cheap: a bot taking over a vacant slot, and a
disconnected player rejoining to resume their own position (porting-plan Phase 8).

**Rejoining is not implemented, and the retained position is inert.** An earlier
revision of this entry claimed a vacated slot could be reclaimed and the
portfolio resumed. That was wrong twice over: nothing could reach it, because a
latecomer is turned away once the match starts (D48), and handing a vacated slot
to *whoever turns up next* would let any arrival claim a dropped player's
portfolio, since the host has no way to tell a reconnecting player from a
stranger. The slot-reclaim path has been removed rather than left as a trap.

So nothing reads the retained position today. It is kept because discarding it is
irreversible while keeping it costs one array, and because both planned
successors need it — see porting-plan Phase 8. The owner's call on 2026-11-14
was to defer rejoining until Steam, which is the right point: Steam IDs are what
make "is this the same person" answerable.

**What it rules out.** A player who drops loses their place in the standings for
any year that resolves while they are away, including dividends they would have
been paid. There is no way around that without pausing the match for everybody,
which is the thing D46 got wrong. A departure is now also a trigger for the year
to resolve — `_advance_if_everybody_is_ready()` is called from the disconnect path
as well as the ready path, because a drop can be the last thing a year was waiting
on.

**Where it lives.** `HostSession._on_peer_disconnected`, `_forget_player`,
`_rebuild_active_players`. Six tests in `test_networked_session.gd` cover it,
including the deadlock itself.

---

### D48 — The roster is whoever is in the lobby at Start
**2026-11-14 · Accepted**

A host opens a lobby as the only player. Players are created as they arrive, and
the roster is fixed when the host presses Start. Latecomers are turned away with
a reason.

**Why.** The first version sized the match up front from a list of names, leaving
unclaimed slots waiting. That reproduced the D46 deadlock by a second route: the
ready gate counts every player, so a match set up for four with two people
present could never advance a year. Creating players on arrival removes the
possibility rather than guarding against it — there is no such thing as an
unclaimed slot.

It also means the menu has no "number of players" control to get wrong, and that
a solo host can simply press Start.

**The handshake.** A slot is created when a peer *introduces itself*, not when
the socket connects, because the player's chosen name arrives with the
introduction. Creating it on connection would show a placeholder name for a frame
and then rename it.

**What it rules out.** Joining a match in progress, which was already ruled out
by D42 — clients accumulate their own history and a latecomer would have none.
Also any pre-arranged seating: player ids are assigned in arrival order, so `p1`
means "second to arrive", not a particular person.

**Readiness means two things**, either side of Start: "ready to begin" in the
lobby and "advance the year" in the match. They share `PlayerState.is_ready`, so
the year gate is disabled while the lobby is open and Start clears the flags.
Without that, a lobby of ready players would resolve year 1 before anybody saw
the board.

---

### D64 — Escape backs out, and the screen host decides what that means
**2026-11-15 · Accepted**

Escape on the playing screen or in a lobby asks "leave the game and go back to
the title screen?" and, on a yes, does. Escape on the Steam browser or the
result screen goes straight back — there is nothing to lose. Escape on the
title screen does nothing.

**Why it exists at all.** There was no way out of a match. The owner found this
the obvious way: "You need to add a way to exit to the title screen so I don't
need to restart the game every time." Every repeat of a test meant killing the
process and starting the game again.

**Why it lives on `Main` rather than on each screen.** What to back out *to* is
the screen host's business. The screens are deliberately ignorant of one
another (architecture.md §6), so a screen cannot know what is behind it. `Main`
does.

**How the overlays get out of the way.** Godot delivers unhandled input from
the deepest node upwards, so the loan panel and the confirmation overlay —
both descendants of the current screen — see Escape before `Main` does and
mark it handled. Shutting a panel therefore closes the panel, rather than
asking whether you want to abandon the game. The loan panel gained its own
Escape handler for exactly this reason.

**Why it asks.** Leaving a match cannot be undone: there is no rejoin yet
(porting-plan.md), so a host who leaves ends the game for everybody and a guest
who leaves forfeits a portfolio. A single keystroke should not do that silently.

**What it rules out.** A pause menu. There is nothing else a player would want
from one — no settings to change mid-match, nothing to save — so a menu
with one item on it would be ceremony. If settings or a save ever appear, this
becomes that menu.

---

### D63 — The bottom bar reserves its tallest shape and never changes height
**2026-11-15 · Accepted**

The message column keeps room for its worst case at all times: one line for the
loan reminder, two for the news line, one for the refusal line. Labels with
nothing to say are blanked rather than hidden.

**Why.** The owner, after a two-machine game: "The bottom bar is larger for
Year 0 than subsequent years due to amount of text. It should be static." The
year-0 explanation wraps onto a second line where later messages fit on one, so
the bar was 57px at year 0 and 42px afterwards — and the boards above it
jumped down fifteen pixels to fill the gap, once per game plus every time a
loan reminder came or went.

**The number comes from the theme**, not from a pixel count written into the
scene: `_reserve_bottom_bar_height` multiplies the font's line height by the
label's `max_lines_visible`. A pixel count would be correct until somebody
changed the font, and then wrong in a way nothing would catch.

**The cost is honest.** The bar is now permanently as tall as its year-0 shape,
which is about a sixth of a 360px-high screen. That is the price of a layout
that does not move, and it is the shape the player already saw at year 0.

**What it rules out.** Letting the bar grow for an unusually long message. A
third line of news would be clipped rather than shown, because the alternative
is the thing this decision exists to prevent. If a message ever genuinely needs
three lines, raise the reserve — do not make it conditional.

**Checked.** `test_the_bottom_bar_holds_one_height_for_a_whole_match` walks a
match through year 0, two ordinary years, borrowing, a payment falling due, a
refusal on screen, settling the loan and the final year, and insists on one
height throughout. Both halves of the fix were confirmed to be load-bearing by
removing them one at a time and watching it fail.

---

### D62 — The title screen's settings travel to a Steam match
**2026-11-15 · Accepted**

`MainMenu.steam_requested` carries a `GameSettings`. `Main` keeps it and hosts
the Steam match with it. The Steam browser shows a one-line summary of what
HOST would start, and says where to change it.

**The bug this fixes.** From the owner's first Steam game: "as far as I could
tell, there was no way to enable loans for a steam lobby... setting the game
settings on the non-steam page, then clicking join steam, did not carry over
the game settings."

They did not carry over. The browser had no settings of its own, and
`_last_settings` was only ever filled in by starting a solo game or hosting a
direct one — so arriving at the browser from the title screen left it null,
and hosting fell back to `GameSettings.new()`. That default has
`loans_enabled = false`, so **every Steam match ever played had loans off**, no
matter what the title screen said.

**Why the browser does not get its own settings controls.** A match is
configured in one place. Two sets of controls for the same settings is two
places for them to disagree, and the title screen's are the ones the player has
already filled in. The browser states what it would use instead, which is the
part that was actually missing: the old screen was silent, so there was nothing
to notice.

**Why a summary and not just the carry-over.** The carry-over alone would have
fixed the behaviour and left the screen just as opaque. The owner's words were
"there was no way to enable loans" — the complaint is as much about not being
able to see the settings as about their not being applied.

**What it rules out.** Changing the settings after a Steam lobby exists. The
lobby is created before the session, so the settings are already fixed by then;
to change them, back out and start again.

---

### D61 — Every screen that can lose a connection says so
**2026-11-15 · Accepted**

`GameplayScreen` listens for `ClientSession.connection_lost` and emits
`connection_ended`, which `Main` turns into a return to the title screen
carrying the reason. It also listens for `HostSession.player_left` and says who
has gone.

**The bug.** From a two-machine game: "if host leaves, client just gets 'Not
connected' message in the game. They should be told the host left and that they
will return to the main menu."

"Not connected." is what `ClientSession._may_act` says when a client tries to
act with no seat. The board itself never noticed anything: it stayed up, fully
drawn, looking live, and answered every click with a refusal. The only way out
was to kill the process.

**Why it had been missed.** The lobby screen has handled this since the kick
was added (D49), and the lobby is where a connection was expected to fail. The
playing screen had the identical exposure and nothing connected the signal.
This is the third variation on the same theme — see D50, where a swapped-out
screen kept listening, and D51, where the board never connected
`ready_state_changed` at all. **A screen that does not connect a signal fails
silently and looks exactly like a screen with nothing to report.**

**So both ends of the chain are now tested separately**: that the board emits
when the host's peer closes, and that `Main` has something connected to it. A
screen emitting into nothing passes the first test on its own.

**No reconnection**, so there is nothing to offer and nothing to decide: say
what happened and hand back to the title screen. A rejoin is still future work
(porting-plan.md), and when it arrives this is where the offer belongs.

**The host side is informational only.** The host keeps playing — that
already worked — but a player who leaves simply vanished from the standings,
which reads as a fault. `HostSession.display_name_of` exists because a departed
player is off `state().players` by the time the signal arrives, while still in
`_roster` with their portfolio (D47).

---

### D60 — Readability rules are checked by a test, not by memory
**2026-11-15 · Accepted**

`tests/unit/test_conventions.gd` scans `src/` as text and fails on patterns
`CLAUDE.md` forbids: an inline `func` connected to a signal, a signal connected
to another signal's `.emit`, a conditional expression split across lines, a
leftover substitution placeholder, a stray `print`.

**Why.** The project had two kinds of rule and only one kind held. Static
typing is enforced in `project.godot` and has never drifted. The naming and
readability rules lived only in `CLAUDE.md` and drifted badly: eighteen signal
connections written in the forbidden style, over weeks, by the author of the
rule, without being noticed until the owner read the code and said it looked
like nonsense.

Same project, same author, opposite outcomes. The only difference was whether a
machine checked. That is strong enough evidence to stop relying on intent.

**The specific code that prompted it:**

```gdscript
_kick_button.pressed.connect(func() -> void: kick_requested.emit(_player_id))
```

Three things wrong at once, and all of them invisible to someone learning the
engine: the behaviour is buried inside the wiring, the function has no name to
search for, and `_ready()` — Godot's "this node now exists" callback — sits
right above it, colliding with the game's own idea of a player "readying up".

**What it rules out.** The checks are crude text scans and will occasionally be
wrong about something legitimate. When that happens the answer is to look hard
at whether the rule is right, and change the rule and the check together — not
to add an exception so the scan goes quiet.

**It is also a documentation gate.** A rule added to `CLAUDE.md` without a
check is a rule that will be broken. Add both or neither.

---

### D59 — Steam's waiting happens in the UI, not in the Transport interface
**2026-11-15 · Accepted**

`SteamService` (a Node) does everything asynchronous: initialising Steam,
creating a lobby, joining one, listing them. `SteamTransport` is constructed
only once a lobby exists, and turning that lobby into a `MultiplayerPeer` is
immediate. The `Transport` interface did not change.

**Why.** Steam lobbies are asynchronous — `createLobby` returns nothing and the
answer arrives on a signal — while `EnetTransport.open_server()` answers on the
spot. The obvious move was to make `Transport` asynchronous for everybody, with
a signal or an `await`. That would have rewritten the interface, both
implementations, `Main`, the harness and every networked test, to accommodate
one implementation.

The alternative is better and smaller: the waiting is a *UI flow*, not a
transport concern. A human clicks "Host", watches a lobby get made, and then
there is something to play on. So the lobby browser owns the waiting, and the
transport is handed a lobby id that already exists.

What makes this fit rather than dodge: `SteamMultiplayerPeer.host_with_lobby()`
and `create_client()` are both synchronous. The asynchronous part really does
belong before the transport, not inside it.

**Why `SteamService` is created on demand and is not an autoload.** An autoload
would initialise Steam for every run, including offline play and every test.
The port's whole point is that it works with Steam closed (D14), and the suite
must pass on a machine with no Steam client and no plugin.

**What it rules out.** A transport that has to negotiate before it can produce
a peer does not fit this interface — it would have to do that negotiation in
its constructor's caller, as Steam now does. If a future transport cannot, the
interface has to change then, deliberately, rather than being made
asynchronous now on speculation.

---

### D58 — The GodotSteam plugin is committed, the SDK never is
**2026-11-15 · Accepted**

`addons/godotsteam/` is committed in full, including the Valve redistributable
libraries it bundles. The Steamworks SDK stays ignored, as does
`steam_appid.txt`.

**Why these are different things.** The earlier `.gitignore` treated anything
matching `steam_api*` as SDK material and blocked it. That conflated two
unrelated things:

- The **Steamworks SDK** — headers, tools and docs from the partner site — is
  not redistributable and must never be committed anywhere.
- The **redistributable libraries** (`steam_api64.dll` and friends) are
  designed to ship with a game. GodotSteam bundles them in its own public
  release zip, and its `.gdextension` file lists them as hard dependencies.

**The state it was in was the worst of both.** The blanket rules would have
committed 24 of the plugin's 31 files and silently dropped the 7 it depends
on, so a fresh clone would get a plugin that fails to load in a way that looks
like a build problem rather than a missing file. Two negation rules fix it, and
they sit directly under the rules they modify with the reasoning attached.

**Why commit rather than ignore.** The alternative puts a manual download
between a stranger and a working checkout, which is exactly what the
documentation bar for this project exists to prevent. The cost is a few MB of
binaries that are already public.

**What it rules out.** The plugin is now pinned at the committed version
(4.24). Upgrading means replacing the folder deliberately rather than each
machine drifting to whatever it last downloaded — which is the better failure
mode, since a GDExtension mismatch shows up as a crash on load.

**Also learned here:** the SDK download is not needed to develop or run at all,
only to upload a build. The setup instructions said otherwise and sent the
owner to the partner site for nothing; corrected in steam-integration.md 3.3.

---

### D57 — Reuse the original's Steam App ID, 1821800
**2026-11-14 · Accepted**

The port ships under the existing App ID rather than a new one. Owner's call,
confirmed against `steam_appid.txt` in the original project.

**Why.** The store page, its reviews, and every achievement players have already
unlocked carry over. A new App ID would mean a fresh store page with no reviews
and the Steam Direct fee again, for a game that is the same game.

**What it rules out, and this is the important part.** The achievement ids are
no longer ours to choose. Whatever the partner backend holds is correct, and a
name that disagrees with it does not error — it silently never unlocks. The
same goes for the stat names the counters use.

That turns the original's casing bug from a wart into a live hazard. It sets
both `SSS_WIN_ONE_GAME` and `SSS_Win_One_Game`, and both `SSS_LOSE_ONE_GAME` and
`SSS_Lose_One_Game`, because Steam's names are case-sensitive and the author was
hedging.

The win pair is settled by reading the original more closely: its only live call
is `SetAchievement("SSS_Win_One_Game")` — the shouting version is commented out
— so that is the spelling real players have actually unlocked, and therefore
what the backend holds. The lose pair sets **both** on consecutive lines, so one
is a no-op and the source cannot say which. That is the single remaining
unknown, recorded in `Achievements.UNCONFIRMED_CASING`.

**Where it lives.** `src/data/achievements.gd` is the catalogue, with every
trigger condition written down; `tests/unit/test_achievements.gd` fails if two
ids ever differ only by case again.

---

### D56 — A session is handed a transport; it never builds one
**2026-11-14 · Accepted**

`HostSession.host()` and `ClientSession.join()` take a `Transport` and ask it
for a `MultiplayerPeer`. `EnetTransport` is the only implementation today;
`SteamTransport` is Phase 6.

**Why.** "Steam is a transport swap, not a rewrite" was the reason Steam was
deferred to a late phase, but the sessions built an `ENetMultiplayerPeer`
themselves, so it was a claim rather than a property of the code. It is now
structural: nothing above the transport knows what carries the match, down to
the lobby, which asks for a `joining_hint()` rather than branching on whether
to print a port or an invite.

`tests/unit/test_transport.gd` stands a host and a client up on a transport that
is deliberately **not** ENet, using a real `OfflineMultiplayerPeer`, so the
property is tested rather than asserted in a comment.

**ENet stays after Steam arrives.** Direct connection is how the automated tests
run — they cannot depend on a Steam client being installed — and it serves LAN
play and anyone outside Steam. A transport is a choice, not a migration.

**What it rules out.** A transport cannot need arguments at connect time: each
is constructed with what *it* needs (a port, later a lobby id), because ENet and
Steam disagree about what "where" even means. It also means a transport that
connects asynchronously, as Steam lobbies do, must report that through the
peer's own signals rather than by blocking in `open_server`.

---

### D55 — An overlay closes when its errand is done
**2026-11-14 · Accepted**

The loan panel closes itself after a successful borrow or payment, reporting
what happened on the board behind it. A *refused* attempt keeps it open and
shows the reason inside the panel.

**Why.** Borrowing left the panel open, where it switched to its pay controls —
so the moment you took a loan you appeared to be asked for money you had just
received. The panel is somewhere you go to do a thing, not a screen you inhabit;
when the thing is done it should hand you back to the game.

**The refusal half was a real bug, not a nicety.** `action_rejected` wrote to the
board's message line, which the open panel covers. A borrow refused for being
over the 25% limit reported its reason somewhere the player could not see it.
Refusals now go to whichever surface the player is actually looking at.

**What it rules out.** Paying twice in a row now takes two trips through the
panel. That is the right trade against the confusion of it staying open, and
the second trip is one click.

**Note for any future overlay**: a panel that covers the message line owns its
own error reporting. This is the second time a message has been delivered where
it could not be read — see D54 for the first.

---

### D54 — Only a refusal is cleared by a state change, and only your own
**2026-11-14 · Accepted**

The board's message line keeps an informational message when state arrives; only
a rejection is swept away, and only when the change was the local player's. The
same rule governs clearing a half-typed quantity.

**Why.** Reported from play: a client never saw "Host wants a yeehaw!", though
it saw its own dividend messages. The board cleared its message on *any* state
change, and the host follows every broadcast with a state push — so on a client
the message was wiped in the same frame it appeared. Hosting hid it entirely,
because the host never pushes state to itself.

The second half was found while fixing the first: the amount fields were also
reset on every state change, so a half-typed quantity vanished whenever anybody
else traded.

**What it rules out.** A rejection shown to one player now outlives another
player's action, expiring on its own timer instead. That is the right trade: a
message that disappears before it is read is worse than one that lingers.

**The pattern, for the third time.** Host and client differ in *what arrives and
in what order*, not in what the code says. Anything driven by a signal needs
checking on the side that receives the most of them.

---

### D53 — Ending a year with a loan payment due asks first
**2026-11-14 · Accepted**

Pressing Ready with an outstanding payment opens a confirmation naming the
penalty. Saying yes goes ahead.

**Why.** The payment stays *advisory* — game-rules 9.5, and the game must never
take the choice away. What was wrong was that the cost was invisible at the
moment of choosing: the nag sat in the bottom bar, easy to miss, so a player
could lose 10% of a loan balance without ever registering that there was a
decision. Asking is not blocking; it is making the choice visible at the point
it is made.

The message names the actual consequence — 10%, 15%, or seizure on the third
miss — because "are you sure?" without a consequence is noise. The percentages
are derived from `LoanRules`' multipliers rather than written out again, so what
the player is shown cannot drift from what they are charged.

**Built as a widget, not `ConfirmationDialog`.** Godot's dialog opens a real OS
popup window, which escapes the 640x360 viewport and breaks the pixel grid
(D40). `ConfirmPanel` is an ordinary `Control` inside the game's own resolution,
styled by the shared theme, following the overlay pattern the loan panel already
uses.

The safe button takes focus, so a stray Enter cannot commit to the costly
option, and Escape dismisses.

---

### D52 — An unanswered yeehaw does not outlive the year
**2026-11-14 · Accepted**

A pending yeehaw request is cleared when the year advances.

**Why.** The original never cleared it — the flag was set on request and
unset only on give. So one ask that nobody answered left every player's button
reading "Give Yeehaw" for the rest of the match, and nobody could ask again.
That is a wart rather than a design, and a new year is the natural place to let
a social gesture lapse.

**What it rules out.** A request cannot span a year boundary, so "ask now,
answer after the year resolves" does not work. Nobody wants that.

---

### D51 — Readying up is reversible, and always visibly acknowledged
**2026-11-14 · Accepted**

Pressing Ready on the playing screen toggles rather than latching, and the board
reacts to `ready_state_changed` — the button becomes "Waiting...", the other
players' dots update, and the status line names who is being waited for.

**Why.** Reported from a real two-window game as "couldn't interact with the game
at all". The board never connected `ready_state_changed`, so pressing Ready
changed nothing whatsoever on screen. In a solo game the year advances the
instant you press it, so the gap never showed; in a networked one the screen
simply stopped responding, which reads as broken rather than as waiting.

Two separate faults, which is why the symptom was so total: no acknowledgement
that the press registered, and no way to undo it. `_on_ready_pressed` hard-set
`true`, so a player who readied by accident was stuck waiting for a year they
did not want to start.

**What it rules out.** Readiness can no longer be treated as a one-way latch, so
anything that assumes "ready means ready for good" is wrong. That is the right
way round: the lobby already toggles, and the two screens disagreeing about what
the same button means would be worse.

**The general lesson, which is the valuable part.** Solo play hides every bug of
this shape, because in solo the local player is the only one and every action
resolves immediately. Any control whose effect depends on *another* player needs
its own test with a real second peer. Four tests in `test_client_board.gd` now
cover this one, and all four were confirmed to fail without the fix.

---

### D50 — A screen stops listening the moment it leaves the tree
**2026-11-14 · Accepted**

`LobbyScreen` and `GameplayScreen` disconnect from the session in `_exit_tree()`,
and refuse to rebuild their rows when not inside the tree.

**Why — this is a crash fix, not tidiness.** `Main` swaps screens with
`remove_child` followed by `queue_free`, and `queue_free` is deferred to the end
of the frame. A replaced screen is therefore still alive, and still connected to
the session, when the next signal arrives.

That is not theoretical. `HostSession.start_match` sends `match_started` and then
a state broadcast. On a client the first swapped in the playing screen and the
second reached the lobby already on its way out; it rebuilt its player rows while
detached from the tree, where `_ready` never runs on a newly added node, so every
`@onready` in those rows was null and the client died mid-swap. From the outside
it looked like "the client didn't load anything".

**This is the third appearance of deferred `queue_free`** in this project — after
sold-out holdings rows lingering, and `Main._swap` needing `remove_child` rather
than only queueing. It is the single most reliable way to be wrong in this
codebase, and the pattern is always the same: the object is gone logically and
present actually.

**What it rules out.** A screen cannot keep a session subscription across being
detached and re-attached; `_attach` and `_detach` have to stay symmetrical, and
adding a signal to one means adding it to the other. That is a real maintenance
cost and worth it.

**Verified by removing the fix.** The first regression tests written for this
passed *with the fix removed*, because they poked the session with a buy at year
0 — which is rejected, and a rejection broadcasts no state. They were rewritten
to reproduce the real sequence and confirmed to fail without the fix. A
regression test that has not been seen to fail is not evidence.

---

### D49 — Start waits for everybody; the host removes anyone holding it up
**2026-11-14 · Accepted**

The host's Start button is disabled until every other player has readied up. The
host does not ready up themselves — pressing Start is their readiness. To get out
of a lobby held up by somebody who has wandered off, the host **removes** them.

**How this arrived.** The first version gave the host a READY button that did
nothing: they could press Start regardless, and Start clears every flag anyway.
The owner found that in the first real two-window test. The fix for the dead
button was easy; what it exposed was the real question, which is whether a
not-ready player should be able to hold the match shut.

I argued no, and made Start always available, on the grounds that one idle player
would otherwise deadlock the lobby — this project having walked into that exact
failure three times already (D46, D47, D48). The owner's answer was better: gate
the start properly, and give the host a kick. That removes the deadlock without
making readiness meaningless, which is what an always-available Start does.

**Why the kick is the right escape.** A rule cannot tell the difference between
somebody reading the rules and somebody who has left the room. A person can. The
deadlock is real, but the answer is to give the host a decision rather than to
guess on their behalf or to let them steamroll a player who is simply slow.

**Lobby only.** `kick_player` refuses once the match has started. Removing
somebody from a running match changes the economy for everybody still playing,
which is the whole subject of D47, and nothing asks for it yet.

**Where it lives.** `HostSession.why_not_start`, `waiting_on` and `kick_player`;
the button on `LobbyRow`. The rule is on the session rather than only on the
button so that it has one home — the host is the authority, so this is not a
security boundary, but a second caller should not be able to skip it.

**What it rules out.** A host cannot start a match while somebody is connected
and not ready; the only way past is to remove them. If that ever proves annoying
in practice — a friend who readies slowly every single time — the thing to add is
a countdown, not an override.

**Still named, not counted.** The status line says "Waiting on Ann and Bob"
rather than "2 of 4 ready", because the host is deciding whether to wait for a
particular person.
