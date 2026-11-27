@tool
class_name NewsChart
extends VBoxContainer
## The News Flow tab (docs/news-flow-chart.md §2; Phase 3: creating, editing
## and linking).
##
## Assembles the screen: a toolbar (**+ New news item**, **Arrange**, the chain
## name and **Rename chain**, **Save**, and a status line); on the left the
## chains and a searchable list of every news item; in the middle a
## `NewsChartCanvas` with one `NewsItemBox` per item shown and an arrow for
## each `requires`; on the right the `NewsDetailsPanel` for the clicked box;
## along the bottom the Problems strip.
##
## **Every change goes through `NewsBookEditor`** (Phase 1), which edits the
## books in memory and remembers which it changed. Nothing reaches a file
## until **Save**, which saves the changed books and the chain names and then
## runs the Problems check again. A drawn arrow is the item's `requires`; there
## is no other record of it (§3.1).
##
## In the editor the books are the editor's own copies, and their items are
## placeholders (decisions.md D224), so nothing here calls a method on a news
## item. `@tool` because it runs inside the editor.
##
## `show_content` is what the tests drive, with books under `user://`.
## `reload_from_project` is what the plugin calls.


## Books were saved, at these paths. The plugin tells the editor's file
## system about them.
signal books_saved(paths: PackedStringArray)

const BOX_SCENE: PackedScene = preload("res://addons/news_flow_chart/ui/news_item_box.tscn")

const NO_PROBLEMS: String = "Problems: none"

## What a drag from the news item list carries: one news item's id.
const DRAG_KEY: String = "news_item_id"

## Where new items go and where names and retired ids are kept. The tests
## point these at `user://`.
var news_dir: String = ContentLibrary.NEWS_DIR
var chain_names_path: String = NewsChainNames.PATH
var retired_ids_path: String = ContentLibrary.RETIRED_NEWS_IDS_PATH

## What runs the validator after loading and after every save, returning the
## news problems. The tests swap in one that runs nothing.
var check_problems: Callable = NewsProblems.run_check

var _book_editor: NewsBookEditor = NewsBookEditor.new({} as Dictionary[String, NewsBook])
var _graph: NewsGraph = NewsGraph.new()
var _chain_names: NewsChainNames = NewsChainNames.new()
var _names_changed: bool = false
var _choice_library: ContentLibrary = ContentLibrary.new()
var _chains: Array[Array] = []
## The ids whose boxes are on the chart.
var _shown: Array[StringName] = []
## The item whose box was clicked, or empty.
var _selected_id: StringName = &""
## A new item being filled in before **Create**, or null.
var _draft: Resource = null
var _problems: Array[String] = []
var _name_problems: Array[String] = []
var _message: String = ""

@onready var _new_item_button: MenuButton = %NewItemButton
@onready var _arrange_button: Button = %ArrangeButton
@onready var _chain_name_edit: LineEdit = %ChainNameEdit
@onready var _rename_button: Button = %RenameButton
@onready var _save_button: Button = %SaveButton
@onready var _status_label: Label = %StatusLabel
@onready var _chain_list: ItemList = %ChainList
@onready var _search_box: LineEdit = %SearchBox
@onready var _news_item_list: ItemList = %NewsItemList
@onready var _chart: NewsChartCanvas = %Chart
@onready var _details_panel: NewsDetailsPanel = %DetailsPanel
@onready var _problems_label: Label = %ProblemsLabel


func _ready() -> void:
	var menu: PopupMenu = _new_item_button.get_popup()
	for kind: NewsKind.Value in NewsKind.ALL:
		menu.add_item(NewsKind.display_name(kind), kind)
	menu.id_pressed.connect(_on_new_item_menu_id_pressed)
	_arrange_button.pressed.connect(arrange)
	_rename_button.pressed.connect(_on_rename_button_pressed)
	_save_button.pressed.connect(_on_save_button_pressed)
	_chain_list.item_selected.connect(_on_chain_list_item_selected)
	_search_box.text_changed.connect(_on_search_box_text_changed)
	_news_item_list.item_selected.connect(_on_news_item_list_item_selected)
	_news_item_list.set_drag_forwarding(_news_item_drag_data, Callable(), Callable())
	_chart.set_drag_forwarding(Callable(), _can_drop_on_chart, _drop_on_chart)
	_chart.node_selected.connect(_on_chart_node_selected)
	_chart.connection_request.connect(_on_chart_connection_request)
	_chart.disconnection_request.connect(_on_chart_disconnection_request)
	_details_panel.field_changed.connect(_on_details_panel_field_changed)
	_details_panel.requirement_added.connect(_on_details_panel_requirement_added)
	_details_panel.requirement_removed.connect(_on_details_panel_requirement_removed)
	_details_panel.create_pressed.connect(create_draft)
	_details_panel.cancel_pressed.connect(cancel_draft)
	_show_problems()
	_show_status()


