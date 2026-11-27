@tool
extends EditorPlugin
## The News Flow Chart's entry point: adds the **News Flow** tab at the top of
## the editor, beside 2D, 3D, Script and AssetLib (docs/news-flow-chart.md §2).
## Godot calls such a tab a "main screen" plugin.
##
## Switched on in **Project > Project Settings > Plugins**, and listed in
## `project.godot` under `[editor_plugins]`. Editor-only: it has no
## `class_name`, so it never enters the exported game's class list, and the
## whole addon is left out of exports (exporting.md).
##
## It holds the `NewsChart` screen and reloads it each time the tab is opened,
## so edits made elsewhere (a text editor, the Inspector) show up when you come
## back. It also ties the tab's unsaved changes into the editor's own saving:
## **Scene > Save All** (and Ctrl+S) saves them too, and closing the editor
## with changes unsaved asks first instead of losing them.


const CHART_SCENE: PackedScene = preload("res://addons/news_flow_chart/ui/news_chart.tscn")
const TAB_NAME: String = "News Flow"
const UNSAVED_QUESTION: String = "The News Flow tab has unsaved changes to the news books. Save them?"

var _chart: NewsChart = null


func _enter_tree() -> void:
	_chart = CHART_SCENE.instantiate() as NewsChart
	EditorInterface.get_editor_main_screen().add_child(_chart)
	_chart.books_saved.connect(_on_chart_books_saved)
	_make_visible(false)


func _exit_tree() -> void:
	if _chart != null:
		_chart.queue_free()
		_chart = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _chart == null:
		return
	_chart.visible = visible
	if visible:
		_chart.reload_from_project()


func _get_plugin_name() -> String:
	return TAB_NAME


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"GraphEdit", &"EditorIcons")


## Called by the editor when it saves (Ctrl+S, **Scene > Save All**, or Save on
## the closing prompt).
func _save_external_data() -> void:
	if _chart != null and _chart.has_unsaved_changes():
		_chart.save()


## Called by the editor before it closes (`for_scene` empty) or closes a scene.
## A non-empty answer makes it ask whether to save first.
func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and _chart != null and _chart.has_unsaved_changes():
		return UNSAVED_QUESTION
	return ""


## Tells the editor's FileSystem panel that these files changed.
func _on_chart_books_saved(paths: PackedStringArray) -> void:
	var file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()
	for path: String in paths:
		file_system.update_file(path)
