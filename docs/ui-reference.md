# UI Reference

## The target: a pixel-art terminal

> **On reference images.** Screenshots and photographs used while designing this
> are kept locally in `reference-images/` and are **deliberately not committed**:
> they came from image searches and the project does not hold the rights to
> republish them. Nothing here links to them, and nothing should — the look is
> described in words below and in decisions.md D40 precisely so that a fresh
> clone loses nothing it needs. If a reference ever becomes load-bearing, write
> down what it shows rather than committing the file.

The interface is a **pixel-art Bloomberg terminal**: dense monospace text on dark
panels, colour-coded fields, everything on a character grid.

That is not a decoration choice, it is what makes the layout tractable. On a fixed
grid every layout question is *"how many characters wide?"* rather than *"how many
pixels?"*, which removes the whole class of proportional-width fitting problems.

| | |
|---|---|
| Reference resolution | **640 × 360** |
| Stretch | `viewport` + `scale_mode = integer` |
| Font | **Terminus TTF** (OFL 1.1), `assets/fonts/` |
| Cell | **6 × 12 px** at font size 12 → a **106 × 30 character grid** |
| Headings | font size 24 → a 12 × 24 cell, exactly 2× |

640×360 scales by whole numbers to every common 16:9 resolution — ×2 to 720p, ×3 to
1080p, ×4 to 1440p, ×6 to 4K — so the art is never resampled. See decisions.md D40.

**Every dimension in the scenes is a whole number of pixels at this resolution**, and
most are multiples of 6. A `custom_minimum_size` of 30 is five characters. When
changing a column, think in characters and multiply by 6.

### Stalk names scroll rather than abbreviate

The name column holds about twelve characters and eight of the ten names are longer
than that. The board still shows the **full name**: the names are the funniest thing
in the game, so they are not abbreviated away.

A name that does not fit **scrolls on hover**, and **clicking pins the scroll** so it
can be read without holding the mouse still. Clicking again releases it. A name that
fits never moves, so most of the board is still. This is `MarqueeLabel`
(`src/ui/widgets/marquee_label.gd`), and it scrolls by whole characters — authentic
to a ticker display, and exact on a monospace grid with no sub-pixel blur.

`StalkDefinition` also carries a **`ticker`** field (`BERRY`, `STRYK`, `PGEN`) which
nothing currently displays. It is there for a future compact view, where a dense
board of symbols would suit the terminal look. Populated for all ten stalks.

---

# The original's layout

Read out of the original Unity project: `Scenes/Gameplay.unity`,
`OfflinePrefabs/GameplayPrefabs/StalkListItem.prefab`,
`Resources/Prefabs/PlayerPrefabs/StalksOwnedListItem.prefab` and
`PlayerRankingsListItem.prefab`.

**Why this exists.** The port follows the original's *layout decisions* — what
information exists and where it sits — because those came from designing and playing
the game. It does not follow its *construction*: managers reaching directly into text
fields, prefabs wired by dragging, UI state duplicated from game state. See
decisions.md D39.

This file is the answer to "what goes where". Consult it instead of guessing.

---

## The playing screen

```
┌─ TopBarPanel ─────────────────────────────────────────────────────────────┐
│  YearText          SpecialEventPanel                     YeehawButtonPanel│
│  "Year: 0/10"      ├ SpecialEventText  (flavour)         └ YeehawButton   │
│  BearOrBullText    └ SpecialEffectText (which stalk,        "Can I Get a  │
│                                         how much)            Yeehaw?"     │
├─ MainGameplayPanel ───────────────────────────────────────────────────────┤
│ AvailableStalksPanel      │ StalksOwnedPanel         │ PlayerRankingsHolder│
│ "Available Stalks"        │ "Your Stats"             │ "Player Rankings"   │
│                           │  Cash on Hand: N         │                     │
│ StalkBoardHeader          │  Networth: N             │ PlayerRankingsHeader│
│  Name of Stalk            │                          │  Player Name        │
│  Price Per Share          │ "Your Stalks"            │  Player Networth    │
│  Bull Dividend            │ StalksOwnedPanelHeader   │  Ready Status       │
│  Bear Dividend            │  Name of Stalk           │                     │
│  Yearly Change            │  # Owned                 │ PlayerRankingsContent│
│  (buy area)               │  Sell Stalks             │  rows               │
│                           │                          │                     │
│ StalkListContent (rows)   │ StalksOwnedContent (rows)│                     │
├─ BottomBarPanel ──────────────────────────────────────────────────────────┤
│  (empty)   │ DontForgetText        │ GoalOfGameText      │ Ready button    │
│            │ "Don't forget to pay  │ "This is Year 0…"   │ "Ready for New  │
│            │  your loan!"          │ ErrorMessageText    │  Year"          │
└───────────────────────────────────────────────────────────────────────────┘
```

