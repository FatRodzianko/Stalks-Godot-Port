extends Control
## Renders the Custom Stalks picker and a full board, so both can be looked at
## rather than reasoned about.
##
## **Why this exists.** A list of thirteen rows with a scroll, and a board of
## ten companies with long names, are exactly the things a passing test does
## not show you: `test_custom_stalk_ui.gd` proves the rows exist and that the
## board has somewhere to scroll to, and neither says whether the result is
## readable. The same reason tools/more_shot.gd and tools/loan_shot.gd exist.
##
## Run it with Movie Maker, because Godot cannot render headless:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/custom_stalks_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 16 --fixed-fps 10
##
## Frames 1-7 are the picker; after that it swaps to the board.

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")
const PickerScene: PackedScene = preload("res://src/ui/widgets/stalk_picker.tscn")

## When to swap the picker for the board.
const BOARD_AT_FRAME: int = 8

var _stage: Stage
var _picker: StalkPicker
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)

	# **Through the real menu, not a picker of its own.** The game draws at a
	# low resolution and the Stage upscales it; a panel added beside the Stage
	# renders at the window's own size and looks nothing like the real thing.
	# The first version of this tool did that and made the picker look cramped
	# when it was not.
	_stage.game().show_menu()


## A stand-in custom stalk, so the list is longer than the panel.
##
## Named plainly on purpose: this is a developer tool and the game's voice is
## not mine to invent. See CLAUDE.local.md.
func _invented(index: int) -> StalkDefinition:
	var schema: StalkSchema = StalkSchema.from_file_data({
		"name": "Custom Company %d" % (index + 1),
		"bull_change": [0, 12],
		"bear_change": [4, 18],
		"bull_dividend": 3,
		"bear_dividend": 1,
	}, "example%d" % index)
	return schema.definition


## Puts three stand-in companies in, so the list is longer than the panel and
## the scroll has something to do. A machine with real custom stalk files
## would show those instead.
func _lengthen_the_list() -> void:
	var available: Array[StalkDefinition] = ContentLibrary.load_from().stalks
	for index: int in 3:
		available.append(_invented(index))
	_picker.show_stalks(available, _shipped_ids(), [
		"broken.json: line 4: Expected ':'",
	] as Array[String])


func _shipped_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for stalk: StalkDefinition in ContentLibrary.load_from().stalks:
		out.append(stalk.id)
	return out


func _process(_delta: float) -> void:
	_frames += 1

	# Opened by pressing the button a player presses, so this also says the
	# wiring works.
	if _frames == 3:
		var menu: MainMenu = _stage.game().current_screen() as MainMenu
		if menu != null:
			var button: Button = menu.get_node("%CustomStalksButton")
			button.pressed.emit()
			_picker = menu.get_node("%Picker")
			_lengthen_the_list()
		return

	if _frames != BOARD_AT_FRAME:
		return

	if _picker != null:
		print("picker rows=", _picker.row_count(), " chosen=", _picker.chosen_ids().size())
		_picker.hide()

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.rng_seed = 555
	_stage.game().start_match(settings)
