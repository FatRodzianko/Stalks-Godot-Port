class_name StalkPicker
extends Control
## Which companies a match is played with.
##
## Opened from Create Game. Lists every stalk this machine has — the shipped
## ones and the player's own, together, because by this point they are the same
## kind of thing — with a tick against each.
##
## **It chooses; it does not load.** The list it is given comes from
## `ContentLibrary.available()` and the problems from `CustomStalkStore`, both
## read by the screen that opens this. A widget that went to disk for itself
## could not be tested without one.
##
## See docs/decisions.md D122.


## The player closed the picker. The choice is read back with `chosen_ids`
## rather than carried here, because the screen holding this already has to ask
## for the other settings the same way.
signal dismissed


## Shown when the player has no custom stalks yet, with the folder to put them
## in. Explanatory, so it says where to go and nothing else.
const NO_CUSTOM_HINT: String = "Your own stalks go in:"

## Heading for the list of problems in the player's own files.
const PROBLEM_HEADING: String = "These files could not be read:"


const RowScene: PackedScene = preload("res://src/ui/widgets/stalk_pick_row.tscn")


## The ticked ids, in the order the list shows them, so a match's board is laid
## out the way the picker was.
var _chosen: Array[StringName] = []

## Every row, by id, so the cap can grey the others out without searching the
## tree for them.
var _rows: Dictionary[StringName, StalkPickRow] = {}

## What the shipped library holds, for Reset. Captured at `show_stalks` rather
## than read from disk here.
var _shipped: Array[StringName] = []


@onready var _list: VBoxContainer = %PickList
@onready var _count: Label = %CountLabel
@onready var _problems: Label = %ProblemLabel
@onready var _hint: Label = %HintLabel
@onready var _reset_button: Button = %ResetButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_reset_button.pressed.connect(reset_to_shipped)
	_close_button.pressed.connect(close)
	hide()


## Puts the list up.
##
## `available` is every stalk that could be played with, `chosen` is what is
## ticked when it opens, and `problems` is one line per unreadable custom file.
## An empty `chosen` ticks the shipped stalks, which is what "no choice made"
## means everywhere else (`GameSettings.chosen_stalk_ids`).
func show_stalks(
	available: Array[StalkDefinition],
	chosen: Array[StringName],
	problems: Array[String],
) -> void:
	_rows.clear()
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	_shipped = []
	for stalk: StalkDefinition in available:
		if not StalkPickRow.is_custom(stalk.id):
			_shipped.append(stalk.id)

	_chosen = chosen.duplicate()
	if _chosen.is_empty():
		_chosen = _shipped.duplicate()

	for stalk: StalkDefinition in available:
		var row: StalkPickRow = RowScene.instantiate()
		_list.add_child(row)
		row.show_stalk(stalk, stalk.id in _chosen)
		row.pick_changed.connect(_on_row_pick_changed)
		_rows[stalk.id] = row

	_show_problems(problems)
	_refresh()
	show()
	_close_button.grab_focus()


## The ids the player has ticked, in list order.
##
## **Returned even when it matches the shipped ten.** The caller compares it
## against the shipped set if it wants to store "no choice"; this widget
## reports what is ticked and nothing cleverer.
func chosen_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _rows:
		if _rows[id].is_chosen():
			out.append(id)
	return out


## Puts the shipped ten back, which is the game as it ships.
##
## **This is what makes remembering the choice safe.** Settings are otherwise
## deliberately not remembered between sessions, because a remembered setting
## silently stops the screen showing the game's real defaults and there is
## nothing on screen to say why (decisions.md D71). A button that says what it
## restores is the thing that rule was missing. See docs/decisions.md D123.
func reset_to_shipped() -> void:
	for id: StringName in _rows:
		_rows[id].set_chosen(id in _shipped)
	_refresh()


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	hide()
	dismissed.emit()


## For tests: the row for an id, or null.
func row_for(stalk_id: StringName) -> StalkPickRow:
	return _rows.get(stalk_id)


## For tests: how many rows are listed.
func row_count() -> int:
	return _rows.size()


# -------------------------------------------------------------------- the cap

## Keeps the count honest and stops an eleventh being ticked.
##
## **Greying out rather than refusing a click.** A tick that silently undoes
## itself reads as a broken control; a tick that cannot be pressed, beside a
## count that says why, does not. Unticking anything brings them all back.
func _refresh() -> void:
	var picked: int = chosen_ids().size()
	var full: bool = picked >= StalkSchema.MAX_STALKS_PER_MATCH

	for id: StringName in _rows:
		var row: StalkPickRow = _rows[id]
		row.set_available(row.is_chosen() or not full)

	_count.text = "%d of %d chosen" % [picked, StalkSchema.MAX_STALKS_PER_MATCH]
	# A match with nothing in it is not a match, and Create Game should say so
	# here rather than failing when Start is pressed.
	_count.theme_type_variation = &"Danger" if picked == 0 else &"Faint"


func _show_problems(problems: Array[String]) -> void:
	_problems.visible = not problems.is_empty()
	if not problems.is_empty():
		var lines: PackedStringArray = [PROBLEM_HEADING]
		lines.append_array(problems)
		_problems.text = "\n".join(lines)

	var has_custom: bool = false
	for id: StringName in _rows:
		if StalkPickRow.is_custom(id):
			has_custom = true
			break
	# The folder is worth naming only to somebody who has not found it yet.
	_hint.visible = not has_custom
	if not has_custom:
		_hint.text = "%s\n%s" % [
			NO_CUSTOM_HINT, ProjectSettings.globalize_path(CustomStalkStore.DIR)
		]


func _on_row_pick_changed(_stalk_id: StringName, _is_chosen: bool) -> void:
	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.keycode != KEY_ESCAPE:
		return
	accept_event()
	close()