## Reads the books in src/data/news/, the chain names and the companies,
## industries and traders for the dropdowns, and runs the Problems check. What
## the tab does each time it is opened. Unsaved changes are kept: the books
## and names are then left as they are, and only the check runs again.
func reload_from_project() -> void:
	if has_unsaved_changes():
		_problems = check_problems.call()
		_refresh_lists()
		_show_problems()
		_show_status()
		return
	var retired: Array[StringName] = ContentLibrary.read_retired_news_ids(retired_ids_path)
	var editor: NewsBookEditor = NewsBookEditor.new(NewsBookEditor.load_books(news_dir), retired)
	var problems: Array[String] = check_problems.call()
	show_content(editor, NewsChainNames.read(chain_names_path), problems, NewsFieldChoices.library_from_files())


## Shows the books `editor` holds, with these chain names and problems.
## `choice_library` supplies the companies, industries and traders the
## dropdowns offer. Shows the first chain, if there is one.
func show_content(
	editor: NewsBookEditor,
	chain_names: NewsChainNames,
	problems: Array[String],
	choice_library: ContentLibrary,
) -> void:
	_book_editor = editor
	_chain_names = chain_names
	_names_changed = false
	_problems = problems
	_choice_library = choice_library
	_draft = null
	_selected_id = &""
	_message = ""
	_graph = _book_editor.graph()
	_name_problems = _chain_names.follow(_graph)
	_refresh_lists()
	_show_problems()
	_show_status()
	_details_panel.clear()
	_show_ids([] as Array[StringName], false)
	if not _chains.is_empty():
		choose_chain(0)


# ----------------------------------------------------------------- viewing


## Shows chain number `index` of the chain list on the chart.
func choose_chain(index: int) -> void:
	if index < 0 or index >= _chains.size():
		return
	_chain_list.select(index)
	var members: Array[StringName] = []
	members.assign(_chains[index])
	_chain_name_edit.text = _chain_names.name_for(_graph, members)
	_show_ids(members, true)


## Shows the chain `id` is in (just its own box if it has no arrows) and
## selects its box.
func choose_item(id: StringName) -> void:
	if not _graph.has(id):
		return
	_show_ids(_graph.chain_of(id), true)
	_select_chain_in_list(id)
	_select_box(id)


## Puts the box of `id` on the chart beside what is already there, at
## `at_offset` in the chart's own coordinates. What dropping an item from the
## list onto the chart does.
func add_to_chart(id: StringName, at_offset: Vector2) -> void:
	if not _graph.has(id):
		return
	if not _shown.has(id):
		var ids: Array[StringName] = _shown.duplicate()
		ids.append(id)
		_show_ids(ids, false)
	box_for(id).position_offset = at_offset
	_select_box(id)


## Lays every box out again, left to right, whatever is selected. What the
## **Arrange** button does. `arrange_nodes` moves only the selected boxes when
## any are selected, so the selection is put aside while it runs. (GraphEdit's
## own arrange button, which does just that, is hidden in the scene: two
## buttons that behave differently would be one too many.)
func arrange() -> void:
	var was_selected: Array[NewsItemBox] = []
	_shrink_boxes()
	for box: NewsItemBox in boxes():
		if box.selected:
			was_selected.append(box)
			box.selected = false
	_chart.arrange_nodes()
	for box: NewsItemBox in was_selected:
		box.selected = true


## Narrows the news item list to items whose id or words contain `text`.
func search(text: String) -> void:
	_search_box.text = text
	_fill_news_item_list()


# ----------------------------------------------------------------- editing


## Opens the details panel on a new, empty item of `kind`. It is made when
## **Create** is clicked (`create_draft`).
func start_new_item(kind: NewsKind.Value) -> void:
	_deselect_boxes()
	_selected_id = &""
	_draft = NewsKind.make(kind)
	_show_details()


## Adds the draft to the book it belongs in, with a new id, and shows its box.
func create_draft() -> void:
	if _draft == null:
		return
	var before: NewsGraph = _graph
	var refusal: String = _book_editor.add(_draft, news_dir)
	if not refusal.is_empty():
		_set_message(refusal)
		return
	var id: StringName = _draft.get("id")
	_draft = null
	_after_edit(before)
	var ids: Array[StringName] = _shown.duplicate()
	ids.append(id)
	_show_ids(ids, ids.size() == 1)
	_select_box(id)
	_set_message("Created %s." % id)


