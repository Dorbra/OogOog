class_name Hazard
extends RefCounted
## A patch of ground that hurts whoever stands in it.
##
## Caltrops, today. Pooled and reset rather than allocated per use, exactly like
## Bullet, for the reason in ADR-0009: GDScript allocation churn surfaces as
## frame hitches, and it surfaces during a fight, which is when the game can
## least afford one.
##
## Damage is dealt per SECOND, not per tick, and not once on entry. Once-on-entry
## rewards dancing in and out of the patch, which is fiddly on a touchscreen and
## invisible to a five-year-old; a rate makes standing in it simply a bad idea
## for as long as you do it.

var position: Vector2 = Vector2.ZERO
var radius: float = 0.0
var damage_per_second: float = 0.0
var life: float = 0.0
var active: bool = false

## Team of whoever dropped it, so it cannot hurt its own side. Carried here
## because the owner may be dead by the time somebody walks into it.
var owner_team: int = 0

## Instance id of the fighter that dropped it, for ability charge.
var owner_id: int = 0


func arm(
	at: Vector2, hazard_radius: float, dps: float, lifetime: float, team: int, dropper_id: int
) -> void:
	position = at
	radius = hazard_radius
	damage_per_second = dps
	life = lifetime
	owner_team = team
	owner_id = dropper_id
	active = true


func deactivate() -> void:
	active = false
	life = 0.0


func tick(delta: float) -> void:
	if not active:
		return
	life -= delta
	if life <= 0.0:
		active = false


## Is `at` inside the patch? Tested against the hazard's own radius plus the
## fighter's, so standing with a paw in it counts — the visible edge is the
## edge, which is the only version a player can reason about.
func covers(at: Vector2, body_radius: float) -> bool:
	if not active:
		return false
	var reach := radius + body_radius
	return position.distance_squared_to(at) <= reach * reach
