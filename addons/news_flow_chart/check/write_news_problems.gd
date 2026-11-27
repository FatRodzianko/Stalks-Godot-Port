extends SceneTree
## Runs the content validator and writes its news errors, as JSON, to the path
## given after `--`. Started by `NewsProblems.run_check` in a headless Godot
## process of its own, because the validator cannot run inside the editor
## (see that file, and decisions.md D224).
##
## By hand, from the project root:
## `<godot> --headless --script res://addons/news_flow_chart/check/write_news_problems.gd -- <file>`


func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Give the file to write after --.")
		quit(1)
		return
	var library: ContentLibrary = ContentLibrary.load_from()
	library.load_fundamentals()
	var problems: Array[String] = NewsProblems.of(library.errors)
	quit(NewsProblems.write_result(problems, arguments[0]))
