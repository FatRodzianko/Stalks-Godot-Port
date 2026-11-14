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


func display(player: PlayerState, is_local: bool, is_ready: bool) -> void:
	if _is_header:
		return

	_name_label.text = player.display_name
	if is_local:
		_name_label.text += " (you)"
	_name_label.tooltip_text = player.display_name

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
