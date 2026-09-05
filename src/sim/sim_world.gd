class_name SimWorld
extends RefCounted
## Owns the simulation and ticks it in a fixed order.
##
## Runs at a fixed 60 Hz from _physics_process. Nothing here reads Input or
## touches a node — the caller feeds it an InputCommand and reads state back
## out for rendering.

signal dummy_hit(position: Vector2, damage: float)
signal arrow_fired

const ARROW_POOL_SIZE := 150

var player := Actor.new()
var dummies: Array[Dummy] = []
var arrows: Array[Arrow] = []
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var _rng := RandomNumberGenerator.new()


func _init(world_bounds: Rect2 = Rect2(0, 0, 1280, 720)) -> void:
	bounds = world_bounds
	_rng.randomize()
	player.position = bounds.get_center()
	player.prev_position = player.position

	arrows.resize(ARROW_POOL_SIZE)
	for i in ARROW_POOL_SIZE:
		arrows[i] = Arrow.new()

	_place_dummies()


## Targets sit in a ring around the spawn rather than spread across the arena.
##
## Spreading them by arena fraction put every one of them outside the camera
## once zoom arrived — the world is much larger than the visible area now, so
## fractions of the world are the wrong unit entirely. Ring radii are in world
## units and alternate near/far so both close snap shots and committed
## long-range draws can be practised, with some targets always on screen.
func _place_dummies() -> void:
	const RADII := [210.0, 350.0, 210.0, 350.0, 260.0]
	var centre := bounds.get_center()

	for i in RADII.size():
		var angle := TAU * float(i) / float(RADII.size()) - PI * 0.5
		var d := Dummy.new()
		d.position = centre + Vector2.RIGHT.rotated(angle) * RADII[i]
		dummies.append(d)


func tick(cmd: InputCommand, delta: float) -> void:
	player.tick(cmd, delta, bounds)

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

	arrow.launch(
		player.position + dir * player.radius,
		dir,
		player.bow.speed_for(cmd.draw_strength),
		player.bow.damage_for(cmd.draw_strength, cmd.snap),
		Tuning.get_value("arrow_lifetime")
	)
	arrow_fired.emit()


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

		arrow.tick(delta, bounds)
		if not arrow.active:
			continue

		for dummy in dummies:
			if not dummy.alive():
				continue
			if arrow.hits_circle(dummy.position, dummy.radius):
				dummy.take_damage(arrow.damage)
				dummy_hit.emit(dummy.position, arrow.damage)
				arrow.deactivate()
				break


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
