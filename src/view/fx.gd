class_name Fx
extends Node2D
## Pooled combat feedback: particles, damage numbers, impact rings, hitstop.
##
## Driven entirely by SimWorld's events, never by polling — the whole point of
## the event refactor. Nothing here touches simulation state, so removing this
## node changes how the game FEELS and nothing about how it BEHAVES.
##
## Everything is pooled with a hard cap, allocated once. FX peak exactly when
## the frame budget is tightest, and GDScript allocation churn shows up as a
## hitch at precisely the moment the effects exist to paper over.

const PARTICLE_CAP := 220
const NUMBER_CAP := 40
const RING_CAP := 24

var _particles: Array[Dictionary] = []
var _numbers: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

# Hitstop is applied by dipping Engine.time_scale, so the simulation, the
# animation and the camera all freeze together. Tracked as a real-time counter
# because a scaled counter would take longer to expire the harder it bit.
var _hitstop_left: float = 0.0


func _ready() -> void:
	_rng.randomize()
	z_index = 5

	for i in PARTICLE_CAP:
		_particles.append({"life": 0.0})
	for i in NUMBER_CAP:
		_numbers.append({"life": 0.0})
	for i in RING_CAP:
		_rings.append({"life": 0.0})


## Wire to a SimWorld. Kept as one call so a second world (a replay, a test)
## cannot half-connect and silently lose events.
func listen_to(world: SimWorld) -> void:
	world.hit.connect(_on_hit)
	world.killed.connect(_on_killed)
	world.fired.connect(_on_fired)


func _on_hit(pos: Vector2, dir: Vector2, damage: float, full_draw: bool) -> void:
	spawn_burst(pos, -dir, 10 if full_draw else 6, Palette.ARROW)
	spawn_ring(pos, 14.0, 52.0 if full_draw else 38.0)
	spawn_number(pos, damage, full_draw)
	hitstop(Tuning.get_value("hitstop_hit"))


func _on_killed(pos: Vector2, dir: Vector2, _scoring_team: int) -> void:
	spawn_burst(pos, -dir, 22, Palette.CAT_ENEMY)
	spawn_ring(pos, 20.0, 110.0)
	hitstop(Tuning.get_value("hitstop_kill"))


func _on_fired(pos: Vector2, dir: Vector2, draw_strength: float) -> void:
	# A brief flash at the bow, scaled by commitment: a snap shot should not
	# look like a fully drawn one.
	spawn_burst(pos, dir, int(lerpf(2.0, 7.0, draw_strength)), Palette.ARROW_TIP)


## Freezes everything briefly. The single largest perceived-impact effect
## available, and the reason a hit reads as an impact rather than a colour change.
func hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, seconds)


func spawn_burst(pos: Vector2, dir: Vector2, count: int, colour: Color) -> void:
	var spread := Tuning.get_value("particle_spread_deg")
	for i in count:
		var p := _free(_particles)
		if p.is_empty():
			return
		var angle := dir.angle() + deg_to_rad(_rng.randf_range(-spread, spread))
		var speed := _rng.randf_range(90.0, 420.0)
		p["pos"] = pos
		p["vel"] = Vector2.RIGHT.rotated(angle) * speed
		p["life"] = _rng.randf_range(0.26, 0.55)
		p["max_life"] = p["life"]
		p["col"] = colour
		p["len"] = _rng.randf_range(9.0, 20.0)


func spawn_ring(pos: Vector2, from_radius: float, to_radius: float) -> void:
	var r := _free(_rings)
	if r.is_empty():
		return
	r["pos"] = pos
	r["from"] = from_radius
	r["to"] = to_radius
	r["life"] = 0.26
	r["max_life"] = 0.26


func spawn_number(pos: Vector2, damage: float, full_draw: bool) -> void:
	var n := _free(_numbers)
	if n.is_empty():
		return
	n["pos"] = pos + Vector2(_rng.randf_range(-14.0, 14.0), -20.0)
	n["vel"] = Vector2(_rng.randf_range(-26.0, 26.0), -96.0)
	n["life"] = 0.8
	n["max_life"] = 0.8
	n["text"] = str(int(round(damage)))
	# Full-draw hits get their own colour and size so committing to the draw is
	# visibly rewarded, rather than being something the player has to be told.
	n["full"] = full_draw


## Returns an empty Dictionary when the pool is exhausted. Callers must test
## with is_empty() — comparing a Dictionary to null is always false, so a `null`
## check here would silently write effects into a throwaway object.
func _free(pool: Array[Dictionary]) -> Dictionary:
	for entry in pool:
		if entry["life"] <= 0.0:
			return entry
	return {}


func _process(delta: float) -> void:
	_tick_hitstop(delta)

	# Effects advance on SCALED time, so a hitstop freezes the particles along
	# with everything else. Letting them keep flying through the freeze defeats
	# the point: the whole effect is that the world stops for an instant.
	var dt := delta

	for p in _particles:
		if p["life"] <= 0.0:
			continue
		p["life"] -= dt
		p["pos"] += p["vel"] * dt
		p["vel"] *= 1.0 - minf(dt * 6.0, 1.0)

	for n in _numbers:
		if n["life"] <= 0.0:
			continue
		n["life"] -= dt
		n["pos"] += n["vel"] * dt
		n["vel"].y += 220.0 * dt

	for r in _rings:
		if r["life"] > 0.0:
			r["life"] -= dt

	queue_redraw()


func _tick_hitstop(delta: float) -> void:
	if _hitstop_left <= 0.0:
		return
	# delta arrives already scaled, so unscale it to count real seconds.
	_hitstop_left -= delta / maxf(Engine.time_scale, 0.0001)
	if _hitstop_left <= 0.0:
		_hitstop_left = 0.0
		Engine.time_scale = 1.0
	else:
		Engine.time_scale = Tuning.get_value("hitstop_scale")


func _draw() -> void:
	_draw_particles()
	_draw_rings()
	_draw_numbers()


func _draw_particles() -> void:
	# One batched call for every particle, the same trick the terrain scatter
	# uses. Individually these would be the most expensive thing on screen.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for p in _particles:
		if p["life"] <= 0.0:
			continue
		var fade: float = p["life"] / p["max_life"]
		var tail: Vector2 = p["pos"] - p["vel"].normalized() * p["len"]
		pts.append(tail)
		pts.append(p["pos"])
		var c: Color = p["col"]
		cols.append(Color(c.r, c.g, c.b, fade))
	if not pts.is_empty():
		draw_multiline_colors(pts, cols, 3.4)


func _draw_rings() -> void:
	for r in _rings:
		if r["life"] <= 0.0:
			continue
		var t: float = 1.0 - r["life"] / r["max_life"]
		var radius: float = lerpf(r["from"], r["to"], t)
		draw_arc(r["pos"], radius, 0.0, TAU, 24, Color(1, 1, 1, (1.0 - t) * 0.5), 2.5)


func _draw_numbers() -> void:
	var font := ThemeDB.fallback_font
	for n in _numbers:
		if n["life"] <= 0.0:
			continue
		var fade: float = clampf(n["life"] / n["max_life"] * 2.2, 0.0, 1.0)
		var full: bool = n["full"]
		var size := int(Tuning.get_value("number_size") * (1.35 if full else 1.0))
		var col := Palette.ARROW_TIP if full else Color.WHITE
		draw_string(
			font,
			n["pos"],
			n["text"],
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			size,
			Color(col.r, col.g, col.b, fade)
		)
