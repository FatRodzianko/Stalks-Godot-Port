# Custom stalks

Players can add their own companies to the game, choose which companies a match
is played with, and host a match on them. This document is the file format, the
rules a file must satisfy, and how a match's content reaches the other players.

The rules a custom stalk is bound by are in [game-rules.md](game-rules.md) §3
and §14; the reasoning behind the design is D119–D123 in
[decisions.md](decisions.md).

---

## 1. Where the files go

One file per company, in the per-user writable folder:

| Platform | Folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\Stalks Stalks Stalks\custom_stalks\` |
| Linux | `~/.local/share/godot/app_userdata/Stalks Stalks Stalks/custom_stalks/` |
| macOS | `~/Library/Application Support/Godot/app_userdata/Stalks Stalks Stalks/custom_stalks/` |

In code this is `user://custom_stalks`, and `CustomStalkStore.DIR` is the one
place that spells it. The folder is **created the first time the game looks for
it**, with a file called `HOW-TO-WRITE-A-STALK.txt` inside explaining the
format — so a player who finds the folder is not left guessing. That text is
generated from the limits in `StalkSchema`, so it cannot drift out of date.

`user://` is outside the exported game, so updating or reinstalling the game
does not touch a player's companies.

### Why JSON and not `.tres`

The shipped stalks are `.tres` resources. Custom ones deliberately are not.

Loading a `.tres` instantiates whatever script the file names, which is the
object-decoding hole that [D41](decisions.md) closed on purpose for the
network. A folder a player can drop files into is exactly as untrusted as a
packet, so it gets the same answer: `JSON` parsing returns nothing but built-in
types, and `StalkSchema` builds the definition field by field from there.

**Never add a path that loads a player-supplied `.tres`, and never enable
object decoding to make something here easier.**

---

## 2. The format

```json
{
  "format": 1,
  "name": "Example Holdings",
  "description": "",
  "starting_price": 100,
  "bull_change": [0, 15],
  "bear_change": [5, 25],
  "bull_dividend": 3,
  "bear_dividend": 1,
  "events": [
    {"mood": "bull", "text": "Something good happened.", "price_change": 10},
    {"mood": "bear", "text": "Something bad happened.", "price_change": -15}
  ]
}
```

### Fields

| Field | Required | Meaning |
|---|---|---|
| `format` | no | File format version. Assumed `1` when absent. A file declaring any other version is refused with a message saying so. |
| `name` | **yes** | What the board and the company panel show. |
| `description` | no | The paragraph on the company panel. **Blank when absent**, and the panel simply shows nothing. |
| `starting_price` | no | Opening price. Defaults to 100. |
| `bull_change` | **yes** | `[smallest, largest]` the price moves in a bull year. |
| `bear_change` | **yes** | The same for a bear year. Written **positive** and subtracted. |
| `bull_dividend` | **yes** | Paid per share held, every bull year. |
| `bear_dividend` | **yes** | Paid per share held, every bear year. |
| `ticker` | no | Short board symbol. Accepted and validated, but **nothing displays it yet** — see `StalkDefinition.ticker`. |
| `is_price_static` | no | A company whose price never moves, like BERRY BONDS. Such a company may carry no events. |
| `investors_are_anonymous` | no | Keeps this company's holders off its details panel (§D103). |
| `id` | no | Overrides the id derived from the filename. Rarely wanted. |
| `events` | no | Special events, below. |

### Events

**Events are optional, and a company with none is never picked for a special
event.** That needs no rule of its own: `EventPool` draws from whatever it is
given, so a company that puts nothing into the pool cannot come out of it.

| Field | Required | Meaning |
|---|---|---|
| `mood` | **yes** | `"bull"` or `"bear"` — which pool the event is drawn from. |
| `text` | **yes** | The flavour text shown in the event strip. |
| `price_change` | **yes** | Added to the price on top of the normal yearly change. Positive for bull, negative for bear. May not be `0`. |
| `id` | no | Derived from the company and the event's position when absent, which is almost always right. |

### Ids, which you do not write

Every custom company's id is `custom:` followed by a slug of the filename —
`my_company.json` becomes `custom:my_company`. The prefix means **a custom
company can never collide with or shadow a shipped one**, whatever its file
says: a file claiming `"id": "berry_bonds"` becomes `custom:berry_bonds`, which
is a different company.

