# Testing

Framework: **GUT 9.7.1**, installed at `addons/gut/`.

Version matters here. GUT's own compatibility table maps **9.7.1 (the `godot_4_7`
branch) to Godot 4.7.x**, while its `main` branch targets 4.6.x — so "latest" is the
wrong thing to grab for this project. If Godot is ever upgraded, check that table
before upgrading GUT.

Do not install gdUnit4 alongside it. One framework only.

---

## Running the suite

From the project root, with `<godot>` being the console executable named in
`CLAUDE.md`:

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

Configuration lives in `.gutconfig.json`, so no flags are needed. On a cold
checkout, import first — there is no `.godot/` cache yet:

```
<godot> --headless --path . --import
```

Useful ad-hoc flags:

| Flag | Effect |
|---|---|
| `-gtest=res://tests/unit/test_year_resolver.gd` | Run one file |
| `-gunit_test_name=test_split` | Run only tests whose name contains this |
| `-glog=2` | More verbose output |
| `-gexit` | Exit when finished (already the default via config) |

### The editor panel needs a one-time setup

The editor also has a GUT panel at the bottom of the window, since the plugin is
enabled in `project.godot`. Headless CLI runs do **not** require the plugin.

**Important:** `.gutconfig.json` configures the **command-line runner only**. The
editor panel keeps its own separate settings in
`user://gut_temp_directory/gut_editor_config.json`, which is in each person's own
Godot user folder, *outside this repository*. It therefore cannot be committed, and
every contributor has to set it once:

> GUT panel → **Settings** → **Test Directories** → type `res://tests/unit` into row
> `0` → **tick the checkbox on that row**.

Until that is done, *Run All* reports *"You do not have any directories set"*. The
checkbox is the part people miss — typing the path alone only lists the directory
without enabling it.

The command line needs none of this and works immediately on a fresh clone, which is
why it is the recommended way to run the suite and the only way a build server should
do it.

---

## Layout

```
tests/
  fixtures/        Shared helpers. NOT scanned for tests.
    stalks_fixture.gd          The ten real stalks, event sets, state builders
    fixed_price_model_stub.gd  Test double with a constant price delta
  unit/            Everything GUT runs. One file per unit under test.
    test_market_mood.gd
    test_random_range_price_model.gd
    test_event_pool.gd
    test_trade_rules.gd
    test_year_resolver.gd
```

`.gutconfig.json` points only at `tests/unit`, which is why fixtures can live
beside them without being mistaken for test scripts.

---

## Conventions

**Always seed the RNG.** Every test touching randomness takes its generator from
`StalksFixture.rng(seed)`. A test whose outcome depends on unseeded randomness is a
bug, not a test — it will eventually fail for no reason and be ignored.

**Statistical assertions are seeded too.** Checks like "the contrarian move fires
~10% of the time" run 60,000 seeded iterations with a generous tolerance. The point
is to catch a *wrong implementation* (50%, or 0%), not to validate Godot's RNG, so
the tolerance is deliberately loose while the seed keeps it stable.

**Use the stub to isolate a rule.** `FixedPriceModelStub` makes prices move by a
constant, so a split or bankruptcy test can set a price by hand and assert on one
behaviour instead of fighting the real random model.

**Pin ordering, not just outcomes.** Several rules only make sense as a sequence —
dividends paid on post-split share counts, a negative event preventing a split, an
event bankrupting a stalk the base move spared. Those tests exist specifically to
stop a future refactor quietly reordering the pipeline.

**Add a regression test for every rule bug found.** The original shipped with
several; the point of this suite is that the port does not.

---

## Current coverage

562 tests, 14,482 asserts, about 21 seconds.

The networked tests account for most of that time — each one opens a real socket.

