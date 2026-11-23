extends GutTest
## Private messages over real ENet, in this process (decisions.md D192, D193):
## the host as a relay and nothing more.
##
## What the wire adds to test_messages.gd: a message reaches its one recipient
## and no other machine; a client cannot say who sent it; the host refuses a
## recipient who is not in the match, cleans the text, and limits each sender;
## and a note to yourself never leaves your machine.
##
## The hostile cases call `_rpc_send_message` directly, which is exactly what a
## modified client could do: it skips every check `send_message` makes.


var _library: ContentLibrary
var _harness: NetHarness


func before_all() -> void:
	_library = ContentLibrary.load_from()


func after_each() -> void:
	if _harness != null and is_instance_valid(_harness):
		_harness.queue_free()
	_harness = null


func _connect() -> bool:
	_harness = NetHarness.new()
	add_child(_harness)
	var settings: GameSettings = StalksFixture.make_settings()
	settings.rng_seed = 4242
	var error: String = _harness.start(settings, _library, "Host", "Guest")
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return false
	var joined: bool = await _harness.await_join(self)
	assert_true(joined, "the client should connect")
	if not joined:
		return false
	await _harness.begin_match(self)
	return true


## A third player, seated in the lobby before Start, as a real one would be.
func _connect_three() -> ClientSession:
	_harness = NetHarness.new()
	add_child(_harness)
	var error: String = _harness.start(
		StalksFixture.make_settings(), _library, "Host", "Guest"
	)
	if not error.is_empty():
		fail_test("harness did not start: %s" % error)
		return null
	if not await _harness.await_join(self):
		fail_test("the first client did not join")
		return null
	var joining: Dictionary = ClientSession.join(
		EnetTransport.new(_harness.port()), _library, "Third"
	)
	var third: ClientSession = joining["session"]
	_harness.attach_extra_client(third, joining["peer"])
	await wait_until(third.has_joined, NetHarness.JOIN_TIMEOUT_SECONDS)
	if not third.has_joined():
		fail_test("the third client did not join")
		return null
	third.set_ready(third.local_player_id(), true)
	await _harness.settle(self)
	await _harness.begin_match(self)
	return third


func _texts(book: MessageBook, other_id: StringName) -> PackedStringArray:
	var texts: PackedStringArray = []
	for line: MessageBook.Line in book.lines(other_id):
		texts.append("%s:%s" % [line.from_id, line.text])
	return texts


# ------------------------------------------------------------------ delivery

func test_a_clients_message_reaches_the_host() -> void:
	if not await _connect():
		return
	assert_eq(_harness.client.send_message(&"p0", "hello host"), "")
	await _harness.settle(self)
	assert_eq(_texts(_harness.host.messages(), &"p1"), PackedStringArray(["p1:hello host"]))
	assert_eq(_harness.host.messages().unread_from(&"p1"), 1)


func test_the_hosts_message_reaches_the_client() -> void:
	if not await _connect():
		return
	assert_eq(_harness.host.send_message(&"p1", "hello guest"), "")
	await _harness.settle(self)
	assert_eq(_texts(_harness.client.messages(), &"p0"), PackedStringArray(["p0:hello guest"]))
	assert_true(_harness.client.messages().has_unread())


func test_the_sender_keeps_their_own_copy_and_it_is_not_unread() -> void:
	if not await _connect():
		return
	_harness.client.send_message(&"p0", "mine")
	await _harness.settle(self)
	assert_eq(_texts(_harness.client.messages(), &"p0"), PackedStringArray(["p1:mine"]))
	assert_false(_harness.client.messages().has_unread())


func test_a_message_between_clients_reaches_only_its_recipient() -> void:
	var third: ClientSession = await _connect_three()
	if third == null:
		return
	assert_eq(_harness.client.send_message(&"p2", "just for you"), "")
	await _harness.settle(self)

	assert_eq(_texts(third.messages(), &"p1"), PackedStringArray(["p1:just for you"]))
	# The host relayed it and kept nothing.
	assert_eq(_harness.host.messages().lines(&"p1").size(), 0)
	assert_eq(_harness.host.messages().lines(&"p2").size(), 0)
	assert_false(_harness.host.messages().has_unread())
	# And the sender was not sent it back.
	assert_false(_harness.client.messages().has_unread())


func test_a_note_never_leaves_the_machine() -> void:
	if not await _connect():
		return
	assert_eq(_harness.client.send_message(&"p1", "my plan"), "")
	await _harness.settle(self)
	assert_eq(_texts(_harness.client.messages(), &"p1"), PackedStringArray(["p1:my plan"]))
	assert_eq(_harness.host.messages().lines(&"p1").size(), 0)
	assert_false(_harness.host.messages().has_unread())


