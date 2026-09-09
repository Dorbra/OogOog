extends SceneTree
## Minimal headless test runner.
##
## Deliberately not GUT: vendoring ~100 files to test a handful of pure
## functions is a poor trade at this size. If the suite outgrows this, swapping
## in GUT is a contained change — the tests themselves barely move.
##
## Run: godot --headless --path . --script tools/run_tests.gd
## Exits non-zero on any failure, so CI fails loudly.

const TEST_DIR := "res://tests"

var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
	var files := _find_tests()
	if files.is_empty():
		push_error("No test files found in %s" % TEST_DIR)
		quit(1)
		return

	for path in files:
		_run_file(path)

	print("")
	if _failures.is_empty():
		print("PASS — %d assertions across %d files" % [_assertions, files.size()])
		quit(0)
	else:
		print("FAIL — %d failed assertion(s):" % _failures.size())
		for failure in _failures:
			print("  ✗ %s" % failure)
		quit(1)


func _find_tests() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		# Exported builds rename .gd to .gdc/.remap; tolerate both.
		if file.begins_with("test_") and file.get_extension() in ["gd", "gdc", "remap"]:
			out.append("%s/%s" % [TEST_DIR, file.trim_suffix(".remap")])
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script: GDScript = load(path)
	if script == null:
		_failures.append("%s: failed to load" % path)
		return

	# load() hands back a GDScript even when the file FAILED TO COMPILE, and the
	# null check above is not enough. There are two distinct ways a broken file
	# disappears from this suite, and BOTH have happened:
	#
	#   1. new() returns null. No test runs, and without the check below the
	#      suite reports PASS having quietly dropped an entire file. That is how
	#      test_bots.gd first went missing — a method name that clashed with
	#      Object._set() took the whole file out.
	#   2. new() itself raises. On a PARSE error the engine prints SCRIPT ERROR,
	#      ABANDONS this function, and returns to the caller as though the file
	#      had been run — so not even the null check is reached and nothing is
	#      appended. Two files vanished exactly this way during the gun rework,
	#      and the only reason it was noticed was an unrelated assertion failing
	#      in the same run.
	#
	# can_instantiate() is false for a script that did not compile, which is the
	# one question that can be asked BEFORE the call that would abandon us.
	if not script.can_instantiate():
		_failures.append("%s: failed to compile — the whole file was skipped" % path.get_file())
		return

	var instance: Object = script.new()
	if instance == null:
		_failures.append("%s: failed to compile — the whole file was skipped" % path.get_file())
		return

	print("== %s" % path.get_file())

	var cases := 0
	for method in instance.get_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue

		# Each test gets a fresh assertion sink so failures name their test.
		instance.set("_case", name)
		instance.set("_runner", self)

		# A GDScript runtime error inside a test does NOT propagate: the engine
		# prints a SCRIPT ERROR, abandons the call, and returns here as if the
		# test had finished. Before this check, a file whose helper crashed on
		# every single test still reported PASS with a smaller total nobody was
		# watching — which is precisely the "green while broken" failure this
		# project keeps finding (ADR-0012). A test that asserts nothing has not
		# run, whatever the exit code says.
		cases += 1
		var before := _assertions
		instance.call(name)
		if _assertions == before:
			_failures.append(
				"%s: %s asserted nothing — it crashed or is empty" % [path.get_file(), name]
			)

	if cases == 0:
		_failures.append("%s: contains no test_ methods" % path.get_file())


## Called by test files.
func check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func check_near(actual: float, expected: float, label: String, epsilon: float = 0.001) -> void:
	_assertions += 1
	if absf(actual - expected) > epsilon:
		_failures.append("%s (got %f, expected %f)" % [label, actual, expected])
