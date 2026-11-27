# Licensing

Copyright (C) 2026 FatRodzianko and contributors.

## The code

The source code of this project (everything under `src/`, `tests/`, `tools/`,
`project.godot`, and the documentation in `docs/`) is free software: you can
redistribute it and/or modify it under the terms of the **GNU General Public
License, version 3** or (at your option) any later version, as published by the
Free Software Foundation. The full text is in [`LICENSE`](LICENSE).

It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
PURPOSE. See the GNU General Public License for more details.

### Additional permission: Steamworks

Under section 7 of the GNU GPL version 3, the following additional permission
applies:

> If you modify this program, or any covered work, by linking or combining it
> with the Steamworks API libraries distributed by Valve Corporation (such as
> `steam_api.dll`, `steam_api64.dll`, `libsteam_api.so` and `libsteam_api.dylib`),
> or a modified version of them, containing parts covered by the terms of
> Valve's Steamworks SDK license, the licensors of this program grant you
> additional permission to convey the resulting work. Corresponding Source for a
> non-source form of such a combination shall not include the source code for
> the parts of the Steamworks libraries used, as long as that source code is not
> itself covered by this license.

**Why this exists.** The game talks to Steam through Valve's Steamworks library,
which is proprietary. Plain GPL would forbid anybody other than the copyright
holder from distributing a build that includes it. This permission allows it,
and allows nothing else: every part of this project stays under the GPL.

### Contributions

By submitting a contribution to this project, you agree that it is licensed
under the same terms as the code above: the GNU GPL version 3 or later,
**including** the Steamworks additional permission.

**Why this exists.** Contributed code belongs to its author. Without this
agreement a contribution would arrive under plain GPL, and the project could no
longer ship a Steam build containing it.

## What is not covered

The GPL above does **not** grant rights to:

- **The name and branding.** "Stalks Stalks Stalks" and the Glacial Lake Studios
  logo (`assets/sprites/glacial_lake_studios.png`) are not licensed for use.
  A fork must use its own name.
- **The sound effects in `assets/audio/`.** No license is granted for any of
  them by this project. Where a sound's source is known it is listed below,
  and its own terms apply; the rest have no recorded origin and should be
  treated as all rights reserved.

## Sound sources

| Files | Source | Terms |
|---|---|---|
| `wilhelm-scream-1.wav` to `-5.wav` | Cut from "S38-01 Man eaten by alligator; screams [Wilhelm screams]" by Craig Smith, https://freesound.org/people/craigsmith/sounds/675810/ — trimmed, faded and level-matched | Marked CC0 on Freesound. **Caveat:** the uploader describes it as an archival copy of Hollywood studio effects from the 1930s–60s, so the CC0 mark may not cover rights held by the original studio. |
| `scream-sonniss-female.wav` | "Female_Scream_005" from SoundBits, *Screams & Shouts 2 - Humans*, Sonniss GDC 2016 Game Audio Bundle — shortened to 1.3 s and level-matched | Sonniss #GameAudioGDC bundle license: royalty-free, no attribution required, may be distributed; may not be sold on its own. |
| `scream-sonniss-warrior.wav` | "Male Warrior 2 Scream, Battle, War, Cry, Fight, Shout 3" from 344 Audio, *Medieval Battle*, Sonniss GDC 2020 Game Audio Bundle — level-matched | As above. |
| `bull1`, `bull2`, `bear1`, `bear2`, `glass-shattering`, `yeehaw` (`.mp3`) | Carried over from the original game | Origin not recorded. |

## Third-party components

These are included in the repository under their own licenses, which are kept
beside them:

| Component | Location | License |
|---|---|---|
| GUT (test framework) | `addons/gut/` | MIT — `addons/gut/LICENSE.md` |
| GUT's bundled fonts | `addons/gut/fonts/` | SIL Open Font License — `addons/gut/fonts/OFL.txt` |
| GodotSteam | `addons/godotsteam/` | MIT — `addons/godotsteam/license.md` |
| Steamworks redistributable libraries | `addons/godotsteam/*/` | Valve's Steamworks SDK terms (proprietary; shipped as GodotSteam ships them) |
| Terminus font | `assets/fonts/` | SIL Open Font License — `assets/fonts/Terminus-OFL.txt` |

The Godot engine itself is not in this repository. It is MIT-licensed.
