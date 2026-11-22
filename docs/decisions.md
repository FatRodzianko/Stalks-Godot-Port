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
**2026-11-14 · Accepted, and amended by D110 on 2026-11-18** (supersedes D46)

**Read D110 first if you are looking at this code today.** The *question* D47
answers is still the right question and its two-part answer is still the
reasoning the code runs on: a dropout must not deadlock the year, and their
position must not be destroyed. What changed is the mechanism. D47 achieved the
first by removing the player from `state.players`, which was the cheap way to
stop the gate waiting on them and took them out of the economy as a side
effect. D110 keeps them in `state.players` and makes the gate skip them
instead, so the position is not merely retained but still live. Everything
below stands as written except where it says a dropped player is removed from
the active roster.

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

**What it ruled out, and no longer does.** A player who dropped lost their
place in the standings for any year that resolved while they were away,
including dividends they would have been paid. That was accepted here as the
price of a match that keeps running — "there is no way around that without
pausing the match for everybody, which is the thing D46 got wrong". The claim
was wrong: there was a third way, which is to leave them in the economy and
take them out of the gate. See D110. A departure is now also a trigger for the year
to resolve — `_advance_if_everybody_is_ready()` is called from the disconnect path
as well as the ready path, because a drop can be the last thing a year was waiting
on.

**Where it lives.** `HostSession._on_peer_disconnected` and `_forget_player`.
`_rebuild_active_players` and the second roster list it maintained are gone;
see D110. Tests in `test_networked_session.gd` cover it, including the deadlock
itself.

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

### D75 — A separate release preset, and an upload script that does not upload
**2026-11-16 · Accepted**

**A second export preset, `Windows Release`.** The everyday build and the build
a player installs are not the same artifact and should not overwrite each
other in the same folder. The release preset writes to `..\stalks-release\`
and excludes `tests/`, `addons/gut/` and `.gutconfig.json`.

Measured, not assumed: the debug pack holds 556 resource paths, 248 of them
GUT and 56 of them tests. The release pack holds 209 and none — 4.1 MB
against 5.7 MB. Shipping a test framework to players is not a crime, but it is
a third of the pack and it tells anybody who opens it where the seams are.

**`tools/steam_upload.ps1` writes SteamPipe's two build scripts and stops.**
It does not upload. Uploading needs a Steam password and a two-factor code
that only the owner can type, and a failed upload is far easier to read when
the command that caused it is on screen. `-Run` is there for when that stops
being interesting.

**The build scripts are generated, not committed.** They carry a depot id read
off the partner site and an absolute path to one machine's build folder.
Neither belongs in a repository that is meant to make sense on a fresh clone.

**Three refusals, because each one is a mistake that is silent otherwise:**

- a content folder without an `.exe` and a `.pck` uploads happily and breaks
  on install
- `steam_appid.txt` in the build folder ships a development-only file, against
  Valve's own guidance; the preset excludes it, this catches a hand-copied one
- `-Branch default` publishes to everybody who already owns the published
  game. It needs `-AllowDefaultBranch` as well, so it cannot be a typo

**The depot id is not guessed.** It is conventionally the App ID plus one, and
that convention is not a guarantee. `publishing.md` says where to read it.

**What it rules out.** An upload from CI, or from here. Publishing the port
over the published Unity build is a decision about a store page, existing
owners and their achievements — not a build step, and nothing in this
repository should be able to do it by accident.

---

### D74 — Settings is a third tab, and failures say what went wrong
**2026-11-15 · Accepted**

Two things, both about what the title screen tells you.

**Settings sits beside Create Game and Join Game**, as a third tab rather than
behind a cog. That is the owner's own description of this screen: make a game,
join a game, settings. It holds the effect volume and nothing else — display
options can join it when somebody wants them.

The volume had existed, persisted and applied itself at startup since D71,
with nothing on screen able to change it. This is the control that was
missing.

**Moving the slider plays a clip**, which is the original's behaviour: its
settings screen played `bull2` on every change. Bearable here because the
slider steps in fives, so a full drag is twenty sounds rather than one per
frame — the same step is why saving on every change is a handful of writes
and not hundreds.

**The name field is hidden under Settings.** Nothing there is done under a
name, and a field with no purpose invites a player to wonder what it is for.

---

**Failures say what went wrong.** Every error from the network layer used to
reach the screen as a bare number: *"Could not listen on port 42420 (24)"*.
That helps nobody — not the player, and barely the person receiving the
screenshot, since nobody knows which enum 24 belongs to either.
`Transport.describe_error` turns the codes this layer can produce into a
clause, and unknown codes keep their number rather than being given an
invented sentence.

**A taken port is `ERR_CANT_CREATE`, not `ERR_ALREADY_IN_USE`.** Found by
writing the obvious mapping and watching the end-to-end test fail with "the
connection could not be opened" — which is true, useless, and exactly what a
player hitting the commonest networking failure would have been told. The
generic description cannot name the cause, because on the client side the same
code means something else, so `EnetTransport` decides that one itself.

**"See the log" is gone.** A broken install used to be reported as *"The
game's content is broken — see the log"*, which is advice a player cannot
take: there is no log window and the file is somewhere nobody has told them
about. It now names the thing they can actually do, and the detail still goes
to the log for whoever is debugging.

**Amended the same day, from play.** Two things in here were wrong.

**The preview must not play on every step of a drag.** Reported: "the previous
sound clip keeps playing when the new one starts — this creates a delay or
echo effect, and makes it difficult to tell what the actual volume you are
setting will be". Exactly right, and the cause is that the clip is longer than
the gap between steps, so a drag stacks previews and the only part at the
volume you chose is the tail. Two changes: the clip is played when the slider
is **let go** (`drag_ended`), and the preview has a **player of its own** so a
new one stops the last rather than sounding over it. A change made without a
drag — the arrow keys, a click on the track — has no release to wait for and
previews immediately, which is why the dedicated player is needed as well as
the deferral and not instead of it.

A third fix followed from testing the first two: a clip still sounding when a
drag *began* rode the volume up and down with the slider, because moving the
bus moves everything on it. That is right for a mixer and wrong for feedback,
so grabbing the slider now silences the last preview. A drag is quiet
whatever was happening before it.

The original played a clip on every change, so this is a place where copying
the original was the wrong instinct: its slider and this one do not have the
same step size or the same clip length.

**A client cannot be told "nothing was listening".** The A9a test step written
above asked for a sentence naming an address after joining one with nothing on
it, and that is not what happens — reported as "I don't understand what this
is saying". ENet is UDP: `create_client` on a valid but dead address returns
`OK`, because there is nobody at the far end to refuse it. Probed rather than
assumed: a dead `127.0.0.1` opens fine, while `nope`, `1.2.3` and
`999.999.999.999` all fail with `ERR_CANT_CREATE`.

So the only failure `open_client` can report is an address that could not be
resolved, and it now says so by name: *"Could not find nope. Check the address
for a typo."* A valid address with nothing on it is reported by the join
timeout instead, twelve seconds later, which is why that message is about the
host and not the address.

**What it rules out.** A settings screen of its own, for now. One tab holding
one row does not need to be a whole screen, and making it one would be
building the thing the owner declined twice.

---

### D73 — The year history shares the result screen rather than the board
**2026-11-15 · Accepted**

The result screen has two tabs over one list: **FINAL STANDINGS** and **YEAR
BY YEAR**. The second is one row per year — the year, its mood, what you were
worth at the end of it, and what the market did.

**The original had no such view.** This is a port addition, so the shape was
chosen rather than copied, and the plan's note that the groundwork was "laid
for charts" is what it answers.

**Nothing new crosses the wire.** Every machine already keeps the history: a
client appends each year's result as it arrives and the host keeps its own.
The feature is entirely presentation over data that was already there, which
is why it needed no RPC and no change to `StateSync`.

**On the result screen, not the board.** The board is dense already and its
bottom bar is full; adding a control there is the kind of unasked-for change
that has gone badly in this project before. The result screen is also where
the question actually gets asked — "how did that happen?" is a thing you
wonder when it is over.

**Tabbed over the standings, not added below them.** The card is 520x310
inside a 640x360 window and there was no room for a second list. A tab costs
one row.

**What it rules out, for now.** Looking at the history *during* a match. If
that is wanted it needs somewhere on the board to live, which is a layout
question rather than a data one.

**A quiet year says "a quiet year"** rather than leaving the column blank,
because a blank cell reads as missing data.

**Two faults the rendering caught that the assertions could not.** The verdict
read "**You wins**" — the solo player is literally called "You", and that is
the first line of the screen every single-player game ends on. And the column
headings ran together as "NET WORTHWHAT HAPPENED": the gap was real but six
pixels, which at this font is narrower than a space. Both were found by
photographing the screen, not by testing it, which is the argument for
`tools/history_shot.gd` existing at all.

---

### D72 — Sound is an autoload, and plays what the original played
**2026-11-15 · Accepted**

`AudioService`, registered as the `Audio` autoload, owns six players on an
`SFX` bus and the effect volume. The board asks it for a mood when a year
resolves, for breaking glass when anything goes under, and for a yeehaw when
one is given.

**An autoload, which this project is otherwise sparing with.** CLAUDE.md names
audio as a service that earns one, and it does: sound is triggered from more
than one screen and belongs to none of them. It stays thin — players, clips
and a volume, no game rules.

Both the autoload and the bus layout were registered by editing
`project.godot` directly, as CLAUDE.md asks. Two things follow that are easy
to trip over. **The editor needs the project closed and reopened** before a
hand-added autoload appears under Project > Project Settings > Globals.
And **Godot strips comments out of `project.godot`** the next time the editor
saves it, so the reasoning for anything registered there has to live in a
docstring or here, not in the file itself — the comments originally written
beside these two entries were gone by the following day.

**Two details from the original that a reimplementation loses by default**,
both read out of `GameplayManager.RpcPlayBearOrBullSounds`:

- A mood plays **two clips at once**. `bull1` and `bull2` together, `bear1`
  and `bear2` together. Layered, not alternated, and not one of them.
- A bankruptcy plays breaking glass **and** a scream, together, and **once per
  year** however many stalks went under. The original used a
  `bankruptThisTurn` flag; here the year's result arrives once, so the guard
  is structural rather than a variable.

Nothing plays for a split, or for buying and selling. That is the original's
choice and not an omission.

**Six voices**, because a yeehaw can land in the same frame a year resolves:
two mood clips, two bankruptcy clips and a yeehaw is five. Players are reused
round-robin rather than searched for a free one, which with clips this short
is both simpler and less likely to find none.

**Zero means silence, not quiet.** Godot's bus volume is in decibels, so a
naive percent-to-dB conversion leaves 0% faintly audible. It is special-cased
to the bottom of the mixer.

**The files are the original's, copied on the owner's instruction.** They were
left out until asked for, because this repository is public and at least two
of the seven are recognisable stock sounds of unknown licensing — the same
reason `reference-images/` is gitignored. That is the owner's call to make and
they made it.

**Tested without listening.** A headless run uses a dummy audio driver, so
"did it make a noise" is not a question a test can ask; which clip each player
was handed is. That is where both inherited details live, and both are the
kind a later change would quietly reduce to one clip. The board's end is
tested separately, because a correct service nobody calls sounds exactly like
no service at all — confirmed by removing the call and watching it fail.

**What it rules out.** Positional audio, music, and per-sound volumes. There
is one bus and one slider's worth of state, and Master is left free in case
music ever arrives.

---

### D71 — Preferences are kept on disk, and the game leaves cleanly when closed
**2026-11-15 · Accepted · amended the same day**

`UserSettings` keeps preferences in `user://settings.cfg` — Godot's
equivalent of Unity's PlayerPrefs, written as a named file rather than hidden
in the registry. Closing the window discards the session properly instead of
vanishing.

**Amended within hours.** The first version also remembered the Create Game
fields: years, starting cash, loans, invite-only and the game's name came back
next session. The owner asked why, and there was no good answer — defaults
plus editable controls already did the job, and a remembered year limit means
the title screen stops *showing* the game's actual defaults, permanently, with
nothing on screen to say so. That is the same objection that had already got
the seed excluded, and I failed to apply it to the other five fields. Removed;
`test_the_title_screen_remembers_nothing` keeps it out.

What survives is the mechanism, which the phase genuinely needed: nothing in
this game had ever been written to disk, so "mixer and volume settings" had
nowhere to live. The volume is now the only thing in the file, and the bar for
adding anything else is high.

**The first piece of Phase 7, and a prerequisite for the rest of it.** The
phase asks for "mixer and volume settings", and there was nowhere to keep a
volume: nothing in this game had ever been written to disk.

**Closing the window does not ask.** Clicking the X is not a keystroke
somebody hits by accident, and a confirmation in front of a window that is
already going away is an argument with somebody who has finished. Escape asks
because it is reversible; this is not.

**What it does do is leave properly.** Before this, closing the window skipped
`_discard_session` entirely: a host's Steam lobby was never marked shut and
its peer was never closed, so the lobby survived until Steam noticed it was
empty. `auto_accept_quit` is off and `NOTIFICATION_WM_CLOSE_REQUEST` does the
tidying before quitting.

**What it rules out.** A settings screen. There is nothing in here a player
chooses twice, and the owner has not asked for one; when volume arrives it
will need one, and this is the store it will use.

---

### D70 — Achievements are decided by pure rules and reported by a thin node
**2026-11-15 · Accepted**

`AchievementRules` (`src/sim/`) takes a match and returns the ids earned. It
has never heard of Steam. `AchievementReporter` (`src/net/`) watches a session
and hands whatever it returns to `SteamService`, which does nothing at all
when Steam is not running.

**Why the split is sharper here than elsewhere.** Every rule in `src/sim/` is
pure so it can be tested without a window; this one has a second reason. The
only other way to check an achievement is to unlock it for real on somebody's
Steam account, and because the App ID is the published game's (D57), that is
permanent and public. An achievement cannot be un-earned one test at a time
— `resetAllStats(true)` wipes the lot or nothing. So the thresholds have to
be right *before* anything is ever sent, which means they have to be provable
without sending anything.

**Per-player and local.** Each machine judges its own player from the replica
it already has. Nothing crosses the wire, no RPC was added, and a client does
not wait on the host to be given anything. The host is authoritative over the
economy; it is not authoritative over somebody else's Steam account.

**Holdings are remembered from before each year**, because `YearResolver` sets
a bankrupt stalk's shares to zero. Asking the current state whether you held
the stalk that just went under would answer no, every time, and
`SSS_BANKRUPT` would never unlock — silently, since Steam does not complain
about an achievement you simply never set. The reporter keeps the previous
holdings and `AchievementRules.for_year` takes them as an argument rather than
reaching for live state.

**Everything reached, not only what was just crossed.** A returning player
whose Steam stats are already past a threshold from the original game is given
those achievements the first time they finish a match here. Setting one that
is already set is harmless, which is what makes this safe.

**Deliberately untested.** The owner declined to test them, and was right to:
testing would unlock achievements on their own account for the published game.
28 tests cover the thresholds instead. What is unproven is the wiring — that
Steam receives what the rules decide — and that is one `setAchievement` call
behind a `_initialised` check.

**What it rules out.** Achievements awarded by the host on a client's behalf,
and any achievement that depends on something only the host can see. Every one
of the 25 is decidable from what a player's own machine already knows, which
is not a coincidence — the original worked the same way.

---

### D69 — Getting into a lobby belongs to the screen host, not to a screen
**2026-11-15 · Accepted**

`Main.join_online_game(lobby_id)` owns the whole business of getting into a
Steam lobby and then into the match inside it. The online games list only
emits which lobby was picked.

**Because there are three ways in and only one has a screen attached.** You
can pick a game from the list; you can accept an invite while the game is
running, with the list nowhere in sight; and you can accept an invite while
the game is **closed**, in which case Steam launches it for you. The list
screen used to call `join_lobby` and wait for `lobby_joined` itself, which
works for exactly the first of those.

**An invite from cold is a command-line argument.** Steam starts the game with
`+connect_lobby <id>`. That is parsed by `SteamService.lobby_from_command_line`
and acted on in `Main._ready` before anything else happens — deliberately not
through `LaunchArgs`, which ignores everything in a release build so that a
shipped game cannot be made to auto-host by a stray argument. An invite has to
work in precisely the build `LaunchArgs` refuses to read.

**Sending an invite opens Steam's own dialog**
(`activateGameOverlayInviteDialog`), rather than building a friend list.
Steam's picker already knows who is online, who owns the game and how to word
an invitation; `inviteUserToLobby` would need a Steam id we have no screen to
collect. The lobby's INVITE button emits `invite_requested` and knows nothing
about how inviting works, like every other control on it.

**Any member may invite, not just the host**, so the button is shown for an
online match rather than for a hosted one.

**Invite-only lobbies** are `k_ELobbyTypePrivate` at creation. A private lobby
is never returned by a lobby list search, so "invite only" and "not listed"
are the same switch rather than two. The setting has been in
`game-rules.md` §2 since the port began and was the only one there with no
implementation.

**What it rules out.** Inviting somebody to a match already under way. The
host shuts the lobby on Start (D68), so an invite sent afterwards leads to a
lobby that refuses the join — reported now as "That game is not open to new
players" rather than a bare code.

---

### D68 — A Steam lobby cannot be destroyed, so the host shuts it instead
**2026-11-15 · Accepted · extends D67 · amended by D104, D105 and D106**

**Amended 2026-11-18.** The fact below is unchanged and is the foundation of
host migration: a Steam lobby outlives its owner, and Steam promotes another
member by itself. What changed is the conclusion drawn from it. The sentence
below saying this game has no host migration and is not getting any was
reversed by the owner on 2026-11-18 - see D104 - and shutting the lobby down on
the way out now happens only when the host is the last member in it (D106).

When the host leaves, they call `setLobbyJoinable(false)` and set the lobby's
`state` to `playing` **before** calling `leaveLobby`. Members are told the host
has gone by `lobby_chat_update`, and leave too, at which point Steam disposes
of the lobby itself. This game has no host migration and is not getting any:
the host leaving ends the match.

**This replaces a guess.** D67 was written without reading Steamworks'
documentation — the twelve-second join timeout in it was a number I chose,
and the comment justifying it was written after the fact. The owner asked
where it came from, and whether a host could simply tell Steam to destroy the
lobby. Both were fair questions and I had not looked.

**What the documentation actually says**, from
`partner.steamgames.com/doc/api/ISteamMatchmaking` and the matchmaking feature
page:

- **There is no destroy or delete call.** "Once all users have left a lobby,
  it is automatically destroyed." So a host cannot end a lobby; it can only
  stop being in it.
- **Ownership migrates automatically and cannot be prevented.** "There always
  one lobby owner — if the current owner leaves, another user in the lobby
  will become the owner automatically."
- **`setLobbyJoinable(false)`** stops new members, including invited ones, and
  per the documentation takes the lobby out of search results.
- **`lobby_chat_update`** reports a member entering, leaving, disconnecting,
  being kicked or being banned, as a bitfield.

**So "the host leaving kills the lobby" is a thing the game does, not a thing
Steam does.** The sequence above is as close as the platform allows, and the
lobby's last moments belong to clients who are already on their way out.

**Steam lobby ownership is not this game's host.** When the host leaves, Steam
hands the lobby to somebody else within milliseconds. A client therefore
cannot ask `getLobbyOwner` who the host was — by the time it asks, the answer
has changed. `Main` records the owner's Steam id when it joins and compares
departures against that.

**The timeout stays, demoted.** `lobby_chat_update` covers the case that was
actually reported, and joining a lobby that no longer exists was already
covered by `lobby_joined`'s response code. The clock now catches only what
neither of those does — a host who stops responding without leaving. Twelve
seconds is still an arbitrary number, and it is now in a place where being
arbitrary costs little.

**Both shutting mechanisms are used**, which is not redundancy: they stop
different things. `setLobbyJoinable` blocks somebody holding an invite or a
stale lobby id; the `state` key is what the browser's own string filter reads.
One caveat recorded honestly: the sentence about non-joinable lobbies being
excluded from search came from a summary of the page rather than text I could
read verbatim, whereas string filters on lobby data are plainly documented.
Keeping both means the part I verified carries the result either way.

**What it rules out.** Host migration. If it is ever wanted, the lobby is the
wrong place to build it — Steam has already moved the lobby on by then. It
would need the game to nominate a successor and the clients to reconnect to
them, which is Phase 8 work and much larger than it sounds.

---

### D67 — A join gives up on a clock, and a started game leaves the list
**2026-11-15 · Accepted**

A client that has opened a socket but not been welcomed gives up after
`ClientSession.JOIN_TIMEOUT_SECONDS` (twelve). While it waits, the lobby says
"Connecting to the host..." and its Ready button is disabled. Separately, a
host marks its Steam lobby `state=playing` when the match starts, and the
browser lists only lobbies still reading `state=open`.

**Two faults from the same session, both about a player being offered
something that is not there.**

**1. A host leaving mid-join left the client stuck for ever.** It showed the
ordinary "Waiting for the host to start" and a Ready button that answered
"Not connected." to every press. Nothing said anything was wrong; LEAVE was
the only way out.

Over ENet this could not happen: a host that goes away produces
`connection_failed` or `server_disconnected`, and the lobby already acts on
both. **Over Steam it does not.** The peer-to-peer session simply stops
carrying traffic, and nothing tells the client. So a signal-based fix would
have worked on the transport that was not broken and not on the one that was.

A clock catches every way of not arriving, including ones neither transport
has thought of yet. Twelve seconds because Steam's relay can take several to
negotiate a route, and a false failure is worse than a slow one.

**The Ready button is disabled while waiting**, which is the smaller half of
the fix and the half a player notices first. A control that refuses every
press reads as a broken game; a disabled one with "Connecting..." beside it
reads as a game that is working.

**2. Games already under way were still listed as joinable.** Joining one put
the player through a lobby and back to the title screen a few seconds later,
when the host refused them. The refusal was right — `HostSession` has always
turned away a latecomer, because a client accumulates its own history (D42)
and somebody arriving at year 5 has none. Offering the game at all was the
fault.

**Marked with lobby data rather than `setLobbyJoinable`,** because the browser
already filters on lobby data for the game tag, so this is one more string
filter on a request that was being made anyway, and it is visible to anybody
debugging a lobby from Steam's own tools.

**What it rules out.** Joining a match in progress, which was already ruled
out, and is now ruled out one step earlier. If a rejoin ever arrives (see
porting-plan Phase 8) this filter is what it has to change: a lobby would need
a third state, open to the player who dropped out of it and closed to
everybody else.

---

### D66 — Steam names the players; the host names the game
**2026-11-15 · Accepted**

In an online game every player is named by their Steam account. The title
screen's **Your name** field applies to local games only, where there is no
account to ask. Separately, the host names the **match**, and that name heads
the lobby on every machine in it and labels the row in the online games list.

**Three faults, found in the first game after the title screen was rebuilt,
and all three are mine from that rebuild or older than it.**

**1. Steam players showed as "Player".** The old menu asked
`SteamService.persona_name()` when hosting or joining a Steam match. The
rebuild replaced that with the name typed on the title screen, which defaults
to the stand-in "Player". Worse, a name typed for an unrelated local game
earlier in the session was still in the field, so it became your name in a
Steam lobby — which does not read as a bug, it reads as a deliberate choice
somebody made for you.

The fix is not a better fallback. It is that **the field has no say at all**
in an online game, so `host_online_requested` no longer carries a name and
`browse_online_requested` carries nothing. A value that is only sometimes
honoured is worse than one that is never sent: the first is confusing, the
second is explainable. The field's placeholder now says where it applies.

**2. There was no way to name a game.** A lobby was always
`"<persona>'s game"`, hardcoded at the point Steam created it. A player could
name themselves but not the thing they were making, which is backwards — your
name is already on your Steam account, and the match is the thing other people
are choosing between in a list.

`game_name` is a **`GameSettings` field**, not Steam lobby data, because it has
to reach the clients and the settings already do: they travel in the opening
snapshot. Steam lobby data only reaches somebody browsing, not somebody
already in the lobby, so a heading built from it would be blank for everyone
who had joined. It also means a local game has a name, which Steam metadata
could never give it.

Blank is allowed, and `Main._name_the_match` fills it in from whoever is
hosting — for an online game, that is the Steam account, which the title
screen has not asked about and should not have to.

**3. The lobby was headed "LOBBY" or "JOINED".** A word for which end of the
connection you were on. You know which end you are on; you pressed the button.
It now reads the name of the match, which is the thing a heading is for and is
the same on both machines.

**And the host is marked**, as "(Host)" after their name in the rankings and
on the result screen, on every machine. It rests on one rule — the host is
always the first player — which is now written once as
`GameState.host_player_id()` rather than spelled `players[0]` by each screen
that wants it.

The first attempt used a leading `*` and put the explanation in a tooltip, on
the grounds that the column is only a few characters wide. The owner's answer
was that a symbol nobody can read without hovering is not a marker, and that
the width was my problem to solve rather than theirs to decode. Both tags go
in one bracket — "(Host, you)" rather than "(Host) (you)" — which is where
the width saving actually comes from.

**What it rules out.** Playing online under a name of your choosing. That is a
real thing some games offer, and if it is ever wanted it belongs next to the
online controls and labelled as an alias — not as a field that silently
overrides your Steam identity, which is what it had become.

---

### D65 — Create Game owns the settings; the kind of game is a choice on it
**2026-11-15 · Accepted · replaces D62**

One **Create Game** panel holds every match setting — years, starting cash,
loans, seed — and three ways to begin with them: single player, host online
through Steam, host on the local network. **Join Game** holds the list of
online games and a direct address for a local one, and no settings at all.
There is no Steam screen.

**What was wrong.** The title screen had SOLO / HOST / JOIN tabs with the
settings on the first two, and a separate "Play on Steam" screen with a HOST
button and no settings. Steam is how this game is actually played; hosting
locally exists so two windows can be tested without Steam running. So the
configuration lived on the development path and was absent from the real one,
and a Steam match was hosted with a default `GameSettings` — ten years, loans
**off** — whatever the player had chosen.

