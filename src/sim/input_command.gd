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

## How far the bow is drawn this tick, 0..1. Power, not direction.
var draw_strength: float = 0.0

## True on the single tick the shot is released.
var fire: bool = false

## True when the release was a snap shot (little drag, little hold): weak, but
## auto-aimed. Meaningful only on the tick `fire` is true.
var snap: bool = false

## True on the single tick an ability is triggered. Unused until M4.
var ability: bool = false


func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	draw_strength = 0.0
	fire = false
	snap = false
	ability = false
