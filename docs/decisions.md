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
