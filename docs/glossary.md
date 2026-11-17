# Glossary

Terms used across the code and documentation. Game terms first, then code terms.

---

## Game terms

**Stalk** — a fictional company share, the game's pun on "stock". Players buy and
sell these. There are ten, listed with their statistics in
[game-rules.md §3](game-rules.md).

**Mood** — whether a given year is **bull** or **bear**. Decided once per year and
applied to the whole market. Bull years generally push prices up, bear years down.
Weighted 7 to 5 in favour of bull. See [game-rules.md §4.2](game-rules.md).

**Bull year** — a good year. Prices generally rise and bull dividends are paid.

**Bear year** — a bad year. Prices generally fall and bear dividends are paid, which
for several stalks is nothing at all.

**Contrarian move** — the 10% chance that an individual stalk moves *against* the
year's mood: a small gain in a bear year, a small loss in a bull year. Rolled per
stalk, independently. See [game-rules.md §4.3](game-rules.md).

**Yearly change** — the price movement displayed to players on the stalk board.
Important subtlety: this is the **normal move only** and deliberately **excludes** any
special-event movement, matching the original game.

**Special event** — one flavoured price shock per year, aimed at a single named
stalk, drawn from a mood-specific pool. Carries comedic flavour text and a price
delta. 45 bull and 45 bear events exist. See [game-rules.md §5](game-rules.md).

**Split** — when a stalk's price rises above 150, the price halves (**rounding up** on
an odd price) and every holder's share count doubles. See
[game-rules.md §6](game-rules.md).

**Bankrupt (a stalk)** — when a stalk's price falls to 0 or below, it fails. All
holders lose every share in it, with no compensation. The board entry stays visible,
overlaid with "BANKRUPT!!!".

**Bankrupt (a player)** — a player who misses a third loan payment. Their cash, net
worth and holdings are all set to zero.

**Dividend** — a fixed payment per share held, paid once a year, with a different rate
for bull and bear years. Paid *after* splits, so a stalk that just split pays out on
the doubled share count.

**Static stalk** — a stalk whose price never moves. There is exactly one: *BERRY
BONDS FROM DIE HARD*, the game's risk-free bond. It cannot move, split, or go
bankrupt, and carries no special events. In code this is the `is_price_static` flag,
not a check on its name.

**Net worth** — cash on hand, plus the market value of holdings, minus any
outstanding loan. The score the game is won on.

**Long-game softening** — price swings are scaled down in longer matches so prices do
not run away: above 19 years and again above 49 years. Undocumented in the original's
public write-up but present in its code. See [game-rules.md §4.4](game-rules.md).

**Loan** — optional borrowing, available from Year 2 when enabled. Up to 25% of net
worth, minimum 100, 10 years at 6% compound, paid out as cash immediately. **One per
player for the entire game**, even after repayment. See
[game-rules.md §9](game-rules.md).

**Minimum payment** — the yearly amount due on a loan, calculated as
`principal / a(n, 6%)` and truncated to an integer. It is recalculated every year and
after every payment, which makes it drift by about ±1 — expected behaviour, not a
bug.

**Annuity factor** — written `a(n, i)`, the standard present-value figure that turns a
principal into a level yearly payment. For the 10-year term at 6% it is about
7.360087. Dividing a balance by it gives the payment that clears the balance over n
years.

**Re-amortisation** — recalculating the minimum payment from the current balance over
the years remaining. Happens after every payment and after every penalty. It is what
makes overpaying visibly reduce next year's minimum.

**Interest-only first year** — the year a loan is taken charges interest but counts no
missed payment, because the loan is created already flagged as paid. This implements
"your first payment is next year", and it is why a ten-year term runs to eleven
year-ends.

**Missed payment** — failing to pay the minimum during a year. First miss adds 10% to
the balance, second adds 15%, third is a **default**.

**Default** — a third missed payment. The player's cash, net worth and all holdings
are seized and they are bankrupt. Lands on the fourth year-end after borrowing, since
the first year is free.

**Yeehaw** — a purely social gesture. A player asks for one; any *other* player may
give it; all players then hear a "YeeHaw!" sound effect. No mechanical effect
whatsoever. Impossible in a one-player game, since you cannot give yourself one.

**Game settings** — the options chosen before a match: starting cash, number of
years, number of players, whether loans are enabled. The original called these "lobby
settings" because every match ran through a Steam lobby; renamed here because the
port must support true offline single-player.

---

## Code terms

**The simulation** / **the sim** — everything in `src/sim/`. The game's rules as plain
objects, with no nodes, no scene tree and no networking. The central architectural
rule is that this layer never depends on anything above it.

**Pure logic** — code that computes a result from its inputs without touching the
scene tree, the filesystem, the network, or global random state. All the economy rules
are written this way so they can be tested headlessly.

**The year pipeline** — the ten ordered steps that resolve one game year, implemented
in `YearResolver.advance_year()`. The order matters; see
[architecture.md §3](architecture.md) and [game-rules.md §4.1](game-rules.md).

