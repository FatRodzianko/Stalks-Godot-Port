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

## 3. Run the game

1. Press **F5**, or click the **▶ play** button at the top-right of the window.
2. The **main menu** opens. Choose the number of years, your starting cash, whether
   loans are enabled, and optionally a seed. Press **Start**.
3. The playing screen appears: the market board on the left, your holdings and the
   standings on the right, cash and net worth along the top.
4. Close the window, or press **F8**.

**You can actually play it.** Type a number into a stalk's amount box and press
**Buy**; the position appears under *Your Stalks* and your cash drops. Press **Ready
for New Year** and the market moves — prices change, the year's mood appears as
*BULL!!!* or *bear...*, and a special event is announced if one fired. Keep going to
the end of year 10 and a winner is declared.

Things worth trying, because they are the parts most likely to be wrong:

- **Type an amount you cannot afford.** The Buy button should disable itself as you
  type, and hovering it should explain why. The original game failed silently here,
  so this is a deliberate fix.
- **Watch for a split.** When a price goes above 150 it halves and your shares
  double. The share count under *Your Stalks* should double in the same step.
- **Watch for a bankruptcy.** A stalk whose price hits zero shows **BANKRUPT!!!** and
  loses its buy control, and any shares you held in it are gone.

- **Take a loan.** From year 2 the button at the bottom-left opens the loan panel.
  Borrow, then skip a payment and watch the warnings escalate. You can always ready
  up with a payment outstanding — that is deliberate.
- **Note the seed.** It is in the top bar and on the result screen. Typing it into
  the menu replays the identical market, which is how to reproduce anything odd.

> The throwaway smoke-test screen from earlier phases has been deleted now that
> there is a real game to run.

### Not there yet

No sound, no pause menu during play, and a year advance changes the numbers without
any animation. Multiplayer and Steam are Phases 5 and 6. See
[porting-plan.md](porting-plan.md).

---

## 4. Run the tests — the part worth seeing

This is where the work so far is actually visible.

### 4a. One-time setup (you must do this once)

**The first time you open the GUT panel it does not know where the tests are**, and
clicking *Run All* gives you:

```
Cannot run tests, you have a configuration error:
*  You do not have any directories set.
Check your settings ----->
```

That is expected on a fresh machine, and it is not a problem with the project. The
repository's `.gutconfig.json` configures the **command-line** runner only; the
editor panel keeps its own separate settings, stored outside the repository in your
own Godot user folder. That is why this cannot be committed and has to be set once per
person, per machine.

To set it:

1. Along the **very bottom edge** of the window, find the row of tabs:
   *Output*, *Debugger*, *Audio*, *Animation*, *Shader Editor*, **GUT**.
2. Click **GUT**. The panel opens. (If there is no GUT tab at all, see troubleshooting
   below.)
3. Click the **Settings** button in the panel's own row of buttons (top-right area of
   the panel, next to *Output* and *Run Results*).
4. Scroll down the settings list to the **Test Directories** heading.
5. In the first directory row — labelled **`0`** — type:

   ```
   res://tests/unit
   ```

6. **Tick the checkbox at the end of that row.** This is the step that is easy to
   miss: typing the path only *lists* the directory, and the checkbox is what actually
   enables it. Without the tick you will get the same error again.
7. Optionally tick **Include Subdirs** just above the directory rows. Not required —
   all the tests are directly in `tests/unit`.

The setting is saved automatically and persists, so you only do this once.

### 4b. Run them

Click **Run All** in the GUT panel.

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

### Troubleshooting

**"You do not have any directories set"** — the one-time setup in §4a has not been
done, or the path was typed but its checkbox was not ticked. The tick is what enables
it.

**"Test directory res://… does not exist"** — a typo in the path. It is
`res://tests/unit`, with the `res://` prefix.

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

## 5a. Tuning the CRT effect

The effect's every knob is a `uniform` in `src/ui/crt_screen.gdshader`. The
editor shows them as sliders, and there are two ways to reach them: live, while
the game runs, which is how you decide what you want; and saved, which is how
you keep it.

