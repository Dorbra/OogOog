class_name Dummy
extends RefCounted
## A stationary practice target.
##
## Exists so M1 can answer "does drawing and loosing feel good?" — aiming at
## empty space tells you nothing. Deliberately static: moving targets are M3's
## job, along with the bot AI that drives them.

const MAX_HEALTH := 100.0

var position: Vector2 = Vector2.ZERO
var radius: float = 28.0
var health: float = MAX_HEALTH

## Counts down after a hit, purely so the view can flash. Not gameplay.
var hit_flash: float = 0.0

## Seconds remaining before a destroyed dummy comes back, so practice never
## runs out of things to shoot.
var respawn_timer: float = 0.0


func alive() -> bool:
	return health > 0.0


func take_damage(amount: float) -> void:
	if not alive():
		return
	health = maxf(health - amount, 0.0)
	hit_flash = 0.15
	if not alive():
		respawn_timer = Tuning.get_value("dummy_respawn_time")


func tick(delta: float) -> void:
	hit_flash = maxf(hit_flash - delta, 0.0)
	if alive():
		return

	respawn_timer -= delta
	if respawn_timer <= 0.0:
		health = MAX_HEALTH
