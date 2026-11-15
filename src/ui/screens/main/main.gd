class_name Main
extends MarginContainer
## The screen host: holds exactly one screen at a time and moves between them.
##
## This exists so screens stay ignorant of each other. The menu does not know
## about the playing screen, and the playing screen does not know what happens
## after a match — each emits intent and this decides.
##
## It also owns the session, so a session outlives the screen that displays it
## long enough for the result screen to read the finished state.


const MenuScene: PackedScene = preload("res://src/ui/screens/main_menu/main_menu.tscn")
const GameplayScene: PackedScene = preload("res://src/ui/screens/gameplay/gameplay_screen.tscn")
const GameOverScene: PackedScene = preload("res://src/ui/screens/game_over/game_over_screen.tscn")
const LobbyScene: PackedScene = preload("res://src/ui/screens/lobby/lobby_screen.tscn")
const SteamBrowserScene: PackedScene = preload(
	"res://src/ui/screens/steam_browser/steam_browser_screen.tscn"
)

var _screen: Control

## The live session, whichever kind it is. Typed as the interface, not
## `LocalSession`, so hosting and joining need no second code path here.
var _session: GameSession

var _last_settings: GameSettings

## Kept so the lobby can tell the host what port to share.
var _listening_port: int = 0

## What this process was launched with, for the `--ready` / `--autostart`
## conveniences. MENU unless flags were given.
var _launch: LaunchArgs = LaunchArgs.new()

## The lobby `--ready` should press the button on. Held because the handler is
## a named method rather than a closure that could capture it.
var _automated_lobby: LobbyScreen

## Steam, created the first time somebody asks for it and kept for the life of
## the process. Never an autoload: a game played offline, and every test run,
## must never touch Steam at all. See docs/decisions.md D59.
var _steam: SteamService


func _ready() -> void:
	apply_launch_args(LaunchArgs.from_command_line())


## Obeys `--host` / `--join` if they were given, otherwise shows the menu.
##
## Separate from `_ready` and taking its arguments explicitly so the behaviour can
## be tested without a command line. `from_command_line()` returns MENU in a
## release build, so a shipped game always lands here on the menu.
func apply_launch_args(launch: LaunchArgs) -> void:
	_launch = launch
	match launch.mode:
		LaunchArgs.Mode.HOST:
			_report_launch_problem(
				host_match(launch.host_settings(), launch.resolved_name(), launch.port)
			)
		LaunchArgs.Mode.JOIN:
			_report_launch_problem(
				join_match(launch.address, launch.port, launch.resolved_name())
			)
		_:
			show_menu()


## A failed auto-host or auto-join falls back to the menu with the reason on it.
## Leaving a blank screen would be a miserable way to discover that a port is
## busy.
func _report_launch_problem(problem: String) -> void:
	if problem.is_empty():
		return
	show_menu()
	_report_to_menu(problem)


func show_menu() -> void:
	_discard_session()
	var menu: MainMenu = MenuScene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
	menu.steam_requested.connect(show_steam_browser)
	_swap(menu)


## Starts a match. Public so a test can begin one without driving the menu.
func start_match(settings: GameSettings) -> void:
	_discard_session()
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return

	_mount_session(LocalSession.create(settings, library))

	var gameplay: Control = GameplayScene.instantiate()
	gameplay.setup(_session)
	gameplay.match_finished.connect(_on_match_finished)
	_swap(gameplay)


func current_screen() -> Control:
	return _screen


func session() -> GameSession:
	return _session


# -------------------------------------------------------------------- networked
#
# Hosting and joining both end in the same place: a session, mounted here, and
# the lobby screen watching it. What differs is only how the session is built.

