extends Control
## Opens the title screen's SETTINGS tab so its layout can be looked at.
##
## Run with Godot's Movie Maker; see tools/loan_shot.gd for the command.

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

var _stage: Stage
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 3:
		return
	# The studio splash is what is on screen at frame 3 in any run with a real
	# window, and this has one. Before it existed the title screen was already
	# up by now, the cast below quietly returned null, and this tool rendered
	# the wrong tab without saying so. Asking for the menu outright is what
	# stops the next thing added in front of it breaking this again.
	_stage.game().show_menu()
	var menu: MainMenu = _stage.game().current_screen() as MainMenu
	if menu != null:
		menu.show_mode(MainMenu.Mode.SETTINGS)
