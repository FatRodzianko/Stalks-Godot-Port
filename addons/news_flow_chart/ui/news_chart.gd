@tool
class_name NewsChart
extends VBoxContainer
## The News Flow tab (docs/news-flow-chart.md §2, Phase 2: read-only).
##
## Assembles the screen: on the left the chains and a searchable list of every
## news item; in the middle a `GraphEdit` with one `NewsItemBox` per item of
## the chain being shown and an arrow for each `requires`; on the right the
## `NewsDetailsPanel` for the clicked box; along the bottom the Problems strip.
##
## Nothing about a chain is stored: the boxes and arrows are worked out from
## the `requires` lists by `NewsGraph` each time (§3.1). Box positions belong
## to `GraphEdit` and are laid out by `arrange_nodes`.
##
## **This phase writes no file.** It reads the books and the chain names and
## shows them. `@tool` because it runs inside the editor.
##
## `show_content` is what the tests drive. `reload_from_project` is what the
## plugin calls: it reads the books the editor has loaded, which are
## placeholders there (decisions.md D224), so nothing here calls a method on a
## news item.


const BOX_SCENE: PackedScene = preload("res://addons/news_flow_chart/ui/news_item_box.tscn")

const NO_PROBLEMS: String = "Problems: none"

var _graph: NewsGraph = NewsGraph.new()
var _chain_names: NewsChainNames = NewsChainNames.new()
var _chains: Array[Array] = []

@onready var _arrange_button: Button = %ArrangeButton
@onready var _chain_list: ItemList = %ChainList
@onready var _search_box: LineEdit = %SearchBox
@onready var _news_item_list: ItemList = %NewsItemList
@onready var _chart: NewsChartCanvas = %Chart
@onready var _details_panel: NewsDetailsPanel = %DetailsPanel
@onready var _problems_label: Label = %ProblemsLabel


func _ready() -> void:
	_arrange_button.pressed.connect(arrange)
	_chain_list.item_selected.connect(_on_chain_list_item_selected)
	_search_box.text_changed.connect(_on_search_box_text_changed)
	_news_item_list.item_selected.connect(_on_news_item_list_item_selected)
	_chart.node_selected.connect(_on_chart_node_selected)
	_problems_label.text = NO_PROBLEMS


## Reads the news books in src/data/news/ and the chain names, and runs the
## validator for the Problems strip. What the News Flow tab does each time it
## is opened.
func reload_from_project() -> void:
	var books: Array[NewsBook] = []
	for file_name: String in DirAccess.get_files_at(ContentLibrary.NEWS_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var book: NewsBook = load("%s/%s" % [ContentLibrary.NEWS_DIR, file_name]) as NewsBook
		if book != null:
			books.append(book)
	# No traders: their own chatter is built by calling a method on each
	# trader, which a placeholder cannot run, and the tool does not edit it.
	var content: NewsContent = NewsContent.build(books, [])
	show_content(content.all_lines(), NewsChainNames.read(), NewsProblems.run_check())


## Shows these news items, with these chain names and problems. Shows the
## first chain, if there is one.
func show_content(lines: Array[Resource], chain_names: NewsChainNames, problems: Array[String]) -> void:
	_graph = NewsGraph.from_lines(lines)
	_chain_names = chain_names
	var all_problems: Array[String] = problems.duplicate()
	all_problems.append_array(_chain_names.follow(_graph))
	_chains = _graph.chains()
	_fill_chain_list()
	_fill_news_item_list()
	_show_problems(all_problems)
	_clear_chart()
	_details_panel.clear()
	if not _chains.is_empty():
		choose_chain(0)


## Shows chain number `index` of the chain list on the chart.
func choose_chain(index: int) -> void:
	if index < 0 or index >= _chains.size():
		return
	_chain_list.select(index)
	var members: Array[StringName] = []
	members.assign(_chains[index])
	_show_on_chart(members)


## Shows the chain `id` is in (just its own box if it has no arrows) and
## selects its box.
func choose_item(id: StringName) -> void:
	if not _graph.has(id):
		return
	_chain_list.deselect_all()
	_show_on_chart(_graph.chain_of(id))
	var box: NewsItemBox = box_for(id)
	if box != null:
		box.selected = true


## Lays every box out again, left to right, whatever is selected. What the
## **Arrange** button does. `arrange_nodes` moves only the selected boxes when
## any are selected, so the selection is put aside while it runs. (GraphEdit's
## own arrange button, which does just that, is hidden in the scene: two
## buttons that behave differently would be one too many.)
##
## Each box is first shrunk to what its contents need. A box's labels wrap,
## and before the first layout they wrap at almost no width, one word per line;
## the box grows to fit that and, being a container, never shrinks back.
func arrange() -> void:
	var was_selected: Array[NewsItemBox] = []
	for box: NewsItemBox in boxes():
		box.reset_size()
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


## The boxes on the chart.
func boxes() -> Array[NewsItemBox]:
	var found: Array[NewsItemBox] = []
	for child: Node in _chart.get_children():
		if child is NewsItemBox:
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
		var from_box: NewsItemBox = _chart.get_node(NodePath(String(connection["from_node"]))) as NewsItemBox
		var to_box: NewsItemBox = _chart.get_node(NodePath(String(connection["to_node"]))) as NewsItemBox
		found.append(PackedStringArray([String(from_box.item_id), String(to_box.item_id)]))
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


func _show_on_chart(members: Array[StringName]) -> void:
	_clear_chart()
	for id: StringName in members:
		var box: NewsItemBox = BOX_SCENE.instantiate() as NewsItemBox
		box.name = _box_name(id)
		_chart.add_child(box)
		box.show_item(_graph.line(id))
	for id: StringName in members:
		for required: StringName in _graph.requires_of(id):
			_chart.connect_node(_box_name(required), NewsItemBox.LINK_SLOT, _box_name(id), NewsItemBox.LINK_SLOT)
	_details_panel.clear()
	# The boxes only know their size once the containers have sorted them,
	# which happens later this frame.
	arrange.call_deferred()


func _clear_chart() -> void:
	_chart.clear_connections()
	for box: NewsItemBox in boxes():
		_chart.remove_child(box)
		box.queue_free()


## A box's node name: the id, made safe for a node name. Ids are snake case,
## so this changes nothing for any written by the tool.
func _box_name(id: StringName) -> StringName:
	return StringName(String(id).validate_node_name())


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


func _show_problems(problems: Array[String]) -> void:
	if problems.is_empty():
		_problems_label.text = NO_PROBLEMS
		return
	_problems_label.text = "Problems (%d):\n%s" % [problems.size(), "\n".join(problems)]


func _item_texts(list: ItemList) -> PackedStringArray:
	var texts: PackedStringArray = []
	for index: int in list.item_count:
		texts.append(list.get_item_text(index))
	return texts


func _on_chain_list_item_selected(index: int) -> void:
	choose_chain(index)


func _on_search_box_text_changed(_new_text: String) -> void:
	_fill_news_item_list()


func _on_news_item_list_item_selected(index: int) -> void:
	choose_item(_news_item_list.get_item_metadata(index))


func _on_chart_node_selected(node: Node) -> void:
	var box: NewsItemBox = node as NewsItemBox
	if box != null and _graph.has(box.item_id):
		_details_panel.show_item(_graph.line(box.item_id))