**D62 did not fix that.** It carried the settings across and put a read-only
summary on the Steam screen. That made loans work and left the shape wrong: a
game was still being created on a screen whose job is finding games, by a
player looking at numbers they could not change, chosen on a screen they had
left. The summary was an admission that the player could not see where they
were. The owner's objection, which is the right one: *when you make a game,
the settings should be there.* I could not name a single game that splits them
this way, and did not look for one before shipping it.

**The original did it the other way**, and this project's own
`game-rules.md` §2 records it: these were "lobby settings", chosen where the
game was made. The reference material said so and I departed from it without
noticing.

**Steam is a transport, not a menu item.** "Play on Steam" was a category
invented to hold the Steam code, not something a player wants to do. A player
wants to make a game or find one. Which transport carries it is a detail of
*how*, so it is a button on Create Game, and the list of games to join does
not care at all.

**Settings are read once and used three ways.** `chosen_settings()` serves all
three buttons, so they cannot drift apart. The failure mode this replaces was
exactly a second path with its own idea of the settings.

**What it rules out.** Changing the settings after a game exists. A lobby is
created from settings, so by the time anyone is in it they are fixed; to
change them, leave and make another. If in-lobby editing is ever wanted it is
a real feature — host-only controls plus a push to every client — not a
tweak to this.

**Also fixed by the same change.** Hosting and joining locally are now plain
options rather than the only visible way to play, and `src/ui/screens/
steam_browser/` became `online_games/`, because a folder named after the
transport is the same mistake in the file tree.

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
**2026-11-15 · Superseded by D65 the same day**

> Kept for the reasoning about what was broken, which is still accurate. The fix was not: it carried the settings to a screen that should not have been creating games at all. See D65.

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

**Amended 2026-11-16: it is now started at launch, and still is not an
autoload.** Initialising Steam takes long enough to see, and it was happening
on the click that opens the lobby list, so Join Game visibly stalled the first
time it was opened in a session. Reported from play. `Main.warm_up_steam()`
does it in `_ready` instead, where the pause hides inside the time the window
takes to appear, and skips it entirely under the headless display server so the
suite still never touches Steam. The paragraph above ruled out one line more
than it had to: not being an autoload is what keeps Steam out of the tests, not
being started late.

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

**It also makes accepting an invite untestable until the port is uploaded.**
Found on 2026-11-15, when invites were first tried. Steam's "Join game" and
`+connect_lobby` launch **the build Steam has installed for 1821800**, which
is the published Unity original — so an invite accepted on a development
machine starts the old game, whatever is running locally. *Sending* an invite
works and was confirmed; accepting one cannot be tried until the port is what
that App ID installs, which means a Steam branch upload. Nothing can be done
in code about this. A new App ID would not have had this problem, which is a
cost of this decision nobody foresaw when it was taken.

**Achievements are the opposite case**, and the difference is worth knowing.
They do not go through Steam's launcher: a locally run build that initialises
as 1821800 *is* that app as far as the API is concerned, so `setAchievement`
would unlock on the real account, for the published game, permanently. That
makes them testable here and unpleasant to test here. See D70.

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

---

### D76 — Pixel-perfect rendering is a hard requirement
**2026-11-16 · Accepted**

**The game's art and UI must be pixel-perfect.** This is a requirement of the
product, stated by the owner, not a consequence of any other choice. It outranks
filling the screen, matching a monitor's native resolution, and convenience.

It had never been written down. Before this entry the phrase appeared nowhere in
`docs/`; D40 chose a reference resolution and integer scaling, and
`ui-reference.md` noted as an aside that "the art is never resampled" — a
description of what D40 happened to produce, not a constraint anybody had to
respect. An audit on 2026-11-16 found the gap.

**What it forbids.**

- Any rendering path that resamples the game image unevenly — a nearest-neighbour
  upscale at a non-integer factor, where one source pixel becomes two columns and
  the next becomes three.
- Fonts with antialiasing, hinting or subpixel positioning on; texture filtering
  other than nearest. These are already set correctly in `project.godot` and must
  stay that way.

**Struck on 2026-11-16: this entry also forbade `stretch/mode = canvas_items`,
and that was wrong.** The reasoning given was that it draws each element at the
window's true resolution rather than upscaling a 640×360 image. That is true,
and it is the thing that *delivers* this requirement rather than breaking it —
there is no resampling step to come out uneven. See D83.

**The constraint, restated correctly.** What cannot be made even at a fractional
multiple is an **upscale of the game image**: at 2.5×, one source pixel has to
cover two output pixels and then three, and no engine escapes that. That is a
reason not to upscale the image, not a reason to shorten the resolution list.
Drawing at native resolution has no such limit and works at any multiple, whole
or not. **Shortening the resolution list is not an acceptable answer to this**
— that was proposed during the audit and rejected by the owner.

**What it rules out.** Treating "looks fine" as sufficient. If a change makes the
game image non-uniform at any offered resolution, the change is wrong.

---

### D77 — A resolution dropdown, populated from the system
**2026-11-16 · Accepted · supersedes part of D40**

The settings screen offers a resolution dropdown listing **the resolutions the
system supports**, as the original did. Restores audit §17.3.

**Why, when the window was resizable.** The original had this and the port
dropped it. "Resize the window instead" was the port's implicit answer, and D78
removes that answer entirely, so the dropdown is now the only way a player
chooses a size.

**What the dropdown actually sets: the window's size.** Decided 2026-11-16. The
game never changes the monitor's video mode — the window is fixed (D78) and
fullscreen is borderless at the desktop mode — so the list is of window sizes
that fit the current monitor, read from
`DisplayServer.screen_get_usable_rect()`.

**No GDExtension.** An earlier version of this entry called the real mode list a
blocker: Godot's `DisplayServer` genuinely cannot enumerate display modes (no
equivalent of Unity's `Screen.resolutions`), so reading them would mean
`EnumDisplaySettings` through a native extension on Windows and a platform
equivalent elsewhere. That cost buys nothing here, because only exclusive
fullscreen needs a mode list and this game does not use it. Owner's decision,
2026-11-16.

**Which stretch mode ships** is settled by D83: `canvas_items` with
`aspect = keep`. Every offered size draws at native resolution, so no size on
the list has to be dropped for scaling reasons.

**What it rules out.** Hardcoding a list of resolutions. Shortening the list to
those that happen to scale exactly. A native extension for display enumeration.

---

### D78 — The window is fixed, not resizable
**2026-11-16 · Accepted · supersedes part of D40**

`window/size/resizable = false`, as the original had it
(`resizableWindow: 0` in its Unity player settings).

**This was never previously decided.** The port's window resized because `true`
is Godot's default and nothing set it. An earlier version of `ui-reference.md`
listed resizability under "where the port deliberately differs", which was wrong:
no decision existed.

**The reason is a reported bug, not a preference.** Dragging a window by its
title bar in Windows means passing close to the resize handle. Catch it, shrink
the window one pixel below a whole multiple of 640×360, and integer scaling has
no choice but to drop a whole step — ×3 becomes ×2 — so the game abruptly renders
at two thirds the size inside a large border. A one-pixel slip produces a
drastic, visible jump. The owner hit this in play.

That interaction is inherent to integer-scaling a resizable window: there is no
setting that makes the step smaller, because the steps *are* whole numbers.
Removing the drag removes the trigger, which is why this is the fix and not a
workaround.

**What it rules out.** Relying on window resizing as the way a player picks a
size — hence D77. Fullscreen is unaffected: a fixed window can still go
fullscreen, since `resizable` only governs dragging the frame.

---

### D79 — The host sets the player limit
**2026-11-16 · Accepted**

The Create Game screen carries a **1–10 player limit**, applied as the Steam
lobby's member limit, as the original did. Restores audit §17.4.

The port created every lobby with ten slots, so a host who wanted a three-player
game could not stop a fourth joining. `GameSettings.player_count` already exists
and is hardcoded to 1 at both call sites.

**What it rules out.** A fixed ten-slot lobby, and deciding the cap anywhere but
the host's own screen.

---

### D80 — The lobby browser row shows years, loans and starting cash
**2026-11-16 · Accepted**

A row in the online games browser shows the game's name, players, **year limit,
whether loans are enabled, and starting cash**. Restores audit §17.5 and goes one
field further than the original.

The original published years and loans as Steam lobby metadata for exactly this
purpose, and the port publishes neither. Starting cash the original never
published at all, so a joiner could not tell a 10,000 game from a 150 one until
they were already in the lobby. All three change how a game plays, so all three
are visible before committing.

**What it rules out.** Choosing a game on its name and player count alone.

---

### D81 — The result screen can stand aside to show the final board
**2026-11-16 · Accepted**

The result screen gains a control that hides it to reveal the finished board —
prices, holdings and rankings as they ended — and a way back. Restores audit
§17.9.

The original did this with an X on the winner panel and a second Quit button
underneath. The port replaced the panel with a dedicated screen carrying final
standings and a year-by-year history, which is more information but not the board
itself. The history does not substitute for it.

**What it rules out.** Treating the history view as a complete replacement for
inspecting the final state.

---

### D82 — The supporter message is gated on Steam DLC ownership
**2026-11-16 · Accepted**

The title screen shows **"Thanks for Supporting the Devs!"** when the player owns
the supporter DLC. Restores audit §17.8 and §3.7.

The original checked for a file named `support-dlc.txt` sitting next to the
executable. That was a stand-in; ownership is the real test, and GodotSteam
exposes it directly as `Steam.isDlcInstalled(dlc_app_id)`. The DLC's own App ID
is read off the Steam partner backend, the same place the achievement names came
from.

**What it rules out.** The file check, and any mechanism a player can satisfy by
creating a file.

---

### D83 — Render at native resolution, in a fixed window
**2026-11-16 · Partly superseded by D85 · supersedes the scaling half of D40 and D77**

**The stretch settings below were replaced the same day by D85**, which
makes the chosen resolution the size of the rendered image rather than
the size of the window. What stands here is the fixed window, the bars
rather than extra content, and that D76 was never superseded.

**D76 stands. Pixel-perfect rendering is still a hard requirement**, and this
entry does not relax it. An earlier version of D83 claimed to supersede D76 on
the grounds that the game would never have pixel art; that claim was wrong and
was removed on 2026-11-16 at the owner's instruction. Nothing below depends on
it.

Display settings as this entry left them, since replaced by D85:

```
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/size/resizable=false
```

`scale_mode` is gone; it only applies to `viewport` stretching.

**Why `canvas_items`.** It lays the UI out in 640×360 coordinates but renders
every glyph and panel at the window's **real** resolution. Text is therefore
sharp at 1080p, 1440p, 4K and everything between, instead of being a 640×360
image enlarged.

This is how pixel-perfect survives an uneven multiple. The uneven-multiple
problem belongs to *upscaling an image* — at 2.5×, one source pixel has to
cover two output pixels and then three. Nothing is upscaled here: every glyph
and every panel edge is drawn straight onto real screen pixels at whatever size
the window implies, so there is no resampling to be uneven. D76's claim that
`canvas_items` is forbidden for this project was written about the image path
and does not apply to drawing at native resolution.

**Why `aspect = keep`.** The owner's requirement: *the same information on every
resolution.* `keep` preserves the 640×360 coordinate space and fills any aspect
mismatch with bars, so a 16:10 Steam Deck and a 16:9 monitor show identical
content. `expand` would grow the coordinate space and reveal extra rows on taller
or wider displays, which is explicitly unwanted. Bars are acceptable; varying
content is not.

**Why `resizable = false`.** See D78. It also stops mattering less: without
integer scaling there is no scale-step jump, but a fixed window remains what the
original had and what the owner wants.

**Supersedes the scaling half of D40.** D40's reference resolution of 640×360,
its character grid and Terminus remain in force — they are what make the layout
tractable, and that reasoning is untouched. What is superseded is
`stretch/mode = viewport` and `scale_mode = integer`.

**Ultrawide needs no special handling.** `keep` pillarboxes it by the same rule
as everything else. Nothing to test, which is what the owner asked for.

**Font settings are unchanged and stay that way.** `project.godot` sets font
antialiasing, hinting and subpixel positioning off, and 2D pixel snapping on.
D76 requires all four. Drawing at native resolution does not change that: a
glyph rasterised with antialiasing off is still a glyph made of whole pixels,
which is the point.

**What it rules out.** Upscaling the game image by any factor, integer or not.
The old argument about integer multipliers and black-bar arithmetic is gone
because nothing is scaled, not because the requirement behind it went away.

---

### D84 — A fullscreen toggle, borderless, with bars where the monitor is not 16:9
**2026-11-16 · Accepted**

The settings screen gets a fullscreen toggle, as the original had (audit §17.3).
It uses Godot's **borderless** fullscreen at the desktop resolution, never
exclusive fullscreen.

**Why borderless.** Exclusive fullscreen is the only mode that would need the
monitor's list of video modes, which Godot cannot supply without a native
extension (D77). Borderless needs none of that: it takes the desktop resolution
as it finds it, alt-tabs cleanly, and is what a UI-only game wants.

**Bars, not more content.** `aspect = keep` (D83) holds the 640×360 coordinate
space, so a 16:10 laptop or an ultrawide gets letterbox or pillarbox rather than
extra rows. That is the owner's standing requirement — the same information on
every display — and fullscreen is not an exception to it.

**What it rules out.** Exclusive fullscreen. Any fullscreen path that changes
how much of the game is visible.

---

### D85 — The dropdown picks the render resolution, and that image is stretched
**2026-11-16 · Accepted · supersedes the stretch settings in D83**

The settings screen offers a resolution dropdown and a fullscreen toggle. The
resolution a player picks is **the size of the image the game is drawn into**,
and that image is then stretched to fill the window or the screen.

```
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="fractional"
window/size/resizable=false
```

**Two of those four are not in `project.godot`.** `aspect = "keep"` and
`scale_mode = "fractional"` are Godot's own defaults, and the engine omits any
setting left at its default when it rewrites the file — which it does whenever
the project is opened or run. They are listed here because they are part of the
decision; do not re-add them to the file expecting them to stay. Same class of
thing as the comments Godot strips (D72).

**This entry describes an intent the build does not achieve.** Corrected
2026-11-16 after it was played. `DisplayMode` sets `content_scale_size` to the
chosen resolution and `content_scale_factor` to that resolution divided by 640,
in the belief that the first sets the image size and the second keeps the
layout on the 640×360 grid. They cancel: in Godot's `viewport` stretch mode the
render target is `content_scale_size ÷ content_scale_factor`, so the game always
renders at 640×360 whatever is picked.

**What that means in practice.** In fullscreen the dropdown changes nothing at
all. In a window it appears to work, but only because the window itself is
resized — the image inside is still 640×360 stretched to fit.

**Why it was not then fixed.** Godot's built-in stretch has one knob: the
logical layout size *is* the render size. "Lay out on 640×360, render at
2560×1440" needs a `SubViewport` at the chosen size displayed by a `TextureRect`
filling the window, with the filter set explicitly. The owner chose on
2026-11-16 to leave the built-in behaviour in place rather than have that
rebuilt here. **Anyone picking this up should start from that paragraph, not
from the three steps below**, which describe the intended design rather than the
shipped one.

**Three steps, and the whole of every scaling argument on this project has been
about the difference between them:**

1. The interface lays out on the 640×360 grid. Never changes. Every player sees
   the same rows and columns at every resolution.
2. That layout is drawn into an image of the chosen resolution.
3. The image is stretched to fill the screen, shape preserved, black bars in
   any leftover space.

**Why this and not `canvas_items`.** `canvas_items` has no step 2 — it draws
straight onto the screen at whatever size the window is, so a resolution
setting has nothing to control and would do nothing in fullscreen. The owner
asked for the resolution to be the render size, explicitly and more than once,
including the case of 720p stretched over a 1080p display and 720p with bars on
a 1920×1200 one. That requires a real image of that size. D83 chose
`canvas_items` before that requirement was stated.

**What this means for D76.** At the default — the monitor's own largest 16:9
size, fullscreen — step 3 is a one-to-one copy and nothing is resampled at all.
Pixel-perfect, with no caveat. A player who deliberately chooses a smaller
render resolution has opted into a stretch, and at a fractional one (720p on a
1080p screen is 1.5×) the pixels of that image cannot all be the same size on
screen. That is the ordinary cost of a lower render resolution in any game, it
is the player's choice to pay it, and it is not a reason to shorten the list.
**The resolution dropdown is greyed out in fullscreen** (added 2026-11-16).
It does nothing there, and a live control that does nothing invites a player to
pick a size, watch the screen not change, and conclude the game is broken. The
greying is a true statement about what the setting currently does, so **it
should be removed the day the resolution works in fullscreen and not before.**

**The filter on that stretch has never been established.**
`rendering/textures/canvas_textures/default_texture_filter=0` is set, and this
entry originally claimed it governs the final blit. That was an assumption, not
a finding, and Godot 4.7.2 exposes no setting for the blit filter. A non-integer
stretch should be filtered linearly; whether it currently is, nobody has looked.

**Only exact 16:9 sizes are offered**, from a fixed ladder capped at what the
monitor can show: 640×360, 960×540, 1280×720, 1600×900, 1920×1080, 2560×1440,
3840×2160. Not 854×480, which is the usual approximation and is 16:9.0075 — one
near-miss in the list gives one resolution whose bars are a different size from
everybody else's.

**First run is the monitor's own size, fullscreen.** As every other game does.
A player who launches into a small window in the corner of a large screen
assumes something is broken. Stored as a zero in `settings.cfg`, meaning "ask
the monitor", so moving the file to another machine still does the right thing.

**A change is applied, then asked about, and undone if nobody answers.** The
question is whether the monitor can show it, and the only way to answer that is
to try it; a player reading "are you sure?" over an unchanged screen has nothing
to go on. `ConfirmPanel.ask_with_countdown` reverts after fifteen seconds, so
doing nothing is the safe outcome when the screen has gone black.

**What it rules out.** A resolution setting that does nothing in fullscreen.
Shortening the list to sizes that happen to scale exactly. Stretching the image
to a monitor's own shape when that is not 16:9.

---

### D86 — The title screen is four things across the top, in one fixed panel
**2026-11-16 · Accepted · replaces the shape chosen in D65**

The tab bar reads **SINGLE PLAYER · HOST ONLINE · JOIN GAME · SETTINGS**, and
every one of them draws into a card of one fixed size.

**Why the panel size is fixed.** It was not, and each tab sized the card to its
own contents, so the heading, the tab bar and the quit button all jumped as you
clicked between them. Reported from play. `test_title_screen_shape.gd` asserts
the card size and the position of the title and the quit button are the same on
every tab, because this is the kind of thing that comes back the next time
somebody adds a field.

**Why Single Player and Host Online are two buttons.** D65 put both behind one
**Create Game** tab with the kind of game chosen underneath. "What do you want
to do" is the question a title screen exists to ask, and half the answer was a
level down. They are still **one panel**: years, starting cash, loans and seed
are settings of the *match* and identical either way, so there is one set of
controls and `_show_fields_for` hides what does not apply.

- Single player hides the game name, the player limit and the privacy toggle,
  and shows the name field.
- Host Online does the reverse: an online game is named from the Steam account
  (D66), so a name field there would silently do nothing.

**Single player forces `player_count = 1` and `invite_only = false`** rather
than reading hidden controls, so whatever the online fields were left holding
cannot leak into a solo match.

**Join Game loads the list when it is opened**, rather than showing a BROWSE
ONLINE GAMES button whose only job was to ask for the thing the player had just
asked for. The browser moved from a screen of its own to a widget inside the
panel (`lobby_browser.gd`) and gained a search box. It asks for the list once
per visit to the title screen; REFRESH is how a player asks again.

**The direct-connection form is gone from the title screen.** Hosting and
joining by address and port is a development tool: it means nothing to somebody
who bought the game on Steam, and it was taking up a third of the Join panel.
It is now `dev_overlay.gd`, a small panel pinned to the top-left corner that
`Main` adds only when `OS.is_debug_build()` — false in anything the
`Windows Release` preset produces. The shape is borrowed from the
network-manager overlays Unity networking libraries ship for the same job.

**Layout corrections from the first look at it running**, all reported the same
day and all now asserted in `test_title_screen_shape.gd`:

- **START and HOST ONLINE are narrow and over to the right**, not the width of
  the panel. A full-width action button directly above a full-width QUIT TO
  DESKTOP is an accidental click waiting to happen.
- **QUIT TO DESKTOP is detached from the panel**, in a row of its own with a
  gap above it, narrow, and over to the left — the opposite corner from the
  button that starts a game.
- **The lobby search box is below the list**, not above it.
- **`ConfirmPanel` carries the theme on its own scene root.** `SettingsPanel`
  parents the revert prompt to the window so it can dim the whole screen, which
  put it outside the themed tree and drew it in Godot's default font. A
  confirmation must not depend on who happens to be its parent.
- **F1 hides the development overlay**, which sits exactly where the heading is.
- **The development overlay lives on a `CanvasLayer` of its own, layer 128, and
  only on the title screen.** The first version was an ordinary child of `Main`
  and could not be used at all: `Main` is a `MarginContainer`, so it stretched
  the panel to fill the screen instead of honouring its offsets, and every
  screen swap added the new screen *after* it, so the screen drew on top and
  took the clicks. A `CanvasLayer` is not a `Control`, so no container lays it
  out, and a high layer number draws above everything whatever the child order.
  This is the same arrangement as the separate canvas such overlays get in
  Unity, which is where the shape came from.

  **It cannot be a fixed number of screen pixels**, unlike the Unity one. The
  whole game renders into a 640x360 image which is then scaled to the window
  (D85), so nothing drawn can escape that scaling — a canvas layer included.
  It is small in game pixels instead.

**What it rules out.** A tab that resizes the panel. A second copy of the match
settings for a second kind of game. A button that loads a list the player has
already asked to see. Direct-connection controls in a shipped build.

---

### D87 — The host chooses the player limit, and the data default is ten
**2026-11-16 · Accepted**

The original's `Max. Number of Players` field is restored: 1 to 10, default 4,
on the Host Online panel (audit 17.4). It sets the Steam lobby's member limit at
creation, exactly as the original did, and `HostSession.seat_count()` enforces
the same number for a direct connection, where Steam is not there to turn
anybody away.

**`GameSettings.player_count` defaults to 10, not to 4.** The form's default is
4, which is what a player sees; the *data* default is the maximum, because
anything that builds settings without going through the form — a test, a launch
flag, a single-player match — means "do not get in my way". It was 1, which was
harmless only while nothing read it: the moment `seat_count()` did, 79 tests
failed because every host session would seat one player and refuse the rest.

**What it rules out.** Creating every lobby with ten slots. Trusting a number
that came from a screen without clamping it.

---

### D88 — A browser row says what kind of match it is
**2026-11-16 · Accepted**

A row in the lobby browser carries the game's name and `n/max`, and underneath
them the year limit, the starting cash and whether loans are on. The three are
written into Steam lobby data when the lobby is created.

**The original did this**, with `NumberOfYears` and `LoansEnabled` lobby keys
written for no other purpose than the browser row (audit 17.5). The port had
dropped both.

**Starting cash is published although the original never published it.** Its
absence left a joiner unable to tell a 10,000 game from a 150 one until they
were already in the lobby — and the lobby shows no settings either, so the
first they would know of it is the opening board. It changes how a game plays
and it belongs on the row.

**A lobby that did not publish something has that part left out.** Steam lobby
data is strings, read back with `to_int()`, which answers 0 for an absent or
unparseable value — which is exactly what a lobby from an older build looks
like. The row omits whatever came back empty. Guessing a default would put a
number on screen that nothing stands behind, and "25 years" written under a
game that is actually ten is worse than nothing written at all.

**`create_lobby` takes the settings as an optional argument**, and publishes
nothing when it is not given one. The alternative was a second call for the
host to remember to make.

**What it rules out.** Filling a gap in lobby data with a default. A joiner
having to enter a lobby to find out what the match is.

---

### D89 — The original's starting-cash bounds, restored
**2026-11-16 · Accepted**

Starting cash is **150 to 69,420**, as the original's create-game form had it
(`wealth > 149 && wealth < 69421`). 150 and 69,420 are both legal, 69,421 is
not, and 69,420 is a joke that was the ceiling on purpose.

**What it replaces.** The port's field was 100 to 1,000,000. Nobody chose those
either: they were a guess made while building the form, at a time when nothing
in `docs/` recorded what the original allowed — `game-rules.md` had the range
as an em dash until the 2026-11-16 audit read it out of the source. The audit
marked the field **Ported**, which was generous.

**The bounds live on `GameSettings`**, as `MIN_STARTING_CASH` and
`MAX_STARTING_CASH`, with `@export_range` on the property. The title screen's
spin box uses them and `chosen_settings()` clamps again. Belt and braces on
purpose: a match can be built without going through the form — a launch flag, a
test, a lobby setting somebody adds later — and the bounds are a rule of the
game, not a property of one control.

**This is a port decision, not a design one.** If the ceiling ever wants
raising, that is a change to the game and belongs in its own entry.

**What it rules out.** Bounds that live only on a `SpinBox`. Starting a match
outside the original's range by any route.

---

### D90 - The finished board is rebuilt, not uncovered
**2026-11-16 - Accepted - implements D81**

**View board** on the result screen shows the board as the match ended;
the bottom bar's button, which otherwise reads "Game Over" and does nothing,
becomes **BACK TO RESULTS**.

**Why rebuilt.** The original's winner panel sat *over* the board, so dismissing
it revealed what was already there. The port's result screen replaced the board,
and it earns that: it carries final standings and a year-by-year history the
original never kept (D73). Making it an overlay instead would mean giving up the
screen it has become. So the board is built again from the finished state.

**What makes that honest.** `Main` owns the session, not the playing screen, and
always has - the result screen reads the same state. Rebuilding the board from it
shows the match as it ended rather than a new one, which a test asserts by
comparing the session identity and the year.

