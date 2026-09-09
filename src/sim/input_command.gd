class_name InputCommand
extends RefCounted
## One tick of intent for one actor.
##
## This is the seam that makes everything else possible. The simulation reads
## ONLY this — never Input, never a touchscreen, never a node. Today the
## producers are the player's thumbs and (from M3) bot AI; if same-WiFi
## multiplayer ever happens, the network becomes a third producer and the
## simulation does not change at all.

## Fixed-timestep tick this command belongs to.
var tick: int = 0

## Desired movement direction, normalised (or zero).
var move: Vector2 = Vector2.ZERO

## Desired aim direction, normalised (or zero when not aiming).
var aim: Vector2 = Vector2.ZERO

## True on the single tick a shot is fired.
##
## There is no longer a power axis alongside it. Draw strength lived here until
## the charge-up it represented turned out to BE the sluggishness — every shot
## is now the same shot, and what varies between them will come from the class
## you picked rather than how long you held your thumb down (ADR-0022).
var fire: bool = false

## True when the shot was a tap rather than an aimed drag: auto-aimed, and it
## leads the target. No damage penalty — it is what a five-year-old uses.
## Meaningful only on the tick `fire` is true.
var snap: bool = false

## True on the single tick an ability is triggered. Unused until M4.
var ability: bool = false


func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	fire = false
	snap = false
	ability = false
