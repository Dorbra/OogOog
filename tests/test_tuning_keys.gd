extends RefCounted
## Every Tuning key referenced in source must exist in tuning_defaults.json.
##
## A missing key returns 0.0 and only pushes an error. On a phone that surfaces
## as "the game is broken" with nothing visible to point at — a zero move speed,
## a zero draw time, an invisible arrow — and no test would otherwise catch it.
## This project has already been bitten once by exactly this class of silent
## failure, and each round of feel-tuning adds more keys.

const SOURCE_DIRS := ["res://src", "res://tools"]
const DEFAULTS_PATH := "res://data/tuning_defaults.json"

## Documents that describe the game as it IS. Every one of these is a claim
## about the current build and goes stale the moment a key is renamed.
const LIVING_DOCS := [
	"res://docs/GAME_DESIGN.md",
	"res://docs/ARCHITECTURE.md",
	"res://docs/CICD.md",
	"res://README.md",
	"res://CONTRIBUTING.md",
]

## Where a backticked identifier is allowed to be "real". Contents AND file
## names, since ARCHITECTURE.md refers to `camera_rig` and `game_view` by
## filename rather than by any symbol inside them.
##
## COMMENTS ARE STRIPPED OUT of .gd files first, and that is load-bearing rather
## than tidy. A comment is prose and goes stale exactly like a document does —
## this very file explains the rule by naming the dead keys it was written to
## catch, and with comments in the corpus that alone made two of the three
## invisible. Only code counts as evidence that a name still means something.
const CORPUS_DIRS := ["res://src", "res://tools", "res://tests", "res://data", "res://.github"]
const CORPUS_FILES := ["res://project.godot", "res://export_presets.cfg"]

var _runner: Object
var _case: String


func test_all_referenced_keys_are_defined() -> void:
	var defined := _defined_keys()
	_runner.check(not defined.is_empty(), "%s: defaults file parsed" % _case)

	var missing: Array[String] = []
	for file in _source_files():
		for key in _referenced_keys(file):
			if not defined.has(key):
				missing.append("%s -> %s" % [file.get_file(), key])

	_runner.check(missing.is_empty(), "%s: undefined Tuning keys: %s" % [_case, ", ".join(missing)])


## A living document must not name a tuning key that no longer exists.
##
## test_all_referenced_keys_are_defined() above scans SOURCE. It has been green
## the whole time GAME_DESIGN.md — the project's stated source of truth on its
## own central mechanic — described a bow that was deleted four milestones ago:
## `draw_time_full` at 0.45 s, a magazine of 10, a full draw worth three rushed
## shots. None of those keys or numbers has existed since the guns landed.
##
## Stale docs are not cosmetic here. Nobody on this project can read the game's
## behaviour off a running build without a phone in hand, so the document IS the
## interface for most decisions, and a wrong one sends the next change in the
## wrong direction.
##
## THE RULE: a backticked snake_case identifier in a living document must name
## something that exists — a tuning key, or any identifier or filename found
## anywhere in the codebase. Deliberately not a hand-kept allowlist: the whole
## failure being fixed is a list somebody forgot to update.
##
## docs/decisions/ is EXCLUDED on purpose. An ADR is a dated record of a
## decision, immutable by the rule in its own README, and ADR-0016 naming
## `arrow_lifetime` is correct history rather than rot. Auditing them would
## force a choice between a red build and rewriting the past.
func test_living_docs_do_not_name_keys_that_no_longer_exist() -> void:
	var defined := _defined_keys()
	var corpus := _corpus()
	_runner.check(
		corpus.length() > 10000, "%s: the corpus looks empty (%d chars)" % [_case, corpus.length()]
	)

	# Matches a lowercase snake_case word in backticks: at least one underscore,
	# no leading underscore (those are private members, written as prose), and
	# no parentheses (those are function calls, written with them).
	var re := RegEx.create_from_string("`([a-z][a-z0-9]*(?:_[a-z0-9]+)+)`")
	var stale: Array[String] = []

	for path in LIVING_DOCS:
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		for m in re.search_all(text):
			var token := m.get_string(1)
			if defined.has(token) or corpus.contains(token):
				continue
			var entry := "%s -> %s" % [String(path).get_file(), token]
			if not stale.has(entry):
				stale.append(entry)

	_runner.check(
		stale.is_empty(),
		"%s: documented names that no longer exist: %s" % [_case, ", ".join(stale)]
	)


## Every file name and every file body, concatenated once.
func _corpus() -> String:
	var parts: Array[String] = []
	for dir_path in CORPUS_DIRS:
		_collect_corpus(dir_path, parts)
	for path in CORPUS_FILES:
		parts.append(FileAccess.get_file_as_string(path))
	return "\n".join(parts)


func _collect_corpus(dir_path: String, parts: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = true
	for file in dir.get_files():
		# The file name itself counts: ARCHITECTURE.md names modules by file.
		parts.append(file.get_basename())
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		var body := FileAccess.get_file_as_string("%s/%s" % [dir_path, file])
		if file.ends_with(".gd"):
			body = _without_comments(body)
		parts.append(body)
	for sub in dir.get_directories():
		_collect_corpus("%s/%s" % [dir_path, sub], parts)


## Drops whole-line comments. Deliberately not trailing ones: `#` inside a
## string literal would make that unsafe, and a name that appears ONLY in a
## trailing comment is rare enough to accept as a miss.
func _without_comments(text: String) -> String:
	var kept: Array[String] = []
	for line in text.split("\n"):
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


func test_defaults_are_within_their_own_bounds() -> void:
	var text := FileAccess.get_file_as_string(DEFAULTS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_runner.check(false, "%s: defaults file is not a JSON object" % _case)
		return

	# A default outside its slider range snaps on first touch, which looks like
	# the slider "jumping" for no reason.
	for key: String in parsed:
		var entry: Dictionary = parsed[key]
		var value := float(entry.get("value", 0.0))
		var low := float(entry.get("min", 0.0))
		var high := float(entry.get("max", 0.0))
		_runner.check(low < high, "%s: %s has min < max" % [_case, key])
		_runner.check(
			value >= low and value <= high, "%s: %s default within [min, max]" % [_case, key]
		)


func _defined_keys() -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULTS_PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		for key: String in parsed:
			out[key] = true
	return out


func _source_files() -> Array[String]:
	var out: Array[String] = []
	for dir_path in SOURCE_DIRS:
		_collect(dir_path, out)
	return out


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file])
	for sub in dir.get_directories():
		_collect("%s/%s" % [dir_path, sub], out)


func _referenced_keys(path: String) -> Array[String]:
	var out: Array[String] = []
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return out

	var re := RegEx.create_from_string('Tuning\\.get_value\\(\\s*"([^"]+)"')
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out
