extends GutTest
## The transport seam: everything above it must be ignorant of what carries the
## match.
##
## This is the groundwork Phase 6 rests on. Steam is meant to be a swap rather
## than a rewrite, and that was a claim until the sessions stopped building an
## `ENetMultiplayerPeer` themselves. These tests are what keep it true.


var _library: ContentLibrary


func before_all() -> void:
	_library = ContentLibrary.load_from()


func _settings() -> GameSettings:
	return StalksFixture.make_settings()


# ----------------------------------------------------- not ENet, and still fine

func test_a_host_can_be_built_on_a_transport_that_is_not_enet() -> void:
	var result: Dictionary = HostSession.host(
		StubTransport.new(), _settings(), _library, "Murph"
	)

	assert_eq(String(result["error"]), "", "a non-ENet transport should be accepted")
	assert_not_null(result["session"])
	assert_false(
		result["peer"] is ENetMultiplayerPeer,
		"the test is pointless if the peer is ENet after all",
	)


func test_a_client_can_be_built_on_a_transport_that_is_not_enet() -> void:
	var result: Dictionary = ClientSession.join(StubTransport.new(), _library, "Guest")

	assert_eq(String(result["error"]), "")
	assert_not_null(result["session"])


func test_the_host_seats_itself_whatever_the_transport() -> void:
	var result: Dictionary = HostSession.host(
		StubTransport.new(), _settings(), _library, "Murph"
	)
	var session: HostSession = result["session"]
	add_child_autofree(session)
	session.attach_peer(result["peer"])

	assert_eq(session.local_player_id(), &"p0")
	assert_eq(session.state().player_by_id(&"p0").display_name, "Murph")


# ------------------------------------------------------------------- failures

func test_a_transport_failure_reaches_the_caller() -> void:
	var transport: StubTransport = StubTransport.new()
	transport.failure = "The lobby could not be created."

	var result: Dictionary = HostSession.host(transport, _settings(), _library, "Murph")

	assert_null(result["session"], "nothing should be built on a dead transport")
	assert_eq(String(result["error"]), "The lobby could not be created.")


func test_a_client_transport_failure_reaches_the_caller() -> void:
	var transport: StubTransport = StubTransport.new()
	transport.failure = "That invite has expired."

	var result: Dictionary = ClientSession.join(transport, _library, "Guest")

	assert_null(result["session"])
	assert_eq(String(result["error"]), "That invite has expired.")


# ---------------------------------------------------- the hint comes from below

func test_the_joining_hint_comes_from_the_transport() -> void:
	# The lobby shows this verbatim. A port today, a Steam invite later, and the
	# screen must not grow a branch for the difference.
	var transport: StubTransport = StubTransport.new()
	transport.hint = "Ask Murph for an invite"
	var session: HostSession = HostSession.host(
		transport, _settings(), _library, "Murph"
	)["session"]

	assert_eq(session.joining_hint(), "Ask Murph for an invite")


func test_the_enet_transport_names_its_port() -> void:
	assert_string_contains(EnetTransport.new(42420).joining_hint(), "42420")


func test_the_enet_transport_refuses_a_port_already_in_use() -> void:
	var squatter: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var port: int = randi_range(44800, 44899)
	assert_eq(squatter.create_server(port, 1), OK, "the test needs the port held")

	var opened: Dictionary = EnetTransport.new(port).open_server(4)
	squatter.close()

	assert_null(opened["peer"])
	assert_string_contains(String(opened["error"]), str(port))
	assert_engine_error("host", "ENet reports the failed bind")
