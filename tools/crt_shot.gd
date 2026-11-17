extends Control
## Renders a picture of the title screen with the CRT effect switched on, so
## the effect can be looked at without starting the game and walking to
## Settings.
##
## **Why this exists.** The shader is the one part of this project that no test
## can reach: the suite runs headless, nothing is rendered, and the shader is
## never compiled. A shader that fails to compile passes every test in the
## repository. This renders it for real and writes a PNG.
##
## It forces a window on the way in, whatever the saved settings say, so
## running this does not throw the machine into fullscreen for a second.
##
## From the project root, in PowerShell:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/crt_shot.tscn --write-movie "$dir\crt.png" `
##          --quit-after 12 --fixed-fps 10
##
## The frames land as `crt00000001.png` onwards; the last one is the one to
## look at. Watch the console output as well: a shader that will not compile
## says so there and nowhere else.
##
## Set `EFFECT_ON` to false to render the same screen without the effect, which
## is what the comparison is against.
##
## Set `SHOW_THE_BOARD` to render the playing screen instead of the title
## screen. The board is the better subject for anything about text: it is a
## table of evenly spaced rows, so a fault that varies down the screen shows up
## as some rows looking different from their neighbours.
##
## This is a developer tool, not part of the game: `tools/` is excluded from
## the export (see `export_presets.cfg`) so none of it ships.

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

## Whether to draw the effect. The point of the tool, but useful both ways.
const EFFECT_ON: bool = true

## A window rather than the whole screen, and a size the picture fits exactly:
## 1920x1080 is three times 640x360, so nothing is letterboxed and the shader
## sees the same enlargement most players will.
const WINDOW: Vector2i = Vector2i(1920, 1080)

## Whether to start a match rather than stay on the title screen.
const SHOW_THE_BOARD: bool = false

## Whether to get rid of the studio logo. Set false to photograph the logo
## itself, which is the one place in the game with a large pixel-art image
## rather than text, and so the one place a sampling fault shows up as a
## jagged edge rather than as a soft letter. Give it thirty frames or so, or
## the capture lands during the fade.
const SKIP_THE_SPLASH: bool = true

var _stage: Stage

## Movie Maker starts drawing immediately, so the screen needs a frame or two
## to exist before anything can be switched on.
var _frames: int = 0


## The splash runs in front of the title screen in any run with a real window,
## and this has one. Four and a half seconds of logo at ten frames a second is
## forty-five frames of the wrong picture.
func _skip_the_splash() -> void:
	if not SKIP_THE_SPLASH:
		return
	var splash: SplashScreen = _stage.game().current_screen() as SplashScreen
	if splash != null:
		splash.skip()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)
	# `Main._ready` has already applied the saved display settings by now, so
	# this undoes that rather than pre-empting it.
	DisplayMode.apply(get_window(), WINDOW, false)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 3:
		return
	_skip_the_splash()
	if SHOW_THE_BOARD:
		_start_a_match()
	_stage.crt_overlay().enable(EFFECT_ON)


## A fixed seed, so the board says the same thing in both renders. Comparing
## two pictures of different markets would measure the market.
func _start_a_match() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.loans_enabled = true
	settings.rng_seed = 555
	_stage.game().start_match(settings)
