# Game Rules

**Authoritative spec for the port.** Every value here was either confirmed by the
project owner or read directly out of the original Unity source. Where the original
code and the [itch.io write-up](https://rodzianko.itch.io/stalksstalksstalks)
disagree, the **code wins** — it is what players actually experienced — and the
disagreement is noted.

Original Unity source files are cited by name (e.g. `StalkManager.cs`) so the
provenance of each number is traceable. **That project is not in this repository and
you do not need it** — every value extracted from it is reproduced in this document.
The citations are for provenance, not a dependency. Where it exists on the original
author's machine, its location is noted in [development.md §2](development.md).

The original is **reference for rules only**; the port reimplements behaviour, not
structure.

Anything still open is marked **[OPEN]**.

---

## 1. Objective

```
net worth = cash on hand
          + sum over holdings of (price per share × shares held)   [only while price > 0]
          - outstanding loan balance
```

Highest net worth after the final year wins.

**Tie-breaking:** highest net worth, then highest cash on hand; if still tied, all
tied players win.

---

## 2. Game settings

Called "lobby settings" in the original, since every game ran through a Steam lobby.
The port renames these **game settings**, because it must support true single-player
with no Steam dependency at all.

| Setting | Range | Default |
|---|---|---|
| Game name | up to 24 characters | named after the host |
| Game | Stalks Stalks Stalks or StalkleHeads | **Stalks Stalks Stalks** (the base game) |
| Starting cash | **150–69,420** | **10,000** |
| Number of years | 2–99 | — |
| Number of players | 1–10 | — |
| Loans enabled | on/off | — |
| Invite only | on/off | **off** (Steam only; meaningless offline) |

**Game** is new in the port (StalkleHeads phase S5): which game the match is. The
original had one. Everything in this file is the base game unless a note says
StalkleHeads; StalkleHeads' rules are
[stalkleheads-design.md](stalkleheads-design.md). It cannot change during a match,
and it is published to the lobby browser beside the years, cash and loans
(decisions.md D171).

**Read the bounds exactly:** the original tested
`wealth > 149 && wealth < 69421`, so 150 and 69,420 are both legal and 69,421
is not. 69,420 is a joke and it is the ceiling on purpose.

The port ran with 100 to 1,000,000 for a while — bounds guessed before the
2026-11-16 audit read the real ones out of the original's source
(`original-game-audit.md` §3.1). Restored the same day; see decisions.md D89.

**Any whole number in range is accepted.** The field briefly rounded to the
nearest 100, which was a spin-box step nobody chose rather than a rule.

---

## 3. The stalks

Ten stalks, all starting at **price 100**. Bear ranges are stored as positive
magnitudes and negated when applied.

| Stalk | Bear range | Bull range | Bear div | Bull div |
|---|---|---|---|---|
| BERRY BONDS FROM DIE HARD | 0 – 0 | 0 – 0 | 3 | 3 |
| My Mutuals and Me Inc. | 0 – 10 | 0 – 5 | 2 | 3 |
| Springfield Nuclear Power | 10 – 20 | 0 – 15 | 0 | 5 |
| My Pillow, Your Pillow, We're All Pillows! | 5 – 25 | 0 – 15 | 1 | 1 |
| Mafia HUD Scam | 5 – 25 | 5 – 15 | 1 | 3 |
| Unionized Submissives LLC | 0 – 25 | 5 – 20 | 0 | 2 |
| North Haverbrook MONORAIL | 5 – 30 | 0 – 20 | 1 | 4 |
| PG&Enron | 10 – 35 | 5 – 15 | 0 | 4 |
| Teamsters Pension Fund | 15 – 40 | 0 – 15 | 0 | 8 |
| strYker!!! | 15 – 50 | 13 – 42 | 0 | 0 |

Source: `Resources/Prefabs/StalkPrefabs/*.prefab`. **In the port these values are
authored** as one `.tres` per stalk in `src/data/stalks/`, each carrying its own
special events. A test cross-checks the files on disk against this table, so if the
two ever disagree the suite fails. To add or change a stalk, see
[development.md §6](development.md).

The design reads clearly: **BERRY BONDS** is the risk-free bond — it never moves and
always pays 3. **strYker!!!** is the casino — the widest swings either way and no
dividend at all. **Teamsters** pays a huge bull dividend (8) to compensate for a
brutal bear range. **Mutuals** is the index-like safe-ish middle.

### BERRY BONDS is special-cased

It is excluded from price movement entirely by an explicit name check
(`stalk.stalkName != "BERRY BONDS FROM DIE HARD"` in `AdjustStalksForNewYear`), and
it has no special events. It cannot split and cannot go bankrupt.

> **Port note:** do not reproduce this as a name comparison. Give the stalk
> definition a flag (e.g. `is_price_static`) and drive behaviour from data.

There is also an unused `StalkPrefab.prefab` template with all-zero stats — the
original's "add a new stalk" starting point. The port replaces it with a documented
`.tres` template.

---

## 4. Year structure

The game opens at **Year 0** with every price at 100 and buying and selling
disabled. When all players press *Ready for New Year*, play advances to Year 1.

During a normal year, players buy and sell freely, then ready up. When all players
have readied, the end-of-year sequence runs.

**Readying up closes your own trading** — a port rule, not the original's. The
year ends the instant the last player readies, so a player who has already said
they are done could otherwise be one stray click from selling everything a
heartbeat before the prices move. Readying is a toggle, so the cost is one
press: un-ready and the board is live again. Other players readying does not
affect you. See decisions.md D97.

### 4.1 End-of-year sequence — the real order

The write-up lists a different order from the code. This is what the code actually
does, traced through `GameplayManager.GetBearOrBull()` →
`StalkManager.AdjustStalksForNewYear()` → `GetYearEvent()` → `CheckForSplitStalks()`
→ `PayDividendsToPlayers()` → `AdjustLoans()` → `CalculateNetWorth()`:

1. **Decide bull or bear** for the year.
2. **Apply the base price change** to every stalk except BERRY BONDS.
3. **Bankruptcy pass 1** — any stalk now at ≤ 0 goes bankrupt.
4. **Apply the one special event** to its single target stalk.
5. **Bankruptcy pass 2** — the event can itself bankrupt a stalk.
6. **Splits** — any stalk now above 150 splits.
7. **Dividends** paid, based on the year's mood.
8. **Loans** — missed-payment penalties, then interest.
9. **Net worth** recalculated, rankings updated.
10. If the year counter has passed the limit, **determine the winner**.

Two consequences worth preserving deliberately:

- **Splits are checked only once, after events.** A stalk pushed above 150 by its
  base move and then knocked back under by a negative event does *not* split. That
  is correct and intentional-looking.
- **Dividends are paid after splits**, so a stalk that splits pays that year's
  dividend on the *doubled* share count. Generous, but it is what shipped.

> The write-up's ordering (events before price changes, bankruptcy before dividends
> in a single pass) is wrong. Ignore it.

