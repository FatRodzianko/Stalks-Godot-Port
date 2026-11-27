class_name WhisperRound
extends RefCounted
## The whispers heard at the end of one year, about the next
## (docs/stalkleheads-design.md §8.4, decisions.md D205). Chosen by
## `NewsSelector.whispers_for`; pure data, read by the screens.
##
## The first round is heard at the end of year 1, about year 2: trading opens
## in year 1, so there is nothing to act on before it (decisions.md D207). The
## last year has no round: there is no next year to whisper about.
##
## **Never sent.** Every peer works it out from the history and the kept draws
## it already holds, and caches it on `EarningsMarket.whisper_rounds`.


## One whisper as heard. A squeeze or crash whisper foretells an event, not
## an outcome band, so `said` and `truth` mean nothing for it; whether it came
## true is `NewsSelector.squeeze_whisper_came_true` (D214).
class Line:
	extends RefCounted
	var id: StringName = &""
	## The company or industry it names.
	var subject: StringName = &""
	var about: NewsBands.Subject = NewsBands.Subject.COMPANY
	var source: WhisperRules.Source = WhisperRules.Source.GOSSIP
	## The outcome it tells.
	var said: NewsBands.Surprise = NewsBands.Surprise.AS_EXPECTED
	## The outcome that really comes. **Not for the screen until the year it is
	## about has been played** (`is_settled`): before that it is next year's
	## earnings, which no player may see.
	var truth: NewsBands.Surprise = NewsBands.Surprise.AS_EXPECTED
	var text: String = ""

	## True for a squeeze or crash whisper (D214).
	func is_about_squeeze() -> bool:
		return about == NewsBands.Subject.SQUEEZE or about == NewsBands.Subject.CRASH


## The year whose end it was heard at; 1 or more.
var year: int = 0

## In the order they were drawn. May be empty.
var lines: Array[Line] = []

## Every line drawn, by id: what later rounds' bags count.
var drawn: Array[StringName] = []


## The year these whispers are about.
func about_year() -> int:
	return year + 1


## True once the year it is about has been played, so its outcomes may be shown.
func is_settled(state: GameState) -> bool:
	return state != null and state.year >= about_year()


## The whispers naming `subject`: a company, or an industry.
func lines_about(subject: StringName) -> Array[Line]:
	var found: Array[Line] = []
	for line: Line in lines:
		if line.subject == subject:
			found.append(line)
	return found


## Every whisper as text, for tests comparing two peers.
func all_lines() -> PackedStringArray:
	var out: PackedStringArray = []
	for line: Line in lines:
		out.append("%d %s %s %d %d %d=%s" % [
			year, line.id, line.subject, line.source, line.said, line.truth, line.text,
		])
	return out
