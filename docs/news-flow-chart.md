# News Flow Chart — design and build plan

**Status: agreed with the owner on 2026-11-27. Phases 1-4 built (D223,
D224, D225, D230).** §6 records the owner's answers that shaped the design.

The News Flow Chart is an editor tool for writing StalkleHeads news as connected
chains. Take a market headline that leads to an industry headline, which in turn
leads to two pieces of company news. The tool draws the chains that the
`requires` lists already make (decisions.md D210). You can add, edit, connect and
delete news items in it, and it saves into the same `NewsBook` files in
`src/data/news/` that the game loads today.

It is a tool for **authoring** news. It changes nothing the game does at runtime.
The base game, the StalkleHeads rules and the golden history hash are all
untouched by it.

Read first: [development.md](development.md), "Writing StalkleHeads news" (how
news is written by hand today); [game-rules.md](game-rules.md) §5.1 (how a news
item is chosen); and decisions.md D199-D215.

**Words used here:**

- A **news item** is one entry in a news book: one market news, industry
  headline, company news, whisper or chatter line. The rest of the docs call it a
  "news line"; they mean the same thing.
- An **arrow** from A to B means "B requires A": B can only appear once A has
  appeared in an earlier year.
- A **chain** is a set of news items joined by arrows.
- A **root** is a news item in a chain that requires nothing. It is where the
  chain starts.

---

## 1. Is it feasible?

**Yes.** Everything the tool needs is part of stock Godot 4.7.2. Each piece below
was checked against 4.7.2 with a headless probe on 2026-11-27, rather than assumed
from documentation.

| Piece | What it is | Checked |
|---|---|---|
| `EditorPlugin` | A script that adds things to the Godot editor. It lives in `addons/<name>/` and is switched on in **Project > Project Settings > Plugins**. GUT is already one. | `add_dock`, `add_control_to_bottom_panel` and `add_inspector_plugin` exist |
| `GraphEdit` + `GraphNode` | Godot's built-in node-graph canvas: boxes with ports that you drag arrows between. The visual shader editor uses the same control. | `connect_node` makes an arrow. The `connection_request`, `disconnection_request`, `delete_nodes_request` and `node_selected` signals exist. `arrange_nodes` (automatic layout) exists. |
| `EditorInspectorPlugin` + `EditorProperty` | Changes how one field is drawn in Godot's ordinary Inspector. Here it turns a text box into a dropdown. | Both classes exist |
| `ResourceSaver.save` | Writes a `NewsBook` back to its `.tres` file. | The round-trip works. See finding 1 below. |

