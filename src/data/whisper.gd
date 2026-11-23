class_name Whisper
extends Resource
## One whisper: a rumor about a company or an industry, shown on the Market
## tab, and on the Company tab of the company it names. At most
## `NewsSelector.WHISPERS_PER_YEAR` a year (docs/stalkleheads-design.md §8.1).
## Lives in a `NewsBook` in src/data/news/.
##
## **A whisper is not always true, and that is the point.** It is in play when
## its trigger holds for something this year. Then a roll against
## `truth_chance_percent` decides: honest, and it names something the trigger
## holds for; or a lie, and it names something the trigger does *not* hold
## for. So at 75, three whispers in four are true and the player learns to
## weigh them. A whisper whose `subject` is set can only name that subject, so
## it cannot lie: when its roll says lie, it is not shown (decisions.md D201).
##
## **The words are the owner's.** Until written, `text` is a placeholder that
## names its slot - `WHISPER: {company}, high short interest` (§8.3).


## Unique across every news line. Never shown.
@export var id: StringName = &""

## A company id (or, for SECTOR_RUN, an industry id) this whisper may only be
## about. Empty: any company (or industry) the selector picks.
@export var subject: StringName = &""

@export var trigger: NewsBands.Trigger = NewsBands.Trigger.HIGH_SHORT_INTEREST

## 0-100. The chance it is honest when it is in play.
@export_range(0, 100) var truth_chance_percent: int = 75

## May contain `{company}` and `{industry}`; a SECTOR_RUN whisper only
## `{industry}`.
@export_multiline var text: String = ""
