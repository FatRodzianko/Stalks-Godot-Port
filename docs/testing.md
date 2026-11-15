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

320 tests, 13,960 asserts, about 17 seconds.

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
| `test_local_session.gd` | Session start-up, seed recording, trading and its rejections, pre-checks agreeing with enforcement, ready-up and year advance, a two-player wait, a full match, loans through the session | 25 |
| `test_gameplay_screen.gd` | **Scene tests** driving the real screen: rows built, header figures, buying and selling through actual controls, live validation disabling the Buy button, bankrupt presentation, event and year-summary display, header/row column alignment, ellipsis on long names, and the UI matching a headless run of the same seed | 27 |
| `test_state_sync.gd` | What crosses the wire: the redaction rules (a rival's cash, holdings and loan schedule are never sent; net worth and *that* they borrowed are), snapshot and `YearResult` round trips, mismatched content being reported, and a walk of the whole payload asserting nothing in it is an object | 20 |
| `test_networked_session.gd` | **Networked tests** with a real host and client in one process: joining and seating, yeehaw in both directions, a refused self-yeehaw, a client's buy applied by the host, an unaffordable and a nonsense request refused, a refusal reaching only the asker, a client unable to act as another player, redaction end to end, the all-ready gate, both sides agreeing on every price after a year, and the disconnect behaviour including the deadlock it used to cause | 28 |
| `test_lobby_screen.gd` | **Scene tests** for the menu's three paths (solo, host, join; a joiner is not offered the host's settings) and the lobby over a live host session: the player list, who you are and who is hosting, arrivals and departures, ready-up both ways, Start being the host's alone, and `Main` opening a lobby, reporting a busy port and carrying on into the match | 27 |
| `test_screens.gd` | **Scene tests** for the menu (ranges, defaults, seed handling), the screen host (one screen at a time, session ownership, play-again), the result screen, and the loan panel (borrowing, paying the minimum, the escalating warnings, and that a player may still ready up with a payment due) | 25 |

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

Two of these tests exist specifically because a layout bug regressed once and would
not announce itself: `test_the_board_header_columns_line_up_with_the_rows` compares
every header column's position and width against the row's, and
`test_long_stalk_names_are_not_hard_clipped` checks the ellipsis behaviour and the
tooltip. Both need a real frame, so they `await get_tree().process_frame` before
measuring.

**Not yet covered:** anything networked (Phase 5), sound, and the visual *appearance*
of a screen. Tests can prove a column is 325px wide and aligned; they cannot say
whether it looks right. That still needs a human pressing F5.
