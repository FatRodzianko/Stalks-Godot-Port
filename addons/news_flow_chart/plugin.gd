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
## All this does is hold the `NewsChart` screen and reload it each time the tab
## is opened, so edits made elsewhere (a text editor, the Inspector, a save)
## show up when you come back.


const CHART_SCENE: PackedScene = preload("res://addons/news_flow_chart/ui/news_chart.tscn")
const TAB_NAME: String = "News Flow"

var _chart: NewsChart = null


func _enter_tree() -> void:
	_chart = CHART_SCENE.instantiate() as NewsChart
	EditorInterface.get_editor_main_screen().add_child(_chart)
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
