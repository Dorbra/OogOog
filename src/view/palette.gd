class_name Palette
extends RefCounted
## Every colour in the game, in one place.
##
## High contrast here is a gameplay requirement, not a taste preference: this is
## played on a ~6" screen, often in daylight. Arrows and cats have to stay
## readable against the ground at a glance, so the grass stays mid-to-dark green
## and everything gameplay-relevant is warm and bright against it.

# Ground — the noise ramp runs between these.
const GRASS_DARK := Color("2f6330")
const GRASS_MID := Color("3f7d3a")
const GRASS_LIGHT := Color("5aa34f")

# Terrain features.
#
# Walls and bushes MUST NOT share a colour. The two behave completely
# differently — a wall stops arrows, a bush only breaks line of sight — and a
# player has to tell them apart at a glance, mid-fight, on a phone. Stone versus
# foliage carries that distinction without needing a legend.
const WALL := Color("6b6255")
const WALL_TOP := Color("8a8072")
const HEDGE := Color("24471f")
const HEDGE_TOP := Color("2d5a2b")
const PATH := Color("b8a179")
const PATH_EDGE := Color("9c8663")
const POND := Color("3d7ea6")
const POND_SHALLOW := Color("5fa3c4")
const FLOWER_A := Color("f2c14e")
const FLOWER_B := Color("e8657f")
const FLOWER_C := Color("d7dce8")
const PEBBLE := Color("8d8f88")
const TUFT := Color("356b31")

# Characters.
const CAT_PLAYER := Color("e08a3c")  # ginger
const CAT_ENEMY := Color("8b9199")  # grey
const CAT_REMOTE := Color("6fa8dc")  # blue — another person, not a bot
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)

# Gameplay elements — deliberately the warmest, brightest things on screen.
const ARROW := Color("ffd166")
const ARROW_TIP := Color("fff3d0")
const AIM := Color("ffd166")
const HEALTH := Color("6ee7a0")
const HEALTH_BG := Color(0.0, 0.0, 0.0, 0.5)

# UI.
const STICK := Color(1, 1, 1, 0.18)
const STICK_KNOB := Color(1, 1, 1, 0.28)


## Ramp used to colour the ground noise texture.
static func grass_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, GRASS_DARK)
	g.set_offset(1, 1.0)
	g.set_color(1, GRASS_LIGHT)
	g.add_point(0.5, GRASS_MID)
	return g
