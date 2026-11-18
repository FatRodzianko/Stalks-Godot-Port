# Original Game Audit

**A functional inventory of the shipped Unity game.** Everything a player can do,
every screen they can reach, every response the game gives back — written down so
the port can be checked against *the original game* rather than against our own
rules document.

This exists because the two are not the same thing. `game-rules.md` is a very
complete specification of the **economy**: prices, dividends, splits, loans, win
conditions. It says almost nothing about how you create a game, what the lobby
browser shows you, what the settings menu contains, or what happens when you press
Escape. Those are also functionality, players notice when they are gone, and a plan
built from the rules document alone will quietly drop them.

**What is in scope:** game flow, screens, controls, inputs and their validation,
settings, persistence, feedback (text, sound, visual state), multiplayer lifecycle,
and the things that happen to you rather than by you.

**What is out of scope:** the original's code structure. It is not a model to follow
(see `CLAUDE.md`). Where this document names a C# file it is to record *where a
behaviour came from*, never to suggest reproducing its shape.

### Where to look instead

| For | Read |
|---|---|
| Economy rules and every number | [game-rules.md](game-rules.md) |
| Screen layout, columns, row contents | [ui-reference.md](ui-reference.md) |
| Why the port's structure differs | [decisions.md](decisions.md) |
| What is built and what is next | [porting-plan.md](porting-plan.md) |

### Status key

Each audited item carries a status, judged against the port as it stood on
**2026-11-16** (phases 0–7 built; see `porting-plan.md`):

| Mark | Meaning |
|---|---|
| **Ported** | A player gets the same thing, however it is built underneath |
| **Changed** | Present but deliberately different; the difference is recorded |
| **Missing** | Not in the port. Candidate work |
| **Dropped** | Deliberately not porting, with the reason |
| **[OPEN]** | Needs a decision before it can be scheduled |

The actionable summary is **§17**. Sections 1–16 are the evidence behind it.

---

## 1. How this audit was done

Every C# file in the original's `Assets/Scripts` was read in full — 25 files, about
5,000 lines — along with its three scenes (`TitleScreen.unity`, `LobbyScene.unity`,
`Gameplay.unity`), the stalk and player prefabs, the settings and sound prefabs, and
the Unity player settings. Scene hierarchies were parsed from the `.unity` YAML so
that panels which ship **disabled** could be told apart from panels a player actually
sees. That distinction turns out to matter (§9.5, §17).

What each original file is responsible for, so a claim here can be traced:

| Original file | Owns |
|---|---|
| `MainMenuManager.cs` | Title screen: create-game fields, validation, lobby list display, search |
| `SteamLobby.cs` | Steam lobby creation, joining, list requests, lobby metadata |
| `NetworkManagerStalks.cs` | Connection policy, lobby-to-game player handover, scene change |
| `SettingsManager.cs` | Resolution, fullscreen, volume; save and load |
| `SteamAchievementManager.cs` | Achievements and lifetime stats |
| `TabGroup.cs`, `TabButton.cs`, `PanelGroup.cs` | The title screen's tab bar |
| `TabNavigation.cs` | Tab key moves between input fields |
| `LobbyManager.cs`, `PlayerListItem.cs`, `LobbyPlayer.cs` | The waiting room |
| `LobbyListItem.cs` | One row in the lobby browser |
| `GameplayManager.cs` | The playing screen, year counter, yeehaw, loan panels, game over |
| `GamePlayer.cs` | One player's cash, holdings, ready state, trade and loan requests |
| `StalkManager.cs` | The year pipeline, the stalks, the special-event tables, the winner |
| `Stalk.cs`, `StalkListItem.cs` | A stalk and its board row |
| `StalkOwnedListItem.cs` | A holding row with its sell control |
| `PlayerRankingsListItem.cs` | A rankings row |
| `Loan.cs` | One player's loan |
| `EscMenuManager.cs` | The in-game pause menu |
| `SoundManager.cs`, `Sound.cs` | The sound bank |
| `FlexibleGridLayout.cs` | A layout helper, no game behaviour |

---

## 2. The shape of the game

Three Unity scenes, played in order, with no way back except quitting:

```
TitleScreen  --create or join-->  LobbyScene  --host starts-->  Gameplay
     ^                                 |                            |
     +--------------- quit ------------+---------- quit ------------+
```

Facts that shape everything else:

- **Steam is mandatory.** `SteamLobby.Start()` returns immediately unless
  `SteamManager.Initialized`, and every path into a game goes through a Steam lobby.
  There is no offline mode, no direct-IP option and no true single-player: a
  one-player game is a Steam lobby with a member limit of 1.
- **The host plays.** One peer owns the simulation and is also a player. The minimum
  player count is 1, so hosting alone is legal.
- **The window is fixed.** Unity player settings: 1920×1080 default, native
  resolution on, **not resizable**. That is why the original needs a resolution
  dropdown and the port does not in the same way (§3.5, §17.3).
- **Nothing persists between matches** except Steam achievements, Steam stats, and
  the three local preferences in §3.5. No save game, no profile, no match history.

---

## 3. Title screen

A single panel with a three-tab bar: **Create A Game**, **Find A Game**,
**Settings**. A `Quit to Desktop` button sits outside the panel.

Selecting a tab shows its body panel and hides the others. Selecting **Find A Game**
also kicks off a lobby-list request, as a side effect of the tab changing.

