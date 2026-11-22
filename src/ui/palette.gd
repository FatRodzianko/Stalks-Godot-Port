class_name Palette
extends RefCounted
## The single source of truth for colour in this game.
##
## The shared Theme in `assets/themes/` is generated from these values, so the
## two can never drift. Scripts use these constants directly for genuinely
## *dynamic* colour — a price change is green or red depending on its sign, which
## no stylebox can express. That is not the same thing as a per-node colour
## override in a scene file, which remains banned (see CLAUDE.md, UI).
##
## The look: a dark trading terminal. Green means the market moved your way, warm
## red means it did not.


# Surfaces, darkest to lightest.
const BACKGROUND: Color = Color("0d1411")
const SURFACE: Color = Color("141e19")
const SURFACE_RAISED: Color = Color("1e2b24")
const BORDER: Color = Color("2a3a32")
const BORDER_STRONG: Color = Color("3c5048")

# Text.
const TEXT: Color = Color("e7eee9")
const TEXT_MUTED: Color = Color("9aaca1")
const TEXT_FAINT: Color = Color("6e8176")

# Market direction. Used for prices, changes, dividends and mood.
const BULL: Color = Color("6ee7a0")
const BEAR: Color = Color("e5947a")

# Interaction and alarm.
const ACCENT: Color = Color("6ee7a0")
const ACCENT_DIM: Color = Color("2f6b4c")
const DANGER: Color = Color("e5604f")
const BANKRUPT: Color = Color("7a2f28")


## Colour for a price movement: green up, red down, muted when nothing happened.
static func for_change(delta: int) -> Color:
	if delta > 0:
		return BULL
	if delta < 0:
		return BEAR
	return TEXT_FAINT


## Colour for a year's market mood.
static func for_mood(mood: MarketMood.Value) -> Color:
	return BEAR if mood == MarketMood.Value.BEAR else BULL


## A signed figure written the way a market board writes it: +15, -8, or an
## em dash when it did not move.
## "Ann", "Ann and Bob", "Ann, Bob and Cal". Names read better than a count
## when the reader is deciding whether to wait for somebody in particular.
static func list_names(names: PackedStringArray) -> String:
	if names.is_empty():
		return ""
	if names.size() == 1:
		return names[0]
	var all_but_last: PackedStringArray = names.slice(0, names.size() - 1)
	return "%s and %s" % [", ".join(all_but_last), names[names.size() - 1]]


static func format_change(delta: int) -> String:
	if delta > 0:
		return "+%d" % delta
	if delta < 0:
		return str(delta)
	return "—"


## What a figure that does not exist is printed as: a P/E with no earnings, an
## average of nothing (`MarketReadouts.NONE`).
const NO_FIGURE: String = "--"


## A ratio to a fixed number of decimal places: 12.6, 9.40. `--` for NAN.
static func format_decimal(value: float, places: int) -> String:
	if is_nan(value):
		return NO_FIGURE
	return ("%." + str(places) + "f") % value


## A ratio to a fixed number of places, signed: +0.84, -0.24. `--` for NAN.
static func format_signed_decimal(value: float, places: int) -> String:
	if is_nan(value):
		return NO_FIGURE
	var text: String = format_decimal(value, places)
	if value > 0.0 and text.to_float() > 0.0:
		return "+" + text
	return text


## A percentage rounded to a whole number, signed: +6%, -4%, 0%. `--` for NAN.
static func format_percent_change(value: float) -> String:
	if is_nan(value):
		return NO_FIGURE
	var whole: int = roundi(value)
	if whole > 0:
		return "+%d%%" % whole
	return "%d%%" % whole


## A percentage rounded to a whole number, unsigned: 38%. `--` for NAN.
static func format_percent(value: float) -> String:
	if is_nan(value):
		return NO_FIGURE
	return "%d%%" % roundi(value)


## A percentage to one decimal place: 3.0%. `--` for NAN.
static func format_percent_decimal(value: float) -> String:
	if is_nan(value):
		return NO_FIGURE
	return "%.1f%%" % value


## Colour for a percentage move, by the sign of its rounded value, so a move
## printed as 0% is never coloured as though it went somewhere.
static func for_percent(value: float) -> Color:
	if is_nan(value):
		return TEXT_FAINT
	return for_change(roundi(value))


## Currency, with thousands separators. Money is always an integer here, so there
## is never a decimal part to show.
static func format_money(amount: int) -> String:
	var negative: bool = amount < 0
	var digits: String = str(absi(amount))
	var grouped: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "," + grouped
	return ("-$" if negative else "$") + grouped
