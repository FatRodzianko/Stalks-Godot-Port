# Glossary

Terms used across the code and documentation. Game terms first, then StalkleHeads terms, then code terms.

---

## Game terms

**Stalk** — a fictional company share, the game's pun on "stock". Players buy and
sell these. There are ten, listed with their statistics in
[game-rules.md §3](game-rules.md).

**Mood** — whether a given year is **bull** or **bear**. Decided once per year and
applied to the whole market. Bull years generally push prices up, bear years down.
Weighted 7 to 5 in favour of bull. See [game-rules.md §4.2](game-rules.md).

**Bull year** — a good year. Prices generally rise and bull dividends are paid.

**Bear year** — a bad year. Prices generally fall and bear dividends are paid, which
for several stalks is nothing at all.

**Contrarian move** — the 10% chance that an individual stalk moves *against* the
year's mood: a small gain in a bear year, a small loss in a bull year. Rolled per
stalk, independently. See [game-rules.md §4.3](game-rules.md).

**Yearly change** — the price movement displayed to players on the stalk board.
Important subtlety: this is the **normal move only** and deliberately **excludes** any
special-event movement, matching the original game.

**Special event** — one flavoured price shock per year, aimed at a single named
stalk, drawn from a mood-specific pool. Carries comedic flavour text and a price
delta. 45 bull and 45 bear events exist. See [game-rules.md §5](game-rules.md).

**Split** — when a stalk's price rises above 150, the price halves (**rounding up** on
an odd price) and every holder's share count doubles. See
[game-rules.md §6](game-rules.md).

**Bankrupt (a stalk)** — when a stalk's price falls to 0 or below, it fails. All
holders lose every share in it, with no compensation. The board entry stays visible,
overlaid with "BANKRUPT!!!".

**Bankrupt (a player)** — a player who misses a third loan payment. Their cash, net
worth and holdings are all set to zero.

**Dividend** — a fixed payment per share held, paid once a year, with a different rate
for bull and bear years. Paid *after* splits, so a stalk that just split pays out on
the doubled share count.

**Static stalk** — a stalk whose price never moves. There is exactly one: *BERRY
BONDS FROM DIE HARD*, the game's risk-free bond. It cannot move, split, or go
bankrupt, and carries no special events. In code this is the `is_price_static` flag,
not a check on its name.

**Net worth** — cash on hand, plus the market value of holdings, minus any
outstanding loan. The score the game is won on.

**Long-game softening** — price swings are scaled down in longer matches so prices do
not run away: above 19 years and again above 49 years. Undocumented in the original's
public write-up but present in its code. See [game-rules.md §4.4](game-rules.md).

**Loan** — optional borrowing, available from Year 2 when enabled. Up to 25% of net
worth, minimum 100, 10 years at 6% compound, paid out as cash immediately. **One per
player for the entire game**, even after repayment. See
[game-rules.md §9](game-rules.md).

**Minimum payment** — the yearly amount due on a loan, calculated as
`principal / a(n, 6%)` and truncated to an integer. It is recalculated every year and
after every payment, which makes it drift by about ±1 — expected behaviour, not a
bug.

**Annuity factor** — written `a(n, i)`, the standard present-value figure that turns a
principal into a level yearly payment. For the 10-year term at 6% it is about
7.360087. Dividing a balance by it gives the payment that clears the balance over n
years.

**Re-amortisation** — recalculating the minimum payment from the current balance over
the years remaining. Happens after every payment and after every penalty. It is what
makes overpaying visibly reduce next year's minimum.

**Interest-only first year** — the year a loan is taken charges interest but counts no
missed payment, because the loan is created already flagged as paid. This implements
"your first payment is next year", and it is why a ten-year term runs to eleven
year-ends.

**Missed payment** — failing to pay the minimum during a year. First miss adds 10% to
the balance, second adds 15%, third is a **default**.

**Default** — a third missed payment. The player's cash, net worth and all holdings
are seized and they are bankrupt. Lands on the fourth year-end after borrowing, since
the first year is free.

**Yeehaw** — a purely social gesture. A player asks for one; any *other* player may
give it; all players then hear a "YeeHaw!" sound effect. No mechanical effect
whatsoever. Impossible in a one-player game, since you cannot give yourself one.

**Game settings** — the options chosen before a match: starting cash, number of
years, number of players, whether loans are enabled. The original called these "lobby
settings" because every match ran through a Steam lobby; renamed here because the
port must support true offline single-player.

---

## StalkleHeads terms

StalkleHeads is a second game mode, being built in phases, in which prices come from
simulated company earnings rather than random rolls. Its design is
[stalkleheads-design.md](stalkleheads-design.md). None of these terms means anything
in the base game.

