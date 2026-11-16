# Manual testing

What a person has to check by hand, why, and what counts as a failure.

Keep this open on screen while testing. It is written to be worked through in
order.

---

## Why anything is manual at all

436 automated tests already cover the economy, the year pipeline, the loan
rules, every screen, and a real host and client exchanging RPCs. Do not re-test
any of that by hand — if it were broken, the suite would be red.

Three things the suite **cannot** reach, and they are the only reasons to do
this:

1. **Two separate computers.** The suite runs two peers in one process. A
   second machine introduces a real network, a firewall, and two copies of the
   game that were built rather than run from source.
2. **Steam's relay.** The suite must pass on a machine with no Steam client at
   all, so it never calls Steam. Lobby creation and peer creation were checked
   by hand on one machine; two *accounts* have never met.
3. **Whether any of it feels right.** Nothing automated has an opinion about
   layout, wording, or a screen that looks frozen when it is waiting.

---

## Test A — two machines, no Steam

**What this tests:** that the game is playable between two real computers at
all. The network, the firewall, the exported build, and every piece of
gameplay as experienced by two people.

**What it does not test:** Steam. Nothing in this test touches it, and Steam
does not need to be running.

**Do this one first.** If it fails, the problem is the game or the network. If
it passes and Test B fails, the problem is specifically Steam. Running Steam
first conflates the two and you learn less from a failure.

### Setup

1. Copy the whole `stalks-build` folder to the second machine. All five files
   — the `.exe` alone will not run.
2. On the machine that will host, find its address. From the project folder:

   ```
   & "C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --script res://tools/lan_check.gd
   ```

   It prints the address to type, and alternatives if the first does not work.
3. Launch the game on both machines.

### A1. Connecting

| Step | Expected |
|---|---|
| Host: **CREATE GAME** → **HOST LOCALLY** | Lobby screen. Subtitle names an address and port. |
| Guest: **JOIN**, type that address, **Join** | Guest reaches the lobby; both players listed on both screens. |

**Windows will probably ask to allow the game through the firewall the first
time it listens. That prompt must be allowed** or nothing will connect, and the
failure is silent.

**Failure signs:** guest never reaches the lobby; host's list stays at one
player; guest sits on "Joining...". Nearly always the wrong address of several,
or the firewall prompt dismissed.

### A2. The lobby

| Step | Expected |
|---|---|
| Guest presses **READY** | Guest's row shows READY on *both* screens. Host's status stops naming them. |
| Host presses **START** before the guest is ready | Nothing. The button is disabled; the status says who it is waiting for. |
| Host presses the **X** on the guest's row | Guest is returned to the menu with a reason. Host's list drops to one. |

The guest rejoins after that last one; it is the kick test.

**Failure signs:** readiness not crossing between machines; Start working while
somebody is unready; a kicked player left sitting in the lobby.

### A3. Starting

| Step | Expected |
|---|---|
| Both in lobby, guest ready, host presses **START** | **Both** reach the playing board. Year 0. |

**Failure signs:** host reaches the board and the guest does not, or the guest's
board is blank. This exact bug happened once and was fixed (decisions.md D50) —
worth confirming it stays fixed.

### A4. The board at year 0

Year 0 is deliberately inert: no trading until year 1. What should still work:

| Step | Expected |
|---|---|
| Either player presses **Ready for New Year** | Button becomes "Waiting...". Their dot turns green in the other player's rankings. The status names who it waits for. |
| Press it again | Un-readies. Button returns to "Ready for New Year". |
| Both ready | Year 1 arrives on both screens together. |

**Failure signs:** pressing Ready changes nothing on screen. That was a real bug
(D51) and is the thing most likely to feel broken rather than look broken.

### A5. Trading

| Step | Expected |
|---|---|
| Guest buys 3 of a stalk | Guest's cash drops, holding appears. |
| Look at the host's rankings | Guest's **net worth does not change.** |
| Guest's own net worth, on their own screen | Also unchanged. |
| Look at the host's view of the guest's **cash** | It must **not** match. Cash is private. |
| Guest types a quantity, host buys something meanwhile | Guest's typed quantity is still there. |
| Guest tries to buy far more than they can afford | Refused, with a reason on screen. Nothing bought. |

**Why net worth must not move.** Buying converts cash into shares at that
moment's price, so nothing is gained or lost by the act of buying — net worth
is cash plus holdings valued at the current price. It moves when **prices**
move, at the end of a year. A net worth that drops when you buy would mean the
host was subtracting the cash without counting the shares.

*(This table previously said net worth changes on a buy. It was wrong, and the
owner caught it in play. Corrected here rather than quietly: a test document
that states a wrong expectation will have somebody chasing a bug that is not
there, or waving through one that is.)*

**Failure signs:** net worth moving on a trade; a rival's exact cash visible; a
typed quantity vanishing when somebody else trades; a refusal with no message.

### A6. A year with both players

