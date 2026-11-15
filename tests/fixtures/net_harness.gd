class_name NetHarness
extends Node
## Stands a host and a client up in **one process** so networked behaviour can be
## tested headlessly, in the ordinary suite.
##
## Lives outside tests/unit so GUT does not scan it for tests.
##
## How it works, and why it has to work this way (established by the spike
## recorded in docs/architecture.md §5.2):
##
## 1. Each side gets its own subtree — `HostWorld` and `ClientWorld` — and its own
##    `MultiplayerAPI`, registered with `SceneTree.set_multiplayer(api, path)`.
##    One process cannot otherwise hold two peers, because a tree has a single
##    default API.
## 2. **The session's path relative to its API's root must match on both sides.**
##    Godot resolves an RPC by that relative path, so both sessions are mounted as
##    `Session` directly under their own world node. The world names differ and
##    that is fine; what is below them may not.
## 3. A non-default API is **not polled by the engine**, so this node polls both
##    by hand every frame. In the real game there is one API, the tree's own, and
##    Godot polls it — this is a test-harness concern only.
##
## Typical use:
## ```gdscript
## var harness: NetHarness = NetHarness.new()
## add_child_autofree(harness)
## assert_eq(harness.start(StalksFixture.make_settings(), library, ["Host", "Guest"]), "")
## assert_true(await harness.await_join(self), "client should connect")
## ```


## Ports are picked from this range per harness, because a socket just closed by a
## previous test can linger and refuse to rebind.
const PORT_FLOOR: int = 42400
const PORT_CEILING: int = 42999

## How long `await_join` waits before giving up. Generous: a loaded CI machine is
## slower than a desktop, and a flaky networking test is worse than a slow one.
const JOIN_TIMEOUT_SECONDS: float = 5.0


var host: HostSession
var client: ClientSession

var _host_world: Node
var _client_world: Node
var _host_api: MultiplayerAPI
var _client_api: MultiplayerAPI
## Kept so teardown can close them without going through the nodes: by the time
## `_exit_tree` runs, the sessions are already detached and `Node.multiplayer`
## no longer resolves.
var _peers: Array[MultiplayerPeer] = []
var _port: int = 0


## Builds both sides and connects them. Returns an error string, empty on success.
##
## `player_names` sizes the match; the host takes the first slot and the client
## the second, so pass at least two names for anything involving both.
func start(
	settings: GameSettings,
	library: ContentLibrary,
	player_names: Array[String] = ["Host", "Guest"],
) -> String:
	_port = randi_range(PORT_FLOOR, PORT_CEILING)

	var host_result: Dictionary = HostSession.host(_port, settings, library, player_names)
	if not String(host_result["error"]).is_empty():
		return String(host_result["error"])
	host = host_result["session"]

	var client_result: Dictionary = ClientSession.join("127.0.0.1", _port, library)
	if not String(client_result["error"]).is_empty():
		return String(client_result["error"])
	client = client_result["session"]

	# Order matters: the node must be in the tree before its API exists, and the
	# API must exist before a peer can be attached to it.
	_host_world = _mount("HostWorld", host)
	_client_world = _mount("ClientWorld", client)
	_host_api = _register_api(_host_world)
	_client_api = _register_api(_client_world)

	host.attach_peer(host_result["peer"])
	client.attach_peer(client_result["peer"])
	_peers = [host_result["peer"], client_result["peer"]]
	return ""


## Pumps both peers until the client has joined, or the timeout expires. Returns
## whether it joined.
##
## Takes the GutTest so it can use GUT's own awaiter, which keeps a hung
## connection from stalling the whole suite.
func await_join(test: GutTest) -> bool:
	await test.wait_until(func() -> bool: return client.has_joined(), JOIN_TIMEOUT_SECONDS)
	return client.has_joined()


## Pumps both peers for `frames` frames, so that a request and its reply have time
## to cross. Two frames is enough for a round trip over loopback; the default is
## deliberately more than enough.
##
## Process frames specifically, because that is where `_process` polls the two
## APIs — waiting on physics frames would advance a clock that moves no packets.
func settle(test: GutTest, frames: int = 6) -> void:
	await test.wait_process_frames(frames)


## Closes the client's socket and waits for the host to notice.
##
## Closing the peer is what a crash or a pulled cable looks like from the host's
## side, which is the case worth testing — a clean "I am leaving" message does not
## exist in this game yet.
func drop_client(test: GutTest) -> bool:
	if client != null:
		client.close()
	await test.wait_until(
		func() -> bool: return host.is_vacated(&"p1"), JOIN_TIMEOUT_SECONDS
	)
	return host.is_vacated(&"p1")


## Both APIs are polled here because the engine only polls the tree's default one.
func _process(_delta: float) -> void:
	if _host_api != null:
		_host_api.poll()
	if _client_api != null:
		_client_api.poll()


func _mount(world_name: String, session: NetworkedSession) -> Node:
	var world: Node = Node.new()
	world.name = world_name
	add_child(world)
	world.add_child(session)
	return world


## A fresh API rooted at `world`, so everything under it talks over that peer.
## The node must already be in the tree: `get_path()` on a detached node fails.
func _register_api(world: Node) -> MultiplayerAPI:
	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	get_tree().set_multiplayer(api, world.get_path())
	return api


## Closes both peers. Called automatically when the harness leaves the tree, so a
## test that frees it needs no teardown of its own.
##
## Two things this deliberately does NOT do:
##
## - It does not go through `host.close()` / `client.close()`. Children are
##   detached before `_exit_tree` runs here, and `Node.multiplayer` resolves by
##   node path, so those calls would be operating on a node with no API. The
##   peers are closed directly instead.
## - It does not unregister the APIs. `SceneTree.set_multiplayer` rejects a null
##   interface outright, and the engine exposes no removal, so the registration
##   for this harness's (now freed) subtree paths simply stays behind. It is inert
##   — nothing resolves to a freed node — and clearing the peer is what actually
##   releases the socket.
func _exit_tree() -> void:
	for api: MultiplayerAPI in [_host_api, _client_api]:
		if api != null:
			api.multiplayer_peer = null
	for peer: MultiplayerPeer in _peers:
		if peer != null:
			peer.close()
	_peers.clear()