**Company** — in StalkleHeads, a stalk with accounts: revenue, a profit margin,
profit, shares outstanding and earnings per share. Authored as a `CompanyProfile`;
live as a `CompanyState`. Eighteen of them, three to an industry.

**Earnings per share (EPS)** — profit divided by shares outstanding. What a company
earns for each share of it. The model moves earnings; the price follows.

**Regime** — which of five states a company's earnings are in this year: GROWTH,
STEADY, SLOWING, DECLINE or DISTRESS. The regime sets how far revenue moves and which
margin the company drifts toward. It changes once a year by a roll against a
published table of odds, the **transition matrix**. See §3.3.

**Ageing and recovery** — the two ways time in a regime changes the odds of leaving
it. Each year already spent in GROWTH or SLOWING makes a worse regime likelier next
year (a good run cannot last); each year already spent in DISTRESS makes leaving it
likelier (a rock-bottom run also ends).

**Quality** — a company's 0-100 rating that biases its regime roll toward better
regimes. 50 is neutral.

**Industry** — a group of three companies that share a yearly **performance** figure,
which reaches each member's revenue through its **beta** (how exposed it is to its
industry, in percent). Performance is persistent: 40% of last year's carries into
this year's. Authored as an `IndustryDefinition`.

**Standing** — what the market will pay for an industry's earnings this year, in
turns of multiple: its performance times 0.06. A +20% industry adds 1.2 to every
member's multiple.

**Sentiment** — last year's whole-market price move, in percent, clamped to +/-20. It
nudges every multiple this year and leans slightly into every industry's roll. It is
*last* year's on purpose, so nothing this year depends on itself (§3.1).

**Multiple** — how many years of earnings the market pays for a share:
`12.5 + sentiment x 0.02 + standing + regime premium`, clamped to 4-30. The
**regime premium** is a small adjustment per regime, from +1.2 for GROWTH to -1.4 for
DISTRESS. The base of 12.5 comes from BERRY BONDS' 3% yield (§3.4).

**Fair value** — earnings per share times the multiple. What a company's earnings are
worth this year, before events and trading.

**Event carry** — the part of the price still owed to announced special events. This
year's event lands in full; each year after, half of what is left fades away.

**Flow** — the part of the price pushed by what traders, NPC and human alike, bought
and sold last year. It persists (70% carries into the next year) and is clamped to
5% of fair value either way.

**The price identity** — StalkleHeads' whole price model:
`price = int(fair_value + event_carry + flow)`. Nothing is hidden in it, which is what
lets the ledger explain every move.

**The ledger** — the breakdown of a year's price move into its causes (earnings,
sentiment, standing, regime premium, valuation limits, this year's event, last
year's event fading, flow), in whole coins that add up exactly to the move. It is
the mode's signature screen. Code: `PriceLedger`.

**Payout policy** — the share of its earnings a company pays as a dividend in a
normal (STEADY) year, 0-100, authored per company. Its regime scales it (a growing
company holds more back; a distressed one pays nothing), and the result is the
**payout ratio**. Paying more slows the company's positive revenue growth, through
the **retention factor** `1 + (35 - policy) / 100`, so a big payer is a different
stock rather than a better one (§3.10a).

**Balance tool** — `tools/balance_report.gd`, a script that plays hundreds of seeded StalkleHeads matches with scripted player strategies and prints how often each finished first (its **win share**). How the design's balance properties P2-P4 are measured. See [development.md](development.md).

**Stand-in year** — the balance tool's own minimal StalkleHeads year (`tools/balance/stand_in_year.gd`) in phase S2, which called the real simulation pieces in order. **Deleted in S3**, when the tool moved onto the real pipeline (decisions.md D161).

**Derived mood** — in StalkleHeads the year's bull or bear label is not rolled. It is a report of what the index did: BULL when the index rose, BEAR otherwise, set after every price is final. It still chooses which bag next year's event comes from (§3.1, decisions.md D153).

**Index move** — the mean percentage price move, before splits, of the companies alive at the start of the year; a company that went bankrupt that year counts -100. It is what moves My Mutuals and Me Inc., what decides the mood, and, clamped, next year's sentiment.

**The index** — in StalkleHeads, My Mutuals and Me Inc.: a row whose price is the market's, moved each year by the index move from a level kept unrounded. It carries no events of its own, splits above 300 like a company, and pays the average of its constituents' dividends (decisions.md D157).

**Constituent** — a company counted in the index. Every company alive at the start of the year is one; a bankrupt company stops being one the year after it fails.