| Step | Expected |
|---|---|
| Both ready up | Year advances on both. |
| Compare every stalk price on the two screens | Identical. |
| Compare the event text | Identical. |

**Failure signs:** any price differing between machines. That would mean a
client computing economics instead of receiving them, which the whole design
forbids.

### A7. Yeehaw

| Step | Expected |
|---|---|
| Host presses **Can I Get a Yeehaw?** | Guest's button becomes **Give Yeehaw**. Host's goes grey. Both see a message naming the asker. |
| Guest presses **Give Yeehaw** | Both see a message saying who gave it to whom. Both buttons return to asking. |

**Failure signs:** the other player's button not changing; no message on the
guest's screen. Both were real bugs (D54).

There is **no sound yet** — that is Phase 7. Silence is correct.

### A8. Loans

Needs year 2 or later.

| Step | Expected |
|---|---|
| Open **LOANS**, borrow the maximum | Panel closes. Message says how much, and that the first payment is next year. |
| Open it again | "Pay minimum" is greyed, with a tooltip saying why. The warning says nothing is due yet. |
| Try to borrow more than allowed | Panel stays open with the reason **inside** it. |
| Next year, press **Ready** without paying | A confirmation appears naming the penalty. |
| Choose **Pay first** | The loan panel opens. |
| Look under the **LOAN** button | The minimum payment is shown there, and matches the panel. |
| Press **Escape** with the loan panel open | The panel closes. Nothing asks about leaving the game. |

**Failure signs:** panel staying open after a successful borrow; a refusal with
no visible reason; readying up with a payment due asking nothing; the minimum
under the button disagreeing with the panel.

### A8a. Sound and the volume control

One machine, no Steam, no second player.

| Step | Expected |
|---|---|
| Start a single-player game and advance a year | **Two** clips together — a bull pair or a bear pair, not one sound. |
| Keep advancing until a stalk goes bankrupt | Breaking glass **and** a scream, once for the year. |
| Give a yeehaw (needs a second player, so skip if alone) | The yeehaw clip. |
| Title screen: **SETTINGS** | A **Sound** slider, and no "Your name" field. |
| Drag the slider | A clip plays at each step, and the percentage follows it. |
| Set it to 0, start a game, advance a year | Silence, not a faint sound. |
| Quit, relaunch, open **SETTINGS** | The slider is where you left it. |

**Failure signs:** one clip where there should be two; a bankruptcy sounding
once per stalk rather than once per year; the slider not moving the volume;
the volume forgotten between runs.

### A8b. The bottom bar holds still

| Step | Expected |
|---|---|
| Note where the bottom bar's top edge is at year 0 | — |
| Advance a year and look again | Exactly the same place. |
| Take a loan and let a payment fall due | Still the same place. |

**Failure signs:** the boards jumping up or down by a line as the text in the
bar gets shorter or longer. See decisions.md D63.

### A8c. Getting out

| Step | Expected |
|---|---|
| Mid-match, press **Escape** | "Leave the game and go back to the title screen?" |
| Choose **Keep playing** | Back to the board, match untouched. |
| Press **Escape**, choose **Leave** | Title screen. |
| On the title screen, press **Escape** | Nothing happens. |

**Failure signs:** no way out but closing the window — which is what this
replaces. Escape offering to leave while a panel is open (it should shut the
panel instead).

### A9. Disconnection

| Step | Expected |
|---|---|
| Mid-match, close the guest's window entirely | Host's rankings drop to one player, and a message names who left. |
| Host readies up | **The year still advances.** |
| Start again, and this time close the **host's** window | Guest lands on the title screen, told the host closed the game. |

### A9a. Failures say what went wrong

| Step | Expected |
|---|---|
| Host locally on a port, then from a second window host locally on the same port | "Could not listen on port NNNNN: something else may already be using it." |
| **JOIN GAME**, type an address nothing is listening on, **JOIN LOCALLY** | A sentence naming the address, not a code. |

**Failure signs:** any message ending in a number in brackets, like "(24)".
See decisions.md D74.

### A9 continued

**Failure signs:** the host stuck unable to advance — that was the deadlock
behind D46/D47 and is the single most important thing in this test. On the
other side, a guest left sitting on a board that answers every click with "Not
connected" instead of being told what happened; that was the state before D61.

**What still does not happen:** there is no rejoin. A player who drops is out
for the rest of that match, and if the host drops the match is over for
everybody. That is a known gap, not a fault — see porting-plan.md.

---

## Test B — two Steam accounts

**What this tests:** only that Steam's relay carries traffic between two
different users, and that lobbies are findable. Everything else was already
proven in Test A and does not change with the transport.

**Prerequisites that are easy to get wrong:**

- Steam running and signed in on both machines, with **different** accounts.
- The second account must **own the game or be in the app's developer group**
  in the Steamworks partner site. Steam refuses to initialise otherwise, and
  that is the likeliest first failure.
