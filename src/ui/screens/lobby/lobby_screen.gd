class_name LobbyScreen
extends MarginContainer
## The waiting room: who is here, who is ready, and the host's Start button.
##
## Serves both sides. The difference is small and entirely about what you are
## allowed to do — only the host can start, and only the host knows the port
## worth sharing — so one screen with two modes beats two screens that would
## drift apart.
##
## Like every screen it emits intent and knows nothing about what happens next.
## It reads the session it is given and never mutates the match.


## The player asked to leave. The screen host decides whether that means closing
## a server or disconnecting a client.
signal leave_requested

## The host pressed Start, or the client was told the match began. Either way the
## screen host swaps in the playing screen.
signal play_requested


const LobbyRowScene: PackedScene = preload("res://src/ui/widgets/lobby_row.tscn")


@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _player_list: VBoxContainer = %PlayerList
@onready var _ready_button: Button = %ReadyButton
@onready var _start_button: Button = %StartButton
@onready var _leave_button: Button = %LeaveButton
@onready var _status: Label = %Status

var _session: GameSession

## The same session, narrowed. Exactly one of these is non-null, and which one
## decides what this screen lets you do.
var _host: HostSession
var _client: ClientSession

## The port the host is listening on, shown so the host can tell people where to
## connect. Zero on a client, which has no use for it.
var _listening_port: int = 0


func _ready() -> void:
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_leave_button.pressed.connect(leave_requested.emit)
	if _session != null:
		_attach()


## Hands the screen its session. Call before adding it to the tree, or straight
## after — both work.
##
## The session is passed as a `GameSession` and narrowed here, so the screen host
## does not need two code paths for hosting and joining.
func setup(session: GameSession, listening_port: int = 0) -> void:
	_session = session
	_host = session as HostSession
	_client = session as ClientSession
	_listening_port = listening_port
	if is_node_ready():
		_attach()


func is_hosting() -> bool:
	return _host != null


## Public so a test can read the list without reaching into the tree.
func player_rows() -> Array[Node]:
	return _player_list.get_children()


func refresh() -> void:
	if _session == null:
		return

	_title.text = "LOBBY" if is_hosting() else "JOINED"
	_subtitle.text = (
		"Others join on port %d" % _listening_port
		if is_hosting() and _listening_port > 0
		else "Waiting for the host to start"
	)

	_rebuild_list()

	var local: PlayerState = _session.state().player_by_id(_session.local_player_id())
	_ready_button.text = "NOT READY" if local != null and local.is_ready else "READY"

	_start_button.visible = is_hosting()
	if is_hosting():
		var count: int = _session.state().players.size()
		_start_button.disabled = count < 1
		_status.text = (
			"Start whenever you like — nobody else has joined yet."
			if count < 2
			else "%d players. Start when everybody is in." % count
		)
	else:
		_status.text = "The host decides when to begin."


func _attach() -> void:
	if not _session.ready_state_changed.is_connected(_on_ready_state_changed):
		_session.ready_state_changed.connect(_on_ready_state_changed)
		_session.player_changed.connect(_on_player_changed)
		_session.action_rejected.connect(_on_action_rejected)

	if _host != null:
		_host.player_joined.connect(_on_roster_changed)
		_host.player_left.connect(_on_roster_changed)
		_host.match_started.connect(play_requested.emit)
	if _client != null:
		_client.match_started.connect(play_requested.emit)
		_client.connection_lost.connect(_on_connection_lost)

	refresh()


## One row per player, rebuilt wholesale.
##
## Rebuilding rather than diffing because a lobby list is at most ten rows and
## changes a handful of times; the simplest correct thing is the right thing here.
func _rebuild_list() -> void:
	_clear_list()
	var players: Array[PlayerState] = _session.state().players
	for index: int in players.size():
		var player: PlayerState = players[index]
		var row: LobbyRow = LobbyRowScene.instantiate()
		_player_list.add_child(row)
		row.display(player, player.id == _session.local_player_id(), index == 0)


## Removes rows immediately rather than only queueing them. `queue_free()` is
## deferred to the end of the frame, so a rebuild that only queued would briefly
## show every row twice — the trap documented in architecture.md §6 and already
## caught once on the holdings board.
func _clear_list() -> void:
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()


func _on_ready_pressed() -> void:
	var local: PlayerState = _session.state().player_by_id(_session.local_player_id())
	var now_ready: bool = local == null or not local.is_ready
	_session.set_ready(_session.local_player_id(), now_ready)
	# A client's own flag is confirmed by the host, so the button settles when
	# `ready_state_changed` comes back rather than guessing here.
	refresh()


func _on_start_pressed() -> void:
	if _host != null:
		_host.start_match()


func _on_ready_state_changed(_player_id: StringName, _is_ready: bool) -> void:
	refresh()


func _on_player_changed(_player_id: StringName) -> void:
	refresh()


func _on_roster_changed(_player_id: StringName) -> void:
	refresh()


func _on_action_rejected(_player_id: StringName, reason: String) -> void:
	_status.text = reason


func _on_connection_lost(reason: String) -> void:
	_status.text = reason
	_ready_button.disabled = true
