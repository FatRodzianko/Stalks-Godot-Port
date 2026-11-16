# Porting Plan

Phased schedule for the port. Rules are in `game-rules.md`; structure is in
`architecture.md`.

**Scope comes from the original game, not from `game-rules.md`.** That document
specifies the economy exhaustively and says almost nothing about menus, settings, the
lobby browser or the pause menu — all of which are functionality a player notices.
`original-game-audit.md` inventories the whole of the shipped game and marks each
piece ported, changed or missing; its **§17 gap list** is the outstanding parity work
and is summarised below under *Parity gaps*.

**Ordering principle:** the economy is built and fully tested *before* any UI exists,
and networking comes *before* Steam. This is deliberate. The game is fundamentally a
random number generator with a scoreboard, so if the numbers are wrong nothing else
matters — and numbers are far easier to verify in a headless test than by clicking
through two Steam clients. Steam is last because it is the most
environment-dependent part and the least able to be automated.

Each phase lists what "done" means, so progress is never a matter of opinion.

Legend: 🖱️ = needs the owner's hands in the Godot editor. ❓ = needs a decision.

---

## The documentation gate

**No phase is complete until its documentation is updated.** This applies to every
phase below, in addition to its own stated criteria, and is not optional — see
decisions.md D20.

The bar: someone with no access to the original authors, no copy of the Unity source,
and **no AI assistance** must be able to read `docs/` and continue the work.

At each phase boundary, update:

- [ ] `porting-plan.md` — mark the phase done, record what was actually delivered
- [ ] `architecture.md` — any new layer, system or seam, and how it connects
- [ ] `decisions.md` — every decision taken, with its reasoning
- [ ] `game-rules.md` — any rule confirmed, changed, or still open
- [ ] `testing.md` — new coverage, and what remains untested
- [ ] `development.md` — any change to setup or workflow
- [ ] `glossary.md` — any new term
- [ ] `README.md` (in `docs/`) — the index, if documents were added

A refreshed visual code map is also worth publishing at each boundary, but the
markdown in `docs/` is the authoritative copy.

---

## Phase 0 — Scaffold ✅ Complete

Repo, `project.godot`, folder structure, `.gitignore`, strict-typing gate, docs,
smoke-test scene. Toolchain verified: import, typecheck, headless run, and
reproducible seeded RNG.

---

## Phase 1 — Economy core ✅ Complete

The heart of the port. **No scenes, no UI, no networking.** Pure GDScript in
`src/sim/` and `src/data/`, exercised entirely by headless tests.

**Delivered:** 1,024 lines of simulation across 14 files, plus GUT 9.7.1 and a
suite of **67 tests / ~12,600 asserts running in 2.4 seconds**. See
`docs/testing.md`.

**Build:**
- `GameSettings`, `StalkDefinition`, `SpecialEventDefinition` resource classes
- `GameState`, `StalkState`, `PlayerState`
- `MarketMood` with weighted bull/bear selection (7/12 bull)
- `PriceModel` interface + `RandomRangePriceModel`:
  - per-stalk range by mood
  - 10% contrarian move
  - long-game softening (>19 years, >49 years)
  - **inclusive** range endpoints
- The year pipeline: `advance_year()` running all ten ordered steps
- Splits (above 150, halve rounding **up**, double holdings)
- Bankruptcy (≤ 0, zero out holdings) — both passes
- Dividends (after splits, by mood)
- Net worth, rankings, tie-breaking
- Buy/sell validation against cash
- `YearResult` record and the year-history list

**Tests (GUT, headless) — the real deliverable:**
- Split at 151 and at 152; odd-price rounding up (153 → 77)
- No split at exactly 150
- Bankruptcy at 0 and below 0; holdings zeroed
- BERRY BONDS never moves, never splits, never bankrupts
- Dividends paid on post-split share counts
- Contrarian roll produces a gain in a bear year and a loss in a bull year
- Softening multipliers at 19/20 and 49/50 year boundaries
- Range endpoints reachable at both ends (the inclusive-range fix)
- Net worth with and without holdings, with price-0 stalks excluded
- Tie-break by cash; three-way tie means all win
- **Determinism:** same seed + same actions ⇒ identical `YearResult` sequence

