# Steam Integration

Phase 6. **In progress** — the groundwork is built and tested; the parts that
need a Steamworks account and a download are waiting on the owner.

This document is the whole plan plus the setup instructions. Read it before
touching anything Steam-related.

---

## 1. The shape of the work

Steam is meant to be a **transport swap, not a rewrite**. That is the single
reason it was deferred to this late phase, and it is now a fact rather than an
aspiration:

```
GameSession            the UI talks to this, and to nothing below it
└── NetworkedSession   every @rpc, for both sides
    ├── HostSession    authority; takes a Transport, never builds one
    └── ClientSession  replica; takes a Transport, never builds one

Transport              abstract: "how is this match carried?"
├── EnetTransport      direct IP, works today, stays after Steam
└── SteamTransport     Phase 6, not yet written
```

`HostSession.host()` and `ClientSession.join()` take a `Transport` and hand back
a `MultiplayerPeer`. Nothing above that layer knows which kind it got — the
lobby does not even know whether to show a port or an invite, because it asks
the transport for a `joining_hint()` and prints it.

`tests/unit/test_transport.gd` keeps this honest by standing a host and a client
up on a transport that is deliberately **not** ENet. If somebody reaches for
`ENetMultiplayerPeer` inside a session again, those tests fail.

### What is left to write

A `SteamTransport` implementing three methods, plus a lobby browser screen.
Everything else — the economy, the RPCs, the authority checks, the redaction,
the lobby flow, the disconnect handling — is already built and tested over ENet
and does not change.

**ENet does not get removed.** A direct connection stays available for
development, for LAN play, and for anyone running the game outside Steam. It is
also how the automated tests run, since they cannot depend on a Steam client
being installed.

---

## 2. Which GodotSteam, and why

Checked 2026-11-14. **Verify before downloading** — this project moves fast.

| | |
|---|---|
| Latest GDExtension release | **v4.24-gde**, 2026-11-07 |
| Steamworks SDK it targets | **1.65** |
| Godot versions it claims | "Works on any Godot version 4.4 and up" |
| Canonical home | **Codeberg**, `codeberg.org/GodotSteam/GodotSteam` |

The GitHub repository is **archived**. Some release assets still link back to
GitHub, but releases are published on Codeberg. Do not follow an old GitHub
link and assume it is current.

### GDExtension, not the module build

GodotSteam ships in two flavours and picking the wrong one costs days:

- **Module** — compiled *into* a custom Godot engine binary. Releases are
  version-specific (the current one names "Godot 4.7.2 and 4.5.2 variants").
- **GDExtension** — a plugin dropped into the project, used with the stock
  Godot editor.

**Use the GDExtension.** The module means building Godot from source and
abandoning the stock 4.7.2 binary this project is pinned to, which is a large
burden for no benefit here.

### A correction to an earlier note in the plan

The porting plan said Phase 6 needed "a build targeting Godot 4.7 specifically —
the 4.7 header rename broke older builds", referring to Godot 4.7 renaming
`callable_method_pointer.h` to `callable_mp.h`.

That applies to the **module** build, which compiles against engine headers. A
GDExtension does not include engine headers; it binds through the stable
GDExtension ABI, which is why its releases say "4.4 and up" with no 4.7 caveat.

⚠️ This has **not been confirmed by running it**. The GodotSteam changelog pages
returned 403 when checked, so the claim rests on the release notes and on how
GDExtension works in general. Treat "the GDExtension loads cleanly in 4.7.2" as
the first thing to verify, not as established.

---

## 3. Setup — owner's steps

These need a Steamworks account and downloads, so they cannot be scripted.

### 3.1 App ID — decided

**App ID `1821800`** — the original's, reused. Owner's decision on 2026-11-14,
confirmed against `steam_appid.txt` in the Unity project. See decisions.md D57.

The store page, its reviews and every already-unlocked achievement carry over.
The consequence is that **the achievement ids are not ours to choose** (see 4).