### 4.2 Bull / bear odds

Confirmed exactly. `GameplayManager` holds a 12-element array of 5 `"bear..."` and
7 `"BULL!!!"` entries and picks one uniformly:

- **Bull: 7/12 ≈ 58.3%**
- **Bear: 5/12 ≈ 41.7%**

The owner recalled "60/40 favouring bull", which is nearly right. Use the exact
7/12 to start, and make it a tunable setting rather than a hardcoded array.

### 4.3 Base price change

Per stalk, independently rolled — not one roll shared across the market.

```
roll a 10-sided chance:
  10% of the time  -> a contrarian move against the year's mood
  90% of the time  -> a normal move with the year's mood, then long-game softening
```

| | Normal move (90%) | Contrarian move (10%) |
|---|---|---|
| Bear year | −maxChangeBear … −minChangeBear | **+0 … +5** |
| Bull year | +minChangeBull … +maxChangeBull | **−10 … 0** |

### 4.4 Long-game softening — undocumented mechanic

Completely absent from the write-up, and important. The base move is scaled down in
longer games so prices don't run away:

| Game length | Bear multiplier | Bull multiplier |
|---|---|---|
| > 49 years | × 0.45 | × 0.50 |
| > 19 years | × 0.70 | × 0.80 |
| ≤ 19 years | × 1.0 | × 1.0 |

