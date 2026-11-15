# Porting Plan

Phased schedule for the port. Rules are in `game-rules.md`; structure is in
`architecture.md`.

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

### Outstanding: confirm ending a turn with a loan payment due

Requested after play-testing, not yet built. Readying up with an unpaid loan should
ask *"Are you sure you want to end your turn without paying your loan?"* before it
goes through.

This is **not** a change to the advisory rule in game-rules.md §9.5 — it is how that
rule should have been implemented. The rule is that the game must never penalise a
player for something it hid from them, while never taking the choice away. A
confirmation does both: it guarantees the player saw the consequence, and they can
still decline and take the penalty. The current bottom-bar nag is easy to miss, which
is exactly the failure the rule exists to prevent.

Belongs with the Phase 7 polish pass unless it comes up sooner.

🖱️ Heaviest editor phase. I'll write the scenes as text where the node tree is
regular, and give numbered click-by-click steps for theme authoring and any fiddly
container layout.

---

## Phase 5 — Multiplayer over ENet

**Status: increment 1 of 2 complete.** The whole networked layer is built and
tested; what is missing is the UI to reach it — a host/join screen and a lobby.
Until that lands, a networked match can be stood up from code and from the test
suite, but not from the running game.

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
- A one-process test harness (`tests/fixtures/net_harness.gd`) and 42 new tests —
  20 pure encoding tests and 22 with a real host and client over real ENet — taking
  the suite to **275 tests / 13,849 asserts in about 13 seconds**. The networked
  tests account for most of that time, since each opens a socket.

Two de-risking spikes ran before any of it was written, because the testing
approach depended on the answer: two ENet peers *can* coexist in one process, and
RPCs route both ways. The three non-obvious requirements that makes are recorded in
[architecture.md §5.2](architecture.md) and in the harness itself.

**Known limitation.** A disconnected player keeps their slot (D46), and the
all-players-ready gate counts every player — so a match cannot advance a year while
a slot sits empty. Filling or closing a slot is a decision for the host to make in
the lobby, which is increment 2.

### Increment 2 — remaining

- Host/join screen: port, address, player name
- Lobby screen: player list, ready-up, host starts the match
- `Main` wiring so the menu can reach hosting and joining
- Host handling of a full match (currently the peer is simply disconnected) and of
  an empty slot blocking the year
- The yeehaw *sound* is Phase 7 work, with the rest of the audio

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
tested (`test_networked_session.gd`). Two *instances* playing together needs
increment 2 — the layer underneath it is done and proven in one process.

---

## Phase 6 — Steam

**Build:**
- GodotSteam GDExtension (a build targeting Godot **4.7** specifically — the 4.7
  header rename broke older builds)
- Steamworks SDK placed locally, gitignored
- `SteamMultiplayerPeer` swapped in for ENet — no game-logic changes
- Lobby create / browse / search / join, invite-only lobbies, Steam invites
- Steam profile names in the lobby
- Achievements (25 IDs, one canonical casing each, verified against the partner
  backend)

**Done when:** two Steam accounts can find each other through the in-game browser
and through a Steam invite, play a full game, and unlock at least one achievement —
while single-player still runs with Steam closed.

🖱️ Owner needed for: Steamworks SDK download from the partner site, app ID decision,
and testing with a second Steam account.

❓ Decisions: reuse the existing Steam App ID or register a new one; which
achievements carry over; GodotSteam vs Foundation for Steamworks.

---

## Phase 7 — Polish

- Sound: bull, bear, bankruptcy, split, yeehaw, UI feedback; mixer and volume
  settings
- Esc / pause menu, settings persistence, quit handling
- Error and edge-case presentation
- Export presets and a Windows build
- Year history retained and inspectable (groundwork already laid for charts)

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
