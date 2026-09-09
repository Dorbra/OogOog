extends RefCounted
## A saved on-device value must never override the build INVISIBLY.
##
## user://tuning.json wins over the shipped defaults, key by key, and it
## survives an APK update because user:// is the app's own data directory. So a
## value saved once from the debug panel is pinned on that device forever and no
## later release can move it.
##
## That is not hypothetical. Movement speed was halved and the projectile
## rebalanced across two releases; CI was green, the APK installed, and the
## playtest that came back described the old numbers. Nothing on screen said
## why, because overriding silently was exactly what the loader did.
##
## The override still wins — deleting somebody's tuning underneath them trades
## one silent surprise for another — but it is now reported, and these are the
## assertions that keep it reported.

const USER_PATH := "user://tuning.json"

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## Puts the real file back, whatever the test did. Without this, running the
## suite on a machine that had real tuning saved would destroy it.
func _with_saved_file(body: Callable) -> void:
	var had := FileAccess.file_exists(USER_PATH)
	var backup := FileAccess.get_file_as_string(USER_PATH) if had else ""

	body.call()

	if had:
		var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
	Tuning.reload()


func _write_override(key: String, value: float) -> void:
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({key: value}))
	file = null
	Tuning.reload()


func test_a_saved_value_is_reported_and_applied() -> void:
	_with_saved_file(
		func() -> void:
			var shipped := Tuning.get_value("move_speed")
			var other := shipped + 77.0
			_write_override("move_speed", other)

			# Both halves matter. Reporting a key that is not actually in force
			# would be a false alarm; applying one without reporting it is the
			# bug this file exists for.
			_runner.check(
				Tuning.overridden_keys() == ["move_speed"],
				_fail("the overridden key is named, got %s" % str(Tuning.overridden_keys()))
			)
			_runner.check(
				is_equal_approx(Tuning.get_value("move_speed"), other),
				_fail("and the saved value is the one in force")
			)
	)


func test_reset_clears_both_the_file_and_the_report() -> void:
	_with_saved_file(
		func() -> void:
			var shipped := Tuning.get_value("move_speed")
			_write_override("move_speed", shipped + 77.0)

			Tuning.reset()

			# The badge disappearing and the value returning have to happen on
			# the same tap, or Reset looks like it did nothing.
			_runner.check(
				Tuning.overridden_keys().is_empty(),
				_fail("reset clears the report, got %s" % str(Tuning.overridden_keys()))
			)
			_runner.check(
				is_equal_approx(Tuning.get_value("move_speed"), shipped),
				_fail("and restores the shipped value")
			)
			_runner.check(
				not FileAccess.file_exists(USER_PATH), _fail("and removes the file itself")
			)
	)


func test_an_unshipped_build_reports_nothing() -> void:
	_with_saved_file(
		func() -> void:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_PATH))
			Tuning.reload()
			# The quiet case, asserted so the badge cannot start crying wolf:
			# with no saved file the build must report itself as clean.
			_runner.check(
				Tuning.overridden_keys().is_empty(),
				_fail("no saved file means no override, got %s" % str(Tuning.overridden_keys()))
			)
	)


func test_an_unknown_key_is_ignored_and_not_reported() -> void:
	_with_saved_file(
		func() -> void:
			var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
			file.store_string(JSON.stringify({"a_key_from_an_older_build": 1.0}))
			file = null
			Tuning.reload()

			# A stale file from an older build must neither inject the key nor
			# claim an override that is not in force.
			_runner.check(
				Tuning.overridden_keys().is_empty(),
				_fail("unknown keys are not reported, got %s" % str(Tuning.overridden_keys()))
			)
	)
