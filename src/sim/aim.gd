class_name Aim
extends RefCounted
## Where to point so a travelling projectile and a moving target arrive together.
##
## There is exactly one of these on purpose. The bots have had proper intercept
## prediction since `feat/bots`; the PLAYER's auto-aim did not, and both
## `SimWorld._try_fire()`'s snap branch and `_apply_aim_assist()` aimed at the
## target's CURRENT position. At a 250 px/s walk against a 780 px/s arrow that
## can only connect inside 90 px, while `autoaim_radius` was 235 — so past a
## third of its own radius the assist did not merely fail to help, it took a shot
## the player had led correctly and bent it back onto a miss.
##
## Two implementations of one idea, one of them wrong, is how that happened. This
## is the single implementation, and every producer of an InputCommand calls it.


## Unit vector from `from` toward where `target_pos` will be when a projectile at
## `projectile_speed` gets there.
##
## `lead` scales the prediction: 1.0 aims at the intercept, 0.0 reproduces the
## old aim-at-where-it-is-now behaviour exactly. That is what lets the bot
## difficulty slider dial leading in gradually AND makes the extraction from
## BotController provably behaviour-preserving.
##
## Two passes. The first estimate uses the target's current distance, which is
## wrong the moment it is moving; feeding that flight time back in once converges
## closely enough for a 60 Hz simulation. A closed-form solve is possible and not
## worth the reading cost for a difference nobody could see.
##
## `fallback` is returned when the answer is degenerate — a target standing on
## top of the shooter — because a zero vector fired as a direction sends the
## arrow nowhere.
static func intercept(
	from: Vector2,
	projectile_speed: float,
	target_pos: Vector2,
	target_vel: Vector2,
	lead: float,
	fallback: Vector2 = Vector2.RIGHT
) -> Vector2:
	var speed := maxf(projectile_speed, 1.0)
	var predicted := target_pos
	var flight := from.distance_to(target_pos) / speed

	for _pass in 2:
		predicted = target_pos + target_vel * flight * lead
		flight = from.distance_to(predicted) / speed

	var dir := predicted - from
	if dir.length_squared() < 0.0001:
		return fallback
	return dir.normalized()
