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


## 2. The export preset

**Present on the author's machine, but gitignored — a fresh clone has to make
its own.** It is three steps, below.

`export_presets.cfg` defines one preset, **Windows Desktop**, which:

- exports to `../stalks-build/StalksStalksStalks.exe` — a **relative** path, so
  it lands beside the repository on any machine rather than inside it. `/build/`
  and `*.exe` are gitignored, but keeping build output out of the repo entirely
  is simpler than trusting a pattern.
- excludes `tools/*` and `steam_appid.txt` from the packed content. The tools
  are editor-and-source utilities, and Valve's guidance is that the App ID file
  should not ship.
- targets x86_64 and enables the console wrapper, so a build run from a
  terminal prints its output.

### Making one on a fresh clone

1. Top menu bar — **Project** — **Export...**
2. **Add...** — **Windows Desktop**.
3. Set **Export Path** to `../stalks-build/StalksStalksStalks.exe`. Relative,
   so it lands beside the repository rather than inside it.

Defaults are fine for everything else. Optionally set **Resources — Filters to
exclude** to `tools/*, steam_appid.txt`, which is what the author's copy does.

To change any of it later: the same dialog, or edit the file directly — it is
plain text and reads clearly.

### Why it is not committed

`.gitignore` excludes it on the general principle that export configuration
carries local paths and signing credentials. Neither applies *yet* — the path
is relative and nothing is signed — so committing it would genuinely save a
successor these three steps.

It is left out because the moment signing is set up, the file starts carrying
credentials, and a file that was already committed is the easy one to forget
about. Three steps now beats a leaked certificate later. Revisit deliberately
if the balance changes.

### What about the Steam plugin?

Nothing to do. A GDExtension declares its own libraries per platform in
`addons/godotsteam/godotsteam.gdextension`, and Godot copies the right ones
next to the executable automatically. That includes `steam_api64.dll`.


## 3. Every time: export

**From the editor:** Project → Export... → select the preset → **Export
Project** → confirm the path.

**From the command line**, which is faster and repeatable:

```
& "C:\Users\murph\Desktop\dev-projects\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" "C:\Users\murph\Desktop\stalks-build\StalksStalksStalks.exe"
```

The preset name in quotes must match exactly what the dialog shows.

Use `--export-debug` instead for a build that prints errors and allows the
`--host` / `--join` development flags. **`--export-release` disables those
flags**, because `LaunchArgs` checks `OS.is_debug_build()`
([steam-integration.md](steam-integration.md), D-numbered notes aside). For
testing on a second machine you almost always want **`--export-debug`**.

---

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