Applied **only to the normal 90% move**, never to the contrarian 10% move. Truncated
to `int` by a C# cast.

### 4.5 ⚠️ Inclusive vs exclusive ranges — a trap in this port

C# `Random.Next(min, max)` excludes `max`. Godot's `randi_range(min, max)`
**includes** it. So a naive line-by-line port silently changes the maths: in the
original, `strYker!!!` could gain 13–41 in a bull year and **never 42**, despite its
stat block saying 42.

The displayed stat block clearly *intends* an inclusive range, so the port should be
inclusive — but this must be a **deliberate, documented decision**, not an accident,
and the tests must pin the chosen behaviour.

---

### 4.6 A player who is away — **not in the original**

A player whose connection drops mid-match, or who quits to the title screen,
stays **in the match**. The original had no answer to this at all: its host
simply carried on and the departed player's game was over.

The rule the port settles on, asked for by the owner on 2026-11-18 and summed
up in their words as "tough but fair":

- **The end-of-year sequence does not care whether anybody is watching.** An
  away player is paid their dividends, their stalks split and double their
  shares, a bankruptcy wipes their holdings out, their loan is charged interest,
  and their net worth is recomputed. Every step of §4.1 applies to them
  unchanged.
- **Every year away is a missed loan payment.** Nobody is there to pay, and
  §9.3 records a miss for a year that went unpaid. So the ordinary schedule
  applies: 10% on the first miss, 15% on the second, and everything seized on
  the third (§9.2.2). Three years away with a loan outstanding wipes a player
  out.
- **They keep their place in the standings and can still win.** The rankings
  and the winner are computed from every player in the match (§1, §12), which
  means an absent player can win a match they were not present for, and can
  equally be overtaken while they are gone.
- **The year does not wait for them.** They cannot ready up, so the all-ready
  gate skips them. This is the one and only thing being away changes.
- **A match nobody is present for does not resolve years at all.** Otherwise it
  would run itself to the end, unwatched, before anybody could come back.
- **They take no actions.** There is nothing to stop: a player who is not
  connected cannot send a request.
- **A yeehaw needs two players who are present** (§10), since there is nobody
  at an absent player's keyboard to answer one.

Coming back is **REJOIN GAME** on the title screen. The seat is matched by
Steam ID, so it is only ever handed back to the account that left it; see
decisions.md D110 and D111.

---

## 5. Special events

One event per year, drawn from a mood-specific pool. The event names its target
stalk, so an event is data about a stalk, not a free-floating market shock.

Each event carries: **target stalk name**, **flavour text**, **price change**.

- **45 bull events** and **45 bear events** — 5 per stalk, for the 9 stalks that
  aren't BERRY BONDS. Hardcoded in `StalkManager.CreateSpecialEvents()`.
- Bull magnitudes run **+5 to +20**; bear magnitudes **−5 to −25**.
- Applied **on top of** the base yearly change, and deliberately **excluded** from
  the *Yearly Change* figure shown to players.
- Presentation: flavour text in red, then target stalk and delta in white.

### Known issues in the original's event handling

- **Off-by-one, drops an event.** `BullEvents[rng.Next(BullEvents.Count - 1)]`
  returns an index in `0 … Count-2`, so **the last event in each pool can never be
  drawn**. Same bug in both pools. Fix in the port.
- **Events repeat.** Nothing removes a drawn event from its pool, so the same event
  can fire in consecutive years. The `else` branch logging *"No more yearly events
  exist!"* is therefore dead code. **Decided: events must not repeat.** The port
  draws without replacement from a shuffled bag per mood. When a bag empties it is
  refilled and reshuffled, so an event cannot recur until every other event in its
  pool has been seen. This matters because a 99-year game has roughly 58 bull years
  against only 45 bull events, so exhaustion is reachable and needs defined
  behaviour.
