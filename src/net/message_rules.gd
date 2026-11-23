class_name MessageRules
extends RefCounted
## What a private message between players may contain, and who it may go to.
##
## **Messages are not part of the game.** They are never in `GameState`, never
## touch the seeded random stream, and never travel in a snapshot. The host
## passes each one on to its one recipient and keeps nothing (decisions.md
## D192). These rules exist only so that text typed by one player cannot do
## anything on another player's screen except be read.
##
## **The text is plain, printable ASCII** (0x20 to 0x7E). That is every key on
## an ordinary keyboard, so `<(' ')>` and `:-)` and `\\server\share` all
## survive - as inert text. Everything else is changed before anybody sees it:
##
## - tab, newline and carriage return become a space, so a message is always
##   one paragraph and cannot push fake lines into the chat;
## - every other control character, and DEL, is removed;
## - anything beyond ASCII - accented letters, emoji, the bidirectional
##   overrides that can reverse how text reads, zero-width characters - becomes
##   `?`, so something visibly stood there but nothing can hide or reorder.
##
## The game's font (Terminus) draws ASCII and little else, so the line costs a
## reader nothing they could have seen anyway. Full reasoning and the threat
## list are in docs/architecture.md (Messages) and decisions.md D193.


## Longest message, in characters, after cleaning. Two lines of a half-width
## chat at the game's resolution is about 80; this allows a few sentences
## without letting one message fill the panel.
const MAX_LENGTH: int = 200

## What stands in for a character outside printable ASCII.
const REPLACEMENT: String = "?"

## Player ids are short ("p0" to "p9"). A recipient longer than this is not a
## player, and is refused before it is looked up.
const MAX_ID_LENGTH: int = 8

## The rate limit's window, in milliseconds.
const WINDOW_MSEC: int = 10000

## How many messages a player's own machine lets them send per window. The
## send box says so when they hit it.
const SEND_LIMIT: int = 5

## How many the host passes on per sender per window. **Looser than the send
## limit on purpose**: packets sent seconds apart can arrive together, and an
## honest client must never have a message silently dropped by the host. Only
## a client that has stopped obeying its own limit reaches this one.
const RELAY_LIMIT: int = 8


## `raw` made safe to show: trimmed, cut to MAX_LENGTH, every character outside
## printable ASCII replaced or removed (see the class notes). Empty means there
## was nothing left to send. Never longer than MAX_LENGTH; shorter when a
## removed control character fell inside the cut.
##
## Trimmed and cut **before** the character loop, so an enormous packet costs
## no more than a normal one.
static func clean(raw: String) -> String:
	var source: String = raw.strip_edges().substr(0, MAX_LENGTH)
	var kept: PackedStringArray = []
	for character: String in source:
		var code: int = character.unicode_at(0)
		if code >= 0x20 and code <= 0x7E:
			kept.append(character)
		elif code == 0x09 or code == 0x0A or code == 0x0D:
			kept.append(" ")
		elif code < 0x20 or code == 0x7F:
			continue
		else:
			kept.append(REPLACEMENT)
	return "".join(kept).strip_edges()


## Why the host will not pass a message from `sender_id` to `recipient_id`, or
## an empty string. `sender_id` is the host's own record of who sent it, never
## anything from the packet (D45).
##
## A message to yourself is a note and stays on your own machine, so one
## arriving at the host has nowhere to go.
static func why_not_relay(
	sender_id: StringName, recipient_id: StringName, state: GameState
) -> String:
	if state == null:
		return "No game in progress."
	if sender_id.is_empty() or state.player_by_id(sender_id) == null:
		return "Unknown sender."
	if recipient_id == sender_id:
		return "Notes to yourself are not sent."
	if state.player_by_id(recipient_id) == null:
		return "No such player."
	return ""
