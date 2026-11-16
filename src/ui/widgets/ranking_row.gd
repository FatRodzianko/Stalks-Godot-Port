class_name RankingRow
extends PanelContainer
## One player in the rankings: name, net worth, ready status.
##
## Columns match the original's PlayerRankingsListItem — name, networth, and a
## coloured dot for whether that player has readied up. See docs/ui-reference.md.


@onready var _name_label: Label = %Name
@onready var _net_worth_label: Label = %NetWorth
@onready var _ready_dot: Panel = %ReadyDot

var _is_header: bool = false


func configure_as_header() -> void:
	_is_header = true
	theme_type_variation = &"HeaderCard"
	_name_label.text = "PLAYER"
	_net_worth_label.text = "NETWORTH"
	for label: Label in [_name_label, _net_worth_label]:
		label.theme_type_variation = &"Faint"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_ready_dot.visible = false
	%ReadyHeading.visible = true


## `is_host` marks the player whose machine is running the match.
##
## Said in a word rather than with a symbol. The first version used a leading
## `*` and explained itself in a tooltip, which meant the only clue on screen
## was a punctuation mark you had to hover to understand.
##
## Both tags go in one bracket — "(Host, you)" rather than "(Host) (you)" —
## because this column is a few characters wide at the game's resolution.
func display(
	player: PlayerState,
	is_local: bool,
	is_ready: bool,
	is_host: bool = false,
) -> void:
	if _is_header:
		return

	# The same text in both places, and the tooltip is the only one of them
	# that is never cut short: this column is a few characters wide, so a name
	# of any length ends in an ellipsis. Hovering is how you read it, and the
	# tags belong there too — the first version put the bare name in the
	# tooltip, so hovering a truncated row told you less than the row did.
	var full: String = player.display_name + _tags_for(player, is_local, is_host)
	_name_label.text = full
	_name_label.tooltip_text = full

	if player.is_bankrupt:
		_net_worth_label.text = "BANKRUPT"
		_net_worth_label.theme_type_variation = &"Danger"
	else:
		_net_worth_label.text = Palette.format_money(player.net_worth)
		_net_worth_label.theme_type_variation = &"Numeric"

	# Red until ready, green once ready — the original used a coloured image.
	_ready_dot.visible = true
	_ready_dot.modulate = Palette.BULL if is_ready else Palette.DANGER
	_ready_dot.tooltip_text = "Ready for the new year" if is_ready else "Not ready yet"


## "", " (Host)", " (you)" or " (Host, you)".
##
## "you" is left off when the name already says it, which it does in a solo
## game where the only player is called "You": "You (you)" was nonsense.
func _tags_for(player: PlayerState, is_local: bool, is_host: bool) -> String:
	var tags: PackedStringArray = []
	if is_host:
		tags.append("Host")
	if is_local and player.display_name.to_lower() != "you":
		tags.append("you")
	if tags.is_empty():
		return ""
	return " (%s)" % ", ".join(tags)
