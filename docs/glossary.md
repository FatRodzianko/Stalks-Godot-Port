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

**Session** — the planned abstraction over "who is playing and how messages travel".
`LocalSession` for offline single-player, `HostSession`/`ClientSession` for
multiplayer. Not built yet; see [architecture.md §5](architecture.md).

**Host-authoritative** — the design where one machine owns the simulation and decides
every number. Clients request actions and receive results; they never compute
economics themselves.

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
