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

27a. Tick **Fullscreen** and check the Resolution dropdown greys out.
27b. Untick it and check the dropdown becomes usable again.

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
24. Check it **asks before closing**, the way LEAVE TO TITLE SCREEN does, and that the pause panel gets out of the way behind the question.
25. Click the cancel option.
26. Check you are still in the match, with the board as you left it.
27. Press **Escape**, click **QUIT TO DESKTOP**, and confirm it this time.
28. Check the game closes.
29. Start the game again and, from the title screen, click **QUIT TO DESKTOP**.
30. Check it closes **without** asking - there is no match to lose from there.
31. Start the game again, begin a match, and click the window's X.
32. Check it closes without asking (D71 - a confirmation in front of a window that is already going is an argument with somebody who has finished).

**Steps 24-32 were added on 2026-11-19**, after the owner met the fault in play:
QUIT TO DESKTOP sat two buttons under one that asks and closed the game on the
press. The three cases above are deliberately not the same, and D117 says why.

### A8h. The studio splash

1. Start the game.
2. Check the Glacial Lake Studios logo appears before the title screen.
3. Check it fades in rather than appearing at once.
4. Check it does not move or grow at all.
5. Check it sits in the middle with a black border all the way round.
6. Check it fades out rather than cutting.
7. Check the title screen follows it.
8. Check the whole thing takes roughly four and a half seconds, with the
   fade in the slowest part of it.
9. Start the game again and press a key while the logo is showing.
10. Check it disappears immediately and the title screen appears.
11. Start the game again and click the mouse while the logo is showing.
12. Check that skips it too.
13. Start the game with `--host` on the command line.
14. Check there is no logo and it goes straight into hosting.

**What to look at, not just click through:** the logo is drawn at exactly twice
its own size, so its pixels should be clean squares with no soft edges and no
uneven rows. It moved in the first version and that is why it does not now -
see decisions.md D93.

### A8i. The CRT effect

1. Start the game.
2. Click SETTINGS.
3. Check there is a row labelled CRT with an unticked box beside it.
4. Tick the box.
5. Check the picture changes the moment you tick it, with no confirmation
   prompt and no countdown.
6. Check the corners of the screen are darker than the middle.
7. Check straight edges near the edges of the screen bow outwards slightly.
8. Check there is faint horizontal banding across the dark background.
9. Check the text is still readable.
10. Click SINGLE PLAYER and start a game.
11. Check the effect is still on during the match.
12. Press Escape.
13. Check the pause menu is drawn through the effect like everything else.
14. Click SETTINGS on the pause menu.
15. Check the CRT box is ticked there too.
16. Untick it.
17. Check the picture goes back to normal at once.
18. Quit the game and start it again.
19. Open SETTINGS and check the box is still unticked.
20. Tick it, quit the game, and start it again.
21. Check the game comes back with the effect already on.

**Straight lines are the thing to watch.** A long horizontal line - the top of
the stalk list, the border of the bottom panel - should stay a single
unbroken line across the whole screen. If it breaks into little steps, the
shader's sampling has gone back to nearest; if its text goes soft in patches
instead, it has gone to plain linear. Both of those shipped once and both were
reported from play. The logo on the splash screen is the other place to look,
since it is the one large picture in the game rather than text: its left and
right edges should be clean.

**What to look at, not just click through:** the effect should be visible but
should not make anything unreadable. If you cannot tell the difference between
ticked and unticked at all, that is a fault and not subtlety — the first build
had a scanline pattern that cancelled itself out exactly, and it looked like a
tasteful effect rather than like nothing. Tick and untick it twice while
watching one line of text.

**Known, and not a fault:** the development overlay in the top-left corner is
*not* drawn through the effect. It is above it on purpose. A release build has
no overlay at all.

**If you want to change how strong it is**, every knob is a `uniform` with its
default in `src/ui/crt_screen.gdshader` — curvature, vignette width, bleed
amount and falloff, scanline count and strength, noise, glow threshold and
strength. The scene sets none of them, so that file is the only place the
look is decided.

### A8j. The window, the picture inside it, and where clicks land

The game is drawn at 640x360 and enlarged by a whole number to fit the window
(decisions.md D96). Nothing in the suite can check that clicks still land where
they look like they do, so that is step one.

1. Start the game.
2. Click **SINGLE PLAYER**, then **JOIN GAME**, then **SETTINGS**.
3. Check each tab responds to the click on the tab itself, not beside it.
4. Open the resolution dropdown.
5. Check the list appears directly under the dropdown, not somewhere else.
6. Check the list is the same chunky size as the rest of the interface, not
   small and sharp.
