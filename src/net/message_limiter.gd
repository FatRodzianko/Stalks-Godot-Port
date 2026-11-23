class_name MessageLimiter
extends RefCounted
## At most `limit` messages per sender in any `window_msec` milliseconds.
##
## A sliding window: each sender's recent send times are kept, and a send is
## allowed while fewer than `limit` of them fall inside the window. The clock is
## passed in rather than read here, so a test can say exactly what time it is.
##
## Two of these exist in a networked match: one on each player's machine
## (MessageRules.SEND_LIMIT, which the send box reports) and one on the host
## for each sender (MessageRules.RELAY_LIMIT, which drops silently). See
## decisions.md D193.


var _limit: int
var _window_msec: int
var _sent_at: Dictionary[StringName, PackedInt64Array] = {}


func _init(limit: int, window_msec: int) -> void:
	_limit = limit
	_window_msec = window_msec


## Whether `sender_id` may send at `now_msec`. Counts the send if so.
func allow(sender_id: StringName, now_msec: int) -> bool:
	var recent: PackedInt64Array = PackedInt64Array()
	for sent: int in _sent_at.get(sender_id, PackedInt64Array()):
		if now_msec - sent < _window_msec:
			recent.append(sent)
	var allowed: bool = recent.size() < _limit
	if allowed:
		recent.append(now_msec)
	_sent_at[sender_id] = recent
	return allowed
