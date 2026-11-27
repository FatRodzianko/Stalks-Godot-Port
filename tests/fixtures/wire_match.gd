class_name WireMatch
extends RefCounted
## A seeded StalkleHeads match with scripted players, and a way to write down
## everything a match or a year holds as lines of text, so two copies can be
## compared field by field. Used by test_wire.gd and tools/wire_report.gd.
##
## **Why lines of text.** "The replica equals the host" is only worth asserting
## if a failure says *which* number differs. Each line names its field, and
## every `float` is written as its 64 bits in hex, so two numbers that print
## alike but differ in the last bit do not compare equal.
##
## The players trade on a fixed script that buys something every year, sells
## out now and then, and borrows, so flow, loans, splits and bankruptcies all
## happen. Not a strategy; a way of making the match do things.


var authority: MatchAuthority
var library: ContentLibrary


## A fresh match at year 0. `players` seats p0, p1 and so on.
static func start(seed_value: int, players: int = 3, max_years: int = 99) -> WireMatch:
	var match_: WireMatch = WireMatch.new()
	var settings: GameSettings = GameSettings.new()
	settings.mode = GameMode.Value.STALKLEHEADS
	settings.rng_seed = seed_value
	settings.max_years = max_years
	settings.loans_enabled = true
	match_.library = MatchSetup.load_library(settings.mode)
	var names: Array[String] = []
	for index: int in players:
		names.append("Player %d" % index)
	match_.authority = LocalSession.build_authority(settings, match_.library, names)
	return match_


var state: GameState:
	get:
		return authority.state


## This year's scripted trades, against `on`: this match's own authority, or
## another one playing the same match (a promoted host).
static func trade(on: MatchAuthority) -> void:
	var played: GameState = on.state
	var year: int = played.year
	for index: int in played.players.size():
		var player: PlayerState = played.players[index]
		var row: StalkState = played.stalks[(year * 3 + index * 7) % played.stalks.size()]
		if row.has_value():
			on.buy(player.id, row.id, 1 + (year % 5) * (index + 1))
		if year % 4 == index:
			for held: StringName in player.holdings.keys():
				on.sell(player.id, held, player.shares_of(held))
		if index == 2 and player.loan == null and year % 7 == 2:
			on.take_loan(player.id, 1000)
		if index == 2 and player.loan != null and year % 3 == 0:
			on.pay_loan(player.id, mini(player.cash, 150))


## Trades, readies everybody and advances one year.
static func play_year(on: MatchAuthority) -> EarningsYearResult:
	trade(on)
	for player: PlayerState in on.state.players:
		on.set_ready(player.id, true)
	var result: EarningsYearResult = on.advance_year()
	for player: PlayerState in on.state.players:
		on.set_ready(player.id, false)
	return result


func play(years: int) -> void:
	for _year: int in years:
		if state.is_over:
			return
		play_year(authority)


# --------------------------------------------------------------- the lines

static func bits(value: float) -> String:
	return PackedFloat64Array([value]).to_byte_array().hex_encode()


## Every field of the market, the board and the players. `with_presence` adds
## each player's ready and away flags, which a host taking a match over resets
## on purpose and so must sometimes be left out of a comparison.
static func state_lines(played: GameState, with_presence: bool = true) -> PackedStringArray:
	var lines: PackedStringArray = ["year %d over %s" % [played.year, played.is_over]]
	for row: StalkState in played.stalks:
		lines.append("row %s price %d change %d bankrupt %s split %s" % [
			row.id, row.price, row.last_yearly_change, row.is_bankrupt, row.did_split,
		])
	for player: PlayerState in played.players:
		var line: String = "player %s cash %d worth %d bankrupt %s holdings %s loan %s" % [
			player.id, player.cash, player.net_worth, player.is_bankrupt,
			_sorted(player.holdings), _loan(player.loan),
		]
		if with_presence:
			line += " ready %s away %s" % [player.is_ready, player.is_away]
		lines.append(line)
	lines.append_array(market_lines(played.market))
	return lines


static func market_lines(market: EarningsMarket) -> PackedStringArray:
	var lines: PackedStringArray = []
	if market == null:
		lines.append("no market")
		return lines
	lines.append("market sentiment %s used %s index %s mood %d key %d" % [
		bits(market.sentiment), bits(market.sentiment_used), bits(market.index_level),
		market.last_mood, market.content_key,
	])
	lines.append("market flow in %s" % _sorted(market.net_shares_traded))
	for company: CompanyState in market.companies:
		lines.append_array(company_lines(company))
	for industry: IndustryState in market.industries:
		lines.append("industry %s performance %s roll %d" % [
			industry.id, bits(industry.performance), industry.roll,
		])
	for trader: NpcTraderState in market.desk.traders:
		lines.append("trader %s cash %d holdings %s shorts %s" % [
			trader.id, trader.cash, _sorted(trader.holdings), _sorted(trader.shorts),
		])
	if market.next_draws == null:
		lines.append("next draws none")
	else:
		lines.append("next draws industries %s regimes %s rolls %s" % [
			_sorted(market.next_draws.industry_rolls),
			_sorted(market.next_draws.regimes),
			_sorted(market.next_draws.growth_rolls),
		])
	return lines


