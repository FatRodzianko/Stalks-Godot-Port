extends GutTest
## The Steam transport and browser, as far as they go without Steam.
##
## **These must pass on a machine with no Steam client and no plugin.** The port
## runs without Steam (decisions.md D14), the suite has to run in the same
## conditions, and a test that only passes on one machine is worse than no test.
## So nothing here calls Steam: it covers argument handling, the interface
## contract, and the browser's rendering, which is where the mistakes a test can
## catch actually live.
##
## Live Steam was exercised by hand during Phase 6 — see
## docs/steam-integration.md section 5.


const BrowserScene: PackedScene = preload(
	"res://src/ui/widgets/lobby_browser.tscn"
)
const RowScene: PackedScene = preload("res://src/ui/widgets/steam_lobby_row.tscn")


# ------------------------------------------------------------------ transport

func test_it_is_a_transport() -> void:
	# The whole point: a session takes this exactly as it takes EnetTransport.
	assert_true(SteamTransport.new(123) is Transport)


func test_hosting_without_a_lobby_is_refused() -> void:
	var opened: Dictionary = SteamTransport.new(0).open_server(9)
	assert_null(opened["peer"])
	assert_string_contains(String(opened["error"]).to_lower(), "lobby")


func test_joining_without_a_host_is_refused() -> void:
	# A lobby whose owner could not be resolved. Connecting to id 0 would fail
	# somewhere deep inside Steam with a far worse message.
	var opened: Dictionary = SteamTransport.new(123, 0).open_client()
	assert_null(opened["peer"])
	assert_string_contains(String(opened["error"]).to_lower(), "host")


func test_the_joining_hint_mentions_invites_not_a_port() -> void:
	# The lobby screen prints this verbatim. There is no port to read out, which
	# is exactly why the screen asks the transport instead of formatting one.
	var hint: String = SteamTransport.new(123).joining_hint().to_lower()
	assert_string_contains(hint, "invite")
	assert_false(hint.contains("port"), "got: %s" % hint)


func test_it_remembers_its_lobby() -> void:
	var transport: SteamTransport = SteamTransport.new(456, 789, "A game")
	assert_eq(transport.lobby_id(), 456)
	assert_eq(transport.lobby_name(), "A game")
	assert_string_contains(transport.describe(), "456")


# ----------------------------------------------------------------- lobby rows

func test_a_lobby_row_shows_its_name_and_count() -> void:
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display({"id": 7, "name": "A game", "players": 2, "capacity": 10})

	assert_eq(row.get_node("%Name").text, "A game")
	assert_eq(row.get_node("%Players").text, "2/10")
	assert_false(row.get_node("%JoinButton").disabled)
	assert_eq(row.lobby_id(), 7)


func test_a_full_lobby_cannot_be_joined() -> void:
	# Offering a button that is certain to fail is worse than not offering it.
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display({"id": 7, "name": "Full", "players": 10, "capacity": 10})

	assert_true(row.get_node("%JoinButton").disabled)


func test_a_nameless_lobby_still_renders() -> void:
	# Lobby metadata is set just after creation, so there is a window where a
	# lobby exists with no name. It must not show as a blank row.
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display({"id": 7, "players": 1, "capacity": 4})

	assert_ne(row.get_node("%Name").text, "")


func test_pressing_join_carries_the_lobby_id() -> void:
	var row: SteamLobbyRow = RowScene.instantiate()
	add_child_autofree(row)
	row.display({"id": 42, "name": "A game", "players": 1, "capacity": 4})

	var asked: Array[int] = []
	row.join_requested.connect(func(id: int) -> void: asked.append(id))
	row.get_node("%JoinButton").pressed.emit()

	assert_eq(asked, [42] as Array[int])


# ---------------------------------------------------------------- the browser

## The browser with no service attached. It has to survive that state: `Main`
## shows the screen first and hands it Steam afterwards.
func _browser() -> LobbyBrowser:
	var browser: LobbyBrowser = BrowserScene.instantiate()
	add_child_autofree(browser)
	return browser


