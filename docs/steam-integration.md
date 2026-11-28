# Steam Integration

Phase 6. **Complete pending an upload.** Built, tested, and played by two Steam
accounts on two machines. What is left needs the port uploaded to a Steam
branch: see porting-plan.md Phase 6 and [publishing.md](publishing.md).

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

### What is built

- **`SteamService`** (`src/net/steam_service.gd`) — the only file that talks to
  the Steam API. Starts Steam, creates and joins lobbies, lists them, and
  reports Steam invites. Created on demand by `Main`, never an autoload, so a
  solo game and every test run never touch Steam at all.
- **`SteamTransport`** (`src/net/steam_transport.gd`) — turns a lobby into a
  `MultiplayerPeer`. Thin, because all the waiting happens before it exists.
- **Lobby lifetime.** Steam has no call to destroy a lobby: one exists until
  its last member leaves, and an owner who leaves is replaced automatically.
  The host therefore shuts its lobby (`setLobbyJoinable(false)` plus a `state`
  key the browser filters on) before leaving, and departures are reported to
  everyone else by `lobby_chat_update`. See decisions.md D68.
- **The online games list** (`src/ui/screens/online_games/`) — lists joinable
  games, hosts a new one, and survives Steam being absent by saying so.
- **Invites** go through Steam's own overlay dialog, and an invite accepted
  from a closed game arrives as `+connect_lobby` on the command line. Both end
  up in `Main.join_online_game`. See decisions.md D69.
- **Menu entry**: none of its own. Hosting online is a button on **Create
  Game** beside single player and local hosting, and the list of online games
  is reached from **Join Game**. Steam is a transport, not a thing a player
  sets out to do — see decisions.md D65.

Nothing in the economy, the RPCs, the authority checks, the redaction or the
lobby flow changed to accommodate any of it. That was the point of the
transport seam (D56), and it held.

### What is left

- **Two machines have never connected over Steam.** Everything below section 6
  was verified on one machine; peer-to-peer needs a second Steam account.
- Steam invites: `SteamService` emits `invited_to` when a friend's invite is
  accepted, but `Main` does not yet act on it.
- Achievements are catalogued (`src/data/achievements.gd`) but nothing unlocks
  them yet.
- Steam persona names are used for the local player; other players' names come
  from the lobby handshake as before.


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

### You do not need a `steam_appid.txt`

**Corrected 2026-11-16.** This section used to say one was required to run the
game outside the Steam client. It is not. `SteamService.start()` calls
`Steam.steamInitEx(APP_ID, ...)` with the App ID as an argument and the plugin
sets Steam's own environment variables from it, so the game identifies itself
at startup however it was launched. A release build was run on a second machine
with no such file present and joined a lobby normally.

The Unity original did need one, because Steamworks.NET's `SteamAPI_Init()`
takes no App ID and has to find one on disk. That is where the belief came
from.

A `steam_appid.txt` in the project root is still **harmless** and still
**gitignored**, and the export presets still exclude it: Valve's guidance is
that it should not ship, and a file that is never committed cannot be shipped
by accident. It is simply not something anybody has to create.

The Steamworks SDK beside it is a different matter: that one is genuinely not
redistributable and must never be committed anywhere.


### 3.2 Install the GodotSteam GDExtension

**This is the only step needed to make Steam work in the project.** You do
*not* need the Steamworks SDK for it — see 3.3.

1. Go to **codeberg.org/GodotSteam/GodotSteam/releases**.
2. Find the newest release whose title contains **GDExtension**. It looks like
   `Godot 4.4+ - Steamworks 1.65 - GodotSteam GDExtension 4.24`. Both flavours
   are in the list with nearly identical titles; the other one ("module")
   requires rebuilding Godot from source and is the wrong one.
