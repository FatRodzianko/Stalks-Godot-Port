class_name LocalSession
extends GameSession
## A complete game played in this process, with no peer and no Steam.
##
## The original could only run through a Steam lobby, so it could not be played
## or tested without Steam running. Offline play is a genuine new feature and the
## simplest place for the UI to be built against — see docs/decisions.md D14.
##
## Being authoritative in-process, this needs none of the prediction or
## reconciliation machinery a client would: every request is validated and applied
## immediately, then a signal fires. It is still validated, because the UI's
## pre-checks are presentation and the authority is here.


var _state: GameState
var _resolver: YearResolver
var _rng: RandomNumberGenerator
var _local_player_id: StringName = &"p0"


## Builds a ready-to-play match from authored content.
##
## `settings.rng_seed` of 0 means "pick one and record it", so that a match is
## always reproducible afterwards even when the player did not choose a seed.
static func create(
	settings: GameSettings,
	library: ContentLibrary,
	player_names: Array[String] = ["You"],
) -> LocalSession:
	var session: LocalSession = LocalSession.new()
	session.name = "LocalSession"

	if settings.rng_seed == 0:
		settings.rng_seed = abs(int(Time.get_unix_time_from_system() * 1000.0)) | 1

	session._rng = RandomNumberGenerator.new()
	session._rng.seed = settings.rng_seed

	session._state = GameState.new(settings)
	session._state.stalks = library.build_stalk_states()
	for index: int in player_names.size():
		session._state.players.append(PlayerState.new(
			StringName("p%d" % index),
			player_names[index],
			settings.starting_cash,
		))

	session._resolver = YearResolver.new(
		RandomRangePriceModel.new(),
		library.build_event_pool(),
	)

	# The match opens at **Year 0**: every price at its starting value, trading
	# closed, waiting for players to ready up. That is the original's opening
	# state and what docs/game-rules.md §4 describes, so the session starts there
	# rather than skipping ahead.
	return session


func state() -> GameState:
	return _state


func local_player_id() -> StringName:
	return _local_player_id


## The seed this match is running on. Worth surfacing somewhere in the UI: it is
## what makes a match reproducible, and a player reporting a bug can quote it.
func seed_value() -> int:
	return _state.settings.rng_seed if _state != null and _state.settings != null else 0


# ------------------------------------------------------------------ the requests

func request_buy(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	var player: PlayerState = _state.player_by_id(player_id)
	var stalk: StalkState = _state.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		action_rejected.emit(player_id, "Unknown player or stalk.")
		return

	var reason: String = TradeRules.validate_buy(player, stalk, shares, _state)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return

	TradeRules.apply_buy(player, stalk, shares)
	player.net_worth = TradeRules.net_worth(player, _state)
	player_changed.emit(player_id)


func request_sell(player_id: StringName, stalk_id: StringName, shares: int) -> void:
	var player: PlayerState = _state.player_by_id(player_id)
	var stalk: StalkState = _state.stalk_by_id(stalk_id)
	if player == null or stalk == null:
		action_rejected.emit(player_id, "Unknown player or stalk.")
		return

	var reason: String = TradeRules.validate_sell(player, stalk, shares, _state)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return

	TradeRules.apply_sell(player, stalk, shares)
	player.net_worth = TradeRules.net_worth(player, _state)
	player_changed.emit(player_id)


func request_loan(player_id: StringName, amount: int) -> void:
	var player: PlayerState = _state.player_by_id(player_id)
	if player == null:
		action_rejected.emit(player_id, "Unknown player.")
		return

	var reason: String = LoanRules.validate_take_loan(player, amount, _state)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return

	LoanRules.take_loan(player, amount)
	player.net_worth = TradeRules.net_worth(player, _state)
	player_changed.emit(player_id)


func pay_loan(player_id: StringName, amount: int) -> void:
	var player: PlayerState = _state.player_by_id(player_id)
	if player == null:
		action_rejected.emit(player_id, "Unknown player.")
		return

	var reason: String = LoanRules.validate_payment(player, amount)
	if not reason.is_empty():
		action_rejected.emit(player_id, reason)
		return

	LoanRules.apply_payment(player, amount)
	player.net_worth = TradeRules.net_worth(player, _state)
	player_changed.emit(player_id)


## Marks a player ready. Once every player is ready the year advances.
##
## The loan payment prompt is deliberately advisory: a player with an unpaid loan
## may still ready up and take the penalty. The game must never withhold a choice
## from them — see docs/game-rules.md §9.5.
func set_ready(player_id: StringName, is_ready: bool) -> void:
	if _state.is_over:
		action_rejected.emit(player_id, "The game is over.")
		return

	var player: PlayerState = _state.player_by_id(player_id)
	if player == null:
		action_rejected.emit(player_id, "Unknown player.")
		return

	player.is_ready = is_ready
	ready_state_changed.emit(player_id, is_ready)

	if _state.all_players_ready():
		_advance()


func _advance() -> void:
	var result: YearResult = _resolver.advance_year(_state, _rng)
	year_resolved.emit(result)
	if result.is_final_year:
		game_over.emit(result.winners)
