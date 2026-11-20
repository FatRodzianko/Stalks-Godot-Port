# Architecture

How the port is structured, and why. Rules live in `game-rules.md`; the phased
schedule lives in `porting-plan.md`.

The driving constraint: **the economy must be a pure, deterministic, testable
simulation that knows nothing about nodes, networking, or Steam.** Everything else
follows from that.

---

## 1. Layers

```
┌─────────────────────────────────────────────────────────┐
│  src/ui/          Control nodes. Presentation + input.  │
│                   Reads state, emits intent. No rules.  │
├─────────────────────────────────────────────────────────┤
│  src/net/         Session + transport. Who is allowed   │
│                   to do what, and how it travels.       │
├─────────────────────────────────────────────────────────┤
│  src/sim/         Pure simulation. RefCounted only.     │
│                   No nodes. No RNG of its own. No I/O.  │
├─────────────────────────────────────────────────────────┤
│  src/data/        Resource definitions (.tres).         │
│                   Content, not behaviour.               │
└─────────────────────────────────────────────────────────┘
```

Dependencies point **downward only**. `sim` never references `net` or `ui`. `ui`
never computes a rule. If a change would make `sim` depend on a node, the change is
wrong — see `CLAUDE.md`.

Why this matters here specifically: this game *is* its RNG. If the economy can only
be exercised by clicking buttons in a window with two Steam clients running, it will
never be properly tested, and subtle rule bugs (the kind the original shipped with)
will survive the port.

---

## 2. Data layer — content as resources

Authored as `.tres`, one file per stalk and one per event pool. No hardcoded arrays.

```gdscript
class_name StalkDefinition extends Resource

@export var id: StringName                  # stable key — NEVER the display name
@export var display_name: String
@export var starting_price: int = 100
@export var bear_change: Vector2i           # min/max magnitude, applied negative
@export var bull_change: Vector2i
@export var bear_dividend: int
@export var bull_dividend: int
@export var is_price_static: bool = false   # BERRY BONDS: never moves
@export var industry: StringName = &""      # unused for now; see §7
```

```gdscript
class_name SpecialEventDefinition extends Resource

@export var id: StringName
@export var target_stalk_id: StringName
@export var mood: MarketMood.Value          # which pool it belongs to
@export var flavour_text: String
@export var price_change: int
```

Events are **bundled onto their stalk**, in `StalkDefinition.bull_events` and
`bear_events`, rather than living in separate pool files. So one `.tres` per stalk
holds the stalk and all ten of its events, and adding a stalk is a single-file change.
That matches the planned custom-stalk feature, where a submitted stalk carries its own
events (decisions.md D29).

### Loading and validating

```gdscript
class_name ContentLibrary extends RefCounted

static func load_from(dir_path := "res://src/data/stalks") -> ContentLibrary
func is_valid() -> bool
func validate() -> Array[String]
func build_stalk_states() -> Array[StalkState]
func build_event_pool() -> EventPool
```

`ContentLibrary` is the only thing that reads the content directory. It sorts by `id`
so load order is identical on every machine (determinism, §8), validates everything,
and hands back factories for a fresh market.

It **always returns a library** — callers check `is_valid()` — and collects *every*
problem rather than stopping at the first, so an author adding a stalk sees all their
mistakes in one run.

Validation is not ceremony. Ninety events reference ten stalks by id, and a single
typo in a target id produces an event that can never fire and reports nothing. The
original shipped with exactly that class of bug. See decisions.md D31.

Two deliberate choices:

**Identity is an `id`, not a display name.** The original matched stalks by comparing
display strings, which is why BERRY BONDS needed a hardcoded name check and why an
event could silently fail to find its target. An `id` makes renaming safe and makes
JSON-authored content possible.

**Behaviour comes from flags, not special cases.** `is_price_static` replaces
`stalkName != "BERRY BONDS FROM DIE HARD"`.

```gdscript
class_name GameSettings extends Resource

@export var starting_cash: int = 10000
@export var max_years: int = 10
@export var player_count: int = 1
@export var loans_enabled: bool = false
@export var rng_seed: int = 0               # 0 = pick one and record it
@export var bull_weight: int = 7            # 7/12 bull, 5/12 bear
@export var bear_weight: int = 5
```

---

## 3. Simulation layer — state and the year pipeline

State objects are plain `RefCounted`: no nodes, no signals to UI, no awaits.

```
GameState
 ├── settings: GameSettings
 ├── year: int
 ├── history: Array[YearResult]     # every year so far, from Year 0
 ├── stalks:  Array[StalkState]     # id, price, last_change, is_bankrupt, did_split
 └── players: Array[PlayerState]    # id, cash, holdings, loan, net_worth
                                    #   holdings: Dictionary[StringName, int]
                                    #   loan: LoanState or null
LoanState                           # balance, min_payment, years_remaining,
                                    #   missed_payments, paid_this_year,
                                    #   is_paid_off, is_defaulted
```