- **Events can target dead stalks.** If the target went bankrupt and was removed, the
  event is announced but changes nothing. **Decided: skip it and draw another.** A
  skipped event returns to the bag rather than being consumed. If every candidate in
  the bag targets a bankrupt stalk, the year simply has no event.

  > Forward note for "StalkleHeads" mode: once events also move an industry or the
  > wider market, an event whose target is bankrupt may still be worth firing for its
  > sector effect. The rule above is specifically for the current model, where an
  > event affects exactly one stalk and nothing else — so a dead target makes it a
  > no-op. Keep the skip decision inside the event-selection strategy, not baked into
  > the year pipeline, so the advanced mode can choose differently.
  >
  > **StalkleHeads, as built (S3):** no shipped event has an industry or market effect
  > yet, so StalkleHeads keeps this rule unchanged. It also draws from last year's
  > mood's bag, and leaves out events aimed at My Mutuals and Me Inc. (decisions.md
  > D154).
  >
  > **StalkleHeads, as built (S4): the short squeeze.** One event is not in either
  > bag. While some company's short interest (the shares the NPC desk has sold
  > short) is at least 10% of its shares outstanding, a roll of 1-100 made every
  > year comes up at most 25 one year in four, and then the year's event is a
  > short squeeze on the most shorted such company, +25 to its price, **instead
  > of** a draw from the bag; the bag is left untouched that year. With nothing
  > flagged it cannot happen. Players cannot sell short. See decisions.md D165
  > and stalkleheads-design.md §5.3. The base game has no squeeze.
  >
  > **When the host changes (S6).** The bag rule above holds across a host
  > migration in StalkleHeads: the bags travel with the match, so the player who
  > takes over deals from what was left (decisions.md D177). **In the base game it
  > does not:** a new host reshuffles every bag, so an event can come round again
  > before its cycle is over. A known gap, left alone because fixing it changes the
  > base game's network data.
  >
  > **A company that fails has no valuation.** In StalkleHeads a bankrupt company's
  > price is 0 and its multiple, fair value, sentiment and the other valuation
  > figures are cleared to 0 in the year it fails. Nothing reads them afterwards;
  > clearing them lets a client rebuild every company exactly (D176).

### 5.1 StalkleHeads news — **not in the original**

StalkleHeads (phase S8) adds five kinds of news line beside the special event. None
of them moves a price; they are things to read. The rules, as built
(stalkleheads-design.md §8, decisions.md D199-D203):

| Line | How many a year | Chosen by |
|---|---|---|
| Market headline | at most one | the year's mood, and the index's move band |
| Industry report | at most one per industry | that industry's move band (and mood, if a line names one) |
| Earnings commentary | at most one per company alive at the year's start | its regime this year, and its surprise band |
| Whisper | at most two | a trigger that holds for something this year; see below |
| NPC chatter | at most one per desk trader | what the trader did: bought, sold, shorted, covered or held |

- **Move bands** (percent): CRASH at -15 or below; DOWN below -3; FLAT -3 to +3;
  UP below +15; SURGE +15 or above.
- **Surprise bands:** revenue growth against what the regime leads one to expect -
  the middle of its growth band, with the long-match damping and the payout
  retention applied. Within 3 points AS_EXPECTED; 3 to 8 BETTER or WORSE; 8 or
  more MUCH BETTER or MUCH WORSE.
- **Whisper triggers:** HIGH_SHORT_INTEREST (flagged this year, §5 above);
  THIRD_GROWTH_YEAR (a third year or more in GROWTH); MARGIN_SLIPPING (margin down,
  revenue up, on last year); PE_ABOVE_INDUSTRY / PE_BELOW_INDUSTRY (more than 20%
  from the industry's average P/E); SECTOR_RUN (an industry the same way three years
  running); NEAR_SPLIT (price above 260; the split is above 300); NEAR_FAILURE
  (DISTRESS and a price under 20).
- **A whisper is a rumor.** One whose trigger holds for something is in play; it
  then rolls against its truth chance (75 for every shipped one). Honest, it names
  something the trigger holds for; a lie, it names something it does not. A whisper
  written about one named company cannot lie, so when its roll says lie it is not
  shown.
- **Without replacement.** A line is not repeated while another line that could fill
  the same slot has been shown fewer times.
- **Nothing matches, nothing shows.** No stand-in line, and the section's heading
  hides with it.
- **The same for everybody.** Every machine chooses the same lines; they never take a
  draw from the match's random numbers, so news cannot change a price.

