class_name NewsBookRouter
extends RefCounted
## Which book in src/data/news/ a new news item is saved into
## (docs/news-flow-chart.md §3.2). The game reads every book alike, so this is
## only about keeping the files tidy for a person reading them; it follows the
## layout the shipped books already have (docs/development.md, "Where each kind
## of line lives"):
##
## - an industry headline for one industry goes in that industry's book
##   (`energy.tres`);
## - company news for one company goes in `companies.tres`;
## - everything else - market news, general headlines and company news,
##   whispers, chatter - goes in `market.tres`.
##
## The tool never makes a book. If the one an item needs is missing it says so.


const MARKET_BOOK: String = "market.tres"
const COMPANIES_BOOK: String = "companies.tres"


## The path of the book `line` belongs in, inside `news_dir`.
static func book_path_for(line: Resource, news_dir: String = ContentLibrary.NEWS_DIR) -> String:
	return "%s/%s" % [news_dir, book_file_for(line)]


## The file name alone.
static func book_file_for(line: Resource) -> String:
	if line is IndustryReport:
		var report: IndustryReport = line as IndustryReport
		if not report.industry_id.is_empty():
			return "%s.tres" % report.industry_id
	if line is CompanyNews:
		var company: CompanyNews = line as CompanyNews
		if not company.company_id.is_empty():
			return COMPANIES_BOOK
	return MARKET_BOOK
