class_name NpcTraderDefinition
extends Resource
## One NPC trader of StalkleHeads mode, as authored content. Saved as a .tres in
## src/data/traders/. Adding a trader is adding a file.
##
## NPC traders are **not players**: they are not in the rankings, cannot win,
## are never in the ready gate, and exist to be watched. What they do during a
## match is `NpcTraderState`; how they decide is `NpcDesk`. See
## docs/stalkleheads-design.md §5 and decisions.md D162.
##
## **The names and chatter are the owner's to write.** Until they are, every one
## is a placeholder that says which slot it fills, in the style of the news
## placeholders (§8.3): `NPC NAME: value trader 1`,
## `NPC CHATTER: value trader 1, bought`. `NewsContent` turns the chatter
## into `NpcChatter` lines and `NewsSelector` chooses one a year (phase S8);
## it shows on the Company tab and the side panel's DESK page.


## What a trader did in a year, as the desk reports it (`NpcDeskYear.actions`).
## Each has one chatter line.
enum Situation {
	## Bought shares (it may also have sold others to do it).
	BOUGHT,
	## Sold what it held and bought nothing back.
	SOLD,
	## Opened or enlarged a short position.
	SHORTED,
	## Bought back some or all of a short position, opening nothing larger.
	COVERED,
	## Traded nothing.
	HELD,
}


## Stable key, unique across traders. Traders act in this key's sorted order,
## which is part of what makes the desk deterministic (§5.4).
@export var id: StringName = &""

@export var display_name: String = ""

@export var strategy: NpcStrategy.Value = NpcStrategy.Value.VALUE

## What it starts the match with. Its own, not a player's starting cash.
@export var starting_cash: int = 8000

## 0-100. The share of its cash it commits to a decision, before the year's
## appetite draw scales it (`NpcDesk`).
@export_range(0, 100) var conviction: int = 45

@export_multiline var chatter_bought: String = ""
@export_multiline var chatter_sold: String = ""
@export_multiline var chatter_shorted: String = ""
@export_multiline var chatter_covered: String = ""
@export_multiline var chatter_held: String = ""


## The chatter line for what it did. Empty when none is written, which §8.2
## says shows nothing rather than a generic line.
func chatter_for(situation: Situation) -> String:
	match situation:
		Situation.BOUGHT:
			return chatter_bought
		Situation.SOLD:
			return chatter_sold
		Situation.SHORTED:
			return chatter_shorted
		Situation.COVERED:
			return chatter_covered
		Situation.HELD:
			return chatter_held
	return ""


func _to_string() -> String:
	return "NpcTraderDefinition(%s, %s)" % [id, NpcStrategy.name_of(strategy)]