7. Check the list contains no 960 x 540 and no 1600 x 900.
8. Pick 1280 x 720.
9. Check the game fills the window exactly, with no black border.
10. Hover the mouse over a disabled button until its tooltip appears.
11. Check the tooltip appears beside the button and matches the interface.
12. Start a game and buy some shares.
13. Check every button and text field responds where you click it.

**What to look at, not just click through:** a click landing a few pixels from
where you aimed is the failure this is for, and it shows up at the edges of the
window before it shows up in the middle.

### A8k. Black bars, and when they are expected

1. Set the game to windowed at 1280 x 720 and check there are no bars.
2. Set it to 1920 x 1080 if the monitor allows it and check the same.
3. Switch to fullscreen.
4. On a 1920x1080, 2560x1440 or 3840x2160 monitor, check there are no bars.
5. On a 16:10 monitor (1920x1200, 2560x1600, or a Steam Deck at 1280x800),
   check there are bars above and below and none at the sides.
6. Check the picture is centred rather than pushed to one edge.
7. Check the resolution dropdown is greyed out while fullscreen is ticked.

**Expected, not a fault:** bars on all four sides on a monitor whose width is
not 1280, 1920, 2560 or 3840 — a 1366x768 laptop shows a 1280x720 picture with
a border. That is the price of every pixel being the same size square.

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

### A8l. Trading closes when you are ready — ✅ passed 2026-11-17

Needs two players, so run it as part of Test B or with two windows on one
machine (`--host` and `--join`). Run and passed on the day the rule was built;
re-run it if anything touches readiness or the board's controls.

1. Start a two-player game and advance to year 1.
2. As player one, buy some shares of anything.
3. Press **Ready for New Year**.
4. Check the button now reads **Waiting...**.
5. Check every **BUY** button on the board is greyed out.
6. Check every **SELL** and **SELL ALL** button under Your Stalks is greyed out.
7. Press the button again to un-ready.
8. Check the buy and sell buttons come back.
9. Press ready again, then have player two stay unready for a moment.
10. Check player one still cannot trade while waiting.
11. Have player two ready up and check the year advances normally.

**What this is for:** the year ends the moment the last player readies, so
without this a player who has finished could sell everything by accident a
heartbeat before the prices move. See decisions.md D97.

**Also worth trying:** ready up, then un-ready, then trade, then ready again.
The board should follow each press with no leftover greying.

### A8m. A long special event reads in full

Three of the ninety event descriptions are longer than the three lines the top
bar reserves. They scroll rather than being cut off. See decisions.md D100.

1. Play years until an event description fills all three lines.
2. Check the text is not cut off mid-sentence with nothing to be done about it.
3. Move the mouse over the description and leave it there.
4. Check it pauses, then creeps down a line at a time.
5. Check it reaches the last line, pauses, and returns to the top.
6. Move the mouse away.
7. Check it goes back to the first line and stops.
8. Move the mouse over it and click once.
9. Check it keeps scrolling with the mouse moved away.
10. Click it again.
11. Check it stops and returns to the first line.
12. Hover a short description that fits in one or two lines.
13. Check it does not move at all.

**Also worth trying:** hover a long one, then end the year. The new year's
description should start at its first line rather than wherever the last one
had scrolled to.

### A8n. The year's news panel

1. Start a game and ready up to reach year 1.
2. Check a panel appears in the middle headed **Breaking Market News!**
3. Check it shows the event's description in full, not cut off.
4. Check it names the stalk and what happened to it underneath.
5. Check the board behind it is dimmed.
6. Try to click a BUY button behind the panel.
7. Check nothing happens — the panel is in the way on purpose.
8. Click **Close**.
9. Check the panel goes and the board is live again.
10. Ready up for the next year.
11. Check the panel comes back for the new year.
12. Close it by clicking anywhere on the dimmed area rather than the button.
13. Check that closes it too.
14. Ready up again and close the next one by pressing Escape.

**The no-event case is not reachable by playing normally.** There is an event
every year unless all nine targetable stalks are bankrupt at once, which is a
wipeout rather than a lull. It is covered by
`test_a_quiet_year_still_gets_a_panel_and_says_so` instead; do not go hunting
for it by hand.

17. Tick **Don't show again** and close the panel.
18. Ready up for the next year and check no panel appears.
19. Open **Settings** and check **Show the year's news** is unticked.
20. Tick it, leave Settings, and ready up again.
21. Check the panel is back.
22. Play until a year whose description is cut short in the top strip.
23. Check **... MORE** appears at the end of the strip.
24. Press it and check the panel comes back with the whole description.
25. Close the panel, then hover the strip instead.
26. Check it scrolls in place without reopening anything.

