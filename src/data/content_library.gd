class_name ContentLibrary
extends RefCounted
## Loads the authored stalk content from disk and validates it.
##
## Content is authored as one `.tres` per stalk in `src/data/stalks/`, each
## carrying its own special events (see docs/decisions.md D29). This class turns
## that directory into something the simulation can use, and refuses to hand back
## content it cannot vouch for.
##
## Validation exists because the content is the easiest part of the project to get
## quietly wrong: ninety events referencing ten stalks by id, where a single typo
## in a target id would silently produce an event that can never fire. The
## original had exactly that class of bug.


const STALKS_DIR: String = "res://src/data/stalks"

## StalkleHeads content (docs/stalkleheads-design.md §3.2). Not loaded by
## `load_from`, so the base game never reads it; `load_fundamentals` adds it.
const COMPANIES_DIR: String = "res://src/data/companies"
const INDUSTRIES_DIR: String = "res://src/data/industries"
const TRADERS_DIR: String = "res://src/data/traders"

## The short-squeeze template (docs/stalkleheads-design.md §5.3): one event whose
## target is filled in at the moment a squeeze fires. Not in `STALKS_DIR`, so the
## base game's event pool never sees it.
const SHORT_SQUEEZE_PATH: String = "res://src/data/squeeze/short_squeeze.tres"

## An industry with fewer members than this is refused: an industry of one is
## indistinguishable from the company in it (§3.2.3).
const MIN_INDUSTRY_MEMBERS: int = 2

## An industry with fewer members than this is reported but allowed: three is
## what survives one bankruptcy without falling below the floor (§3.2.3).
const TARGET_INDUSTRY_MEMBERS: int = 3

## Loaded stalk definitions, sorted by id so the order is identical on every
## machine. Directory listing order is not guaranteed, and determinism matters
## here (docs/architecture.md §8). Display order on the board is a separate
## concern for the UI phase.
var stalks: Array[StalkDefinition] = []

## StalkleHeads company profiles, sorted by id. Empty unless
## `load_fundamentals` ran.
var companies: Array[CompanyProfile] = []

## StalkleHeads industries, sorted by id. Empty unless `load_fundamentals` ran.
var industries: Array[IndustryDefinition] = []

## StalkleHeads NPC traders, sorted by id. Empty unless `load_fundamentals` ran.
var traders: Array[NpcTraderDefinition] = []

## The StalkleHeads short-squeeze template, or null unless `load_fundamentals`
## ran. Its `target_stalk_id` is empty: the squeeze names its own target.
var short_squeeze: SpecialEventDefinition = null

## Problems found by `validate()`. Empty means the content is usable.
var errors: Array[String] = []

## What `validate()` reports without refusing the content - today only an
## industry below its target of three members. Does not affect `is_valid()`.
var warnings: Array[String] = []


## Loads and validates every stalk resource in `dir_path`.
##
## Always returns a library; check `is_valid()` before using it. Loading never
## pushes an error or crashes, so a caller can report problems its own way.
static func load_from(dir_path: String = STALKS_DIR) -> ContentLibrary:
	var library: ContentLibrary = ContentLibrary.new()

	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		library.errors.append("Cannot open content directory: %s" % dir_path)
		return library

	var file_names: PackedStringArray = dir.get_files()
	var loaded_names: Array[String] = []
	for file_name: String in file_names:
		# Exported projects rename .tres to .res, so accept both.
		var usable: String = file_name.trim_suffix(".remap")
		if not (usable.ends_with(".tres") or usable.ends_with(".res")):
			continue
		loaded_names.append(usable)

	loaded_names.sort()
	for usable: String in loaded_names:
		var path: String = "%s/%s" % [dir_path, usable]
		var resource: Resource = load(path)
		if resource == null:
			library.errors.append("Failed to load %s" % path)
			continue
		var definition: StalkDefinition = resource as StalkDefinition
		if definition == null:
			library.errors.append(
				"%s is not a StalkDefinition (got %s)" % [path, resource.get_class()]
			)
			continue
		library.stalks.append(definition)

	library.stalks.sort_custom(_by_id)
	library.validate()
	return library


