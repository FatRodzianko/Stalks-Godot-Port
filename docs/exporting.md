# Exporting a build

How to produce a runnable `.exe` to copy to a second computer.

**You usually do not need this.** For testing gameplay, two instances on one
machine or two machines over a direct connection are far faster — see
[development.md §6a and §6b](development.md). Export when you want to test the
*shipped artifact*: Steam with a second account, or what a player actually gets.

---

## 1. One-time: install the export templates

Godot cannot export anything until it has the templates for its exact version.
They are a separate download of roughly 1 GB and they are **version-matched** —
4.7.2 templates for a 4.7.2 editor, no exceptions.

1. Open the project in the Godot editor.
2. In the top menu bar, click **Editor**.
3. Click **Manage Export Templates...**
4. The dialog shows "Templates installed: No" if you have none. Click
   **Download and Install**.
5. Wait. It is a large download and the editor will look busy.
6. When it finishes the dialog shows the version. Close it.

If the download fails, the dialog offers mirrors, or you can fetch
`Godot_v4.7.2-stable_export_templates.tpz` from the Godot website and use
**Install from File** in the same dialog.

---

## 2. One-time: create the export preset

1. In the top menu bar, click **Project**.
2. Click **Export...**
3. Click **Add...** (top left of the dialog) and choose **Windows Desktop**.
4. In **Export Path** (right-hand panel, near the top), click the folder icon
   and choose a path **outside the repository** — for example
   `C:\Users\murph\Desktop\stalks-build\StalksStalksStalks.exe`.

   Outside, because `/build/` and `*.exe` are gitignored but a stray path is
   easy to get wrong, and a 100 MB binary committed by accident is annoying to
   remove from history.
5. Leave everything else at its defaults. Close the dialog.

The preset is saved to `export_presets.cfg`, which is **gitignored** — it holds
machine-specific paths, and signing credentials if you ever add them. Each
machine makes its own.

### What about the Steam plugin?

Nothing to do. A GDExtension declares its own libraries per platform in
`addons/godotsteam/godotsteam.gdextension`, and Godot copies the right ones
next to the executable automatically. That includes `steam_api64.dll`.

---

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

## 5. Checking the build on the far machine

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
