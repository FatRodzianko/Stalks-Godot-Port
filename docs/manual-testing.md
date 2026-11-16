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

One step per line, in order. Sub-steps belong to the step above them.

1. Start a single-player game.
2. Advance a year.
   - **Two** clips together: a bull pair or a bear pair, never one sound.
3. Keep advancing until a stalk goes bankrupt.
   - Breaking glass **and** a scream.
   - Once for the year, however many stalks went under. Two in one year is
     uncommon in play — the once-per-year rule is covered by
     `test_audio_service.gd` rather than by hand.
4. Give a yeehaw. (Needs a second player. Skip it if you are alone.)
   - The yeehaw clip.
5. Return to the title screen and open **SETTINGS**.
   - A **Sound** slider.
   - No "Your name" field.
6. Drag the slider from one end to the other without letting go.
   - The percentage follows your finger.
   - **No sound at all while you are dragging.**
7. Let go, wait for the clip to start, and immediately drag again.
   - The clip stops the moment the drag begins.
   - It does **not** ride the volume up and down as you drag.
8. Let go.
   - One clip, at the volume you landed on.
9. Click once on the far left of the slider track.
   - One clip, and the previous one cut off if it was still sounding.
10. Set the slider to 0, start a game, advance a year.
    - Silence, not a faint sound.
11. Quit, relaunch, open **SETTINGS**.
    - The slider is where you left it.

**Failure signs:** one clip where there should be two; a bankruptcy sounding
once per stalk rather than once per year; clips overlapping into an echo, which
is the fault D74 was amended for; the volume forgotten between runs.

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

### A8d. Resolution and fullscreen

Nothing here has been seen running. These steps are the first look.

1. Start the game.
2. Check that it opens **fullscreen**, filling the screen.
3. Check that the picture is not stretched out of shape.
4. If your monitor is not 16:9, check there are even black bars and no
   distortion.
5. Press **Escape** to reach the title screen if the game opened elsewhere.
6. Click the **SETTINGS** tab.
7. Check there is a **Resolution** dropdown and a **Fullscreen** tick box.
8. Open the Resolution dropdown.
9. Check every entry is 16:9 and none is larger than your monitor.
10. Select **1280 x 720**.
11. Check the picture changes immediately.
12. Check a "Keep this display setting?" prompt appears with a countdown.
13. Do nothing for fifteen seconds.
14. Check the display goes back to what it was by itself.
15. Select **1280 x 720** again.
16. Click **Keep it**.
17. Check the prompt closes and the display stays.
18. Untick **Fullscreen**.
19. Click **Keep it**.
20. Check the game is now a 1280x720 window, centred.
21. Try to drag the window's edge or corner to resize it.
22. Check it cannot be resized.
23. Drag the window by its title bar.
24. Check the picture does not jump in size while dragging.
25. Close the game.
26. Start it again.
27. Check it opens as a 1280x720 window, not fullscreen.
28. Open **SETTINGS** and move the volume slider.
29. Close the game, start it again, and check it is **still** a 1280x720
    window — changing the volume must not reset the display.
30. Set the resolution back to the largest on the list and tick Fullscreen.

**Known broken as of 2026-11-16, left deliberately — do not re-report:**

- The resolution does nothing in fullscreen. The game draws at 640 x 360 and
  stretches, whatever is selected.
- A 2560 x 1440 monitor is not offered 2560 x 1440, because the list is capped
  on the taskbar-free height.

Steps 8 to 17 and 20 to 29 therefore only mean something in windowed mode.
See decisions.md D85.

### A8e. Getting out of the game

1. Start the game and reach the title screen.
2. Check there is a **QUIT TO DESKTOP** button at the bottom of the panel.
3. Click it.
4. Check the game closes.
5. Start the game again and begin a single-player match.
6. Press **Escape**.
7. Check a **PAUSED** panel appears with **BACK TO THE GAME**, **SETTINGS**,
   **LEAVE TO TITLE SCREEN** and **QUIT TO DESKTOP**.
8. Click **SETTINGS**.
9. Check it holds Sound, Resolution and Fullscreen, the same as the title
   screen.
10. Move the Sound slider.
11. Check no sound clip plays while you move it.
12. Press **Escape**.
13. Check it goes back to the four buttons rather than closing altogether.
14. Press **Escape** again.
15. Check the panel closes and the board is still there.
16. Press **Escape** once more.
17. Click **LEAVE TO TITLE SCREEN**.
18. Check it asks before leaving.
19. Click the cancel option.
20. Check you are still in the match.
21. Press **Escape**, click **LEAVE TO TITLE SCREEN**, and confirm it this time.
22. Check you are on the title screen.
23. Begin another match, press **Escape**, and click **QUIT TO DESKTOP**.
24. Check the game closes.

### A8f. The rebuilt title screen