## Adds the StalkleHeads company profiles, industries, NPC traders and the
## short-squeeze template, then re-validates everything. Problems loading a file
## land in `errors`, as in `load_from`.
func load_fundamentals(
	companies_dir: String = COMPANIES_DIR,
	industries_dir: String = INDUSTRIES_DIR,
	traders_dir: String = TRADERS_DIR,
	short_squeeze_path: String = SHORT_SQUEEZE_PATH,
) -> void:
	var load_errors: Array[String] = []
	companies = []
	for resource: Resource in _load_all(companies_dir, load_errors):
		var profile: CompanyProfile = resource as CompanyProfile
		if profile == null:
			load_errors.append("%s is not a CompanyProfile" % resource.resource_path)
			continue
		companies.append(profile)
	industries = []
	for resource: Resource in _load_all(industries_dir, load_errors):
		var industry: IndustryDefinition = resource as IndustryDefinition
		if industry == null:
			load_errors.append("%s is not an IndustryDefinition" % resource.resource_path)
			continue
		industries.append(industry)
	traders = []
	for resource: Resource in _load_all(traders_dir, load_errors):
		var trader: NpcTraderDefinition = resource as NpcTraderDefinition
		if trader == null:
			load_errors.append("%s is not an NpcTraderDefinition" % resource.resource_path)
			continue
		traders.append(trader)
	short_squeeze = null
	if ResourceLoader.exists(short_squeeze_path):
		short_squeeze = load(short_squeeze_path) as SpecialEventDefinition
	if short_squeeze == null:
		load_errors.append("No short-squeeze event at %s" % short_squeeze_path)

	companies.sort_custom(_company_by_id)
	industries.sort_custom(_industry_by_id)
	traders.sort_custom(_trader_by_id)
	validate()
	errors.append_array(load_errors)


func is_valid() -> bool:
	return errors.is_empty()


## Re-runs validation, replacing `errors`. Returns the error list.
##
## Collects every problem rather than stopping at the first, so one run reports
## everything an author needs to fix.
func validate() -> Array[String]:
	errors = []
	warnings = []
	_validate_fundamentals()

	if stalks.is_empty():
		errors.append("No stalks were loaded.")
		return errors

	var seen_stalk_ids: Dictionary[StringName, bool] = {}
	var seen_event_ids: Dictionary[StringName, bool] = {}

	for stalk: StalkDefinition in stalks:
		var label: String = str(stalk.id) if stalk.id != &"" else "<missing id>"

		if stalk.id == &"":
			errors.append("A stalk has no id (display name %s)." % stalk.display_name)
		elif seen_stalk_ids.has(stalk.id):
			errors.append("Duplicate stalk id: %s" % label)
		else:
			seen_stalk_ids[stalk.id] = true

		if stalk.display_name.is_empty():
			errors.append("Stalk %s has no display name." % label)
		if stalk.starting_price <= 0:
			errors.append("Stalk %s has a starting price of %d." % [label, stalk.starting_price])

		_validate_range(stalk, label, stalk.bear_change, "bear_change")
		_validate_range(stalk, label, stalk.bull_change, "bull_change")

		if stalk.is_price_static and not stalk.all_events().is_empty():
			errors.append(
				"Stalk %s is static-price but carries %d events, which can never fire."
				% [label, stalk.all_events().size()]
			)

		_validate_events(stalk, label, stalk.bull_events, MarketMood.Value.BULL, seen_event_ids)
		_validate_events(stalk, label, stalk.bear_events, MarketMood.Value.BEAR, seen_event_ids)

	return errors


func _validate_range(
	_stalk: StalkDefinition,
	label: String,
	bounds: Vector2i,
	field: String,
) -> void:
	if bounds.x < 0 or bounds.y < 0:
		errors.append("Stalk %s has a negative %s %s; magnitudes are stored positive."
			% [label, field, str(bounds)])
	if bounds.x > bounds.y:
		errors.append("Stalk %s has %s with min above max %s."
			% [label, field, str(bounds)])


func _validate_events(
	stalk: StalkDefinition,
	label: String,
	events: Array[SpecialEventDefinition],
	expected_mood: MarketMood.Value,
	seen_event_ids: Dictionary[StringName, bool],
) -> void:
	for event: SpecialEventDefinition in events:
		if event == null:
			errors.append("Stalk %s has an empty slot in its %s event list."
				% [label, MarketMood.label(expected_mood)])
			continue

		var event_label: String = str(event.id) if event.id != &"" else "<missing id>"

		if event.id == &"":
			errors.append("Stalk %s has an event with no id." % label)
		elif seen_event_ids.has(event.id):
			errors.append("Duplicate event id: %s" % event_label)
		else:
			seen_event_ids[event.id] = true

		# The whole point of validating: an event whose target does not match the
		# stalk it lives on would never fire, silently.
		if event.target_stalk_id != stalk.id:
			errors.append("Event %s lives on stalk %s but targets %s."
				% [event_label, label, str(event.target_stalk_id)])

		if event.mood != expected_mood:
			errors.append("Event %s is in the %s list but is marked %s."
				% [event_label, MarketMood.label(expected_mood), MarketMood.label(event.mood)])

		if event.price_change == 0:
			errors.append("Event %s has a price change of 0 and would do nothing."
				% event_label)

		if event.flavour_text.is_empty():
			errors.append("Event %s has no flavour text." % event_label)