**What this is for:** the event is the one thing each year that moves the
market under you, and in the top strip alone it was easy to miss entirely. See
decisions.md D101, and D102 for the tick box and MORE.

### A8o. A company's details, and who is in it

Needs two players for the Investors list to be worth looking at.

1. Start a two-player game and reach year 1.
2. Click a stalk's row, on the name or the empty space - not the BUY button.
3. Check a panel opens with the company's name at the top.
4. Check there is a paragraph under it. It is placeholder text for now.
5. Check there is an **Investors** heading.
6. Check it says nobody owns any yet.
7. Close the panel and buy some shares of that company.
8. Open it again and check your own name is listed.
9. Have the other player buy some of the same company.
10. Open it again and check both names are listed.
11. Check neither name has a number beside it.
12. Sell your whole position and open it again.
13. Check your name has gone from the list.
14. Click the BUY button on a row rather than the row itself.
15. Check that buys shares and does **not** open the panel.

16. Open **BERRY BONDS FROM DIE HARD**, whether or not anybody holds it.
17. Check its Investors section says **Anonymous.** and names nobody.
18. Buy some BERRY BONDS and open it again.
19. Check it still says **Anonymous.** and does not name you either.

**What this is for:** seeing who is in what makes the board a place where
players watch each other. How much they hold is deliberately not shown - see
decisions.md D103.

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
- **No `steam_appid.txt` is needed**, on either machine, whether the build is
  launched through Steam or by double-clicking it. The game passes its App ID
  to Steam itself. An earlier version of this list asked for one; that was
  wrong and was corrected on 2026-11-16 after a release build was run on a
  second machine without it.

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

### B5. Avatars and the supporter message

**Steps 1-3 and 10-11 passed on 2026-11-16.** The portraits are pixelated and
that is expected: Steam's smallest portrait is 32 pixels square and a lobby row
is sixteen tall on the game's grid. Left as it is on purpose.

With two Steam accounts, in a lobby:

1. Host a game from one account and join from the other.
2. Check each player row shows that account's Steam portrait.
3. Check your own row shows your portrait too, not only the other player's.
4. Have the other player press Ready.
5. Check the portraits stay put - the list is rebuilt whenever anything
   changes, so this is where they would vanish.
6. Have them leave and rejoin.
7. Check their portrait comes back.
8. Start a single-player game instead.
9. Check the lobby shows no portraits and no blank squares where they would
   be.

On the title screen:

10. Sign in as an account that owns the supporter DLC.
11. Check **Thanks for Supporting the Devs!** appears under the tagline.
12. Sign in as an account that does not own it.
13. Check the message is absent.
14. Close Steam entirely and start the game.
15. Check the message is absent rather than shown by default.

### A9 - The host leaves and somebody else takes over

**Needs two Steam accounts on two machines.** None of this is covered by the
suite: the decision about who takes over is tested (`test_lobby_migration.gd`)
and so is continuing a match from a client's copy
(`test_host_migration.gd`), but nothing that talks to Steam is. See
decisions.md D104 and D105.

Expect each handover to take a few seconds, and up to twenty before it gives
up. A frozen screen during the wait is expected - there is deliberately no
message on it yet.

In a lobby, before the match has started:

1. Host a Steam game on machine A.
2. Join it from machine B.
3. Quit the game entirely on machine A.
4. Check machine B ends up in a lobby rather than on the title screen.
5. Check machine B is now the host - it has the Start button.
6. Check the lobby still shows the same game name.
7. Start the game on machine A and open Join Game.
8. Check the migrated lobby is listed. **This is the step that failed first
   time** - the leaving host used to shut the lobby down on its way out
   (D106).
9. Check the listed row shows the right name, year limit and starting cash.
10. Join it from machine A.
11. Check A appears in B's lobby as a new player.
12. Press Start on B.
13. Check both machines reach the playing screen.

In a match already under way:

14. Host a Steam game on machine A, join from B, and start the match.
15. On each machine, buy a different stalk, so each player has a position.
16. Note B's cash, B's holdings, the year, and two or three prices.
17. Quit the game entirely on machine A.
18. Check machine B stays on the playing screen.
19. Check the year is unchanged.
20. Check the prices are unchanged.
21. Check B's own cash and holdings are unchanged.
22. Check A still appears on the board, with the net worth they had.
23. Check B can buy and sell.
24. Ready up on B and check the year advances with only B playing.
25. On machine A, open Join Game.
26. Check the match is **not** listed - a game under way is unlisted on
    purpose, and is reached by invite instead (D106).