For local development before any build is uploaded, App ID **480** (Spacewar,
Valve's public test app) works for lobbies and the overlay. Never ship with it.

### You need a local `steam_appid.txt`

Running the game outside the Steam client needs an App ID on disk. Create a file
called **`steam_appid.txt`** in the project root containing exactly:

```
1821800
```

It is **gitignored on purpose**, so every checkout makes its own. An App ID is
public, so this is not about secrecy — it is that Valve's own guidance is to
keep this file out of a shipped build, and a file that is never committed
cannot be shipped by accident. The export presets in Phase 7 should exclude it
as well, belt and braces.

The Steamworks SDK beside it is a different matter: that one is genuinely not
redistributable and must never be committed anywhere.


### 3.2 Get the Steamworks SDK

1. Go to **partner.steamgames.com** and sign in.
2. Download the **Steamworks SDK** matching the GodotSteam release (1.65 at the
   time of writing).
3. Keep the zip somewhere outside this repository for now.

⚠️ **The SDK is not redistributable.** It must never be committed, even to a
private repo. `.gitignore` already covers it; do not override that.

### 3.3 Install the GodotSteam GDExtension

1. Go to **codeberg.org/GodotSteam/GodotSteam/releases**.
2. Find the newest release whose title contains **GDExtension** — it looks like
   `Godot 4.4+ - Steamworks 1.65 - GodotSteam GDExtension 4.24`.
3. Download the plugin zip, e.g. `godotsteam-4.24-gdextension-plugin-4.4.zip`.
4. Unzip it into the **root of this project**, next to `project.godot`. The
   release notes say: *"Just drop the contents of this zip into the base of your
   project and that's it!"*
5. In the Godot editor, choose **Project → Reload Current Project**.
6. Open the **Output** panel at the bottom and check for load errors.

To confirm it loaded, open **Project → Project Settings → Globals** and look for
Steam entries, or run this in a test script: `print(ClassDB.class_exists("Steam"))`.

⚠️ Whether that zip includes the Steam API DLL is **unconfirmed** — the
GDExtension release notes do not say, while the module release notes explicitly
do. If Steam fails to initialise, copy `steam_api64.dll` from the SDK's
`redistributable_bin/win64/` to the project root.

### 3.4 Tell me when it is in

Once the extension loads, I can write `SteamTransport` and the lobby browser.
Paste the Output panel contents, working or not — the failure mode is as useful
as the success.

---

## 4. Achievements

All 25 ids and their trigger conditions live in **`src/data/achievements.gd`**,
read out of the original's source. [game-rules.md 13](game-rules.md) has the
same list in prose.

Because the App ID is reused, **the backend is the authority on these names** —
not this document, and not the original's source. A name that disagrees with the
backend does not error; the achievement simply never unlocks for anyone.

Steam's achievement API names are **case-sensitive**, and the original hedged:
it sets both `SSS_WIN_ONE_GAME` and `SSS_Win_One_Game`, and both
`SSS_LOSE_ONE_GAME` and `SSS_Lose_One_Game`.

- **Win is settled.** The original's only live call is
  `SetAchievement("SSS_Win_One_Game")`; the shouting version is commented out.
  So that is the spelling real players have actually unlocked, and therefore
  what the backend holds.
- **Lose is not.** Both spellings are set on consecutive lines, so one of them
  is a no-op and the source cannot say which.

### The one thing to check in the partner backend

Open the app's achievement list at **partner.steamgames.com** and read the API
name for "lose one game" exactly as written. If it is `SSS_Lose_One_Game`,
change `Achievements.LOSE_ONE` — nothing else needs to move, and
`tests/unit/test_achievements.gd` keeps the rest honest.

While you are there, confirm the four stat names the counters use: `sss_wins`,
`sss_loses`, `lifetime_networth`, `sss_yeehaws`.

---


## 5. Done when

Two Steam accounts can find each other through the in-game browser **and**
through a Steam invite, play a full game, and unlock at least one achievement —
while single-player still runs with **Steam closed entirely**.

That last clause is not a nicety. The original could not run without Steam, and
fixing that is one of the stated goals of the port (decisions.md D14). Any
Steam code must be reachable only when a Steam match is actually requested.