Event ids are derived the same way (`custom:my_company#bull0`), so an author
never has to invent ten unique keys and a whole class of duplicate-id mistake
cannot be made.

---

## 3. The limits

Every one of these is a measurement of the shipped content, rounded up, rather
than a round number chosen for looking sensible. They live as constants in
`src/data/stalk_schema.gd` and the suite asserts that all ten shipped stalks
satisfy them — **if a rule here would reject the game's own content, the rule
is wrong.**

| Thing | Limit | Why that number |
|---|---|---|
| `name` | 48 characters | The longest shipped name is 41 (`My Pillow, Your Pillow, We're All Pillows!`). |
| `description` | 600 characters | The longest shipped one is 344. |
| event `text` | 300 characters | The longest shipped one is 240. |
| `ticker` | 8 characters | Nothing draws it yet; it is bounded because it is accepted. |
| id | 40 characters | Long enough to be descriptive, short enough for a log line. |
| `starting_price` | 1 to 150 | A company above 150 splits in the same year, so a higher start means one that halves before anybody has traded it. |
| dividends | 0 to 99 | The board's dividend columns are four characters. The largest shipped dividend is 8. |
| change bounds | 0 to 99 | The largest shipped bound is 50 (strYker's bear range). |
| events | 10 bull and 10 bear | The shipped companies carry five of each. |
| stalks per match | 10 | §4 below. |
| file size | 64 KB | About eighty times the largest shipped company. Checked **before** the bytes are read. |

### Characters

**Printable ASCII only**: space (32) through `~` (126).

The instruction when this was built was "alphanumeric strings", and that was
raised rather than implemented, because strictly alphanumeric rejects the
game's own voice — `PG&Enron`, `strYker!!!` and
`My Pillow, Your Pillow, We're All Pillows!` all contain punctuation. Printable
ASCII is the widest rule the game can actually draw: Terminus is a fixed-width
bitmap font whose columns are measured in characters, and anything outside this
range is either a glyph the font does not have or a control character that
corrupts a row.

Accented letters and emoji are therefore refused, with a message saying why.

---

## 4. Choosing what a match uses

**Create Game → CUSTOM STALKS** lists every company this machine has, shipped
and custom together, with a tick against each.

- **A match holds at most 10 companies.** When ten are ticked, the rest grey
  out; unticking one brings them back. The cap is `StalkSchema.MAX_STALKS_PER_MATCH`
  and **raising it is that one number** — the picker counts against it, the
  board scrolls, and the wire has no per-stalk assumption. Around fifty is the
  figure that has been discussed.
- **The choice is remembered between sessions**, which is an exception to the
  rule that match settings are not (D71) — see D123 for why, and note that the
  **Reset** button, which puts the shipped ten back, is the thing that makes it
  safe.
- A choice identical to the shipped ten is stored as *no choice at all*, so
  opening the screen, looking, and closing it changes nothing.
- A file that could not be read is named on this screen, with the line and the
  reason, and **the rest still load**. Nine good files and one typo give nine
  companies and one message.

---

## 5. How a match's content reaches the other players

This is the part that is not a content feature.

Before custom stalks, both sides loaded the same `.tres` files, so only ids
travelled and each receiver looked the definition up locally. `state_sync.gd`
said so in its own documentation and `apply_state` refused a snapshot naming a
stalk it did not know. **Custom stalks end that assumption**: a host may be
playing companies no other machine has ever seen, and no local lookup can
invent them.

So:

1. **The host decides the content.** Whatever the host ticked is assembled into
   a `ContentLibrary` for that match, and that library — not the host's disk —
   is what the match runs on.
2. **It travels once, with the welcome.** `_rpc_welcome` carries the whole
   match's content, every company, shipped ones included. Not only the custom
   ones: sending all of them makes the host's content the match's content
   outright and removes the second way a definition could arrive.
3. **It is applied before anything else in the welcome.** The snapshot and the
   year history both name companies and events by id, so there must be a
   library to resolve them against first.
4. **A snapshot still carries ids only.** Snapshots go out on every trade; the
   content goes once, when there is a new receiver. The id rule survives, and
   `apply_state` still fails loudly on an unresolvable id, which after a
   welcome can only mean the two sides disagree about a match they are both in.
5. **A new host serves the content it received.** After a host migration the
   player taking over uses the library that arrived with its welcome, not its
   own files. A host that re-read its own folder would hand the remaining
   players a different market — the companies would still be on the board,
   because the board comes from the promoted `GameState`, but **no event could
   ever fire for them again**, because the event pool comes from the library.
6. **Rejoining needs nothing extra.** A returning player is welcomed like any
   other arrival, so the content rides the same path.

### Treating a received definition as hostile

A definition now arrives from another player, so it goes through the same
`StalkSchema` as a file off disk. The checks are identical; only the answer to
a failure differs — a bad file is listed in the picker and skipped, a bad
payload ends the connection with a reason, which `ClientSession.connection_lost`
already carries to the screen.

Concretely, and each of these has a test that was written by reinstating the
fault it guards:

- **Fields are whitelisted.** The definition is built key by key; a dictionary
  is never copied across. A key the game does not know is an error rather than
  something ignored, so a misspelled `bull_dividends` is named instead of
  silently becoming zero.
- **Integers are refused, not clamped.** Every number here feeds integer money
  or a column measured in characters. A value with a fractional part is
  refused rather than truncated, a boolean is not accepted as a number, and a
  value too large for a float to represent exactly is refused before it is
  compared against anything.
- **Counts and size are capped**, structurally: at most 10 companies, 10 events
  per mood, and a bounded length on every string. An oversized payload is
  refused with a reason. Note honestly that the engine has already decoded the
  packet by the time any of this runs, so the cap limits what the game
  *builds*, not what it *receives*; the file-size check, which happens before
  the bytes are read, is the one that prevents the allocation.
- **Ids must be well formed** — a plain token, optionally behind `custom:`,
  optionally with one derived event suffix. No separator, scheme or traversal
  survives that, so an id cannot be mistaken for a path. Duplicate ids in one
  payload are refused.
- **Nothing is partial.** A library missing the one company that failed would
  be a board quietly short a column, so the whole payload is refused together.
- **The refusal itself is sanitised.** The reason is drawn on screen, so
  untrusted text in it is stripped of unprintable characters and cut short — a
  hostile id may not use the complaint about it as a way in.

### What a dishonest host can still do, and why that is not the threat

A host that sends a shipped company with invented numbers is a host rewriting
its own simulation, which it can already do: it owns every price, dividend and
ranking in the match. Validation is not there to stop that and could not.

What it stops is a host **breaking the client that trusts it** — markup
injection, unprintable characters, an integer that overflows a money
calculation or a fixed-width column, or counts large enough to hang the
machine. See D121.

### Square brackets

`[` is the one character here that is dangerous rather than merely untidy: the
event strip is a `RichTextLabel` with BBCode enabled, so a `[` in flavour text
is markup. It is **allowed in content** — it is ordinary punctuation — and
**escaped where it is drawn**, by `ScrollingLabel`. Every other place content
text is rendered (`StalkPanel`, `StalkRow`, `HoldingRow`, the news panel) is a
plain `Label`, which draws markup as text.

If you ever turn one of those into a `RichTextLabel`, escape the text there
too. `test_custom_stalks.gd` asserts both halves of this today.

---

## 6. Where the code is

| File | What it does |
|---|---|
| `src/data/stalk_schema.gd` | The rules. Builds a `StalkDefinition` from plain data, field by field, and refuses what it cannot vouch for. Pure, no nodes. |
| `src/data/custom_stalk_store.gd` | Reads the player's folder. One file per company; a bad one is skipped and reported. |
| `src/data/content_library.gd` | `available()` is everything this machine has; `subset()` is one match's content, and holds the cap. |
| `src/data/game_settings.gd` | `chosen_stalk_ids` — empty means the shipped ten. |
| `src/ui/widgets/stalk_picker.gd` | The Custom Stalks screen. Chooses; does not load. |
| `src/ui/widgets/stalk_pick_row.gd` | One row of it. |
| `src/net/state_sync.gd` | `encode_content` / `decode_content`. |
| `src/ui/screens/main/main.gd` | `_match_library()` assembles a match's content; `_migrating_library` carries it through a handover. |
| `tools/custom_stalks_shot.gd` | Renders the picker and the board, for looking at what a test cannot show. |