### 3.1 Create A Game — the fields

Six inputs. Every numeric field is a free-text box whose placeholder text states the
default and the limits.

| Field | Placeholder shown | Accepted | Blank means | Status |
|---|---|---|---|---|
| Name of Lobby | `Lobby Name...` | any text | named after the host (§3.2) | **Ported** |
| Number of Years | `Default 10. Max 99.` | **2–99** | 10 | **Ported** |
| Max. Number of Players | `Default 4. Max 10.` | **1–10** | 4 | **Missing** (§17.4) |
| Starting Wealth | `Default $10k. Min $150. Max $69420` | **150–69,420** | 10,000 | **Ported** (bounds restored 2026-11-16, D89) |
| Enable Loans | — (toggle) | on/off | off | **Ported** |
| Invite Only | — (toggle) | on/off | off | **Ported** |

Read the ranges exactly: the code tests `years > 1 && years < 100`,
`players > 0 && players < 11`, `wealth > 149 && wealth < 69421`. So 99 years is legal
and 100 is not; 69,420 is legal and 69,421 is not. The joke number is the ceiling on
purpose.

**Invalid input is rejected silently.** `MainMenuManager.CreateNewLobby` writes a
line to the debug log and returns. The player gets no message, and the button appears
to do nothing. The port replaces each of these boxes with a clamped `SpinBox`, so the
state cannot be reached — a better fix than a message.

### 3.2 Create A Game — what pressing the button does

1. The toggle picks the Steam lobby type: **friends-only** if Invite Only is on,
   **public** otherwise.
2. A Steam lobby is created with the chosen member limit.
3. On success the Mirror host starts, and the lobby gets its metadata:

| Lobby key | Value | In the port? |
|---|---|---|
| `HostAddress` | the host's Steam ID, used by joiners to connect | Equivalent |
| `name` | the typed name, or the fallback below | **Ported** |
| `GameName` | the literal `StalksStalksStalks`, so the browser can ignore other apps' lobbies | **Ported** (as a game tag) |
| `NumberOfYears` | the year limit, for display in the browser | **Missing** (§17.5) |
| `LoansEnabled` | whether loans are on, for display in the browser | **Missing** (§17.5) |

**The default lobby name** is the host's Steam persona **truncated to 12
characters**, plus `'s lobby`. The same 12-character truncation is applied to every
player's display name when they join (§4).

Note what is *not* published: **starting wealth and the player limit never reach the
browser**, so a joiner cannot see how much money they will start with. That is
original behaviour, not an oversight to fix silently — but it is worth a decision
(§20).

### 3.3 Find A Game — the lobby browser

| Control | Behaviour | Status |
|---|---|---|
| The list | One row per matching lobby | **Ported** |
| `Search for Lobby by name...` + `Search` | Case-insensitive substring match on the lobby name, applied client-side after the list arrives | **Missing** (§17.6) |
| `Refresh List` | Re-requests the list from Steam and rebuilds every row | **Ported** |
| A row's `Join` button | Joins that Steam lobby, then connects as a Mirror client | **Ported** |

**Which lobbies appear.** Two filters, and they are not the same kind:

- Steam-side: `AddRequestLobbyListFilterSlotsAvailable(1)` — only lobbies with **at
  least one free slot**.
- Client-side: the lobby's `GameName` must equal `StalksStalksStalks`. This exists
  because the original was developed against Valve's Spacewar test App ID, where
  every test lobby in the world would otherwise have shown up.

**Each row shows** the lobby name, `Years: N`, `Players: n/max`, and `Loans: Y` or
`Loans: N`. The port's row shows the name and `n/max` only.

**Quirks worth knowing before reimplementing.** All three are original behaviour, and
all three are things the port is better off not copying:

1. **The tab only fetches once.** `GetListOfLobbies` requests the list only when the
   row list is empty, so returning to the tab shows a stale list. Only
   `Refresh List` actually refetches.
2. **Search mode sticks.** The "did the player search" flag is reset only on a code
   path the normal flow never reaches, so once a search has run the filter keeps
   applying to later refreshes until the player searches again with an empty box.
3. **In-progress games are listed and then reject you.** The original publishes no
   "playing" state, so a running match with a free slot still appears in the browser.
   You join the Steam lobby, `NetworkManagerStalks.OnServerConnect` sees that the
   host is no longer on the title or lobby scene, and disconnects you — with no
   message. The port fixes this by publishing an open/playing state key and hiding
   games that have begun.

### 3.4 Joining by Steam invite

`SteamLobby.OnGameLobbyJoinRequested` handles a join coming from outside the game:
the Steam overlay's *Join Game*, a friends-list join, or an accepted invite. It joins
the lobby directly, skipping the browser entirely.

**Ported**, and extended: the port also handles being invited while the game is
**closed**, launching into the lobby from a `+connect_lobby` command line
(decisions.md D69). The original had no equivalent.

### 3.5 Settings tab

Three settings, one Save button. The same panel is reused inside the in-game pause
menu (§13), which is why both places offer the same three.

