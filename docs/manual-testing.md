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
| Host: **HOST** → **Open a lobby** | Lobby screen. Subtitle names an address and port. |
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
| Look at the host's rankings | Guest's **net worth** changes. |
| Look at the host's view of the guest's **cash** | It must **not** match. Cash is private. |
| Guest types a quantity, host buys something meanwhile | Guest's typed quantity is still there. |
| Guest tries to buy far more than they can afford | Refused, with a reason on screen. Nothing bought. |

**Failure signs:** a rival's exact cash visible; a typed quantity vanishing when
somebody else trades; a refusal with no message.

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

**Failure signs:** panel staying open after a successful borrow; a refusal with
no visible reason; readying up with a payment due asking nothing.

### A9. Disconnection

| Step | Expected |
|---|---|
| Mid-match, close the guest's window entirely | Host's rankings drop to one player. |
| Host readies up | **The year still advances.** |

**Failure signs:** the host stuck unable to advance. That was the deadlock
behind D46/D47 and is the single most important thing in this test.

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
| **Play on Steam** from the menu | The browser screen says "Signed in as <your persona name>". |

**Failure signs:** a message saying Steam is not running, or not installed.
If Steam *is* running, suspect the account ownership above.

### B2. Finding each other

| Step | Expected |
|---|---|
| Machine 1: **HOST** | Lobby screen. Subtitle mentions invites, not a port. |
| Machine 2: **Play on Steam**, then **REFRESH** | Machine 1's game appears in the list, named after their persona. |
| Machine 2: **JOIN** on that row | Both reach the lobby, as in A1. |

**Failure signs:** the lobby never appearing in the list. Both accounts must be
running the same App ID, and the lobby is filtered on a `game=stalks` tag.

### B3. Playing

Repeat **A3 through A7** over the Steam connection. They are the same screens
and the same code; what is being checked is that the traffic arrives.

**Failure signs:** anything that worked in Test A failing here points at the
Steam transport specifically, which is a much narrower place to look.

### Known gaps, so they are not surprises

- **Steam invites do not work yet.** Accepting an invite reports to the game,
  but nothing acts on it. Use the browser.
- **No achievements unlock.** They are catalogued but nothing calls Steam yet.
- **No sound.**

---

## Reporting back

For anything that fails, the useful things are: which step, what you expected,
what happened instead, and a screenshot if it is visual. Layout faults have
been diagnosed far faster from a screenshot than from a description.

If a build misbehaves, run `StalksStalksStalks.console.exe` instead of the
plain one — it prints errors to a terminal window.
