class_name YeehawRules
extends RefCounted
## Who may ask for a yeehaw, and who may give one. All static, all pure.
##
## A yeehaw has **no mechanical effect whatsoever** — no cash, no price, no
## standing changes. It is a social gesture, and the owner of the original game
## calls it a critical feature. See docs/game-rules.md §10.
##
## It still gets a rules file rather than an `if` in the session, for the same
## reason every other action has one: the authority and the UI's pre-check must
## call the *same* function, so a greyed-out button can never disagree with what
## the host would have allowed. See docs/architecture.md §5.1.
##
## Validation returns an empty string for "allowed", or player-facing text saying
## why not.


## A yeehaw needs a giver and a receiver who are different people, so a solo game
## can neither ask for one nor give one.
const MIN_PLAYERS: int = 2


## Why `player_id` cannot ask for a yeehaw right now.
static func validate_request(player_id: StringName, state: GameState) -> String:
	if state.is_over:
		return "The game is over."
	if state.player_by_id(player_id) == null:
		return "Unknown player."
	if state.players.size() < MIN_PLAYERS:
		return "Yeehaws need other players."
	return ""


## Why `giver_id` cannot give a yeehaw to `receiver_id` right now.
##
## The self-yeehaw check is the whole reason this is server-side: a client could
## otherwise claim to have yeehawed itself, and the gesture only means anything
## because it came from somebody else.
static func validate_give(
	giver_id: StringName,
	receiver_id: StringName,
	state: GameState,
) -> String:
	if state.is_over:
		return "The game is over."
	if state.player_by_id(giver_id) == null or state.player_by_id(receiver_id) == null:
		return "Unknown player."
	if giver_id == receiver_id:
		return "You cannot give yourself a yeehaw."
	return ""
