extends EarningsYearResolver
## The real StalkleHeads year, `EarningsYearResolver`, with the balance tool's
## levers applied through its two seams. For the balance tool only; nothing in
## the game may use it (decisions.md D144, D150).
##
## Replaced S2's `stand_in_year.gd` in S3 (decisions.md D161). Everything the
## year does - industries, earnings, the market news, the
## identity, the index, the derived mood, bankruptcy, splits, dividends, the
## settlement - is the game's own code. This file changes only:
##
## - **the regime roll**, when a regime lever is set: one roll, drawn here, then
##   the growth roll from that regime's band. Same two draws as the real path,
##   made a year early like it (decisions.md D205);
## - **the industry performance a company is valued on**, when the premium lever
##   is set, shifted so the multiple comes out as if the premium table had the
##   override (`Levers.valuation_performance`);
## - **the squeeze chance**, when that lever is set, still 0 in a year with
##   nothing flagged; and **the squeeze's size**, its lift per point of short
##   interest (D213). Its on/off switch is whether a template is passed.
##
## With every lever at its default both seams call straight through, and
## `test_balance_smoke.gd` checks the override path reproduces that exactly.


const Levers := preload("res://tools/balance/levers.gd")

var levers: Levers


func _init(
	overrides: Levers = null,
	short_squeeze: SpecialEventDefinition = null,
) -> void:
	super(short_squeeze)
	levers = overrides
	if levers == null:
		levers = Levers.new()


func draw_company_earnings(
	market: EarningsMarket,
	company: CompanyState,
	match_years: int,
	rng: RandomNumberGenerator,
) -> Vector2i:
	if not levers.changes_regimes():
		return super(market, company, match_years, rng)
	var roll: int = rng.randi_range(1, 100)
	var next: EarningsRegime.Value = levers.regime_for_roll(
		company.regime, roll, company.profile.quality, company.years_in_regime
	)
	var band: Vector2i = RegimeRules.GROWTH_BAND[next]
	return Vector2i(int(next), rng.randi_range(band.x, band.y))


func squeeze_chance_percent(any_flagged: bool) -> int:
	if levers.squeeze_chance < 0 or not any_flagged:
		return super(any_flagged)
	return levers.squeeze_chance


func valuation_performance(market: EarningsMarket, company: CompanyState) -> float:
	return levers.valuation_performance(company.regime, market.performance_of(company))


## The squeeze's lift, at the lever's percent per point of short interest when
## it is set, capped as the rule caps it.
func squeeze_spike(price: int, short_percent: float) -> int:
	if levers.squeeze_size < 0:
		return super(price, short_percent)
	if price <= 0 or short_percent <= 0.0:
		return 0
	var lift: float = minf(ShortInterestRules.SPIKE_MAX_PERCENT, short_percent * float(levers.squeeze_size))
	return int(float(price) * lift / 100.0)
