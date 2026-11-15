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

var _screen: Control

## The live session, whichever kind it is. Typed as the interface, not
## `LocalSession`, so hosting and joining need no second code path here.
var _session: GameSession

var _last_settings: GameSettings

## Kept so the lobby can tell the host what port to share.
var _listening_port: int = 0


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	_discard_session()
	var menu: MainMenu = MenuScene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	menu.host_requested.connect(_on_host_requested)
	menu.join_requested.connect(_on_join_requested)
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

	var result: Dictionary = HostSession.host(port, settings, library, player_name)
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

	var result: Dictionary = ClientSession.join(address, port, library, player_name)
	if not String(result["error"]).is_empty():
		return String(result["error"])

	_listening_port = 0
	var session: ClientSession = result["session"]
	_mount_session(session)
	session.attach_peer(result["peer"])
	_show_lobby()
	return ""


func _show_lobby() -> void:
	var lobby: LobbyScreen = LobbyScene.instantiate()
	lobby.leave_requested.connect(show_menu)
	lobby.play_requested.connect(_on_play_requested)
	_swap(lobby)
	# After the swap, so the screen is in the tree and its @onready nodes exist.
	lobby.setup(_session, _listening_port)


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
	remove_child(_session)
	_session.queue_free()
	_session = null
	_listening_port = 0
