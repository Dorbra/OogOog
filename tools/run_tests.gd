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

	var instance: Object = script.new()
	print("== %s" % path.get_file())

	for method in instance.get_method_list():
		var name: String = method["name"]
		if not name.begins_with("test_"):
			continue

		# Each test gets a fresh assertion sink so failures name their test.
		instance.set("_case", name)
		instance.set("_runner", self)
		instance.call(name)

	if instance.has_method("free"):
		pass


## Called by test files.
func check(condition: bool, label: String) -> void:
	_assertions += 1
	if not condition:
		_failures.append(label)


func check_near(actual: float, expected: float, label: String, epsilon: float = 0.001) -> void:
	_assertions += 1
	if absf(actual - expected) > epsilon:
		_failures.append("%s (got %f, expected %f)" % [label, actual, expected])