| Setting | Control | Detail | Status |
|---|---|---|---|
| Resolution | dropdown | Only **16:9** modes at the monitor's **current refresh rate** are listed. The shipped prefab's options are 2560×1440, 1920×1080, 1280×720, 852×480 | **Missing** (§17.3) |
| Fullscreen | toggle | Sets `Screen.fullScreen` directly | **Missing** (§17.3) |
| Volume | slider, **−35 to +5** | Writes the `volume` parameter on the audio mixer, in decibels. 0 is the default, so this is not a 0–100 scale and its default is not at the left | **Changed** — the port uses 0–100% with 100 as the default |
| Save Settings | button | Writes all three, then reloads them | **Ported** for volume |

**Applied on change, saved on command.** Moving the slider or flipping the toggle
takes effect immediately; nothing is written to disk until **Save Settings** is
pressed. A player who changes something and backs out keeps the change for the rest
of the session and loses it on restart.

**Persistence** is four Unity `PlayerPrefs` keys: `VolumePreference`, `FullScreen`,
`ResolutionWidth` and `ResolutionHeight`. Loaded once at startup, with validation on
the way in and a fallback to 1920×1080 windowed at volume 0.

**A detail worth keeping:** changing the volume plays the `bull2` clip, so the player
hears the level they have chosen. The port keeps this and improves it — a drag plays
the clip once on release instead of stacking one preview per slider step
(`main_menu.gd`).

### 3.6 Quit to Desktop

A button on the title screen, outside the tab panel, calling `Application.Quit()`.

**Missing** in the port, which has no quit button anywhere: closing the window is the
only way out. See §17.2.

### 3.7 Thanks for Supporting the Devs

If a file named `support-dlc.txt` exists next to the executable, a
**`Thanks for Supporting the Devs!`** label appears on the title screen. Otherwise it
stays hidden. Checked once, at title-screen startup.

This is the entire supporter-DLC feature: a file check and a label. **Missing** — the
port will check Steam DLC ownership rather than a file. See §17.8.

### 3.8 Tab key moves between fields

`TabNavigation.cs` makes **Tab** move focus to the next selectable control and
**Shift+Tab** to the previous one, across the create-game form.

**Ported** for free: this is Godot's default focus-next and focus-previous behaviour,
so no code was needed. Recorded so nobody reimplements it.

---

## 4. The lobby — the waiting room

A list of who is here, a ready toggle, and the host's start button.

| Element | Behaviour | Status |
|---|---|---|
| Heading | The lobby's name, read from Steam lobby data | **Ported** |
| A player row | **Steam avatar**, display name, and `Ready` / `Not Ready` in green or red | **Changed** — no avatar (§17.7) |
| `Ready Up` | Toggles your own ready state; the button's label becomes `Unready` | **Ported** |
| `Start Game` | **Hidden unless you are the leader and everyone is ready.** Appears and disappears as readiness changes | **Ported** |
| `Quit` | Leader: shuts the host down, which ends the lobby for everybody. Anyone else: disconnects just them | **Ported** |

**Display names come from Steam**, truncated to 12 characters. There is no way to
type a name. The port keeps Steam personas for online play and adds a name field for
local games, which the original had no need of.

**The leader is whoever joined first** — the flag is set when the lobby player list
is still empty. There is no host migration: if the leader leaves, the lobby ends.

**What the lobby does not have**, in the original or the port: chat, kicking, any way
to change the match settings after creation, and any display of the settings that
were chosen. A joiner's only information about the match is whatever the browser row
told them.

**A player arriving while the lobby is full** is disconnected once the server sees
the connection count at the limit. No message.

---

## 5. Starting the match

The host presses `Start Game`. `NetworkManagerStalks.StartGame` re-checks that
everybody is ready and that the lobby scene is still the active one, then changes
scene to `Gameplay`.

During the change, each lobby player is **replaced** by a game player carrying
forward their name, connection, player number and Steam ID. The stalks are spawned
and the match opens at **Year 0**.

**Ported**, with a structural difference the player does not see: the port has no
scene handover of this kind, because match state lives in the simulation layer rather
than in scene objects.

---

## 6. The playing screen

Layout, columns and row contents are in [ui-reference.md](ui-reference.md) and are
not repeated here. What follows is the **behaviour** of each piece.

### 6.1 Year 0 — the opening state

The match opens before the first year, in a state the player sees exactly once:

- Every stalk sits at 100 with a yearly change of 0.
- **There are no buy or sell controls at all.** The buy input and buy button on every
  board row start disabled and are only switched on when the first year begins.
- Two lines of explanatory text are on screen:
  - *"This is Year 0. The game will begin when all players are ready."*
  - *"The goal of the game is to have the highest networth after the last year."*
- Both lines are removed for good the moment Year 1 starts.

**Ported.**

### 6.2 The year counter and the mood

- `Year: N/M` in the top bar.
- Below it, the year's mood as **`bear...`** in italics or **`BULL!!!`** in bold. The
  styling is part of the joke; the original decides it by inspecting the string, the
  port from the mood value.

**Ported.**

### 6.3 The special event line

Two lines in the top bar: the event's flavour text, then which stalk changed and by
how much (`<stalk> changed <n>`). Both are blank in a year with no event.

**Ported.**

### 6.4 A stalk's board row