**Yardstick** — BERRY BONDS' role in StalkleHeads. Its 3% yield is the risk-free rate, and the 12.5x base multiple is an 8% earnings yield, five points over it (decisions.md D156).

**Earnings pipeline** — `EarningsYearResolver`, the StalkleHeads year: industries, earnings, the event, prices, the index, the mood, bankruptcy, splits and dividends, then the shared settlement. The base game's year is `YearResolver`; the two share only `YearSettlement`.

**Settlement** — `YearSettlement`, the back half of a year that both pipelines share: loans, net worth and standings, the game-end check, and closing the year (decisions.md D152).

**Strategy (balance tool)** — a fixed rule a scripted player follows, such as `LOWPE` (hold the three cheapest by P/E) or `TREND` (hold the three whose earnings grew fastest). The list is in [stalkleheads-design.md](stalkleheads-design.md) §2.1.

**The desk (NPC desk)** — the twenty-four simulated traders of a StalkleHeads match. They are not players: not ranked, cannot win, never asked to ready up. They trade once a year after the year settles, and what they bought and sold becomes next year's flow. Code: `NpcDesk` (design §5, decisions.md D162).

**NPC trader** — one member of the desk, authored as an `NpcTraderDefinition` with a name, a strategy, starting cash and conviction. Names and chatter are placeholders until the owner writes them.

**NPC strategy** — the published rule a trader follows: VALUE (lowest P/E), MOMENTUM (rose most last year), CONTRARIAN (fell most), INCOME (highest dividend yield), INDEXER (only My Mutuals and Me Inc.), PANIC (the bond in a bear year, a company in a bull one), GROWTH (earnings grew fastest), SHORT (sells short whichever company has the highest P/E). Three traders follow each. Not the same thing as a balance-tool strategy, though several share a rule.

**Conviction** — the share of its cash, 0-100, a trader commits to a decision. Authored; 45 for every shipped trader.

**Appetite** — a trader's yearly draw, 70-130, that scales its conviction for that year, so three traders with one strategy buy the same company in different amounts. Drawn every year before the trader decides anything (decisions.md D163).

**Selling short / a short** — selling shares you do not own, to buy them back later, which profits when the price falls. Only the desk's SHORT traders can; **players cannot** (design §14 q10).

**Short interest** — the number of shares the desk is short in a company, summed over its traders. A real figure, not a hint, published on the Company tab (S7). Code: `NpcDesk.short_interest`.

**Flagged** — a company whose short interest is at least 10% of its shares outstanding. Only while some company is flagged can a short squeeze happen (decisions.md D165).

**Short squeeze** — in StalkleHeads, a special event aimed at the most shorted flagged company: its price jumps (+25 as shipped), and the short sellers lose. In a year with a company flagged it replaces the year's ordinary event 25% of the time; with none flagged it never happens.

**Chatter** — a one-line remark a trader makes about what it did this year (bought, sold, shorted, covered, held). Shown under its name on the Company tab and on the side panel's DESK page (S8). Written on the trader's own file, or for a whole strategy in a news book; placeholders until the owner writes them.

**FOLLOW** — the balance-tool strategy that copies whichever NPC trader is worth most, holding what it holds. It reads nothing about companies, only the desk.

**Game mode** — which game a match is: the base game (*Stalks Stalks Stalks*) or StalkleHeads. Chosen on the title screen's **Game** row, fixed for the whole match, published to the lobby browser. Code: `GameSettings.mode`, `GameMode`; read only by `MatchSetup` (decisions.md D171). Not the title screen's `MainMenu.Mode`, which is which tab is showing.

**Base game** — the faithful port of the original, as opposed to StalkleHeads. `GameMode.Value.BASE`, and the default everywhere.

**Year pipeline** — the code that advances one year for a game mode: `YearResolver` for the base game, `EarningsYearResolver` for StalkleHeads. Both extend `YearPipeline`, which is what `MatchAuthority` holds.

**Inputs and readouts** — the two kinds of number in a StalkleHeads market (design §9.1). An *input* is drawn or carried and cannot be worked out from anything else: an industry's roll, a company's regime and growth roll, its revenue. A *readout* follows from the inputs: profit, EPS, the multiple, fair value, P/E. Inputs go over the network; a client works the readouts out itself with the same code (`CompanyState.derive_readouts`). Sending a readout would mean a second copy of the rule on the wire (decisions.md D176).

**Replaying a year** — a client's way of getting a StalkleHeads year: it receives the host's draws for that year and runs the second half of the year pipeline on them (`EarningsYearResolver.replay_year`), which gives exactly the host's result. Only the host rolls dice; everyone runs the arithmetic (decisions.md D178).