A note on `PlayerState.loan`: a non-null loan means the player **has ever borrowed**,
not that they currently owe money — a player may only take one loan per game, so the
object's presence is what blocks a second (decisions.md D27). Use
`PlayerState.owes()` for the amount outstanding, which is zero once the loan is paid
off or written off by a default.

### The year advance is one function

```gdscript
func advance_year(state: GameState, rng: RandomNumberGenerator) -> YearResult:
```

It runs the ten steps in `game-rules.md` §4.1 in order, mutates `state`, and returns
an **immutable record of everything that happened**:

```gdscript
class_name YearResult extends RefCounted

var year: int
var mood: MarketMood.Value
var event: SpecialEventDefinition          # may be null
var price_changes: Dictionary              # stalk id -> {before, base_delta,
                                           #   event_delta, after}
var splits: Array[StringName]
var bankruptcies: Array[StringName]
var dividends: Dictionary                  # player id -> amount
var loan_events: Array                     # penalties, interest, defaults
var net_worths: Dictionary                 # player id -> net worth
var rankings: Array[StringName]
```

`YearResult` is the keystone of the design. It serves four jobs at once:

1. **The UI animates from it** — it already knows what changed and in what order, so
   presentation never has to re-derive or guess.
2. **The network sends it** — the host resolves the year and broadcasts one result;
   clients never compute economics.
3. **Tests assert on it** — a year's entire outcome is one inspectable value.
4. **Charts and history read a list of them** — see §7.

### RNG is injected, never ambient

`advance_year` takes an `RandomNumberGenerator`. Nothing in `sim` ever calls global
`randi()`. The seed lives in `GameSettings` and is part of match state, so any game
can be replayed exactly — which is what makes an RNG-driven game testable at all.

---

## 4. The price model — the main extensibility seam

This is the single most important design decision for where the game is going.

Price movement is **a strategy, not a hardcoded formula**:

```gdscript
class_name PriceModel extends RefCounted

## Returns this year's base price delta for one stalk.
## `market` is the whole market, read-only, so a model may consider other stalks.
func next_change(
    stalk: StalkState,
    definition: StalkDefinition,
    mood: MarketMood.Value,
    market: GameState,
    rng: RandomNumberGenerator,
) -> int:
    push_error("abstract")
    return 0
```

Two implementations are planned:

| Implementation | When | What it does |
|---|---|---|
| `RandomRangePriceModel` | Now — the faithful port | Per-stalk random range by mood, 10% contrarian roll, long-game softening |
| `EarningsPriceModel` | "StalkleHeads" mode | Earnings reports, company profile stats, industry performance, momentum across years |

Because `next_change` receives the **whole market**, a future model can do things the
current one cannot — notably make *My Mutuals and Me Inc.* behave as a genuine index
of the other stalks, which is on the wishlist.

Getting this interface in on day one costs almost nothing. Retrofitting it after the
rules are threaded through the UI and the network layer would be a rewrite.

---

## 5. Network layer — session abstraction

The game must run **truly single-player with no Steam and no peer**, which the
original could not do. So "who is playing" and "how messages travel" are separate
from both the rules and each other.

```gdscript
class_name GameSession extends Node          # interface

signal year_resolved(result: YearResult)
signal player_changed(player_id: StringName)
signal action_rejected(player_id: StringName, reason: String)
signal ready_state_changed(player_id: StringName, is_ready: bool)
signal game_over(winners: Array[StringName])

func state() -> GameState                    # read to render; never write
func local_player_id() -> StringName
func controls(player_id: StringName) -> bool

func request_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void
func request_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void
func request_loan(player_id: StringName, amount: int) -> void
func pay_loan(player_id: StringName, amount: int) -> void
func set_ready(player_id: StringName, is_ready: bool) -> void
func request_yeehaw(player_id: StringName) -> void
func give_yeehaw(giver_id: StringName, receiver_id: StringName) -> void

# Pre-checks for live UI feedback. Presentation only — see §5.1.
func why_not_buy(player_id: StringName, stalk_id: StringName, shares: int) -> String
func why_not_sell(player_id: StringName, stalk_id: StringName, shares: int) -> String
func why_not_loan(player_id: StringName, amount: int) -> String
func why_not_request_yeehaw(player_id: StringName) -> String
func why_not_give_yeehaw(giver_id: StringName, receiver_id: StringName) -> String
func max_affordable(player_id: StringName, stalk_id: StringName) -> int
```

It is a **Node**, not a `RefCounted`: the later `HostSession` and `ClientSession` need
to issue `@rpc` calls, which requires being in the scene tree. Making the base class a
Node now means the UI's contract does not change when multiplayer arrives
(decisions.md D32). `src/sim` remains node-free; this is the layer above, where nodes
are allowed.