| State | What the player sees | Status |
|---|---|---|
| Normal | Name, price, bull dividend, bear dividend, yearly change | **Ported** |
| Yearly change | A signed number **and an arrow sprite** — up, down, or flat | **Ported** |
| Split this year | The price is prefixed `SPLIT!!!` on its own line | **Ported** |
| Bankrupt | The whole detail area is replaced by a **`BANKRUPT!!!`** overlay. The row stays on the board for the rest of the match | **Ported 2026-11-17.** Recorded as ported before it was: the port abbreviated it to `BNKRT` in the price column and left the dividends, the change and the buy controls in place. See D99 |
| Buy control | An amount box whose **placeholder is the largest number you can currently afford**, recomputed whenever your cash or that price changes | **Ported** |

That affordable-maximum placeholder is the original's *only* guidance on
affordability, and it is why an unaffordable purchase could fail silently
(game-rules.md §11).

### 6.5 Your holdings

A row per stalk you own, showing the name, the quantity, and a sell amount box with a
`Sell` button. A row appears when you first buy that stalk and is destroyed when your
holding reaches zero.

**Other players' holdings are hidden.** The original spawns a holdings row object for
every player on every client, then moves the ones that are not yours off screen and
disables them. Functionally: **you cannot see what anyone else owns**, only their net
worth.

**Ported** as written. Making holdings public is a requested change, scheduled as
Phase 8 in `porting-plan.md`.

### 6.6 Player rankings

A row per player: name, net worth, and a **coloured dot** for ready or not ready.
Re-sorted by net worth, descending, whenever any net worth changes.

**Ported.**

### 6.7 Your stats

`Cash on Hand` and `Networth`, both formatted with thousands separators.

**Ported**, with the loan balance added as a third line — the original showed what
you owed only inside the loan panel.

### 6.8 Error messages

A single line in the bottom bar, shown for **3.5 seconds** then hidden. Every
server-side rejection arrives this way, addressed to the one player who caused it.

Messages the original can produce, verbatim:

- `Cannot afford stalk purchase. Cost of stalks is: <n>`
- `You are trying to sell more stalks than you own.`
- `Minimum loan amount is $100.`
- `Loan request of <n> is more than your max available loan of <n>`
- `Loan payment of <n> is less than the minimum payment of: <n>`
- `Loan payment of <n> is more than you cash of <n>`

**Ported** as a mechanism. The port also makes the failures the original handled
silently visible (game-rules.md §11).

---

## 7. The turn loop

There are no turns in the usual sense. Every player acts **simultaneously** and for
as long as they like; the year ends when the last one says so.

1. Players buy and sell freely, in any order, at the same time.
2. Each presses `Ready for New Year`. The button's label becomes `Unready` and can be
   pressed again to take it back.
3. Their dot in the rankings turns green.
4. When **every** player is ready, the server clears all ready flags and runs the
   end-of-year sequence (`game-rules.md` §4.1).
5. Prices, dividends, loans, net worth and rankings all update at once, and the next
   year begins.

**There is no timer.** One idle player stalls the match indefinitely, and there is no
way to nudge or remove them.

On the last year, a warning replaces the bottom-bar text: *"This is the last year of
the game! This is your last opportunity to buy/sell stalks to increase your wealth.
Highest net worth wins, with cash on hand as a tie breaker!"*

**Ported**, including the warning.

---

## 8. Buying and selling

| Action | Flow | Status |
|---|---|---|
| Buy | Type an amount on a board row, press `Buy`. The server prices it, checks your cash, moves the shares and deducts the money | **Ported** |
| Sell | Type an amount on a holdings row, press `Sell`. The server checks you own that many, pays you the current price per share | **Ported** |

Both are validated entirely on the server; the client sends an intent, never a price
or a total. Negative amounts are made absolute, and zero does nothing. Trading is
blocked once the year counter has passed the limit.

**No limits.** There is no cap on how many shares one player may hold, no limit on
how much of a stalk exists, and no market depth: the price is unaffected by anyone
buying or selling. The board is a price table, not an order book.

---

## 9. Loans

Loans are the most elaborate piece of UI in the original. The rules are in
`game-rules.md` §9; what follows is the **flow a player walks through**, which the
rules document does not describe.

The whole thing only exists when the host enabled loans, and only from **Year 2**.

### 9.1 Being offered a loan

From Year 2, a player with no loan and no bankruptcy sees, every year, a prompt in
the bottom bar: *"Would you like to learn about our loans?"* with a **`Tell me more`**
button.

### 9.2 The terms

Pressing it replaces the prompt with the terms panel, which states, verbatim:

> You can take out a loan up 25% of your net worth. The minimum loan is $100. Terms
> are 10 years and 6% interest. If you take out a loan this year, your first payment
> is NEXT year. Penalties for missed payments: 1st missed payment: 10% added to loan
> balance. 2nd: 15% added. 3rd: All assets seized and you are bankrupt

Below it, two figures computed for **you**, now:

- *"The max loan you can take out is: "* — 25% of your current net worth
- *"The minimum payment for the loan would be: "* — what that maximum would cost per
  year

### 9.3 Borrowing

`I want a loan!!!` reveals an amount box whose placeholder is your maximum, and a
`Request Loan` button. On success the panel becomes *"Congratulations on your loan
of: <n>"* and the cash lands immediately.

Rejections come back as error-line messages (§6.8).

### 9.4 Paying

Each year that you have an unpaid loan, the payment panel appears, showing:

- *"Don't forget to pay your loan!"*
- *"The remaining balance on the loan is **X** with **Y** years remaining."*
- *"Your minimum payment is: **Z** (You must pay at least the minimum.)"*
- The penalty schedule, followed by **your** missed-payment count
- An amount box with the minimum as its placeholder, and a `Pay Loan` button

