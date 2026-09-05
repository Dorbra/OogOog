class_name Actor
extends RefCounted
## A moving fighter in the simulation. No node, no sprite, no input.
##
## Driven purely by an InputCommand each tick, so the same code runs the player,
## a bot, and (if LAN ever happens) a remote player.

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var radius: float = 24.0
var alive: bool = true

# Previous tick's position, so the view can interpolate between fixed ticks
# instead of rendering at the simulation's 60 Hz staircase.
var prev_position: Vector2 = Vector2.ZERO

var bow := Bow.new()


func tick(cmd: InputCommand, delta: float, bounds: Rect2) -> void:
	prev_position = position
	bow.tick(delta)
	_apply_movement(cmd.move, delta)
	_integrate(delta, bounds)

	if cmd.aim != Vector2.ZERO:
		facing = cmd.aim
	elif velocity.length_squared() > 1.0:
		facing = velocity.normalized()


func _apply_movement(move: Vector2, delta: float) -> void:
	var max_speed := Tuning.get_value("move_speed")

	if move == Vector2.ZERO:
		# Friction toward rest, without overshooting into a jitter.
		var drop := Tuning.get_value("move_friction") * delta
		if velocity.length() <= drop:
			velocity = Vector2.ZERO
		else:
			velocity -= velocity.normalized() * drop
		return

	var target := move * max_speed
	var accel := Tuning.get_value("move_accel") * delta
	velocity = velocity.move_toward(target, accel)


func _integrate(delta: float, bounds: Rect2) -> void:
	position += velocity * delta
	position.x = clampf(position.x, bounds.position.x + radius, bounds.end.x - radius)
	position.y = clampf(position.y, bounds.position.y + radius, bounds.end.y - radius)


## Interpolated position for rendering. `alpha` is the fraction between the
## previous and current tick.
func render_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))