**Done when:** a 10-year and a 99-year game can be simulated start to finish in a
headless test with zero scenes loaded, all assertions green. ✅ Met — both run to
completion, and a 99-year 10-player match is asserted year by year.

GUT was installed from the release zip rather than the Asset Library, so no editor
step was needed after all.

---

## Phase 2 — Loans ✅ Complete

Still pure, still headless.

**Delivered:** `LoanState`, `LoanRules`, `LoanYearChange`, wired into step 8 of the
year pipeline, with **41 new tests** (40 in `test_loan_rules.gd`, 1 added to
`test_trade_rules.gd`) taking the suite to **108 tests / 12,754 asserts in about 2.8
seconds**.

Two details recovered from the original that changed the maths — the 11-year term
counter and the interest-only first year — are recorded in decisions.md D28, and the
reference schedule in game-rules.md §9.2.1 was **corrected** as a result. One-loan-
per-game is D27.

**Build:**
- `LoanState`
- Annuity minimum payment: `principal / a(n, 6%)`, truncated to `int`
- Max loan = 25% of net worth; minimum 100; one loan at a time; from Year 2
- Yearly processing: years decrement → miss penalties (×1.10, ×1.15, bankruptcy on
  third) → re-amortise → ×1.06 interest
- Payment validation: ≥ minimum, ≤ cash, clamped to balance, overpay allowed,
  partial rejected
- Re-amortisation after payment over `yearsRemaining − 1`
- Loan balance subtracted from net worth
- Player bankruptcy: cash 0, net worth 0, holdings cleared

**Tests:** ✅ all passing
- `a(10, 6%)` payment: a 2,500 loan gives a minimum payment of 339; also 100 → 13,
  1,000 → 135, 10,000 → 1,358
- **The full schedule matches game-rules.md §9.2.1 year by year** — ten payments,
  landing at exactly 0, totalling 3,392 on 2,500 borrowed
- The first year is interest-only and counts no miss
- First miss (+10%), second miss (+15%), third miss (default) in sequence, with the
  default landing on the fourth year-end because the first year is free
- A penalty raises the minimum payment
- Minimum payment drifts by ±1 from truncation — asserted, not "fixed"
- Overpayment is clamped to the balance and lowers the subsequent minimum
- Partial payment rejected; payment above cash rejected; payment on a settled loan
  rejected
- One loan per game, even after payoff
- Loan deducted from net worth; a settled or defaulted loan is not
- The pipeline processes loans, reports defaults, and skips loans entirely when
  disabled

~~Holding the payment fixed instead of re-amortising leaves a residue — a guard test
proving the annual re-amortisation is actually doing work~~ — **dropped.** This
criterion was based on the incorrect schedule noted above. With the correct term
counter the minimum barely moves, so the test would prove nothing. Re-amortisation
still matters for overpayment, which is covered.

**Done when:** every loan rule in `game-rules.md` §9 has a passing test. ✅ Met.

---

## Phase 3 — Content ✅ Complete

**Delivered:** ten `.tres` stalk files, each carrying its own events, plus
`ContentLibrary` (loader and validator) and **29 new tests** taking the suite to
**137 tests / 13,302 asserts in about 3.3 seconds**.

- Ten `StalkDefinition` `.tres` files with the exact stat blocks from
  `game-rules.md` §3
- 90 `SpecialEventDefinition` entries (45 bull, 45 bear), ported **verbatim**
  including flavour text, bundled onto their stalks (decisions.md D29)
- `ContentLibrary` loads the directory in a deterministic order (D30) and validates
  it, collecting every problem rather than the first (D31)
- Authoring instructions in `development.md` §6

The 90 events were imported by machine rather than retyped: the `SpecialEvent` lines
were extracted from the original source, parsed (three contain escaped quotes), and
the `.tres` files were written by `ResourceSaver`. The importer was then deleted — the
`.tres` files are the source of truth from here. Retyping ninety strings by hand was
exactly the risk worth avoiding.

**Done when:** a headless test loads all content, validates it, and confirms pool
sizes of 45/45 and ten stalks all starting at 100. ✅ Met, plus a cross-check that
every shipped stat block matches the documented table, and an end-to-end match played
from the authored content.

---

## Phase 4 — Single-player UI ✅ Complete

First visible game. Still **no networking at all** — driven by `LocalSession`.

