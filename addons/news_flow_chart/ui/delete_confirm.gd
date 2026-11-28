@tool
class_name NewsDeleteConfirm
extends ConfirmationDialog
## The two questions the News Flow tab asks about a box (decisions.md D231):
##
## - **Delete resource**: delete the news item from its book. Always asked,
##   whether or not it has arrows.
## - **Remove from tree**: cut its arrows, so it leaves the chain, and take its
##   box off the chart; the item stays in its book. Asked only when it has
##   arrows, since without any there is nothing to lose.
##
## Either names the items its arrows join it to (docs/news-flow-chart.md §6:
## "Ask first, naming the linked items").
##
## A reusable widget: it is told what to ask about, and says through
## `action_confirmed` when the person agreed. It changes nothing itself.
## `@tool` because it runs inside the editor.


## The person agreed to `action` on `id`.
signal action_confirmed(id: StringName, action: Action)

enum Action { DELETE_RESOURCE, REMOVE_FROM_TREE }

## The dialog's title and its OK button, by action. The titles are the words
## of the box's right-click menu.
const TITLES: Dictionary[Action, String] = {
	Action.DELETE_RESOURCE: "Delete resource",
	Action.REMOVE_FROM_TREE: "Remove from tree",
}
const OK_TEXTS: Dictionary[Action, String] = {
	Action.DELETE_RESOURCE: "Delete",
	Action.REMOVE_FROM_TREE: "Remove",
}

var _asked_id: StringName = &""
var _asked_action: Action = Action.DELETE_RESOURCE


func _ready() -> void:
	dialog_autowrap = true
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


## Asks whether to do `action` to `id`, naming the items its arrows join it to.
func ask(id: StringName, linked: Array[StringName], action: Action) -> void:
	_asked_id = id
	_asked_action = action
	title = TITLES[action]
	ok_button_text = OK_TEXTS[action]
	dialog_text = question_for(id, linked, action)
	popup_centered(Vector2i(480, 0))


## The id being asked about, or empty when nothing is.
func asked_id() -> StringName:
	return _asked_id


func asked_action() -> Action:
	return _asked_action


## What the dialog says about doing `action` to `id`.
static func question_for(id: StringName, linked: Array[StringName], action: Action) -> String:
	var parts: PackedStringArray = []
	if action == Action.DELETE_RESOURCE:
		parts.append("Delete %s from its book?" % id)
	else:
		parts.append("Remove %s from the tree? It stays in its book." % id)
	if not linked.is_empty():
		var names: PackedStringArray = []
		for other: StringName in linked:
			names.append(String(other))
		parts.append("Its arrows to and from these news items will be removed:\n%s" % "\n".join(names))
	if action == Action.DELETE_RESOURCE:
		parts.append("Its id is retired and will not be given to a new item.")
	parts.append("Ctrl+Z puts it back.")
	return "\n\n".join(parts)


## Godot hides the dialog itself when one of its buttons is pressed. It is
## hidden here as well, so an answer given any other way (the tests emit the
## signals) never leaves it open: a dialog freed while open, with the screen
## that holds it, crashed a headless run.
func _on_confirmed() -> void:
	hide()
	var id: StringName = _asked_id
	_asked_id = &""
	if not id.is_empty():
		action_confirmed.emit(id, _asked_action)


func _on_canceled() -> void:
	hide()
	_asked_id = &""