**Nothing is switched off for it.** Trading is already refused once the year
counter passes the limit, and the loan panels hide themselves at game over, so a
finished board is inert on its own. The only change is the one button.

**Why that button rather than a new one.** The bottom bar already had a control
sitting there saying "Game Over" at the player, and the original used that same
space for the second Quit Game button it added when the panel was dismissed. A
second button would be a second thing to lay out for no gain.

**What it rules out.** A result screen that is an overlay. Disabling controls on
the finished board that the rules already refuse.

---

### D91 - The supporter message asks Steam, and the DLC has its own App ID
**2026-11-16 - Accepted**

**Thanks for Supporting the Devs!** shows on the title screen when
`Steam.isDLCInstalled(1856290)` says this player owns the supporter DLC.

**1856290 is the DLC, 1821800 is the game.** Steam issues a separate App ID per
DLC and owning the game says nothing about owning this one. The owner supplied
the number on 2026-11-16, after first giving the game's by mistake, which is
exactly the confusion worth recording.

**Not a file check.** The original showed the label if a file called
`support-dlc.txt` sat next to the executable - a stand-in anybody could satisfy
by making a file. Ownership is the real test.

**`isDLCInstalled`, not `isDlcInstalled`.** GodotSteam capitalises the acronym,
and the wrong spelling is a **parse** error rather than a runtime one, so it
takes the whole script down and 86 tests with it. The correct name was read out
of the plugin binary rather than guessed; do the same for any other Steam call
whose casing is not obvious.

**False whenever Steam is not running**, which is every offline game and every
test run. A thank-you that appeared because the question could not be asked
would be worse than no thank-you.

**The title screen is told, not asked.** `Main` owns Steam and passes the answer
in, because the title screen has to come up identically with Steam closed and a
screen that reaches for Steam on its own cannot promise that.

**What it rules out.** A file, or anything else a player can satisfy themselves.
Using the game's App ID for a DLC question.

---

### D92 - A player carries a Steam id, beside their display name
**2026-11-16 - Accepted**

`PlayerState.steam_id` holds the Steam account a player is playing as, or 0 for
anybody not playing through Steam. It exists so the lobby can show a portrait
(audit 17.7), and nothing else reads it.

**Why it is allowed in the simulation layer.** It looks like transport-specific
data in a place that forbids it. It is the same kind of thing as
`display_name`, which has always lived there and is equally transport-shaped -
an online game reads the name from Steam, a local one from a text field. Both
are *identity for display*. The rule that matters is that no game rule may
branch on either, and none does: `src/sim` never reads `steam_id`.

**Why not keep it out and map it in the lobby screen.** Two routes were
possible. The host could ask the Steam peer for each connection's account, but
only when the transport happens to be Steam, which puts a transport check in
`HostSession`; and a *client* has no such mapping at all, so no client could
draw anybody's portrait but its own. Matching by persona name instead breaks on
two players with the same name. Carrying it with the player is the only one of
the three that works for everybody in the lobby.

**The client states its own.** It travels with the introduction, defaulting to
0, so a direct connection needs no special case. A client could lie; the worst
that buys is somebody else's face beside their name, which is not worth
validating.

**Not redacted.** Every account in a Steam lobby is already visible to everyone
in it through Steam itself, so hiding it from the snapshot would protect nothing
and would stop the portraits working.

**Portraits are cached by the lobby screen**, because the player list is rebuilt
from scratch whenever anything changes - somebody readying up throws away every
row - and asking Steam again each time would be a request per player per event.
An arriving portrait is offered to every row and each decides whether it is
theirs, which is cheaper than tracking requests for a list of at most ten.

**What it rules out.** A rule that reads `steam_id`. A transport check inside
`HostSession`. Matching players to accounts by name.

---

### D93 - A studio splash, skippable, and not pixel-perfect
**2026-11-16 - Accepted**

The game opens on the Glacial Lake Studios logo: it fades in, holds, and fades
out, **four and a half seconds** end to end - 1.4 in, 2.0 held, 1.1 out.
**Nothing moves.** It sits at an exact **2x** - 512x288 of the 256x144
original - centred on a black screen.

It ran for two and a half seconds at first, with a 0.7 fade in, which read as
the logo being flashed at you rather than presented. The opening fade is now
the slowest part of it, at the owner's asking.

**The slow push towards the viewer was built first, and dropped after looking
at it.** It is the shape an engine's own logo splash usually takes and it is
what the owner asked for, but scaling pixel art by a fraction that changes
every frame makes its pixels crawl, and at this size the crawling was the only
thing you could see. Reported from play the same day it was built.

**Standing still buys back pixel-perfection.** A fixed logo can sit at a whole
multiple, so every source pixel is a clean square of four and nothing is
resampled at all. The linear-filtering exception the moving version needed is
gone with it, and D76 governs the splash like everything else.

**Skippable by anything** - a key, a mouse button, a controller face button.
A splash that cannot be skipped is a tax on everybody who launches the game
more than once, and during development that is many times a day. A key
*release* does not count, so letting go of whatever launched the game cannot
skip it before a frame of it has been seen.

**Not shown when the game was launched into something.** An accepted Steam
invite is a player asking for one particular lobby, and `--host` / `--join` are
the development flags that put two windows up in a hurry. Neither wants a logo
in front of it. Nor does a headless run, which is the whole test suite.

**The source art is the 256x144 original**, not the 1792x1008 version of it,
which is the same image at seven times the size. Scaling the small one up is
what makes the movement smooth; scaling the big one down would throw away most
of what was in it.

**What it rules out.** An unskippable splash. Making a development launch wait
for it. Animating pixel art by a fraction - which is what this entry exists to
record, because it was tried here and looked wrong.

### D94 - A CRT effect, optional and off by default, drawn over the whole game

**Decision.** The game can be drawn through a CRT shader: barrel-warped,
scanlined, with colour bleeding rightwards and bright areas glowing. It is a
tick box in Settings, it is off until a player turns it on, and it is kept
between sessions like the volume and the resolution.

It is one `CanvasLayer` (`src/ui/widgets/crt_overlay.tscn`) holding one
`ColorRect` that fills the screen and carries `src/ui/crt_screen.gdshader`.
The shader reads the picture already drawn underneath it through
`hint_screen_texture` and replaces it. Nothing else in the game knows it
exists.

**It is ported from a Unity URP shader** used on another of the owner's
projects (`RetroCRT/CRT Screen`). The physics transferred almost line for
line - the gamma handling, the one-sided exponential bleed kernel, the
bright-pass glow, the normalised sin-squared scanline weight, the barrel warp
where each axis is bent by the other's distance from the centre. What follows
is only what had to change.

**No phosphor mask, and this is the one real loss.** The original anchors its
R/G/B triad to output pixels, deliberately, because a real shadow mask sits on
the glass and does not move with the picture. This game renders at 640x360 and
Godot stretches that to the window afterwards (`window/stretch/mode="viewport"`
in `project.godot`), so a fragment shader here is shaded in 640x360 space and
`FRAGCOORD` counts game pixels, not monitor pixels. A three-pixel triad would
come out three *game* pixels wide and then be stretched two or four times
larger: coloured stripes across the picture, not a mask. Left out rather than
left in badly.

Getting it would mean rendering the game into a `SubViewport` and displaying
that through a `TextureRect` at window size, with the project's stretch mode
off - which moves fixed-size-and-letterbox out of Godot's own stretch system
and into this project's code, taking input routing, mouse coordinates,
`DisplayMode` and every scene test with it. That is a bigger change than the
effect is worth on its own. It is worth knowing that the same restructure is
what D85's unfinished business needs: it would put the final blit filter under
our control and make the resolution dropdown mean something in fullscreen.
If those are ever done, they should be done together.

**Three rows per scanline, not two, and this was measured.** The original
clamps the line count to half the rows, reasoning that a line needs one dark
row and one light row. That is right about the pixels and wrong about where
they are sampled. A fragment is shaded at the centre of its row, so at exactly
two rows per line the samples land on phases 0.25 and 0.75 of the sine, and
sin squared is equal at both - every row comes out at exactly the mean and the
pattern is invisible. The first build had 180 lines over 360 rows and rendered
a picture identical, row for row, to the one with the effect switched off. At
three rows per line the phases are a sixth, a half and five sixths, which are
not equal, and the comb appears. 120 lines over 360 rows.

This was found by rendering the title screen twice, with the effect on and
off, and comparing the two images pixel by pixel - not by looking, because at
that strength the difference between "working" and "doing nothing at all" is
not something an eye can be sure about on a dark screen.

**The distances are in game pixels.** Every default the original expressed in
output pixels - vignette width, bleed falloff, glow radius - is divided by
roughly the window scale, because this shader's pixels are the game's, not the
monitor's.

**It sits above the game and below the development overlay.** Everything the
game draws is on layer 0, including the pause menu and the confirmation panels
parented to the window, so one layer above that covers all of it. The
development overlay stays above at 128 on purpose: debugging text read through
a barrel warp and a scanline comb is worse debugging text, and it is not part
of what a player sees.

**Off by default.** It is a taste, not an improvement. It warps the picture,
softens the text and costs a little every frame, and a player who has never
heard of it should see the game as it was drawn.

**No revert countdown, unlike the resolution.** The countdown exists because a
resolution a monitor cannot show leaves a player looking at nothing with no
way back. This cannot do that: the picture is still there underneath, the tick
box is still on screen and readable through the effect, and turning it off is
the same click again.

**The one surface in the game sampled linearly.** The warp moves pixels by
fractions of a pixel and the whole job of the shader is to stop the picture
looking like a grid; nearest sampling puts stair-steps along the curve. D76
still governs everything else, and when the effect is off nothing samples
anything.

**Tuning lives in the shader file.** The scene sets no shader parameters at
all, so the `uniform` defaults are the only statement of how the effect looks
and a change to it shows up in a diff.

**What it rules out.** A phosphor mask, until the `SubViewport` restructure
happens. Any other code knowing about the effect - it is reached through a
group, not a signal chain, so neither the title screen nor the pause menu has
to carry it. And a full-screen overlay that takes mouse input: the glass is
`MOUSE_FILTER_IGNORE` and a test holds it there, because a rect in front of
the whole game that swallows clicks would swallow the one that turns it off.

**Softened on 2026-11-17, after the effect was played with.** Reported as
"a little harder to read, which is expected to a certain extent", with a
question about whether a brightness control would help. It would not, and
measuring said why.

The effect was not darkening anything: **99.4%** of the picture's light
survived it, and 100.2% in the middle half where the vignette has no say.
Block contrast was at 97.7%. Both of the obvious measurements said nothing was
wrong. What had fallen was **horizontal stroke definition - 87.9%** - measured
as the mean absolute difference between neighbouring pixels, which is almost
the definition of a stroke one pixel wide. This game's text has strokes one and
two pixels wide, so that is the number readability lives on.

Knocking out one component at a time, against the same effect-off render:

| Variant | Detail across | Detail down |
|---|---|---|
| As built | 87.9% | 128.8% |
| No glow | 87.2% | 128.2% |
| **No bleed** | **92.9%** | 129.4% |
| No scanlines | 87.9% | 94.6% |

So of the twelve points lost, five were the colour bleed and the rest was the
warp's own resampling, which cannot be given back without giving up the warp.
The glow costs nothing horizontally. The scanlines cost nothing horizontally
either, but add 29% more vertical edge energy, which is the comb cutting across
letters eight rows tall.

`bleed_amount` went 0.55 to 0.30 and `scanline_strength` 0.30 to 0.22. Measured
after: detail across **90.0%**, detail down **118.0%**, block contrast 99.0%,
brightness unchanged. It still reads as a CRT.

**A brightness control was considered and not built.** It works mechanically -
it is a multiply, and a game being nothing but UI does not change that - but
brightness was never what was lost, so it would raise the text and the
background together and wash the picture out while leaving legibility exactly
where it was. A "CRT strength" slider scaling the three knobs together is the
control to add if taste still varies; a slider whose job is to undo an untuned
default is the wrong shape.

**How to look at it.** `tools/crt_shot.gd` renders the title screen with the
effect on and writes a PNG; the command is in the file. No test can judge the
picture, and a shader that will not compile passes every test in this
repository, so this is how it is checked. `tools/crt_compare.gd` is the
other half: it differences two renders and prints the figures above. See
testing.md for what each one answers.

### D94a - What the SubViewport option was measured to cost

An appendix to D94 rather than a decision: **nothing has been decided and
nothing has been built.** This is what was measured on 2026-11-17 so that
whoever picks it up does not have to find it again, and so that the reasons it
looked expensive are not quoted back as fact when two of the three turned out
to be wrong.

**The fault that prompted it.** Reported from play: some rows of text in the
stalk list are noticeably blurrier than the rows right next to them. Measured
by rendering the board twice, effect on and off, and comparing stroke
definition one row at a time:

| Variant | Best-to-worst spread across text rows |
|---|---|
| As shipped | 41.6% to 100.3% - 58.7 points |
| Scanlines off | 41.6% to 100.3% - 58.7 points, identical |
| Warp off | 80.6% to 102.6% - 22.0 points |

**The barrel warp is the whole of it and the scanlines contribute nothing.** A
barrel bends each axis by the other axis's distance from the centre, so every
row gets its own fractional shift. A row displaced by a whole pixel stays
sharp; a row displaced by half a pixel is blended with its neighbour by the
linear filter. Sharpness also peaks in the middle of the screen, where the
displacement is zero.

**This is the one thing the 640x360 shader genuinely cannot fix.** A stroke in
this game is one pixel wide, so a half-pixel error halves it. Flattening the
curve trades the two off smoothly and never removes the variation - at
curvature 30, flat enough to barely read as a curve, the spread is still 34
points. Snapping the sampled pixel to a whole pixel gives 96.6% definition but
stair-steps, and at roughly 1.5 pixels of total displacement the curve nearly
disappears anyway. **At this resolution you can have a visible curve or
uniformly sharp text, not both.** Run the warp at monitor resolution and the
same half-pixel error is half a *monitor* pixel - about an eighth of a game
pixel, invisible.

**Two of the three costs feared for the restructure are not real.** Both were
checked by running them rather than by reasoning, and the tools are kept:

- **Input routing is free.** `tools/subviewport_spike.gd`. A button inside a
  `SubViewport` shown at twice its size reported a click at its own middle in
  its own coordinates. Godot transforms through both spaces by itself. The
  project also has **no** direct pointer reads anywhere in `src/`, so there is
  nothing else to convert. The Unity notes that prompted this worry list nine
  such reads, but that is a Unity-shaped problem: its UI is camera-coupled.
- **Popups are one property.** `tools/popup_spike.gd`. With
  `gui_embed_subwindows = true` on the `SubViewport`, the resolution dropdown
  is at the same position and the same size as it is today, to the pixel.
  Without it the popup lives in the root viewport at the container's scale -
  which still lands beside its button, but is drawn outside the SubViewport, so
  at window resolution and outside any effect.
- **Tooltips: checked by hand and correct.** Confirmed by the owner in a real
  session over Steam on 2026-11-17, along with the dropdown and the finished
  board. The spike could not establish them - a synthetic hover produced none -
  so this one was always going to need eyes.

**No screen, widget, theme or layout file would change, and neither would the
simulation.** This is where Godot and the Unity experience diverge: that
project needed a sweep over twenty-seven canvases because its UI is bound to a
camera, while a Godot `Control` neither knows nor cares which viewport draws
it.

**The real cost is integer scaling.** `SubViewportContainer.stretch_shrink` is
a whole number, so only a window that is a whole multiple of 640x360 can
produce a 640x360 viewport. Today the game fills any 16:9 window by scaling
fractionally; that would become black bars on the sizes that do not divide.
Against the game's own ladder in `DisplaySettings.LADDER`:

| Resolution | Multiple | Result |
|---|---|---|
| 640x360 | 1x | exact |
| **960x540** | **1.5x** | shows 640x360, bars 160 / 90 |
| 1280x720 | 2x | exact |
| **1600x900** | **2.5x** | shows 1280x720, bars 160 / 90 |
| 1920x1080 | 3x | exact |
| 2560x1440 | 4x | exact |
| 3840x2160 | 6x | exact |

Five of the seven lose nothing. The two that do are precisely the two that
scale fractionally today, so what is lost in screen area is gained in square
pixels - and the ladder is ours, so dropping those two rungs would retire the
question. Outside the ladder, a 1366x768 laptop would show 1280x720.

The alternative is a plain `TextureRect`, which fills fractionally but gives up
the free input routing: then the coordinate transform really would have to be
written and maintained. **Integer scaling is what buys the free input.**

**What this appendix rules out:** repeating the claim that the restructure
needs hand-written input maths, or that it would mean reworking the UI. It
rules in one open question of taste - bars or fill. The one unchecked detail it
left, the tooltips, was confirmed correct by hand on 2026-11-17.

### D95 - Personal notes live in an uncommitted file beside CLAUDE.md

**Decision.** `CLAUDE.md` is committed and holds conventions of the codebase.
A `CLAUDE.local.md` sits beside it, is loaded with it, and is in `.gitignore`.
Anything about one machine or one person goes in the local file: where Godot is
installed, where the original Unity project sits, and working preferences that
would read as strange to a stranger who had just cloned the repository.

**Why.** This repository is meant to be published, and `CLAUDE.md` had grown
three kinds of content that do not belong in a public file: absolute paths
containing a Windows username, a statement of one person's experience level,
and instructions about how to talk to that person. None of it is a rule about
the code, and all of it would be noise - or worse, confusing - to anyone else
reading the repository.

**Why not simply delete it.** Those instructions are load-bearing. They were
each written after something went wrong, and the reasoning behind them is the
part that stops it going wrong again. Moving them keeps them working while
taking them out of the public file.

**Why not put all of `CLAUDE.md` in `.gitignore` instead.** That was considered
and rejected. `CLAUDE.md` carries the static typing rule, the naming
conventions, the rule that the simulation must not depend on the scene tree,
the money-is-always-an-int rule and the documentation gate. Removing it from
the repository would take all of that out of a public clone, which is directly
against the documentation bar this project holds itself to - a successor with
no access to anyone who worked on this has to be able to continue. It would
also stop the file being versioned and reviewable in a diff, which is how the
rest of this project's rules are kept honest.

**Why not a separate style guide document either.** The same content in two
places drifts, and D60 is this project's own record of exactly that happening.
`CLAUDE.md` is the file an assistant loads every session, so it is where the
conventions have to live to be followed; a `docs/code-style.md` restating them
would be a second copy with nothing checking the two agree.

**The test of which file something belongs in**, written into `CLAUDE.md`
itself: would the rule read as strange to a stranger who had just cloned the
repository? If so it is personal. If not it is a convention and it is public,
even when it came from one person's preference originally.

**One thing deliberately stayed public in depersonalised form.** "Write for a
reader with little or no Godot experience" is a real documentation standard
here - it is why `docs/godot-editor-guide.md` exists and why editor steps are
numbered click by click. The standard is public; who it was written for is not.

**What it rules out.** Personal notes in `CLAUDE.md`. Absolute paths in any
committed file except `docs/development.md`, which is the one place the project
has always allowed them and labels them as one machine's layout. And a second
copy of the conventions anywhere.

**Still exposed, and a separate decision if it ever matters:** the machine
paths in `docs/development.md`, which are there on purpose, and the author's
name and email in the commit history.

### D96 - The game is drawn into a SubViewport and enlarged by a whole number

**Decision.** Godot's own stretch setting is switched off. The game renders
into a `SubViewport` of exactly 640x360, and `Stage` - the new root scene -
shows that picture through a `SubViewportContainer` enlarged by **the largest
whole number that fits the window**, centred, with black around whatever is
left. `Main` and every screen under it are unchanged and know nothing about any
of it.

**Why.** Two problems with one cause.

The first was reported from play: under the CRT effect, some rows of text were
noticeably blurrier than the rows right next to them. D94a has the measurement
- the barrel warp is the whole of it, the scanlines contribute nothing, and a
row displaced by half a pixel is blended with its neighbour. At 640x360 a
stroke is one pixel wide, so a half-pixel error halves it.

The second is older. D85 recorded that the resolution dropdown did nothing,
because `content_scale_size` and `content_scale_factor` cancelled out exactly.
Both faults come from the same place: **a stretch happens after everything is
drawn, where nothing can reach it.** Put the picture in a viewport and it is an
ordinary texture, which an effect can read.

**What it fixed, measured.** Stroke definition across the playing screen, the
effect on against the effect off:

| | Detail across |
|---|---|
| Before, shader at 640x360 | 90.0% |
| **After, shader at the monitor's resolution** | **102.1%** |

Over a hundred per cent because the effect's own glow adds edge energy. The
point is that the warp no longer costs any: the fault is gone, not reduced.

**Enlarged by a whole number, which is the real cost.** Enlarging 640x360 by
2.5 makes some source pixels three screen pixels wide and others two, so a
letter's strokes come out uneven. Whole multiples keep every source pixel the
same square, and `SubViewportContainer.stretch_shrink` is a whole number
anyway. It is the **width** that decides: 1280, 1920, 2560 and 3840 take no
side bars at any height, so every 16:10 and 3:2 device, Steam Deck included,
gets bars above and below only. Odd widths - 1366, 1440, 1600, 1680 - get a
border all round.

**So the resolution ladder was trimmed.** 960x540 and 1600x900 were the only
two rungs that are not whole multiples of 640x360; a window at either would
have shown a smaller picture with a wasted border. Dropped on the owner's
instruction, and `test_every_rung_of_the_ladder_is_a_whole_multiple` now stops
another one being added.

**Input needed nothing**, which is the opposite of what was feared.
`SubViewportContainer` transforms mouse coordinates into its viewport itself -
measured in `tools/subviewport_spike.gd` - and the game has no code anywhere
that reads the pointer directly. **Popups needed one property**:
`gui_embed_subwindows` on the `SubViewport`, without which the resolution
dropdown is drawn in the window around the picture rather than in it
(`tools/popup_spike.gd`). Both are asserted in `test_stage.gd`, because a
silent change to either would be found by a player rather than by a test.

**No screen, widget, theme or layout file changed.** Not one, and neither did
the simulation. This is where Godot and the Unity notes that prompted the
worry diverge: that project needed a sweep over twenty-seven canvases because
its UI is bound to a camera, while a Godot `Control` neither knows nor cares
which viewport draws it.

**Four things broke on the way, and each is worth knowing.**

1. **The splash screen stopped being skippable by mouse.** Its nodes took mouse
   input, so a click was swallowed by the interface and never reached
   `_unhandled_input`. Every node in that scene is `MOUSE_FILTER_IGNORE` now,
   which is correct regardless - a logo is not a control.
2. **A new test resized the root viewport and did not put it back**, which
   broke the next test that pushed input. `Stage.fit_to` takes the window size
   as an argument so the layout can be tested without touching anything
   shared.
3. **The shader could not take the picture as a function argument.** Godot's
   built-ins exist only inside `fragment()` and `vertex()`, and handing
   `TEXTURE` to a function of your own makes the compiler complain on every
   compile. The picture is a plain `uniform sampler2D` that `CrtOverlay` sets.
4. **The CRT effect stopped being a node in front of the game** and became the
   material on the control that draws it. Reading the *screen* would have
   framed the window rather than the picture, so on a letterboxed monitor the
   tube's edge would have been out in the black.

**Three ways to sample a warped pixel-art picture, and the third is the one.**
This shipped each of the first two and each was reported from play, which is
worth recording because the choice looks like a detail and is not:

| Sampling | What it does |
|---|---|
| Plain linear | Every sample blends with its neighbours by whatever fraction the warp lands on, so rows of text get different amounts of blur. The original fault. |
| Nearest | Whole source pixels, so no blur at all - and a stair-step in every straight line, because a row jumps a whole pixel at once. Reported the day it shipped. |
| **Sharpened** | A source pixel is flat across its whole area, and the interpolation is squeezed into a band at its edge. Flat inside, so no blur; a ramp at the boundary, so no step. |

How wide that band is matters and is a uniform, `edge_softness`, in screen
pixels. At 0 it is nearest and every bent line stair-steps. At 1 the step's
corner is softened but the step is still a whole source pixel tall and still
reads as one - which is what shipped first, and was reported as still stepped.
At the enlargement factor and above it is plain bilinear and the text goes soft
in patches again. **2 is the default**: the step is spread over most of its own
height and stops reading as a step, while the inside of each source pixel stays
flat.

The third is a handful of lines (`sharpened` in `crt_screen.gdshader`): measure
how far the sample is from the nearest **seam between** two source pixels,
divide by how many source pixels a screen pixel covers - `fwidth` of the warped
coordinate, so it follows the curve - and clamp to half a pixel.

**Two engine traps sat underneath all of this, and both made the filter inert
while leaving a plausible picture on screen.** They are the reason this took
three attempts rather than one.

1. **`fwidth` returns zero under the Compatibility renderer.** The filter needs
   to know how many source pixels one screen pixel covers, and a screen-space
   derivative is the obvious way to ask. Getting zero collapses the ramp to
   nothing, so the shader samples each source pixel's exact centre - plain
   nearest-neighbour, steps and all - while appearing to do something clever.
   The enlargement is handed in from `Stage` instead, which it already knows.
2. **A `CanvasItem`'s `texture_filter` overrides the `filter_linear` hint on a
   shader's own sampler.** With the container left on nearest, the shader
   samples nearest whatever it declares, and a filter that works by nudging
   *where* it reads from can have no effect at all. `CrtOverlay` now switches
   the target to linear with the effect and back to nearest without it.

**Neither announced itself.** Both produce a crisp, reasonable-looking picture
that merely has a stair-step in every bent line, and the measurement being used
at the time - how much edge energy survives - reads that as a *good* result.
What caught them was rendering the same screen at two settings of the softness
control and differencing the images: 147 pixels out of 921,600, all of it
scanline noise. A control that does nothing is the cheapest possible test that
a shader is actually running, and it should have been the first thing checked.