**Draws (of a year)** — everything random the host decided in a year: the industry rolls, each company's regime and growth roll, the squeeze roll, each NPC trader's appetite. Recorded on the year's result so a client can replay it.

**Content key** — a fingerprint of the companies, industries, traders and events a StalkleHeads match was built from, in order (`EarningsMarket.content_key`). The market travels as numbers in a fixed order, so both ends must hold the same content; a client whose key differs refuses the host's snapshot.

**Packed block** — a list of numbers sent as one typed array (`PackedInt32Array`, `PackedInt64Array`, `PackedFloat64Array`) where each number's position says what it is, instead of a dictionary per company with named keys. An eighth of the size (decisions.md D178).

**Event bags (as match state)** — what is left of each mood's shuffled bag of events this cycle. In StalkleHeads they are kept on the market (`EarningsMarket.event_bags`) and sent to clients, so a host that takes a match over deals from the same bags (decisions.md D177). In the base game they are not, and are reshuffled when the host changes.

**Sentiment used** — the market sentiment a year's prices were valued on (`EarningsMarket.sentiment_used`). By the time a snapshot is sent, `sentiment` has already moved on to next year's, so this is kept to let a client rebuild the valuation.

**Placeholder company** — a company the owner has not written yet, named by industry
and letter (*Transportation Company A*) with an obviously temporary ticker (`TRNA`).


**Ticker** — a company's short code, four or five capitals (`PLLW`, `STRYK`), shown beside its name on the StalkleHeads board (column SYM). Authored on the stalk definition (`StalkDefinition.ticker`); the base game has them too but never shows them.

**The tabs** — in a StalkleHeads match the three boards of the playing screen are replaced by four tabs: **EXCHANGE** (the board), **MARKET** (the whole market), **INDUSTRIES** and **COMPANY** (one company in depth). Code: `MarketTabs` (decisions.md D180).

**Industry group** — on the EXCHANGE board, an industry's header line (its year and average P/E) with its companies beneath. Click the header to collapse or expand it. The bond and the index sit in a group of their own, INDEX & BOND.

**HELD** — the EXCHANGE board's column for how many shares of that row you own. StalkleHeads only; the base board keeps its separate "Your Stalks" list (design §14 q1).

