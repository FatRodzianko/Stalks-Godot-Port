# Development

How to get this project running on a machine that has never seen it, and how to work
on it afterwards.

Written to be followed by someone with no prior context. If a step does not work as
described, that is a bug in this document worth fixing.

---


## 1. What you need

| Requirement | Version | Notes |
|---|---|---|
| **Godot** | **4.7.2 stable** | The *standard* build, **not** the .NET/Mono build. See §2. |
| **git** | any recent | For the repository. |
| Nothing else | | No .NET SDK, no Node, no Python, no build system. |

**You do not need:**

- The .NET build of Godot — this project is GDScript (see decisions.md D1).
- The original Unity project — it is not in this repository and is not required. Every
  value extracted from it is written into [game-rules.md](game-rules.md).
- Steam, or a Steam developer account — not until Phase 6.
- An AI assistant.

### Why the version is exact

Do not substitute a different Godot 4.x release. GUT's compatibility is pinned to the
Godot minor version, and Godot 4.7 changed internals that break other addons. See
decisions.md D2.

---

## 2. Get Godot

Godot needs no installer — it is a single executable.

1. Download **Godot 4.7.2 stable**, standard (not .NET) build, for your platform,
   from <https://godotengine.org/download/archive/> (look under 4.7.2).
2. Extract the zip somewhere sensible. It contains two executables:
   - `Godot_v4.7.2-stable_<platform>` — the **GUI editor**.
   - `Godot_v4.7.2-stable_<platform>_console` — the **command-line** version, which
     prints to stdout. *This is the one you want for tests and scripts.*
3. Note where you put it. These docs call the console executable **`<godot>`**.

> **Watch out:** on Windows, extracting the zip may produce a *folder* whose name ends
> in `.exe`, with the real executables inside it. That is a quirk of the archive, not
> a problem — just be aware the path has an extra level.

### Optional: make `<godot>` a real command

Life is easier if you do not retype the path. On Windows PowerShell:

```powershell
Set-Alias godotc "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
```

On macOS or Linux:

```bash
alias godotc="/path/to/Godot_v4.7.2-stable_linux.x86_64"
```

Add it to your shell profile to make it permanent. Everywhere below, `<godot>` means
this executable.

### Paths on the original author's machine

Recorded only so existing notes make sense. **This is one machine's layout and need
not match yours.** The engine folder sits beside the project folder, so commands in
these docs that start `& "..\Godot_v4.7.2-stable_win64\..."` and are run from the
project root find it with no change:

```
<any folder>\
  Godot_v4.7.2-stable_win64\
    Godot_v4.7.2-stable_win64.exe           (editor)
    Godot_v4.7.2-stable_win64_console.exe   (CLI — this is <godot>)
  Stalks-Godot-Port\                        (this repository)
```

The original Unity project is kept elsewhere on that machine and is not in git.

An automated assistant needs a literal path rather than a placeholder, so one is
kept in `CLAUDE.local.md` — a file beside `CLAUDE.md` that is loaded with it and is
deliberately not committed, because it is about one machine rather than about the
project. Every document, `CLAUDE.md` included, uses `<godot>`.

---

## 3. Get the code and run it

```bash
git clone https://github.com/FatRodzianko/Stalks-Godot-Port.git
cd Stalks-Godot-Port
```

**Import the assets first.** A fresh clone has no `.godot/` cache, and most commands
fail or behave oddly without it:

```
<godot> --headless --path . --import
```

**Then run the test suite.** If this passes, your setup is correct:

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

You should see roughly:

```
Totals
------
Scripts               5
Tests                67
Passing Tests        67
Asserts           12641
Time              2.4s

---- All tests passed! ----
```

That is the whole verification. There is no build step.

**To open the editor**, launch the GUI executable, click *Import*, select this
folder's `project.godot`, and click *Import & Edit*. First-time users should read
[godot-editor-guide.md](godot-editor-guide.md), which walks through the whole
interface.

---

## 4. The verification loop

Four commands cover everything. Learn these and you can work without the editor at
all.

| Purpose | Command |
|---|---|
| Import assets (first in a fresh clone; re-run after adding asset files) | `<godot> --headless --path . --import` |
| Parse and typecheck one script, without running it | `<godot> --headless --path . --check-only --script res://path/to/file.gd` |
| Run a one-off script headlessly | `<godot> --headless --path . --script res://path/to/file.gd` |
| Run the test suite | `<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd` |
| Run the game | `<godot> --path .` |

