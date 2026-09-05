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


func _place_dummies() -> void:
	# Spread across the arena at different ranges, so close-quarters snap shots
	# and long committed draws can both be practised.
	var spots := [
		Vector2(0.22, 0.25),
		Vector2(0.78, 0.25),
		Vector2(0.5, 0.15),
		Vector2(0.22, 0.78),
		Vector2(0.78, 0.78),
	]
	for spot: Vector2 in spots:
		var d := Dummy.new()
		d.position = bounds.position + bounds.size * spot
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
