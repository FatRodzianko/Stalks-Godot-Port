class_name SteamTransport
extends Transport
## Carries a match over Steam's peer-to-peer relay.
##
## Deliberately thin. All the hard parts of Steam — initialising it, creating or
## joining a lobby, waiting for Steam to answer — happen in `SteamService`
## before this is constructed. By the time a `SteamTransport` exists there is a
## lobby, and turning that into a `MultiplayerPeer` is immediate.
##
## That is why the `Transport` interface did not have to become asynchronous to
## accommodate Steam. See decisions.md D59.


## Virtual port, in Steam's networking sense rather than a TCP/UDP one. Peers
## must agree on it; there is only ever one channel here, so zero.
const VIRTUAL_PORT: int = 0


var _lobby_id: int
var _owner_steam_id: int
var _lobby_name: String


## `owner_steam_id` is who to connect to, and is ignored when hosting. A client
## connects to the lobby's *owner*, not to the lobby itself.
func _init(lobby_id: int, owner_steam_id: int = 0, lobby_name: String = "") -> void:
	_lobby_id = lobby_id
	_owner_steam_id = owner_steam_id
	_lobby_name = lobby_name


## Argument checks come before the plugin check on purpose, so "was this
## constructed properly?" gives the same answer with or without Steam installed
## and can be tested on any machine.
func open_server(_max_clients: int) -> Dictionary:
	if _lobby_id == 0:
		return {"peer": null, "error": "No Steam lobby to host in."}
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return {"peer": null, "error": "Steam support is not installed in this build."}

	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: int = peer.host_with_lobby(_lobby_id)
	if error != OK:
		return {
			"peer": null,
			"error": "Could not host on Steam: %s." % Transport.describe_error(error),
		}
	return {"peer": peer, "error": ""}


func open_client() -> Dictionary:
	if _owner_steam_id == 0:
		return {"peer": null, "error": "That game has no host to connect to."}
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return {"peer": null, "error": "Steam support is not installed in this build."}

	var peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
	var error: int = peer.create_client(_owner_steam_id, VIRTUAL_PORT)
	if error != OK:
		return {
			"peer": null,
			"error": (
				"Could not reach that game on Steam: %s."
				% Transport.describe_error(error)
			),
		}
	return {"peer": peer, "error": ""}


## Nothing for the host to pass on: Steam invites are how people join, and the
## lobby browser finds the rest. There is no port to read out loud, which is
## the entire reason the lobby asks the transport rather than printing one.
func joining_hint() -> String:
	return "Invite friends through Steam, or let them find you in the browser"


func describe() -> String:
	return "Steam lobby %d" % _lobby_id


func lobby_id() -> int:
	return _lobby_id


func lobby_name() -> String:
	return _lobby_name