func test_the_browser_survives_having_no_service() -> void:
	var browser: LobbyBrowser = _browser()
	assert_eq(browser.lobby_rows().size(), 0)
	browser.get_node("%RefreshButton").pressed.emit()
	assert_true(true, "pressing things with no service must not crash")


func test_the_browser_lists_what_steam_reports() -> void:
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "First", "players": 1, "capacity": 10},
		{"id": 2, "name": "Second", "players": 3, "capacity": 10},
	] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 2)
	assert_eq(browser.lobby_rows()[1].get_node("%Name").text, "Second")
	assert_string_contains(browser.get_node("%Status").text, "2 game")


func test_an_empty_list_says_so_rather_than_looking_broken() -> void:
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list([] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 0)
	assert_true(browser.get_node("%EmptyNote").visible)


func test_refreshing_replaces_the_list_rather_than_doubling_it() -> void:
	# Rows are removed immediately, not queued, or a refresh briefly shows every
	# lobby twice. The same trap as D50.
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "First", "players": 1, "capacity": 10},
	] as Array[Dictionary])
	browser._on_lobby_list([
		{"id": 2, "name": "Second", "players": 1, "capacity": 10},
	] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 1)
	assert_eq(browser.lobby_rows()[0].get_node("%Name").text, "Second")


func test_one_game_is_not_described_as_one_games() -> void:
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "Only", "players": 1, "capacity": 10},
	] as Array[Dictionary])
	assert_string_contains(browser.get_node("%Status").text, "1 game available")


func test_a_failure_is_reported_rather_than_swallowed() -> void:
	var browser: LobbyBrowser = _browser()

	browser._on_lobby_failed("Steam could not reach that lobby.")

	assert_string_contains(browser.get_node("%Status").text, "could not reach")
	assert_false(
		browser.get_node("%RefreshButton").disabled,
		"a failed attempt must leave the player able to try again",
	)


func test_the_empty_note_points_at_where_games_are_made() -> void:
	# This screen no longer hosts, so an empty list has to say where to go.
	var browser: LobbyBrowser = _browser()
	browser._on_lobby_list([] as Array[Dictionary])

	var said: String = (
		(browser.get_node("%EmptyNote") as Label).text
		+ " " + (browser.get_node("%Status") as Label).text
	).to_lower()
	assert_string_contains(said, "host online")


# ------------------------------------------------ lobby departures, decoded
#
# `lobby_chat_update` is how Steam reports somebody leaving. It is the only
# thing that reports a host going away over Steam — the peer-to-peer session
# itself just goes quiet. See decisions.md D68.
#
# These drive `SteamService._on_lobby_chat_update` directly, with no Steam
# behind it, because the decoding of the bitfield is the part worth pinning
# and it is pure arithmetic.

func _service_in_lobby(lobby_id: int) -> SteamService:
	var service: SteamService = SteamService.new()
	add_child_autofree(service)
	service._lobby_id = lobby_id
	return service


func _departures_seen(chat_state: int) -> Array:
	var service: SteamService = _service_in_lobby(77)
	var seen: Array = []
	service.lobby_member_left.connect(func(id: int) -> void: seen.append(id))
	service._on_lobby_chat_update(77, 1234, 0, chat_state)
	return seen


func test_a_member_leaving_is_reported() -> void:
	assert_eq(_departures_seen(0x0002), [1234])


func test_a_member_dropping_out_is_reported_too() -> void:
	# Disconnected rather than Left: a crash or a pulled cable, which for this
	# game has exactly the same consequence.
	assert_eq(_departures_seen(0x0004), [1234])


func test_a_kicked_member_is_reported() -> void:
	assert_eq(_departures_seen(0x0008), [1234])


func test_a_member_arriving_is_not_a_departure() -> void:
	# Entered. The game hears about arrivals through its own networking.
	assert_eq(_departures_seen(0x0001), [])


