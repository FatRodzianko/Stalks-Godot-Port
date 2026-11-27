class_name TermTips
extends RefCounted
## The tooltip for every financial term on the StalkleHeads tabs, in one place,
## so the same word means the same thing wherever a player hovers over it
## (decisions.md D183).
##
## **These explain; they do not have a voice.** Each says what the number is and
## how to read it, in the words of docs/glossary.md, which is the longer form.
## A rule changing means its sentence here changes too; where a figure comes
## from code (the short-interest flag), it is read from the rule, not retyped.
##
## **Every tooltip is passed through `fit`**, which wraps it at `MAX_CHARS`.
## Godot's tooltip is one line per newline, as wide as its longest line, so an
## unwrapped sentence stretched most of the way across the screen, far from the
## mouse (manual-testing.md F5, decisions.md D184).


## The widest a tooltip line may be, in characters: about a third of the
## picture, so a tooltip stays beside the pointer.
const MAX_CHARS: int = 36


# ------------------------------------------------------------ the board

const SYM: String = "The company's short code."
const PRICE: String = "What one share costs now."
const CHANGE: String = (
	"How far the price moved this year, in coins, the year's special event included.\n"
	+ "The Company tab's WHY THE PRICE MOVED breaks it down."
)
const EPS: String = (
	"Earnings per share: this year's profit divided by the company's shares.\n"
	+ "What each share earned."
)
const PE: String = (
	"Price to earnings: the price divided by earnings per share.\n"
	+ "How many years of this year's earnings one share costs. Lower is cheaper.\n"
	+ "-- when the company made no profit."
)
const DIVIDEND: String = "Dividend: coins paid for every share you hold, at the end of the year."
const HELD: String = "How many shares you own."
const INDUSTRY_PE: String = (
	"The average P/E of the industry's companies still trading.\n"
	+ "A company's P/E under it says whether it costs more or less than its neighbours."
)
const INDUSTRY_MOVE: String = "The industry's performance this year: how far conditions moved its companies' revenue."

# ----------------------------------------------------------- the market

const INDEX_LEVEL: String = (
	"My Mutuals and Me Inc.: the whole market as one number.\n"
	+ "Each year it moves by the average price move of the companies trading when the year began."
)
const MARKET_PE: String = "The average P/E of every company still trading."
const MOOD: String = (
	"BULL when the index rose this year, bear when it fell.\n"
	+ "It decides which set of special events next year's comes from."
)
const BREADTH: String = "How many companies rose this year, out of those still trading."
const RISK_FREE: String = (
	"What BERRY BONDS pays a year for its price: the safe return.\n"
	+ "Compare a company's earnings yield with it."
)
const SENTIMENT: String = (
	"This year's index move, held to 20% either way, nudges every company's P/E next year:\n"
	+ "up after a rise, down after a fall."
)

# ------------------------------------------------------------ industries

const THREE_YEARS: String = "The industry's last three years of performance, compounded."
const STANDING: String = (
	"How much extra the market pays for this industry's earnings this year, in years of earnings.\n"
	+ "Its performance times 0.06: a +20% industry adds 1.2 to every member's P/E."
)
const INDUSTRY_SHARE: String = "The industry's revenue as a share of the whole market's."
const COMPANIES: String = "Companies in the industry still trading."
const MARKET_SHARE: String = "The company's revenue as a share of its industry's."
const MARKET_SHARE_CHANGE: String = "How the company's share of its industry moved this year, in points."

# --------------------------------------------------------------- company