**The seam is the whole trick, and the first version anchored on the pixel's
centre instead.** One term, and it inverts the filter: it then ramps across the
middle of every source pixel and snaps at the edges, so nothing is ever flat.
The result looks precisely like pixel art scaled by a fraction - letters with
strokes of different weights, pixels of different apparent sizes - and that is
how it was reported. `floor(x + 0.5)` is the seam; `floor(x) + 0.5` is the
centre. Anyone changing this should render a screen of text and look at it
before believing the arithmetic. It degrades gracefully: enlarged many times the
ramp is a sliver and the picture is crisp, and as the enlargement approaches 1
it widens into ordinary bilinear rather than into aliasing.

**The Unity original does not need this**, and the reason is worth knowing
before anyone copies it back. There, each camera renders into a *window-sized*
texture, so by the time its shader warps anything the picture has already been
enlarged. Half a pixel of warp is half a *monitor* pixel. Here the shader reads
the 640x360 picture directly, so half a pixel of warp is half a *source* pixel
- large enough to see whichever way it is resolved. Sampling it this way is
what buys back what the two-texture arrangement gives Unity for free, without a
second viewport.

**Nearest is still right with the effect off.** The container draws the picture
at a whole multiple with `TEXTURE_FILTER_NEAREST`, where there is nothing to
interpolate. The reconstruction above lives in the shader and applies only when
the picture is being bent.

**The settings panel parents its confirmation to the viewport, not the
window.** Those were the same thing before. Now the window is the monitor and
the viewport is the picture, and a prompt parented to the window would be laid
out at 2560x1440 with text a few pixels tall.

**The development overlay is now inside the picture.** It used to sit above the
effect on its own layer; it is inside the `SubViewport` with everything else,
so with the effect on it is warped and scanlined like the rest. It is a
debug-only tool in a debug-only build and this was not worth a second viewport.

**What has NOT changed, and is worth saying plainly:** the resolution setting
still does nothing in fullscreen, because the monitor's size is the window.
D85's greying-out of the control stays. The honest position is that a
pixel-art game drawn at 640x360 has one picture size, and the only question
was ever how many times it is enlarged.

**What it rules out.** Godot's `stretch` settings, and any `content_scale_*`
call - a second resize on top of `Stage`'s would fight it, which is exactly
what D85 was. Filling a window fractionally: that needs a plain `TextureRect`
instead of a `SubViewportContainer`, and with it a hand-written coordinate
transform for every pointer position, which is the one thing this design gets
for free. And resolution rungs that are not whole multiples of 640x360.


### D97 - Readying up closes your own trading

**Decision.** Once a player presses Ready for New Year, their own buying and
selling is refused until they un-ready. Other players readying has no effect on
them.

**Why.** The year ends the instant the *last* player readies, and everybody
else is still trading until then. So a player who has already said they are
done can be one stray click away from selling everything a heartbeat before the
prices move - and Sell All sits directly beside the list of holdings. Reported
from play on 2026-11-17 after exactly that near miss.

**It costs the player nothing**, which is what makes it safe to do. Readying is
a toggle and always has been: press it again and the board is live. The refusal
says so rather than leaving somebody looking at a screen that has stopped
responding, and `test_the_refusal_says_how_to_undo_it` is what keeps that true.

**The original allowed it** (audit 7, step 1: "players buy and sell freely, in
any order, at the same time"), so this is a deliberate divergence and is listed
as one in audit 19. It is the kind of divergence this project accepts: the
original's behaviour is not a rule anybody chose, it is what falls out of not
having thought about the case.

**Confirmed in a two-player game on 2026-11-17**, by the owner, the day it was
built. Worth recording because the rule only works if un-readying really does
open the board again, and nothing in the suite can play two peers against each
other through the real screen.

**Enforced in `TradeRules`, not in the screen.** The validators are the single
implementation behind the host's enforcement and a client's instant pre-check,
so one edit covers a client being refused, a host refusing a forged request,
and an offline game. The screen greys the controls out as well, which is a
courtesy rather than the rule - a player should not be invited to press
something that will be refused.

**Buying is closed too, not only selling.** The near miss was a sale, but a
purchase made in the last moment of a year is just as much an accident and
cheaper to leave out than to explain.

**Loans were deliberately left alone.** Taking or paying a loan while ready is
still allowed. It is not the reported fault, the buttons are not adjacent to
anything dangerous, and game-rules.md §9.5 is explicit that the game must never
withhold a player's choice about an unpaid loan. If that should change it is a
separate decision.

**What it rules out.** Enforcing this only in the UI, where a client could
ignore it. And any future "ready" that is not a toggle - the rule is only
reasonable because taking it back is one press.

### D98 - Two corners of the playing screen keep their size

**Decision.** The yeehaw panel has a fixed width, and the LOANS button is
centred in the bottom bar when nothing is under it. Both were reported from
play on 2026-11-17 as looking wrong, and both were measured before and after
rather than eyeballed.

**The yeehaw corner used to grow when somebody asked.** Its note changes from
"needs other players" to "<name> wants a yeehaw!", which is wider, and the top
bar is a row - so the corner expanded and the event text beside it re-flowed
mid-sentence. Measured at 128px becoming 150px, with the event panel dropping
from 372 to 350.

It is pinned at **128**, its narrower state. **Revised 2026-11-17, the same
day:** the note first wrapped to a second line to fit the sentence, and then
stopped carrying the sentence at all. It shows only the asker's name now - or
"you" when it is you - because the bottom bar already announces "<name> wants a
yeehaw!" and the corner only has to be the part that persists after that
message fades. One short line, one reserved line, no wrapping.

**The first attempt pinned it at 150 instead** - the wider state - and clipped
the note. That removed the jump but cost the event text 22 pixels permanently,
and the owner reported within the hour that event descriptions were being cut
off because of it. 128 with a shorter note is strictly better: the event area
keeps its full 372 and nothing moves.

**Two lines are reserved under the button whether or not both are used**
(`_reserve_yeehaw_note_height`), or the top bar grows by two pixels the moment
somebody asks - the same fault in the other axis.

**The LOANS button rode half a line high.** Its box is centred in the bar, but
the blank minimum-payment label underneath still took a line, so the button sat
seven pixels above the middle. The label is now hidden rather than blank when
nothing is owed.

**That does not change the bar's height**, which is what the blank-rather-than-
hidden rule in `_refresh_loan_controls` exists to protect. The height comes
from the two reserved lines of the info label in the message column, which is
taller than the loan box either way. The docstring there now says so, because
the rule as written would otherwise forbid this.

**Superseded on 2026-11-17 by D101, which put the description in a panel of
its own.** The strip went back to two lines once it stopped being the only
place the news appeared. The counting below is kept because it is what proved
two lines was never enough *on its own*, which is the finding D101 acts on.

**The event description got three lines, not two.** Raising the yeehaw
fix was not enough on its own: counted across all ninety events in the content,
twenty-one need one line, forty-nine need two, **seventeen need three, two need
four and one needs five**. At a two-line reserve the longest fifth of the
game's writing was cut off mid-sentence. Three lines covers eighty-seven of the
ninety; the last three are 170 characters and up, which is a content question
rather than a layout one.

**The top bar was permanently taller for it** - 49 pixels to 62 - and held that
height whether the year's event was one line or three. It is back to two lines
and its original height under D101. That is D63's rule for
the bottom bar applied to the top one, and D63 also says what to do when a
message genuinely needs another line: raise the reserve, do not make it
conditional. This is that.

**Both corners are pinned by tests that measure**, not by looking:
`test_asking_for_a_yeehaw_does_not_move_the_event_text` and
`test_the_loans_button_is_centred_when_it_stands_alone`. Both were written
first, failed with the numbers above, and only then passed - which is the only
way to know a layout test is testing anything. The top bar has two more:
`test_the_top_bar_holds_one_height_for_every_event` walks all ninety, and
`test_almost_every_event_fits_the_space_reserved_for_it` fails if somebody adds
writing far longer than the rest.

**What it rules out.** Letting any of the three size itself from its contents.
And reclaiming the empty space under a short event description - that space is
the reserve, and the years with a long one are what it is for.

### D99 - A bankrupt stalk keeps its name and loses the rest of its row

**Decision.** When a stalk goes bankrupt its row shows the name and
`BANKRUPT!!!` across the space the detail used to occupy. The dividends, the
yearly change, the amount box and the buy button are hidden rather than
disabled.

**This is the original's shape**, and the audit had already described it -
"the whole detail area is replaced by a BANKRUPT!!! overlay" (section 3.1) -
and then marked it **Ported** when it was not. The port abbreviated it to
`BNKRT` in the price column and left everything else sitting there as though
it still meant something.

**The fault that prompted it.** Reported from play on 2026-11-17: a dead stalk
was still showing how many shares you could afford. The amount box had been
given the affordable maximum as its *placeholder* while the stalk was alive,
and going bankrupt cleared the box's `text` but not its `placeholder_text` - so
the row went on offering five thousand shares of a company that no longer
existed. `set_affordable_hint` already declined to run on a bankrupt row, which
is why it looked right in code and wrong on screen.

**Hidden, not disabled.** A greyed-out buy button still says there is something
here to buy. The original made the row inert and unmistakable, which is the
better answer for a thing that will sit on the board for the rest of the match.

**The row keeps its height**, so the board does not shift when a stalk dies
mid-match. The price label expands to take the freed space rather than anything
changing size.

**Checked by `test_a_bankrupt_row_shows_nothing_but_its_name`**, which sets the
affordable hint first and then kills the stalk - because the stale placeholder,
not the live one, was the actual bug.

**What it rules out.** Abbreviating the word to fit a column. Leaving any part
of the buy controls visible on a dead stalk.

### D100 - A description too long for its panel scrolls, because shrinking it does not work

**Amended 2026-11-18.** Two parts of this were reported as not working and are
gone. The **tooltip** repeated the whole description on one unwrapped line, so
it was redundant for anything short enough to fit and cut off for anything long
enough to want - "redundant and incomplete", which is exactly right. And the
**pause before the first step** was two idle ticks, nearly five seconds, which
is indistinguishable from hovering doing nothing; it is kept for the
wrap-around and dropped on the way in. The scrolling itself stands, and is now
tested by stepping it rather than by waiting on a timer.


**Decision.** A special event description that needs more than the three lines
reserved for it scrolls a line at a time on hover, and pins on click - the same
gesture a stalk's name already uses. `ScrollingLabel` is the vertical cousin of
`MarqueeLabel`.

**Three of the ninety need it.** Measured with the real label at the real
width: twenty-one descriptions fit one line, forty-nine fit two, seventeen fit
three, two need four and one needs five. Eighty-seven never move.

**Shrinking the font was tried first and was the owner's preference.** It does
not work, and the reason is worth keeping because the arithmetic says it should.

Terminus advances by whole pixels at every *even* size - 8 gives a 4x9 cell, 10
a 5x11, 12 a 6x12 - so by the character-grid rule in D40 those look like legal
sizes. They are not. The font has no designed shape below 12, so a smaller size
is rasterised from outlines with hinting off and comes out mangled: at 10 the
letter `m` collapses into a solid block and `i` loses its dot into the stem; at
8 apostrophes disappear entirely, turning "day's" into "day s". Rendered and
looked at, not inferred - a whole-number *advance* is not the same thing as a
whole-number *glyph*, and that is the trap.

**Size 10 would not have been enough anyway.** It fixes one of the three. Only
size 8 fits all ninety, and 8 is the unreadable one. So the font route could
not solve the problem even if the quality were acceptable.

**Why not simply reserve more lines.** Four lines still leaves one clipped and
five would take the top bar to about a quarter of a 360-pixel screen. The three
outliers are 170 characters and more where the rest are far shorter; sizing the
whole interface around them is the wrong trade.

**The whole text is in the tooltip too**, for a player who would rather read it
at once than wait for it.

**What it rules out.** Font sizes below 12 anywhere in this interface, for
anything. And rewriting the three long descriptions to fit, which was the other
way out and is the author's call rather than a layout fix.

### D101 - The year's news is a panel, not a strip along the top

**Decision.** When a year turns, a panel comes up in the middle of the screen
headed **Breaking Market News!** carrying the event's description and what it
did to which stalk. It dims the board and blocks it until the player closes it,
by the Close button, a click anywhere, or Escape. It appears **every** year,
including the ones with no event, where it says so.

**Why.** The event is the one thing each year that moves the market under you,
and it was living in a strip along the top of the board where it is easy to
miss entirely. Reported from play on 2026-11-17. Putting it in front of the
player once a year makes it news rather than furniture.

**This is new, not a port.** The original had nothing like it - the event only
ever appeared in its top strip. Recorded in original-game-audit.md section 18
with the rest of what this port added.

**Every year, which the owner chose over showing it only when something
happened.** In practice that is every year full stop: there is one event a
year, drawn from 45 per mood, and the bag refills when it empties. A year with
no event needs **every one of the nine targetable stalks to be bankrupt at
once** - `EventPool.draw` returns null only when no candidate has a living
target - so it is a wipeout, not a lull. BERRY BONDS is static and is never
targeted.

That case still gets a panel, saying "No special event this year." - the same
sentence the strip uses, so the two can never disagree - rather than being
silently skipped, which would read as the panel being broken in the one game
where everything has already gone wrong.

**It blocks on purpose.** A panel the board can be used around is a panel that
gets ignored, which is the fault this exists to fix. The cost is honest: in a
multiplayer game the others are still trading while you read, so reading
carefully is a small disadvantage. That is the same trade every player makes
and nobody is forced to read slowly.

**Closed three ways.** The button is there to be obvious the first time; a
click anywhere is for the ninth year of the fourth game, when hunting a small
target every year would be a toll; Escape because every other panel in the game
takes it.

**What it lets go of.** Two things built earlier the same day, both of which
were trying to make the strip carry the whole description on its own:

- The strip is back to **two lines** and its original height (D98, D100). It is
  a reminder of news already delivered now, so clipping there is correct -
  twenty of the ninety descriptions do - and the scrolling from D100 stays as
  the way to read a clipped one in place.
- The yeehaw corner keeps its narrow width and shows only the **asker's name**
  under the button rather than a sentence. The bottom bar already announces who
  asked; the corner is the part that has to persist after that message fades.

**What it rules out.** Making the panel optional or skippable-by-default - the
point is that it is in the way. And ever making the top strip the only place
the description appears again.

### D102 - The news panel can be switched off, and a clipped description offers the rest

**Decision.** The news panel carries a **Don't show again** tick box. Ticking
it is saved immediately and lasts beyond the match and beyond the session. The
Settings panel carries the same setting the other way up, as **Show the year's
news**, which is how it is turned back on.

**And the top strip now says when it has cut something short.** Twenty of the
ninety descriptions do not fit its two lines, and until now the text simply
stopped - nothing said there was more. A **... MORE** button appears at the end
of the strip when the description overflows, and pressing it brings the panel
back. Hovering still scrolls the strip in place (D100); the button is the
discoverable version of the same thing.

**Saved on the tick, not on the close.** A player who ticks the box and then
quits another way - Alt+F4 on a fullscreen window - still gets what they asked
for next time.

**The box is clear every time the panel opens.** It is a statement about the
future rather than a control that stays pressed, and a ticked box on a panel
that is nevertheless showing would read as broken.

**Settings is the way back, and it is not optional.** Without it the tick box
is a one-way door: a player who ticked it by accident could never see the
year's news again without hand-editing `user://settings.cfg`. That is the kind
of trap that is obvious once somebody falls into it and invisible before.

**The setting lives in a new `[game]` section** of the settings file rather than
`[display]`, because it is about how the game is played rather than how it
looks. The first thing in there.

**What it rules out.** A dismissal that only lasts the session - the ask was
explicitly for the rest of the game and future games. And making the panel the
only place a long description can be read: the strip scrolls, the tooltip
carries the whole thing, and MORE reopens the panel, so switching the panel off
costs nothing.

### D103 - Who is in a stalk is public; how much they hold is not

**Superseded in part by D105, 2026-11-18.** The investor list below stands, and
so does BERRY BONDS keeping its investors to itself. What no longer holds is
the redaction it was carved out of: position sizes, cash and the loan schedule
all travel now, because host migration needs every client to hold a whole
match. Read this for the Investors panel and D105 for what the wire carries.

**Decision.** Clicking a row on the board opens a panel with the company's
name, a paragraph about it, and **Investors** - the players holding it, by
name. The host sends every player the list of companies each other player is
in, and keeps the sizes of those positions back. Cash and the loan schedule
stay private as they were.

**This moves the line drawn in architecture.md section 5.3**, which had
holdings entirely redacted. The first ask was for amounts as well; the owner
narrowed it within the hour to membership only, which is a better line than
either end. Knowing somebody is in a company is enough to make the board a
place where players watch each other. Knowing *how much* would let you work out
their cash and their next move from the rankings.

**`PlayerState.invests_in` is the only question anything asks**, and it answers
from the amounts when it has them - your own player, and every player in an
offline game - and from the public list otherwise. So nothing in the UI has to
know which side of the wire it is on, and an offline game shows the same panel
as a networked one without a second code path.

**The membership is decoded before the private half is given up on.** The
player decoder returns early for anybody who is not you, and the first version
put the new field after that line, so rivals arrived with an empty list and the
Investors panel was silently always empty in multiplayer. Caught by a test that
applies an encoded state and asks about the other player.

**Descriptions are placeholder text.** Every stalk resource now has a
`description`, and all ten are lorem ipsum. The field exists so the panel has
something to lay out and so there is somewhere for the real ones to go; writing
them is the owner's, like every other line of the game's voice. A stalk with no
description shows "No description." rather than an invented one.

**BERRY BONDS never names its investors.** Added 2026-11-18 on the owner's
instruction: it is the risk-free instrument everybody parks money in, and who
is sitting in the safe haven is nobody's business - that is what a safe haven
is. Who has bet on a *company* is exactly what the rest of the board is for.

**Driven by a flag on the resource, not a check against the id in code.** The
original matched stalks by comparing display strings and needed a hardcoded
BERRY BONDS case for it, which is the mistake this port avoids everywhere
else. `investors_are_anonymous` sits beside the dividends, so a future
instrument that wants the same treatment sets it and needs no code change.

**It says the same whether or not anybody holds it.** "Nobody owns any yet"
where the truth is "we are not telling you" would be a lie, and a player could
read the difference between the two messages to work out the very thing being
withheld.

**Clicking the name opens the panel, and that cost the name's old trick.**
Reported from play straight after this shipped: the name is the most obvious
part of a row to click and it did nothing, because `MarqueeLabel` consumed the
click to pin its scrolling. Pinning is gone - the name scrolls on hover only -
and the label passes clicks through to the row. Pinning existed so a long name
could be read without holding the mouse still, which is exactly what this panel
does better.

**What it rules out.** Showing position sizes anywhere, to anyone but their
owner. And a per-match toggle for this: the owner chose it plainly over the
"open book versus hidden holdings" option the porting plan had recommended, so
that recommendation is settled rather than outstanding.


### D104 - Steam picks the new host; every client only asks who it is

When the host left a Steam game, everybody else was sent back to the title
screen. That is the behaviour `_on_steam_lobby_member_left` was written for and
its own comment admitted it: "this game has no host migration, so their
departure ends the match for everybody."

**Steam already solves the hard half.** A Steam lobby outlives its owner -
there is no way to destroy one, as D68 records - and when the owner leaves,
Steam hands ownership to another member by itself. So there is no election to
run and nothing for the remaining players to agree on. Each one asks Steam the
same question, gets the same answer, and acts on it: *am I the owner now?*

The owner's Unity game does exactly this (`LobbyHostMigration.SteamMoveRoutine`
polls once a second for up to twenty seconds, then either starts hosting or
connects to whoever Steam named), and it is the right shape for the reason
above rather than because it was there first.

**The decision is a class with no Steam in it.** `LobbyMigration` is told who
this player is, who left, and who Steam currently says owns the lobby; it
answers `WAITING`, `BECOME_HOST`, `JOIN_NEW_HOST` or `GAVE_UP`. That split
exists because **none of the plumbing can be tested here** - it needs two Steam
accounts on two machines - so everything that can be got wrong without a second
machine is put where a test can reach it. `test_lobby_migration.gd` covers it.

Two details that are easy to get wrong and are therefore tested:

- **The departed host counts as "not decided yet".** Steam goes on reporting
  the leaver as the owner for a moment after they have gone, and taking that at
  face value means trying to reconnect to the player who just left.
- **An answer after the deadline is still an answer.** The twenty seconds are
  for a lobby that never replies, not a slow one.

`Main` polls every half second rather than every frame, and ignores the
session's own `connection_ended` while a migration is running - the same
departure arrives twice, once from Steam and once from the dying connection,
and acting on the second would drop the player onto the title screen while a
new host was being found for them.

**What it rules out.** Electing a host among the peers, and any notion of a
dedicated server. Also direct (non-Steam) play: ENet has no lobby to hand on,
so a direct match still ends when its host leaves, and says so.


### D105 - Every client holds the whole match, so any of them can host it

Reverses the redaction half of D103. Decided 2026-11-18, by the owner, in these
terms: this is "a very simple and casual game that is just betting on a random
number generator", so secrecy is not important - but "a player shouldn't be able
to change data for another player", so **integrity is**.

Those two sentences settle the design, because the two things had been
conflated. The host sends every client a complete snapshot now: everybody's
cash, share counts and loan schedule, not only their own.

**Why it had to change for migration.** A new host carries the match on from a
copy it already holds. A redacted copy is not a match - it is missing every
other player's position - so a client promoted to host would have had to ask
the remaining players what they owned.

That was buildable and was half-built before being thrown away. Net worth is
public and exactly derivable from cash, prices, shares and debt, all integers,
so a new host could have checked each claim against the figure already on the
board and caught a liar. It was dropped because:

- **The departed host's own half is unrecoverable** however clever the checking
  is. Nobody was ever told it. So that player's position had to be frozen or
  written off regardless, which is a rule invented to serve a mechanism.
- **It is a protocol, a round of waiting, and a failure mode** for every
  player, every migration, to reconstruct something that could simply have
  been sent in the first place.
- Keeping cash secret was buying nothing anybody wanted. The game's own board
  publishes net worth, which is the number players actually watch.

**What integrity means here, and what it does not.** The host still owns every
rule. A client sends requests - "buy 5 of X" - and the host validates them
against its own state; nothing a client says about a position is believed, its
own included. Seeing a number and being able to change it are different powers
and only the first was given away. `test_networked_session.gd` asserts both
halves: a client ends up holding a rival's real cash, and cannot spend it.

**What changed in the code.** `StateSync.encode_state` no longer takes a
recipient and the host builds one snapshot for everybody instead of one each.
`PlayerState.invested_in` and the wire's `has_loan` are gone - both were the
public shadow of a field that now travels in full - and `invests_in` is simply
"do they hold any". `apply_player` overwrites rather than tiptoeing round
absent keys.

**The random stream's position travels too.** A match is reproducible from its
seed *plus the number of draws taken off it*. Seeded afresh from `rng_seed`, a
new host would deal year one's rolls out again in year six. So `rng_state`
rides in every snapshot and `MatchAuthority.adopt_rng_state` picks the stream
up where the departed host left it. Zero is not a reserved value - a freshly
seeded generator sits somewhere arbitrary - so a new host adopts whatever it is
given rather than testing for "unset".

**A lobby is re-hosted; a match is taken over.** Nobody in a lobby has a
position yet, so there is nothing to preserve and the simplest correct thing is
a fresh lobby with the same settings, which the others rejoin as they would any
new game. A match in progress goes through `HostSession.take_over`, which wraps
the client's own `GameState` in a `MatchAuthority` and closes the lobby.

**Returning players are recognised by Steam, not by what they say.** This is
the rejoin D47 deferred, and it was deferred for exactly the reason it is now
possible: handing a slot back hands over its cash, holdings and loan, so "is
this the same person" must be answered by something the arriving client does
not get to choose. A Steam ID comes with the connection; a display name is
typed in by whoever is connecting. A connection with no Steam reclaims nothing,
because matching 0 against 0 would let any arrival walk into the richest vacant
slot. This also fixes an ordinary mid-match dropout, which previously could not
come back at all.

Everybody except the new host starts vacated and reclaims their slot as they
arrive. That is not tidiness: the year gate counts every active player, so
leaving them in would hang the match on people who have not yet had a chance to
reconnect - the deadlock D47 is about.

**Two things this does not do, stated rather than implied.**

- **Whoever Steam promotes is trusted.** They could have tampered with their
  own copy before promoting it. Steam chooses who that is, not this game. There
  is a cheap check available and not built: every client now holds an identical
  snapshot, so each could compare the new host's first one against what it
  already had and object. It is not built because a false positive would
  disconnect an honest player, and nothing has been seen to justify it yet.
- **A migrating player sees a frozen screen for up to twenty seconds** with
  nothing on it saying why. Telling them needs a new piece of UI and its words
  are the owner's to write, so an empty wait was chosen over an invented
  message.

**What it rules out.** Per-recipient redaction, and the `GameSettings`
open-book toggle Phase 8 recommended - there is no toggle, and the book is
open.


### D106 - A lobby that is changing hands must not be shut down on the way out

The first fault reported from playing D104/D105 over two accounts: the lobby
migrated correctly and the new host could start the match, but **the migrated
lobby was not listed in the browser and nobody could join it.**

**The departing host had killed it on the way out.** D68 established that Steam
offers no way to destroy a lobby - one exists until its last member leaves -
so a host leaving shut theirs down as far as Steam allows, by both available
means: the `state` key the browser's filter reads, and `setLobbyJoinable`.
That was right when a host leaving ended the game. It is sabotage when the
lobby is about to change hands.

So `leave_lobby_as_host` now asks how many members are left. One (just the
host) is a lobby dying, and is shut down as before. More than one is a lobby
changing hands, and is left exactly as it is for them to migrate into.

