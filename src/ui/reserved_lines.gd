class_name ReservedLines
extends RefCounted
## Holds a wrapping label at its full height whether its text fills it or not.
##
## **A label that wraps is a panel that changes size.** `autowrap_mode` plus
## `max_lines_visible` gives a label a minimum height of however many lines it
## currently needs, so a sentence that grows from one line to two pushes
## everything below it down and makes the card around it jump. The player sees a
## panel resize because somebody joined, or because a different tab was chosen.
##
## The fix is to reserve the space up front: the label is as tall as it is ever
## allowed to be, and short text simply leaves part of it empty.
##
## **The height has to be measured rather than written down.** It depends on the
## theme's font and size, so a number in a scene file would be wrong the moment
## either changed. See docs/decisions.md D125.


## Pins `label` to the height of `max_lines_visible` lines. Call it once, after
## the label is in the tree so its theme has resolved.
static func reserve(label: Label) -> void:
	if label == null or label.max_lines_visible <= 0:
		return

	var line_height: int = label.get_theme_font("font").get_height(
		label.get_theme_font_size("font_size")
	)
	# Not every theme defines line spacing, and asking for one that is not there
	# logs an error rather than returning zero.
	var spacing: int = 0
	if label.has_theme_constant("line_spacing"):
		spacing = label.get_theme_constant("line_spacing")

	label.custom_minimum_size.y = (line_height + spacing) * label.max_lines_visible
