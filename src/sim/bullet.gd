class_name Bullet
extends RefCounted
## A travelling projectile.
##
## Bullets travel rather than hitscan even now that they are fast: a shot can be
## dodged, the flight is readable on a small screen, and it keeps the door open
## for LAN later, where hitscan across latency is miserable. At 1400 px/s the
## flight is 165 ms to maximum range, which is short enough that where the shot
## lands is something you can read rather than predict.
##
## Pooled — never freed and reallocated mid-match. GDScript allocation churn
## surfaces as frame hitches, and retrofitting pooling later is tedious.

var position: Vector2 = Vector2.ZERO
var prev_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var life: float = 0.0
var active: bool = false

## Team of whoever fired it. Carried on the projectile because at the moment of
## impact the shooter may already be dead, and a bullet in flight has to keep
## knowing whose it was. This is what makes friendly fire rejectable.
var owner_team: int = 0


func launch(
	from: Vector2, dir: Vector2, speed: float, dmg: float, lifetime: float, team: int = 0
) -> void:
	owner_team = team
	position = from
	prev_position = from
	velocity = dir * speed
	damage = dmg
	life = lifetime
	active = true


func tick(delta: float, bounds: Rect2) -> void:
	if not active:
		return

	prev_position = position
	position += velocity * delta
	life -= delta

	if life <= 0.0 or not bounds.has_point(position):
		active = false


func deactivate() -> void:
	active = false


func render_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, clampf(alpha, 0.0, 1.0))


## Swept collision test against a circle.
##
## A fast bullet crosses a whole target between two ticks — at 1400 px/s that is
## 23 px per tick against a 58 px cat — so testing only the end point would let
## shots pass straight through. This tests the segment travelled.
func hits_circle(centre: Vector2, radius: float) -> bool:
	var segment := position - prev_position
	var to_centre := centre - prev_position

	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return to_centre.length_squared() <= radius * radius

	var t := clampf(to_centre.dot(segment) / length_sq, 0.0, 1.0)
	var closest := prev_position + segment * t
	return closest.distance_squared_to(centre) <= radius * radius
