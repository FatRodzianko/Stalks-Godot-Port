class_name CrtOverlay
extends Node
## The optional CRT effect: a material put on the control that shows the game.
##
## It owns no picture of its own. `Stage` draws the game into a `SubViewport`
## and shows it through a `SubViewportContainer`; this hangs the shader on that
## container, so the effect covers exactly the picture and runs at the
## monitor's resolution. Off unless the player turns it on in Settings. See
## docs/decisions.md D94 for the effect and D96 for the display path.
##
## **It used to be a `CanvasLayer` with a full-screen rectangle on it**, reading
## the screen texture. That worked while the whole game was drawn at 640x360,
## and it had to go when the display path was rebuilt. Two reasons, and the
## second is the one that matters:
##
##   * Reading the *screen* means the warp and the vignette frame the window.
##     Once the window stopped being the picture - a letterboxed monitor has
##     black bars around it - the tube's edge was out in the bars rather than
##     around the game.
##   * A rectangle over the whole screen has to be told not to take mouse
##     clicks, and getting that wrong swallows every press in the game
##     including the one that turns the effect off. A material has no such
##     failure mode, because it is not a node in front of anything.
##
## **Nothing else in the game knows it exists.** The settings panel reaches it
## through a group rather than a chain of signals: the panel is used in two
## places and is several nodes deep in both, so bubbling a signal up to the
## root from each of them would mean two new signals and two new handlers in
## scenes with no other reason to know. Volume goes to the `Audio` autoload and
## resolution goes to `DisplayMode`; this is the same idea.


## How the settings panel finds this without knowing where it is.
const GROUP: String = "crt_overlay"

## The effect itself. A resource rather than a material built in code, so the
## shader it points at is visible in a diff.
const MATERIAL: ShaderMaterial = preload("res://src/ui/crt_screen.tres")


## What the effect is drawn on: the control showing the game's picture. Set by
## whoever builds this, before it enters the tree.
var target: CanvasItem

## The picture to read. The same image the target is already drawing, handed
## over explicitly because the shader takes it as a uniform rather than reading
## the built-in `TEXTURE` — see the note at the top of `crt_screen.gdshader`.
var source: Texture2D

## How many times the picture is enlarged to fill the window. The shader needs
## it to know how wide one screen pixel is in the picture's own terms.
var enlargement: int = 1

## What was asked for, which is the truth even in a headless run where there is
## nothing to draw on.
var _wanted: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	_put_it_on_or_take_it_off()


## Turns the effect on or off wherever it is in this tree.
##
## A no-op when there is none, which is what a widget built on its own in a
## test looks like.
static func apply(tree: SceneTree, on: bool) -> void:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var overlay: CrtOverlay = node as CrtOverlay
		if overlay != null:
			overlay.enable(on)


func enable(on: bool) -> void:
	_wanted = on
	_put_it_on_or_take_it_off()


func is_enabled() -> bool:
	return _wanted


## **The filter is switched with the effect, and that is not optional.**
##
## A `CanvasItem`'s `texture_filter` overrides the `filter_linear` hint on the
## shader's own sampler, so with the target left on nearest the shader samples
## nearest no matter what it asks for - and its edge reconstruction, which
## works by nudging where it reads from, does nothing at all. The picture then
## comes out as a plain nearest upscale with a stair-step in every line the
## tube bends, which is exactly how it was reported.
##
## It is the opposite with the effect off: there the target draws the picture
## itself at a whole multiple, where nearest is the only right answer and
## linear would soften every letter for nothing.
func _put_it_on_or_take_it_off() -> void:
	if target == null:
		return
	if source != null:
		MATERIAL.set_shader_parameter("picture", source)
	MATERIAL.set_shader_parameter("enlargement", float(enlargement))
	target.material = MATERIAL if _wanted else null
	target.texture_filter = _filter_for(_wanted)


func _filter_for(effect_on: bool) -> CanvasItem.TextureFilter:
	if effect_on:
		return CanvasItem.TEXTURE_FILTER_LINEAR
	return CanvasItem.TEXTURE_FILTER_NEAREST