Proportions from the original: the stalk board is the widest column, the middle is
narrower, player rankings is narrowest.

---

## Row structures

**Available Stalks row** (`StalkListItem`):

| Node | Shows |
|---|---|
| `StalkName` | Display name |
| `PricePerShare` | Current price |
| `BullDividendPerShare` | Dividend in a bull year |
| `BearDividendPerShare` | Dividend in a bear year |
| `YearlyChange` + `YearlyChangeArrowImage` | The base move, with a direction arrow |
| `BuyInputField` + `BuyButton` | The buy control |
| `BankruptPanel` > `BankruptText` | Overlay reading "bankrupt!!!" |

Note the yearly change has **a number and an arrow image** beside it.

**Your Stalks row** (`StalksOwnedListItem`):

| Node | Shows |
|---|---|
| `StalkOwnedListNameOfStalkText` | Display name |
| `StalkOwnedListNumberOwned` | How many held |
| `SellStalkInput` + `SellButton` | The sell control |

No price column — the price is on the Available Stalks board.

**Player Rankings row** (`PlayerRankingsListItem`):

| Node | Shows |
|---|---|
| `PlayerRankingsName` | Player name |
| `PlayerRankingsNetworthText` | Net worth |
| `PlayerReadyStatusImage` | A coloured dot: ready or not |


---

## The StalkleHeads playing screen (port only)

**Not in the original.** StalkleHeads is the port's second mode
([stalkleheads-design.md](stalkleheads-design.md) §7). Its playing screen is the base
one above with the three panels of `MainGameplayPanel` replaced by four tabs; the top
and bottom bars are unchanged (decisions.md D180).

```
┌ top bar, as above ─────────────────────────────────────────────────────────┐
│ [EXCHANGE] [MARKET] [INDUSTRIES] [COMPANY]                                 │
│ EXCHANGE:                                                                  │
│  SYM  NAME        PRICE  CHG   EPS  P/E  DIV HELD  [qty] B S │ CASH  NET   │
│  - CONSUMER GOODS         +3%       14.2                     │ RANKINGS    │
│  CONA Consumer Go  136    +7 10.26 13.3    3    0  [   ] B   │ THE DESK    │
│  ...                                                         │ SHORT INT.  │
├ bottom bar, as above ──────────────────────────────────────────────────────┤
```

**Column widths on the EXCHANGE board**, in characters of the 6 x 12 grid: marker 2,
SYM 6, NAME 18 (scrolls on hover), PRICE 6, CHG 6, EPS 7, P/E 6, DIV 6, HELD 5, then
the quantity box (5) and B and S (4 each). A header, a group line and a company row
are one scene (`CompanyRow`), so the columns line up. A bankrupt row hides CHG and
writes BANKRUPT across PRICE and CHG.

**MARKET**: index level and move, market P/E, mood and bull years, breadth,
risk-free rate; the index by year (a text chart 38 wide, 7 tall); the year's news;
the mood of each year as B (bull) or b (bear).

**INDUSTRIES**: one line per industry (this year, three years, standing, average
P/E, revenue share and a bar, member count); click one for its by-year chart (22
wide, signed) and its companies' shares.

**COMPANY**: `<` and `>` walk the board in its order; ticker, industry and earnings
regime ("SLOWING, 1st year"); five years of revenue, expenses, profit, margin,
earnings per share, price and P/E, with `^split` under a year it split; the ledger
"why the price moved"; earnings yield against risk-free; investors by name; which
of the desk's traders traded it last year; its short interest.

**The news panel** gains the year in review above the event, and widens to 480 px.

---

## Loans

Loans live in `LoanArea`, an overlay, plus a persistent nag in the bottom bar.

- **Bottom bar:** `DontForgetText` — *"Don't forget to pay your loan!"*
- **`WouldYouLikeALoanPanel`** — *"Would you like to learn about our loans?"*, with
  `LearnAboutLoanButton`, `TakeOutLoanButton` and `EnterLoanAmountPanel`
