extends Control
## Renders the title screen with REJOIN GAME showing, so its placement can be
## looked at rather than reasoned about.
##
## The owner asked for it "bottom right, mirroring the existing Quit to Desktop
## button", and that is a claim about pixels. `test_main_rejoin.gd` asserts the
## two share a row and a size, which is as far as a test can honestly go.
##
## A record is written to a **temporary** path and the screen host is pointed at
## it, so looking at the button never invents a match on this machine.
##
## Run it with Movie Maker, because Godot cannot render headless:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/rejoin_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 12 --fixed-fps 10

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

const RECORD: String = "user://rejoin_shot.cfg"

var _stage: Stage


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)

	LastMatch.remember(4242, "Friday night", RECORD)
	_stage.game()._last_match_path = RECORD
	_stage.game().show_menu()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		LastMatch.forget(RECORD)
