class_name CrtOverlay
extends CanvasLayer
## The optional CRT effect: a sheet of glass laid over the whole game.
##
## It is one `ColorRect` filling the screen, carrying `crt_screen.gdshader`,
## which reads the picture drawn underneath it and hands back a warped, bled,
## scanlined version of the same thing. Off unless the player turns it on in
## Settings. See docs/decisions.md D94.
##
## **It is a `CanvasLayer`, for the same two reasons the development overlay
## is.** A container lays out its `Control` children, and `Main` is a
## `MarginContainer`, so an ordinary child would be stretched and shuffled by
## whatever screen was swapped in. A `CanvasLayer` is not a `Control`, so no
## container touches it, and its `layer` decides what it draws over regardless
## of child order.
##
## **Its layer sits between the game and the development overlay.** Everything
## the game draws is on layer 0 - screens, the pause menu, the confirmation
## panels parented to the window - so anything above that covers all of it.
## The development overlay is at 128 and stays above this one on purpose:
## debugging text behind a barrel warp and a scanline comb is worse debugging
## text, and it is not part of the game a player sees.
##
## **It must never take a click.** A full-screen rect in front of everything
## with the usual mouse handling would swallow every press in the game and
## there would be no way to turn it off again. The scene sets
## `mouse_filter = MOUSE_FILTER_IGNORE` and `test_crt_overlay.gd` checks that
## it stays that way.


## How the settings panel reaches this without a chain of signals.
##
## The panel is used in two places - the title screen's Settings tab and the
## pause menu - and is several nodes deep in both. Bubbling a signal up to
## `Main` from each of them would mean two new signals and two new handlers in
## scenes that have no other reason to know this exists. Volume goes to the
## `Audio` autoload and resolution goes to `DisplayMode`; this is the same
## idea, reached by group rather than by node path, so nothing has to know
## where in the tree it was put.
const GROUP: String = "crt_overlay"


func _ready() -> void:
	add_to_group(GROUP)


## Turns the effect on or off wherever it is in this tree.
##
## A no-op when there is no overlay, which is what a test that builds a widget
## on its own looks like.
static func apply(tree: SceneTree, on: bool) -> void:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var overlay: CrtOverlay = node as CrtOverlay
		if overlay != null:
			overlay.enable(on)


func enable(on: bool) -> void:
	visible = on


func is_enabled() -> bool:
	return visible
