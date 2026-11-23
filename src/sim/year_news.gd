class_name YearNews
extends RefCounted
## The news lines `NewsSelector` chose for one StalkleHeads year, with their
## `{...}` tokens already filled in. Pure data, read by the screens.
##
## **Every slot may be empty**, and an empty slot shows nothing
## (docs/stalkleheads-design.md §8.2 rule 3): no generic line stands in for a
## line nobody has written.
##
## **Never sent.** Every peer works this out for itself from the match's
## history, which it already holds (decisions.md D200), and keeps it on the
## year's `EarningsYearResult.news`.


var year: int = 0

## The market headline, or empty.
var headline: String = ""

## Industry reports by industry id. An industry with none has no key.
var industry_reports: Dictionary[StringName, String] = {}

## Earnings commentary by company id. A company with none has no key.
var commentary: Dictionary[StringName, String] = {}

## Chatter by NPC trader id. A trader with none has no key.
var chatter: Dictionary[StringName, String] = {}

## Every line drawn this year, by id: what the next years' bags count.
var drawn: Array[StringName] = []


## Every chosen line, as text: headline, reports, commentary, chatter, each
## group in id order. For tests comparing two peers.
func all_lines() -> PackedStringArray:
	var lines: PackedStringArray = ["headline=%s" % headline]
	for key: StringName in _sorted(industry_reports.keys()):
		lines.append("report %s=%s" % [key, industry_reports[key]])
	for key: StringName in _sorted(commentary.keys()):
		lines.append("earnings %s=%s" % [key, commentary[key]])
	for key: StringName in _sorted(chatter.keys()):
		lines.append("chatter %s=%s" % [key, chatter[key]])
	return lines


static func _sorted(keys: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in keys:
		out.append(key as StringName)
	out.sort_custom(_by_text)
	return out


static func _by_text(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)