**And the new host advertises it again anyway.** Belt and braces, because the
departing player may have shut it down before this fix, or crashed, or raced
the member count. A new host taking over a *lobby* rewrites `game`, `state` and
the settings and sets it joinable; that is `reopen_lobby_to_the_browser`.
Rewriting all of it rather than only the one key that was wrong is deliberate -
the lobby is being advertised from scratch, and a key the previous owner
cleared would otherwise leave a row the browser filters out or cannot label.

**The second finding, which the report did not name but follows from it.**
Closing a lobby by *both* means also blocks a returning player, because
`setLobbyJoinable(false)` stops anybody getting in at all - invite or stale
lobby id included. The mid-match reclaim D105 built was therefore unreachable:
a dropped player comes back through the same lobby, and Steam's door was
bolted. The two mechanisms are now used separately:

| | Listed in the browser | Joinable |
|---|---|---|
| Lobby, waiting to start | yes | yes |
| Match under way | no | **yes** |
| Host left, nobody else there | no | no |

A match under way staying joinable is the point: **the host is the gatekeeper,
not Steam.** An arrival is matched against the roster by Steam ID and either
reclaims their seat or is turned away with a reason (`_slot_to_reclaim`), which
is a better answer than a silent Steam-level refusal and is the only way back
in for somebody whose connection dropped.

**What it rules out.** Treating "the host left" as one event. It is two, and
which one it is depends on whether anybody else is still in the lobby.

**Not covered by the suite.** All three calls are Steam calls, and the suite
must not reach for Steam (testing.md). Only the guards in front of them are
tested - that a local game or a client with no lobby calls them harmlessly.
The behaviour is manual-testing.md A9.


### D107 - Migration needs two waits, and the Unity game already knew both

The second fault from playing D104: after the lobby migrated, **the new host
could not be connected to.** It hosted without error and played perfectly well
by itself, and every attempt to join it sat on "connecting" until it gave up.

Two causes, and the owner's Unity game carries a named constant for each. That
implementation was read for its *decision* logic when D104 was written - who
takes over, and the twenty-second deadline - and these two numbers were not
carried across with it. They should have been: a constant with a name like
`NewHostStartDelaySeconds` is somebody recording a fault.

**1. A listen socket opened in the same frame as the old peer closed comes up
dead.** The new host tore its client connection down and called
`host_with_lobby` immediately afterwards. Steam had not finished letting go of
the virtual port, and what came back was a peer that reported no error, served
its own process correctly, and accepted nobody. `NEW_HOST_START_SECONDS` is
half a second between the two, matching `NewHostStartDelaySeconds`.

That symptom is worth remembering because it is so misleading: **the new host
sees a working game.** Nothing on that machine is wrong. The fault is only
visible from another one.

**2. One attempt to reach the new host is not enough.** Steam needs a moment to
route to a host that has only just started listening, so an attempt that lands
too early fails for good - the client waits out its own join timeout and gives
up. The port made exactly one attempt and then stopped. It now makes another
on every poll, once a second until one connects or the twenty seconds run out,
which is what `SteamMoveRoutine` does by calling `JoinSteamHost` on every turn
of its loop.

Making this work needed two smaller corrections. An attempt during a migration
**keeps the Steam lobby** rather than leaving it, because the lobby is where
the new host is rather than something being left behind; it used to leave,
which is nonsense on an attempt that is about to be retried. And it **swaps no
screen**, because a half-built session would otherwise put an empty lobby or an
empty market up once per attempt. `Main` watches for the welcome instead and
shows the right screen when one actually arrives.

**What it rules out.** Treating a transport as available the instant it reports
no error. Both of these are the same lesson: over Steam, "no error" and "ready"
are different things, and only time tells them apart.

**Still not covered by the suite**, for the usual reason - it is all Steam. The
decision core and the takeover are unit-tested; the waiting is not.


### D107a - "... MORE" sits in a box of its own, which is a fallback, not the ask

**What was asked for: a button that reads as part of the description**, at the
very end of it, the way "...more" ends a truncated paragraph on a web page.
The owner's words: it "should be a part of the special event text at the very
end, not its own separate section blocking all text from its large block."
What is built is not that. It is what the owner specified *after* two failed
attempts, prefaced with "since you cannot do this". Recording that honestly
matters, because a successor reading only the result would think the result
was the requirement.

**Attempt one: a column in the row.** The button was a second child of an
`HBoxContainer` beside the description. An HBoxContainer gives a sibling its
width for the full height of the row, so a button one line tall took a column
out of *every* line: the first line ended in mid-air with an empty block
beside it. Moving it between rows changed which text it spoiled rather than
stopping it.

**Attempt two: an overlay inside the label.** Anchored to the label's bottom
right corner it took no width, but it sat on top of the text - a few pixels
low, covering the end of the second line. Snapping its left edge to the
character grid stopped it bisecting a letter; it did not stop it covering
them.

**What is built now**, to the owner's drawing: the button keeps a box of its
own in the row and sits at the *foot* of that box, so it lines up with the
second line of the description rather than the first. Nothing is covered and
the description is one column narrower than it would be with no button.

**Why the real thing was not built, for whoever picks this up.** A `Label`
cannot do it. The button has to occupy space on the *last visible line only*,
and a Label offers no way to say that - it wraps all lines to one width. The
tool that can is `RichTextLabel`, where the button becomes an inline
`[url=more]` at the end of the text and `meta_clicked` replaces `pressed`.

The catch, and the reason it was dodged twice: **the inline marker has to go
at the end of the *visible* text, not the end of the description**, so the
text must be truncated by hand. That means laying it out, asking
`get_line_range(1)` where the second line ends, cutting there and appending
the marker - a two-pass measure-then-set, redone on every resize. And it
fights the hover-scrolling from D100, which needs the whole description in the
label: scrolling and truncation cannot both be true at once, so hovering would
have to restore the full text and leaving would have to re-truncate it.

That is a real piece of work rather than an impossibility, and the fallback
above is what is in the game until somebody does it.

Two tests in `test_gameplay_screen.gd` pin the fallback: the button having a
box of its own beside the description, and its bottom lining up with the
description's. `tools/more_shot.gd` renders the strip with a description too
long for it - this was a fault nobody could see in a passing test and anybody
could see in a picture, which is the whole argument for that tool existing.


### D108 - The orchestration is where the faults were, so that is what is tested now

Three host-migration faults were reported from play in a row - D106, D107, and
the one below - and **the suite caught none of them.** It had 759 tests at the
time, including fifteen on migration. Worth writing down properly, because the
lesson is not "write more tests".

**Every one of the three was in `Main`.** Not in `LobbyMigration`, which
decides who takes over and is tested thoroughly, and not in
`HostSession.take_over`, which continues a match and is tested thoroughly.
They were in the orchestration between those two: noticing the host had left,
waiting the right amount, tearing down in the right order, retrying, and
choosing what to tell Steam about the lobby. That code does not call the Steam
API. **It only acts on answers that come from it** - who owns the lobby, which
member left - and that is precisely why it was testable all along and was not
being tested.

The third fault is the clearest example. The reconnect check asked "is the
client connected?", and the session still mounted when the host leaves is a
client that has joined - it joined the host who just left. So the migration
declared success on its first poll, before attempting anything, and stopped.
In play that looked like no migration at all: the lobby kept showing the
departed player as host, anybody trying to rejoin sat on "connecting" because
nobody had taken over, and eventually the dead connection timed out. One
boolean - "has *this migration* tried yet" - is the whole fix.

**What changed, beyond the fix.** Two seams, both of which exist only so the
orchestration can be driven without Steam:

- `StubSteamService` answers `is_running`, `current_lobby`, `lobby_owner` and
  the rest, and *records* the lobby-visibility calls rather than making them.
  What `Main` chose is the testable part; what Steam would do with it is not.
- `SteamTransportSource` is where `Main` gets a `SteamTransport` from. It
  exists because calling the real Steam API uninitialised does not return an
  error - **it takes the process down with a signal 11**, which is what
  happened the first time a test reached that line. The stub hands back an
  ordinary engine peer, so everything above the transport runs for real.

`test_main_migration.gd` then drives the whole sequence: the host leaving,
Steam not having decided, Steam still naming the leaver, being made the owner,
standing down and hosting a turn later, following somebody else and retrying,
giving up after twenty seconds, and the dying connection not cancelling any of
it. **It was checked by reinstating the fault**: six of its thirteen tests
failed, including the one named for it. A test that has never failed is not
evidence (testing.md says this already).

It also covers D106 and D107 in passing - that a migrated lobby is advertised
again, that a match taken over is hidden instead, and that standing down and
hosting happen a turn apart rather than together.

**What it rules out.** "It needs Steam, so it cannot be tested." That was true
of about four lines and was being used to excuse several hundred. What still
genuinely cannot be tested is what Steam does with a lobby and whether a peer
is reachable; that remains manual-testing.md A9.


### D108a - Migration gets a log, and the no-print rule gets one exemption

**Host migration is the one thing in this game that cannot be watched.** It
happens on somebody else's machine, in the seconds after a host walks out, and
every way it fails looks like something else failing: a board that stops
updating, a player stuck on "connecting", a game that carries on single-handed.
Three faults (D106, D107, D108) were diagnosed by reasoning from symptoms,
twice wrongly, because nothing recorded what the code actually did.

So the migration path now prints what it is doing - the host leaving, who Steam
named, standing down, hosting, reconnecting, giving up - and those lines land in
the log file (development.md S10), which is the only account anybody has of a
handover that has already happened.

**This breaks a rule that is checked, so the check was amended rather than
dodged.** `test_conventions.gd` forbids `print()` in `src/`, on the grounds
that it is either a leftover trace or output that belongs on screen. This is
neither. The exemption is keyed to the `MIGRATION_LOG` constant, so it covers
these lines and cannot be widened by accident - any other `print` still fails
the suite.

**What it rules out.** Diagnosing a migration from what the player saw. The
question "did it migrate, or did it quietly become a single-player game?" is
answerable from the log and was not answerable from the screen.


### D109 - The host marker follows the host, instead of meaning "first in the list"

Found while answering a question about what the board shows after a host
leaves, and worth recording because it was wrong for a reason that only
migration could expose.

`GameState.host_player_id()` returned `players[0].id`. That was correct for as
long as the host never changed: the host made the match, so they were slot
zero, so first-in-the-list was the host.

Migration breaks both halves of that. The new host can be any slot, and the
player who left is taken out of `players` entirely (D47) - so the first player
still in the match is just whoever is left, and the board hangs "(Host)" on
them.

**It is invisible with two players**, which is how it survived: when one of two
leaves, the survivor is both the new host and the only entry, so the label is
right by accident. From three players up it names a bystander.

So `GameState.hosted_by` is set by whoever is actually hosting - in
`HostSession.host` and again in `take_over` - and travels in the snapshot, with
the old first-player rule kept as the fallback for a local game, where it is
right by definition.

**What it rules out.** Deriving anything about *roles* from the order of
`players`. That list is the active roster and migration makes it change shape;
it answers "who is playing", not "whose machine this is".

---

### D110 - An absent player stays in the match and leaves the ready gate
**2026-11-18 · Accepted** (amends D47)

A player whose peer has gone is marked `PlayerState.is_away` and stays in
`state.players`. `GameState.all_players_ready()` skips away players; everything
else - dividends, splits, bankruptcies, loan interest, missed-payment
penalties, net worth, the rankings and the winner - treats them exactly as it
treats a player sitting at the keyboard.

**Why.** The owner asked for rejoining, and specified that while you are away
"the game goes on without you and your position is still affected". Under D47
that was impossible: a dropped player was removed from `state.players`, which
is the list `YearResolver` walks, so they earned nothing, were charged nothing
and ranked nowhere. Coming back would have returned the position they left
rather than the one the match had been building for them, which is a save file,
not a rejoin.

D47 removed them for one reason only - the all-ready gate counted every player,
so a dropout deadlocked the year (D46). That is a problem with the **gate**, and
fixing it in the gate costs one flag and one loop. Removing the player fixed the
gate by taking a sledgehammer to the economy.

**What it buys beyond the rejoin.** Three things that were simply wrong before
and are now right by construction:

- **A migration no longer costs everybody a year.** `take_over` marks every
  player except the new host as away, and they keep being paid while they
  reconnect.
- **`HostSession` keeps one list instead of two.** `_roster` held every slot and
  `state.players` held that list minus the dropouts, rebuilt on every arrival
  and departure by `_rebuild_active_players`. The difference between them *was*
  this flag. Both are gone, and `state.players` is the roster.
- **`display_name_of` stopped needing its own lookup.** It existed because
  `state.player_by_id` stopped finding a player at exactly the moment a screen
  wanted to name them.

**The missed loan payments needed no new rule.** `LoanRules.process_year_end`
records a miss whenever `paid_this_year` is false, and an absent player never
pays, so the existing 10% / 15% / seizure schedule applies the moment they stay
in the pipeline. Three years away with a loan outstanding wipes a player out.
The owner was told this and called it "tough but fair". It is pinned down in
`test_away_players.gd` because it is a load-bearing accident rather than
something anybody wrote.

**What it rules out, and the hazard it introduces.**

- **An away player can win a match they were absent for half of.** The owner was
  told and asked for it anyway. It cuts both ways: they can also be overtaken
  while they are gone.
- **A match everybody has left must not resolve years.** With the gate skipping
  away players, a deserted match satisfies it vacuously - nobody present, so
  nobody unready - and would run itself to the end before anybody could rejoin.
  `all_players_ready()` returns false when nobody is present, which is the
  guard, and `test_a_match_everybody_has_left_does_not_resolve_years` is why it
  will stay.
- **Reading a role off the order of `players` is now wronger than it was.** The
  host who walked out is still first in the list. D109 already said not to; this
  makes the mistake invisible in two-player play and wrong from three up.

**Where it lives.** `PlayerState.is_away`, `GameState.players_present()` and
`all_players_ready()`, `HostSession._on_peer_disconnected`, `_reclaim_slot`,
`take_over` and `waiting_on()`, `StateSync.encode_player`/`apply_player`,
`YeehawRules.validate_request`, and the `(away)` tag and grey dot in
`RankingRow`. Tested in `test_away_players.gd` (20 tests),
`test_networked_session.gd` and `test_host_migration.gd`.

---

### D111 - Rejoining is a remembered lobby id, and nothing more than that
**2026-11-18 · Accepted, and amended by D115 the same day**

**Two entries amend this one.** D115 is the half it was missing: the button is
now offered only once Steam has confirmed the lobby is still a game worth going
back to, rather than offered on trust and allowed to fail. D116 corrects the
bullet below about the welcome landing on the playing screen, which was true of
REJOIN GAME and false of every other way back in.

REJOIN GAME sits at the right-hand end of the title screen's bottom row,
opposite QUIT TO DESKTOP, and appears only when this machine has an online
match to go back to. Pressing it joins the remembered Steam lobby and the
existing reclaim path does the rest.

**Why there was nothing to build.** Every piece already existed, for host
migration:

- The lobby of a match in progress is unlisted but **still joinable**. The
  `state` metadata key is what the browser filters on and `setLobbyJoinable` is
  Steam's own door; D106 separated them precisely so somebody could come back.
  So `Steam.joinLobby(id)` works on a running match and needs no new API.
- `HostSession._slot_to_reclaim` matches an arriving Steam ID against the roster
  and `_reclaim_slot` seats them on it (D105). Steam ID is the identity check
  and must stay that way: a display name is typed in by whoever is connecting.
- The lobby owner is read at rejoin time, so a match that changed hands while
  this player was away is rejoined through whoever hosts it now (D104).

What was missing was a **route**, and the route is a lobby id written down.

**Where the record lives: `user://last_match.cfg`, not `UserSettings`.** D71
kept match state out of the settings file deliberately, and this is the
opposite kind of thing from a preference: written when a match reaches the
playing screen, forgotten when it ends, meaningless a week later. Its own file
also means a stale rejoin record and somebody's volume setting cannot damage
each other. It holds a lobby id and the game's name, and nothing worth forging -
the position comes from the host, and the seat from Steam.

**Written in `Main._show_gameplay`**, because every route into the playing
screen passes through it: hosting, joining, a migrated host, a migrated client,
and a rejoin. One call instead of five.

**Decisions inside it, each put to the owner on 2026-11-18 and accepted:**

- **A deliberate "quit to menu" is rejoinable, like a crash.** The host cannot
  tell the two apart - a peer simply stops answering - so a distinction would
  mean inventing one, and "I had to go, let me back in" is the ordinary case.
- **A failed rejoin does not forget the match.** A Steam relay having a bad
  minute would otherwise destroy the only route back into a game that is still
  being played. The record is forgotten when the match *ends*, which is the one
  thing the game knows first-hand, and overwritten by the next match.
  *(Amended by D115: still true of a failure or a silence, but the button is no
  longer offered on trust and then allowed to fail — Steam is asked first, and
  a definite "that game is not there" does forget it.)*
- **The welcome lands on the playing screen, unconditionally.** A match is only
  remembered once it has reached the board, so there is no lobby for a rejoin to
  arrive in. This is why no "has the match started" flag had to be added to the
  snapshot.
  *(Amended by D116: true of this route and of no other. Steam's friends list
  and an accepted invite come in through the ordinary join path, which shows
  the lobby and waits to be told the match has begun — so the host now tells a
  reclaiming peer, rather than `Main` knowing it by arrangement.)*
- **A finished match refuses the returning player, with its own sentence.** This
  refusal only became reachable with this feature: the title screen offers a
  match it has no way of knowing has ended, because the player was not there to
  see it finish. Without it they would be welcomed onto a final board and left
  looking at a result as though it were a turn. `HostSession.why_not_rejoin` is
  the one place both refusals are decided, kept pure so the rule is testable
  without peers.
- **No confirmation on the button.** Rejoining a game you were already in takes
  nothing away from you.

**What it rules out.** An invite from the host into a running match. The owner
was explicit that a player who was *not* in the match must not be let in, and
the two were briefly conflated. Nothing here lets a host add anybody: the only
way past `_on_introduced` is a Steam ID already on the roster.

**Not verified in play.** Everything that talks to Steam needs two accounts on
two machines; see manual-testing.md B6. What the code establishes is that
nothing in this project closes the door - `hide_lobby_from_the_browser` writes
metadata only, and the single `setLobbyJoinable(false)` is guarded by the host
being the last member out. Whether Steam itself admits a client to an unlisted
lobby is unverified, as is whether the friends list offers "Join Game" for one
(which, if it does, already works: `join_requested` is wired to
`Main.join_online_game`).

**Where it lives.** `src/data/last_match.gd`, `Main._on_rejoin_requested`,
`_rejoin_the_match`, `_on_rejoin_landed`, `_give_up_on_rejoin`,
`_remember_this_match`, `MainMenu.offer_rejoin`, and
`HostSession.why_not_rejoin`. Tested in `test_main_rejoin.gd` (21 tests) and
`test_host_migration.gd`.

---

### D112 - A refused join reports itself, instead of failing in silence
**2026-11-18 · Accepted**

`SteamService.lobby_failed` is connected in `Main._watch_the_service`, which
every path that touches Steam goes through, rather than only in
`_on_host_online_requested`.

**The fault.** It was connected only when *hosting*. A join Steam refused - a
lobby that no longer exists, one that is full, one not open to new players -
emitted its reason to nobody at all. `SteamService._why_refused` words those
three with some care, and D67 records the owner meeting the proof that code 3
deserves its own sentence. None of it reached the screen: picking a stale game
out of the browser reported nothing and looked like a button that did not work.

**Why it surfaced now.** REJOIN GAME must fail with a sentence rather than hang,
and writing the test for that found the gap in the path it shares with the
browser. Found by reading rather than from play, which is the one kind of bug
this project has had trouble finding - see D108.

**Where it lives.** `Main._watch_the_service`, and `_on_steam_lobby_failed`,
which now also clears `_pending_join_lobby` and `_rejoining`. Tested by
`test_main_rejoin.gd::test_steam_refusing_the_lobby_says_so_on_the_title_screen`.

---

### D113 - A one-line conditional hid a typed-array fault on the branch that mattered
**2026-11-18 · Accepted**

`GameOverScreen._render` read

    var winners: Array[StringName] = result.winners if result != null else []

which is wrong in a way that only fires when `result` is null: a bare `[]` is an
untyped `Array`, and assigning one to an `Array[StringName]` is a **run-time**
error, not a parse error. So the defensive branch - the one written to keep the
screen up when a match has no result yet - was the branch that took the screen
down. It is now an if/else block.

**Why it sat there.** Nothing in play reaches it. A match that is over has a
result, so `latest_result()` is never null by the time this screen is built. It
was found by a test that drove `Main._on_match_finished` on a state with no
history.

**Worth recording because the shape recurs.** Static typing is enforced here as
a parse error (`untyped_declaration=2`), and that has made it easy to assume the
parser catches typed-collection mistakes. It does not catch this one. The
project already bans conditional expressions split across lines for readability
(`test_conventions.gd`); this is a second reason to prefer the block, and the
one-line form was inside the rule.

**Where it lives.** `src/ui/screens/game_over/game_over_screen.gd`.

---

### D114 - A session that fails to open its socket frees itself
**2026-11-18 · Accepted**

`HostSession.host`, `HostSession.take_over` and `ClientSession.join` build the
session Node *before* asking the transport for a socket, and on failure they
returned `{session: null, error: ...}` while leaving that Node unparented and
unfreed - an orphan for the rest of the process. They now free it.

Harmless in a real game, which gives up after one such failure, and the reason
the suite reported orphans it was not responsible for. Worth a line because the
"build, then try, then report" shape is the right one and will be copied: the
free is the part that is easy to leave out.

**Where it lives.** `src/net/host_session.gd`, `src/net/client_session.gd`. The
suite's orphan count went from 10 to 3.

---

### D115 - A remembered lobby is a candidate, and Steam is the authority
**2026-11-18 · Accepted** (amends D111)

Before REJOIN GAME is offered, `Main` asks Steam whether the remembered lobby
still exists and whether the match in it is still being played
(`SteamService.request_lobby_details`, which wraps `requestLobbyData`). The
button is hidden until that answer comes back good, re-asked every five seconds
while the title screen is up, and the record is thrown away when the answer is
a definite no.

**The fault, reported from play on 2026-11-18** - after the feature itself
worked over Steam, which it did first time. A player who left a game they were
the last one in came back to a title screen still offering it. Pressing it said
"That game no longer exists." Playing a single-player game in between changed
nothing, because nothing in that path touches the record. The owner's words:
"this seems like it will be very confusing to the player."

**D111 got one half right and the other half wrong.** The half it got right is
that a *failed attempt* must not forget the match: a Steam relay having a bad
minute would otherwise destroy the only route back into a game still being
played. That reasoning stands. The half it got wrong is that it left the
failed attempt as the **only** way to find out, so the player did the
discovering, by pressing a button. Remembering a lobby was treated as knowing
it was alive, and those are different things.

**Steam can be asked, and this is what it is for.** `requestLobbyData` refreshes
the metadata of a lobby this process is **not** in and answers on
`lobby_data_update`. It is the only way to tell a match still being played from
one that ended, because neither is in the lobby browser - a match in progress is
deliberately unlisted (D106). Verified against the installed plugin with
`tools/steam_signals.gd` rather than against documentation for some other
version.

**Three answers, one of which offers the button:**

| Answer | Button | Record |
|---|---|---|
| The lobby exists and its state is not `over` | shown | kept |
| The lobby is gone, or its state is `over` | hidden | **forgotten** |
| Steam did not answer | hidden | kept, asked again in five seconds |

**Failing closed is the change in posture.** D111 offered the button and let the
attempt fail; this hides it and lets the next tick put it back. A player never
presses a button that cannot work, and a flicker of a bad connection costs five
seconds rather than a seat. The distinction D111 drew is kept exactly where it
belongs: a *silence* still does not forget, and only a definite "that game is
not there" does.

**`STATE_OVER` is new, and is for somebody who was not there.** A match that
ends does not take its lobby with it - everybody is still in it, reading the
result screen - so the lobby is alive and reachable and a returning player
would be let in and put on a dead board. The host writes `state = over` when
the match finishes, which is the only way a player who was away can learn that
it did. The host's own refusal ("That game has finished.", D111) is still there
as the backstop; this is what stops it being reached.

**One case is answered without asking Steam anything.** When this process
leaves a lobby it was the last member of, the game is definitively over and it
watched that happen, so `leave_lobby_as_host` now reports it and the record is
dropped on the spot. That is exactly the case that was reported, and it is
fixed whether or not Steam's answer for a destroyed lobby turns out to be the
one assumed.

**What it rules out, and what is still unverified.**

- **The button can appear a moment after the title screen does.** It is hidden,
  then shown when Steam answers. Offering it immediately and retracting it would
  be worse: a button that moves under the cursor.
- **With Steam closed the button never appears.** Correct rather than
  unfortunate - there is nothing it could do - and the record is kept, so it
  comes back when Steam does.
- **Whether Steam reports `success = 0` for a lobby that no longer exists** is
  assumed, not verified. If instead it simply never answers, the behaviour is
  still right: no button, and the record lingers harmlessly on disk. The design
  is correct under either, which is why it was built this way rather than
  waiting for a two-machine run to settle it.

**Where it lives.** `SteamService.STATE_OVER`, `mark_lobby_finished`,
`request_lobby_details`, `lobby_details`, `_on_lobby_data_update` and
`leave_lobby_as_host`'s return value; `Main._ask_whether_the_remembered_match_is_still_there`,
`_on_steam_lobby_details`, `_offer_rejoin_on_the_menu`, `_tick_the_rejoin_check`
and `REJOIN_CHECK_SECONDS`. Seventeen tests in `test_main_rejoin.gd`.

**Standing with the field.** The shape - remember a handle, ask the service
whether it is still live, offer the action only then, treat an empty answer as
ordinary rather than as an error - is the one Epic's EOS documents for
reconnecting to a session, and matches the general advice to decide what to
show from a health signal rather than from a stored id. Nothing here is novel;
the first version simply skipped the middle step.

