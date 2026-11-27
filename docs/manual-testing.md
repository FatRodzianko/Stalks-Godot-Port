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

**7a to 7e check that the title screen does not move when it says something.**
It used to: the message was a row inside the centred column, so showing one
pushed the title up and the quit button down (D126). The hard part of checking
it is that the message you normally see - "Creating a lobby..." while an online
game is being made - is gone before you can look at it, because the lobby
screen replaces the title screen the moment the lobby exists. A failed join is
the way round that: it leaves a message on the title screen and goes nowhere,
so it stays up for as long as you like.

7a. Note where the title text starts, and where the bottom edge of **QUIT TO DESKTOP** is.
7b. Find the small **DEV** panel in the top-left corner of the window. It has a Host box, a Port box, and **HOST** and **JOIN** buttons.
7c. Leave Host and Port exactly as they are and click **JOIN**. Nothing is hosting at that address, so it will fail - that is the point.
7d. Check a red message about not reaching the host appears along the very bottom of the window, **below** QUIT TO DESKTOP rather than across it.
7e. Check the title text and QUIT TO DESKTOP are exactly where they were in 7a.
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

#### B6j. Coming back through Steam's friends list — **run on 2026-11-20**

**Needs a build Steam installed**, not one copied onto the machine, because
Steam's friends list only offers "Join Game" for a game it owns the
installation of. That became possible when the game went up as a beta branch,
and it was run then: **Join Game works for an ordinary online game, and is not
offered for an invite-only one.**

The second half of that is the correct answer rather than a gap. An invite-only
game is created as `k_ELobbyTypePrivate` (`steam_service.gd`), which Steam does
not show to friends at all - that is the whole difference between it and a
public lobby, and it is what the setting promises. The lobby type that *would*
put a game in the friends list without listing it in the browser is
`k_ELobbyTypeFriendsOnly`, which this game does not use and which would not be
invite-only any more. So there is nothing to fix here; an invite is how you get
into an invite-only game.

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
**invite only**, which makes it `k_ELobbyTypePrivate` and is not offered to
friends at all - confirmed in play, see above - and whether both accounts
actually see each other as friends.
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
10b. On B, press **VIEW BOARD** and check the bottom bar says it too, alongside the game being over.
10c. On B, press **BACK TO RESULTS**.
10d. On B, switch between **FINAL STANDINGS** and **YEAR BY YEAR** and check the panel does not change size (D125).
10e. On A, check the lobby panel is the same size with two players in it as it was with one.
10f. On A, press **LEAVE**, and check the lobby panel's heading started level with STALKS STALKS STALKS and its bottom edge level with QUIT TO DESKTOP.
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

### C - Choosing StalkleHeads (phase S5) — **passed 2026-11-22**

**Run on 2026-11-22**, C1-C5, two Steam accounts on two machines for C3-C5. Every
check passed. Three things came back, none of them a failure of S5:

- **C1 step 9:** the panel is the same size on both tabs, but the second column
  starts further left on HOST ONLINE than on SINGLE PLAYER, because the label column
  was as wide as its widest visible label. Fixed afterwards: both tabs now line the
  settings up at the same place (D173).
- **C2 step 3:** the twenty-row board scrolls, but nothing said so except a row cut
  off at the bottom. Fixed afterwards with a thin scroll bar (D173).
- **C2 step 5:** Teamsters went from 150 to 207 without splitting. Correct: in
  StalkleHeads a stalk splits above 300, not 150 (design §3.6).
- **C5 step 6:** B showed "A StalkleHeads match cannot change hosts yet." and was
  back at the title screen.

Built on 2026-11-22 (decisions.md D171). The suite covers the choice itself, the
board it builds, players' trades reaching flow, the snapshot, the lobby row's text
and the title card's size, all without Steam. What it cannot reach is two Steam
accounts reading a real lobby, and whether the row reads well.

**StalkleHeads is not playable on screen yet.** The playing screen is the base
game's, showing the twenty-row board with nothing about earnings. That is S7. These
steps check only that the mode is chosen, travels and is shown; do not judge the
game itself from them.

**The mode names are the games' own**: *Stalks Stalks Stalks* and *StalkleHeads*.
They are in one place, `GameMode.label` in `src/data/game_mode.gd`, if they should
read differently.

#### C1. The title screen, one machine, no Steam needed

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Check there is a **Game** row, and it reads **Stalks Stalks Stalks**.
4. Click the **Game** list.
5. Check it offers **Stalks Stalks Stalks** and **StalkleHeads**, and nothing else.
6. Click **StalkleHeads**.
7. Click **HOST ONLINE**.
8. Check the **Game** row still reads **StalkleHeads**.
9. Check the panel is the same size as it was on **SINGLE PLAYER**.
10. Check every row fits inside the panel, with **HOST ONLINE** at the bottom right and nothing cut off.
11. Click **JOIN GAME**, then **SETTINGS**, then **SINGLE PLAYER**.
12. Check the panel did not change size on any of them.

#### C1a. Re-check after D173: the settings line up — **passed 2026-11-22**

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Check the fields (the boxes after **Your name**, **Game**, **Years** and the rest) start at the line where the **SINGLE PLAYER** and **HOST ONLINE** tabs meet.
4. Click **HOST ONLINE**.
5. Check the fields start at exactly the same place as on **SINGLE PLAYER**.
6. Check every label still fits to the left of its field, with nothing cut off.

#### C2. A StalkleHeads single-player match starts, one machine

1. On **SINGLE PLAYER**, set **Game** to **StalkleHeads**.
2. Click **START**.
3. Check the board has twenty rows, including companies the base game does not have (some are placeholders named like *Transportation Company A*).
4. Press Ready.
5. Check the year reads **1** and prices have moved.
6. Quit to the title screen.
7. Set **Game** to **Stalks Stalks Stalks** and click **START**.
8. Check the board is the usual ten stalks, all at 100.

#### C2a. Re-check after D173: a list that scrolls says so — **passed 2026-11-22**

1. On **SINGLE PLAYER**, set **Game** to **StalkleHeads** and click **START**.
2. Check there is a thin bar down the right-hand side of the stalk list, lighter than the panel behind it.
3. Scroll the list with the mouse wheel.
4. Check the bar's lighter part moves down as the list scrolls.
5. Check the column headings still sit above their columns.
6. Quit to the title screen, set **Game** to **Stalks Stalks Stalks**, and click **START**.
7. Check the ten-stalk board's headings still sit above their columns.

#### C2b. Re-check after D174: a list that fits has no bar — **passed 2026-11-22**

1. On **SINGLE PLAYER**, set **Game** to **Stalks Stalks Stalks** and click **START**.
2. Check the stalk list has no scroll bar.
3. Check the headings still sit above their columns.
4. Buy shares in one stalk.
5. Check the owned stalks list has no scroll bar.
6. Check the player rankings list has no scroll bar.
7. Quit to the title screen, set **Game** to **StalkleHeads**, and click **START**.
8. Check the stalk list shows its scroll bar.
9. Quit to the title screen and click **HOST ONLINE**, then host.
10. Check the lobby's players list has no scroll bar with one player in it.

#### C2c. Re-check after D175: the bottom bar and scrolling text — **passed 2026-11-22**

1. On **SINGLE PLAYER**, tick loans, set **Game** to **Stalks Stalks Stalks**, and click **START**.
2. Click **Ready for New Year**.
3. Check the message beside **LOANS** is level with **LOANS** and **Ready for New Year**.
4. Take a loan.
5. Check **PAY LOAN** has not moved, with **Min** under it.
6. Hover **My Pillow, Your Pillow, We're All Pillows!** on the board.
7. Check the end of the name holds for about two seconds before it goes back to the start.
8. Play on until an event description runs past two lines.
9. Hover the description.
10. Check it moves up one line at a time, about three seconds apart.
11. Check the last lines hold for about five seconds before it goes back to the top.
12. Check **... MORE** stays in one place and no word is hidden under it.
13. Check a long bottom-bar message runs up to **Ready for New Year** before it wraps.

