class_name Terrain
extends RefCounted
## Procedural garden: noise ground, seeded scatter, pond, path and hedge border.
##
## Two constraints shape all of this. First, there is no image editor in this
## workflow, so the ground has to be generated rather than painted. Second it
## runs on a phone, so it must not turn into hundreds of draw calls: the ground
## is a single tiled texture, and scatter is culled to the camera rect.
##
## Placement is SEEDED, so the arena is identical every run. That matters more
## than it sounds — the screenshot test is the main art feedback loop, and it is
## useless if the garden reshuffles between renders.

const SEED := 20260906
const GROUND_TEXTURE_SIZE := 512

## Scatter categories, spawned at these base counts scaled by `decor_density`.
const TUFT_COUNT := 620
const FLOWER_COUNT := 90
const PEBBLE_COUNT := 70

var bounds: Rect2
var ground: NoiseTexture2D

var _tufts: Array[Dictionary] = []
var _flowers: Array[Dictionary] = []
var _pebbles: Array[Dictionary] = []
var _pond_centre: Vector2
var _pond_size: Vector2
var _path_points: PackedVector2Array = PackedVector2Array()


func _init(world_bounds: Rect2) -> void:
	bounds = world_bounds
	_build_ground()
	_scatter()


func _build_ground() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.024
	noise.fractal_octaves = 3

	ground = NoiseTexture2D.new()
	ground.noise = noise
	ground.width = GROUND_TEXTURE_SIZE
	ground.height = GROUND_TEXTURE_SIZE
	# Seamless so it can tile across the world without visible joins, which is
	# what lets the whole ground be one draw call.
	ground.seamless = true
	ground.color_ramp = Palette.grass_gradient()


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	_pond_centre = bounds.position + bounds.size * Vector2(0.76, 0.30)
	_pond_size = Vector2(230, 150)

	# A gentle path across the arena, drawn as overlapping blobs so it reads as
	# worn dirt rather than a geometric stripe.
	var start := bounds.position + bounds.size * Vector2(0.06, 0.72)
	var end := bounds.position + bounds.size * Vector2(0.94, 0.44)
	for i in 150:
		var t := float(i) / 149.0
		var p := start.lerp(end, t)
		p.y += sin(t * PI * 2.2) * 90.0
		_path_points.append(p)

	for i in TUFT_COUNT:
		var p := _free_point(rng)
		(
			_tufts
			. append(
				{
					"p": p,
					"h": rng.randf_range(5.0, 9.5),
					"w": rng.randf_range(1.3, 2.0),
					"lean": rng.randf_range(-0.22, 0.22),
					"c": Palette.TUFT.lerp(Palette.GRASS_LIGHT, rng.randf() * 0.7),
				}
			)
		)

	for i in FLOWER_COUNT:
		var colours := [Palette.FLOWER_A, Palette.FLOWER_B, Palette.FLOWER_C]
		(
			_flowers
			. append(
				{
					"p": _free_point(rng),
					"r": rng.randf_range(2.2, 3.4),
					"c": colours[rng.randi() % colours.size()],
				}
			)
		)

	for i in PEBBLE_COUNT:
		(
			_pebbles
			. append(
				{
					"p": _free_point(rng),
					"r": rng.randf_range(3.0, 7.0),
					"c": Palette.PEBBLE.darkened(rng.randf_range(0.0, 0.25)),
				}
			)
		)


## A point inside the arena that isn't in the pond — grass tufts floating on
## open water would undo the whole illusion.
func _free_point(rng: RandomNumberGenerator) -> Vector2:
	for _attempt in 12:
		var p := Vector2(
			rng.randf_range(bounds.position.x + 40.0, bounds.end.x - 40.0),
			rng.randf_range(bounds.position.y + 40.0, bounds.end.y - 40.0)
		)
		if not _in_pond(p, 20.0):
			return p
	return bounds.get_center()


func _in_pond(p: Vector2, margin: float) -> bool:
	var d := (p - _pond_centre) / (_pond_size + Vector2(margin, margin))
	return d.length_squared() <= 1.0


## `view` is the camera's world rect; everything outside is skipped. At the
## default zoom that is most of the arena, and it is what keeps a few hundred
## scattered items affordable on a phone.
func draw_into(canvas: CanvasItem, view: Rect2) -> void:
	_draw_ground(canvas)
	_draw_path(canvas, view)
	_draw_pond(canvas)
	_draw_scatter(canvas, view)
	_draw_hedges(canvas)


