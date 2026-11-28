@tool
extends EditorInspectorPlugin
## The News Flow tab's dropdowns in Godot's ordinary Inspector
## (docs/news-flow-chart.md §3.4, Phase 4; decisions.md D230).
##
## Whenever a news item is open in the Inspector (a market news, industry
## headline, company news, whisper or chatter line inside one of the books in
## src/data/news/), its company, industry, subject and trader fields are
## dropdowns of everything of that kind that exists, read from their files
## (`NewsFieldChoices`), and its `requires` is a list of ids with **Remove**
## buttons and a dropdown to add one. The file still holds a plain string; a
## text editor can still type a wrong name, and the validator refuses it.
##
## Editor-only: it has no `class_name`, and the plugin adds it
## (`add_inspector_plugin`). Changes go through `emit_changed`, so the
## Inspector records them in the editor's undo history like any other field.
## News items are placeholders in the editor (D224): only `get` and `is` are
## used on them.


func _can_handle(object: Object) -> bool:
	return object is Resource and NewsKind.of(object as Resource) >= 0


func _parse_property(
	object: Object,
	_type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool,
) -> bool:
	var line: Resource = object as Resource
	var field: StringName = StringName(name)
	if NewsFieldChoices.has_choices(line, field):
		add_property_editor(name, ChoiceProperty.new(NewsFieldChoices.library_from_files()))
		return true
	if field == &"requires":
		add_property_editor(name, RequiresProperty.new())
		return true
	return false


## A company, industry, subject or trader field as a dropdown.
class ChoiceProperty:
	extends EditorProperty

	var _library: ContentLibrary
	var _option: OptionButton = OptionButton.new()
	## The ids offered, in item order.
	var _ids: Array[StringName] = []

	func _init(library: ContentLibrary) -> void:
		_library = library
		_option.fit_to_longest_item = false
		_option.clip_text = true
		add_child(_option)
		add_focusable(_option)
		_option.item_selected.connect(_on_option_item_selected)

	## Called by the Inspector whenever the value may have changed. A
	## whisper's subject lists industries or companies by its `about`, so
	## the list is worked out again each time.
	func _update_property() -> void:
		var line: Resource = get_edited_object() as Resource
		var field: StringName = get_edited_property()
		var value: StringName = StringName(str(line.get(field)))
		var ids: Array[StringName] = []
		var labels: PackedStringArray = []
		for choice: NewsFieldChoices.Choice in NewsFieldChoices.choices_for(line, field, _library):
			ids.append(choice.id)
			labels.append(choice.label)
		if not ids.has(value):
			ids.append(value)
			labels.append("%s (not found)" % value)
		if ids != _ids:
			_ids = ids
			_option.clear()
			for label: String in labels:
				_option.add_item(label)
		_option.select(_ids.find(value))

	func _on_option_item_selected(index: int) -> void:
		emit_changed(get_edited_property(), _ids[index])


## `requires` as a picker: each id required, with **Remove**, then a dropdown
## of the ids that could be added without making a loop.
class RequiresProperty:
	extends EditorProperty

	const ADD_REQUIREMENT: String = "Add a requirement..."

	var _box: VBoxContainer = VBoxContainer.new()
	var _shown: Array[StringName] = []
	var _built: bool = false
	## The ids offered by the add dropdown, in item order after its first.
	var _options: Array[StringName] = []

	func _init() -> void:
		add_child(_box)
		set_bottom_editor(_box)

	## Called by the Inspector whenever the value may have changed. The rows
	## are built again only when the list itself has changed.
	func _update_property() -> void:
		var required: Array[StringName] = _required()
		if _built and required == _shown:
			return
		_built = true
		_shown = required
		for child: Node in _box.get_children():
			_box.remove_child(child)
			child.queue_free()
		for id: StringName in required:
			var row: HBoxContainer = HBoxContainer.new()
			var label: Label = Label.new()
			label.text = String(id)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var remove: Button = Button.new()
			remove.text = "Remove"
			remove.pressed.connect(_on_remove_button_pressed.bind(id))
			row.add_child(remove)
			_box.add_child(row)
		var adder: OptionButton = OptionButton.new()
		adder.fit_to_longest_item = false
		adder.clip_text = true
		adder.add_item(ADD_REQUIREMENT)
		_options.clear()
		var line: Resource = get_edited_object() as Resource
		var graph: NewsGraph = NewsBookEditor.new(NewsBookEditor.load_books(ContentLibrary.NEWS_DIR)).graph()
		for id: StringName in NewsFieldChoices.requires_choices_without_loops(line, graph):
			if not required.has(id):
				_options.append(id)
				adder.add_item(String(id))
		adder.select(0)
		adder.item_selected.connect(_on_adder_item_selected)
		_box.add_child(adder)
		add_focusable(adder)

	func _required() -> Array[StringName]:
		var required: Array[StringName] = []
		required.assign(get_edited_object().get(get_edited_property()))
		return required

	func _on_adder_item_selected(index: int) -> void:
		if index <= 0:
			return
		var updated: Array[StringName] = _required()
		updated.append(_options[index - 1])
		emit_changed(get_edited_property(), updated)

	func _on_remove_button_pressed(id: StringName) -> void:
		var updated: Array[StringName] = _required()
		updated.erase(id)
		emit_changed(get_edited_property(), updated)