3. Download the plugin zip, e.g. `godotsteam-4.24-gdextension-plugin-4.4.zip`.
4. Unzip it anywhere. It contains a single folder: `addons/godotsteam`.
5. Copy that **`godotsteam` folder** into this project's existing **`addons`**
   folder, so you end up with:
   `Stalks-Godot-Port/addons/godotsteam/godotsteam.gdextension`

   Your `addons` folder already contains `gut` (the test framework). You are
   adding alongside it, not replacing it — if Windows offers to "replace the
   folder", choose **merge** instead.
6. If the Godot editor is open, choose **Project** in the top menu bar, then
   **Reload Current Project**.

#### How to tell whether it worked

**A successful load prints nothing at all.** The Output panel stays quiet and
nothing new appears in Project Settings, so there is nothing to look for by
eye. That is normal and is not a sign of failure.

To actually check, run this from a terminal in the project root — the same way
the tests are run (see [development.md](development.md)):

```
<godot> --headless --script res://tools/steam_check.gd
```

It prints three lines. All three saying `true` means the extension is working:

```
Steam class registered: true
  steamInit available:  true
  SteamMultiplayerPeer: true
```

If the first line says `false`, the extension did not load. The usual cause is
the folder landing in the wrong place: check that
`addons/godotsteam/godotsteam.gdextension` exists at that exact path.

### 3.3 The Steamworks SDK — not needed yet

**You do not need to download the Steamworks SDK to develop or test.** The
GDExtension zip already contains Valve's redistributable libraries
(`addons/godotsteam/win64/steam_api64.dll` and the Linux/macOS equivalents),
and its `.gdextension` file lists them as its own dependencies.

The SDK is needed later, once there is a build to publish, for the SteamPipe
upload tools. That belongs with the export work in Phase 7.

⚠️ When that time comes: **the SDK is not redistributable.** It must never be
committed, even to a private repo.

### 3.4 Tell me when it is in

Paste the three lines from the check above. If anything says `false`, paste
whatever the command printed instead — a failure says as much as a success.


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

Both were checked against the backend on 2026-11-14 and the answer is
**`SSS_Win_One_Game`** and **`SSS_Lose_One_Game`** — `Title_Case`, against the
pattern of every other id. Guessing from the majority would have got both
wrong. The shouting variants are dead; do not reintroduce them.

`Achievements.UNCONFIRMED_CASING` is now empty, and a test keeps it that way:
anything added later whose casing has not been read off the backend belongs in
that list until somebody looks.

### Still worth confirming while you are in there

The four stat names the counters use: `sss_wins`, `sss_loses`,
`lifetime_networth`, `sss_yeehaws`. These are case-sensitive too, and unlike the
achievements they were never ambiguous in the source — so they are probably
right, and nothing has verified them.

---


## 5. What has actually been verified

On **2026-11-15**, on one machine with Steam running, by
`tools/steam_lobby_check.gd`:

- `steamInitEx` returns status 0 and the signed-in persona name
- `createLobby` returns a real lobby, owned by this user, with the `name` and
  `game` metadata the browser filters on
- `SteamTransport.open_server()` returns a `SteamMultiplayerPeer` with unique
  id 1, meaning a working server peer
- Leaving the lobby cleans up

**Not verified, and it needs you:** two machines, or two Steam accounts, in the
same lobby actually exchanging RPCs. Everything underneath that — the economy,
the authority checks, the per-player redaction, disconnect handling — is tested
over ENet in the ordinary suite and does not change with the transport. What is
unproven is specifically Steam's relay carrying the traffic between two
different users.

The GDExtension also loads cleanly in Godot **4.7.2**, confirmed by
`tools/steam_check.gd`. That closes the caveat in section 2: the "4.4 and up"
claim holds, and the `callable_mp.h` break really was module-only.

---

## 6. Done when

Two Steam accounts can find each other through the in-game browser **and**
through a Steam invite, play a full game, and unlock at least one achievement —
while single-player still runs with **Steam closed entirely**.

That last clause is not a nicety. The original could not run without Steam, and
fixing that is one of the stated goals of the port (decisions.md D14). Any
Steam code must be reachable only when a Steam match is actually requested.
