class_name MessageBook
extends RefCounted
## This machine's private messages: one conversation per other player, plus
## notes to yourself, and which conversations have unread lines.
##
## **Held only here, in memory.** Nothing in it is sent anywhere, saved to
## disk, or part of the match. Each player's machine keeps its own. A host
## migration hands this machine's book to its next session (D197); a player who
## rejoins starts with an empty one. That is a known limit, not a fault
## (decisions.md D192).
##
## A conversation is keyed by **the other player's id**: what you sent to Ann
## and what Ann sent you are one list, in order. Your notes are keyed by your
## own id, and the ALL PLAYERS room by `MessageRules.ALL_PLAYERS` (D195).
##
## **Blocking lives here, and only here** (D196). A blocked player's messages
## are dropped on arrival, in private chats and in the room alike. Nobody else
## is told - not the host, not the blocked player - so there is nothing to
## sync and nothing that could tell them. It lasts as long as the book.


## A line was added, a player was blocked or unblocked, or the book was
## cleared. Marking a conversation read does not fire it: that is the reader's
## own act, and the reader redraws.
signal changed


## Oldest lines are dropped beyond this, per conversation, so a long match
## cannot grow the book without bound.
const MAX_LINES: int = 200


## One line of a conversation: who wrote it, and what they wrote.
class Line:
	extends RefCounted
	var from_id: StringName
	var text: String

	func _init(writer_id: StringName, body: String) -> void:
		from_id = writer_id
		text = body


var _chats: Dictionary[StringName, Array] = {}
var _unread: Dictionary[StringName, int] = {}
var _blocked: Dictionary[StringName, bool] = {}


## Something this machine's player wrote to `recipient_id` - or a note, when
## `recipient_id` is `writer_id`. Never unread.
func record_sent(writer_id: StringName, recipient_id: StringName, text: String) -> void:
	_append(recipient_id, Line.new(writer_id, text))
	changed.emit()


## A message from `sender_id`, as it arrived: to this player alone, or to
## the ALL PLAYERS room when `in_room`. Cleaned again here: the host cleans
## first, and this is the second check before anything is shown. Dropped,
## without a trace, when the sender is blocked.
func record_received(sender_id: StringName, raw: String, in_room: bool = false) -> void:
	if is_blocked(sender_id):
		return
	var text: String = MessageRules.clean(raw)
	if text.is_empty():
		return
	var chat_id: StringName = sender_id
	if in_room:
		chat_id = MessageRules.ALL_PLAYERS
	_append(chat_id, Line.new(sender_id, text))
	_unread[chat_id] = _unread.get(chat_id, 0) + 1
	changed.emit()


## Blocks or unblocks `player_id`. Blocking also marks their chat read, so
## nothing from them is left lighting a dot. What they already said stays.
func set_blocked(player_id: StringName, blocked: bool) -> void:
	if blocked:
		_blocked[player_id] = true
		_unread.erase(player_id)
	else:
		_blocked.erase(player_id)
	changed.emit()


func is_blocked(player_id: StringName) -> bool:
	return _blocked.get(player_id, false)


## The conversation with `other_id`, oldest first.
func lines(other_id: StringName) -> Array[Line]:
	var found: Array[Line] = []
	found.assign(_chats.get(other_id, []))
	return found


## How many lines from `other_id` have not been seen.
func unread_from(other_id: StringName) -> int:
	return _unread.get(other_id, 0)


## Whether any conversation has an unread line.
func has_unread() -> bool:
	for other_id: StringName in _unread:
		if _unread[other_id] > 0:
			return true
	return false


## Marks the conversation with `other_id` as seen. Returns whether anything
## was unread.
func mark_read(other_id: StringName) -> bool:
	var had_unread: bool = _unread.get(other_id, 0) > 0
	_unread.erase(other_id)
	return had_unread


## Forgets everything. A rematch starts a new book, because its seats need not
## be the same people as the last match's.
func clear() -> void:
	_chats.clear()
	_unread.clear()
	_blocked.clear()
	changed.emit()


func _append(other_id: StringName, line: Line) -> void:
	if not _chats.has(other_id):
		_chats[other_id] = []
	var chat: Array = _chats[other_id]
	chat.append(line)
	while chat.size() > MAX_LINES:
		chat.pop_front()
