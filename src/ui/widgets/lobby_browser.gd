class_name LobbyBrowser
extends VBoxContainer
## The list of games being hosted online. Lives inside the title screen's
## **Join Game** panel.
##
## **It used to be a screen of its own**, reached by a BROWSE ONLINE GAMES
## button on a Join panel that otherwise held a direct-connection form. That
## was a button whose only job was to show the thing the player had already
## asked for. The list now loads when Join Game is selected, and the direct
## connection moved to the development overlay (`dev_overlay.gd`).
##
## It lists and it joins. It does not create a game and it has no settings on
## it, because neither belongs to somebody looking for a match to join: the
## host owns the settings and sends them with the opening state
## (architecture.md §5.3).
##
## **It used to be the "Steam screen"**, with a HOST button and a read-only
## summary of settings chosen somewhere else. That was wrong twice over: Steam
## is a transport, not a category of thing a player wants to do, and a game was
## being created on a screen whose job is finding games. Creating one now
## happens under Create Game like every other kind. See docs/decisions.md D65.
##
## The only screen that touches `SteamService`, and even then only through its
## signals. `Main` owns the service and turns a chosen lobby into a session.
##
## **It must survive Steam being absent.** A checkout without the plugin, or a
## machine with Steam closed, has to reach this screen and be told why it is
## empty rather than crash. That is the same requirement as D14 — the game runs
## without Steam — applied to the one screen that cannot.


## The player picked a game. Only the asking happens here: getting into a
## Steam lobby is `Main`'s job, because the same thing has to work from an
## invite, when this screen is not on display at all.
signal join_requested(lobby_id: int)


const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/steam_lobby_row.tscn")


@onready var _status: Label = %Status
@onready var _persona: Label = %Persona
@onready var _list: VBoxContainer = %LobbyList
@onready var _empty: Label = %EmptyNote
@onready var _refresh_button: Button = %RefreshButton
@onready var _search_field: LineEdit = %SearchField

var _service: SteamService

## Whether `setup` has been called. Not `_service != null`, because a null
## service is a real answer — it means a build with no Steam plugin — and that
## case still has to reach `_attach` and be reported.
var _was_set_up: bool = false

## The last list Steam sent, unfiltered. Kept so typing in the search box can
## narrow it without asking Steam again — and so clearing the box puts
## everything back without a round trip.
var _found: Array[Dictionary] = []


func _ready() -> void:
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_search_field.text_changed.connect(_on_search_changed)
	if _was_set_up:
		_attach()


## Hands the screen the service. `Main` owns it, because Steam is initialised
## once per process and outlives any one screen.
func setup(service: SteamService) -> void:
	_service = service
	_was_set_up = true
	if is_node_ready():
		_attach()


func _attach() -> void:
	# No service at all is the extreme case of Steam being unavailable: a build
	# without the plugin. The screen still has to come up and say so.
	if _service == null:
		_show_unavailable("Steam is not available in this build.")
		return

	_service.lobby_failed.connect(_on_lobby_failed)
	_service.lobby_list.connect(_on_lobby_list)

	if not _service.is_running():
		var problem: String = _service.start()
		if not problem.is_empty():
			_show_unavailable(problem)
			return

	_persona.text = "Signed in as %s" % _service.persona_name()
	_status.text = "Looking for games..."
	_service.refresh_lobbies()


## Stops listening on the way out. The same deferred-`queue_free` trap as every
## other screen — see decisions.md D50.
func _detach() -> void:
	if _service == null:
		return
	if _service.lobby_failed.is_connected(_on_lobby_failed):
		_service.lobby_failed.disconnect(_on_lobby_failed)
		_service.lobby_list.disconnect(_on_lobby_list)


func _exit_tree() -> void:
	_detach()


## Public so a test can read the list without reaching into the tree.
func lobby_rows() -> Array[Node]:
	return _list.get_children()


func _show_unavailable(reason: String) -> void:
	_persona.text = ""
	_status.text = reason
	_refresh_button.disabled = true
	_search_field.editable = false
	_empty.visible = false
	_found = []
	_clear_list()


func _on_refresh_pressed() -> void:
	if _service == null or not _service.is_running():
		return
	_status.text = "Looking for games..."
	_service.refresh_lobbies()


func _on_row_join_requested(lobby_id: int) -> void:
	_status.text = "Joining..."
	join_requested.emit(lobby_id)


# ------------------------------------------------------------- what Steam says

func _on_lobby_failed(reason: String) -> void:
	_status.text = reason


func _on_lobby_list(lobbies: Array[Dictionary]) -> void:
	_found = lobbies
	_show_matching()


## Narrows the list as the player types.
##
## **Filtered here rather than asked of Steam**, because Steam's lobby list
## has no name filter worth the name and a round trip per keystroke would be
## absurd. Case-insensitive substring, as the original's Search button did.
##
## **The filter does not stick.** Emptying the box puts the whole list back
## immediately, and a refresh re-applies whatever is in the box right now.
## The original kept a "did the player search" flag that was never cleared on
## any path the normal flow reached, so once you had searched the filter went
## on applying to later refreshes for ever (audit §3.3).
func _on_search_changed(_text: String) -> void:
	_show_matching()


func _show_matching() -> void:
	_clear_list()

	var wanted: String = _search_field.text.strip_edges().to_lower()
	var shown: int = 0
	for lobby: Dictionary in _found:
		var name: String = String(lobby.get("name", "")).to_lower()
		if not wanted.is_empty() and not name.contains(wanted):
			continue
		var row: SteamLobbyRow = LobbyRowScene.instantiate()
		_list.add_child(row)
		row.display(lobby)
		row.join_requested.connect(_on_row_join_requested)
		shown += 1

	_empty.visible = shown == 0
	_status.text = _count_of(shown, wanted)


## How many games are on screen, and why there are none if there are none.
func _count_of(shown: int, wanted: String) -> String:
	if shown == 0 and not wanted.is_empty():
		return "No games match \"%s\"." % wanted
	if shown == 0:
		return "No games right now. Host one from Host Online."
	if shown == 1:
		return "1 game available"
	return "%d games available" % shown


## Removes rows immediately rather than only queueing them, so a refresh never
## briefly shows every lobby twice. See decisions.md D50.
func _clear_list() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