---

### D116 - The welcome says who you are; something has to say the game is on
**2026-11-19 · Accepted** (amends D111)

`HostSession._on_introduced` sends `_rpc_match_started` to a reclaiming peer,
right after the welcome.

**What was wrong.** The welcome carries a player id and a snapshot, and neither
of them says whether the match has *started*. A client cannot work it out
either: year 0 is a real year, and a lobby that has not begun and a match on
its opening position produce the same snapshot. The lobby screen swaps itself
for the board on the client's `match_started` signal, and that signal was only
ever sent by `start_match()` - which, for somebody coming back, ran long ago.

So a reclaiming client was **seated correctly and then stranded**: put back on
its own slot with its own cash and holdings, and left looking at a lobby
screen while the match ran on without it. With a Ready button that was
enabled, and that reached `_apply_ready` on the host, where readiness means
"advance the year".

**Why REJOIN GAME never showed it.** That route suppresses the lobby screen
entirely (`join_steam_match` with `reconnecting`) and `Main._on_rejoin_landed`
puts the board up itself when the welcome arrives. D111 recorded that as a
decision - "the welcome lands on the playing screen, unconditionally" - and
justified it by noting a match is only remembered once it has reached the
board, so there is no lobby to arrive in. That was true of REJOIN GAME and
false of everything else.

**Everything else** is Steam's friends-list "Join Game" and an accepted invite,
both of which arrive through `Main.join_online_game` - the ordinary join path,
which shows the lobby and waits to be told. The owner asked on 2026-11-19
whether that route would work. The seat reclaim half of it did; the screen half
did not.

**Why the host tells the client, rather than the client working it out.**
`join_online_game` could have guessed, by checking whether the arriving lobby
matches the remembered one. That fails exactly where it matters most: a player
on a fresh install, a different PC, or one who cleared their record has no
remembered lobby and is precisely the person using the friends list. The host
is the only party that knows, it already has a signal that means this, and
saying it costs one line. One fix for every route in, including routes nobody
has thought of yet.

**Ordering is not luck.** `_rpc_welcome` and `_rpc_match_started` are both
`("authority", "call_remote", "reliable")`, so they arrive in the order sent:
the state is applied and `has_joined` is true before anything acts on the
second.

**What it rules out.** Nothing. The paths that already worked have no listener
for the extra signal - REJOIN GAME and host migration both suppress the lobby
screen - so it is received and dropped. A lobby migration never reaches this
branch at all, because the new host re-hosts with the lobby open.

**Where it lives.** `HostSession._on_introduced`. Tested in
`test_networked_session.gd`, which now exercises the whole reclaim over a real
socket: `NetHarness.start` takes Steam ids, and `_slot_to_reclaim` only ever
asks for an integer, so ENet carries a reclaim end to end with no Steam
anywhere. That is four tests covering something that previously had none below
the `Main` level.

---

### D117 - Quitting to desktop mid-match asks; the window's X still does not
**2026-11-19 · Accepted**

The pause menu's **Exit to Desktop** raises a confirmation before closing the
game. Clicking the window's X, and the title screen's QUIT TO DESKTOP, still do
not ask.

**The fault, reported from play.** Exit to Desktop sat two buttons under Leave
Game, which asks, and closed the game on the press. A misclick ended the
session. There was no argument for the asymmetry: both buttons end the match
you are in, and one of them also ends the program.

**Why the X is different, and why that is not an inconsistency.** D71 decided
that `_notification` must not ask, on the grounds that a confirmation in front
of a window that is already going away is an argument with somebody who has
finished. That reasoning is about the *X*, and it holds. What it never covered
is a button inside a menu, sitting beside one that asks, reachable by accident.
The title screen's button is a third case and also stays silent: there is no
match to lose from there, and D111's wording for it says so.

So the rule is not "quitting asks". It is **"a press that can end a match you
are in the middle of asks"**, which is true of this button, false of the X,
and false of the title screen.

**Its own `ConfirmPanel`, not the leave prompt's.** `confirmed` is connected
once, when the panel is built, and a shared panel would need its handler
swapped on every ask. That is precisely how a yes ends up doing the other
thing. Two questions, two panels, two yeses that cannot be confused;
`test_leaving_and_quitting_do_not_share_a_confirmation` is there to keep it
that way.

**The pause menu now closes on the press**, which reverses a smaller decision
recorded in `test_quitting_stays_open_until_the_host_acts`: it used to stay
open because "closing first would flash the board for a frame on the way out".
True while the press was final; false now that the player may say no, and a
menu left standing is a menu the question is being asked from behind.

**The wording does not say the game is over**, because it is not. Rejoining
exists (D111): a player who quits to desktop mid-match keeps their seat, the
match goes on without them (D110), and the title screen offers REJOIN GAME when
they come back. The question is "Leave the game and quit to desktop?", which is
the leave prompt's shape and claims nothing further. It does not promise a
rejoin either - that would be false in a single-player match, and varying the
sentence by match type is a branch for no gain.

**Testing it needed care.** Saying yes calls `get_tree().quit()`, which in a
headless run takes the whole suite down, so the yes is asserted as a connection
rather than pressed. The check that the fix works at all is unusual and worth
recording: reinstating the old wiring and running
`test_pause_menu.gd` **ends the run mid-suite with no summary at all**, which
is the strongest available evidence that the press no longer closes the game.
A green run of that file is part of the assertion.

**Where it lives.** `Main._ask_about_quitting`, `_quit_prompt`,
`quit_prompt()`, and `PauseMenu._on_quit_pressed`. Seven tests in
`test_pause_menu.gd`.


### D118 - The year-by-year record travels with the welcome

Reported from play, 2026-11-19: a player who rejoined a match and played it to
the end saw a **year-by-year page that began at their rejoin**. The screenshot
showed one row, Y11, on a match that had run eleven years.

**Why.** `GameState.history` is filled in two different places. The host's
grows inside `YearResolver.advance_year`, which appends the `YearResult` it has
just produced. A client's grows in `ClientSession._on_year_pushed`, one entry
per year broadcast it is **present for**. A snapshot carries the year number
and the prices but has never carried the history, so a client that arrives
mid-match starts with none and accumulates only from its arrival.

**It was worse than reported.** The same thing happens on every host migration:
each surviving client reconnects to the new host, is welcomed into a fresh
`GameState`, and loses the record of the match it has been playing all along.
The new host keeps its own, because `take_over` promotes the copy it already
held. So the only player with a full record after a migration was whoever
happened to take over.

**The fix is the welcome, not the snapshot.** `_rpc_welcome` gained a third
argument carrying every year so far. It is deliberately not part of
`encode_state`: a snapshot goes out on every trade, and the history changes
only when a year resolves and matters only to somebody who was not there. One
welcome of a long match costs a few tens of kilobytes on a reliable channel,
once; the alternative would have sent the whole past every time anybody bought
a share.

**Applied wholesale rather than appended.** A reconnecting client may already
hold the years it was present for. The host's record is the authoritative one
and merging the two would print some years twice.

Nothing new crosses the wire in kind: `encode_year_result` already existed for
the live broadcast and is built-in types only, so D41 is untouched.

**What it rules out.** A client's history being something it assembles for
itself. It is now told to it, like everything else about the match.

---

## Phase 12 - considered and removed

### D119 - Custom stalks were built, hardened, and taken back out
**2026-11-20 · Accepted**

Players writing their own companies as JSON files, choosing which companies a
match uses, and hosting a match on them, was built on 2026-11-19, hardened on
2026-11-20, and removed the same day. The decision is the owner's and it is
not a verdict on the implementation: the suite was green, the receive path had
been attacked deliberately and the two things that gave way were fixed.

**Why it was removed.** The feature widened what one machine accepts from
another, and the owner had not settled on wanting it. A permanent widening of
that surface in exchange for a feature nobody is sure about is a poor trade,
and the cheapest moment to decide that is before anything is built on top.

**What it would cost to bring back**, which is the part worth having written
down:

The port's network rule was that **definitions are not sent**. Both machines
load the same `.tres` content, so only ids travel and each receiver looks the
definition up locally; `apply_state` refuses a snapshot naming a stalk it
cannot resolve, on the grounds that a client running different content from
the host is worth failing loudly over. Custom stalks cannot work under that
rule - a host may be playing companies no other machine has ever seen - so the
definitions had to travel, once, with the welcome. That is the whole of the
design and everything else followed from it:

- Content stopped being a property of an installation and became part of a
  match, because a client that takes the match over after a migration has to
  serve the content it received rather than re-reading its own disk. The board
  survives either way, since the promoted `GameState` already holds its
  definitions - but the **event pool comes from the library**, so a new host
  reading its own files runs a match whose board shows the departed host's
  companies while nothing can ever happen to them again.
- A definition became hostile input, since it arrives from another player. It
  needed the same posture D41 takes for the wire: built-in types only, every
  field listed by hand off a whitelist, object decoding never enabled.
- Player-written content had to be JSON rather than `.tres`, because loading a
  `.tres` instantiates whatever script it names.

**Two faults found by attacking that path**, worth knowing before writing
anything like it again:

- `NAN` defeats a magnitude guard, because every comparison against NAN is
  false. It reached `int(NAN)` - the most negative integer there is - and was
  caught only by a range check that happened to follow. Check `is_nan` first.
- Refusing can be made expensive. A stalk carrying two hundred thousand bad
  events took 1490ms to refuse, building an error string for each; ten such
  stalks would have held a joining client for fifteen seconds. Refuse a list
  by its size before walking it, and cap the error list.

**Where it is.** Commits `042a40a` (the feature) and `15d5ab6` (the attack and
its fixes), reverted together by `bbc58a5`. Reverting that commit restores
both, hardened, in one step. Everything else - the shipped companies and their
descriptions, host migration, rejoining, and the year history travelling with
the welcome (D118) - was untouched, and the tree after the revert is
byte-identical to the commit before the feature.

**What it rules out.** Nothing permanently. If this is picked up again, start
from the rule it has to break - definitions are not sent - rather than from
the file format, which was the easy half.


### D120 - A broadcast does not reach the host, so the host has to be told separately

Reported from play, 2026-11-20. A player drops out mid-match and their rankings
dot goes grey, which is right. They rejoin, and **on the host's screen they stay
grey** - with nothing to say they are back - until something unrelated redraws
the board, in practice another player pressing Ready.

**The state was never wrong; the view was.** `_reclaim_slot` clears `is_away`
and `_broadcast_state` sends the corrected snapshot to every peer. But
`_broadcast_state` skips `HOST_PEER_ID` - the host is not a peer it sends to,
because the host already holds the authoritative state. So on the host's own
machine nothing happened that the board could react to.

The host *was* told, by `player_joined`, which the reclaim path emits. **Only
the lobby screen was listening.** The playing screen connected `player_left`
and not its opposite, so it heard about people going and not about people
coming back. Adding the other half is the whole fix.

The board now says "so-and-so rejoined the game." on the same transient line
that already says "so-and-so left the game.", and refreshes.

**A limitation, stated rather than hidden.** Both messages are host-only,
because both ride a `HostSession` signal and a client's `_host` is null. A
non-host client sees the dot correct itself through the ordinary state
broadcast but gets no sentence. That asymmetry is not new - "left the game" has
always behaved this way - and it is not fixed here, because a client cannot
currently tell a rejoin from any other state change: `player_changed` fires for
a share purchase too. Telling clients would mean a signal that says what
happened, which is a bigger change than the fault warranted.

**What it rules out.** Assuming that broadcasting state informs everybody. It
informs everybody *else*. Anything the host's own screen must notice has to
reach it by a signal, and the two halves of a pair - joined and left, opened
and closed - should be wired together or neither.


### D121 - The event strip is derived from state, not written once by a signal

Reported from play, 2026-11-20, in two shapes that turned out to be one fault:
a player who rejoined a match saw **no special event text at all**, and so did
a **new host after a migration**. Both held whether the rejoin happened in the
same year as the disconnect or years later.

**The strip was only ever written by the year turning.** `_show_event` had one
caller, `_on_year_resolved`, so the text was set at the moment a year resolved
and never again. `refresh()` - which rebuilds every other part of the board
from `GameState` - did not touch it.

So any board built *after* a year had turned started blank and stayed blank
until the next year. That is every board built on a match in progress:
rejoining shows the playing screen fresh, and a migration rebuilds it for the
player taking over. The mood label survived, because `_refresh_year` already
reads `game.latest_result()` - which is precisely the value the strip needed
and was not using.

**The fix is to derive it like everything else.** `refresh()` now fills the
strip from `state.latest_result()`. That is only possible because the history
travels (D118); before that a rejoining client had nothing to derive it from,
which is why these two faults arrived together.

**Guarded on the year, deliberately.** `refresh()` runs on every state
broadcast - every trade anybody makes - and `set_full_text` returns a long
description to its first line (D100). Re-setting it each time would snatch the
text back under a player in the middle of reading it, so the strip is rewritten
only when the year it is showing changes. There is a test for the scroll
position holding, because that regression would be subtle and annoying rather
than obvious.

**What it rules out.** Treating a signal as the only way a piece of the board
gets its value. A signal says *when* something changed; the state says *what it
is*, and a screen that can be rebuilt at any moment - which every screen in
this game now can, after migration and rejoining - has to be able to ask.

### D122 - A finished match is still a match, and which screen is read off the state

Reported from play, 2026-11-20. A match ended, everybody was on the result
screen, and the host left. The host reached the title screen, which is right.
The remaining client did **not** stay on the result screen: it was put into a
**lobby** for the match that had just finished - carrying that game's name, and
offering to start it again.

**One line decided all of it.** `Main._begin_migration` asked

    _migrating_in_match = _screen is GameplayScreen

and a player reading the standings is on a `GameOverScreen`, so the answer was
false and the whole handover went down the re-host-a-lobby branch: a brand new
`HostSession.host` rather than `take_over`, the Steam lobby advertised again,
and `_show_lobby()`.

Two consequences followed from that branch rather than from the flag, and both
were reported as separate complaints. The lobby kept the finished game's name,
because `_name_the_match` leaves a name that is already set. And it kept the
finished game's **seed**: `build_authority` writes the chosen seed back into
the settings, so by the end of a match `settings.rng_seed` is a concrete
number, and re-hosting with those settings reuses it. Pressing Play in that
lobby would have replayed the exact market everybody had just finished.

**A finished match is a match to be carried over.** The flag now includes the
result screen, so `take_over` runs and the match is preserved. That is safe
without further guards: `_advance_if_everybody_is_ready` and the yeehaw rules
are already gated on `state.is_over`, so a finished match that changes hands
cannot resolve another year.

**Which screen is a separate question, and it is now read off the state.**
`_show_the_screen_for` is the one place that answers it, as a three-way:

1. `state.is_over` - the result screen
2. otherwise, the host has said the match is on - the board
3. otherwise - the lobby

`is_over` ranks first because a reconnecting seat-holder is told *both* that
they are in a finished match and, by `_rpc_match_started`, that the match is on
(D116); the result screen is the right answer to that pair.

**Case 2 reads the host's own word for it, and that had to start being
remembered.** Year 0 is a real year, so a lobby and a match that has just begun
are indistinguishable in the state - which is exactly why D116 made the host
say so outright. `ClientSession` re-emitted that and forgot it, because the
only listener was the lobby screen, which acts the instant it hears. A
migration has to answer the same question long afterwards, so `_match_is_on` is
recorded now, set by `_rpc_match_started` and cleared by every welcome.

**Case 3 is unreachable in play today, and is written anyway.** Nothing can
currently produce a client holding a *lobby* while another client holds a
*finished match* - it needs somebody to join a new lobby after a match has
ended, which is what a rematch would be. A two-way answer is correct only
because that case cannot happen; the moment it can, it sends somebody to a
board for a game that has not started. Writing the rule out in full costs three
lines and a test, and means whatever reaches it finds the rule already right.
`test_main_migration.gd` drives all three branches directly, the third by
setting the state rather than by playing, and says so.

**This also absorbed a second fault.** A migration while a player was looking
at the *final board* - which is a `GameplayScreen`, so the old flag was right -
rebuilt that screen without `_viewing_final_board`, giving a disabled "Game
Over" button and no route back to the standings. Under the three-way such a
player goes to the result screen instead, because their state is over. Nothing
is lost: View board is still there.

**And it amends D111.** `why_not_rejoin` refused any arrival into a finished
match with "That game has finished." - including somebody whose own seat was
still on the roster. That was decided when the only way to reach it was REJOIN
GAME from the title screen, and the objection was real: being welcomed onto a
final board read as a turn you could take. But the answer to that is the result
screen, which now exists on every route in, and seeing how the match you were
in ended is worth coming back for. A seat-holder is let in and lands on the
standings. Strangers still get a sentence, and the right one of the two.

The migration above forces it as well as improving it: a handover during the
results leaves *every* remaining player holding a finished match, and whoever
Steam does not pick has to reconnect into one. With three players, refusing
them dropped somebody to the title screen for no reason but having read the
standings on the wrong machine. Two accounts cannot see it - the only client
left becomes the host - which is why it was found by reading rather than in
play.

**Play again is hidden in a networked match.** `_on_play_again` duplicates the
finished settings, clears the seed and calls `start_match`, which is the *solo*
path: `LocalSession.create`. In a networked game that walked out on everybody
still reading the result, and on the host it discarded the session - closing
the peer and leaving the Steam lobby - which is what made the client see the
host leave and start the migration above. So the second reported fault had the
same cause as the first.

It is hidden rather than disabled, and rather than rewired, because **the
original has no rematch at all**: its result panel has `Quit Game` and a close
box (original-game-audit.md 12). A result screen offering Main menu and View
board is what the port is meant to be, and a button that drops a networked
player into a single-player game is worse than no button. A multiplayer rematch
is a feature in its own right; when it is built, this is the button it takes
over.

**What it rules out.** Deciding anything about a match from the class of the
screen the player happens to be looking at. The screen is a consequence of the
state, and this is the second time that got the wrong way round - the first was
D121, where a piece of the board was written by a signal instead of derived.

### D123 - A screen swap takes any open question with it

Found by the session that built REJOIN GAME and deliberately left, because
nothing could reach it then. Fixed here because D122 made it reachable.

`Main._swap` closed the pause menu and nothing else. Both confirmation prompts
- "leave the game?" and "quit to desktop?" - are children of `Main` rather than
of the screen that asked, so one left open across a swap stayed on screen,
sitting over the next screen with its **yes still wired to the old one**.

Unreachable before, for a reason worth writing down: a screen changed only when
the player pressed something, and a prompt takes the keyboard while it is up.
Host migration broke that assumption - the host can walk out while somebody is
deciding whether to leave - and D122 adds another swap to that same path, to
the result screen.

Both prompts are hidden on every swap. `hide_panel` rather than a signal,
because the question is not being answered, it is being withdrawn: nothing
should act on a prompt the player never finished.

**What it rules out.** Assuming the player caused the screen change. Anything
`Main` owns on behalf of a screen has to be put away when that screen goes,
whoever ended it.

### D124 - A rematch is the host reopening the lobby, and nobody is waited on

Asked for on 2026-11-20, after the result screen's *Play again* turned out to do
nothing useful in a networked match (D122). The want is ordinary: a group of
friends who have just finished want another game without going back to the
title screen and finding each other again.

**The host offers; the others opt in; whoever does not is simply not in the
next match.** That shape was the owner's, and it is what makes the feature
safe. Two earlier designs were costed and rejected, and both failed on the same
thing - shared state about who wants a rematch:

- *Everybody must agree, then it starts.* The agreement is state, and it has to
  survive a player dropping and a host migrating. Worse, the natural gate -
  every player who is not away - starts the rematch the instant the last
  undecided player's connection drops, enrolling them in a match they never
  agreed to and throwing away the result they were reading. Avoiding that meant
  dropping away players from the rematch roster, which contradicts D110's
  "being away never costs you anything".
- *Any player can return to the lobby.* A client cannot: the host holds one
  authoritative state, and until the host resets it that state is the finished
  match, which is what every result screen is reading. A lobby does not exist
  until the host makes one, so a client's press can only ever be a request.

**Nobody can hold a rematch up, and there is no timer.** The new lobby's roster
is built from arrivals, not inherited from the finished match, so a player who
walks away from the keyboard is not in it - `why_not_start` has nothing to wait
on. That is D48 doing the work: *creating players on arrival removes the
possibility rather than guarding against it; there is no such thing as an
unclaimed slot*. It is also why no timeout was needed, and why there is no way
to kick somebody from the result screen. `kick_player` still covers the person
who joins the rematch lobby and then wanders off, which is the case D49 is for.

**It returns to the lobby rather than restarting the match in place.** Same
number of presses - the host's second press is Play in the lobby instead of
Start on the result screen - and it reuses paths that have been played:
`_seat_new_player` already records the Steam ID, `LobbyScreen` already relays
`match_started`, `_on_play_requested` already unlists the lobby, and
`_show_gameplay` already writes the rejoin record. Restarting in place would
have reimplemented all four. The lobby also shows who is coming, so the result
screen needs no roster of its own.

It is the shape the research pointed at: the lobby is the long-lived object and
a match is a thing that happens inside it. Steamworks has no rematch concept at
all - no such call, no documented flow - and a Steam lobby is destroyed only
when its last member leaves, so a rematch was always going to be the game's own
business conducted over its existing RPCs.

**Four RPCs, all carrying nothing.** `_rpc_ask_for_rematch` and
`_rpc_want_rematch` from a client, `_rpc_rematch_offered` and
`_rpc_rematch_joined` from the host. No arguments anywhere, so the sender's peer
id is the only statement of who is acting (D45).

`_rpc_want_rematch` is deliberately **not** a second `_rpc_introduce`. Reusing
that would have got the seating and the Steam ID for free, but it carries a
name, and `_on_introduced`'s duplicate guard - which exists because the lobby is
not a place to change your name - no longer applies once the reset has cleared
the peer map. A packet that says nothing cannot be used to say something else.
The host already knows who each peer is, from `_rematch_identities`.

`_rpc_rematch_joined` exists rather than inferring from `joined`, for the same
reason D116 added `_rpc_match_started`: a welcome cannot say which situation it
is. Clients are welcomed on a first join, on a rejoin and on every migration
reconnect, so inferring would mean `Main` guessing from which screen is up and
whether a migration is in flight - the exact shape of the fault D108 was.

**Asking decides nothing.** A client can tell the host it would like another
game; the host's result screen names whoever asked, and no gate anywhere reads
it. It exists because without it a client's result screen has no rematch
control at all until the host offers, which reads as a missing feature rather
than as waiting. If it ever gates anything it has become the first rejected
design again.

**The peer maps are rebuilt, not amended.** `HostSession.local_player_id()` *is*
`_player_by_peer[HOST_PEER_ID]`, and every request resolves through
`_require_player`, so a map left pointing at the finished match's slots does not
fail loudly - it makes every button answer nothing. `test_rematch.gd` drives a
whole year and a buy after a rematch for exactly this reason.

**Identities are captured before the reset, and only two fields are read.** A
seat built without its Steam ID cannot be reclaimed, so a rematch that lost them
would silently take reconnecting, REJOIN GAME and the seat-matching half of host
migration with it - all at once, and only inside a rematch. There is a named
test.

**A new seed every time**, for the reason D38 gives: `build_authority` writes the
chosen seed back into the settings, so a finished match's settings carry a
concrete number and reusing them would deal the same years out again. A typed
seed is not distinguishable from a generated one in `GameSettings`, so honouring
one is not an option the data supports.

**The result screen reacts to `match_started` by putting its own controls away,
never by changing screen.** `start_match` broadcasts to every peer rather than
to the seated ones, so a player who declined the rematch is told it went ahead.
That is wanted - their way in has to stop looking open, or it fails when pressed
- but swapping them onto a board would put them in a match they chose not to
join. Scoping the broadcast instead would have left them with a live button and
no way to know.

**The achievement reporter is kept, and its memory of the last match is not.**
It is created once per session (`Main._watch_for_achievements`) and a rematch
reuses the session, which is right: a rematch is a real match and its wins,
losses and net worth should count. But `_held_before` would still hold the
finished match's final position when the new match's first year resolved, and
`AchievementRules.for_year` reads it to decide whether a stalk that split or
went bankrupt was one you owned. `forget_holdings` closes that one-year window.

**An offer is said in words, not shown as a changed button.** Reported from
play the same day, once the rest of it worked: a client learned that the host
had gone back to the lobby only because its own button changed label, and a
player reading the final standings is not watching the buttons. The result
screen has one line for this, used by both sides — naming whoever asked, on the
host, and saying the host has restarted the lobby, on a client.

No sound goes with it. The only cues this game owns are the bull, bear,
bankruptcy and yeehaw ones, each of which already means something specific, and
inventing a new one is not a decision this change gets to make.

**The final board carries the same line**, on the row that already says the game
is over. A player who pressed View board to look the market over is still in the
finished match and would otherwise be the one person never told. The sentence
itself lives in `RematchNotice` rather than in either screen, because two copies
of it would mean two places to keep in step - and the board falling quietly
behind the result screen is exactly what D120 and D121 both were.

**What it rules out.** Any shared, synchronised record of who wants a rematch.
The moment such a thing exists it has to survive a disconnect and a migration,
and it has to decide what an away player's silence means - which is the question
that sank both rejected designs. Here the asks are host-local and advisory, the
offer is a single broadcast, and the only durable state a rematch creates is an
ordinary open lobby.

### D125 - A panel's size is decided up front, not by what is in it

Reported from play on 2026-11-20. The result card grew and shrank as you
switched between FINAL STANDINGS and YEAR BY YEAR, and the lobby card jumped
downwards when somebody joined. Neither showed a wrong number; both simply
would not hold still.