The panel hides as soon as a payment is accepted, and reappears the following year.

### 9.5 The prompt that never fires

The gameplay scene contains a confirmation — *"You haven't paid your loan yet. If you
do not pay, you will be penalized. Are you sure you want to continue to the next
year?"* with a `Yes, continue` button — which is **disabled in the scene and
activated by no code anywhere in the project.** It was built and never wired up.

The port implements it (decisions.md D53): readying up with a payment due asks first.
So this is **Ported**, from an intention rather than from shipped behaviour — worth
knowing if anybody ever compares the two builds and finds the original never asked.

### 9.6 Loan panels and the end of the game

All loan panels are hidden when a player goes bankrupt, and hidden once the year
counter passes the limit — so nobody is offered a loan they could never repay on the
final advance. **Ported.**

### 9.7 One loan per game, forever

Covered in `game-rules.md` §9: the "has a loan" flag is never cleared, so a player
who repays in full still cannot borrow again. It reads like an oversight; it is what
shipped; the port reproduces it (decisions.md D27). Recorded here because it is a
*flow* consequence — the "would you like a loan?" prompt never returns.

---

## 10. Yeehaw

Purely social, no mechanical effect, and the owner calls it a critical feature. Rules
in `game-rules.md` §10.

As a flow: one button in the top bar does both jobs. It reads **`Can I Get a
Yeehaw?`** until somebody asks, then **`Give Yeehaw`** for everybody else; a line of
text names who is asking, and then who answered. The asker cannot answer themselves,
so a solo player can neither give nor receive one.

**Ported**, with two recorded differences: the asker's button is disabled rather than
hidden so the top bar does not reflow (D37), and an unanswered request is cleared
when the year advances, where the original left it pending for the rest of the match
(D52).

---

## 11. Sound

Seven clips, one mixer group, one audio source per clip, all at pitch 1. There is
**no music** — every sound is an event.

| Trigger | Clips played | Status |
|---|---|---|
| A bear year begins | `bear1` **and** `bear2`, together | **Ported** |
| A bull year begins | `bull1` **and** `bull2`, together | **Ported** |
| Any stalk goes bankrupt | `glassShatter` **and** `scream` (a Wilhelm scream), **once per year** however many stalks died | **Ported** |
| A yeehaw is given | `yeehaw`, heard by everybody | **Ported** |
| The volume slider moves | `bull2`, as an audition | **Ported** (improved, §3.5) |

The bankrupt pair is guarded by a once-per-year flag, so a year that kills three
stalks still screams once.

---

## 12. The end of the game

After the final year's advance resolves, every client gets the result:

- **`And the winner is... <name>`**, with ` (cash on hand tie breaker).` appended if
  the tie-break decided it, or ` and <name>` repeated for an unbroken tie.
- Then one of two verdicts, verbatim:
  - Won: *"Congratulations, that's you!!!! You're the best at picking stalks! What a
    useful skill for society!!!"*
  - Lost: *"You're terrible at picking stalks! You're fired and your father will never
    be proud of you!!!"*
- The ready button disappears. Achievements and lifetime stats are submitted (§15).

**Two buttons:** `Quit Game` returns to the title screen, and an **`X`** closes the
result panel so the player can **look back over the final board** — prices, holdings
and rankings as they ended. A second `Quit Game` button appears in the bottom bar so
there is still a way out once the panel is gone.

**Changed.** The port replaces this with a dedicated result screen carrying final
standings and a year-by-year history, plus `Play Again`. It is more informative, but
inspecting the **final board** is not possible. See §17.9.

---

## 13. The pause menu

**Escape** during a match toggles a menu over the board:

| Button | Does |
|---|---|
| `Back to the Game` | Closes the menu |
| `Settings` | Swaps in the same three settings as §3.5, with `Save Settings` and `Back` |
| `Quit Game` | Leaves the match and returns to the title screen |
| `Exit to Desktop` | Quits the application |

The menu does not pause anything — there is nothing running to pause — but it is the
only way to change the volume, go fullscreen, or leave without closing the window.

**Missing.** In the port, Escape during a match asks *"Leave the game and go back to
the title screen?"* and nothing else. See §17.1.

---

## 14. Leaving, disconnects and failure modes

| Situation | What the original does | Status |
|---|---|---|
| A client quits the lobby | Disconnects; their row vanishes for everyone | **Ported** |
| The leader quits the lobby | Host shuts down; everybody is returned to the title screen | **Ported** |
| A client quits mid-match | They are gone. The remaining players continue, and the departed player no longer blocks the ready check | **Ported** |
| The host quits mid-match | The match ends for everyone | **Ported** |
| A disconnected player returns | **Cannot.** There is no rejoin, and their portfolio is simply out of the game | **Ported** (rejoin is a Phase 8 item) |
| The lobby is full | The connection is refused, with no message | **Changed** — the port disables the Join button on a full row |
| The match has already started | The connection is refused, with no message (§3.3) | **Changed** — the port hides started games |
| A player goes bankrupt from loan default | Cash and net worth zeroed, every holding seized, loan destroyed, all loan panels hidden. **They keep playing** with nothing | **Ported** |

