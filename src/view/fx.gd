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

## The world this node is listening to, so an event's position can be compared
## against the local player's. Read-only from here: nothing in Fx may change
## simulation state.
var _world: SimWorld = null

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
	_world = world
	world.hit.connect(_on_hit)
	world.killed.connect(_on_killed)
	world.fired.connect(_on_fired)


## True when this happened to the LOCAL PLAYER rather than somewhere else.
##
## Hitstop dips Engine.time_scale GLOBALLY, and this node used to do it for every
## hit in the match. With six fighters that meant the whole game micro-froze
## roughly once a second because two bots traded shots somewhere off screen —
## the single worst contributor to the game not feeling steady, and invisible
## because the cause was never on screen.
func _concerns_player(pos: Vector2) -> bool:
	if _world == null:
		return false
	var near := Tuning.get_value("fighter_radius") * 1.5
	return pos.distance_squared_to(_world.player.position) <= near * near


## Roughly "is this within the camera's view", used to skip effects nobody can
## see. Generous on purpose: culling a particle that WOULD have been visible is
## a worse failure than spawning one that is not, so this errs outward.
func _on_screen(pos: Vector2) -> bool:
	# get_viewport_rect() needs a viewport, which a node built outside the scene
	# tree — as the headless tests do — does not have.
	if _world == null or not is_inside_tree():
		return true
	var zoom := maxf(Tuning.get_value("camera_zoom"), 0.01)
	var half := get_viewport_rect().size / zoom * 0.5 + Vector2(140.0, 140.0)
	var delta := (pos - _world.player.position).abs()
	return delta.x <= half.x and delta.y <= half.y


## Every hit looks the same now, because every hit IS the same.
##
## The burst and the ring used to come in two sizes, scaled by whether the shot
## was a committed full draw — visibly rewarding the draw rather than making the
## player take it on trust. With the draw curve gone there is nothing left to
## reward, and keeping two sizes would mean picking one arbitrarily and dressing
## it up as meaning.
func _on_hit(pos: Vector2, dir: Vector2, damage: float) -> void:
	if _on_screen(pos):
		spawn_burst(pos, -dir, 8, Palette.ARROW)
		spawn_ring(pos, 14.0, 45.0)
		spawn_number(pos, damage)
	if _concerns_player(pos):
		hitstop(Tuning.get_value("hitstop_hit"))


func _on_killed(pos: Vector2, dir: Vector2, _scoring_team: int) -> void:
	if _on_screen(pos):
		spawn_burst(pos, -dir, 22, Palette.CAT_ENEMY)
		spawn_ring(pos, 20.0, 110.0)
	if _concerns_player(pos):
		hitstop(Tuning.get_value("hitstop_kill"))


func _on_fired(pos: Vector2, dir: Vector2) -> void:
	# A brief muzzle flash. One size, for the same reason as _on_hit().
	if not _on_screen(pos):
		return
	spawn_burst(pos, dir, 5, Palette.ARROW_TIP)


## Freezes everything briefly. The single largest perceived-impact effect
## available, and the reason a hit reads as an impact rather than a colour change.
func hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_hitstop_left = maxf(_hitstop_left, seconds)


## Remaining hitstop, for tests. "The game did not freeze for somebody else's
## fight" is the assertion this exists to make.
func hitstop_left() -> float:
	return _hitstop_left


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


func spawn_number(pos: Vector2, damage: float) -> void:
	var n := _free(_numbers)
	if n.is_empty():
		return
	n["pos"] = pos + Vector2(_rng.randf_range(-14.0, 14.0), -20.0)
	n["vel"] = Vector2(_rng.randf_range(-26.0, 26.0), -96.0)
	n["life"] = 0.8
	n["max_life"] = 0.8
	n["text"] = str(int(round(damage)))


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
		var size := int(Tuning.get_value("number_size"))
		var col := Color.WHITE
		draw_string(
			font,
			n["pos"],
			n["text"],
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			size,
			Color(col.r, col.g, col.b, fade)
		)
