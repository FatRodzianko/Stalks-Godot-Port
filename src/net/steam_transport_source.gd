class_name SteamTransportSource
extends RefCounted
## Where `Main` gets a Steam match's transport from.
##
## **A seam, and it exists for one reason: the suite must never reach Steam.**
## `Main` builds a `SteamTransport` at four points - hosting, joining, taking a
## match over and re-hosting a migrated lobby - and all four are on the paths
## host migration runs through. Calling the real Steam API with Steam not
## initialised does not fail politely; it takes the process down with a signal
## 11, which is how this seam came to be written (testing.md, "No test may
## touch Steam").
##
## So the orchestration round those four points is tested against a stub that
## hands back an ordinary peer, and what Steam itself does is left to
## docs/manual-testing.md. Nothing here decides anything: it is one `new` call
## per method, deliberately, so that replacing it changes only where the peer
## comes from.


## For a host: a transport serving the lobby this process owns.
func host_in(lobby_id: int) -> Transport:
	return SteamTransport.new(lobby_id)


## For a client: a transport dialling the lobby's owner.
func client_to(lobby_id: int, owner_steam_id: int) -> Transport:
	return SteamTransport.new(lobby_id, owner_steam_id)
