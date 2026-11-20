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
    test_ports.gd              Hands out a port no other test has been given
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

862 tests, about 50 seconds.

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
| `test_gameplay_screen.gd` | **Scene tests** driving the real screen: rows built, header figures, buying and selling through actual controls, live validation disabling the Buy button, bankrupt presentation, event and year-summary display, header/row column alignment, ellipsis on long names, the UI matching a headless run of the same seed, and the "... MORE" button taking no width from the description, sitting in its bottom right corner and landing between characters rather than through one (D107a) | 30 |
| `test_state_sync.gd` | What crosses the wire, which as of 2026-11-18 is the whole match (D105): a rival's cash, holdings and loan schedule all arriving, every player being sent the identical snapshot — the property host migration rests on — the random stream's position travelling, snapshot and `YearResult` round trips, mismatched content being reported, and a walk of the whole payload asserting nothing in it is an object | 23 |
| `test_main_migration.gd` | **The orchestration**, driven end to end without Steam: the host leaving being noticed, Steam not having decided yet, Steam still naming the leaver, being made the owner and standing down a turn before hosting, following somebody else and retrying, giving up after twenty seconds, the dying connection not cancelling the migration, and a taken-over lobby being advertised again, keeping its name, and being hidden instead when a match was under way | 19 |
| `test_away_players.gd` | **What the match does to a player who is not there** (D110): the year gate skipping them while still waiting for everybody present, a deserted match refusing to resolve years at all, dividends paid, splits doubling their shares, a bankruptcy wiping them out, net worth recomputed, every year away counting as a missed loan payment through the 10% and 15% penalties to seizure on the third, their place in the rankings kept, a match won while absent and a lead lost while absent, a lone survivor refused a yeehaw nobody could give, and the flag crossing the wire | 20 |
| `test_main_rejoin.gd` | **The orchestration of REJOIN GAME**, driven without Steam (D111): the lobby being remembered on the way to the board but not for a solo game, the newest match overwriting the last, the match ending forgetting it, the button offered only when there is something to rejoin and sitting opposite QUIT TO DESKTOP, the remembered lobby being asked for, a client built rather than a host, the screen not swapping until the welcome lands and then showing the board, a match that changed hands being rejoined through its new host, Steam's refusal and the host's refusal each reaching the title screen as a sentence, a refused rejoin keeping the record, the handlers coming off once it has landed, and going back to the title screen cancelling one in flight. Then **whether the remembered game is still on** (D115): Steam being asked about the lobby before anything is offered, a lobby still playing being offered, one that no longer exists and one whose match is over both being forgotten, Steam's silence hiding the button without forgetting, Steam being closed asking nothing, an answer about another lobby being ignored, the question being re-asked on the timer and only on the title screen, the button going away when the match ends out there and coming back when Steam answers again, leaving a lobby you were the last one in forgetting it while leaving one others are still in keeps it, and the host - and only the host - marking the lobby finished | 38 |
| `test_lobby_migration.gd` | Who takes over a lobby when its host leaves, with no Steam in it: waiting while Steam has not decided, the departed host's id not being mistaken for a new owner, becoming the host, joining the new one, giving up after twenty seconds, and a late answer still being acted on | 9 |
| `test_host_migration.gd` | Continuing a match on a new host: the year, prices and **every** player's position surviving the handover, the departed host staying in the match marked away, everybody else starting away so the year gate cannot hang while they reconnect, the random stream being picked up rather than restarted, and reclaiming a seat — matched by Steam ID, refused without Steam, refused for a seat already being played, landing them back on the position the match built for them, keeping the player's place in the roster order, and the two refusals `why_not_rejoin` decides between | 22 |
| `test_networked_session.gd` | **Networked tests** with a real host and client in one process: joining and seating, yeehaw in both directions, a refused self-yeehaw, a client's buy applied by the host, an unaffordable and a nonsense request refused, a refusal reaching only the asker, a client unable to act as another player, a client ending up holding the host's whole match and still being unable to spend a rival's money, the all-ready gate, both sides agreeing on every price after a year, the disconnect behaviour including the deadlock it used to cause and a dropped player now staying in the match marked away (D110), and **the whole reclaim over a real socket** - a returning Steam account seated back on its own slot with the position the match kept for it, the away flag cleared, a stranger's account refused the waiting seat, and the reclaiming client being told the match is under way (D116) | 46 |
| `test_lobby_screen.gd` | **Scene tests** for the title screen (Create Game and Join Game; one settings panel serving all three ways to start a game; a joiner offered none of them; the lobby's invite button and invite-only games; the host naming the match, that name heading the lobby on both machines, and an online game taking its player names from Steam rather than from the title screen) and the lobby over a live host session: the player list, who you are and who is hosting, arrivals and departures, ready-up both ways, Start being the host's alone, the all-ready gate and the host's kick that escapes it, that the host has no ready button because Start is their readiness, and `Main` opening a lobby, reporting a busy port and carrying on into the match; and the volume slider neither previewing until it is let go nor leaving a clip sounding into the next drag, both reported from play | 70 |
| `test_client_board.gd` | The client's path from lobby to board, which nothing covered before two windows were played for real: the board building and filling for a `ClientSession`, a swapped-out lobby or board ignoring the signals that follow it, a live one still updating, a removed player returned to the menu with the reason, the board visibly acknowledging a Ready press — readying, un-readying, naming who it waits for, and showing another player's dot — and the host going away mid-match, which leaves the board reporting it and `Main` listening | 25 |
| `test_display_settings.gd` | The resolution list as arithmetic over a monitor size handed in as a number: every offer being exactly 16:9, a monitor offered only what it can show, a 16:10 and an odd laptop panel both resolving to the tallest 16:9 that fits, a saved size too big for a replaced monitor being reduced, and the layout scale including the 1.5x half-step | 14 |
| `test_confirm_panel.gd` | The yes/no overlay and its revert countdown: starting at the number given, stopped by an answer, cleared when the panel is reused for a plain question, visible in the message, and — the one that matters — nobody answering counting as no | 6 |
| `test_pause_menu.gd` | Escape during a match opening the pause overlay rather than offering to end the game, leaving still asking first, the overlay not surviving a screen change, its volume slider applying without a preview clip, both quit buttons being present and wired, and **quitting to desktop mid-match asking first** (D117) - the question raised, its yes wired to `quit_to_desktop`, saying no leaving the match untouched, the two confirmations not sharing a panel, the pause menu getting out of the way, and the title screen still asking nothing | 16 |
| `test_title_screen_shape.gd` | The rebuilt title screen: the card being the same size on every tab and the heading and quit button not moving, no address form anywhere on it, the development overlay hosting and joining, the lobby list's search filtering and not sticking across a refresh, the pause menu showing the same settings panel as the title screen, and the layout corrections from play: a start button narrower than the panel and over to the right, a quit button clear of the panel, a confirmation that carries the theme wherever it is parented, and the development overlay being on a canvas layer above the game rather than inside a container that swallowed its clicks | 18 |
| `test_lobby_row.gd` | What a browser row tells a joiner before they commit: the year limit, the starting cash and whether loans are on, each one omitted rather than guessed when the lobby did not publish it, and a full game offering no join button | 8 |
| `test_final_board.gd` | Looking at the board after the match: the result screen offering it, the board rebuilt from the session the match actually ended in rather than a fresh one, the bottom bar becoming the way back, that same button still readying up during a real match, going back and forth repeatedly, and asking for a board when there is no match | 7 |
| `test_steam_identity.gd` | Everything around the Steam calls without making any: a player's Steam id surviving the snapshot and deliberately not being redacted, a lobby row taking the portrait that is its own and refusing one that is not, a player with no account never showing a blank, the supporter thank-you appearing only when it is earned, and every Steam-shaped question answering no when Steam is absent | 12 |
| `test_splash_screen.gd` | The studio logo: that it ends, that it ends only once however many times it is told to, that a key or a mouse click gets rid of it while a key release does not, that it times out on its own, that a headless run never shows one, that it hands over to the menu, and that the fade takes the time its constants say - added after a timing change appeared to do nothing | 10 |
| `test_audio_service.gd` | Sound, checked without listening: a mood being **two** clips layered rather than one, a bankruptcy being glass **and** a scream, a yeehaw being one, six voices surviving a year and a yeehaw landing together, volume round-tripping with zero meaning silence rather than quiet, the volume preview having a voice of its own so a second one replaces the first instead of echoing over it, and the SFX bus existing at all — without which every volume assertion would agree with itself and mean nothing | 12 |
| `test_user_settings.gd` | Preferences kept between runs: full volume on a first run, a volume round trip, silence staying silent, a hand-edited nonsense value clamped, a corrupt file reading as a first run rather than crashing, and the title screen remembering **nothing** — the guard on a convenience that was added and then removed the same day | 7 |
| `test_achievement_rules.gd` | What a match earns, decided without Steam: the all-in and diversified thresholds and their near-misses, borrowing and settling, a split or bankruptcy judged from the holdings **before** the year (a bankrupt stalk's shares are zeroed, so the current state would never award it), winning and losing being exclusive, the net-worth targets including the starting-cash guard that stops one being bought, doubling and halving, long-match ids, the lifetime ladders awarding every rung reached, and that every id these rules can award is in the catalogue | 28 |
| `test_achievements.gd` | The achievement catalogue: 25 distinct ids, none differing only by case (the bug the original shipped), none padded, and the win achievement keeping the spelling that actually fired | 10 |
| `test_conventions.gd` | Readability rules checked by machine rather than memory: no inline function connected to a signal, no signal connected to another signal's `emit`, no conditional expression split across lines, no leftover placeholder in `src/` **or in `docs/`**, no stray `print` | 8 |
| `test_steam_transport.gd` | The Steam transport and the online games list **without touching Steam**: that the transport satisfies the `Transport` contract, refuses a missing lobby or host, offers invites rather than a port, and that the browser renders a list, an empty list, a full lobby and a failure, and the decoding of Steam lobby departures (left, dropped, kicked, and an arrival not being one), Steam's join refusals turned into sentences, and the `+connect_lobby` parse an invite from a closed game arrives as; and that advertising, hiding and shutting down a lobby are each a harmless no-op without Steam, which is all of D106 the suite can reach | 33 |
| `test_transport.gd` | The transport seam Phase 6 rests on: a host and a client built on a transport that is deliberately not ENet, failures surfacing to the caller, and the lobby's joining hint coming from below rather than being branched on, and the LAN address ranking pinned against a real multi-adapter machine, and failures reaching the screen as sentences rather than bare error codes — including that ENet reports a taken port as ERR_CANT_CREATE, which is what the obvious mapping got wrong, and that a valid address with nothing listening on it opens anyway, so the only client-side failure to report is a mistyped address | 22 |
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

### The orchestration round Steam is tested; Steam is not

Three migration faults reached play with a green suite, and all three were in
`Main` rather than in the pieces it calls (D108). The code that decides what to
do when a host leaves never calls the Steam API - it only acts on answers that
come from it - so it is now driven in tests with those answers faked.

Two fixtures make that possible, and both are worth knowing about before
writing anything else that touches Steam:

- `StubSteamService` answers `is_running`, `local_steam_id`, `current_lobby`
  and `lobby_owner`, and records the lobby-visibility calls instead of making
  them. `join_lobby` records the lobby asked for and answers on the same signal
  the real one does - `lobby_joined`, or `lobby_failed` when
  `refuse_join_with` is set - which is what lets the rejoin's failure paths be
  tested at all. `request_lobby_details` answers on `lobby_details` from
  `details_exist` / `details_state`, or not at all when
  `details_never_arrive` is set, because Steam never answering is a case the
  title screen has to survive. `leave_lobby_as_host` returns `last_one_out`.
**A reclaim needs no Steam at all, and is tested without it.** `_slot_to_reclaim`
only ever asks for a Steam id, and a Steam id is an integer to everything below
`SteamService`, so `NetHarness.start` takes one for each side and ENet carries a
real drop-and-return end to end. The ids default to 0 — which is what a direct
connection really has, and what makes `_slot_to_reclaim` refuse outright — so no
test that is not about reclaiming is affected.

- `StubTransportSource` replaces `Main._steam_transports`. **This one is not
  optional.** Calling `SteamMultiplayerPeer` with Steam uninitialised does not
  return an error, it crashes the process with a signal 11 - a test run that
  reaches it dies mid-suite with a C++ backtrace rather than a failure.

The line is: anything `Main` decides is tested; anything Steam decides is not.

**REJOIN GAME is tested the same way and for the same reason**
(`test_main_rejoin.gd`). Writing it also found a fault by reading rather than
from play: `lobby_failed` was connected only when hosting, so a join Steam
refused reported nothing to anybody (D112).

**A test that drives `Main` must set `_last_match_path`.** The remembered match
lives in `user://last_match.cfg` and the real game writes it on the way to the
board, so a suite that left the default would either wipe a match somebody
meant to go back to or invent one that does not exist. The seam exists for that
and nothing else.

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

### Display settings are tested as arithmetic, not as pixels

`DisplaySettings` takes a monitor size as a plain `Vector2i` and answers with
numbers. That is deliberate: it means the resolution list can be tested for a
1920×1200 panel, a 1366×768 laptop and a 4K display on a machine that has none
of them, and it means the suite never touches a window.

`DisplayMode` is the other half — the only place in the project that sets a
window size or asks `DisplayServer` anything — and it **does nothing at all
under the headless driver**, returning the resolution it would have used. That
is what stops a scene test putting the test runner fullscreen.

**What this does not cover, and no test can:** whether the game actually looks
right at a given resolution. Godot renders nothing headless, so sharpness,
black-bar placement and whether text is legible at 640×360 are all answered by
looking at it. See `manual-testing.md`.

### The CRT effect is tested around the shader, never through it

`test_crt_overlay.gd` covers everything except the picture: that the overlay is
built, that it starts in whatever state was saved, that the tick box in
Settings switches it at once and writes the choice down, that a screen change
does not switch it off, and that the full-screen rectangle in front of the game
is `MOUSE_FILTER_IGNORE`. That last one is the fault worth having a test for —
a rect over the whole game that takes clicks would swallow the click that turns
the effect off, and the only way out would be a hand-edited settings file.

**What no test here can reach:** the shader. The suite runs headless, nothing
is rendered, and the shader is never compiled, so **a shader that will not
compile at all passes every test in this repository.** That is the gap, and it
is why there is a tool:

```
<godot> --path . res://tools/crt_shot.tscn --write-movie "$env:TEMP\crt\c.png" --quit-after 10 --fixed-fps 10
```

It runs the real game with a real window, switches the effect on, and writes
the frames as PNGs. Compile errors appear in the console output and nowhere
else.

**Judge it by comparing two renders, not by looking at one.** The first build
had an invisible scanline pattern — 180 lines over 360 rows samples every row
at the same phase of the sine, so the comb cancels exactly (decisions.md D94).
On a dark screen that is indistinguishable from "a subtle effect" by eye. It
was caught by rendering the same screen with the effect on and off and
differencing the two images: identical, row for row.

`tools/crt_compare.gd` is that comparison, kept:

```
<godot> --headless --script res://tools/crt_compare.gd -- <on.png> <off.png> [<zoom dir>]
```

Set `EFFECT_ON` in `tools/crt_shot.gd` to render each side. What it prints and
what each figure is for:

| Figure | Answers |
|---|---|
| mean difference, pixels changed | is the effect doing anything at all |
| mean brightness, and the middle half alone | is it darkening the picture — the middle excludes the vignette |
| **detail across** | stroke definition, which is what text legibility is |
| detail down | how hard the scanline comb is cutting across glyphs |
| peak stroke, local contrast | what a bright block keeps |

**"Detail across" is the one that matters for readability**, and it is the one
the obvious measurements miss. When the effect was reported as hard to read,
brightness measured at 99.4% and block contrast at 97.7% — both effectively
untouched — while horizontal detail was at 87.9%. Mean absolute difference
between neighbouring pixels is almost the definition of a one-pixel stroke, so
a horizontal smear shows up there and nowhere else. Knocking out one component
at a time said the colour bleed was five of the twelve points.

A third argument writes a nearest-neighbour zoom of both, because a three-pixel
scanline period cannot be seen in a screenshot viewed at anything but 1:1.

### The display path is tested as arithmetic and as wiring

`test_stage.gd` covers how the picture is sized and placed: that the game is
always drawn at 640x360, that the enlargement is a whole number, that every
rung of the resolution ladder fills its window exactly, that a 16:10 window
gets bars above and below only, and that a 1366x768 one is letterboxed all
round. None of that needs a window, because `Stage.fit_to` takes the window
size as an argument.

**That argument exists because of a bug.** The first version of these tests
resized the root viewport to pretend the window had changed, and did not put it
back. The root viewport is shared with every other test in the suite, so the
next test that pushed input at it failed — and the failure pointed at the
splash screen, which had nothing to do with it. A test that mutates shared
state and leaves it is worse than no test, because it breaks something else.

The same file asserts three properties that carry the whole design:
`stretch` on the container, `gui_embed_subwindows` on the viewport, and nearest
filtering. Each was established by running Godot rather than by reading about
it, and a silent change to any of them would be found by a player rather than
by a test.

**What none of it covers is whether a click lands where it looks like it
should.** That is the one thing worth checking by hand after any change here,
and it is step one of the display section in `manual-testing.md`.

### Content is tested against the layout that has to hold it

`test_every_event_description_fits_after_shrinking` was replaced by scroll
tests when shrinking turned out not to work (D100), but the idea behind it
stayed: the suite walks all ninety special event descriptions through the real
label at the real width rather than checking the three known-long ones. A new
event written longer than anything in the game today fails there, in a test,
rather than being discovered mid-match by a player.

The same shape covers the top bar: `test_the_top_bar_holds_one_height_for_every_event`
puts every description into the panel in turn and checks the bar never moves.

### Questions about the engine get a spike, not an opinion

Two tools in `tools/` exist only to answer a question about how Godot itself
behaves, and are kept because the answers are worth more than the scripts:

- `subviewport_spike.gd` — does Godot transform mouse input into a
  `SubViewport` for us? (It does.)
- `popup_spike.gd` — does a dropdown land correctly inside one? (With one
  property set, yes.)

Both are recorded in decisions.md D94a. Two things about the method are worth
carrying to the next one of these:

**Both needed a real window.** Headless does no mouse picking and shows no
popups, so neither question can be answered by the test suite. Run them with
`--path . --script res://tools/<name>.gd` and no `--headless`.

**Write the control case first.** The first run of the input spike reported
that Godot does *not* forward input — which was wrong, and would have been
believed, because it confirmed what was expected. What caught it was a plain
button in the ordinary viewport hearing nothing either: the harness was broken,
not the engine. A spike with no control case can only tell you what you already
thought.

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

### The red run that could not be reproduced, 2026-11-15 — resolved 2026-11-16

**Almost certainly two tests drawing the same port**, though the 2026-11-15
run's failing test was never named, so this is a matching fingerprint rather
than proof: a lone test, three asserts failing together, gone on the next run.
A failure with that fingerprint was diagnosed on 2026-11-16 and fixed. Left
here in full because the way it was found is the lesson, not the bug.

A full run reported **536 of 537 passing**, the next run with no code change
was clean, and so were ten after it. The failing test's name had not been
captured. All that was known was that three asserts in one test had failed
together, so it was one test rather than a stray engine error. The first
theory — that `test_user_settings.gd`'s teardown removed a file that was not
there and Godot logged an error GUT would count — was probed and disproved:
`DirAccess.remove_absolute` on a missing path returns a failure code and logs
**nothing**. The note closed by asking whoever saw it next to capture the name.

It happened again on 2026-11-16, and the name was there:
`test_leaving_a_lobby_frees_the_port_for_the_next_attempt`, three asserts,
with `ERROR: Couldn't create an ENet host` underneath it. Tests that bind a
socket were each picking a port at random from a range of five hundred. Seven
draws in one script makes a collision about one run in twenty, and a collision
fails only when the first test is still holding its port — which is why it was
rare, and why it never came back on demand.

`tests/fixtures/test_ports.gd` now counts instead of guessing, so no port is
handed out twice in a run. Its docstring explains why it does not probe a port
by binding it first.

**The lesson: capture the name and the engine error before re-running.** A
flake that is re-run is a flake that stays open. This one cost a day of
suspicion pointed at the wrong file.

### One fix is verified by the run dying

`test_pause_menu.gd` cannot press "yes" on the quit confirmation: that calls
`get_tree().quit()`, which in a headless run takes the whole suite with it. So
the yes is asserted as a signal connection rather than exercised.

That leaves the central claim - that the button no longer closes the game on
the press - without an ordinary assertion. It has an unusual one instead.
Reinstating the old wiring and running that file **ends the run mid-suite with
no summary printed at all**, because the test presses the button and the game
quits. A green run of `test_pause_menu.gd` is therefore part of the evidence,
not just the assertions inside it. Recorded here because it looks like a gap in
coverage and is not. See decisions.md D117.

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
