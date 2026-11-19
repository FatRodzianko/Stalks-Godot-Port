extends Control
## Renders the top strip with a description too long for it, so the "... MORE"
## button's placement can be looked at rather than reasoned about.
##
## **Why this exists.** The button was a column in an HBoxContainer, which gave
## it the full height of the strip and narrowed every line of the description;
## the first line ended in mid-air with an empty block beside it. That is
## obvious in a screenshot and invisible in a test, which is the same reason
## tools/loan_shot.gd exists.
##
## Run it the same way — Movie Maker, because Godot cannot render headless:
##
##     $g = "<path to>\Godot_v4.7.2-stable_win64_console.exe"
##     $dir = "$env:TEMP\stalks_frames"
##     New-Item -ItemType Directory -Force $dir | Out-Null
##     & $g --path . res://tools/more_shot.tscn --write-movie "$dir\f.png" `
##          --quit-after 12 --fixed-fps 10

const StageScene: PackedScene = preload("res://src/ui/stage.tscn")

## A real description from the shipped content, one of the twenty that do not
## fit the two lines the strip reserves.
const LONG: String = (
	'"What ever happened to the Gary Cooper types" you say to yourself as you '
	+ "start to cry watching your portfolio burn to the ground for the third "
	+ "year running"
)

var _stage: Stage
var _frames: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage = StageScene.instantiate()
	add_child(_stage)

	var settings: GameSettings = GameSettings.new()
	settings.max_years = 10
	settings.player_count = 1
	settings.rng_seed = 555
	_stage.game().start_match(settings)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames != 3:
		return

	var screen: GameplayScreen = _stage.game().current_screen()
	var flavour: ScrollingLabel = screen.get_node("%EventFlavour")
	var effect: Label = screen.get_node("%EventEffect")
	flavour.set_full_text(LONG)
	effect.text = "Mafia HUD Scam fell by 15"
	print("lines=", flavour.line_count(), " per_line=", flavour.characters_per_line(),
		" overflows=", flavour.overflows())
