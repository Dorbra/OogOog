class_name Arena
extends RefCounted
## An arena parsed from an ASCII grid.
##
## The grid is a hand-edited text file, chosen over hand-authored .tscn tilemap
## data because this project has no editor: a layout change has to be something
## that can be typed and reviewed in a diff on a phone.
##
## This class is also the source of truth for world size — bounds come from
## cols x cell_size, so resizing the arena means editing the file rather than
## keeping a constant in sync across SimWorld, Terrain and CameraRig.
##
## No Godot physics anywhere. Circle push-out and a DDA grid walk are pure
## maths, which is what keeps the whole thing testable without a display.

enum Cell { OPEN, WALL, BUSH }

const DEFAULT_PATH := "res://data/arenas/arena_01.txt"
const LEGEND_PATH := "res://data/arenas/legend.json"

var cols: int = 0
var rows: int = 0
var cell_size: float = 60.0

var _cells: PackedInt32Array = PackedInt32Array()
var _spawns: Array[Vector2] = []

## Built once on first use, because the grid never changes after parsing.
##
## The bot AI used to find bushes by calling cells_in_rect(bounds()), which
## allocates an Array of every non-open cell — 108 of them — on every call, to
## then look at the 16 that are bushes. Measured at 141 us a call against a mean
## simulation tick of 226 us. Nothing here can change at runtime, so nothing
## here needs recomputing (ADR-0027).
var _bush_centres: Array[Vector2] = []
var _open_centres: Array[Vector2] = []
## An arena with no bushes at all would otherwise rebuild an empty list forever,
## since is_empty() cannot tell "not built yet" from "genuinely none".
var _cell_lists_built := false


func _init(path: String = DEFAULT_PATH) -> void:
	_load_legend()
	_parse(path)


func _load_legend() -> void:
	var text := FileAccess.get_file_as_string(LEGEND_PATH)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("cell_size"):
		cell_size = float(parsed["cell_size"])


## Ragged rows and unknown characters are treated as open ground rather than
## errors. The file is hand-edited, so malformed input is the expected case —
## failing the build over a short line would make the format hostile to use.
func _parse(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Arena: could not read %s" % path)
		return

	var lines: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if not line.is_empty():
			lines.append(line)

	if lines.is_empty():
		push_error("Arena: %s contains no rows" % path)
		return

	rows = lines.size()
	cols = 0
	for line in lines:
		cols = maxi(cols, line.length())

	_cells.resize(cols * rows)
	_cells.fill(Cell.OPEN)

	for y in rows:
		var line: String = lines[y]
		for x in cols:
			var symbol := line[x] if x < line.length() else "."
			match symbol:
				"#":
					_cells[y * cols + x] = Cell.WALL
				"b":
					_cells[y * cols + x] = Cell.BUSH
				"P":
					_spawns.append(cell_centre(x, y))
				_:
					pass


func bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(cols * cell_size, rows * cell_size))


func cell_centre(x: int, y: int) -> Vector2:
	return Vector2((float(x) + 0.5) * cell_size, (float(y) + 0.5) * cell_size)


func cell_at(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.y / cell_size)))


func in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows


func cell(x: int, y: int) -> int:
	if not in_grid(x, y):
		return Cell.WALL  # outside the grid behaves as solid
	return _cells[y * cols + x]


func is_solid(x: int, y: int) -> bool:
	return cell(x, y) == Cell.WALL


## Bushes hide what stands in them. Nothing reads this yet beyond fading the
## player, but the bot AI will, and adding it later would mean touching arena,
## simulation and view all over again.
func conceals(pos: Vector2) -> bool:
	var c := cell_at(pos)
	return cell(c.x, c.y) == Cell.BUSH


func spawn_points() -> Array[Vector2]:
	return _spawns.duplicate()


## Pushes a circle out of any solid cell it overlaps.
##
## Resolves along the axis of least penetration, twice: one pass leaves a circle
## wedged in a concave corner still overlapping the other wall, which reads as
## the player sticking to geometry.
func resolve_circle(pos: Vector2, radius: float) -> Vector2:
	var out := pos
	for _pass in 2:
		var min_c := cell_at(out - Vector2(radius, radius))
		var max_c := cell_at(out + Vector2(radius, radius))
		for y in range(min_c.y, max_c.y + 1):
			for x in range(min_c.x, max_c.x + 1):
				if is_solid(x, y):
					out = _push_out(out, radius, x, y)
	return out