const REGIME: String = (
	"Which of five states the company's earnings are in, and for how long:\n"
	+ "GROWTH, STEADY, SLOWING, DECLINE or DISTRESS.\n"
	+ "It sets how fast revenue moves and where the margin heads. It can change once a year."
)
const REVENUE: String = "Everything the company took in this year."
const EXPENSES: String = "What it cost to run: revenue less profit."
const PROFIT: String = "Revenue less expenses."
const MARGIN: String = "Profit as a share of revenue."
const EARNINGS_YIELD: String = (
	"Earnings per share divided by price: P/E turned upside down.\n"
	+ "Above the risk-free rate, the company earns more for its price than the bond pays."
)
const YEAR_ON_YEAR: String = "The price's move this year as a percentage of last year's price."
const LEDGER_EARNINGS: String = "The part of the move from earnings per share rising or falling."
const LEDGER_MULTIPLE: String = (
	"The part from what the market pays for each coin of earnings:\n"
	+ "sentiment, the company's regime, and the limits on how high or low that goes."
)
const LEDGER_INDUSTRY: String = "The part from how the market rates the company's industry this year (its standing)."
const LEDGER_EVENT: String = "This year's special event, in full."
const LEDGER_FADED: String = "Earlier events wearing off: half of what is left fades each year."
const LEDGER_FLOW: String = (
	"The part from what traders, the desk and players alike, bought and sold last year.\n"
	+ "Never more than 5% of what the company's earnings are worth."
)

# ------------------------------------------------------- the Company tab

const NPC_LAST_YEAR: String = "What the trader did with this company last year: bought, sold, shorted, covered or held."
const NPC_NOW: String = (
	"What the trader holds now: a number of shares, or \"short\" and the shares it has sold short."
)
const NPC_HOLDERS: String = "How many of the desk's traders hold this company, or have sold it short."

# ---------------------------------------------------------------- the news

const WHISPERS: String = (
	"Whispers from the Avenue. Rumors circulating around the Market.\n"
	+ "Most are true, but some are not. Can you find the truth?"
)
const NPC_CHATTER: String = "What each desk trader said about what it did last year."
const WHISPER_HISTORY: String = "Every whisper heard so far, year by year, and what came of it."

# ------------------------------------------------------------- the panel

const NET_WORTH: String = "Your cash, plus your shares at today's prices, less what you owe."
const DESK: String = (
	"Twenty-four computer traders, three for each of eight strategies.\n"
	+ "Each line is that strategy's return so far.\n"
	+ "What they buy and sell pushes next year's prices: the flow line in WHY THE PRICE MOVED."
)


## Short interest, with the flag's threshold read from the rule itself.
static func short_interest() -> String:
	return (
		"The share of a company sold short by the desk's short sellers, betting its price falls.\n"
		+ "At %d%% it is FLAGGED: a short squeeze can make its price jump.\n"
		+ "Squeezed, the shorts buy back over a few years. When they reach 0%%, the jump comes off."
	) % roundi(ShortInterestRules.FLAG_AT_PERCENT)


## What each desk strategy buys (design §5.1, glossary "NPC strategy").
static func strategy(value: NpcStrategy.Value) -> String:
	match value:
		NpcStrategy.Value.VALUE:
			return "Buys the company with the lowest P/E."
		NpcStrategy.Value.MOMENTUM:
			return "Buys the company that rose most last year."
		NpcStrategy.Value.CONTRARIAN:
			return "Buys the company that fell most last year."
		NpcStrategy.Value.INCOME:
			return "Buys the company paying the highest dividend for its price."
		NpcStrategy.Value.INDEXER:
			return "Buys only My Mutuals and Me Inc."
		NpcStrategy.Value.PANIC:
			return "Buys the bond in a bear year and a company in a bull year."
		NpcStrategy.Value.GROWTH:
			return "Buys the company whose earnings grew fastest."
		NpcStrategy.Value.SHORT:
			return "Sells short the company with the highest P/E, betting it falls."
	return ""


## `text` word-wrapped so no line is longer than `MAX_CHARS`. Existing line
## breaks are kept; a single word longer than the limit is left whole.
static func fit(text: String) -> String:
	var out: PackedStringArray = []
	for paragraph: String in text.split("\n"):
		var line: String = ""
		for word: String in paragraph.split(" ", false):
			if line.is_empty():
				line = word
			elif line.length() + 1 + word.length() <= MAX_CHARS:
				line += " " + word
			else:
				out.append(line)
				line = word
		out.append(line)
	return "\n".join(out)