func _draw_ground(canvas: CanvasItem) -> void:
	if ground == null:
		return
	canvas.draw_texture_rect(ground, Rect2(bounds.position, bounds.size), true)


func _draw_path(canvas: CanvasItem, view: Rect2) -> void:
	for p: Vector2 in _path_points:
		if not view.has_point(p):
			continue
		canvas.draw_circle(p, 24.0, Palette.PATH_EDGE)
	for p: Vector2 in _path_points:
		if not view.has_point(p):
			continue
		canvas.draw_circle(p, 19.0, Palette.PATH)


func _draw_pond(canvas: CanvasItem) -> void:
	_draw_ellipse(canvas, _pond_centre, _pond_size + Vector2(10, 10), Palette.POND_SHALLOW)
	_draw_ellipse(canvas, _pond_centre, _pond_size, Palette.POND)
	_draw_ellipse(
		canvas,
		_pond_centre - _pond_size * 0.25,
		_pond_size * 0.35,
		Palette.POND_SHALLOW.lerp(Color.WHITE, 0.25)
	)


func _draw_scatter(canvas: CanvasItem, view: Rect2) -> void:
	var density := clampf(Tuning.get_value("decor_density"), 0.0, 1.0)

	var pebble_limit := int(_pebbles.size() * density)
	for i in pebble_limit:
		var e: Dictionary = _pebbles[i]
		if view.has_point(e["p"]):
			_draw_ellipse(canvas, e["p"], Vector2(e["r"], e["r"] * 0.7), e["c"])

	var tuft_limit := int(_tufts.size() * density)
	var blades := PackedVector2Array()
	var blade_cols := PackedColorArray()
	for i in tuft_limit:
		var e: Dictionary = _tufts[i]
		var p: Vector2 = e["p"]
		if not view.has_point(p):
			continue
		var h: float = e["h"]
		var lean: float = e["lean"]
		var col: Color = e["c"]
		blades.append(p)
		blades.append(p + Vector2(lean * h, -h))
		blades.append(p)
		blades.append(p + Vector2((lean - 0.34) * h, -h * 0.78))
		blades.append(p)
		blades.append(p + Vector2((lean + 0.34) * h, -h * 0.7))
		for _b in 3:
			blade_cols.append(col)
	if not blades.is_empty():
		canvas.draw_multiline_colors(blades, blade_cols, 1.7)

	var flower_limit := int(_flowers.size() * density)
	var stems := PackedVector2Array()
	var heads: Array[Dictionary] = []
	for i in flower_limit:
		var e: Dictionary = _flowers[i]
		var p: Vector2 = e["p"]
		if not view.has_point(p):
			continue
		stems.append(p)
		stems.append(p + Vector2(0, -6))
		heads.append(e)
	if not stems.is_empty():
		canvas.draw_multiline(stems, Palette.TUFT, 1.5)
	for e: Dictionary in heads:
		canvas.draw_circle(e["p"] + Vector2(0, -7.5), e["r"], e["c"])


## The arena edge as a hedge ring rather than a stroked rectangle: it reads as
## the boundary of a real place instead of a debug outline.
func _draw_hedges(canvas: CanvasItem) -> void:
	const T := 46.0
	var b := bounds
	var rects := [
		Rect2(b.position.x, b.position.y, b.size.x, T),
		Rect2(b.position.x, b.end.y - T, b.size.x, T),
		Rect2(b.position.x, b.position.y, T, b.size.y),
		Rect2(b.end.x - T, b.position.y, T, b.size.y),
	]
	for r: Rect2 in rects:
		canvas.draw_rect(r, Palette.HEDGE)

	# A lighter inner lip suggests the top of the hedge catching the light and
	# stops the border reading as a flat wall of colour.
	var inner := Rect2(b.position + Vector2(T, T), b.size - Vector2(T, T) * 2.0)
	canvas.draw_rect(inner, Palette.HEDGE_TOP, false, 6.0)


static func _draw_ellipse(canvas: CanvasItem, centre: Vector2, radii: Vector2, col: Color) -> void:
	const STEPS := 28
	var pts := PackedVector2Array()
	for i in STEPS:
		var a := TAU * float(i) / float(STEPS)
		pts.append(centre + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	canvas.draw_colored_polygon(pts, col)
