class_name Arrow
extends RefCounted
## A travelling projectile.
##
## Arrows travel rather than hitscan: you have to lead a moving target, shots
## can be dodged, and the flight is readable on a small screen. It also keeps
## the door open for LAN later, where hitscan across latency is miserable.
##
## Pooled — never freed and reallocated mid-match. GDScript allocation churn
## surfaces as frame hitches, and retrofitting pooling later is tedious.

var position: Vector2 = Vector2.ZERO
var prev_position: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var damage: float = 0.0
var life: float = 0.0
var active: bool = false


func launch(from: Vector2, dir: Vector2, speed: float, dmg: float, lifetime: float) -> void:
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
## A fast arrow can cross a whole target between two ticks, so testing only the
## end point would let shots pass through. This tests the segment travelled.
func hits_circle(centre: Vector2, radius: float) -> bool:
	var segment := position - prev_position
	var to_centre := centre - prev_position

	var length_sq := segment.length_squared()
	if length_sq <= 0.0001:
		return to_centre.length_squared() <= radius * radius

	var t := clampf(to_centre.dot(segment) / length_sq, 0.0, 1.0)
	var closest := prev_position + segment * t
	return closest.distance_squared_to(centre) <= radius * radius