**Price model** — a swappable strategy for how a price moves. The current one
(`RandomRangePriceModel`) is the faithful port; the interface exists so an
earnings-driven model can replace it later without touching the pipeline.

**Content** — the authored game data: the ten stalks and their ninety events, stored
as `.tres` resource files in `src/data/stalks/`. Distinct from code; a new stalk is
new content, not a new feature.

**Content library** — `ContentLibrary`, the only thing that reads the content
directory. It loads every stalk in a deterministic order, validates the whole set, and
builds a fresh market from it. Always returns a library; callers check `is_valid()`.

**Validator** — the checks `ContentLibrary` runs on load: duplicate ids, missing
fields, inverted ranges, events targeting the wrong stalk, events in the wrong mood
list, events on a static stalk. It exists because a typo in an event's target id would
otherwise produce an event that silently never fires.

**The bag** — how special events are drawn. Each mood has a shuffled bag that is drawn
from without replacement, refilled only once empty, so an event cannot repeat until
every other event in its pool has been seen.

**Year result** — an immutable record of everything one year advance did
(`YearResult`). Used four ways: the UI animates from it, the host broadcasts it,
tests assert on it, and the list of them is the match history.

**Match history** — the list of every `YearResult` so far, recorded from Year 0. Kept
because this information cannot be reconstructed later; it is what future charts and
year-over-year figures will read.

**Determinism** — the property that the same settings, the same seed and the same
player actions always produce an identical match. Enforced by using integers for all
money and taking all randomness from an injected generator. See
[architecture.md §8](architecture.md).

**Injected RNG** — a `RandomNumberGenerator` passed in as an argument rather than
created on the spot or taken from Godot's global functions. Non-negotiable: global
`randi()` would make the game untestable.

**Session** — the abstraction over "who is playing and who is allowed to do what", and
the only thing the UI talks to. `LocalSession` plays offline, `HostSession` is
authoritative over a networked match, and `ClientSession` joins one. A Node, because
the networked ones need to issue RPCs. See [architecture.md §5](architecture.md).

**Authority** — `MatchAuthority`, the single place a match is allowed to change. It
validates an action, applies it, and returns a rejection reason or an empty string.
Pure: no nodes, no signals, no peers. Both `LocalSession` and `HostSession` own one,
which is why offline and hosted play cannot resolve an action differently.

**Replica** — the partial copy of the match a client holds. It is overwritten from
the host's snapshots and never computed locally. "Partial" because this client's own
cash, holdings and loan are real while other players carry only their public figures.

**Snapshot** — one encoded, redacted copy of the match, built per recipient and sent
to one client. What keeps a replica current. See [architecture.md §5.3](architecture.md).

**Redaction** — leaving private figures out of a snapshot as it is encoded. A rival's
cash, holdings and loan schedule are never put on the wire at all, so there is
nothing private in the payload to leak.

**Slot** — a player position in a networked match. Slots are **created as players
arrive**, not declared up front, and the roster is whoever is present when the host
presses Start (decisions.md D48). A peer that drops before Start is forgotten; one
that drops afterwards leaves the active roster while its cash and holdings are
retained (D47).

**Lobby** — the waiting room between the menu and the board. Shows who is here and
who is ready; only the host gets a Start button. One screen serves both sides, since
the difference is entirely about what you are allowed to do.

**Pending yeehaw** — the one outstanding request for a yeehaw, held as match
state rather than fired and forgotten. It is what lets a single button read "Can I
Get a Yeehaw?" until somebody asks and "Give Yeehaw" afterwards. Cleared when the
year advances. See decisions.md D52.

**Kick** — the host removing a player from the lobby. Exists because Start waits
for everybody to be ready, so somebody who has wandered off would otherwise hold the
lobby shut; a person can tell the difference between slow and gone, and a rule
cannot. Lobby only. See decisions.md D49.

**Introduction** — the first thing a joining client sends: the name the player typed.
The host creates their slot when this arrives rather than when the socket connects,
so a player never appears under a placeholder name.

**Peer id** — the number Godot assigns each connected machine; the host is always 1.
The host maps peer ids to slots, and derives *who is acting* from the sender's peer
id rather than trusting anything in the packet.

**Pre-check** — a `why_not_*` call on the session that the UI uses to grey out or
red-flag a control *before* anything is sent. It runs the same validation function
the authority runs, so it can never disagree with enforcement. Presentation only: a
client is never a second source of truth.

**Palette** — `src/ui/palette.gd`, the single source of truth for colour. The shared
Theme is generated from it. Also holds the money and signed-change formatters, so
every figure on screen is written the same way.

**Theme type variation** — Godot's mechanism for naming a look (`Heading`, `Numeric`,
`Bull`, `Card`, `PrimaryButton`) that a control opts into. How this project styles
things without per-node colour overrides.

**Widget** — a small reusable UI scene under `src/ui/widgets/`: one board row, one
holdings row, one standings row, the loan panel. A widget displays what it is given
and emits intent outward; it knows nothing about the session or the screen holding it.

**Screen host** — `Main`, the node that holds exactly one screen at a time and moves
between the menu, the playing screen and the result screen. It owns the session, so a
finished match's state outlives the screen that displayed it. Screens emit intent and
know nothing about each other.

