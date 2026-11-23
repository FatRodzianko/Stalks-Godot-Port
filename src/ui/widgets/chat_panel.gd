class_name ChatPanel
extends PanelContainer
## One conversation on the Messages tab: who it is with, what has been said
## (scrolling once it is long), and a box to say more (decisions.md D192).
##
## **Every line is a plain `Label`.** A Label has no markup of any kind - no
## BBCode, no links, no meta tags - so a message reading `[url]...[/url]` or
## `\server\share` is drawn as exactly those characters and nothing on screen
## can be clicked to open it. That is half of the security (D193); the other
## half is `MessageRules.clean`, which has already run twice before a line
## reaches here.
##
## Knows nothing about sessions. It shows what it is handed and reports what
## the player typed; the screen decides whether it was sent.


## The player typed `text` for `recipient_id` and pressed SEND or Enter.
signal message_submitted(recipient_id: StringName, text: String)

## The player started typing in this chat, which makes it the one to keep
## open when a third is opened (MessagesTab).
signal used(recipient_id: StringName)

## The player pressed BLOCK? or UNBLOCK at the top of this chat (D196).
signal block_toggled(player_id: StringName, blocked: bool)


## Before a line's text, for lines this machine's player wrote.
const YOU: String = "You"

## The block button's two captions, the owner's words (D196).
const BLOCK_CAPTION: String = "BLOCK?"
const UNBLOCK_CAPTION: String = "UNBLOCK"


var _recipient_id: StringName = &""
## The last line drawn, so a redraw with nothing new does nothing. A count
## would not do: a full conversation stays the same length as lines arrive
## (MessageBook.MAX_LINES).
var _last_line: MessageBook.Line = null
var _line_count: int = 0
var _is_blocked: bool = false

@onready var _title: Label = %Title
@onready var _block_button: Button = %BlockButton
@onready var _scroll: ScrollContainer = %Scroll
@onready var _lines: VBoxContainer = %Lines
@onready var _empty: Label = %Empty
@onready var _field: LineEdit = %Field
@onready var _send_button: Button = %SendButton
@onready var _refusal: Label = %Refusal


func _ready() -> void:
	_field.max_length = MessageRules.MAX_LENGTH
	_send_button.pressed.connect(_on_send_button_pressed)
	_block_button.pressed.connect(_on_block_button_pressed)
	_field.text_submitted.connect(_on_field_text_submitted)
	_field.focus_entered.connect(_on_field_focus_entered)
	_scroll.get_v_scroll_bar().changed.connect(_on_scroll_bar_changed)


## Shows the conversation with `recipient_id`. `names` maps every player id to
## the name to write before their lines; this machine's player is "You".
##
## Call `show_block_state` as well for a chat with one other player; a note or
## the ALL PLAYERS room has nobody to block, and shows no button.
func show_chat(
	recipient_id: StringName,
	title: String,
	is_note: bool,
	lines: Array[MessageBook.Line],
	names: Dictionary[StringName, String],
	local_id: StringName,
) -> void:
	if recipient_id != _recipient_id:
		_recipient_id = recipient_id
		_field.clear()
		_refusal.visible = false
		_last_line = null
		_line_count = -1
	_title.text = title
	_title.tooltip_text = title
	_block_button.visible = false
	if is_note:
		_field.placeholder_text = "Type a note"
	else:
		_field.placeholder_text = "Type a message"

	var newest: MessageBook.Line = null
	if not lines.is_empty():
		newest = lines.back()
	if newest == _last_line and lines.size() == _line_count:
		return
	_last_line = newest
	_line_count = lines.size()

	for child: Node in _lines.get_children():
		if child != _empty:
			_lines.remove_child(child)
			child.queue_free()
	_empty.visible = lines.is_empty()
	for line: MessageBook.Line in lines:
		var label: Label = Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var writer: String = YOU
		if line.from_id != local_id:
			writer = names.get(line.from_id, "?")
		else:
			label.theme_type_variation = &"Muted"
		label.text = "%s: %s" % [writer, line.text]
		_lines.add_child(label)


## Shows BLOCK? or UNBLOCK for the player this chat is with.
func show_block_state(is_blocked: bool) -> void:
	_is_blocked = is_blocked
	_block_button.visible = true
	if is_blocked:
		_block_button.text = UNBLOCK_CAPTION
		_block_button.tooltip_text = "Show their messages again"
	else:
		_block_button.text = BLOCK_CAPTION
		_block_button.tooltip_text = "Drop their messages. They are not told."


func block_button() -> Button:
	return _block_button


## What became of the last thing typed: an empty `reason` means it went, so the
## box empties; otherwise the reason is shown and the text is kept.
func show_send_result(reason: String) -> void:
	_refusal.visible = not reason.is_empty()
	_refusal.text = "Not sent: %s" % reason
	if reason.is_empty():
		_field.clear()


func recipient_id() -> StringName:
	return _recipient_id


## The lines as drawn, for tests.
func line_texts() -> PackedStringArray:
	var texts: PackedStringArray = []
	for child: Node in _lines.get_children():
		if child != _empty:
			texts.append((child as Label).text)
	return texts


## The line controls themselves, for the test that every one is a Label.
func line_controls() -> Array[Control]:
	var controls: Array[Control] = []
	for child: Node in _lines.get_children():
		if child != _empty:
			controls.append(child as Control)
	return controls


func title_text() -> String:
	return _title.text


func field() -> LineEdit:
	return _field


func send_button() -> Button:
	return _send_button


func refusal_text() -> String:
	return _refusal.text if _refusal.visible else ""


func _submit() -> void:
	if _field.text.strip_edges().is_empty():
		return
	used.emit(_recipient_id)
	message_submitted.emit(_recipient_id, _field.text)


func _on_block_button_pressed() -> void:
	block_toggled.emit(_recipient_id, not _is_blocked)


func _on_send_button_pressed() -> void:
	_submit()


func _on_field_text_submitted(_text: String) -> void:
	_submit()


func _on_field_focus_entered() -> void:
	used.emit(_recipient_id)


## A new line made the history taller: keep the newest in view.
func _on_scroll_bar_changed() -> void:
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)
