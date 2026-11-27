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

## Each industry's headline, FROM THE HEADLINES on the Industries tab, by
## industry id. An industry with none has no key. (Called industry reports
## before D212 gave that name to the report below.)
var industry_reports: Dictionary[StringName, String] = {}

## The first sentence of each industry's INDUSTRY REPORT: its year against what
## was expected (D212), written by `ReportWriter` (D215). By industry id.
var industry_years: Dictionary[StringName, String] = {}

## The second sentence: what is expected of it next year. By industry id.
var industry_outlooks: Dictionary[StringName, String] = {}

## How each company's revenue growth compared with what its regime led one to
## expect, by company id: what the Company tab's EARNINGS line says (D211).
## Every company that had an earnings season has one.
var earnings_surprise: Dictionary[StringName, NewsBands.Surprise] = {}

## Each company's EARNINGS report, written by `ReportWriter` (D215), by company
## id. Every company that had an earnings season has one.
var earnings: Dictionary[StringName, String] = {}

## IN THE NEWS, by company id (D211).
var company_news: Dictionary[StringName, String] = {}

## Chatter by NPC trader id. A trader with none has no key.
var chatter: Dictionary[StringName, String] = {}

## Every line drawn this year, by id: what the next years' bags count.
var drawn: Array[StringName] = []


## The INDUSTRY REPORT for an industry: its two sentences, or as many as were
## chosen, joined by a space. Empty when neither was.
func industry_report(industry_id: StringName) -> String:
	var parts: PackedStringArray = []
	if industry_years.has(industry_id):
		parts.append(industry_years[industry_id])
	if industry_outlooks.has(industry_id):
		parts.append(industry_outlooks[industry_id])
	return " ".join(parts)


## Every chosen line, as text: headlines, reports, earnings, company news,
## chatter, each group in id order. For tests comparing two peers.
func all_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	for key: StringName in _sorted(industry_reports.keys()):
		lines.append("headline %s=%s" % [key, industry_reports[key]])
	for key: StringName in _sorted(industry_years.keys()):
		lines.append("report %s=%s" % [key, industry_years[key]])
	for key: StringName in _sorted(industry_outlooks.keys()):
		lines.append("outlook %s=%s" % [key, industry_outlooks[key]])
	for key: StringName in _sorted(earnings.keys()):
		lines.append("earnings %s=%s" % [key, earnings[key]])
	for key: StringName in _sorted(company_news.keys()):
		lines.append("news %s=%s" % [key, company_news[key]])
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