**Header mode** — a row widget configured by `configure_as_header()` to be the column
header above its own list. Sharing the scene is what guarantees the header's columns
cannot drift out of alignment with the rows'.

**Year summary** — the one-line digest under the special event reporting dividends,
splits, bankruptcies and loan interest. These all happen in the simulation and were
invisible until Phase 4, which made a doubled share count look like a bug.

**Host-authoritative** — the design where one machine owns the simulation and decides
every number. Clients request actions and receive results; they never compute
economics themselves.

**Yeehaw** — see the game term above. In code it is the first networked feature,
chosen because it needs a request, an authority check and a broadcast while being
incapable of corrupting the economy.

**Steam lobby** — Valve's matchmaking object: a small named room with metadata
and a member list, which other players can find or be invited to. It is not the
game's own lobby screen, though the two appear together: the Steam lobby is how
peers find each other, and the lobby screen is what they see once they have.

**Transport** — what physically carries network messages. Godot's
`ENetMultiplayerPeer` first, Steam's relay later. Deliberately separate from the
session layer so Steam is a swap rather than a rewrite.

---

## Godot terms worth knowing

**Node** — the basic building block of a Godot scene. Everything on screen is a node.

**Scene** (`.tscn`) — a saved tree of nodes. Godot scenes are plain text, which is why
they can be hand-written and reviewed in a diff.

**Resource** (`.tres`) — a saved data object. Used here for authored content: stalk
definitions and special events.

**Control node** — Godot's UI node type. This entire game is `Control` nodes; there is
no 2D sprite work and no 3D.

**Autoload** — a singleton registered in `project.godot` and available globally. Used
for services, never for game rules.

**Signal** — Godot's built-in event mechanism. A node emits a signal; listeners decide
what to do. The way this project avoids nodes reaching into each other.

**`@onready`** — an annotation that resolves a node reference once the scene is ready,
rather than repeatedly at runtime.

**GDScript** — Godot's own scripting language, used throughout this project.
Python-like syntax, optional static typing (mandatory here).

**GUT** — Godot Unit Test, the testing framework. Version 9.7.1, matched to Godot
4.7. See [testing.md](testing.md).

**`--headless`** — a command-line flag that runs Godot with no window. How the tests
run, and how a build server would run them.

**Shader** (`.gdshader`) — a small program the graphics card runs once for every
pixel it draws. This project has exactly one, the optional CRT effect.

**`CanvasLayer`** — a node that draws its children on a separate plane, above or
below everything else according to its `layer` number. It is not a `Control`, so no
container lays it out. Used here for the two overlays that must float over whatever
screen is showing: the CRT effect and the development panel.

**`SubViewport`** — a viewport inside the scene tree rather than the window. The
whole game is drawn into one, 640x360, so the finished picture is an ordinary
texture that an effect can read. See decisions.md D96.

**`SubViewportContainer`** — the control that shows a `SubViewport`. It does the
enlarging, and it transforms mouse coordinates into the viewport so nothing in
the game has to.

**Integer scaling** — enlarging the picture by a whole number only. At 2x every
source pixel is a 2x2 square; at 2.5x some would be three screen pixels wide and
some two, which makes a letter's strokes uneven.

**Letterboxing** — the black bars left when the picture cannot fill the window.
Here they appear whenever the window is not a whole multiple of 640x360.

## CRT terms

The optional CRT effect (decisions.md D94) borrows the vocabulary of the
cathode-ray tube televisions it imitates. None of these are Godot terms.

**CRT effect** — the whole thing: the tick box in Settings that draws the game as
though it were on an old television. Off unless a player asks for it.

**Scanline** — one horizontal sweep of the electron beam. On a real tube the lines
have gaps between them, which is the faint horizontal banding the effect draws.

**Barrel warp** — the gentle outward bulge of a tube's glass, which makes straight
lines near the edges bow. Here it is a distortion applied to where each pixel is
read from.

**Vignette** — the darkening towards the corners, where the frame shades the glass.

**Colour bleed** — colour running horizontally away from a bright edge, because the
beam cannot change intensity instantly. It trails to the right, the direction the
beam travels.

**Beam glow** — bright areas spreading into their surroundings, because the beam
grows wider as its drive voltage rises. Keyed off a brightness threshold, so dark
areas stay dark.

**Phosphor mask** — the grid of red, green and blue phosphor dots on the glass
itself. **This game does not draw one**; it needs monitor-pixel density and the game
renders at 640x360. D94 explains what it would cost.

## Screen

This project's word for a top-level scene that fills the window and is swapped
in and out by `Main`: the title screen, the online games list, the lobby, the
playing screen, the result screen. They live in `src/ui/screens/`.

Godot has no such concept. Its unit is a **scene** (a `.tscn` file), and a
reusable widget — a stalk row, a lobby row — is a scene as well. "Screen"
only means *this* scene owns the whole window, and exactly one of them exists
at a time.

The word was used throughout the code and these documents for weeks before it
was written down here, which is the sort of thing this glossary exists to
catch.
