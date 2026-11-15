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
	"res://src/ui/screens/steam_browser/steam_browser_screen.tscn"
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
func _browser() -> SteamBrowserScreen:
	var browser: SteamBrowserScreen = BrowserScene.instantiate()
	add_child_autofree(browser)
	return browser


func test_the_browser_survives_having_no_service() -> void:
	var browser: SteamBrowserScreen = _browser()
	assert_eq(browser.lobby_rows().size(), 0)
	browser.get_node("%HostButton").pressed.emit()
	browser.get_node("%RefreshButton").pressed.emit()
	assert_true(true, "pressing things with no service must not crash")


func test_the_browser_lists_what_steam_reports() -> void:
	var browser: SteamBrowserScreen = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "First", "players": 1, "capacity": 10},
		{"id": 2, "name": "Second", "players": 3, "capacity": 10},
	] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 2)
	assert_eq(browser.lobby_rows()[1].get_node("%Name").text, "Second")
	assert_string_contains(browser.get_node("%Status").text, "2 game")


func test_an_empty_list_says_so_rather_than_looking_broken() -> void:
	var browser: SteamBrowserScreen = _browser()
	browser._on_lobby_list([] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 0)
	assert_true(browser.get_node("%EmptyNote").visible)


func test_refreshing_replaces_the_list_rather_than_doubling_it() -> void:
	# Rows are removed immediately, not queued, or a refresh briefly shows every
	# lobby twice. The same trap as D50.
	var browser: SteamBrowserScreen = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "First", "players": 1, "capacity": 10},
	] as Array[Dictionary])
	browser._on_lobby_list([
		{"id": 2, "name": "Second", "players": 1, "capacity": 10},
	] as Array[Dictionary])

	assert_eq(browser.lobby_rows().size(), 1)
	assert_eq(browser.lobby_rows()[0].get_node("%Name").text, "Second")


func test_one_game_is_not_described_as_one_games() -> void:
	var browser: SteamBrowserScreen = _browser()
	browser._on_lobby_list([
		{"id": 1, "name": "Only", "players": 1, "capacity": 10},
	] as Array[Dictionary])
	assert_string_contains(browser.get_node("%Status").text, "1 game available")


func test_a_failure_is_reported_and_hosting_stays_possible() -> void:
	var browser: SteamBrowserScreen = _browser()
	browser.get_node("%HostButton").disabled = true

	browser._on_lobby_failed("Steam could not create the lobby.")

	assert_string_contains(browser.get_node("%Status").text, "could not create")
	assert_false(
		browser.get_node("%HostButton").disabled,
		"a failed attempt must leave the player able to try again",
	)
