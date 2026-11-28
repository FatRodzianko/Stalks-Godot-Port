class_name NewsEditHistory
extends RefCounted
## The News Flow tab's own list of edits to undo and redo, used when the tab
## runs outside the editor: in the tests (decisions.md D230).
##
## Inside the editor the tab records its edits in Godot's own history instead
## (`EditorUndoRedoManager`, from `plugin.gd`), so that Ctrl+Z, Ctrl+Y and
## **Scene > Undo** work there as they do everywhere else in Godot. Both are
## handed the same thing: a name for the edit and the state before and after
## it, as `NewsChart` snapshots it. Undoing hands back the state before;
## redoing, the state after.
##
## Typing in one text box is many small edits. Each carries a merge key (the
## item and the field), and an edit with the same key as the one just made is
## folded into it, so one undo takes back the whole of the typing. Godot's own
## history does the same with `UndoRedo.MERGE_ENDS`.


## One recorded edit.
class Edit:
	extends RefCounted
	var action: String
	var before: Dictionary
	var after: Dictionary
	var merge_key: String

	func _init(edit_action: String, state_before: Dictionary, state_after: Dictionary, key: String) -> void:
		action = edit_action
		before = state_before
		after = state_after
		merge_key = key


var _done: Array[Edit] = []
var _undone: Array[Edit] = []


## Records an edit that has already been made. Anything undone and not redone
## is forgotten, as in any editor.
func record(action: String, before: Dictionary, after: Dictionary, merge_key: String = "") -> void:
	_undone.clear()
	if not merge_key.is_empty() and not _done.is_empty() and _done[-1].merge_key == merge_key:
		_done[-1].after = after
		return
	_done.append(Edit.new(action, before, after, merge_key))


func can_undo() -> bool:
	return not _done.is_empty()


func can_redo() -> bool:
	return not _undone.is_empty()


## The state to go back to, or empty when there is nothing to undo.
func undo() -> Dictionary:
	if _done.is_empty():
		return {}
	var edit: Edit = _done.pop_back()
	_undone.append(edit)
	return edit.before


## The state to go forward to, or empty when there is nothing to redo.
func redo() -> Dictionary:
	if _undone.is_empty():
		return {}
	var edit: Edit = _undone.pop_back()
	_done.append(edit)
	return edit.after


## The name of the edit `undo` would take back, or "".
func next_undo_name() -> String:
	if _done.is_empty():
		return ""
	return _done[-1].action


func clear() -> void:
	_done.clear()
	_undone.clear()
