class_name Transport
extends RefCounted
## How a networked match is carried. Abstract.
##
## The sessions used to build an `ENetMultiplayerPeer` themselves, which made
## "Steam is a transport swap, not a rewrite" a claim rather than a fact. A
## transport owns everything about *reaching* other players — a port, a lobby
## id, an invite — and hands back a `MultiplayerPeer`. Nothing above this layer
## knows which kind it got.
##
## Implementations: `EnetTransport` now, `SteamTransport` in Phase 6. They differ
## more than they look: ENet needs an address and a port typed by a human, while
## Steam needs a lobby that must be created asynchronously and joined by id. That
## is why `open_server` and `open_client` take no arguments — each transport is
## constructed with whatever *it* needs, and the sessions stay ignorant.
##
## See docs/architecture.md 5.4 and docs/decisions.md D56.


## Result of opening a connection: `{peer: MultiplayerPeer, error: String}`.
## `error` empty means `peer` is usable. A non-empty error is player-facing text.
##
## Returning a dictionary rather than throwing keeps the failure path visible at
## every call site; a busy port is an ordinary thing for a player to hit.
func open_server(_max_clients: int) -> Dictionary:
	push_error("Transport.open_server is abstract")
	return {"peer": null, "error": "This transport cannot host."}


func open_client() -> Dictionary:
	push_error("Transport.open_client is abstract")
	return {"peer": null, "error": "This transport cannot join."}


## One line telling the host what to pass on so others can join: a port for a
## direct connection, an invite for Steam. Empty when there is nothing to say.
## Godot's `Error` code, in words a player can act on.
##
## **Why this exists.** Every failure in this layer used to end up on screen as
## a bare number: "Could not listen on port 42420 (24)". That tells a player
## nothing and tells somebody reporting a bug almost as little — nobody knows
## which enum 24 belongs to either.
##
## The number is kept on the end, because the sentence is for the player and
## the number is for whoever they send a screenshot to.
##
## Only the codes this layer can actually produce are named. Anything else
## keeps its number and says so plainly, which is more honest than inventing a
## sentence for a case nobody has seen.
static func describe_error(code: int) -> String:
	if code == ERR_ALREADY_IN_USE:
		return "something else is already using that port"
	if code == ERR_CANT_CREATE:
		return "the connection could not be opened"
	if code == ERR_CANT_CONNECT:
		return "there was nothing listening"
	if code == ERR_CANT_RESOLVE:
		return "that address could not be found"
	if code == ERR_CONNECTION_ERROR:
		return "the connection failed"
	if code == ERR_UNAVAILABLE:
		return "that is not available on this machine"
	return "error %d" % code


func joining_hint() -> String:
	return ""


## A short name for logs and for the lobby to show. Not player-facing prose.
func describe() -> String:
	return "unknown"
