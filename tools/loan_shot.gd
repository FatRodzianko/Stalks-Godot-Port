extends Control
## Renders a picture of the board in the state that is hardest to check by
## hand: year 3, with a loan running and a payment due.
##
## **Why this exists.** The playing screen can be asserted about in tests, but
## some faults are only visible — a caption that does not fit its button, a bar
## that changes height, text clipped mid-sentence. Looking at those used to
## mean building the game, copying it to another machine and playing three
## years. This gets a PNG in about two seconds.
##
## Godot cannot render anything with `--headless`, so this runs the real game
## with **Movie Maker**, which draws frames at a fixed rate and writes each one
## to a numbered file. `--quit-after 12` is a frame count, not seconds.
##
## From the project root, in PowerShell:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/loan_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 12 --fixed-fps 10
##
## The frames land as `f00000001.png` onwards; the last one is the one to look
## at. To photograph a different state, change what `_process` does below.
##
## This is a developer tool, not part of the game: `tools/` is excluded from the
## export (see `export_presets.cfg`) so none of it ships.

const MainScene: PackedScene = preload("res://src/ui/screens/main/main.tscn")

var _main: Main

## Movie Maker starts drawing immediately, so the board needs a frame or two to
## exist before anything can be pressed on it.
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_main = MainScene.instantiate()
	add_child(_main)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.loans_enabled = true
	settings.rng_seed = 555
	_main.start_match(settings)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 3:
		return

	var screen: GameplayScreen = _main.current_screen()
	var ready_button: Button = screen.get_node("%ReadyButton")

	# Loans only become available from year 2.
	for _step: int in 2:
		ready_button.pressed.emit()

	var session: LocalSession = _main.session()
	session.request_loan(&"p0", LoanRules.max_loan_for(
		session.state().player_by_id(&"p0")
	))

	# A loan taken this year counts as paid, so one more year is what makes a
	# payment fall due and the reminder appear.
	ready_button.pressed.emit()
