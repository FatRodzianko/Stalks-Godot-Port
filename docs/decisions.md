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
**2026-11-15 · Accepted · extends D67**

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