func test_a_departure_from_another_lobby_is_ignored() -> void:
	var service: SteamService = _service_in_lobby(77)
	var seen: Array = []
	service.lobby_member_left.connect(func(id: int) -> void: seen.append(id))
	service._on_lobby_chat_update(99, 1234, 0, 0x0002)
	assert_eq(seen, [])


# --------------------------------------------- Steam's refusals, in words
#
# Found in play: clicking a game in a list that had not been refreshed since
# it started gave "Could not join that game (code 3)". The refusal was right
# — the host marks a started lobby unjoinable — but a bare number is not a
# message. The codes are EChatRoomEnterResponse, read off the installed
# plugin.

func _refusal_for(response: int) -> String:
	var service: SteamService = SteamService.new()
	add_child_autofree(service)
	return service._why_refused(response)


func test_a_started_or_closed_game_says_so() -> void:
	var said: String = _refusal_for(SteamService.ENTER_NOT_ALLOWED).to_lower()
	assert_string_contains(said, "not open")
	assert_false(said.contains("code"), "got: %s" % said)


func test_a_vanished_game_says_so() -> void:
	assert_string_contains(
		_refusal_for(SteamService.ENTER_DOESNT_EXIST).to_lower(), "no longer exists"
	)


func test_a_full_game_says_so() -> void:
	assert_string_contains(_refusal_for(SteamService.ENTER_FULL).to_lower(), "full")


func test_an_unexpected_refusal_keeps_its_number() -> void:
	# A ban or a rate limit. Rare enough not to deserve wording, common enough
	# that the player needs something to report.
	assert_string_contains(_refusal_for(15), "15")


# ------------------------------------------------- invites, from a cold start
#
# Accepting an invite to a game that is not running launches it with
# `+connect_lobby <id>`. That is the only way an invite can work from closed,
# and it has to work in a **release** build — which is why it is not a
# `LaunchArgs` flag, since those are ignored outside a debug build. The parse
# is pure, so it is tested without Steam. See decisions.md D69.

func test_an_invite_launch_names_the_lobby() -> void:
	assert_eq(
		SteamService.lobby_from_command_line(
			PackedStringArray(["+connect_lobby", "109775241009"])
		),
		109775241009,
	)


func test_an_ordinary_launch_names_no_lobby() -> void:
	assert_eq(
		SteamService.lobby_from_command_line(PackedStringArray(["--host", "--ready"])),
		0,
	)


func test_a_connect_lobby_with_nothing_after_it_is_ignored() -> void:
	assert_eq(
		SteamService.lobby_from_command_line(PackedStringArray(["+connect_lobby"])), 0
	)


func test_a_nonsense_lobby_id_is_ignored_rather_than_crashing() -> void:
	assert_eq(
		SteamService.lobby_from_command_line(
			PackedStringArray(["+connect_lobby", "not-a-number"])
		),
		0,
	)


func test_the_lobby_is_found_among_other_arguments() -> void:
	assert_eq(
		SteamService.lobby_from_command_line(
			PackedStringArray(["--verbose", "+connect_lobby", "42", "--fullscreen"])
		),
		42,
	)


# -------------------------------------------------- the list only asks to join
#
# Getting into a Steam lobby moved to `Main`, because the same thing has to
# work from an invite, when this screen is not on display at all.

func test_a_row_asks_to_join_and_nothing_more() -> void:
	var browser: LobbyBrowser = _browser()
	var asked: Array = []
	browser.join_requested.connect(func(lobby_id: int) -> void: asked.append(lobby_id))

	browser._on_row_join_requested(4242)

	assert_eq(asked, [4242])


## Steam is started at launch now rather than on the first click of Join Game,
## which visibly stalled the panel (D59, amended). The suite still must not
## reach for Steam, so the warm-up skips itself without a display.
func test_warming_up_steam_does_nothing_without_a_display() -> void:
	var main: Main = preload("res://src/ui/screens/main/main.tscn").instantiate()
	add_child_autofree(main)

	main.warm_up_steam()

	assert_false(
		DisplayMode.has_a_real_window(),
		"this assertion only means anything headless, which is where the suite runs",
	)
	assert_null(main.session(), "and nothing about the game changed")
