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

var _screen: Control
var _session: LocalSession
var _last_settings: GameSettings


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	_discard_session()
	var menu: MainMenu = MenuScene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	_swap(menu)


## Starts a match. Public so a test can begin one without driving the menu.
func start_match(settings: GameSettings) -> void:
	_discard_session()
	_last_settings = settings

	var library: ContentLibrary = ContentLibrary.load_from()
	if not library.is_valid():
		for error: String in library.errors:
			push_error("Content error: %s" % error)
		return

	_session = LocalSession.create(settings, library)
	add_child(_session)

	var gameplay: Control = GameplayScene.instantiate()
	gameplay.setup(_session)
	gameplay.match_finished.connect(_on_match_finished)
	_swap(gameplay)


func current_screen() -> Control:
	return _screen


func session() -> LocalSession:
	return _session


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


func _discard_session() -> void:
	if _session != null:
		remove_child(_session)
		_session.queue_free()
		_session = null
