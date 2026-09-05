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
