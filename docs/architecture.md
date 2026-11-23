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
 ├── market:  EarningsMarket        # StalkleHeads only; null in the base game (§9)
 └── players: Array[PlayerState]    # id, cash, holdings, loan, net_worth
                                    #   holdings: Dictionary[StringName, int]
                                    #   loan: LoanState or null
LoanState                           # balance, min_payment, years_remaining,
                                    #   missed_payments, paid_this_year,
                                    #   is_paid_off, is_defaulted
```

A note on `PlayerState.loan`: a non-null loan means the player **has ever borrowed**,
not that they currently owe money — in the base game a player may only take one loan
per game, so the object's presence is what blocks a second (decisions.md D27). With
`GameSettings.multiple_loans_enabled` on (StalkleHeads, D159), a *settled* loan no
longer blocks a new one, which replaces it; it is still one loan at a time. Use
`PlayerState.owes()` for the amount outstanding, which is zero once the loan is paid
off or written off by a default.

### The year advance is one function

```gdscript
func advance_year(state: GameState, rng: RandomNumberGenerator) -> YearResult:
```

It runs the ten steps in `game-rules.md` §4.1 in order, mutates `state`, and returns
an **immutable record of everything that happened**. Steps 8-10 (loans, net worth and
standings, game end) and closing the year (ready flags, history) are not in
`YearResolver` itself: they are `YearSettlement.settle`, a stateless class both year
pipelines end with (decisions.md D152, and §9 below for the second pipeline):

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
| In StalkleHeads: the market's state - companies, industries, the desk's books, the flow input, the event bags (§9, D176, D177) | yes |

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

### 5.8 Private messages: a relay beside the game

Players can message each other privately, talk to everybody in the ALL PLAYERS
room, block a player, and write themselves notes (decisions.md D192, D193, D195,
D196). None of it is part of the match: no `GameState`, no RNG, no snapshot.

```
ChatPanel (Label lines)  --message_submitted-->  MessagesTab --> MarketTabs
  --> GameplayScreen._on_message_submitted --> session.send_message(to, text)

GameSession.send_message      clean, check, own rate limit (5 / 10 s),
                              record in this machine's MessageBook,
                              then _deliver_message:
  LocalSession                nowhere (a note never gets this far)
  ClientSession               _rpc_send_message.rpc_id(host, to, text)
  HostSession                 _route_message(host player, to, text)