All the shipped text is placeholder - the category in capitals, then the conditions
(`INDUSTRY REPORT: energy, down`) - until the owner writes it.

---

## 6. Splits

If a stalk's price is **above 150** after the base change and the event:

- Price is **halved, rounding up on an odd price** — `153 → 77`, not 76.
- Every holder's shares are **doubled**.

The live code is `CheckForSplitStalks()`:

```csharp
newPriceAfterSplit = price / 2;
if (price % 2 != 0) newPriceAfterSplit++;
```

> The owner's instinct was that it *should* round up. It already does. Note that a
> second, **dead** `SplitStalks()` function rounds *down*; it is commented out of the
> call path. Use the round-up behaviour.

There is no cap on how high a price can go before splitting, and no limit on the
number of shares a player may hold.

---

## 7. Bankruptcy of a stalk

If a price reaches **0 or below**, the stalk goes bankrupt:

- Every holder's shares in it go to **0**. No compensation.
- The board entry stays visible, overlaid with **BANKRUPT!!!**
- A sound plays.

BERRY BONDS can never go bankrupt (it never moves).

---

## 8. Dividends

Paid per share, after splits, based on the year's mood:

```
payout = shares held × (bull year ? bullDividend : bearDividend)
```

Fixed per stalk — no randomness. Holdings in a stalk that went bankrupt this year
pay nothing, because the bankruptcy pass has already zeroed the share count.

---

## 9. Loans

Only when loans are enabled, and only from **Year 2** onward.

**One loan per player for the entire game** — not one at a time. The original sets a
"has a loan" flag when a loan is issued and **never clears it**; the only line that
would reset it is commented out. So once a player has borrowed, they can never borrow
again, even after paying the loan off in full. Verified in
`GamePlayer.CmdRequestLoan` and every assignment to `doesPlayerHaveLoan`. This looks
more like an oversight than a design choice, but it is what shipped, and the port
reproduces it. See decisions.md D27.

**A toggle for repeat borrowing exists, off in the base game.**
`GameSettings.multiple_loans_enabled` lets a player borrow again once their loan is
settled, still one loan at a time. It is for StalkleHeads (decisions.md D159), which
turns it on for every match since S5 (D171); nothing in the base game turns it on.

### 9.1 Terms

| Rule | Value |
|---|---|
| Maximum principal | 25% of current net worth (`(int)(netWorth * 0.25)`) |
| Minimum principal | 100 |
| Term | 10 years (10 payments) |
| Interest | 6%, **compound, annual** |
| First payment due | the **following** year |
| Loans per player | **One, for the whole game** |

### 9.1.1 Two implementation details that change the maths

Both come straight from `GamePlayer.CmdRequestLoan` and are easy to get wrong:

- **The term counter starts at 11, not 10.** A new loan is created with
  `yearsRemaining = 11`, while its opening minimum payment is amortised over **10**.
  The year-end pass decrements the counter before assessing anything, so the extra
  year is consumed immediately. Start it at 10 and every payment figure comes out
  wrong.
- **A new loan is flagged as already paid for the current year.** `paidThisYear` is
  set `true` on creation. That is how "your first payment is next year" is
  implemented: the first year-end sees the loan as paid, counts no miss, and simply
  charges interest. A player *may* still pay in the year they borrow, which is legal
  but produces a different (longer, cheaper-per-payment) schedule.

### 9.2 Minimum payment — standard annuity amortisation

`GamePlayer.LoanMinimumPayment(loanAmount, years)` computes:

```
denominator = (1.06^years − 1) / (0.06 × 1.06^years)
minPayment  = (int)(loanAmount / denominator)
```

That `denominator` is the **present-value annuity factor** at 6%. So this is the
textbook amortising-loan payment, `principal / a(n, 6%)`, truncated to an integer.

For the standard 10-year term, `a(10, 6%) ≈ 7.360087`, so:

```
minPayment ≈ loanAmount / 7.360087
```

A 2,500 loan (the max for a player worth 10,000) gives a minimum payment of **339**.

This settles the open question: **interest is compound, and the scheme is a proper
amortisation**, not simple interest.