#### C3. The lobby row says which game it is, two Steam accounts

Two accounts on two machines, **A** and **B**. A hosts.

1. On A, click **HOST ONLINE**.
2. Set **Game** to **StalkleHeads** and **Years** to 10.
3. Click **HOST ONLINE** at the bottom of the panel.
4. Check A shows the lobby.
5. On B, click **JOIN GAME**.
6. Find A's game in the list.
7. Check its second line starts with **StalkleHeads**, followed by **10 years**.
8. On A, leave the lobby.
9. On A, click **HOST ONLINE**, set **Game** to **Stalks Stalks Stalks**, and host again.
10. On B, refresh the list.
11. Check A's game's second line now starts with **Stalks Stalks Stalks**.
12. On A, leave the lobby.

#### C4. A client joins a StalkleHeads game, two Steam accounts

1. On A, host an online game with **Game** set to **StalkleHeads** and loans ticked.
2. On B, join it from **JOIN GAME**.
3. Check B reaches the lobby with no error.
4. On A, press **Start**.
5. Check both machines show the same twenty rows at the same prices.
6. On both machines, press Ready.
7. Check both machines show year 1 with the same prices.
8. On B, buy some shares of any company.
9. Check B's cash went down by the cost and B holds the shares.
10. Play to the end of the match.
11. Check both machines show the same final standings.

#### C5. What must refuse, two Steam accounts — **superseded by S6**

**Do not run this any more.** It passed on 2026-11-22, when a StalkleHeads match
could not change hosts. Since S6 (D176-D178) it can, so step 5 now gives the
opposite result: B carries on hosting. Section D below replaces it. Kept as the
record of what was run.

**A StalkleHeads match cannot change hosts yet** (D171): the market is not sent to
clients until S6, so a client has nothing to carry on from. This step checks it
fails cleanly rather than inventing a market.

1. On A, host a StalkleHeads game; on B, join it.
2. On A, press **Start**.
3. On both machines, press Ready once, to reach year 1.
4. On A, quit the game to the desktop.
5. Check B shows a message that the game could not continue, and returns to the title screen rather than freezing or showing a board.
6. Write down the message B shows.

#### What a failure here means

- **C1 step 9 or 10** is a layout fault: the card is a fixed size (D86, D125) and
  the Game row must fit inside it. Send a screenshot.
- **C3 step 7 showing no mode** means the lobby key did not publish; a screenshot
  of the row and the console output help.
- **C4 step 3 failing with "Unknown stalk"** means the client did not load the
  StalkleHeads companies when the host's settings arrived.
- **C5 step 5 freezing** rather than returning is a fault; the message's wording
  is not, and can change.

### D - A StalkleHeads match over the wire (phase S6) — **passed 2026-11-22**

**Run on 2026-11-22**, D1-D4, two Steam accounts on two machines, on a locally
exported build containing S6. Every check passed:

- **D1:** B rejoined with **REJOIN GAME** on A's year. Prices, yearly changes and
  B's cash matched, and so did bankruptcies after the next year.
- **D2:** A quit. B stayed on the playing screen on the same year with the same
  prices, and carried on: trades and year advances worked.
- **D3:** A came back with **REJOIN GAME** (step 31 originally said a Steam invite,
  which a locally exported build cannot accept; corrected below). A landed on B's
  year with matching prices.
- **D4:** The final standings and the YEAR BY YEAR page matched on both machines.
- **Also checked, unscripted:** a rematch after the match. The rematch request and
  the lobby notices worked, both players reached the lobby, and the new match
  started in StalkleHeads and played normally.

**The build must contain S6.** A build made before S6 is on `main` fails at step 23
with "A StalkleHeads match cannot change hosts yet." That is the old build, not a
fault. To check a checkout before exporting it: open `src/sim/match_setup.gd` and
search for `cannot change hosts yet`. If it is there, the checkout is older than S6.

**First attempt, 2026-11-22, on a build from before S6:** D1 steps 12-14 and 19
matched, and D2 step 23 gave the old refusal. Those D1 results do not count for S6:
before S6 a rejoin already copied the twenty board rows, which is all D1 can see.
Run D again on a build that contains S6.

**Needs two Steam accounts on two machines**, A and B, both on the same build.
Built on 2026-11-22 (decisions.md D176-D178). The suite proves, without Steam, that
a client's copy of the market is the host's to the bit after a snapshot, a year, a
rejoin and a host migration (`test_wire.gd`). What it cannot reach is Steam itself,
and two different computers doing the same arithmetic.

**What you can see is limited.** The playing screen is still the base game's (S7):
the twenty-row board, prices, cash, standings and the year-by-year page. Nothing
about earnings is on screen. So every check below compares those. If they match on
both machines, the market underneath matches too, because the prices are worked
out from it.

Before starting, on each machine:

1. Start the game.
2. Check the title screen's **Game** row can be set to **StalkleHeads**.

#### D1. Rejoining a StalkleHeads match

3. On A, set **Game** to **StalkleHeads**, then host an online game.
4. On B, join it from **JOIN GAME**.
5. On A, press **Start**.
6. On B, buy some shares of any company.
7. On both machines, press Ready.
8. Repeat step 7 until the year is 5.
9. On B, press Escape, then **Leave Game**, then confirm.
10. On A, press Ready twice, so the match moves on two years without B.
11. On B, press **REJOIN GAME**.
12. Check B lands on the playing screen on the same year as A.
13. Check every price on B's board is the price on A's board.
14. Check B's cash matches what A's rankings show for B.
15. Write down the two years B was away (step 10). The year-by-year page is only on the result screen at the end of the match, so they are checked in step 41.
16. (No step: there is no year-by-year page during the match.)
17. (No step: see step 41.)
18. On both machines, press Ready.
19. Check both boards show the same prices for the new year.

#### D2. The host leaves and B carries on

20. On both machines, press Ready until the year is at least 3 past where D1 ended.
21. Write down the year and five prices from A's board.
22. On A, quit the game entirely to the desktop.
23. Check B stays on the playing screen, with no message saying the game could not continue. (Before S6, C5, B was sent back to the title screen.)
24. Check B's year is the year from step 21.
25. Check the five prices on B are the ones written down in step 21.
26. On B, buy some shares of any company.
27. On B, press Ready.
28. Check the year advances and prices change.
29. Repeat steps 27-28 three more times.

#### D3. Coming back to the match B now hosts

30. Start the game on A.
31. On A, press **REJOIN GAME**.
32. Check A lands on the playing screen, on B's year.
33. Check every price on A's board is the price on B's board.
34. Check A's cash is the figure A had before quitting in step 22.
35. Write down the year of the handover (step 21), for step 41.
36. (No step: the year-by-year page is checked at the end, in step 41.)

#### D4. Playing on to the end after the handover

37. On both machines, press Ready.
38. Check both boards show the same prices.
39. Repeat steps 37-38 until the match ends.
40. Check both machines show the same final standings.
41. On both machines, open **YEAR BY YEAR** on the result screen and check they show the same figures for every year, including the years from step 15 and the handover year from step 35.

#### What a failure here means

- **Step 13, 19, 33 or 38 showing different prices** is the fault S6 exists to
  prevent: the client's copy of the market differs from the host's. Write down the
  year, the company and both prices, and send the console output from both machines.
  If it only ever happens on two *different* computers, it is the one thing the
  suite cannot test (testing.md, StalkleHeads wire).
- **Step 11 failing with a message**, or step 32: the history or snapshot was
  refused. The message names why; "different content" means the two machines are not
  running the same build.
- **Step 23 sending B to the title screen** means the take-over refusal from S5 is
  still in the build; check both machines have the new one.
- **Step 25 showing different prices** means the year was not carried over at the
  moment of the handover; step 28 going wrong after a correct step 25 means the new
  host is not dealing from the market it was handed.
- **Step 41 differing** is the year-by-year page, which is replayed from the
  host's draws (D178). Send a screenshot of both pages.

### E - Playing StalkleHeads on screen (phase S7) — **passed 2026-11-22, with findings**

