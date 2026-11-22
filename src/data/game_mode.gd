class_name GameMode
extends RefCounted
## Which game a match is: the base game, or StalkleHeads.
##
## Chosen before a match starts and never changed (docs/stalkleheads-design.md
## §9.4). It lives on `GameSettings.mode`, travels to clients with the rest of
## the settings in the snapshot, and is published to the Steam lobby so the
## browser row can show it.
##
## **What the mode changes is decided in one place, `MatchSetup`, at match
## start** — which board, which year pipeline, which settings it forces. Nothing
## during a match asks which mode it is in (design §10.2, decisions.md D171).


enum Value {
	## The faithful port. The default, so every match built without saying
	## otherwise — a test, a launch flag, an older snapshot — is the base game.
	BASE,
	## Prices from earnings, industries and the NPC desk
	## (docs/stalkleheads-design.md).
	STALKLEHEADS,
}


## Every mode, in the order the title screen offers them.
const ALL: Array[Value] = [Value.BASE, Value.STALKLEHEADS]

## The lobby-data string for each mode. **Strings, not numbers**, because
## Steam lobby data read back with `to_int()` answers 0 for a key that is not
## there, and 0 is `BASE`: a lobby from an older build would be labelled as the
## base game. A missing string is just empty, and the row leaves it out
## (design §9.4, decisions.md D88).
const LOBBY_BASE: String = "base"
const LOBBY_STALKLEHEADS: String = "stalkleheads"


## The mode's name as the title screen and the lobby browser show it. These are
## the two games' own names, not descriptions; change them here and both
## places follow.
static func label(mode: Value) -> String:
	match mode:
		Value.BASE:
			return "Stalks Stalks Stalks"
		Value.STALKLEHEADS:
			return "StalkleHeads"
	return ""


## What a lobby publishes for this mode.
static func lobby_value(mode: Value) -> String:
	match mode:
		Value.BASE:
			return LOBBY_BASE
		Value.STALKLEHEADS:
			return LOBBY_STALKLEHEADS
	return ""


## The label for a lobby's published value, or an empty string for a value
## this build does not know — absent, from an older build, or from a newer one.
static func label_for_lobby_value(value: String) -> String:
	for mode: Value in ALL:
		if lobby_value(mode) == value:
			return label(mode)
	return ""


## A mode from a number that came off the wire, or `BASE` for anything that is
## not a mode, so a damaged or older snapshot is the base game.
static func from_int(value: int) -> Value:
	for mode: Value in ALL:
		if int(mode) == value:
			return mode
	return Value.BASE