**Delivered across two increments.** A complete solo game plays end to end from the
main menu, and the numbers on screen are asserted to match a headless run of the same
seed. 77 new tests take the suite to **214 tests / 13,524 asserts in about 3.3
seconds**.

### Increment 1

- `GameSession` (the interface the UI talks to) and `LocalSession` (offline,
  authoritative in-process) — `src/net/`
- `Palette` and a generated shared `Theme` — all colour in one place
- Widgets: `StalkRow`, `HoldingRow`, `RankingRow`
- The gameplay screen: market board, holdings, standings, header with cash and net
  worth, special-event panel, buy and sell with **live validation and visible
  rejection**, ready-up, bankruptcy presentation, game-over message
- The throwaway smoke-test scene is deleted; the gameplay screen is now
  `main_scene`

### Increment 2

- Main menu with game settings: years (2–99), starting cash, loans on/off, and an
  optional seed. Player count is deliberately absent — meaningless solo, and it
  belongs to the Phase 5 lobby
- `Main`, a screen host that owns the session and moves between menu, play and
  result, so screens stay ignorant of each other
- Game-over screen: winner (or tie), final standings, how the player did against
  their starting cash, and the seed
- Loan panel: terms, maximum, status, borrow and pay controls, the escalating
  missed-payment warnings, and an **advisory, never blocking** payment prompt.
  Loans are now **on by default**
- Year summary line reporting dividends, splits, bankruptcies and loan interest —
  all of which previously happened invisibly
- The match seed on screen, in the header and on the result screen

### Layout fixes

The first increment's screen was reported as having five distinct layout faults. All
five were diagnosed by measuring the computed layout headlessly rather than by eye,
and all five are fixed with a scene test guarding the two that can regress silently:

| Reported | Cause | Fix |
|---|---|---|
| Text on stalks cut off | Name column got 199px; the longest name needs 289px | Fewer, narrower columns; dividends merged into one; ellipsis plus a tooltip (D36) |
| Everything shifts left when you buy | Board minimum widths totalled 1198 of 1248, so the stretch ratio could not apply and content changes moved the split | Minimums cut to 510/483; the ratio now governs |
| Rankings unreachable with several players | Standings had no scroll and no reserved height | Own scroll container with a minimum height |
| Special events push everything down | The panel was shown and hidden, reflowing the screen | Always visible with a placeholder (D37) |
| Dead space at top and bottom | An anchored `Control` root with a nested anchored `MarginContainer` | Container-rooted screens, no anchors (D35) |

A sixth fault was found while measuring and had not been reported: the board header
was misaligned from its rows by 20px, and by a further 8px whenever a scrollbar
appeared. See D36.

**Build:**
- Shared `Theme` resource; all colours and fonts in one place
- Widgets: stalk board row, holdings row, ranking row
- Gameplay screen: available stalks, your stalks, cash, net worth, year, mood,
  rankings, special-event display
- Buy/sell controls with **visible rejection feedback** — the original's silent
  failure is explicitly fixed here
- Ready-for-new-year flow and year-advance presentation driven by `YearResult`
- Split / bankruptcy / dividend presentation; **BANKRUPT!!!** overlay
- Loan panel: terms, max loan, minimum payment, advisory (never blocking) prompt
- Game-over screen with winner and final rankings
- Main menu with game settings: starting cash, years, loans on/off

**Done when:** a complete 10-year solo game is playable end to end from the main
menu, with no Steam and no network peer, and the numbers on screen match what a
headless simulation with the same seed produces.

✅ **Met.** A test plays a full match through the real controls, then plays the same
seed headlessly and compares every stalk price and the final net worth — the UI
invents nothing. Another starts from the menu, plays to the end, and checks the result
screen takes over.

**Known rough edges, deliberately left:** no sound, no pause or settings menu during
play, and no animation on a year advance — prices simply change. Sound and polish are
Phase 7.

### Done in Phase 5: confirm ending a turn with a loan payment due

Requested after play-testing in Phase 4, built during Phase 5 when it came up
again. Readying up with an unpaid loan now asks before it goes through, naming
the penalty it will cost.