## Drops the draft without making it.
func cancel_draft() -> void:
	_draft = null
	_show_details()


## Draws an arrow from `from_id` to `to_id`: `to_id` then requires `from_id`.
## Refused, with the reason in the status line, if it would make a loop. An end
## that is not on the chart yet (picked in the details panel's requires list)
## is put on it, and the boxes arranged, so the new arrow can be seen.
func link(from_id: StringName, to_id: StringName) -> void:
	var before: NewsGraph = _graph
	var refusal: String = _book_editor.link(from_id, to_id)
	if not refusal.is_empty():
		_set_message(refusal)
		return
	_after_edit(before)
	var ids: Array[StringName] = _shown.duplicate()
	for id: StringName in [from_id, to_id]:
		if not ids.has(id):
			ids.append(id)
	if ids.size() > _shown.size():
		_show_ids(ids, true)
		if not _selected_id.is_empty():
			_select_box(_selected_id)
	_set_message("")


## Removes the arrow from `from_id` to `to_id`. Every other arrow stays.
func unlink(from_id: StringName, to_id: StringName) -> void:
	var before: NewsGraph = _graph
	var refusal: String = _book_editor.unlink(from_id, to_id)
	if not refusal.is_empty():
		_set_message(refusal)
		return
	_after_edit(before)
	_set_message("")


## Sets one field of the selected item, or of the draft.
func set_field(field: StringName, value: Variant) -> void:
	if _draft != null:
		_draft.set(field, value)
		if not value is String:
			_show_details()
		return
	if _selected_id.is_empty():
		return
	var refusal: String = _book_editor.set_field(_selected_id, field, value)
	if not refusal.is_empty():
		_set_message(refusal)
		return
	if value is String:
		# Typing: refresh the box's words only, so the text box keeps focus.
		var box: NewsItemBox = box_for(_selected_id)
		if box != null:
			box.show_item(_graph.line(_selected_id))
		_show_status()
		return
	_after_edit(_graph)


## Names the chain chosen in the chain list. An empty name gives it back its
## automatic one, its root's id.
func rename_chain(new_name: String) -> void:
	var index: int = _chosen_chain_index()
	if index < 0:
		_set_message("Choose a chain in the list first.")
		return
	var members: Array[StringName] = []
	members.assign(_chains[index])
	_chain_names.rename(_graph, members, new_name)
	_names_changed = true
	_fill_chain_list()
	_chain_list.select(index)
	_chain_name_edit.text = _chain_names.name_for(_graph, members)
	_set_message("")


## Saves every changed book and the chain names, then runs the Problems check
## again. Returns what could not be saved.
func save() -> Array[String]:
	var saved: PackedStringArray = PackedStringArray(_book_editor.changed_paths())
	var failures: Array[String] = _book_editor.save_changed()
	if _names_changed:
		var result: Error = _chain_names.write(chain_names_path)
		if result == OK:
			_names_changed = false
			saved.append(chain_names_path)
		else:
			failures.append("Could not save %s (error %d)." % [chain_names_path, result])
	books_saved.emit(saved)
	_problems = check_problems.call()
	_show_problems()
	if failures.is_empty():
		_set_message("Saved.")
	else:
		_set_message(" ".join(failures))
	return failures


func has_unsaved_changes() -> bool:
	return _names_changed or not _book_editor.changed_paths().is_empty()


# ------------------------------------------------------- read by the tests


## The boxes on the chart.
func boxes() -> Array[NewsItemBox]:
	var found: Array[NewsItemBox] = []
	for child: Node in _chart.get_children():
		if child is NewsItemBox and not child.is_queued_for_deletion():
			found.append(child)
	return found


func box_for(id: StringName) -> NewsItemBox:
	for box: NewsItemBox in boxes():
		if box.item_id == id:
			return box
	return null


## The arrows on the chart, each `[from id, to id]`: "to requires from".
func arrows() -> Array[PackedStringArray]:
	var found: Array[PackedStringArray] = []
	for connection: Dictionary in _chart.get_connection_list():
		var from_id: StringName = _id_of_box(connection["from_node"])
		var to_id: StringName = _id_of_box(connection["to_node"])
		found.append(PackedStringArray([String(from_id), String(to_id)]))
	found.sort()
	return found


