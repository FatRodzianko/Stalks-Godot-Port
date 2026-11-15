class_name EnetTransport
extends Transport
## A direct IP connection over Godot's built-in ENet.
##
## No accounts, no storefront, works offline and between two windows on one
## machine. It is what the whole networked layer was built and tested against,
## and it stays after Steam arrives: a Steam-free direct connection is useful
## for development, for LAN play, and for anyone who does not own the game on
## Steam. See docs/decisions.md D56.


## Where a client connects when nobody types an address. Two windows on one
## machine is overwhelmingly the common case.
const LOCAL_ADDRESS: String = "127.0.0.1"


var _address: String
var _port: int


func _init(port: int, address: String = LOCAL_ADDRESS) -> void:
	_port = port
	_address = address


func open_server(max_clients: int) -> Dictionary:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(_port, max_clients)
	if error != OK:
		return {
			"peer": null,
			"error": "Could not listen on port %d (%d)." % [_port, error],
		}
	return {"peer": peer, "error": ""}


func open_client() -> Dictionary:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(_address, _port)
	if error != OK:
		return {
			"peer": null,
			"error": "Could not reach %s:%d (%d)." % [_address, _port, error],
		}
	return {"peer": peer, "error": ""}


func joining_hint() -> String:
	return "Others join on port %d" % _port


func describe() -> String:
	return "ENet %s:%d" % [_address, _port]


func port() -> int:
	return _port
