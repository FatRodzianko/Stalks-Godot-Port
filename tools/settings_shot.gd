extends Control
## Opens the title screen's SETTINGS tab so its layout can be looked at.
##
## Run with Godot's Movie Maker; see tools/loan_shot.gd for the command.

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")

var _main: Main
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_main = MainScene.instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 3:
		return
	var menu: MainMenu = _main.current_screen() as MainMenu
	if menu != null:
		menu.show_mode(MainMenu.Mode.SETTINGS)
