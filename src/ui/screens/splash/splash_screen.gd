class_name SplashScreen
extends Control
## The studio logo, shown once as the game starts.
##
## A slow push towards the viewer with a fade in and out, the shape every
## engine's own logo splash uses. Nothing here is interactive except getting
## rid of it.
##
## **Skippable by anything.** A key, a mouse button, a controller face button —
## all of them end it immediately. A splash that cannot be skipped is a tax on
## everybody who launches the game more than once, and during development that
## is many times a day.
##
## **Not pixel-perfect, on purpose.** The logo is pixel art, but it is being
## scaled by a fraction that changes every frame, so nearest-neighbour sampling
## would make its pixels crawl and shimmer as the number drifted. It is drawn
## with linear filtering instead, which is the one place in this project that
## happens. The owner asked for the movement and said pixel-perfection here was
## not needed; see decisions.md D93.


## The splash is over, by time or by a keypress. The screen host decides what
## comes next — this knows nothing about menus.
signal finished


## How long the whole thing lasts if nobody interrupts it.
const FADE_IN_SECONDS: float = 0.7
const HOLD_SECONDS: float = 1.1
const FADE_OUT_SECONDS: float = 0.7

## The logo grows by this much across the whole splash. Small on purpose: the
## effect wanted is "slowly moving toward you", not a zoom.
const START_SCALE: float = 0.88
const END_SCALE: float = 1.06


## Set once the splash has ended, so a late keypress cannot finish it twice.
var _done: bool = false

@onready var _logo: TextureRect = %Logo


func _ready() -> void:
	_logo.modulate.a = 0.0
	# A Control scales about its pivot, which starts at its top-left corner.
	# Without this the logo would grow away towards the bottom right instead of
	# towards the viewer.
	_logo.pivot_offset = _logo.size / 2.0
	_logo.scale = Vector2.ONE * START_SCALE
	_play()


## Runs the whole sequence as one tween: the movement is continuous from first
## frame to last, while the fade happens at each end of it.
##
## Two tweens rather than one because they run over different spans — the
## growth never pauses, and the fade does.
func _play() -> void:
	var total: float = FADE_IN_SECONDS + HOLD_SECONDS + FADE_OUT_SECONDS

	var movement: Tween = create_tween()
	movement.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	movement.tween_property(_logo, "scale", Vector2.ONE * END_SCALE, total)

	var fade: Tween = create_tween()
	fade.tween_property(_logo, "modulate:a", 1.0, FADE_IN_SECONDS)
	fade.tween_interval(HOLD_SECONDS)
	fade.tween_property(_logo, "modulate:a", 0.0, FADE_OUT_SECONDS)
	fade.finished.connect(skip)


## Ends the splash now. Public so the screen host, or a test, can cut it short
## without pretending to press a key.
func skip() -> void:
	if _done:
		return
	_done = true
	finished.emit()


## Anything at all ends it.
##
## `_unhandled_input` rather than `_unhandled_key_input` so a mouse click and a
## controller button work too — a player who has just launched the game may
## well not have a hand on the keyboard.
func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	var pressed: bool = (
		(event is InputEventKey and event.is_pressed() and not event.is_echo())
		or (event is InputEventMouseButton and event.is_pressed())
		or (event is InputEventJoypadButton and event.is_pressed())
	)
	if not pressed:
		return
	accept_event()
	skip()