`--check-only` is the fastest feedback available — under a second — and because of
decisions.md D18 it catches untyped declarations as hard errors, not warnings.

A one-off script must extend `SceneTree` and do its work in `_initialize()`, calling
`quit()` when finished. Useful for probing a formula before committing to it.

More test-running options are in [testing.md](testing.md).

---

## 5. Project layout

```
addons/gut/      The test framework. Committed deliberately (decisions.md D17).
addons/news_flow_chart/
                 Ours: the News Flow Chart, an editor tool for writing news
                 (news-flow-chart.md). Not part of the game. Adds the
                 News Flow tab; core/ logic, ui/ screens, check/ validator run.
assets/
  themes/        Shared Theme resources. All colours and fonts belong here.
  sprites/
  audio/
docs/            All documentation. Start at docs/README.md.
src/
  data/          Authored content and settings. Resource classes, saved as .tres.
  sim/           The entire economy. No nodes, no networking. See architecture.md.
  net/            (empty — Phase 5) Session and transport.
  autoload/       (empty) Global services, registered in project.godot.
  ui/
    screens/     One folder per screen, scene and script together.
    widgets/     Reusable UI pieces.
tests/
  fixtures/      Shared test helpers. Not scanned for tests.
  unit/          Everything GUT runs.
tools/           Headless scripts a developer runs by hand: network checks,
                 screenshots, and the StalkleHeads balance tool (balance_report.gd,
                 with its pieces in tools/balance/), plus measure_loudness.gd
                 and level_sounds.gd, which measure and level the sounds in
                 assets/audio/ (run both before adding a sound, D221).
                 Nothing in src/ uses them.
project.godot    Engine configuration. Edited directly; see decisions.md D19.
.gutconfig.json  Test runner configuration.
CLAUDE.md        Coding standards. Addressed to an AI, but applies to everyone.
CLAUDE.local.md  Not committed. One machine's paths and personal preferences.
```

The single most important structural rule: **`src/sim` never depends on anything above
it.** No nodes, no scene tree, no network. See decisions.md D3 — this is not a
preference, it is what makes the game testable.

---

## 6. How to do common things

### Add a new stalk

A stalk and all its events are **one file**, so this is a single-file change
(decisions.md D29). The easiest route is to copy an existing one.

1. Copy any file in `src/data/stalks/` — `mafia.tres` is a good, ordinary example —
   and rename it.
2. Open it in the Godot editor (double-click it) and edit it in the Inspector, or
   edit the text directly; `.tres` is plain text.
3. Set a unique **`id`** (a `StringName`, never the display name — decisions.md D9)
   and a `display_name`.
4. Set `starting_price` (100 for every shipped stalk), `bear_change`, `bull_change`,
   and the two dividends. `bear_change` and `bull_change` are `(min, max)` magnitudes
   and are **always stored positive** — the bear one is applied negatively. The
   shipped values for all ten existing stalks are in
   [game-rules.md §3](game-rules.md).
5. Under **Special Events**, fill in `bull_events` and `bear_events`. Each entry is a
   `SpecialEventDefinition` with a unique `id`, a `target_stalk_id` **matching this
   stalk's id**, the matching `mood`, `flavour_text`, and a non-zero `price_change`
   (positive in the bull list, negative in the bear list by convention, though a
   negative bull event is legal).
6. For a static-price instrument like BERRY BONDS, set `is_price_static` and leave
   both event lists empty — it cannot be moved by anything.
7. Run the suite. `ContentLibrary` validates the whole directory and will name
   anything wrong.

No code change is needed. If you find yourself writing one, something has been
hardcoded that should be data.

**The validator is your friend here.** It catches the mistake that is otherwise
invisible: an event whose `target_stalk_id` has a typo will never fire, and without
validation nothing would tell you. It reports every problem in one run rather than
stopping at the first, so you can fix a new stalk in one pass. See decisions.md D31
for the full list of checks.

### Where the shipped content came from

The ten stalks and ninety events were imported from the original Unity source by a
one-off script that parsed `StalkManager.CreateSpecialEvents()` and wrote the `.tres`
files via `ResourceSaver`, rather than being retyped. That importer has been deleted:
the `.tres` files are the source of truth now. If you ever need to re-derive them,
the method is in the git history for the Phase 3 commit.

### Writing StalkleHeads news

