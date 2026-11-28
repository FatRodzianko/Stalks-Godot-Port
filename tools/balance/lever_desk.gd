extends NpcDesk
## The game's NPC desk, `NpcDesk`, with the balance tool's SHORT-target lever
## applied through its one seam, `choose_target`. For the balance tool only;
## nothing in the game may use it (decisions.md D150, D168, D169).
##
## Two SHORT targets:
##
## - `highpe`, the published rule since D169: the highest P/E, positive
##   earnings only, ties to the lowest id. With this the desk is exactly the
##   game's.
## - `slowest`, the rule S4 first shipped (D164): the company whose profit grew
##   slowest last season, from a positive base, ties to the lowest id.
##
## Also the flag threshold (`flag_at`), through `flagged_companies`.
##
## Every other strategy, the draws and the trading are the real desk's.


const SHORT_HIGHPE: StringName = &"highpe"
const SHORT_SLOWEST: StringName = &"slowest"
const SHORT_TARGETS: Array[StringName] = [SHORT_HIGHPE, SHORT_SLOWEST]

var short_target: StringName = SHORT_HIGHPE

## The flag threshold in percent of shares outstanding; -1 = the published
## `ShortInterestRules.FLAG_AT_PERCENT` (decisions.md D232).
var flag_at: float = -1.0


## As `NpcDesk.flagged_companies`, at this desk's threshold.
func flagged_companies(state: GameState) -> Array[StringName]:
	if flag_at < 0.0:
		return super(state)
	var scored: Array[Array] = []
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt or company.in_squeeze():
			continue
		var interest: int = short_interest(company.id)
		var percent: float = ShortInterestRules.percent_of(interest, company.shares_outstanding)
		if interest > 0 and percent >= flag_at:
			scored.append([-percent, company.id])
	scored.sort_custom(_score_then_id)
	var flagged: Array[StringName] = []
	for entry: Array in scored:
		flagged.append(entry[1])
	return flagged


func choose_target(strategy: NpcStrategy.Value, state: GameState, pick: int) -> StringName:
	if strategy != NpcStrategy.Value.SHORT or short_target == SHORT_HIGHPE:
		return super(strategy, state, pick)
	var worst: StringName = &""
	var worst_growth: float = 0.0
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt or row.price <= 0:
			continue
		var growth: float = company.profit_growth_percent()
		if is_nan(growth):
			continue
		# Companies are in id order, so strictly less keeps ties at the lowest id.
		if worst == &"" or growth < worst_growth:
			worst = company.id
			worst_growth = growth
	return worst
