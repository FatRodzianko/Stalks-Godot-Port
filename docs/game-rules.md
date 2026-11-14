# Game Rules

**Source:** reconstructed from the original game's
[itch.io write-up](https://rodzianko.itch.io/stalksstalksstalks).

**Status:** ⚠️ Draft, needs confirmation by the project owner. Items marked
**[CONFIRM]** are unknown or ambiguous from the write-up alone and must be settled
before the relevant feature is built. Where the original Unity source is the only
authority, it is cited as reference only — behaviour is to be reimplemented, not
copied.

---

## Objective

Finish the final year with the highest **net worth**.

```
net worth = cash on hand + (for each holding: shares × current price per share)
```

---

## Match setup (host options)

| Option | Range | Notes |
|---|---|---|
| Lobby name | — | Defaults to the host's Steam profile name |
| Number of years | 2–99 | |
| Number of players | 1–10 | Host may start without filling the lobby |
| Enable loans | on/off | Loans become available from Year 2 |
| Invite only | on/off | Hides the lobby from the browser; Steam invites only |

Starting cash: **[CONFIRM]** — not stated in the write-up. The original lobby
metadata carried a `startingWealth` field, so it was configurable; the default value
needs confirming.

### Joining

Players browse or search lobbies by name, or accept a Steam invite. Every joiner
must **ready up**; the host can start once all lobby members are ready.

---

## Year structure

The game opens at **Year 0**: every stalk is priced at **100**, and no buying or
selling is allowed. When all players press *Ready for New Year*, play advances to
Year 1.

During a normal year players may buy and sell freely:

- **Buying** — from the *Available Stalks* board. Purchases are capped by cash on
  hand; if total cost exceeds cash, the purchase fails. **[CONFIRM]** whether this
  fails silently, shows an error, or clamps to the affordable amount.
- **Selling** — from *Your Stalks*. Proceeds are `shares sold × current price`.

### End-of-year sequence

Strictly ordered. Order matters and must be preserved:

1. Pick **BEAR** or **BULL** for the year.
2. Pick special events.
3. Apply price changes from the bull/bear modifier **and** special events.
4. **Split** any stalk priced above 150.
5. **Bankrupt** any stalk whose price has reached 0.
6. Pay **dividends**.
7. Recalculate **net worth** for all players.

**[CONFIRM]** the probability of BULL vs BEAR, and whether it is a flat coin flip
or weighted.

---

## Price movement

Each stalk carries, and displays on the board:

- Name
- Price per share
- Dividend paid in **bull** years
- Dividend paid in **bear** years
- **Yearly change** in price — the bull/bear modifier only, *excluding* special events
- A buy control

Generally bear years push prices down and bull years push them up. A price may sit
at 0.

**[CONFIRM]** the exact per-stalk price-change formula — whether each stalk has a
fixed step, a random range, or a volatility stat, and whether the roll is per-stalk
or shared across the market.

### Special events

- **One** event is drawn per year, as long as stalks other than `BERRY BONDS` exist.
- Event effects are applied **on top of** the yearly change, and are deliberately
  **not** included in the displayed *Yearly Change* figure.
- Presentation: flavour text in red, then the affected stalk and its price delta in
  white (e.g. *Springfield Nuclear Power rose by 5*).

**[CONFIRM]** the full event list, each event's magnitude, whether an event can
target any stalk or only specific ones, and why `BERRY BONDS` is excluded (it reads
like a bond — a stable, event-immune instrument).

### Splits

If a stalk's price is **above 150** after the yearly change and events:

- Price is **halved**
- Every holder's share count is **doubled**

Example from the write-up: price 152 → 76; a holder of 10 shares ends with 20.

**[CONFIRM]** rounding direction on an odd price (e.g. 153 → 76 or 77). Since all
money is integer, this must be pinned down and tested.

### Bankruptcy

If a stalk's price falls to **0 or below**, the stalk goes bankrupt and all holders'
shares in it drop to **0**. No compensation.

**[CONFIRM]** whether a bankrupt stalk is removed from the board, replaced, or
remains listed at 0.

---

## Loans

Only if *Enable Loans* was set, and only from **Year 2** onward.

Quoted terms from the write-up:

> You can take out a loan up 25% of your net worth. The minimum loan is $100. Terms
> are 10 years and 6% interest.

| Rule | Value |
|---|---|
| Maximum principal | 25% of current net worth |
| Minimum principal | $100 |
| Term | 10 years |
| Interest | 6% |
| First payment due | The **following** year |

- Any amount between the minimum and maximum may be borrowed. Cash is paid out
  immediately.
- **Missed payments** escalate:
  1. First miss — loan balance +10%
  2. Second miss — loan balance +15%
  3. Third miss — **all assets seized, player bankrupt**
- The minimum payment rises with the balance after a miss.
- **Overpayment** is allowed if the player has the cash. **Partial payment is not** —
  a payment must meet at least the minimum.
- The minimum payment is recalculated every year, and integer rounding makes it
  drift by roughly ±1 per year. Example from the write-up: a minimum of 657 falling
  to 631 after an overpayment.

**[CONFIRM]** whether interest is simple or compound, whether 6% is annual, the
exact minimum-payment formula, whether multiple concurrent loans are allowed, and
what happens to an outstanding loan at game end (deducted from net worth?).

---

## Final year and winning

In the last year players get one more round of buying and selling. The year then
advances once more with the **full** end-of-year sequence, and the game ends.

Tie-breaking, in order:

1. Highest net worth
2. Highest cash on hand
3. Still tied — **all tied players win**

---

## Yeehaw

- Any player may **request** a Yeehaw at any time.
- Any **other** player may then **give** it. You cannot give one to yourself,
  so Yeehaws are impossible in a 1-player game.

**[CONFIRM]** what a Yeehaw actually does. The write-up never says — it may be
purely social/cosmetic, or it may be tied to a Steam achievement.

---

## Platform notes

- Original shipped Windows-only, ~18 MB, free, "In development".
- Steam client must be running in the background; lobbies use Steam profile names
  and Steam invites.
- The original had Steam achievements (`SteamAchievementManager`).
  **[CONFIRM]** the achievement list and whether it carries over to the port.