Every news line in StalkleHeads - market news, industry headlines, company news,
whispers and NPC chatter - is a short piece of text in a `.tres` file. **Writing
them needs no code change.** Until somebody writes them they are placeholders that
say which slot they fill, like `IN THE NEWS: {company}, crash`, so one that turns
up on screen tells you exactly which line is missing. To find every line still to
write, search `src/data/` for `IN THE NEWS:`, `EVENT:`, `NPC NAME:` and
`NPC CHATTER:`; whispers have no prefix (D218), and are the `whispers` list in
`src/data/news/market.tres`.

**Two things on screen are not lines and cannot be written here:** the Company
tab's EARNINGS report and the Industries tab's INDUSTRY REPORT. Code writes both
from the numbers each year (`src/sim/report_writer.gd`, decisions.md D215), so
there is nothing to fill in. To change their wording, edit that file.

What the game does with them - which line is chosen when, where it shows - is in
[game-rules.md](game-rules.md) §5.1 and decisions.md D199-D215.

**To see the news as chains**, open the **News Flow** tab at the top of the
editor, beside **2D**, **3D**, **Script** and **AssetLib**. It is the News Flow
Chart ([news-flow-chart.md](news-flow-chart.md)), and so far it only shows:
the chains, every line with a search box, each line's fields, and the
validator's news errors under **Problems**. Editing still happens in the
Inspector as described below. If the tab is missing, switch the plugin on:
**Project > Project Settings > Plugins**, tick **Enable** on the **News Flow
Chart** row. Then close and reopen the project.

#### Where each kind of line lives

| Kind | File | One line per |
|---|---|---|
| Market news (headline, event text, effect) | `src/data/news/market.tres`, the `market_news` list | **last year's** mood and index move band |
| Company news (IN THE NEWS) | `src/data/news/companies.tres` for the ported events; the general ones in `market.tres`; the `company_news` list | the company's own price move band |
| Whisper | `src/data/news/market.tres`, the `whispers` list | outcome it foretells, for a company or for an industry; or a squeeze or a crash |
| Industry headline (FROM THE HEADLINES) | `src/data/news/<industry>.tres` (`energy.tres` and so on), the `industry_reports` list | move band |
| The short squeeze's words | `src/data/squeeze/short_squeeze.tres`, `flavour_text` | (one line; `{company}` is the squeezed company) |
| NPC name and chatter | `src/data/traders/<trader>.tres`: `display_name` and `chatter_bought`, `chatter_sold`, `chatter_shorted`, `chatter_covered`, `chatter_held` | trader |

The game loads **every** `.tres` in `src/data/news/`, so a new file there (made as
below) is picked up too, and a line can sit in any of them. Its own fields say what
it is about, not the file it is in.

#### Rewrite a placeholder in a text editor (the quickest way)

A `.tres` file is plain text. Each line is a block like this:

```
[sub_resource type="Resource" id="Resource_12cwi"]
script = ExtResource("4_qenhj")
id = &"ind_energy_down_1"
industry_id = &"energy"
move = 2
text = "INDUSTRY REPORT: energy, down"
```

1. Close the Godot editor if it is open (it can overwrite a file you changed
   outside it).
2. Open the file in any text editor (Notepad, VS Code).
3. Find the placeholder, for example search for `energy, down`.
4. Replace only what is between the quotes after `text =`. Keep the quotes. To put
   a `"` inside the text, write `\"`.
5. Save the file.
6. Run the tests (§4 of this file). `test_news.gd` and `test_content_library.gd`
   fail with a message naming anything wrong.

Leave every other line alone. In particular, **never change an `id`** to reword a
line: the id is how the game remembers which lines it has shown this match.

**Deleting a line by hand?** Add its id to `src/data/news_retired_ids.txt`, on a
line of its own, so it is never given to a new line. The tests refuse a line whose
id is on that list (decisions.md D223).

**Tokens.** Some lines may contain words in braces, which the game fills in:

| Token | Becomes | Allowed in |
|---|---|---|
| `{company}` | the company's name | market news event text (its target company), company news, company, squeeze and crash whispers, chatter (the company the trader picked) |
| `{industry}` | the industry's name (for a company line, the company's industry) | industry headlines, company news, whispers |
| `{trader}` | the trader's name | chatter |

A token a kind of line does not fill (or a misspelt one, like `{compnay}`) is an
error the tests report.

#### Rewrite a placeholder in the Godot editor