- A `steam_appid.txt` containing `1821800` next to the `.exe` on both machines,
  since the builds are being launched directly rather than through Steam.

### B1. Steam starts at all

| Step | Expected |
|---|---|
| **JOIN GAME** → **BROWSE ONLINE GAMES** | The list says "Signed in as <your persona name>". |

**Failure signs:** a message saying Steam is not running, or not installed.
If Steam *is* running, suspect the account ownership above.

### B2. Finding each other

| Step | Expected |
|---|---|
| Machine 1: **CREATE GAME** → **HOST ONLINE** | Lobby screen. Subtitle mentions invites, not a port. |
| Machine 2: **JOIN GAME** → **BROWSE ONLINE GAMES**, then **REFRESH** | Machine 1's game appears in the list, under the name they gave it. |
| Both: look at the lobby heading | The game's name, the same on both machines — not "LOBBY" or "JOINED". |
| Both: look at the player list | Steam names, not "Player". Type something in **Your name** first and check it is ignored for an online game. |
| Machine 2: **JOIN** on that row | Both reach the lobby, as in A1. |

**Failure signs:** the lobby never appearing in the list. Both accounts must be
running the same App ID, and the lobby is filtered on a `game=stalks` tag.

### B3. The settings reach an online game

The bug from the first Steam game: a match hosted through Steam always had
loans off, whatever the title screen said. The settings now sit on the same
panel as the button that starts the game, so there is nothing to carry.

| Step | Expected |
|---|---|
| **CREATE GAME**, set Years to 25, tick **Loans** | — |
| **HOST ONLINE**, then **Start** in the lobby | The board reads **Year: 0/25** and the **LOANS** button is there. |
| Leave, untick **Loans**, **HOST ONLINE**, **Start** | No **LOANS** button. |

You do not need the second account for this — a host can start alone.

**Failure signs:** the match not matching what you ticked. See decisions.md
D65.

**There are no settings on the online games list**, deliberately. It is for
finding a game to join; a joiner is told the settings by the host.

### B3b. The host leaving ends the game

Steam has no way to destroy a lobby — one lives until its last member leaves
— so the host shuts theirs on the way out and tells everyone. See
decisions.md D68.

| Step | Expected |
|---|---|
| Both in a lobby. Machine 1 (host) presses **LEAVE** | Machine 2 lands on the title screen, told the host left. |
| Machine 2: **BROWSE ONLINE GAMES**, **REFRESH** | The game is gone from the list. |
| Repeat, but have the host **close the window** instead of pressing LEAVE | Same outcome on machine 2. |
| Host starts a match, then machine 2 browses | The started game is not listed. |

**Failure signs:** machine 2 sitting on the lobby with a Ready button that
does nothing — the fault this was written for. A game still listed after it
started or after its host left.

### B3c. Invites

Phase 6 is not done until two accounts can meet this way as well as through
the browser. See decisions.md D69.

| Step | Expected |
|---|---|
| Machine 1: host online, then press **INVITE** in the lobby | Steam's own friend picker opens. |
| Host **locally** instead | No INVITE button. |
| Invite the second account | The invitation arrives. |
| Machine 1: tick **Invite only** on Create Game, host, and have machine 2 **REFRESH** the online list | The game is not listed. |

**Failure signs:** no INVITE button on an online game, or one on a local game;
the picker not opening; an invite-only game appearing in the list.

> **Accepting an invite cannot be tested before the port is uploaded.** Steam
> launches whatever is installed for App ID 1821800, which is the published
> Unity original, so following an invitation starts the old game no matter
> what is running locally. The same goes for a cold start through
> `+connect_lobby`. Both are written and both wait on a Steam branch upload.
> See decisions.md D57.

### B4. Playing

Repeat **A3 through A7** over the Steam connection. They are the same screens
and the same code; what is being checked is that the traffic arrives.

**Failure signs:** anything that worked in Test A failing here points at the
Steam transport specifically, which is a much narrower place to look.

### Known gaps, so they are not surprises

- **Steam invites do not work yet.** Accepting an invite reports to the game,
  but nothing acts on it. Use the browser.
- **Achievements are not being tested, on purpose.** They are implemented and
  their thresholds are covered by 28 tests, but the App ID is the published
  game's, so unlocking one here awards it for real on the tester's Steam
  account. `resetAllStats(true)` is the only undo and it wipes everything.
  See decisions.md D70.
- **No sound.**
- **A kick takes a few seconds to land over Steam**, where it is immediate over
  a direct connection. Steam's lobby callbacks are not instant and the game
  waits for them rather than guessing; it is slow, not broken. Observed in the
  first two-account game and left alone.

---

## Reporting back

For anything that fails, the useful things are: which step, what you expected,
what happened instead, and a screenshot if it is visual. Layout faults have
been diagnosed far faster from a screenshot than from a description.

If a build misbehaves, run `StalksStalksStalks.console.exe` instead of the
plain one — it prints errors to a terminal window.
