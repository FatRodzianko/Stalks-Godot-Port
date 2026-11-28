@tool
class_name NewsDeleteConfirm
extends ConfirmationDialog
## The question the News Flow tab asks before deleting a news item that has
## arrows (docs/news-flow-chart.md §6: "Ask first, naming the linked items").
## An item with no arrows is deleted without it.
##
## A reusable widget: it is told which item and which linked items to name,
## and says through `delete_confirmed` when the person agreed. It deletes
## nothing itself. `@tool` because it runs inside the editor.


## The person agreed to delete `id`.
signal delete_confirmed(id: StringName)

const TITLE: String = "Delete news item"
const OK_TEXT: String = "Delete"

var _asked_id: StringName = &""


func _ready() -> void:
	title = TITLE
	ok_button_text = OK_TEXT
	dialog_autowrap = true
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


## Asks whether to delete `id`, naming the items its arrows join it to.
func ask(id: StringName, linked: Array[StringName]) -> void:
	_asked_id = id
	dialog_text = question_for(id, linked)
	popup_centered(Vector2i(480, 0))


## The id being asked about, or empty when nothing is.
func asked_id() -> StringName:
	return _asked_id


## What the dialog says about deleting `id`.
static func question_for(id: StringName, linked: Array[StringName]) -> String:
	var names: PackedStringArray = []
	for other: StringName in linked:
		names.append(String(other))
	return "Delete %s?\n\nIts arrows to and from these news items will be removed:\n%s\n\nIts id is retired and will not be given to a new item. Ctrl+Z puts it back." % [
		id, "\n".join(names)]


## Godot hides the dialog itself when one of its buttons is pressed. It is
## hidden here as well, so an answer given any other way (the tests emit the
## signals) never leaves it open: a dialog freed while open, with the screen
## that holds it, crashed a headless run.
func _on_confirmed() -> void:
	hide()
	var id: StringName = _asked_id
	_asked_id = &""
	if not id.is_empty():
		delete_confirmed.emit(id)


func _on_canceled() -> void:
	hide()
	_asked_id = &""
