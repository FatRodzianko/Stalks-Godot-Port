extends GutTest
## The yes/no overlay, and the countdown that answers for a player who cannot.
##
## The countdown exists for one situation: a resolution has just been applied
## and the player cannot read the screen well enough to press anything. Doing
## nothing has to be the safe outcome, so these tests are mostly about what
## happens when nobody answers.


const PanelScene: PackedScene = preload("res://src/ui/widgets/confirm_panel.tscn")


func _panel() -> ConfirmPanel:
	var panel: ConfirmPanel = PanelScene.instantiate()
	add_child_autofree(panel)
	return panel


func test_a_plain_question_has_no_countdown() -> void:
	var panel: ConfirmPanel = _panel()
	panel.ask("Leave?", "Leave", "Stay")

	assert_true(panel.is_open())
	assert_eq(panel.seconds_remaining(), 0)


func test_a_countdown_starts_at_the_number_given() -> void:
	var panel: ConfirmPanel = _panel()
	panel.ask_with_countdown("Keep this?", "Keep it", "Go back", 15)

	assert_eq(panel.seconds_remaining(), 15)


func test_saying_yes_stops_the_countdown() -> void:
	var panel: ConfirmPanel = _panel()
	panel.ask_with_countdown("Keep this?", "Keep it", "Go back", 15)
	watch_signals(panel)

	(panel.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_signal_emitted(panel, "confirmed")
	assert_eq(panel.seconds_remaining(), 0, "nothing left running")
	assert_false(panel.is_open())


func test_asking_again_without_a_countdown_clears_the_old_one() -> void:
	# The same panel is reused for every question a screen asks. A countdown
	# left running from a display change would cancel an unrelated question.
	var panel: ConfirmPanel = _panel()
	panel.ask_with_countdown("Keep this?", "Keep it", "Go back", 15)
	panel.ask("Leave?", "Leave", "Stay")

	assert_eq(panel.seconds_remaining(), 0)


func test_nobody_answering_counts_as_no() -> void:
	# One second rather than fifteen, so the suite does not sit here. The
	# behaviour under test is the tick reaching zero, which is the same tick
	# either way.
	var panel: ConfirmPanel = _panel()
	panel.ask_with_countdown("Keep this?", "Keep it", "Go back", 1)
	watch_signals(panel)

	await wait_seconds(1.5)

	assert_signal_emitted(panel, "cancelled")
	assert_signal_not_emitted(panel, "confirmed")
	assert_false(panel.is_open())


func test_the_countdown_is_visible_in_the_question() -> void:
	# A prompt that is about to answer itself has to say so, or waiting it out
	# looks like the game has frozen.
	var panel: ConfirmPanel = _panel()
	panel.ask_with_countdown("Keep this?", "Keep it", "Go back", 15)

	var message: String = (panel.get_node("%Message") as Label).text
	assert_string_contains(message, "Keep this?")
	assert_string_contains(message, "15")
