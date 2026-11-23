class_name LedgerWidget
extends VBoxContainer
## Why a company's price moved this year, every point of it attributed and
## summing to the total (docs/stalkleheads-design.md §7.5, §3.5).
##
## "The mode's thesis in one widget": if a player asks why something went down,
## this is the answer, and it is arithmetic rather than a story. The lines are
## `PriceLedger`'s, in the design's order, plus the flow line the design's sketch
## left out - order flow is published in the ledger (§15 Q), so it is shown.
##
## **The event is in the total.** In this mode Yearly Change includes the
## year's event (§14 q7, decisions.md D158), and this is where it is broken
## back out: the board's CHG is this widget's total.
##
## Every line is always present, zero or not, so the widget is the same height
## every year and nothing below it moves (decisions.md D125).


const CellRowScene: PackedScene = preload("res://src/ui/widgets/cell_row.tscn")

## Each line's caption, in order. Explanatory names, not voice.
const CAPTIONS: Array[String] = [
	"Earnings", "Multiple", "Industry", "This event", "Last, faded", "Flow",
]

## What each line means, in the same order (`TermTips`).
const TIPS: Array[String] = [
	TermTips.LEDGER_EARNINGS, TermTips.LEDGER_MULTIPLE, TermTips.LEDGER_INDUSTRY,
	TermTips.LEDGER_EVENT, TermTips.LEDGER_FADED, TermTips.LEDGER_FLOW,
]

const CAPTION_CHARS: int = 13
const VALUE_CHARS: int = 6


@onready var _move: CellRow = %Move
@onready var _lines: VBoxContainer = %Lines
@onready var _total: CellRow = %Total

var _rows: Array[CellRow] = []


func _ready() -> void:
	_move.configure([CAPTION_CHARS, VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
	_total.configure([CAPTION_CHARS, VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
	_total.set_framed(&"HeaderCard")
	_move.set_cell_tooltip(1, TermTips.YEAR_ON_YEAR)
	for index: int in CAPTIONS.size():
		var row: CellRow = CellRowScene.instantiate()
		_lines.add_child(row)
		row.configure([CAPTION_CHARS, VALUE_CHARS], [CellRow.LEFT, CellRow.RIGHT])
		row.set_cell(0, "  " + CAPTIONS[index])
		row.set_cell_variation(0, &"Faint")
		row.set_cell_tooltip(0, TIPS[index])
		_rows.append(row)
	show_nothing()


## A company with no year behind it yet, or not a company at all.
func show_nothing() -> void:
	_move.set_texts(["", ""])
	for row: CellRow in _rows:
		row.set_cell(1, "")
	_total.set_texts(["  Total", ""])


func show_ledger(ledger: PriceLedger) -> void:
	if ledger == null:
		show_nothing()
		return
	# The year-on-year move as a percentage beside the two prices.
	var percent: float = MarketReadouts.percent_change(ledger.price_before, ledger.price_after)
	_move.set_texts([
		"%d -> %d" % [ledger.price_before, ledger.price_after],
		Palette.format_percent_change(percent),
	])
	_move.set_cell_colour(1, Palette.for_percent(percent))
	var values: Array[int] = [
		ledger.earnings,
		ledger.multiple_total(),
		ledger.industry_standing,
		ledger.this_years_event,
		ledger.last_years_event_faded,
		ledger.flow,
	]
	for index: int in _rows.size():
		_rows[index].set_cell(1, Palette.format_change(values[index]))
		_rows[index].set_cell_colour(1, Palette.for_change(values[index]))
	_total.set_texts(["  Total", Palette.format_change(ledger.total())])
	_total.set_cell_colour(1, Palette.for_change(ledger.total()))


## Every line as text, for tests.
func lines_text() -> PackedStringArray:
	var lines: PackedStringArray = [_move.line_text()]
	for row: CellRow in _rows:
		lines.append(row.line_text())
	lines.append(_total.line_text())
	return lines
