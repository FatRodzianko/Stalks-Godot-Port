# Exporting a build

How to produce a runnable `.exe` to copy to a second computer.

**You usually do not need this.** For testing gameplay, two instances on one
machine or two machines over a direct connection are far faster — see
[development.md §6a and §6b](development.md). Export when you want to test the
*shipped artifact*: Steam with a second account, or what a player actually gets.

---

## 1. One-time: install the export templates

**Already done on the author's machine** (2026-11-15, 4.7.2.stable). This
section is for a fresh machine.

Godot cannot export anything until it has the templates for its exact version.
They are a separate **1.28 GB** download and are strictly version-matched —
4.7.2 templates for a 4.7.2 editor, no exceptions.

**From the editor:**

1. Open the project in the Godot editor.
2. Top menu bar — **Editor** — **Manage Export Templates...**
3. If it says "Templates installed: No", click **Download and Install**.
4. Wait. It is a large download and the editor will look frozen.

**From a terminal**, if you would rather see progress:

```
Invoke-WebRequest -Uri "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz" -OutFile "$env:TEMP\godot-templates.tpz"
```

```
Expand-Archive -Path "$env:TEMP\godot-templates.tpz" -DestinationPath "$env:TEMP\godot-templates" -Force
```

```
Copy-Item "$env:TEMP\godot-templates\templates\*" "$env:APPDATA\Godot\export_templates\4.7.2.stable\" -Recurse -Force
```