Coming back after the handover:

27. With B hosting the match from step 17, invite A from B, or use the same
    lobby A was in.
28. Check A lands on the playing screen rather than in a lobby.
29. Check A's cash is the figure it had before A quit.
30. Check A's holdings are the ones A had before quitting.
31. Check A is not already readied for the year.
32. Check the board on B shows A back in the standings.
33. Check the rankings order has A and B in their original places.

Somebody else arriving mid-match, who was never in it:

34. From a third account not in the match, try to join that lobby.
35. Check they are turned away with a reason rather than seated.
36. Check the match on A and B is undisturbed.

With three machines, if available:

37. Host on A, join from B and C, start the match.
38. Quit on A.
39. Check B and C both end up in the same match, with one of them hosting.
40. Check the one that did not become host can still buy and sell.

### B6 - Rejoining a match you dropped out of

**B6a-B6h passed on 2026-11-18** and **B6i on 2026-11-19**, on a Steam build
with two accounts on two machines. The one fault that came back from the first
run was that the title screen went on offering a game that had ended; B6i covers
the fix for it (D115).

**Also confirmed on 2026-11-19, unprompted by any of the steps below** - worth
keeping because it is the whole feature end to end, through a migration:

1. A hosts, B joins, both reach the board.
2. B quits to desktop, restarts the game, sees **REJOIN GAME**, and rejoins successfully.
3. A quits to desktop. B takes the match over as host (A9).
4. A restarts the game, sees **REJOIN GAME**, and rejoins the match **now hosted by B**.

Step 4 is the one that could only work if the lobby owner is read at rejoin
time rather than remembered (D111), and it did.

**Needs two Steam accounts on two machines.** None of the Steam plumbing is
covered by the suite. What *is* covered is the economics of being away
(`test_away_players.gd`), the host's refusals (`test_host_migration.gd`) and
every decision `Main` makes (`test_main_rejoin.gd`), so a failure here is
almost certainly Steam's answer rather than the game's logic. See decisions.md
D110 and D111.

Call the machines **A** and **B** throughout. A hosts.

#### B6a. The button only appears when there is something to rejoin

1. On B, delete `%APPDATA%\Godot\app_userdata\Stalks Stalks Stalks\last_match.cfg` if it exists.
2. Start the game on B.
3. Check the bottom row of the title screen shows **QUIT TO DESKTOP** on the left and nothing on the right.
4. On A, host an online game.
5. On B, join it from the lobby list.
6. On B, press Ready.
7. On A, press Start.
8. Check both machines are on the playing screen.
9. On B, press Escape, then **Leave Game**, then confirm.
10. Check B is on the title screen.
11. Check **REJOIN GAME** is now at the right-hand end of the bottom row, level with QUIT TO DESKTOP.

#### B6b. Going back in, as a client

12. On B, press **REJOIN GAME**.
13. Check B shows **Rejoining <the game's name>...** under the panel while it works.
14. Check B lands on the **playing screen**, not on a lobby.
15. Check B is on the same year as A.
16. Check B's cash matches what A's rankings show for B.
17. Check B's owned-stalks list shows the holdings B had before leaving.
18. On B, buy one share of any stalk.
19. Check A's rankings show B's net worth change.

#### B6c. The match goes on without you

20. On A, note B's net worth from the rankings.
21. On B, press Escape, then **Leave Game**, then confirm.
22. On A, check B's row is still in the rankings, tagged **(away)**.
23. On A, check B's ready dot is grey rather than red.
24. On A, check the waiting line does not name B.
25. On A, press Ready.
26. Check the year advances **without waiting for B**.
27. On A, check B's net worth has changed - they were paid their dividends.
28. On A, advance two more years the same way.
29. On B, press **REJOIN GAME**.
30. Check B lands on the current year, not the year they left.
31. Check B's cash and holdings reflect the three years that passed.

#### B6d. A loan goes unpaid while you are away

Loans must be enabled, and B must be past year 2.

32. On B, take a loan.
33. Note the balance and the minimum payment shown on B.
34. On B, press Escape, then **Leave Game**, then confirm.
35. On A, advance one year.
36. On B, press **REJOIN GAME**.
37. Check B's loan balance has grown by roughly 10% plus a year's interest.
38. Check B's loan panel shows one missed payment.
39. On B, press Escape, then **Leave Game**, then confirm.
40. On A, advance one year.
41. On B, press **REJOIN GAME**.
42. Check the balance has grown again, by roughly 15% plus interest, and shows two missed payments.
43. On B, press Escape, then **Leave Game**, then confirm.
44. On A, advance one year.
45. On B, press **REJOIN GAME**.
46. Check B is **bankrupt**: no cash, no holdings, and BANKRUPT in the rankings on both machines.

