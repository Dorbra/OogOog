extends Node
## Runtime-tunable gameplay parameters.
##
## This project is developed without a local machine: the only way to change a
## number and feel the result is either a ~10 minute CI round trip, or this.
## Therefore NO feel constant is ever a hardcoded literal. Everything that
## affects how the game feels lives in data/tuning_defaults.json, is adjustable
## on-device via the debug overlay, and applies live with no restart.
##
## Workflow: tune on the phone -> "Copy JSON" -> paste into chat -> the values
## are committed as the new defaults.

## Emitted whenever any value changes. Hot paths should connect to this and
## cache, rather than calling get_value() every frame.
signal changed(key: String, value: float)

## Emitted after a bulk change (reset / load), when every cached value is stale.
signal reloaded

const DEFAULTS_PATH := "res://data/tuning_defaults.json"
const USER_PATH := "user://tuning.json"

var _defs: Dictionary = {}
var _values: Dictionary = {}


func _ready() -> void:
	_load_defaults()
	_load_user_overrides()


func _load_defaults() -> void:
	var text := FileAccess.get_file_as_string(DEFAULTS_PATH)
	if text.is_empty():
		push_error("Tuning: could not read %s" % DEFAULTS_PATH)
		return

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Tuning: %s is not a JSON object" % DEFAULTS_PATH)
		return

	_defs = parsed
	for key: String in _defs:
		_values[key] = float(_defs[key].get("value", 0.0))


func _load_user_overrides() -> void:
	if not FileAccess.file_exists(USER_PATH):
		return

	var text := FileAccess.get_file_as_string(USER_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Tuning: ignoring malformed %s" % USER_PATH)
		return

	# Only accept keys we know about. A stale user file from an older build
	# must never inject unknown keys or crash the game on launch.
	for key: String in parsed:
		if _defs.has(key):
			_values[key] = float(parsed[key])

	reloaded.emit()


func get_value(key: String) -> float:
	if not _values.has(key):
		push_error("Tuning: unknown key '%s'" % key)
		return 0.0
	return _values[key]


func set_value(key: String, value: float) -> void:
	if not _defs.has(key):
		push_error("Tuning: unknown key '%s'" % key)
		return

	var clamped := clampf(value, get_min(key), get_max(key))
	if is_equal_approx(_values.get(key, NAN), clamped):
		return

	_values[key] = clamped
	changed.emit(key, clamped)


func get_min(key: String) -> float:
	return float(_defs[key].get("min", 0.0))


func get_max(key: String) -> float:
	return float(_defs[key].get("max", 1.0))


func get_group(key: String) -> String:
	return String(_defs[key].get("group", "Misc"))


func keys() -> Array:
	return _defs.keys()


## Keys grouped by their "group" field, for the debug panel's sections.
func grouped_keys() -> Dictionary:
	var out: Dictionary = {}
	for key: String in _defs:
		var group := get_group(key)
		if not out.has(group):
			out[group] = []
		out[group].append(key)
	return out


func reset() -> void:
	for key: String in _defs:
		_values[key] = float(_defs[key].get("value", 0.0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
	reloaded.emit()


func save() -> bool:
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Tuning: could not write %s" % USER_PATH)
		return false
	file.store_string(to_json())
	return true


## Flat {key: value} JSON — this is what gets pasted back into chat and
## committed into tuning_defaults.json.
func to_json() -> String:
	return JSON.stringify(_values, "  ", true)
