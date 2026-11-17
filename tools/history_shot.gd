extends Control
## Plays a match to its end and opens the result screen's year-by-year tab,
## so the layout can be looked at rather than only asserted about.
##
## Run with Godot's Movie Maker; see tools/loan_shot.gd for the command.

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

var _stage: Stage
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.loans_enabled = true
	settings.rng_seed = 555
	_stage.game().start_match(settings)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8:
		_measure()
	if _frames != 3:
		return

	var screen: GameplayScreen = _stage.game().current_screen()
	var ready_button: Button = screen.get_node("%ReadyButton")
	while not _stage.game().session().state().is_over:
		ready_button.pressed.emit()

	var over: GameOverScreen = _stage.game().current_screen()
	over.show_history()


## Measured several frames later: containers lay out at the end of a frame, so
## asking in the frame that built them gives every control its minimum size at
## the origin, which is what the first attempt at this measured.
func _measure() -> void:
	var over: GameOverScreen = _stage.game().current_screen() as GameOverScreen
	if over == null or over.history_rows().is_empty():
		return
	var header: Node = over.get_node("%HistoryHeaderSlot").get_child(0)
	var first: Node = over.history_rows()[0]
	for pair: Array in [["header", header], ["row", first]]:
		var row: Node = pair[1]
		var line: PackedStringArray = []
		for column: String in ["%Year", "%Mood", "%NetWorth", "%Summary"]:
			var label: Control = row.get_node(column)
			line.append("%s x=%d w=%d" % [
				column.substr(1), int(label.global_position.x), int(label.size.x)
			])
		print("%-7s %s" % [pair[0], " | ".join(line)])
