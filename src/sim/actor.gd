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


func tick(cmd: InputCommand, delta: float, arena: Arena) -> void:
	prev_position = position
	radius = Tuning.get_value("player_radius")
	bow.tick(delta)
	_apply_movement(cmd.move, delta)
	_integrate(delta, arena)

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


func _integrate(delta: float, arena: Arena) -> void:
	position += velocity * delta

	# Walls, not just the arena rectangle. The border cells are solid, so this
	# subsumes the old bounds clamp rather than needing both.
	var resolved := arena.resolve_circle(position, radius)
	if not resolved.is_equal_approx(position):
		# Kill the velocity component pushing into the wall, otherwise the actor
		# keeps accelerating into it and slides along at full speed on release.
		var normal := (resolved - position).normalized()
		velocity -= normal * minf(velocity.dot(normal), 0.0)
		position = resolved


## Interpolated position for rendering. `alpha` is the fraction between the
## previous and current tick.
func render_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))