```
GameSession              interface; a Node, so the two networked sides can use @rpc
├── LocalSession         offline; owns a MatchAuthority, no MultiplayerAPI at all
└── NetworkedSession     declares every @rpc, for both sides, in one script
    ├── HostSession      owns a MatchAuthority; validates, applies, broadcasts
    └── ClientSession    holds a replica; asks, and computes nothing
```

| Implementation | Role |
|---|---|
| `LocalSession` | Single player. Owns a `MatchAuthority` and turns its answers into signals. |
| `HostSession` | The same `MatchAuthority`, plus peer-to-player mapping and broadcast. |
| `ClientSession` | Sends requests, applies snapshots. Holds no authority object at all. |

The roster is built from arrivals rather than declared in advance: a host opens a
lobby as the only player, each joiner is seated when it introduces itself with
its chosen name, and the roster is fixed when the host presses Start. Declaring
the size up front left unclaimed slots that the ready gate waited on forever
(D48). One consequence worth knowing: **only one `Main` can hold a peer per
process**, because `Main` uses the tree's single default `MultiplayerAPI` — two
instances in one process overwrite each other's peer.

### The rules are not in the session

`MatchAuthority` (`src/sim`, a `RefCounted`) is the single place a match may change.
It validates an action, applies it, and returns a rejection reason or an empty
string. It emits nothing and knows nothing about peers.

Both `LocalSession` and `HostSession` own one. That is what makes "hosted and
offline play cannot diverge" a structural fact rather than a promise: there is one
implementation of what happens when somebody buys, and both sessions call it.

The sessions are left with one job each — turning answers into signals, and (on
the host) putting them on the wire. This also restores the rule from `CLAUDE.md`
that the economy must not depend on the scene tree: before the extraction, the
validate-and-apply logic lived in `LocalSession`, which is a Node. See D43.

### The authority line

**A client-to-host RPC carries no player id.** Who is acting is derived from
`multiplayer.get_remote_sender_id()`, which a client cannot forge. So a client has
no way to even *express* "act as somebody else" — the attack is removed rather
than validated against. See D45.

On top of that, every `any_peer` entry point re-validates through
`MatchAuthority`: sufficient cash, loan eligibility, correct phase. The original
validated on the server too; the port keeps that and makes it structural.

### 5.1 Responsiveness without prediction

This game does not depend on reaction time. The only requirement is that clicking
**Buy** or **Sell** never feels like the game ignored you. That is a UI-feedback
problem, not a netcode problem, and it does **not** need client-side prediction,
optimistic state mutation, or reconciliation.

The host stays the only source of truth for every number. What the client does
locally is cheap and does not touch state:

1. **Acknowledge the input immediately** — the button reacts, a click sound plays,
   and the control enters a brief in-flight state. This is what makes it feel
   responsive, and it costs nothing.
2. **Pre-check obviously invalid actions locally** and reject them on the spot: a
   purchase the player cannot afford shows red feedback at once and **is never
   sent**. No round trip, no waiting, and no state was changed.
3. **Send valid requests** to the host, which validates authoritatively and
   broadcasts the resulting state.
4. **Apply the host's numbers when they arrive.** Over LAN or Steam relay that is
   tens of milliseconds for a turn-based game — imperceptible once the click itself
   has already been acknowledged.

Deliberately **not** doing optimistic mutation buys a lot: no divergence between
predicted and authoritative state, no rollback path, no reconciliation code, and no
class of bug where a client briefly believes it owns shares it does not. The cost
would only be worth paying in a game with real latency pressure, and this is not one.

The local pre-check in step 2 is a **presentation** concern, not a second authority.
It reuses the same validation function from `src/sim` that the host calls for
enforcement, so the two can never disagree about what is legal — one implementation,
called from two places. That reuse is a direct payoff of keeping rules out of the
node layer.

`LocalSession` needs none of this: it is already authoritative in-process, so
single-player is instant by construction.

### 5.2 Testing two peers in one process

Verified by spike before any of Phase 5 was built, because the whole testing
approach depended on it: **a host and a client can run in a single headless
process and exchange RPCs both ways.** Networked behaviour is therefore testable
in the normal suite, with no second process and no manual two-window dance.

Three things make it work, and all three are easy to get wrong:

1. **Each side needs its own subtree and its own `MultiplayerAPI`**, registered
   with `SceneTree.set_multiplayer(api, subtree_path)`. The nodes must already be
   in the tree when that is called — doing it from `_initialize()` fails with
   "Cannot get path of node as it is not in a scene tree".
2. **The session node's path must be identical on both sides.** Godot resolves an
   RPC by node path, so a host node at `HostWorld/Session` can only reach a client
   node at `ClientWorld/Session` — the part below the subtree root has to match.
   This is why the session node is named consistently rather than after its class.
3. **A non-default `MultiplayerAPI` must be polled by hand.** In a real game there
   is one API and Godot polls it; a test harness holding two must call `poll()` on
   each itself.

### 5.3 What a client is told

