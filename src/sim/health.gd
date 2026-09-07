class_name Health
extends RefCounted
## Hit points, damage, death, and out-of-combat regeneration.
##
## Split out of Dummy so the player and (next milestone) bots share one
## implementation. Every combatant needs identical hit and death semantics, and
## writing this twice is how the two quietly drift apart — a bot that dies at
## -1 HP while the player dies at 0 is the kind of bug nobody finds by reading.
##
## Regeneration follows the Brawl Stars / CoD model settled in the design: a
## dead period after taking damage, then a fast heal. The gate is deliberately
## time-since-damage rather than a boolean "in combat" flag, because the flag
## version always ends up with a path that forgets to clear it.

var maximum: float = 100.0
var current: float = 100.0

## Seconds since the last damage taken. Starts high so a freshly spawned
## combatant is not treated as having just been hit.
var since_damage: float = 999.0

## Counts down after a hit purely so the view can flash. Not gameplay.
var hit_flash: float = 0.0

## Set on the tick death occurs and cleared once observed, so the kill event
## fires exactly once rather than every tick the entity is dead.
var died_this_tick: bool = false


func _init(max_hp: float = 100.0) -> void:
	maximum = max_hp
	current = max_hp


func alive() -> bool:
	return current > 0.0


func fraction() -> float:
	return clampf(current / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0


## Returns the damage actually applied, which is less than `amount` on the blow
## that kills — the view uses it so a 40-damage hit on a 5 HP target doesn't
## claim 40.
func take_damage(amount: float) -> float:
	if not alive() or amount <= 0.0:
		return 0.0

	var applied := minf(amount, current)
	current -= applied
	since_damage = 0.0
	hit_flash = 1.0

	if not alive():
		died_this_tick = true
	return applied


func revive() -> void:
	current = maximum
	since_damage = 999.0
	hit_flash = 0.0
	died_this_tick = false


func tick(delta: float) -> void:
	hit_flash = maxf(hit_flash - delta / 0.15, 0.0)
	if not alive():
		return

	since_damage += delta
	if since_damage < Tuning.get_value("regen_delay"):
		return

	# regen_rate_pct is percent of MAX health per second, so time-to-full does
	# not depend on how big the health pool happens to be.
	var per_second := maximum * (Tuning.get_value("regen_rate_pct") / 100.0)
	current = minf(current + per_second * delta, maximum)