#### B6e. Rejoining a match that changed hands

47. Start a fresh online game with A hosting and B joining, and reach the playing screen.
48. On B, press Escape, then **Leave Game**, then confirm.
49. On A, press Escape, then **Leave Game**, then confirm.
50. On B, press **REJOIN GAME**.
51. Check B fails with a sentence on the title screen rather than hanging.

A third account would be needed to test rejoining a match that migrated and is
still running; with two, step 49 ends the match, which is what step 51 checks.

#### B6f. Failing cleanly

52. On B, with REJOIN GAME showing, close the game on A entirely.
53. On B, press **REJOIN GAME**.
54. Check B stays on the title screen with a sentence saying the game is gone.
55. Check **REJOIN GAME** is still there - a failed attempt does not forget the match.
56. On B, open the **JOIN GAME** tab and pick a game that is no longer there (host one on A, start it, then press Join on B).
57. Check B reports a reason rather than appearing to do nothing. This is the fault D112 fixed, on the path REJOIN GAME shares.

#### B6g. A finished match is not offered

58. Play a short online match (set the year limit to 1 or 2) through to the result screen on both machines.
59. On B, go back to the title screen from the result screen.
60. Check **REJOIN GAME** is absent.

#### B6h. The host rejoining

61. Start an online game with A hosting and B joining, and reach the playing screen.
62. On A, press Escape, then **Leave Game**, then confirm.
63. Wait for B to take the match over - B should end up on the playing screen as the host (see A9).
64. On A, check **REJOIN GAME** is showing.
65. On A, press it.
66. Check A lands on the playing screen as a **client** of B, with A's own cash and holdings.
67. On B, check A's row loses its **(away)** tag.
68. Check the **(Host)** tag is on B on both machines.

#### B6i. The button is only there when the game is — ✅ passed 2026-11-19

**Added after the first Steam run, 2026-11-18.** Everything else in B6 passed;
this did not exist, and the title screen went on offering a game that had
ended. Steam is now asked before the button appears, and again every five
seconds while the title screen is up (D115). These steps are the ones that
check it, and they are worth running first: the rest of B6 assumes the button
means something.

Machine **B** does all of this unless a step says otherwise.

The case that was reported — a game you were the last one in:

1. Host an online game on B and do not let anybody join it.
2. Press Start and reach the playing screen.
3. Press Escape, then **Leave Game**, then confirm.
4. Check **REJOIN GAME** is **not** on the title screen.
5. Start a single-player game.
6. Leave it back to the title screen.
7. Check **REJOIN GAME** is still absent.

A game that is still being played:

8. On A, host an online game; join it from B and reach the playing screen.
9. On B, press Escape, then **Leave Game**, then confirm.
10. Check **REJOIN GAME** appears, within a second or two of the title screen.
11. Start a single-player game on B.
12. Leave it back to the title screen.
13. Check **REJOIN GAME** is still there - the match on A is still running, and a solo game in between changes nothing.

The button going away on its own:

14. With B sitting on the title screen and REJOIN GAME showing, finish the match on A - play it out to the result screen.
15. Watch B's title screen without touching it.
16. Check **REJOIN GAME** disappears within about five seconds.
17. Check it does not come back.

The same, for a host who closes the game rather than finishing it:

18. On A, host an online game; join from B and reach the playing screen.
19. On B, press Escape, then **Leave Game**, then confirm.
20. Check **REJOIN GAME** is showing on B.
21. On A, close the game entirely.
22. Watch B's title screen.
23. Check **REJOIN GAME** disappears within about five seconds.

Steam closed, and a connection that drops:

**Closing Steam while the game is running is not a test you can do.** Steam
closes the game with it, because the game was launched through Steam. The steps
that used to be here asked for exactly that and were replaced on 2026-11-19
after the owner met it. **The replacements passed the same day**, and the run
went further than the steps ask: A exited Steam, which closed A's game; the
match migrated to B; A reopened the game with Steam closed and saw no button;
A then started Steam, relaunched, saw the button, and rejoined the match now
hosted by B.

24. Close Steam entirely.
25. Launch the build by double-clicking it, rather than through Steam. (No `steam_appid.txt` is needed - see the prerequisites at the top of Test B.)
26. Check **REJOIN GAME** is absent, and that the title screen is otherwise normal.
27. Start Steam, wait for it to sign in, then start the game again.
28. Check **REJOIN GAME** is back, and that pressing it still works.