### 9.2.1 The canonical schedule

> **This section was corrected during Phase 2.** An earlier version of this document
> gave a trace built from a model that started the term counter at 10 and omitted the
> interest-only first year. Both were wrong (see §9.1.1), so its figures were wrong
> too. The trace below is taken from the implemented `LoanRules` and is asserted
> year-by-year in `tests/unit/test_loan_rules.gd`.

A 2,500 loan — the maximum for a player worth 10,000 — where the player pays nothing
in the year they borrow (which is explicitly not a miss) and then pays the minimum
every year:

```
taken:  balance 2500, min payment 339, years_remaining 11, paid_this_year true

  yr  1: paid    0  (not a miss)      +interest 150  -> 2650
  yr  2: paid  339  -> 2311           +interest 138  -> 2449
  yr  3: paid  339  -> 2110           +interest 126  -> 2236
  yr  4: paid  339  -> 1897           +interest 113  -> 2010
  yr  5: paid  339  -> 1671           +interest 100  -> 1771
  yr  6: paid  339  -> 1432           +interest  85  -> 1517
  yr  7: paid  339  -> 1178           +interest  70  -> 1248
  yr  8: paid  339  ->  909           +interest  54  ->  963
  yr  9: paid  340  ->  623           +interest  37  ->  660
  yr 10: paid  339  ->  321           +interest  19  ->  340
  yr 11: paid  340  ->    0                          ->    0   PAID OFF

settled after exactly 10 payments. Total paid 3,392 on 2,500 borrowed.
```

Four things this establishes:

1. **Exactly ten payments, landing precisely on zero.** The advertised "10 year"
   term is real: one interest-only year, then ten payments in years 2–11.
2. **The payment holds at 339 throughout**, drifting to 340 twice. That is the ±1
   integer-truncation drift the write-up describes, and the port preserves it rather
   than "fixing" it.
3. **Interest is charged before the player's first opportunity to pay**, taking the
   balance from 2,500 to 2,650. A borrower never owes less than they borrowed.
4. **Total interest over the term is 892** on 2,500, which is what compound 6% over
   ten amortised years should cost.

**Correction to a claim made earlier:** a previous version of this document asserted
that holding the payment fixed instead of re-amortising would leave a residue, and
the porting plan listed a guard test for it. That was an artefact of the wrong term
counter. With the correct setup the minimum barely moves, so holding it fixed is
nearly identical and no such guard test is meaningful. The re-amortisation still
matters for *overpayment* (§9.4), where it visibly lowers the next minimum.

Other verified minimum payments at the 10-year term: principal 100 → **13**,
1,000 → **135**, 10,000 → **1,358**. The annuity factor is `a(10, 6%) ≈ 7.360087`.

### 9.2.2 Never paying: the default schedule

Same loan, player never pays:

```
  yr  1: no miss (first year is free)   +interest 150  -> 2650
  yr  2: miss 1   penalty +265 (10%)    +interest 174  -> 3089
  yr  3: miss 2   penalty +463 (15%)    +interest 213  -> 3765
  yr  4: miss 3   ->  DEFAULT: cash 0, net worth 0, all holdings seized
```

Note the default lands on the **fourth** year-end, not the third, because the year
the loan is taken is free.

### 9.3 Yearly loan processing (`AdjustLoans`)

Per loan, in this order:

1. `yearsRemaining` decrements.
2. If the player **did not pay** this year, `missedPayments` increments and:
   - **1st miss** — balance × 1.10, then minimum payment re-amortised over the
     remaining years.
   - **2nd miss** — balance × 1.15, then re-amortised.
   - **3rd miss** — **player bankrupt**: cash set to 0, net worth set to 0, all
     holdings removed, loan destroyed.
3. If the player **did** pay, the paid-this-year flag resets.
4. **Balance × 1.06** — interest applied unconditionally, after the payment.

Because the payment is deducted before interest is applied, and the payment is the
annuity amount, the balance amortises to zero over the term. The maths is sound.

### 9.4 Making a payment (`CmdPayLoan`)

Validated server-side, in order:

