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
	var port: int = TestPorts.next(TestPorts.TRANSPORT_BASE)
	assert_eq(squatter.create_server(port, 1), OK, "the test needs the port held")

	var opened: Dictionary = EnetTransport.new(port).open_server(4)
	squatter.close()

	assert_null(opened["peer"])
	assert_string_contains(String(opened["error"]), str(port))
	# And in words. ENet reports a taken port as ERR_CANT_CREATE rather than
	# ERR_ALREADY_IN_USE, which is why the transport decides this itself
	# instead of leaving it to the generic description — found by writing the
	# obvious mapping and watching this fail. See decisions.md D74.
	assert_string_contains(String(opened["error"]).to_lower(), "already be using")
	assert_false(String(opened["error"]).contains("("), String(opened["error"]))
	assert_engine_error("host", "ENet reports the failed bind")


## The behaviour the join timeout exists for, and the reason the error message
## for a client cannot say "there was nothing listening".
func test_a_valid_address_with_nothing_on_it_opens_anyway() -> void:
	# ENet is UDP, so there is nobody at the other end to refuse the socket.
	# Nothing has failed yet; the failure arrives later as a timeout in
	# client_session.gd. See decisions.md D74.
	var port: int = TestPorts.next(TestPorts.TRANSPORT_BASE)
	var opened: Dictionary = EnetTransport.new(port).open_client()

	assert_not_null(opened["peer"], "a dead address still opens")
	assert_eq(String(opened["error"]), "")


func test_a_mistyped_address_says_to_check_it() -> void:
	# Which, given the test above, is the only way open_client can fail: the
	# address could not be resolved.
	var opened: Dictionary = EnetTransport.new(42420, "nope").open_client()

	assert_null(opened["peer"])
	assert_string_contains(String(opened["error"]), "nope", "name what was typed")
	assert_string_contains(String(opened["error"]).to_lower(), "typo")
	assert_false(String(opened["error"]).contains("("), String(opened["error"]))
	assert_engine_error("resolve", "ENet reports the unresolvable address")
	assert_engine_error("connect", "and then that it could not connect")


# --------------------------------------------- which address to tell a friend
#
# A host's lobby has to name an address another machine can reach. "Join on
# port 42420" is useless from a second computer, and the obvious implementation
# — first non-loopback address — picked a virtual adapter on the machine this
# was written on. These pin the ranking against that real address list.

## Exactly what Godot reported on a Windows developer machine, in order. The
## real network was `Ethernet` at 192.168.1.242; everything above it was WSL,
## Hyper-V or a failed DHCP lease.
const REAL_WORLD_ADDRESSES: PackedStringArray = [
	"fe80:0:0:0:2faa:91db:3516:4076",
	"172.31.160.1",
	"fe80:0:0:0:6b11:c7df:1e93:377e",
	"172.20.0.1",
	"0:0:0:0:0:0:0:1",
	"127.0.0.1",
	"fe80:0:0:0:e1c0:aec1:bc4e:9f41",
	"169.254.56.57",
	"fe80:0:0:0:5f73:c7b8:2b47:f37b",
	"169.254.190.105",
	"169.254.44.119",
	"192.168.1.242",
	"192.168.56.1",
]


func test_the_real_network_beats_the_virtual_ones() -> void:
	# The case that caused this: taking the first non-loopback address offered
	# the WSL switch, which no other computer can reach.
	assert_eq(EnetTransport.rank_addresses(REAL_WORLD_ADDRESSES)[0], "192.168.1.242")


func test_loopback_and_link_local_are_never_offered() -> void:
	# Loopback reaches only this machine; 169.254 means DHCP failed, so that
	# adapter is not on a working network at all.
	var ranked: PackedStringArray = EnetTransport.rank_addresses(REAL_WORLD_ADDRESSES)
	for address: String in ranked:
		assert_false(address.begins_with("127."), "offered loopback: %s" % address)
		assert_false(address.begins_with("169.254."), "offered link-local: %s" % address)


func test_ipv6_is_never_offered() -> void:
	# Nobody is typing an IPv6 address into a text field by hand.
	for address: String in EnetTransport.rank_addresses(REAL_WORLD_ADDRESSES):
		assert_false(address.contains(":"), "offered IPv6: %s" % address)


func test_every_plausible_address_is_still_offered() -> void:
	# The first choice is a guess, so the alternatives have to survive for a
	# human to try. Four of the thirteen above are plausible.
	assert_eq(EnetTransport.rank_addresses(REAL_WORLD_ADDRESSES).size(), 4)


func test_virtualbox_ranks_below_a_real_192_168() -> void:
	var ranked: PackedStringArray = EnetTransport.rank_addresses(
		PackedStringArray(["192.168.56.1", "192.168.1.242"])
	)
	assert_eq(ranked[0], "192.168.1.242")


func test_a_corporate_ten_dot_beats_a_docker_172() -> void:
	var ranked: PackedStringArray = EnetTransport.rank_addresses(
		PackedStringArray(["172.17.0.1", "10.0.0.5"])
	)
	assert_eq(ranked[0], "10.0.0.5")


func test_equal_ranks_keep_the_order_the_machine_gave() -> void:
	# Two addresses with nothing to choose between them should not be shuffled
	# arbitrarily between runs.
	var ranked: PackedStringArray = EnetTransport.rank_addresses(
		PackedStringArray(["192.168.1.10", "192.168.1.20"])
	)
	assert_eq(ranked, PackedStringArray(["192.168.1.10", "192.168.1.20"]))


func test_a_machine_with_no_network_offers_nothing() -> void:
	assert_eq(
		EnetTransport.rank_addresses(PackedStringArray(["127.0.0.1", "::1"])),
		PackedStringArray(),
	)


func test_the_hint_names_an_address_not_just_a_port() -> void:
	var hint: String = EnetTransport.new(42420).joining_hint()
	assert_string_contains(hint, "42420")
	# On a machine with no network this degrades to the port alone, which is
	# why this does not assert a specific address.
	assert_true(hint.to_lower().contains("join"), "got: %s" % hint)


# ----------------------------------------------------- failures, in words
#
# Every failure in this layer used to reach the screen as a bare number:
# "Could not listen on port 42420 (24)". That helps nobody, including whoever
# receives the screenshot. See decisions.md D74.

func test_a_busy_port_says_what_is_wrong() -> void:
	assert_string_contains(
		Transport.describe_error(ERR_ALREADY_IN_USE).to_lower(), "already using"
	)


func test_nothing_listening_says_so() -> void:
	assert_string_contains(
		Transport.describe_error(ERR_CANT_CONNECT).to_lower(), "nothing listening"
	)


func test_an_unknown_code_keeps_its_number() -> void:
	# More honest than inventing a sentence for a case nobody has seen, and
	# the number is the only thing a bug report could use.
	assert_string_contains(Transport.describe_error(9999), "9999")