The `.tpz` is an ordinary zip whose `templates/` folder contents go into
`%APPDATA%\Godot\export_templates\<version>\`. The version must match the
`version.txt` inside the archive exactly, which is where the folder name comes
from. Delete the download afterwards; it is 1.28 GB and the installed copy is
all that matters.


## 2. What an export preset is

**A preset is a saved recipe for making a build.** Which platform, where to put
the file, what to call it, what to leave out. Unity keeps the equivalent in its
Build Settings window; Godot calls each saved recipe a *preset* and lets you
have several — one for Windows, one for Linux, one for a demo version, and so
on.

A project with no presets cannot be built at all. That is what the export
dialog means when it says **"No presets found."**

### Where it lives

All of them are stored in one plain text file in the project folder:

```
Stalks-Godot-Port/export_presets.cfg
```

You never have to edit it by hand — the dialog writes it — but it is readable
if you are curious, and it is how the setting you click in the dialog actually
persists.

⚠️ **It is gitignored.** Presets are per-machine, so a fresh clone of this
project has none and the export dialog will be empty until somebody makes one.
That is normal, and section 2.3 is how.

### 2.1 Opening it

**Project → Export...** from the top menu bar.

The window has three parts:

- **Left:** the list of presets, with **Add...** above it.
- **Right:** every setting for whichever preset is selected.
- **Bottom:** the buttons that actually build — **Export Project...** is the
  one you want.

If the left list is empty, the right side is blank and the bottom buttons are
greyed out. Nothing is broken; there is just no recipe yet.

### 2.2 The preset this project uses

One, called **Windows Desktop**. The settings that were deliberately chosen,
rather than left at their defaults:

| Setting | Value | Why |
|---|---|---|
| **Export Path** | `../stalks-build/StalksStalksStalks.exe` | Where the build is written. Relative, and starting `../` means *the folder next to the project*, so builds never land inside the repository where they could be committed by accident. |
| **Resources → Filters to exclude** | `tools/*, steam_appid.txt` | Leaves the developer tools and the Steam App ID file out of the finished build. Valve's guidance is that the App ID file should not ship. |
| **Binary Format → Architecture** | `x86_64` | Ordinary 64-bit Windows. |
| **Debug → Export Console Wrapper** | on | Produces a second small `.console.exe` that prints output to a terminal. Useful when something goes wrong on another machine. |

Everything else is Godot's default and has not been thought about.

### 2.3 Making one yourself, from nothing

If the list is empty — a fresh clone, or a new platform:

1. **Project → Export...**
2. Click **Add...** at the top of the left-hand list.
3. Choose **Windows Desktop** from the menu that appears.
4. A preset called "Windows Desktop" appears in the list and its settings fill
   the right-hand side.
5. Find **Export Path** near the top right. Click the folder icon and choose
   where the build should go, or type `../stalks-build/StalksStalksStalks.exe`
   to match this project's convention.
6. Close the window. It saves by itself.

That is the whole thing. The other settings in the table above are refinements,
not requirements — a preset with nothing but a path will build.

### 2.4 Changing it later

Open the same dialog, click the preset, change the setting, close the window.
There is no Save button; it writes as you go.

To delete one, select it and click the dustbin icon above the list. To make a
variant — a release preset with different filters, say — select it and click
the copy icon next to the dustbin.

### 2.5 If the dialog is empty when you expect a preset

The dialog reads `export_presets.cfg` when the **project** opens, not when the
dialog opens. A preset file that appeared while the editor was already running
is invisible to it.

**Project → Reload Current Project**, then open the dialog again.

### What about the Steam plugin?

Nothing to do, and nothing to configure. A GDExtension declares its own
libraries per platform in `addons/godotsteam/godotsteam.gdextension`, and the
exporter copies the right ones next to the finished executable — including
`steam_api64.dll`.


## 3. Every time: export

Godot's equivalent of Unity's **File → Build Settings** is **Project →
Export...**. Use it.

1. Top menu bar → **Project** → **Export...**
2. In the left-hand list, click **Windows Desktop**.
3. Click **Export Project...** (bottom of the dialog).
4. Check the path in the file dialog. It should already be
   `stalks-build/StalksStalksStalks.exe`, beside the repository.
5. **Mind the "Export With Debug" checkbox** at the bottom of that file
   dialog. This is the one setting that matters:
   - **Ticked** → debug build. `--host`, `--join` and the other development
     flags work. **Use this for testing.**
   - **Unticked** → release build. Those flags are silently ignored,
     because `LaunchArgs` checks `OS.is_debug_build()`. A release build used
     for testing looks exactly like the flags not existing.
6. Click **Save**.

Next time it is three clicks: the dialog remembers the preset.

### "No presets found"

See [section 2.5](#25-if-the-dialog-is-empty-when-you-expect-a-preset) → **Project → Reload Current Project**.

### The command-line equivalent

Only worth knowing if you ever want to build without opening the editor:

```
& "C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-debug "Windows Desktop" "..\stalks-build\StalksStalksStalks.exe"
```

`--export-release` instead of `--export-debug` for a release build. The preset
name in quotes has to match the dialog exactly.


## 4. Copying to the second computer

Copy the **whole output folder**, not just the `.exe`. Alongside it Godot puts:

- `StalksStalksStalks.pck` — all the game's content. Without it the exe does
  nothing.
- `steam_api64.dll` — Valve's library, copied in by the GDExtension.

### If you want Steam to work on that machine

Add a **`steam_appid.txt`** next to the `.exe` containing exactly:

```
1821800
```

Without it, a build launched directly (rather than through Steam) cannot
initialise the Steam API. It is not committed to the repository — see
[steam-integration.md §3.1](steam-integration.md).

⚠️ **The second Steam account must be able to run the app.** Steam refuses to
initialise for an account that neither owns the game nor is listed as a
developer on it. If `steam_check` reports failure on the second machine and
Steam is definitely running, add that account to the app's developer group in
the Steamworks partner site.

### If you only want direct (non-Steam) play

Nothing else is needed. No `steam_appid.txt`, no Steam client, no accounts.
The build runs and Solo, Host and Join all work. That is the point of keeping
ENet (decisions.md D56).

---

## 5. What a build actually contains

Confirmed by exporting one on 2026-11-15:

```
StalksStalksStalks.exe                              103 MB   the game
StalksStalksStalks.console.exe                       72 KB   prints to a terminal
StalksStalksStalks.pck                              5.4 MB   all the content
libgodotsteam.windows.template_debug.x86_64.dll     4.3 MB   the GDExtension
steam_api64.dll                                     319 KB   Valve's library
```

The last two are copied in **automatically** DASH nothing in the preset mentions
them. The `.gdextension` file declares its libraries and dependencies per
platform, and the exporter follows that.

Run `StalksStalksStalks.console.exe` rather than the plain one when you want to
see output; it is a small wrapper around the same game.

**Verified on the exported debug build:** it runs, hosts, accepts a joining
client, and honours `--host` DASH the port really does get bound. That last check
matters because a *release* build would silently ignore the flag and show the
menu instead, which looks like the flag not existing rather than being
disabled.

---

## 6. Checking the build on the far machine

The two tools ship inside the `.pck`, so they are not runnable from an exported
build — they are editor-and-source tools. On the second machine, check by
playing:

1. Launch the build. The menu should appear.
2. **HOST** → **Open a lobby**. The lobby subtitle should name an address.
3. On the first machine, **JOIN**, type that address, and connect.

If the two machines cannot see each other, it is almost always one of:

- **The wrong address.** The host's machine may be on several networks. Run
  `tools/lan_check.gd` on the host (from source, not the build) to see every
  candidate in order.
- **Windows Firewall.** The first time a build listens on a port, Windows asks
  whether to allow it. If that prompt was dismissed, the rule is a "no". Check
  under Windows Defender Firewall → Allow an app.
- **Different ports.** Both ends default to 42420, but the field is editable.
