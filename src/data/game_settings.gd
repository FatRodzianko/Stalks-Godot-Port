class_name GameSettings
extends Resource
## Everything chosen before a match starts.
##
## The original called these "lobby settings", since every game ran through a Steam
## lobby. The port calls them game settings because it must support true
## single-player with no Steam involved at all.
##
## See docs/game-rules.md §2.


## What the host calls this match. Shown as the lobby's heading on every
## machine in it, and as the row in the online games list.
##
## A setting rather than lobby metadata because it has to reach the clients,
## and the settings already do: they travel with the opening snapshot. Steam
## lobby data would only reach somebody browsing, not somebody already in.
##
## Blank means "name it after the host", which `Main` fills in when the match
## is created, so by the time anybody sees this it always says something.
@export var game_name: String = ""

## Whether an online game is reachable only by invitation. Steam-only and
## meaningless offline — see docs/game-rules.md §2. An invite-only lobby is
## created `k_ELobbyTypePrivate`, which the in-game browser never lists.
@export var invite_only: bool = false

@export var starting_cash: int = 10000

@export_range(2, 99) var max_years: int = 10

@export_range(1, 10) var player_count: int = 1

@export var loans_enabled: bool = false

## Seed for the match RNG. Recorded as part of match state so any game can be
## replayed exactly — the basis of every determinism test. 0 means "choose one at
## match start and write it back here".
@export var rng_seed: int = 0

@export_group("Market Odds")

## Relative weights for the yearly mood. The original is 7 bull to 5 bear,
## i.e. 58.3% bull — see docs/game-rules.md §4.2.
@export var bull_weight: int = 7
@export var bear_weight: int = 5

## Chance in 100 that a stalk moves *against* the year's mood. The original rolls
## a 10-sided value and takes the top face, so 10%.
@export_range(0, 100) var contrarian_chance_percent: int = 10

@export_group("Long Game Softening")
## Price swings are damped in longer games so prices do not run away. Applied only
## to the normal move, never to a contrarian one. Undocumented in the original's
## write-up but present in its code — see docs/game-rules.md §4.4.

@export var soften_major_above_years: int = 49
@export var soften_major_bear: float = 0.45
@export var soften_major_bull: float = 0.50

@export var soften_minor_above_years: int = 19
@export var soften_minor_bear: float = 0.70
@export var soften_minor_bull: float = 0.80


## Returns the multiplier to apply to a normal yearly change, given this match's
## length and the year's mood. 1.0 means no softening.
func softening_multiplier(mood: MarketMood.Value) -> float:
	var is_bear: bool = mood == MarketMood.Value.BEAR
	if max_years > soften_major_above_years:
		return soften_major_bear if is_bear else soften_major_bull
	if max_years > soften_minor_above_years:
		return soften_minor_bear if is_bear else soften_minor_bull
	return 1.0