func _push_out(pos: Vector2, radius: float, x: int, y: int) -> Vector2:
	var rect := Rect2(Vector2(x, y) * cell_size, Vector2(cell_size, cell_size))
	var closest := Vector2(
		clampf(pos.x, rect.position.x, rect.end.x), clampf(pos.y, rect.position.y, rect.end.y)
	)
	var delta := pos - closest
	var dist := delta.length()

	if dist > radius:
		return pos

	if dist > 0.001:
		# Outside the cell (edge or corner): push straight out along the normal.
		return closest + delta / dist * radius

	# Centre is inside the cell. Leave by the nearest face — but only through a
	# face whose neighbour is actually open.
	#
	# Nearest-face alone ejects out of a BORDER wall into off-grid space, which
	# is itself treated as solid, so the circle lands somewhere worse than it
	# started. Dead-centre in a cell all four faces tie, and the first one wins
	# arbitrarily.
	var options := [
		{
			"d": pos.x - rect.position.x,
			"n": Vector2i(x - 1, y),
			"p": Vector2(rect.position.x - radius, pos.y)
		},
		{
			"d": rect.end.x - pos.x,
			"n": Vector2i(x + 1, y),
			"p": Vector2(rect.end.x + radius, pos.y)
		},
		{
			"d": pos.y - rect.position.y,
			"n": Vector2i(x, y - 1),
			"p": Vector2(pos.x, rect.position.y - radius)
		},
		{
			"d": rect.end.y - pos.y,
			"n": Vector2i(x, y + 1),
			"p": Vector2(pos.x, rect.end.y + radius)
		},
	]
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])

	for o: Dictionary in options:
		var n: Vector2i = o["n"]
		if not is_solid(n.x, n.y):
			return o["p"]

	# Fully enclosed by walls. Nothing better to do than the nearest face.
	return options[0]["p"]


## Walks the grid from `from` toward `to`, returning the first point at which a
## wall is struck, or `to` if the path is clear.
##
## An exact DDA traversal (Amanatides & Woo), NOT sampling along the segment.
## Arrows already use a swept circle test against targets specifically so a fast
## shot cannot tunnel through them; at full draw an arrow covers ~24px per tick
## against 60px cells, so point sampling would work most of the time and
## occasionally let a shot pass clean through a wall. Reintroducing that bug in
## a second place is not a trade worth making for a few lines.
func cast_segment(from: Vector2, to: Vector2) -> Dictionary:
	var delta := to - from
	var distance := delta.length()
	if distance < 0.0001:
		var c0 := cell_at(from)
		var solid0 := is_solid(c0.x, c0.y)
		return {"hit": solid0, "point": from}

	var dir := delta / distance
	var cur := cell_at(from)
	var step_x := 1 if dir.x > 0.0 else -1
	var step_y := 1 if dir.y > 0.0 else -1

	# Distance along the ray to the next cell boundary on each axis, and the
	# distance between successive boundaries. INF encodes an axis-aligned ray
	# that never crosses boundaries on the other axis.
	var t_delta_x := absf(cell_size / dir.x) if absf(dir.x) > 0.0001 else INF
	var t_delta_y := absf(cell_size / dir.y) if absf(dir.y) > 0.0001 else INF

	var next_x := float(cur.x + (1 if step_x > 0 else 0)) * cell_size
	var next_y := float(cur.y + (1 if step_y > 0 else 0)) * cell_size
	var t_max_x := ((next_x - from.x) / dir.x) if absf(dir.x) > 0.0001 else INF
	var t_max_y := ((next_y - from.y) / dir.y) if absf(dir.y) > 0.0001 else INF

	if is_solid(cur.x, cur.y):
		return {"hit": true, "point": from}

	var travelled := 0.0
	while travelled <= distance:
		if t_max_x < t_max_y:
			travelled = t_max_x
			t_max_x += t_delta_x
			cur.x += step_x
		else:
			travelled = t_max_y
			t_max_y += t_delta_y
			cur.y += step_y

		if travelled > distance:
			break
		if is_solid(cur.x, cur.y):
			return {"hit": true, "point": from + dir * travelled}

	return {"hit": false, "point": to}


## Centres of every bush cell. The array is shared, not copied — callers read it
## and must not mutate it.
func bush_centres() -> Array[Vector2]:
	_build_cell_lists()
	return _bush_centres


## Centres of every non-solid cell, in row-major order. Shared, not copied.
func open_centres() -> Array[Vector2]:
	_build_cell_lists()
	return _open_centres


func _build_cell_lists() -> void:
	if _cell_lists_built:
		return
	_cell_lists_built = true
	for y in rows:
		for x in cols:
			var c := cell(x, y)
			if c == Cell.BUSH:
				_bush_centres.append(cell_centre(x, y))
			if c != Cell.WALL:
				_open_centres.append(cell_centre(x, y))


## Cells overlapping a rect, for the view to draw only what is on screen.
func cells_in_rect(rect: Rect2) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var min_c := cell_at(rect.position)
	var max_c := cell_at(rect.end)
	for y in range(maxi(min_c.y, 0), mini(max_c.y + 1, rows)):
		for x in range(maxi(min_c.x, 0), mini(max_c.x + 1, cols)):
			var c := cell(x, y)
			if c != Cell.OPEN:
				out.append(Vector3i(x, y, c))
	return out
