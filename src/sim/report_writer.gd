class_name ReportWriter
extends RefCounted
## Writes the two automated StalkleHeads reports from the numbers alone
## (decisions.md D215): the Company tab's EARNINGS report and the Industries
## tab's INDUSTRY REPORT. Nobody authors these lines: each is a plain statement
## of facts every player could work out, so there is no content file and
## nothing to fill in.
##
## - EARNINGS: "Mafia HUD Scam's revenue fell 14%, far worse than expected.
##   The company is in distress."
## - INDUSTRY REPORT: "Energy fell again, worse than expected. Expected to rise
##   next year."
##
## Past tense, so the verb reads the same after a singular name ("Energy") and
## a plural one ("Consumer Goods").
##
## The hand-written news (the market news, FROM THE HEADLINES, IN THE NEWS,
## whispers, chatter) is separate; these are only the reports.


const _VERBS: Dictionary[NewsBands.Move, String] = {
	NewsBands.Move.CRASH: "crashed",
	NewsBands.Move.DOWN: "fell",
	NewsBands.Move.FLAT: "held steady",
	NewsBands.Move.UP: "rose",
	NewsBands.Move.SURGE: "surged",
}

const _OUTLOOK_VERBS: Dictionary[NewsBands.Move, String] = {
	NewsBands.Move.CRASH: "crash",
	NewsBands.Move.DOWN: "fall",
	NewsBands.Move.FLAT: "hold steady",
	NewsBands.Move.UP: "rise",
	NewsBands.Move.SURGE: "surge",
}

const _SURPRISES: Dictionary[NewsBands.Surprise, String] = {
	NewsBands.Surprise.MUCH_WORSE: "far worse than expected",
	NewsBands.Surprise.WORSE: "worse than expected",
	NewsBands.Surprise.AS_EXPECTED: "as expected",
	NewsBands.Surprise.BETTER: "better than expected",
	NewsBands.Surprise.MUCH_BETTER: "far better than expected",
}


## What each earnings regime means, as the EARNINGS report's second sentence.
const _REGIMES: Dictionary[EarningsRegime.Value, String] = {
	EarningsRegime.Value.GROWTH: "The company is growing.",
	EarningsRegime.Value.STEADY: "The company is steady.",
	EarningsRegime.Value.SLOWING: "Growth is slowing.",
	EarningsRegime.Value.DECLINE: "The company is in decline.",
	EarningsRegime.Value.DISTRESS: "The company is in distress.",
}


## A company's EARNINGS report: its revenue growth this year, rounded to a
## whole percent, how that compared with what its regime led one to expect,
## and the regime in plain words.
static func earnings_sentence(
	company_name: String,
	growth_percent: float,
	surprise: NewsBands.Surprise,
	regime: EarningsRegime.Value,
) -> String:
	var change: int = roundi(growth_percent)
	var moved: String = "held steady"
	if change > 0:
		moved = "rose %d%%" % change
	elif change < 0:
		moved = "fell %d%%" % -change
	return "%s revenue %s, %s. %s" % [possessive(company_name), moved, _SURPRISES[surprise], _REGIMES[regime]]


## "Mafia HUD Scam's", "Easy Breezy Airways'".
static func possessive(name: String) -> String:
	if name.ends_with("s"):
		return name + "'"
	return name + "'s"


## How the industry's year went: its move, "again" when last year went the same
## way, and how it compared with what was expected. `last_move` is ANY when
## there was no last year.
static func year_sentence(
	industry_name: String,
	move: NewsBands.Move,
	surprise: NewsBands.Surprise,
	last_move: NewsBands.Move,
) -> String:
	var again: String = ""
	if _direction(last_move) == _direction(move) and last_move != NewsBands.Move.ANY:
		again = " again"
	return "%s %s%s, %s." % [industry_name, _VERBS[move], again, _SURPRISES[surprise]]


## What is expected of the industry next year.
static func outlook_sentence(outlook: NewsBands.Move) -> String:
	return "Expected to %s next year." % _OUTLOOK_VERBS[outlook]


## -1 for a fall, 0 for flat, 1 for a rise: CRASH and DOWN count as the same way.
static func _direction(move: NewsBands.Move) -> int:
	match move:
		NewsBands.Move.CRASH, NewsBands.Move.DOWN:
			return -1
		NewsBands.Move.UP, NewsBands.Move.SURGE:
			return 1
	return 0