Worth stating plainly, because it is easy to assume otherwise: **a bankrupt player is
not removed from the match.** They stay in the rankings at zero, still have to ready
up each year, and can still buy if they somehow acquire cash — which, with no
holdings and no further loan, they cannot. They are a spectator who still has to press
a button.

---

## 15. Achievements and stats

25 Steam achievements and four lifetime stats (`sss_wins`, `sss_loses`,
`lifetime_networth`, `sss_yeehaws`). The full catalogue, the unlock conditions, and
the resolved casing question are in `game-rules.md` §13. **Ported.**

> **Achievements are finished. Never raise them with the owner.** They are implemented
> in code and the subject is closed — no audit, no review, no "worth revisiting" note,
> and no questions. If you need to know how one behaves, read
> `src/data/achievements.gd`, `src/sim/achievement_rules.gd`,
> `src/net/achievement_reporter.gd` and their tests, and verify it yourself. See the
> rule in `CLAUDE.md`. This applies to everything below as much as to the catalogue.

Two audit findings not in that section:

- **`SSS_CHEATED` exists as artwork only.** Achievement art for it ships in the
  original's `AchievementStuff` folder, with achieved and unachieved variants, and
  **no code anywhere sets it.** Recorded as a fact about the original. Closed.
- **End-of-match achievements are evaluated on the client**, from the local player's
  own final figures. The port moves this decision into the simulation
  (`achievement_rules.gd`) and reports from one place, which is both testable and not
  trivially spoofable.

---

## 16. The economy

Deliberately not duplicated. [game-rules.md](game-rules.md) is the authoritative
specification and was itself built from this same source. It covers: the ten stalks
and their statistics (§3), the year pipeline in execution order (§4.1), bull/bear odds
(§4.2), price movement including the contrarian roll and the undocumented long-game
softening (§4.3–4.4), special events (§5), splits (§6), stalk bankruptcy (§7),
dividends (§8), loans in full (§9), trading (§11), the final year and winner
determination (§12), and the six confirmed bugs in the original with the decision
taken on each (§14).

All of it is **Ported** and covered by tests; see `testing.md`.

---

## 17. The gap list

Original functionality that a player would notice is absent or different. This is the
part of the document a porting plan should consume. Ordered by how much a player
would miss it.

### 17.1 No in-game pause menu — **Ported 2026-11-16**

Escape during a match opens an overlay with **BACK TO THE GAME**, **SETTINGS**,
**LEAVE TO TITLE SCREEN** and **QUIT TO DESKTOP**. Escape backs out one step: from
the settings page to the buttons, from the buttons to the game.

**Settings is the same panel the title screen shows** - sound, resolution and
fullscreen - as the original's pause menu reused the title screen's. A volume slider
on the pause menu by itself was the first attempt and answered a third of the
question.

Before this, Escape went straight to "leave the game?" — so the only key that did
anything mid-match was one that offered to end your game. Leaving still asks, behind
the same confirmation; the pause menu emits the request and `Main` owns the question,
because the session being abandoned lives there.

**Differences from the original, both deliberate:**