**Revised 2026-11-18 (D105): everything.** The host sends every client a
complete snapshot of the match - every player's cash, share counts and loan
schedule, not only their own. This section described a partial replica until
that date; the history is in D103 and D105.

A client therefore holds a **full replica**. `StateSync.encode_state` takes no
recipient, and the host builds one snapshot and sends the same one to everybody.

| | Sent |
|---|---|
| Cash | yes |
| Holdings, with amounts | yes |
| Loan balance, schedule, missed payments | yes |
| Net worth | yes |
| Display name, ready flag, bankruptcy, Steam ID | yes |
| How far the match's random stream has run | yes |

**Two reasons, and the second is the one that decided it.** There was never
much worth protecting - the board already publishes net worth, which is the
figure players watch, and nobody plays a game of bets on a random number
generator differently for knowing a rival's cash. And **host migration needs
it**: when the host leaves, one of the remaining players continues the match
from the copy they already hold (§5.5), and a redacted copy is not a match.

**This is about visibility, not authority.** The host owns every rule. A client
sends requests - "buy 5 of X" - and the host validates them against its own
state and applies them; no client writes anybody's position, its own included.
That line did not move, and it is the one the owner cared about: secrecy is not
important in this game, integrity is.

Consequences worth knowing:

- `apply_player` **overwrites** the recipient's values. A snapshot is complete,
  so there is no "was this field withheld" case to reason about, and the
  tiptoeing the old partial entries required is gone.
- A client can answer any question about any player locally, which is what the
  Investors panel reads (`PlayerState.invests_in`).
- The rules are asserted in `tests/unit/test_state_sync.gd` and, end to end
  over a real connection, in `tests/unit/test_networked_session.gd`.

### 5.5 When the host leaves

A Steam lobby outlives its owner, and Steam hands ownership to another member
by itself (D68, D104). So migration is not an election: every client asks Steam
who owns the lobby now and acts on the answer.

- `LobbyMigration` (src/net/lobby_migration.gd) is that decision with no Steam
  in it - `WAITING`, `BECOME_HOST`, `JOIN_NEW_HOST`, `GAVE_UP` - and is the
  part that can be tested without two Steam accounts.
- `Main` polls Steam every half second, holds on to the match while it waits,
  and ignores the dying session's own `connection_ended` meanwhile.
- The new owner calls `HostSession.take_over`, which wraps its own `GameState`
  in a `MatchAuthority`, adopts the random stream's position and closes the
  lobby. In a lobby that had not started, it re-hosts instead: there is no
  position to preserve.
- Everybody else reconnects and **reclaims their own slot**, matched by Steam
  ID. Their `PlayerState` was never removed from the match at all - they are
  marked away and keep being paid while they reconnect (§5.6, D110).

**The lobby itself has to be told what it now is** (D106). Steam offers two
separate switches and this game uses them separately: the `state` key decides
whether the browser *lists* a lobby, and `setLobbyJoinable` decides whether
anybody can get in at all.

| | Listed | Joinable |
|---|---|---|
| Lobby, waiting to start | yes | yes |
| Match under way | no | yes |
| Host left, nobody else there | no | no |

A match under way stays joinable because the host is the gatekeeper, not Steam:
an arrival is matched against the roster by Steam ID and either reclaims a seat
or is turned away with a reason. That is also the only way back for a player
whose connection dropped, and REJOIN GAME (§5.7) is built on it. And a host
leaving is two different events - the last player out is a lobby dying, and is
shut down; a host leaving others behind is a lobby changing hands, and is left
alone.

What cannot be verified here: all of the Steam plumbing. See
docs/manual-testing.md.

### 5.6 A player who is away is still in the match

`PlayerState.is_away` is the whole of it: one flag, set when a peer drops and
cleared when they come back.

An away player stays in `state.players`, which is the list `YearResolver`
walks, so the year pays them their dividends, splits and bankrupts their stalks,
charges their loan and ranks them. The **only** thing the flag changes is
`GameState.all_players_ready()`, which skips them, so one dropout cannot hold
the year for everybody else. `players_present()` is the list every "is
everybody done?" question asks, and `all_players_ready()` is false when nobody
is present, so a deserted match does not play itself out.

This replaced taking the player out of `state.players` altogether (D47), which
fixed the same deadlock by removing them from the economy. Two consequences
worth knowing:

- **`HostSession` has one roster, not two.** It used to keep `_roster` (every
  slot) alongside `state.players` (that list minus the dropouts), rebuilt on
  every arrival and departure. The difference between them was this flag.
  `roster()` now returns `state.players`.
- **`state.players` is not ordered by anything meaningful about roles.** The
  host who walked out is still first in it. Read `hosted_by` (D109).

The flag travels in the snapshot, so a client can mark who is absent - the
rankings show `(away)` and grey the ready dot - and so that a client promoted to
host inherits it. See D110 and docs/game-rules.md §4.6.