**Measured rather than eyeballed.** `tools/measure_panels.gd` lays both screens
out headless at 1280x720 and prints the card heights, which is how the real
causes were found - guessing from a screenshot would have produced a plausible
fix for the wrong thing. The result card was 285 tall on one tab and 279 on the
other. The lobby card was the same height for one player as for ten, because
the list already scrolls; what moved it was the **status line**, which wraps to
a second line as soon as it has a name in it.

**The result card now holds both tabs in one fixed-height wrapper.** They were
siblings, each with its own minimum height, so whichever was visible decided the
card. A `Pages` container with the height written once makes them two views of
one space, and each scrolls inside it. The height is 120 - what the standings
tab already used - so the card looks exactly as it did, it just stops moving.

**The lobby panel is sized to the title screen**, which was the second half of
the report: the lobby is the screen you arrive at from the title screen and the
two sat at noticeably different sizes. The marks are the top of the heading text
and the bottom of the panel against the bottom of QUIT TO DESKTOP. The title
screen runs 213 to 507 at 1280x720, so the lobby card is 296 tall, which lands
its heading at 214 and its bottom at 508.

One pixel out on each, and it cannot be better: the card is centred vertically,
the panel draws two pixels of padding above its heading, and that puts the two
marks a pixel either side of centre. One pixel is a sixth of a character here.

**That leaves a window on the roster rather than room for everybody.** How many
players fit is not a fixed number - a row grows once its Steam avatar arrives -
so the guarantee is the window, and the scrollbar shows the rest. A panel that
holds all ten at any row height would have to be taller than anything else the
game draws, which is the trade the owner chose against.

**A wrapping label is a panel that changes size.** `autowrap_mode` with
`max_lines_visible` gives a label the height of however many lines it needs
right now, so a sentence growing from one line to two pushes everything below it
down. The playing screen already knew this and reserved the space for two of its
labels by measuring the theme font - and the measuring was written out twice in
that one file. It is `ReservedLines` now, used three times: both of those and
the lobby's status.

The height has to be measured rather than written into the scene, because it
depends on the theme's font and size and would be silently wrong the moment
either changed.

**Checked, not trusted.** `tests/unit/test_panel_sizes.gd` asserts both cards
are the same height across a tab switch, across one player and ten, and across a
one-line and a two-line status, and that both still fit in a 720-tall window. A
layout that sizes to its contents is Godot's default, so this is exactly the
kind of rule that drifts back the moment somebody adds a row - which is what
`test_conventions.gd` exists for and the same argument applies here. See D60.

**What it rules out.** Letting a container decide a panel's size from what
happens to be inside it, anywhere the player can change what is inside it.

### D126 - The title screen says things at the foot of the window

Reported from play on 2026-11-20, immediately after D125 and from the same
complaint: pressing HOST ONLINE made the title screen jump. The panel rose and
QUIT TO DESKTOP sank, and the lobby arrived too quickly to read whatever had
appeared.

**The message was not Steam's.** It is ours: `Main` calls
`MainMenu.show_status("Creating a lobby...")` while the lobby is being made
(`src/ui/screens/main/main.gd`). Hosting online is the one path that is
guaranteed to say something, which is why that is the press that showed it.

**The cause is the same one as D125, one level up.** The message label was the
last row of `Centre/Shell`, between the panel and the quit button. `Shell` is
what `CenterContainer` centres, so a row appearing made the column taller and
the centring pushed everything outwards from the middle - the title and the
panel up, the quit button down. Clearing the message moved it all back. Nothing
was the wrong size; the column was simply a different size with a message in it.

**So the message is no longer part of the column.** It is a sibling of `Centre`
inside the root `MarginContainer`, shrunk to the bottom with
`size_flags_vertical = SIZE_SHRINK_END`. A `MarginContainer` gives each child
the same rectangle rather than a share of it, so the label overlays the bottom
of that rectangle and takes nothing from the column. However long the text is,
the column cannot move.

This is the owner's second suggestion, taken over the first. Fixing the label's
height would have stopped it *growing*, but not stopped it *existing*: a
reserved row inside the column still moves everything the first time, because
the column is taller than it was before the row was added. The only version
where nothing moves is one where the message is not in the column.

**The first version of this landed on top of the quit button**, and why is
worth more than the fix. It was measured at 1280x720, because that is what
`project.godot` says the window is - but **the interface is not laid out at the
window size**. The whole game is drawn into a 640x360 `SubViewport` and that
picture is enlarged by a whole number to fill whatever window the player has
(`src/ui/stage.gd`, D40 and D96). A screen is 640x360 and nothing else. So the
first attempt put the message at the foot of a screen with twice the room the
game really has, the tests agreed with it, and in play it sat across QUIT TO
DESKTOP. Reported from play the same day, with a screenshot.

The real numbers: the centred column runs 33 to 327 of 360, so the gap below
the quit button is **33 pixels**. That is the whole budget.

**So the message is not held to two lines by `ReservedLines`** (D125), which is
what the first version did. A reserved second line spends most of those 33
pixels on nothing. Left to find its own height and pinned to the bottom, a one-line
message - which is all but the longest of them at this width, around 105
characters - sits 15 pixels below the button at 342, and a two-line one grows
upwards into the gap and exactly fills it: 27 pixels of text plus the screen's
6-pixel bottom margin is the 33 there are, so a long message ends up adjacent
to the button rather than clear of it. That is the most the space allows without
either clipping the text or shrinking the column, and losing the end of a long
error message is worse than a tight fit on a rare one.

**Everything in `test_panel_sizes.gd` is laid out at 640x360 now**, which also
corrects the numbers D125 quoted: the lobby card is 296 tall from 32 to 328,
and the title screen's column runs 33 to 327. The alignment D125 describes was
right - both cards are centred in the same rectangle, so matching them holds
whatever that rectangle is - but it was measured in a space the game never
uses, and a test that measures in the wrong space will agree with a layout the
player cannot live with.

**`tools/measure_panels.gd` cannot measure this screen, and said so in
numbers.** It printed the title text at y=6 and the quit button at y=300 - a
span of 294, which is the right answer from the wrong place, so it looked
plausible. Two reasons, both worth knowing before trusting a `--script` run:
autoload names are resolved when a script is *compiled* and a `--script` run
has registered none, so the settings panel's `Audio` reference fails to compile
and takes the whole menu scene with it; and a screen added to the root keeps
its own minimum size rather than the window's, so positions come out measured
from the wrong origin. Standing an `Audio` node up by hand does not help - the
failure is at compile time, before any node exists.

So the title screen is measured from a GUT test, which starts the project
properly, and the tool now says in its header that it cannot do it. The tool
also sizes its screens, to 640x360, and with that its lobby numbers agree with
the test's: heading 34, card 32 to 328.

**Checked, not trusted.** `tests/unit/test_panel_sizes.gd` asserts that showing
a status, showing a message long enough to wrap, and clearing one again all
leave the heading and the quit button exactly where they were, that changing
tab does not move them either, and that neither a short message nor a wrapping
one lands on the column or runs off the bottom of the screen.

**`SupporterNote` is the tight case, and it is still a row in the column.**
The thank-you line for owning the supporter DLC makes a supporter's column 307
tall instead of 294, so it ends at 333 and the gap below it is 20 pixels rather
than 33. It is set once, from Steam ownership, before the screen is ever drawn,
so it never moves under a player - but it is why the screenshot that reported
this showed an overlap rather than the near-miss a non-supporter would have
seen, and it means **a message long enough to wrap overlaps the quit button by
six pixels on a supporter's screen**. One line always clears it, on both
screens, and that is asserted.

Nothing here fixes that, because every fix is a decision about how the screen
looks rather than about geometry: give everybody a blank line so the two agree
and the lobby in D125 needs re-matching; move the thank-you out of the column
and it is no longer part of the title block; clip the message to one line and
the end of a long error is lost, which is the one time it is worth reading.
The exposure is a single message - `Content problem: ...`, with an authoring
error in it - so it is recorded rather than traded away blind.

**What this does not fix either.** The message is still only up for as long as
the title screen is - hosting succeeds and the lobby replaces it, so "Creating
a lobby..." is still too brief to read. That is a different complaint about a
different thing (how long a transient message lives) and it is not what this
decision is about.

**What it rules out.** Putting anything in the centred column that appears and
disappears while the player is looking at it.

## StalkleHeads

### D127 - The base game is guarded by a hash of one recorded match
**2026-11-21 · Accepted**

Build phase S0 of [stalkleheads-design.md](stalkleheads-design.md) (§11), property
P5. `tests/unit/test_golden_history.gd` plays a seeded 99-year base-game match,
writes down everything the year pipeline decided as one block of text, and
compares the text's sha256 with a hash written into the test. It was recorded
before any StalkleHeads code existed, because S3 moves the back half of
`YearResolver` into a shared `YearSettlement`, and a guard written after that move
could only prove the base game matches itself as it then is.

**What goes into the record, and why each part is there.**

- **Every year, every stalk:** price before and after, base delta, event delta,
  split, bankruptcy. This is the front half of the year, which S3 does not move,
  but which StalkleHeads must not disturb either.
- **The mood and the event** (id, target and price change). These are the two
  draws the rest of the year reads, so a change in the order of random draws
  shows here first.
- **Per player, every year:** dividend, the loan assessment (balance before and
  after, paid, misses, penalty, interest, the new minimum, default), cash, net
  worth as stored on the player and as reported in the `YearResult`, bankruptcy,
  the whole loan state and the holdings. Loans, net worth, standings and the
  game end are exactly what S3 moves, so they are recorded in full rather than
  summarised.
- **Standings and the end:** the ranking order, whether the match is over, whether
  this was the final year, and the winners.
- **The scripted players' own actions**, and whether each was allowed. Legality
  is a rule too (`TradeRules`, `LoanRules`), and recording it means a change in
  what is allowed cannot hide behind the script quietly skipping an action.

**The players are scripted to reach the back half.** Prices alone would guard the
part S3 does not touch. So there are three players: one who rotates through the
board every fourth year, one who borrows the maximum in year 2 and never pays
(10% penalty, 15% penalty, then seizure in year 5), and one who borrows, misses
year 6 once, and overpays in year 10 so the clamp in `apply_payment` runs. Every
action goes through the sim-layer validation first. The test also asserts that the
match really contained a split, a bankruptcy, penalties, exactly one default and a
paid-off loan, so an edit to the script that stopped reaching one of them fails
loudly rather than leaving the hash guarding less.

**What is deliberately left out.**

- **Display text.** The mood is written as the fixed word `BULL` or `BEAR`, not
  `MarketMood.label()`; event flavour text and stalk names are not recorded.
  Rewording what a player reads is not a rule change and must not break this.
- **Floats.** None are written. The loan maths uses floats internally but every
  value that leaves it is an `int`, and only those are recorded.
- **Dictionary order.** Stalks, players and holdings are all written in sorted-id
  order, never in the order a `Dictionary` happens to iterate.

**Shipped content is part of the record.** The match runs on `ContentLibrary.load_from()`
and its real event pool, the way `LocalSession.build_authority` builds a match,
rather than on the synthetic events in `StalksFixture`. The guard is about the base
game as players get it, and a stalk's ranges or an event's price change are rules
of that game. The cost is that a deliberate content edit also breaks the hash; that
is intended, and is handled the same way as any other deliberate change.

**When it breaks.** The header of the test says what to do: find what moved first
(the failure message names a file, `user://golden_history_record.txt`, holding the
full record, which can be diffed against the same file from the last passing
commit); fix the code if the change was not meant; and only if it was meant,
update `GOLDEN_HASH` and add an entry here saying which rule changed and why.

**Proved to bite** when it was written: the hash changed when split rounding was
switched from up to down, and again when one player's net worth was nudged by 1 in
year 50 alone. Both perturbations were reverted.

**Rules out:** treating a failure of this test as a number to refresh. A new hash
with no entry here is the drift CLAUDE.md warns about.

### D128 - StalkleHeads content sits beside the base game's, and the validator guards it
**2026-11-21 · Accepted**

Build phase S1 of [stalkleheads-design.md](stalkleheads-design.md). Company
fundamentals are a new resource, `CompanyProfile` (`src/data/company_profile.gd`,
one `.tres` per company in `src/data/companies/`), and industries are another,
`IndustryDefinition` (`src/data/industries/`). Neither touches `StalkDefinition`.

**Why beside, not inside.** §3.2 leaves the choice to the code and §10 recommends
it: adding fields to `StalkDefinition` would edit the ten shipped `.tres` files,
which are part of the record `test_golden_history.gd` (D127) guards. Separate files
mean the base game cannot read StalkleHeads content even by accident, and
`ContentLibrary.load_from()` still loads exactly what it did.

**`CompanyProfile.industry`, not `StalkDefinition.industry`.** The stalk field was
reserved for this mode, but using it would mean editing base-game content to fill
it in, and eight of the eighteen companies have no `StalkDefinition` at all. So the
reserved field stays unused, and S3 or S8 may remove it. A profile for a company the
base game ships has the stalk's `id`, `display_name` and `ticker`; a test checks
they agree, so the duplication cannot drift silently. How the eight new companies
get board rows is S3's to decide.

**The validator.** `ContentLibrary.load_fundamentals()` loads both directories and
re-runs `validate()`, which now also refuses: an industry id that does not resolve
(the typo §3.2.1 is about), an industry with fewer than two members, a missing or
duplicated ticker, duplicate ids, and out-of-range fundamentals. An industry with
two members is **reported** in a new `warnings` list and allowed, because §3.2.3
makes three the target and two the floor. The checks run only when there is
StalkleHeads content loaded, so base-game validation is unchanged.

**Tickers for the five new named companies** (Landlords United, Video Chrome,
Meowly, Chichen Pizza, Farms+) are not in the design. The validator needs one, and
choosing a real symbol is the owner's to do. So they use the same obviously
temporary pattern §3.2.3 gives the placeholders, continuing the letters within each
industry: `FINA`, `TECB`, `TECC`, `FODB`, `FODC`. They are to be replaced, exactly as
`TRNA` and the rest are.

**Industry ids** are the short ones the §3.2.4 table uses: `energy`, `transport`,
`financial`, `consumer`, `tech`, `food`. The display names are the owner's (§14).

**Rules out:** filling in `StalkDefinition.industry` for this mode; an industry
check that pushes an error at runtime instead of refusing the content at load.

### D129 - A company's year 0: STEADY, a 12% margin, 1,000 shares
**2026-11-21 · Accepted**

The design gives each company's opening EPS but not the rest of its year-0 state.
Taken from the balance probe (Appendix A), which every measured figure in the design
came from, and recorded so S2 can reproduce it:

- **Regime STEADY, in its first year** (`years_in_regime` 0). STEADY's premium is 0,
  so with no sentiment and no industry standing the multiple is exactly the base
  12.5 and the opening price is `EPS x 12.5`, as §3.2.4 says it is.
- **Margin 12.0%** for every company, STEADY's target, so the margin does not drift
  in a company's first steady year. Authored per company in the `.tres` as
  `starting_margin_percent`, so a company can be given its own later.
- **1,000 shares outstanding**, also authored per company. Revenue at year 0 is
  derived: `profit x 100 / margin`, where `profit = EPS x shares`.
- **No event carry and no flow.**

The opening price is computed from the authored EPS directly, not from
`profit / shares`, so that a float round trip cannot cost a company a coin of its
opening price; `test_company_content.gd` checks all eighteen against the table.

**Rules out:** a separately authored starting price.

### D130 - Revenue, profit and margin are floats inside the sim
**2026-11-21 · Accepted**

The design contradicts itself here. §3.7's table lists revenue, expenses and profit as
`int`. The same section's rule, in bold, is that a float becomes money in **exactly
two places** per company per year, the price and the dividend. An `int` revenue
compounding by a float growth rate needs a third truncation every year, and so does
an `int` profit. §3.3 also says the margin moves a third of the way "truncating",
which is left over from the first draft's fixed-point scheme (§3.7 says that scheme
was dropped).

**Decided:** the two-truncation rule wins. `CompanyState.revenue`, `profit` and
`margin_percent` are `float`, and the margin step is not truncated. That is also
what the probe does, so S2 can reproduce its numbers. Revenue and profit are
accounting figures that are never paid to anybody; when S7 shows them as `$86,142`,
that is a display rounding in the shared formatter, not a rule.

**Rules out:** adding a truncation anywhere in the price path beyond
`PriceIdentity.price_of` and `DividendRules.dividend_per_share`.

### D131 - How the regime roll counts years and draws
**2026-11-21 · Accepted**

§3.3 states the matrix and its modifiers but not three details, taken here from the
probe:

- **The roll is `randi_range(1, 100)`**, one call, every time. The adjusted roll is
  `roll - (quality - 50) / 5 + ageing`, in float, then walked along the row's
  cumulative weights. It is clamped to 1-100 first; with rows that sum to 100 the
  clamp changes no outcome.
- **`years_in_regime` counts the years beyond the year a regime was entered.** A
  company in its first year of GROWTH has 0 and is not aged; in its second it has
  1 and the roll gets +10. So the stay chance in GROWTH runs 58, 48, 38, 28 - the
  fourth straight year is below even odds, which is §3.3's "four straight growth
  years and the odds have turned over". Recovery counts the same way at 12 points.
  (Since D151 GROWTH's row starts at 42, so the run is 42, 32, 22, 12; the counting
  is unchanged.)
- **The roll uses the regime the company is leaving**, and the growth band uses the
  regime it lands in.

`RegimeRules.regime_for_roll` is a plain function of the roll so the odds can be
enumerated exactly (`RegimeRules.odds`), which is what the tests assert and what
the Company tab can later publish.