- **`LoanInfoPanel`** — the terms, verbatim from the original:
  - *"Loan Terms:"*
  - *"You can take out a loan up 25% of your net worth. The minimum loan is $100.
    Terms are 10 years and 6% interest…"*
  - *"Penalties for missed payments: 1st missed payment: 10% added to loan balance…"*
  - `MaxLoanText` — *"The max loan you can take out is: "*
  - `MinPaymentText` — *"The minimum payment for the loan would be: "*
  - `ClosePanelButton`
- **`LoanTakenOutText`** — *"Congratulations on your loan of: "*
- **`LoanBalanceArea`** — *"The remaining balance on the loan is X with Y…"*
- **`LoanPaymentPanel`** — `CurrentMinPaymentText` (*"Your minimum payment is: "*),
  `PayLoanInput`, `PayLoanButton`, `PenaltiesText`, and `DidNotPayLoanText`
  (*"You haven't paid your loan yet. If you do not pay, you will be penalized."*)

---

## The title screen

Four buttons across the top, and **one fixed panel size behind all of them** so
that the heading, the tab bar and the quit button never move as you click
between them (decisions.md D86).

| Tab | Holds |
|---|---|
| **SINGLE PLAYER** | Your name, years, starting cash, loans, seed, **START** |
| **HOST ONLINE** | Game name, years, starting cash, max players, loans, invite only, seed, **HOST ONLINE** |
| **JOIN GAME** | The lobby list, with a search box and REFRESH. Loads when the tab is opened |
| **SETTINGS** | Sound, resolution, fullscreen |

Single Player and Host Online are **one panel**, not two. Years, starting cash,
loans and seed are settings of the match and identical either way; what differs
is hidden. An online game takes your display name from Steam (D66), so the name
field is single-player only; a solo game has no second player, so the limit and
the privacy toggle are online only.

`QUIT TO DESKTOP` sits below the panel, outside it, as the original's did.

**The development overlay** (`DevOverlay`) is pinned to the top-left corner in
debug builds only, and holds the direct host/join form that used to be on the
Join panel.

## The icon

`icon.svg` at the project root: a green line graph on a dark rounded square,
hand-written, four elements. The stroke is `#6ee7a0`, the same bull green the
board uses for a price that went up, so it belongs to the palette rather than
sitting beside it. Change one and change the other.

It becomes the `.exe` icon through `config/icon` in `project.godot`; see
[exporting.md](exporting.md).

## Other screens

- **`GameOverPanel`** — `GameWinnerText`, `DidLocalPlayerWinText`,
  `EndGameMessageText`, `BackButton`. The port has a fuller result screen with
  final standings and a year-by-year history (D73)
- **`EscMenuPanel`** — `ResumeGame`, `SettingsButton`, `ExitToDesktop`, and a
  settings menu with a fullscreen toggle, resolution, and a volume slider.
  **Built 2026-11-16** as `PauseMenu`, showing the same `SettingsPanel` widget
  the title screen does, exactly as the original reused its settings panel

---

## Where the port differs

Three places. **Two were chosen; the first was not** — it is here because this is
where a reader looks for it, not because anybody decided it.

1. **Resizable — but by accident, not by choice.** The original explicitly disabled
   window resizing (`resizableWindow: 0`). The port's window resizes because `true` is
   Godot's default for `window/size/resizable` and nothing ever set it; there is no
   decision behind it and `project.godot` does not mention it. An earlier version of
   this list presented it as a deliberate improvement, which was wrong. The layout
   *does* survive resizing, because it is built from containers on a character grid —
   but that is a property of the layout, not evidence that anybody chose the policy.
   **Decided 2026-11-16: fix the window, as the original had it**, with a resolution
   dropdown instead. Not yet implemented — see original-game-audit.md §17.3 and §17.10
   for the decision and the reasoning.
2. **Rejections are visible.** The original showed
   *"You do not have enough cash for this purchase."* in the bottom bar but also let
   a purchase fail silently in some paths. The port disables the control as you type
   and always gives a reason (game-rules.md §11).
3. **No duplicated state.** The original's UI held its own copies of values that the
   network layer pushed into it. The port's widgets render from the simulation and
   own nothing.
