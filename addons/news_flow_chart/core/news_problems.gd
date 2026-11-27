class_name NewsProblems
extends RefCounted
## What the News Flow Chart's **Problems** strip shows: the content
## validator's messages about news (docs/news-flow-chart.md §2).
##
## **The check runs in a separate Godot process, not in the editor.** Inside
## the running editor every company, trader, stalk and news item loaded from
## its file is a *placeholder*: its script is not a `@tool` script, so Godot
## keeps its fields but will not run its methods, and
## `ContentLibrary.load_fundamentals` stops at the first method call
## (decisions.md D224). So `run_check` starts the same Godot executable
## headless on `check/write_news_problems.gd`, which runs the real validator
## exactly as the tests do and writes what it found to a file. It takes about a
## second. It checks the books **as saved on disk**.


const CHECK_SCRIPT: String = "res://addons/news_flow_chart/check/write_news_problems.gd"
const RESULT_PATH: String = "user://news_flow_chart/problems.json"


## The validator's errors that are about news: every message naming news, a
## news line or the news folder.
static func of(errors: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for error: String in errors:
		if error.to_lower().contains("news"):
			found.append(error)
	return found


## Runs the validator in a headless Godot process and returns its news
## errors. If the check itself could not run, says so as the one problem.
static func run_check() -> Array[String]:
	var result_path: String = ProjectSettings.globalize_path(RESULT_PATH)
	DirAccess.make_dir_recursive_absolute(result_path.get_base_dir())
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)
	var arguments: PackedStringArray = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", CHECK_SCRIPT,
		"--", result_path,
	]
	var exit_code: int = OS.execute(OS.get_executable_path(), arguments)
	var found: Array[String] = read_result(result_path)
	if found.is_empty() and not FileAccess.file_exists(result_path):
		found.append("The news check did not run (Godot exited with code %d)." % exit_code)
	return found


## Writes `problems` where `read_result` will find them.
static func write_result(problems: Array[String], path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(problems))
	file.close()
	return OK


## The problems a check wrote to `path`; none if there is no file.
static func read_result(path: String) -> Array[String]:
	var found: Array[String] = []
	if not FileAccess.file_exists(path):
		return found
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array:
		found.append("The news check wrote something unreadable to %s." % path)
		return found
	for problem: Variant in parsed:
		found.append(str(problem))
	return found