- Resolution and fullscreen are not offered here, only volume. The original's pause
  menu reused the whole settings panel. Changing resolution mid-match is a larger
  change than it looks (see §17.3's known faults) and was not worth carrying into a
  live game before it works on the title screen.
- It does not pause anything, and neither did the original's: a year only advances
  when every player readies, so there is no clock to stop. The overlay says so.

### 17.2 No way to quit the game from inside it — **Ported 2026-11-16**

**QUIT TO DESKTOP** on the title screen, and the same on the pause menu. Both go
through the session shutdown that closing the window uses (D71), so a host's Steam
lobby is closed properly rather than left standing.

Found the hard way on 2026-11-16: with fullscreen shipped and no quit button
anywhere, Alt+F4 was the only way out of the game.

### 17.3 No resolution or fullscreen settings — **Partly ported 2026-11-16**

The original's settings offered a resolution dropdown and a fullscreen toggle
(§3.5). The port now has both, on the same Settings tab as the volume slider.

**How it works** is in decisions.md D85. In short: the chosen resolution is the size
of the image the game is drawn into, that image is stretched to fill the screen with
black bars where the monitor is not 16:9, and the window cannot be dragged to resize
(§17.10).

**Differences from the original, all deliberate:**

- The list is exact 16:9 sizes capped at what the monitor can show, rather than the
  original's four hardcoded options. The original's 852×480 was an approximation of
  16:9 and the port offers none like it. Every rung is a whole multiple of 640×360,
  which is why 960×540 and 1600×900 were dropped on 2026-11-17 (D96).
- A change is applied and then confirmed, reverting after fifteen seconds if nobody
  answers. The original applied immediately with no way back if the result was
  unreadable.
- Settings are saved when kept, rather than by a separate **Save Settings** button.
- A first run is the monitor's own largest 16:9 size, fullscreen. The original's
  fallback was 1920×1080 windowed.

**Settled on 2026-11-17, not broken:**

- **The resolution does nothing in fullscreen**, and will not. The monitor's own
  size is the window there. D96 states the position plainly: a pixel-art game
  drawn at 640×360 has one picture size, and the only question is how many times
  it is enlarged. **The dropdown is greyed out in fullscreen**, which is now a
  true statement about the design rather than a placeholder.

**Still open:**

- **The list is capped on the taskbar-free area rather than the whole screen**, so
  a 2560×1440 monitor is not offered 2560×1440. One line in
  `DisplayMode.screen_size`. It matters less than it reads: the cap only applies to
  *windowed* sizes, where a window as tall as the screen would not fit anyway, and
  fullscreen ignores the setting entirely. Left alone rather than fixed, because
  changing it would start offering window sizes that do not fit.

### 17.4 The host cannot choose a player limit - **Ported 2026-11-16**

**Max players**, 1 to 10, default 4, on the Host Online panel. It sets the Steam
lobby's member limit at creation as the original did, and `HostSession.seat_count()`
enforces it for a direct connection too, which the original had no equivalent of.

A single-player game is one player whatever the hidden control holds. See
decisions.md D87, which also records why `GameSettings.player_count` defaults to ten
rather than to the form's four.

### 17.5 The lobby browser shows less than the original's - **Ported 2026-11-16**

A row now carries the game's name and `n/max` as before, and underneath them the
year limit, the starting cash and whether loans are on.

Published as Steam lobby data when the lobby is created, which is how the original
did it: `NumberOfYears` and `LoansEnabled` existed for exactly this. **Starting cash
goes further than the original**, which never published it - a joiner could not tell a
10,000 game from a 150 one until they were already in the lobby, where nothing shows
the settings either (4).

**Anything a lobby did not publish is left out rather than guessed.** A lobby created
by a build that predates this has none of the three, and a row claiming ten years
because that is the usual answer would be worse than a row that says nothing.

### 17.6 No search in the lobby browser - **Ported 2026-11-16**

A search box above the list, filtering by name, case-insensitive substring, as the
original did.

**Two deliberate improvements.** It filters as you type rather than behind a Search
button, and **the filter does not stick**: emptying the box puts the whole list back
at once, and a refresh re-applies whatever is in the box right now. The original kept
a "did the player search" flag that was cleared only on a path the normal flow never
reached, so once you had searched the filter went on applying to every later refresh
for the rest of the session (3.3).

### 17.7 No Steam avatars - **Ported 2026-11-16**

Each lobby row shows that player's Steam portrait, as the original's did, including
the case where Steam has not cached it yet and it arrives after the row was built.

**What it needed.** Nothing in the port knew which Steam account a player was. A
player now carries a `steam_id`, which is 0 for anybody on a direct connection; a
client states its own when it introduces itself, and it travels in the snapshot so
every client can draw every portrait. See decisions.md D92 for why that sits beside
`display_name` rather than being kept out of the simulation.

**A lobby with no portraits looks like a lobby with no portraits.** Nothing reserves
space for one, so a local game is unchanged.

**Confirmed in play 2026-11-16.** Portraits appear in the lobby. They are visibly
pixelated, because the smallest size Steam offers is 32 pixels square and the lobby
draws on a 640x360 grid where a row is sixteen tall. The owner looked at it and left
it alone deliberately, so do not "fix" it by asking Steam for a larger portrait.

### 17.8 No supporter DLC thank-you message - **Ported 2026-11-16**

**Thanks for Supporting the Devs!** appears under the tagline on the title screen
for a player who owns the supporter DLC.

The original checked for a file called `support-dlc.txt` next to the executable,
which anybody could create. The port asks Steam whether the DLC is owned, using the
DLC's own App ID - **1856290**, which is its own number and not the game's 1821800.
Owning the game says nothing about owning this.

**False whenever Steam is not running**, which includes every offline game and every
test. A thank-you that appeared because the question could not be asked would be
worse than no thank-you. See decisions.md D91.

**Confirmed in play 2026-11-16** against an account that owns the DLC.

### 17.9 The final board cannot be inspected - **Ported 2026-11-16**

The result screen has a **View board** button. It puts the finished board back on
screen - prices as they ended, your holdings, the rankings - and the bottom bar's
button becomes **BACK TO RESULTS**, which is the way out of it again.

The original did this by closing its winner panel to reveal the board underneath,
and put a second Quit Game button in the bottom bar so there was still a way out.
The port's result screen **replaced** the board rather than covering it, so getting
back means rebuilding it. That works because `Main` owns the session, which outlives
the playing screen: the board renders the match exactly as it ended rather than a
fresh one. See decisions.md D90.

Nothing is disabled on the way in. Trading is already refused once the year counter
passes the limit, and the loan panels hide themselves at game over, so a finished
board is inert without anybody switching it off.

### 17.10 The window is resizable, and nobody chose that — **Fixed 2026-11-16**

The original explicitly set `resizableWindow: 0` in its Unity player settings: a fixed
1920×1080 window that the player could not drag. The port's window resizes freely.

**That was never a decision.** `window/size/resizable` does not appear anywhere in
`project.godot`, and `decisions.md` has no entry about it. The window is resizable
because **`true` is Godot's default and nothing ever turned it off.**

`ui-reference.md` compounded this by listing resizability under "Where the port
deliberately differs", describing an engine default as a design choice. That claim has
been corrected; the behaviour has not been changed, because changing it is a decision
for the owner and this audit changes nothing.

**Done 2026-11-16.** `window/size/resizable=false` in `project.godot`. The
resolution dropdown added with it (§17.3) is how a player changes the size now.

**The reason, from play, and it is a bug rather than a preference.** Dragging a window
by its title bar in Windows means passing close to the resize handle. Catch it and
shrink the window by a single pixel below a whole multiple of 640×360, and
`scale_mode = integer` has no choice but to drop a whole step — ×3 becomes ×2 — so the
game abruptly renders at two thirds the size inside a large border. A one-pixel slip
produces a drastic, visible jump. The owner reported exactly this.

That interaction is inherent to integer scaling of a resizable window: there is no
setting that makes the step smaller, because the steps *are* whole numbers. A fixed
window removes the input that triggers it, which is why it is the right fix rather
than a workaround.

This entry is the clearest illustration of why the audit was worth doing. It is not a
missing feature anyone would have thought to look for — it is a difference from the
original that arrived by default, went unnoticed, and then got written up in the
documentation as intentional.

### 17.11 The volume scale changed — **Changed**, no action needed

The original's slider was −35 to +5 decibels with 0 as the default, so the default sat
most of the way to the right and the leftmost position was quiet but audible. The port
uses 0–100% with 100 as the default. Recorded only so nobody "restores" the decibel
scale thinking it was lost by accident.

---

## 18. Port functionality the original never had

Listed so that a plan aimed at parity does not treat these as surplus and remove them.
All are already built.

| Addition | Why it exists |
|---|---|
| **True single-player, with no Steam** | The original could not start without Steam running. The port's simulation runs with no peer at all |
| **Direct host/join over ENet** | Playing on a LAN, and testing two instances on one machine, without Steam |
| **A seeded match** | The RNG seed is match state and is shown on the result screen, so any game can be replayed exactly. The basis of every determinism test |
| **A typed player name for local games** | Online play still uses the Steam persona |
| **Year-by-year history on the result screen** | The original kept no record of a finished match |
| **The loan balance in Your Stats** | The original showed it only inside the loan panel |
| **Confirming a turn with a payment due** | Built in the original and never wired up (§9.5) |
| **Visible purchase rejections** | The original failed silently in some paths |
| **In-progress games hidden from the browser** | The original listed them and then refused the connection |
| **Join disabled on a full lobby row** | Same reasoning |
| **Launching straight into an accepted invite** | Works even when the game was closed |
| **Scrolling stalk names** | The original's column truncated eight of the ten names |

---

## 19. Original behaviour deliberately not reproduced

| Behaviour | Why not |
|---|---|
| Silent rejection of invalid create-game input | Replaced by clamped inputs, so the state cannot be reached |
| Silent rejection on a full or in-progress lobby | Replaced by not offering the join |
| Fetching the lobby list only when it is empty | A stale list behind a tab is a bug, not a feature |
| A search filter that sticks across refreshes | Same |
| Steam as a hard requirement | The port must run without it |
| The unreachable "haven't paid" confirmation | Built properly instead (§9.5) |
| The six economy bugs in `game-rules.md` §14 | Each has a recorded decision |
| Letting a readied player keep trading (§7 step 1) | One stray click could sell everything a heartbeat before the year turned. Readying now closes your own board until you un-ready (D97) |

---

## 20. Questions this audit raised

Decisions for the project owner, not a developer's judgement. All raised and answered
on 2026-11-16, recorded here so the answer travels with the finding.

**Items 4, 4a and 5 are built** (§17.3, §17.10; decisions.md D85). Everything else
below is decided and unbuilt.

### Answered

1. **The player limit** (§17.4) — **restore the host's field.** A 1–10 limit on the
   Create Game form, applied as the Steam lobby's member limit, as the original did.
   `GameSettings.player_count` already exists for it.
2. **What a browser row shows** (§3.2, §17.5) — **years, loans and starting cash.**
   The original published years and loans; starting cash is added because it changes
   how a game plays and a joiner should see it before committing. This goes further
   than the original deliberately.
3. **Inspecting the final board** (§17.9) — **add a view-board button.** The result
   screen's history does not replace being able to study the finished board, so the
   result screen needs a way to stand aside and a way back.
4. **Resolution** (§17.3) — **build the dropdown, listing window sizes that fit the
   monitor.** As the original had, minus its one real cost: the game never changes the
   monitor's video mode, so Godot's inability to enumerate display modes does not
   matter and no native extension is needed (D77).
4a. **Fullscreen** (§17.3) — **build the toggle, borderless, letterboxed on a monitor
   that is not 16:9** so every player sees the same content (D84).
5. **The window** (§17.10) — **fixed, not resizable.** As the original had. Driven by
   a reported bug, not a preference: a one-pixel accidental resize makes an
   integer-scaled window jump a whole scale step.

Items 4 and 5 together revise **D40**, which chose integer scaling without settling
either. All five need a `decisions.md` entry when the work is scheduled; the audit is
where the answer was captured, not where it belongs permanently.

6. **The supporter DLC message** (§17.8) — **check Steam DLC ownership and show the
   message.** No file check.

**Nothing in this audit is open.** Every question it raised has been answered. If a
later session finds a genuinely new question, it goes here with the same discipline:
one line, the decision, and a pointer to the entry it settles.

---

## 21. Keeping this document current

This is a snapshot of the **original**, which cannot change, against the **port**,
which does. The left-hand side of every table is permanent; the status marks are not.

When a gap in §17 is closed, change its status, move its entry into the body of the
document as **Ported**, and note it in `porting-plan.md`. When an open question in §20
is answered, replace it with the decision and add an entry to `decisions.md`.

The audit itself does not need redoing. Every claim in it was read out of the
original's source and scenes, and that source is frozen.