## The chain list's entries, in order.
func chain_labels() -> PackedStringArray:
	return _item_texts(_chain_list)


## The news item list's entries, in order.
func news_item_labels() -> PackedStringArray:
	return _item_texts(_news_item_list)


func problems_text() -> String:
	return _problems_label.text


func status_text() -> String:
	return _status_label.text


## The item being edited: the draft, or the selected item.
func edited_item() -> Resource:
	if _draft != null:
		return _draft
	return _graph.line(_selected_id)


# ----------------------------------------------------------------- private


## After any change to the books: rebuild the graph, move chain names to
## follow their chains, and redraw everything without losing the view.
func _after_edit(before: NewsGraph) -> void:
	_graph = _book_editor.graph()
	var names_before: Dictionary[StringName, String] = _chain_names.names.duplicate()
	_name_problems = _chain_names.follow(_graph, before)
	if _chain_names.names != names_before:
		_names_changed = true
	_refresh_lists()
	var still_there: Array[StringName] = []
	for id: StringName in _shown:
		if _graph.has(id):
			still_there.append(id)
	_show_ids(still_there, false)
	if not _selected_id.is_empty():
		_select_chain_in_list(_selected_id)
		_select_box(_selected_id)
	_show_problems()
	_show_status()


## Puts these boxes on the chart and the arrows between them. Boxes already
## on the chart keep their place; with `arrange_after`, everything is laid out
## afresh.
func _show_ids(ids: Array[StringName], arrange_after: bool) -> void:
	var places: Dictionary[StringName, Vector2] = {}
	for box: NewsItemBox in boxes():
		places[box.item_id] = box.position_offset
	_chart.clear_connections()
	for box: NewsItemBox in boxes():
		_chart.remove_child(box)
		box.queue_free()
	_shown = ids.duplicate()
	for id: StringName in _shown:
		var box: NewsItemBox = BOX_SCENE.instantiate() as NewsItemBox
		box.name = _box_name(id)
		_chart.add_child(box)
		box.show_item(_graph.line(id))
		box.position_offset = places.get(id, Vector2.ZERO)
	for id: StringName in _shown:
		for required: StringName in _graph.requires_of(id):
			if _shown.has(required):
				_chart.connect_node(_box_name(required), NewsItemBox.LINK_SLOT, _box_name(id), NewsItemBox.LINK_SLOT)
	if not _shown.has(_selected_id):
		_selected_id = &""
		if _draft == null:
			_details_panel.clear()
	# The boxes only know their size once the containers have sorted them,
	# which happens later this frame.
	if arrange_after:
		arrange.call_deferred()
	else:
		_shrink_boxes.call_deferred()


## Shrinks each box to what its contents need. Its labels wrap, and before the
## first layout they wrap at almost no width, one word per line; the box grows
## to fit that and, being a container, never shrinks back by itself.
func _shrink_boxes() -> void:
	for box: NewsItemBox in boxes():
		box.reset_size()


func _select_box(id: StringName) -> void:
	_deselect_boxes()
	var box: NewsItemBox = box_for(id)
	if box != null:
		box.selected = true


func _deselect_boxes() -> void:
	for box: NewsItemBox in boxes():
		box.selected = false


## Fills the details panel from the draft or the selected item.
func _show_details() -> void:
	var line: Resource = edited_item()
	if line == null:
		_details_panel.clear()
		return
	var choices: Dictionary[StringName, Array] = {}
	for property: Dictionary in NewsItemSummary.stored_properties(line):
		var field: StringName = property["name"]
		if NewsFieldChoices.has_choices(line, field):
			choices[field] = NewsFieldChoices.choices_for(line, field, _choice_library)
	var options: Array[StringName] = []
	if _draft == null:
		options = NewsFieldChoices.requires_choices(line, _graph)
	_details_panel.show_item(line, choices, options, _draft != null)


## A box's node name: the id, made safe for a node name. Ids are snake case,
## so this changes nothing for any the tool writes.
func _box_name(id: StringName) -> StringName:
	return StringName(String(id).validate_node_name())


func _id_of_box(node_name: StringName) -> StringName:
	var box: NewsItemBox = _chart.get_node_or_null(NodePath(String(node_name))) as NewsItemBox
	if box == null:
		return &""
	return box.item_id


func _refresh_lists() -> void:
	_chains = _graph.chains()
	_fill_chain_list()
	_fill_news_item_list()


