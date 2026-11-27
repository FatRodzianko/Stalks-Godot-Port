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

1477 tests in 57 scripts, about 200 seconds.

The networked tests account for most of that time — each one opens a real socket.

| File | Covers | Tests |
|---|---|---|
| `test_market_mood.gd` | 7/12 bull weighting, labels, degenerate weights | 5 |
| `test_random_range_price_model.gd` | Contrarian rate, inclusive range endpoints, softening thresholds, truncation direction, static stalks | 8 |
| `test_event_pool.gd` | Pool sizes 45/45, no repeats within a cycle, refill on exhaustion, bankrupt-target skipping without consuming | 9 |
| `test_trade_rules.gd` | Buy/sell validation and rejection reasons, max affordable, net worth with holdings and loans, ranking and tie-breaking | 25 |
| `test_year_resolver.gd` | Split rounding, threshold boundary, both bankruptcy passes, dividend sequencing, displayed yearly change, 10- and 99-year matches, determinism | 21 |
| `test_golden_history.gd` | **The base game is bit-for-bit unchanged** (StalkleHeads P5, D127): one seeded 99-year match on the shipped content, with a rotating trader, a borrower who defaults and a borrower who misses once and overpays, written year by year as sorted text — prices, deltas, splits, bankruptcies, mood, event, dividends, loan assessments, cash, holdings, net worth, standings, game end — and compared by sha256 with a recorded hash; plus checks that the match really reached a split, a bankruptcy, penalties, a default and a paid-off loan | 1 |
| `test_regime_rules.gd` | **StalkleHeads regimes** (§3.3, D131): every matrix row sums to 100 and is the published one; a neutral unaged company rolls exactly its row; the stationary distribution within half a point of 15.1 / 28.8 / 22.8 / 22.9 / 10.4 (GROWTH's row since D151); ageing taking 10 points a year off GROWTH and applying to SLOWING; STEADY and DECLINE never ageing; recovery letting DISTRESS out at 12 points a year; quality biasing both ways and its -10 to +10 range; the adjusted roll's clamp; one draw per roll; the roll following its odds over 20,000 draws; the damping ladder at 19/20 and 49/50 years; the growth, margin and premium tables | 16 |
| `test_company_fundamentals.gd` | **StalkleHeads earnings, industries, valuation, price, split and dividends** (§3.3-§3.6, §3.10a, D129-D135): year 0 at EPS x 12.5; margin a third of the way; revenue from own growth plus industry through beta; damping and retention reaching own growth and never the industry's share; earnings season drawing exactly twice; years-in-regime counting; the industry roll's carry, tilt, clamp, one draw and id order; standing; the multiple's four terms and its clamps; sentiment clamped to 20; fair value and its clamp; the one truncation; carry halving; flow's persistence, gain and **5% clamp asserted as a constant**; a desk buying everything held at the clamp; player and NPC shares counting the same; the split value-neutral with the identity holding, the §3.6 worked example, odd prices rounding up, and 300 versus 301; policy 0 never paying, DISTRESS never paying, policy 35 against the old table, the published scales, the dividend truncation, and the retention factor | 37 |
| `test_price_ledger.gd` | **The StalkleHeads ledger (P1) and determinism**: over forty seeds of thirty years on all eighteen companies, every company's ledger sums exactly to its price move and every price equals `int(fair + carry + flow)`; the event and fade lines; earnings, sentiment, standing and regime separated; a clamp reported on its own line; balancing across a split; the same seed giving the same market and a different one not | 6 |
| `test_company_content.gd` | **StalkleHeads content and its validator** (D128): the 18 profiles and 6 industries load clean with no warnings; six industries of three; the owner's industry names; the approved roster, with the owner's names from f41d317; every ticker different; shipped companies agreeing with their stalk's name and ticker; all 18 opening prices; the base game never loading any of it; and the validator refusing an unresolvable industry, an industry of one or none, a missing or duplicated ticker, out-of-range fundamentals and duplicate ids, and reporting but allowing an industry of two | 15 |
| `test_earnings_year_resolver.gd` | **The StalkleHeads year (S3)**, D152-D160: the twenty-row board, companies at their own prices, shared and built definitions, the index at its authored price; `YearSettlement` computing net worth and standings, ending the game and skipping loans when off; the earnings pipeline running the same loans and game end; same seed same match; **every ledger balancing and being the Yearly Change** over 20 seeds of 15 years; market news inside Yearly Change; the mood BULL exactly when the index rose; sentiment as last year's move clamped; **no circularity** (prices valued on the sentiment carried in, and the mood label moving no price but through the market news); **the derived bull rate between 45% and 65%** over 200 seeds; **market news (D209, D210):** bull news in year 1, last year's mood after, the shipped news fitting last year's mood and move over a whole match, drawn before prices and in them, not drawn at a bankrupt target, an industry target giving every living member the same amount, a follow-up waiting for an earlier year then coming first then becoming ordinary, a requirement never shown keeping a line out, the index never hit; the index as the mean pre-split move, a bankrupt constituent at -100 once then dropped, alive while one constituent is, failing only when all do, paying the average dividend; the bond fixed at 100 and paying 3 in both moods, and its 3% / 8% / 5-point yardstick; one bankruptcy pass wiping out holders; a dead company frozen; a split doubling holders and value-neutral; dividends from earnings on post-split shares; policy 0 never paying; the flow input consumed once; scans for mode checks in the shared files and for `pow`/`exp`/`log`/`sqrt` in the price path | 48 |
| `test_game_mode.gd` | **StalkleHeads mode and lobby (S5)**, D171: the base game the default; `MatchSetup` choosing board, pipeline, content and loans by mode; players' trades reaching flow; the mode in the snapshot and a base-content client resolving a StalkleHeads board; take-over refused without a market (since S6: a snapshot from an older build that sent none); the lobby row; the title screen's Game row and its card size; `Main` starting either mode; only `MatchSetup` branching on the mode | 33 |
| `test_wire.gd` | **StalkleHeads over the wire (S6)**, D176-D178: every snapshot of three 60-year matches rebuilding the host's market on a base-content replica to the bit, derived readouts included; year 0 as the profiles' figures; every live year replayed to the host's result, ledgers and all, then the snapshot; a year sent as inputs only; a welcomed history year for year; a rejoiner equal to a player who stayed; **a promoted host making the same thirty years the old host would have**; every year's market news reaching the client by id (D209); the squeeze's premium, share of shorts still open, rolls, spike, moves and drifts in every comparison (D213, D220); the same through real sessions over ENet; refusals of other content, short blocks, 32-bit reals, a desk entry off the board, a truncated year and a history with one broken year; the 32/64-bit packing; the layout widths pinned; the base game's snapshot and year keys unchanged; a stale market cleared; a failed company's valuation cleared; the 99-year ten-player welcome under 256 KB | 24 |
| `test_news.gd` | **StalkleHeads news (S8)**, D199-D215 (whispers rebuilt by D205, reports written by code since D215): the shipped news loading clean and covering every slot that can come up; the validator reporting every kind of authoring mistake, warning on a strategy nobody follows and checking the transition matrix; a trader's own chatter as a news line; the move and surprise bands at their edges and the expectation damped like real growth; the least-drawn line first and a full cycle before any repeat; an empty slot staying empty; a specific line beating a general one; commentary naming its company and regime; whispers honest and lying as their roll says, truth 100 and 0, a one-company whisper never lying; the triggers reading real state; chatter by trader and by strategy with tokens filled; the same match the same news; **reading the news never moving the match**; a welcomed client's and a promoted host's news equal to the host's; **D209-D214:** the twelve market headlines moved over, the ported company news, follow-ups and target errors in the validator, squeeze whispers from a Questionable source on top of the two (D218), crash whispers Questionable, heard only as often as the end is likely (D220), with whether they came true; whispers and kept draws in the final year (D219); **D223:** a loop of requires of any length refused and named once, a retired id refused, the retired-ids file shipping and read with its comments skipped | 33 |
| `test_news_flow_chart.gd` | **The News Flow Chart's core (D223)**, news-flow-chart.md Phase 1: the id for every kind from its own fields, numbered after the highest taken, retired ids never reused, no collision with the shipped news; the book each new item goes in; arrows from `requires`, chains, roots and chain keys, loops found before they are drawn; adding, editing, linking, unlinking and deleting items in fresh copies of the shipped books, saved under `user://`, reloaded and passed by the validator; the retired-ids file written under its explanation; chain names read and written, following a new root, a deleted root or middle, dropped and reported when they cannot be placed; what each dropdown offers | 27 |
| `test_news_flow_chart_ui.gd` | **The News Flow tab (D224)**, news-flow-chart.md Phase 2, on the real `news_chart.tscn` in GUT's scene tree: each chain listed by its root's id or its own name, an item on its own not a chain; the first chain's boxes shown; one arrow per `requires` inside the chain, none for an id that is not an item; choosing a chain or an item in the lists showing its members and selecting the item's box; a box's kind, id, conditions and first words; every shipped item listed and none in a chain; the search box; Arrange putting each follower right of what it requires; clicking a box filling the details panel with every field, nothing in it editable; a lost chain name and the validator's news errors in Problems; the real check run in its own headless process on the shipped books | 15 |
| `test_market_readouts.gd` | **StalkleHeads readouts (S7)**, D179: each year recording every company as it closed, and a year's record not moving with later years; year 0 read from the profile; five years of history oldest first; a P/E without earnings as no figure; an industry's average P/E as its members' mean; market shares and industry revenue shares summing to 100; the three-year move compounding; the regime caption and ordinals; the index by year starting at its opening price; breadth; bull years; the dividend shown as last year's payout; the desk's returns, nothing before it trades; short interest most first; which traders' pick a company was; no digest before year 1, then its market line, industries, surprise, dividend cut and desk pick; `TextChart` bars, the latest values that fit, a flat series, signed bars and share bars as exact strings; the shared formatter's ratios and missing figures | 30 |
| `test_stalkleheads_screen.gd` | **StalkleHeads on screen (S7)**, D180-D182, on the real `gameplay_screen.tscn`: a base match keeps its three boards and builds no tabs; a StalkleHeads match shows the four tabs in their place; one tab at a time; every row under its industry with its ticker; a header's average P/E and year; a row's figures; buying and selling through a row changing HELD; an unaffordable quantity greying B; year 0 and readying up closing the board; collapsing a group; collapse and sort changing nothing in `GameState`; sorting within groups only, and surviving a refresh; the strip's cash, rankings, desk and short interest; clicking a row opening its company with the regime named; five years of earnings; the ledger's total equal to CHG for every company; the arrows walking and wrapping; traders and investors named; the index chart and mood row; selecting an industry; the digest arriving with the year's news; the mood line carrying the index move; **a client's four tabs, line for line, equal to the host's** after a welcome; every tab fitting 640 x 360; the header lining up with a row; a bankrupt row showing BANKRUPT whole without moving a column. **S8:** the market news headline first in THIS YEAR'S NEWS, whispers, the industry headline and INDUSTRY REPORT (year line then outlook), the Company tab's EARNINGS line ("Distress. Much worse than expected."), commentary, IN THE NEWS and whispers in that order, company news for every living company every year, chatter, the short interest list as percent with FLAGGED or SQUEEZED; with no line written only the worked-out EARNINGS line is left. D208: a click away from a row's name staying on the Exchange. D218: the industry chart as text, every year that fits, each bar the same width in year 1 as later, the oldest dropped once full and on a resize, a tooltip per year. D222: a short interest entry opening its company | 79 |
| `test_balance_smoke.gd` | **StalkleHeads balance, smoke only** (§12.1, D144-D150, on the real pipeline since D161): 30 fixed-seed ten-year matches of the balance tool's nine strategies; the same seed replaying the same match; a strategy subset leaving the market unchanged; the bond player ending on 13,426 every time; splits, bankruptcies and bull-year rate in wide bands; no strategy winning three in four; RANDOM keeping half its cash; the best reader beating RANDOM; the sweep's lever overrides, set to the published values, reproducing the real path exactly, a moved lever moving the market, a rebuilt GROWTH row summing to 100, and the SHORT-target lever at its published value changing nothing while `slowest` moves the market. Does **not** assert P4 | 16 |
| `test_loan_rules.gd` | Annuity arithmetic, eligibility, the full ten-payment schedule, penalties and default, overpayment, one-loan-per-game, pipeline integration | 40 |
| `test_marquee_label.gd` | The scrolling name label: overflow detection against the real font, hover and click-to-pin, character-by-character stepping, a two-second hold on the end of the name before going back (D175), reset on leave | 14 |
| `test_content_library.gd` | The shipped content loads and validates clean, stat blocks match the documented table, 45/45 pools, deterministic order, a full match played from real content, and every validator rule rejecting bad content | 29 |
| `test_local_session.gd` | Session start-up, seed recording, trading and its rejections, pre-checks agreeing with enforcement, ready-up and year advance, a two-player wait, a full match, loans through the session | 26 |
| `test_gameplay_screen.gd` | **Scene tests** driving the real screen: rows built, header figures, buying and selling through actual controls, live validation disabling the Buy button, bankrupt presentation, event and year-summary display, header/row column alignment, ellipsis on long names, the UI matching a headless run of the same seed, and the "... MORE" button taking no width from the description, sitting in its bottom right corner and landing between characters rather than through one (D107a), and a scroll bar wide enough to see and lighter than its track (D173) that shows only when its list overflows, with every list reserving its width (D174), the bottom bar's message and both buttons sharing the bar's middle with and without a loan, the messages running up to the ready button, and the event strip stepping a line at a time with "... MORE" in one column and every word shown (D175) | 64 |
| `test_state_sync.gd` | What crosses the wire, which as of 2026-11-18 is the whole match (D105): a rival's cash, holdings and loan schedule all arriving, every player being sent the identical snapshot — the property host migration rests on — the random stream's position travelling, snapshot and `YearResult` round trips, mismatched content being reported, and a walk of the whole payload asserting nothing in it is an object | 23 |
| `test_main_migration.gd` | **The orchestration**, driven end to end without Steam: the host leaving being noticed, Steam not having decided yet, Steam still naming the leaver, being made the owner and standing down a turn before hosting, following somebody else and retrying, giving up after twenty seconds, the dying connection not cancelling the migration, and a taken-over lobby being advertised again, keeping its name, and being hidden instead when a match was under way; **a handover during the result screen** - a finished match still being carried over rather than re-hosted as a lobby, the player staying on the standings, the lobby being marked finished rather than advertised; all three branches of `_show_the_screen_for`, including the one nothing can reach by playing yet; the result screen not offering Play again in a networked match; an open confirmation being withdrawn by a screen swap, and a rematch that starts without you leaving you on the standings with its way in closed (D122, D123, D124) | 29 |
| `test_away_players.gd` | **What the match does to a player who is not there** (D110): the year gate skipping them while still waiting for everybody present, a deserted match refusing to resolve years at all, dividends paid, splits doubling their shares, a bankruptcy wiping them out, net worth recomputed, every year away counting as a missed loan payment through the 10% and 15% penalties to seizure on the third, their place in the rankings kept, a match won while absent and a lead lost while absent, a lone survivor refused a yeehaw nobody could give, and the flag crossing the wire | 20 |
| `test_main_rejoin.gd` | **The orchestration of REJOIN GAME**, driven without Steam (D111): the lobby being remembered on the way to the board but not for a solo game, the newest match overwriting the last, the match ending forgetting it, the button offered only when there is something to rejoin and sitting opposite QUIT TO DESKTOP, the remembered lobby being asked for, a client built rather than a host, the screen not swapping until the welcome lands and then showing the board, a match that changed hands being rejoined through its new host, Steam's refusal and the host's refusal each reaching the title screen as a sentence, a refused rejoin keeping the record, the handlers coming off once it has landed, and going back to the title screen cancelling one in flight. Then **whether the remembered game is still on** (D115): Steam being asked about the lobby before anything is offered, a lobby still playing being offered, one that no longer exists and one whose match is over both being forgotten, Steam's silence hiding the button without forgetting, Steam being closed asking nothing, an answer about another lobby being ignored, the question being re-asked on the timer and only on the title screen, the button going away when the match ends out there and coming back when Steam answers again, leaving a lobby you were the last one in forgetting it while leaving one others are still in keeps it, and the host - and only the host - marking the lobby finished | 38 |
| `test_lobby_migration.gd` | Who takes over a lobby when its host leaves, with no Steam in it: waiting while Steam has not decided, the departed host's id not being mistaken for a new owner, becoming the host, joining the new one, giving up after twenty seconds, and a late answer still being acted on | 9 |
| `test_host_migration.gd` | Continuing a match on a new host: the year, prices and **every** player's position surviving the handover, the departed host staying in the match marked away, everybody else starting away so the year gate cannot hang while they reconnect, the random stream being picked up rather than restarted, and reclaiming a seat — matched by Steam ID, refused without Steam, refused for a seat already being played, landing them back on the position the match built for them, keeping the player's place in the roster order, and what `why_not_rejoin` decides - a seat-holder let back into a **finished** match, which amends D111, and the two sentences a stranger gets depending on whether that match is running or over (D122) | 23 |
| `test_networked_session.gd` | **Networked tests** with a real host and client in one process: joining and seating, yeehaw in both directions, a refused self-yeehaw, a client's buy applied by the host, an unaffordable and a nonsense request refused, a refusal reaching only the asker, a client unable to act as another player, a client ending up holding the host's whole match and still being unable to spend a rival's money, the all-ready gate, both sides agreeing on every price after a year, the disconnect behaviour including the deadlock it used to cause and a dropped player now staying in the match marked away (D110), and **the whole reclaim over a real socket** - a returning Steam account seated back on its own slot with the position the match kept for it, the away flag cleared, a stranger's account refused the waiting seat, and the reclaiming client being told the match is under way (D116) and **remembering it** so a later migration can tell a lobby from a match, which a client in a lobby does not (D122) | 48 |
| `test_lobby_screen.gd` | **Scene tests** for the title screen (Create Game and Join Game; one settings panel serving all three ways to start a game; a joiner offered none of them; the lobby's invite button and invite-only games; the host naming the match, that name heading the lobby on both machines, and an online game taking its player names from Steam rather than from the title screen) and the lobby over a live host session: the player list, who you are and who is hosting, arrivals and departures, ready-up both ways, Start being the host's alone, the all-ready gate and the host's kick that escapes it, that the host has no ready button because Start is their readiness, and `Main` opening a lobby, reporting a busy port and carrying on into the match; and the volume slider neither previewing until it is let go nor leaving a clip sounding into the next drag, both reported from play | 70 |
| `test_client_board.gd` | The client's path from lobby to board, which nothing covered before two windows were played for real: the board building and filling for a `ClientSession`, a swapped-out lobby or board ignoring the signals that follow it, a live one still updating, a removed player returned to the menu with the reason, the board visibly acknowledging a Ready press — readying, un-readying, naming who it waits for, and showing another player's dot — and the host going away mid-match, which leaves the board reporting it and `Main` listening | 25 |
| `test_display_settings.gd` | The resolution list as arithmetic over a monitor size handed in as a number: every offer being exactly 16:9, a monitor offered only what it can show, a 16:10 and an odd laptop panel both resolving to the tallest 16:9 that fits, a saved size too big for a replaced monitor being reduced, and the layout scale including the 1.5x half-step | 14 |
| `test_confirm_panel.gd` | The yes/no overlay and its revert countdown: starting at the number given, stopped by an answer, cleared when the panel is reused for a plain question, visible in the message, and — the one that matters — nobody answering counting as no | 6 |
| `test_pause_menu.gd` | Escape during a match opening the pause overlay rather than offering to end the game, leaving still asking first, the overlay not surviving a screen change, its volume slider applying without a preview clip, both quit buttons being present and wired, and **quitting to desktop mid-match asking first** (D117) - the question raised, its yes wired to `quit_to_desktop`, saying no leaving the match untouched, the two confirmations not sharing a panel, the pause menu getting out of the way, and the title screen still asking nothing | 16 |
| `test_title_screen_shape.gd` | The rebuilt title screen: the card being the same size on every tab and the heading and quit button not moving, no address form anywhere on it, the development overlay hosting and joining, the lobby list's search filtering and not sticking across a refresh, the pause menu showing the same settings panel as the title screen, and the layout corrections from play: a start button narrower than the panel and over to the right, a quit button clear of the panel, a confirmation that carries the theme wherever it is parented, and the development overlay being on a canvas layer above the game rather than inside a container that swallowed its clicks, and the settings column starting at the same place on both tabs, where the first two tabs meet (D173) | 23 |
| `test_lobby_row.gd` | What a browser row tells a joiner before they commit: the year limit, the starting cash and whether loans are on, each one omitted rather than guessed when the lobby did not publish it, and a full game offering no join button | 8 |
| `test_rematch.gd` | **Playing again with the same people**, over a real socket: a rematch only being offerable once the match is over, offering reopening the lobby at year 0 with a new seed and the same settings, a second offer doing nothing, the host seated with its own name and Steam ID and the host marker moving, a client being told an offer is live, taking a seat and keeping the name and **Steam account** it played under, both ends able to resolve a year and apply a buy immediately afterwards, everybody starting level with no holdings or loan, the year-by-year not carrying over, a player who never joins being left out and not holding Start up, that player being told it started without them, and the asking — recorded once however often it is sent, gating nothing, forgotten when an offer goes out, and withdrawn when the asker leaves; and the result screen saying both halves of it in words — the host told who asked, a client told the host has restarted the lobby, and the final board carrying the same line without losing the one saying the match has ended (D124) | 22 |
| `test_panel_sizes.gd` | **Panels that must not change size under the player**: the result card the same height on either tab and for two players or ten, the lobby card the same for one player or ten and for a one-line or a two-line status, both still fitting a 720-tall window, the roster window not resizing whoever is in it, and the lobby lining up with the title screen at both ends (D125), and the title screen not moving when it shows, wraps or clears a message, or when the player changes tab, and the message landing clear of the column and on screen whether it wraps or not, every screen laid out at the 640x360 the game is actually drawn at, the supporter screen included (D126) | 16 |
| `test_final_board.gd` | Looking at the board after the match: the result screen offering it, the board rebuilt from the session the match actually ended in rather than a fresh one, the bottom bar becoming the way back, that same button still readying up during a real match, going back and forth repeatedly, asking for a board when there is no match, and Play again surviving in a solo game where it is the only place it works (D122) | 8 |
| `test_steam_identity.gd` | Everything around the Steam calls without making any: a player's Steam id surviving the snapshot and deliberately not being redacted, a lobby row taking the portrait that is its own and refusing one that is not, a player with no account never showing a blank, the supporter thank-you appearing only when it is earned, and every Steam-shaped question answering no when Steam is absent | 12 |
| `test_splash_screen.gd` | The studio logo: that it ends, that it ends only once however many times it is told to, that a key or a mouse click gets rid of it while a key release does not, that it times out on its own, that a headless run never shows one, that it hands over to the menu, and that the fade takes the time its constants say - added after a timing change appeared to do nothing | 10 |
| `test_audio_service.gd` | Sound, checked without listening: a mood being **two** clips layered rather than one, a bankruptcy being glass **and** a scream, the screams taking turns, every clip within 1 dB of the volume preview's loudness (D221, reported from play as painfully loud), a yeehaw being one, six voices surviving a year and a yeehaw landing together, volume round-tripping with zero meaning silence rather than quiet, the volume preview having a voice of its own so a second one replaces the first instead of echoing over it, and the SFX bus existing at all — without which every volume assertion would agree with itself and mean nothing | 15 |
| `test_user_settings.gd` | Preferences kept between runs: full volume on a first run, a volume round trip, silence staying silent, a hand-edited nonsense value clamped, a corrupt file reading as a first run rather than crashing, and the title screen remembering **nothing** — the guard on a convenience that was added and then removed the same day | 7 |
| `test_achievement_rules.gd` | What a match earns, decided without Steam: the all-in and diversified thresholds and their near-misses, borrowing and settling, a split or bankruptcy judged from the holdings **before** the year (a bankrupt stalk's shares are zeroed, so the current state would never award it), winning and losing being exclusive, the net-worth targets including the starting-cash guard that stops one being bought, doubling and halving, long-match ids, the lifetime ladders awarding every rung reached, and that every id these rules can award is in the catalogue | 28 |
| `test_achievements.gd` | The achievement catalogue: 25 distinct ids, none differing only by case (the bug the original shipped), none padded, the win achievement keeping the spelling that actually fired, and a rematch forgetting the position the previous match ended on before judging its own first year (D124) | 11 |
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

### The golden history: one hash that guards the base game

`test_golden_history.gd` is a different kind of test from everything else in the
suite. It does not state what a rule should do. It records what the whole base
game **did** in one seeded 99-year match and fails if any of it changes. It was
written in StalkleHeads phase S0, before any StalkleHeads code, so that phase S3
(which moves loans, net worth, standings and the game-end check out of
`YearResolver`) can prove the move changed nothing. See
[stalkleheads-design.md §12.1](stalkleheads-design.md) and [D127](decisions.md).

**A failure means a base-game outcome moved.** It does not say which one. Every run
writes the full record to `user://golden_history_record.txt` (the failure message
gives the real path on that machine). To find the change, run the test at the last
commit where it passed, copy that file aside, run it again on the current code,
and diff the two: the first differing line is the first year and the first value
that moved.

**Only update the hash for a deliberate rule change**, and record it in
`decisions.md` when you do. The header of the test says the same thing. Rewording
display text (mood labels, event flavour, stalk names) does not affect the record;
changing a stalk's numbers or an event's price change does, because those are
rules of the game.

**It was shown to bite** when written: flipping split rounding from up to down, and
separately adding 1 to one player's net worth in year 50 only, each changed the
hash. Both were reverted.

### StalkleHeads fundamentals: what is covered and what is not

Phase S1 of [stalkleheads-design.md](stalkleheads-design.md) added the four
`test_regime_rules.gd`, `test_company_fundamentals.gd`, `test_price_ledger.gd` and
`test_company_content.gd` files above. Three things about them are worth knowing.

**Odds are enumerated, not sampled.** `RegimeRules.regime_for_roll` is a plain
function of a roll from 1 to 100, so `RegimeRules.odds` tries all hundred and the
tests assert exact percentages. Only one test samples, to check that `roll_next`
really follows those odds.

**Draw counts are checked against a twin.** A test seeds two generators the same,
runs the code under test on one and makes the documented calls by hand on the
other, then compares their `state`. It compares calls rather than counting state
steps because one `randi_range` call can take more than one step (D131).

**The ledger test uses its own loop.** `test_price_ledger.gd` was written in S1,
before the pipeline existed, and calls the pieces in §4's order itself with a random
event and random net shares. It still does: random net shares exercise flow, which
the real pipeline cannot until S4's desk. The real pipeline's ledgers are checked in
`test_earnings_year_resolver.gd`.

### StalkleHeads year: what S3 covers and what it does not

`test_earnings_year_resolver.gd` covers the pipeline item by item (the table above).
Three things about it are worth knowing.

- **Tests that need one event build their own `EventPool`**, and tests that must not
  be disturbed by an event use an empty one. A pool of one event, like an empty pool,
  draws nothing from the RNG, so a run with and without it sees the same market.
- **A company is sent bankrupt by wiping out its earnings** (`_doom`), not by setting
  its price, because the pipeline recomputes the price from earnings.
- **The no-circularity test is two tests.** One checks that every company was valued
  on the sentiment carried in. The other flips last year's mood label in a run with
  no events and checks that no price changes.

**Not covered yet:** players' trades reaching flow in a real match (S5, through
`MatchAuthority`); the mode flag and picking the resolver (S5); the wire, migration and rejoin in a
StalkleHeads match (S6); anything on screen, including a second loan being offered
(S7); events with industry or market effects (S8). The "every money figure that
leaves the sim is an `int`" check is answered by static typing: every money field on
`EarningsYearResult`, `StalkYearChange` and `StalkState` is declared `int`.

**The multiple-loans toggle** (D159) is covered in `test_loan_rules.gd` (off by
default; a settled loan frees the slot; still one at a time; nothing changes with
loans off) and `test_state_sync.gd` (it travels in the snapshot).

### StalkleHeads NPC desk: what S4 covers and what it does not

`test_npc_desk.gd` covers phase S4 item by item, every test seeded.

| Item | What is asserted |
|---|---|
| The content | 24 traders, three per strategy, sorted by id; every name and chatter line is a placeholder beginning `NPC NAME: ` or `NPC CHATTER: `; a duplicate id, a conviction over 100 and a zero starting cash are refused; the base-game library loads no traders; the squeeze template exists and names no target |
| Sorted order (§5.4) | A desk built from the content reversed still acts in id order |
| Fixed draw count (§5.4) | A desk on a live market and one on a market where every company is bankrupt leave the RNG in the same state, and that state is exactly two bounded draws per trader |
| The appetite draw | Stays within 70-130 over twenty years |
| Same seed, same desk | Two twelve-year matches on one seed end with every trader's cash, holdings and shorts identical: the StalkleHeads sibling of `test_the_same_seed_reproduces_a_whole_match` that design §5.4 asks for |
| Not players | A year advance adds nobody to `players` or the standings |
| The eight strategies | Each pick on a hand-set board, including VALUE ignoring a loss-maker, INDEXER never substituting for a bankrupt index, PANIC's bond in a bear year and its pick in a bull one, GROWTH needing a positive base, SHORT betting against the highest P/E and ignoring a loss-maker, and no strategy picking a bankrupt company |
| Trading | A long trader's sale and purchase to the coin; a short sale leaves worth unchanged and is the short interest; a short is covered when the target moves; bankruptcy, splits and dividends for holders and short sellers, alone and through the pipeline |
| Flow | The desk's net shares are exactly the next year's flow input; the next price's flow is the identity's from those shares; flow stays within 5% of fair value every year of a 25-year match |
| Short interest (§5.3) | The flag (10%) and the chance (25%) as constants; most shorted first; over 400 seeds a squeeze fires about a quarter of the time when flagged and **never** when not; a squeeze fires exactly when the roll is at most the chance; without a template nothing squeezes and the stream is the same; the desk's own SHORT traders flag something in a real match |
| The meme-stock squeeze (D213, D220) | The spike as 5% a point, capped at 150%; covering the year's roll, rounding up, and all of it once the fuel is gone; the end chance and the drift at their edges; a squeeze lifting the most shorted company by its spike plus anything the year took off, on the ledger's squeeze line, with the shorts still open; each later year ending exactly when the roll says, the whole lift off, or drifting by the rule, on the ledger; over many squeezes, none over in its own year, some in their second, some four years or more; a squeezed company never shorted more and never FLAGGED; FLAGGED and NONE read from the desk |
| Players cannot short (§14 q10) | Selling shares not held is refused, by the base game's unchanged rule |

**Not covered yet:** the desk in the snapshot, migration and rejoin (S6); anything on screen, including the published
short interest and the strategies' help panel (S7); chatter and the short-interest
news line being chosen (S8). Since D214, a squeeze or crash whisper's subject and
source are not asserted in a seeded match (only that ordinary whispers stay true);
manual section V checks them on screen.

### StalkleHeads mode and lobby: what S5 covers and what it does not

`test_game_mode.gd`, 33 tests, covers phase S5 (D171). Seeded throughout.

| Item | What is asserted |
|---|---|
| The default | `GameSettings.mode` is the base game; every mode has a name and a lobby word; a number that is not a mode reads as the base game |
| Read in one place | A scan of every script in `src/` finds no comparison with a game mode outside `match_setup.gd` and `game_mode.gd`; `test_earnings_year_resolver.gd`'s scan of the shared files now includes `match_authority.gd` |
| The choice, made once | `MatchSetup` gives the base game `YearResolver` and StalkleHeads `EarningsYearResolver` with the library's squeeze template; the base game loads no StalkleHeads content |
| The base game unchanged | A base match is the same board, in the same order at the same prices, as `build_stalk_states`; no market; one loan per match. `test_golden_history.gd` is the proof that its year is unchanged |
| StalkleHeads | A market beside a board of every company plus the bond and the index; `multiple_loans_enabled` on; a year advances and returns an `EarningsYearResult` |
| Players' trades in flow | A purchase adds its shares to the flow input and a sale subtracts them; a refused trade records nothing; on one seed, a match where the player buys ends the next year with more flow and a different price for that company than one where they do not; a base-game trade touches no market |
| The wire | The mode round-trips in the settings; a snapshot without one is the base game; a client holding only the base content resolves every row of a StalkleHeads board at the host's prices; a promoted host refuses a StalkleHeads match with no market, and a base match is not refused |
| The lobby row | A StalkleHeads or base lobby names its mode first; one that published none, or a word this build does not know, names no mode and keeps the rest of the row |
| The title screen (scene tests) | The Game list offers every mode by name and starts on the base game; the choice reaches the settings on both tabs; on the host tab, the one with the most rows, the card is exactly its authored size |
| The screen host (scene tests) | `Main.start_match` builds a StalkleHeads match with a market and a base match without; a StalkleHeads year runs on the existing playing screen |

**Not covered, and why.** Steam lobby data is never written or read by the suite (no
test may touch Steam), so publishing `mode` and reading it back is checked by hand,
[manual-testing.md](manual-testing.md) C3. A real client joining a StalkleHeads lobby
over a socket is not in `test_networked_session.gd`; the snapshot test above covers
what it depends on, and C4 covers the rest by hand. Migration and rejoin of a
StalkleHeads match are S6, below. Anything about how it looks beyond the card size is S7.

### StalkleHeads over the wire: what S6 covers and what it does not

`test_wire.gd`, 24 tests (D176-D178), with `tests/fixtures/wire_match.gd`.

**The property.** A client's copy of a StalkleHeads match, built from what the host
sent, is the host's match. Every comparison writes both copies out as lines of text,
one per field, every float as its 64 bits in hex (`WireMatch.state_lines`,
`result_lines`), and reports the first line that differs. So a pass means identical,
not close, and a failure names the field.

**The ways a copy is made, each tested:** a snapshot onto a fresh replica that loaded
only the base content (every year of three 60-year matches, which are asserted to
include splits and bankruptcies); a live year replayed and then its snapshot applied;
a whole history replayed from year 0; a host migration followed by thirty more years
on both hosts; and the real `HostSession`/`ClientSession` pair over ENet loopback.

**Shown to fail.** Each of these faults, put back by hand, failed the file: the split
halving left out of `derive_readouts` (3 tests), a failed company keeping its
valuation (4), the replay ignoring the flow input (3), the snapshot dropping the
desk's shorts (4), and `ClientSession` applying the snapshot before replaying the year
(the ENet test: every result a year late). The event-bag test is itself the fault
check for D177.

**The base game.** One test pins the base game's snapshot and year-record keys, so a
new key would fail it; `test_golden_history.gd` still proves its year unchanged.

**Before S6 was built**, a fingerprint of three seeded 99-year StalkleHeads matches -
every field of every company, industry, trader, row and player, every year - was
recorded, and the refactor of `EarningsYearResolver` into its two halves was checked
against it: identical, apart from the valuation readouts of failed companies, which
D176 clears on purpose. That probe was a one-off and is not in the suite; the
comparisons in `test_wire.gd` are what guard the two halves from here.

**Not covered, and why.**

- **Steam.** No test may touch Steam. Whether a StalkleHeads match migrates and
  rejoins over Steam between two machines is [manual-testing.md](manual-testing.md)
  D1-D4, passed by hand on 2026-11-22.
- **Two different machines.** Every test runs both ends in one process, on one CPU
  and one build. That float arithmetic gives the same bits on two machines running
  the same build rests on IEEE 754 and on the price path using no transcendental
  functions (D130); D2 and D3 are where a difference would show.
- **The payload over a real socket.** `tools/wire_report.gd` measures the encoded
  size, not what Steam or ENet add to it.
- **Nothing on screen.** Covered since S7, below.


### StalkleHeads on screen: what S7 covers and what it does not

`test_market_readouts.gd` (32) and `test_stalkleheads_screen.gd` (63), `test_drawn_chart.gd` (13), D179-D191.

**After the first play (D183)**, tests for each finding: the arrows walk the board's
order; the identity line keeps the industry whole; one tab lit after opening a
company; the side panel opens and closes as asked; holdings listed and sold from;
the trade box keeps its place with S greyed; the sorted heading's marker; trading
from an industry's members and the Company tab; the ledger's YoY; clicking the event
opens the year in review; the digest's sentiment line; the news panel's tick box
showing the setting (`test_gameplay_screen.gd`).

**After the second play (D184)**: the side panel lies over a tab without changing
its width and beside the board without covering it; the holdings are compact
`HoldingRow`s, sell only; the arrows walk the match's order again; the company list
opens, picks, closes and counts the desk's holders; the NPC table's heading and
lines; `TermTips.fit`; every visible tooltip on every tab within `MAX_CHARS`.

**After the third play (D185)**: sorting moves no heading and the headings take
their cell, hover and lit styles; an industry header has no tooltip; the Company
tab's title line is outside its scroll; the company list sorts by each heading;
the year in review's captions are capitalised.

**After the fourth play (D186)**: the longest description is shown with every line
visible and no trimming; every board heading's style has a margin either side, and
`PRICE^` fits its column without widening it.

**After the fifth play (D187)**: a signed chart colours bars above zero in the gain
colour and below in the loss colour, and leaves the axis and captions plain; the
industry chart shows colour while `chart_text()` stays plain. The placeholder
descriptions are not tested, at the owner's word.

**Drawn charts (D188)**: `test_drawn_chart.gd` tests `ChartGeometry`'s placing -
the scale (NAN skipped, bars reaching zero, a flat scale widened), the top and
bottom of the plot, slots and finding the slot under the mouse, candles never
vanishing, bars side by side from zero, captions thinning, labels within five
characters, the legend's room - plus `DrawnChart`'s tooltip, its message, and
split adjustment. The screen tests: the index chart is a line of the index levels;
each Company tab view shows its kind of chart at the table's size with one button
lit; switching to a chart moves nothing below (it takes the table's measured height); candles open at last year's close and today's price is not restated; the bond
has no buttons; dividends and industry P/E by year. **Not tested:** the drawing
itself (checked by eye, manual-testing.md section K).

**The year in review on the Market tab (D189)**: it is shown, narrow (two industry
columns, the market on two lines), inside the right half's own scroll; year 0 hides
it.

**Owned companies (D191)**: the company list stars exactly the companies the player
holds, and its heading reads NAME (* OWNED).

**The rule they protect.** No node works out a figure. So the numbers are tested in
`test_market_readouts.gd` without a window, and the screen test checks that each tab
shows what `MarketReadouts` says, not what the screen thinks.

**The client.** One screen test welcomes a client from the host's snapshot and
history, refreshes both screens and compares every line of every tab. Because the
per-year record is written in the half of the year a client replays (D179), this is
the test that would catch a figure the client cannot rebuild.

**Layout.** Two tests measure instead of looking: every tab's combined minimum size
is within 640 x 360, with the side panel shut and open, and the header's columns start where a row's do. A third checks
a bankrupt row's word is not clipped.

**Not covered, and why.**

- **How it looks.** Colours, the text charts' shapes, readability on the CRT. A
  developer tool renders the four tabs and the digest to pictures with Movie Maker
  (`tools/stalkleheads_shot.tscn`, instructions at the top of its script); a person
  looks. Manual steps E1-E6 in [manual-testing.md](manual-testing.md).
- **Hover and scrolling.** The name marquee and the board's scroll bar are the base
  game's widgets, tested there.
- **Tooltips.** That each one appears where the mouse is, over the CRT. Section F.
- **Over Steam.** The tabs draw only from state the suite already proves identical
  on host and client (S6). E6 checks it once by hand.
- **News headlines, whispers and chatter.** S8.

### Private messages: what is covered and what is not

`test_messages.gd` (74) and `test_messages_wire.gd` (18), D192-D193, D195-D196; three
`--game` cases in `test_launch_args.gd`; the DEV panel's game button (D194) in
`test_title_screen_shape.gd` (it names and switches the game, HOST carries it) and
`test_lobby_screen.gd` (HOST opens a StalkleHeads lobby with its market).

- **The sanitiser**, one test per threat in architecture.md §5.8: printable ASCII
  untouched, emoticons, markup and network paths kept as text, newlines and tabs to
  spaces, control characters removed, bidi and zero-width and other non-ASCII to
  `?`, the length cap and that
  leading space does not use it up.
- **The rate limit** with an explicit clock: the count, the sliding window, one
  limit per sender, and that the host's is looser than a player's.
- **The relay rules**: unknown recipient, unknown sender, a note to yourself.
- **The book**: unread counts, sent lines never unread, one ordered conversation per
  player, cleaning on arrival, the 200-line cap, clearing.
- **The ALL PLAYERS room** (D195): it may be relayed to and can never be a player's
  id; a room arrival lands in the room, not the sender's chat; your own copy is kept
  and not unread; sending to it is rate limited.
- **Blocking** (D196): a blocked player's private and room messages are dropped;
  everybody else is still heard; blocking marks their chat read and keeps what was
  said; unblocking hears them again but not what was dropped; `changed` fires;
  clearing forgets blocks.
- **The send path** on a `LocalSession`: notes stay local and are not limited, text
  is cleaned, empty and unknown and away recipients are refused, the player's own
  limit refuses with a reason, and the match's snapshot is unchanged by messages.
- **Over ENet**: delivery both ways; the sender's own copy; between two clients the
  host keeps nothing and the sender is not echoed; a note never reaches the host;
  the match unchanged on both sides; and the hostile cases sent straight through
  `_rpc_send_message`, skipping the client's checks - a forged sender, unknown and
  overlong recipients, addressing yourself, dirty text, a flood past the host's
  limit, and a client asked to relay. With three players: a room message reaches
  everybody but its sender, and is not echoed; the host's own room message reaches
  every client once; the host cleans room messages; a blocked player can keep
  sending, is still heard by the others, and nothing about the block reaches the
  host or them.
- **The tab**, on the real playing screen: the caption; the tab's dot and each
  name's dot, grey and yellow, and their size and colours; every player listed
  including you; opening a chat reads it and puts the dot out; a line arriving in an
  open chat is read at once and on another tab is not; the header; send empties the
  box; Enter (a real key event) and SEND both leave the cursor in the box (D198); a refusal keeps the text and says why; the box's length cap; two chats and
  the third replacing the less recent, by clicking and by typing; every line a
  `Label` and no `RichTextLabel` on the tab; a solo game lists only your notes; a
  base-game screen has no tab. ALL PLAYERS listed first, absent in a solo game,
  with its own dot and header; BLOCK? on a chat with a player and not on notes or
  the room; pressing it blocks, turns it to UNBLOCK and marks the header and the
  name; pressing again undoes all of it; the `BlockedName` look is in the theme.

**Not covered, and why.**

- **How it looks**, and whether the history scrolls to the newest line on a real
  screen: `tools/messages_shot.tscn` renders the tab with Movie Maker (instructions
  at the top of its script), checked by eye; manual-testing.md section O.
- **Two real processes.** The ENet tests run both ends in one process;
  section O runs two copies of an exported build.
- **History across a rejoin**: none is kept, by design (D192). Blocks are lost
  the same way (D196).
- **Across a host migration** (D197): `test_host_migration.gd` checks a new host
  keeps an adopted book, lines and blocks, and that later messages land in it. The
  `Main` plumbing that hands the book over needs Steam: section R.
- **That the grey of a blocked name is readable**: frame 31 of
  `tools/messages_shot.tscn`, by eye; section Q.

### StalkleHeads news: what S8 covers and what it does not

`test_news.gd` (29 tests) and more in `test_stalkleheads_screen.gd` and
`test_earnings_year_resolver.gd`, D199-D215.

**Covered.**

- **The content.** The shipped news loads with no errors or warnings, in the
  numbers shipped (the owner's 12 market news headlines, none still prefixed and
  none moving a price yet; 85 company news lines, 12 whispers, 120 trader lines); every base event
  of a StalkleHeads company is its company news, word for word, two per move band
  (D211); every slot that can come up has a line (every mood and move market news
  can have, every industry at every move, every move for company news, a squeeze and a crash whisper, every outcome a
  whisper can tell about a company and about an industry). That second test stays
  true whatever the words become.
- **The validator.** One test plants every kind of mistake - an industry, company or
  trader that does not exist, a misspelt token, a token the kind of line does not
  fill, a whisper that foretells no outcome, a whisper about the wrong kind of subject, an empty
  line, a duplicate id, a band number that does not exist, market news with two
  targets, a target that does not exist or an amount with none, a line that
  requires itself or an id that is not a line - and checks each is reported. A strategy nobody follows is a warning, not an error; the transition
  matrix rows sum to 100.
- **The selector.** The move and surprise bands at their edges; the expectation
  damped and retained like real growth; the least-drawn line first; four lines for
  one slot over twelve years coming round once per cycle (both on energy's
  industry headline, which is drawn every year); an empty slot staying empty in
  every category, while the two reports are still written; an industry's own
  headline beating a general one, with `{industry}` filled in.
- **The reports (D215).** `ReportWriter`'s wording word for word ("Mafia HUD Scam's
  revenue fell 14%, far worse than expected. The company is in distress.", "held
  steady" at 0%, "Airways'" for a name ending in s, "again" for a crash after a
  fall and never without a last year); a sentence for every move, surprise and
  regime; over a whole match, every company's EARNINGS report equal to one written
  again from its revenue growth, surprise and regime.
- **Whispers (D205).** Next year's draws are made when the match opens and at each
  year's end, and the next year uses exactly them; none is made after the last
  year. No round in year 0; the first is heard after year 1, about year 2, and none
  after the last year (D207).
  Over thirty years, every whisper's true outcome (squeeze and crash whispers aside) equals one worked out again from
  the next year's record; two a round, never about one subject twice, about both
  companies and industries, each naming its subject. The line heard is written
  for the outcome its source told, and some are wrong. Each source's odds hold
  within 2 points over 20,000 seeded draws; Rock Solid is never two bands out; a
  bent outcome stays on the scale. A line written for one subject beats a general
  one.
- **Chatter.** Each trader says its own line for what it did; a strategy line speaks
  for traders with none, with `{trader}` and `{company}` filled in.
- **Determinism.** The same match makes the same news; **reading the news every year
  leaves the match identical, field for field, to one where it is never read**; a
  welcomed client makes the host's news for thirty years; a promoted host goes on
  making the news the departed host would have.
- **On screen.** The Market tab shows the headline and the whispers with their
  sources, and nothing in year 0 (`test_no_whispers_before_trading_opens`); VIEW HISTORY lists every round newest first with its
  outcomes once known, CLOSE and leaving the tab shut it (D206); the Industries tab
  each industry's report; the Company tab each company's EARNINGS report (one line,
  nothing repeating it), company news and the whispers about it or its industry;
  the chatter under each trader in NPC ACTIVITY and on the DESK page; with no lines
  written, every slot and its heading hidden. The host-and-client comparison now
  includes all of it, and every tab still fits 640 x 360.

**Not covered, and why.**

- **How it reads.** Whether the placement and the faint chatter read well is for a
  person: [manual-testing.md](manual-testing.md) sections S and T.
- **Real words.** Every line is a placeholder. A test cannot judge the owner's
  writing, only that it is valid and reachable.
- **Two machines.** Covered in one process, as for S6; the news adds nothing to the
  wire, so section S does not need Steam.

### The News Flow Chart: what Phase 1 covers and what it does not

`test_news_flow_chart.gd` (27 tests) covers all of the tool's `core/`
([news-flow-chart.md](news-flow-chart.md) §5): ids, the router, the graph, every
edit to the books, chain names and the dropdown lists. Its books are fresh copies
of the shipped ones (`CACHE_MODE_IGNORE_DEEP`), so editing them never touches the
copies other tests use. It saves only under `user://`, never to src/data/news/,
because a headless save drops a book's `uid` line.

**Not covered, because it does not exist yet:** the Inspector dropdowns, undo,
and saving from the editor (Phases 3-4). The plugin and the Inspector can only be
checked by hand, in the running editor.

### The News Flow Chart: what Phase 2 covers and what it does not

`test_news_flow_chart_ui.gd` (15 tests) drives the tab's screen,
`news_chart.tscn`, in GUT's scene tree: boxes, arrows, both lists, Arrange, the
details panel and the Problems strip. It hands the screen news items directly
(`NewsChart.show_content`), shipped ones loaded fresh with
`CACHE_MODE_IGNORE_DEEP`, and writes nothing under `res://`. One test runs the
real Problems check, a headless Godot process, on the shipped books.

**Not covered automatically:**

- **The tab itself** (`plugin.gd`). `EditorPlugin` exists only in the running
  editor. [manual-testing.md](manual-testing.md) section Z.
- **Placeholders.** In the editor a news item's methods cannot run (D224), but
  in GUT they can, so a test would not catch a method call creeping into the
  tab's code. It was checked once with a throwaway plugin in a headless editor
  run (`<godot> --headless -e`): the boxes, the enum names in the details and the
  Problems check all worked. Section Z checks it by hand.
- **How it looks**: box sizes, the split between the panels, readability.

### StalkleHeads balance: the tool and its smoke test

Phase S2 added `tools/balance_report.gd`, the balance tool. How to run it is in
[development.md](development.md); how it is built is [architecture.md §9](architecture.md).

**What it covers.** Properties P2, P3 and P4 of
[stalkleheads-design.md](stalkleheads-design.md) §1: does reading the information win
more often than not reading it, is the no-reader still in the game, and does any one
strategy dominate a ten-year match. Each is a distribution over hundreds of whole
matches, so it is measured, not asserted: the tool prints the strategy table and the
leading strategy's win share against the 30% ceiling, and a person reads it. It plays
the real `src/sim/` classes, which is the difference from the Python probe it replaced
(design Appendix A).

**How it differs from the GUT suite.** The suite asserts exact behaviour and has to
stay fast; the tool measures distributions and takes seconds to minutes. Nothing the
tool prints can fail a build. Since S3 it plays the real pipeline,
`EarningsYearResolver`, through `tools/balance/lever_year.gd` (D161).

**The smoke test.** `test_balance_smoke.gd` runs the tool's own code over 30 fixed seeds
of ten years, in about a second, and asserts only what a badly broken market would
violate: the same seed gives the same match; running fewer strategies leaves the
market unchanged when only the desk feeds flow (D145), and changes it when the
players do (the default since S4); with no flow and no squeeze the desk moves no
price; FOLLOW plays in every match; the bond player ends on exactly 13,426 every time; splits,
bankruptcies and the bull-year rate stay in wide bands; no strategy wins three matches
in four; RANDOM's median keeps half its starting cash; the best reader's median beats
RANDOM's. **It does not assert P4**: thirty matches could not measure it. The tool
measured it at 29.6% over 4,000 ten-year seeds on the real pipeline (D161).

**Not covered yet:** news (S8); loans and leverage; Mutuals as a player's holding;
anything about how a real person plays. Re-run the tool when each arrives. The S4
measurement, with the desk, is decisions.md D167; the SHORT target that made P4 pass
is D169. S5 re-ran it once players' trades reached flow in the game: LOWPE 27.7%,
identical to D170 (D172). S8 re-ran it after next year's earnings began to be drawn a
year early for the whispers (D205): identical to D172 in every figure, as expected,
since the draws take the same place in the stream.

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