Godot can edit the same files through its Inspector, which shows the conditions as
named choices instead of numbers.

1. Open the project in the Godot editor.
2. In the **FileSystem** panel (bottom left), open `src` > `data` > `news`.
3. Double-click `market.tres`. The **Inspector** panel (right) shows its lists:
   **Market News**, **Industry Reports**, **Company News**, **Whispers**, **Chatter**.
4. Click a list's name, for example **Market News**, to open it. It shows its
   entries, numbered from 0.
5. Click an entry's box (it reads **MarketNews**) to open it. Its fields show:
   **Id**, **Mood**, **Move**, **Headline**, **Text**, **Target Company**,
   **Target Industry**, **Amount**, **Requires**.
6. Click in **Headline** (market news) or **Text** (every other kind) and type the
   new words.
7. At the top of the Inspector, click the floppy-disk icon, then click **Save** in
   the menu that opens.
8. Run the tests.

#### Add a new line

More lines for one slot means it repeats less: the game shows every line that fits a
slot once before showing any of them again.

**In a text editor**, copy an existing block in the same file, including its
`[sub_resource ...]` header, and paste it below. Then:

1. Change the header's `id="..."` to something not used anywhere else in the file,
   for example `Resource_energy_down_2`.
2. Change `id = &"..."` to a new id used by no other news line anywhere, for example
   `&"ind_energy_down_2"`.
3. Change `text`.
4. At the bottom of the file, find the list the block belongs to (for example
   `industry_reports = Array[...]([SubResource("..."), ...])`) and add
   `, SubResource("Resource_energy_down_2")` before its closing `])`. A block that
   is not in a list is ignored.
5. Save and run the tests.

**In the Godot editor:**

1. Open the file and the list as above.
2. At the bottom of the list, click **+ Add Element**. A new empty entry appears.
3. Click the new entry's **<empty>** box and pick **New MarketNews** (or
   whichever kind the list holds) from the menu.
4. Click the new entry to open it, and fill in **Id**, the conditions and **Text**.
5. Save as above, and run the tests.

#### The conditions, and what the numbers in a file mean

A condition left out of a block means **ANY**: the line fits whatever that
condition is. In the Inspector they are named; in the text they are numbers:

| Field | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| `mood` | ANY | BULL | BEAR | | | |
| `move` | ANY | CRASH | DOWN | FLAT | UP | SURGE |
| `regime` | ANY | GROWTH | STEADY | SLOWING | DECLINE | DISTRESS |
| `surprise` | ANY | MUCH_WORSE | WORSE | AS_EXPECTED | BETTER | MUCH_BETTER |

`outcome` (whispers) uses the `surprise` numbers above, but never 0: a whisper
must foretell something. `about` (whispers): 0 COMPANY, 1 INDUSTRY, 2 SQUEEZE,
3 CRASH; a squeeze or crash whisper has no `outcome`. `outlook` and `last_move`
(the industry report) use the `move` numbers.

#### Market news: the headline, the event text and the effect

A market news line is what the top strip and THIS YEAR'S NEWS show, once a year.

- **`headline`**: the line itself.
- **`text`**: optional words under it. May use `{company}` for its target company.
- **`target_company` or `target_industry`**: what it moves, if anything - a company
  id (`stryker`) or an industry id (`energy`), never both.
- **`amount`**: coins added to the price (negative to take off). An industry target
  gives this **same** amount to every living member. An amount needs a target.
  Leave the amount 0 for a line that only says something.
- **`mood` and `move`** are about **last year**: a BEAR, CRASH line comes up the year
  after the market crashed.

A line aimed at a company that has gone bankrupt is not drawn.

#### Follow-ups: `requires`

Every kind of line has a **`requires`** list: ids of other news lines, of any kind.
The line can only be shown once every one of them has been shown in an **earlier
year**. When it can be, and has not been shown yet, it is chosen ahead of every
other line that fits, so a follow-up comes the first year it can. After that it is
an ordinary line.

In a text editor, a block that requires two lines has:

```
requires = Array[StringName]([&"mkt_bear_crash_1", &"whisp_squeeze_1"])
```

In the Inspector: open the entry, click **Requires**, click **+ Add Element**, and
type the id. The tests report an id that is not a news line, a line that
requires itself, and lines that wait for each other in a loop (A requires B, B
requires A), since none of them could ever be shown.

