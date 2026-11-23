class_name MessagesTab
extends HBoxContainer
## The MESSAGES tab: private messages between the players in this match
## (decisions.md D192).
##
## On the right, every player in the match **including this one**, each with
## the unread dot the MESSAGES tab itself carries (StatusDot). Clicking a name
## opens the chat with that player; this player's own name opens notes, which
## are kept on this machine and never sent.
##
## **Two chats at once.** A first name opens one chat across the left side, a
## second opens a second beside it. A third replaces whichever of the two was
## used less recently - clicked, typed in or sent from - so the one being
## talked in stays put. Clicking a name that is already open only marks it
## used.
##
## Open chats are read: whatever arrives in one while this tab is showing is
## marked read as it is drawn, so its dot never lights.
##
## Holds which chats are open and nothing else. The lines come from the
## MessageBook it is handed, the names from the state.


signal message_submitted(recipient_id: StringName, text: String)

## Drawing an open chat marked lines read, so the MESSAGES dot may go out.
signal lines_read


## How many chats can be open side by side.
const MAX_OPEN: int = 2


## The chat in each panel, left to right. At most MAX_OPEN.
var _open: Array[StringName] = []
## The open chat used most recently, which a third chat will not replace.
var _last_used: StringName = &""
var _buttons: Dictionary[StringName, Button] = {}
var _roster: Array[StringName] = []

var _state: GameState
var _local_id: StringName = &""
var _book: MessageBook

@onready var _first_chat: ChatPanel = %FirstChat
@onready var _second_chat: ChatPanel = %SecondChat
@onready var _no_chat: Label = %NoChat
@onready var _player_list: VBoxContainer = %PlayerList


func _ready() -> void:
	for panel: ChatPanel in _panels():
		panel.message_submitted.connect(_on_chat_message_submitted)
		panel.used.connect(_on_chat_used)


## Redraws the list and the open chats, and marks the open chats read. Called
## only while this tab is showing, because marking read means "seen".
func refresh(state: GameState, local_id: StringName, book: MessageBook) -> void:
	_state = state
	_local_id = local_id
	_book = book
	if _state == null or _book == null:
		return
	_rebuild_list_if_needed()
	var read_any: bool = false
	for player_id: StringName in _open:
		if _book.mark_read(player_id):
			read_any = true
	_draw_chats()
	_draw_dots()
	if read_any:
		lines_read.emit()


## Opens the chat with `player_id`, by the rule in the class notes.
func open_chat(player_id: StringName) -> void:
	if not _open.has(player_id):
		if _open.size() < MAX_OPEN:
			_open.append(player_id)
		else:
			var replaced: int = 0
			if _open[0] == _last_used:
				replaced = 1
			_open[replaced] = player_id
	_last_used = player_id
	refresh(_state, _local_id, _book)


## What became of a message typed in the chat with `recipient_id`.
func show_send_result(recipient_id: StringName, reason: String) -> void:
	var panel: ChatPanel = chat_with(recipient_id)
	if panel != null:
		panel.show_send_result(reason)


func open_chats() -> Array[StringName]:
	return _open.duplicate()


func last_used() -> StringName:
	return _last_used


func player_button(player_id: StringName) -> Button:
	return _buttons.get(player_id, null)


## The panel showing the chat with `player_id`, or null.
func chat_with(player_id: StringName) -> ChatPanel:
	var index: int = _open.find(player_id)
	if index < 0:
		return null
	return _panels()[index]


func _panels() -> Array[ChatPanel]:
	return [_first_chat, _second_chat]


## One button per player, in roster order. Rebuilt only when the roster
## changes, which in a match is never: an away player keeps their seat.
func _rebuild_list_if_needed() -> void:
	var ids: Array[StringName] = []
	for player: PlayerState in _state.players:
		ids.append(player.id)
	if ids == _roster:
		return
	_roster = ids
	for child: Node in _player_list.get_children():
		_player_list.remove_child(child)
		child.queue_free()
	_buttons.clear()
	for player: PlayerState in _state.players:
		var button: Button = Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.clip_text = true
		button.pressed.connect(_on_player_button_pressed.bind(player.id))
		_player_list.add_child(button)
		_buttons[player.id] = button
	for player_id: StringName in _open.duplicate():
		if not _roster.has(player_id):
			_open.erase(player_id)


func _draw_chats() -> void:
	var names: Dictionary[StringName, String] = {}
	for player: PlayerState in _state.players:
		names[player.id] = player.display_name
	var panels: Array[ChatPanel] = _panels()
	for index: int in panels.size():
		var panel: ChatPanel = panels[index]
		panel.visible = index < _open.size()
		if not panel.visible:
			continue
		var other_id: StringName = _open[index]
		panel.show_chat(
			other_id, _title_for(other_id, names), other_id == _local_id,
			_book.lines(other_id), names, _local_id,
		)
	_no_chat.visible = _open.is_empty()


func _title_for(other_id: StringName, names: Dictionary[StringName, String]) -> String:
	if other_id == _local_id:
		return "Notes - only you see these"
	return "Chat with %s" % names.get(other_id, "?")


func _draw_dots() -> void:
	for player: PlayerState in _state.players:
		var button: Button = _buttons.get(player.id, null)
		if button == null:
			continue
		var unread: int = _book.unread_from(player.id)
		var label: String = player.display_name
		if player.id == _local_id:
			# Not "You (you)" in a game where the name already says it.
			if player.display_name.to_lower() != "you":
				label += " (you)"
		elif player.is_away:
			label += " (away)"
		button.text = label
		button.icon = StatusDot.unread(unread > 0)
		button.set_pressed_no_signal(_open.has(player.id))
		if player.id == _local_id:
			button.tooltip_text = "Your notes"
		elif unread > 0:
			button.tooltip_text = "%s: %d unread" % [player.display_name, unread]
		else:
			button.tooltip_text = player.display_name


func _on_player_button_pressed(player_id: StringName) -> void:
	open_chat(player_id)


func _on_chat_message_submitted(recipient_id: StringName, text: String) -> void:
	message_submitted.emit(recipient_id, text)


func _on_chat_used(recipient_id: StringName) -> void:
	_last_used = recipient_id