**Side panel (HOLDINGS / RANKINGS / DESK)** — the StalkleHeads panel to the right of the tabs. HOLDINGS lists cash, net worth and every company you hold by ticker, each with a box and SELL (the base game's row); RANKINGS the players; DESK the desk's strategies and short interest. Always open on EXCHANGE, beside the board; opened by its buttons elsewhere, over the tab in a bright frame. Code: `SidePanel` (decisions.md D183, D184).

**Company list (COMPANIES)** — the Company tab's list of every company, opened over the tab by its COMPANIES button; click one to show it. Its NPC column counts the desk's traders holding or short that company. Click a heading to sort by it. A `*` before a name means you own shares in it. Code: `CompanyPicker` (D184, D185, D191).

**Trade box** — a quantity box with **BUY** and **SELL**, on every company shown on its own in StalkleHeads. SELL is greyed when you hold none. Code: `TradeBox`, checked through `TradeContext` (D183, D184).

**YoY (year on year)** — a change measured against the same figure a year earlier, as a percentage of the earlier one. The Company tab's ledger shows the price's.

**Why the price moved** — the Company tab's ledger widget: last year's price, this year's, and every point between them attributed to earnings, multiple, industry, this event, last event faded and flow. Its total is the board's CHG. Code: `LedgerWidget`.

**The year in review** — the extra block at the top of the news panel in a StalkleHeads match: the market's move and mood, each industry's year, and the year's outliers (biggest earnings surprise, biggest disappointment, dividend cut, what the desk piled into). Code: `YearDigest`, `YearDigestPanel` (design §6.3).

**Breadth** — how many companies rose this year, out of those still trading ("11/17"). On the Market tab.

**Earnings yield** — earnings per share divided by price, as a percentage: the inverse of P/E. The Company tab puts it beside the bond's risk-free rate, the yardstick (§3.8).

**Market share (within an industry)** — a company's revenue as a share of its industry's revenue. On the Industries tab, with its change on last year.

**Text chart** — a bar chart drawn in characters, using the font's eighth-block characters so a bar can end an eighth of a cell up. Every chart in StalkleHeads is one (decisions.md D181). Code: `TextChart`.

**Candlestick (candle)** — a chart mark for one period: a bar from the price the period opened at to the price it closed at, green if it closed higher, red if lower. Real candles also have thin "wicks" to the period's high and low; StalkleHeads' have none, because a company has one price a year (decisions.md D188).

**Split-adjusted** — a per-share figure from before a split, restated as if the split had already happened, so a chart does not show a split as a crash. Code: `MarketReadouts.per_share_adjusted` (D188).

**Readouts (on screen)** — every number the StalkleHeads tabs show that is worked out rather than stored: P/E, market share, averages, breadth. All come from `MarketReadouts` in `src/sim/`, never from a node (decisions.md D179).

**News (StalkleHeads)** — the lines a StalkleHeads year shows besides its numbers: a market headline, an industry report per industry, earnings commentary per company, each desk trader's chatter, plus the special event; and, heard at each year's end about the next, two whispers. None of them moves a price. Chosen by `NewsSelector` (design §8, decisions.md D199-D206; rules in game-rules.md §5.1).

**News book** — a `.tres` file in `src/data/news/` holding news lines of any kind (`NewsBook`). The game loads every one in the folder.

**Market headline** — one line about the whole market, chosen by the year's mood and how far the index moved. On the Market tab, above the event.

**Industry report** — one line about an industry's year, chosen by how far it moved. On the Industries tab under the selected industry.

**Earnings commentary** — one line about a company's earnings, chosen by its regime and its surprise band. On the Company tab under NEWS.

**Whisper** — a rumor about a company or an industry, heard at the end of a year (from year 1; none in year 0) and about **the next year**: whether it will do much worse, worse, as expected, better or much better than everyone expects. Two a round, on the Market tab with their sources, and on the Company tab of a company they name or its industry. A whisper can be wrong, and how often depends on its **source** (decisions.md D205).

**Source (of a whisper)** — who a whisper came from, which says how far to trust it: Rock Solid, Credible, Hit-or-miss, Questionable or Gossip. Rock Solid is right 85% of the time and never far out; Gossip is right 20% of the time. The table is in game-rules.md §5.1; the code is `WhisperRules`.

**Whisper history** — every round of whispers so far, opened with VIEW HISTORY on the Market tab, each with what really came of it once its year has been played (decisions.md D206).

**Kept draws** — next year's industry swings and every living company's regime and growth roll, drawn a year early and kept on the market (`KeptDraws`, `EarningsMarket.next_draws`) so a whisper can foretell them. The odds are the same as drawing them in their own year (decisions.md D205).

**Move band** — a move sorted into CRASH, DOWN, FLAT, UP or SURGE, at -15, -3, +3 and +15 percent. Headlines use the index's move, industry reports the industry's.

**Surprise band** — how a company's revenue growth compared with what its regime leads one to expect: MUCH WORSE, WORSE, AS EXPECTED, BETTER or MUCH BETTER, 3 and 8 points either side (decisions.md D202). Also what a whisper foretells (D205).

**Token** — a word in braces in a news line, filled in when the line is shown: `{company}`, `{industry}`, `{trader}`.

**Placeholder line** — a news line nobody has written yet: the category in capitals, a colon, and the conditions it was chosen for (`INDUSTRY REPORT: energy, down`), so it says on screen which line is missing (design §8.3).

---

## Code terms

**The simulation** / **the sim** — everything in `src/sim/`. The game's rules as plain
objects, with no nodes, no scene tree and no networking. The central architectural
rule is that this layer never depends on anything above it.

**Pure logic** — code that computes a result from its inputs without touching the
scene tree, the filesystem, the network, or global random state. All the economy rules
are written this way so they can be tested headlessly.

**The year pipeline** — the ten ordered steps that resolve one game year, implemented
in `YearResolver.advance_year()`. The order matters; see
[architecture.md §3](architecture.md) and [game-rules.md §4.1](game-rules.md).

**Host migration** — carrying a match or lobby on when the host leaves, instead of
sending everybody back to the title screen. Steam hands lobby ownership to another
member by itself, so the game only has to ask Steam who the owner is now and act on
it. See [decisions.md D104](decisions.md).

**Taking over** — what the player Steam promotes does: `HostSession.take_over` wraps
that player's own copy of the match in a `MatchAuthority` and starts hosting it. The
copy is already complete, so nothing is asked of anybody.

**Reclaiming a seat** — a returning player being put back into the slot they were
playing. Note that it is not the position they *left*: the match went on paying and
charging it while they were gone, so what they get back is whatever it has become.
Matched by Steam ID, because a display name is typed in by whoever is connecting.
See [decisions.md D105](decisions.md) and [D110](decisions.md).

**Away** — a player whose connection has gone while the match carries on. They
are **still in the match**: paid their dividends, split and bankrupted with their
stalks, charged their loan, ranked in the standings and able to win. The one
thing being away changes is that the year does not wait for them. See
[decisions.md D110](decisions.md) and [game-rules.md §4.6](game-rules.md).

**Vacated** — what "away" used to be called, when a dropped player was taken out
of `state.players` and so out of the economy as well as out of the ready gate.
The word is gone from the code; it survives here because
[decisions.md D47](decisions.md) is written in it.

**Rejoining** — getting back into a match you dropped out of, from **REJOIN GAME**
on the title screen. The whole mechanism is a Steam lobby id written down when the
match starts (`user://last_match.cfg`): a match in progress is unlisted but still
joinable, so the remembered id is a working door. The button is shown only once
Steam has confirmed the lobby is still a game being played, and the host decides
whether the arrival gets their seat. See [decisions.md D111](decisions.md) and
[D115](decisions.md).

**Rematch** — playing again with the same people, without going back to the title
screen. The host reopens the lobby on a finished match, with the same settings and
a new seed, and whoever wants another game joins it; whoever does not is simply not
in the next match, and nothing waits on them. Not in the original, which ends a
match with `Quit Game` and nothing else. See [decisions.md D124](decisions.md).

**Lobby state** — the `state` key a Steam lobby carries, which is how the game
says what the lobby *is* without anybody joining it. `open` is a lobby waiting to
start and is the only value the browser lists; `playing` is a match under way,
unlisted but still reachable by somebody coming back; `over` is a match that has
finished, which matters because the lobby outlives it — everybody is still in
there reading the result screen. See [decisions.md D106](decisions.md) and
[D115](decisions.md).

**The stream position** — how far a match's random number generator has run, as
distinct from its seed. A match is reproducible from the seed *plus* the number of
draws taken off it, so a new host adopts the position rather than reseeding, or it
would deal the match's own past out a second time.

**Price model** — a swappable strategy for how a price moves. The current one
(`RandomRangePriceModel`) is the faithful port; the interface exists so an
earnings-driven model can replace it later without touching the pipeline.

**Content** — the authored game data: the ten stalks and their ninety events, stored
as `.tres` resource files in `src/data/stalks/`. Distinct from code; a new stalk is
new content, not a new feature.

**Content library** — `ContentLibrary`, the only thing that reads the content
directory. It loads every stalk in a deterministic order, validates the whole set, and
builds a fresh market from it. Always returns a library; callers check `is_valid()`.

**Validator** — the checks `ContentLibrary` runs on load: duplicate ids, missing
fields, inverted ranges, events targeting the wrong stalk, events in the wrong mood
list, events on a static stalk. It exists because a typo in an event's target id would
otherwise produce an event that silently never fires.

**The bag** — how special events are drawn. Each mood has a shuffled bag that is drawn
from without replacement, refilled only once empty, so an event cannot repeat until
every other event in its pool has been seen.

**Year result** — an immutable record of everything one year advance did
(`YearResult`). Used four ways: the UI animates from it, the host broadcasts it,
tests assert on it, and the list of them is the match history.

**Match history** — the list of every `YearResult` so far, recorded from Year 0. Kept
because this information cannot be reconstructed later; it is what future charts and
year-over-year figures will read.

**Determinism** — the property that the same settings, the same seed and the same
player actions always produce an identical match. Enforced by using integers for all
money and taking all randomness from an injected generator. See
[architecture.md §8](architecture.md).

**Injected RNG** — a `RandomNumberGenerator` passed in as an argument rather than
created on the spot or taken from Godot's global functions. Non-negotiable: global
`randi()` would make the game untestable.

**Session** — the abstraction over "who is playing and who is allowed to do what", and
the only thing the UI talks to. `LocalSession` plays offline, `HostSession` is
authoritative over a networked match, and `ClientSession` joins one. A Node, because
the networked ones need to issue RPCs. See [architecture.md §5](architecture.md).

**Authority** — `MatchAuthority`, the single place a match is allowed to change. It
validates an action, applies it, and returns a rejection reason or an empty string.
Pure: no nodes, no signals, no peers. Both `LocalSession` and `HostSession` own one,
which is why offline and hosted play cannot resolve an action differently.

**Replica** — the partial copy of the match a client holds. It is overwritten from
the host's snapshots and never computed locally. "Partial" because this client's own
cash, holdings and loan are real while other players carry only their public figures.

**Snapshot** — one encoded, redacted copy of the match, built per recipient and sent
to one client. What keeps a replica current. See [architecture.md §5.3](architecture.md).

**Redaction** — leaving private figures out of a snapshot as it is encoded. A rival's
cash, holdings and loan schedule are never put on the wire at all, so there is
nothing private in the payload to leak.

**Slot** — a player position in a networked match. Slots are **created as players
arrive**, not declared up front, and the roster is whoever is present when the host
presses Start (decisions.md D48). A peer that drops before Start is forgotten,
because there is nothing to keep; one that drops afterwards stays in the match and
is marked away (D110).

**Roster** — every slot in a match, in the order they were seated. It is
`state.players`, and `HostSession.roster()` is the same list; there were once two
of them, differing only by who had dropped (D110). Its order says nothing about
roles — after a migration the host who left is still first in it, which is why
`hosted_by` exists (D109).

**Lobby** — the waiting room between the menu and the board. Shows who is here and
who is ready; only the host gets a Start button. One screen serves both sides, since
the difference is entirely about what you are allowed to do.

**Pending yeehaw** — the one outstanding request for a yeehaw, held as match
state rather than fired and forgotten. It is what lets a single button read "Can I
Get a Yeehaw?" until somebody asks and "Give Yeehaw" afterwards. Cleared when the
year advances. See decisions.md D52.

**Kick** — the host removing a player from the lobby. Exists because Start waits
for everybody to be ready, so somebody who has wandered off would otherwise hold the
lobby shut; a person can tell the difference between slow and gone, and a rule
cannot. Lobby only. See decisions.md D49.

**Introduction** — the first thing a joining client sends: the name the player typed.
The host creates their slot when this arrives rather than when the socket connects,
so a player never appears under a placeholder name.

**Peer id** — the number Godot assigns each connected machine; the host is always 1.
The host maps peer ids to slots, and derives *who is acting* from the sender's peer
id rather than trusting anything in the packet.

**Pre-check** — a `why_not_*` call on the session that the UI uses to grey out or
red-flag a control *before* anything is sent. It runs the same validation function
the authority runs, so it can never disagree with enforcement. Presentation only: a
client is never a second source of truth.

**Palette** — `src/ui/palette.gd`, the single source of truth for colour. The shared
Theme is generated from it. Also holds the money and signed-change formatters, so
every figure on screen is written the same way.

**Theme type variation** — Godot's mechanism for naming a look (`Heading`, `Numeric`,
`Bull`, `Card`, `PrimaryButton`) that a control opts into. How this project styles
things without per-node colour overrides.

