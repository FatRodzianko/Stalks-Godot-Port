class_name StubTransport
extends Transport
## A transport that is deliberately not ENet.
##
## Lives outside tests/unit so GUT does not scan it. Its whole job is to prove
## that nothing above the transport layer knows or cares what carries the match
## — which is the claim Phase 6 rests on. If a session ever reaches for
## `ENetMultiplayerPeer` again, these tests stop working.


## Set to make `open_server` / `open_client` report a failure instead.
var failure: String = ""

var hint: String = "join however you like"


func open_server(_max_clients: int) -> Dictionary:
	if not failure.is_empty():
		return {"peer": null, "error": failure}
	# Not ENet, and not a stub class either: a real engine peer of a different
	# kind, so the session is exercised against the actual MultiplayerPeer API.
	return {"peer": OfflineMultiplayerPeer.new(), "error": ""}


func open_client() -> Dictionary:
	if not failure.is_empty():
		return {"peer": null, "error": failure}
	return {"peer": OfflineMultiplayerPeer.new(), "error": ""}


func joining_hint() -> String:
	return hint


func describe() -> String:
	return "stub"