This was **not** a change to the advisory rule in game-rules.md §9.5 — it is how
that rule should have been implemented. The rule is that the game must never
penalise a player for something it hid from them, while never taking the choice
away. A confirmation does both: it guarantees the player saw the consequence, and
they can still decline and take the penalty. The bottom-bar nag alone was easy to
miss, which is exactly the failure the rule exists to prevent. See D53.


🖱️ Heaviest editor phase. I'll write the scenes as text where the node tree is
regular, and give numbered click-by-click steps for theme authoring and any fiddly
container layout.

---

## Phase 5 — Multiplayer over ENet

**Status: both increments built, not yet played by two people.** The networked
layer and the screens to reach it are done and tested. What has not happened is a
human running two copies of the game and playing a match, which is the one
condition below that automated tests cannot stand in for.

### Increment 1 — delivered

- `MatchAuthority` extracted from `LocalSession`, so one implementation of
  validate-and-apply serves offline and hosted play alike (D43). The existing
  `LocalSession` tests passing unchanged is what verified the move.
- `NetworkedSession`, declaring every `@rpc` once for both sides (D44).
- `HostSession`: peer-to-slot mapping, every request re-validated through the
  authority, redacted per-player snapshots pushed out, year results broadcast.
- `ClientSession`: a replica that asks and computes nothing.
- `StateSync`: hand-written encoding of built-in types only (D41), whole snapshots
  rather than deltas (D42), per-recipient redaction (architecture §5.3).
- `YeehawRules` plus the full request/notify/give/broadcast path — the first
  networked feature, working end to end in both directions.
- A one-process test harness (`tests/fixtures/net_harness.gd`) and 48 new tests —
  20 pure encoding tests and 28 with a real host and client over real ENet. With
  increment 2's screen tests the suite stands at **337 tests / 14,003 asserts in
  about 19 seconds**; the networked tests account for most of that time, since
  each opens a socket.

Two de-risking spikes ran before any of it was written, because the testing
approach depended on the answer: two ENet peers *can* coexist in one process, and
RPCs route both ways. The three non-obvious requirements that makes are recorded in
[architecture.md §5.2](architecture.md) and in the harness itself.

**Disconnect handling, corrected in place.** The first attempt kept a dropped
player in the match, which deadlocked the year: the all-ready gate counts every
player, so the remaining players could ready up forever. A dropped player now
leaves the active roster while their portfolio is retained for a later rejoin or
bot takeover. See D46 (superseded) and D47, and the owner-requested direction under
Phase 8 below.

### Increment 2 — delivered

- Menu with three paths: Solo, Host and Join. A joiner is not offered the match
  settings, because the host owns them.
- Lobby screen serving both sides: the player list with who you are and who is
  hosting, ready-up, and a Start button only the host sees. Start waits for
  everybody to be ready, and the host can remove a player who is holding the
  lobby up (D49).
- `Main` wiring — `host_match`, `join_match`, the lobby, and the swap into the
  playing screen when the match begins. A busy port or an unreachable host is
  shown on the menu rather than only logged.
- Roster built from arrivals rather than declared up front (D48), which removed
  the unclaimed-slot deadlock before it could be hit.
- Latecomers and a full match are refused *with a reason*, sent before the
  disconnect.
- 44 tests in `test_lobby_screen.gd`, driving the real controls.

**Found by actually playing two windows**, after the suite was green. Each one
was invisible to the tests for the same underlying reason — solo play hides
anything that depends on a second player:

- The client died on Start: a swapped-out lobby still reacting to the state
  broadcast that follows (D50).
- A kicked player stayed sitting in the lobby, with only a status line to say
  otherwise (D50).
- The board never acknowledged a Ready press, so a client could reach the match
  and find nothing responded at all (D51).

The lesson is recorded in D51: any control whose effect depends on another
player needs a test with a real second peer, because solo play will never show
the fault.

Yeehaw is now complete bar the sound (Phase 7, with the rest of the audio): one
button asks or gives, a pending request is synced match state, and the asker
cannot answer themselves. The confirmation before ending a year with a loan
payment due — outstanding since Phase 4 — is also in (D53).

**Still open in Phase 5:** nothing. The yeehaw *sound* was the last item and
arrived with the rest of the audio on 2026-11-15 (D72).