A host that loses its connection rather than leaving — run on 2026-11-19 and
**passed**:

29. On A, host an online game; join from B and reach the playing screen.
30. On B, press Escape, then **Leave Game**, then confirm.
31. Check **REJOIN GAME** is showing on B.
32. Disconnect A from the internet, leaving the game running.
33. Wait a minute, watching B's title screen.
34. Check **REJOIN GAME** is **still showing** on B.
35. Reconnect A to the internet.
36. Check **REJOIN GAME** disappears from B.

**Step 34 is the deliberate part, not a bug.** A host that has gone quiet for a
minute may be back in the next one, and D115's rule is that only a definite "that
game is not there" forgets the record - a silence never does. The cost is that B
could press the button during the outage and be told it could not reach the host
(the twelve-second join timeout, D67). The alternative is a player losing their
seat because their friend's router blinked, which is worse.

**Step 36 is right, and the mechanism is Steam's rather than the game's.** The
lobby had one member left in it, and that member's membership did not survive
the outage, so by the time Steam's view settled there was no lobby - which is
what B's next query found. The game did nothing special here; it asked the same
question it asks every five seconds and acted on a different answer. The exact
Steam-side sequence was not established and is not relied on: the game treats
"the lobby is gone" the same whatever made it go.

#### B6j. Coming back through Steam's friends list — **cannot be run yet**

**Needs a build Steam installed**, not one copied onto the machine, because
Steam's friends list only offers "Join Game" for a game it owns the
installation of. Written down now because the code path exists and was fixed
for it on 2026-11-19 (D116); run it at the first beta or release build.

1. On A, host an online game; join from B and reach the playing screen.
2. On B, quit to desktop entirely.
3. On A, keep playing - advance a year or two.
4. On B, open Steam's friends list and find A.
5. Check Steam offers **Join Game** on A.
6. Click it.
7. Check B's game launches, or comes to the front if it is running.
8. Check B lands on the **playing screen**, on the same year as A, with B's own cash and holdings.
9. On A, check B's row loses its **(away)** tag.

**Step 8 is the one that was broken.** Until D116 the host welcomed a returning
peer back onto its seat and never told it the match had begun, so B was left on
a lobby screen while the game ran on - with a Ready button that reached the
year gate. REJOIN GAME was unaffected and is not a test of this.

**If step 5 shows nothing**, that is Steam's decision, not the game's. Two
things to check before suspecting the port: whether the lobby was created
**invite only**, which makes it `k_ELobbyTypePrivate` and may not be offered to
friends at all, and whether both accounts actually see each other as friends.
The lobby being absent from the in-game browser is expected and is not the
cause - a match in progress is deliberately unlisted but still joinable (D106).

#### What a failure in B6i means

- **The button never appears, even for a match that is definitely running** -
  Steam is not answering `requestLobbyData` for a lobby this machine is not in,
  or the answer is arriving with `success` 0. The game log is the place to look.
- **The button appears and then vanishes every few seconds** - the answer is
  arriving inconsistently. Nothing in the game decides this on a timer other
  than the five-second re-ask.
- **The button survives a finished match** (steps 15-17) - the host did not
  write `state = over`, or it is not being read back. Only the lobby's owner
  can write it, so check which machine hosted.
- **The button survives a lobby everybody left** (steps 3-4) - this one does
  not depend on Steam at all: leaving a lobby you were the last member of
  forgets the record on the spot. A failure here is in the game, not in Steam.

#### What a failure here means

- **"That game no longer exists." when the match is still running** - Steam is
  refusing a client into an unlisted lobby. That is the one assumption the code
  could not verify (D111); it would mean `hide_lobby_from_the_browser` has to
  do something other than write metadata.
- **B sits on "Rejoining..." and then reports it could not reach the host** -
  the 12-second join timeout (D67). The lobby was reachable and the host was
  not.
- **"That game has already started."** - the host did not recognise B's Steam
  ID on the roster. A different Steam account from the one that was playing, or
  a match the roster was rebuilt on.
- **B lands on a lobby instead of the board** - `_on_rejoin_landed` was not
  reached; the welcome arrived down the ordinary join path.

### B7 - The host leaves while you are reading the result

**B7a, B7c and B7d passed on 2026-11-20** with two accounts on two machines.
B7b and B7e have not been run. Covers D122 and D123. Call the machines **A** and
**B**; A hosts.

