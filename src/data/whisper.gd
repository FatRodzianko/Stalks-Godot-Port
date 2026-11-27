class_name Whisper
extends Resource
## One whisper line: a rumor about a company or an industry, heard at the end
## of a year and **about the next one** (docs/stalkleheads-design.md §8.4,
## decisions.md D205). Lives in a `NewsBook` in src/data/news/.
##
## **What a line means is its `outcome`**: how next year's earnings will
## compare with what everyone expects - much worse, worse, as expected, better
## or much better. The words need not mention earnings at all ("the CEO has
## been at the golf course more than the board room" is a WORSE line). The
## selector picks a company or industry, works out its real outcome from next
## year's kept draws, lets a **source** (Rock Solid to Gossip) bend it, and then
## draws a line written for the outcome the source tells. So a line is always
## said with conviction; how far to trust it is the source's.
##
## **The words are the owner's.** Until written, `text` is a placeholder that
## names its slot - `WHISPER: {company}, much better` (§8.3).


## Unique across every news line. Never shown.
@export var id: StringName = &""

## Whether this line is about a company or an industry.
@export var about: NewsBands.Subject = NewsBands.Subject.COMPANY

## A company id (an industry id, when `about` is INDUSTRY) this line may only
## be said of. Empty: whichever one the selector picks. A line for one subject
## is preferred over a general one when that subject comes up.
@export var subject: StringName = &""

## The outcome this line foretells. Never ANY: a rumor that means nothing is
## not a rumor.
@export var outcome: NewsBands.Surprise = NewsBands.Surprise.AS_EXPECTED

## A company line may contain `{company}` and `{industry}` (its industry); an
## industry line only `{industry}`.
@export_multiline var text: String = ""

## Ids of news lines, of any kind, that must have been shown in an earlier
## year before this one can be (decisions.md D210).
@export var requires: Array[StringName] = []