**Widget** — a small reusable UI scene under `src/ui/widgets/`: one board row, one
holdings row, one standings row, the loan panel. A widget displays what it is given
and emits intent outward; it knows nothing about the session or the screen holding it.

**Screen host** — `Main`, the node that holds exactly one screen at a time and moves
between the menu, the playing screen and the result screen. It owns the session, so a
finished match's state outlives the screen that displayed it. Screens emit intent and
know nothing about each other.

**Header mode** — a row widget configured by `configure_as_header()` to be the column
header above its own list. Sharing the scene is what guarantees the header's columns
cannot drift out of alignment with the rows'.

**Year summary** — the one-line digest under the special event reporting dividends,
splits, bankruptcies and loan interest. These all happen in the simulation and were
invisible until Phase 4, which made a doubled share count look like a bug.

**Host-authoritative** — the design where one machine owns the simulation and decides
every number. Clients request actions and receive results; they never compute
economics themselves.

**Yeehaw** — see the game term above. In code it is the first networked feature,
chosen because it needs a request, an authority check and a broadcast while being
incapable of corrupting the economy.

**Steam lobby** — Valve's matchmaking object: a small named room with metadata
and a member list, which other players can find or be invited to. It is not the
game's own lobby screen, though the two appear together: the Steam lobby is how
peers find each other, and the lobby screen is what they see once they have.