**Worth knowing: only one `Main` can hold a peer per process.** `Main` uses the
tree's default `MultiplayerAPI`, as a shipped game should, and a tree has exactly
one of those — so two `Main` instances in one process overwrite each other's
peer and both break. Two *sessions* in one process is what `NetHarness` does, and
it works only because each side gets its own subtree and its own API. That is why
the host-and-client handshake is tested at the session level while `Main` is
tested one session at a time.


**Build:**
- `HostSession` / `ClientSession` behind the existing `GameSession` interface
- `ENetMultiplayerPeer` transport; direct IP/port connection
- Server-side re-validation at every `any_peer` RPC entry point, including that the
  caller owns the player they act as
- All-players-ready gate for year advance
- Per-player private view: you see your own cash, holdings and loan, not others'
- **Yeehaw** — request, notify, give, broadcast sound
- Lobby screen: player list, ready-up, host starts

**Why Yeehaw first:** it is trivial logic that still needs a request, an authority
check ("not yourself"), and a broadcast to every peer. It exercises the whole RPC
path end to end while being impossible to get subtly wrong in a way that corrupts
the economy. It is also, per the owner, a critical feature.

**Done when:** two instances on one machine can play a full game together over ENet,
the host rejects a malformed or unaffordable client request, and both clients show
identical market state after every year.

Of those three: the rejection and the identical-market conditions are met and
tested (`test_networked_session.gd`). Two instances playing together is now
*possible* — menu, lobby and transport are all in place — but has not been
done by a person, and the suite cannot prove it (see the note on one `Main` per
process below). **That is the remaining gate on calling Phase 5 complete.**

---

## Phase 6 — Steam

**Status: built on one machine. Two Steam accounts have never met.**

Full detail, including the setup steps, is in
[steam-integration.md](steam-integration.md). In short:

- **Done:** the transport seam (D56). `HostSession` and `ClientSession` are
  handed a `Transport` and never build one, so Steam is now a swap as a property
  of the code rather than a claim. Proven by `test_transport.gd`, which stands
  both sides up on a transport that is not ENet.
- **Done:** researched which GodotSteam build to use. **GDExtension v4.24-gde**
  (Steamworks 1.65), from **Codeberg** — the GitHub repo is archived.
- **Done:** App ID decided (1821800, D57), the GDExtension installed and
  committed (D58), and the achievement catalogue pinned against the backend.
- **Done:** `SteamService`, `SteamTransport` and the lobby browser. Verified
  live on one machine — Steam starts, a real lobby is created, and the
  transport turns it into a working `SteamMultiplayerPeer`. Nothing in the
  economy, the RPCs or the lobby flow changed to accommodate it, which is what
  the transport seam was for.
- **Done:** two Steam accounts in one lobby, playing. Confirmed by the owner
  on 2026-11-15: lobbies are findable and joinable, Steam persona names load,
  the host can kick, and the whole game plays through. A kick takes a few
  seconds longer to land than over a direct connection, which is Steam's lobby
  callback latency and was left alone.
- **Fixed after that session:** the title screen's settings never reached a
  Steam match, so every Steam game was played with loans off whatever the
  player had chosen (D62). The browser now states what HOST would start.
- **Done:** Steam invites, both directions. The lobby's INVITE button opens
  Steam's own friend picker, an invite accepted while the game is running
  joins that lobby, and one accepted while the game is **closed** launches it
  with `+connect_lobby` and joins from there. Invite-only lobbies too, which
  was the last setting in game-rules.md §2 without an implementation. See
  decisions.md D69.

  **Half-tested, and the other half cannot be tested here.** Confirmed on
  2026-11-15: the INVITE button appears only for an online game, Steam's
  friend picker opens, an invitation is sent and arrives, and an invite-only
  lobby is absent from the browser. *Accepting* an invite could not be tried
  — Steam launches whatever is installed for App ID 1821800, which is the
  published Unity original (D57). That needs a Steam branch upload, not a code
  change.
- **Done:** achievements. `AchievementRules` decides what a match earned and
  `AchievementReporter` tells Steam, including the four lifetime counters.
  28 tests cover the thresholds. **Deliberately untested against Steam**: the
  App ID is the published game's, so trying one would unlock it for real on
  the tester's account. See decisions.md D70.