func _fill_chain_list() -> void:
	_chain_list.clear()
	for chain: Array in _chains:
		var members: Array[StringName] = []
		members.assign(chain)
		var index: int = _chain_list.add_item(_chain_names.name_for(_graph, members))
		_chain_list.set_item_tooltip(index, "%d news items" % members.size())


func _fill_news_item_list() -> void:
	_news_item_list.clear()
	var wanted: String = _search_box.text.strip_edges().to_lower()
	for id: StringName in _graph.ids():
		if not wanted.is_empty() and not NewsItemSummary.search_text(_graph.line(id)).contains(wanted):
			continue
		var index: int = _news_item_list.add_item(String(id))
		_news_item_list.set_item_metadata(index, id)
		_news_item_list.set_item_tooltip(index, NewsItemSummary.first_words(_graph.line(id)))


## Selects, without redrawing, the chain `id` is in, if it is in one.
func _select_chain_in_list(id: StringName) -> void:
	_chain_list.deselect_all()
	for index: int in _chains.size():
		if _chains[index].has(id):
			_chain_list.select(index)
			var members: Array[StringName] = []
			members.assign(_chains[index])
			_chain_name_edit.text = _chain_names.name_for(_graph, members)
			return


func _chosen_chain_index() -> int:
	var chosen: PackedInt32Array = _chain_list.get_selected_items()
	if chosen.is_empty():
		return -1
	return chosen[0]


func _show_problems() -> void:
	var all: Array[String] = _problems.duplicate()
	all.append_array(_name_problems)
	if all.is_empty():
		_problems_label.text = NO_PROBLEMS
		return
	_problems_label.text = "Problems (%d):\n%s" % [all.size(), "\n".join(all)]


func _set_message(message: String) -> void:
	_message = message
	_show_status()


## The status line: the last message, then what is not saved yet.
func _show_status() -> void:
	var parts: PackedStringArray = []
	if not _message.is_empty():
		parts.append(_message)
	var unsaved: PackedStringArray = []
	for path: String in _book_editor.changed_paths():
		unsaved.append(path.get_file())
	if _names_changed:
		unsaved.append(chain_names_path.get_file())
	if not unsaved.is_empty():
		parts.append("Unsaved: %s" % ", ".join(unsaved))
	_status_label.text = "   ".join(parts)


func _item_texts(list: ItemList) -> PackedStringArray:
	var texts: PackedStringArray = []
	for index: int in list.item_count:
		texts.append(list.get_item_text(index))
	return texts


func _news_item_drag_data(at_position: Vector2) -> Variant:
	var index: int = _news_item_list.get_item_at_position(at_position, true)
	if index < 0:
		return null
	var id: StringName = _news_item_list.get_item_metadata(index)
	var preview: Label = Label.new()
	preview.text = String(id)
	_news_item_list.set_drag_preview(preview)
	return {DRAG_KEY: id}


func _can_drop_on_chart(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has(DRAG_KEY)


func _drop_on_chart(at_position: Vector2, data: Variant) -> void:
	var id: StringName = (data as Dictionary)[DRAG_KEY]
	add_to_chart(id, (at_position + _chart.scroll_offset) / _chart.zoom)


func _on_new_item_menu_id_pressed(id: int) -> void:
	start_new_item(id as NewsKind.Value)


func _on_rename_button_pressed() -> void:
	rename_chain(_chain_name_edit.text)


func _on_save_button_pressed() -> void:
	save()


func _on_chain_list_item_selected(index: int) -> void:
	choose_chain(index)


func _on_search_box_text_changed(_new_text: String) -> void:
	_fill_news_item_list()


func _on_news_item_list_item_selected(index: int) -> void:
	choose_item(_news_item_list.get_item_metadata(index))


func _on_chart_node_selected(node: Node) -> void:
	var box: NewsItemBox = node as NewsItemBox
	if box == null or not _graph.has(box.item_id):
		return
	_draft = null
	_selected_id = box.item_id
	_show_details()


func _on_chart_connection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	link(_id_of_box(from_node), _id_of_box(to_node))


func _on_chart_disconnection_request(from_node: StringName, _from_port: int, to_node: StringName, _to_port: int) -> void:
	unlink(_id_of_box(from_node), _id_of_box(to_node))


func _on_details_panel_field_changed(field: StringName, value: Variant) -> void:
	set_field(field, value)


func _on_details_panel_requirement_added(id: StringName) -> void:
	if not _selected_id.is_empty():
		link(id, _selected_id)


func _on_details_panel_requirement_removed(id: StringName) -> void:
	if not _selected_id.is_empty():
		unlink(id, _selected_id)
