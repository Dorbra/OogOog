extends RefCounted
## Every res://assets/... path referenced in source must exist and load.
##
## With no editor in this workflow, nothing else catches a typo'd asset path.
## A missing texture is a null or a silent placeholder — the cat simply does not
## appear, with no error naming the file. This is the same silent-failure class
## the Tuning key test guards, applied to art.

const SOURCE_DIRS := ["res://src", "res://tools"]

var _runner: Object
var _case: String


func test_referenced_assets_exist() -> void:
	var referenced := _referenced_paths()
	_runner.check(not referenced.is_empty(), "%s: found asset references to check" % _case)

	for path: String in referenced:
		_runner.check(ResourceLoader.exists(path), "%s: missing asset %s" % [_case, path])


func test_referenced_assets_load_as_textures() -> void:
	# Existing is not enough — an SVG that ThorVG fails to rasterise still
	# "exists" but yields nothing usable at runtime.
	for path: String in _referenced_paths():
		if not ResourceLoader.exists(path):
			continue
		var res: Resource = load(path)
		_runner.check(res != null, "%s: %s loaded" % [_case, path])
		if res is Texture2D:
			var tex := res as Texture2D
			_runner.check(
				tex.get_width() > 0 and tex.get_height() > 0,
				"%s: %s has non-zero size" % [_case, path]
			)


func _referenced_paths() -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	var re := RegEx.create_from_string('"(res://assets/[^"]+)"')

	for file in _source_files():
		var text := FileAccess.get_file_as_string(file)
		for m in re.search_all(text):
			var path := m.get_string(1)
			if not seen.has(path):
				seen[path] = true
				out.append(path)
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