| File | Covers | Tests |
|---|---|---|
| `test_market_mood.gd` | 7/12 bull weighting, labels, degenerate weights | 5 |
| `test_random_range_price_model.gd` | Contrarian rate, inclusive range endpoints, softening thresholds, truncation direction, static stalks | 8 |
| `test_event_pool.gd` | Pool sizes 45/45, no repeats within a cycle, refill on exhaustion, bankrupt-target skipping without consuming | 9 |
| `test_trade_rules.gd` | Buy/sell validation and rejection reasons, max affordable, net worth with holdings and loans, ranking and tie-breaking | 25 |
| `test_year_resolver.gd` | Split rounding, threshold boundary, both bankruptcy passes, dividend sequencing, displayed yearly change, 10- and 99-year matches, determinism | 21 |
| `test_loan_rules.gd` | Annuity arithmetic, eligibility, the full ten-payment schedule, penalties and default, overpayment, one-loan-per-game, pipeline integration | 40 |
| `test_marquee_label.gd` | The scrolling name label: overflow detection against the real font, hover and click-to-pin, character-by-character stepping, reset on leave | 14 |
| `test_content_library.gd` | The shipped content loads and validates clean, stat blocks match the documented table, 45/45 pools, deterministic order, a full match played from real content, and every validator rule rejecting bad content | 29 |
| `test_local_session.gd` | Session start-up, seed recording, trading and its rejections, pre-checks agreeing with enforcement, ready-up and year advance, a two-player wait, a full match, loans through the session | 26 |
| `test_gameplay_screen.gd` | **Scene tests** driving the real screen: rows built, header figures, buying and selling through actual controls, live validation disabling the Buy button, bankrupt presentation, event and year-summary display, header/row column alignment, ellipsis on long names, and the UI matching a headless run of the same seed | 27 |
| `test_state_sync.gd` | What crosses the wire: the redaction rules (a rival's cash, holdings and loan schedule are never sent; net worth and *that* they borrowed are), snapshot and `YearResult` round trips, mismatched content being reported, and a walk of the whole payload asserting nothing in it is an object | 21 |
| `test_networked_session.gd` | **Networked tests** with a real host and client in one process: joining and seating, yeehaw in both directions, a refused self-yeehaw, a client's buy applied by the host, an unaffordable and a nonsense request refused, a refusal reaching only the asker, a client unable to act as another player, redaction end to end, the all-ready gate, both sides agreeing on every price after a year, and the disconnect behaviour including the deadlock it used to cause | 40 |
| `test_lobby_screen.gd` | **Scene tests** for the title screen (Create Game and Join Game; one settings panel serving all three ways to start a game; a joiner offered none of them; the lobby's invite button and invite-only games; the host naming the match, that name heading the lobby on both machines, and an online game taking its player names from Steam rather than from the title screen) and the lobby over a live host session: the player list, who you are and who is hosting, arrivals and departures, ready-up both ways, Start being the host's alone, the all-ready gate and the host's kick that escapes it, that the host has no ready button because Start is their readiness, and `Main` opening a lobby, reporting a busy port and carrying on into the match | 66 |
| `test_client_board.gd` | The client's path from lobby to board, which nothing covered before two windows were played for real: the board building and filling for a `ClientSession`, a swapped-out lobby or board ignoring the signals that follow it, a live one still updating, a removed player returned to the menu with the reason, the board visibly acknowledging a Ready press — readying, un-readying, naming who it waits for, and showing another player's dot — and the host going away mid-match, which leaves the board reporting it and `Main` listening | 25 |
| `test_audio_service.gd` | Sound, checked without listening: a mood being **two** clips layered rather than one, a bankruptcy being glass **and** a scream, a yeehaw being one, six voices surviving a year and a yeehaw landing together, volume round-tripping with zero meaning silence rather than quiet, and the SFX bus existing at all — without which every volume assertion would agree with itself and mean nothing | 10 |
| `test_user_settings.gd` | Preferences kept between runs: full volume on a first run, a volume round trip, silence staying silent, a hand-edited nonsense value clamped, a corrupt file reading as a first run rather than crashing, and the title screen remembering **nothing** — the guard on a convenience that was added and then removed the same day | 7 |
| `test_achievement_rules.gd` | What a match earns, decided without Steam: the all-in and diversified thresholds and their near-misses, borrowing and settling, a split or bankruptcy judged from the holdings **before** the year (a bankrupt stalk's shares are zeroed, so the current state would never award it), winning and losing being exclusive, the net-worth targets including the starting-cash guard that stops one being bought, doubling and halving, long-match ids, the lifetime ladders awarding every rung reached, and that every id these rules can award is in the catalogue | 28 |
| `test_achievements.gd` | The achievement catalogue: 25 distinct ids, none differing only by case (the bug the original shipped), none padded, and the win achievement keeping the spelling that actually fired | 10 |
| `test_conventions.gd` | Readability rules checked by machine rather than memory: no inline function connected to a signal, no signal connected to another signal's `emit`, no conditional expression split across lines, no leftover placeholder in `src/` **or in `docs/`**, no stray `print` | 8 |
| `test_steam_transport.gd` | The Steam transport and the online games list **without touching Steam**: that the transport satisfies the `Transport` contract, refuses a missing lobby or host, offers invites rather than a port, and that the browser renders a list, an empty list, a full lobby and a failure, and the decoding of Steam lobby departures (left, dropped, kicked, and an arrival not being one), Steam's join refusals turned into sentences, and the `+connect_lobby` parse an invite from a closed game arrives as | 31 |
| `test_transport.gd` | The transport seam Phase 6 rests on: a host and a client built on a transport that is deliberately not ENet, failures surfacing to the caller, and the lobby's joining hint coming from below rather than being branched on, and the LAN address ranking pinned against a real multi-adapter machine, and failures reaching the screen as sentences rather than bare error codes — including that ENet reports a taken port as ERR_CANT_CREATE, which is what the obvious mapping got wrong | 20 |
| `test_launch_args.gd` | The `--host` / `--join` development flags: every flag and its default, nonsense values ignored rather than breaking the launch, Godot's own arguments passing through untouched, and `Main` going straight into a lobby or falling back to the menu with a reason | 20 |
| `test_screens.gd` | **Scene tests** for the title screen (ranges, defaults, seed handling, and that single player, hosting online and hosting locally are all offered the same settings), the screen host (one screen at a time, session ownership, play-again), the result screen, the loan panel (borrowing, paying the minimum, the escalating warnings, and that a player may still ready up with a payment due), the minimum payment shown under the loan button, the bottom bar holding one height through a whole match, Escape as the way out, and the title screen's settings reaching a Steam match , and that the board actually asks for its sounds , and the result screen's year-by-year tab — a row per year including the eleventh settling one, a quiet year still saying something, and a solo winner told they *win* rather than that they *wins* | 72 |

Counts above are read from a suite run, not estimated. If you add tests, re-run and
update them — a stale number here is a small lie that erodes trust in the rest.

The loan schedule test is worth knowing about: it asserts the whole ten-year
amortisation **year by year** against the reference trace in
[game-rules.md §9.2.1](game-rules.md) — payment due and resulting balance for each
year, the exact total paid, and that it lands on zero. That table caught a real
transcription error during Phase 2, which is the point of pinning a schedule rather
than spot-checking a couple of figures.

Two tests in `test_content_library.gd` are worth knowing about:

- **The stat-block cross-check** compares the `.tres` files on disk against the table
  encoded by hand in `StalksFixture`. That duplication is deliberate: it means a bad
  edit to a `.tres`, or a mistake in the importer that produced them, fails a test
  instead of quietly changing how the game plays.
- **The validator tests work by breaking a good stalk one way at a time**, so each
  one proves a specific check actually fires rather than relying on the real content
  happening to be correct.

### Scene tests

`test_gameplay_screen.gd` instantiates the real `.tscn`, injects a session with a
fixed seed, and interacts **through the actual controls** — setting a `LineEdit`'s
text and emitting a `Button`'s `pressed` signal — rather than calling the session
directly. That is the whole point: it proves the *wiring*, which no amount of
simulation testing can.

It has already earned its place. It caught a real bug where a sold-out position
stayed on the holdings board, because `queue_free()` is deferred to the end of the
frame and the row was still a child immediately afterwards. Reading the code would
not have shown that. Fixing it also cut the suite from 14 seconds to 2, since the
stale rows were accumulating.

Note the helper pattern: setting `text` on a `LineEdit` in code does **not** emit
`text_changed`, so a test that wants live-validation behaviour has to emit it by
hand. The helpers at the top of that file do this.

The acceptance test to keep an eye on is
`test_what_is_on_screen_matches_a_headless_simulation_of_the_same_seed`: it plays a
whole match through the UI, plays the same seed headlessly, and compares every stalk
price and the final net worth. It is what proves the UI invents nothing.

### Networked tests

`test_networked_session.gd` stands up a real `HostSession` and `ClientSession`,
connected over real ENet, **in one process**. No second window, no manual
two-window dance, and they run in the ordinary suite.

`tests/fixtures/net_harness.gd` does the work, and the three things that make it
possible are each easy to get wrong:

1. **Each side needs its own subtree and its own `MultiplayerAPI`**, registered
   with `SceneTree.set_multiplayer(api, path)`. A tree has one default API, so two
   peers cannot otherwise coexist. The nodes must already be in the tree when that
   call is made.
2. **The session's path *relative to its API's root* must match on both sides.**
   Godot resolves an RPC by that relative path. The harness mounts both sessions as
   `Session` directly under their own world node — the world names differ, which is
   fine; what is below them may not.
3. **A non-default `MultiplayerAPI` is not polled by the engine.** The harness
   polls both by hand in `_process`. In the real game there is one API, the tree's
   own, and Godot polls it; this is a harness concern only.

Ports are handed out sequentially from a random per-run base rather than picked
at random per harness. Random picking collided often enough to redden a run, and
a failed bind is not silent — ENet logs an engine error, which GUT counts
against the test. A retry remains as a safety net for a socket left over from a
previous run.

**Only one `Main` can hold a peer per process.** `Main` uses the tree's default
`MultiplayerAPI`, as a shipped game should, and a tree has exactly one of those,
so two `Main` instances overwrite each other's peer. Two *sessions* work only
because the harness gives each its own subtree and API. So the handshake is
tested at the session level, and `Main` is tested one session at a time — the
reasoning is spelled out at the top of `test_lobby_screen.gd`.

A third peer needs its own world too, for the same reason: mounted as a sibling
it cannot be named `Session`, and the host's RPCs would fail with "Failed to get
path from RPC". `attach_extra_client` handles that.

Use `await harness.settle(self)` to let a request and its reply cross. It waits on
**process** frames, not physics frames, because that is where the polling happens —
waiting on physics frames would advance a clock that moves no packets.

What these tests deliberately do *not* cover is the rules. Those are tested without
a network, where they are faster and the failures are clearer. What is asserted here
is only what the wire adds: that a request arrives, that the answer comes back, and
that a client cannot do what it must not.

One teardown quirk is documented in the harness and worth repeating: Godot's
`SceneTree.set_multiplayer` **rejects a null interface**, and there is no removal
API, so a harness cannot unregister the API it registered. Clearing the peer is what
actually releases the socket; the stale path registration is inert.

### Testing by hand

What only a person can check — two separate machines, Steam's relay, and
whether anything feels right — has its own document, written to be worked
through in order: [manual-testing.md](manual-testing.md).

**Looking at the screen without playing the game.** Godot draws nothing with
`--headless`, so a purely visual question used to mean building and playing.
`tools/loan_shot.gd` puts the board into a chosen state and Godot's Movie Maker
writes the frames to PNG files; the script's own header has the command. It was
written to answer three questions at once — does "Min $339" fit under the LOAN
button, does the bottom bar sit at the same height at year 0 as at year 3, and
is the year-0 sentence clipped (it was) — and all three took one run. Point it
at a different state by changing what its `_process` presses.

Being able to see the screen does not replace asserting about it: a picture
proves one state looked right once, where `test_the_bottom_bar_holds_one_height_for_a_whole_match`
proves every state does, every run.

### No test may touch Steam

`SteamService` is created on demand and is never an autoload, so a test that
does not ask for Steam never gets it (decisions.md D59). Anything that reaches
`Main.show_online_games()` **does** ask for it: that screen starts Steam, and
on a machine where Steam happens to be running that initialises it for real.

This is not hypothetical. Two tests written for the settings carry-over (D62,
since replaced by D65)
went through `Main`; on a machine with Steam open the second one failed with an
engine error from initialising Steam twice, and on a machine without Steam both
would have passed. A test whose result depends on whether the author had Steam
running is worse than no test.

So those tests drive `SteamBrowserScreen` directly and hand it a null service,
which is the real build-without-the-plugin case the screen is required to
survive. What is left uncovered is the single line in `Main` that stores the
settings on the way through — covered at both ends instead: the menu emits
them, and the browser displays them.

### What the suite deliberately will not test

Anything that talks to Steam. `test_steam_transport.gd` covers argument
handling and rendering only, because the suite has to pass on a machine with no
Steam client and no GodotSteam plugin — the same condition the game itself
must run in (decisions.md D14). A test that only passes on one developer's
machine is worse than no test.

The Steam path is checked by hand instead, with two tools:

```
<godot> --headless --script res://tools/steam_check.gd
<godot> --headless --script res://tools/steam_lobby_check.gd
```

The first says whether the plugin is installed. The second starts Steam,
creates a real lobby, turns it into a peer and leaves again. Neither is a test,
because "Steam is not installed" is a legitimate answer on a fresh checkout.

### One unexplained red run, 2026-11-15

A full run reported **536 of 537 passing, 14,431 of 14,434 asserts**, and the
next run with no code change in between was clean. Ten further runs have been
clean. The failing test's name was not captured.

What is known: three asserts in a single test failed together, so it is a test
with at least three of them rather than a stray engine error.

What was ruled out: the first theory was that `test_user_settings.gd`'s
teardown removed a file that was not there and that Godot logged an error GUT
would count. A probe showed `DirAccess.remove_absolute` on a missing path
returns a failure code and logs **nothing**, so that was not it. The teardown
now checks anyway, because it should.

Still suspected, unproven: the networked tests take real ports. They are
chosen from a random base per run and the harness retries a taken one, but a
collision has cost a red run before.

**If you see a lone failure, capture the name before re-running.** That is the
thing this note could not do and the reason it is still open.

### A regression test that has not failed is not evidence

The tests in `test_client_board.gd` were written twice. The first versions passed
**with the fix removed**: they poked the session with a buy at year 0, which is
rejected, and a rejection broadcasts no state — so nothing ever reached the
detached screen they were supposed to be testing. They proved nothing.

Before trusting a regression test, take the fix out and watch it fail. That is
cheap, and it is the only thing that separates a test which guards behaviour from
one that merely runs.

Two of these tests exist specifically because a layout bug regressed once and would
not announce itself: `test_the_board_header_columns_line_up_with_the_rows` compares
every header column's position and width against the row's, and
`test_long_stalk_names_are_not_hard_clipped` checks the ellipsis behaviour and the
tooltip. Both need a real frame, so they `await get_tree().process_frame` before
measuring.

**Not yet covered:** anything networked (Phase 5), sound, and the visual *appearance*
of a screen. Tests can prove a column is 325px wide and aligned; they cannot say
whether it looks right. That still needs a human pressing F5.