func test_messages_do_not_change_the_match_on_either_side() -> void:
	if not await _connect():
		return
	var host_before: Dictionary = StateSync.encode_state(_harness.host.state(), 0)
	var client_before: Dictionary = StateSync.encode_state(_harness.client.state(), 0)
	_harness.client.send_message(&"p0", "one")
	_harness.host.send_message(&"p1", "two")
	await _harness.settle(self)
	assert_eq(StateSync.encode_state(_harness.host.state(), 0), host_before)
	assert_eq(StateSync.encode_state(_harness.client.state(), 0), client_before)


# ------------------------------------------------------- a hostile client

func test_the_sender_is_the_peer_not_anything_in_the_packet() -> void:
	# There is no sender field to forge: whatever a client sends, the host
	# writes it down as coming from that client's own seat.
	if not await _connect():
		return
	_harness.client._rpc_send_message.rpc_id(NetworkedSession.HOST_PEER_ID, "p0", "p0: I am the host")
	await _harness.settle(self)
	var lines: Array[MessageBook.Line] = _harness.host.messages().lines(&"p1")
	assert_eq(lines.size(), 1)
	if lines.size() == 1:
		assert_eq(lines[0].from_id, &"p1", "filed under the real sender")
	assert_eq(_harness.host.messages().lines(&"p0").size(), 0)


func test_a_recipient_not_in_the_match_gets_nothing_and_nothing_breaks() -> void:
	if not await _connect():
		return
	var host_peer: int = NetworkedSession.HOST_PEER_ID
	_harness.client._rpc_send_message.rpc_id(host_peer, "p7", "anyone?")
	_harness.client._rpc_send_message.rpc_id(host_peer, "", "nobody")
	_harness.client._rpc_send_message.rpc_id(host_peer, "x".repeat(5000), "long id")
	await _harness.settle(self)
	assert_false(_harness.host.messages().has_unread())
	assert_false(_harness.client.messages().has_unread())
	# The connection is still good afterwards.
	_harness.client.send_message(&"p0", "still here")
	await _harness.settle(self)
	assert_eq(_harness.host.messages().lines(&"p1").size(), 1)


func test_a_client_addressing_itself_over_the_wire_is_not_bounced_back() -> void:
	if not await _connect():
		return
	_harness.client._rpc_send_message.rpc_id(NetworkedSession.HOST_PEER_ID, "p1", "echo?")
	await _harness.settle(self)
	assert_eq(_harness.client.messages().lines(&"p1").size(), 0)
	assert_eq(_harness.host.messages().lines(&"p1").size(), 0)


func test_the_host_cleans_what_a_client_sends() -> void:
	if not await _connect():
		return
	var nasty: String = "a\nb" + char(7) + char(0x202E) + "c" + "x".repeat(1000)
	_harness.client._rpc_send_message.rpc_id(NetworkedSession.HOST_PEER_ID, "p0", nasty)
	await _harness.settle(self)
	var lines: Array[MessageBook.Line] = _harness.host.messages().lines(&"p1")
	assert_eq(lines.size(), 1)
	if lines.size() == 1:
		assert_eq(lines[0].text, MessageRules.clean(nasty))
		assert_lte(lines[0].text.length(), MessageRules.MAX_LENGTH)
		assert_true(lines[0].text.begins_with("a b?c"))


func test_the_host_limits_a_client_that_ignores_its_own_limit() -> void:
	if not await _connect():
		return
	for index: int in MessageRules.RELAY_LIMIT * 3:
		_harness.client._rpc_send_message.rpc_id(
			NetworkedSession.HOST_PEER_ID, "p0", "flood %d" % index
		)
	await _harness.settle(self, 12)
	assert_eq(_harness.host.messages().lines(&"p1").size(), MessageRules.RELAY_LIMIT)


func test_only_the_host_relays() -> void:
	# A client handed a send request - which Godot's server relay would let one
	# client address to another - does nothing with it.
	if not await _connect():
		return
	_harness.client._rpc_send_message("p0", "relay this")
	await _harness.settle(self)
	assert_eq(_harness.host.messages().lines(&"p1").size(), 0)
	assert_eq(_harness.client.messages().lines(&"p0").size(), 0)


# ------------------------------------------------------- the receiving client

func test_a_client_ignores_a_message_from_somebody_not_in_the_match() -> void:
	if not await _connect():
		return
	_harness.client._on_message_pushed(&"p7", "ghost")
	_harness.client._on_message_pushed(&"p1", "from myself")
	assert_false(_harness.client.messages().has_unread())


func test_a_client_cleans_what_arrives_again() -> void:
	if not await _connect():
		return
	_harness.client._on_message_pushed(&"p0", "x\ty" + char(0x200B))
	assert_eq(_texts(_harness.client.messages(), &"p0"), PackedStringArray(["p0:x y?"]))
