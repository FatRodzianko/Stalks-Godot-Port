class_name NetworkedSession
extends GameSession
## The wire. Declares every RPC the game uses, for both sides, in one place.
##
## **Why both sides share one script.** Godot routes an RPC by node path and
## method name: a call made on the host's `Session` node runs the method of that
## name on the client's `Session` node. So the two ends must agree exactly on the
## set of remote methods and their modes. Declaring them once here, and having
## HostSession and ClientSession override ordinary (non-`@rpc`) handlers instead,
## makes that agreement structural rather than something to keep in step by hand.
## See docs/decisions.md D44.
##
## **The node must be named the same on both sides** for the same reason — hence
## NODE_NAME, which both factories apply. The spike that established this is
## recorded in docs/architecture.md §5.2.
##
## **Every client-to-host RPC is `any_peer` and carries no player id.** Who is
## acting is derived from the sender's peer id, which a client cannot forge. A
## client therefore has no way to even express "act as somebody else" — the
## strongest form of the authority check, because it removes the attack rather
## than validating against it. See docs/decisions.md D45.


## Both ends must mount the session node under this name. See the class docs.
const NODE_NAME: StringName = &"Session"

## Ten players maximum, so nine clients plus the host. See docs/game-rules.md §2.
const MAX_CLIENTS: int = 9


## The peer id that is always the host in Godot's multiplayer.
const HOST_PEER_ID: int = 1


# ------------------------------------------------------- client → host (requests)
#
# Mode is stated explicitly on every one of these, never left to a default.
# Economy traffic is `reliable`: losing a buy is not acceptable.