### 5.7 Getting back into a match you dropped out of

REJOIN GAME on the title screen. The mechanism is a lobby id written down, and
nothing else:

- `Main._show_gameplay` writes the current Steam lobby to
  `user://last_match.cfg` (`src/data/last_match.gd`). Every route onto the
  board passes through there, so hosting, joining, both halves of a migration
  and a rejoin are all covered by one call. `Main._on_match_finished` deletes
  it.
- `show_menu` hides the button and asks Steam whether that lobby is still a
  game: `request_lobby_details` wraps `requestLobbyData`, which answers for a
  lobby this process is **not** in. The button appears only on a good answer,
  the question is re-asked every five seconds while the menu is up, and a
  definite no throws the record away. Steam not answering is not a no — the
  button stays off and the record stays put (D115).
- Pressing it calls the existing `join_online_game`, then `_rejoin_the_match`,
  which joins as a client **without swapping the screen** - the same treatment
  a migration's reconnect attempts get, because a half-built session would
  otherwise put an empty market on screen. `_on_rejoin_landed` shows the board
  when the welcome arrives.
- The host decides whether they get their seat. `why_not_rejoin` is that rule,
  pure and testable: having a seat is checked first and lets the player in even
  when the match has finished, and a Steam ID that is not on the roster gets one
  of two sentences depending on whether that match is running or over. A
  returning seat-holder whose match ended lands on the result screen, which is
  what D122 amended D111 to allow.

A record is **not** deleted when a rejoin fails or when Steam is silent, so a
bad minute on the relay does not destroy the only route back. It *is* deleted
when the answer is definite: the lobby is gone, or its `state` key reads
`over`, which the host writes when the match finishes so that a player who was
away can learn it ended. See D111 and D115.

The lobby's `state` key now carries three values, and the table in §5.5 gains a
row:

| | Listed | Joinable | Offered as a rejoin |
|---|---|---|---|
| Lobby, waiting to start (`open`) | yes | yes | no record yet |
| Match under way (`playing`) | no | yes | **yes** |
| Match finished (`over`) | no | yes | no |
| Host left, nobody else there | no | no | no, the lobby is gone |

### 5.4 Transport is a choice, not a migration

A `Transport` answers one question: how is this match carried? It hands back a
`MultiplayerPeer` and nothing above it knows which kind.

```
Transport                 abstract
├── EnetTransport         direct IP; what the tests run on
└── SteamTransport        Steam's relay, via a lobby
```

`HostSession.host()` and `ClientSession.join()` take one and never build one.
Each transport is constructed with what *it* needs — a port for ENet, a lobby for
Steam — because the two disagree about what "where" even means, so `open_server`
and `open_client` take no arguments. Even the lobby screen stays ignorant: it
asks for a `joining_hint()` and prints it, rather than branching on whether to
show a port or an invite. See decisions.md D56 and
[steam-integration.md](steam-integration.md).

Steam needed one thing the interface does not provide: creating or joining a
lobby is asynchronous. Rather than make every transport asynchronous for one
implementation, the waiting lives in `SteamService` and the lobby browser — a
UI flow, where a human is already waiting — and `SteamTransport` is built only
once a lobby exists. Turning a lobby into a peer is immediate. See D59.

### Transport is separate again

`HostSession`/`ClientSession` talk through Godot's `MultiplayerAPI`. What carries it
is swappable:

- **Now:** `ENetMultiplayerPeer` — works offline, two windows on one machine, no
  Steam, no accounts, fully scriptable in tests.
- **Later:** GodotSteam's `SteamMultiplayerPeer` — lobbies, invites, relay.

Because Godot's high-level multiplayer sits on top of a `MultiplayerPeer`, Steam is a
transport swap plus a lobby UI, not a rewrite of game code. That is the whole reason
Steam is deferred to a late phase.

---

## 6. UI layer

All `Control` nodes, laid out with containers — never hardcoded pixel positions.

### The screen host

`Main` (`src/ui/screens/main/`) holds exactly one screen at a time and moves between
them: menu → play → result → menu or play again. It also **owns the session**, so a
finished match's state outlives the screen that displayed it long enough for the
result screen to read it.

This exists so screens stay ignorant of each other. The menu emits
`start_requested(settings)`; the playing screen emits `match_finished(winners)`; the
result screen emits `play_again_requested` or `menu_requested`. None of them knows
what comes next.

**A screen that can lose its connection emits `connection_ended(reason)`**, and
`Main` turns that into a return to the title screen carrying the reason. The
lobby and the playing screen both do. This is a separate signal from
`match_finished` because the two mean opposite things — one is a game that
reached its end, the other is a game that stopped — and only one of them has a
result worth showing. See decisions.md D61 for how the playing screen came to be
the one screen that had not connected it.