- Payment must be **≥ the minimum**. Partial payments are rejected with an error.
- Payment must be **≤ cash on hand**, else rejected with an error.
- Payment is **clamped** down to the outstanding balance, so you cannot overpay into
  a negative balance.
- Overpayment **is** allowed, and then the minimum is re-amortised over
  `yearsRemaining − 1`, which is why the owner saw a minimum drop from 657 to 631.
- The ±1 year-to-year drift in the minimum is the `(int)` truncation in the annuity
  formula. It is expected, and the port should reproduce it rather than "fix" it.
- Paying the balance to 0 marks the loan paid off.

### 9.5 Payment prompt is advisory, not blocking

A player with a loan is **prompted** to pay the minimum before ending their turn,
but is **never forced to**. This is a deliberate design choice by the owner: the
player may choose to miss a payment and eat the penalty, but the game must never
penalise them for something it *hid* from them. The prompt must be clearly visible
and dismissible, never a silent default.

### 9.6 At game end

An outstanding loan balance is **subtracted from net worth**, and the balance is
updated for the final year like any other.

---

## 10. Yeehaw

Purely social. No mechanical effect. The owner calls it **a critical feature**.

- Any player may **request** one: *"Can I get a yeehaw?"* All other players are
  notified.
- Any **other** player may **give** it. You cannot give one to yourself, so a
  1-player game can neither give nor receive.
- When given, **all players hear the "YeeHaw!" sound**.

Implemented via `PlayerRequestOrGiveYeehaw` → `CmdRequestYeehaw` /
`CmdGiveYeehaw` → `RpcYeehawRequested` / `RpcYeehawGiven`, with the sound broadcast
through `RpcPlayBearOrBullSounds("yeehaw")`.

> Because it is trivial logic that nonetheless requires a request, a broadcast, and
> an authority check, Yeehaw makes an excellent **first networked feature** to build
> and prove the RPC path with.

**Ported, Phase 5.** A pending request is **match state**, not an event: one
request at a time, synced to everybody, exactly as the original kept it. That is
what lets a single button do both jobs — it reads "Can I Get a Yeehaw?" until
somebody asks, then "Give Yeehaw" for everyone else.

`YeehawRules` holds the checks. The self-yeehaw rule is enforced on the host and
a client cannot route around it: the giver comes from the sender's peer id and
the receiver is whoever is asking, so **neither end of the gesture travels in the
packet** (decisions.md D45).

Two deliberate differences from the original, both documented: the asker's button
is disabled rather than hidden, so the top bar does not reflow (D37); and an
unanswered request is cleared when the year advances, where the original left it
pending forever and locked the button for the rest of the match (D52).

The sound is **not yet wired** — it arrives with audio in Phase 7. Until then the
gesture shows as a message line.

---

## 11. Buying and selling

- Bought from the *Available Stalks* board; sold from *Your Stalks*.
- Proceeds on sale: `shares sold × current price`.
- **No limit** on total shares a player may hold.
- **No short selling.** A player can sell only shares they hold. This holds in
  StalkleHeads too (design §14 q10): only the NPC desk's SHORT traders sell short,
  and players bet against a company by reading them (decisions.md D164).
- Purchases are validated against cash on hand server-side
  (`StalkManager.GetPriceOfPurchase` / `PlayerBuyOrSellStalks`).

### Failed purchase feedback — improve on the original

The original **failed silently** when a purchase exceeded cash, showing only the
maximum affordable as placeholder text in the input field
(`GetMaxPlayerCanAfford` / `RpcMaxPlayerCanAfford`).

The port must give real feedback. Agreed direction: an error state on the buy
control — red text and/or a rejection sound — plus a clear affordable-maximum
affordance. The exact treatment is a UI decision to make during that phase.

---

## 12. Final year and game end

With a limit of N years, players play out year N normally, including buying and
selling. After they ready up on year N:

- One final year advance runs, with the **full** end-of-year sequence.
- Players **cannot buy or sell** during it. Holdings can still change through splits
  and bankruptcies.
- Net worth is recalculated, the winner is declared, and the game ends.

`CalculateNetWorth` triggers `DetermineWhoWonGame()` once
`currentYear > maxNumberOfYears`.

---

## 13. Steam achievements

