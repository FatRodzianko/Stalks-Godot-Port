class_name RematchNotice
extends RefCounted
## The one line that says where a rematch stands, for whichever screen is up.
##
## **Two screens show it and the rule lives here.** A player who has finished a
## match can be on the result screen or on the final board, and the news is the
## same either way: somebody has asked for another game, or the host has gone
## back to the lobby for one. Writing it twice would mean two places to keep in
## step, and the board would quietly fall behind — which is how the board came
## to be the one screen that did not notice a player rejoining (D120) and the
## one that did not notice the special event (D121).
##
## **Which half applies is decided by the side, not by a flag.** Only a host has
## anybody asking it for a game, and only a client is told that an offer exists,
## so the two branches cannot both answer. See docs/decisions.md D124.
##
## Pure and static: it reads the session and returns a sentence, so a test needs
## no screen.


## What to tell this player about a rematch, or an empty string when there is
## nothing to say.
static func for_session(session: GameSession) -> String:
	if session == null:
		return ""

	var asked: PackedStringArray = session.rematch_asked_for_by()
	if not asked.is_empty():
		return "%s asked for another game." % ", ".join(asked)

	if session.rematch_is_offered():
		return "Host has restarted the lobby"

	return ""
