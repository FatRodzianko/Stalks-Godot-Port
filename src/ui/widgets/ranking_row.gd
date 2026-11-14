class_name RankingRow
extends PanelContainer
## One player in the standings: position, name, net worth.
##
## Trivial in a solo game, but the standings are the whole point of the game and
## this is what multiplayer will populate, so it exists from the start.


@onready var _position_label: Label = %Position
@onready var _name_label: Label = %Name
@onready var _net_worth_label: Label = %NetWorth


func display(position_index: int, player: PlayerState, is_local: bool) -> void:
	_position_label.text = "%d." % (position_index + 1)
	_name_label.text = player.display_name
	if is_local:
		_name_label.text += "  (you)"
	_net_worth_label.text = Palette.format_money(player.net_worth)

	# A bankrupt player is out; say so rather than showing a bare zero.
	if player.is_bankrupt:
		_net_worth_label.text = "BANKRUPT"
		_net_worth_label.theme_type_variation = &"Danger"
	else:
		_net_worth_label.theme_type_variation = &"Numeric"

	_name_label.theme_type_variation = &"Label" if is_local else &"Muted"