- **Still open:** the four Steam *stat* names (`sss_wins`, `sss_loses`,
  `lifetime_networth`, `sss_yeehaws`) have never been checked against the
  partner backend. They are unambiguous in the original's source, but a wrong
  stat name fails the same silent way a wrong achievement name does.

### Found by playing, fixed on 2026-11-15

A two-machine direct-connection game (Test A in
[manual-testing.md](manual-testing.md)) and a two-account Steam game between
them turned up five things. All are fixed and covered by tests:

| What was wrong | Fix |
|---|---|
| Losing the host mid-match left the client on a board that answered every click with "Not connected" | The playing screen now reports a lost connection and `Main` returns to the title screen with the reason (D61) |
| A player leaving mid-match simply vanished from the host's standings | The host is told who left (D61) |
| A Steam match always had loans off | The title screen was rebuilt: one Create Game panel, with single player, host online and host locally as choices on it (D65, replacing the same-day D62) |
| The bottom bar was taller at year 0 than afterwards | It reserves its tallest shape permanently (D63) |
| No way out of a match but closing the window | Escape backs out, asking first when a match is running (D64) |

Two smaller things came out of the same session: the minimum loan payment is
now shown under the **LOAN** button, and that button reads **PAY LOAN** for as
long as anything is owed — both of which were the Phase 7 items recorded on
2026-11-14, brought forward because they were asked for again.

One documentation fault was found too: the A5 step in
[manual-testing.md](manual-testing.md) said a player's net worth changes when
they buy. It does not — buying converts cash into shares at that moment's
price — and the table has been corrected.

⚠️ **A correction to the note below.** The `callable_method_pointer.h` —
`callable_mp.h` rename in Godot 4.7 breaks the **module** build, which compiles
against engine headers. The GDExtension binds through the stable GDExtension ABI
and its releases say "4.4 and up" with no 4.7 caveat. Unconfirmed by running it;
see steam-integration.md 2.

**Build:**
- GodotSteam **GDExtension** v4.24-gde or newer, from Codeberg
- Steamworks SDK placed locally, gitignored
- `SteamMultiplayerPeer` swapped in for ENet — no game-logic changes
- Lobby create / browse / search / join, invite-only lobbies, Steam invites
- Steam profile names in the lobby
- Achievements (25 IDs, one canonical casing each, verified against the partner
  backend)

**Done when:** two Steam accounts can find each other through the in-game browser
and through a Steam invite, play a full game, and unlock at least one achievement —
while single-player still runs with Steam closed.

⚠️ **Two of those cannot be met on a development machine**, both because of
D57. *Accepting* an invite needs the port to be what App ID 1821800 installs,
which means a Steam branch upload. *Unlocking an achievement* can be done here
but would award it for real on the tester's account, so it is being left
alone. Everything else in this phase is built and tested. Read Phase 6 as
complete **pending an upload**, with those two as what the upload is for.

The upload itself is now prepared rather than described: a `Windows Release`
export preset, `tools/steam_upload.ps1`, and [publishing.md](publishing.md)
with the partner-site steps. What remains is the owner's — a depot id, an SDK
download, and a Steam login.

🖱️ Owner needed for: Steamworks SDK download from the partner site, app ID decision,
and testing with a second Steam account.

✅ Decided: **reuse App ID 1821800** (D57), which means all 25 achievements
carry over and the partner backend owns their exact names. **GodotSteam
GDExtension**, not the module build and not Foundation for Steamworks — see
[steam-integration.md](steam-integration.md) 2.

✅ Also settled: both singular "one game" achievements are `Title_Case`
(`SSS_Win_One_Game`, `SSS_Lose_One_Game`), read off the backend. The four Steam
*stat* names are still unverified, though unambiguous in the source.

---

## Phase 7 — Polish ✅ Complete

- ~~Sound: bull, bear, bankruptcy, yeehaw~~ — **done 2026-11-15** (D72).
  The original's seven effects are in `assets/audio/`, copied on the owner's
  instruction after the licensing question was put to them. A mood plays two
  clips layered and a bankruptcy plays glass and a scream once per year, both
  as the original did. A volume control followed the same day (D74): a
  **SETTINGS** tab beside Create Game and Join Game, with a slider that
  previews what it is doing, as the original's did.