**Run on 2026-11-22**, E1-E6, E6 on two Steam accounts on two machines. Every check
passed except step 49. E6 also passed a second leave-and-rejoin with the host two
years ahead. What came back, and what was done about it (decisions.md D183):

- **Step 49 failed:** `<` and `>` walked the companies in id order, not board order.
- **E6 step 62:** a long industry name ran into the regime phrase on the Company tab.
- **Step 52:** with the news panel turned off, the year in review could only be
  reached through ... MORE, which only a long event has; and the panel opened from
  ... MORE showed "Don't show again" unticked when it was on.
- **Asked for:** your holdings listed in a panel beside the board, with selling
  from it, alongside RANKINGS and the desk; buying from every place a single company
  is shown; the trade box fixed in place with S greyed rather than hidden; a sort
  direction marker; lines between the year in review's sections; tooltips on the
  financial terms; a year-on-year change on the Company tab.
- **Asked about:** what the desk is, what breadth is, what "carried into year 9 as
  sentiment" means; whether the Industries tab has room for industry news (S8).

The steps below are as run. Section F re-checks the changes.


Built on 2026-11-22 (decisions.md D179-D182). The suite checks that every tab shows
the right figures, that a client's tabs match the host's line for line, and that
every tab fits the 640 x 360 picture. What it cannot judge is whether the screen
reads well: colours, the text charts, how crowded it feels, whether the year in
review is useful. **This is the first time StalkleHeads is playable.**

Run on a locally exported build containing S7. To check a checkout before
exporting: the folder `src/ui/screens/stalkleheads/` exists.

E1-E5 need one machine and no Steam. E6 needs two Steam accounts on two machines.

#### E1. The base game is unchanged

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **Stalks Stalks Stalks**.
4. Click **START**.
5. Check the screen has the three panels it always had: the stalk board, **Your Stats** and the rankings.
6. Check there are no tabs and no HELD column.
7. Press Escape, then quit to the title screen.

#### E2. The Exchange tab

8. On **SINGLE PLAYER**, set **Game** to **StalkleHeads**.
9. Click **START**.
10. Check there are four tabs under the top bar: **EXCHANGE**, **MARKET**, **INDUSTRIES**, **COMPANY**, with **EXCHANGE** lit.
11. Check the board shows industry headings (for example **CONSUMER GOODS**), each with its companies beneath it.
12. Check each company row shows a short code (SYM) before its name.
13. Check the B buttons are greyed (year 0, trading closed).
14. Press **Ready for New Year**.
15. Check the year reads **1** and the mood line under it shows BULL!!! or BEAR!!! followed by a percentage.
16. Click any industry heading.
17. Check its companies disappear and its marker changes from **-** to **+**.
18. Click the same heading again.
19. Check its companies come back.
20. Click the **P/E** column heading.
21. Check the companies inside each industry are re-ordered by P/E, and no company moves to a different industry.
22. In any company row, type **5** in the quantity box.
23. Click that row's **B**.
24. Check that row's HELD reads **5** and an **S** button has appeared.
25. Check **CASH** on the right went down.
26. Type **5** in the same quantity box and click **S**.
27. Check HELD reads **0** and the **S** button is gone.
28. Check the right-hand side shows **RANKINGS**, **THE DESK** (a list of strategies with percentages) and **SHORT INTEREST**.

#### E3. The Market and Industries tabs

29. Press **Ready for New Year** three times, closing the news panel each time it opens.
30. Click **MARKET**.
31. Check it shows the index level, market P/E, mood, breadth and risk-free rate.
32. Check **INDEX, BY YEAR** shows one bar per year, numbered from 0.
33. Check **THIS YEAR'S NEWS** shows the same event as the top bar.
34. Check **MOOD, BY YEAR** shows a B or b under each year played and a dot under each year still to come.
35. Click **INDUSTRIES**.
36. Check it lists six industries with this year's move, three-year move, average P/E and a share bar.
37. Click **Food**.
38. Check the chart heading reads **BY YEAR: FOOD** and the list on the right lists Food's companies with their shares.

#### E4. The Company tab

39. Click **EXCHANGE**.
40. Click a company's name.
41. Check the **COMPANY** tab opens on that company.
42. Check the line under the name shows the code, the industry and a phrase such as **SLOWING, 2nd year**.
43. Check **EARNINGS** has a column per year played, up to five, with whole numbers for revenue, expenses and profit.
44. Check **WHY THE PRICE MOVED** shows two prices with an arrow between them, then six lines, then **total**.
45. Click **EXCHANGE** and write down that company's **CHG**.
46. Click **COMPANY**.
47. Check **total** is the figure from step 45.
48. Click **>** three times.
49. Check each click shows the next row of the board.
50. Check **INVESTORS** reads **You** on a company you hold, and **none** on one nobody holds.

#### E5. The year in review

51. Press **Ready for New Year**.
52. Check the news panel opens with **THE YEAR IN REVIEW** above the event.
53. Check it shows the market's move and mood, every industry's move, and four lines below: biggest earnings surprise, biggest disappointment, dividend cut, the desk piled into. A line may be blank in a year with nothing to report.
54. Check nothing in the panel is cut off or overlapping.
55. Click **Close**.
56. Play on until the match ends.
57. Check every year advances, and no tab ever shows text spilling past its edge.

#### E6. A client sees what the host sees (two machines)

58. On A, set **Game** to **StalkleHeads**, then host an online game.
59. On B, join it from **JOIN GAME**.
60. On A, press **Start**.
61. On both machines, press Ready until the year is 3.
62. On both, click **COMPANY** and pick the same company with **<** and **>**.
63. Check the **EARNINGS** figures and **WHY THE PRICE MOVED** lines are the same on both machines.
64. On both, click **INDUSTRIES**.
65. Check the table is the same on both machines.
66. On B, press Escape, then **Leave Game**, then confirm.
67. On B, press **REJOIN GAME**.
68. Check B's **COMPANY** and **MARKET** tabs show the same as A's.

#### What a failure here means

- **Step 5 or 6 showing tabs** in the base game: the screen is choosing tabs for the wrong match (D180).
- **Step 21 moving a company out of its industry**: the sort is crossing groups (D182).
- **Step 47 not matching**: the ledger's total is not the board's change. Write down the company, both figures and the year.
- **Step 63, 65 or 68 differing**: a figure the client cannot rebuild. Send a screenshot of both screens.
- **Anything cut off**: write down the tab, the step and what was cut.

### F - StalkleHeads after the first play (decisions.md D183) — **passed 2026-11-22, with findings**

**Run on 2026-11-22.** F2's other steps, F3 and F4's sorting passed. What came back,
and what was done about it (decisions.md D184):

- **F1:** the panel should lie over MARKET, INDUSTRIES and COMPANY like a window, in
  a bright border, not push them across; holdings should look like the base game's,
  with SELL only.
- **F2 step 35:** "you hold 3" read as unprofessional; now **HELD 3**.
- **F4:** the sort mark belongs after the caption. Steps 51-56 tested something
  never asked for: the arrows following the board's sort. Reverted; a **COMPANIES**
  list was asked for instead, drawn over the tab.
