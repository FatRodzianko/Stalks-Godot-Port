class_name YeehawRules
extends RefCounted
## Who may ask for a yeehaw, and who may give one. All static, all pure.
##
## A yeehaw has **no mechanical effect whatsoever** — no cash, no price, no
## standing changes. It is a social gesture, and the owner of the original game
## calls it a critical feature. See docs/game-rules.md 10.
##
## It still gets a rules file rather than an `if` in the session, for the same
## reason every other action has one: the authority and the UI's pre-check must
## call the *same* function, so a greyed-out button can never disagree with what
## the host would have allowed. See docs/architecture.md 5.1.
##
## **One request is pending at a time.** While somebody is asking, nobody else
## may ask — their button is offering to *give* instead. That is the original's
## design and it is what makes a single button work for both jobs.
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
	# Players who are *here*, not players in the match. An away player still has
	# a position and a place in the standings (D110), but nobody is at their
	# keyboard to answer, so a lone survivor asking a roomful of absentees would
	# be offered a gesture that can never come back.
	if state.players_present().size() < MIN_PLAYERS:
		return "Yeehaws need other players."
	if state.is_yeehaw_pending():
		var asker: PlayerState = state.player_by_id(state.yeehaw_requested_by)
		if asker == null:
			return "Somebody is already asking for one."
		return "%s is already asking for one." % asker.display_name
	return ""


## Why `giver_id` cannot give a yeehaw right now.
##
## There is no receiver argument: a yeehaw is given to whoever is currently
## asking. That is the original's shape, and it means a client cannot nominate
## who receives one at all — combined with the giver coming from the sender's
## peer id, neither end of the gesture is forgeable.
static func validate_give(giver_id: StringName, state: GameState) -> String:
	if state.is_over:
		return "The game is over."
	if state.player_by_id(giver_id) == null:
		return "Unknown player."
	if not state.is_yeehaw_pending():
		return "Nobody is asking for a yeehaw."
	if giver_id == state.yeehaw_requested_by:
		return "You cannot give yourself a yeehaw."
	return ""
