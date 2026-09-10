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

## True on every tick this actor is holding the trigger down.
##
## Not an event any more. The gun went automatic, so this is a STATE that stays
## true for as long as a thumb (or a bot's decision) is on the trigger, and
## Gun.consume()'s cooldown decides which of those ticks actually produce a
## bullet. Nothing here says how hard or how well — the power axis went with the
## draw curve (ADR-0022) and the tap variant went with automatic fire.
var fire: bool = false

## True on the single tick an ability is triggered. Unused until M4.
var ability: bool = false


func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	fire = false
	ability = false