**Is there an existing tool?** None fits. The Asset Library has graph editors
([Custom Graph Editor](https://www.godotengine.org/asset-library/asset/4613),
[GodotStateGraphs](https://github.com/GMunozRodr/GodotStateGraphs),
[Resource Wrangler](https://www.godotengine.org/asset-library/asset/1994)). Each
of them either keeps the graph in a format of its own or links resources directly
to each other. Our news items link **by id string**, inside books that already
exist, and every edit has to pass the content validator. Adapting one of those
tools would mean rewriting the part that matters. It would also leave a
third-party dependency for a successor to keep working. Building directly on
`GraphEdit` is less code than either.

### 1.1 Findings that shape the design

1. **The first save rewrites a whole book.** Godot writes the blocks in a file in
   its own order. So the first save of `market.tres` through Godot produces about
   76 lines of diff without changing any content. A second save is byte-identical
   to the first, so this happens once per file. Phase 1 does it on purpose, in a
   commit of its own.
2. **Saving from a headless script drops each file's `uid` line.** Saving from
   inside the editor keeps it, and that includes the editor run headless
   (`<godot> --headless -e`), which is how Phase 1 re-saved the books. So the tool
   saves only from the editor. The headless tests save only to throwaway copies
   under `user://`, never to `src/data/news/`.
3. **The loader reads every `.tres` file in `src/data/news/` and refuses any that
   is not a `NewsBook`.** So anything else the tool writes, such as chain names,
   must live outside that folder.
4. **The validator does not catch a loop.** It refuses a news item that requires
   itself. It does not refuse A requires B while B requires A, although neither
   could ever appear. Phase 1 adds that check, which is useful with or without the
   tool.
5. **No shipped news item uses `requires` yet** (all eight books checked). So
   there are no existing chains for the tool to break.
6. **Inside the editor, every news item is a placeholder** (found in Phase 2,
   D224). A script that is not a `@tool` script does not run in the editor. An
   object loaded from a file with such a script keeps its fields, but calling any
   of its methods fails with "Attempt to call a method on a placeholder
   instance". All the data scripts in `src/data` are of this kind. So the tool
   reads news items only through their fields, and the content validator, which
   calls methods, runs in a headless Godot process of its own.

### 1.2 What it cannot do

- **Make a follow-up appear.** An arrow from A to B only means that B *may* appear
  once A has appeared in an earlier year. B's own conditions still have to match
  as well. For example, an industry headline set to DOWN waits until a year in
  which its industry falls. A news item with narrow conditions may wait years, or
  never appear at all in a 10-year match. Each box shows its item's conditions so
  you can see this, but the tool cannot promise that a chain plays out. This is
  how D210 works.
- **Edit the automated reports.** The EARNINGS line and the INDUSTRY REPORT are
  written by code (`ReportWriter`, D215). They are not content.
- **Edit a trader's own chatter.** Each trader's chatter is stored in that
  trader's file in `src/data/traders/`. It has generated ids
  (`<trader>_<situation>`) and no `requires` list. The chatter items in a news
  book are covered.
- **Stop edits made outside the tool.** A text editor can still put any value in
  any field. The dropdowns and the id rules protect you while you author in the
  tool. The validator and the tests remain the real check, as they are now.
- **Be tested headless in full.** See §5.

---

## 2. What it looks like

A new **News Flow** tab sits at the top of the editor, beside **2D**, **3D**,
**Script** and **AssetLib**. Godot calls this a "main screen" plugin. A chart
needs the width, and a side panel would be too narrow.

```
┌ News Flow ──────────────────────────────────────────────────────────────────┐
│ [+ New news item] [Arrange] [Rename chain]                                  │
│ ┌─────────────┐ ┌───────────────────────────────────┐ ┌──────────────────┐  │
│ │ CHAINS      │ │ ┌──────────────┐   ┌────────────┐ │ │ DETAILS          │  │
│ │ Oil crisis  │ │ │ MARKET       │──▶│ INDUSTRY   │ │ │ Id  mkt_bear_…   │  │
│ │ mkt_bull_…  │ │ │ bear · crash │   │ energy·down│ │ │ Mood [Bear ▾]    │  │
│ │ NEWS ITEMS  │ │ │ "If you're…" │─┐ └────────────┘ │ │ Move [Crash ▾]   │  │
│ │ [search…]   │ │ └──────────────┘ │ ┌────────────┐ │ │ Headline [....]  │  │
│ │ cnews_…     │ │                  └▶│ COMPANY …  │ │ │ Target [Energy▾] │  │
│ │ whisp_…     │ │                    └────────────┘ │ │ Amount [-5]      │  │
│ └─────────────┘ └───────────────────────────────────┘ └──────────────────┘  │
│ Problems: none                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **Left: chains and news items.** The left side lists every chain, and below it
  a searchable list of every news item. Dragging an item from the list onto the
  chart adds an existing item to it.
- **Middle: the chart.** Each news item is a box. The box shows the item's kind,
  its id, its conditions, and the first words of its headline or text. Those words
  are the owner's own; the tool never writes any.
- **Arrows.** Dragging from A's box to B's box draws an arrow, which adds A's id
  to B's `requires` list. Deleting the arrow removes the id again, and leaves
  every other arrow as it was. A box with two arrows coming in waits for
  **both**: B appears only after every item with an arrow into it has appeared.
- **Right: details.** Clicking a box shows **every field of that news item** in
  the details panel, and every field can be edited there. The company, industry,
  subject and trader fields are dropdowns. Anything Godot's Inspector can change
  about a news item, the tool can change too.
- **+ New news item.** The button asks which kind of item to make: market news,
  industry headline, company news, whisper or chatter. The details panel then
  opens with that kind's fields, and the item is created when you click
  **Create**. Its id is generated (§3.3), and it is saved into the right book
  (§3.5).
- **Delete.** Selecting a box and pressing **Delete** removes that news item. If
  it has any arrows, in or out, the tool first asks you to confirm, and names the
  items it is linked to. If you confirm, the item is deleted and its arrows are
  removed too. In A → B → C, deleting B removes B and both of its arrows, so A and
  C are no longer joined, and C becomes the start of a chain of its own.
- **Problems.** After every save, the strip at the bottom shows the content
  validator's messages about news. A mistake then shows up at once, rather than
  at the next test run.

---

## 3. Design decisions

### 3.1 Chains are worked out from `requires`, not stored

A chain is **not stored** anywhere. Every time the tab opens, the tool builds the
chart from the `requires` lists. Each news item becomes a box, and each id in a
`requires` list becomes an arrow.

Why:

- `requires` is already the one thing the game reads. A separate "tree file"
  would be a second copy of the same facts, and the two would drift apart. The
  first time one file said A leads to B and the other did not, which would be
  right?
- When `requires` is changed in a text editor, the chart shows the change with
  nothing else to update.
- The loader, the validator and a successor have no new file type to learn.

This rules out a chart that holds links of its own. It also rules out an item
belonging to two charts on purpose.

**Box positions are automatic.** When a chain opens, the tool lays its boxes out
from left to right with `GraphEdit.arrange_nodes`. The **Arrange** button does it
again. If you drag a box, it moves, but its position is not saved.

**A chain is named automatically, and can be renamed.** By default, a chain is
labelled with the id of its root, for example `mkt_bear_crash_1`. **Rename
chain** gives it a name of your own, such as "Oil crisis". Names are the one
thing the tool stores, in `src/data/news_chains.cfg`: a plain text file of
`root id = name`. The file sits beside `src/data/news/`, not inside it, so the
loader never reads it as a book. It holds names and nothing else, never arrows.

The name follows its root. Suppose you add an item in front of the old root, so
the old root now requires something. The tool moves the name to the new root.
Some chains have two roots, meaning two items that require nothing both lead
into it. The name is then kept under the root whose id comes first in
alphabetical order. If the root is deleted, its name moves to the next root if
there is one, and is dropped if there is not. A name whose root no longer exists
anywhere is reported in Problems, never silently kept.

### 3.2 Every kind of news item in a book

The tool can create, edit, link and delete all five kinds:

| Kind | Fields | Saved in |
|---|---|---|
| Market news | mood, move (both *last year's*), headline, text (optional), target company **or** target industry (or neither), amount | `market.tres` |
| Industry headline | industry (or any), mood, move, text | `<industry>.tres`; an any-industry item in `market.tres` |
| Company news | company (or any), move, text | `companies.tres` for a named company; an any-company item in `market.tres` |
| Whisper | about (company, industry, squeeze, crash), subject (or any), outcome, text | `market.tres` |
| Chatter (for every trader of a strategy) | trader (or none, for every trader of a strategy), strategy, situation, text | `market.tres` |

Every kind has a `requires` list, so any kind can sit anywhere in a chain. For
example, a whisper can lead to a market headline, or company news can follow a
whisper.

### 3.3 Ids: generated once, never reused

Every news item needs an id, and the tool writes it, so you never type one. Each
kind has its own pattern, which matches how the shipped ids are already written:

| Kind | Pattern | Example |
|---|---|---|
| Market news | `mkt_<mood>_<move>_<n>` | `mkt_bear_crash_3` |
| Industry headline | `ind_<industry or any>_<move>_<n>` | `ind_energy_down_2` |
| Company news | `cnews_<company or any>_<move>_<n>` | `cnews_stryker_surge_1` |
| Whisper | `whisp_<about>_<outcome>_<n>`; a squeeze or crash whisper `whisp_<squeeze or crash>_<n>` | `whisp_company_worse_2`, `whisp_squeeze_2` |
| Chatter | `chat_<strategy>_<situation>_<n>` | `chat_value_bought_1` |

`<mood>`, `<move>`, `<outcome>` and `<situation>` are the lower-case names of the
choice made (`any`, `bull`, `crash`, `much_worse`, `bought`, ...). Industry
headlines and company news are named for their subject instead of their mood,
for two reasons. The shipped ones are already named that way, and company news
has no mood. (Owner's answer, §6.)

**An id is fixed once created.** If the mood is changed later, the id keeps the
old word. It is a key, not a description, and development.md already says never
to change one. Changing an id would mean finding and rewriting every `requires`
list that names it. The cost is an id that can read wrong. The details panel
shows the id but does not let you edit it.

**An id is never reused.** `<n>` is one more than the highest number ever used
with that prefix, counting the live items **and** a list of retired ids. When the
tool deletes an item, its id goes into `src/data/news_retired_ids.txt`: a plain
list with one id per line, committed with the rest. Without that list, deleting
`mkt_bear_crash_3` and then creating a new item would produce a new
`mkt_bear_crash_3`. Any follow-up that still required the old item would then
silently follow the new one instead of being reported. The validator also gains a
check: a live id that appears on the retired list is an error.

An item deleted by hand in a text editor bypasses the list; that is the one gap.
The existing check still catches the dangerous half of it: a `requires` that
names an item which no longer exists.

**Nothing is ever overwritten.** Before saving, the tool checks the loaded
content in every book. It never writes an item whose id already exists.

**Existing ids that do not fit a pattern** are left as they are. This covers
`cnews_mafia_bear_1` and the other ported events. The generator only reads them,
to avoid collisions.

### 3.4 Dropdowns: an `EditorInspectorPlugin`, not `@export_enum`

The company, industry, subject and trader fields become dropdowns. Each dropdown
lists everything of that kind that exists, plus **(any)** wherever an empty value
means any. The same dropdowns appear in the tool's details panel and in Godot's
ordinary Inspector, whenever a news item is open there.

| Option | Verdict | Why |
|---|---|---|
| `@export_enum("mafia", "stryker", ...)` | **No** | The list would be typed into the script. Adding a company would then need a code change, against "adding a company is adding a file" (CLAUDE.md, D128). The list and the files would drift apart. |
| `_validate_property` on `MarketNews` and the others | **No** | It only runs in the editor if the data scripts become `@tool` scripts. The data scripts would then have to read `src/data/companies/` themselves, putting file loading into classes that are meant to be pure data. |
| `EditorInspectorPlugin` in the addon | **Yes** | It lives entirely in `addons/`. It reads the company, industry and trader files when a news item opens, so a new company appears with no code change. The data scripts are untouched. |

In both places, `requires` is shown as a picker of existing ids rather than a box
you type into.

**In the `.tres` file itself the value stays a plain string**, such as
`&"stryker"`. A file cannot hold a dropdown, so an edit in a text editor can
still type a wrong name. The validator already refuses one ("names company X,
which does not exist").

### 3.5 Staying inside the validator and the existing `.tres` layout

- **The tool edits the same `NewsBook` objects the editor already has open.**
  `load()` returns the editor's own cached copy. So the tool and the Inspector
  always agree, and saving from either one keeps the other's changes.
- **One tested function decides which book a new item goes into** (§3.2's
  table). The tool never creates a book file; it only uses the eight that exist.
  If the book an item needs is missing, the tool reports it instead of creating
  one.
- **After every save the tool runs the validator.** It calls
  `ContentLibrary.load_fundamentals` and shows the news errors. Only two checks
  are added to what counts as valid: no loops (§1.1), and no retired ids (§3.3).
- **Every edit can be undone.** The tool's edits go through Godot's undo system
  (**Edit > Undo**, or Ctrl+Z). So a wrong arrow or a deleted item can be taken
  back, provided the book has not been saved since.

### 3.6 Where the code lives

```
addons/news_flow_chart/
  plugin.cfg                  Godot's description of the plugin
  plugin.gd                   EditorPlugin: adds the tab and the inspector plugin
  core/                       pure logic, no editor classes, tested headless
    news_kind.gd              the five kinds: their list in a book, their name
    news_graph.gd             builds boxes and arrows from NewsContent; chains; loops
    news_id_maker.gd          the id patterns and numbering
    news_book_router.gd       which book a new item goes into
    news_book_editor.gd       add, edit, link, unlink and delete items; the retired list
    news_chain_names.gd       reads and writes news_chains.cfg; moves a name to a new root
    news_field_choices.gd     what each dropdown lists
    news_item_summary.gd      what a box and the details panel show (Phase 2)
    news_problems.gd          the Problems strip: runs the check, filters to news (Phase 2)
    news_layout.gd            Arrange, top to bottom as a tree; where a new box goes (D226, D227)
    news_edit_history.gd      undo and redo outside the editor, in the tests (Phase 4, D230)
  check/
    write_news_problems.gd    the validator, run headless in a process of its own (Phase 2)
  ui/                         Control scenes, testable in GUT's scene tree
    news_chart.tscn / .gd     the whole tab: lists, GraphEdit chart, details, Problems
    news_chart_canvas.gd      the GraphEdit; dots top and bottom, arrows with heads, Delete
    news_item_box.tscn / .gd  one GraphNode (box)
    details_panel.tscn / .gd  every field of the selected item
    delete_confirm.tscn / .gd the question asked before deleting an item with arrows (Phase 4)
  editor/                     needs the running editor; manual tests only
    id_dropdown_inspector.gd  EditorInspectorPlugin + EditorProperty (Phase 4)
```

The house rules carry over. Static typing is required. Signals are connected in
code to named methods. `tests/unit/test_conventions.gd` is widened to scan
`addons/news_flow_chart/` as well as `src/`.

Two things keep the plugin out of the exported game. The editor-only scripts take
no `class_name`, so they never enter the exported game's class list. And
`addons/news_flow_chart/*` goes into the export presets' exclude filter
(exporting.md).

---

## 4. Build phases

Every phase ends with the suite passing and the base game's golden hash
unchanged. Its documentation is updated, per CLAUDE.md's per-phase gate.

### Phase 0 — Spike (done for this document)

A probe of the 4.7.2 APIs and of save round-trips, described in §1. Nothing was
committed.

### Phase 1 — Groundwork, no UI — **done 2026-11-27** (D223)

**Delivered as planned**, with these details settled while building it:

- The loop finder is `NewsContent.requires_loops`, in `src/data`, because the
  validator lives there and must not depend on an addon. `NewsGraph.would_loop`
  is the tool's own check before an arrow is drawn.
- A sixth core script, `news_kind.gd`, holds what the others need to know about
  the five kinds.
- The retired ids are read by `ContentLibrary.read_retired_news_ids`. An exported
  game carries no `.txt` files, so there the list reads as empty, which only
  matters while news is being written.
- Chatter for one trader is named `chat_<trader id>_<situation>_<n>`, and chatter
  for every trader of a strategy `chat_<strategy>_<situation>_<n>`.
- The books were re-saved from a headless editor run, which keeps the `uid` lines
  (§1.1). Every field of every news item was compared before and after: equal.
- `test_conventions.gd` now scans `addons/news_flow_chart/` as well as `src/`.
- 31 new tests: 27 in `test_news_flow_chart.gd`, 4 in `test_news.gd`. The suite
  is 1,477, all passing, the golden history hash unmoved.

The plan as written:

- Validator: refuse a `requires` loop of any length, and refuse a live id that is
  on the retired list. Add `src/data/news_retired_ids.txt`, empty.
- The `core/` scripts: `news_graph.gd`, `news_id_maker.gd`,
  `news_book_router.gd`, `news_book_editor.gd`, `chain_names.gd` and
  `field_choices.gd`.
- A commit of its own that re-saves the eight books from the editor. The one-time
  reordering (§1.1) is then never mixed into later work.

**Tested by** GUT unit tests, all headless:

- Graph: built from a hand-made `NewsContent`; arrows, chains and roots are
  right, and a loop is found.
- Ids: every pattern for every kind; the next number; a retired id is not
  reused; no collision across kinds.
- Router: each kind and subject goes to its book.
- Book editor: add, edit, link, unlink and delete on books held in memory. Each
  is saved to `user://`, reloaded and passed through the validator. Deleting an
  item removes its id from every `requires` list and retires the id.
- Chain names: a name moves to a new root and survives a second root; a name
  whose root has gone is reported.
- Dropdowns: each lists what exists, plus (any) where it is allowed.
- Validator: regression tests for both new checks.
- The re-saved books load and validate exactly as before.

### Phase 2 — The chart, read-only — **done 2026-11-27** (D224)

**Delivered as planned**, with these details settled while building it:

- `plugin.gd` adds the **News Flow** tab. It is switched on in `project.godot`
  under `[editor_plugins]`, beside GUT. The tab reloads everything each time it
  is opened, so edits made elsewhere show up when you come back to it.
- `ui/news_chart.tscn` is the whole tab, not just the `GraphEdit`: the chain list,
  the searchable news item list, the chart, the details panel and the Problems
  strip. The chart shows **one chain at a time**. Choosing a chain shows it;
  choosing a news item from the list shows the chain it is in, or its box on its
  own, and selects its box. 161 boxes at once would be unreadable.
- Each box (`ui/news_item_box.tscn`) shows the kind as its title, then the id,
  the conditions (`Mood: Bear  ·  Move: Crash`) and the first eight words of the
  headline, or of the text when there is no headline. The words are the file's
  own (`NewsItemSummary`).
- The details panel (`ui/details_panel.tscn`) lists every field the item's
  script saves, in the script's order, as plain labels. Nothing in it can be
  edited.
- **The Problems strip comes from a separate Godot process** (finding 6). It
  checks the books as saved on disk, so an unsaved change in the Inspector does
  not show in it until it is saved. The chart itself shows unsaved changes,
  because it reads the editor's own copies.
- **The traders' own chatter is not on the chart** in the editor. It is built by
  calling a method on each trader, which a placeholder cannot run, and the tool
  does not edit it anyway (§1.2). An item that requires one shows that id in its
  details panel, with no arrow.
- Chain names that can no longer be placed are listed in Problems
  (`NewsChainNames.follow`), and nothing is written back.
- The UI scripts are `@tool`, so they run in the editor, and have a `class_name`,
  so the tests can use them as types. `plugin.gd` has none.
- **An arrowhead on every arrow.** `GraphEdit` draws a plain line, so the
  chart's `GraphEdit` has a script of its own, `ui/news_chart_canvas.gd`, that
  adds a head at the end that requires. Found in the first manual run.
- **Arrange** arranges every box, and shrinks each to its contents first.
  `GraphEdit`'s own arrange button, which arranges only the selected boxes, is
  hidden. Both were found in the first manual run.
- 19 new tests, in `test_news_flow_chart_ui.gd`.

The plan as written:

- The plugin and the **News Flow** tab: the chain list and the news item list;
  boxes and arrows drawn from `requires`; **Arrange**; automatic chain names;
  clicking a box shows its fields (read-only for now); the Problems strip.

**Tested by:**

- GUT scene-tree tests of `news_chart.tscn` outside the editor. `GraphEdit` is an
  ordinary Control, so this works headless. Given some content, the right boxes
  and arrows exist.
- **Manual** numbered steps for the plugin itself: switch it on; the tab appears;
  a chain opens; clicking a box shows its fields. These are
  [manual-testing.md](manual-testing.md) section Z.

### Phase 3 — Creating, editing and linking — **done 2026-11-27** (D225)

**Delivered as planned**, with these details settled while building it:

- **Changes are held in memory until Save.** The toolbar's status line names
  every book not yet saved ("Unsaved: market.tres"). **Save** writes them, and
  so do Ctrl+S and **Scene > Save All**. Closing the editor with changes unsaved
  asks first. Opening the tab again keeps unsaved changes.
- **The dropdowns' companies, industries and traders are read straight from
  their files** (`NewsFieldChoices.library_from_files`). In the editor they are
  placeholders, so `ContentLibrary.load_fundamentals` cannot supply them (D224).
- **An arrow can be drawn two ways:** drag from a dot of one box to a dot of
  another, or pick an id from **Add a requirement...** in the details panel. An
  end that is not on the chart is put on it. **An arrow is removed** by
  clicking it and pressing Delete, or with **Remove** beside the id in the
  details panel. (As first built, the dots were on the sides, drawing ran
  right dot to left dot, and an arrow was removed by dragging its head off.
  D227 changed all three.)
- **The chart shows a set of boxes, not always one whole chain.** Choosing a
  chain shows it; a created item, a dropped item and the far end of a new arrow
  are added beside what is there, and keep their places when other things
  change.
- **A new item is a draft until Create.** Its id reads "(given on Create)"; its
  requires list appears once it exists. Clicking any box drops the draft.
- Typing in a text field changes the item at once and updates its box, without
  redrawing the panel, so the text box keeps the cursor.
- 18 new tests in `test_news_flow_chart_ui.gd`, which now has 33.

**After the first manual run (D226):** chains read top to bottom, with
**Arrange** done by `core/news_layout.gd` and arrows drawn from the bottom of
one box into the top of the next. A right-click on empty chart makes a new
item there. A new box goes beside everything rather than on top of the first.
An item in the news item list opens when the mouse button is let go, so it can
be dragged onto the chart. Six more tests; the file has 39.

**After the second manual run (D227):** each box has its dots at the top and
bottom middle; an arrow can be drawn from either dot to either dot, or let go
anywhere on the other box, and the box pressed first is the one required.
**Arrange** lays a chain out as a tree. A clicked arrow is selected, and Delete
removes it. Adding an item to a book with none of its kind yet no longer fails
in the editor. Six more scene-tree tests (45) and one more core test (28).
Undo stays in Phase 4.

**After the third manual run (D228):** the line being dragged runs from the
dot pressed to the mouse on a scrolled chart too, and ends on the dot under the
mouse; a drag whose button release was lost ends when the mouse moves. Three
more tests; the file has 48.

**After the fourth manual run (D229):** a selected arrow is drawn orange. Section
AA passed on its fifth run, 2026-11-27, which completes Phase 3. The
file has 49 tests.

The plan as written:

- **+ New news item** for all five kinds.
- Every field editable in the details panel, with the dropdowns.
- Drawing and deleting arrows, which writes `requires`.
- Dragging an existing item onto the chart.
- **Rename chain**.
- Save; Problems refreshes.

**Tested by:**

- Scene-tree tests: a drawn arrow adds the id to `requires`; a deleted one
  removes it; an arrow that would make a loop is refused;
  each kind is created with the right id in the right book; editing a field in
  the panel changes that field and nothing else.
- **Manual** steps: build the owner's example chain, market news → industry
  headline and company news, then industry headline → two company news. Save,
  close the editor and reopen it, and check the chain is unchanged. These are
  [manual-testing.md](manual-testing.md) section AA. The suite is run by the
  person building the phase, not as a manual step: a check of the books is
  what the Problems strip already shows.

### Phase 4 — Delete, undo, dropdowns in the ordinary Inspector — **done 2026-11-27** (D230)

**Delivered as planned**, with these details settled while building it:

- **Delete:** select a box and press Delete, or click **Delete news item** in
  the details panel. The question (`ui/delete_confirm.tscn`) names every item
  the arrows join it to; an item with no arrows is deleted without one. One box
  at a time. The retired ids are written on Save.
- **Undo goes into the editor's own history** (`EditorUndoRedoManager`), so
  Ctrl+Z, Ctrl+Y and **Scene > Undo** take back every edit made in the tab:
  create, delete, a field, an arrow drawn or removed, a chain renamed. Each
  edit is recorded as a snapshot of the state before and after it. Ctrl+Z in a
  text box of the details panel undoes the typing in that box, as anywhere in
  Godot; click an empty part of the chart first to undo the field as one edit.
  Moving a box and Arrange are not edits. In the tests, where there is no
  editor, a history of the tab's own (`core/news_edit_history.gd`) stands in.
- **The Inspector** (`editor/id_dropdown_inspector.gd`) shows the company,
  industry, subject and trader dropdowns and the requires picker for any news
  item open in it. Its requires dropdown leaves out ids that would make a loop.
- **Found while building it:** an arrow selected earlier stayed selected when a
  box was clicked, so Delete would have removed it instead of the box. Clicking
  a box now clears it.
- 6 new core tests (`test_news_flow_chart.gd`, now 34) and 17 scene-tree tests
  (`test_news_flow_chart_ui.gd`, now 66). Undo in the editor and the Inspector
  dropdowns were also run once in a headless editor with a throwaway plugin.
  [manual-testing.md](manual-testing.md) section AB checks both by hand.

The plan as written:

- Delete, with the confirmation shown when the item has arrows. It removes the
  item and its arrows, and retires the id.
- Undo and redo for every edit made in the tool.
- The same dropdowns and the `requires` picker in Godot's ordinary Inspector.

**Tested by:**

- Headless tests: delete and the retired list; a confirmation is asked exactly
  when the item has arrows. Both are covered at the `core/` level, and in
  `delete_confirm.tscn` through the scene tree.
- **Manual** steps for undo and for the Inspector dropdowns. Both exist only in
  the running editor.

---

## 5. What can and cannot be tested automatically

| Part | Headless GUT | Why |
|---|---|---|
| `core/` (graph, ids, router, book edits, chain names, dropdown lists, new validator checks) | **Yes, fully** | It is pure `RefCounted` logic working on `NewsBook` objects. |
| `ui/` scenes (chart, boxes, details panel, delete confirmation) | **Yes, mostly** | `GraphEdit` and `GraphNode` are ordinary Controls and run in GUT's scene tree. A mouse drag is not simulated, but the signals a drag emits are. |
| `plugin.gd` (the tab appears; switching the plugin on and off) | **No: manual** | `EditorPlugin` and `EditorInterface` exist only inside the running editor, not in a `--headless --script` run. |
| The chart inside the editor, on placeholder items (finding 6) | **No: manual** | GUT runs the game's scripts for real, so a method call on an item would pass there and fail in the editor. The UI reads items through their fields only; that it works on placeholders was checked once with a throwaway plugin in a headless editor run, and is checked by hand in section Z. |
| The Problems check | **Yes** | A test runs the real headless check on the shipped books and expects no problems. |
| Inspector dropdowns | **The list yes, the display no** | What each dropdown contains is a tested function; that the Inspector shows it is checked by hand. |
| Undo and redo | **The snapshots yes, the editor's history no** | Every edit's snapshot, and undoing and redoing it, are tested through the tab's own history. `EditorUndoRedoManager`, and Ctrl+Z reaching it, belong to the running editor: section AB. |
| Saving with `uid` lines kept | **No: manual** | Headless saving drops them (§1.1). So a real save is checked by hand, then with `git diff`. |

The manual steps for each phase go into [manual-testing.md](manual-testing.md) as
numbered steps, one action per step.

---

## 6. The owner's answers (2026-11-27)

| Question | Answer |
|---|---|
| An item with two arrows coming in | It waits for **both**, which is how `requires` works today. No rule change. |
| Which kinds the tool makes | **All five**: market news, industry headlines, company news, whispers, chatter. Whispers link to the other kinds like any item. |
| Ids | Generated, and fixed once created. Industry headlines and company news are named by subject. §3.3. |
| Box positions | Automatic. |
| Chain names | Automatic (the root's id), and renamable. §3.1. |
| Where the tool sits | A tab at the top of the editor. |
| Editing | Every field of a news item can be edited inside the tool. |
| Deleting an item with arrows | Ask first, naming the linked items. If confirmed, delete it and remove its arrows. Deleting an arrow never touches any other arrow. |