### Live, while the game is running

Changes here show up instantly and are **lost when you close the game**. That
is the point — it is for finding the numbers, not for keeping them.

1. Press **F5** to run the game.
2. Go to **Settings** in the game and tick **CRT** if it is not already on.
3. Leave the game running and switch back to the editor window.
4. In the **Scene** dock (top left), click the **Remote** tab. It sits next to
   **Local** and only appears while the game is running.
5. You are now looking at the live scene tree. Click the triangle beside
   **Stage** to open it.
6. Click **Screen**.
7. In the **Inspector** (right-hand side), find **Material** near the top and
   click the arrow beside it to open it.
8. Click **Shader Parameters** to open that section.
9. You will see five groups: **Sampling**, **Tube Geometry**, **Colour Bleed**,
   **Scanlines** and **Beam Glow**.
10. Drag any slider and watch the running game change as you drag.
11. Write down the numbers you settle on.

If **Material** shows `<empty>`, the effect is switched off in the game — go
back to Settings and tick the box.

### Saving what you chose

1. Stop the game.
2. In the **FileSystem** dock (bottom left), open `src` ▸ `ui`.
3. Double-click **crt_screen.tres**.
4. The Inspector shows the same **Shader Parameters** groups.
5. Type your numbers in.
6. Press **Ctrl+S**.

That writes one line per changed value into `crt_screen.tres`, so the change
shows up in a diff. The numbers in the shader file stay as the fallback for
anything you have not overridden.

### What each knob does

| Knob | Does |
|---|---|
| **Edge softness** | How much the curve's displacement is smoothed. 0 gives hard stair-steps in straight lines; at 3 or more the text goes soft. 2 is the default and the reasoning is in decisions.md D96 |
| **Enlargement** | **Leave alone.** The game sets it from the window size and overwrites anything typed here |
| **Barrel curvature** | A divisor, so *larger is flatter*. 0 switches the bend off entirely |
| **Vignette width** | How far the darkening reaches in from the edges, in game pixels out of 640x360 |
| **Bleed amount** | How far colour runs rightwards from a bright edge. The single biggest cost to how readable text is |
| **Bleed falloff** | How far that run reaches, in game pixels |
| **Bleed luma keep** | 1 lets only the colour run and keeps edges sharp; 0 lets brightness smear too |
| **Scanline count** | Lines down the picture. 360 is one per row of the game's own image. Values above a third of the monitor's height are clamped |
| **Scanline strength** | How dark the gaps between lines are |
| **Line noise** / **speed** | How much the line brightness flickers, and how fast |
| **Glow threshold** | How bright something must be before it glows at all |
| **Glow strength** | How much it glows |
| **Glow radius** | How far the glow spreads, in game pixels |

**The effect reads as subtle because most of these are deliberately low.** The
ones worth raising first are **Scanline strength**, **Glow strength** and
**Bleed amount**, in that order. Raising **Bleed amount** is also the quickest
way to make text harder to read, which is why it was lowered in the first place
— see decisions.md D94.

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

## Running a one-off script

Some checks are not tests and do not belong in the suite. They live in `tools/`
and are run the same way, with `--script` instead of `-s`:

```
<godot> --headless --script res://tools/steam_check.gd
```

That one reports whether the Steam plugin is installed. You do not need to open
the editor, create anything, or know any GDScript to run it — it is a file that
already exists in the repository, and the command prints its answer to the
terminal.

**There is no "script console" in Godot.** If you are told to run something in
one, that instruction is wrong. A script is either attached to a node in a
scene, or run from the command line like the above.

### Why `tools/` and not `tests/`

A tool can legitimately fail — `steam_check.gd` reports "not installed" on a
checkout where nobody has installed the plugin, which is a correct answer, not
a broken build. Tests must pass everywhere, so anything with a legitimate
failure mode stays out of `tests/`.
