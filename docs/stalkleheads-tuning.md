# StalkleHeads tuning — phase S9's working file

Phase S9 of [stalkleheads-design.md](stalkleheads-design.md) is "Play it. Tune.
Repeat." It has no end date. This file is where the loop lives:

1. **The baseline** — what the market measures as shipped, so any change can be
   compared with it.
2. **The agenda** — every balance lever the design leaves open, its current value,
   what it measures, and the balance-tool argument that sweeps it.
3. **Waiting for the owner** — the decisions only play, or the owner, can make.

How to run the tool is in [development.md](development.md) ("Measure StalkleHeads
balance"); what it can and cannot tell you is in [testing.md](testing.md). What to
watch for in play, and what to write down, is section AD of
[manual-testing.md](manual-testing.md).

**The rules of the loop.**

- A sweep changes a number **in the tool only**, through its lever arguments
  ([decisions.md](decisions.md) D150, D232). Nothing in `src/` changes until the
  owner picks a setting.
- When the owner picks one, it is changed in `src/sim/` as an ordinary change with
  its tests, recorded as a decision, and the baseline below is re-run and replaced.
- The golden hash (`test_golden_history.gd`) must stay green and is never re-pinned:
  StalkleHeads may not change the base game.
- **Any change to the market voids the figures here.** Market news (D209) and the
  squeeze (D213, D220) each changed every seed's match. After such a change, re-run
  section 1 before trusting anything below it.
- Compare like with like. A 1,000-seed run is compared with a 1,000-seed run on the
  same seeds, never with the 4,000-seed baseline: the seeds differ, and so does the
  noise.

**How big the noise is.** A win share measured over N matches moves by about
±2.3 points at 400 seeds, ±1.4 at 1,000 and ±0.7 at 4,000 from sampling alone. A
difference smaller than that is not a result. For example, the published market
measures `TREND` 31.1% over seeds 0-3,999 and 29.4% over seeds 0-999. It is the same
market, measured on a different sample.

---

## 1. The baseline (2026-11-27, after D233)

Published values, flow from the desk and the players, the squeeze on. Market news
(D209), the meme-stock squeeze (D213), the squeeze of no fixed length (D220) and the
squeeze at 4% a point (D233) are all in. The ten-year table is the D233 run; the
comparison column and the long matches were measured at 5% a point, just before.

### Ten years, 4,000 seeds

| Strategy | Median net | Mean net | Win share |
|---|---|---|---|
| HOLD | 10,991 | 11,462 | 0.1% |
| LOWPE | 15,707 | 21,281 | 20.1% |
| HIGHPE | 12,810 | 14,544 | 2.2% |
| **TREND** | 22,059 | 25,518 | **30.5%** |
| MOMENTUM | 15,399 | 17,383 | 6.1% |
| CONTRARIAN | 6,372 | 8,713 | 1.5% |
| INCOME | 15,028 | 17,105 | 10.7% |
| FOLLOW | 10,924 | 21,378 | 16.4% |
| RANDOM | 12,599 | 15,901 | 9.6% |
| BOND | 13,426 | 13,426 | 2.7% |

| Measure | Now (4% a point) | D170 / D172 (before market news) |
|---|---|---|
| **P4: leading strategy** | **`TREND` 30.5%, fails by 0.5** (31.1% at 5% a point) | `LOWPE` 27.7%, held by 2.3 |
| Strategies winning at least 4% | 6 of 10 | 6 |
| P2: the best reader's median over RANDOM's | 22,059 / 12,599 = 1.75 | 1.64 |
| P3: RANDOM's median over the leader's | 0.57 | 0.64 |
| Bull-year rate | 55.6% | 55.5% |
| Splits / bankruptcies per match | 1.69 / **0.14** | 1.64 / 0.59 |
| Short squeezes per match | 0.63 | 1.16 |
| Years with a company flagged | 25.6% | 47.8% |
| Desk's richest trader at the end | GROWTH 32.7%, VALUE 27.9%, PANIC 15.2%, INCOME 13.1% | VALUE 36.4%, GROWTH 24.7% |
| No squeeze (`--no-squeeze`) | `TREND` 26.5%, 7 contenders | `LOWPE` 29.4% |
| No flow (`--flow=none`) | `TREND` 31.9%, `LOWPE` 10.5%, 8 contenders | `TREND` 25.3% |
| Cost of the squeeze | **4.0 points** (4.6 at 5% a point), all to TREND | it took 1.7 from LOWPE |
| Cost of flow | **none** (31.1 with it, 31.9 without); it moves 9 points from TREND's rivals to LOWPE | 2.4 points |

**P4 moved, and fails.** At 5% a point it matches the figure recorded after D220 (design
Appendix A, "After the squeeze of no fixed length"). Three things changed between D172
and now, all in the owner's news and squeeze work, none in S9:

- **Market news replaced the base game's special events** (D209). The shipped lines
  carry no amounts, so the event noise left the prices. Bankruptcies fell from 0.59
  to 0.14 a match.
- **The squeeze became a meme stock** (D213, D220). A squeezed price rises for years
  in a row, which a trend follower rides. It adds 4.6 points to TREND.
- **The flag now skips a company already in a squeeze**, and SHORT traders stop
  shorting it. So companies are flagged in a quarter of years, not half.

P5 (the base game unchanged) is the golden-hash test, green.
P1 (every point of every move has a cause) is `test_price_ledger.gd`, green.

### Long matches, 1,000 seeds

| Length | Leader | TREND | FOLLOW | Contenders | P3 | Bull rate | Splits | Bankruptcies | Squeezes | Flagged |
|---|---|---|---|---|---|---|---|---|---|---|
| 10 (4,000 seeds, 4% a point) | `TREND` 30.5% | 30.5 | 16.4 | 6 | 0.57 | 55.4% | 1.69 | 0.14 | 0.63 | 25.6% |
| 25 (4% a point) | `LOWPE` 38.6% | 31.7 | 21.0 | 4 | 0.22 | 61.2% | 3.97 | 0.67 | 1.82 | 29.0% |
| 25 (5% a point) | `LOWPE` 38.0% | 31.9 | 21.6 | 4 | 0.25 | 61.3% | 3.98 | 0.67 | 1.75 | 27.9% |
| 50 (5% a point) | `LOWPE` 59.3% | 19.0 | 20.7 | 3 | 0.02 | 64.2% | 6.10 | 0.97 | 3.19 | 24.7% |
| 99 (5% a point) | `LOWPE` 76.2% | 10.2 | 13.4 | 3 | 0.00 | 65.1% | 11.34 | 3.25 | 4.87 | 19.3% |

**Long matches are flatter than they were** (D169: 50.8% at 25 years; this file's
first round, before market news: 73.5% at 50 and 89.2% at 99). They are still far
from parity. FOLLOW's median at 99 years is 0: copying the richest trader often ends
with nothing.

---

## 2. The agenda

Each lever: what it is, where it lives, its value, the argument that sweeps it, and
what was measured. The ten-year sweeps are 1,000 seeds from 0. Compare them with the
**published row at 1,000 seeds: `TREND` 29.4%, LOWPE 19.3, FOLLOW 18.5, INCOME 9.1,
BOND 2.2, 6 contenders, P3 0.56**. `--flag-at=10` reproduces that row exactly, which
checks the flag lever. Rows marked 4,000 are confirmations.

### Lever 0 — the squeeze's size and chance (D213, D220): what P4 now turns on

- **What it is.** A flagged company is squeezed one year in four, jumping 5% of its
  price per point of short interest, at most 150%. It then holds or ends each year.
- **Where:** `ShortInterestRules.SPIKE_PERCENT_PER_POINT` and
  `SQUEEZE_CHANCE_PERCENT` (`src/sim/short_interest_rules.gd`).
- **Value:** 4% a point since D233 (5% before); a 25% chance in a flagged year.
- **Sweeps:** `--squeeze-size=N` (percent a point), `--squeeze-chance=N`,
  `--no-squeeze`.

| Setting | Seeds | Leader | LOWPE | FOLLOW | Squeezes / match | Contenders | P3 | P4 |
|---|---|---|---|---|---|---|---|---|
| 5% a point (D213) | 4,000 | `TREND` 31.1 | 19.9 | 16.6 | 0.63 | 6 | 0.57 | fails by 1.1 |
| **4% a point (published since D233)** | 4,000 | `TREND` 30.5 | 20.1 | 16.4 | 0.63 | 6 | 0.57 | **fails by 0.5** |
| 3% a point | 1,000 | `TREND` 29.4 | 19.7 | 17.1 | 0.65 | 6 | 0.58 | — |
| 2% a point | 1,000 | `TREND` 26.6 | 20.6 | 17.7 | 0.66 | 6 | 0.59 | — |
| 1% a point | 1,000 | `TREND` 26.1 | 21.6 | 16.6 | 0.69 | 6 | 0.61 | — |
| **1% a point** | 4,000 | `TREND` 28.1 | 21.7 | 15.9 | 0.68 | 6 | 0.61 | **holds by 1.9** |
| chance 10% | 1,000 | `TREND` 26.9 | 21.3 | 17.0 | 0.26 | 6 | 0.61 | — |
| no squeeze | 1,000 | `TREND` 24.7 | 23.0 | 16.1 | 0 | 6 | 0.64 | — |
| **no squeeze** | 4,000 | `TREND` 26.5 | 22.1 | 15.6 | 0 | 7 | 0.63 | **holds by 3.5** |

**What it says.** The squeeze is the whole of P4's failure. Smaller or rarer, it
passes. At 2% a point or less it costs about two points; at 3% or 4% it costs most
of what 5% does. **Decided (D233):** the owner's rule was to take 4% if it measured
lower than 5% over the same 4,000 seeds. It did, by 0.6, so the squeeze is 4% a
point. P4 still fails by 0.5.

### Lever 1 — the slope of the income trade-off (design §3.10a)

- **What it is.** A company that pays out more grows more slowly:
  `retention = 1 + slope * (35 - policy) / 100`, on positive growth only.
- **Where:** `DividendRules.retention_factor` (`src/sim/dividend_rules.gd`).
- **Value:** slope 1 (one point of growth per point of policy).
- **Sweep:** `--retention-slope=F` (D232). 0 removes the trade-off, 0.5 halves it.
- **Why open:** §2.6 found income "a niche rather than a route", its median barely
  above the bond's, and named halving the slope as the first thing to try.

| Slope | Leader | LOWPE | INCOME | INCOME median | Contenders | Splits | P3 |
|---|---|---|---|---|---|---|---|
| 0 (no trade-off) | `TREND` 29.5 | 18.2 | **13.4** | 16,831 | 6 | 2.06 | 0.56 |
| 0.5 (half) | `TREND` 30.4 | 19.2 | 11.2 | 15,916 | 6 | 1.88 | 0.56 |
| **1 (published)** | `TREND` 29.4 | 19.3 | 9.1 | 14,834 | 6 | 1.71 | 0.56 |
| 1.5 | `TREND` 32.7 | 21.6 | 7.6 | 13,936 | 6 | 1.58 | 0.55 |

The bond's median is 13,426 in every row.

**What it says.**

- **Lowering the slope is safe.** At 0 or 0.5 the leader stays within noise of the
  published one. **Raising it to 1.5 hurts P4** (+3.3 to TREND): slow payers make fast
  growers' trends steadier.
- **Halving it is worth about two points of INCOME** (9.1 → 11.2) and 1,100 of
  median. Removing it is worth four (13.4%) and 2,000.
- **Income is a route already.** INCOME's median beats the bond's by about 1,400 at
  the published slope. It pays steadily and rarely wins.
- **The real question is a play one**: does holding a payer *feel* worth it?
  Sheet line **f** of manual section AD.

### Lever 2 — flattening long matches toward parity (design §1, §13.2, §14 q13) — **closed by D235: not flattened**

- **What it is.** Any real per-year edge, reinvested, dominates a long enough
  match. §1 argues this is the mode working; q13 asks whether to flatten it
  anyway, and was deferred to after first play.
- **Where:** no single place. Candidates are the flow clamp scaled by length, the
  long-match damping ladder (`RegimeRules.growth_damping`: ×0.80 over 19 years,
  ×0.50 over 49), the squeeze, and the regime premium.
- **Value:** no flattening beyond the damping ladder.
- **Sweeps:** `--flow-limit-99=F` (scale the clamp from 5% at ten years to F at 99,
  D232), `--flow-limit=F`, `--flow=none` and `--no-squeeze` at a given `--years`;
  `--premium-scale=F` at a given `--years` for the premium. No argument yet damps
  the premium *only* in long matches.

400 seeds from 0:

| Length | Setting | Leader | TREND | LOWPE | FOLLOW | P3 |
|---|---|---|---|---|---|---|
| 25 | **published** | `LOWPE` 37.5 | 27.5 | 37.5 | 24.8 | 0.24 |
| 25 | no squeeze | `LOWPE` 46.8 | 26.5 | 46.8 | 16.5 | 0.21 |
| 25 | clamp 2.5% | `TREND` 46.5 | 46.5 | 21.5 | 18.0 | 0.23 |
| 25 | no flow | `TREND` 49.8 | 49.8 | 16.8 | 17.3 | 0.21 |
| 50 | **published** | `LOWPE` 60.5 | 20.0 | 60.5 | 18.8 | 0.02 |
| 50 | clamp to 0 at 99 years (2.2% at 50) | `LOWPE` 41.0 | 32.0 | 41.0 | 22.8 | 0.08 |
| 50 | no flow | `TREND` 44.8 | 44.8 | 30.5 | 20.5 | 0.07 |

**What it says.**

- **Two edges pull against each other in long matches.** Flow feeds LOWPE (the
  VALUE traders buy what it buys); the squeeze feeds TREND, but also breaks up
  LOWPE's run. Remove either and the other wins by more: at 25 years, no squeeze
  gives LOWPE 46.8%, and no flow gives TREND 49.8%. **The published market, with
  both, is the flattest 25-year match measured.**
- **Scaling the clamp with length helps at 50 years** (60.5% → 41.0%), by balancing
  the two edges, not by removing them.
- **No lever measured gets a 25-year match under 30%.** Parity would need something
  new, such as damping the premium in long matches. That is a design question first.
- **The owner's call first**: should a 25-year match reward the best reader
  decisively? Manual section AD3.

### Lever 3 — how often the short-interest flag shows (D165, D170, D213)

- **What it is.** A company is flagged when the desk's short interest reaches a
  share of its shares outstanding, unless it is already in a squeeze. A squeeze can
  only fire in a flagged year, so the flag also sets how often squeezes happen.
- **Where:** `ShortInterestRules.FLAG_AT_PERCENT` (`src/sim/short_interest_rules.gd`).
- **Value:** 10%. Some company is flagged in about a quarter of years.
- **Sweep:** `--flag-at=N` (D232).

| Flag at | Seeds | Years flagged | Squeezes / match | Leader | LOWPE | FOLLOW | P3 |
|---|---|---|---|---|---|---|---|
| **10% (published)** | 1,000 | 24.9% | 0.63 | `TREND` 29.4 | 19.3 | 18.5 | 0.56 |
| 15% | 1,000 | 14.2% | 0.37 | `TREND` 28.1 | 20.3 | 17.6 | 0.58 |
| 20% | 1,000 | 9.2% | 0.26 | `TREND` 27.5 | 21.3 | 16.8 | 0.59 |
| 25% | 1,000 | 6.4% | 0.18 | `TREND` 27.5 | 21.3 | 16.3 | 0.60 |
| **20%** | 4,000 | 9.1% | 0.23 | `TREND` 29.0 | 20.9 | 15.9 | 0.59 |

**What it says.** A higher flag means fewer, bigger squeezes, since only heavily
shorted companies qualify. It passes P4 at 20% over 4,000 seeds, but only by 1.0
point: fewer squeezes help less than smaller ones (lever 0). Its main effect is how
the flag reads on screen. At 10% a company is flagged one year in four; at 20%, one
year in eleven.

### Lever 4 — the margin flow leaves (design §3.10, D170, D172)

- **What it is.** Net shares traded last year push this year's price, clamped to a
  share of fair value. It is what makes reading the desk pay (FOLLOW).
- **Where:** `PriceIdentity.FLOW_LIMIT_FRACTION` (`src/sim/price_identity.gd`).
- **Value:** 5% of fair value.
- **Sweeps:** `--flow-limit=F` (D232); `--flow=none` or `--flow=desk`.

| Clamp | Leader | TREND | LOWPE | FOLLOW | INCOME | BOND | Contenders | P3 |
|---|---|---|---|---|---|---|---|---|
| 0% (`--flow=none`, 4,000 seeds) | `TREND` 31.9 | 31.9 | 10.5 | 12.2 | 12.8 | 7.3 | 8 | 0.58 |
| 2.5% | `TREND` 30.8 | 30.8 | 13.6 | 13.4 | 11.7 | 4.1 | 8 | 0.56 |
| 3.5% | `TREND` 31.9 | 31.9 | 15.1 | 13.1 | 10.3 | 3.7 | 7 | 0.55 |
| **5% (published)** | `TREND` 29.4 | 29.4 | 19.3 | 18.5 | 9.1 | 2.2 | 6 | 0.56 |
| 7.5% | `LOWPE` 30.4 | 30.1 | 30.4 | 16.8 | 6.3 | 1.3 | 6 | 0.57 |
| 2.5% with the squeeze at 1% a point | `TREND` 29.5 | 29.5 | 13.5 | 12.9 | 12.6 | 5.1 | 8 | 0.60 |

**What it says.** **This lever has turned round since D170.** Flow used to be what
P4 hung on; now it costs nothing, because the leader is TREND and flow feeds LOWPE.
Tightening the clamp no longer helps P4 and makes FOLLOW worse (18.5 → 13%), so the
desk is less worth reading. Widening it to 7.5% makes LOWPE and TREND level at 30%.
**Leave it at 5%** unless the squeeze changes.

### Lever 5 — what reading the whispers is worth (design §8.4, D234)

- **What it is.** At the end of each year from year 1, two whispers about next year
  (a company or an industry, from a rated source), plus a squeeze or crash whisper
  when one applies (D214). They move no price; a player who believes them can trade
  on them.
- **Where:** `WhisperRules.ODDS` (each source's chance of telling the truth),
  `NewsSelector.WHISPERS_PER_YEAR` (2), `NewsSelector.SQUEEZE_WHISPER_SOURCE`
  (Questionable).
- **Value:** Rock Solid 85% true, Credible 60, Hit-or-miss 40, Questionable 30,
  Gossip 20; two whispers a year.
- **Sweeps:** `--strategies=...,WHISPER` adds the WHISPER player (D234), which reads
  the whispers and nothing else: what each tells, weighted by its source's odds, a
  squeeze coming as a strong buy, the bond when nothing is worth buying. Then
  (D236) `--whispers=N` (ordinary whispers a round), `--whisper-odds=A,B,C,D,E`
  (each source's chance of the truth, Rock Solid to Gossip),
  `--no-squeeze-whisper`, and (D237) `--whisper-sources=A,B,C,D,E` (how often each
  source is heard, as weights; published: evenly). These change only what WHISPER
  hears: whispers move no price.

WHISPER is **not** one of the default ten, so the baseline in §1 is unchanged. With
it as an eleventh player, published values:

| Run | Seeds | WHISPER | WHISPER median | TREND | LOWPE | FOLLOW | Contenders | P3 |
|---|---|---|---|---|---|---|---|---|
| eleven strategies, 10 years | 4,000 | **38.2%** | 26,096 | 18.2 | 13.1 | 12.9 | 6 of 11 | 0.48 |
| WHISPER, TREND, RANDOM, BOND only | 4,000 | 51.6% | 26,199 | 32.7 | — | — | 3 of 4 | 0.50 |
| eleven, no squeeze | 1,000 | 30.5% | — | 17.4 | 16.2 | 12.6 | 7 of 11 | 0.60 |
| eleven, no flow | 1,000 | 39.9% | — | 19.8 | 5.7 | 8.3 | 7 of 11 | 0.48 |
| eleven, 25 years | 1,000 | 43.1% | — | 15.1 | 24.3 | 13.2 | 4 of 11 | 0.15 |

**What it says.**

- **Reading the whispers is the strongest edge in the game.** WHISPER wins 38% of
  ten-year matches against ten other strategies, and its *median* is the highest of
  all (26,096 against TREND's 21,898), so it is not luck from holding fewer stocks.
  Counted as a strategy, P4 fails by 8.2 points.
- **About eight of those points are the squeeze whisper.** With no squeeze WHISPER
  falls to 30.5%. A "squeeze coming" whisper lets a reader buy before a jump of up to
  150%, and the source's 30% odds do not stop that paying.
- **Flow is not part of it** (39.9% with none).
- **What it means for play:** a player who acts on every whisper should beat one who
  reads the board. That may be what the owner wants, or too much. It also bears on
  shared and personal whispers (design §14): a personal whisper would be a private
  edge of this size.

**The whisper sweep** (D236): ten years, 1,000 seeds, eleven players. Compare with
the published row, measured on the same seeds.

| Setting | WHISPER | WHISPER median | Leader | TREND | LOWPE | FOLLOW | Contenders | P3 |
|---|---|---|---|---|---|---|---|---|
| **published** (2 a round, 85/60/40/30/20, squeeze whisper on) | **39.7** | 27,375 | WHISPER | 18.0 | 12.2 | 13.0 | 6 | 0.46 |
| 3 a round | 42.9 | 29,106 | WHISPER | 14.8 | 12.4 | 12.5 | 6 | 0.43 |
| 1 a round | 30.9 | 23,129 | WHISPER | 19.3 | 14.4 | 13.6 | 7 | 0.54 |
| no squeeze whisper | 31.9 | 21,991 | WHISPER | 19.7 | 13.6 | 13.7 | 7 | 0.58 |
| odds 60/45/30/20/15 | 27.7 | 20,163 | WHISPER | 19.9 | 15.1 | 14.6 | 7 | 0.62 |
| **odds halved** (43/30/20/15/10) | 20.2 | 17,250 | `TREND` 22.1 | 22.1 | 16.7 | 14.9 | 7 | 0.57 |
| **1 a round, no squeeze whisper** | 20.2 | 17,880 | `TREND` 22.9 | 22.9 | 15.9 | 15.0 | 7 | 0.58 |
| every source 20% | 20.1 | 16,535 | `TREND` 23.5 | 23.5 | 16.3 | 14.8 | 7 | 0.58 |
| only the squeeze whisper (0 a round) | 18.5 | 19,044 | `TREND` 23.0 | 23.0 | 16.4 | 16.2 | 7 | 0.58 |
| nothing heard (it holds the bond) | 2.0 | 13,426 | `TREND` 28.8 | 28.8 | 19.0 | 18.1 | 6 | 0.57 |

**What the sweep says.**

- **The squeeze whisper alone is worth a lot**: with no ordinary whisper at all,
  WHISPER still wins 18.5%, buying whatever is flagged. That company is also shown
  as FLAGGED on the DESK page, so this part of the edge is reading short interest,
  which any player can do; the whisper only points at it.
- **Each lever takes WHISPER from dominant to a contender.** Halving every source's
  odds, or one whisper a round with no squeeze whisper, puts it at about 20%, just
  behind TREND, with seven strategies in contention.
- **Making every source 20% also gets it to 20%,** but then the source names mean
  nothing, which is the point of §8.4's sources.
- **A third whisper a round makes it stronger** (42.9%).
- WHISPER's presence costs the other strategies; with nothing heard it holds the bond
  and the table is close to the ten-strategy baseline.
- **A caveat on lower odds:** WHISPER weighs each source by its *published* honesty,
  so with lower odds it believes labels that are now wrong. A real player would learn
  to trust them less. Lower odds would probably mean renaming the sources.

**How often each source is heard** (D237): the same run with the source picked by
weight instead of evenly. Weights are Rock Solid, Credible, Hit-or-miss,
Questionable, Gossip; each source keeps its honesty.

| Source weights | WHISPER | WHISPER median | TREND | LOWPE | FOLLOW | Contenders | P3 |
|---|---|---|---|---|---|---|---|
| **evenly (published)**; `1,1,1,1,1` gives the same | **39.7** | 27,375 | 18.0 | 12.2 | 13.0 | 6 | 0.46 |
| 10, 15, 25, 25, 25 | 29.0 | 22,478 | 19.5 | 14.5 | 15.0 | 7 | 0.58 |
| 5, 15, 25, 30, 25 | 28.5 | 21,254 | 19.5 | 15.1 | 14.9 | 7 | 0.60 |
| 2, 8, 20, 35, 35 | 27.7 | 19,889 | 19.9 | 15.0 | 14.7 | 7 | 0.64 |
| 0, 20, 25, 30, 25 (no Rock Solid) | 28.1 | 21,600 | 19.6 | 15.2 | 14.7 | 7 | 0.60 |
| 0, 0, 20, 40, 40 | 26.0 | 19,191 | 20.5 | 15.8 | 14.5 | 7 | 0.66 |
| 5, 15, 25, 30, 25, no squeeze whisper | 24.2 | 18,695 | 21.7 | 14.6 | 15.4 | 7 | 0.68 |

- **Making good sources rarer takes WHISPER from about 40% to 26-29%**, under P4's
  30% ceiling, and adds a seventh contender. WHISPER still leads in every row.
- **The exact weights matter little.** Anything that makes Rock Solid and Credible
  rarer lands at 28-29%; even with no Rock Solid at all it is 28.1%. Most of the gain
  is from not hearing a good source every round, not from removing one.
- **Unlike lower odds, the names stay true.** A Rock Solid whisper is still right 85%
  of the time; it is just heard less, so WHISPER's trust in the labels is correct
  here.
- **With no squeeze whisper too**, 24.2%, close to TREND's 21.7%.

### Other things the design leaves to S9 or to after first play

These are not numbers to sweep but features to add or not, each waiting on play:

| # | What | Where it is written | What would decide it |
|---|---|---|---|
| 6 | **Market news amounts.** The shipped market news moves no price (D209). Lines with amounts would put event noise back into prices | `src/data/news/market.tres` | The owner's writing. Re-run section 1 when lines with amounts are added: the event noise was worth about two points to LOWPE before D209 |
| 7 | **The VALUE cohort.** D170 named it the second lever after the clamp. With TREND leading it is no longer the problem | `src/data/traders/` | Only if LOWPE leads again |
| — | **Dividend smoothing**: boards holding a dividend flat through a bad year | design §3.10a, "considered and left out" | Whether a dividend cut reads as too sudden in play |
| — | **A capped short for players** | §14 q10 | Whether players ask to bet against a company directly |
| — | **A cheap/expensive marker** on the board | §14 q9 | Whether reading P/E proves too hard in play |
| — | **A "flatten groups" toggle** on the Exchange | §14 q12 | Whether players ask for it |
| — | **Pace**: four tabs in a party game | §12.2, §13.2 risk 2 | Manual section AD2, sheet line **i** |
| — | **Shared and personal whispers** in multiplayer | §14, "Still open" | The owner's request of 2026-11-27; not scheduled |

Key personnel, prices within the year and NPC thoughts are separate tasks (§14,
"Still open") and are not part of this agenda.

---

## 3. Waiting for the owner

**Decided on 2026-11-27 ([D235](decisions.md)):** P4's half-point miss stands; the
flag stays at 10%; the income slope stays at 1; long matches are not flattened (the
longer the match, the more the best reader is rewarded). Levers 1 to 4 need nothing
further. Nothing in `src/` changes until the owner decides.

1. **Whispers (lever 5).** Reading them wins 38% of ten-year matches. Keep them that
   strong, or weaken them. Hearing good sources less often (for example weights
   5/15/25/30/25) puts a whisper reader at about 28%, under the ceiling, with the
   names still true. Halving every source's odds, or one whisper a round with no
   squeeze whisper, puts it at about 20%. All 1,000 seeds; confirm over 4,000 if
   chosen. Each would be a change to §8.4, so it is the owner's call.
2. **Play reports.** Section AD of manual-testing.md. Sheet line **k** is about
   whispers.

## Rounds

| Date | What changed | Decision | Baseline after |
|---|---|---|---|
| 2026-11-23 | S9 opened on `5835de9`: baseline `LOWPE` 27.7% (identical to D172); four levers added to the tool | D232 (tool only) | superseded the same week |
| 2026-11-27 | Rebased onto `29ab7a9` (market news, meme-stock squeeze, squeeze of no fixed length). Every figure re-measured; the first round's sweeps are void | — | `TREND` 31.1%, P4 fails |
| 2026-11-27 | The squeeze from 5% to 4% a point. The sweeps in §2 were measured at 5% and are not re-run | D233 | §1: `TREND` 30.5%, P4 fails by 0.5 |
| 2026-11-27 | The owner kept P4's miss, the flag, the income slope and long matches as they are. WHISPER added to the tool and measured (lever 5) | D234, D235 | §1, unchanged |
| 2026-11-27 | Whisper levers added to the tool and swept (lever 5) | D236 (tool only) | §1, unchanged |
| 2026-11-27 | Source weights added to the tool and swept (lever 5) | D237 (tool only) | §1, unchanged |