## Opens a lobby and shows it. Returns an error string, empty on success.
func host_match(settings: GameSettings, player_name: String, port: int) -> String:
	_discard_session()
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return "The game's content is broken — see the log."

	var result: Dictionary = HostSession.host(
		EnetTransport.new(port), settings, library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = port
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


## Connects to somebody else's lobby. An empty return means the socket opened —
## the connection itself is asynchronous and reported by the lobby screen.
func join_match(address: String, port: int, player_name: String) -> String:
	_discard_session()

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return "The game's content is broken — see the log."

	var result: Dictionary = ClientSession.join(
		EnetTransport.new(port, address), library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


## Steam, started on first use. Public so a test can see whether anything has
## touched it.
func steam_service() -> SteamService:
	if _steam == null:
		_steam = SteamService.new()
		_steam.name = "SteamService"
		add_child(_steam)
	return _steam


## The Steam lobby browser. Reachable even when Steam is unavailable — the
## screen explains why rather than the menu silently refusing.
func show_steam_browser() -> void:
	_discard_session()
	var browser: SteamBrowserScreen = SteamBrowserScene.instantiate()
	browser.back_requested.connect(show_menu)
	browser.host_requested.connect(_on_steam_host_requested)
	browser.join_requested.connect(_on_steam_join_requested)
	_swap(browser)
	browser.setup(steam_service())


## Hosts inside a Steam lobby that already exists. The browser created it and
## waited for Steam to answer, so by here there is nothing left to wait for.
func host_steam_match(lobby_id: int, settings: GameSettings, player_name: String) -> String:
	_discard_session()
	_last_settings = settings

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return "The game's content is broken — see the log."

	var result: Dictionary = HostSession.host(
		SteamTransport.new(lobby_id), settings, library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: HostSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


func join_steam_match(lobby_id: int, owner_steam_id: int, player_name: String) -> String:
	_discard_session()

	var library: ContentLibrary = _loaded_library()
	if library == null:
		return "The game's content is broken — see the log."

	var result: Dictionary = ClientSession.join(
		SteamTransport.new(lobby_id, owner_steam_id), library, player_name
	)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


func _on_steam_host_requested(lobby_id: int) -> void:
	var settings: GameSettings = (
		_last_settings if _last_settings != null else GameSettings.new()
	)
	var problem: String = host_steam_match(lobby_id, settings, _steam_name())
	if not problem.is_empty():
		show_menu()
		_report_to_menu(problem)


func _on_steam_join_requested(lobby_id: int, owner_steam_id: int) -> void:
	var problem: String = join_steam_match(lobby_id, owner_steam_id, _steam_name())
	if not problem.is_empty():
		show_menu()
		_report_to_menu(problem)


## The player's Steam display name, which saves them typing one.
func _steam_name() -> String:
	var persona: String = _steam.persona_name() if _steam != null else ""
	return persona if not persona.is_empty() else "Player"


func _show_lobby() -> void:
	var lobby: LobbyScreen = LobbyScene.instantiate()
	lobby.leave_requested.connect(show_menu)
	lobby.play_requested.connect(_on_play_requested)
	lobby.connection_ended.connect(_on_connection_ended)
	_swap(lobby)
	# After the swap, so the screen is in the tree and its @onready nodes exist.
	lobby.setup(_session, _listening_port)
	_apply_lobby_automation(lobby)


## The `--ready` / `--autostart` development conveniences. Does nothing unless
## those flags were given, which they never are outside a debug build.
##
## `--ready` presses the lobby's own button rather than calling the session, so
## that a scripted two-process run exercises the same path a player does. An
## automation that takes a shortcut past the UI cannot reproduce a UI bug.
func _apply_lobby_automation(lobby: LobbyScreen) -> void:
	if _launch.auto_ready:
		var client: ClientSession = _session as ClientSession
		if client != null:
			_automated_lobby = lobby
			client.joined.connect(_on_automation_joined)

	if _launch.auto_start:
		var host: HostSession = _session as HostSession
		if host != null:
			host.ready_state_changed.connect(_on_automation_ready_changed)


## `--ready`: press the lobby's own button as soon as this client is seated.
func _on_automation_joined(_player_id: StringName) -> void:
	if _automated_lobby != null:
		_automated_lobby.press_ready_for_testing()


## `--autostart`: begin as soon as the gate allows it. Readiness is the only
## thing the gate waits on once somebody has joined, so this is the only moment
## worth re-checking.
func _on_automation_ready_changed(_player_id: StringName, _is_ready: bool) -> void:
	var host: HostSession = _session as HostSession
	if host == null:
		return
	if host.why_not_start().is_empty() and host.state().players.size() > 1:
		host.start_match()


## Kicked, or the host quit. Back to the menu, carrying the reason: a player
## left sitting in a lobby they are no longer part of has no idea what happened.
func _on_connection_ended(reason: String) -> void:
	show_menu()
	_report_to_menu(reason)


## The lobby is done with: show the board. The session is untouched — the match
## has already begun as far as the host is concerned.
func _on_play_requested() -> void:
	var gameplay: Control = GameplayScene.instantiate()
	gameplay.setup(_session)
	gameplay.match_finished.connect(_on_match_finished)
	_swap(gameplay)


## A session must be in the tree before `attach_peer`, because `multiplayer`
## resolves by node path — see architecture.md §5.2.
func _mount_session(session: GameSession) -> void:
	_session = session
	add_child(_session)


## A busy port or an unreachable host is a normal thing for a player to run into,
## not a fault in the game, so it goes on the screen rather than into the log.
## `push_error` is reserved for things that mean the build is broken — bad
## content, say.
func _on_host_requested(settings: GameSettings, player_name: String, port: int) -> void:
	var problem: String = host_match(settings, player_name, port)
	if not problem.is_empty():
		_report_to_menu(problem)


func _on_join_requested(address: String, port: int, player_name: String) -> void:
	var problem: String = join_match(address, port, player_name)
	if not problem.is_empty():
		_report_to_menu(problem)


## Puts a failure back on the menu, where the player still is. Nothing has been
## swapped at this point, so the menu is still the current screen.
func _report_to_menu(problem: String) -> void:
	var menu: MainMenu = _screen as MainMenu
	if menu != null:
		menu.show_problem(problem)


func _on_start_requested(settings: GameSettings) -> void:
	start_match(settings)


func _on_match_finished(_winners: Array[StringName]) -> void:
	# The state is read from the session, which this node owns, so it is still
	# alive after the playing screen goes away.
	var finished_state: GameState = _session.state()
	var local_id: StringName = _session.local_player_id()

	var over: GameOverScreen = GameOverScene.instantiate()
	over.play_again_requested.connect(_on_play_again)
	over.menu_requested.connect(show_menu)
	_swap(over)
	over.display(finished_state, local_id)


func _on_play_again() -> void:
	if _last_settings == null:
		show_menu()
		return
	# A fresh seed, so "play again" is a new market rather than a replay. The
	# chosen seed, if the player typed one, is deliberately not reused.
	var settings: GameSettings = _last_settings.duplicate() as GameSettings
	settings.rng_seed = 0
	start_match(settings)


## Replaces the current screen. Removes the old one from the tree immediately
## rather than only queueing it, so nothing briefly sees two screens at once —
## the same deferred-free trap described in docs/architecture.md §6.
func _swap(next: Control) -> void:
	if _screen != null:
		remove_child(_screen)
		_screen.queue_free()
	_screen = next
	add_child(next)


## The validated content, or null with the problems already logged.
func _loaded_library() -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.load_from()
	if library.is_valid():
		return library
	for error: String in library.errors:
		push_error("Content error: %s" % error)
	return null


## Closes any transport before freeing the session, so a lobby left behind does
## not hold its socket open and block the next attempt on the same port.
func _discard_session() -> void:
	if _session == null:
		return
	var networked: NetworkedSession = _session as NetworkedSession
	if networked != null:
		networked.close()
	# Leaving the match means leaving the Steam lobby too, or the browser would
	# keep listing a game nobody is in.
	if _steam != null and _steam.is_running():
		_steam.leave_lobby()
	remove_child(_session)
	_session.queue_free()
	_session = null
	_listening_port = 0
