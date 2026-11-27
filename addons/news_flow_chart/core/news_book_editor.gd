class_name NewsBookEditor
extends RefCounted
## Every change the News Flow Chart makes to the news: add an item, change a
## field, draw or remove an arrow, delete an item (docs/news-flow-chart.md §3).
## It works on `NewsBook` objects held in memory, keyed by the path each is
## saved to, and remembers which ones it changed so only those are saved.
##
## In the editor the books are the editor's own cached copies, so the
## Inspector and the chart always agree. In the tests they are copies saved
## under `user://`, never src/data/news/ - a headless save drops a file's `uid`
## line (docs/news-flow-chart.md §1.1).
##
## Every method that can be refused returns a message saying why, or "" when
## it did what was asked. Nothing is ever overwritten: an id already in use, or
## retired, is never given to a new item.


## The books, by path.
var books: Dictionary[String, NewsBook] = {}

## Ids of deleted items, which no item may have again. Deleting adds to it.
var retired_ids: Array[StringName] = []

var _changed: Dictionary[String, bool] = {}


func _init(loaded_books: Dictionary[String, NewsBook], retired: Array[StringName] = []) -> void:
	books = loaded_books
	retired_ids = retired.duplicate()


## Loads every book in `news_dir`, keyed by its path.
static func load_books(news_dir: String) -> Dictionary[String, NewsBook]:
	var loaded: Dictionary[String, NewsBook] = {}
	var names: Array[String] = []
	names.assign(DirAccess.get_files_at(news_dir))
	names.sort()
	for file_name: String in names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [news_dir, file_name]
		var book: NewsBook = load(path) as NewsBook
		if book != null:
			loaded[path] = book
	return loaded


## Every item in every book, as one `NewsContent`. Traders' own chatter is not
## in the books, so it is not here.
func content() -> NewsContent:
	var all: Array[NewsBook] = []
	all.assign(books.values())
	return NewsContent.build(all, [] as Array[NpcTraderDefinition])


## The graph of every item in the books.
func graph() -> NewsGraph:
	return NewsGraph.build(content())


## Every id taken: the items' and the retired ones.
func taken_ids() -> Array[StringName]:
	var taken: Array[StringName] = retired_ids.duplicate()
	for line: Resource in content().all_lines():
		taken.append(line.get("id"))
	return taken


## The item with this id, or null.
func find(id: StringName) -> Resource:
	for path: String in books:
		var line: Resource = _find_in(books[path], id)
		if line != null:
			return line
	return null


## The path of the book holding the item with this id, or "".
func book_path_of(id: StringName) -> String:
	for path: String in books:
		if _find_in(books[path], id) != null:
			return path
	return ""


## Gives `line` its id and puts it in the book it belongs in
## (`NewsBookRouter`). Its other fields are filled in already.
func add(line: Resource, news_dir: String) -> String:
	var kind: int = NewsKind.of(line)
	if kind < 0:
		return "That is not a news item."
	var path: String = NewsBookRouter.book_path_for(line, news_dir)
	if not books.has(path):
		return "There is no book %s to put it in." % path.get_file()
	line.set("id", NewsIdMaker.next_id(line, taken_ids()))
	var list: Array = books[path].get(NewsKind.list_name(kind))
	list.append(line)
	_changed[path] = true
	return ""


## Sets one field of an item. Its id never changes (§3.3).
func set_field(id: StringName, field: StringName, value: Variant) -> String:
	if field == &"id":
		return "An id is fixed once made."
	var line: Resource = find(id)
	if line == null:
		return "There is no news item %s." % id
	if not field in line:
		return "A %s has no field %s." % [NewsKind.display_name(NewsKind.of(line)), field]
	line.set(field, value)
	_changed[book_path_of(id)] = true
	return ""


## Draws an arrow from `from_id` to `to_id`: `to_id` then requires `from_id`.
func link(from_id: StringName, to_id: StringName) -> String:
	var to_line: Resource = find(to_id)
	if to_line == null or find(from_id) == null:
		return "Both ends of an arrow must be news items."
	var required: Array[StringName] = to_line.get("requires")
	if required.has(from_id):
		return "%s already requires %s." % [to_id, from_id]
	if graph().would_loop(from_id, to_id):
		return "%s already waits for %s, so this arrow would make a loop and neither could appear." % [from_id, to_id]
	var updated: Array[StringName] = required.duplicate()
	updated.append(from_id)
	to_line.set("requires", updated)
	_changed[book_path_of(to_id)] = true
	return ""


## Removes the arrow from `from_id` to `to_id`. Every other arrow stays.
func unlink(from_id: StringName, to_id: StringName) -> String:
	var to_line: Resource = find(to_id)
	if to_line == null:
		return "There is no news item %s." % to_id
	var required: Array[StringName] = to_line.get("requires")
	if not required.has(from_id):
		return "%s does not require %s." % [to_id, from_id]
	var updated: Array[StringName] = required.duplicate()
	updated.erase(from_id)
	to_line.set("requires", updated)
	_changed[book_path_of(to_id)] = true
	return ""


## Deletes an item, removes every arrow to and from it, and retires its id. The
## tool asks first when it has arrows (`NewsGraph.arrow_count`); this does not.
func delete(id: StringName) -> String:
	var path: String = book_path_of(id)
	if path.is_empty():
		return "There is no news item %s." % id
	var line: Resource = find(id)
	var list: Array = books[path].get(NewsKind.list_name(NewsKind.of(line)))
	list.erase(line)
	_changed[path] = true
	for other_path: String in books:
		var book: NewsBook = books[other_path]
		for list_name: StringName in _list_names():
			for other: Resource in book.get(list_name):
				var required: Array[StringName] = other.get("requires")
				if required.has(id):
					var updated: Array[StringName] = required.duplicate()
					updated.erase(id)
					other.set("requires", updated)
					_changed[other_path] = true
	if not retired_ids.has(id):
		retired_ids.append(id)
	return ""


## The paths of the books changed since the last save, sorted.
func changed_paths() -> Array[String]:
	var paths: Array[String] = []
	paths.assign(_changed.keys())
	paths.sort()
	return paths


## Saves every changed book to its path. Returns one message per book that
## failed; the rest are saved and no longer count as changed.
func save_changed() -> Array[String]:
	var problems: Array[String] = []
	for path: String in changed_paths():
		var result: Error = ResourceSaver.save(books[path], path)
		if result != OK:
			problems.append("Could not save %s (error %d)." % [path, result])
		else:
			_changed.erase(path)
	return problems


## Writes the retired ids to `path`, keeping the explanation at its top.
func save_retired_ids(path: String) -> String:
	var header: PackedStringArray = []
	if FileAccess.file_exists(path):
		for raw: String in FileAccess.get_file_as_string(path).split("\n"):
			var line: String = raw.strip_edges()
			if not line.is_empty() and not line.begins_with("#"):
				break
			header.append(line)
	while not header.is_empty() and header[-1].strip_edges().is_empty():
		header.remove_at(header.size() - 1)
	var text: String = "\n".join(header)
	if not text.is_empty():
		text += "\n"
	for id: StringName in retired_ids:
		text += "%s\n" % id
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Could not write %s." % path
	file.store_string(text)
	file.close()
	return ""


static func _find_in(book: NewsBook, id: StringName) -> Resource:
	for list_name: StringName in _list_names():
		for line: Resource in book.get(list_name):
			if line.get("id") == id:
				return line
	return null


static func _list_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for kind: NewsKind.Value in NewsKind.ALL:
		names.append(NewsKind.list_name(kind))
	return names
