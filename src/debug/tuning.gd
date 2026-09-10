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

## Every get_value() since boot. Read by the DBG Info tab and by
## tools/measure_frame.gd, which divides it by the tick count to get lookups per
## frame — the number that says whether caching this is worth the risk of a
## slider silently going dead (ADR-0027). An integer increment against two
## dictionary operations is not a cost worth hiding behind a debug flag.
var lookups: int = 0

var _defs: Dictionary = {}
var _values: Dictionary = {}
var _loaded := false

## Keys whose value came from user://tuning.json rather than the shipped
## defaults. See _load_user_overrides() for why this is worth tracking.
var _overridden: Array[String] = []


func _ready() -> void:
	_ensure_loaded()


## Loads on first use rather than relying on _ready().
##
## Under `--script` (the headless test runner) autoloads are registered but
## never enter the tree, so _ready() never fires and every lookup would return
## 0.0 — silently, which is the worst way for a tuning system to fail.
func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
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


## Applies the on-device saved values over the shipped defaults.
##
## THIS FILE OUTLIVES AN APK UPDATE. `user://` is the app's own data directory,
## so a saved value is pinned FOREVER and no future release can move it — a
## shipped tuning change simply never reaches the device for that key.
##
## That cost two releases. Movement speed was halved and the arrow rebalanced in
## PR #15, CI was green, the APK installed, and the report that came back
## described the old numbers. There was nothing on screen to say why, because
## overriding silently is exactly what this function used to do.
##
## So the keys are recorded and surfaced: the debug panel shows a badge, and the
## count goes to the log at boot. The override still wins — deleting somebody's
## tuning underneath them trades one silent surprise for another — but it can no
## longer happen invisibly.
func _load_user_overrides() -> void:
	_overridden.clear()
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
			_overridden.append(key)

	if not _overridden.is_empty():
		# print(), not push_warning(): this must land in the Log tab, which is
		# the only place the user can read it without a PC.
		print(
			(
				"Tuning: %d value(s) overridden by %s - the shipped defaults for these are NOT in use: %s"
				% [_overridden.size(), USER_PATH, ", ".join(_overridden)]
			)
		)

	reloaded.emit()


## Keys currently taking their value from user://tuning.json instead of the
## shipped default. Empty means the build is running exactly what was released.
func overridden_keys() -> Array[String]:
	_ensure_loaded()
	return _overridden.duplicate()


## Re-reads the defaults and the saved overrides from disk.
##
## Exists so the override behaviour can be tested at all: without it the only
## way to exercise _load_user_overrides() is to restart the process, which a
## headless test cannot do.
func reload() -> void:
	_loaded = false
	_values.clear()
	_overridden.clear()
	_ensure_loaded()
	reloaded.emit()


func get_value(key: String) -> float:
	_ensure_loaded()
	lookups += 1
	# One dictionary operation rather than has() plus [], which halves the work
	# in the hottest function in the project. NAN is safe as the sentinel: every
	# stored value comes from float() over parsed JSON and through clampf(), so
	# a genuine NAN cannot get in.
	var value: float = _values.get(key, NAN)
	if is_nan(value):
		push_error("Tuning: unknown key '%s'" % key)
		return 0.0
	return value


func set_value(key: String, value: float) -> void:
	_ensure_loaded()
	if not _defs.has(key):
		push_error("Tuning: unknown key '%s'" % key)
		return

	var clamped := clampf(value, get_min(key), get_max(key))
	if is_equal_approx(_values.get(key, NAN), clamped):
		return

	_values[key] = clamped
	changed.emit(key, clamped)


func get_min(key: String) -> float:
	_ensure_loaded()
	return float(_defs[key].get("min", 0.0))


func get_max(key: String) -> float:
	_ensure_loaded()
	return float(_defs[key].get("max", 1.0))


func get_group(key: String) -> String:
	_ensure_loaded()
	return String(_defs[key].get("group", "Misc"))


func keys() -> Array:
	_ensure_loaded()
	return _defs.keys()


## Keys grouped by their "group" field, for the debug panel's sections.
func grouped_keys() -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}
	for key: String in _defs:
		var group := get_group(key)
		if not out.has(group):
			out[group] = []
		out[group].append(key)
	return out


func reset() -> void:
	_ensure_loaded()
	for key: String in _defs:
		_values[key] = float(_defs[key].get("value", 0.0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
	# Clearing this alongside the file is what makes the badge disappear on the
	# same tap that restores the defaults.
	_overridden.clear()
	reloaded.emit()


## Writes every current value to user://tuning.json.
##
## Saving is what CREATES the override, so this is where the badge starts
## showing: from this moment those keys are pinned on this device and no shipped
## default will move them again until Reset. Telling the user at the moment they
## do it is far better than letting them discover it two releases later.
func save() -> bool:
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Tuning: could not write %s" % USER_PATH)
		return false
	file.store_string(to_json())

	_overridden.clear()
	for key: String in _defs:
		_overridden.append(key)
	reloaded.emit()
	return true


## Flat {key: value} JSON — this is what gets pasted back into chat and
## committed into tuning_defaults.json.
func to_json() -> String:
	_ensure_loaded()
	return JSON.stringify(_values, "  ", true)
