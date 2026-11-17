class_name SplashScreen
extends Control
## The studio logo, shown once as the game starts.
##
## Fades in, holds, fades out. Nothing moves.
##
## **There was a slow push towards the viewer**, the shape an engine's own logo
## splash usually takes. It was built, looked at, and dropped: scaling pixel
## art by a fraction that changes every frame makes its pixels crawl, and at
## this size the crawling was all you could see.
##
## With nothing moving, the logo can sit at an exact **2x** — 512x288 of the
## 256x144 original — centred on black, so every source pixel is a clean
## square of four and nothing is resampled at all. Standing still is what buys
## that back. See decisions.md D93.
##
## **Skippable by anything.** A key, a mouse button, a controller face button —
## all of them end it immediately. A splash that cannot be skipped is a tax on
## everybody who launches the game more than once, and during development that
## is many times a day.


## The splash is over, by time or by a keypress. The screen host decides what
## comes next — this knows nothing about menus.
signal finished


## How long the whole thing lasts if nobody interrupts it.
const FADE_IN_SECONDS: float = 0.7
const HOLD_SECONDS: float = 1.1
const FADE_OUT_SECONDS: float = 0.7


## Set once the splash has ended, so a late keypress cannot finish it twice.
var _done: bool = false

@onready var _logo: TextureRect = %Logo


func _ready() -> void:
	_logo.modulate.a = 0.0
	_play()


func _play() -> void:
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
