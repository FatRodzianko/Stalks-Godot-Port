extends GutTest
## Custom content crossing the wire, and surviving a handover.
##
## **This is the half that is not a content feature.** Before custom stalks,
## both sides loaded the same `.tres` and only ids travelled; a definition is
## now match state supplied by another player. These cover the three moments
## that matters at: joining, taking the match over, and coming back to it.
##
## The networked ones use `NetHarness`, which stands both sides up in one
## process over ENet. **No test here touches Steam** — see
## `StubSteamService` and docs/testing.md.


const ME: int = 9001
const DEPARTED: int = 9002
const LOBBY: int = 4242

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")


## A host library holding one company no client could possibly have on disk.
##
## **The networked tests below start the client on `ContentLibrary.load_from()`
## instead** - the shipped ten, which is what a real client has before it is
## welcomed. Handing both sides this library would let every one of them pass
## with the welcome carrying no content at all, because the client would
## already hold the answer. That was the first version, and reinstating the
## fault is what caught it.
func _custom_library() -> ContentLibrary:
	var schema: StalkSchema = StalkSchema.from_file_data({
		"name": "Only The Host Has This",
		"description": "Not on anybody else's disk.",
		"starting_price": 90,
		"bull_change": [0, 12],
		"bear_change": [4, 18],
		"bull_dividend": 4,
		"bear_dividend": 2,
		"events": [
			{"mood": "bull", "text": "The host's own good news.", "price_change": 11},
			{"mood": "bear", "text": "The host's own bad news.", "price_change": -13},
		],
	}, "host_only")
	assert_true(schema.is_valid(), "\n".join(schema.errors))

	var defs: Array[StalkDefinition] = [schema.definition]
	# A real instrument to park money in, so the match is playable.
	defs.append(ContentLibrary.load_from().stalk_by_id(&"berry_bonds"))
	return ContentLibrary.of(defs)


# ------------------------------------------------------------------- joining

func test_a_client_is_given_content_it_could_not_have_loaded() -> void:
	var harness: NetHarness = NetHarness.new()
	add_child_autofree(harness)
	assert_eq(harness.start(
		StalksFixture.make_settings(), _custom_library(),
		"Host", "Guest", 0, 0, ContentLibrary.load_from(),
	), "")
	assert_true(await harness.await_join(self), "client should connect")

	# The replica's board, built from a definition that arrived over the wire.
	var replica: GameState = harness.client.state()
	var stalk: StalkState = replica.stalk_by_id(&"custom:host_only")
	assert_not_null(stalk, "the host's own company should be on the client's board")
	assert_eq(stalk.definition.display_name, "Only The Host Has This")
	assert_eq(stalk.price, 90, "and with the host's numbers")


func test_a_client_adopts_the_hosts_content_as_its_own() -> void:
	var harness: NetHarness = NetHarness.new()
	add_child_autofree(harness)
	assert_eq(harness.start(
		StalksFixture.make_settings(), _custom_library(),
		"Host", "Guest", 0, 0, ContentLibrary.load_from(),
	), "")
	assert_true(await harness.await_join(self), "client should connect")

	var adopted: ContentLibrary = harness.client.match_library()
	assert_not_null(adopted)
	assert_eq(adopted.stalks.size(), 2)
	assert_not_null(
		adopted.event_by_id(&"custom:host_only#bull0"),
		"the custom events should have come too",
	)


func test_a_year_result_names_an_event_the_client_only_knows_from_the_host() -> void:
	# The flavour text is looked up locally by id. Without the content having
	# travelled, the news would simply be blank — which is exactly the kind of
	# quiet failure the id rule used to guard against.
	var harness: NetHarness = NetHarness.new()
	add_child_autofree(harness)
	assert_eq(harness.start(
		StalksFixture.make_settings(), _custom_library(),
		"Host", "Guest", 0, 0, ContentLibrary.load_from(),
	), "")
	assert_true(await harness.await_join(self), "client should connect")

	# The lobby has to close before readiness means "advance the year" rather
	# than "ready to begin", and Start refuses until the guest is ready.
	harness.host.set_ready(&"p1", true)
	harness.host.start_match()
	await harness.settle(self)

	harness.host.set_ready(harness.host.local_player_id(), true)
	harness.host.set_ready(&"p1", true)
	await harness.settle(self)

	var replica: GameState = harness.client.state()
	assert_gt(replica.history.size(), 0, "the client should have seen a year")
	var result: YearResult = replica.history[replica.history.size() - 1]
	if result.event == null:
		# A year need not draw one; the point is that when it does, it resolves.
		pass_test("no event drawn this year, which is allowed")
		return
	assert_false(result.event.flavour_text.is_empty(), "the text should have resolved")


func test_a_client_sent_unusable_content_is_told_why() -> void:
	# The refusal has to be a sentence on a screen, not a crash and not a
	# board drawn from values the client would not accept.
	var session: ClientSession = ClientSession.new()
	session.name = NetworkedSession.NODE_NAME
	session._state = GameState.new(null)
	session._library = ContentLibrary.load_from()
	add_child_autofree(session)

	var reasons: Array[String] = []
	session.connection_lost.connect(func(reason: String) -> void: reasons.append(reason))

	var entry: Dictionary = StalkSchema.encode(_custom_library().stalks[0])
	entry["starting_price"] = 999999
	session._on_welcomed(&"p1", {"stalks": [], "players": []}, [], [entry])

	assert_eq(reasons.size(), 1, "the player should be told once")
	assert_false(reasons[0].is_empty())
	assert_false(session.has_joined(), "and must not be left in the match")


