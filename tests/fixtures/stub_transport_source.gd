class_name StubTransportSource
extends SteamTransportSource
## Hands `Main` a transport that is not Steam.
##
## See `SteamTransportSource` for why this seam exists: calling the real Steam
## API uninitialised crashes the process rather than returning an error, so a
## test that drives `Main` through hosting, joining or a migration has to be
## given something else. `StubTransport` returns a real engine peer of a
## different kind, so everything above the transport is exercised for real.
##
## Lives outside tests/unit so GUT does not scan it.


## Set to make every transport fail to open, for the paths that handle it.
var failure: String = ""

## Every transport handed out, so a test can see which was asked for.
var built: Array[StringName] = []


func host_in(_lobby_id: int) -> Transport:
	built.append(&"host")
	return _stub()


func client_to(_lobby_id: int, _owner_steam_id: int) -> Transport:
	built.append(&"client")
	return _stub()


func _stub() -> StubTransport:
	var transport: StubTransport = StubTransport.new()
	transport.failure = failure
	return transport
