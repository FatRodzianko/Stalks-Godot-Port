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
			"error": _why_the_port_refused(error),
		}
	return {"peer": peer, "error": ""}


func open_client() -> Dictionary:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(_address, _port)
	if error != OK:
		return {
			"peer": null,
			"error": "Could not reach %s:%d: %s." % [
				_address, _port, Transport.describe_error(error)
			],
		}
	return {"peer": peer, "error": ""}


## What to tell the other players.
##
## Names this machine's address on the network, not just the port. "Others join
## on port 42420" is useless from a second computer, which is exactly where a
## direct connection earns its keep — two machines on a desk, no Steam, no
## accounts, fast enough to test a gameplay change on.
## Why a bind failed, for the one failure players actually hit.
##
## **ENet reports a taken port as `ERR_CANT_CREATE`**, not
## `ERR_ALREADY_IN_USE` — established by binding twice in
## `test_transport.gd` rather than assumed. The generic description cannot
## say "that port is taken" for that code, because on the client side the same
## code means something else entirely.
func _why_the_port_refused(error: int) -> String:
	if error == ERR_CANT_CREATE or error == ERR_ALREADY_IN_USE:
		return "Could not listen on port %d: something else may already be using it." % _port
	return "Could not listen on port %d: %s." % [_port, Transport.describe_error(error)]


func joining_hint() -> String:
	var address: String = local_address()
	if address.is_empty():
		return "Others join on port %d" % _port
	return "Others join at %s:%d" % [address, _port]


## This machine's best guess at its own address, or empty if it has none.
##
## **It is a guess, and it can be wrong.** A developer machine is typically on
## several networks at once, most of them virtual and unreachable from anywhere
## else. On the machine this was written on, Godot reported nine addresses and
## the real one was eighth:
##
##     172.31.160.1   vEthernet (WSL)              virtual
##     172.20.0.1     vEthernet (Default Switch)   virtual, Hyper-V
##     169.254.x.x    three adapters               link-local, DHCP failed
##     192.168.1.242  Ethernet                     the real one
##     192.168.56.1   Ethernet 2                   virtual, VirtualBox
##
## Taking the first non-loopback address — the obvious implementation — picked
## the WSL switch, which no other computer can reach. Hence the ranking below.
## Use `local_addresses()` and try another if the first does not work.
static func local_address() -> String:
	var candidates: PackedStringArray = local_addresses()
	return candidates[0] if not candidates.is_empty() else ""


## Every address another machine might be able to reach, best guess first.
##
## The ordering is heuristic and deliberately conservative about ranges that
## are usually virtual on Windows. There is no reliable way to ask "which of
## these can the computer over there reach?", so this orders by how likely each
## is to be a real network and leaves the rest to a human. `tools/lan_check.gd`
## prints the whole ordered list for exactly that purpose.
static func local_addresses() -> PackedStringArray:
	return rank_addresses(IP.get_local_addresses())


## The ranking, separated from asking the machine so it can be tested against a
## real-world address list instead of whatever the test runner happens to be
## plugged into. See `tests/unit/test_transport.gd`.
##
## Sorted stably, so addresses of equal rank keep the order the OS gave them.
static func rank_addresses(raw: PackedStringArray) -> PackedStringArray:
	var ranked: Array[Array] = []
	var order: int = 0

	for address: String in raw:
		if address.contains(":"):
			continue  # IPv6: not what anybody is going to type.
		if address.begins_with("127."):
			continue  # Loopback. Reaches only this machine.
		if address.begins_with("169.254."):
			continue  # Link-local: DHCP failed, so this is not a working network.
		ranked.append([_rank_of(address), order, address])
		order += 1

	ranked.sort_custom(
		func(a: Array, b: Array) -> bool:
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1]
	)

	var out: PackedStringArray = []
	for entry: Array in ranked:
		out.append(entry[2])
	return out


## Lower is more likely to be a real network. See `local_addresses()`.
static func _rank_of(address: String) -> int:
	# VirtualBox's host-only network. A real 192.168 address beats it.
	if address.begins_with("192.168.56."):
		return 2
	# The classic home and small-office range.
	if address.begins_with("192.168."):
		return 0
	# Common on larger networks.
	if address.begins_with("10."):
		return 1
	# 172.16-31 is a legitimate private range, but on a Windows developer
	# machine it is nearly always Docker, WSL or Hyper-V.
	if address.begins_with("172."):
		return 3
	return 4


func describe() -> String:
	return "ENet %s:%d" % [_address, _port]


func port() -> int:
	return _port