## One line per field, so a failure names it.
static func company_lines(company: CompanyState) -> PackedStringArray:
	var id: String = String(company.id)
	var fields: Dictionary = {
		"revenue": bits(company.revenue),
		"margin": bits(company.margin_percent),
		"profit": bits(company.profit),
		"profit_before_season": bits(company.profit_before_season),
		"shares": company.shares_outstanding,
		"revenue_growth": bits(company.revenue_growth_percent),
		"growth_roll": company.growth_roll,
		"regime": company.regime,
		"years_in_regime": company.years_in_regime,
		"sentiment": bits(company.sentiment),
		"industry_standing": bits(company.industry_standing),
		"regime_premium": bits(company.regime_premium),
		"multiple": bits(company.multiple),
		"fair_value": bits(company.fair_value),
		"valuation_clamped": company.valuation_clamped,
		"event_carry": bits(company.event_carry),
		"event_delta": company.event_delta,
		"flow": bits(company.flow),
		"price": company.price,
		"did_split": company.did_split,
		"squeeze_premium": company.squeeze_premium,
		"squeeze_remaining_percent": company.squeeze_remaining_percent,
	}
	var lines: PackedStringArray = []
	for field: String in fields:
		lines.append("company %s %s %s" % [id, field, fields[field]])
	return lines


## Everything a year result says, the base game's part and this mode's.
static func result_lines(result: YearResult) -> PackedStringArray:
	var lines: PackedStringArray = ["result year %d mood %d final %s" % [
		result.year, result.mood, result.is_final_year,
	]]
	if result.event != null:
		lines.append("result event %s on %s by %d: %s" % [
			result.event.id, result.event.target_stalk_id, result.event.price_change,
			result.event.flavour_text,
		])
	for change: StalkYearChange in result.stalk_changes:
		lines.append("result change %s %d %+d %+d -> %d split %s bankrupt %s" % [
			change.stalk_id, change.price_before, change.base_delta, change.event_delta,
			change.price_after, change.did_split, change.went_bankrupt,
		])
	for change: LoanYearChange in result.loan_changes:
		lines.append("result loan %s %d paid %s missed %d +%d +%d -> %d min %d default %s" % [
			change.player_id, change.balance_before, change.paid_during_year,
			change.missed_payments, change.penalty_added, change.interest_added,
			change.balance_after, change.min_payment_after, change.defaulted,
		])
	lines.append("result dividends %s worths %s" % [_sorted(result.dividends), _sorted(result.net_worths)])
	lines.append("result rankings %s winners %s" % [result.rankings, result.winners])
	if not result is EarningsYearResult:
		return lines

	var earnings: EarningsYearResult = result
	lines.append("result index %s sentiment %s bag %d" % [
		bits(earnings.index_move_percent), bits(earnings.sentiment_used), earnings.event_bag,
	])
	lines.append("result squeeze %d end %d drift %d cover %d %s spike %d flagged %s moves %s drifts %s" % [
		earnings.squeeze_roll, earnings.squeeze_end_roll, earnings.squeeze_drift_roll, earnings.squeeze_cover_roll,
		earnings.squeezed, earnings.squeeze_spike,
		earnings.short_interest_flagged, _sorted(earnings.squeeze_moves), _sorted(earnings.squeeze_drift_moves),
	])
	var news_id: String = "none"
	if earnings.market_news != null:
		news_id = String(earnings.market_news.id)
	lines.append("result market news %s" % news_id)
	lines.append("result per share %s" % _sorted(earnings.dividend_per_share))
	lines.append("result inputs rolls %s regimes %s growth %s priced %s" % [
		_sorted(earnings.industry_rolls), _sorted(earnings.regimes),
		_sorted(earnings.growth_rolls), _sorted(earnings.net_shares_priced),
	])
	for industry_id: StringName in _keys(earnings.industry_performance):
		lines.append("result industry %s %s" % [industry_id, bits(earnings.industry_performance[industry_id])])
	for company_id: StringName in _keys(earnings.ledgers):
		lines.append("result ledger %s %s" % [company_id, earnings.ledgers[company_id]])
	lines.append("result index level %s" % bits(earnings.index_level_after))
	for company_id: StringName in _keys(earnings.companies_after):
		for line: String in company_lines(earnings.companies_after[company_id]):
			lines.append("result after %s" % line)
	if earnings.desk != null:
		lines.append("result desk %s appetites %s targets %s actions %s net %s" % [
			earnings.desk.trader_ids, _sorted(earnings.desk.appetites),
			_sorted(earnings.desk.targets), _sorted(earnings.desk.actions),
			_sorted(earnings.desk.net_shares),
		])
	return lines


## The first line where two records part, with its neighbour, or "" if they do
## not. What a failing assertion prints.
static func first_difference(expected: PackedStringArray, actual: PackedStringArray) -> String:
	for index: int in maxi(expected.size(), actual.size()):
		var want: String = expected[index] if index < expected.size() else "<nothing>"
		var got: String = actual[index] if index < actual.size() else "<nothing>"
		if want != got:
			return "line %d\n  host:    %s\n  replica: %s" % [index, want, got]
	return ""


static func _sorted(source: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: Variant in _keys(source):
		parts.append("%s=%s" % [key, source[key]])
	return "{%s}" % ", ".join(parts)


static func _keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort_custom(_by_text)
	return keys


static func _by_text(a: Variant, b: Variant) -> bool:
	return str(a) < str(b)


static func _loan(loan: LoanState) -> String:
	if loan == null:
		return "none"
	return "%d/%d/%d/%d/%s/%s/%s" % [
		loan.balance, loan.min_payment, loan.years_remaining, loan.missed_payments,
		loan.paid_this_year, loan.is_paid_off, loan.is_defaulted,
	]
