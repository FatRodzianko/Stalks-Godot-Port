# StalkleHeads — game design document

**Status: design approved by the owner on 2026-11-21. Nothing in here is built.** No
gameplay code, no scenes and no changes to any existing system were written for this
document. Every open question in §14 is answered; the build plan is §11. The balance
figures were re-measured on the approved roster on the same day (§2.6).

**What it is.** StalkleHeads is an *additional* game mode, chosen in the lobby
alongside the shipped game, in which stalk prices come from a simulated market
rather than from random rolls. Each company carries earnings and expense reports,
belongs to an industry, and its price can be accounted for, point by point, from
information the player was shown.

**What it is not.** It does not replace the base game, change a single rule of it,
or alter any number in [game-rules.md](game-rules.md). The two modes exist side by
side in one build and a match is one or the other. Every claim in this document about
not disturbing the base game is written as a test in [§12](#12-testing).

**Who this is written for.** Somebody who has read [CLAUDE.md](../CLAUDE.md),
[game-rules.md](game-rules.md) and [architecture.md](architecture.md), has never seen
the original Unity project, and has no AI assistance. Godot concepts are explained
where they come up. Every number used anywhere in this document is defined in it.

**Reading order if you are short of time.** [§2](#2-the-market-model-the-decision)
is the recommendation and the argument for it, including where it disagrees with the
brief. [§14](#14-open-questions-for-the-owner) is what needs deciding before any of
this is built. Everything in between is the detail.

---

## Contents

1. [The design bar, as testable properties](#1-the-design-bar-as-testable-properties)
2. [The market model: the decision](#2-the-market-model-the-decision)
3. [The market model in full](#3-the-market-model-in-full)
4. [The year, step by step](#4-the-year-step-by-step)
5. [The NPC traders](#5-the-npc-traders)
6. [How much a player has to hold in their head](#6-how-much-a-player-has-to-hold-in-their-head)
7. [The interface](#7-the-interface)
8. [Content taxonomy](#8-content-taxonomy)
9. [Reaching the client](#9-reaching-the-client)
10. [Where this plugs into the existing code](#10-where-this-plugs-into-the-existing-code)
11. [Build plan](#11-build-plan)
12. [Testing](#12-testing)
13. [Size and risk, honestly](#13-size-and-risk-honestly)
14. [Open questions for the owner](#14-open-questions-for-the-owner)
15. [Decisions this document proposes](#15-decisions-this-document-proposes)
- [Appendix A — the balance probe](#appendix-a--the-balance-probe)
- [Appendix B — prior art, and what was taken from it](#appendix-b--prior-art-and-what-was-taken-from-it)
- [Appendix C — on the game-design-document skill](#appendix-c--on-the-game-design-document-skill)

---

## 1. The design bar, as testable properties

The brief states the bar in the owner's words:

> while realism isn't the ultimate goal, it still needs to be believable. Players
> need to feel like they are actually analyz[ing] real information, not just random
> flavor with no real effect on the game. Prices for stalks need to mean something to
> the player, something they feel like they can quantify if they look hard enough at
> the information provided.

That is a feeling, and a feeling cannot be asserted in a test. So it is restated here
as five properties that can be, and the rest of this document is held to them.

| # | Property | How it is checked |
|---|---|---|
| **P1** | **Every point of every price movement has a published cause.** Given a company's year, the movement decomposes into named terms that sum exactly to the realised change. | A test asserts the ledger sums to the delta, for every company, every year, over many seeds. [§3.5](#35-the-price-identity-and-the-movement-ledger) |
| **P2** | **A player who reads the information wins more often than one who does not** — by enough to feel earned. | Measured: strategy win shares over 600 seeds. [§2.1](#21-what-was-measured) |
| **P3** | **A player who reads nothing is still in the game.** Ignoring every tab must not be ruinous. | Measured: the no-reader's median net worth against the readers'. |
| **P4** | **No single mechanical rule dominates a match of typical length.** If one column of the board decides a 10-year game, the mode is a lookup table, not a market. | Measured: the leading strategy's win share at the default length. Target: under 30% with nine contenders. |
| **P5** | **The base game is bit-for-bit unchanged.** | A seeded 99-year base-mode match produces an identical history before and after StalkleHeads exists. |

P4 is the one that killed the first three versions of this design, and
[§2.2](#22-the-structural-finding-an-anchor-is-an-arbitrage) is about why.

**P4 is deliberately scoped to the default match length, and that scoping is not a
dodge — it is a measured fact about compounding.** A strategy with any real per-year
edge, reinvested, dominates a long enough match by arithmetic alone. Measured across
match lengths with the recommended model:

| Match length | Leading strategy's win share |
|---|---|
| **10 years (the default)** | **22%** |
| 25 years | 47% |
| 50 years | 78% |
| 99 years | 88% |

On the approved eighteen-company roster (§2.6); the thirteen-company draft measured
23%, 45%, 72% and 87%.

> **Superseded by the balance tool, 2026-11-21.** These figures came from a probe whose
> `TREND` strategy compared earnings with two years earlier and was distorted by splits.
> Measured correctly, over the real simulation, the leading strategy won **48.5%** of
> ten-year matches, so P4 failed. **Fixed on 2026-11-22** ([D151](decisions.md)): with
> `GROWTH`'s stay chance at 42 and its premium at 1.2, the leader wins about 28% of
> ten-year matches and 49% of 25-year ones, with no flow and no desk yet. See
> [Appendix A](#appendix-a--the-balance-probe).

The base game escapes this only by having no edge to compound — which is why parking
everything in BERRY BONDS wins 38% of its 10-year matches and 41% of its 25-year ones
([§2.1](#21-what-was-measured)). So **a long StalkleHeads match rewarding the better
analyst decisively is the mode working, not failing.** Whether 99-year matches should
be capped back toward parity is a design preference rather than a bug, and it is
question 13 in [§14](#14-open-questions-for-the-owner).

---

## 2. The market model: the decision

The brief asks for an honest evaluation of two approaches and a recommendation.

- **Order flow first** (the owner's note): NPC traders and players trade; the
  cumulative buying and selling *creates* the price movement; news and events are then
  chosen to match what the market did.
- **Fundamentals first**: earnings, industry and market conditions determine what a
  company is worth; the price follows from that; NPC trading is a visible consequence
  rather than the cause.

**Recommendation: fundamentals first, in a strict form — the price *is* the
fundamentals, with no hidden noise at all. Order flow is then added back as a small,
published, clamped term, because measurement says that at the default match length it
costs nothing and it pays for watching the traders.**

The argument is below, and it is not the argument I expected to be making when I
started. The measurements changed it three times, and the third reversal came from the
owner's design notes removing a constraint I had imposed on myself.

> **A note on this section's history, because the reasoning matters more than the
> conclusion.** The first version of this document recommended *against* an order-flow
> price term on four grounds. Two of those were answered by the owner's notes (many
> NPC traders, acting independently of players, make flow exist in single-player and
> make reading the crowd a deliberate goal). A measurement then appeared to confirm
> the remaining objection emphatically — flow took the leading strategy's win share
> from 30% to 61%. A further measurement overturned *that*: the harm was conditional
> on a separate parameter, and once that parameter was corrected for an unrelated
> reason, flow became free. The sequence is left visible in §2.4 because a reader who
> only sees the conclusion will reinstate the mistake.

### 2.1 What was measured

A throwaway reference implementation of both models was written in Python with
integer arithmetic matching GDScript's (truncation toward zero), including the shipped
game's exact stat block, 7/12 mood weighting, 10% contrarian roll, long-game softening,
one event per year, splits above 150 rounding up, bankruptcy at zero, and dividends by
mood. Eight player strategies were run through 600 seeded matches of each model.

The probe and its output are preserved; see
[Appendix A](#appendix-a--the-balance-probe). **Everything it computes is specified in
prose and tables in [§3](#3-the-market-model-in-full), so the document stands alone if
the probe is lost.**

The strategies, each a rule a real player could follow:

| Strategy | Rule |
|---|---|
| `HOLD` | Buy every company equally in year 1 and never trade again |
| `LOWPE` | Each year, hold the three lowest P/E companies |
| `HIGHPE` | Each year, hold the three highest P/E companies |
| `TREND` | Each year, hold the three whose published earnings per share grew fastest |
| `MOMENTUM` | Each year, hold the three whose price rose most last year |
| `CONTRARIAN` | Each year, hold the three whose price fell most last year |
| `FOLLOW` | Each year, copy whichever NPC trader is doing best |
| `RANDOM` | Each year, hold three at random |
| `BOND` | Put everything in BERRY BONDS and never move |

`FOLLOW` exists to test whether "read the other traders" is a real route to winning,
which the brief asks for explicitly. It is, and [§5.2](#52-what-they-are-for) gives the
numbers.

**Result 1 — the shipped game is barely analysable, and the safest asset wins it.**
Ten-year matches, starting cash 10,000:

```
  strategy        median net   mean net    win share
  HOLD                10576      11288     0.0%
  LOWPE               11031      13224    15.8%
  HIGHPE              11029      11355     2.5%
  TREND               11453      13015    11.8%
  MOMENTUM            10844      11856     8.0%
  CONTRARIAN          11869      13412    14.8%
  RANDOM              11647      12262     9.2%
  BOND                13426      13425    37.8%      <-- do nothing
```

`RANDOM` beats four of the six active strategies on median net worth, and parking
everything in BERRY BONDS beats all of them and wins 38% of matches. At 25 years the
bond's win share rises to 41%.

This is not a criticism of the original — it is a party game of bets on a random
number generator and it is enjoyable as exactly that. But it is a measured, concrete
statement of **why this mode is worth building**: in the shipped game there is almost
nothing to analyse, and the dominant strategy is to not play. Any version of
StalkleHeads that beats those numbers on P2 and P4 is an improvement, and the figures
above are the baseline to beat.

Note also what the probe says about the stat block: for most stalks the expected
yearly move is *negative* (Teamsters, for instance, averages −7 a year: a mean bull
gain of 7.5 at 58% against a mean bear loss of 27.5 at 42%). Prices drift down and the
dividends are the real return. That is why the bond wins, and it is worth knowing
before anybody tunes anything.

### 2.2 The structural finding: an anchor is an arbitrage

The first two versions of the fundamentals model worked like this: fundamentals
compute a **fair value**; the price moves some fraction of the way toward it each
year; a little random noise is added. That is the textbook design and it is what I
would have proposed on reasoning alone.

It failed P4 badly, and got worse the more it was tuned:

| Version | Convergence | Noise | `LOWPE` win share, 10 years | `LOWPE` median net |
|---|---|---|---|---|
| v1 | 55% of the gap | ±2…±8 | 40.2% | 33,319 |
| v2 | 35% of the gap | ±2…±8 | 55.3% | 35,493 |
| v3 | 85% of the gap | ±6…±18 | 53.2% | 33,063 |

Against a `HOLD` median of 12,000–16,000, that is a strategy returning two to three
times what everybody else gets, and at 25 years the gap reached eighteen-fold. Reading
one column was not an edge, it was the game.

**The cause is structural and no amount of tuning fixes it.** If the price reverts
toward a value the player can compute, then computing that value is free money: buy
whatever sits below the anchor, wait for the reversion, repeat. Both halves of the
design are doing it:

- **Partial convergence** leaves a *known* gap that the rules guarantee will close.
- **Mean-zero noise** manufactures fresh gaps every year for the dip-buyer to collect.

And note the uncomfortable corollary, because it explains Result 1 as well:

> **Analysability and anchoring are the same thing.** The shipped game resists
> analysis precisely because its random walk has no level to return to — there is
> nothing to arbitrage because there is nothing to compute. The more computable a
> fair value is, the more mechanical the winning strategy becomes.

So the design question is not "how do we add fundamentals". It is **"how do we make
the price computable without making it predictable"** — and the answer is to move all
of the uncertainty into the *future* and leave none of it in the present.

**There was a third source of reversion, and it took another round of measurement to
find.** Dropping convergence and noise fixed ten-year matches and left twenty-five-year
ones at 64% for a mechanical low-P/E rule. The cause was the **valuation premium** — the
bonus a company's multiple gets for being in a good earnings regime (§3.4). That
premium is bounded and the regimes revert, so a company on a discounted multiple will
on average see that discount close, and buying discounts harvests it. It is the same
arbitrage one layer up: not price reverting to fair value, but *the multiple* reverting
to its mean.

Narrowing the premium spread to 40% of its first-draft width:

| Premium spread | Leading strategy's win share, 25 years |
|---|---|
| First draft (`GROWTH` +1.5 … `DISTRESS` −3.5) | **63.7%** |
| × 0.4 (recommended) | **27.0%** |
| × 0.0 (no premium at all) | 27.3% |

So ×0.4 captures essentially all of the benefit while keeping some of the "market pays
up for growth" character that makes P/E worth reading at all. Going all the way to zero
buys nothing. **The lesson generalises: any bounded, mean-reverting quantity that
enters the price is an arbitrage, however deeply it is buried.** That is now three
layers deep and worth checking against any future addition.

### 2.3 The recommendation: the price is an identity

**Drop convergence and drop noise. The price is not something that moves toward the
fundamentals; it is the fundamentals, restated.**

```
price = fair_value + event_carry
```

where `fair_value` is this year's earnings per share multiplied by this year's
valuation multiple, and `event_carry` is the undecayed remainder of the special
events that have hit this company (the announced shocks, which fade over a couple of
years). Both terms are fully specified in [§3](#3-the-market-model-in-full).

The consequences are the whole design:

- **There is no hidden wobble to buy.** A price below where its earnings say it
  should be happens for exactly one reason: an event knocked it there, and the event
  was announced in the news panel that year. Reading that and buying the dip is a
  real skill with a real, bounded payoff, rather than a mechanical pump.
- **Every point is accountable** (P1). The year's change decomposes into earnings,
  multiple, industry standing, event, and event decay, and those terms sum to the
  realised number. That decomposition is a *screen* — see
  [§7.5](#75-tab-4--company).
- **All the uncertainty is forward-looking.** What a player cannot know is next
  year's earnings regime, next year's industry roll, next year's mood and next year's
  event. Those are forecastable from published odds and never knowable. That is the
  gamble, and it is the same shape of gamble the base game offers, with the odds now
  legible.

Measured, with the model exactly as specified in §3 — 13 companies, derived mood, the
narrowed valuation premium, and the flow term clamped at 5% (ten-year matches, 400
seeds):

```
  strategy        median net   mean net    win share
  HOLD                11291      11855     0.2%
  LOWPE               15820      20249    23.2%
  HIGHPE              10783      12503     3.8%
  TREND               15645      18764    14.2%
  MOMENTUM            16997      18871    21.8%
  CONTRARIAN           6660       9529     0.8%
  FOLLOW               9631      19855    16.8%
  RANDOM              12078      15056    12.0%
  BOND                13426      13426     7.2%
  leading strategy win share: 23.2%
```

Reading against the five properties:

- **P2, met.** Four separate readings of the board — cheapness, trend, momentum and
  following the traders — return 1.4× to 1.5× the no-reader's median and between them
  take three matches in four.
- **P3, met.** `RANDOM` wins 12% and `BOND` 7.2%, with medians a few thousand off the
  readers'. The friend who buys whatever has the funniest name is still in the match,
  and the bond has gone from dominant to ordinary (38% → 7.2%).
- **P4, met.** 23.2% against a 30% target, and the distribution is the healthy part:
  **seven of nine strategies win between 3.8% and 23.2% of matches.** No column of the
  board decides the game.
- **P1 and P5** are properties of the construction, not of the numbers, and are
  tested directly.

**Four readings pay, and they pay differently.** This is the result worth dwelling on,
because it is what the first draft's model could not do. `LOWPE` (buy the cheap),
`MOMENTUM` (buy the rising), `TREND` (buy the growing) and `FOLLOW` (copy the best
trader) all beat doing nothing, none dominates, and they disagree with each other about
what to buy — which means a table of friends can hold four different convictions and
all of them be reasonable.

And the mode still feels like a game of this shape: **1.8 splits per ten-year match**
against the base game's 2.0, **0.4 bankruptcies** against 1.0, and mean yearly movement
of 21 points against 16. Slightly fewer wipeouts, a bit more movement.

**The bull/bear rate came out at 55.4%** — and nothing set it. The mood is now derived
from what the index actually did ([§3.1](#31-three-layers-three-kinds-of-predictability)),
so that figure is an *output*. The shipped game's hand-tuned 7/12 is 58.3%. Landing
within three points of a number the original arrived at by choosing it is the single
best evidence available that the simulated market behaves like the game it is
simulating.

### 2.4 Where this disagrees with the brief, and where it does not

The brief asked for scrutiny of the NPC-order-flow idea and said not to implement it
out of deference, nor dismiss it. Taking both halves seriously:

**What the order-flow idea gets right, and this design keeps in full.** The NPC
traders are the best idea in the brief. They are kept, with published strategies, and
they do four jobs that nothing else does:

1. **They are a human-readable summary of the analysis.** They act on the same
   fundamentals the player can read. A player who cannot be bothered to compute
   anything can watch where the value traders are piling in and follow them. That is
   the single best on-ramp in the design — Tier 1 in
   [§6.1](#61-four-tiers-of-engagement) is "follow a hotdog".
2. **They give the Company tab something alive in it.** "Recent activity in this
   company" is a real list of real decisions made for stated reasons.
3. **They make the short-squeeze idea honest.** A short-selling NPC's position *is*
   the short interest, so the news item that foreshadows a squeeze is a true statement
   about a real state variable, and the squeeze really is likelier. See
   [§5.3](#53-short-interest-and-honest-foreshadowing).
4. **They make a one-player match a market.** Nine other traders are at the table
   even when nobody else is in the lobby.

**The four objections the first draft raised, and what happened to each.**

1. ~~**Order flow is not information the player has in time.**~~ **Withdrawn.** This
   assumed the crowd was unreadable. With many NPC traders whose strategies are
   published (§5.1), the crowd is a *second* analysable system: you can work out what
   the value cohort will buy next year from the same board they are reading. The brief
   asked for prices quantifiable from the information provided, and the traders'
   positions and rules *are* information provided. Measured: `FOLLOW`, which does
   nothing but copy the best-performing trader, wins 16.8% of ten-year matches — the
   third-best strategy of nine.
2. **It is reflexive, and reflexive in the player's favour. Still true, and now
   quantified rather than feared.** Net worth is computed from the posted price, so
   raising the posted price of something you hold flatters your own score. Two things
   contain it: the clamp (§3.10) bounds the effect at 5% of fair value, and the NPC
   desk is large, so one player's share of total flow is small — which is precisely
   the owner's point about having many simulated traders. The residual exploit is a
   few percent for a year, decaying by half each year after. **Accepted, with the cost
   stated.**
3. ~~**It has no scale.**~~ **Withdrawn, because the premise was mine, not the
   design's.** The objection was that an emergent price level would drift out of the
   band the base game's splits and bankruptcy are pinned to. The owner's notes removed
   that constraint: StalkleHeads sets its own scale (§3.2), and the flow term is a
   bounded fraction of a fundamentally-determined fair value rather than a free-running
   level, so it cannot drift anywhere.
4. ~~**It does not survive one player.**~~ **Withdrawn.** This was the weakest
   objection and the owner answered it directly: the NPC desk trades independently of
   the players and is far larger than they are, so flow exists in a solo match exactly
   as it does in a ten-player one. A single player is one voice in a market of
   twenty-four, which is the right ratio.

**What the measurement actually found, which was none of the above.** Adding the flow
term to the first draft's model took the leading strategy from 30% to 61% of matches —
far worse than any of the four objections predicted. The mechanism is specific and
worth knowing:

> **A price term driven by NPC flow amplifies whatever rule the largest NPC cohort
> follows.** The value traders buy the lowest P/E; a player buying the lowest P/E is
> therefore front-running a published, deterministic order book. The flow term does
> not add uncertainty, it adds a self-reinforcing echo of the most readable signal.

**And then that finding was overturned too.** The amplification only matters if there
is a strong signal to amplify. Once the valuation premium was narrowed for the
unrelated reason in §2.2 — which weakened the low-P/E signal — flow stopped costing
anything:

| Ten-year matches | Leading strategy's win share |
|---|---|
| No flow term | 24.2% |
| Flow clamped at 5% of fair value | **23.2%** |
| Flow clamped at 18% of fair value (first draft's clamp) | 61.3% |

So **flow at a tight clamp is free at the default match length, and it raises
`FOLLOW` from 14.2% to 16.8%** — it pays for watching the traders, which is what the
owner asked for. The clamp is doing real work: at 18% the amplification returns in
full.

**One honest caveat: flow's cost scales with match length, like everything else.** At
25 years, flow at a 5% clamp takes the leading strategy from 27.0% to 45.5%. The
natural remedy is to scale the clamp down in long matches, which is the third use of
the same ladder the game already applies to price swings and to earnings growth
(§3.3). It is specified in §3.10 and is not yet measured.

**One part of the brief is still rejected, and for a different reason:** choosing the
news and events *after* the market has moved, to match it. That inverts cause and
effect, and P1 forbids it — a price that moved and then had a reason picked for it is
exactly "random flavour" with a caption. In this design the event is drawn first and
*causes* its part of the movement, which is what makes the ledger balance.

**On "NPCs move the stalks players are ignoring".** Worth separating out, because it is
a real concern with an answer the owner may not expect: **in a fundamentals model an
ignored stalk moves anyway**, because its price is its earnings and its earnings do not
care whether anybody is watching. That concern is a *base-game* concern, where nothing
moves a stalk except its own roll and the one yearly event. Flow is not needed to solve
it, and it is solved either way.

### 2.5 The P/E circularity, resolved

The brief is right that this quietly becomes incoherent if it is not nailed down. It
is nailed down as follows, and the direction never reverses:

> **Earnings are the input. Price is derived from earnings. P/E is a readout of the
> price, and is never an input to anything.**

In order:

1. A company's **profit** comes from its revenue and its margin, which come from its
   earnings regime and its industry. Authored content and the simulation's own state —
   no prices involved.
2. **Earnings per share** is profit divided by shares outstanding.
3. The **multiple** is what the market will pay for a unit of earnings this year. It
   comes from the market mood, the industry's standing, and the company's regime.
   No prices involved.
4. **Price** = earnings per share × multiple, plus event carry.
5. **P/E** = price ÷ earnings per share. Which, by construction, is approximately the
   multiple — so P/E is the one number on the board that tells the player *what the
   market thinks of this company*, in a single figure, and it required no arithmetic
   from them.

Because P/E is derived in step 5 and consumed by nobody, **it is never stored at
all** — it is computed where it is displayed and thrown away. A number that is never
stored cannot be mis-scaled, mis-rounded, or fed back into the simulation by accident.
See [§3.7](#37-money-is-int-ratios-are-float).

**A word on what P/E actually is**, because it is easy to make it sound harder than it
is. P/E is not a ratio of two numbers in the sense that needs a colon and cannot be
reduced — it is a single quotient, a multiple: *"this company costs 13.1 times its
annual earnings."* One number, like a temperature. So there is never a question of
whether some stored figure means 13:11 or 131:1; there is one value, 13.1, and the only
decision is how many decimal places to show. The answer is one.

What makes P/E *useful* rather than merely present is that the board shows it next to
its industry's average (§7.2). A company on 9.4 in an industry averaging 13.1 is
cheap relative to its peers, and the player has made that judgement by looking at two
adjacent numbers. That is the design target for how hard the analysis should be.

### 2.6 Re-measured on the approved roster

> **Read with care: the `TREND` row below is wrong.** The probe that produced this
> section measured `TREND` over two years, not one, and split-distorted. With that
> corrected `TREND` wins 40-51% of ten-year matches depending on configuration, so
> "P4 still holds" below was not true as measured. P4 was restored by a matrix and
> premium change on 2026-11-22 ([D151](decisions.md)), and every figure below predates it. The balance tool reproduces the probe's
> no-flow run once the probe is corrected; the flow and `FOLLOW` figures wait for the
> desk (S4). See [Appendix A](#appendix-a--the-balance-probe) and
> [D149](decisions.md).

**Every figure in §2.1–§2.4 was measured on the thirteen-company draft.** The owner's
decisions of 2026-11-21 changed the market under it: eighteen companies in six
industries of three, a dividend policy for each company, and paying out slowing growth
(§3.2.3, §3.10a). So the measurement was run again on exactly that, with one addition —
an `INCOME` player strategy (buy the three highest dividend yields), because the
dividend policy is the newest place an arbitrage could hide (proposed decision A2).

Ten-year matches, 400 seeds, flow clamped at 5%:

```
  strategy        median net   mean net    win share
  HOLD                11489      12246     0.0%
  LOWPE               16501      22825    22.2%
  HIGHPE              12502      14496     4.2%
  TREND               18721      21547    22.0%
  MOMENTUM            18864      20703    15.0%
  CONTRARIAN           6397       8333     1.0%
  INCOME              13491      15093     6.2%
  FOLLOW               9871      26890    12.8%
  RANDOM              13179      16866    14.2%
  BOND                13426      13426     2.2%
  leading strategy win share: 22.2%
```

| Measure | Thirteen-company draft | Approved roster |
|---|---|---|
| Leading strategy, 10 years | `LOWPE` 23.2% | `LOWPE` 22.2%, `TREND` 22.0% |
| Strategies winning at least 4% | 7 of 9 | 7 of 10 |
| `FOLLOW` (copy the best trader) | 16.8% | 12.8% |
| `RANDOM` (the no-reader) | 12.0% | 14.2% |
| `BOND` (do nothing) | 7.2% | 2.2% |
| Leading strategy with no flow term | 24.2% | 21.0% |
| Bull-year rate | 55.8% | 56.9% |
| Splits per 10-year match | 1.8 | 2.0 |
| Bankruptcies per 10-year match | 0.4 | 0.4 |
| Leading strategy, 25 / 50 / 99 years | 45.5% / 71.6% / 87.3% | 47.2% / 78.4% / 88.0% |

**What it shows.**

- **P4 still holds at the default length**, a point better than before, and the lead
  is now shared: reading cheapness and reading earnings trend are level at 22%. Two
  readings tied at the top is a healthier shape than one in front.
- **The dividend policy is not an arbitrage.** `INCOME` wins 6.2%. The growth
  trade-off is what keeps it there, and the comparison is worth having:

  | Variant | `INCOME` win share | Leader |
  |---|---|---|
  | Every company at the neutral 35 | 15.2% | 19.0% |
  | Policies, no growth trade-off | 10.0% | 19.8% |
  | **Policies with the trade-off (the design)** | **6.2%** | **22.2%** |

  Without the trade-off income is a respectable strategy; with it, it is a weak one.
  The policy did not create a dominant strategy — **it made income worse**, because the
  highest yields now belong to the slow growers. That is believable (a pension fund is
  not a growth stock) but it may be more than wanted: `INCOME`'s median, 13,491, barely
  beats the bond's 13,426. **The slope of the trade-off is the tuning lever.** It is
  written as one point of growth per point of policy (§3.10a); halving it is the obvious
  first thing for S9 to try if income should be a real route rather than a niche.
- **Flow is still close to free**, costing about one point of P4 (22.2% with it, 21.0%
  without), and it is still what makes watching the traders pay: `FOLLOW` is 12.8% with
  flow and 10.0% without.
- **The bond has stopped winning.** Eighteen companies mean that a reader has more
  places to find an edge, and doing nothing finishes first in one match in fifty. It
  is still the safe line (its median beats `HOLD`'s), which is what it is for.
- **The long-match gradient got slightly worse** at 50 years (71.6% → 78.4%) and is
  unchanged elsewhere. More companies give a compounding edge more to compound on. This
  is the known risk of [§13.2](#132-the-risks-worst-first), not a new one, and its
  levers are unchanged.

**The same limitations apply** ([Appendix A](#appendix-a--the-balance-probe)): this is a
parallel implementation, not the real simulation, with no loans, a faked index and no
news. The probe is `model_probe_v3.py`, beside the others.

---

## 3. The market model in full

Everything in this section is integer arithmetic. Division truncates toward zero,
matching GDScript's `int / int` and the `(int)` casts the original used — the same
convention [game-rules.md §4.4](game-rules.md) pins for long-game softening.

### 3.1 Three layers, three kinds of predictability

| Layer | What it decides | How predictable | Why that is right |
|---|---|---|---|
| **The market** | Nothing directly. It **reports** what the market did, and last year's report becomes this year's *sentiment* | **Weakly.** Sentiment persists, so a rising market tends to keep rising, but it is the sum of everything else and cannot be read off any one company | The market is a consequence, not a cause |
| **An industry** | A yearly performance figure per industry | **Partly.** Persistent year to year, so last year's figure informs this year's | This is the owner's "the market can be up, but oil and gas is down" |
| **A company** | Its earnings regime, and from that its revenue and profit | **Substantially.** Regimes persist, and a long good run visibly ages | This is where the analysis lives and where reading pays |

**The mood is derived, not rolled — the first draft had this wrong.** It asked whether
a bull or bear year should be decided by a weighted coin, and the owner's note answers
it: the market's mood *should* be what the market did. It now is:

```
index_move_pct = the mean price move of the surviving companies this year
mood           = BULL if index_move_pct > 0 else BEAR        # a label for the year
sentiment      = clamp(index_move_pct, -20, +20)             # carried into next year
```

So "BULL!!!" is a **report**, published after the prices settle, and it is true by
construction. There is no coin left in the design.

**The circularity this appears to create is avoided by one year of lag.** The mood
cannot set this year's multiples, because it is not known until this year's prices
exist. What feeds the multiple is **last year's** index move, as `sentiment` (§3.4).
That is both non-circular and more believable than a roll — real markets do run on
momentum of exactly this kind — and it has the side effect of making market conditions
*mildly* forecastable, which gives a player one more thing to read.

**It also lands on the right number without being told to.** The derived bull rate
measures at **55.4%** over ten-year matches and 58.7% over twenty-five-year ones. The
original's hand-chosen array is 7 bull to 5 bear, or 58.3%. Nothing in the model was
tuned toward that; it falls out of the earnings transitions. The shipped figure is
therefore no longer a setting StalkleHeads needs, and `bull_weight` / `bear_weight` are
unused in this mode.

**The feedback loop in sentiment is real and is damped deliberately.** Sentiment raises
multiples, which raises prices, which raises sentiment. Left at the first draft's gains
the bull rate ran to 66% at ten years and 74% at twenty-five — a market that only ever
went up. The gains in §3.4 are the damped values, and the bull rate is a figure to
assert in a test precisely because a future edit to either gain can quietly inflate the
whole market.

### 3.2 Company fundamentals

New authored content per company. Whether these fields live on `StalkDefinition` or
on a separate `CompanyProfile` resource beside it is a code decision, not a design
one; [§10](#10-where-this-plugs-into-the-existing-code) recommends the latter so that
base-mode content is untouched.

| Field | Type | Meaning |
|---|---|---|
| `industry` | `StringName` | Which industry it belongs to, by that industry's `id`. **The field already exists on `StalkDefinition`**, reserved for this mode and currently unused |
| `starting_earnings_per_share` | `float` | What it earns a share in year 0. With the base multiple, this is what sets its opening price |
| `starting_margin_percent` | `float` | Profit as a percentage of revenue, at year 0 |
| `shares_outstanding` | `int` | Divisor for earnings per share. Doubles on a split |
| `quality` | `int` 0-100 | Biases the regime roll toward better regimes. 50 is neutral |
| `industry_beta_percent` | `int` | How much of its industry's performance reaches its own revenue. 100 is one-for-one |
| `payout_policy_percent` | `int` 0-100 | Share of its earnings it pays as a dividend in a normal year. Paying more slows its growth (§3.10a). 35 is neutral |

The first draft also had a `volatility` field. **It is gone**: in a model with no noise
term there is nothing for it to scale, and a field that exists "for later" is a field
somebody will eventually wire into something.

### 3.2.1 Why `industry` is a `StringName` and not an enum

> **For a reader new to Godot:** a `StringName` is Godot's *interned* string type. The
> engine keeps one copy of each distinct value, so comparing two `StringName`s is a
> pointer comparison rather than a character-by-character one - fast enough to do in a
> loop. But it is still a string, so `&"oil_and_gas"` and `&"oil-and-gas"` are simply
> two different values and nothing in the language will complain. An `enum` is the
> opposite trade: `Industry.ENERGY` is checked when the script is parsed, so a typo
> cannot compile - but the set of values lives *in code*, so adding an industry means
> editing a script.

The concern is real: a mistyped industry id would silently produce a company in an
industry of one, or an industry report that can never fire.

**This is not a rule against enums.** The project uses them where they fit
(`MarketMood.Value`, `LaunchArgs.Mode`), and this design adds two more: the five
earnings regimes (§3.3) and the NPC strategies (§5.1). The rule that applies is
narrower. [CLAUDE.md](../CLAUDE.md), under *Data as Resources*, says stalk and event
definitions are resources and that *"new content should be addable by creating a
resource file, with no code change."* So the question is which side of that line an
industry is on, and there is a simple test for it:

> **Does the code do something different for each value?** If yes, it is a closed set
> and belongs in an enum. If the code treats every value the same way and only the
> *data attached to it* differs, it is content and belongs in a resource.

| Set | Does code branch on each value? | So |
|---|---|---|
| Regimes | **Yes.** Each has its own row in the transition matrix, its own growth band, its own payout ratio, and ageing applies to two of them only | Enum. Adding a sixth regime *should* need code, because it needs new rules |
| NPC strategies | **Yes.** Each is a different trading rule, written as code | Enum |
| Industries | **No.** Every industry is handled identically: roll its performance, average its members, apply its beta. What differs is its name, its members and its news | Content |

The test is a widely used one, not something peculiar to this project - it is the
usual line between *data-driven* and *code-driven* design, and the cost of getting it
wrong runs both ways. An enum for content means two places to keep in step: the enum
entry, and a resource anyway, because an industry still needs a display name and news
that do not belong in a script. A resource for a closed set means the code ends up
matching on strings to decide behaviour, which is the typo risk with none of the
benefit.

**So: keep `StringName`, and catch the typo where this project already catches typos.**
Industries become first-class content - an `IndustryDefinition` resource with an `id`,
a display name and its own news - and `ContentLibrary.validate()` refuses to vouch for
a company whose `industry` does not resolve to one of them. That mechanism is already
built and already load-bearing: [D31](decisions.md) exists because ninety events
reference ten stalks by id, and a single typo produces an event that can never fire and
reports nothing. This is the same risk, answered the same way, with no new machinery.

The practical difference from an enum is only *when* you find out: at content-load time
with a named error, rather than at parse time.

**An enum would not be a mistake**, only a slightly worse trade. If the industry list
is expected to stay at four or six for the life of the game, the cost is one line of
code per industry and the benefit is a parse-time check. It becomes the wrong choice
the first time some code wants to say `if industry == Industry.TECH`, because that is
an industry being given its own rule - and a rule for one industry is better expressed
as a field on its resource that every industry has.

### 3.2.2 No base-game anchoring

The first draft worked hard to make every company start at exactly price 100, to match
the base game. **The owner's notes remove that as a goal**, and the design is better for
it:

> Generally speaking, "matching the base game" should not be a priority of the new
> StalkleHeads mode. It should be thought of as independent of the base game. The only
> thing they really share are the idea of buying/selling stalks, the stalk names and
> the stalk descriptions.

What that licence is spent on - each of these now a measured improvement rather than a
compromise:

| Freed | What this mode does instead | Why |
|---|---|---|
| All prices starting at 100 | **Companies start at different prices**, 30 to 150 | Real companies do not all cost the same. A board already varied at year 0 has something to read on turn one, so a player's first decision is a real one |
| The shipped stat block (`bear_change`, `bull_change`) | **Unused in this mode.** Profiles come from what a company *is* | Those ranges *are* the base game's price model. Translating them into profile numbers would be reimplementing it badly |
| Authored `bull_dividend` / `bear_dividend` | **Dividends are a payout ratio of earnings** (§3.10a) | A company with earnings pays out of earnings - and it removes a second place where the mood mattered |
| Splits above 150 | **Splits above 300** | With earnings that mostly grow, a 150 ceiling made companies split constantly - the first draft measured 5.7 splits a ten-year match against the base game's 2.0. At 300 it measures 1.8, which reads as an event again |
| The 7/12 mood weighting | **Derived** (§3.1) | And it lands at 55.4% anyway |

**What is deliberately *not* changed**, because this is the shared identity the owner
named: the company names, their descriptions, buying and selling stalks, BERRY BONDS
being the safe haven, and My Mutuals and Me Inc. being the fund.

### 3.2.3 The roster

**Decided by the owner on 2026-11-21: option B, six industries of three.** Companies the owner
has not yet created are placeholders named by industry and letter, so that a reader can
see at a glance which rows are waiting to be written.

| Company | Industry | Status |
|---|---|---|
| Springfield Nuclear Power | Energy | shipped |
| PG&Enron | Energy | shipped |
| strYker!!! | Energy | shipped |
| North Haverbrook MONORAIL | Transportation | shipped |
| Transportation Company A | Transportation | **placeholder** |
| Transportation Company B | Transportation | **placeholder** |
| Teamsters Pension Fund | Financial Services | shipped, moved from transport |
| Mafia HUD Scam | Financial Services | shipped, moved from transport |
| Landlords United | Financial Services | new, named |
| My Pillow, Your Pillow, We're All Pillows! | Consumer Goods | shipped |
| Consumer Goods Company A | Consumer Goods | **placeholder** |
| Unionized Submissives LLC | Consumer Goods | shipped |
| Video Chrome | Technology | new, named |
| Meowly | Technology | new, named |
| Technology Company A | Technology | **placeholder** |
| Chichen Pizza | Food | new, named |
| Farms+ | Food | new, named |
| Food Company A | Food | **placeholder** |

Eighteen companies in six industries, three each, plus BERRY BONDS and My Mutuals and
Me Inc., which are not companies — **twenty rows on the board**, which is the case §7.2's
collapsible groups were designed for.

Unionized Submissives LLC was missing from the owner's first list and was placed in
Consumer Goods on the same day (question 15 in [§14](#14-open-questions-for-the-owner)),
which brings Consumer Goods to three with one placeholder.

So **five companies are placeholders.** They need a ticker too, and until they have
real ones they use `TRNA`, `TRNB`, `CONA`, `TECA` and `FODA`, chosen to be obviously
temporary. Every shipped company keeps the ticker it already has (Unionized Submissives
LLC is `SUBS`).

**Why three per industry — the mechanical reason, kept for the record.**

Two is the hard floor, because an industry of one is indistinguishable from the company
in it: its performance, its standing and its average P/E are all just that company's,
so the Industries tab becomes a second copy of the Company tab wearing a hat. But three
is the right target, for two reasons:

1. **Three is the minimum for a comparison to mean anything.** With three members there
   is a leader, a middle and a laggard, which is what makes *"this is the weak one in a
   strong sector"* a real reading. With two, "within the industry" is a single pairwise
   comparison and the market-share chart is two bars.
2. **A bankruptcy must not hollow out an industry.** Bankruptcies measure at 0.4 per
   ten-year match and 1.4 per twenty-five-year one, so they happen. A two-member
   industry whose weaker member dies becomes a one-member industry *mid-match* - which
   breaks the floor rule dynamically, and nothing can fix it once a match is running.
   Three members survive one death.

**Re-measured on this roster** in §2.6: the default ten-year match still meets P4
(22.2%), with cheapness and earnings trend level at the top. §2.1–§2.4 keep the
thirteen-company figures, because the argument there is about how the model was
arrived at.

The owner's worked example ("the market can be 'up,' but oil and gas is down") still
works as written, since Energy holds exactly the three companies the shipped events
describe as oil, gas and power.

### 3.2.4 Proposed profiles

**Placeholders with a rationale, not confirmed content.** They come from what each
company is described as being, not from the base game's stat block. The `payout` column
is the company's dividend policy, explained in §3.10a.

| Company | Industry | Opening EPS | Opening price | `quality` | `beta` | `payout` | Reasoning |
|---|---|---|---|---|---|---|---|
| Springfield Nuclear Power | energy | 9.60 | 120 | 60 | 110 | 60 | A big regulated utility: dependable, dull, pays out |
| PG&Enron | energy | 6.40 | 80 | 30 | 120 | 50 | The name is the risk profile |
| strYker!!! | energy | 4.00 | 50 | 25 | 140 | 0 | Oil wildcat. Never pays — kept from the base game, where it pays nothing either |
| North Haverbrook MONORAIL | transport | 3.20 | 40 | 35 | 100 | 0 | A boondoggle. Cheap, speculative, nothing to pay from |
| Transportation Company A | transport | 8.00 | 100 | 50 | 100 | 35 | Placeholder |
| Transportation Company B | transport | 6.00 | 75 | 50 | 100 | 35 | Placeholder |
| Teamsters Pension Fund | financial | 12.00 | 150 | 55 | 85 | 80 | A pension fund exists to pay out. Keeps its base-game character as the big payer |
| Mafia HUD Scam | financial | 5.60 | 70 | 30 | 110 | 20 | Housing fraud. Low quality by construction |
| Landlords United | financial | 10.40 | 130 | 50 | 115 | 70 | Property holdings pay rent through to shareholders |
| My Pillow, Your Pillow... | consumer | 7.20 | 90 | 55 | 60 | 40 | A staple. Least exposed to its sector |
| Consumer Goods Company A | consumer | 8.00 | 100 | 50 | 80 | 35 | Placeholder |
| Unionized Submissives LLC | consumer | 6.00 | 75 | 50 | 75 | 35 | Services, moderately exposed |
| Video Chrome | tech | 8.80 | 110 | 60 | 130 | 10 | Chips are the most cyclical thing there is; reinvests |
| Meowly | tech | 2.40 | 30 | 40 | 150 | 0 | A startup. Tiny, violent, pays nothing |
| Technology Company A | tech | 8.00 | 100 | 50 | 130 | 35 | Placeholder |
| Chichen Pizza | food | 5.20 | 65 | 50 | 55 | 40 | Frozen food is recession-proof |
| Farms+ | food | 11.20 | 140 | 60 | 70 | 45 | A conglomerate with patents. Big and steady |
| Food Company A | food | 8.00 | 100 | 50 | 60 | 35 | Placeholder |

Opening price is `EPS x 12.5`, the base multiple (§3.4), so those two columns are the
same number stated twice - **the price is not separately authored**, which is the whole
point of the model. Placeholder rows all use the neutral values (quality 50, payout 35)
so that they change nothing about the balance until somebody gives them a character.

### 3.3 Earnings regimes and the transition matrix

This is the heart of it, and it is deliberately the same shape as the single best
piece of prior art for a market players actually learn to read: Animal Crossing's
turnip market, which is four named price patterns and a published table of odds for
which pattern follows which. See
[Appendix B](#appendix-b--prior-art-and-what-was-taken-from-it).

Every company is in exactly one of five regimes, and the regime decides how its
revenue moves this year.

| Regime | Revenue growth | Margin it moves toward |
|---|---|---|
| `GROWTH` | +15% … +35% | 14% |
| `STEADY` | −3% … +6% | 12% |
| `SLOWING` | +2% … +12% | 11% |
| `DECLINE` | −20% … −5% | 7% |
| `DISTRESS` | −45% … −15% | 1% |

Margin does not jump: each year it moves **one third of the way** toward its regime's
target, truncating. So a collapse takes a few years and is visible coming — which is
the point, because a margin falling while revenue still rises is the single most
useful early warning in the whole mode.

**The transition matrix.** Rows are this year's regime, columns are next year's, in
the order above. Percentages, each row summing to 100:

| from \ to | `GROWTH` | `STEADY` | `SLOWING` | `DECLINE` | `DISTRESS` |
|---|---|---|---|---|---|
| `GROWTH` | **42** | 19 | 28 | 8 | 3 |
| `STEADY` | 16 | **50** | 18 | 13 | 3 |
| `SLOWING` | 10 | 28 | **38** | 21 | 3 |
| `DECLINE` | 6 | 18 | 16 | **46** | 14 |
| `DISTRESS` | 5 | 10 | 10 | 25 | **50** |

Left to itself this settles at `GROWTH` 15.1%, `STEADY` 28.8%, `SLOWING` 22.8%,
`DECLINE` 22.9%, `DISTRESS` 10.4% — computed, not guessed, and worth asserting in a
test so that editing a row cannot quietly make the mode miserable.

**The `GROWTH` row was changed on 2026-11-22** ([D151](decisions.md)). It was
`58 | 14 | 20 | 6 | 2`, which settled at `GROWTH` 19.8%. The balance tool showed that a
run that sticky let one strategy, buying last year's fastest earnings growers, win 47%
of ten-year matches. Its stay chance is now 42, with the other columns respread in the
same proportions; Appendix A has the sweep.

**Two modifiers on the roll**, and between them they are what turns a memoryless
chain into something a player has to actually think about:

- **Quality.** `(quality − 50) / 5` points are subtracted from the roll, biasing a
  good company toward the left-hand (better) columns. Range −10 to +10. A quality-25
  company like strYker!!! is five points likelier to fall out of `GROWTH` than a
  quality-60 one like Springfield.
- **Ageing — a good run cannot last forever.** Each consecutive year in `GROWTH` or
  `SLOWING` adds **10 points** to the roll, pushing it right. So `GROWTH`'s stay chance
  runs 42, 32, 22, 12 over a four-year run: a second year of growth is already less
  likely than not, and a fourth is rare. This is the brief's "a fast grower slows, then
  stagnates", and it is the reason the player must count years rather than just read
  the current regime.
- **Recovery — a rock-bottom run also ends.** Each consecutive year in `DISTRESS`
  subtracts **12 points**. Without this, `DISTRESS` is a 50%-sticky death sentence and
  over a 25-year match almost every company reaches it; with it, roughly a quarter of
  companies are dead by year 25 against the base game's 22%. It is also what makes a
  turnaround from the floor possible at all, which the brief's short-squeeze idea
  needs.

Note that `DECLINE` deliberately gets **neither** modifier: bad years beget bad years,
as the brief asks, and bankruptcy is what the end of that road looks like.

**Long matches damp the growth bands**, by the same ladder the base game already uses
for price swings ([game-rules.md §4.4](game-rules.md)) and for the same reason:

| Match length | Growth multiplier |
|---|---|
| > 49 years | × 0.50 |
| > 19 years | × 0.80 |
| ≤ 19 years | × 1.00 |

Without this, a company that holds `GROWTH` for fifteen years compounds at 25% and
leaves the board. Reusing the shipped ladder is a deliberate echo: it is the same
problem the original already solved, with the same numbers.

### 3.4 Industries and the multiple

**An industry's year.** For each industry, in id order:

```
roll        = rng.randi_range(-15, 15)
carried     = last_year_performance * 0.40
tilt        = sentiment * 0.10                      # last year's market, damped
performance = clamp(roll + carried + tilt, -30, +30)    # percent
```

The `carried` term is what makes an industry's performance worth reading: a sector
that fell 20% last year starts this year eight points in the hole, so sector trends
run for several years and a player can see one coming. The `tilt` is deliberately tiny
— a 10% read-through, so a +20% market year moves a sector by two points against a
thirty-point swing — because that is what makes the owner's "market up, oil down"
common rather than a curiosity. It is also the main feedback path into the market, and
the first draft's larger value is what inflated the bull rate to 66% (§3.1).

**An industry's standing** is what the market will pay for its earnings:
`standing = performance * 0.06`, so a +20% sector adds 1.2 turns to every member's
multiple.

**The multiple:**

```
multiple = 12.5                       # the base, see below
         + sentiment * 0.02           # last year's index move, clamped to +/-20
         + industry_standing          # performance * 0.06
         + regime_premium             # the table in 3.3
multiple = clamp(multiple, 4.0, 30.0)
```

Note what replaced the mood here: **`sentiment`, which is last year's index move**, not
this year's bull-or-bear label. The label does not exist yet when multiples are set
(§3.1), and using last year's figure is both non-circular and a better description of
how a market actually prices things.

| Regime | Premium | First draft had |
|---|---|---|
| `GROWTH` | **+1.2** (was +0.6 until D151) | +1.5 |
| `STEADY` | 0 | 0 |
| `SLOWING` | **+0.24** | +0.6 |
| `DECLINE` | **−0.6** | −1.5 |
| `DISTRESS` | **−1.4** | −3.5 |

**The premium spread is 40% of the first draft's, and that number is measured** —
except `GROWTH`'s, raised to 1.2 on 2026-11-22 with its shorter runs
([D151](decisions.md)). With growth less persistent, the market pays more for a growth
year; widening the other four as well brought the cheap-P/E exploit back, which is why
only `GROWTH` moved. It is
the third and last of the mean-reverting quantities that made this design a lookup
table; §2.2 has the figures. The spread is narrow enough that a discounted multiple is
not a free lunch and wide enough that P/E still says something about what the market
thinks — which is the only reason the column is on the board.

**Where 12.5 comes from, which is where BERRY BONDS earns its keep.** The bond pays
3 a share on a price of 100, so the risk-free yield in this game is 3%. A multiple of
12.5 is an earnings yield of 8% — five points of compensation for owning a company
instead of the bond. That is a believable number and it is derived from something
already in the game rather than picked. It also gives the Company tab a genuinely
useful line to print: *earnings yield 8.0% against a risk-free 3.0%*.

### 3.5 The price identity and the movement ledger

```
earnings_per_share = profit / shares_outstanding
fair_value         = clamp(earnings_per_share * multiple, -40.0, 1200.0)

event_carry        = previous_event_carry * 0.50           # last year's, halved
event_carry        = event_carry + this_year_event_delta    # if targeted this year

flow               = previous_flow * 0.70                   # last year's, mostly kept
flow               = flow + net_shares_traded_last_year / shares_outstanding * 100 * 0.55
flow               = clamp(flow, -0.05 * fair_value, +0.05 * fair_value)

price              = int(fair_value + event_carry + flow)   # one truncation
```

That is the entire price model. **There is no convergence term and no hidden noise
term**, and [§2.2](#22-the-structural-finding-an-anchor-is-an-arbitrage) is why.

The three terms, and what each is for:

| Term | What it is | Readable because |
|---|---|---|
| `fair_value` | Earnings times the multiple | Both inputs are published in last year's report |
| `event_carry` | The undecayed remainder of announced events | The event was the headline in the news panel |
| `flow` | What the traders, NPC and human, did last year | Their positions and their rules are published (§5) |

**`flow` is the term the first draft left out**, and §2.4 is the full account of why it
is back. Three properties keep it safe, and all three are load-bearing:

- **It is clamped to 5% of fair value.** Measured: at this clamp it costs at most a
  point of P4 (23.2% against 24.2% without it on the thirteen-company draft, 22.2%
  against 21.0% on the approved roster, §2.6); at the first draft's 18% the leading
  strategy jumps to 61.3%.
- **It persists rather than reverting.** `0.70` carried forward means a crowd that
  bought last year is still pushing this year, so a price below fair value is not a
  reliable dip to buy — it may be a crowd still leaving.
- **It is published, so it is in the ledger.** *"net buying last year, +4"* is a line a
  player can read, not an invisible hand.

**One thing to watch, honestly.** The clamp is a fixed fraction, and flow's cost grows
with match length like every other edge: at 25 years it takes the leading strategy from
27.0% to 45.5%. If that matters, the clamp should scale down in long matches — the same
ladder the game already applies to price swings and to earnings growth, used a third
time. **Not yet measured**, and listed as such in [§13](#13-size-and-risk-honestly).

**The ledger.** Because the price is an identity, the year's change decomposes
exactly, and the decomposition is the mode's signature screen:

```
WHY THE PRICE MOVED          year 7      112 -> 128      +16

  earnings                   +21      profit up 18% on revenue up 14%
  market sentiment            +3      the market rose 6% last year
  industry standing           -2      energy -4% this year
  this year's event          -12      [event headline placeholder]
  last year's event, faded    +6      half of year 6's -12
  net buying last year        +0      the traders were flat
  ----------------------------------
  total                      +16
```

**This must balance, and that is a test**, not a hope: for every company in every
year of a many-seeded run, the terms sum to the realised delta. Any future change that
breaks the identity fails it loudly. The ledger is also what makes P1 real rather than
rhetorical — the player is not told *that* prices mean something, they are shown the
arithmetic.

One presentational decision this forces: the board's **Yearly Change** column.
[game-rules.md §5](game-rules.md) pins that the base game's figure deliberately
*excludes* the event delta. In StalkleHeads the whole point is that it is complete, so
**the column shows the total move and the ledger breaks it down.** That is a
divergence between modes, it is deliberate, and it is question 7 in
[§14](#14-open-questions-for-the-owner).

### 3.6 Splits and bankruptcy need no new rules

This is the strongest evidence the model is coherent, and it was a pleasant surprise
rather than a design goal.

**A split is already exactly what an earnings model predicts.** The base game halves
the price (rounding up) and doubles every holder's shares. In this model a split also
doubles `shares_outstanding`, which halves earnings per share, which halves fair
value. Halve `event_carry` too and the identity still holds:

```
before:  price 320   eps 25.60   multiple 12.5   fair 320
split:   shares x2 -> eps 12.80   multiple 12.5   fair 160   price 160
```

The split is value-neutral, as a real one is, and no clause anywhere needs to know
about it. `event_carry` and `flow` halve with it for the same reason.

**The threshold moves to above 300**, and the rounding stays **up**. The base game's
150 was tuned for a market whose expected drift is slightly negative; here earnings
mostly grow, and at 150 the first draft measured 5.7 splits per ten-year match against
the base game's 2.0 — splitting became routine rather than an event. At 300 it measures
1.8. [D22](decisions.md)'s round-up rule is untouched; only the threshold is this
mode's own.

**Bankruptcy needs no new rule either.** The price falls to zero when fair value plus
event carry does, which happens when earnings go to nothing — the `DISTRESS` regime —
or when a large negative event lands on an already-weak company. Both are forecastable
from published information, which is right: a company dying should be something a
player saw coming and either fled or gambled on. The threshold stays **at or below 0**
and the consequences are unchanged: every holder loses every share, no compensation,
the row stays on the board overlaid with BANKRUPT!!!.

**One divergence, and it needs stating plainly.** The base pipeline has *two*
bankruptcy passes, because it applies two independent deltas — the base move, then the
event — and either can kill a stalk
([game-rules.md §4.1](game-rules.md), steps 3 and 5). StalkleHeads sets the price once,
from an identity that already contains the event, so **it has one bankruptcy pass.**
The two orderings that [year_resolver.gd](../src/sim/year_resolver.gd) documents as
must-preserve are untouched by this: splits are still checked exactly once and still
after the event, and dividends are still paid after splits.

### 3.7 Money is int, ratios are float

**The first draft got this wrong.** It stored every ratio as a fixed-point integer —
the multiple in tenths, earnings per share in cents — to honour [D4](decisions.md).
The owner's note asked whether that was necessary, and it is not. The scheme is
replaced.

> **Money stays `int`. Ratios are `float`. A float becomes money at exactly two places
> per company per year — its price and its dividend per share — and each conversion is
> a documented truncation.**

| Quantity | Type | Example | Shown as |
|---|---|---|---|
| Cash, price, net worth, dividend, loan balance | `int` | `128` | `$128` |
| Revenue, expenses, profit | `int` | `86_142` | `$86,142` |
| Earnings per share | `float` | `9.0` | `$9.00` |
| Valuation multiple | `float` | `12.5` | `12.5x` |
| Margin, growth, industry performance, sentiment | `float` | `-8.4` | `-8%` |
| P/E, earnings yield | **not stored** — computed where displayed | | `11.8`, `7.0%` |

The two conversions are the last line of the price identity,
`price = int(fair_value + event_carry + flow)`, and the dividend,
`dividend_per_share = int(earnings_per_share * payout_ratio)` (§3.10a). Everything
downstream of them — net worth, a purchase, a dividend paid — is integer money, so
[D4](decisions.md) holds exactly where it was written to hold. The dividend truncating
to a whole number per share matches the base game, whose dividends are whole numbers
too; it also means a company earning under about 3 a share at a 35 policy pays nothing,
which is right for the small speculative companies that sit there.

**Why this is safe, and it is not a new risk.** The first draft's caution about floats
and determinism was overstated, because **the shipped game already does this**:

- [`loan_rules.gd:40`](../src/sim/loan_rules.gd) computes the annuity factor with
  `pow(1.0 + ANNUAL_RATE, years)` — a float, and a transcendental function at that —
  and truncates the resulting minimum payment to `int`. That ±1 truncation drift is a
  *documented, tested* behaviour ([game-rules.md §9.2](game-rules.md)).
- [`random_range_price_model.gd:60`](../src/sim/random_range_price_model.gd) multiplies
  a price delta by a float softening multiplier and truncates with `int()`.

So the pattern — float arithmetic, one documented truncation at the money boundary — is
established practice in this codebase and is already covered by the determinism tests
that pass today. StalkleHeads follows it rather than inventing something stricter.

**The one real condition**, worth writing down because it is invisible until it is not:
float results are identical across machines for the same build and the same sequence of
operations, which is what a host-authoritative design needs. What is *not* guaranteed
identical across platforms is the standard library's implementation of transcendental
functions. The base game's `pow` call is in the loan path, where both peers get the
figure from the host anyway. **StalkleHeads should use only `+ - * /` and explicit
rounding in its price path** — every formula in §3 already does — and that is a rule
cheap enough to check with a scan, in the spirit of
[CLAUDE.md](../CLAUDE.md)'s "if you add a rule here that you actually care about, add a
check for it".

Currency formatting goes through the existing
[`Palette.format_money`](../src/ui/palette.gd), and these ratios want siblings beside
it — `format_multiple`, `format_ratio`, `format_percent` — because
[CLAUDE.md](../CLAUDE.md) requires one shared formatting helper rather than ad-hoc
labels.

### 3.8 What BERRY BONDS becomes

**Mechanically: nothing changes.** Price fixed at 100, pays 3 a share in every year,
cannot move, cannot split, cannot go bankrupt, carries no events, and keeps its
investors to itself ([D103](decisions.md)). `is_price_static` does all of it, exactly
as now.

**What changes is what it is for.** In the base game it is the safe haven, and the
probe shows it is also the dominant strategy (§2.1). In StalkleHeads it keeps the first
job, loses the second, and gains a third: **it is the yardstick.** Its 3% yield is the
risk-free rate that justifies the 12.5× base multiple (§3.4), so it is the number every
other company is implicitly measured against, and the Company tab says so in as many
words.

Its "earnings report" is therefore not an earnings report. It is a **coupon
statement**: price 100, coupon 3, yield 3.00%, no issuer risk. One short panel that
explains what it is and why it is the benchmark. That is a far better answer to "what
is BERRY BONDS in a world with earnings reports?" than inventing accounts for it.

A nice consequence worth noting: the bond going from winning 38% of matches to 12% is
not a nerf to the bond. The bond is identical. The *companies* got better, because
their prices now follow earnings that mostly grow instead of a stat block whose
expected move is negative.

### 3.9 What My Mutuals and Me Inc. becomes

**It becomes a genuine index of the other eight companies**, which is what
[architecture.md §4](architecture.md) and [D7](decisions.md) gave the price model the
whole market for in the first place.

It has no earnings report. It has a **holdings sheet** — the eight constituents, their
weights, and what each contributed to the index this year. Its price is the index
level:

```
for each surviving constituent c:
    move_pct(c) = (price_after_event(c) - price_before(c)) * 100 / price_before(c)
# a constituent that went bankrupt this year contributes -100 in that year only
index_move_pct = sum(move_pct) / count
index_price     = index_price * (100 + index_move_pct) / 100
```

Computed from **pre-split** prices, so a constituent splitting does not halve the
index — which is the divisor problem every real index has, solved here by measuring
moves rather than levels. The index itself then splits above 300 and doubles its own
holders' shares like anything else.

Three consequences:

- **It is the market's price, so it is the market's P/E.** Mutuals' own multiple is
  the average of its constituents', and that single number is what tells a player
  whether the whole board is expensive. It makes Mutuals the most *informative* row on
  the board even for somebody who never buys it.
- **It cannot go bankrupt unless every constituent does**, which is correct and is
  worth a test.
- **Its dividend** should be the average of its constituents' — otherwise the index
  pays like a single company while behaving like eight. The authored `2`/`3` figures
  stop making sense. This is question 4 in [§14](#14-open-questions-for-the-owner).

### 3.10 Order flow — in, clamped, and published

**Recommended, at a 5% clamp.** The first draft specified this term and advised against
shipping it; §2.4 is the full account of that reversal. The mechanics are in §3.5 with
the rest of the identity. What matters here is the design around it:

`net_shares_traded` counts **both** NPC and player buying and selling in the year just
finished, treated identically — a player's order is not special, it is one voice among
the desk's twenty-four or more. It appears as its own line in the ledger (§3.5), and
the Company tab publishes the raw share figure, so it is information rather than a
hidden hand.

**Three things the clamp has to survive, and how:**

| Risk | Containment |
|---|---|
| **Self-pumping.** Net worth reads the posted price, so inflating something you hold flatters your score | Bounded at 5% of fair value, decaying by 30% a year, and diluted by a desk far larger than any one player. Measured by the probe at no cost to P4 at the default match length; **on the real pipeline (S4) flow costs 5.2 points** without the squeeze, so it is not free ([D167](decisions.md)) |
| **Amplifying the readable signal** (§2.4's real finding) | The clamp. At 18% the leading strategy hits 61.3%; at 5% it is 23.2%, and 22.2% on the approved roster |
| **Compounding over long matches** | **Unsolved.** At 25 years flow costs 18 points of P4. The proposed remedy is to scale the clamp with match length, as the game already scales two other things. Not measured |

### 3.10a Dividends come from earnings, by each company's policy

A consequence of dropping base-game anchoring (§3.2.2), and it is listed here because
it is a rule change rather than a parameter. **Decided by the owner on 2026-11-21**,
with one addition from them: companies should have their own dividend *character*.

The base game pays a fixed `bull_dividend` or `bear_dividend` per share, chosen by the
year's mood. In StalkleHeads a company has earnings, so it pays out of them — and how
much it pays out is a choice the company makes, as it is in real life:

```
payout_ratio       = payout_policy_percent / 100 * regime_payout_scale
dividend_per_share = int(earnings_per_share * payout_ratio)
```

**`payout_policy_percent` is a new field on each company profile** (§3.2.4): the share
of its earnings it pays out in a normal year. The regime then scales it:

| Regime | Scale | Why |
|---|---|---|
| `GROWTH` | ×0.30 | Even a payer holds cash back when it has somewhere to put it |
| `STEADY` | ×1.00 | The normal year: the company pays its policy |
| `SLOWING` | ×0.85 | Still paying, growth no longer the story |
| `DECLINE` | ×0.55 | Paying what it can |
| `DISTRESS` | ×0.00 | Nothing to pay from |

A company with the neutral policy of 35 pays exactly what the previous draft's single
table paid in every regime, so this is a strict extension of it rather than a new model.

**Real companies do work like this.** A dividend is a decision by the company's board,
not a fixed share of profit, and different kinds of company settle on very different
policies:

- **Utilities, pension funds and property companies pay out most of what they earn.**
  Their earnings are steady and they have little to reinvest in, so their shareholders
  hold them for the income. Springfield Nuclear Power, Teamsters Pension Fund and
  Landlords United are written that way (60, 80 and 70).
- **Young and fast-growing companies pay nothing.** Every dollar goes back into the
  business, and shareholders are buying the growth. Meowly is written that way (0).
- **Some companies simply never pay**, whatever they earn. strYker!!! keeps its
  base-game character as the stalk that pays nothing (0).

This answers the cost the first draft flagged: Teamsters is the big payer again, and
strYker!!! pays nothing, because those are now *policies* the profile states rather than
outcomes the regime happens to produce.

**The policy has to cost something, or high payers win.** In this model a dividend
paid does not lower the price — fair value is earnings times a multiple, and nothing
leaves the company. So with no other change, a company paying 80% of its earnings would
be the same stock as one paying 10%, plus free cash. The `INCOME` strategy would
dominate and the field would be an arbitrage (proposed decision A2).

Real companies face the trade-off that fixes it: **money paid out is money not
reinvested, so a company that pays more grows more slowly.** The design writes that in
directly, on revenue growth only:

```
retention_factor = 1 + (35 - payout_policy_percent) / 100
revenue_growth   = regime_growth * retention_factor        # positive growth only
```

| Policy | Factor | Effect on a `GROWTH` year of +25% |
|---|---|---|
| 0 (Meowly, strYker!!!) | ×1.35 | +33.8% |
| 35 (neutral) | ×1.00 | +25% |
| 80 (Teamsters) | ×0.55 | +13.8% |

It applies only when growth is positive, so a high payer in `DECLINE` does not shrink
more slowly for having paid out. **Measured in §2.6**: `INCOME` wins 6.2% of ten-year
matches, so the policy is not an arbitrage — but with the trade-off at this slope,
income is a niche rather than a route, and its median barely beats the bond's. The
slope is the tuning lever; halving it is the first thing to try in S9.

**Why this is better than inheriting the authored figures**, beyond coherence:

1. **It makes income a real strategy with a real trade-off.** A high-payout company
   yielding more than BERRY BONDS' 3% wins only if its earnings hold, and grows slowly
   while it pays. That is a genuine decision, and it is the one the `INCOME` trader
   personifies.
2. **It removes the second place the mood mattered.** With the mood derived (§3.1) and
   dividends from earnings, nothing in the model needs to know whether the year was
   labelled bull or bear. The label becomes purely a report.
3. **It makes the regime visible in the cash.** A company cutting its dividend has
   changed regime, and a player who notices the cash stop arriving has learned
   something before they opened any tab. With policies, a cut means more: a company
   that always pays and suddenly does not is telling you something.

**Considered and left out: dividend smoothing.** Real boards hate cutting a dividend
and often hold it flat through a bad year, so a cut is rarer and louder than profit
alone would make it. That would be believable, but it is a second hidden rule between
earnings and cash. It is a candidate for after first play, not part of this design.

---

## 4. The year, step by step

The base game's ten-step sequence is in [game-rules.md §4.1](game-rules.md) and is
traced from the original's real call chain. StalkleHeads replaces the price-setting
front half and leaves the back half alone.

| # | Step | Base game | StalkleHeads |
|---|---|---|---|
| 1 | Industry year | — | **new**: per industry, persistent roll leaning on last year's sentiment (§3.4) |
| 2 | Earnings season | — | **new**: per company, regime advances, revenue and margin move, earnings per share recomputed (§3.3) |
| 3 | Valuation | — | **new**: multiple per company from sentiment, standing and regime; then fair value (§3.4) |
| 4 | Draw the event | step 4, after prices moved | **moved earlier**: drawn now, so it is an input to the price rather than a correction to it |
| 5 | Set prices | steps 1–3: mood roll, base move, bankruptcy pass | **replaced**: the identity, once, including last year's flow (§3.5) |
| 6 | Recompute the index | — | **new**: Mutuals from the constituents' pre-split moves (§3.9) |
| 7 | **Report the mood** | step 1, *before* prices, as a roll | **moved to the end and derived**: bull or bear is what the index did. Next year's sentiment is set here (§3.1) |
| 8 | Bankruptcy | two passes, steps 3 and 5 | **one pass** — one price-setting step needs one (§3.6) |
| 9 | Splits | step 6, above 150, rounding up, exactly once, after the event | above **300**; `shares_outstanding`, `event_carry` and `flow` all halve with it (§3.6) |
| 10 | Dividends | step 7, on post-split counts, fixed figure by mood | **from a payout ratio of earnings** (§3.10a) |
| 11 | Loans | step 8 | **unchanged** |
| 12 | Net worth and standings | step 9 | **unchanged** |
| 13 | NPC traders act | — | **new**: after prices settle, on the published state. Their flow becomes next year's `flow` term (§5) |
| 14 | News selection | — | **new**: describe what happened, flag what is building (§8) |
| 15 | Game end | step 10 | **unchanged** |

**Four things about this table are load-bearing.**

**Steps 11, 12 and 15 are untouched.** Loans, net worth, standings, tie-breaking and
the game-end condition are the base game's, unmodified. Step 9 keeps both orderings
that [year_resolver.gd](../src/sim/year_resolver.gd) marks must-preserve — splits are
still checked exactly once and still after the event, and dividends are still paid after
splits — with only the threshold changed.

**The mood has moved from the front of the year to the back**, and from a cause to a
report. This is the largest structural change from the first draft and it comes from
the owner's note. It is only possible because nothing upstream needs it any more: the
multiple reads last year's `sentiment` (§3.4) and dividends read earnings (§3.10a). If
anything in a future change wants this year's mood *before* prices, that circularity is
back and the design is broken — worth a comment in the code at step 7.

**The event moves to before prices are set.** It has to: the identity contains
`event_carry`, so the event must be known before the price is computed. This is a
genuine divergence from the traced order and it is justified rather than quiet — in the
base model the event is a second, independent delta applied after the first, which is
why two bankruptcy passes exist; here there is one delta and it includes the event.

**Step 13 is after everything.** NPC traders act on the published, settled state, so
what a player sees of their positioning is a true record of decisions made on
information the player also has. It also means their activity cannot influence the year
it happened in, only the next — which is both the lag that makes their behaviour
*readable* and the reason the `flow` term persists rather than reverting (§3.5).

**An event whose target is already bankrupt.** [D24](decisions.md) skips it and leaves
it in the bag, and [game-rules.md §5](game-rules.md) carries a forward note saying this
mode may want to choose differently, with the decision deliberately left inside
`EventPool` so it can. The recommendation here: **in StalkleHeads an event may fire at
a bankrupt target if it carries an industry or market effect, and is skipped if it
carries only a company price delta.** The forward note anticipated exactly this and the
seam is already in the right place.

---

## 5. The NPC traders

### 5.1 What they are

**A desk of around twenty-four simulated traders** who are **not in the rankings**,
cannot win, and exist to be watched. The first draft said eight to ten; the owner's
note asks for more, and more is right for two reasons beyond liveliness:

1. **It dilutes the self-pumping exploit.** A player who is one voice in twenty-four
   moves the `flow` term far less than one voice in eight, which is a large part of why
   the clamp in §3.10 holds. The owner's instinct and the exploit's containment are the
   same instinct.
2. **Three traders per strategy means a strategy can disagree with itself.** Give each
   trader an individual appetite (§5.4) and the value cohort does not move as one
   block, so a player cannot read off exactly what the cohort will buy. That is what
   stops "mirror the biggest cohort" being mechanical.

**The computational cost is nothing.** One decision per trader per year is
twenty-four decisions a year, against a market of fifteen rows — a few hundred
operations in a step that already walks every company and every player. The real cost
is **state size**, not time, and [§9.2](#92-state-size-estimated) budgets it: the design
scales comfortably to about fifty traders, and the limit is what has to cross the wire
on every trade.

Each trader is one authored resource:

| Field | Type | Meaning |
|---|---|---|
| `id` | `StringName` | Stable key |
| `display_name` | `String` | **The owner's to write.** Their example of the register is *"C. Hotdog"* |
| `strategy` | enum | Which rule it trades by, below |
| `starting_cash` | `int` | Its endowment |
| `conviction` | `int` 0–100 | What fraction of its cash it commits to a decision |

Their strategies are **published in the game**, in a help panel, because a trader
whose logic is secret is just more randomness wearing a hat:

| Strategy | The rule, as the player is told it |
|---|---|
| `VALUE` | Buys the lowest P/E, sells the highest |
| `MOMENTUM` | Buys whatever rose most last year |
| `CONTRARIAN` | Buys whatever fell most last year |
| `INCOME` | Buys the highest dividend yield |
| `INDEXER` | Buys My Mutuals and Me Inc., and nothing else, ever |
| `PANIC` | Sells everything in a bear year, buys back in a bull one |
| `GROWTH` | Buys whatever grew its earnings fastest |
| `SHORT` | Bets against the most expensive company on the board, by P/E ([D169](decisions.md)) |

### 5.2 What they are for

Each strategy is one of the readings a player might make, personified. That is the
design: **the NPC desk is the analysis, rendered as a room full of characters with
opinions.**

**And it is measurably a route to winning.** A `FOLLOW` strategy — copy whichever
trader is doing best, understand nothing — wins **12.8% of ten-year matches** on the
approved roster (§2.6), against 10.0% when the desk's trading does not move prices and
the do-nothing bond's 2.2%. Its median is low and its mean is the highest of any
strategy: it is the high-variance route. That
is the brief's "reading other people" paying off, measured, without the player ever
opening a financial statement.

- A player who will not read a financial statement can see that the value traders
  have piled into one company and the panic trader has fled another, and trade on
  that. Tier 1 in [§6.1](#61-four-tiers-of-engagement).
- A player who *will* read one gets something better: they can see when the crowd is
  wrong. The momentum trader buying a company whose margin is collapsing is an
  opportunity, and spotting it is real analysis of real published information.
- Their fortunes over the match are a readable commentary on the market. If the
  indexer is winning, the board is broadly rising; if the panic trader is winning, it
  is a bloodbath.

### 5.3 Short interest and honest foreshadowing

> **Superseded in part, 2026-11-27 (decisions.md D213, D214).** The squeeze below is
> S4's: a +25 special event. It is now a **meme stock**: a jump of 5% of the price
> for every point of short interest (at most 150%), no loss in its year, held while
> the shorts cover over 1-3 years, and taken off whole the year after short interest
> reaches 0. The trigger and its odds are unchanged. The percent is shown with
> FLAGGED or SQUEEZED, and squeeze and crash whispers come from a Questionable
> source. The text below is kept as the reasoning for the trigger; the size and
> the balance numbers in it are S4's.

The brief asks for industry news that foreshadows events — specifically news of a
large short position making a squeeze likelier on a failing company. The honest
implementation, which this design commits to:

1. The `SHORT` trader holds a notional short position. **That position is the short
   interest**, a real state variable, published on the Company tab as a number.
2. When short interest on a company exceeds a threshold, a news item says so. It is a
   true statement about state, not a tease.
3. **The event pool's weighting reads that flag.** While it is set, the squeeze event
   for that company is eligible and weighted up by a documented amount.

So the news genuinely predicts, by a stated amount, and a test can assert that the
squeeze's probability rises when the flag is set and not otherwise. That is the
difference between foreshadowing and decoration, and it costs nothing extra to do it
the honest way because the state variable has to exist anyway.

**As built (S4).** The threshold is 10% of shares outstanding and the documented
amount is 25%: in a year with a company flagged, a roll drawn every year makes the
squeeze the year's event, in place of the bag draw, one time in four; with nothing
flagged it never happens. The squeeze is +25 on the most shorted flagged company
([D165](decisions.md)).

**What the squeeze foreshadows is an overvalued company, not a failing one.** The
SHORT traders bet against the highest P/E ([D169](decisions.md)), so the squeeze lands
on the company the market has priced highest against its earnings. S4 first built
SHORT against the slowest grower, the closer reading of "failing"; that put every
squeeze on what `LOWPE` holds and broke P4 at 41.8%. With the highest P/E, P4 holds
at the numbers above (`LOWPE` 27.7%). The squeeze ships at these numbers
([D170](decisions.md)).

### 5.4 Determinism

The brief asks for confirmation that the shape works. It does, and these are the
conditions:

- The desk lives in `src/sim/`, is `RefCounted`, touches no node and no autoload, and
  takes the injected `RandomNumberGenerator` like everything else — never global
  `randi()`. [D5](decisions.md).
- **Traders act in sorted id order.** Not in dictionary order, not in load order.
  This is the same discipline [D30](decisions.md) applies to content loading, and for
  the same reason: a different order is a different sequence of draws, which is a
  different match.
- Each trader draws from the RNG a **fixed number of times per year regardless of
  what it decides.** A trader that only rolls when it has cash shifts every subsequent
  draw in the match, which makes the stream depend on history in a way no test will
  catch until it is a bug in play. **Draw first, then decide whether to use it** — the
  per-trader appetite draw (§5.1) happens before the decision for exactly this reason,
  not only to vary the behaviour.
- Their decisions are a pure function of `(GameState, NpcTraderState, rng)`. No wall
  clock, no node lookups, nothing from the UI.
- Their positions travel in the snapshot ([§9](#9-reaching-the-client)) rather than
  being recomputed by each client. [D105](decisions.md) is the precedent and the
  reasoning transfers unchanged: a client that is promoted to host must be able to
  continue from the copy it already holds, and a derived copy is not a match.

The existing test `test_the_same_seed_reproduces_a_whole_match` in
`tests/unit/test_year_resolver.gd` is the pattern; it needs a StalkleHeads sibling that
asserts the NPC positions are identical too.

---

## 6. How much a player has to hold in their head

The brief is right that this is where the mode most plausibly dies. Four tabs of
financials, once a year, with a ready-up gate and friends waiting, is a recipe for one
person reading and five people bored.

The three answers below are the design's actual defence, and the third is the
important one.

### 6.1 Four tiers of engagement

Measured on the approved roster (§2.6):

| Tier | What they do | Effort | Measured, ten-year matches |
|---|---|---|---|
| **0 — ignores everything** | Watches the price and the yearly change, buys what looks cheap or funny | None | `RANDOM`: **14.2%** of matches, median 13,179. Competitive |
| **1 — follows a hotdog** | Looks at which traders are doing well and copies one | One glance at the Market tab | `FOLLOW`: **12.8%**, median 9,871 but a mean of 26,890 — a high-variance route, which suits a party game |
| **2 — reads one column** | Compares a company's P/E to its industry's average, printed next to each other on the board | One comparison, no arithmetic | `LOWPE`: **22.2%**, median 16,501 — 1.25× tier 0. **The design target** |
| **2b — reads the board's movement** | Buys whatever rose most last year | One glance | `MOMENTUM`: **15.0%**, median 18,864 — the highest median of any strategy |
| **3 — reads the trend** | Opens the Company tab, looks at five years of earnings, notices margin falling while revenue still rises, counts the years in regime | A minute a year | `TREND`: **22.0%**, median 18,721 |

**The spread is the point, and it is better than the first draft's.** Four different
readings — cheapness, crowd, momentum and earnings trend — all beat doing nothing, none
takes more than a quarter of matches, and *they disagree with each other about what to
buy*. A table of friends can hold four different convictions and every one of them be
defensible. The first draft had a single reading returning 1.9× and taking 40% of
matches, which is a correct answer rather than an argument.

**Tier 2 is still where the mode wants most players to live**, because it is the
cheapest: two adjacent numbers on the main board, no tab switching, no arithmetic, no
memorised table.

**Tier 3 draws level with tier 2 at ten years and does not pass it**: on the approved
roster `TREND` and `LOWPE` win 22.0% and 22.2%, with `TREND` ahead on median (18,721
against 16,501). On the thirteen-company draft tier 3 trailed at 14.2%. Level is the
right place for it — the deep read should pay for the effort without being required.
Over a longer horizon earnings persistence has more time to tell, and a party game
played over ten years should not require homework to compete. It does not.

### 6.2 Nothing in the analysis is time-critical

A structural guarantee, and it is the reason the pace problem is smaller than it looks:

> **Every figure on every analysis tab is last year's published data, and none of it
> changes while anybody is trading.**

So a slow reader is not missing anything, and a fast trader gains nothing by being
fast. A player can read the Company tab while the others trade, ready up, and have
lost nothing. The only thing that moves during a trading window is other players'
positions, and those are on the Exchange tab where they are already looking.

This is the opposite of the trade-off [D101](decisions.md) accepted for the news panel,
where reading carefully is a small disadvantage because the others are still trading.
Worth being explicit about, because it is the single strongest argument that four tabs
are affordable.

### 6.3 The year digest, which is the real answer

**The whole year's fundamentals, in one panel, at the year turn.** The news panel from
[D101](decisions.md) already exists, already appears every year, already blocks the
board until it is closed, and already has a Don't-show-again tick box and a settings
switch to bring it back ([D102](decisions.md)). In StalkleHeads it carries more:

```
  THE YEAR IN REVIEW                                     year 7
  the market   +6%   -> BULL!!!       P/E 13.1     carried into year 8 as sentiment

  energy     -4%  |  tech      +14%  |  transport  +11%
  financial  +2%  |  consumer   -1%  |  food        +5%

  biggest earnings surprise    [company]   profit +31%
  biggest disappointment       [company]   margin 12% -> 8%
  dividend cut                 [company]   3 -> 0, now in distress
  the desk piled into          [company]   value and growth both buying

  [this year's event headline placeholder]
  [whisper placeholder]
                                              [ ] Don't show again
```

**The mood line reads in the order it was decided.** The market's move comes first and
the label follows from it (§3.1), so a player sees *why* it was a bull year rather than
being told one happened. The base game's digest leads with the label because there the
label is a cause; here it is a consequence, and the layout says so.

Two lines are new since the first draft, both because of the owner's notes. The
**dividend cut** line exists because dividends now come from earnings (§3.10a), so a
cut is a regime change made visible in cash. The **desk** line exists because reading
the crowd is now a route to winning in its own right (§5.2), and this is the cheapest
place to show it. The industry rows are the decided six (§3.2.3).

Twelve lines. A player who reads only this panel and nothing else is operating at tier
2 or better, because it hands them the industry moves and the earnings outliers directly.
**The tabs are the drill-down for people who want it, not the way the mode is played.**

That reframes the UI question considerably: the four tabs are not four things a player
must read every year. They are four things a player *can* read, with the digest as the
thing they actually do read.

---

## 7. The interface

### 7.1 The grid, and what the tabs cost

The game is drawn on a fixed **640×360** picture, enlarged to the window by a whole
number ([D40](decisions.md), [D96](decisions.md)). At font size 12 the cell is 6×12
pixels, so the screen is a **106 × 30 character grid** and every layout question is
"how many characters wide?". See [ui-reference.md](ui-reference.md).

> **For a reader new to Godot:** nothing here is positioned in pixels by hand. The
> screens are built from container nodes — `VBoxContainer` stacks its children
> vertically, `HBoxContainer` horizontally, `GridContainer` in a grid — and each child
> says how it wants to be sized. A column five characters wide is written as a
> `custom_minimum_size` of 30, because 5 × 6 = 30. [CLAUDE.md](../CLAUDE.md) forbids
> hardcoded pixel positions for exactly this reason: containers survive a layout
> change and hand-placed pixels do not.

The row budget for all four tabs:

| Rows | What |
|---|---|
| 1 | Tab strip |
| 3 | Top bar: year, mood, the year's event, the yeehaw corner |
| 22 | Tab content |
| 3 | Bottom bar: loan nag, messages, errors, READY |
| **30** | |

The tab strip costs **one row** against the current board, which has 23 rows of
content. The existing board loses one row of its stalk list and nothing else.

### 7.2 Tab 1 — Stalk Exchange

The main view. The first draft built it around "all stalks visible at once"; the owner's
note corrects that to *all stalks on the same page*, with groups that collapse and a
list that scrolls. That is a better requirement, and with twenty rows under the decided
six-industry roster (§3.2.3) it is also the only one that works.

```
|<--------------------------- board, 78 characters -------------------------->| |<- 24 ->|
 EXCHANGE | MARKET | INDUSTRIES | COMPANY
 Year 7/10   BULL!!!  +6%   [event headline placeholder]        Can I Get a Yeehaw?

 SYM    NAME                PRICE    CHG     EPS    P/E    DIV  HELD   QTY        RANKINGS
                                                                                  Ann   24,180 *
 - ENERGY                     -4% this yr          11.8                           Bob   19,044 *
   SPNG  Springfield Nuc...    118    +12    9.40   12.6      5    20  [  ] B  S  Cal   17,765 o
   PGEN  PG&Enron               84    -16    7.11   11.8      3    40  [  ] B  S  Dee   11,002 o
   STKR  strYker!!!             61    -22    5.80   10.5      0     0  [  ] B
                                                                                  THE DESK
 + TECHNOLOGY                 +14% this yr          16.1                          value     +61%
                                                                                  growth    +44%
 - TRANSPORTATION             +11% this yr          14.2                          momentum  +23%
   MONO  N. Haverbrook M...    141    +29   10.20   13.8      0    15  [  ] B  S  indexer   +12%
   TRNA  Transportation ...     96     +9    7.40   13.0      2     0  [  ] B     income     +9%
   TRNB  Transportation ...     72     +6    5.55   13.0      1     0  [  ] B     contrarian -4%
 + FINANCIAL SERVICES          +2% this yr          13.0                          short     -18%
                                                                                  panic     -31%
 + CONSUMER GOODS              -1% this yr          12.4
                                                                                  SHORT INTEREST
 + FOOD                        +5% this yr          13.6                          STKR  240 shares

 - INDEX AND BOND
   MYMM  My Mutuals and ...    107     +7      --   13.1      2     0  [  ] B     index of 18
   BERY  BERRY BONDS FRO...    100     --      --     --      3    30  [  ] B  S  yield 3.0%
```

Column widths, in characters, for whoever builds it:

| Column | Width | Notes |
|---|---|---|
| Group marker | 2 | `-` open, `+` collapsed. The whole header row is the click target |
| SYM | 6 | **The ticker.** See below |
| NAME | 18 | Indented 1 under its group. Clipped with `...`; scrolls on hover (`MarqueeLabel`, as now); click opens the Company tab |
| PRICE | 6 | Right-aligned |
| CHG | 6 | Right-aligned, signed, green or red from `Palette.for_change`, with the existing arrow |
| EPS | 7 | Right-aligned, two decimals |
| P/E | 6 | Right-aligned, one decimal. Blank for the bond and the index |
| DIV | 6 | Dividend per share, a whole number as in the base game — now from earnings and the company's policy (§3.10a), so it is one figure rather than a bull/bear pair |
| HELD | 5 | Right-aligned. **Folded in from the separate holdings board** |
| QTY + B + S | 13 | One quantity field, two buttons. `S` is hidden when nothing is held |
| Rankings strip | 24 | Name, net worth, ready dot — the existing `RankingRow` |

**Six things about this layout are design decisions, not sketching.**

**Tickers, finally.** `StalkDefinition.ticker` **already exists, is already populated
for all ten shipped stalks, and nothing displays it.** [ui-reference.md](ui-reference.md)
says why it is there: *"for a future compact view, where a dense board of symbols would
suit the terminal look."* This is that view. The owner's note asks for exactly this and
the field has been waiting for it — `BERY`, `STKR`, `PGEN` are already written. New
companies need one each.

The base game shows full names because *"the names are the funniest thing in the game,
so they are not abbreviated away"*. That reasoning still holds, which is why the name
column survives at 18 characters beside the symbol, the name still scrolls on hover, and
the Company tab shows it in full. The symbol is an addition, not a replacement.

**Collapsible industry groups.** A `+`/`-` marker on each header row, which is the whole
click target. Collapsed state is per-player, per-session, and is **presentation only** —
it never touches `GameState`, so it cannot desync and does not travel. A player who only
cares about tech collapses the other five and has a four-row board.

**Sortable columns.** Clicking a column header sorts by it; clicking again reverses.
Two rules keep it from fighting the grouping: sorting happens **within** a group, never
across groups, so the industry structure that makes the P/E comparison work (§7.2, next
point) is never destroyed; and sort state is presentation only, like collapse. A
"flatten groups" toggle for players who would rather see one ranked list is a cheap
addition and is question 12 in [§14](#14-open-questions-for-the-owner).

**The industry header row is how the P/E comparison becomes free.** It carries the
industry's performance for the year and its average P/E, immediately above its members.
A player comparing 10.5 to 11.8 does tier-2 analysis by moving their eyes two lines,
with no arithmetic and no tab switch. That is the cheapest possible way to make the
central number mean something, and it is why grouping beats a flat sorted list as the
default.

**No verdict column.** No "cheap"/"expensive" marker, no arrow saying which way the
model thinks the price will go. The comparison *is* the gameplay and labelling it would
hand the player the answer. A marker is specified in question 9 of
[§14](#14-open-questions-for-the-owner) as a fallback if play shows tier 2 is too hard to
reach, not as a default.

**Holdings fold into the board as a HELD column**, so buying and selling one company
happens in one row and the base game's separate "Your Stalks" panel is not needed. This
is a change the base game might also want, and it is deliberately not proposed for it —
question 1 in [§14](#14-open-questions-for-the-owner).

**The right-hand strip carries three things now**, not two: the rankings (knowing you
are losing is how the base game generates its best moments), **the desk by strategy**
rather than by individual trader — with twenty-four traders, "value is up 61%" is the
readable summary and individual names belong on the Company tab — and **short interest**,
which is the one state variable the squeeze mechanic (§5.3) needs a player to have seen.

### 7.3 Tab 2 — Market Analysis

```
 EXCHANGE | MARKET | INDUSTRIES | COMPANY

 THE MARKET                                        WHISPERS FROM THE AVENUE
  index level        107   +7      +7%              [whisper placeholder]
  market P/E        13.1                            [whisper placeholder]
  mood            BULL!!!   7 of last 10 bull       [whisper placeholder]
  breadth            5/8   rose this year
  risk-free         3.0%   BERRY BONDS
                                                   THIS YEAR'S NEWS
 INDEX, BY YEAR                                     [market headline placeholder]
  140 |                               ▄▄
      |                          ▄▄   ██            [event headline placeholder]
  120 |                ▄▄   ▄▄   ██   ██
      |      ▄▄   ▄▄   ██   ██   ██   ██           MOOD, BY YEAR
  100 |▄▄   ██   ██   ██   ██   ██   ██            1 2 3 4 5 6 7 8 9 10
      |██   ██   ██   ██   ██   ██   ██            B b B B b B B . . .
   80 +--------------------------------------
       1    2    3    4    5    6    7
```

### 7.4 Tab 3 — Industries

```
 EXCHANGE | MARKET | INDUSTRIES | COMPANY

 INDUSTRY        THIS YR   3-YR   STANDING   AVG P/E   REVENUE SHARE   COMPANIES
  energy             -4%    -11%      -2.4      11.8        38%   ▄▄▄▄▄▄▄▄     3
  transport         +11%    +19%      +6.6      14.2        44%   ▄▄▄▄▄▄▄▄▄    3
  consumer           +2%     +6%      +1.2      13.0        18%   ▄▄▄▄         2

 BY YEAR                                      WITHIN THE INDUSTRY: TRANSPORT
  +20 |                    ██                  COMPANY            SHARE    CHG
      |          ▄▄   ██   ██                   N. Haverbrook MON.   41%    +4%
    0 +----▄▄----██---██---██---------          Teamsters Pension    34%    -1%
      |    ██   ██                              Mafia HUD Scam       25%    -3%
  -20 |
        4    5    6    7                       [industry headline placeholder]
         energy  transport  consumer
```

**Market share is a derived figure, not a new simulated quantity**: a company's
revenue over its industry's total revenue. It costs nothing to compute, it moves for
reasons the earnings reports already explain, and it gives the industry tab the
comparison the brief asked for.

### 7.5 Tab 4 — Company

The drill-down. Opened by clicking a row on the Exchange, which is the gesture
[D103](decisions.md) already established for the existing details panel — that panel's
name, description and Investors list are the top-left of this screen.

```
 EXCHANGE | MARKET | INDUSTRIES | COMPANY         < PG&Enron >

 PG&Enron                    energy       SLOWING, 2nd year
 [company description placeholder]

 EARNINGS           yr3    yr4    yr5    yr6    yr7      WHY THE PRICE MOVED
  revenue          64.1   71.8   79.2   83.4   86.1       112 -> 128      +16
  expenses         56.4   62.0   68.6   73.4   77.1
  profit            7.7    9.8   10.6   10.0    9.0        earnings        +21
  margin            12%    14%    13%    12%    10%        multiple         +3
  earnings/share   7.70   9.80  10.60  10.00   9.00        industry        -2
  price             100    118    141     71    128         this event    -12
  P/E              13.0   12.0   13.3   11.8   11.8         last, faded    +6
                                           ^split          -------------------
                                                            total          +16
 earnings yield 7.0%  against risk-free 3.0%

 INVESTORS            NPC ACTIVITY, LAST YEAR          NEWS
  Ann                  Value      bought 120            [earnings commentary
  Cal                  Panic      sold everything        placeholder]
                       Short      short 240 shares      [whisper placeholder]
```

**The ledger on the right is the mode's thesis in one widget.** Every point of the
year's move, attributed, summing to the total. If a player ever asks "why did this go
down?", this is the answer, and it is arithmetic rather than a story.

**The regime is named on screen** ("SLOWING, 2nd year"), which is a choice worth
flagging. The alternative is to make the player infer it from the earnings series, as
Animal Crossing hides its price pattern. Naming it is recommended because the project
has a standing rule against penalising a player for something the game hid from them
([game-rules.md §9.5](game-rules.md)), and because the *useful* part — what the regime
will do next, and how many years it has left to run — still has to be worked out from
the published transition table. Question 8 in [§14](#14-open-questions-for-the-owner).

### 7.6 Charts on a character grid — measured, not assumed

The brief asks for charts and the owner's note says "there's got to be charts…". On a
106×30 character grid there are two ways to draw one, and the choice was settled by
measuring rather than guessing.

**Terminus carries the glyphs.** A headless probe loaded
`assets/fonts/Terminus.ttf` and asked it directly:

| Range | Present |
|---|---|
| Block elements, U+2580–U+259F | 30 of 32 |
| Box drawing, U+2500–U+257F | 120 of 128 |
| Geometric shapes, U+25A0–U+25FF | 15 of 96 |
| Arrows, U+2190–U+219F | 6 of 16 |

Specifically confirmed present: the full eighth-block ramp needed for bar heights
(U+2581 through U+2588), the half blocks, the three shade blocks, the light box-drawing
horizontal and vertical, and up and down arrows. The two missing block elements are
quadrants, which nothing here needs.

**So charts are text, and that is the recommendation.** A bar chart built from
eighth-blocks gets eight sub-steps of vertical resolution per character cell — a
12-row chart resolves to 96 levels, which is ample for a price series around 100. The
consequences are all good ones: no new art, no custom drawing code, the chart is a
`Label` so it inherits the shared `Theme` and the CRT shader with no special handling,
it costs nothing to test (assert the string), and it is exactly the right aesthetic for
a pixel-art terminal.

**The fallback, if a chart ever needs more than a grid can give**, is a small `Control`
with a `_draw()` method drawing integer-snapped lines. That is not forbidden by
[CLAUDE.md](../CLAUDE.md)'s ban on hardcoded pixel coordinates — the ban is about
*positioning nodes*, and drawing inside a control that containers have placed is a
different thing. It is listed as a fallback because it needs its own tests, its own
theming hookup, and care with the CRT effect, and the glyph measurement says it is not
needed.

**Chart sizes.** Every chart is a whole number of cells, so it sits on the grid: the
index chart is 38 × 7 cells, the industry chart 22 × 5, a sparkline in a row is 1 × 8.

---

## 8. Content taxonomy

The owner will write the words. This section is the **structure** those words go into:
what categories exist, what fields each carries, and how the game chooses one at
runtime.

**No flavour text has been written here.** Every example below reads
`[… placeholder]`, deliberately. [CLAUDE.local.md](../CLAUDE.local.md) is emphatic that
taglines, jokes and anything whose job is tone belong to the owner, and that an empty
label beats an invented one; the game's voice already exists in the original's events
(*"You invite your son to go bowling with you. Things don't end \"well.\""*) and
anything written to fill a gap reads as generic beside it.

### 8.1 The categories

> **Changed after S8's play, 2026-11-27 (decisions.md D208-D214).** The market
> headline became **market news** - headline, event text and an optional effect -
> and replaced the special events in this mode. The industry report became FROM
> THE HEADLINES, with a new automated INDUSTRY REPORT (year line and outlook) under
> it. The Company tab gained an EARNINGS line and IN THE NEWS (company news, the
> base events ported). Every line can require earlier ones. The categories below
> are as first designed; game-rules.md §5.1 is the current list.

Six, each with its own resource type. All are `.tres` files, like every other piece of
content in this project — **not** player-authored JSON, which [D119](decisions.md)
closed for now.

| Category | One per | Carries |
|---|---|---|
| **Market headline** | year | `id`, `conditions`, `text` |
| **Industry report** | industry per year | `id`, `industry_id`, `conditions`, `text` |
| **Earnings commentary** | company per year | `id`, `company_id` or `any`, `regime`, `surprise_band`, `text` |
| **Whisper** | zero or more per year | `id`, `subject`, `trigger`, `truth_chance_percent`, `text` |
| **Special event** | year | the existing `SpecialEventDefinition`, extended |
| **NPC chatter** | zero or more per year | `id`, `npc_id` or `strategy`, `situation`, `text` |

**Conditions are named bands, not expressions.** A condition is a set of enum values
the state must match, never a formula in a string — so the validator can check every
one at load and a typo cannot produce content that never fires. The bands:

| Field | Values |
|---|---|
| `mood` | `BULL`, `BEAR`, `ANY` |
| `move_band` | `CRASH` (≤ −15%), `DOWN` (−15…−3), `FLAT` (−3…+3), `UP` (+3…+15), `SURGE` (≥ +15%), `ANY` |
| `regime` | the five regimes of §3.3, or `ANY` |
| `surprise_band` | `MUCH_WORSE`, `WORSE`, `AS_EXPECTED`, `BETTER`, `MUCH_BETTER` — actual growth against the regime's midpoint |
| `standing_band` | `CHEAP`, `FAIR`, `RICH` — the company's P/E against its industry average |

**Whisper triggers are named state predicates**, each one a real condition on real
state, computed in `sim` and asserted in tests:

| Trigger | True when |
|---|---|
| `HIGH_SHORT_INTEREST` | The `SHORT` trader's position exceeds the threshold (§5.3) |
| `THIRD_GROWTH_YEAR` | A company has held `GROWTH` for three years — ageing is about to bite |
| `MARGIN_SLIPPING` | Margin fell while revenue rose |
| `PE_ABOVE_INDUSTRY` | P/E more than 20% above its industry average |
| `PE_BELOW_INDUSTRY` | More than 20% below |
| `SECTOR_RUN` | An industry has moved the same way three years running |
| `NEAR_SPLIT` | Price above 130, so a split is in reach |
| `NEAR_FAILURE` | In `DISTRESS` with a price under 20 |

**`truth_chance_percent` is the field that makes whispers a skill.** A whisper that is
always right is a free hint; one that is always wrong is noise. At, say, 75 the player
learns to weigh them, and the game can say in as many words that these are rumors. The
roll uses the injected RNG like everything else.

**Superseded by §8.4** (built 2026-11-23, D205): whispers that foreshadow next year,
from sources of named reliability, in place of the triggers.

### 8.2 How one is chosen

Every category uses **the bag pattern the game already has.**
[`EventPool`](../src/sim/event_pool.gd) draws without replacement from a shuffled bag,
refills and reshuffles when it empties, and shuffles with the injected RNG rather than
`Array.shuffle()` which would use the global one ([D23](decisions.md)). That is the
mechanism, reused per category and per condition:

1. Gather every entry whose conditions match this year's state.
2. Draw from that set's bag, without replacement, using the injected RNG.
3. **If nothing matches, show nothing.** No generic fallback line, no "something
   happened in the market this year". An empty slot is correct and a filler line is
   not.

Rule 3 is a content decision with teeth: it means a sparsely authored category simply
stays quiet most years, which is fine and self-repairing as content is written.

**The validator must cover all of this.** [D31](decisions.md) made
`ContentLibrary.validate()` refuse to vouch for bad content and collect *every* problem
rather than stopping at the first, because ninety events referencing ten stalks by id
means one typo produces an event that can never fire and reports nothing. The same risk
is now six categories deep. Specifically it must check: every `company_id` and
`industry_id` resolves; every industry has at least two members (§3.2); every
transition matrix row sums to 100; every `trigger` is a known predicate; and
`truth_chance_percent` is in range.

### 8.3 The authoring tables

Content is easiest to write in bulk, in a spreadsheet, and these are the column
layouts to write it in. Each maps one-to-one onto a resource's fields, so the shape
below is the shape on disk.

**Placeholder text says which slot it fills** (decided 2026-11-21). Until the owner
writes a line, its text is the category in capitals, a colon, and the conditions it was
chosen for — `INDUSTRY REPORT: energy, down`. So a placeholder that turns up on screen
tells whoever is playing exactly which line is missing and where it goes, and a search
for the category name finds every line still to write. None of it is meant to be read
as the game's voice.

**Market headlines**

| id | mood | move_band | text |
|---|---|---|---|
| `mkt_bull_surge_1` | BULL | SURGE | `MARKET HEADLINE: bull, surge` |
| `mkt_bear_crash_1` | BEAR | CRASH | `MARKET HEADLINE: bear, crash` |

**Industry reports**

| id | industry | move_band | text |
|---|---|---|---|
| `ind_energy_down_1` | energy | DOWN | `INDUSTRY REPORT: energy, down` |

**Earnings commentary**

| id | company | regime | surprise_band | text |
|---|---|---|---|---|
| `earn_pgenron_slow_1` | pgenron | SLOWING | WORSE | `EARNINGS: PG&Enron, slowing, worse than expected` |
| `earn_any_distress_1` | *(any)* | DISTRESS | ANY | `EARNINGS: {company}, distress` |

**Whispers**

| id | subject | trigger | truth% | text |
|---|---|---|---|---|
| `whisp_short_1` | stryker | HIGH_SHORT_INTEREST | 75 | `WHISPER: strYker!!!, high short interest` |

**NPC chatter**

| id | npc / strategy | situation | text |
|---|---|---|---|
| `chat_value_bought_1` | *(strategy)* VALUE | BOUGHT | `NPC CHATTER: value trader, bought` |

**How much is needed.** A rough budget, for scheduling rather than as a target: three
or four market headlines per mood-and-band combination that can actually occur, two or
three industry reports per industry per band, one earnings line per regime per
surprise band (with `any`-company lines carrying most of the load), and a handful of
whispers per trigger. The bag refills, so under-authoring makes lines repeat sooner
rather than breaking anything — which is the right failure mode for content that will
be written over time.

**Where it lives on disk.** Following [D29](decisions.md), which bundles a stalk and
its events into one authorable `.tres` so that adding a stalk is a single-file change:
company-scoped content (earnings commentary, whispers about that company, its events)
bundles onto the company's own resource; market and industry content gets one `.tres`
per industry plus one for the market.

**As built (S8):** not bundled. Every news line lives in a `NewsBook` in
`src/data/news/`, one per industry plus one for the market, and says what it is
about in its own fields; see [D199](decisions.md) for why.

### 8.4 Whispers that foreshadow — **built 2026-11-23** (decisions.md D205, D206)

Manual section S found that the S8 whispers (§8.1's triggers, D201) state a fact
about the year just played - "third growth year", "margin slipping" - which a player
can check on the Company tab. That is a company spotlight, not a rumor. The owner
wants a whisper to be **the traders' gossip mill: a hint about next year, against
what everyone expects, from a source of known reliability.** This section is the
design for that. It replaces the triggers. Built as written, with the owner's
answers to the three open questions at the end of this section.

#### What a whisper is about

**Next year's surprise for one company or one industry.** Everyone can see a
company's regime and so what growth to expect from it (§3.3;
`NewsSelector.expected_growth`). A whisper says whether next year will beat or miss
that, and by how much, in the five surprise bands the earnings commentary already
uses. An industry's whisper is about its swing, the part of its year nobody can see
coming (`IndustryState`), in the same bands:

| Band | Meaning |
|---|---|
| `MUCH_WORSE` | next year's growth 8 points or more below what this regime leads one to expect |
| `WORSE` | 3 to 8 below |
| `AS_EXPECTED` | within 3 |
| `BETTER` | 3 to 8 above |
| `MUCH_BETTER` | 8 or more above |

A line need not mention earnings at all. "The CEO has been at the golf course more
than the board room" is a `WORSE` line; "the sales team all have new Mercedes" a
`BETTER` one. The band is what the line *means*, not what it says.

#### How a whisper can know next year

A company's year of earnings takes exactly two draws (`CompanyState.advance_earnings`):
the regime roll, then the growth roll inside the new regime's band. Neither depends on
anything players do. So:

1. **At the end of each year** (and once at match setup, for year 1), after
   everything else in the year, each living company's two draws for **next** year
   are made from the match's generator and kept on the company.
2. Next year's earnings season **uses those kept draws** instead of drawing.
3. A whisper reads them: the true band is next year's growth, before the industry's
   effect, against what **this** year's regime leads one to expect. A regime change
   therefore shows up as a surprise, which is exactly what a rumor should foreshadow.

**Why this and not a whisper that causes its result.** The draws come from the same
distributions as now, only a year earlier, so prices, regimes and balance are
unchanged in distribution - nothing is nudged to make a rumor come true. As built
it turned out better than that: drawing at the end of a year is the same place in
the match's random stream as drawing at the start of the next, so a seed plays
exactly the match it played before (D205; the 4,000-seed balance run matched D172
to every figure). The balance tool's regime-roll override still applies. The base
game draws none of this; the golden hash does not move.

**The price is not promised.** The whisper is about the company's own luck and
regime. The industry's year, special events, the desk's flow and a squeeze still move
the price. Even a perfect source predicts earnings, not the chart.

#### Sources

Each whisper comes from a **source**, rolled per whisper (not written into the line),
and shown beside it. The source decides how far the band the whisper speaks for is
from the true one. Names are the owner's; the numbers are a first proposal:

| Source | Names the true band | One band off | Two or more off |
|---|---|---|---|
| Rock Solid | 85% | 15% | 0% |
| Credible | 60% | 35% | 5% |
| Hit-or-miss | 40% | 35% | 25% |
| Questionable | 30% | 35% | 35% |
| Gossip | 20% | 30% | 50% |

- **One band off** goes up or down with equal chance, or the only way there is at
  the edge (`MUCH_BETTER` can only be off to `BETTER`).
- **Two or more off** picks evenly among the bands that far away.
- So a Credible "much better" almost always means better or much better, and very
  rarely a bad year; Gossip is a weak hint at best.
- Each source is equally likely to be rolled (20% each), a first proposal too.

#### How many, about whom

- **Two a year**, about two different subjects, picked evenly from every industry
  and every company still alive. A whisper appearing at all says nothing; only its
  words and its source do.
- **Shown from the end of year 1** (about year 2) to the start of the last year.
  None in year 0: nobody can trade then, so a whisper could not be acted on (D207).
  The last year has no next year, so no whispers.
- The line is drawn from the lines written for the band it speaks for, through the
  bag (§8.2), so lines repeat as little as possible.
- All of this is chosen by `NewsSelector` with its own generator (D200), never the
  match's, so reading the whispers cannot move a price.

#### Content

A `Whisper` resource is `id`, `about` (company or industry), `subject` (optional:
one company or industry it alone fits), `outcome` (one of the five bands) and `text`.
`trigger` and `truth_chance_percent` are gone. The owner writes the pool: as many
lines per band as wanted, every band needing at least one general line for companies
and one for industries. The placeholders are one per band and kind:
`WHISPER: {company}, much better`, `WHISPER: {industry}, worse`.

#### On the wire

Every peer must know next year's kept draws to choose the same whispers, so they go
in the state snapshot (welcome, rejoin, host migration) and each year's record. This
**exposes nothing new**: clients already receive the match generator's state
(`StateSync.encode_state`'s `rng_state`) for host migration, from which a modified
client could compute next year anyway.

#### On screen

- Market tab, WHISPERS: each line with its source before it, in a faint column.
- **VIEW HISTORY** under them opens every round so far over the right half, newest
  first, each whisper with what really came of it once its year is played. CLOSE,
  or leaving the tab, shuts it (D206).
- Company tab, NEWS: the current whispers about that company or its industry.

#### The open questions, as the owner answered them (2026-11-23)

- **Showing last year's whispers again:** yes, in a history panel opened by a VIEW
  HISTORY button over the news (the owner's mockup), year by year. CURRENT and
  HISTORY tabs were the fallback if a panel was too much; it was not.
- **The source names:** as in the table above.
- **Industries:** yes. A whisper may be about an industry - a rumor of new
  regulation affects every company in it - as well as a company.

---

## 9. Reaching the client

The host owns the simulation and clients own only their view
([D12](decisions.md)). Everything a client renders has to cross the wire, survive a
host migration, and reach a player who rejoins.

### 9.1 The rule: inputs travel, readouts are derived

The project already has a rule of exactly this shape, and this is its sibling:

> Definitions are not sent. Both sides load the same `.tres` content, so only ids
> travel and the receiver looks the definition up locally. — [`state_sync.gd`](../src/net/state_sync.gd)

> **Derived figures are not sent. The inputs travel and the receiver recomputes.**

So the wire carries revenue, margin, shares outstanding, regime, years in regime,
industry performance, event carry and the mood. It does **not** carry profit, earnings
per share, the multiple, fair value, P/E, earnings yield, market share, the index
level or the ledger — all of which are pure integer functions of those inputs.

This is safe only because of §3.7: every derivation is integer arithmetic with
specified rounding, in `sim`, with no floats anywhere. Two machines running the same
build therefore derive bit-identical numbers. **And that is a test**: encode a state,
decode it, re-derive every readout, and compare against the host's.

It is also a real saving, which §9.2 quantifies.

### 9.2 State size, estimated

The concern in the brief is right: earnings reports, industry history, NPC activity and
chart data, per company per year, for up to 99 years, all of which has to reach a
rejoining player in one go ([D118](decisions.md) sends the whole year-by-year record
with the welcome).

**Where the cost actually is: dictionary keys, not numbers.** Godot encodes a
`Dictionary` with its keys as strings, so `"revenue"` costs about eleven bytes *every
time it appears*. The existing history already pays this — ten stalks × seven fields
per year, as a dictionary each — and at 99 years it is already on the order of
**150 KB**. A naive StalkleHeads history would add roughly 130 more numbers a year and
land near **400 KB** in total, which is uncomfortably close to real limits: Steam's
networking messages are documented as capping a single reliable message at 512 KB — a
figure to confirm against the SDK before relying on it — and a 99-year match is an
achievement (`SSS_CENTURY`) so it genuinely happens.

Three measures, which together make the problem go away rather than manage it:

| Measure | Effect |
|---|---|
| **Store inputs, derive readouts** (§9.1) | ~8 numbers per company-year become 3 |
| **Per-year rows as `PackedInt32Array`, not `Dictionary`** | A fixed field order costs 4 bytes a number and no key strings at all |
| **Cap the welcome's history, fetch deeper years on request** | A chart needs the last ten years; year 3 of a 99-year match is a curiosity |

With the first two: roughly 30 numbers a year at 4 bytes is **120 bytes a year**, or
about **12 KB over 99 years** — a thirtieth of the naive figure, and small enough that
the third measure is a precaution rather than a requirement.

**The per-trade snapshot** is a separate budget and a tighter one, because it goes out
on *every* buy and sell, not once a year ([D42](decisions.md) replicates whole
snapshots rather than deltas, deliberately). It gains three things, and the desk is the
one that matters:

| Added to every snapshot | Numbers |
|---|---|
| 13 companies' current fundamentals (revenue, margin, shares, regime, years in regime, event carry, flow) | ~91 |
| 6 industries (performance, standing) | ~12 |
| Market (index level, sentiment) | 2 |
| **24 NPC traders' books** (cash plus a holding per stalk) | **~384** |

So the desk is roughly three quarters of the addition. As `PackedInt32Array` rows that
is about **2 KB on top of a current payload of well under one**, which is acceptable;
the design scales to about fifty traders before this needs rethinking, which is why §5.1
puts the ceiling there.

**Why the desk's books travel at all**, rather than each client recomputing them: the
same reason [D105](decisions.md) gives for sending every player's position. A client
promoted to host must continue the match from the copy it holds, and a market whose
other twenty-four participants have to be re-derived from scratch is not that copy. The
alternative — sending only aggregate flow and a per-strategy leaderboard, about 30
numbers — is tempting and should be measured before being rejected, but it cannot serve
a migration on its own.

**None of these figures is measured.** They are estimates from field counts and
Godot's encoding, and the first job of the phase that builds the wire format is to
replace them with a measurement.

#### Measured, 2026-11-22 (S6)

Phase S6 built the wire and measured it with `tools/wire_report.gd`: bytes of Godot's
own Variant encoding of exactly what the host passes the RPC, on seeded 99-year
matches in which every player carries a loan every year they can (the heaviest case,
because loans are the largest per-player part of a year). Full table in
[D178](decisions.md).

| | Estimated above | Measured, 10 players | Measured, 1 player |
|---|---|---|---|
| Per-trade snapshot, year 99 | "well under one" + ~2 KB | **11.1 KB** (base game 6.6 KB) | 6.4 KB (base 2.5 KB) |
| of which the market | ~2 KB | **2.8 KB**, the desk 1.0 KB of it | 2.3 KB, the desk 0.5 KB |
| The market's part of a year's record | 120 bytes | **about 680 bytes** | about 670 bytes |
| Welcome history, 99 years | ~12 KB | **153 KB** (base game 300 KB) | 97 KB (base 246 KB) |
| The same history as dictionaries | ~400 KB | **1.32 MB**, built and measured | 1.27 MB |

What the estimates missed, and why it does not change the design:

- **The market's record is larger than estimated** because the estimate counted
  thirteen companies and no desk. The companies cost exactly the three numbers a year
  it predicted (regime, growth roll, net shares priced); there are eighteen of them,
  and the desk's record of what each trader did is another 72 numbers a year.
- **The welcome is dominated by the players' part**, which the estimate did not count
  at all: dividends, loan changes, net worths and standings, sent as the base game
  sends them. Even so it is half the base game's own welcome for the same match.
- **The dictionary encoding is three times worse than estimated**, and over the
  512 KB Steam limit by more than double. The warning above was right; the packed
  format is what answers it, at an eighth of the size.
- **The third measure, capping the welcome's history, is not needed** and was not
  built. At 153 KB the heaviest welcome is under a third of the documented limit.
  The limit itself is still unconfirmed against the SDK headers.
- **Worth knowing beside it:** the base game's ten-player 99-year welcome is 300 KB.
  Not a StalkleHeads problem, and the base game's wire was deliberately left alone.

### 9.3 Migration, rejoining, and a player who is away

All three already work and all three constrain this design. Nothing below is new
behaviour; it is the checklist this mode has to satisfy.

**Satisfied in S6** ([D176](decisions.md)-[D178](decisions.md)), each row tested
in `test_wire.gd` by comparing a client's copy with the host's field by field. One
row needed more than the table foresaw: the event bags belong to the pipeline, not the
state, so a promoted host would have dealt from freshly shuffled bags. They now
travel with the market ([D177](decisions.md)).

| Mechanism | What StalkleHeads must do |
|---|---|
| **Everything travels** ([D105](decisions.md)) | Every client holds a whole match so any of them can host it. NPC positions and company fundamentals are part of "whole" — a promoted host that recomputed them would be running a different market |
| **Steam picks the new host** ([D104](decisions.md)) | A promoted host adopts the random stream's position (`rng_state`) and carries on. The NPC desk's draws are in that stream, so this works unchanged — provided §5.4's fixed draw count holds |
| **The year record travels with the welcome** ([D118](decisions.md)) | A rejoining player gets the full fundamentals history, not just the years they were present for. This is the payload §9.2 is about |
| **An away player is still in the match** ([D110](decisions.md), [game-rules.md §4.6](game-rules.md)) | The year pays them, splits and bankrupts their stalks and ranks them, and the ready gate skips them. Nothing in this mode changes that. **NPC traders are not players** and are never in `state.players`, so they never affect the ready gate |
| **Content must match** | `apply_state` refuses a snapshot naming a stalk it cannot resolve, because a client running different content from the host is worth failing loudly over. The same must apply to industries and NPC traders |

### 9.4 Mode selection

A match is one mode or the other, chosen before it starts and never changed.

- **`GameSettings` gains a `mode` field.** It is already how a match is configured and
  it already travels to clients in the opening snapshot — including the game name,
  which is there precisely because it has to reach the clients and the settings already
  do.
- **The title screen's panel gains the choice.** Single Player and Host Online are one
  panel with one fixed size behind every tab ([D86](decisions.md)), so the control has
  to fit the existing shape rather than grow it; [D125](decisions.md) says a panel's
  size is decided up front, not by what is in it.
- **The lobby publishes it, and the browser row shows it.**
  [D88](decisions.md) already writes years, starting cash and loans into Steam lobby
  data for no other purpose than the browser row, and its rule applies verbatim here:
  **a lobby that did not publish something has that part left out.** Lobby data is
  strings read back with `to_int()`, which answers 0 for an absent value — which is
  exactly what a lobby from an older build looks like. So a lobby with no `mode` key
  shows no mode, rather than being labelled as the base game and surprising a joiner.
- **A rejoin needs no change.** The remembered record is a lobby id and nothing else
  ([D111](decisions.md)), and the mode arrives with the settings in the welcome.

---

## 10. Where this plugs into the existing code

### 10.1 What the seam already gives us

[`price_model.gd`](../src/sim/price_model.gd) was written for this, and says so:

> This is the main extensibility seam in the project. The faithful port uses
> RandomRangePriceModel; "StalkleHeads" mode will add an earnings-driven model without
> touching the year pipeline.
>
> `next_change` receives the WHOLE market state, not just one stalk, so a future model
> can price a stalk relative to the others — which is what lets "My Mutuals and Me Inc."
> eventually behave as a genuine index.

Four decisions taken on day one for this mode. Three hold up as written; the first holds
for the base game and is superseded for this mode:

| Decision | Still right? |
|---|---|
| [D6](decisions.md) Price movement is a swappable strategy | **Right, but not what StalkleHeads uses.** The first draft leaned on it; the revised year reorders its steps, so this mode needs its own pipeline rather than a new price model (§10.2) |
| [D7](decisions.md) The price model receives the whole market | **Yes, as a principle** — the index of §3.9 needs the whole market, and the new pipeline has it |
| [D8](decisions.md) Record the year history from Year 0 | **Yes.** Every chart and every multi-year read in §7 is impossible without it, and it could not be backfilled |
| [D9](decisions.md) Content is keyed by `id`, not display name | **Yes** — industries, NPC traders and six content categories all reference by id |

### 10.2 What the seam does not give us, and what is needed instead

**The first draft got this section wrong, and the revisions made it obvious.** It
proposed a `MarketModel` with three no-op hooks, called from three points in the
existing `YearResolver`. That fitted a year whose *order* matched the base game's. The
year in §4 no longer does:

| Base game ([`year_resolver.gd`](../src/sim/year_resolver.gd)) | StalkleHeads (§4) |
|---|---|
| Mood rolled **first**, and every later step reads it | Mood **derived last**, from the index |
| Prices move, *then* the event is drawn | Event drawn **before** prices, as an input to them |
| Two bankruptcy passes | One |
| Split above `TradeRules.SPLIT_ABOVE` (150) | Split above 300, and three more fields halve |
| Dividends `stalk.dividend_per_share(mood)` | Dividends from earnings |

Each row is a step the shared resolver would have to do differently, and the only way
to do a step differently inside one function is `if mode ==`. [§13.3](#133-what-it-does-to-the-base-game)
names that clause as the sign the modes have stopped being additive. So hooks would
have produced exactly the entanglement they were meant to prevent.

**What is needed instead is a second pipeline that shares the back half.** The front
half of the year — everything up to and including dividends — differs; the back half
does not. The design splits along that line:

```
YearResolver                       unchanged in behaviour; the base game's pipeline
EarningsYearResolver               new; the StalkleHeads pipeline, steps 1-10 of §4
YearSettlement                     new home for what both share: loans, net worth,
                                   standings, game end (§4 steps 11, 12, 15)
```

**Change 1 — extract the back half.** `_process_loans`, the net-worth step and the
game-end check move out of `YearResolver` into `YearSettlement`, a `RefCounted` with no
state, and `YearResolver` calls it. This is the only edit to existing code that moves
anything, and it is a pure move: same statements, same order, no draws from the RNG.
**P5 is the test that proves it** — a seeded 99-year base match hashed before and after
the move must be identical (§12.1).

**Change 2 — `GameSettings` gains `mode`**, as §9.4 describes, and whatever builds the
resolver today picks one of the two by it. That is one decision in one place, at match
start, and nothing during the year ever asks which mode it is.

**That is the complete list of changes to existing systems** — two, down from the first
draft's three. `PriceModel` is not changed and not reused: the earnings price is the
identity of §3.5, computed once per company inside the new pipeline, and squeezing it
through `next_change(stalk, mood, state, rng)` would mean passing a mood that does not
exist yet. The seam [D6](decisions.md) built is honoured rather than used — it was a
promise that the year pipeline would not need rewriting for a new price model, and that
promise holds for the base game; StalkleHeads is a new year, not a new price.

**One open consequence: which event pool.** [`EventPool.draw`](../src/sim/event_pool.gd)
takes the year's mood and draws from that mood's bag, and in StalkleHeads the event is
drawn before the mood exists. The proposal is that it draws from the bag of **last
year's reported mood**, which is the same one-year lag that keeps sentiment
non-circular (§3.1), so a bull year tends to be followed by bull-flavoured news. Year 1,
having no previous year, draws from the bull bag. The alternative — one merged bag — is
simpler and loses the flavour; it is a content question as much as a code one.

Everything else is new files: `src/sim/` gains the fundamentals, the regimes, the
valuation, the index, the NPC desk, the news selector and `EarningsYearResolver`;
`src/data/` gains the company profiles, the industries, the traders and six content
categories; `src/ui/` gains a tab host and four tab screens. If the design is right, no
existing rule, no existing test assertion and no existing screen changes.

### 10.3 One thing that should not be done

**Do not put the fundamentals in an autoload.** [CLAUDE.md](../CLAUDE.md) is explicit
that an autoload is a service locator and not a place for game rules, and the pull to
make a global `Market` singleton that every tab reads from will be strong, because four
screens all want the same numbers. They should read `GameState` through the session, as
every existing screen does, and derive what they display.

> **For a reader new to Godot:** an "autoload" is a node Godot creates once at startup
> and keeps for the whole run, reachable by name from anywhere. That convenience is
> exactly why rules must not live in one — anything reachable from anywhere ends up
> called from everywhere, and the simulation stops being testable without the engine.

---

## 11. Build plan

Phased so that each phase is independently useful and independently testable, and so
that the riskiest thing — balance — is reachable early rather than discovered late.
The ordering rationale matches the port's own ([porting-plan.md](porting-plan.md)):
economy first, UI second, content last.

**Revised for the owner's notes.** The first draft's phases assumed hooks in the shared
resolver, a separate index phase, and a small NPC desk added late. All three changed:
the mode has its own pipeline (§10.2), the index is part of that pipeline, and the desk
is now an input to every price through `flow`, so it cannot come last.

| Phase | What | Rough size | Two Steam accounts? | Waits on §14 |
|---|---|---|---|---|
| **S0 — Guard the base game** ✅ **Done 2026-11-21** | The P5 golden-history test, written and passing **before any other change**: a seeded 99-year base match, hashed. **Delivered:** `tests/unit/test_golden_history.gd` — shipped content, three scripted players (a rotating trader, a borrower who defaults in year 5, a borrower who misses once and overpays), every year's prices, deltas, splits, bankruptcies, mood, event, dividends, loan assessments, cash, holdings, net worth, standings and game end written as sorted text and compared by sha256. Shown to fail on two deliberate perturbations. See [D127](decisions.md) | Small | No | — |
| **S1 — Fundamentals** ✅ **Done 2026-11-21** | Regimes and the matrix, ageing, recovery, the long-match damping ladder; revenue, margin and earnings per share; `IndustryDefinition` and the validator check; sentiment and the multiple; the price identity with `event_carry` and `flow`; the ledger; payout-ratio dividends; the split at 300. Pure `sim`, headless. **Delivered:** `EarningsRegime`, `CompanyProfile` and `IndustryDefinition` in `src/data/`; `RegimeRules`, `CompanyState`, `IndustryState`, `ValuationRules`, `PriceIdentity`, `PriceLedger` and `DividendRules` in `src/sim/`; `ContentLibrary.load_fundamentals()` with the industry, ticker and range checks and a new `warnings` list; 18 company profiles and 6 industries as placeholder `.tres`; 75 tests in four new files. **Scope:** no year pipeline - the pieces are called in §4's order by a stand-in loop in `test_price_ledger.gd`, and S3 builds the real one; flow takes net shares as a plain input until S4. Decisions D128-D135 (including where this document contradicts itself), the §15 decisions recorded as D136-D143 | Largest single phase | No | 3 |
| **S2 — Balance tooling** ✅ **Done 2026-11-21** | The probe of Appendix A rebuilt as a `tools/` script over the **real** `sim` code, reporting the strategy table of §2.1. Its first job is to reproduce Appendix A's numbers; if it cannot, either the probe or the implementation is wrong, and that must be settled before tuning anything. **Delivered:** `tools/balance_report.gd` (arguments for years, seeds, first seed, strategies, player flow; 400 ten-year matches in about 4 s); `tools/balance/balance_match.gd`, the nine strategies and the trading loop; `tools/balance/stand_in_year.gd`, a §4-order year over the S1 classes that **S3 replaces**; `tests/unit/test_balance_smoke.gd`, 30 fixed-seed matches with loose bands, about 1 s. Nothing added to `src/`. **Finding: the probe's TREND strategy was mis-measured, and P4 failed at ten years** (TREND 48.5%) — see Appendix A and [D149](decisions.md). **Then swept and fixed** (2026-11-22): GROWTH's stay chance 58 → 42 and premium 0.6 → 1.2, leader about 28% ([D150](decisions.md), [D151](decisions.md)); the sweep's levers are tool arguments. No FOLLOW and no desk flow until S4. Decisions D144-D149 | Small to build, open-ended to use | No | — |
| **S3 — The pipeline** ✅ **Done 2026-11-22** | `YearSettlement` extracted from `YearResolver` (P5 must stay green); `EarningsYearResolver` running §4 steps 1–10; the derived mood; the event drawn from last year's mood; Mutuals as an index; the bond as the yardstick. **Delivered:** `YearSettlement` (loans, net worth, standings, game end, closing the year) moved out of `YearResolver` by a pure move, `GOLDEN_HASH` unchanged ([D152](decisions.md)); `EarningsMarket` on `GameState.market`, building a twenty-row board (eighteen companies, the bond, the index) and an event pool without the index's events ([D160](decisions.md), [D154](decisions.md)); `EarningsYearResult`; `EarningsYearResolver`, §4 steps 1–10 then the settlement, with the mood derived from the index move and last year's move as sentiment ([D153](decisions.md)), the event from last year's bag and the bull bag in year 1, one bankruptcy pass ([D155](decisions.md)), the bond paying its coupon in every year with its yardstick readouts ([D156](decisions.md)), Mutuals as an index of all eighteen companies' pre-split moves paying their average dividend ([D157](decisions.md)), and Yearly Change including the event ([D158](decisions.md)); `GameSettings.multiple_loans_enabled`, off by default, one loan at a time, sent in the snapshot ([D159](decisions.md)); the balance tool moved onto the real pipeline and `stand_in_year.gd` deleted ([D161](decisions.md)); `test_earnings_year_resolver.gd`, 45 tests, plus loan and snapshot tests. **Measured:** TREND 29.6%, LOWPE 23.9% over 4,000 ten-year seeds, so P4 holds by 0.4 points. **Scope:** flow is still a plain input; nothing selects the mode or turns the loans toggle on (S5); nothing on screen (S7). Decisions D152-D161 | Medium | No | 2, 4, 7, 14 |
| **S4 — The NPC desk** ✅ **Done 2026-11-22** | About twenty-four traders, the eight strategies, the per-trader appetite draw, sorted order and fixed draw count; recording net shares traded into `flow`; short interest and its event weighting. **Then re-run S2**: `flow` is clamped and measured as free only at 5%, so this is where that is confirmed or not. **Delivered:** `NpcStrategy` and `NpcTraderDefinition` in `src/data/`, with 24 trader files in `src/data/traders/` (three per strategy, 8,000 cash and conviction 45 as the probe had, names and chatter placeholders) and the squeeze template `src/data/squeeze/short_squeeze.tres`; `ContentLibrary.load_fundamentals()` loads and validates both ([D162](decisions.md)); `NpcDesk`, `NpcTraderState`, `NpcDeskYear` and `ShortInterestRules` in `src/sim/`; the desk on `EarningsMarket.desk`, acting at §4 step 13 after the settlement, in id order, two draws per trader, its net shares recorded through `EarningsMarket.record_trade` as next year's flow ([D163](decisions.md)); the SHORT trader with real short accounting and players unable to short ([D164](decisions.md)); short interest flagged at 10% of shares outstanding, and a squeeze in place of the bag draw one flagged year in four, the roll drawn every year ([D165](decisions.md)); the balance tool's FOLLOW, `--flow` modes and squeeze levers ([D166](decisions.md)); `test_npc_desk.gd`, 41 tests. **Measured: P4 fails as shipped, LOWPE 41.8%** over 4,000 ten-year seeds; it holds at 28.9% with the squeeze off. Nothing in `src/` was retuned ([D167](decisions.md), Appendix A). **Then** the owner moved SHORT's target to the highest P/E: P4 holds as shipped, `LOWPE` 27.7% ([D168](decisions.md), [D169](decisions.md)), and the squeeze ships with flow's cost accepted until S5 ([D170](decisions.md)). **Scope:** players' trades are not yet recorded into flow in the game, because `MatchAuthority` cannot run this mode until S5, which must call `record_trade` and pass the squeeze template; nothing sends the desk (S6) or shows it (S7); chatter is not chosen (S8). Decisions D162-D170 | Medium | No | 10, 11 |
| **S5 — Mode and lobby** ✅ **Done 2026-11-22** | `GameSettings.mode`, picking the resolver at match start, mode selection on the title screen, the lobby key, the browser row. **Also:** record players' trades into `flow` through `MatchAuthority`, then re-run the balance tool at 4,000 ten-year seeds; if the leader passes 30%, tighten the flow clamp first ([D170](decisions.md)). **Delivered:** `GameMode` in `src/data/` and `GameSettings.mode`, the base game by default; `MatchSetup` in `src/sim/`, the one place the mode is read: content, board, pipeline, and `multiple_loans_enabled` on for StalkleHeads ([D159](decisions.md)); `YearPipeline`, the base class of both resolvers, which `MatchAuthority` holds and tells about every accepted trade, so a player's trade is next year's flow in this mode and nothing in the base game; the squeeze template passed to `EarningsYearResolver`; a **Game** row on the title screen inside the fixed card; the lobby key `mode` as a word and the browser row naming the mode first, nothing for a lobby that published none; `mode` in the snapshot, and a joining client loading the companies when the host's settings say StalkleHeads; a promoted host refusing a StalkleHeads match, since its market is not on the wire until S6 ([D171](decisions.md)); `test_game_mode.gd`, 33 tests. **Measured:** LOWPE 27.7% over 4,000 ten-year seeds, identical to D170, because the tool already recorded players' trades the same way; the clamp is not tightened ([D172](decisions.md)). **Scope:** the playing screen is the base game's, showing the twenty-row board (S7); no migration or rejoin of a StalkleHeads match (S6); the browser row, a two-account join and the take-over refusal were checked by hand on 2026-11-22, manual steps C1-C5 in [manual-testing.md](manual-testing.md), all passing. Decisions D171-D172 | Small | Yes, for the browser row | — |
| **S6 — The wire** ✅ **Done 2026-11-22** | Inputs-travel encoding, packed history rows, the desk in the snapshot, derive-on-client; migration and rejoin in a StalkleHeads match; the payload measured rather than estimated. **Delivered:** `src/net/market_sync.gd`, called by `StateSync` only for a match with a market, so the base game's snapshot and year record are unchanged (a test pins their keys; the golden hash did not move). **The snapshot** carries the market's state as packed blocks - per company six reals and seven integers, per industry its performance and roll, the market's scalars, the flow input, the event bags, and every NPC trader's book, sparse - and a client rebuilds every readout with `CompanyState.derive_readouts`; a `content_key` fingerprint refuses a host running different content ([D176](decisions.md)). **The event bags** travel with the market, so a promoted host deals the departed host's next event ([D177](decisions.md)). **A year** travels as its draws - industry rolls, each company's regime, growth roll and net shares priced, the squeeze, the desk's record - and the client replays it through the resolver's own second half, `EarningsYearResolver.replay_year`, so host and client run one implementation; a welcome replays the whole history from year 0 in under 0.2 s ([D178](decisions.md)). `HostSession.take_over` now accepts a StalkleHeads match. Two changes to what the match computes, both proven harmless by a fingerprint of three 99-year matches: a failed company's valuation readouts are cleared, and the resolver records its draws. `test_wire.gd`, 24 tests: every snapshot and every live year of three 60-year matches identical to the host's to the bit, a welcomed history year for year, a rejoiner equal to a player who stayed, **a promoted host making the same thirty years the old host would have**, the same over ENet, the refusals, the payload under a ceiling. `tools/wire_report.gd` measures the payload. **Measured:** snapshot 11.1 KB, welcome 153 KB at ten players and 99 years; see §9.2. **Scope:** nothing on screen (S7); Steam itself not exercised, manual steps D1-D4 in [manual-testing.md](manual-testing.md), all passing on 2026-11-22, as did a rematch afterwards. Decisions D176-D178 | Medium | Yes | — |
| **S7 — Interface** ✅ **Done 2026-11-22** | Tab host; the Exchange board with tickers, collapsible industry groups, in-group sorting and the HELD column; the Market, Industries and Company tabs; the chart widget; the ledger widget; the year digest. **Delivered:** `GameplayScreen` puts `MarketTabs` (`src/ui/screens/stalkleheads/`) in place of the three boards the first time its state has a market; the base game's screen is unchanged ([D180](decisions.md)). **EXCHANGE**: twenty rows under six industry headers plus INDEX & BOND, each header carrying its average P/E and year; tickers beside the scrolling names; clicking a header collapses it, clicking a column heading sorts every group by it and never across one; HELD with one quantity box and B/S per row, checked by the same rules the authority enforces; down the right CASH, NET, the rankings, THE DESK by strategy and SHORT INTEREST. **MARKET**: index level, market P/E, mood with bull years, breadth, risk-free rate, the index by year as a text chart, the year's news, the mood row. **INDUSTRIES**: the six industries' year, three-year and standing moves, average P/E and revenue share, a signed chart of the selected industry by year, its members' shares. **COMPANY**: walked with < and >; ticker, industry and the regime named ("SLOWING, 2nd year", q8); five years of earnings with splits marked; the ledger "why the price moved", every point attributed and the total equal to CHG (q7, D158); earnings yield against risk-free; investors by name and the desk's traders by name (q11). **The year in review** inside the base news panel. No cheap/expensive marker (q9), no flatten toggle (q12). **Underneath:** each year records every company as it left it, in the half a client replays, so the client builds the same history with nothing new on the wire; every figure on screen comes from `MarketReadouts` and `YearDigest` in `src/sim/` ([D179](decisions.md)); charts are text from the eighth-block ramp, tables are `CellRow`s measured in characters ([D181](decisions.md)); the remaining layout choices are [D182](decisions.md). `test_market_readouts.gd` (30 tests) and `test_stalkleheads_screen.gd` (31), including a client's four tabs equal to the host's and every tab fitting 640 x 360. The golden hash did not move. **Scope:** headlines, whispers and NPC chatter are S8; checked by hand as manual steps E1-E6 in [manual-testing.md](manual-testing.md), passed 2026-11-22 except step 49, with requests. **Then** ([D183](decisions.md)): the arrows walk the board's order, the identity line split into cells, the HOLDINGS / RANKINGS / DESK side panel, a fixed trade box with S greyed on every company shown on its own, a sort marker, tooltips on the financial terms, YoY on the Company tab, the year in review's dividers and sentiment line, the event clickable, the tick box showing the setting; re-checked as section F, passed with findings. **Then** ([D184](decisions.md)): the side panel over the tabs in a bright frame, holdings as the base game's row with SELL only, the arrows back to the match's order, a COMPANIES list with an NPC column, NPC activity as a table, HELD N, the sort marker after the caption, BUY and SELL in full, tooltips opaque and wrapped; re-checked as section G, passed with findings. **Then** ([D185](decisions.md)): captions capitalised, the Company tab's title pinned, NPC ACTIVITY in fixed columns, the company list sortable, the board's headings drawn as cells that never move; re-checked as section H, passed with findings. **Then** ([D186](decisions.md)): "The Market:", descriptions shown whole, headings padded with PRICE/CHG/DIV/HELD rebalanced; re-checked as section I, passed. **Then** ([D187](decisions.md)): lorem ipsum descriptions for the placeholder companies, the industry chart coloured by sign, no tooltip on a desk trader's name; re-checked as section J. **Then** ([D188](decisions.md)): drawn charts - the index as a line, and the Company tab's earnings area offering price candles, sales, margin, per-share and P/E charts beside the table; checked as section K. **Then** ([D189](decisions.md)), a trial: the Market tab in two halves, the right one scrolling with the news, the mood and the year in review; checked as section L, passed with findings. **Then** ([D190](decisions.md)): bright rules between the right half's sections, and more spacing; checked as section M. **Then** ([D191](decisions.md)): the company list stars the companies you own; checked as section N. Decisions D179-D191 | Largest UI phase | Partly | 1, 8, 9, 12 |
| **S8 — Content** ✅ **Done 2026-11-23** | The roster to three per industry, the industry resources, the trader resources, the six news categories and their selector. **Placeholders until the owner writes them**. **Delivered:** the roster, industries and traders audited against §3.2.3, §3.2.4 and §5.1 and found complete; the validator now also checks the transition matrix and warns of a strategy no trader follows ([D204](decisions.md)). Five news resources (`MarketHeadline`, `IndustryReport`, `EarningsCommentary`, `Whisper`, `NpcChatter`) beside `SpecialEventDefinition`, with their bands in `NewsBands`, held in `NewsBook` files in `src/data/news/` - one folder of words rather than §8.3's bundling ([D199](decisions.md)); a trader's own chatter is read from its file. `NewsSelector` and `YearNews` in `src/sim/`: a pure function of the history with its own generator seeded from the year's draws, so every peer chooses the same lines, nothing goes on the wire and no price can move; least-drawn-first as the bag; specific lines first; an empty slot shows nothing ([D200](decisions.md)). Whispers drawn when their trigger can hold, then rolled against their truth chance ([D201](decisions.md)); the band edges, with the surprise measured against damped, retained growth and NEAR_SPLIT at 260 for this mode's split ([D202](decisions.md)). Shown on the Market tab (headline, WHISPERS), Industries (NEWS), Company (NEWS, whispers, chatter under NPC ACTIVITY) and the DESK page (CHATTER) ([D203](decisions.md)). Seven books of placeholders, each line its category and conditions; the authoring guide in [development.md](development.md). `test_news.gd` (23 tests) and five more in `test_stalkleheads_screen.gd`; the golden hash did not move. **Scope:** key personnel not built (§14); the five new tickers and all words are the owner's; checked by hand as section S of [manual-testing.md](manual-testing.md), passed. **Then** ([D205](decisions.md), [D206](decisions.md)): whispers rebuilt to foretell next year (§8.4) - next year's earnings drawn a year early and kept in the snapshot, each whisper's outcome bent by one of five sources, about a company or an industry, heard from the end of year 1 (D207), with a VIEW HISTORY panel showing what came of each; `test_news.gd` 26 tests, the screen tests 70; checked as section T. **Then** ([D208](decisions.md)-[D214](decisions.md)): market news (headline, event text, an effect on a company or an industry) in place of the headline and the special events; `requires` follow-ups; the EARNINGS line and IN THE NEWS, with the 80 base events of the eight shared companies ported; the INDUSTRY REPORT; the squeeze as a meme stock, shown as a percent with FLAGGED or SQUEEZED; squeeze and crash whispers; ticker-and-name clicks, an industry chart of every year that fits. 1,437 tests; P4 fails as shipped (§ "After market news and the meme-stock squeeze"); to be checked as section V. Decisions D199-D214 | Medium, mostly writing | No | 5, 6, 11 |
| **S9 — Balance, properly** | Play it. Tune. Repeat | Unbounded | Yes | 13 |

**S0 comes first because it is the cheapest insurance in the plan.** Every later phase
claims not to touch the base game; S3 is the one that actually moves code inside
`YearResolver`. A guard written after the move can only prove the base game matches
itself as it now is.

**S2 starts before S1 is finished, not after.** The balance tool is what turns "does
this feel right?" into a number, and this document exists because a throwaway version
of it overturned three designs. Building it late means tuning blind.

**S4 is no longer optional polish.** In the first draft the desk was flavour and could
have been cut. It is now how the crowd is read (§5.2), one of the four routes to winning
that §2.1 measured, and an input to every price. A StalkleHeads match without it is a
different game from the one the numbers describe.

**Every phase before S7 runs headless**, so the economy can be built, tested and tuned
with no screen at all, which is what [CLAUDE.md](../CLAUDE.md) requires of the
simulation layer. The first time a person can *play* StalkleHeads is the end of S7.

**S9 is not a formality.** [§13](#13-size-and-risk-honestly) says why it is the
largest risk in the whole proposal.

The last column is which open questions ([§14](#14-open-questions-for-the-owner)) a
phase needs answered before it can finish. None blocks S0 or S2, and S1 can begin on the
recommendations as written.

Each phase ends with the documentation gate in [CLAUDE.md](../CLAUDE.md): the plan,
the architecture, the decisions, the rules, the testing notes and the glossary. The
glossary will need a lot — "regime", "multiple", "fair value", "sentiment", "the
ledger", "event carry", "flow", "standing", "payout ratio", "short interest", "the
desk" and "ticker" all mean nothing to a newcomer.

---

## 12. Testing

### 12.1 What is automatic

The design is deliberately shaped so that almost all of it is. The five properties of
§1 first:

| Property | Test | Where it runs |
|---|---|---|
| **P1** the ledger balances | For every company in every year of a many-seeded run, the ledger's terms — fair-value change, event carry, flow — sum exactly to the realised price delta | GUT suite |
| **P2** reading pays | The strategy table of §2.1: the readers' win shares against `RANDOM`'s, asserted against a band rather than a number | Balance tool (S2) |
| **P3** the no-reader survives | `RANDOM`'s median net worth within a stated fraction of the leader's | Balance tool |
| **P4** no dominant rule | The leading strategy under 30% **at the default ten-year length**. The 25-, 50- and 99-year figures are recorded and reported, not asserted, because §1 scopes P4 to the default | Balance tool |
| **P5** the base game is untouched | A seeded 99-year base-mode match's history, hashed, identical before and after StalkleHeads exists. **Written in S0, before anything else changes** | GUT suite |

**Why P2–P4 are not in the GUT suite.** Each is a distribution over hundreds of whole
matches, which is minutes of run time for a suite that currently takes seconds. They run
in the balance tool, which is part of every phase from S1 on. The suite carries a small
fixed-seed smoke version — a few dozen matches, with loose bands — so that a change
which breaks balance badly fails somewhere a person will see it without remembering to
run anything.

P5 deserves emphasis: it is the single most valuable test in the whole proposal,
because [CLAUDE.md](../CLAUDE.md) records that **everything written down and nowhere
else has drifted** — eighteen signal connections in a forbidden style, over weeks,
unnoticed, by the author of the rule. "StalkleHeads does not touch the base game" is
exactly that kind of promise, and it needs a check, not a sentence. It matters more now
than in the first draft, because S3 moves code out of `YearResolver` (§10.2).

Then the mode's own rules:

- **Regimes** — every matrix row sums to 100; the stationary distribution sits in a
  stated band; ageing fires after the stated number of years; quality biases the right
  way; recovery lets a `DISTRESS` company out.
- **Earnings** — revenue and margin move as specified; margin moves one third of the
  way; the long-match damping ladder applies above 19 and 49 years.
- **The mood and sentiment** — the mood is `BULL` exactly when the index move is
  positive; sentiment is clamped to ±20 and carried into next year; and **the derived
  bull rate stays in a stated band over many seeds** (it measures 55.4%). That last one
  is the guard on the feedback loop of §3.1: a future edit to either sentiment gain can
  quietly inflate the whole market, and nothing else would notice.
- **No circularity** — changing this year's index move after the fact changes nothing
  computed before step 7 of §4. This is the test that catches the one change §4 says
  would break the design: something reading this year's mood before prices exist.
- **Valuation** — the multiple composes from its four terms (base, sentiment, standing,
  regime premium) and clamps to 4–30; fair value is the product.
- **The two truncations** — the posted price is `int(fair_value + event_carry + flow)`
  and the dividend per share is `int(earnings_per_share × payout_ratio)`, truncated in
  those two places and nowhere else, and every money figure that leaves the
  sim layer is an `int`.
- **Flow** — clamped to ±5% of fair value; persists at 0.70 a year; a player's share
  and an NPC's share count identically; a desk that buys every share it can still cannot
  move a price past the clamp. **The clamp value is asserted as a constant**, because §2.4
  measured that raising it to 18% restores the dominant strategy in full.
- **The split is value-neutral** — above 300 the price halves, shares double, earnings
  per share, `event_carry` and `flow` halve, and the identity still holds. This one is
  worth writing first; it is the design's coherence check.
- **Dividends** — `int(earnings_per_share × payout_ratio)`, where the ratio is the
  company's policy scaled by its regime; `DISTRESS` pays nothing; a policy of 0 never
  pays; a policy of 35 reproduces the single regime table exactly; the retention factor
  applies to positive revenue growth only.
- **The index** — tracks its constituents; a constituent's split does not move it; a
  bankrupt constituent contributes −100% once and then drops out; it cannot fail unless
  all of them do.
- **The event** — drawn before prices from the bag of last year's mood, the bull bag in
  year 1 (§10.2); an event at a bankrupt target fires if it carries an industry or
  market effect and is skipped if it carries only a company delta (§4).
- **The NPC desk** — same seed, same positions; traders act in sorted id order; the
  draw count per trader per year is fixed regardless of the decision; no trader appears
  in `state.players` or affects the ready gate. The existing
  `test_the_same_seed_reproduces_a_whole_match` in `test_year_resolver.gd` is the
  pattern, and needs a StalkleHeads sibling that asserts the desk is identical too.
- **Foreshadowing is real** — the squeeze event's probability rises when
  `HIGH_SHORT_INTEREST` is set and not otherwise.
- **The wire** — encode, decode, re-derive every readout, compare with the host's;
  nothing in the payload is an `Object` (the existing `test_state_sync.gd` already walks
  the payload asserting this, and it must keep passing); a snapshot naming an unknown
  industry or trader is refused.
- **Content** — the validator catches an unresolvable industry id, an industry with
  fewer than two members (and reports one with fewer than three), a missing or
  duplicated ticker, a bad trigger name and an out-of-range `truth_chance_percent`; bags
  do not repeat until exhausted; a category with no match renders nothing.
- **Layout** — each tab measured headlessly at 640×360, asserting columns align and
  nothing overflows. The project's existing practice is to *measure* layout rather than
  read it — a throwaway script that instantiates a screen, forces a size and prints
  every computed rect, which is how "the name column has 199px and needs 289px" was
  found. The column table in §7.2 is what it checks against.
- **Grouping and sorting** — sorting reorders rows within an industry and never across
  one; collapsing and sorting change nothing in `GameState`, so a client that collapses
  every group sends and receives exactly what one that collapses none does.
- **Charts** — a chart is a string, so assert the string.

And the existing test worth extending rather than copying:
`test_what_is_on_screen_matches_a_headless_simulation_of_the_same_seed` in
`test_gameplay_screen.gd` already pins the board against a headless run of the same
seed. A StalkleHeads sibling is the single best end-to-end guard available.

**What the balance tool cannot tell you.** It plays strategies, not people. It has no
idea whether reading the desk *feels* like reading people, whether a twelve-line digest
is read or skipped, or whether a ten-year match with four tabs is too slow for a party.
Those are S9's, and §12.2's last item.

### 12.2 What needs two Steam accounts

The same things that already do ([manual-testing.md](manual-testing.md)), plus what
this mode adds:

- A **host migration mid-match** in a StalkleHeads game, confirming the new host
  continues the same market — same regimes, same desk positions, same `flow` carried
  into the next year, same next year.
- A **rejoin** into a StalkleHeads match in progress, confirming the full fundamentals
  history arrives and the charts are complete rather than starting at the rejoin.
- An **away player** ([D110](decisions.md)) in a StalkleHeads match, confirming the
  desk keeps trading and the market keeps moving around them.
- The **lobby browser row** showing the mode, including an older-build lobby with no
  `mode` key showing none (§9.4).
- The **payload size** of a long match's welcome, measured on a real connection rather
  than estimated. §9.2's figures are estimates, and the desk is about three quarters of
  them.
- **The pace.** Whether four tabs in a party game is a good idea cannot be tested. It
  needs friends, a 10-year match and somebody watching whether anyone is bored.

When these are written into [manual-testing.md](manual-testing.md) they follow its
existing form: numbered steps, one action each.

---

## 13. Size and risk, honestly

### 13.1 Size

**This roughly doubles the conceptual surface of the project.** Not the line count
necessarily, but the number of things a newcomer has to understand.

| Layer | Now | Added |
|---|---|---|
| `src/sim/` | 16 files | ~11: fundamentals, regimes, industry state, valuation, the earnings year resolver, the shared year settlement, index, NPC state, NPC desk, news selector, the ledger |
| `src/data/` | 9 scripts, 10 stalk resources | 13 company profiles (1 or 5 of them new companies, §3.2.3), 4 or 6 industries, ~24 traders, 6 content categories and their resources |
| `src/ui/` | 2 screens, 17 widgets | A tab host, 4 tab screens, a chart widget, a ledger widget, ~6 row widgets |
| `tests/unit/` | 40 files, 929 test functions | Several hundred more, on the above |

The 929 existing test functions should see **no changed assertions** — that is the
acceptance criterion for "additive", and P5 is how it is checked. The one existing file
that changes shape is `year_resolver.gd`, which loses its back half to
`YearSettlement` (§10.2); its tests call `advance_year` and should not notice.

### 13.2 The risks, worst first

**1. Balance in long matches.** The default ten-year match meets P4 at 22.2% on the
approved roster, with seven of ten strategies in contention (§2.6), so the headline risk
from the first draft is **closed**. What remains is the gradient with match length:

| Match length | Leading strategy | Win share |
|---|---|---|
| 10 years (default) | `LOWPE` (`TREND` 22.0%) | 22.2% ✓ |
| 25 years | `LOWPE` | 47.2% |
| 50 years | `LOWPE` | 78.4% |
| 99 years | `LOWPE` | 88.0% |

§1 argues this is partly intrinsic — compounding means any real edge dominates a long
enough match, and the base game escapes it only by having no edge — so the question is
how much to flatten it rather than whether to. Two levers are identified and **neither
is measured**: scaling the `flow` clamp down with match length (§3.10, worth 18 points
at 25 years on its own), and damping the valuation premium in long matches as well as
the growth bands. A third, raising the `truth_chance` on whispers so deep reads are less
reliable, is cheaper but blunter.

The first draft's three candidate remedies are worth recording as resolved: **narrowing
the premium spread worked** (63.7% → 27.0% at 25 years, §2.2) and is now in the design;
damping growth in long matches **did not** (tested at ×0.50, ×0.30 and ×0.20 over
99-year matches, all between 77% and 85%), which is what pointed at compounding rather
than growth rates as the cause.

**This is still the mode's main risk and S9 is still a phase, not polish** — but it is
now a question of tuning a known gradient rather than of whether the model works at all.

**2. Pace.** Four tabs of financials in a game played with friends, once a year, with
a ready-up gate. §6 is the defence — the digest panel, the tiers, the guarantee that
nothing is time-critical — and I believe it, but it is a belief. The honest mitigation
is that the mode is optional: a group that finds it slow plays the base game, which is
the whole reason the brief's first constraint is additivity.

**3. The mode could become a lookup table.** Related to 1 but distinct: if the
analysis has a single right answer, the mode is homework with a solution. The
protections are that the mood is unforecastable, the industry layer adds a second
unknown, whispers are only sometimes true, and the regime's *remaining duration* is
never published — only its odds. Whether that is enough is a play question.

**4. State size over 99 years.** §9.2 believes it is solved by design, but the
numbers in it are estimates and not measurements. It is cheap to get wrong quietly
(nobody plays a 99-year match until somebody does) and cheap to measure early.

**5. Two games to maintain forever.** Every future change has to be considered twice.
A new stalk needs a profile as well as a stat block; a new event may need an industry
effect; the glossary doubles. This is the permanent cost of the first constraint and it
is worth saying out loud once.

**6. Scope.** This is larger than any single phase of the port was, and the port is
finished and shipped. It is a second project wearing the first one's clothes.

### 13.3 What it does to the base game

If the design holds: two changes, listed in §10.2, neither touching a rule. The base
game gains a mode flag that picks its resolver at match start, and its resolver hands
loans, net worth and the game-end check to a shared class instead of doing them inline.

If the design does not hold, the failure mode to watch for is the one every "additive"
feature has: a clause somewhere in the shared pipeline that asks *which mode is this?*
The moment `YearResolver` or `TradeRules` contains `if mode ==`, the modes have stopped
being additive and started being entangled — and that is the point at which to stop and
redesign the seam rather than add a second branch.

---

## 14. Open questions for the owner

**Answered by the owner on 2026-11-21.** The numbers are kept so that references
elsewhere in this document still resolve. Where the answer was "take the
recommendation", the recommendation is what is recorded.

| # | Question | Decision |
|---|---|---|
| 1 | Fold the HELD column into the base game's board too? | **No.** The base board is left alone |
| 2 | More than one loan in StalkleHeads? | **A `GameSettings` toggle**, off in the base game, on in StalkleHeads |
| 3 | Dividends from earnings rather than authored figures? | **From earnings — with a per-company dividend policy**, added at the owner's suggestion (§3.10a) |
| 4 | What does the index pay? | **The average of its constituents' dividends**, which follows from 3 |
| 5 | Option A or option B on industries? | **B, six industries of three**, with the owner's assignments and placeholder companies (§3.2.3) |
| 6 | Are the industry assignments right? | **The owner's, in §3.2.3.** Teamsters Pension Fund, Mafia HUD Scam and Landlords United are Financial Services |
| 7 | Does Yearly Change include the event in this mode? | **Yes**, and the ledger breaks it down. A deliberate difference from the base game |
| 8 | Is the earnings regime named on screen? | **Yes** ("SLOWING, 2nd year") |
| 9 | Mark a company as cheap or expensive? | **No.** A single marker character stays in reserve if play shows tier 2 is too hard to reach |
| 10 | Can a player short a stalk? | **Not at first.** Players bet against others by reading the desk and short interest. A capped short is a candidate after first play |
| 11 | How many NPC traders? | **About twenty-four**, three per strategy, shown by strategy on the board and by name on the Company tab |
| 12 | A "flatten groups" toggle? | **Not in the first build**; added if players ask |
| 13 | Flatten 99-year matches toward parity? | **Deferred to after first play** (S9) |
| 14 | Which event bag before the mood exists? | **Last year's mood**, the bull bag in year 1 |
| 15 | What happens to Unionized Submissives LLC? | **Consumer Goods**, in place of the second placeholder |
| 16 | Is the market model itself approved? | **Yes.** The price is `fair_value + event_carry + flow`, the mood is derived from what the market did, and NPC order flow is capped at 5% of fair value (§2) |

**Content that is placeholder until the owner writes it**, decided as placeholders
rather than left open:

- **Companies not yet created** are named by industry and letter — *Transportation
  Company A*, *Technology Company A* — with temporary tickers (§3.2.3).
- **News text** in all six categories of §8 is placeholder text that begins with its
  category, so a reader can tell at a glance which slot a line fills (§8.3).
- **Industry display names** are the owner's: Energy, Transportation, Financial
  Services, Consumer Goods, Technology, Food.
- **NPC trader names and chatter** are the owner's to write. Until then they are
  placeholders in the same style as the news.

### Still open

**None from S4.** Its measurement ([D167](decisions.md)) is closed: the SHORT target is
the highest P/E ([D169](decisions.md)), the squeeze ships at 25% / +25, and flow's cost
is accepted until S5 re-measures it ([D170](decisions.md)).

**Key personnel: asked for on 2026-11-22, not scheduled.** The owner wants a KEY
PERSONNEL section on the Company tab listing executives: a CEO and a Chairman of the
Board for every company, a CFO for most, and an industry-specific officer for some
(a technology company's CTO, for example). Each executive is named, with the names
supplied by the owner, and has a temperament matching a personality (risk averse,
innovator, a leader who pushes growth at any cost).

Executives can change. A board can fire one after poor results, or to signal a change
of course: a fast-growing company with a risk-averse CEO replaces them with an
aggressive one. That change is company news, and a signal to players about when to
buy or sell.

The owner's instruction is to table this until the current plan works, but keep it in
mind meanwhile. Its effect on the simulation is not yet designed. Questions to settle
when it is taken up:

- **What a temperament does.** It could do nothing and only foreshadow. Or it could
  be an input, for example nudging regime transitions (§3.3), the payout policy
  (§3.10a) or the multiple (§3.4). As an input it has to pass the §1 properties and
  the balance tool, like any other.
- **What triggers a change.** Results, a regime change, or a draw from the event bags
  (§8). It needs one injected RNG draw per decision, in a fixed order, so the
  replay on the client (§9.1, D178) stays exact.
- **What travels.** Each company's current officers and a record of changes, as
  inputs (§9.1).

**Prices within the year: asked for on 2026-11-23, not scheduled.** The owner wants
the simulation to work out figures between the years, every month say, so the
Company tab's price chart can show a candle a month instead of a year (D188's
candles have no wicks because a year has one price). It changes the simulation, so
it is a task of its own. Questions when it is taken up:

- **What moves monthly.** Only the price, as a path drawn between this year's and
  next year's (cheap, but the months would be decoration), or the earnings
  pipeline itself, run in smaller steps (real, but every rule tuned per year -
  regimes, margins, events, flow - would need restating).
- **What players see when.** Whether trading stays once a year, with the months as
  history, or becomes monthly.
- **Determinism.** Every monthly figure must come from the match's injected RNG in
  a fixed order, so a client's replay (§9.1, D178) stays exact, and the balance tool
  must re-measure.

**NPC thoughts: a stretch goal, asked for on 2026-11-22, not scheduled.** Resting the
mouse on a desk trader's name would show a thought: a line about the market, a
company or life, drawn at random from lines tagged for how that trader feels. A
panic trader in a bear year draws from lines tagged "panic" or "anxious", say. The
lines are the owner's to write, and there would need to be many, so this waits on
that content. Until then a trader's name has no tooltip: it would only repeat the
name ([D187](decisions.md)). Questions when it is taken up:

- **The tags.** By strategy, by the trader's situation (bought, sold, short, hit by
  a squeeze), by the year's mood, or a mix.
- **The draw.** A thought is presentation, so it must not take a draw from the
  match's RNG and shift the simulation. It needs its own generator, or a pick
  derived from the seed, year and trader, so every player sees the same line.
- **Where it shows.** The Company tab's NPC ACTIVITY names, the side panel's desk,
  or both.
- **Chatter.** Each trader already carries chatter: one line per action (bought,
  sold, shorted, covered, held), placeholders, shown since S8 under NPC ACTIVITY and on the DESK page (D203).
  Thoughts are a different thing - how a trader feels, not what it did - but could
  live beside chatter in the trader's resource.
- **Content.** Names, temperaments and the news lines are the owner's to write.

Until it is designed, nothing in S8 or S9 should assume a company has no officers;
the Company tab has room below NPC ACTIVITY.

**Messages: what was left out on 2026-11-23.** Private messages between players
were built ([D192](decisions.md), [D193](decisions.md)). Not built, on the owner's
word, and waiting on design or content:

- **Messages to and from NPCs.** A PLAYERS / NPCS switch on the MESSAGES tab's list;
  desk traders replying, or starting a conversation themselves. It needs either
  written lines (the owner's to write, like the trader chatter and the NPC thoughts
  above) or a chat-bot feature, and a rule for when an NPC speaks. Whatever an NPC
  says must not take a draw from the match's RNG.
- **Key personnel leaking hints** about special events, as messages. This hangs on
  the key personnel entry above, which is not yet designed: who the officers are
  comes first, and then which of them talk, to whom, and how reliable a hint is
  (an honest hint is foreshadowing, so §5.3 applies: it must read a real state
  variable).
- **Messages in the base game.** The networking and the book are on `GameSession`,
  so only a place on the base screen is missing, which has no tab strip (D192).
- **Keeping blocks beyond one match** ([D196](decisions.md)). A block lasts as long
  as the book, so a rejoin or a rematch unblocks. Keeping it would mean
  saving it on disk against something that outlives a match, such as a Steam id.

Every question raised by this document has an answer. What remains is
content the owner will write over time — the five placeholder companies, the trader
names and every news line — and the measurement in S2, which may reopen a number but
not a decision.

---

## 15. Decisions this document proposes

**Accepted by the owner on 2026-11-21**, together with the market model (§14,
question 16), but not yet in [decisions.md](decisions.md). That file records what was
decided *for the code that exists*, so each of these goes in as a numbered entry in the
phase that builds it (S1 recorded A, A2, B, B2, D, D2, E, E2, P, P2, Q, R and R2 as D136-D143; S4 recorded L as D162-D163 and M as D165). The reasoning is written here
so that the entry can be copied rather than reconstructed.

| Proposed | Summary | Section |
|---|---|---|
| A | **The price is an identity, not a convergence.** Fair value plus the undecayed remainder of announced events. No hidden noise, because an anchor the player can compute plus noise is a mechanical arbitrage | §2.2, §2.3 |
| A2 | **Any bounded, mean-reverting quantity in the price is an arbitrage**, however deep. Three were found: convergence to fair value, mean-zero noise, and the valuation premium. Check any future addition against this | §2.2 |
| B | **Earnings are the input, P/E is a readout** — and P/E is never stored at all, only computed where it is displayed | §2.5, §3.7 |
| B2 | **Money is `int`, ratios are `float`, with two documented truncations, where a ratio becomes a price and a dividend.** The fixed-point scheme in the first draft is dropped; this is the pattern `LoanRules` already uses | §3.7 |
| C | **The mood is derived, not rolled.** Bull or bear is a report of what the index did; last year's move is carried into this year's multiples as sentiment, which is what keeps it non-circular. The derived bull rate lands at 55.4% without being tuned toward the shipped 58.3% | §3.1 |
| D | **Five earnings regimes with a published transition matrix**, plus ageing on good runs and recovery from the floor — the Animal Crossing turnip model in a suit | §3.3 |
| D2 | **The valuation premium spread is 40% of what intuition suggests**, measured. It is the difference between a 64% dominant strategy and a 27% one over 25-year matches | §2.2, §3.3 |
| E | **A split needs no new rule**, because doubling shares outstanding halves earnings per share and therefore halves fair value. The split is value-neutral by construction. The threshold is this mode's own, at 300 | §3.6 |
| E2 | **StalkleHeads sets its own scale and inherits no base-game number** it does not need: not the starting price, not the split threshold, not the stat block, not the dividends, not the mood weighting. Only the names, the descriptions and the idea of buying stalks are shared | §3.2.2 |
| F | **One bankruptcy pass, not two**, because there is one price-setting step. The two must-preserve orderings are untouched | §3.6, §4 |
| G | **BERRY BONDS is unchanged and becomes the yardstick**; its 3% yield is where the 12.5× base multiple comes from | §3.8 |
| H | **Mutuals is an index of pre-split moves**, which is how the divisor problem is avoided | §3.9 |
| I | **StalkleHeads has its own year pipeline, sharing the back half**, rather than hooks in the shared resolver — because the revised year reorders steps, and hooks would need `if mode ==` to do it. Replaces the first draft's `MarketModel` | §10.2 |
| I2 | **In StalkleHeads the event is drawn from the bag of last year's mood**, since this year's does not exist yet; the bull bag in year 1 | §10.2 |
| J | **Derived figures are not sent; inputs travel and the receiver recomputes** — the sibling of the existing "definitions are not sent" rule, and what makes the 99-year payload affordable | §9.1, §9.2 |
| K | **Per-year history rows are `PackedInt32Array`, not `Dictionary`**, because dictionary keys are most of the payload | §9.2 |
| L | **NPC traders are published, deterministic, and not players.** Sorted order, fixed draw count, never in the ready gate | §5 |
| M | **Foreshadowing is a real state variable or it is not foreshadowing.** Short interest exists; the news reports it; the event weighting reads it | §5.3 |
| N | **Charts are text**, built from Terminus's eighth-block ramp — measured, not assumed | §7.6 |
| O | **A content category with no match shows nothing.** No generic filler line | §8.2 |
| P | **An industry needs three members, and two is the hard floor** — because a bankruptcy must not be able to reduce an industry to one mid-match. **Six industries of three, decided 2026-11-21** | §3.2.3 |
| P2 | **`industry` is a `StringName` resolved against industry resources, not an enum**, so an industry can be added as a file; the content validator is what catches a typo | §3.2.1 |
| Q | **Order flow ships, clamped at 5% of fair value, persistent rather than reverting, and published in the ledger.** Measured as free at the default match length and costly at 18% | §2.4, §3.10 |
| Q2 | **A price term driven by NPC flow amplifies whatever rule the largest NPC cohort follows**, so the clamp and a heterogeneous desk are both load-bearing rather than decorative | §2.4 |
| R | **Dividends are a payout ratio of earnings**, not an authored figure by mood. **Decided 2026-11-21** | §3.10a |
| R2 | **Each company has a dividend policy, and paying out more slows its growth**, so a high payer is a different stock rather than a better one | §3.10a |
| S | **Tickers are shown on the board.** The field has existed and been populated since the port's content was authored, for exactly this view | §7.2 |

---

## Appendix A — the balance probe

Every number in §2 and §13.2 came from a throwaway reference implementation,
not from reasoning. It is worth knowing what it is and what it is not.

**What it is.** A single Python file implementing both market models with integer
arithmetic matching GDScript's truncation, the shipped stat block from
[game-rules.md §3](game-rules.md), the 7/12 mood weighting, the 10% contrarian roll,
long-game softening, one event a year, splits above 150 rounding up, bankruptcy at or
below zero, dividends by mood, and eight player strategies run over 600 seeded matches
at two match lengths.

**There are two versions, and both are worth keeping.** `model_probe.py` is the first
draft's: integer fixed-point, mood as a 7/12 roll, every company starting at 100, no NPC
desk. `model_probe_v2.py` is the one every number in the current document comes from:
floats for ratios, derived mood and sentiment, a desk of 24 traders, the `flow` term with
a sweepable clamp, 13 companies in 6 industries, and dividends from a payout ratio.
`model_probe_v3.py` is v2 on the approved roster — 18 companies, per-company dividend
policies, the growth trade-off and an `INCOME` strategy — and is the source of §2.6 and
of every current figure outside §2.1–§2.4. The first is kept because the comparison
between them *is* the argument in §2.2 and §2.4.

**Where they are.** Outside the repository, in this group of sessions' shared notes
folder, as `stalkleheads/model_probe.py`, `model_probe_v2.py` and `model_probe_v3.py` with their outputs
beside them. Deliberately not committed: they are measuring instruments, not project
code, and **everything they compute is specified in prose and tables in §3, so losing
them loses nothing but the convenience.** S2 in the build plan replaces them with a
proper `tools/` script in GDScript, run against the real simulation rather than a
parallel implementation of it.

**What they are not, and these matter.**

- **A parallel implementation can agree with itself and still be wrong.** The real
  version must run against `src/sim/` or it proves nothing about the shipped model.
  This is the single biggest caveat on every figure in this document.
- **Player strategies rebalance completely every year at no cost**, which no real
  player does and which exaggerates every edge measured. A real player holds positions,
  hesitates, and buys the company with the funniest name.
- **There are no loans**, so leverage is absent from every measurement — which matters
  more now that question 2 proposes repeat borrowing.
- **The index is faked.** v2 has no index instrument; the `INDEXER` trader buys an
  ordinary company as a stand-in. So nothing here tests §3.9.
- **The news, whispers and foreshadowing are absent entirely.** Events fire with a
  random target and a mood-leaning magnitude; no trigger, no `truth_chance`. So §8 is
  unmeasured.
- **"Mean yearly change" counts a split's halving as a movement**, which inflates the
  figure for every model equally. Comparisons are sound; the absolute number is not a
  volatility measurement.
- **Parameters were tuned by hand across seven passes.** Enough to show the shape
  works; nowhere near enough to call it balanced.
- **Win share is a crude score.** It counts how often a strategy finishes first against
  eight rivals playing simultaneously, which is not the same as how a strategy does
  against three friends. It is the right *shape* of measurement for P4 and the wrong one
  for predicting a real table.

### The balance tool, and how its numbers compare with the probe's

**The probe has been replaced (phase S2, 2026-11-21).** `tools/balance_report.gd` plays
seeded matches over the real `src/sim/` classes and prints the §2.6 table; how to run
it is in [development.md](development.md), what it covers in [testing.md](testing.md).
In S2 it drove the year with a stand-in, `tools/balance/stand_in_year.gd`; since S3
it plays the real `EarningsYearResolver` (see the end of this appendix). Until S4 there
is no desk, so no `FOLLOW` and no flow by default. Its comparison target is therefore
the probe's **no-flow** ten-year run. Since S4 the desk, `FOLLOW` and flow are in,
on by default (the last section of this appendix).

**The raw comparison.** Ten years, 400 seeds each, no flow:

| Figure | Probe (no flow) | Tool | Cause of the gap |
|---|---|---|---|
| Leading strategy | `MOMENTUM` 21.0% | `TREND` 48.5% | The probe's `TREND` bug ([D146](decisions.md)) |
| `TREND` win share | 19.8% | 48.5% | D146 |
| `LOWPE` | 15.5% | 16.5% | Noise, after D132 raised it and the stronger `TREND` took wins back |
| `MOMENTUM` | 21.0% | 9.8% | Lost wins to the corrected `TREND` |
| `FOLLOW` | 10.0% | — | No desk until S4; its wins redistribute to the other eight |
| `BOND` median | 13,426 | 13,426 | None: the bond is deterministic |
| Bankruptcies per match | 0.37 | 0.66 | [D132](decisions.md): an event lands in full in its own year, so a large bear event kills a weak company more often |
| Splits per match | 2.10 | 2.00 | Noise |
| Mean yearly move | 21.05 | 21.27 | D132, slightly larger event moves |
| Bull-year rate | 56.8% | 55.2% | Noise |

**The check that explains every gap.** A copy of the probe (outside the repository,
like the probe itself) was given the tool's four differences one at a time. Ten
years, 400 seeds, no flow, win shares:

| Probe variant | `TREND` | `LOWPE` | `MOMENTUM` | Bankruptcies | Leader |
|---|---|---|---|---|---|
| As published | 19.8% | 15.5% | 21.0% | 0.37 | 21.0% |
| `FOLLOW` removed | 23.0% | 17.5% | 22.5% | 0.37 | 23.0% |
| + D132 event carry | 18.5% | 23.5% | 23.2% | 0.62 | 23.5% |
| + D146 `TREND` | 48.0% | 19.2% | 8.2% | 0.62 | 48.0% |
| + D147 index floor | 49.2% | 18.8% | 8.2% | 0.63 | 49.2% |
| **The tool** | **48.5%** | **16.5%** | **9.8%** | **0.66** | **48.5%** |
| The tool, 4,000 seeds | 47.3% | 17.5% | 10.2% | 0.61 | 47.3% |

With all four applied, the probe and the tool agree within sampling noise (about ±2.5
points of win share at 400 seeds) on every figure, at 25 years too (`TREND` 61.8%
against 58.8%, `LOWPE` 28.5% against 33.0%). **No gap is unexplained.** Two
implementations written separately, in two languages, agreeing once their known
differences are aligned is the evidence that S1's code does what the design says.
D130 (floats for revenue and profit) causes no gap, because the probe used floats
there too.

**What the comparison found: P4 fails.** The probe's `TREND` was weaker than the rule
§2.1 describes, so every P4 figure in §1 and §2.6 understated the leader. Measured
correctly:

| | 10 years | 25 years |
|---|---|---|
| The tool, no flow | `TREND` 48.5% | `TREND` 58.8% |
| The tool, flow from player trades only | `TREND` 45.0% | — |
| Probe, §2.6's setup (flow 5%, desk, `FOLLOW`), `TREND` corrected | `TREND` 46.2% | — |
| The same, also with D132 | `TREND` 40.0% | — |

**Nothing was tuned to close this.** It is [D149](decisions.md), open for the owner
and S9. The tool is what to re-run after any change.

### The sweep of candidate fixes (2026-11-22)

The owner asked for D149 to be answered by measurement before anything changed. Two
levers were swept with the balance tool's overrides ([D150](decisions.md)), which
change a number for one run and leave `src/sim/` alone:

1. **Price expected growth into the multiple.** The GROWTH premium alone raised from
   0.6 toward the first draft's 1.5 (`G0.9` to `G1.5`), and the whole published spread
   scaled by 1.5, 2.0 and 2.5 (`x1.5` to `x2.5`; 2.5 is the first draft).
2. **Make GROWTH runs less predictable.** GROWTH's stay chance lowered from 58 to 50,
   42, 34 and 26, the removed weight spread over the other columns in proportion to the
   published row (D150): 42 is `[42, 19, 28, 8, 3]`, 34 is `[34, 22, 32, 9, 3]`. As a
   variant, ageing raised from 10 to 15, 20 and 25 points a year.

Then combinations around the best single setting. No flow, as everywhere in S2.
"Contenders" is how many of the nine strategies win at least 4%. P3 is RANDOM's
median net worth over the leader's.

| Setting | Seeds | 10y leader | TREND | LOWPE | Contenders | Bull rate | Splits | Bankruptcies | P3 | 25y leader |
|---|---|---|---|---|---|---|---|---|---|---|
| **Published** | 4,000 | TREND 47.3 | 47.3 | 17.5 | 6 | 0.561 | 2.10 | 0.61 | 0.46 | TREND 58.2 |
| G0.9 | 400 | TREND 45.0 | 45.0 | 17.8 | 6 | 0.563 | 2.08 | 0.65 | 0.49 | TREND 53.5 |
| G1.2 | 400 | TREND 42.0 | 42.0 | 18.8 | 6 | 0.573 | 2.19 | 0.63 | 0.51 | TREND 46.3 |
| G1.5 | 400 | TREND 37.3 | 37.3 | 18.0 | 7 | 0.580 | 2.28 | 0.63 | 0.54 | TREND 43.8 |
| x1.5 | 400 | TREND 39.3 | 39.3 | 22.0 | 6 | 0.577 | 2.10 | 0.64 | 0.53 | LOWPE 48.3 |
| x2.0 | 400 | TREND 33.3 | 33.3 | 31.0 | 6 | 0.602 | 2.27 | 0.64 | 0.59 | LOWPE 71.3 |
| x2.5 | 400 | LOWPE 43.0 | 22.3 | 43.0 | 6 | 0.620 | 2.38 | 0.65 | 0.55 | LOWPE 84.5 |
| stay 50 | 400 | TREND 43.5 | 43.5 | 19.3 | 6 | 0.544 | 1.77 | 0.69 | 0.51 | TREND 51.3 |
| stay 42 | 400 | TREND 35.8 | 35.8 | 21.5 | 6 | 0.524 | 1.45 | 0.73 | 0.53 | LOWPE 42.0 |
| stay 34 | 4,000 | TREND 30.8 | 30.8 | 25.4 | 6 | 0.519 | 1.28 | 0.68 | 0.58 | LOWPE 47.5 |
| stay 26 | 4,000 | LOWPE 27.1 | 25.6 | 27.1 | 6 | 0.508 | 1.10 | 0.70 | 0.79 | LOWPE 51.8 |
| ageing 15 | 400 | TREND 43.3 | 43.3 | 19.8 | 6 | 0.531 | 1.66 | 0.72 | 0.51 | TREND 52.5 |
| ageing 20 | 400 | TREND 39.0 | 39.0 | 24.3 | 6 | 0.518 | 1.46 | 0.81 | 0.50 | LOWPE 49.8 |
| ageing 25 | 400 | TREND 36.0 | 36.0 | 24.3 | 6 | 0.512 | 1.27 | 0.84 | 0.53 | LOWPE 49.8 |
| stay 42 + ageing 15 | 400 | TREND 34.0 | 34.0 | 24.0 | 6 | 0.507 | 1.22 | 0.80 | 0.57 | LOWPE 45.3 |
| stay 42 + ageing 20 | 400 | TREND 32.3 | 32.3 | 25.8 | 6 | 0.496 | 1.10 | 0.86 | 0.57 | LOWPE 56.3 |
| stay 34 + ageing 15 | 400 | TREND 30.0 | 30.0 | 27.3 | 6 | 0.498 | 1.06 | 0.79 | 0.60 | LOWPE 53.5 |
| stay 42 + G0.9 | 400 | TREND 31.8 | 31.8 | 23.8 | 6 | 0.530 | 1.50 | 0.71 | 0.57 | LOWPE 47.3 |
| stay 42 + x1.25 | 400 | TREND 34.0 | 34.0 | 22.8 | 6 | 0.539 | 1.49 | 0.71 | 0.58 | LOWPE 49.3 |
| ageing 20 + G1.2 | 400 | TREND 32.5 | 32.5 | 24.5 | 6 | 0.534 | 1.62 | 0.78 | 0.57 | LOWPE 52.3 |
| stay 34 + G1.2 | 400 | LOWPE 26.8 | 22.8 | 26.8 | 6 | 0.526 | 1.33 | 0.74 | 0.69 | LOWPE 54.0 |
| **stay 34 + G0.9** | 4,000 | TREND 27.3 | 27.3 | 26.6 | 6 | 0.526 | 1.33 | 0.66 | 0.63 | LOWPE 52.1 |
| **stay 42 + G1.2** | 4,000 | TREND 27.9 | 27.9 | 25.4 | 6 | 0.544 | 1.63 | 0.64 | 0.62 | LOWPE 49.0 |

Sampling noise is about ±2.3 points of win share at 400 seeds and ±0.7 at 4,000.
That is why `stay 34`, at 28.3% over 400 seeds, failed at 30.8% over 4,000.

**What the sweep says.**

- **Three settings pass P4 at ten years over 4,000 seeds**, with no other strategy over
  30%: `stay 34 + G0.9` (27.3%), `stay 42 + G1.2` (27.9%) and `stay 26` (LOWPE 27.1%).
  None passes by much, so P4 is now a close thing rather than a comfortable one.
- **No single lever passes.** Widening the premium helps TREND only until LOWPE takes
  over. `x2.0` already puts LOWPE at 71% of 25-year matches, which is D2's original
  finding reproduced, and `x2.5` lets LOWPE lead even at ten years. Widening GROWTH's
  premium alone is safer for LOWPE but does not get TREND under 37%. Stronger ageing on
  its own bottoms out near 36%.
- **Every passing setting hands the lead to LOWPE at 25 years**, at 49-52%, against
  TREND's 58% today. That is lower than today, not higher, and §1 scopes P4 to ten years.
- **The market gets flatter.** Fewer GROWTH years mean fewer splits (1.1-1.6 against
  2.1), a bull rate of 51-54% (against 56%) and more bankruptcies at 25 years. BOND wins
  8-12% of ten-year matches, against 4.7% today.
- **P3 gets better everywhere.** RANDOM's median goes from 46% of the leader's to
  62-79%. But at `stay 26` it falls just below the starting 10,000 (9,825), so the
  player who reads nothing ends slightly down, and at `stay 34` it barely clears it
  (10,073).

**Which of these are design changes rather than tuning.**

- **Lowering GROWTH's stay chance changes §3.3's published matrix**, and with it the
  stationary mix that §3.3 states and `test_regime_rules.gd` asserts. GROWTH falls from
  19.8% of company-years to 15.1% at 42, 13.6% at 34 and 12.3% at 26. It agrees with
  §3.3's stated intent ("a good run cannot last forever"). At 34 or below, though,
  GROWTH would be the *least* sticky regime but one, and the matrix's bold diagonal
  would stop saying "growth persists".
- **Raising the GROWTH premium partly reverses decision D2** (§15), which narrowed
  the spread because of LOWPE. Raising GROWTH alone to 1.2, with the other four
  unchanged, kept LOWPE at 25% over ten years. That makes it a narrow reversal, but it
  is still the owner's decision, not a tuning step.
- **`stay 26` is a design change, not tuning.** It makes GROWTH a regime a company
  passes through rather than one it settles in, and its splits fall to about half
  today's.

**Recommendation, adopted by the owner on 2026-11-22 ([D151](decisions.md)):
`stay 42 + G1.2`.** GROWTH's row becomes `[42, 19, 28, 8, 3]` and its
premium 1.2, with the other premiums unchanged. Of the three that pass, it moves the
market least from the design's other figures: a bull rate of 54.4%, 1.63 splits per
match and bankruptcies unchanged at ten years. RANDOM still ends above its starting
cash, and six strategies contend. Its margin under the ceiling is about two points, so
**the flow term and the desk (S4) must be re-measured with it before it is called
settled**. §2.6 measured flow as costing about a point of P4.

### On the real pipeline (S3, 2026-11-22)

S3 deleted the stand-in and pointed the tool at `EarningsYearResolver`
([D161](decisions.md)). The one difference in the market is the event: the stand-in's
was the probe's shape on any living company, and the pipeline's is a real authored
event from `EventPool`, which only lands on the eight companies the base game ships.
Ten years, 4,000 seeds, no flow, published values:

| | Stand-in | Pipeline |
|---|---|---|
| Leader | `TREND` 27.9% | `TREND` 29.6% |
| `LOWPE` | 25.4% | 23.9% |
| Strategies winning at least 4% | 6 | 6 |
| Bull-year rate | 54.4% | 54.5% |
| Splits / bankruptcies per match | 1.63 / 0.64 | 1.69 / 0.69 |
| RANDOM's median over the leader's | 0.62 | 0.63 |

**P4 holds, by 0.4 points. Nothing was retuned.** The stand-in column is a re-run on
the same seeds just before it was deleted, and matches D151 exactly. S4's desk and flow
are the next re-measurement, and the margin is now too thin to absorb the point that
§2.6 measured flow as costing.

### With the desk (S4, 2026-11-22)

S4 added the NPC desk, FOLLOW, and short interest with its squeeze, and re-ran the
tool as §11 asks. The desk is the game's own (`EarningsMarket.desk`). FOLLOW is back
as the tenth strategy. `--flow` says what feeds the flow term: `all` is the desk and
the players, as in the game; `none` clears it, so the desk trades but its trading
reaches no price. `--no-squeeze` turns the squeeze off ([D166](decisions.md)). Ten
years, 4,000 seeds, published values:

| Flow | Squeeze | Leader | `TREND` | `LOWPE` | `FOLLOW` | Contenders | P3 |
|---|---|---|---|---|---|---|---|
| **all (the game)** | **on** | **`LOWPE` 41.8%** | 16.1 | 41.8 | 16.3 | 5 | 0.44 |
| all | off | `LOWPE` 28.9% | 24.1 | 28.9 | 15.5 | 6 | 0.63 |
| none | on | `LOWPE` 32.3% | 16.8 | 32.3 | 14.4 | 7 | 0.58 |
| none | off | `TREND` 23.7% | 23.7 | 19.7 | 13.6 | 7 | 0.64 |
| S3 (no desk, nine strategies) | — | `TREND` 29.6% | 29.6 | 23.9 | — | 6 | 0.63 |

**P4 fails as shipped, by 11.8 points.** The squeeze costs 8.6 points with no flow and
12.9 with it. Flow costs 5.2 points with no squeeze and 9.5 with it, against the one
point §2.6 measured. Both push `LOWPE`: the squeeze lands on the SHORT traders'
target, the slowest grower, which is usually cheap and on a low multiple, and the
VALUE traders, who buy what `LOWPE` buys, are the desk's richest at the end of half
of all matches. That second one is Q2 (§15) measured on the real code. **With the
squeeze off, P4 holds by 1.1 points.**

**The squeeze sweep**, flow on, through the tool's levers only:

| Chance | Size | Seeds | Leader | `TREND` | `LOWPE` | `FOLLOW` | Squeezes per match |
|---|---|---|---|---|---|---|---|
| **25 (published)** | **+25** | 4,000 | `LOWPE` 41.8 | 16.1 | 41.8 | 16.3 | 1.60 |
| 25 | +10 | 400 | `LOWPE` 32.8 | 21.3 | 32.8 | 19.5 | 1.84 |
| 25 | +5 | 400 | `LOWPE` 30.5 | 24.0 | 30.5 | 17.0 | 1.94 |
| 10 | +25 | 400 | `LOWPE` 32.8 | 21.8 | 32.8 | 20.0 | 0.70 |
| 5 | +25 | 400 | `LOWPE` 30.0 | 24.0 | 30.0 | 19.5 | 0.36 |
| 10 | +10 | 4,000 | `LOWPE` 31.5 | 22.5 | 31.5 | 15.6 | 0.76 |
| 5 | +10 | 4,000 | `LOWPE` 30.8 | 22.8 | 30.8 | 15.9 | 0.38 |
| **10** | **+5** | 4,000 | `LOWPE` **29.6** | 23.4 | 29.6 | 15.7 | 0.77 |
| **5** | **+5** | 4,000 | `LOWPE` **29.5** | 23.5 | 29.5 | 15.8 | 0.38 |
| 0 (= no squeeze) | — | 4,000 | `LOWPE` 28.9 | 24.1 | 28.9 | 15.5 | 0 |

Sampling noise is about ±2.3 points at 400 seeds and ±0.7 at 4,000. `--squeeze-chance=0`
reproduced `--no-squeeze` exactly at 400 seeds, as D166 says it must.

**Two settings pass, both by half a point:** chance 10% or 5% with a +5 squeeze. Every
setting still makes `LOWPE` the leader; the squeeze never helps anything else. A +5
squeeze is the smallest shipped event size, and at 5% a match of ten years sees one
about every two and a half matches.

**At 25 years** (1,000 seeds, flow on), `LOWPE` leads at 64.8% with the squeeze and
54.9% without, against 49.0% on S2's stand-in (D151). §3.10's long-match compounding risk is real and
still unsolved; P4 is scoped to ten years (§1).

**Nothing in `src/` was retuned.** The squeeze ships at the published chance and size
([D170](decisions.md)), once the SHORT target below had moved.

**The SHORT traders' target** (2026-11-22, [D167](decisions.md), [D168](decisions.md)).
Betting against the highest P/E instead of the slowest grower moves the squeeze off
what LOWPE holds. Ten years, 4,000 seeds, flow on:

| SHORT target | Chance | Size | Leader | TREND | `LOWPE` | HIGHPE | FOLLOW | Contenders | P3 | Squeezes / match |
|---|---|---|---|---|---|---|---|---|---|---|
| `slowest` (published then) | 25 | +25 | `LOWPE` 41.8 | 16.1 | 41.8 | 0.6 | 16.3 | 5 | 0.44 | 1.60 |
| `slowest` | 10 | +5 | `LOWPE` 29.6 | 23.4 | 29.6 | 1.6 | 15.7 | 6 | 0.64 | 0.77 |
| `slowest` | 5 | +5 | `LOWPE` 29.5 | 23.5 | 29.5 | 1.5 | 15.8 | 6 | 0.63 | 0.38 |
| `slowest` | off | — | `LOWPE` 28.9 | 24.1 | 28.9 | 1.2 | 15.5 | 6 | 0.63 | 0 |
| **`highpe`** | **25** | **+25** | **`LOWPE` 27.7** | 23.9 | 27.7 | 2.0 | 17.2 | 6 | 0.64 | 1.16 |
| `highpe` | 10 | +5 | `LOWPE` 28.2 | 22.4 | 28.2 | 1.1 | 18.2 | 6 | 0.64 | 0.47 |
| `highpe` | 5 | +5 | `LOWPE` 28.8 | 22.3 | 28.8 | 1.1 | 17.9 | 6 | 0.62 | 0.23 |
| `highpe` | off | — | `LOWPE` 29.4 | 21.8 | 29.4 | 1.0 | 17.7 | 6 | 0.62 | 0 |

**With `highpe`, P4 holds at every setting, the published squeeze included (27.7%).**
At 25 years `LOWPE` leads at 50.8% with it, against 64.8%. **The owner chose
`highpe`** ([D169](decisions.md)); it is the published rule, and a default run
reproduces the bold row. The measurements above it were taken with `slowest`.

**Flow's cost with `highpe`** (2026-11-22, [D167](decisions.md)). Ten years, 4,000 seeds:

| Flow | Squeeze | Leader | `TREND` | `LOWPE` | HIGHPE | FOLLOW | Contenders | P3 | Squeezes / match |
|---|---|---|---|---|---|---|---|---|---|
| **desk and players (the game)** | **on** | **`LOWPE` 27.7** | 23.9 | 27.7 | 2.0 | 17.2 | 6 | 0.64 | 1.16 |
| desk and players | off | `LOWPE` 29.4 | 21.8 | 29.4 | 1.0 | 17.7 | 6 | 0.62 | 0 |
| none | on | `TREND` 25.3 | 25.3 | 17.7 | 4.2 | 13.7 | 8 | 0.63 | 1.13 |
| none | off | `TREND` 23.1 | 23.1 | 19.7 | 2.6 | 14.5 | 7 | 0.64 | 0 |

- **Flow costs 2.4 points as shipped** (27.7 against 25.3), against 9.5 with the old
  target and §2.6's estimate of about one. With no squeeze it costs 6.3 (29.4
  against 23.1).
- **Flow still changes who leads**: TREND without it, LOWPE with it. That is Q2 (§15):
  flow amplifies the largest cohort, and the VALUE traders buy what LOWPE buys.
- **The squeeze works in opposite directions with and without flow.** Without flow it
  adds 2.2 points to the leader, TREND: a dear company is often a fast grower, which
  TREND holds. With flow it takes 1.7 points from LOWPE.
- **The tool overstates flow.** Its players sell everything and rebuy each year at no
  cost, and the game does not yet record players' trades into flow (S5). Re-measure
  when S5 does.

**Decided** ([D170](decisions.md)): the squeeze ships, and this flow cost is accepted
until S5.

### With players' trades in the game's flow (S5, 2026-11-22)

S5 made `MatchAuthority` record every player's trade into flow (D171) and re-ran the
tool at 4,000 ten-year seeds with published values. **`LOWPE` 27.7%, `TREND` 23.9,
`FOLLOW` 17.2, six contenders, P3 0.64, 1.16 squeezes a match**: the D170 row to the
digit. The tool already recorded its players' trades the same way, so the market did
not change; the game now matches what the tool assumed. P4 holds by 2.3 points and the
flow clamp stays at 5% ([D172](decisions.md)).

---

### After market news and the meme-stock squeeze (2026-11-27, D209, D213)

`tools/balance_report.gd`, ten years, 4,000 seeds, flow on. Sampling noise is about
±0.7 points.

| Squeeze | Leader | `TREND` | `LOWPE` | `FOLLOW` | Squeezes a match | P4 (ceiling 30%) |
|---|---|---|---|---|---|---|
| **as shipped, 5% a point** | `TREND` **32.8** | 32.8 | 18.9 | 16.5 | 0.60 | **fails** |
| 2% a point | `TREND` 31.1 | 31.1 | 19.9 | 16.6 | 0.65 | fails |
| 1% a point | `TREND` 29.9 | 29.9 | 20.3 | 16.8 | 0.68 | passes, by 0.1 |
| none (`--no-squeeze`) | `TREND` 28.2 | 28.2 | 21.2 | 15.9 | 0 | passes |

Two things moved. **Without any squeeze the leader changed** from `LOWPE` (27.7%
before) to `TREND` (28.2%): removing the special events took the base game's
event noise out of this mode's prices, and the market news ships with no
amounts. **The squeeze adds about 4.6 points to `TREND` at 5% a point**: a squeezed
price rises for years in a row, which a trend follower rides. Six strategies still
win at least 4%; `RANDOM`'s median is 0.55 of the leader's (P3).

**Not changed here.** The size is the owner's (D213); the numbers are recorded for
the owner to decide on. `--squeeze-size=N` is the lever.

## Appendix B — prior art, and what was taken from it

The brief asked what other games do and which patterns fit a party game.

**Animal Crossing's turnip market — the one that matters, and the origin of the
"stalk" joke.** Reverse-engineered by the community; the detail below is from
[mcpower's write-up](https://mcpower.github.io/turnips/info), which credits Ninji's
work. The mechanism:

- Turnips are bought once a week at 90–110 bells and sold across twelve half-days,
  each with its own price expressed as a **percentage of that buy price**.
- There are **four patterns**, each with a published shape. *Constantly decreasing*
  starts at 85–90% and falls 3–5% a half-day with no spike. *Decreasing, high spike,
  low* has a five-half-day spike peaking on the third at 200–600%. *Decreasing, spike,
  decreasing* peaks on the fourth at 140–200%. *Two decreasing dips* mostly sits at
  90–140% with two randomly placed dips.
- **Which pattern you get depends on the one you had last week**, by a published 4×4
  table of probabilities. From *constantly decreasing*, for instance, the next week is
  25%/45%/5%/25% across the four. The long-run shares work out at roughly 35/25/15/26.

**What makes it work, and what this design takes.** Four patterns is a number a human
holds in their head. The shapes are *qualitatively* different, so a couple of prices
narrows the possibilities. The transitions depend on history, so last week's
information is worth keeping. And underneath it is a tiny state machine with a table of
odds — the depth is in the *inference*, not the simulation.

That is the model for §3.3 exactly: five regimes instead of four patterns, a 5×5
transition table instead of 4×4, and inference from a published earnings series instead
of from the first few prices. The dressing is investor-grade; the machine underneath is
turnip-grade, on purpose.

**Capitalism Lab — the cautionary one.** It does generate financial statements players
analyse, which is nominally what the brief asks for, and it is the best available
warning about what that costs. Its own educational material calls it hard to master
"due to the complexity and many variables involved" and warns new players may go
bankrupt learning; a reviewer describes the complexity as expanding the closer you
look, puts the tutorial at an hour and a half, and says the finance tutorial almost
made them abandon the game. **For a party game played with friends in an evening, that
is the failure mode, not the target.** It is the direct source of §6's insistence that
the digest panel, not the tabs, is how the mode is actually played.

**Offworld Trading Company — the order-flow case, and why it is not this game's.**
Prices run on supply and demand, moved by what players produce and sell, with
non-player pressure only from the colony, surpluses and shortages. Community
documentation notes the price step scales with player count, and the designer's own
notes describe revisiting how much the market could be played at all. It works there
because it is a real-time game with continuous production — there is a flow for order
flow to be *about*. StalkleHeads has one trading window a year and between one and ten
traders, which is the thin-market problem §2.4 describes.

**Taipan! (1979/82) — buy low, sell high, by port, with random price jumps and
drops.** Worth noting for what it proves rather than what it teaches: a trading game
can be gripping on almost no model at all, if the *decisions* are tense. Its tension
comes from loan sharks, pirates and ship capacity, not from price formulae. A useful
corrective to the assumption that a better market model makes a better game — the base
game's loans do more for tension than any amount of this document's arithmetic.

**Stockpile** sets prices by bidding and moves them with action cards, which is closer
to order flow than to fundamentals; a reviewer singles out for praise that *all* its
stocks do something every round, so there is never a dead turn. §7.2's industry
grouping does the same job — every row on the board has a number that moved this year.
A 1970 Avalon Hill stock game drew the complaint that it "at times allows players too
great a control over the total market", which is §2.4's second objection, in a box, in
1970.

**Space Warlord Organ Trading Simulator** — added on the owner's suggestion, and the
most directly relevant of the two new references. Its market is dozens of commodities
with stats, and reviews describe the core loop as reading market trends to buy cheap and
sell at the right moment, **while rival traders undercut you** and random events (an
organ hauler's union striking) move things. Two things to take from it:

- **Rivals are named, visible and have their own behaviour.** That is this design's NPC
  desk, and the fact that a commercial trading game built its whole mid-game around
  watching rivals is support for the owner's instinct, not for mine.
- **It eases players in over several in-game days** rather than presenting the whole
  market at once. Worth considering for a first StalkleHeads match: the year digest
  (§6.3) is the mechanism, and showing fewer tabs in the first year or two would be a
  cheap version of the same idea. Not in the design; worth raising.

Reception is split on whether the depth is real — Metacritic's summary calls it a deep
trading game, the Guardian's review calls it closer to a frantic clicker — which is a
useful warning that a market with lots of numbers can still read as busywork.

**Cruelty Squad** — the market most unlike this one, and instructive for exactly that
reason. Community accounts say it runs in **real time** whether you are in a mission or
a menu, prices change between rooms, an item makes it run faster, and a "bullish" stock
is *likely* to rise without any guarantee. Fish you collect are sold through it.

What it shows is that **a market can be compelling with no analysable content at all,
purely as texture and tempo** — it is an atmosphere generator, and in that game it
works. It is the strongest available argument *against* this document's entire premise,
and worth holding onto for that: if StalkleHeads' analysis turns out to be homework, the
fallback is not a better model but a market that is simply fun to watch. The relevant
difference is the pacing. Cruelty Squad's market moves while you do other things; this
one moves once a year behind a ready-up gate, which is why §6.2's guarantee that nothing
is time-critical matters so much here and not at all there.

**Sources:**
[mcpower's turnip write-up](https://mcpower.github.io/turnips/info) ·
[Capitalism Lab educational use guide](https://www.capitalismlab.com/cap_lab_files/education/Capitalism_Lab_Educational_Use_Guide.pdf) ·
[Capitalism Lab educational resources](https://www.capitalismlab.com/educational-resources/) ·
[The Obscuritory on the Capitalism series](https://obscuritory.com/sim/capitalism/) ·
[Offworld Trading Company market wiki](https://offworldtradingcompany.fandom.com/wiki/Market?oldid=4901) ·
[Soren Johnson, OTC Designer Notes #2: Free Markets](https://www.designer-notes.com/otc-designer-notes-2-free-markets/) ·
[Taipan! on Wikipedia](https://en.wikipedia.org/wiki/Taipan!) ·
[Stockpile review, Gaming Trend](https://gamingtrend.com/reviews/looking-good-billy-ray-stockpile-review) ·
[Designing stock market games, BGDF](https://www.bgdf.com/blog/designing-stock-market-games) ·
[Space Warlord Organ Trading Simulator on Steam](https://store.steampowered.com/app/1507780/Space_Warlord_Organ_Trading_Simulator/) ·
[SWOTS review, Dread Central](https://www.dreadcentral.com/reviews/485653/space-warlord-organ-trading-simulator-review-buy-lobe-sell-eye/) ·
[SWOTS review, AV Club](https://www.avclub.com/space-warlord-organ-trading-simulator-review) ·
[Cruelty Squad on Steam](https://store.steampowered.com/app/1388770) ·
[Cruelty Squad money guide, KosGames](https://kosgames.com/cruelty-squad-how-to-make-money-12712/)

**A note on these sources.** Everything about Offworld Trading Company, Cruelty Squad
and Space Warlord Organ Trading Simulator above is **community-sourced** — fan wikis,
forum posts and reviews, not developer documentation. The Animal Crossing figures are
reverse-engineered but numerically precise and widely replicated. Treat the turnip
numbers as reliable and the rest as impressions.

---

## Appendix C — on the game-design-document skill

The owner asked whether `github.com/ityes22/game-design-document` was worth installing.
**The answer is no**, and the reasons are worth recording so the question does not come
back:

- It produces 40–80 page publisher-pitch documents with mandatory monetisation
  strategy, market sizing, competitive analysis and investor framing — none of which
  applies to a solo casual party game that is already on Steam.
- It runs a compulsory multi-batch discovery interview before writing anything.
- It ships unreviewed Python that generates `.docx` and `.pdf`.
- **Its own `CLAUDE.md` auto-loads if cloned into a project**, which would collide
  with this project's carefully maintained one.
- Seven stars, one maintainer, last commit eight months ago with the message "test".

**What was worth borrowing from its section list**, and is in this document:

| Borrowed | Why |
|---|---|
| A one-paragraph **high-concept statement** up front | The "what it is / what it is not" header. A reader who reads nothing else should know whether this replaces the base game |
| An explicit **scope boundary** section | Became the first constraint and §13.3 |
| A **risk register**, ordered by severity | §13.2. The most useful section in this document and the one most easily left out |
| **Open questions** as a numbered list the owner answers | §14 |

**What was deliberately left out**: monetisation, market sizing, competitive analysis,
target-demographic framing, art bible, audio bible, a marketing beat sheet, and page
budgets. This document is in the house style of
[game-rules.md](game-rules.md) and [architecture.md](architecture.md) instead: prose
that explains the why, numbers that are traceable, and explicit notes about what has
*not* been verified.