HostSession._on_message_sent  sender from the peer id; why_not_relay;
                              clean again; relay limit (8 / 10 s per sender);
                              _route_message: host's own book, or
                              _rpc_message.rpc_id(recipient's peer) - one peer;
                              to ALL_PLAYERS, _route_to_room: one rpc_id per
                              present peer but the sender's, in_room = true
ClientSession._on_message_pushed   sender must be in the match and not itself;
                              MessageBook.record_received drops a blocked
                              sender, cleans a third time, and files the line
                              under the sender or under ALL_PLAYERS
```

**The files**, all in `src/net/` except the screen's: `message_rules.gd`
(`MessageRules`: `clean`, `why_not_relay`, the limits), `message_limiter.gd`
(`MessageLimiter`, a sliding window with the clock passed in), `message_book.gd`
(`MessageBook`, conversations, unread counts and blocks; `changed` fires when a
line is added or a block changes). The screen: `src/ui/screens/stalkleheads/messages_tab.gd`,
`src/ui/widgets/chat_panel.gd` and `src/ui/status_dot.gd`.

**The book lives on the session**, because the session is what receives. The
screen listens to `messages().changed` and redraws the tab and its dot. A session
replaced by a host migration is handed the old one's book
(`GameSession.adopt_messages`, from `Main`, D197); one replaced by a rejoin starts
an empty book: a known limit.

**What was considered, and how each is handled:**

| Threat | Handling | Tested in |
|---|---|---|
| BBCode or other markup injection | Lines are plain `Label`s, which parse nothing; markup is drawn as text | `test_messages.gd`: `test_every_line_is_a_plain_label`, `test_no_rich_text_anywhere_on_the_tab`, `test_markup_is_kept_as_literal_text` |
| Clickable links (`https://`, `file://`) | No control on the tab can open a URL; text is inert | as above |
| UNC / SMB auto-fetch (`\\server\share`) | Nothing resolves or fetches text; drawn as characters | `test_a_network_path_is_kept_as_literal_text`, `test_every_line_is_a_plain_label` |
| Control characters, newlines, escape codes | Tab/newline/CR to a space; other C0 and DEL removed | `test_newlines_and_tabs_become_spaces`, `test_other_control_characters_are_removed` |
| Bidi overrides, zero-width and other non-ASCII | Replaced with `?` | `test_bidirectional_overrides_are_replaced`, `test_zero_width_characters_are_replaced`, `test_anything_beyond_ascii_is_replaced` |
| Oversize message | Cut to 200 before the character loop; send box capped | `test_a_message_is_cut_to_the_maximum_length`, `test_the_send_box_is_capped_at_the_message_length`, `test_the_host_cleans_what_a_client_sends` |
| Flood | 5 per 10 s on the sender's machine, 8 per 10 s per sender on the host | `test_your_own_send_limit_refuses_with_a_reason`, `test_the_host_limits_a_client_that_ignores_its_own_limit` |
| Spoofed sender | No sender in the packet; the host uses the peer id | `test_messages_wire.gd`: `test_the_sender_is_the_peer_not_anything_in_the_packet` |
| Recipient not in the match, or yourself over the wire | `why_not_relay` refuses; long ids dropped unread | `test_a_recipient_not_in_the_match_gets_nothing_and_nothing_breaks`, `test_a_client_addressing_itself_over_the_wire_is_not_bounced_back` |
| A client relaying to another client | `_rpc_send_message` acts only on the server | `test_only_the_host_relays` |
| A bad host, or a fault on the way | The receiver cleans again and ignores senders not in the match | `test_a_client_cleans_what_arrives_again`, `test_a_client_ignores_a_message_from_somebody_not_in_the_match` |
| Delivery to the wrong machine | One `rpc_id` to the recipient's peer; never broadcast | `test_a_message_between_clients_reaches_only_its_recipient`, `test_a_note_never_leaves_the_machine` |
| A room message echoed to its sender | `_route_to_room` skips the sender's peer by name | `test_a_room_message_reaches_everybody_but_its_sender`, `test_the_hosts_room_message_reaches_every_client_and_not_the_host_twice` |
| A blocked player learning they are blocked | Blocks are never sent anywhere; their sends succeed and are dropped on arrival | `test_blocking_is_silent_and_drops_what_the_blocked_player_sends` |

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
lobby's roster is a fixed window with a scrollbar, and a label that wraps reserves its full height through
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

Two things fix it together: every list reserves its vertical bar's width whether or
not the bar is showing (`vertical_scroll_mode = 4`, `SCROLL_MODE_RESERVE`: the bar
appears only when the rows overflow, D174), and each header is inset on the right by exactly that
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
| StalkleHeads earnings model | New `PriceModel` | **`PriceModel` interface exists from day one.** StalkleHeads turned out to need its own year pipeline rather than a new price model (stalkleheads-design.md §10.2); its pieces are in §9 |
| Mutual fund as a real index | `PriceModel` | **`next_change` receives the whole market, not just one stalk** |
| Charts, YoY, P/E history | `YearResult` list | **Year history recorded from Year 0** — cheap now, impossible to backfill |
| Custom stalks from JSON | `StalkDefinition` | **`id`-based identity, no engine-only types in definitions** |
| Industries, sector performance | `StalkDefinition.industry` + year context | Field added now, unused. **Superseded for StalkleHeads**: industries are `IndustryDefinition` content named from `CompanyProfile.industry`, and the field on the stalk stays unused (D128, §9) |
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

---

## 9. StalkleHeads: fundamentals, its year, the NPC desk, the mode, the wire, the screen and the news (phases S1-S8)

StalkleHeads is an optional second game mode in which prices come from simulated
earnings instead of random rolls. Its design is
[stalkleheads-design.md](stalkleheads-design.md); this section is how the code built
so far is laid out. **Nothing here is reachable from the base game.** No base-game
code path builds an `EarningsMarket` or an `EarningsYearResolver`,
`ContentLibrary.load_from()` does not load its content, and `test_golden_history.gd`
(D127) proves the base game is unchanged. Since S5 the title screen picks the mode,
and `MatchSetup` is the only code that reads it (D171).

Phase S1 built the pieces of a StalkleHeads year. Phase S3 built the year itself,
`EarningsYearResolver`, and the state it runs on, `EarningsMarket`. Phase S4 built
the NPC desk, which trades after every year settles and whose trading is next year's
flow, and short interest, which makes a short squeeze possible. Phase S5 made the
mode selectable: the title screen, the lobby, and `MatchSetup` choosing the board and
the year at match start. Phase S6 put the market on the wire, so a client holds the
whole match, can rejoin it and can take it over. Phase S7 put it on screen. Phase S8
added the news: headlines, industry reports, earnings commentary, whispers and NPC
chatter, as content, chosen each year by a pure selector.

### The files

| Layer | File | What it is |
|---|---|---|
| data | `earnings_regime.gd` | `EarningsRegime.Value`: GROWTH, STEADY, SLOWING, DECLINE, DISTRESS. An enum because code branches on each |
| data | `industry_definition.gd` + `industries/*.tres` | An industry as content: `id` and `display_name`. Six of them |
| data | `company_profile.gd` + `companies/*.tres` | A company's authored fundamentals: industry, opening EPS, margin, shares, quality, beta, payout policy. Eighteen of them, placeholder values from §3.2.4 |
| data | `npc_strategy.gd` | **S4.** `NpcStrategy.Value`: the eight published trading rules. An enum because the desk branches on each |
| data | `npc_trader_definition.gd` + `traders/*.tres` | **S4.** An NPC trader as content: id, name, strategy, starting cash, conviction, and a chatter line per `Situation`. Twenty-four of them, names and chatter placeholders (D162) |
| data | `squeeze/short_squeeze.tres` | **S4.** The short-squeeze template: a `SpecialEventDefinition` with no target, +25, placeholder text (D165) |
| data | `content_library.gd` | `load_fundamentals()` loads companies, industries, traders, the squeeze template and the news; `validate()` checks them, the transition matrix included (D128, D162, D204) |
| sim | `regime_rules.gd` | The transition matrix and every per-regime table; the regime roll; the damping ladder |
| sim | `company_state.gd` | One company during a match: accounts, regime, valuation, the three price terms, the posted price |
| sim | `industry_state.gd` | One industry during a match, and its persistent yearly roll |
| sim | `valuation_rules.gd` | The multiple and fair value |
| sim | `price_identity.gd` | Event carry, flow, the price, the split threshold and the split price |
| sim | `price_ledger.gd` | Why a price moved, in whole coins that sum to the move |
| sim | `dividend_rules.gd` | Payout ratio, dividend per share, the retention factor |
| sim | `earnings_market.gd` | **S3.** `GameState.market`: the companies, industries, sentiment, last year's mood, the index level, the flow input. Builds a match's board and its event pool. The bond's yardstick readouts (D160, D156) |
| sim | `earnings_year_result.gd` | **S3.** `YearResult` plus the ledgers, the index move, the sentiment used, the event bag, industry figures and every row's dividend per share |
| sim | `earnings_year_resolver.gd` | **S3.** The StalkleHeads year, §4 steps 1-10, ending in `YearSettlement` |
| sim | `year_settlement.gd` | **S3.** The back half both pipelines share: loans, net worth and standings, game end, closing the year (D152) |
| sim | `npc_trader_state.gd` | **S4.** One trader during a match: cash, shares held, shares short, and its worth at the posted prices |
| sim | `npc_desk.gd` | **S4.** `EarningsMarket.desk`: every trader in id order; `act()` (§4 step 13), each strategy's pick, short interest, the flagged companies, and what bankruptcy, splits and dividends do to traders (D162-D164, D169) |
| sim | `npc_desk_year.gd` | **S4.** What the desk did in a year: each trader's appetite, target and action, and the net shares traded |
| sim | `short_interest_rules.gd` | **S4.** The flag threshold, the squeeze chance and building a squeeze event from the template (D165) |
| data | `game_mode.gd` | **S5.** `GameMode.Value`: BASE or STALKLEHEADS. Each mode's name and lobby word (D171) |
| sim | `year_pipeline.gd` | **S5.** The base class of `YearResolver` and `EarningsYearResolver`: `advance_year` and `record_trade` (D171) |
| sim | `match_setup.gd` | **S5.** The one place the mode is read: content, board, pipeline, forced settings, take-over refusal (D171) |
| net | `market_sync.gd` | **S6.** The StalkleHeads half of the wire: the market block of a snapshot, and a year as its draws, both as packed rows; called only by `StateSync` (D176-D178) |
| tools | `wire_report.gd` | **S6.** Measures the snapshot, the year packet and the welcome in both modes, in bytes (D178) |
| data | `news_bands.gd` | **S8.** `NewsBands`: the named conditions news is chosen by - mood, move, regime, surprise - and the eight whisper triggers. Enums, `ANY` first (§8.1) |
| data | `market_headline.gd`, `industry_report.gd`, `earnings_commentary.gd`, `whisper.gd`, `npc_chatter.gd` | **S8.** One resource type per news category: an id, its conditions and its text (D199) |
| data | `news_book.gd` + `news/*.tres` | **S8.** A file of news lines of any category. Every `.tres` in `src/data/news/` is loaded; seven ship, all placeholders (D199) |
| data | `news_content.gd` | **S8.** Every news line, one sorted list per category, the traders' own chatter turned into `NpcChatter` lines. `ContentLibrary.news`, `EarningsMarket.news` |
| sim | `news_selector.gd` | **S8.** Chooses a year's news from the history: bands, triggers, the bag, the whispers' honesty roll. Its own seeded generator, never the match's (D200, D201) |
| sim | `year_news.gd` | **S8.** One year's chosen lines with their tokens filled in, kept on `EarningsYearResult.news` |
| tests | `fixtures/wire_match.gd` | **S6.** A seeded StalkleHeads match with scripted players, and every field of a match or a year written as lines, so two copies compare field by field |

`CompanyState` pairs with `CompanyProfile` the way `StalkState` pairs with
`StalkDefinition`, and `IndustryState` with `IndustryDefinition`: the resource is
immutable content, the `RefCounted` is what changes during a match. The `*Rules`
classes are static functions with no state, like `TradeRules` and `LoanRules`.

### One year: `EarningsYearResolver.advance_year`

**Two halves since S6 (D178).** Everything up to step 4 is the year's *draws*, made
only on the host and written into the result as inputs. Everything from steps 3 and
5 to 10 is `_settle_prices`, arithmetic on those inputs. `advance_year` is
draw-then-settle; `replay_year`, which a client runs, takes the host's draws and
settles with the same code.

```
restore the event pool from market.event_bags (D177)
year += 1; open a StalkYearChange per row; copy() every living company
market.sentiment_used = market.sentiment       # what this year is valued on

1   IndustryState.advance_all(industries, market.sentiment, rng)  # one draw each, id order
2   company.advance_earnings(performance, max_years, rng)         # two draws each, id order
4   roll = rng.randi_range(1, 100)                                # the squeeze roll, every year
    flagged = desk.flagged_companies(state)                       # short interest, as last year left it
    if template and roll <= squeeze_chance(flagged): event = squeeze on flagged[0]
    else: event = EventPool.draw(market.last_mood, state, rng)    # last year's bag; bull in year 1
    market.event_bags = pool.bag_state()
    result.net_shares_priced[id] = market.net_shares_traded[id]  # the last input
--- _settle_prices: everything below draws nothing, and replay_year runs it too ---
3,5 company.reprice(market.sentiment, performance, event_delta,  # no draws
                    result.net_shares_priced[id])
    ledger = PriceLedger.between(copy, company); row.price = company.price
6   index move = mean pre-split % move (bankrupt this year = -100)
    index_level *= (100 + move) / 100
7   mood = BULL if move > 0 else BEAR; market.sentiment = clamp(move, -20, 20)
8   bankruptcy, one pass: price <= 0 -> row bankrupt, holders wiped out (traders' too),
    company.fail() clears its valuation readouts (D176)
9   splits above 300: company.split_if_above(), holders' shares doubled; the index too
10  dividends: company from earnings, bond its coupon, index the mean of its constituents'
    (traders are paid on what they hold and pay on what they are short)
--- end of _settle_prices; replay_year stops here ---
YearSettlement.settle(state, result)                              # loans, net worth, game end
13  result.desk = desk.act(state, rng)                            # two draws per trader, id order
    market.record_trade(id, net) for each of the desk's trades    # next year's flow input
```

**How the board and the market stay in step (D160).** The board is still
`GameState.stalks`, a `StalkState` per row, so `TradeRules`, `LoanRules` and
`YearSettlement` work on it unchanged. The fundamentals sit beside it in
`GameState.market`. Every time the resolver changes a company's price it copies it to
that company's row; the bankrupt flag lives on the row. A company the base game does
not ship gets a row definition built in memory from its profile.

**The flow input.** `market.net_shares_traded` is filled through
`EarningsMarket.record_trade`, and the next advance reads the companies' entries,
then clears it. Two things fill it: the NPC desk at step 13 of every advance, and
the players' trades during the trading phase that follows. Since S5 the second
arrives through `MatchAuthority`: every accepted buy and sell calls the pipeline's
`record_trade`, which in this mode is `EarningsMarket.record_trade` (D163, D171). The
balance tool records its own players' trades the same way.

**Four seams, for the balance tool only.** `advance_company_earnings`,
`valuation_performance` and `squeeze_chance_percent` are public methods that
`tools/balance/lever_year.gd` overrides to apply its levers (D150, D161, D166), and
`NpcDesk.choose_target` is one that `tools/balance/lever_desk.gd` overrides (D168).
The game never overrides them.

**The squeeze template is passed in.** `EarningsYearResolver.new(pool, squeeze)`
takes `ContentLibrary.short_squeeze` as its second argument; without it no squeeze
can fire, and the roll is drawn anyway so the stream is the same (D165).
`MatchSetup.new_pipeline` passes it (S5, D171).

### The NPC desk (phase S4)

The desk is `EarningsMarket.desk`, an `NpcDesk` of twenty-four `NpcTraderState`s
built from `ContentLibrary.traders`. It acts once a year, at §4 step 13, after the
settlement, on the published state, so its trading can only move the next year
(design §4). Traders are not players: they are never in `GameState.players`, never
ranked, never in the ready gate.

**How a trader decides** (`NpcDesk.target_for`, pure): each strategy reads the board
and picks one id, ties to the lowest. **How it trades:** every strategy but SHORT
sells everything except its target at the posted price, then spends
`cash * conviction * appetite / 10000` on the target, rounding down to whole shares.
SHORT keeps real short accounting: selling short adds the proceeds to its cash, its
worth subtracts what buying back would cost, it pays dividends on what it is short,
and a bankruptcy closes the short at zero in its favour (D164).

**Determinism (§5.4, D163).** Traders act in sorted id order. Each draws exactly
twice a year, appetite then pick, before deciding anything. A decision reads only
the state and those two draws.

**Short interest is not stored.** `NpcDesk.short_interest(id)` sums the traders'
short positions, which are the state. A company is flagged at 10% of its shares
outstanding (`ShortInterestRules`).

### Choosing the mode (phase S5)

A match is the base game or StalkleHeads, chosen before it starts:
`GameSettings.mode`, a `GameMode.Value`, `BASE` by default. **One class reads it**,
`src/sim/match_setup.gd`, once, when the match is built (D171):

```
title screen (Game row) -> GameSettings.mode
Main._loaded_library(mode) -> MatchSetup.load_library   base content, + fundamentals for StalkleHeads
LocalSession.build_authority
    MatchSetup.apply_mode_rules(settings)               StalkleHeads: multiple_loans_enabled on
    MatchSetup.new_game_state(settings, library)        the board (and the market)
    MatchSetup.new_pipeline(settings, library)          YearResolver or EarningsYearResolver
    MatchAuthority.new(state, pipeline, rng)
```

`HostSession.host` and the rematch go through `build_authority` too, so offline,
hosted and rematched matches are built identically. `HostSession.take_over` builds
its pipeline with `MatchSetup.new_pipeline`, and first asks
`MatchSetup.why_not_take_over`, which refuses a StalkleHeads match without its market.
Since S6 a client's copy has one, so only a snapshot from an older build is refused.

**`YearPipeline`** (`src/sim/year_pipeline.gd`) is the base class of both resolvers:
`advance_year`, and `record_trade`, which `MatchAuthority` calls after every accepted
trade. The base game's `record_trade` does nothing. That is how a player's trade
becomes flow in StalkleHeads without `MatchAuthority` knowing the mode.

**Reaching the client.** The mode travels in the snapshot's settings. A joining
client loads the base content, then `StateSync.apply_state` tops its library up with
`MatchSetup.prepare_library` once the settings say StalkleHeads, and resolves a
company the base game does not ship with `MatchSetup.board_definition`. The
market follows it in the same snapshot (next section).

**The lobby.** `SteamService` publishes `mode` (`KEY_MODE`) as `GameMode.lobby_value`,
a word, beside years, cash and loans (D88). `SteamLobbyRow.describe` puts
`GameMode.label_for_lobby_value` first, and leaves it out for a lobby that published
none.

### Reaching the client (phase S6)

Design §9.1's rule, **inputs travel, readouts are derived**, applied twice
(`src/net/market_sync.gd`, D176-D178). `StateSync` calls `MarketSync` only when a
match has a market, so the base game's wire is unchanged.

```
host                                         client
StateSync.encode_state                       StateSync.apply_state
  + "market": MarketSync.encode_market         board and players as before, then
      packed rows of the market's STATE          MarketSync.apply_market
      (no profit, multiple, fair value...)         content_key must match its own
                                                   CompanyState.derive_readouts per company

StateSync.encode_year_result(result, state)  StateSync.decode_live_year   (BEFORE the snapshot)
  - stalk_changes, - mood                      EarningsMarket.replay_state(state)   a copy
  + "inputs": the year's DRAWS                 EarningsYearResolver.replay_year(copy, result)
      and the desk's record                       -> row changes, ledgers, mood, dividends

StateSync.encode_history                     StateSync.apply_history
  every year as above                          a fresh year-0 match, replayed year by year
```

**Why the client can trust its own numbers.** Every readout comes from the same
`sim` code the host ran: `derive_readouts` mirrors `reprice`, and `replay_year`
*is* the host's year after its draws. Both are integer arithmetic and IEEE floats
with no transcendental functions (D130), so two machines on the same build compute
the same bits. `test_wire.gd` checks that over whole matches.

**Order matters on a live year.** The replay needs the market as it was before the
year, and the snapshot that comes with the year replaces it, so `ClientSession`
decodes the year first and applies the snapshot second.

**Migration** needs nothing new: the promoted host's `GameState` already holds the
whole market, including the event bags (D177), and `take_over` builds the pipeline
as before. The first year it advances restores the pool from those bags.

### On screen (phase S7)

The base playing screen, with the boards swapped out (D180). Nothing below draws a
number it worked out: every figure comes from `src/sim/` (D179).

```
GameplayScreen (base game's, unchanged around the boards)
  %Boards          hidden in StalkleHeads
  %MarketSlot      MarketTabs, built the first time state.market exists
    TopRow           tab strip, then HOLDINGS / RANKINGS / DESK buttons
    ExchangeTab      CompanyRow per board row, under group CompanyRows
    MarketTab        two halves: CellRow lines and DrawnChart index line; a
                     scrolling right half with the whispers, the headline,
                     the event, mood row and a narrow YearDigestPanel (D189)
    IndustriesTab    CellRow table, signed TextChart, members as TradeLines,
                     the selected industry's report
    CompanyTab       pinned title line (COMPANIES < name >), then a scroll:
                     identity line with a TradeBox, CellRow earnings table,
                     LedgerWidget, its news, investors, desk table with each
                     trader's chatter under its line
    MessagesTab      two ChatPanels side by side and the player list, each
                     name a Button with a StatusDot icon (§5.8, D192)
    Body (MarginContainer: every child over the same rectangle)
      PagesRow       the four tabs, and SideSpace (a free column on EXCHANGE)
      PickerLayer    CompanyPicker in an OverlayFrame, over the Company tab
      SideLayer      SidePanel in an OverlayFrame: HOLDINGS (compact
                     HoldingRows), RANKINGS, DESK (with CHATTER) - over the tab
  NewsPanel        + YearDigestPanel in its %DigestSlot

src/sim/ MarketReadouts   every derived figure: P/E, shares, averages, breadth...
src/sim/ YearDigest       the year in review's picks
src/sim/ NewsSelector     the year's news lines (S8)
EarningsYearResult.companies_after / index_level_after   the per-year record
```

**Where the history comes from.** `_settle_prices`, the half of the year a client
replays (D178), copies every company into `EarningsYearResult.companies_after`. So a
client's Company tab shows the same five years as the host's without anything new
on the wire; `test_stalkleheads_screen.gd` compares all four tabs line by line.

**The widgets.** `CellRow` is one line of a text table, its columns a whole number of
characters wide (D181). `CompanyRow` is a board row, an industry header or the column
headings, in one scene so the three line up. `ChartWidget` shows a `TextChart`
string (the industry chart); `DrawnChart` draws line, candle and bar charts, placed
by the pure `ChartGeometry` (D188: the index line and the Company tab's charts);
`LedgerWidget` the price ledger, `YearDigestPanel` the year in review. Each
emits signals with ids and knows nothing of the tab holding it.

**Trading** goes through the base game's handlers: `MarketTabs.buy_requested` is
connected to the same `_on_buy_requested` as a base `StalkRow`. Every company shown
on its own has a `TradeBox` (quantity, BUY, SELL): a board row, an industry's member
line (`TradeLine`, a `CellRow` and a box) and the Company tab. A holding is the base
game's `HoldingRow`, compact and sell only (D184). Each refresh
`MarketTabs` builds one `TradeContext` from the screen's two checks
(`set_trade_checks`, the session's `why_not_buy`/`why_not_sell`), and every box is
prepared and checked through it (D183).

**The side panel** is open on EXCHANGE always and on the other tabs only when one
of its buttons is pressed; changing tab closes it (D183). Elsewhere it lies over the
tab; on EXCHANGE the board leaves it a column (D184). Holdings follow
`ExchangeTab.board_order()`. The Company tab's arrows and its list of companies
follow `state.stalks`, the match's own order.

**Definitions** of financial terms, used as tooltips, are constants in
`src/ui/term_tips.gd`, so a definition is written once. `TermTips.fit` wraps any
tooltip to `MAX_CHARS`; `CellRow.set_cell_tooltip` calls it, so every table cell's
tooltip is wrapped without the caller remembering (D184).

**Collapse and sort** are held in `ExchangeTab` only (D182): the viewer's, not the
match's.

### The news (phase S8)

```
src/data/news/*.tres ──┐                 (NewsBook files, words only)
src/data/traders/*.tres ┤ chatter_* fields
                        ▼
ContentLibrary.load_fundamentals → NewsContent.build → validate()
                        │
EarningsMarket.news ────┘
                        │   a screen asks
NewsSelector.news_for(state, year)
   ├─ earlier years first (their draws are this year's bag counts)
   ├─ rng seeded from the year's own draws (D200)
   ├─ headline, report per industry, commentary per company,
   │  up to two whispers, chatter per trader
   └─ YearNews, kept on EarningsYearResult.news
                        │
MarketTab / IndustriesTab / CompanyTab / SidePanel
```

**A readout, not state.** The selector reads only the year records every peer
already holds - mood, index move, industry performance, each company as the year
left it (`companies_after`), the regimes, the flagged short interest, what the desk
did - and the content. It writes nothing back to the market and sends nothing, so
the wire, the snapshot and the match's random stream are exactly what S6 left
(D200). A client works out the host's news; `test_news.gd` checks that, a rejoiner
and a promoted host over thirty years.

**Adding content is adding lines**, to an existing book or a new `.tres` in the
folder. [development.md](development.md) "Writing StalkleHeads news" is the
step-by-step; [game-rules.md](game-rules.md) §5.1 is what each condition means.

### The rules that hold it together

- **Draw counts are fixed** (D131): an industry is one draw, earnings season two,
  valuation and pricing none. So the random stream never depends on what happened,
  which multiplayer and the golden-history style of test both need.
- **Two truncations per company** (D130, D138): `PriceIdentity.price_of` and
  `DividendRules.dividend_per_share`. Revenue, profit, margin, EPS, the multiple,
  fair value, event carry and flow are all floats. The index adds two of its own, its
  posted price `int(index_level)` and its averaged dividend (D157).
- **The ledger balances by construction** (D133), and a test checks it over forty
  seeded 30-year runs of all eighteen companies.

### The balance tool (phases S2 and S3)

The balance tool plays many seeded StalkleHeads matches and prints how each player
strategy did (design §2.6, §12.1). It is a tool, not game code: everything is in
`tools/`, and nothing in `src/` refers to it.

| File | What it is |
|---|---|
| `tools/balance_report.gd` | The command-line entry point: reads arguments, runs the matches, prints the table |
| `tools/balance/balance_match.gd` | One match: a real `GameState` from `EarningsMarket.new_game_state`, the ten strategies as real `PlayerState`s (FOLLOW copies the desk's richest trader since S4), their trading, the flow mode, net worth at the end |
| `tools/balance/lever_year.gd` | `EarningsYearResolver` with the sweep's levers applied through its two seams (D161) |
| `tools/balance/levers.gd` | Balance overrides for a sweep (premium, GROWTH stay chance, ageing; since S4 the squeeze on or off, its chance and its size, and the SHORT traders' target), applied without touching `src/sim/` (D150, D166, D168) |
| `tools/balance/lever_desk.gd` | `NpcDesk` with the SHORT-target lever applied through its one seam, `choose_target`: the old slowest-grower rule, since the game's desk bets against the highest P/E (D168, D169) |
| `tests/unit/test_balance_smoke.gd` | 30 fixed-seed matches with loose bands, in the GUT suite |

S2 drove the year with a stand-in, `tools/balance/stand_in_year.gd` (D144). S3 deleted
it: the tool now plays the game's own year, so dividends, splits, bankruptcies, the
index, the derived mood and the event pool are all the pipeline's (D161).

**Two random streams** (D145): the market, the desk included, draws from a generator
seeded with the match seed, and only the RANDOM strategy draws from a second one. So
which strategies run never changes the market they run on, unless their own trades
feed the flow term (`--flow=all`, the default since S4), which is the game's rule.

**What it leaves out:** loans, and Mutuals as something a player strategy buys (the
INDEXER traders do buy it).
