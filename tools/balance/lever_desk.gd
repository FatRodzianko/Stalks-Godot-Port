extends NpcDesk
## The game's NPC desk, `NpcDesk`, with the balance tool's SHORT-target lever
## applied through its one seam, `choose_target`. For the balance tool only;
## nothing in the game may use it (decisions.md D150, D168).
##
## Two SHORT targets:
##
## - `slowest`, the published rule (D164): the company whose profit grew slowest
##   last season. With this the desk is exactly the game's.
## - `highpe`: the highest P/E (price over earnings per share), positive
##   earnings only, ties to the lowest id. What the balance tool's HIGHPE holds,
##   and close to the probe's rule (design Appendix A), which broke ties the
##   other way.
##
## Every other strategy, the draws and the trading are the real desk's.


const SHORT_SLOWEST: StringName = &"slowest"
const SHORT_HIGHPE: StringName = &"highpe"
const SHORT_TARGETS: Array[StringName] = [SHORT_SLOWEST, SHORT_HIGHPE]

var short_target: StringName = SHORT_SLOWEST

func choose_target(strategy: NpcStrategy.Value, state: GameState, pick: int) -> StringName:
	if strategy != NpcStrategy.Value.SHORT or short_target == SHORT_SLOWEST:
		return super(strategy, state, pick)
	var best: StringName = &""
	var best_pe: float = 0.0
	for company: CompanyState in state.market.companies:
		var row: StalkState = state.stalk_by_id(company.id)
		if row == null or row.is_bankrupt or row.price <= 0:
			continue
		var eps: float = company.earnings_per_share()
		if eps <= 0.0:
			continue
		var pe: float = float(company.price) / eps
		# Companies are in id order, so strictly greater keeps ties at the lowest id.
		if best == &"" or pe > best_pe:
			best = company.id
			best_pe = pe
	return best