`situation` (chatter): 0 BOUGHT, 1 SOLD, 2 SHORTED, 3 COVERED, 4 HELD.
`strategy` (chatter): 0 VALUE, 1 MOMENTUM, 2 CONTRARIAN, 3 INCOME, 4 INDEXER,
5 PANIC, 6 GROWTH, 7 SHORT.

**Lines for one thing beat general ones.** An industry headline with an
`industry_id`, company news with a `company_id`, and a trader's own chatter are
preferred over lines that leave that field empty. So the shipped general company
news (`IN THE NEWS: {company}, ...`) covers every company, and a line written for
one company replaces it for that company, in the years it fits.

#### Whispers

A whisper is a rumor about **next year**, heard at the end of this one. The game
already knows next year's earnings (it draws them a year early), works out how a
company or industry will really do against what everyone expects, then lets a
**source** - Rock Solid down to Gossip - bend that, and shows a line written for
whatever the source told. So:

- **Write each line as if it were certain.** How far to trust it is the source's
  job, and the game shows the source beside the line.
- **`outcome` is what the line means**, not what it says. "The CEO has been at the
  golf course more than the board room" is a WORSE line; "the sales team all have
  new Mercedes" is a BETTER one. Write as many lines for each of the five outcomes as
  you like; more means fewer repeats.
- **`about`** says whether the line is about a company (`{company}`, and `{industry}`
  for its industry) or about an industry (`{industry}` only), such as a rumor of new
  regulation.
- Leave **`subject`** empty for a line that fits any company (or any industry). Set
  it to one company's or industry's id for a line that only fits that one; it is
  then used for that subject in preference to the general lines.
- Every combination of `about` and `outcome` needs at least one general line, or a
  whisper that comes up there is not heard; the tests check the shipped set has
  them.

#### NPC names and chatter

Each trader is one file in `src/data/traders/`, for example `value_1.tres`.

1. Open it in a text editor (or double-click it in the Godot editor's FileSystem
   panel and use the Inspector).
2. Replace `display_name` with the trader's name.
3. Replace each `chatter_...` line with what it says after that action. A line left
   empty (`""`) shows nothing.
4. Save and run the tests.

Never change `id`, `strategy`, `starting_cash` or `conviction` to rename a trader:
those decide how it trades, and changing them changes the balance.

A chatter line for **every trader of a strategy** can also go in a news book's
`chatter` list, with `npc_id` left empty and `strategy` and `situation` set. A
trader's own line, when it has one, is preferred.

#### Add a news file

1. In the Godot editor's **FileSystem** panel, right-click the `news` folder and
   click **Create New** > **Resource...**.
2. In the window that opens, type `NewsBook` in the search box, click
   **NewsBook**, then click **Create**.
3. Type a file name ending `.tres`, for example `extra.tres`, and click **Save**.
4. Add lines to its lists as in "Add a new line".

#### Add a company, an industry or a trader

Each is one file. Copy an existing one in `src/data/companies/`,
`src/data/industries/` or `src/data/traders/`, rename it, and give it a new `id`
(and a company a new `ticker`). An industry needs at least two companies and the
validator warns below three (design §3.2.3); a company's `industry` must be an
industry's `id`. A company's numbers are balance, not words: change them only with
the balance tool (§6, "Measure StalkleHeads balance"). Every file a match loads is
listed in `EarningsMarket.content_key`, so every player in an online match needs the
same set.

### Add a test

1. Put it in `tests/unit/`, in the file matching the unit under test, named
   `test_<what_it_checks>`.
2. Extend `GutTest`.
3. Use `StalksFixture` for content and state, and `FixedPriceModelStub` when you need
   prices to hold still so you can isolate one rule.
4. **Seed every generator** via `StalksFixture.rng(seed)`. A test that depends on
   unseeded randomness is a bug (decisions.md D5).

Conventions and current coverage are in [testing.md](testing.md).

### Add a rule to the year pipeline

Rules go in `YearResolver.advance_year()`, in the correct position in the ordered
sequence. **The order is load-bearing** — see [game-rules.md §4.1](game-rules.md) and
the two order traps described there. Record the new step in `YearResult` so the UI and
the tests can see it happened.

### Change how prices move

Write a new `PriceModel` subclass rather than editing `RandomRangePriceModel`. That is
what the interface is for (decisions.md D6).

### Change a game rule

1. Update [game-rules.md](game-rules.md) first, including *why*.
2. Add an entry to [decisions.md](decisions.md) if it is a divergence or a reversal.
3. Change the code.
4. Add or update a test that pins the new behaviour.