## Sent by a client immediately on connecting, carrying the name the player
## typed and, over Steam, the account it belongs to. The host assigns the slot.
##
## A slot is created when this arrives rather than when the socket connects, so
## that a player appears in the lobby already named instead of flickering through
## a placeholder.
##
## **`steam_id` is 0 for anyone not playing through Steam**, which is every
## direct connection. It is used for one thing — fetching an avatar for the
## lobby list (audit 17.7) — and no rule may branch on it.
##
## **The client states its own Steam ID rather than the host deriving it.** The
## host could ask the peer, but only when the transport happens to be Steam,
## and this has to work the same way over a direct connection where the answer
## is simply 0. A client could lie about it; the worst that buys is somebody
## else's avatar beside your name, which is not worth a round of validation.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_introduce(player_name: String, steam_id: int = 0) -> void:
	_on_introduced(_sender(), player_name, steam_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_buy(stalk_id: String, shares: int) -> void:
	_on_buy_requested(_sender(), StringName(stalk_id), shares)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_sell(stalk_id: String, shares: int) -> void:
	_on_sell_requested(_sender(), StringName(stalk_id), shares)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_take_loan(amount: int) -> void:
	_on_loan_requested(_sender(), amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_pay_loan(amount: int) -> void:
	_on_payment_requested(_sender(), amount)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(is_ready: bool) -> void:
	_on_ready_requested(_sender(), is_ready)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask_yeehaw() -> void:
	_on_yeehaw_asked(_sender())


## No arguments at all: the giver is the sender and the receiver is whoever is
## asking, so there is nothing for a client to put in this packet.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_give_yeehaw() -> void:
	_on_yeehaw_offered(_sender())


## "I would like another game." Advisory and nothing more: it puts the asker's
## name on the host's result screen and gates nothing. Only the host can start a
## rematch, because only the host can reopen the lobby.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_ask_for_rematch() -> void:
	_on_rematch_asked(_sender())


## "Put me in the rematch." Sent after the host has offered one.
##
## **Deliberately not a second `_rpc_introduce`.** Reusing that would get the
## seating and the Steam ID for free, but it carries a name — and the lobby is
## not a place to change your name (`HostSession._on_introduced`). After the
## reset the duplicate guard there no longer applies, so a second introduction
## would be honoured with whatever name it carried. This one cannot say
## anything. The host already knows who this peer is, from the finished match.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_want_rematch() -> void:
	_on_rematch_wanted(_sender())


## A private message for `recipient_id` (decisions.md D192). Carries no
## sender: the host takes that from the peer id, so a client cannot write as
## somebody else.
##
## **Only the host relays.** With Godot's default server relay a client can
## address an RPC to another client, so the check is here rather than left to
## the client's handler being empty.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_send_message(recipient_id: String, text: String) -> void:
	if not multiplayer.is_server():
		return
	if recipient_id.length() > MessageRules.MAX_ID_LENGTH:
		return
	_on_message_sent(_sender(), StringName(recipient_id), text)


# ------------------------------------------------------- host → client (results)

## `history_data` is every year resolved before this player arrived. Empty for
## somebody who was there from the start, and the whole match for a player
## rejoining or reconnecting after a migration. See docs/decisions.md D118.
@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(player_id: String, state_data: Dictionary, history_data: Array) -> void:
	_on_welcomed(StringName(player_id), state_data, history_data)


## The host closed the lobby. A client's screen host swaps the lobby for the
## playing screen on this.
@rpc("authority", "call_remote", "reliable")
func _rpc_match_started() -> void:
	_on_match_start_pushed()


## The host refused the connection — the match is full, or already under way.
## Sent before the peer is disconnected so the player gets a reason rather than a
## silent failure.
@rpc("authority", "call_remote", "reliable")
func _rpc_turned_away(reason: String) -> void:
	_on_turned_away(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_state(state_data: Dictionary, changed_player_id: String) -> void:
	_on_state_pushed(state_data, StringName(changed_player_id))


@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: String) -> void:
	_on_rejection_pushed(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_year(result_data: Dictionary, state_data: Dictionary) -> void:
	_on_year_pushed(result_data, state_data)


@rpc("authority", "call_remote", "reliable")
func _rpc_ready_changed(player_id: String, is_ready: bool) -> void:
	_on_ready_pushed(StringName(player_id), is_ready)


@rpc("authority", "call_remote", "reliable")
func _rpc_yeehaw_asked(player_id: String) -> void:
	_on_yeehaw_ask_pushed(StringName(player_id))


@rpc("authority", "call_remote", "reliable")
func _rpc_yeehaw_given(giver_id: String, receiver_id: String) -> void:
	_on_yeehaw_given_pushed(StringName(giver_id), StringName(receiver_id))


## The host has gone back to the lobby and is willing to play again. Every
## client hears it, including anyone who never asked for one.
@rpc("authority", "call_remote", "reliable")
func _rpc_rematch_offered() -> void:
	_on_rematch_offer_pushed()


## This client now has a seat in the rematch lobby. Sent to one peer, straight
## after its welcome.
##
## **A separate packet rather than an inference**, for the same reason D116
## added `_rpc_match_started`: the welcome cannot say which situation it is. A
## client is welcomed when it first joins, when it rejoins, and on every
## migration reconnect, so `joined` alone would have `Main` guessing from which
## screen happens to be up and whether a migration is in flight — which is the
## shape of the fault D108 was.
@rpc("authority", "call_remote", "reliable")
func _rpc_rematch_joined() -> void:
	_on_rematch_join_pushed()


## A message for this player, passed on by the host. `sender_id` is the host's
## record of who sent it, never anything the sender wrote. `in_room` says it was
## sent to the ALL PLAYERS room rather than to this player alone (D195).
@rpc("authority", "call_remote", "reliable")
func _rpc_message(sender_id: String, text: String, in_room: bool) -> void:
	_on_message_pushed(StringName(sender_id), text, in_room)


# ------------------------------------------------------------------- the handlers
#
# Plain methods, overridden by exactly one side. The other side never receives
# the call in the first place: an `authority` RPC cannot be sent by a client, and
# the host simply has nobody sending it the host-to-client ones. They are no-ops
# rather than errors so that a stray late packet during shutdown is harmless.

func _on_buy_requested(_peer: int, _stalk_id: StringName, _shares: int) -> void:
	pass


func _on_sell_requested(_peer: int, _stalk_id: StringName, _shares: int) -> void:
	pass


func _on_loan_requested(_peer: int, _amount: int) -> void:
	pass


func _on_payment_requested(_peer: int, _amount: int) -> void:
	pass


func _on_ready_requested(_peer: int, _is_ready: bool) -> void:
	pass


func _on_yeehaw_asked(_peer: int) -> void:
	pass


func _on_yeehaw_offered(_peer: int) -> void:
	pass


func _on_rematch_asked(_peer: int) -> void:
	pass


func _on_rematch_wanted(_peer: int) -> void:
	pass


func _on_introduced(_peer: int, _player_name: String, _steam_id: int = 0) -> void:
	pass


func _on_message_sent(_peer: int, _recipient_id: StringName, _text: String) -> void:
	pass


func _on_message_pushed(_sender_id: StringName, _text: String, _in_room: bool) -> void:
	pass


func _on_welcomed(
	_player_id: StringName, _state_data: Dictionary, _history_data: Array = []
) -> void:
	pass


func _on_match_start_pushed() -> void:
	pass


func _on_turned_away(_reason: String) -> void:
	pass


func _on_state_pushed(_state_data: Dictionary, _changed_player_id: StringName) -> void:
	pass


func _on_rejection_pushed(_reason: String) -> void:
	pass


func _on_year_pushed(_result_data: Dictionary, _state_data: Dictionary) -> void:
	pass


func _on_ready_pushed(_player_id: StringName, _is_ready: bool) -> void:
	pass


func _on_yeehaw_ask_pushed(_player_id: StringName) -> void:
	pass


func _on_yeehaw_given_pushed(_giver_id: StringName, _receiver_id: StringName) -> void:
	pass


func _on_rematch_offer_pushed() -> void:
	pass


func _on_rematch_join_pushed() -> void:
	pass


# -------------------------------------------------------------------- internals

## Who sent the RPC currently being handled. Zero outside an RPC.
func _sender() -> int:
	return multiplayer.get_remote_sender_id()


## Tears the transport down. Safe to call twice, and safe when no peer was ever
## set, so cleanup paths and tests do not have to check first.
func close() -> void:
	if multiplayer == null:
		return
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer != null:
		# `close` is on MultiplayerPeer itself, so this works for whatever
		# transport produced the peer — no `is ENetMultiplayerPeer` here.
		peer.close()
	multiplayer.multiplayer_peer = null