**Messages** (the MESSAGES tab) — private, text-only messages between the players
in a match, in StalkleHeads. Not part of the game: the host passes each one to its
one recipient and keeps nothing, and every machine keeps its own conversations in
memory (`MessageBook`). See decisions.md D192.

**Note** (messages) — a message to yourself, opened by clicking your own name on
the MESSAGES tab. Kept on your machine and never sent.

**Unread dot** — the small square on the MESSAGES tab and beside each name in its
player list: grey when nothing is unread, yellow when something is. The same shape
as the ready mark in the rankings (`StatusDot`).

**ALL PLAYERS** (messages) — the room at the top of the MESSAGES tab's list:
every message written in it goes to everybody else in the match. See decisions.md
D195.

**Blocked** (messages) — a player whose messages this machine drops, set with
BLOCK? at the top of their chat. Silent: nobody else, the blocked player included,
is told. Shown greyed in the list with "(blocked)". See decisions.md D196.

**Relay** (messages) — what the host does with a message from one client to
another: works out who sent it from the connection, checks and cleans it, and hands
it to the recipient alone. See architecture.md §5.8.

**Transport** — what physically carries network messages. Godot's
`ENetMultiplayerPeer` first, Steam's relay later. Deliberately separate from the
session layer so Steam is a swap rather than a rewrite.