25 achievements. The port **reuses the original's App ID, 1821800**
(decisions.md D57), so these names must match what the Steam partner backend
already holds — a name that disagrees does not error, it just never unlocks.

The catalogue lives in `src/data/achievements.gd`, which is the single source of
truth for the ids. The table below is the same information in prose, read out of
the original's `SteamAchievementManager.cs` and its callers.

| Id | Unlocked by |
|---|---|
| `SSS_Win_One_Game` | Win a game |
| `SSS_WIN_TEN` / `_HUNDRED` / `SSS_WINS_THOUSAND` | 10 / 100 / 1000 lifetime wins (stat `sss_wins`) |
| `SSS_Lose_One_Game` | Lose a game |
| `SSS_LOSES_TEN` / `_HUNDRED` / `_THOUSAND` | 10 / 100 / 1000 lifetime losses (stat `sss_loses`) |
| `SSS_NETWORTH_FIFTY` | Finish with net worth >= 50,000, **and** starting cash <= 10,000 |
| `SSS_NETWORTH_HUNDRED` | Finish with net worth **<= 100**. A wipe-out, despite the name |
| `SSS_ONE_MIL` / `SSS_ONE_BIL` | Cumulative net worth across all games >= 1,000,000 / 1,000,000,000 (stat `lifetime_networth`) |
| `SSS_DOUBLED` | Finish with >= 2x your starting cash |
| `SSS_HALVED` | Finish with <= half your starting cash |
| `SSS_MORTGAGE` | Play a match of 30 years or more |
| `SSS_CENTURY` | Play a match of exactly 99 years |
| `SSS_TOOK_OUT_LOAN` / `SSS_PAID_LOAN` / `SSS_DEFAULT_LOAN` | Borrow / pay off / default |
| `SSS_SPLIT` | Hold a stalk that splits |
| `SSS_ALL_IN` | Hold **300 or more shares of one stalk** |
| `SSS_BANKRUPT` | Hold a stalk that goes bankrupt |
| `SSS_DIVERSIFIED` | Hold **>= 10 shares of all ten stalks** at once |
| `SSS_YEEHAW_ONE` / `SSS_YEEHAW_HUNDRED` | Give 1 / 100 yeehaws (stat `sss_yeehaws`) — **given**, not received |

**The casing bug, resolved.** Steam's achievement API names are case-sensitive,
and the original hedged: it set both `SSS_WIN_ONE_GAME` and `SSS_Win_One_Game`,
and both `SSS_LOSE_ONE_GAME` and `SSS_Lose_One_Game`.

Both were read off the partner backend on 2026-11-14, and the answer is **not**
what the majority pattern suggests: the two singular "one game" achievements are
`Title_Case` (`SSS_Win_One_Game`, `SSS_Lose_One_Game`) while every other id
shouts. Guessing from the other 23 would have got both of them wrong, and a
wrong name does not error — the achievement simply never unlocks.

The shouting variants are dead. Do not reintroduce them.

### Faithful but fragile, worth fixing in the port

The original's lifetime counters test `== 1000` and `== 100` rather than `>=`.
If a `StoreStats` call ever fails on exactly the right game, the achievement is
missed forever. The port should use `>=` throughout. This changes no outcome
that the original would have produced correctly.


---

## 14. Confirmed bugs in the original

Carried here so the port fixes them deliberately rather than inheriting them.

| # | Issue | Decision |
|---|---|---|
| 1 | Last special event in each pool unreachable (`Count - 1`) | **Fix** |
| 2 | `Random.Next` max-exclusive makes stat-block maximums unreachable | **Fix** — make ranges inclusive, and test it |
| 3 | Dead `SplitStalks()` rounds down, live path rounds up | Keep **round up** |
| 4 | Duplicate mixed-case Steam achievement IDs | Use one canonical casing |
| 5 | Silent failure on unaffordable purchase | **Fix** — visible error |
| 6 | BERRY BONDS special-cased by string comparison | **Fix** — data flag |

---

## 15. Still open

- Achievement thresholds beyond the two confirmed above (§13).
- Steam App ID reuse (§13).
- Whether long-game softening thresholds stay hardcoded or become settings (§4.4).
