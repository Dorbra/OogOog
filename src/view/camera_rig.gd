class_name CameraRig
extends Camera2D
## Follows the player, clamps to the arena, and shakes.
##
## Extracted from main.gd, which had grown into a god object doing camera, HUD,
## rendering and input plumbing at once.

var world_size: Vector2 = Vector2(2400, 1350)
var target_position: Vector2 = Vector2.ZERO

## Trauma rather than a raw shake amount. Shake is trauma SQUARED, so small hits
## barely register while a kill is unmistakable, and repeated hits accumulate
## instead of restarting a fixed-length animation.
var _trauma: float = 0.0
var _shake_offset: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# Smoothing is done by hand so it can be a tuning slider.
	position_smoothing_enabled = false


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Current trauma, for tests. Read-only: "the camera is steady" is an assertion
## worth being able to make, and it is the one nobody could make before.
func trauma() -> float:
	return _trauma


## True when something happened to the LOCAL PLAYER rather than somewhere else
## in the match.
##
## `target_position` is the player's position, kept current by main.gd, and every
## sim event carries the position it happened at — so no signal needs to grow a
## field for this.
##
## This check is the whole fix for "the screen doesn't stop shaking". SimWorld
## emits hit/killed/fired for EVERY fighter anywhere on the map, and this node
## used to add trauma for all of them. With six fighters, trauma arrived at about
## 0.72/s against a decay of 1.9/s, so it settled at a permanent ~4 px jitter that
## never reached zero — punctuated by hard shakes from kills happening off screen,
## which look like the game glitching rather than like feedback.
func _concerns_player(event_position: Vector2) -> bool:
	var near := Tuning.get_value("fighter_radius") * 1.5
	return event_position.distance_squared_to(target_position) <= near * near


func listen_to(world: SimWorld) -> void:
	world.hit.connect(
		func(p: Vector2, _d: Vector2, _dmg: float) -> void:
			if _concerns_player(p):
				add_trauma(Tuning.get_value("shake_hit"))
	)
	world.killed.connect(
		func(p: Vector2, _d: Vector2, _team: int) -> void:
			if _concerns_player(p):
				add_trauma(Tuning.get_value("shake_kill"))
	)
	# Firing shakes nothing by default (`shake_fire` is 0). Your own gun
	# moving the camera is not something the reference game does, and at five
	# shots a second it was the largest single contributor to the jitter.
	world.fired.connect(
		func(p: Vector2, _d: Vector2) -> void:
			if _concerns_player(p):
				add_trauma(Tuning.get_value("shake_fire"))
	)


func follow(delta: float, viewport_size: Vector2) -> void:
	var z := maxf(Tuning.get_value("camera_zoom"), 0.01)
	zoom = Vector2(z, z)

	# Keep the camera inside the arena so the player never stares at dead space
	# past the hedge. Half-extents shrink as zoom rises.
	var half := viewport_size * 0.5 / z
	var goal := target_position
	if world_size.x > half.x * 2.0:
		goal.x = clampf(goal.x, half.x, world_size.x - half.x)
	else:
		goal.x = world_size.x * 0.5
	if world_size.y > half.y * 2.0:
		goal.y = clampf(goal.y, half.y, world_size.y - half.y)
	else:
		goal.y = world_size.y * 0.5

	# Unscaled delta: during hitstop the camera should hold still with the world
	# rather than crawl toward its target in slow motion.
	var dt := delta / maxf(Engine.time_scale, 0.0001)
	var weight := 1.0 - exp(-Tuning.get_value("camera_smoothing") * dt)
	var base := position - _shake_offset
	base = base.lerp(goal, weight)

	_trauma = maxf(_trauma - Tuning.get_value("shake_decay") * dt, 0.0)
	var magnitude := _trauma * _trauma * Tuning.get_value("shake_max_offset")
	_shake_offset = Vector2(
		_rng.randf_range(-magnitude, magnitude), _rng.randf_range(-magnitude, magnitude)
	)
	position = base + _shake_offset


## The camera's world rect, for culling. Padded so props do not pop in at the edge.
func view_rect(viewport_size: Vector2) -> Rect2:
	var z := maxf(Tuning.get_value("camera_zoom"), 0.01)
	var size := viewport_size / z
	return Rect2(position - size * 0.5, size).grow(140.0)
