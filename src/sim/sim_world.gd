class_name SimWorld
extends RefCounted
## Owns the simulation and ticks it in a fixed order.
##
## Runs at a fixed 60 Hz from _physics_process. Nothing here reads Input or
## touches a node — the caller feeds it an InputCommand and reads state back
## out for rendering.

## Typed events, emitted at the MOMENT something happens.
##
## The view used to poll sim state each frame, which can express "is hurt" but
## never "was just hit, from that direction, for this much" — and every piece of
## feedback needs the latter. All damage funnels through apply_damage() so no
## code path can bypass these.
signal hit(position: Vector2, direction: Vector2, damage: float, full_draw: bool)
signal killed(position: Vector2, direction: Vector2)
signal fired(position: Vector2, direction: Vector2, draw_strength: float)
signal arrow_expired(position: Vector2)

const ARROW_POOL_SIZE := 150

var player := Actor.new()
var dummies: Array[Dummy] = []
var arrows: Array[Arrow] = []
var arena: Arena
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var _rng := RandomNumberGenerator.new()


## The arena defines the world, not the caller. Bounds used to be a constant in
## main.gd that SimWorld, Terrain and CameraRig each had to agree on by hand;
## now editing the arena text file resizes everything at once.
func _init(from_arena: Arena = null) -> void:
	arena = from_arena if from_arena != null else Arena.new()
	bounds = arena.bounds()
	_rng.randomize()

	arrows.resize(ARROW_POOL_SIZE)
	for i in ARROW_POOL_SIZE:
		arrows[i] = Arrow.new()

	_place_from_spawns()


## Spawn points come from the arena's `P` cells now, replacing the hardcoded
## ring. The ring existed only because there was no map; with one, placement is
## a level-design decision and belongs in the text file where it can be edited
## and reviewed without touching code.
##
## The player takes the spawn nearest the middle so the opening view is central,
## and targets take the rest, farthest-first so the arena reads as populated
## rather than crowded around one corner.
func _place_from_spawns() -> void:
	var points := arena.spawn_points()
	var centre := bounds.get_center()

	if points.is_empty():
		push_warning("Arena has no spawn points; falling back to centre")
		player.position = centre
		player.prev_position = centre
		return

	points.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return a.distance_squared_to(centre) < b.distance_squared_to(centre)
	)

	player.position = points[0]
	player.prev_position = player.position

	for i in range(1, points.size()):
		var d := Dummy.new()
		d.position = points[i]
		dummies.append(d)


func tick(cmd: InputCommand, delta: float) -> void:
	player.tick(cmd, delta, arena)

	for dummy in dummies:
		dummy.tick(delta)

	if cmd.fire:
		_try_fire(cmd)

	_tick_arrows(delta)


func _try_fire(cmd: InputCommand) -> void:
	if not player.bow.consume():
		return

	var dir := cmd.aim
	if cmd.snap:
		# The snap shot is the fast, weak, assisted option: it aims itself.
		var target := nearest_dummy(player.position, Tuning.get_value("autoaim_radius"))
		dir = (target.position - player.position).normalized() if target != null else player.facing
	if dir == Vector2.ZERO:
		dir = player.facing

	if not cmd.snap:
		dir = _apply_aim_assist(dir)

	dir = player.bow.apply_deviation(dir, cmd.draw_strength, _rng)

	var arrow := _free_arrow()
	if arrow == null:
		return

	var origin := player.position + dir * player.radius
	arrow.launch(
		origin,
		dir,
		player.bow.speed_for(cmd.draw_strength),
		player.bow.damage_for(cmd.draw_strength, cmd.snap),
		Tuning.get_value("arrow_lifetime")
	)
	# A snap shot is never a "full draw" however long the thumb happened to rest.
	arrow.full_draw = cmd.draw_strength >= 0.98 and not cmd.snap
	fired.emit(origin, dir, cmd.draw_strength)


## Optional magnetism on aimed shots. Defaults to zero: bending a shot the
## player aimed themselves erodes the whole point of committing to a draw. It
## exists as a slider so difficulty can be dialled in on the device rather than
## argued about here.
func _apply_aim_assist(dir: Vector2) -> Vector2:
	var max_angle := deg_to_rad(Tuning.get_value("aim_assist_deg"))
	if max_angle <= 0.0:
		return dir

	var target := nearest_dummy(player.position, Tuning.get_value("autoaim_radius"))
	if target == null:
		return dir

	var to_target := (target.position - player.position).normalized()
	var delta := dir.angle_to(to_target)
	if absf(delta) > max_angle:
		return dir
	return to_target


func _free_arrow() -> Arrow:
	for arrow in arrows:
		if not arrow.active:
			return arrow
	return null


func _tick_arrows(delta: float) -> void:
	for arrow in arrows:
		if not arrow.active:
			continue

		var was_active := arrow.active
		var from := arrow.position
		arrow.tick(delta, bounds)
		if not arrow.active:
			if was_active:
				arrow_expired.emit(arrow.position)
			continue

		# Walls are checked BEFORE targets, and the arrow's segment is shortened
		# to the impact point first — otherwise a target standing behind a wall
		# would still be hit by a shot that should have been stopped by it.
		var wall: Dictionary = arena.cast_segment(from, arrow.position)
		if wall["hit"]:
			arrow.position = wall["point"]

		for dummy in dummies:
			if not dummy.alive():
				continue
			if arrow.hits_circle(dummy.position, dummy.radius):
				apply_damage(dummy, arrow.damage, arrow.velocity.normalized(), arrow.full_draw)
				arrow.deactivate()
				break

		if arrow.active and wall["hit"]:
			arrow.deactivate()
			arrow_expired.emit(arrow.position)


## The single funnel for every point of damage in the game.
##
## Keeping this as the only entry point is what guarantees the view never misses
## a hit: there is no second path that damages something quietly.
func apply_damage(target: Dummy, amount: float, direction: Vector2, full_draw: bool) -> void:
	var applied := target.take_damage(amount)
	if applied <= 0.0:
		return

	target.apply_knockback(direction, Tuning.get_value("knockback_force"))
	hit.emit(target.position, direction, applied, full_draw)

	if target.health.died_this_tick:
		target.health.died_this_tick = false
		killed.emit(target.position, direction)


func nearest_dummy(from: Vector2, max_range: float) -> Dummy:
	var best: Dummy = null
	var best_dist := max_range * max_range

	for dummy in dummies:
		if not dummy.alive():
			continue
		var dist := from.distance_squared_to(dummy.position)
		if dist < best_dist:
			best_dist = dist
			best = dummy

	return best