**After a handover, the screen is derived from the match, not from the screen
before it.** `_show_the_screen_for(state, match_is_on)` is the single place that
decides, and it is a three-way: a match that is over shows the result screen, a
match the host has said is on shows the board, anything else shows the lobby.
Both halves of a migration end there, and neither consults what the player was
looking at a moment ago — the new host serves whatever *it* holds, which need
not be the same thing.

`match_is_on` is `ClientSession.match_is_on()`, the host's own statement that
the lobby is closed (D116), remembered rather than only re-emitted. The state
cannot stand in for it: year 0 is a real year, so a lobby and a match that has
just begun look identical. The third branch cannot be reached by playing today
and is written out regardless — see decisions.md D122 for why, and for the fault
a two-way answer caused.

**Anything `Main` owns on a screen's behalf is put away when that screen goes.**
The pause menu and both confirmation prompts are children of `Main`, not of the
screen that asked, so `_swap` closes all three. A screen no longer changes only
because the player pressed something — a host walking out changes it too — so a
question left open would otherwise sit over the next screen with its yes still
wired to the last one (D123).

**A rematch is the host reopening the lobby.** On a finished match the host can
call `offer_rematch`, which rebuilds the authority from the same settings with a
cleared seed, reopens the lobby, clears and re-seats the peer maps, and tells
every client. A client that takes up the offer is seated by the ordinary
`_seat_new_player` — with the name and Steam ID it played the finished match
under, captured before the reset — and welcomed, then told by `_rpc_rematch_joined`
that it is in a lobby rather than a match. From the host pressing Play onwards
nothing is new: it is `_on_play_requested` and the path every match takes.

Both the result screen and the final board show where a rematch stands, and the
sentence is `RematchNotice` (`src/ui/rematch_notice.gd`) rather than either
screen's own: a player can be reading the standings or looking the market over,
and the news is the same.

The roster is built from arrivals rather than inherited, so a player who never
answers is not in the next match and nothing waits on them (D48). Who wants a
rematch is therefore never shared state — the asks are host-local and advisory,
and the lobby itself is what shows who is coming. See decisions.md D124.

**`Main` also owns Escape.** Backing out means going to whatever is behind the
current screen, and only the screen host knows what that is. Overlays inside a
screen — the loan panel, the confirmation — take Escape first, because Godot
delivers unhandled input from the deepest node upwards. See decisions.md D64.

**A panel the player can change the contents of has its size decided up
front.** The result card holds both its tabs in one fixed-height wrapper, the
lobby reserves ten rows, and a label that wraps reserves its full height through
`ReservedLines` (`src/ui/reserved_lines.gd`) rather than growing a line at a
time. Sizing to content is Godot's default and it makes panels jump while
somebody is reading them; `tests/unit/test_panel_sizes.gd` holds the rule. See
decisions.md D125.

**Every screen's root is a container**, not an anchored `Control` — see
decisions.md D35. The first version anchored a Control and produced dead space at the
top and bottom of the window.

- **Screens** in `src/ui/screens/<name>/`, scene and script together. A
  *screen* is this project's word, not Godot's: a top-level scene that fills
  the window and is swapped in and out by `Main`. Godot's own unit is a
  *scene*, and a widget is a scene too — the distinction is what owns the
  whole window. See the glossary.
- The screens are: the **title screen** (`main_menu`), which is Create Game
  and Join Game; the **online games** list reached from Join Game; the
  **lobby**; the **playing screen**; and the **result screen**. Every match
  setting lives on Create Game, whatever kind of game it turns into — see
  decisions.md D65.
- **Widgets** in `src/ui/widgets/` — one reusable scene per repeated row (stalk
  board row, holdings row, ranking row, lobby member). Instantiated into containers,
  never duplicated by hand.
- A widget **emits intent outward** (`buy_requested(stalk_id, shares)`) and knows
  nothing about the screen holding it, or about the session.
- A screen translates widget signals into `GameSession` calls, and `YearResult` into
  display updates.
- All colours, fonts and styleboxes come from **one shared `Theme`** in
  `assets/themes/`, applied once at the screen root and inherited. Components pick a
  look with `theme_type_variation` (`Heading`, `Numeric`, `Bull`, `Bear`, `Card`,
  `PrimaryButton`, …) rather than setting their own colours.
- `Palette` (`src/ui/palette.gd`) holds the colour constants and the Theme is
  generated from them, so the two cannot drift. Scripts use `Palette` directly only
  for genuinely **dynamic** colour — a price change is green or red depending on its
  sign, which no stylebox can express. That is not the same thing as a per-node
  override in a scene file, which stays banned.
- Currency and signed-change formatting live in `Palette.format_money()` and
  `format_change()`, so every figure on screen is written the same way.

### The splash is a screen like any other

`SplashScreen` is swapped in by `Main` exactly as the menu or the board is, and
emits `finished` when it is over. It knows nothing about what comes next, so
the question of whether the game was launched into a lobby, into a development
flag or into the menu stays where it already lived - `Main._open_first_screen`
answers it either immediately or when the logo is done.

