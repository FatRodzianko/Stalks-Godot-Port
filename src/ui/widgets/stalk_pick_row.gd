class_name StalkPickRow
extends PanelContainer
## One company in the Custom Stalks list, with the tick that puts it in a match.
##
## Knows nothing about the match, the cap, or the other rows: it shows a stalk
## and reports being ticked. The picker decides what that means. See
## docs/decisions.md D122.


## This row was ticked or unticked. Carries the id rather than the row, so the
## picker never holds a reference to a widget it did not build.
signal pick_changed(stalk_id: StringName, is_chosen: bool)


## What the right-hand column says about where a stalk came from. A player
## needs to tell their own companies from the shipped ones at a glance, and the
## id is no help — `custom:` is a prefix they never typed.
const SHIPPED_TAG: String = "shipped"
const CUSTOM_TAG: String = "custom"


@onready var _check: CheckBox = %Check
@onready var _origin: Label = %Origin
@onready var _figures: Label = %Figures


var _stalk_id: StringName = &""


func _ready() -> void:
	_check.toggled.connect(_on_check_toggled)


## Fills the row in. Called once, by the picker, after instantiating it.
func show_stalk(stalk: StalkDefinition, is_chosen: bool) -> void:
	_stalk_id = stalk.id
	_check.text = stalk.display_name
	_check.set_pressed_no_signal(is_chosen)
	_origin.text = CUSTOM_TAG if is_custom(stalk.id) else SHIPPED_TAG
	_figures.text = _summary_of(stalk)


## Whether an id belongs to a stalk the player wrote. One prefix, checked in one
## place, so nothing else has to know the spelling of it.
static func is_custom(stalk_id: StringName) -> bool:
	return String(stalk_id).begins_with(StalkSchema.CUSTOM_PREFIX)


## The stat block, in the order the board shows it: price, then what it pays in
## each mood. Enough to compare two companies without opening anything.
func _summary_of(stalk: StalkDefinition) -> String:
	return "$%d  +%d/%d" % [
		stalk.starting_price, stalk.bull_dividend, stalk.bear_dividend
	]


func stalk_id() -> StringName:
	return _stalk_id


func is_chosen() -> bool:
	return _check.button_pressed


## Ticks or unticks without reporting it, for the picker's own Reset and for
## the cap putting a row back.
func set_chosen(value: bool) -> void:
	_check.set_pressed_no_signal(value)


## Greys the tick out. Used when the match is full and this row is not in it:
## the row stays readable, it simply cannot be added to.
func set_available(value: bool) -> void:
	_check.disabled = not value


func _on_check_toggled(is_on: bool) -> void:
	pick_changed.emit(_stalk_id, is_on)
