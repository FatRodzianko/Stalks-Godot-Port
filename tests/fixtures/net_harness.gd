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
## assert_eq(harness.start(StalksFixture.make_settings(), library), "")
## assert_true(await harness.await_join(self), "client should connect")
## ```


## Ports are picked from this range per harness, because a socket just closed by a
## previous test can linger and refuse to rebind.
const PORT_FLOOR: int = 42400
const PORT_CEILING: int = 42999

## How many times to try a different port before giving up.
const PORT_ATTEMPTS: int = 8

## The next port to hand out. Chosen once per run from a random base and then
## walked upwards, so two harnesses in the same run can never pick the same
## number DASH random-per-harness collided often enough to redden a run, and a
## failed bind is not silent: ENet logs an engine error that GUT counts.
static var _next_port: int = 0

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

## APIs for any extra clients a test mounts, each with its own world.
var _extra_apis: Array[MultiplayerAPI] = []

var _port: int = 0


## Builds both sides and connects them. Returns an error string, empty on success.
##
## The host takes the first slot and the client the second, as they would in a
## real lobby: the host exists from the start and the client is seated when it
## introduces itself.
func start(
	settings: GameSettings,
	library: ContentLibrary,
	host_name: String = "Host",
	guest_name: String = "Guest",
) -> String:
	# Retry on a taken port rather than failing the test. Ports are picked at
	# random because one just closed can linger, and with a suite this size a
	# collision is a matter of when, not if — it cost a red run once already.
	var host_result: Dictionary = {}
	for attempt: int in PORT_ATTEMPTS:
		_port = _take_port()
		host_result = HostSession.host(
			EnetTransport.new(_port), settings, library, host_name
		)
		if String(host_result["error"]).is_empty():
			break
	if not String(host_result["error"]).is_empty():
		return String(host_result["error"])
	host = host_result["session"]

	var client_result: Dictionary = ClientSession.join(
		EnetTransport.new(_port), library, guest_name
	)
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
## Waits on the player being gone from the *active* roster, which covers both
## outcomes: a lobby drop forgets the player outright, while an in-match drop
## vacates the slot and keeps the portfolio.
func drop_client(test: GutTest) -> bool:
	if client != null:
		client.close()
	var gone: Callable = func() -> bool: return host.state().player_by_id(&"p1") == null
	await test.wait_until(gone, JOIN_TIMEOUT_SECONDS)
	return gone.call()


## Takes the lobby through to a running match the way a real one goes: every
## guest readies up, then the host presses Start.
##
## Start refuses until everybody is ready (D49), so readying is not optional
## scene-setting — it is how a match begins.
func begin_match(test: GutTest) -> void:
	if client != null and client.has_joined():
		client.set_ready(client.local_player_id(), true)
		await settle(test)
	host.start_match()
	await settle(test)


## The next free port, walking upwards from a per-run random base. The retry in
## `start` remains as a safety net for a socket left over from a previous run.
static func _take_port() -> int:
	if _next_port == 0:
		_next_port = randi_range(PORT_FLOOR, PORT_CEILING - PORT_ATTEMPTS)
	var port: int = _next_port
	_next_port += 1
	if _next_port > PORT_CEILING:
		_next_port = PORT_FLOOR
	return port


## The port this harness bound, for a test that wants to connect a third peer.
func port() -> int:
	return _port


## Mounts an additional client in **its own world with its own API**, exactly as
## the first two are.
##
## It cannot share the first client's world. Two sessions under one API would be
## siblings, so only one of them could be named `Session`, and the host's RPCs
## resolve by that relative path — the second would fail with "Failed to get path
## from RPC". That is requirement 2 at the top of this file, met the hard way.
func attach_extra_client(extra: ClientSession, peer: MultiplayerPeer) -> void:
	var world: Node = _mount("ExtraWorld%d" % _extra_apis.size(), extra)
	var api: MultiplayerAPI = _register_api(world)
	_extra_apis.append(api)
	extra.attach_peer(peer)
	_peers.append(peer)


## Both APIs are polled here because the engine only polls the tree's default one.
func _process(_delta: float) -> void:
	if _host_api != null:
		_host_api.poll()
	if _client_api != null:
		_client_api.poll()
	for api: MultiplayerAPI in _extra_apis:
		api.poll()


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
	var apis: Array[MultiplayerAPI] = [_host_api, _client_api]
	apis.append_array(_extra_apis)
	for api: MultiplayerAPI in apis:
		if api != null:
			api.multiplayer_peer = null
	for peer: MultiplayerPeer in _peers:
		if peer != null:
			peer.close()
	_peers.clear()
