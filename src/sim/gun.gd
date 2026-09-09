class_name Gun
extends RefCounted
## Magazine, reload and rate of fire. One shot, always the same shot.
##
## Deliberately free of nodes, rendering and input so it can be unit tested
## headless — which is the only verification available without a phone in hand.
##
## THIS REPLACED A BOW, and the reason is worth keeping. Draw strength — hold
## time driving speed, damage and deviation together — was the game's whole
## shooting mechanic, chosen because the gesture and the fiction were the same
## action. In the hand it read as a 450 ms delay in front of every shot, on a
## projectile slow enough that where it would land was guesswork:
##
##     "the Arrow shooting is sluggish and cant be expected,
##      lets change back to GUNS! with a clear line-of-fire"
##
## So the curve is gone rather than turned down. What it bought — a reason for
## one shot to differ from another — now has to come from class asymmetry in
## feat/classes, which is where Brawl Stars keeps it anyway. That debt is real
## and is named in ADR-0022.
##
## The rate limit lives HERE rather than in the input layer, so the player and
## the bots are gated by the same code. A bot cannot out-shoot you because it
## fires the same gun.

## Rounds available right now.
var magazine: int = 0

var _reload_accum: float = 0.0

## Seconds until this gun will fire again. Counted down in tick().
var _cooldown: float = 0.0


func _init() -> void:
	magazine = capacity()


func capacity() -> int:
	return int(Tuning.get_value("magazine_size"))


func speed() -> float:
	return Tuning.get_value("bullet_speed")


func damage() -> float:
	return Tuning.get_value("bullet_damage")


## How far a bullet gets before it expires. Pinned under the visible half-view
## by test_screen_budget.gd: if something can hit you, you can see it coming.
func reach() -> float:
	return speed() * Tuning.get_value("bullet_lifetime")


func can_fire() -> bool:
	return magazine > 0 and _cooldown <= 0.0


## Spends one round and starts the cooldown. Returns false and changes nothing
## when the magazine is empty or the gun is still between shots.
func consume() -> bool:
	if not can_fire():
		return false
	magazine -= 1
	_cooldown = Tuning.get_value("fire_interval")
	return true


## Call once per simulation tick.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_tick_reload(delta)


func _tick_reload(delta: float) -> void:
	var cap := capacity()
	if magazine >= cap:
		# Sitting at full must not bank progress toward an instant future reload.
		_reload_accum = 0.0
		return

	var reload_time := Tuning.get_value("reload_time")
	if reload_time <= 0.0:
		magazine = cap
		return

	_reload_accum += delta
	while _reload_accum >= reload_time and magazine < cap:
		_reload_accum -= reload_time
		magazine += 1

	if magazine >= cap:
		_reload_accum = 0.0