What it is launched to do is read once, in `_ready`, and held in
`_pending_invite` and `_pending_launch` while the logo plays. Reading the
command line again afterwards would work too, and would be a second place for
the answer to come from.

### Widgets shared between screens

Three things are shown in more than one place and are therefore widgets rather
than parts of a screen:

- **`SettingsPanel`** — sound, resolution, fullscreen. The title screen's
  Settings tab and the in-match `PauseMenu` both instantiate it, as the
  original reused one settings panel in both places. Its `preview_volume`
  export is the only difference between them: the pause menu turns the volume
  audition off, because a bull-market clip arriving mid-match in a bear year,
  heard by one player, is worse than silence.
- **`LobbyBrowser`** — the list of online games, inside the title screen's Join
  Game panel. It was a screen of its own until 2026-11-16 (D86).
- **`ConfirmPanel`** — any yes/no question, including the display revert
  countdown.

A widget knows nothing about the screen holding it: each emits what was asked
for and the owner decides. `SettingsPanel` is the one exception, and knowingly
so — it applies and saves its own settings, because nothing above it should
have to know that volume goes to a bus and resolution goes to a window.

### Display settings are split the same way as everything else

The resolution a player picks is handled by two pieces that do not know about
each other, for the same reason the economy is kept out of the scene tree.

- **`DisplaySettings`** (`src/data/`) is arithmetic. Hand it a monitor size as
  a `Vector2i` and it answers with the list of resolutions worth offering, the
  one a first run should get, and how much bigger a chosen one is than the
  640x360 layout grid. It never touches a window, so the whole list is testable
  for monitors nobody owns.
- **`DisplayMode`** (`src/ui/`) is the only place in the project that sets a
  window size or asks `DisplayServer` anything. It resolves a request through
  `DisplaySettings` and puts the answer on a real `Window` — and does nothing
  at all under the headless driver, which is what keeps the test suite from
  resizing the runner.

`Main` applies the stored settings before the first screen is shown; the title
screen's Settings tab changes them.

**What the resolution setting actually does is pick the size of the window.**
The game is always drawn at 640x360 and `Stage` enlarges it by a whole number,
so every rung of the ladder fills its window exactly. In fullscreen the
monitor's own size is the window, so the setting does nothing there and the
panel greys it out rather than letting a player change a number and watch
nothing happen. See decisions.md D96, and D85 for the arrangement it replaced.

### The game is drawn into a viewport, and the window shows that picture

`Stage` (`src/ui/stage.gd`) is the root scene and the only thing that knows how
big the monitor is. It holds a `SubViewport` of exactly 640x360 with `Main`
inside it, and shows that picture through a `SubViewportContainer` enlarged by
the largest whole number that fits the window, centred, with black around the
rest.

```
Stage                        the window
 ├─ Bars                     black, behind everything
 ├─ Screen                   SubViewportContainer, enlarges by a whole number
 │   └─ GameViewport         SubViewport, always 640x360
 │       └─ Main             the screen host, and every screen under it
 └─ CrtOverlay               hangs the effect's material on Screen
```

**Nothing below `Stage` knows it exists.** `Main` and every screen lay
themselves out on the 640x360 grid exactly as they always did; being in a
viewport rather than in the window is invisible to them. That is why this
change touched no screen, no widget, no theme and no layout file.

Three properties carry the whole design, and each is asserted in
`test_stage.gd` because getting one wrong is invisible until a player finds it:

- **`stretch` on the container.** It is what makes the container do the
  enlargement, and it is also what makes Godot transform mouse coordinates into
  the viewport for us. Without it the game would need its own pointer maths.
- **`gui_embed_subwindows` on the viewport.** Dropdowns and tooltips are
  `Window`s, not `Control`s. Without this they are drawn in the window around
  the picture instead of in it.
- **Nearest filtering on the container.** The game is pixel art and the
  enlargement is a whole number, so there is nothing to interpolate. That is
  the path with the CRT effect **off**; with it on, the shader does its own
  sampling, because a bent picture does need interpolating and neither nearest
  nor plain linear is right for it. See decisions.md D96.

**Godot's own `stretch` settings are off**, and must stay off. A stretch
happens after everything is drawn, where nothing can reach it — which is both
why the CRT effect could not run at the monitor's resolution and why the
resolution setting did nothing for weeks. See decisions.md D96, and D85 for
the fault that preceded it.

**The cost is black bars on windows that are not a whole multiple of 640x360.**
It is the width that decides, so 1280, 1920, 2560 and 3840 are all exact; a
1366-wide laptop gets a border. The resolution ladder was trimmed to match.

### The CRT effect is a material on that picture, not a layer over the game

The optional CRT look (decisions.md D94) is a `ShaderMaterial` on `Screen`, the
control that draws the game's picture. `CrtOverlay` is a bare `Node` whose only
job is to put that material on and take it off.