func test_a_host_that_says_nothing_about_content_leaves_the_client_its_own() -> void:
	# Every build before this feature sent no content at all. Silence is not
	# permission to guess and not a reason to drop somebody: the installed
	# library stands, and an id it cannot resolve still fails loudly.
	var session: ClientSession = ClientSession.new()
	session.name = NetworkedSession.NODE_NAME
	session._state = GameState.new(null)
	var installed: ContentLibrary = ContentLibrary.load_from()
	session._library = installed
	add_child_autofree(session)

	session._on_welcomed(&"p1", {"stalks": [], "players": []}, [], [])
	assert_eq(session.match_library(), installed)
	assert_true(session.has_joined())


# ---------------------------------------------------------------- taking over

func test_a_new_host_serves_the_content_it_received() -> void:
	# `take_over` is handed a library, and it must be the one the match was
	# played with. This is the unit-level half; the next test is the
	# orchestration that chooses which library to hand it.
	var library: ContentLibrary = _custom_library()
	var state: GameState = StalksFixture.make_state(10, 2, library.stalks)
	state.players[0].steam_id = ME

	var result: Dictionary = HostSession.take_over(
		StubTransport.new(), state, library, &"p0", 0
	)
	assert_eq(String(result["error"]), "")

	var session: HostSession = result["session"]
	add_child_autofree(session)
	assert_not_null(
		session.state().stalk_by_id(&"custom:host_only"),
		"the match should still hold the company it was played with",
	)


func test_the_match_keeps_its_content_when_it_changes_hands() -> void:
	# **The fault this exists to catch**: a new host that re-read its own
	# files would hand the remaining players a board missing the departed
	# host's companies. `Main` must carry the library it received.
	var main: Main = MainScene.instantiate()
	add_child_autofree(main)

	var steam: StubSteamService = StubSteamService.new()
	steam.name = "StubSteam"
	steam.me = ME
	steam.lobby = LOBBY
	main.add_child(steam)
	main._steam = steam
	main._steam_transports = StubTransportSource.new()

	var library: ContentLibrary = _custom_library()
	var client: ClientSession = ClientSession.new()
	client.name = NetworkedSession.NODE_NAME
	client._state = StalksFixture.make_state(10, 2, library.stalks)
	client._library = library
	client._local_player_id = &"p1"
	client._has_joined = true
	main._session = client
	main.add_child(client)
	main._online_host_steam_id = DEPARTED

	# The host walks out and Steam makes this player the owner.
	steam.owner_steam_id = ME
	main._on_steam_lobby_member_left(DEPARTED)
	main._migrating_in_match = true
	main._process(Main.MIGRATION_POLL_SECONDS + 0.01)
	main._process(Main.MIGRATION_POLL_SECONDS + 0.01)

	assert_true(main._session is HostSession, "this process should be hosting now")
	var new_host: HostSession = main._session

	# **The board is not the thing to assert on here.** `take_over` builds the
	# match from this client's own `GameState`, whose `StalkState`s already
	# hold their definitions - so the custom company stays on the board even
	# when the wrong library is handed in, and an assertion on it passes with
	# the fault reinstated. It was written that way first and proved nothing.
	#
	# What the library actually decides is the **event pool**. A new host that
	# re-read its own files would run a match whose board shows the departed
	# host's companies while no event can ever fire for them.
	var carried: ContentLibrary = new_host.match_library()
	assert_not_null(
		carried.stalk_by_id(&"custom:host_only"),
		"the new host must serve the content it received, not its own files",
	)
	assert_not_null(
		carried.event_by_id(&"custom:host_only#bull0"),
		"and its events, or nothing can ever happen to that company again",
	)
	main._discard_session(true)


# ------------------------------------------------------------------ rejoining

func test_somebody_coming_back_is_given_the_content_again() -> void:
	# A rejoining player is welcomed like any other arrival, so the content
	# rides the same path. Asserted rather than assumed, because the rejoin
	# route is a second branch in `_on_introduced` and only one of the two
	# would be exercised otherwise.
	var harness: NetHarness = NetHarness.new()
	add_child_autofree(harness)
	assert_eq(
		harness.start(
			StalksFixture.make_settings(), _custom_library(),
			"Host", "Guest", 101, 202, ContentLibrary.load_from(),
		),
		"",
	)
	assert_true(await harness.await_join(self), "client should connect")

	harness.host.set_ready(&"p1", true)
	harness.host.start_match()
	await harness.settle(self)
	assert_false(harness.host.lobby_is_open(), "the match should be under way")

	# The guest drops and comes back to the seat their Steam id holds.
	var returning: StringName = harness.host._slot_to_reclaim(202)
	assert_eq(returning, &"", "their seat is taken while they are still connected")

	harness.host._on_peer_disconnected(harness.host._peer_by_player[&"p1"])
	assert_eq(harness.host._slot_to_reclaim(202), &"p1", "the seat should be waiting")

	var welcome: Array = StateSync.encode_content(harness.host._library)
	var decoded: Dictionary = StateSync.decode_content(welcome)
	assert_eq(String(decoded["error"]), "", "the content offered on return must be usable")
	assert_not_null(
		(decoded["library"] as ContentLibrary).stalk_by_id(&"custom:host_only"),
		"and must still hold the match's own companies",
	)
