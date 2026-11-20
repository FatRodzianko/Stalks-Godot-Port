# Documentation

Everything written down about **Stalks Stalks Stalks**, a port of a Unity
stock-trading game to Godot 4.7.

These documents are written to stand alone. You do not need the original Unity
project, access to anyone who worked on this, or an AI assistant to continue the
work. If you find a place where that is not true, that is a documentation bug worth
fixing.

---

## Start here

**New to the project?** Read in this order:

1. **[game-rules.md](game-rules.md)** — what the game actually is. Start here even if
   you only care about the code; the rules explain why the code is shaped as it is.
2. **[architecture.md](architecture.md)** — how the code is organised, and the one
   rule that everything else follows from.
3. **[decisions.md](decisions.md)** — *why* it is organised that way. Read this
   before changing anything structural, or you will undo a deliberate choice.
4. **[development.md](development.md)** — get the toolchain working and run the
   tests.
5. **[porting-plan.md](porting-plan.md)** — what is done, what is next.

**Planning the remaining work?** Read
**[original-game-audit.md](original-game-audit.md)**. It inventories the shipped
Unity game's functionality — not just its economy — and §17 is the list of things the
original did that the port does not yet. The scope of a port comes from the original
game, not from the rules document.

**Never used Godot before?** Read
**[godot-editor-guide.md](godot-editor-guide.md)** after step 4.

**Hit an unfamiliar word?** **[glossary.md](glossary.md)**.

---

## The documents

| Document | What it is | Read it when |
|---|---|---|
| [game-rules.md](game-rules.md) | The authoritative game specification. Every rule, every number, every formula, plus the bugs in the original and what was decided about them. | You need to know what the game does, or are implementing any rule |
| [original-game-audit.md](original-game-audit.md) | A functional inventory of the shipped Unity game — screens, controls, settings, lobby flow, feedback, failure modes — each marked ported, changed or missing, with the gap list in §17 | You are planning work, or need to know whether the port still does something the original did |
| [architecture.md](architecture.md) | The four layers, the simulation's internals, the year pipeline, the network design, and the determinism contract | You are writing or reading code |
| [decisions.md](decisions.md) | A dated log of every significant decision, with the reasoning and what it rules out | You are about to change something structural, or wondering "why on earth is it like this" |
| [development.md](development.md) | Toolchain setup on a fresh machine, the verification loop, how to add content, and project conventions | You are setting up, or doing the work |
| [exporting.md](exporting.md) | Export templates, presets, and getting a build onto a second computer | You need a runnable build rather than the editor |
| [publishing.md](publishing.md) | Uploading a release build to a Steam branch with SteamPipe, and the two tests that needs | You are putting a build on Steam |
| [steam-integration.md](steam-integration.md) | The Phase 6 plan, which GodotSteam build to use and why, and the owner's setup steps | You are working on Steam, or about to download anything for it |
| [manual-testing.md](manual-testing.md) | What a person has to check by hand, in order, with expected outcomes and failure signs | You are about to test a build, or two machines |
| [testing.md](testing.md) | How to run the suite, how it is organised, testing conventions, and current coverage | You are writing or running tests |
| [porting-plan.md](porting-plan.md) | The seven phases, what each delivers, and the pass/fail criteria for each | You want to know status, or what to do next |
| [godot-editor-guide.md](godot-editor-guide.md) | A first-time walkthrough of the Godot editor for this project, written for a complete beginner | You have never opened Godot |
| [glossary.md](glossary.md) | Domain and technical terms used throughout | Something is unexplained |
| [ui-reference.md](ui-reference.md) | The pixel grid, and the original's layout read from its scenes | You are building or changing a screen |

There is also **[../CLAUDE.md](../CLAUDE.md)** in the repository root. It holds the
coding standards and conventions. It is addressed to an AI assistant, but the
standards in it apply to anyone working on this project, so read it as a style guide
regardless of whether you use AI.

It may refer to a `CLAUDE.local.md` beside it. That file is **not committed** and you
are not missing anything by not having it: it holds one machine's paths and one
person's working preferences, never a rule about the code. Anything that turns out to
be a rule about the code belongs in `CLAUDE.md` where everyone can see it. See
decisions.md D95.

---

## How this documentation is maintained

A phase is not complete until its documentation is updated. The checklist is in
[../CLAUDE.md](../CLAUDE.md) under "Documentation", and
[porting-plan.md](porting-plan.md) repeats it as a gate on each phase.

The markdown in this folder is the **authoritative** copy — it versions with the code
and is what a successor will actually read. Visual code maps published as shareable
pages are useful summaries, but they are derived from these files, not the other way
round.

---

## Conventions used in these documents

- **`<godot>`** means the Godot 4.7.2 console executable. Where it comes from is in
  [development.md](development.md).
- Rules are cited by section, e.g. *game-rules.md §4.1*, so references stay valid as
  documents grow.
- **[OPEN]** marks something genuinely undecided. If you resolve one, replace it with
  the decision and add an entry to [decisions.md](decisions.md).
- Original Unity source files are sometimes cited (e.g. `StalkManager.cs`) to show
  where a value came from. **That project is not in this repository** and you do not
  need it — every extracted value is reproduced here. The citations exist so the
  provenance of a number is traceable, not because the source is a dependency.
