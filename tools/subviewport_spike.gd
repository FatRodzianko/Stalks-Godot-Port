extends SceneTree
## Does Godot route mouse input into a `SubViewport` for us, or would we have
## to transform coordinates by hand?
##
## This is the question that decides whether rendering the game through a
## `SubViewport` - the open option in decisions.md D94, and the same restructure
## D85's unfinished half needs - is a small change or a risky one.
##
## **The answer, measured 2026-11-17: Godot does it for us.** A button at
## (80, 40) inside a 640x360 `SubViewport`, shown at twice that size by a
## `SubViewportContainer`, reported a click at (30, 15) - its own middle, in its
## own coordinates, transformed through two spaces without a line of code. The
## project also has **no** direct pointer reads anywhere in `src/`, so there is
## nothing else that would need converting.
##
## **The catch is `stretch_shrink`, which is a whole number.** Only windows that
## are a whole multiple of 640x360 can produce a 640x360 viewport this way, so
## this route means integer scaling with black bars on the sizes that are not.
## The run prints that arithmetic.
##
## **Needs a real window.** Headless does no mouse picking at all, which is why
## `_control_case` exists: without it the first run of this spike reported that
## input was not forwarded, when in truth nothing was being picked anywhere.
##
##     <godot> --path . --script res://tools/subviewport_spike.gd
##
## This is a developer tool, not part of the game: `tools/` is excluded from
## the export (see `export_presets.cfg`) so none of it ships.


var _heard: Array[Vector2] = []
var _control: Array[Vector2] = []


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	await _control_case()

	# A container twice the size of the viewport inside it, which is what a
	# 1280x720 window showing a 640x360 game looks like.
	var container := SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = 2
	container.size = Vector2(1280, 720)
	container.position = Vector2.ZERO
	root.add_child(container)

	var inner := SubViewport.new()
	inner.handle_input_locally = true
	container.add_child(inner)

	var button := Button.new()
	button.position = Vector2(80, 40)
	button.size = Vector2(60, 30)
	button.gui_input.connect(_on_button_input)
	inner.add_child(button)

	await process_frame
	await process_frame

	print("container size    %s" % container.size)
	print("subviewport size  %s  (expected 640 x 360)" % inner.size)
	print("button rect       %s" % button.get_global_rect())

	# Mind which space each number is in. A pushed event is in WINDOW pixels,
	# and the project's stretch mode already halves those into the root
	# viewport's 640x360 before anything sees them. The container lives in that
	# viewport space, and shrinks by two again on the way in.
	#
	# So: button middle (110, 55) inside the SubViewport, times the container's
	# shrink of 2 is (220, 110) in viewport space, times the window's own stretch
	# of 2 is (440, 220) to push. Getting this wrong was the first result of this
	# spike and it looked exactly like "Godot does not forward input".
	_click_at(Vector2(440, 220))
	await process_frame
	await process_frame

	print("")
	if _heard.is_empty():
		print("RESULT  nothing reached the button - input is NOT forwarded")
	else:
		print("RESULT  the button heard a click at %s" % _heard[0])
		print("        the button sits at (80,40), so its own middle is (30, 15)")
		print("        input IS forwarded, and the coordinates are transformed")

	_report_non_integer()
	quit()


## Without this the spike cannot be trusted. If a click does not reach an
## ordinary button sitting in the ordinary viewport, then a headless run simply
## does not do mouse picking and the SubViewport result below means nothing.
func _control_case() -> void:
	var plain := Button.new()
	plain.position = Vector2(10, 10)
	plain.size = Vector2(60, 30)
	plain.gui_input.connect(_on_control_input)
	root.add_child(plain)

	await process_frame
	await process_frame
	_click_at(Vector2(40, 25))
	await process_frame
	await process_frame

	print("CONTROL  a plain button in the ordinary viewport heard: %s" % [
		"nothing - this spike cannot answer anything" if _control.is_empty()
		else str(_control[0])
	])
	print("")
	plain.queue_free()
	await process_frame


func _on_control_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed:
		_control.append(click.position)


func _click_at(where: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = where
		event.global_position = where
		root.push_input(event)


func _on_button_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed:
		_heard.append(click.position)


## The catch, if there is one: `stretch_shrink` is a whole number, so a window
## that is not a whole multiple of 640x360 cannot produce a 640x360 viewport
## this way.
func _report_non_integer() -> void:
	print("")
	print("what a window that is not a whole multiple gives:")
	for size: Vector2i in [
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1366, 768),
		Vector2i(1600, 900), Vector2i(1280, 800),
	]:
		var shrink: int = maxi(1, mini(size.x / 640, size.y / 360))
		print("  window %s  shrink %d  ->  viewport %d x %d%s" % [
			size, shrink, size.x / shrink, size.y / shrink,
			"" if size.x / shrink == 640 and size.y / shrink == 360 else "   NOT 640 x 360",
		])
