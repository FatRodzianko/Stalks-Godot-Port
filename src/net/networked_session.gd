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
## typed. Nothing else is sent with it: the host assigns the slot.
##
## A slot is created when this arrives rather than when the socket connects, so
## that a player appears in the lobby already named instead of flickering through
## a placeholder.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_introduce(player_name: String) -> void:
	_on_introduced(_sender(), player_name)


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


# ------------------------------------------------------- host → client (results)

@rpc("authority", "call_remote", "reliable")
func _rpc_welcome(player_id: String, state_data: Dictionary) -> void:
	_on_welcomed(StringName(player_id), state_data)


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


func _on_introduced(_peer: int, _player_name: String) -> void:
	pass


func _on_welcomed(_player_id: StringName, _state_data: Dictionary) -> void:
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
	if peer != null and peer is ENetMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = null
