extends SceneTree
## Do dropdowns land in the right place inside a `SubViewport`?
##
## **The question.** Rendering the game through a `SubViewport` is the open
## option in decisions.md D94 - it is what would let the CRT effect run at
## monitor resolution, and it is the same restructure D85's unfinished half
## needs. A `PopupMenu` is a `Window`, not a `Control`, so it is placed in its
## own space rather than by the layout, and if popups land wrongly the
## restructure costs far more than it looks. The game has one `OptionButton`,
## the resolution dropdown in Settings, and about nineteen tooltips.
##
## **The answer, measured 2026-11-17.** Set `gui_embed_subwindows = true` on
## the `SubViewport` and a dropdown is exactly where it is today, to the pixel:
##
##     ordinary viewport              position (100, 181)  size (160, 62)
##     SubViewport, left alone        position (200, 236)  size (320, 124)
##     SubViewport, embedding set     position (100, 181)  size (160, 62)
##
## Left alone, the popup lives in the root viewport instead: position and size
## both multiplied by the container's shrink. It still appears beside its own
## button on screen, so it does not look broken - it is drawn outside the
## SubViewport, which under that restructure means at window resolution and
## outside any screen effect. A small sharp dropdown over a chunky pixel UI.
## One property fixes it.
##
## **Tooltips are not answered here.** A synthetic hover produced none within
## a second and a half, so this proves nothing either way about them. They
## ought to follow the dropdown, since a tooltip is made by whichever viewport
## owns the GUI and a `SubViewport` owns its own - but that is reasoning, not
## a measurement, and reasoning about viewports is exactly what
## `subviewport_spike.gd` got wrong. Check them by hand against a real build.
##
## Needs a real window; popups do nothing headless:
##
##     <godot> --path . --script res://tools/popup_spike.gd
##
## This is a developer tool, not part of the game: `tools/` is excluded from
## the export (see `export_presets.cfg`) so none of it ships.


const SHRINK: int = 2

## Where the dropdown sits. Far enough down that a popup placed in the wrong
## space is obvious rather than marginal.
const BUTTON_AT: Vector2 = Vector2(100, 150)


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	print("subwindows embedded by default:  %s" % root.gui_embed_subwindows)
	print("")

	var plain: OptionButton = _dropdown()
	root.add_child(plain)
	await process_frame
	await _describe("in the ordinary viewport", plain)

	var left_alone: OptionButton = _in_a_subviewport(false)
	await process_frame
	await _describe("in a SubViewport, left alone", left_alone)

	var embedding: OptionButton = _in_a_subviewport(true)
	await process_frame
	await _describe("in a SubViewport that embeds its own", embedding)

	print("The third should match the first exactly. If it does not, read the")
	print("note at the top of this file - it did on 2026-11-17.")
	quit()


## A `SubViewport` shown at `SHRINK` times its size, the way the game would be.
func _in_a_subviewport(embed_subwindows: bool) -> OptionButton:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = SHRINK
	container.size = Vector2(640 * SHRINK, 360 * SHRINK)
	root.add_child(container)

	var inner := SubViewport.new()
	inner.handle_input_locally = true
	# The whole finding, in one property.
	inner.gui_embed_subwindows = embed_subwindows
	container.add_child(inner)

	var option: OptionButton = _dropdown()
	inner.add_child(option)
	return option


func _dropdown() -> OptionButton:
	var option := OptionButton.new()
	option.position = BUTTON_AT
	option.size = Vector2(160, 24)
	option.add_item("1920 x 1080")
	option.add_item("1280 x 720")
	return option


## Awaited by its callers, so the three reports come out in order. The first
## version was not, and printed its headings and its figures interleaved -
## which is a good way to misread your own experiment.
func _describe(where: String, option: OptionButton) -> void:
	option.show_popup()
	await process_frame
	await process_frame

	var popup: PopupMenu = option.get_popup()
	var bottom_edge: int = int(option.position.y + option.size.y)
	print("%s" % where)
	print("  button at          %s  size %s" % [option.position, option.size])
	print("  popup position     %s" % popup.position)
	print("  popup size         %s" % popup.size)
	print("  directly below?    %s" % [
		"yes" if popup.position.y == bottom_edge
		else "no - the button's bottom edge is y=%d" % bottom_edge
	])
	popup.hide()
	await process_frame
	print("")
