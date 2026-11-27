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

## What is not covered

The GPL above does **not** grant rights to:

- **The name and branding.** "Stalks Stalks Stalks" and the Glacial Lake Studios
  logo (`assets/sprites/glacial_lake_studios.png`) are not licensed for use.
  A fork must use its own name.
- **The sound effects in `assets/audio/`.** Their origin is not yet recorded, so
  no license is granted for them. Treat them as all rights reserved.

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
