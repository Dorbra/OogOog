class_name Bow
extends RefCounted
## Bow state and the draw-strength curves.
##
## Deliberately free of nodes, rendering and input so it can be unit tested
## headless — which is the only verification available without a phone in hand.
##
## Design: draw strength replaces the spread/recoil/accuracy-cone stack a gun
## would need. One number, set by how long you hold, drives speed, damage and
## deviation together. That reads instantly on a small screen, and it makes the
## fiction and the control gesture the same action.

## Arrows currently available to fire.
var quiver: int = 0

var _refill_accum: float = 0.0


func _init() -> void:
	quiver = capacity()


func capacity() -> int:
	return int(Tuning.get_value("quiver_size"))


func can_fire() -> bool:
	return quiver > 0


## Consumes one arrow. Returns false (and changes nothing) if the quiver is empty.
func consume() -> bool:
	if quiver <= 0:
		return false
	quiver -= 1
	return true


## Refills the quiver over time. Call once per simulation tick.
func tick(delta: float) -> void:
	var cap := capacity()
	if quiver >= cap:
		# Sitting at full must not bank progress toward an instant future refill.
		_refill_accum = 0.0
		return

	var refill_time := Tuning.get_value("quiver_refill_time")
	if refill_time <= 0.0:
		quiver = cap
		return

	_refill_accum += delta
	while _refill_accum >= refill_time and quiver < cap:
		_refill_accum -= refill_time
		quiver += 1

	if quiver >= cap:
		_refill_accum = 0.0


func speed_for(draw: float) -> float:
	return lerpf(
		Tuning.get_value("draw_min_speed"),
		Tuning.get_value("draw_max_speed"),
		clampf(draw, 0.0, 1.0)
	)


func damage_for(draw: float, snap: bool) -> float:
	var base := lerpf(
		Tuning.get_value("draw_min_damage"),
		Tuning.get_value("draw_max_damage"),
		clampf(draw, 0.0, 1.0)
	)
	return base * (Tuning.get_value("snap_damage_mult") if snap else 1.0)


## Maximum angular error in radians. Full draw is dead straight; a rushed shot
## sprays. This is what makes committing to a draw worth the risk.
func deviation_for(draw: float) -> float:
	return deg_to_rad(Tuning.get_value("draw_max_deviation_deg")) * (1.0 - clampf(draw, 0.0, 1.0))


## Applies random deviation to an aim direction. The RNG is passed in so tests
## can seed it and assert exact outcomes.
func apply_deviation(dir: Vector2, draw: float, rng: RandomNumberGenerator) -> Vector2:
	var spread := deviation_for(draw)
	if spread <= 0.0:
		return dir
	return dir.rotated(rng.randf_range(-spread, spread))