### Measure StalkleHeads balance

The balance tool plays hundreds of seeded StalkleHeads matches with ten scripted
player strategies and prints how each did. Run it after any change to a StalkleHeads
number: a regime, a band, a multiple term, a company profile. What it measures, and
what it cannot, is in [testing.md](testing.md); how it is built is
[architecture.md §9](architecture.md).

From the project root:

```
<godot> --headless --path . --script res://tools/balance_report.gd
```

That is the default: 10-year matches, 400 seeds, every strategy, flow from the NPC
desk and the players, the short squeeze on. It plays the game's own StalkleHeads
year (`EarningsYearResolver`) and the game's own NPC desk, and takes about 15
seconds for 400 matches. To change
any of it, put a lone `--` after the script and the options after that. The `--` tells
Godot that what follows is for the script, not for the engine:

```
<godot> --headless --path . --script res://tools/balance_report.gd -- --years=25 --seeds=1000
```

| Option | Meaning | Default |
|---|---|---|
| `--years=N` | Match length in years | 10 |
| `--seeds=N` | How many matches to play | 400 |
| `--first-seed=N` | The first seed; the rest follow on from it | 0 |
| `--strategies=A,B,...` | Which strategies play, from `HOLD`, `LOWPE`, `HIGHPE`, `TREND`, `MOMENTUM`, `CONTRARIAN`, `INCOME`, `FOLLOW`, `RANDOM`, `BOND` | all ten |
| `--flow=MODE` | What feeds the price's flow term. `all`: the NPC desk's trades and the players', as in the game. `desk`: the desk's only, so the players never move the market. `none`: nothing; the desk still trades and `FOLLOW` still copies it, but no price moves because of its trading | `all` |

**Balance levers, for a sweep.** These change a published balance number for one run
only. The real values in `src/sim/` never change; when the owner adopts a setting,
it is changed there as an ordinary code change (decisions.md D150).

| Option | Meaning | Published value |
|---|---|---|
| `--premium=G,S,L,D,X` | The regime premiums in turns of multiple, GROWTH, STEADY, SLOWING, DECLINE, DISTRESS | `1.2,0,0.24,-0.6,-1.4` |
| `--premium-scale=F` | The published premiums all multiplied by F. 2.5 is the first draft's wider spread | 1 |
| `--growth-stay=N` | GROWTH's chance of staying GROWTH, in percent. The rest of its row is respread in proportion (D150) | 42 |
| `--ageing=N` | Points a year added to the regime roll in GROWTH and SLOWING | 10 |
| `--no-squeeze` | No short squeeze can fire (design §5.3) | squeeze on |
| `--squeeze-chance=N` | The chance of a squeeze in a year when a company's short interest is flagged, in percent. Still 0 when nothing is flagged | 25 |
| `--squeeze-size=N` | The squeeze's jump, in percent of the price for every point of short interest (capped at 150%) | 5 |
| `--short-target=T` | What the NPC desk's SHORT traders bet against: `highpe` (the highest P/E, the published rule) or `slowest` (the company whose earnings grew slowest, S4's first rule). The squeeze lands on that company | `highpe` |

The output's `levers:` line says what was overridden, and its last line, starting
`summary:`, has every figure a sweep compares on one line, for searching.

An unknown option prints the list above and exits with code 1.

**How long it takes**, measured on the original author's machine: about 15 seconds
for the default and six to ten minutes for 4,000 ten-year seeds. Several runs at
once share the processor, so four 4,000-seed runs side by side take longer each. Time grows
in step with years × seeds. The last line of the output says how long the run took.

**Reading the output.** The top lines are about the market: splits and bankruptcies
per match, the average yearly price move, how often a year was a bull year, and the
spread of closing prices. Then one row per strategy: its median and mean final net
worth, and its **win share**, the fraction of matches where it finished first (a tie
counts as a win for each). The last line names the leading strategy and compares its
win share with the 30% ceiling of property P4 (design §1). Two lines above the table
are about the NPC desk: how many short squeezes a match had and how often a company
was flagged, and which strategy the desk's richest trader followed at the end. The verdict only says
HOLDS or FAILS at 10 years, because P4 is defined for the default length only.

**The same seed always gives the same numbers.** If a change moves a figure, the
change did it.

## 6a. Playing a networked match yourself