---

## Godot terms worth knowing

**Node** — the basic building block of a Godot scene. Everything on screen is a node.

**Scene** (`.tscn`) — a saved tree of nodes. Godot scenes are plain text, which is why
they can be hand-written and reviewed in a diff.

**Resource** (`.tres`) — a saved data object. Used here for authored content: stalk
definitions and special events.

**Control node** — Godot's UI node type. This entire game is `Control` nodes; there is
no 2D sprite work and no 3D.

**Autoload** — a singleton registered in `project.godot` and available globally. Used
for services, never for game rules.

**Signal** — Godot's built-in event mechanism. A node emits a signal; listeners decide
what to do. The way this project avoids nodes reaching into each other.

**`@onready`** — an annotation that resolves a node reference once the scene is ready,
rather than repeatedly at runtime.

**GDScript** — Godot's own scripting language, used throughout this project.
Python-like syntax, optional static typing (mandatory here).

**GUT** — Godot Unit Test, the testing framework. Version 9.7.1, matched to Godot
4.7. See [testing.md](testing.md).

**`--headless`** — a command-line flag that runs Godot with no window. How the tests
run, and how a build server would run them.

**Shader** (`.gdshader`) — a small program the graphics card runs once for every
pixel it draws. This project has exactly one, the optional CRT effect.

**`CanvasLayer`** — a node that draws its children on a separate plane, above or
below everything else according to its `layer` number. It is not a `Control`, so no
container lays it out. Used here for the two overlays that must float over whatever
screen is showing: the CRT effect and the development panel.

**`SubViewport`** — a viewport inside the scene tree rather than the window. The
whole game is drawn into one, 640x360, so the finished picture is an ordinary
texture that an effect can read. See decisions.md D96.

**`SubViewportContainer`** — the control that shows a `SubViewport`. It does the
enlarging, and it transforms mouse coordinates into the viewport so nothing in
the game has to.

**Integer scaling** — enlarging the picture by a whole number only. At 2x every
source pixel is a 2x2 square; at 2.5x some would be three screen pixels wide and
some two, which makes a letter's strokes uneven.

**Letterboxing** — the black bars left when the picture cannot fill the window.
Here they appear whenever the window is not a whole multiple of 640x360.

**Marquee** — a label that scrolls its text sideways, by whole characters, when
it is too long for its column. Hover to start it, click to pin it. Stalk names
use it (`MarqueeLabel`).

**Scrolling label** — the same idea down the page instead of across: a block of
wrapped text that creeps a line at a time when there is more of it than the
panel reserves. The three longest special event descriptions use it
(`ScrollingLabel`, decisions.md D100).

## CRT terms

The optional CRT effect (decisions.md D94) borrows the vocabulary of the
cathode-ray tube televisions it imitates. None of these are Godot terms.

**CRT effect** — the whole thing: the tick box in Settings that draws the game as
though it were on an old television. Off unless a player asks for it.

**Scanline** — one horizontal sweep of the electron beam. On a real tube the lines
have gaps between them, which is the faint horizontal banding the effect draws.

**Barrel warp** — the gentle outward bulge of a tube's glass, which makes straight
lines near the edges bow. Here it is a distortion applied to where each pixel is
read from.

**Vignette** — the darkening towards the corners, where the frame shades the glass.

**Colour bleed** — colour running horizontally away from a bright edge, because the
beam cannot change intensity instantly. It trails to the right, the direction the
beam travels.

**Beam glow** — bright areas spreading into their surroundings, because the beam
grows wider as its drive voltage rises. Keyed off a brightness threshold, so dark
areas stay dark.

**Phosphor mask** — the grid of red, green and blue phosphor dots on the glass
itself. **This game does not draw one**; it needs monitor-pixel density and the game
renders at 640x360. D94 explains what it would cost.

## Screen

This project's word for a top-level scene that fills the window and is swapped
in and out by `Main`: the title screen, the online games list, the lobby, the
playing screen, the result screen. They live in `src/ui/screens/`.

Godot has no such concept. Its unit is a **scene** (a `.tscn` file), and a
reusable widget — a stalk row, a lobby row — is a scene as well. "Screen"
only means *this* scene owns the whole window, and exactly one of them exists
at a time.

The word was used throughout the code and these documents for weeks before it
was written down here, which is the sort of thing this glossary exists to
catch.