- **NPC activity** was unreadable: names ran into the action and the position.
  Asked: a way to see which companies the desk holds (the list's NPC column).
- **F5:** tooltips were hard to read over text, too wide, and far from the pointer.
- **Asked:** do BUY and SELL fit on the board? They do now.

The steps below are as run. Section G re-checks the changes.


Re-checks what section E found and asked for. One machine, no Steam. Run on a
locally exported build containing D183. To check a checkout before exporting: the
file `src/ui/screens/stalkleheads/side_panel.tscn` exists.

#### F1. The side panel

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Check **HOLDINGS**, **RANKINGS** and **DESK** buttons sit at the right end of the tab strip, with **HOLDINGS** lit.
6. Check the panel on the right shows **CASH**, **NET** and **YOUR STALKS**, with **none** under it.
7. Click **RANKINGS**.
8. Check the panel shows the rankings.
9. Click **DESK**.
10. Check the panel shows the desk's strategies and **SHORT INTEREST**.
11. Click **HOLDINGS**.
12. Press **Ready for New Year**, closing the news panel if it opens.
13. Click **MARKET**.
14. Check the side panel is gone and the three buttons are still there, none lit.
15. Click **HOLDINGS**.
16. Check the panel opens beside the Market tab, and nothing on the tab is cut off.
17. Click **HOLDINGS** again.
18. Check the panel closes.
19. Click **DESK**.
20. Check the panel opens on the desk.
21. Click **INDUSTRIES**.
22. Check the panel is closed.
23. Click **EXCHANGE**.
24. Check the panel is open.

#### F2. The trade box and holdings

25. On the Exchange tab, check every company row ends in a quantity box, **B**, and a greyed **S**.
26. In the first company row, type **5** in the quantity box.
27. Click that row's **B**.
28. Check the box and the **B** did not move, and the row's **S** is no longer greyed.
29. Check **YOUR STALKS** on the right lists that company's short code with **5**.
30. In that line on the right, type **2** in the quantity box.
31. Click its **S**.
32. Check it now reads **3**, and the board row's HELD reads **3**.
33. Click the short code in the right-hand line.
34. Check the **COMPANY** tab opens on that company, with only **COMPANY** lit in the tab strip.
35. Check the line under the name reads the code, the whole industry name, the regime phrase, then **you hold 3**.
36. Type **3** in the Company tab's quantity box.
37. Click its **S**.
38. Check it reads **you hold 0** and its **S** is greyed.

#### F3. Buying from Industries

39. Click **INDUSTRIES**.
40. Click **Technology**.
41. Check each company in the list on the right has a quantity box, **B** and **S**.
42. Type **1** in the first company's box.
43. Click its **B**.
44. Click **HOLDINGS**.
45. Check that company is in **YOUR STALKS** with **1**.

#### F4. Walking and sorting

46. Click **EXCHANGE**.
47. Click the **P/E** column heading.
48. Check the heading now reads **^P/E** or **vP/E** and is brighter than the others.
49. Click **P/E** again.
50. Check the marker turns over.
51. Write down the first three companies of the board, top to bottom, by short code.
52. Click the first company's name.
53. Click **>** twice.
54. Check the codes shown are the second and then the third you wrote down.
55. Click **<** three times.
56. Check it shows the last company on the board.

#### F5. Tooltips and the year in review

57. On the Company tab, rest the mouse on **margin**.
58. Check a short definition appears.
59. Check **WHY THE PRICE MOVED**'s first line shows a percentage after the two prices.
60. Click **EXCHANGE** and rest the mouse on the **EPS** heading.
61. Check a definition appears.
62. Click **MARKET** and rest the mouse on **breadth**.
63. Check a definition appears.
64. Press Escape.
65. Click **SETTINGS**.
66. Untick **Show the year's news**.
67. Click **BACK**.
68. Click **BACK TO THE GAME**.
69. Press **Ready for New Year**.
70. Check the news panel does not open.
71. Click the event text in the top bar.
72. Check the news panel opens with **THE YEAR IN REVIEW**.
73. Check **Don't show again** is ticked.
74. Check lines separate the market line, the industries and the four lines below.
75. Check the market line ends **year N sentiment** and a percentage, N being next year.
76. Untick **Don't show again**.
77. Click **Close**.

#### What a failure here means

- **Step 14 or 22 showing the panel open**: the panel is not closing on a tab change.
- **Step 28 moving the box or B**: the trade box is not fixed.
- **Step 34 lighting two tabs**: the tab strip is not releasing the old tab.
- **Step 54 or 56 showing another company**: the arrows are not walking the board.
- **Anything cut off with the panel open**: write down the tab and what was cut.

### G - StalkleHeads after the second play (decisions.md D184) — **passed 2026-11-22, with findings**

**Run on 2026-11-22.** G1-G4 mostly passed; the tooltips read well. What came back,
and what was done about it (decisions.md D185):

- **G1:** the year in review had captions and phrases in lower case. Titles are now
  capitalised, phrases start with a capital, on every StalkleHeads screen.
- **G2:** asked for the company list to sort by its headings (done), and for the
  Company tab's title line to stay on screen while scrolling (pinned).
- **G3:** NPC ACTIVITY's columns were far apart; the trader column is now 30
  characters, under a framed heading.
- **G4:** marking a sort moved a right-aligned heading; and the gap left of a
  heading belongs to it, which looked like the previous heading's. Headings now
  keep a space for the mark and are drawn as cells, lit under the mouse.
  An industry header's tooltip repeated its name; removed.
- **Asked for:** key personnel on the Company tab. Recorded, not scheduled
  (stalkleheads-design.md §14).

The steps below are as run. Section H re-checks the changes.


Re-checks what section F found and asked for. One machine, no Steam. Run on a
locally exported build containing D184. To check a checkout before exporting: the
file `src/ui/screens/stalkleheads/company_picker.tscn` exists.

#### G1. The side panel over the tabs

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Check the panel on the right has a bright green border.
6. Check the board's rows end to the left of that border, none under it.
7. Check each company row ends in a quantity box, **BUY** and a greyed **SELL**.
8. Press **Ready for New Year**, closing the news panel if it opens.
9. In the first company row, type **5** in the quantity box.
10. Click that row's **BUY**.
11. Check **YOUR STALKS** on the right shows that company's short code, **5**, a box and **SELL**, and no **BUY**.
12. Click **MARKET**.
13. Write down the last word you can read at the right end of the **THIS YEAR'S NEWS** text's first line.
14. Click **HOLDINGS**.
15. Check the panel opens with a bright green border, on top of the right side of the tab.
16. Check the text you can still see on the left has not moved.
17. Click **HOLDINGS** again.
18. Check the panel closes and the word from step 13 is still at the end of the line.
19. Click **HOLDINGS**.
20. In the panel's line, type **2** in the box.
21. Click its **SELL**.
22. Check the line now reads **3**.
23. Click the short code in that line.
24. Check the **COMPANY** tab opens on that company and the line under the name ends **HELD 3**.

#### G2. The company list

25. On the Company tab, click **COMPANIES**.
26. Check a list of every company opens on top of the left side of the tab, with a bright green border, below the **COMPANIES** button.
27. Check the company on show is highlighted in the list.
28. Check some companies show a number under **NPC**.
29. Scroll the list to the bottom.
30. Click the last company in the list.
31. Check the list closes and the tab shows that company.
32. Click **COMPANIES**.
33. Click **COMPANIES** again.
34. Check the list closes.
35. Click **>**.
36. Check it shows the first company in the list from step 26.

#### G3. NPC activity

37. Click **COMPANIES**.
38. Click a company with a number under **NPC**.
39. Check **NPC ACTIVITY, LAST YEAR** shows headings **TRADER**, **LAST YEAR** and **NOW**, or the word **none**.
40. If it has headings, check each line shows a trader's name, one word such as **bought** or **shorted**, then a number or **short** and a number.

#### G4. Sorting and tooltips

41. Click **EXCHANGE**.
42. Click the **P/E** column heading.
43. Check it reads **P/E^** or **P/Ev**, the mark after the letters.
44. Rest the mouse on the **EPS** heading.
45. Check the tooltip has a solid background, its text easy to read.
46. Check the tooltip starts at the mouse pointer, not across the screen from it.
47. Click **COMPANY** and rest the mouse on **margin**.
48. Check the tooltip is no wider than about a third of the screen.
49. Click **MARKET** and rest the mouse on **risk-free**.
50. Check the tooltip touches the mouse pointer.
51. Click **EXCHANGE** and rest the mouse on the **HELD** heading, at the right of the board.
52. Check the tooltip sits beside the pointer, not against the far left of the screen.

#### What a failure here means

- **Step 6 showing a row under the panel**: the board's free column is narrower than the panel.
- **Step 16 or 18 showing text moved**: the panel is pushing the tab, not lying over it.
- **Step 26 covering COMPANIES**: the list starts too high.
- **Step 36 showing another company**: the arrows are not walking the list's order.
- **Steps 45-52**: send a screenshot with the pointer in it.

### H - StalkleHeads after the third play (decisions.md D185) — **passed 2026-11-22, with findings**

**Run on 2026-11-22.** H1-H3 passed. What came back, and what was done about it
(decisions.md D186):

- **H1:** the market line should start **The Market:**. Changed.
- **H2:** a long company description was cut off, and the Company tab is the only
  place it is shown. It is now shown whole and pushes the rest of the tab down.
- **H3:** the headings' captions touched the lines between them. Each now has 2
  pixels either side; PRICE and HELD gained a character, CHG and DIV gave one.

The steps below are as run. Section I re-checks the changes.

Re-checks what section G found and asked for. One machine, no Steam. Run on a
locally exported build containing D185. To check a checkout before exporting: the
file `src/ui/palette.gd` contains the word `sentence_case`.

#### H1. Capitals

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Press **Ready for New Year** twice.
6. Check the news panel's year in review reads **Year 2** at the right, and its market line starts **The market** and has **Market P/E** and **Year 3 sentiment**.
7. Check the four lines below start **Biggest earnings surprise**, **Biggest disappointment**, **Dividend cut** and **The desk piled into**, and their right-hand words start with a capital.
8. Click **Close**.
9. Click **MARKET**.
10. Check the captions read **Index level**, **Market P/E**, **Mood**, **Breadth**, **Risk-free**.
11. Click **COMPANY**.
12. Check the earnings captions start with a capital (**Revenue**, **Expenses**) and the year columns read **Year 0**, **Year 1**, **Year 2**.
13. Check **WHY THE PRICE MOVED** lines start with a capital and the last reads **Total**.

#### H2. The Company tab

14. Click **COMPANIES**.
15. Click the **NPC** heading.
16. Check it reads **NPC^** and the list is re-ordered by that column.
17. Click **NPC** again.
18. Check it reads **NPCv** and the companies with the largest numbers are at the top.
19. Click **SYM**.
20. Check the list is in alphabetical order of the short codes.
21. Click the company at the top of the list.
22. Scroll down to **NPC ACTIVITY, LAST YEAR**.
23. Check **COMPANIES**, **<**, the company name and **>** are still at the top.
24. If it shows traders, check the three columns sit close together under a framed heading row: **TRADER**, **LAST YEAR**, **NOW**.

#### H3. The board's headings

25. Click **EXCHANGE**.
26. Check each column heading has a faint line down its right-hand edge.
27. Move the mouse slowly from **P/E** across to **DIV**.
28. Check each heading lights up while the mouse is over it, and the light moves from P/E to DIV at the line between them.
29. Click **P/E**.
30. Check the letters **P/E** did not move and **^** appeared after them.
31. Click **P/E** again.
32. Check it reads **P/Ev** and the letters still did not move.
33. Rest the mouse on an industry name, such as **FOOD**.
34. Check no tooltip appears.

#### What a failure here means

- **Step 23 showing the title line gone**: the title line is scrolling with the tab.
- **Step 28 lighting the wrong heading**: write down which heading lit and where the mouse was.
- **Step 30 or 32 showing the letters moved**: the heading's spare space is missing.

### I - StalkleHeads after the fourth play (decisions.md D186) — **passed 2026-11-22**

**Run on 2026-11-22.** I1-I3 passed. Asked for with it (decisions.md D187): lorem
ipsum descriptions for the companies that have none, the industry chart in green
and red, and no tooltip on a desk trader's name. Section J checks them.

Re-checks what section H found. One machine, no Steam. Run on a locally exported
build containing D186. To check a checkout before exporting: the file
`src/ui/widgets/company_row.gd` contains `PRICE_CHARS: int = 7`.

#### I1. The Market:

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Press **Ready for New Year** twice.
6. Check the year in review's market line starts **The Market:**.
7. Click **Close**.

#### I2. Whole descriptions

8. Click **COMPANY**.
9. Click **COMPANIES**.
10. Click a company with a long name, such as **My Pillow, Your Pillow, We're All Pillows!**.
11. Check the description under the identity line ends in a full stop, not **...**.
12. Check the tables below it start under the description's last line, not over it.
13. Click **>** until you have looked at five more companies.
14. Check none of their descriptions ends in **...**.

#### I3. The board's headings

15. Click **EXCHANGE**.
16. Check there is a gap between each heading's letters and the faint line either side of it: **NAME**, **PRICE**, **HELD** especially.
17. Click **PRICE**.
18. Check **PRICE^** has a gap before the line on its right.
19. Click **PRICE** again.
20. Check **PRICEv** still has the gap.
21. Check each company's price, change, EPS, P/E, dividend and held number still sits under its heading.
22. Find a bankrupt company, if one has gone bankrupt.
23. Check **BANKRUPT** is written in full and the columns after it line up with the rows above.

#### What a failure here means

- **Step 11 or 14 showing ...**: the description still has a line limit.
- **Step 12 showing overlapping text**: the description grew without pushing the rest down.
- **Step 21 showing a figure out from under its heading**: the header and the rows have different widths.

### J - StalkleHeads after the fifth play (decisions.md D187) — **not yet run**

One machine, no Steam. Run on a locally exported build containing D187. To check a
checkout before exporting: the file `src/ui/widgets/chart_widget.gd` contains
`coloured_signed`.

#### J1. The industry chart

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Press **Ready for New Year** four times, closing the news each time.
6. Click **INDUSTRIES**.
7. Click an industry that has both rising and falling years.
8. Check the bars above the **0** line are green and the bars below it are red.
9. Check the numbers, the axis line and the year numbers are not coloured.

#### J2. Placeholder descriptions

10. Click **COMPANY**.
11. Click **COMPANIES**.
12. Click **Food Company A**.
13. Check a lorem ipsum paragraph is shown under the identity line.

#### J3. Trader names

14. Click **COMPANIES**.
15. Click a company whose **NPC** number is not blank.
16. Scroll down to **NPC ACTIVITY, LAST YEAR**.
17. Rest the mouse on a trader's name.
18. Check no tooltip appears.

### K - StalkleHeads drawn charts (decisions.md D188) — **not yet run**

One machine, no Steam. Run on a locally exported build containing D188. To check a
checkout before exporting: the file `src/ui/widgets/drawn_chart.gd` exists. Can be
run before or after section J.

#### K1. The index line

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Press **Ready for New Year** five times, closing the news each time.
6. Click **MARKET**.
7. Check **INDEX, BY YEAR** is a green line with a dot for each year, and year numbers under it.
8. Rest the mouse over the dot for year 3.
9. Check a tooltip says **Year 3** and the index level.

#### K2. The Company tab's charts

10. Click **COMPANY**.
11. Check a row of buttons reads **TABLE**, **PRICE**, **SALES**, **MARGIN**, **PER SHARE**, **P/E**, with **TABLE** lit.
12. Check the earnings table is shown as before.
13. Click **PRICE**.
14. Check only **PRICE** is lit, and the table is replaced by one bar per year from year 1: green where the price rose, red where it fell.
15. Check each bar starts at the height where the bar before it ended.
16. Rest the mouse over one bar.
17. Check a tooltip gives that year and the price it moved from and to.
18. Click **SALES**.
19. Check two bars per year, named **Revenue** and **Profit** above the chart.
20. Click **MARGIN**.
21. Check one line, a point for each year.
22. Click **PER SHARE**.
23. Check two bars per year, named **Earnings/share** and **Dividend**.
24. Click **P/E**.
25. Check two lines, named **P/E** and **Industry**.
26. Click **>**.
27. Check the next company is shown and **P/E** is still the chart shown.
28. Click **TABLE**.
29. Check the earnings table is back and nothing below it has moved.

#### K3. The bond

30. Click **COMPANIES**.
31. Click **BERRY BONDS**.
32. Check there is no row of chart buttons.

#### What a failure here means

- **Step 14 showing more than one button lit**: the buttons are not releasing each other.
- **Step 15 showing a gap or a jump**: write down the company and the year.
- **Step 29 showing the tab below moved**: the chart and the table are different heights.

### L - StalkleHeads year in review on the Market tab (decisions.md D189) — **passed 2026-11-23, with findings**

**Run on 2026-11-23.** It looked good, but condensed: no clear sections, and lines
too tight. Done in D190: bright rules between the sections, a gap under the event,
ordinary spacing. Section M checks it.

A trial: if it is not wanted, it is one commit to revert. One machine, no Steam.
Run on a locally exported build containing D189. To check a checkout before
exporting: the file `src/ui/widgets/year_digest_panel.gd` contains `set_narrow`.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Click **MARKET**.
6. Check there is no **THE YEAR IN REVIEW** yet.
7. Press **Ready for New Year**.
8. Click **Close** on the news.
9. Check the left half shows **THE MARKET** and the index chart, and the right half shows **THIS YEAR'S NEWS** and **MOOD, BY YEAR**.
10. Check **THE YEAR IN REVIEW** is under the mood, with **Year 1** at its right.
11. Scroll down with the mouse over the right half.
12. Check only the right half moves, and the left half stays put.
13. Check the industries are in two columns.
14. Check each line such as **Biggest earnings surprise** has the company and its figure on the line below it.
15. Check the lines match the ones the news panel showed.
16. Click **... MORE** in the top strip.
17. Check the news panel's year in review looks as it did before.
18. Click **Close**.

#### What a failure here means

- **Step 12 showing the whole tab moving**: the tab, not the right half, is scrolling.
- **Step 15 showing different figures**: write down which line differs.

### M - StalkleHeads Market tab spacing (decisions.md D190) — **passed 2026-11-23**

One machine, no Steam. Run on a locally exported build containing D190. To check a
checkout before exporting: the file `assets/themes/stalks_theme.tres` contains
`SectionRule`.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Press **Ready for New Year**.
6. Click **Close** on the news.
7. Click **MARKET**.
8. Check there is a gap between the event's text and the line saying what it did.
9. Check a bright green line runs between **THIS YEAR'S NEWS** and **MOOD, BY YEAR**.
10. Check a bright green line runs between the mood and **THE YEAR IN REVIEW**.
11. Check the lines inside the year in review are the faint ones, as before.
12. Check no lines of text touch the lines above or below them, on either half.

### N - StalkleHeads owned companies in the company list (decisions.md D191) — **passed 2026-11-23**

One machine, no Steam. Run on a locally exported build containing D191. To check a
checkout before exporting: the file `src/ui/screens/stalkleheads/company_picker.gd`
contains `OWNED_MARK`.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. On **EXCHANGE**, click **BUY** on any company's row.
6. Click **COMPANY**.
7. Click **COMPANIES**.
8. Check the name heading reads **NAME (* OWNED)**.
9. Check the company you bought has **\*** before its name, and no other company does.
10. Check the other names line up with the starred one's first letter.
11. Click **COMPANIES** to close the list.

### O - StalkleHeads private messages (decisions.md D192, D193) — **passed 2026-11-23**

One machine, two copies of the game, no Steam. Run on a locally exported debug build
containing D192 (a release build ignores the launch flags). To check a checkout
before exporting: the file `src/net/message_rules.gd` exists. The two copies are
called **A** (the host) and **B**.

1. Open the folder holding the exported build (`stalks-build`) in File Explorer.
2. Click the address bar, type `powershell` and press **Enter**.
3. In the PowerShell window, type the command below and press **Enter**:

   ```powershell
   .\StalksStalksStalks.exe --host --game=stalkleheads --name=A
   ```

4. In the same PowerShell window, type the command below and press **Enter**:

   ```powershell
   .\StalksStalksStalks.exe --join --name=B
   ```

5. If Windows asks to allow the game through the firewall, click **Allow**.
6. On B, click **READY**.
7. On A, click **START**.
8. On both, click **Close** on the news if it is showing.
9. On A, check the **MESSAGES** tab button ends in a grey square.
10. On A, click **MESSAGES**.
11. Check the list on the right reads **A (you)** and **B**, each with a grey square.
12. On A, click **B** in the list.
13. Check the header reads **Chat with B**.
14. Click the message box.
15. Type `hello <(' ')>` and press **Enter**.
16. Check the chat shows **You: hello <(' ')>** and the box is empty.
17. On B, check the **MESSAGES** button's square is yellow.
18. On B, click **MESSAGES**.
19. Check the square beside **A** is yellow.
20. On B, click **A** in the list.
21. Check the chat shows **A: hello <(' ')>**.
22. Check the square beside **A** and the square on the **MESSAGES** button are grey.
23. On B, click the message box.
24. Type `[url=https://example.com]x[/url] \\server\share` and press **Enter**.
25. On A, check the line shows exactly those characters, square brackets and backslashes included.
26. On A, click on that line.
27. Check nothing opens: no browser, no File Explorer window.
28. On B, click **B (you)** in the list.
29. Check two chats are side by side, and the new one's header reads **Notes - only you see these**.
30. Click the notes' message box.
31. Type `a note` and press **Enter**.
32. Check the notes show **You: a note**.
33. On A, check nothing new arrived in the chat with B, and every square is grey.
34. On B, click **A**'s message box.
35. Type `1` and press **Enter**.
36. Type `2` and press **Enter**.
37. Type `3` and press **Enter**.
38. Type `4` and press **Enter**.
39. Type `5` and press **Enter**.
40. Type `6` and press **Enter**.
41. Check red text under the box reads **Not sent: Too many messages. Wait a few seconds.** and `6` is still in the box.
42. Wait ten seconds.
43. Press **Enter**.
44. Check **You: 6** appears and the red text is gone.
45. On A, check the chat with B shows 1 to 6, each once.
46. Close B's window.
47. On A, click the message box in the chat with B.
48. Type `are you there` and press **Enter**.
49. Check red text says B is not here, and the text stays in the box.
50. Close A's window.

#### What a failure here means

- A square that never turns yellow, or never goes grey: the book's `changed` signal
  is not reaching the screen (`GameplayScreen._on_messages_changed`).
- A message that arrives at the wrong copy, or twice: the relay
  (`HostSession._route_message`).
- Step 27 opening anything is a security fault: stop and report it before playing on.

### P - StalkleHeads from the DEV panel, three players (decisions.md D194) — **passed 2026-11-23**

One machine, three copies of the game, no Steam. Run on a locally exported debug
build containing D194 (a release build has no DEV panel). To check a checkout before
exporting: the file `src/ui/widgets/dev_overlay.tscn` contains `DevGameButton`. The
copies are called **A** (the host), **B** and **C**.

1. Open the folder holding the exported build (`stalks-build`) in File Explorer.
2. Double-click `StalksStalksStalks.exe`. This is A.
3. Double-click `StalksStalksStalks.exe` again. This is B.
4. Double-click `StalksStalksStalks.exe` a third time. This is C.
5. On A, find the **DEV** panel in the top-left corner.
6. Check the button under **Port** reads **Stalks Stalks Stalks**.
7. On A, click that button.
8. Check it now reads **StalkleHeads**.
9. On A, click **HOST**.
10. If Windows asks to allow the game through the firewall, click **Allow**.
11. Check A shows a lobby.
12. On B, click **JOIN** on the DEV panel.
13. On C, click **JOIN** on the DEV panel.
14. Check all three lobbies list three players.
15. On B, click **READY**.
16. On C, click **READY**.
17. On A, click **START**.
18. On all three, click **Close** on the news if it is showing.
19. Check all three show the tabs, including **MESSAGES**.
20. On A, click **MESSAGES**.
21. Check the list shows three players, A's own marked **(you)**.
22. On A, click **B**'s name.
23. Click the message box, type `for B` and press **Enter**.
24. On B, check the **MESSAGES** button's square is yellow.
25. On C, check the **MESSAGES** button's square is grey.
26. On C, click **MESSAGES**.
27. On C, click **B**'s name.
28. Click the message box, type `from C` and press **Enter**.
29. On B, click **MESSAGES**.
30. Check the squares beside **A** and **C** are both yellow.
31. On B, click **A**'s name, then **C**'s name.
32. Check two chats are open: **for B** from A and **from C** from C.
33. On A, check nothing from C arrived: every square is grey.
34. Close all three windows.

### Q - StalkleHeads ALL PLAYERS and blocking (decisions.md D195, D196) — **passed 2026-11-23**

One machine, three copies of the game, no Steam. Run on a locally exported debug
build containing D195 and D196. To check a checkout before exporting: the file
`src/ui/widgets/chat_panel.tscn` contains `BlockButton`. The copies are called
**A** (the host), **B** and **C**.

1. Open the folder holding the exported build (`stalks-build`) in File Explorer.
2. Double-click `StalksStalksStalks.exe`. This is A.
3. Double-click `StalksStalksStalks.exe` again. This is B.
4. Double-click `StalksStalksStalks.exe` a third time. This is C.
5. On A, click the button under **Port** on the **DEV** panel until it reads **StalkleHeads**.
6. On A, click **HOST**.
7. If Windows asks to allow the game through the firewall, click **Allow**.
8. On B, click **JOIN** on the DEV panel.
9. On C, click **JOIN** on the DEV panel.
10. On B, click **READY**.
11. On C, click **READY**.
12. On A, click **START**.
13. On all three, click **Close** on the news if it is showing.
14. On all three, click **MESSAGES**.
15. Check the first name in each list is **ALL PLAYERS**.
16. On A, click **ALL PLAYERS**.
17. Check the chat's header reads **Chat with all players**.
18. Check the chat has no **BLOCK?** button.
19. Click the message box, type `hello all` and press **Enter**.
20. On B, check the square beside **ALL PLAYERS** is yellow.
21. On C, check the square beside **ALL PLAYERS** is yellow.
22. On A, check the square beside **ALL PLAYERS** is grey.
23. On B, click **ALL PLAYERS**.
24. Check the chat shows **hello all** from A.
25. On C, click **A**'s name.
26. Check the chat with A is empty: the room message did not land here.
27. Check **BLOCK?** shows at the right of the chat's header.
28. On C, click **BLOCK?**.
29. Check the button now reads **UNBLOCK**.
30. Check the header ends **(blocked)**.
31. Check A's name in C's list is grey and ends **(blocked)**.
32. On A, click **C**'s name.
33. Click the message box, type `secret` and press **Enter**.
34. Check A shows no **Not sent** line.
35. On A, click **ALL PLAYERS**.
36. Click the message box, type `to the room` and press **Enter**.
37. On C, check nothing from A arrived: no square in C's list is yellow.
38. On B, check **to the room** arrived in **ALL PLAYERS**.
39. On C, click **UNBLOCK**.
40. Check A's name in C's list is no longer grey and has no **(blocked)**.
41. On A, type `again` in the chat with C and press **Enter**.
42. On C, check **again** arrived from A, and **secret** did not.
43. Close all three windows.

### R - Messages kept through a host migration (decisions.md D197, D198) — **passed 2026-11-23**

Needs Steam: a host migration happens only in a Steam lobby. Three computers (or
accounts), each with a locally exported build containing D197; to check a checkout
before exporting, `src/ui/screens/main/main.gd` contains `_migrating_messages`.
The players are **A** (the host), **B** and **C**.

1. On A, host a StalkleHeads match over Steam.
2. On B, join it.
3. On C, join it.
4. On A, click **START** once B and C are ready.
5. On all three, click **MESSAGES**.
6. On B, click **C**'s name.
7. Click the message box, type `one` and press **Enter**.
8. Check the cursor is still in the box.
9. Type `two` and press **Enter**.
10. Type `three` and click **SEND**.
11. Check the cursor is still in the box.
12. On C, click **B**'s name.
13. Check **one**, **two** and **three** are there.
14. On C, click **ALL PLAYERS**, type `room` and press **Enter**.
15. On B, click **C**'s name, then click **BLOCK?**.
16. On A, close the game window.
17. Wait until B and C are back on the playing screen.
18. On whichever of B or C is now the host, click **MESSAGES**.
19. Check its chat with the other one still holds **one**, **two** and **three**.
20. Check **ALL PLAYERS** still holds **room**.
21. On the other of B or C, click **MESSAGES**.
22. Check the same two things.
23. On B, check **C**'s name is still grey and ends **(blocked)**.
24. On C, send B `after`.
25. Check B shows nothing new from C.
26. On B, click **C**'s name, then **UNBLOCK**.
27. On C, send B `again`.
28. Check B shows **again**.
29. Close all the game windows.

### S - StalkleHeads news (decisions.md D199-D203) — **passed 2026-11-23, with findings**

**Run on 2026-11-23.** Every step passed. What came back:

- **Step 13:** the tooltip read strangely; the owner gave its words, now in place.
  Text added to the game is in American spelling (rumor, not rumour).
- **The whispers themselves:** they state facts about this year, which reads like a
  company spotlight, not a rumor. The owner wants them to foreshadow next year
  against expectations, from sources of named reliability. A design question, not a
  layout one; built as stalkleheads-design.md §8.4 (D205, D206), checked as section T.

One machine, no Steam. Run on a locally exported build containing D199; to check a
checkout before exporting, the file `src/sim/news_selector.gd` exists. Every line is
a placeholder that starts with its kind in capitals, such as
**INDUSTRY REPORT: energy, down**. The point is where each shows and how it reads,
not the words.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Click **MARKET**.
6. Check there is no **WHISPERS** heading and no headline yet: no year has been played.
7. Press **Ready for New Year**.
8. Click **Close** on the news.
9. Click **MARKET**.
10. Check a line starting **MARKET HEADLINE:** sits under **THIS YEAR'S NEWS**, above the event.
11. If a **WHISPERS** heading shows at the top of the right half, check each line under it starts **WHISPER:** and names a company or an industry, not `{company}`.
12. Hover over the word **WHISPERS**.
13. Check a tooltip says whispers are rumors and not all are true.
14. Click **INDUSTRIES**.
15. Check a **NEWS** heading under the members list has a line starting **INDUSTRY REPORT:** naming the selected industry.
16. Click **Food**.
17. Check the report now names **food**.
18. Click **COMPANY**.
19. Check a **NEWS** section above **INVESTORS** has a line starting **EARNINGS:** with this company's name in it.
20. Click **>** until **NPC ACTIVITY** lists at least one trader.
21. Check a fainter, indented line under the trader's row starts **NPC CHATTER:**.
22. Click **DESK** on the side panel.
23. Scroll to the bottom of the DESK page.
24. Check a **CHATTER** list names each trader that acted, each followed by its **NPC CHATTER:** line.
25. Press **Ready for New Year** four more times, clicking **Close** on the news each time.
26. Click **MARKET**.
27. Check the headline still sits above the event, and nothing overlaps.
28. Close the game window.

### T - StalkleHeads whispers that foretell next year (decisions.md D205, D206) — **passed 2026-11-23, with findings**

**Run on 2026-11-23.** Every whisper step passed. What came back:

- **Steps 6 and 13:** whispers showed in year 0, and again in the history as ABOUT
  YEAR 1. Nobody can trade in year 0, so a whisper about year 1 cannot be used.
  Fixed by D207 (none before the end of year 1), checked as section U. The steps
  below are as run; with D207, steps 6-14 now find no whispers.


One machine, no Steam. Run on a locally exported build containing D205; to check a
checkout before exporting, the file `src/sim/whisper_rules.gd` exists. Every whisper
is still a placeholder, such as **WHISPER: Food, much worse**; the last words are
the outcome it foretells for next year.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Click **MARKET**.
6. Check **WHISPERS** shows two lines before any year has been played.
7. Check each line starts with a faint source name: **Rock Solid**, **Credible**, **Hit-or-miss**, **Questionable** or **Gossip**.
8. Check the words of both lines start at the same place, whatever the source.
9. Hover over the word **WHISPERS**.
10. Check the tooltip reads "Whispers from the Avenue. Rumors circulating around the Market." and "Most are true, but some are not. Can you find the truth?"
11. Check a **VIEW HISTORY** button sits under the whispers.
12. Click **VIEW HISTORY**.
13. Check a **WHISPER HISTORY** panel covers the right half, with **ABOUT YEAR 1** and the same two whispers.
14. Check each whisper has **Outcome: not known yet** under it.
15. Click **CLOSE**.
16. Press **Ready for New Year**.
17. Click **Close** on the news.
18. Click **MARKET**.
19. Click **VIEW HISTORY**.
20. Check **ABOUT YEAR 2** is at the top, its whispers marked **Outcome: not known yet**.
21. Check **ABOUT YEAR 1** is below it, each whisper now with an outcome such as **Outcome: better than expected**.
22. Click **EXCHANGE**.
23. Click **MARKET**.
24. Check the history panel is closed and the current whispers show.
25. If neither whisper names a company, press **Ready for New Year**, click **Close**, click **MARKET**, and repeat until one does.
26. Note the company's name.
27. Click **COMPANY**.
28. Click **>** until the company you noted is shown.
29. Check its **NEWS** section shows the same whisper, with its source before it.
30. Close the game window.

### U - No StalkleHeads whispers in year 0 (decisions.md D207) — **passed 2026-11-23**

**Run on 2026-11-23.** Every step passed.

One machine, no Steam. Run on a locally exported build containing D207; to check a
checkout before exporting, `src/sim/news_selector.gd` contains `FIRST_WHISPER_YEAR`.

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Click **START**.
5. Click **MARKET**.
6. Check there is no **WHISPERS** heading.
7. Check there is no **VIEW HISTORY** button.
8. Press **Ready for New Year**.
9. Click **Close** on the news.
10. Click **MARKET**.
11. Check **WHISPERS** shows two lines.
12. Click **VIEW HISTORY**.
13. Check only **ABOUT YEAR 2** is listed.
14. Close the game window.

### V - StalkleHeads news redesign (decisions.md D208-D214) — **not yet run**

One machine, no Steam. Run on a locally exported build containing D215; to check a
checkout before exporting, the file `src/sim/report_writer.gd` exists. The EARNINGS
and INDUSTRY REPORT lines are written by code. Every other line except the twelve
market news headlines, the industry headlines and the company news ported from the
base game's events is still a placeholder, such as **IN THE NEWS: strYker!!!, up**.

**The headline and the Exchange**

1. Start the game.
2. Click **SINGLE PLAYER**.
3. Set **Game** to **StalkleHeads**.
4. Set **Years** to **30**.
5. Click **START**.
6. Press **Ready for New Year**.
7. Check the news panel shows one of the twelve market headlines, with no **MARKET HEADLINE:** in front of it.
8. Click **Close** on the news.
9. Check the top strip shows the same headline.
10. Check the line under it is empty, not "No special event this year."
11. Click **MARKET**.
12. Check **THIS YEAR'S NEWS** shows the same headline.
13. Check the whisper heading reads **WHISPERS FROM THE AVENUE**.
14. Click **EXCHANGE**.
15. Click a company row's price, away from its ticker and name.
16. Check the Exchange is still shown.
17. Click the same row's ticker.
18. Check the **COMPANY** tab opens on that company.

**The Company tab**

19. Check **NEWS** starts with a faint **EARNINGS** heading.
20. Check the line under it reads like "Mafia HUD Scam's revenue fell 14%, far worse than expected. The company is in distress.", naming this company.
21. Check the regime in its last sentence matches the one shown at the top of the tab.
22. Check a faint **IN THE NEWS** heading follows, with one line under it, and that no line starting **EARNINGS:** is shown.
23. Click **>** until **Mafia HUD Scam** is shown.
24. Check its **IN THE NEWS** line is one of the base game's Mafia events, with no price change written after it.

**The Industries tab**

25. Click **INDUSTRIES**.
26. Check a **FROM THE HEADLINES** heading is shown, with the industry's headline under it.
27. Check an **INDUSTRY REPORT** heading follows, with a line like "Energy fell, worse than expected. Expected to rise next year.", naming the selected industry.
28. Check the **BY YEAR** chart shows one bar, captioned **1**.
29. Press **Ready for New Year**.
30. Click **Close** on the news.
31. Repeat steps 29 and 30 five more times, to year 7.
32. Click **INDUSTRIES**.
33. Check **BY YEAR** shows a bar for each year from 1 to 7, each captioned with its year.
34. Hover over the year 7 bar.
35. Check the tooltip names year 7 and the industry's move.

**Short interest and the squeeze**

36. Look at **SHORT INTEREST** in the side panel.
37. Check each entry is a ticker and a percent, such as **STRYK 12%**, not a share count.
38. Hover over a percent.
39. Check the tooltip gives the number of shares sold short.
40. If no entry ends **FLAGGED** or **SQUEEZED**, press **Ready for New Year**.
41. Click **Close**.
42. Repeat steps 40 and 41 until an entry ends **FLAGGED** or **SQUEEZED**, up to year 20.
43. If none did by year 20, write down "no squeeze seen" and skip to step 59.
44. Note the company, and whether it says **FLAGGED** or **SQUEEZED**.
45. Click **MARKET**.
46. Check one of the two whispers names that company and has the source **Questionable**.
47. Check the other whisper is about something else.
48. If it said **SQUEEZED**, skip to step 54.
49. Press **Ready for New Year**.
50. Click **Close**.
51. Repeat steps 49 and 50 until **THIS YEAR'S NEWS** shows a short squeeze, or the company is no longer **FLAGGED**, up to five years. If no squeeze showed, skip to step 59.
52. Check **THIS YEAR'S NEWS** has the market headline first, with the squeeze as its own item under it.
53. Check the squeezed company's entry under **SHORT INTEREST** now ends **SQUEEZED**.
54. Press **Ready for New Year**.
55. Click **Close**.
56. Repeat steps 54 and 55, watching that company's percent, until **THIS YEAR'S NEWS** says **Short squeeze over**, up to five years.
57. Check the percent fell each year, and the company left the **SHORT INTEREST** list the year before the squeeze came off.
58. Click **MARKET**, click **VIEW HISTORY**, and check the squeeze whisper shows **Outcome: it happened** or **Outcome: it did not happen**.
59. Close the game window.

**Not checked here:** a market news line that moves a price. No shipped line has an
amount yet; `test_earnings_year_resolver.gd` covers company and industry effects.

### Known gaps, so they are not surprises

- **Everything below was found with locally exported builds until
  2026-11-20**, when the game first went up as a Steam **beta branch** and was
  played from two real installs. Steam invites, host migration and rejoining
  all worked that way. That is a stronger result than it sounds: an installed
  build exercises the App ID, the depot and Steam's own overlay and invite
  plumbing, none of which a local export touches. Where an entry below says
  "confirmed in play" without saying how, it means a local export - the
  beta-branch run is the only one so far that covers the real pipeline.
- **The rematch has been played**, on 2026-11-20, the day it was built: a
  client asking for one and the host seeing the request, both players going
  back to the lobby and playing again, a different market the second time, the
  host starting a rematch alone, and a rematch surviving a host migration. The
  notice on the final board - the host's view of a request, and a client being
  told the host has reopened the lobby - was confirmed the same day. What that
  run did *not* cover is a player who declines, or a rematch from an installed
  build rather than the editor.

- **Steam's friends list was run on the beta build** (B6j). **Join Game** is
  offered for an ordinary online game and works; it is **not** offered for an
  invite-only one, which is what `k_ELobbyTypePrivate` means and is therefore
  the right answer rather than a gap. See B6j.

- **The two panels that would not hold still were confirmed in play on
  2026-11-20** (D125): the result card no longer changes size when you switch
  between FINAL STANDINGS and YEAR BY YEAR, the lobby card no longer grows when
  somebody joins, and the lobby now sits where the title screen does. The title
  screen's own message (D126) has **not** been looked at in play - A8f 7a-7e.

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