**Draws are fixed per call**: a regime roll is one call, earnings season is two (the
regime, then the growth roll), an industry is one. So the stream never depends on
what happened. One `randi_range` call is not always one step of the generator's
state (Godot's bounded draw can reject and redraw), which is why the tests compare
against a twin RNG making the same calls rather than counting steps.

### D132 - Event carry and flow, where the probe and the design disagree
**2026-11-21 · Accepted**

**Event carry follows the design, not the probe.** §3.5 writes
`event_carry = previous * 0.50 + this_year_event_delta`: last year's halves and this
year's lands in full. The probe adds the event first and then halves the sum, so a
new event counts at half strength in its own year. The design is the specification,
and it is the reading the §3.5 ledger example assumes ("last year's event, faded:
half of year 6's -12"). **S2 should expect its numbers to differ from the probe's
because of this**, and should not change the code to match the probe.

**The flow clamp uses the magnitude of fair value.** §3.5 writes
`clamp(flow, -0.05 * fair_value, +0.05 * fair_value)`, which inverts if fair value
goes negative (it can, down to -40). `PriceIdentity.flow_limit` uses
`abs(fair_value) * 0.05`, as the probe does.

**Flow's input** is `net_shares_traded / shares_outstanding * 100 * 0.55`, with the
current shares outstanding. S1 takes the net figure as a plain `int`; S4's desk is
what will supply it, summed with the players' own, which count identically (§3.10).

### D133 - The ledger in whole coins, with two lines the design's example lacks
**2026-11-21 · Accepted**

`PriceLedger.between(before, after)` explains a price move in integer lines that sum
**exactly** to the move, which is P1.

**How float terms become whole coins.** Each line is the change in
`int(running total)` as the float terms are added one at a time, starting from last
year's posted price and ending at this year's. That telescopes, so the lines sum to
the delta by construction, with no rounding step of its own and no remainder parked
on one line. The `int()` calls are a readout, not money; they do not add to D130's
two truncations. A split between the two years is already in last year's posted
price, so it needs no line.

**The fair-value change is split** as `(eps1 - eps0) * m0` for earnings, then
`eps1 x` the change in each of the multiple's three moving terms: sentiment,
industry standing, regime premium. That is exact algebra while no clamp is hit.

**Two lines the §3.5 example does not show:**

- **Regime premium.** The example lists earnings, sentiment, standing, the two event
  lines and flow, but the multiple also moves when the regime changes, so it needs a
  line or the example would not balance. S7 may print it merged into "earnings".
- **Valuation limits.** What the 4-30 multiple clamp or the -40/1,200 fair-value
  clamp took off. It is zero unless a clamp was hit in either year, so float noise
  cannot print a stray coin on it.

**Rules out:** a ledger that balances by adjusting whichever line is largest.

### D134 - After a split the price may sit one coin above the identity
**2026-11-21 · Accepted**

§3.6 says a split halves the price **rounding up** (D22's rule, kept) and that the
identity still holds. Both cannot be exactly true for an odd price: 333 halves to
167, while `int(fair_value/2 + event_carry/2 + flow/2)` is 166. The design's worked
example uses 320, which is even.

**Decided:** keep rounding up, as §3.6 says explicitly. The posted price may then sit
at most one coin above the identity until the next `reprice`, which sets it from the
identity again. The split is value-neutral to within that coin per share (a holder's
shares double too, which S3 does), and the next year's ledger absorbs the coin in
its first line. Tested in `test_company_fundamentals.gd`.

### D135 - The dividend scales are the published ones, and policy 35 matches the old table to a hundredth
**2026-11-21 · Accepted**

§3.10a says a company with the neutral policy of 35 "pays exactly what the previous
draft's single table paid in every regime". It does not: the previous table was
GROWTH 0.10, STEADY 0.35, SLOWING 0.30, DECLINE 0.20, DISTRESS 0, while 35% times
the published scales (0.30, 1.00, 0.85, 0.55, 0.00) is 0.105, 0.35, 0.2975,
0.1925, 0. So it reproduces STEADY and DISTRESS exactly and the other three to
within a hundredth, which can differ by a coin per share after the truncation.

**Decided:** keep the published scales. They are the table §3.10a specifies and
the ones the v3 probe measured §2.6 with; changing them to make the sentence true
would change the measured balance. The test asserts what is true: the ratio is the
policy times the published scale, STEADY pays the policy exactly, and each regime is
within 0.01 of the old table.

**Also decided here, from the probe:** the long-match damping multiplies the
regime's **own** growth roll, of either sign, before the retention factor; neither
applies to the industry's share. So `growth = roll x damping (x retention if
positive) + industry_performance x beta / 100`.

**The design decisions S1 builds.** The entries below record them.

[stalkleheads-design.md §15](stalkleheads-design.md) lists the decisions the owner
accepted on 2026-11-21 and says each goes in here in the phase that builds it. These
are the ones phase S1 built. Each is short because the full reasoning, with the
measurements, is in the section named; that section is the source if the two ever
disagree.

### D136 - The price is an identity, not a convergence (§15 A, A2)
**2026-11-21 · Accepted**

`price = int(fair_value + event_carry + flow)`, and nothing else: no term pulling
the price toward fair value and no hidden noise. A player who can compute fair
value would otherwise have a mechanical arbitrage - buy below it, wait for the pull
(§2.2). The general form (A2): **any bounded, mean-reverting quantity in the price is
an arbitrage**; three were found (convergence, mean-zero noise, the valuation
premium). Check any future price term against this. Code: `PriceIdentity`,
`CompanyState.reprice`.

### D137 - Earnings are the input; P/E is a readout and is never stored (§15 B)
**2026-11-21 · Accepted**

A company's earnings per share is what the model moves; the multiple is computed
from published inputs; P/E and earnings yield are derived wherever they are shown
and exist nowhere in state (§2.5, §3.7). `CompanyState.earnings_per_share()` is
itself derived from profit and shares, so a split cannot leave it stale.

### D138 - Money is `int`, ratios are `float`, with two truncations (§15 B2)
**2026-11-21 · Accepted**

The first draft's fixed-point scheme is dropped. A float becomes money in exactly two
places: `PriceIdentity.price_of` and `DividendRules.dividend_per_share`, both
`int()` toward zero. This is the pattern `LoanRules` already uses (§3.7). The price
path uses only `+ - * /` and clamps, never a transcendental function, because only
those are guaranteed identical across machines. D130 is where this rule met a
contradiction in the design and won.

### D139 - Five earnings regimes with a published transition matrix (§15 D, D2)
**2026-11-21 · Accepted**

GROWTH, STEADY, SLOWING, DECLINE and DISTRESS, an enum (`EarningsRegime`) because
code branches on each. The matrix, the growth bands and margin targets, the quality
bias, ageing on GROWTH and SLOWING, recovery from DISTRESS and the long-match damping
ladder are in `RegimeRules`, all copied from §3.3. The model is Animal Crossing's
turnip market: named patterns and a published table of which follows which
(Appendix B). **D2:** the regime premiums are 40% of the first draft's spread
(+0.6 / 0 / +0.24 / -0.6 / -1.4); at the wider spread a low-P/E rule took 63.7% of
25-year matches, at this one 27.0% (§2.2). D131 records the roll's details.
**Amended by D151:** GROWTH's row and GROWTH's premium changed; the other four rows
and premiums are as written here.

### D140 - A split needs no new rule, and splits above 300 (§15 E, E2)
**2026-11-21 · Accepted**

Doubling shares outstanding halves earnings per share and so halves fair value;
halving event carry and flow with it keeps the identity. The split is value-neutral
by construction (§3.6). **E2:** StalkleHeads sets its own scale - the threshold is
300, not the base game's 150, because at 150 a market whose earnings mostly grow
split 5.7 times a ten-year match; at 300, 1.8. Rounding stays **up** (D22), which
D134 reconciles with the identity. Companies start at different prices (30 to 150)
rather than all at 100. Code: `CompanyState.split_if_above`.

### D141 - An industry needs three members, two is the floor, and it is content (§15 P, P2)
**2026-11-21 · Accepted**

An industry of one is the company in it wearing a hat; three survives one bankruptcy
without falling below two mid-match (§3.2.3). Six industries of three, decided by
the owner. **P2:** `industry` is a `StringName` resolved against `IndustryDefinition`
resources, not an enum, because the code treats every industry identically and only
its data differs - so adding one is adding a file (§3.2.1). The content validator
catches the typo that choice risks (D128).

### D142 - Order flow is in the price, clamped at 5% of fair value, persistent (§15 Q)
**2026-11-21 · Accepted**

`flow = previous * 0.70 + net_shares / shares * 100 * 0.55`, clamped to +/-5% of fair
value. Persistent rather than reverting, so a price below fair value is not a
reliable dip to buy (it may be a crowd still leaving). The clamp is a constant a test
asserts: at 18% the leading strategy wins 61.3% of matches, at 5% 23.2% (§2.4,
§3.10). The cost in long matches is unsolved and is S9's (§13.2). S1 takes the net
shares as an input; S4's desk supplies them.

### D143 - Dividends are a payout ratio of earnings, by company policy (§15 R, R2)
**2026-11-21 · Accepted**

`dividend = int(eps x policy / 100 x regime scale)`, with each company's
`payout_policy_percent` authored on its profile and the scales GROWTH 0.30, STEADY
1.00, SLOWING 0.85, DECLINE 0.55, DISTRESS 0 (§3.10a). Decided by the owner. **R2:**
paying out costs growth - `retention = 1 + (35 - policy) / 100` multiplies positive
revenue growth only - or the highest payer would simply be the best stock, since a
dividend paid does not lower the price in this model. D135 records the one
inconsistency in the section.

**Phase S2, the balance tool.** The entries below are the choices it made.

### D144 - The balance tool plays the real sim through a stand-in year kept in `tools/`
**2026-11-21 · Accepted**

`tools/balance_report.gd` (phase S2, [stalkleheads-design.md](stalkleheads-design.md)
§11) has to play whole StalkleHeads matches, but the year pipeline is S3's and does
not exist. So `tools/balance/stand_in_year.gd` strings the S1 classes together in §4's
order: industry year, earnings season, valuation, the event, prices, index and mood,
bankruptcy, splits, dividends. Every price, earnings figure and dividend comes from a
call into `src/sim/`. The file adds only three things the sim does not have yet (the
event, the index, a bankruptcy flag), and each is marked as stand-in.

**Why `tools/` and not `src/`.** Anything in `src/` is something the game may call.
A half-pipeline there is what S3 would have to work around or delete, and it would be
tempting to grow it into the real one without the `YearSettlement` split §10.2 asks
for. In `tools/` nothing in the game can reach it. `YearResolver` is untouched.

**No sim helper was needed.** Everything the driver calls already existed in S1, so
nothing was added to `src/sim/`.

**When S3 lands:** point `tools/balance/balance_match.gd` at `EarningsYearResolver`,
delete `stand_in_year.gd`, and re-run the tool. A gap between the two runs is then a
difference between the stand-in and the real pipeline, and worth explaining before
anything is tuned.

**Rules out:** a year driver in `src/`; changing `YearResolver` for the tool.

### D145 - The balance tool draws the market and the players from two streams
**2026-11-21 · Accepted**

The probe drew everything from one generator, so the market a strategy was measured
on depended on which other strategies were playing: RANDOM draws, and its draws shift
everything after them. The tool lets you pick strategies on the command line, which
would then change the market under the ones you kept.

**Decided:** the market's generator is seeded with the match seed; RANDOM draws from a
second one seeded with `hash("balance players <seed>")`. No other strategy draws.
Running a subset leaves every price unchanged, and `test_balance_smoke.gd` checks it.

Consequence: no seed reproduces a probe match (the probe uses Python's generator in
any case). The tool and the probe can only agree in distribution, which is how they
are compared (Appendix A).

### D146 - TREND reads last year's earnings growth, split-adjusted; the probe's did not
**2026-11-21 · Accepted**

§2.1 defines `TREND` as "hold the three whose published earnings per share grew
fastest". The tool measures last year's growth of **profit**, which is the growth of
earnings per share restated for any split (profit does not change when shares
double). A company with no previous report has no growth figure, so in year 1 TREND
takes the first three companies by id.

**The probe measured something else, by accident.** It appends each year's earnings
per share to a history *before* updating profit, then compares the current figure
with the second-to-last entry. From year 3 on that is growth over **two** years, and
the stored entry predates the most recent split, so a company that split looks as if
its earnings halved. TREND in the probe was a weaker, noisier signal than the rule it
was named for.

**What it changes, measured.** In a copy of the probe with only this corrected
(outside the repository, like the probe), TREND's ten-year win share goes from 23% to
51% with no flow; in the §2.6 configuration (flow at 5%, the desk, FOLLOW) from about
22% to 46%. The tool measures 48.5%. See D149.

**Rules out:** reproducing the probe's two-year comparison to match its numbers.

### D147 - Where the stand-in year and the probe differ, the design wins
**2026-11-21 · Accepted**

Four places the probe and the design disagree, all decided for the design:

- **Event carry** lands in full in its own year (D132, decided in S1).
- **A constituent that goes bankrupt counts -100 in the index** (§3.9). The probe used
  its raw move, which is below -100 when the price goes negative.
- **The event's sign follows last year's mood** (§10.2), the bull bag in year 1. The
  probe used `sentiment >= 0`, which differs only when last year's index move was
  exactly zero.
- **No zeroing of tiny event carry.** The probe set carry under 0.01 to zero;
  `PriceIdentity` has no such rule and the tool adds none.

**Kept from the probe, because the design has nothing yet:** the event's shape (one a
year, on a living company chosen uniformly, +5 to +20 after a bull year, -5 to -25
after a bear one) stands in for `EventPool`, which S3 wires to StalkleHeads.

### D148 - Strategy details the design leaves open
**2026-11-21 · Accepted**

§2.1 gives each strategy one line. The tool needed more, and took the probe's choice
where it had one:

- **Trading:** at the start of each year a player sells everything and splits its cash
  equally across its targets at last year's closing price, whole shares only. HOLD
  buys every living company in year 1 and never trades again. BOND buys BERRY BONDS,
  whose price and coupon are read from the shipped `berry_bonds.tres`. Starting cash
  is `GameSettings`' default, 10,000.
- **MOMENTUM and CONTRARIAN** rank by last year's move in **coins**, before splits:
  the board's Yearly Change column, which is what a player sees.
- **INCOME** ranks by last year's dividend per share over price. Nothing is paid
  before year 1, so year 1 picks the first three by id.
- **LOWPE and HIGHPE** skip a company with earnings at or below zero. If none is left,
  LOWPE takes the first three by id and HIGHPE does not trade that year.
- **Ties break by company id**, everywhere.
- **FOLLOW is absent.** It copies the best NPC trader, and there is no desk until S4.
- **Flow is off by default**, because without the desk the comparison target is the
  probe's no-flow run. `--player-flow` passes the players' own net buying into the
  flow term, as §3.10 says it will count once the desk exists.

### D149 - P4 does not hold at ten years once TREND is measured correctly
**2026-11-21 · Resolved by D151 on 2026-11-22**

The tool's first job was to reproduce the probe. It does, once the probe is given the
same corrections (D132, D146, D147, and FOLLOW removed): the two implementations then
agree to within sampling noise on every figure. Appendix A of
[stalkleheads-design.md](stalkleheads-design.md) has the table. That agreement is the
evidence that neither S1 nor the tool has a bug of its own in what was compared.

What it shows is that **§2.6's headline was wrong**. With TREND as §2.1 defines it, the
leading strategy wins 48.5% of ten-year matches with no flow (47.3% over 4,000 seeds),
against the 30% P4 ceiling. Every configuration measured fails:

| Configuration | Leader, 10 years |
|---|---|
| The tool, no flow | TREND 48.5% |
| The tool, flow from player trades only | TREND 45.0% |
| Probe, §2.6 setup (flow, desk, FOLLOW), TREND corrected | TREND 46.2% |
| The same, also with D132's carry | TREND 40.0% |

At 25 years TREND wins 58.8%. The likely reason: a company whose earnings grew fastest
last year is usually in GROWTH, GROWTH is the stickiest good regime (58% stay in its
first year), and next year's revenue grows 15-35% again. The regime persists, it shows
in published earnings, and TREND reads it directly. That is an explanation, not a
measurement; S9 should confirm it before acting on it.

**Not tuned.** S2's brief forbids closing a gap by tuning, and the levers (GROWTH's
stay chance, ageing, the growth premium, the band widths) are balance decisions for S9
and the owner. Recorded so nobody quotes §2.6's 22% again; §1, §2.6 and Appendix A of
the design carry a note pointing here.

**Swept, 2026-11-22 (still open).** At the owner's request two levers were swept with
the tool's overrides (D150): pricing expected growth into the multiple (a wider
regime premium) and making GROWTH runs less predictable (a lower stay chance, and
stronger ageing as a variant). The full table is in the design's Appendix A, "The
sweep of candidate fixes". In short:

- **No single lever passes P4 over 4,000 seeds.** Widening the whole premium spread
  brings the LOWPE exploit back: 71% of 25-year matches at twice today's spread, and
  LOWPE leads even at ten years at the first draft's spread. Stay 34 alone measured
  30.8%.
- **Three combinations pass at ten years**, with no other strategy over 30%: stay 34
  with GROWTH premium 0.9 (27.3%), stay 42 with GROWTH premium 1.2 (27.9%), and stay 26
  (LOWPE 27.1%). Each passes by two to three points.
- **Every one is partly a design change.** A lower stay chance edits §3.3's matrix and
  its stated stationary mix, which `test_regime_rules.gd` asserts. A higher GROWTH
  premium partly reverses D2. Stay 26 changes what GROWTH is.

**Recommendation: GROWTH row `[42, 19, 28, 8, 3]` and GROWTH premium 1.2, other
premiums unchanged.** It is the passing setting closest to the design's other
figures: bull rate 54.4%, 1.63 splits per match, ten-year bankruptcies unchanged, and
RANDOM ending above its starting cash. It must be re-measured with the desk and flow
(S4) before it is called settled, because its margin is about two points. The owner
decides. Nothing in `src/` has changed.

### D150 - Balance levers are overridden in the tool, never in `src/`, for a sweep
**2026-11-22 · Accepted**

The owner asked for D149 to be answered by measurement first: sweep candidate fixes,
then decide. A sweep needs to change numbers that are constants in `src/sim/`
(`RegimeRules.PREMIUM`, `TRANSITION`, `AGEING_POINTS`), and the owner has not chosen
one yet, so the constants must not move.

**Decided:** `tools/balance/levers.gd` holds the overrides, set from the tool's
arguments (`--premium`, `--premium-scale`, `--growth-stay`, `--ageing`). They reach
the real code in two ways:

- **The premium** goes in through `CompanyState.reprice`'s industry-performance
  argument, shifted by `(override - published) / STANDING_GAIN`. Standing is
  performance times that gain, so the multiple comes out exactly as if the premium
  table held the override, and its clamp sees the same sum. Only the company's
  `industry_standing` readout is wrong, and the tool never reads it.
- **The regime roll** is done in the tool with the overridden matrix and ageing,
  using `RegimeRules.quality_bias` and `age_shift` for everything not overridden;
  the accounts then move by the real `CompanyState.move_accounts`. The draws are the
  real ones in the real order.

The roll is the one piece re-implemented, which is the risk a parallel
implementation always carries (Appendix A). So with every lever **set** to its
published value the override path runs, and `test_balance_smoke.gd` asserts it gives
exactly the same matches as the real path.

**How a new GROWTH stay chance is spread.** The weight removed from (or added to)
the stay column goes to the other four in proportion to the published row's
14 : 20 : 6 : 2 (the row at the time of the sweep; since D151 the published row is
`[42, 19, 28, 8, 3]` and the override respreads in its proportions), in whole points
by largest remainder, ties to the better regime.
So 50 gives `[50, 17, 24, 7, 2]`, 42 `[42, 19, 28, 8, 3]`, 34 `[34, 22, 32, 9, 3]`:
the row keeps the published lean toward SLOWING and STEADY. Ageing overrides apply
to GROWTH and SLOWING together, as §3.3's ageing does.

**When the owner picks a fix**, it is made in `src/sim/` as an ordinary change with
its tests, and these overrides stay for the next sweep.

**Rules out:** mutable statics or a tuning object threaded through `src/sim/` for a
measurement the game itself never needs.

### D151 - GROWTH stays GROWTH 42% of the time, and its premium is 1.2
**2026-11-22 · Accepted (decided by the owner)**

The fix for D149, chosen from the balance sweep in Appendix A of
[stalkleheads-design.md](stalkleheads-design.md) and adopted by the owner.

- **`RegimeRules.TRANSITION`, GROWTH's row:** `[58, 14, 20, 6, 2]` becomes
  `[42, 19, 28, 8, 3]`. The 16 points taken off the stay column are respread across
  the other four in the published row's proportions (D150). With ageing, GROWTH's stay
  chance over a four-year run is 42, 32, 22, 12. The stationary mix moves from
  19.8 / 27.3 / 21.5 / 21.7 / 9.8 to 15.1 / 28.8 / 22.8 / 22.9 / 10.4.
- **`RegimeRules.PREMIUM`, GROWTH:** 0.6 becomes 1.2. The other four premiums are D2's,
  unchanged.

**Why.** A GROWTH run that sticky let a player who buys last year's fastest earnings
growers win 47% of ten-year matches. Shortening the runs makes "it grew last year"
a weaker promise about next year. Paying more for a growth year then prices in the
growth that does persist, so a TREND buyer is not getting it for free. Neither lever
passed alone. Widening the whole premium spread instead brought back the LOWPE
exploit D2 was made to remove.

**Measured with the published values, 4,000 seeds, no flow:**

| | 10 years | 25 years |
|---|---|---|
| Leader | TREND 27.9% (was 47.3%) | LOWPE 49.0% (was TREND 58.2%) |
| TREND / LOWPE | 27.9% / 25.4% | 33.5% / 49.0% |
| Strategies winning at least 4% | 6 | 4 |
| Bull-year rate | 54.4% (was 56.1%) | 59.6% |
| Splits / bankruptcies per match | 1.63 / 0.64 (was 2.10 / 0.61) | 3.95 / 2.01 |
| RANDOM's median over the leader's (P3) | 0.62 (was 0.46) | 0.23 |

These are the sweep's `stay 42 + G1.2` figures exactly. Run through the real code,
the tool reproduced them to the last digit, which also confirms the sweep's override
path (D150).

**What it costs.** It is a design change, not only a parameter: §3.3's matrix and
its stationary mix change, and GROWTH's stay chance is now below STEADY's 50, so a
growth year is more often a spell than a state. It partly reverses D2, for GROWTH
only. The market is a little flatter: fewer splits and a slightly lower bull rate.

**Still to confirm.** The margin under P4's 30% ceiling is about two points, and the
measurement has no NPC desk and no flow. §2.6 measured flow as costing about a point.
**S4 must re-run the tool with the desk before this is called settled.** At 25 years
LOWPE leads at 49%, which §1 records rather than asserts.

**Code:** `src/sim/regime_rules.gd`. Tests updated to the new values:
`test_regime_rules.gd` (the row, the stationary mix, the ageing run, the premium),
`test_company_fundamentals.gd` (the multiple's four terms), `test_price_ledger.gd`
(the regime-premium line). The base game is untouched; `test_golden_history.gd` passes
unchanged.


### D152 - StalkleHeads has its own year pipeline, sharing the back half (§15 I)
**2026-11-22 · Accepted**

The year is two pipelines that share one class:

| Class | What it is |
|---|---|
| `YearResolver` | The base game's year, unchanged in behaviour |
| `EarningsYearResolver` | StalkleHeads' year: [stalkleheads-design.md](stalkleheads-design.md) §4 steps 1-10 |
| `YearSettlement` | What both share: loans, net worth and standings, game end, then closing the year (ready flags, history) |

**Why.** StalkleHeads reorders the year: the mood moves from first to last, the event
moves before prices, there is one bankruptcy pass instead of two, and splits and
dividends follow different rules. Doing any of that inside `YearResolver` needs
`if mode ==`, which §13.3 of the design names as the sign that the modes have stopped
being additive. The back half does not differ, so it is shared rather than copied.

**How the extraction was done.** A pure move: steps 8-10 of
`YearResolver.advance_year` and `_process_loans`, moved into `YearSettlement` with the
same statements in the same order, no new draws from any RNG. `YearResolver` now ends
with `YearSettlement.settle(state, result)`. `tests/unit/test_golden_history.gd`
passed with `GOLDEN_HASH` unchanged, which is the proof (D127).

**Rules out.** Hooks or mode checks in `YearResolver`, `YearSettlement`, `TradeRules`,
`LoanRules` or `EventPool`. `test_earnings_year_resolver.gd` scans those files for
`settings.mode` and `market != null` and fails if either appears.

**Code:** `src/sim/year_settlement.gd`, `src/sim/year_resolver.gd`,
`src/sim/earnings_year_resolver.gd`.

### D153 - The mood is derived from the index, and read only a year late (§15 C)
**2026-11-22 · Accepted**

`EarningsYearResolver` sets the year's mood at step 7, after every price is final:
BULL exactly when the index move is above 0, so a flat year is BEAR. The same step
sets next year's sentiment, the index move clamped to ±20. This year's prices are
valued on the sentiment carried in from last year.

**Why.** Design §3.1 and the owner's note: the mood should be what the market did.
Reading last year's figure is what stops this being circular, because this year's
figure does not exist until prices do.

**Rules out.** Anything before step 7 reading this year's mood or index move. Two
tests guard it: every company's `sentiment` this year equals the figure carried in,
and flipping last year's mood label (with no events to draw) changes no price.

**Also pinned:** the derived bull rate over 200 ten-year seeds sits between 45% and 65%.
It measures 54.5% over 4,000 seeds (D161).

### D154 - The event comes from last year's mood bag, and the index carries none (§15 I2)
**2026-11-22 · Accepted**

The event is drawn at step 4, before prices, from the bag of **last year's** reported
mood. Year 1 has no last year, so it draws from the bull bag (design §14 q14). The pool
is the shipped `EventPool`, holding every authored event aimed at a company.

**Events aimed at My Mutuals and Me Inc. are left out of the pool** in this mode
(`EarningsMarket.build_event_pool`). The index's price is the mean move of its
constituents (§3.9), so an event on it would be a second way to move it that no
constituent explains, and the ledger could not show it.

**An event whose target is already bankrupt is skipped and left in the bag**, as the
base game does (D24). §4 of the design says to fire such an event when it carries an
industry or market effect. No shipped event does yet, so the base rule holds. When
events gain those effects (S8), the decision belongs inside `EventPool`.

**Rules out.** An event on the index, and drawing from this year's mood, which does
not exist yet at step 4.

### D155 - One bankruptcy pass (§15 F)
**2026-11-22 · Accepted**

StalkleHeads sets each price once, from an identity that already contains the event,
so it checks for bankruptcy once, at step 8. A company priced at or below 0 fails, its
price is pinned to 0, and every holder's shares are wiped out with no compensation. The
consequences are the base game's. A bankrupt company is never advanced again; its
fundamentals freeze where they were.

The two orderings the base game must keep still hold: splits are checked once, after
the event, and dividends are paid after splits.

### D156 - BERRY BONDS is unchanged, and is the yardstick (§15 G)
**2026-11-22 · Accepted**

In this mode the bond is mechanically the base game's: price 100, no moves, no splits,
no bankruptcy, no events. It pays its 3 coupon every year, whichever mood the year
reports. `EarningsYearResolver` pays a static-price row `EarningsMarket.bond_coupon`
rather than looking the dividend up by mood. The two are the same number on shipped
content, and a test pins that.

**What is new is a set of readouts**, which nothing in the price path reads:
`risk_free_yield_percent` (3.0), `earnings_yield_percent(12.5)` (8.0) and
`equity_premium_percent` (5.0). They are the arithmetic behind §3.4's base multiple,
which S7's Company tab will print.

### D157 - My Mutuals and Me Inc. is an index of pre-split moves (§15 H, §14 q4)
**2026-11-22 · Accepted**

- **Constituents:** every company alive at the start of the year (eighteen on the
  shipped roster).
- **The move:** the mean of their percentage moves, measured **before splits**. A
  company that went bankrupt this year counts -100 that year only; after that it is
  not a constituent.
- **The level:** `index_level = index_level * (100 + move) / 100`, kept as a `float`
  on `EarningsMarket`. The row posts `int(index_level)`.
- **Splits:** above 300, like a company. The posted price halves, rounding up (D22),
  and the level halves.
- **Bankruptcy:** only when every constituent fails in the same year, or the posted
  price otherwise reaches 0.
- **Dividend:** the mean of its living constituents' dividends per share, truncated.

**Why.** Measuring moves rather than levels is how an index avoids the divisor
problem: a constituent's split does not halve the index. The dividend is the owner's
answer to §14 q4.

**Two more places a ratio becomes money.** §3.7 promises two truncations per company
(price and dividend). The index is not a company, and it adds two of its own: its
posted price and its averaged dividend. Both are `int()` toward zero, like everything
else. Like a company's (D134), the posted price can sit a coin above `int(index_level)`
after a split, until the next move.

### D158 - Yearly Change includes the event in this mode (§14 q7)
**2026-11-22 · Accepted (decided by the owner in §14)**

In StalkleHeads a row's `last_yearly_change` is its whole pre-split move, the event
included. The base game's excludes the event (game-rules.md §5). The ledger is what
breaks the move down. `StalkYearChange` keeps both halves: `event_delta` is the
ledger's this-year's-event line in whole coins, and `base_delta` is everything else,
so `total_delta()` is the move.

**Why the ledger's line and not the authored figure.** The ledger telescopes in whole
coins (D133). The event line is the change in the truncated running total when the
event is added, which can be the authored figure or one coin either side. Using it
keeps `base_delta + event_delta` equal to the move exactly.

### D159 - More than one loan is a `GameSettings` toggle, one at a time (§14 q2)
**2026-11-22 · Accepted**

`GameSettings.multiple_loans_enabled`, off by default. Off is the base game: one loan
per player for the whole match (D27). On, a loan that is **settled** frees the slot,
so a player can borrow again. It is still one loan at a time. A second request while
one is outstanding is refused with "You must pay off your loan before taking another."

**Why one at a time.** The deferred question in porting-plan.md was "borrow, repay, and
borrow again". Concurrent loans would change `PlayerState.loan` into a list and touch
every loan screen, for a choice nobody asked for. A defaulted player is bankrupt, so
can never borrow again whatever the toggle says.

**Where it travels.** The setting goes in the snapshot (`StateSync`), so a client's
instant pre-check applies the host's rule.

**Not done here.** Nothing turns the toggle on yet: that is S5's mode selection.
Nothing on screen offers a second loan either: that is S7.

### D160 - A StalkleHeads match is a `GameState` with a market beside the board
**2026-11-22 · Accepted**

The fundamentals live on `GameState.market`, an `EarningsMarket`. It is null in a
base-game match. The board is still `GameState.stalks`, one `StalkState` per row, so
trading, net worth, standings and loans read prices exactly as they do in the base
game. `EarningsYearResolver` copies each company's price onto its row every time it
changes.

- **The board** (`EarningsMarket.new_game_state`): every company in id order, then
  BERRY BONDS, then My Mutuals and Me Inc. That is twenty rows on the shipped roster.
- **A company the base game ships** reuses that stalk's definition, so its name and
  description are the shared ones (design §3.2.2). Its row opens at the company's own
  price, not at the definition's 100.
- **A company the base game does not ship** (ten of them, five still placeholders) gets
  a definition built in memory from its profile: id, name, ticker, industry, no
  description, no events. It is never saved. S8 may replace these with authored files.
- **The flow input** is `EarningsMarket.net_shares_traded`: per company, net shares
  traded in the year being played. The next year advance reads it and clears it. It
  stays a plain input until S4's desk fills it.

**Why.** Every existing system that touches money (`TradeRules`, `LoanRules`,
`YearSettlement`) already works on `StalkState` prices. Mirroring the price onto the
row lets all of them work unchanged, rather than teaching each one about companies.
Putting the market on `GameState` rather than inside the resolver means S6 can
snapshot it, as it does the rest of the match.

**Rules out.** An autoload for the market (design §10.3), and a second copy of a
company's price that the board does not show.

### D161 - The balance tool plays the real pipeline; P4 holds at 29.6%
**2026-11-22 · Accepted**

`tools/balance/stand_in_year.gd` is deleted, as D144 planned. The tool now builds a
real `GameState` with `EarningsMarket.new_game_state`, seats each strategy as a real
`PlayerState`, and advances the year with `EarningsYearResolver`. Dividends, splits,
bankruptcies and net worth are the pipeline's own.

**The levers (D150) reach the pipeline through two seams.**
`EarningsYearResolver.advance_company_earnings` and `valuation_performance` are public
methods that `tools/balance/lever_year.gd` overrides. The game never overrides them.
With every lever at its default they call straight through, and
`test_balance_smoke.gd` checks the override path reproduces that exactly.

**What changed in the market the tool measures.** One thing only: the event. The
stand-in drew the probe's event, `+5..+20` or `-5..-25` on any living company. The
pipeline draws a real authored event from `EventPool`, which can only land on the eight
companies the base game ships. Its magnitudes are 5 to 25.

**Measured, 4,000 ten-year seeds, no flow, published values:**

| | Stand-in (D151) | Pipeline |
|---|---|---|
| Leader | TREND 27.9% | TREND **29.6%** |
| LOWPE | 25.4% | 23.9% |
| INCOME | 15.5% | 14.9% |
| Strategies winning at least 4% | 6 | 6 |
| Bull-year rate | 54.4% | 54.5% |
| Splits / bankruptcies per match | 1.63 / 0.64 | 1.69 / 0.69 |
| RANDOM's median over the leader's (P3) | 0.62 | 0.63 |

The stand-in column was re-run on the same 4,000 seeds just before the stand-in was
deleted, and matched D151 to the digit.

**P4 holds, by 0.4 points.** Nothing was retuned. The margin is now thinner than D151
recorded, and S4's desk adds flow, which §2.6 measured as costing about a point. **S4's
re-run is the one that decides whether D151 is enough.**

**Cost.** The real pipeline is slower: 4,000 matches take about 130 s against the
stand-in's 47 s. Most of that is `GameState.stalk_by_id`, a linear search, called per
company per step. Fine for a tool. Worth an index if the game ever runs many years at
once.