The suite covers every decision `Main` makes here without Steam
(`test_main_migration.gd`), so a failure in these steps is more likely to be
Steam's answer about who owns the lobby than the game's logic.

#### B7a. You stay on the standings

1. On A, host an online game and set the match to 2 years.
2. On B, join it from the lobby list.
3. On B, press Ready.
4. On A, press Start.
5. Play both years out on both machines, readying up each year.
6. Check both machines show the result screen with the final standings.
7. Note the seed printed at the bottom of B's result screen.
8. On A, press **MAIN MENU**.
9. Check A is on the title screen.
10. Check B is **still on the result screen**, with the same standings and the
    same seed as step 7.
11. Check B is **not** in a lobby, and that no Play button is on screen.

#### B7b. There is no rematch button to press

12. On B, check the result screen shows **VIEW BOARD** and **MAIN MENU** only,
    with no PLAY AGAIN.
13. On B, press **VIEW BOARD**.
14. Check the board shows the final prices and **BACK TO RESULTS** in the
    bottom bar.
15. On B, press **BACK TO RESULTS**.

#### B7c. The finished game is not offered again

16. On B, press **MAIN MENU**.
17. Check B is on the title screen and **REJOIN GAME** is not shown.
18. On A, open the lobby list.
19. Check the finished game is not in it.

#### B7d. A question does not outlive its screen

20. On A, host an online game; on B, join, ready up, and let A start it.
21. On B, press Escape, then **Leave Game**, and leave the confirmation open.
22. On A, press Escape, then **Leave Game**, and confirm.
23. On B, check the confirmation has gone and B is reading the board or the
    standings, not a question about a game that has ended.

#### B7e. Play again still works on its own

24. On B, start a single-player game of 2 years from the title screen.
25. Play it out to the result screen.
26. Check **PLAY AGAIN** is on the result screen.
27. On B, press **PLAY AGAIN**.
28. Check a new match starts at Year 0.
29. Play it out and check the seed differs from the one in step 25.

**If something goes wrong here**

- **B lands in a lobby named after the finished game** - the fault D122 fixed.
  `_migrating_in_match` is false on the result screen again, or
  `_show_the_screen_for` is not being reached.
- **B lands on the board with a disabled "Game Over" button** - the three-way
  is picking case 2 over case 1; `state.is_over` is not arriving in the
  snapshot.
- **B is dropped to the title screen** - with two accounts B becomes the host,
  so this means `take_over` failed rather than that B was refused. The log's
  `[migration]` lines say which.
- **A third player is refused with "That game has finished."** - `why_not_rejoin`
  is checking `is_over` before the seat again (D122).

### B8 - A rematch

**Passed on 2026-11-20** with two accounts on two machines, along with four
cases these steps do not ask for — they are B8g below, because every one of them
is a rematch meeting host migration and that is where the last four faults came
from. Covers D124. Two Steam accounts on two machines, **A** and **B**; A hosts.

One thing came back from that run and is fixed: a client was told the host
wanted another game only by a button quietly changing its label. There is a line
on the result screen now, the same one the host sees naming who asked (B8a step
10a).

**Button wording is the owner's.** The steps name them by what they do.

`test_rematch.gd` drives all of this over a real socket, so a failure in these
steps is more likely to be Steam than the game's logic. What the suite cannot
reach is a third player, so the one case left to judgement is a rematch where
one of three declines.

#### B8a. The client asks, the host offers

1. On A, host an online game and set the match to 2 years.
2. On B, join it, press Ready, and let A press Start.
3. Play both years out on both machines.
4. Check both machines show the result screen.
5. On B, press the request-rematch button.
6. Check B's button now says the request has been made and cannot be pressed again.
7. Check A's result screen names B as having asked.
8. On A, press the return-to-lobby button.
9. Check A shows the lobby, headed with the same game name.

#### B8b. The client takes a seat

10. Check B is still on the result screen, and its button now offers a way into the lobby.
10a. Check B's result screen says in words that the host has gone back to the lobby.
11. On B, press it.
12. Check B shows the lobby.
13. Check A's lobby lists both players.
14. On B, press Ready.
15. On A, press Play.
16. Check both machines show Year 0 of a new match.
17. Check both players have the starting cash and no holdings.
18. On B, buy one share of any company and check it appears on both machines.

#### B8c. It is a different market

19. Play the new match out to the result screen on both machines.
20. Check the seed on the result screen differs from the one in step 4.

#### B8d. Declining leaves you alone