Nothing else in the game knows it exists. No screen, no widget and no
simulation code mentions it; `Stage` builds it at startup and switches it to
whatever was saved.

- **It covers the picture, not the window.** That is the whole reason it is a
  material rather than a rectangle in front of everything. It used to read the
  screen, which was the same thing while the game filled the window — once the
  picture could be letterboxed, the tube's edge and its vignette would have
  been out in the black bars.
- **A material cannot swallow a click.** The previous version was a full-screen
  rectangle that had to be told not to take mouse input, and getting that wrong
  eats every press in the game including the one that turns the effect off.
- **The settings panel reaches it through a group, not a signal chain.** The
  panel appears in two places and is several nodes deep in both; bubbling a
  signal to the root from each would mean two new signals and two new handlers
  in scenes with no other reason to know. Volume goes to the `Audio` autoload
  and resolution goes to `DisplayMode`; `CrtOverlay.apply(tree, on)` is the
  same idea, reached by group so nothing has to know where in the tree it was
  put.

**The shader runs at the monitor's resolution**, because that is what the
control it sits on is drawn at, while the picture it reads stays 640x360. Every
distance in it is therefore expressed in *source* pixels and stepped in
`TEXTURE_PIXEL_SIZE`, so the effect is the same size on a 720p window and a 4K
one with nothing to rescale.

**The development overlay is inside the picture**, not above the effect. With
the effect on it is warped and scanlined like everything else. It is a
debug-only panel in a debug-only build and a second viewport to keep it crisp
was not worth it.

### A Godot gotcha worth knowing

`queue_free()` is **deferred to the end of the frame**. Emptying a container with it
alone leaves the freed nodes as children for the rest of the current call, so
anything that then counts or searches that container sees rows which are logically
gone — a sold-out position stayed visible on the holdings board because of exactly
this. Remove from the tree first, then free:

```gdscript
for child: Node in container.get_children():
    container.remove_child(child)
    child.queue_free()
```

This was caught by a scene test asserting the board after a sale, not by reading the
code.

### A second one: scroll containers and column alignment

A list's column header has to sit **outside** its `ScrollContainer` to stay put while
the list scrolls — which also means it is not narrowed by the scrollbar the list
reserves. The result is a header that lines up only when no scrollbar is showing.

Two things fix it together: both scrolls show their vertical bar permanently
(`vertical_scroll_mode = 2`), and each header is inset on the right by exactly that
bar's width, read from `scroll.get_v_scroll_bar()` at runtime rather than guessed.

Related, and the reason this was worth solving properly: a hand-built header will
drift out of alignment with its rows the moment a column changes. The headers here
*are* the row widgets in header mode, so the columns are literally the same columns.
See decisions.md D36.

**Diagnose layout by measuring it, not by reading it.** Both of these were found by
a throwaway script that instantiated the screen headlessly, forced a size, and printed
every node's computed rect at 1024×600, 1280×720 and 1920×1080. That turned "the
layout looks wrong" into "the name column has 199px and needs 289px" in one run.

---

## 7. Designed for where the game is going

The future ideas were read before fixing this structure. Four of them changed
decisions that would be expensive to retrofit; the rest already fit.

| Future feature | Plugs into | Decision taken **now** |
|---|---|---|
| StalkleHeads earnings model | New `PriceModel` | **`PriceModel` interface exists from day one** |
| Mutual fund as a real index | `PriceModel` | **`next_change` receives the whole market, not just one stalk** |
| Charts, YoY, P/E history | `YearResult` list | **Year history recorded from Year 0** — cheap now, impossible to backfill |
| Custom stalks from JSON | `StalkDefinition` | **`id`-based identity, no engine-only types in definitions** |
| Industries, sector performance | `StalkDefinition.industry` + year context | Field added now, unused; sector modifiers slot into the price model |
| Momentum / earnings building over years | Price model reading history | History is available, so a model can be stateful across years |
| Industry news hinting at events | Event pool selection | Events are data with a pluggable pool selector, not a hardcoded list |
| Meme stalk / short squeeze | A price model + event type | Both are already data-driven seams |

**Year history** deserves emphasis. Keeping `Array[YearResult]` from the first year
costs one append per year and makes charts, year-over-year figures, replays and
determinism checks all possible later. Not recording it would make every one of those
features a retrofit.

---

## 8. Determinism contract

Non-negotiable, and the thing most worth protecting:

1. All money is `int`. Never `float` for cash, prices, dividends, or balances.
2. All randomness comes from an injected `RandomNumberGenerator`.
3. Given the same `GameSettings` (seed included), the same sequence of player
   actions must produce an identical sequence of `YearResult`s.
4. Integer rounding is specified, not incidental — splits round **up**, the loan
   minimum payment **truncates**. Both are tested.
5. Range endpoints are **inclusive**, a deliberate divergence from the original's
   max-exclusive C# behaviour. See `game-rules.md` §4.5.