1. Start the game.
2. Check the top of the panel reads **SINGLE PLAYER**, **HOST ONLINE**,
   **JOIN GAME**, **SETTINGS**.
3. Check **SINGLE PLAYER** is the one already selected.
4. Click each of the four in turn.
5. Check the panel stays exactly the same size on all four.
6. Check the title text does not move as you click between them.
7. Check the **QUIT TO DESKTOP** button does not move either.
8. Click **SINGLE PLAYER**.
9. Check there is a **Your name** field.
10. Check there is no game name, no max players and no invite-only control.
11. Click **HOST ONLINE**.
12. Check **Your name** is gone.
13. Check there is a **Game name**, a **Max players** and an **Invite only**
    control.
14. Check **Max players** starts at 4.
15. Check the years, starting cash, loans and seed controls are the same on
    both panels.
15a. Type 1234 into starting cash and check it stays 1234 rather than
     rounding to 1200.
15b. Type 70000 and check it is held at 69420.
15c. Type 1 and check it is raised to 150.
16. Check the button at the bottom reads **HOST ONLINE** here and **START** on
    the Single Player panel.
17. Click **JOIN GAME**.
18. Check the lobby list is already loading, with no button to press first.
18a. Check there is no noticeable pause before the panel appears - Steam is
     started at launch now, not on this click.
19. Check there is a search box and a **REFRESH** button.
20. Check there is no address or port field anywhere on the title screen.
21. Look at the top-left corner of the window.
22. Check there is a small **DEV** panel with Host, Port, and HOST and JOIN
    buttons.
22a. Click into its **Host** field and type something.
22b. Check the field accepts the typing - it must not be behind the title
     screen.
23. Press **F1**.
24. Check the development panel disappears, leaving the title screen clear.
25. Press **F1** again and check it comes back.
26. Click **SETTINGS**.
27. Check it holds Sound, Resolution and Fullscreen.
28. Change the resolution.
29. Check the "Keep this display setting?" prompt is in the game's own font and
    colours, not a plain white system dialog.

**With a second Steam account hosting**, in Test B:

29a. Have the other account host a game with a year limit and starting cash
     that are not the defaults, and loans on.
30. Open **JOIN GAME** and check the search box is **below** the list.
30a. Check their row shows the year limit, the starting cash and "loans".
30b. Have them host again with loans off and check the row says "no loans".
31. Check their game is listed.
32. Type part of their lobby name into the search box.
33. Check the list narrows as you type.
34. Clear the search box.
35. Check the whole list comes back.
36. Type something that matches nothing and check it says so.
37. Click **REFRESH** with text still in the search box.
38. Check the filter is still applied and the list is not stale.

### A8g. The final board, after the match

1. Play a short single-player game through to the end.
2. Check the result screen appears.
3. Check there is a **View board** button beside Main menu and Play again.
4. Click **View board**.
5. Check the board comes back with the final prices.
6. Check your holdings are still listed as they ended.
7. Check the rankings show the final net worth of every player.
8. Check the bottom bar button reads **BACK TO RESULTS**.
9. Try to buy a stalk.
10. Check it is refused - the match is over.
11. Click **BACK TO RESULTS**.
12. Check the result screen comes back, with the standings still right.
13. Click **View board** and **BACK TO RESULTS** twice more.
14. Check nothing breaks or goes blank.

### A9. Disconnection

| Step | Expected |
|---|---|
| Mid-match, close the guest's window entirely | Host's rankings drop to one player, and a message names who left. |
| Host readies up | **The year still advances.** |
| Start again, and this time close the **host's** window | Guest lands on the title screen, told the host closed the game. |

### A9a. Failures say what went wrong

One machine. No Steam, no second player needed.

1. Host locally on the default port.
2. Launch a second copy of the game and host locally on the **same** port.
   - "Could not listen on port NNNNN: something else may already be using it."
3. Change the port on the second copy and host again.
   - It hosts.
4. **JOIN GAME**, clear the address field, type `nope`, **JOIN LOCALLY**.
   - "Could not find nope. Check the address for a typo."
   - You stay on the title screen. Nothing is swapped.
5. **JOIN GAME**, type a real address with nothing listening on it (`127.0.0.1`
   on a port nobody is hosting), **JOIN LOCALLY**.
   - The lobby appears, saying it is connecting.
   - After about twelve seconds you are returned to the title screen with
     "Could not reach the host. They may have left."

**Failure signs:** any message ending in a number in brackets, like "(24)".

**Why step 5 is not an error message about the address.** ENet is UDP, so a
valid address with nothing on it cannot refuse the connection — opening the
socket succeeds and there is nothing to report yet. The failure can only be a
timeout, which is why it takes a few seconds and why the wording is about the
host rather than the address. Step 4 is the only client-side failure that knows
anything at the moment it happens. See decisions.md D74.

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