21. On A, press the return-to-lobby button.
22. On B, do not press anything.
23. Check A's lobby lists only A.
24. On A, press Play.
25. Check A is on Year 0 of a new match.
26. Check B is **still on the result screen** of the finished match.
27. Check B's rematch button no longer offers a way in.
28. On B, press **MAIN MENU** and check B reaches the title screen.

#### B8e. A rematch of a rematch

29. On A, host an online game of 2 years; on B, join, ready, and let A start it.
30. Play it out on both machines.
31. On A, press return-to-lobby; on B, join; on A, press Play.
32. Play that match out on both machines.
33. On A, press return-to-lobby; on B, join; on A, press Play.
34. Check both machines reach Year 0 again, with the starting cash and no holdings.
35. Check the year-by-year tab shows only the current match's years.

#### B8f. The host leaves mid-offer

36. On A, host an online game of 2 years; on B, join, ready, and let A start it.
37. Play it out on both machines.
38. On A, press the return-to-lobby button.
39. On A, press **LEAVE** in the lobby.
40. Check B is still on the result screen and has not been dropped to the title screen.

#### B8g. A rematch meeting host migration — **passed 2026-11-20**

Four cases found by playing rather than by these steps. They are the ones worth
re-running after any change to migration or to the rematch, because each is a
rematch lobby changing hands.

41. A returns to the lobby, B follows, then A leaves. Check the lobby migrates to
    B and B can carry on.
42. With A gone and B now hosting, check B's result screen offers the way back to
    the lobby, and that starting a new game from it works.
43. A returns to the lobby and B goes to the title screen instead. Check B can
    see that lobby in the browser and join it, and that the game then starts.
44. A goes to the title screen, so the match migrates to B. B returns to the
    lobby. Check A can see that lobby in the browser and join it.

**If something goes wrong here**

- **B's buttons do nothing after a rematch** - the peer maps were not rebuilt;
  `local_player_id()` reads `_player_by_peer[HOST_PEER_ID]` (D124).
- **B cannot rejoin after dropping out of a rematch** - the seats lost their
  Steam IDs when the roster was rebuilt. `test_rematch.gd` has a named test for
  this, so suspect the Steam ID arriving as 0 rather than the rebuild.
- **The rematch replays the same market** - the seed was not cleared, so
  `build_authority` kept the finished match's.
- **B is pulled into a match it declined** - the result screen is treating
  `match_started` as a reason to change screen rather than to close its own way
  in (D124).
- **The game is not in the browser during a rematch lobby** -
  `reopen_lobby_to_the_browser` was not called, so the lobby is still marked
  finished from `_on_match_finished`.

### Known gaps, so they are not surprises

- **Achievements are not being tested, on purpose.** They are implemented and
  their thresholds are covered by 28 tests, but the App ID is the published
  game's, so unlocking one here awards it for real on the tester's Steam
  account. `resetAllStats(true)` is the only undo and it wipes everything.
  See decisions.md D70.
- **Host migration works, confirmed in play on 2026-11-18** with two accounts
  on two machines, after failing three times (D106, D107, D108). The logs are
  the evidence, and they are the reason to keep logging it (D108a): three
  handovers, in both directions, one of a lobby and two of a match in
  progress. Each surviving player took over and carried on - "now hosting the
  moved match as p1" - which is what distinguishes a migration from a game
  quietly continuing single-handed, and is not distinguishable on screen.
- **One path has still never run: reconnecting to somebody else.** With two
  accounts the survivor is always the one Steam promotes, so every real
  handover so far has taken the BECOME_HOST branch. The JOIN_NEW_HOST branch -
  Steam names a third player and this one reconnects to them - exists only in
  `test_main_migration.gd`. Steps 37-40 need the third machine.
- **A rejoining player's year-by-year page was empty before their rejoin**,
  found in play on 2026-11-19, fixed and **confirmed in play the same day**
  (D118). The whole record now travels with the welcome. The run covered all
  three ways of arriving mid-match: a client that left and rejoined, a client
  reconnecting after a host migration, and a match where the host migrated
  back and forth. Host and client agreed on the year-by-year page in every
  case.

  Note what that run did **not** establish: with two accounts the survivor is
  always the player Steam promotes, so a handover "back and forth" is still
  BECOME_HOST each time. The JOIN_NEW_HOST branch remains untried in play.
- **Reclaiming a seat works, confirmed in play on 2026-11-19** by running B6
  end to end. That run also answered the one question the code could not:
  **Steam does admit a client into a lobby that is joinable but unlisted.**
  The whole feature rested on it, and reading the code could only show that
  nothing in *this* project closes the door (D111). It is now observed rather
  than inferred.
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