## The StalkleHeads checks (decisions.md D128). Runs only when there is
## StalkleHeads content to check, so base-game validation is unchanged.
##
## The one that matters most is the industry id: `industry` is a `StringName`
## rather than an enum (§3.2.1), so a typo would silently put a company in an
## industry of one. This is where that typo is caught instead.
func _validate_fundamentals() -> void:
	if companies.is_empty() and industries.is_empty():
		return

	var members: Dictionary[StringName, int] = {}
	for industry: IndustryDefinition in industries:
		var label: String = str(industry.id) if industry.id != &"" else "<missing id>"
		if industry.id == &"":
			errors.append("An industry has no id (display name %s)." % industry.display_name)
		elif members.has(industry.id):
			errors.append("Duplicate industry id: %s" % label)
		else:
			members[industry.id] = 0
		if industry.display_name.is_empty():
			errors.append("Industry %s has no display name." % label)

	var seen_ids: Dictionary[StringName, bool] = {}
	var seen_tickers: Dictionary[StringName, bool] = {}
	for company: CompanyProfile in companies:
		_validate_company(company, members, seen_ids, seen_tickers)

	var industry_ids: Array[StringName] = members.keys()
	industry_ids.sort_custom(_string_name_order)
	for industry_id: StringName in industry_ids:
		var count: int = members[industry_id]
		if count < MIN_INDUSTRY_MEMBERS:
			errors.append("Industry %s has %d member(s); an industry needs at least %d."
				% [industry_id, count, MIN_INDUSTRY_MEMBERS])
		elif count < TARGET_INDUSTRY_MEMBERS:
			warnings.append("Industry %s has %d members; the target is %d, so one bankruptcy cannot leave it with one."
				% [industry_id, count, TARGET_INDUSTRY_MEMBERS])

	_validate_traders()
	if short_squeeze != null:
		if short_squeeze.price_change <= 0:
			errors.append("The short squeeze must raise the price; its price_change is %d."
				% short_squeeze.price_change)
		if short_squeeze.target_stalk_id != &"":
			errors.append("The short squeeze names a target (%s); it must leave it empty."
				% short_squeeze.target_stalk_id)


## The NPC desk's content (docs/stalkleheads-design.md §5.1). Duplicate ids
## matter more here than usual: traders act in id order, so two with one id
## would make that order depend on load order.
func _validate_traders() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for trader: NpcTraderDefinition in traders:
		var label: String = str(trader.id) if trader.id != &"" else "<missing id>"
		if trader.id == &"":
			errors.append("A trader has no id (display name %s)." % trader.display_name)
		elif seen.has(trader.id):
			errors.append("Duplicate trader id: %s" % label)
		else:
			seen[trader.id] = true
		if trader.display_name.is_empty():
			errors.append("Trader %s has no display name." % label)
		if trader.strategy not in NpcStrategy.ALL:
			errors.append("Trader %s has an unknown strategy (%d)." % [label, trader.strategy])
		if trader.starting_cash <= 0:
			errors.append("Trader %s starts with %d cash." % [label, trader.starting_cash])
		if trader.conviction < 0 or trader.conviction > 100:
			errors.append("Trader %s has conviction %d; it must be 0-100." % [label, trader.conviction])


func _validate_company(
	company: CompanyProfile,
	members: Dictionary[StringName, int],
	seen_ids: Dictionary[StringName, bool],
	seen_tickers: Dictionary[StringName, bool],
) -> void:
	var label: String = str(company.id) if company.id != &"" else "<missing id>"
	if company.id == &"":
		errors.append("A company has no id (display name %s)." % company.display_name)
	elif seen_ids.has(company.id):
		errors.append("Duplicate company id: %s" % label)
	else:
		seen_ids[company.id] = true

	if company.display_name.is_empty():
		errors.append("Company %s has no display name." % label)
	if company.ticker == &"":
		errors.append("Company %s has no ticker." % label)
	elif seen_tickers.has(company.ticker):
		errors.append("Duplicate ticker %s (company %s)." % [company.ticker, label])
	else:
		seen_tickers[company.ticker] = true

	if members.has(company.industry):
		members[company.industry] += 1
	else:
		errors.append("Company %s names industry %s, which does not exist."
			% [label, str(company.industry)])

	if company.starting_earnings_per_share <= 0.0:
		errors.append("Company %s has starting earnings per share of %s."
			% [label, company.starting_earnings_per_share])
	if company.starting_margin_percent <= 0.0 or company.starting_margin_percent > 100.0:
		errors.append("Company %s has a starting margin of %s; it must be above 0 and at most 100."
			% [label, company.starting_margin_percent])
	if company.shares_outstanding <= 0:
		errors.append("Company %s has %d shares outstanding." % [label, company.shares_outstanding])
	if company.quality < 0 or company.quality > 100:
		errors.append("Company %s has quality %d; it must be 0-100." % [label, company.quality])
	if company.payout_policy_percent < 0 or company.payout_policy_percent > 100:
		errors.append("Company %s has a payout policy of %d; it must be 0-100."
			% [label, company.payout_policy_percent])
	if company.industry_beta_percent < 0:
		errors.append("Company %s has a negative industry beta (%d)."
			% [label, company.industry_beta_percent])


