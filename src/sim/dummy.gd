class_name Dummy
extends RefCounted
## A practice target.
##
## Health lives in a shared Health component rather than here, so the player and
## the bots arriving next milestone get identical hit and death semantics for
## free. Movement is the only thing a Dummy still lacks compared to an Actor.

var position: Vector2 = Vector2.ZERO
var radius: float = 42.0
var health := Health.new()

## Knockback velocity, decaying to rest. Arrows shove targets so they feel like
## they carry mass rather than passing through.
var velocity: Vector2 = Vector2.ZERO

var respawn_timer: float = 0.0


func alive() -> bool:
	return health.alive()


func take_damage(amount: float) -> float:
	var applied := health.take_damage(amount)
	if not health.alive():
		respawn_timer = Tuning.get_value("dummy_respawn_time")
	return applied


func apply_knockback(dir: Vector2, force: float) -> void:
	velocity += dir * force


func tick(delta: float) -> void:
	radius = Tuning.get_value("dummy_radius")
	health.tick(delta)

	# Knockback decays even while dead, so a killing blow still visibly shoves
	# the target rather than freezing it mid-air.
	var drop := Tuning.get_value("knockback_damping") * delta
	if velocity.length() <= drop:
		velocity = Vector2.ZERO
	else:
		velocity -= velocity.normalized() * drop
	position += velocity * delta

	if health.alive():
		return

	respawn_timer -= delta
	if respawn_timer <= 0.0:
		health.revive()
		velocity = Vector2.ZERO
