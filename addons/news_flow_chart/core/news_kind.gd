class_name NewsKind
extends RefCounted
## The five kinds of news item a `NewsBook` holds, and what the News Flow Chart
## needs to know about each: which list of the book it sits in, what to call it,
## and how to make an empty one (docs/news-flow-chart.md §3.2).
##
## Part of the News Flow Chart's `core/`: pure logic with no editor classes, so
## the whole of it is tested headless.


enum Value { MARKET, INDUSTRY, COMPANY, WHISPER, CHATTER }

const ALL: Array[Value] = [Value.MARKET, Value.INDUSTRY, Value.COMPANY, Value.WHISPER, Value.CHATTER]


## The kind of a news item, or -1 for anything that is not one.
static func of(line: Resource) -> int:
	if line is MarketNews:
		return Value.MARKET
	if line is IndustryReport:
		return Value.INDUSTRY
	if line is CompanyNews:
		return Value.COMPANY
	if line is Whisper:
		return Value.WHISPER
	if line is NpcChatter:
		return Value.CHATTER
	return -1


## The `NewsBook` property holding this kind's list.
static func list_name(kind: Value) -> StringName:
	match kind:
		Value.MARKET:
			return &"market_news"
		Value.INDUSTRY:
			return &"industry_reports"
		Value.COMPANY:
			return &"company_news"
		Value.WHISPER:
			return &"whispers"
	return &"chatter"


## What the tool calls this kind.
static func display_name(kind: Value) -> String:
	match kind:
		Value.MARKET:
			return "Market news"
		Value.INDUSTRY:
			return "Industry headline"
		Value.COMPANY:
			return "Company news"
		Value.WHISPER:
			return "Whisper"
	return "Chatter"


## A new, empty news item of this kind, with no id.
static func make(kind: Value) -> Resource:
	match kind:
		Value.MARKET:
			return MarketNews.new()
		Value.INDUSTRY:
			return IndustryReport.new()
		Value.COMPANY:
			return CompanyNews.new()
		Value.WHISPER:
			return Whisper.new()
	return NpcChatter.new()