Multiplayer needs two copies of the game running. **You do not need to export a
build for this** — the editor can launch several instances at once, and that is
the fastest loop by a wide margin.

In the Godot editor:

1. In the top menu bar, click **Debug**.
2. Choose **Customize Run Instances...** (on Godot versions before 4.2 this is
   **Run Multiple Instances** with a submenu instead).
3. Tick **Enable Multiple Instances** and set the number to **2**.
4. Click **OK**.
5. Press **F5** (or the play button, top right). Two windows open.

Then, in one window click **HOST LOCALLY**; in the other click **JOIN GAME** and
**JOIN** and **Join**. The address and port are pre-filled for the same machine,
so neither needs typing.

In a debug build the same is on the **DEV** panel in the top-left corner: **HOST**
in one window, **JOIN** in the others. To host StalkleHeads, click the button under
Port until it reads **StalkleHeads**, then **HOST** (decisions.md D194). Up to ten
windows can join one host.

### Skipping the menu with flags

Clicking through the menu in two windows gets old fast, so the game reads a few
command-line flags and goes straight into a match. In the **Customize Run
Instances** dialog each instance has its own arguments field:

- instance 1: `--host`
- instance 2: `--join`

Press **F5** and you are in a lobby with two players, nothing typed. The host is
named "Host" and the joiner "Guest" so the windows are told apart at a glance.

| Flag | Meaning |
|---|---|
| `--host` | Open a local lobby immediately |
| `--join` | Join `127.0.0.1` immediately |
| `--join=<address>` | Join a specific host |
| `--port=<n>` | Listen on, or connect to, this port (default 42420) |
| `--name=<name>` | Play under this name |
| `--seed=<n>` | Host with a fixed match seed, to reproduce a bug |
| `--ready` | Ready up as soon as the lobby is joined |
| `--autostart` | Host: start the match as soon as everybody is ready |
| `--game=stalkleheads` | Host a StalkleHeads match instead of the base game (decisions.md D192) |

They work from a terminal too, in either form:

```
<godot> --path . --host
```

```
<godot> --path . -- --join --name=Ada
```

`--autostart` with `--ready` on the other instance takes two windows from launch
to a running match with no input at all:

```
<godot> --path . --host --autostart --port=44701
```

```
<godot> --path . --join --ready --port=44701
```

Worth knowing about: this is how the "client didn't load anything" bug was found.
The suite could not reach it, because two `Main` instances cannot coexist in one
process, and reproducing it by hand meant clicking through two windows every
attempt. With these flags it is two commands and a log file.

A flag-launched host turns **loans on** and uses a ten-year match. That is
deliberately not the same as `GameSettings`' own defaults: these flags exist for
testing the game, and the loan panel is part of it.

If the auto-host or auto-join fails — a busy port, no host to connect to — the
game falls back to the menu with the reason on it rather than sitting on a blank
screen.

**These are debug-build only.** `LaunchArgs.from_command_line()` returns "show
the menu" in an exported release build, so a shipped game cannot be made to
auto-host by a stray argument. The parsing itself is pure and always works, which
is what makes it testable — see `tests/unit/test_launch_args.gd`.

### Without the editor

Run the project twice from a terminal, from the project root:

```
<godot> --path .
```

Use the **console** executable so you see `print` output. Running one instance
this way and one from the editor works too, which is handy when you want the
editor's debugger attached to only one side.

### Why not an exported build?

You can, but exporting needs the **export templates** for your exact Godot
version — a separate download of several hundred megabytes, matched to
4.7.2.stable. Worth doing when you want to test the real shipped artifact, and a
waste of time for everyday multiplayer work. See Phase 7 in
[porting-plan.md](porting-plan.md) for when export presets get set up properly.

### What the automated tests can and cannot cover

The suite runs a real host and client over real ENet in a single process, so the
handshake, the economy and the disconnect behaviour are all tested without any of
this (see [testing.md](testing.md)). What it cannot test is two *processes*:
`Main` uses the scene tree's single default `MultiplayerAPI`, so two `Main`
instances in one process overwrite each other's peer. Anything about the real
two-window experience has to be checked by hand, the way described above.

---

## 6b. Playing across two machines, without Steam

Direct connection is the **fast path for testing**, and it stays that way after
Steam exists. No accounts, no store, no second Steam install, and it is what
the automated suite uses. Save Steam for testing Steam.

On the machine that will host, find the address to give out:

```
<godot> --headless --script res://tools/lan_check.gd
```

