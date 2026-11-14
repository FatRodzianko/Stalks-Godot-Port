# Opening the Project in Godot

A first-time walkthrough. Written for someone who has not used Godot before.

**Honest expectation first:** there is almost nothing to *look at* yet. No menus, no
stalk board, no gameplay. Phase 1 built the economy, which has no appearance. What is
worth doing is seeing the project open, running the one placeholder screen, and
watching the 67 tests pass with a button click — that last one is the genuinely
satisfying part.

---

## 1. Open the project

1. Double-click the Godot **editor** executable — the one whose name does *not* end in
   `_console`. If you have not downloaded Godot yet, [development.md §2](development.md)
   explains where to get it and where to put it.

   (The `_console` version beside it is the command-line one, used for running tests.
   Either will open the editor; the console one just also opens a black terminal
   window alongside it.)
2. The **Project Manager** window opens, listing projects you have opened before.
3. Click **Import** (top-left area of the window).
4. Click **Browse**, navigate to wherever you cloned this repository, select the file
   **`project.godot`** in its top level, and click **Open**.
5. Click **Import & Edit**.

The editor opens. The first time, it spends a few seconds importing — the status bar
at the bottom shows progress. This is normal and only happens once.

> **Expect a git change afterwards.** Godot rewrites `project.godot` when it opens a
> project, usually just reordering lines or adding defaults. If `git status` shows
> `project.godot` as modified after this, that is Godot tidying its own file, not
> something breaking.

---

## 2. What you are looking at

The window is divided into docks. Four matter right now:

| Where | Dock | What it is |
|---|---|---|
| Bottom-left | **FileSystem** | The project's files. This is the file tree. |
| Left | **Scene** | The node tree of whichever scene is open. |
| Centre | **Viewport** / **Script** | Either the visual canvas or the code editor. Tabs at the top switch between **2D**, **3D**, **Script** and **AssetLib**. |
| Bottom | **Output / Debugger / GUT** | Tabs along the very bottom edge. |

In the **FileSystem** dock you should see:

```
addons/      GUT, the test framework
assets/      empty for now — art, audio, themes will live here
docs/        the written design: rules, architecture, plan, testing
src/         all the code
tests/       the test suite
```

Open `src` and you will find `data`, `sim`, `net`, `autoload` and `ui`. The `net`,
`autoload` and most of `ui` folders are empty on purpose — they are Phases 4 and 5.

---

## 3. Run the game (and see the placeholder)

1. Press **F5**, or click the **▶ play** button at the top-right of the window.
2. A small window opens showing three lines of text, centred:

```
STALKS STALKS STALKS
Godot 4.7.2-stable (official) — toolchain OK
Seeded RNG (seed 12345): 57, 48, 42, 21, 7
```

3. Close that window, or press **F8**.

That is the whole game right now. It is a deliberate throwaway called
`smoke_test.tscn` that proves four things work: the project loads, a script runs, a
scene displays, and a seeded random number generator produces the same five numbers
every single time. That last property is what makes a game built on randomness
testable, so it is worth proving on day one.

It gets deleted in Phase 4 when a real main menu replaces it.

---

## 4. Run the tests — the part worth seeing

This is where the work so far is actually visible.

1. Along the **very bottom edge** of the window, find the row of tabs:
   *Output*, *Debugger*, *Audio*, *Animation*, *Shader Editor*, **GUT**.
2. Click **GUT**. The panel opens. (If there is no GUT tab, see troubleshooting
   below.)
3. In the GUT panel, click **Run All**.

The panel fills with test names and ends with a summary:

```
Totals
------
Scripts               5
Tests                67
Passing Tests        67
Asserts           12641
Time              2.424s

---- All tests passed! ----
```

Those 67 tests are the real deliverable of Phase 1. They check things like: a stalk
at 153 splits to 77 and not 76; a stalk at exactly 150 does *not* split; BERRY BONDS
never moves across a 99-year game; dividends are paid on the *doubled* share count
after a split; and the same seed reproduces an entire 20-year match identically.

You can click any individual test file in the panel to run just that one.

### Troubleshooting the GUT tab

If there is no **GUT** tab at the bottom:

1. Menu bar → **Project** → **Project Settings…**
2. Click the **Plugins** tab along the top of that dialog.
3. Find **Gut** in the list and make sure its **Enable** checkbox is ticked.
4. Close the dialog, then close and reopen Godot. GUT needs a restart to appear.

The plugin is already enabled in `project.godot`, so this should not be necessary —
but Godot occasionally wants the restart.

---

## 5. Read the code, if you want to

The best single file to look at is the one that runs a game year.

1. In **FileSystem**, open `src` → `sim`.
2. Double-click **`year_resolver.gd`**.
3. The centre panel switches to the **Script** editor.

Scroll to `advance_year()`. It is the ten numbered steps of an end-of-year sequence,
in order, with a comment on each. Reading that function tells you how the game works
more directly than anything else in the project.

Two other short ones worth a look:

- `src/data/stalk_definition.gd` — what makes up a stalk. Short and readable.
- `src/sim/trade_rules.gd` — what counts as a legal buy or sell.

Every file has a comment block at the top saying what it is for and pointing at the
relevant section of `docs/game-rules.md`.

---

## 6. Things you do *not* need to do

- **Don't create scenes or nodes by hand.** Scenes get written as text files where
  the structure is simple, so they show up in git diffs. You will be given
  click-by-click steps when something genuinely needs doing by hand — mostly theme
  colours and fiddly layout, in Phase 4.
- **Don't worry about the 2D/3D viewport.** This game is entirely `Control` nodes
  (Godot's UI nodes). The 3D tab will never be used.
- **Don't install anything from AssetLib.** GUT is the only addon, and it is already
  in place at a version matched to Godot 4.7.

---

## Running the tests without the editor

For reference, the same suite from a terminal in the project folder, where `<godot>`
is the `_console` executable from [development.md §2](development.md):

```
<godot> --headless --path . -s res://addons/gut/gut_cmdln.gd
```

`--headless` means "no window". This is how the tests are run from the command line,
and what a build server would use later. See [testing.md](testing.md).
