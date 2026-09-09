class_name Fighter
extends RefCounted
## One combatant. The player, a bot, and (from M3.3) a remote player are all
## this — the only difference is who produces the InputCommand.
##
## This is the payoff of the sim/view split (ADR-0003). `Actor` and `Dummy` used
## to be separate types with separate movement, separate damage handling and
## separate respawn logic, which meant every combat feature had to be written
## twice and the two halves quietly drifted. A bot that died at -1 HP while the
## player died at 0 is the kind of bug nobody finds by reading.
##
## A Fighter fed an EMPTY InputCommand stands perfectly still and does nothing,
## which is exactly what the old practice dummy was. So the dummy did not need
## deleting so much as recognising: it was always a fighter with nobody at the
## controls.

## Which side this fighter is on. Friendly fire is rejected on this, and it
## decides the tint the view draws.
var team: int = 0

var position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var radius: float = 34.0

## Previous tick's position, so the view can interpolate between fixed ticks
## instead of rendering the simulation's 60 Hz staircase.
var prev_position: Vector2 = Vector2.ZERO

## Where this fighter returns to on respawn. Assigned from the arena's spawn
## cells, so respawning never drops anyone inside a wall.
var spawn_point: Vector2 = Vector2.ZERO

var health := Health.new()
var gun := Gun.new()

## Produces this fighter's InputCommand each tick. Null means nobody is driving,
## and the fighter stands still — which is both the practice-dummy behaviour and
## the deterministic mode the screenshot tool needs.
var controller: Variant = null

var respawn_timer: float = 0.0

## Counts down after firing. While it is above zero this fighter is visible even
## from inside a bush: loosing an arrow gives your position away, which is what
## stops an ambusher from sitting in cover killing people with impunity.
## SimWorld.can_see() is the only reader.
var reveal_timer: float = 0.0


func alive() -> bool:
	return health.alive()


func tick(cmd: InputCommand, delta: float, arena: Arena) -> void:
	prev_position = position
	radius = Tuning.get_value("fighter_radius")
	health.set_maximum(Tuning.get_value("fighter_health"))
	health.tick(delta)
	# Ahead of the death check on purpose: a corpse should stop being "revealed"
	# rather than respawning still lit up from its last shot.
	reveal_timer = maxf(0.0, reveal_timer - delta)

	if not alive():
		_tick_dead(delta)
		return

	gun.tick(delta)
	_apply_movement(cmd.move, delta)
	_integrate(delta, arena)

	if cmd.aim != Vector2.ZERO:
		facing = cmd.aim
	elif velocity.length_squared() > 1.0:
		facing = velocity.normalized()


## Knockback keeps decaying while dead, so a killing blow visibly shoves the
## body rather than freezing it mid-air.
func _tick_dead(delta: float) -> void:
	_decay_knockback(delta)
	position += velocity * delta

	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn()


func respawn() -> void:
	health.revive()
	velocity = Vector2.ZERO
	position = spawn_point
	prev_position = spawn_point
	reveal_timer = 0.0
	gun = Gun.new()


func take_damage(amount: float) -> float:
	var applied := health.take_damage(amount)
	if not health.alive():
		respawn_timer = Tuning.get_value("respawn_time")
	return applied


func apply_knockback(dir: Vector2, force: float) -> void:
	velocity += dir * force


## Interpolated position for rendering. `alpha` is the fraction between the
## previous tick and this one.
func render_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))


func _apply_movement(move: Vector2, delta: float) -> void:
	if move == Vector2.ZERO:
		_decay_knockback(delta)
		return

	var target := move * Tuning.get_value("move_speed")
	var accel := Tuning.get_value("move_accel") * delta
	velocity = velocity.move_toward(target, accel)


## Friction toward rest, without overshooting into a jitter. Also what decays
## knockback, since both are "no input, bleed off speed".
func _decay_knockback(delta: float) -> void:
	var drop := Tuning.get_value("move_friction") * delta
	if velocity.length() <= drop:
		velocity = Vector2.ZERO
	else:
		velocity -= velocity.normalized() * drop


func _integrate(delta: float, arena: Arena) -> void:
	position += velocity * delta

	# Walls, not just the arena rectangle. Border cells are solid, so this
	# subsumes the old bounds clamp rather than needing both.
	var resolved := arena.resolve_circle(position, radius)
	if not resolved.is_equal_approx(position):
		# Kill the velocity component pushing into the wall, otherwise the
		# fighter keeps accelerating into it and slides along at full speed the
		# moment the input releases.
		var normal := (resolved - position).normalized()
		velocity -= normal * minf(velocity.dot(normal), 0.0)
		position = resolved