## Every `.tres`/`.res` resource in a directory, in file-name order. Problems go
## into `problems` rather than being pushed, as in `load_from`.
static func _load_all(dir_path: String, problems: Array[String]) -> Array[Resource]:
	var loaded: Array[Resource] = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		problems.append("Cannot open content directory: %s" % dir_path)
		return loaded

	var usable_names: Array[String] = []
	for file_name: String in dir.get_files():
		# Exported projects rename .tres to .res, so accept both.
		var usable: String = file_name.trim_suffix(".remap")
		if usable.ends_with(".tres") or usable.ends_with(".res"):
			usable_names.append(usable)
	usable_names.sort()

	for usable: String in usable_names:
		var path: String = "%s/%s" % [dir_path, usable]
		var resource: Resource = load(path)
		if resource == null:
			problems.append("Failed to load %s" % path)
			continue
		loaded.append(resource)
	return loaded


# ------------------------------------------------------------------- accessors

func company_by_id(company_id: StringName) -> CompanyProfile:
	for company: CompanyProfile in companies:
		if company.id == company_id:
			return company
	return null


func industry_by_id(industry_id: StringName) -> IndustryDefinition:
	for industry: IndustryDefinition in industries:
		if industry.id == industry_id:
			return industry
	return null

func stalk_by_id(stalk_id: StringName) -> StalkDefinition:
	for stalk: StalkDefinition in stalks:
		if stalk.id == stalk_id:
			return stalk
	return null


## One event by id, or null. Needed to rebuild a YearResult on a client: only the
## event's id crosses the wire, and the client reads the flavour text from its own
## copy of the content. See StateSync.
func event_by_id(event_id: StringName) -> SpecialEventDefinition:
	for event: SpecialEventDefinition in all_events():
		if event.id == event_id:
			return event
	return null


func all_events() -> Array[SpecialEventDefinition]:
	var combined: Array[SpecialEventDefinition] = []
	for stalk: StalkDefinition in stalks:
		combined.append_array(stalk.all_events())
	return combined


func events_for_mood(mood: MarketMood.Value) -> Array[SpecialEventDefinition]:
	var selected: Array[SpecialEventDefinition] = []
	for stalk: StalkDefinition in stalks:
		selected.append_array(
			stalk.bull_events if mood == MarketMood.Value.BULL else stalk.bear_events
		)
	return selected


# -------------------------------------------------------------------- factories

## A fresh set of StalkStates for a new match.
func build_stalk_states() -> Array[StalkState]:
	var states: Array[StalkState] = []
	for stalk: StalkDefinition in stalks:
		states.append(StalkState.new(stalk))
	return states


## An EventPool holding every authored event.
func build_event_pool() -> EventPool:
	return EventPool.new(all_events())


static func _by_id(a: StalkDefinition, b: StalkDefinition) -> bool:
	return String(a.id) < String(b.id)


static func _company_by_id(a: CompanyProfile, b: CompanyProfile) -> bool:
	return String(a.id) < String(b.id)


static func _industry_by_id(a: IndustryDefinition, b: IndustryDefinition) -> bool:
	return String(a.id) < String(b.id)


static func _trader_by_id(a: NpcTraderDefinition, b: NpcTraderDefinition) -> bool:
	return String(a.id) < String(b.id)


static func _string_name_order(a: StringName, b: StringName) -> bool:
	return String(a) < String(b)


func _to_string() -> String:
	return "ContentLibrary(%d stalks, %d events, %s)" % [
		stalks.size(),
		all_events().size(),
		"valid" if is_valid() else "%d errors" % errors.size(),
	]