It prints the best candidate and the alternatives. More than one is normal: a
developer machine is usually on several networks and most of them are virtual.
On the machine this was written on, Godot reported nine addresses and the real
one was eighth — WSL, Hyper-V and VirtualBox all offer plausible-looking
addresses no other computer can reach.

Then:

1. On the host machine: **CREATE GAME** — **HOST LOCALLY**. The lobby names the
   address, which is the same one the tool printed.
2. On the other machine: **JOIN**, type that address, **Join**.

The port is 42420 on both by default. The host listens on every network
interface, so there is nothing to configure beyond the address.

If they cannot see each other, it is nearly always the wrong address of the
several, or Windows Firewall quietly refusing — see
[exporting.md section 5](exporting.md).

Running a build rather than the editor on the far machine is covered in
[exporting.md](exporting.md), but note you do not need one: Godot and a copy of
the project work just as well for testing gameplay.

---

## 7. Conventions

Full detail in [../CLAUDE.md](../CLAUDE.md). The ones that bite most often:

- **Everything is typed.** Untyped declarations are a *parse error*, not a warning.
  `var x := 5` (inferred) is fine; `var x = 5` will not load.
- **All money is `int`.** Never a float for cash, prices, dividends or balances.
- **Randomness is injected**, never global `randi()`. `Array.shuffle()` is banned in
  `src/sim` for the same reason.
- **`snake_case`** files and functions, **`PascalCase`** classes and nodes,
  **`CONSTANT_CASE`** constants, **past-tense** signal names (`year_advanced`, not
  `advance_year`).
- **Connect signals in code**, not in the editor's Signal panel, so connections appear
  in diffs.
- **Nodes never reach into parents or siblings.** They emit; listeners decide.
- **No per-node colour overrides.** Colours live in the shared `Theme`.

---

## 8. Committing

- Run the suite before committing. It takes two seconds.
- `.godot/` is generated and gitignored. Never commit it.
- The Steamworks SDK is **not redistributable** and must never be committed, even to
  a private repository. `.gitignore` already blocks the usual paths.
- `.uid` files next to scripts are generated by Godot 4.4+ and *should* be committed —
  they keep resource references stable.
- Opening the project in the editor rewrites `project.godot`: it reorders keys and
  **deletes any comments you put in it**. That is Godot tidying its own file, not a
  problem — but it means **`project.godot` cannot hold documentation**. Reasoning for
  a setting belongs in [decisions.md](decisions.md), which is exactly why
  `untyped_declaration=2` is explained there (D18) and not in a comment beside the
  setting. The same applies to `export_presets.cfg`.
- A phase is not complete until its documentation is updated (decisions.md D20). The
  checklist is in `CLAUDE.md`.

---

## 9. Troubleshooting

**"Tests fail immediately" / "GUT doesn't know where to find the tests"**
You are probably missing `--path .` or running from the wrong directory. GUT reads
`.gutconfig.json` from the project root.

**Scripts fail to load with "has no static type"**
That is decisions.md D18 working as intended. Add the type annotation.

**No GUT tab in the editor**
*Project → Project Settings → Plugins* and tick *Gut*, then restart Godot. The plugin
is already enabled in `project.godot`, so this is rarely needed.

**Weird import errors, or classes not found**
Delete the `.godot/` folder and re-run `--headless --path . --import`. It is a cache
and is safe to discard.

**`godot` not recognised**
It is not on PATH by design. Use the full path to the console executable, or set up
the alias in §2.

**A test passes locally but behaves oddly in the editor**
The editor's GUT panel and the CLI use the same runner, but the editor keeps scripts
loaded between runs. Restart the editor if results look stale.

---

## 10. Where the game writes its log

Godot writes a log file for an exported build, which is the quickest way to see
what a player's copy actually did. On Windows:

```
%APPDATA%\Godot\app_userdata\Stalks Stalks Stalks\logs\
```

`godot.log` is the current run. Older runs sit beside it with the date and time
in the name, five of them before the oldest is dropped. The folder is the
project's `user://` directory, so it is also where the settings file lives.

This is on by default for PC exports and nothing in `project.godot` changes it.
Editor and `--headless` runs write there too, which means **a test run will
push a real session's log out of the window** - copy a log worth keeping before
running the suite.

A build also prints to a terminal if it is started as
`StalksStalksStalks.console.exe` rather than the plain `.exe`, which is the
same distinction as the two Godot executables described above.