- ~~Loan button: minimum payment underneath, "PAY LOAN" whenever a loan is
  outstanding~~ — **done 2026-11-15**, brought forward after a second request
- ~~Esc as a way out of a match~~ — **done 2026-11-15** (D64)
- ~~Settings persistence and tidy quit handling~~ — **done 2026-11-15** (D71).
  `user://settings.cfg` holds the effect volume, and closing the window now
  shuts the Steam lobby and the peer instead of vanishing. Match settings are
  deliberately **not** remembered — the first version did and it was removed
  the same day; D71 says why. There is no pause menu and no settings screen
- ~~Error and edge-case presentation~~ — **done 2026-11-15** (D74).
  Network failures say what went wrong instead of carrying a bare code, and a
  damaged install names what a player can do about it instead of pointing at
  a log they cannot open
- ~~Export presets and a Windows build, excluding `steam_appid.txt`~~ —
  **done**. `export_presets.cfg` has excluded it since the preset was written
  (Valve's guidance is that it is a development-only file) and builds have
  been produced from it all through Phases 6 and 7. A second preset,
  **Windows Release**, was added on 2026-11-16 (D75): no debug symbols, no
  test suite, its own output folder. See exporting.md and publishing.md
- ~~Year history retained and inspectable~~ — **done 2026-11-15** (D73).
  The result screen has a **YEAR BY YEAR** tab beside the final standings: one
  row per year with its mood, what you were worth at the end of it, and what
  the market did. Nothing new crosses the wire — every machine already kept
  the history. Not available *during* a match; that is a layout question and
  the board is full

---

## Parity gaps — unscheduled

Phases 0–7 delivered the whole economy and a playable game over Steam, but an audit
of the original on 2026-11-16 found functionality the port does not have. These are
**port work, not new features**: the original did each of them.

Full detail, with suggested scope for each, is in
[original-game-audit.md §17](original-game-audit.md). Not repeated here, so there is
one list rather than two that can disagree. In rough order of how much a player would
miss it:

| # | Gap | Decision |
|---|---|---|
| 1 | No in-game pause menu — the original's Escape menu held Resume, Settings, Quit Game and Exit to Desktop. `ui-reference.md` listed this as Phase 7 work and Phase 7 closed without it | Port it — no choice to make |
| 2 | No quit button anywhere; closing the window is the only way out | Port it — no choice to make |
| 3 | No fullscreen toggle, and no resolution dropdown | Decided 2026-11-16: build the dropdown, populated from the system. Revises D40; see audit §17.3 |
| 4 | The host cannot choose a player limit; every lobby is created with ten slots | Decided 2026-11-16: restore the 1–10 field |
| 5 | The lobby browser omits the year limit and whether loans are on, both of which the original published for exactly that purpose | Decided 2026-11-16: publish years, loans **and** starting cash |
| 6 | No search box in the lobby browser | Port it — no choice to make |
| 7 | No Steam avatars on lobby rows | Port it — no choice to make |
| 8 | No supporter DLC thank-you message (*"Thanks for Supporting the Devs!"*) | Decided 2026-11-16: check Steam DLC ownership, show the message |
| 9 | The final board cannot be inspected after the result screen appears | Decided 2026-11-16: add a view-board button |
| 10 | **The window is resizable and nobody chose that.** The original explicitly disabled resizing; `window/size/resizable` is unset, so Godot's default applies | Decided 2026-11-16: fix the window. Driven by a reported bug — see audit §17.10 |

**Every gap on this list is to be ported.** "Port it — no choice to make" means the
original had the thing, the port does not, and restoring it needs no decision from
anybody: build it as the original had it. It does **not** mean the item was dropped.
The rest were decided on 2026-11-16; those decisions are in
[original-game-audit.md §20](original-game-audit.md) and in each gap's own entry under
§17. Gaps 3 and 10 together revise **D40**, which chose integer scaling without
settling either the resolution list or the window policy.

Every decision recorded in the audit still needs a `decisions.md` entry when its work
is scheduled. The audit is where the answer was captured, not where it belongs
permanently.

---

## Phase 8 — Requested follow-ups, after the port ships

Three things the owner has asked for that are **not** port work: the original did
none of them. Recorded here with enough reasoning to act on, and deliberately not
started, so the port ships first.

### Public holdings — seeing who owns what

Players should be able to see which stalks other players hold, and how much. The
owner's suggested shapes, any of which would do:

- a separate panel or menu listing holdings per player
- hovering a player in the rankings
- an eye symbol on a stalk row whose tooltip lists every holder and their amount

**What it changes.** This reverses part of the privacy model in
[architecture.md §5.3](architecture.md): holdings are currently redacted per
recipient and never put on the wire. Making them public is a change to
`StateSync.encode_player` — delete the redaction for `holdings` — plus the UI to
show them. Cash and the loan schedule are a separate question and should stay
private unless asked for.

**Do it as a `GameSettings` toggle, not a code change.** "Open book" versus
"hidden holdings" are genuinely different games, and the toggle costs almost
nothing while the alternative is choosing for everybody. Note the redaction tests
in `test_state_sync.gd` encode the current rule and will need to express both.

### A bot takes over a vacant slot

When a player drops, a bot plays their position rather than the slot sitting empty.

Needs AI logic that does not exist yet — at minimum: decide whether to buy or sell,
pick a stalk and an amount, and ready up. Note that a bot must go through
`MatchAuthority` exactly as a human does, not mutate state directly, or it becomes
a second source of truth. The groundwork is already in place: D47 keeps a dropped
player's portfolio alive, so a bot has a position to take over rather than needing
one invented.

### A disconnected player rejoins and resumes

A player who drops can reconnect and pick their own position back up — including
taking over from a bot, if one was playing it.

**Deferred until after Steam, by the owner's call on 2026-11-14.** None of it is
implemented, and an earlier version of this plan wrongly said part of it worked:
a latecomer is turned away once a match starts, so a vacated slot cannot be
claimed at all.

What is missing is **identity**. The host cannot tell a reconnecting player from a
stranger, and handing a vacated slot to whoever turns up next would let any
arrival claim a dropped player's portfolio. Phase 6 brings Steam IDs, which is
what makes the claim checkable — match the reconnecting ID against the one that
vacated, and refuse otherwise. That is the reason to wait for Steam rather than
bolt something on now.

The groundwork that does exist: a dropped player's `PlayerState` is retained in
the host's roster with its cash and holdings (D47), so there is a position to
resume. Nothing reads it yet.

---

## Phase ordering rationale

| Choice | Why |
|---|---|
| Economy before UI | The game *is* its numbers. Headless tests catch rule bugs that clicking never would — and the original shipped with several. |
| Loans separate from Phase 1 | Self-contained, mathematically fiddly, and optional in-game. Worth its own tested slice. |
| Content after logic | Authoring 90 events is only safe once a validator exists to catch typos in 90 stalk references. |
| Single-player before multiplayer | Removes network variables while the UI is being shaped. Also a genuinely new feature — the original had no offline mode. |
| ENet before Steam | Proves the authority model with zero external dependencies, two windows, and no accounts. |
| Steam last | Most environment-dependent, least automatable, and a transport swap by design. |

---

## Future direction — not in this plan

"StalkleHeads" mode (earnings reports, industries, momentum, indices, charts, news
hinting at events) and JSON-authored custom stalks are **out of scope** for the port.

They are not, however, ignored: `architecture.md` §7 records the four decisions taken
now specifically so those features are additive later rather than a rewrite — the
`PriceModel` interface, market-wide read access in the price model, year history from
Year 0, and `id`-based content identity.

### Questions deliberately deferred to that mode's design

Not open questions for the port — settled for now, with the review scheduled:

- **Should a player be able to take more than one loan per game?** The port
  faithfully reproduces the original's one-loan-ever behaviour, which appears to be
  an oversight on its part. Repeat borrowing would let a player compound leverage
  across a long match, which suits a deeper financial model better than it suits the
  faithful port. If both are wanted it should become a `GameSettings` toggle rather
  than a code change. See decisions.md D27.
- **Should an event still fire when its target stalk is already bankrupt?** Currently
  skipped, because an event affects exactly one stalk and a dead target makes it a
  no-op. Once events also move an industry or the wider market, firing it for the
  sector effect may be right. The decision lives inside `EventPool` precisely so this
  can change without touching the year pipeline. See decisions.md D24.

The port ships the original game, faithfully and correctly, on a structure that can
grow into the bigger one.
