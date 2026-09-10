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

## True on the ticks this actor wants to put a bullet out.
##
## "On this tick", not "for as long as the trigger is held". The gun stopped
## being automatic: a thumb going DOWN aims and a thumb coming UP shoots, so the
## player sets this for exactly one tick per release. A bot sets it whenever it
## decides to shoot and lets Gun.consume()'s cooldown pace it. Both go through
## the same gun, which is what keeps a bot from out-shooting a person.
##
## The frame-rate trap ADR-0026 named is still avoided, by a different means:
## the input layer records an EDGE and the simulation consumes it at the tick
## boundary (TouchControls.take_fire), so one release is one bullet whatever the
## frame rate. What is gone is the automatic fire on top of it (ADR-0031).
var fire: bool = false

## Aim this shot for me, at whoever is nearest.
##
## Set by a TAP — a press and release that never carried a direction. It is the
## shot a five-year-old can land, and with one deliberate bullet per release it
## is no longer a way to spray (ADR-0013). A bot never sets it: bots aim.
var snap: bool = false

## True on the single tick an ability is triggered. Unused until M4.
var ability: bool = false


func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	fire = false
	snap = false
	ability = false
