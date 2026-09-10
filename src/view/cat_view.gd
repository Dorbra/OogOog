class_name CatView
extends Node2D
## Draws one cat: shadow, tinted body, untinted face, and an orbiting gun.
##
## The cat stays upright and faces the camera rather than rotating to face its
## aim. From directly overhead a cat is an oval with two ear triangles, which
## throws away the entire reason for choosing cats — so the body stays readable
## and AIM MOVES ONTO THE BOW instead.

const BODY_PATH := "res://assets/cats/cat_body.svg"
const FACE_PATH := "res://assets/cats/cat_face.svg"

## Below this |aim.x| the facing is left alone. Without it a cat aiming near
## vertical strobes between left and right every frame.
const FLIP_HYSTERESIS := 0.18

var tint: Color = Palette.CAT_PLAYER
var radius: float = 30.0
var aim: Vector2 = Vector2.RIGHT
var show_gun: bool = true

## Which cat this is. The gun silhouette is drawn from it, and that silhouette
## is the ONLY thing on screen that says what an enemy is carrying — a
## five-year-old cannot read a class name, and colour is already spoken for by
## the teams.
var fighter_class: FighterClass = FighterClass.at(0)
var flash: float = 0.0

var _body: Sprite2D
var _face: Sprite2D
var _facing_right := true

## Squash-and-stretch impulse, decaying to rest. Firing a shot punches the
## cat; taking a hit flinches it. Static sprites read as cardboard, and this is
## the cheapest possible animation given there is no animator in this workflow.
var _punch: float = 0.0


func _ready() -> void:
	_body = Sprite2D.new()
	_body.texture = load(BODY_PATH)
	_body.modulate = tint
	add_child(_body)

	_face = Sprite2D.new()
	_face.texture = load(FACE_PATH)
	add_child(_face)


func _process(_delta: float) -> void:
	if _body == null:
		return

	# The art is 128px tall and sits on the ground line; scale so the cat's
	# footprint matches the simulation's collision radius.
	var scale_factor := (radius * 2.4) / 128.0

	# Squash conserves apparent volume — wider as it gets shorter — which is
	# what makes it read as impact rather than as the sprite simply resizing.
	var squash := _punch
	var sx := scale_factor * (1.0 + squash * 0.6)
	var sy := scale_factor * (1.0 - squash * 0.5)
	_body.scale = Vector2(sx, sy)
	_face.scale = _body.scale

	# Anchor the sprite so its feet land on the entity position rather than its
	# centre, otherwise the cat appears to float above its own shadow.
	var offset := Vector2(0, -radius * 0.55)
	_body.position = offset
	_face.position = offset

	if absf(aim.x) > FLIP_HYSTERESIS:
		_facing_right = aim.x > 0.0
	_body.flip_h = not _facing_right
	_face.flip_h = not _facing_right

	_body.modulate = tint.lerp(Color.WHITE, flash)

	# Unscaled, so the animation keeps moving during a hitstop freeze rather
	# than locking mid-squash.
	var dt := _delta / maxf(Engine.time_scale, 0.0001)
	_punch = maxf(_punch - dt * 6.0, 0.0)
	if flash > 0.0:
		_punch = maxf(_punch, flash * Tuning.get_value("squash_amount"))
	queue_redraw()


## Kick the squash-and-stretch. Called when this cat fires.
func punch(amount: float) -> void:
	_punch = clampf(maxf(_punch, amount), 0.0, 0.9)


func _draw() -> void:
	_draw_shadow()
	if show_gun:
		_draw_gun()


## Grounds the sprite. Without a shadow, top-down characters read as stickers
## floating on the background — this is the cheapest large win available.
func _draw_shadow() -> void:
	var alpha := Tuning.get_value("shadow_alpha")
	var col := Color(Palette.SHADOW.r, Palette.SHADOW.g, Palette.SHADOW.b, alpha)
	var radii := Vector2(radius * 0.95, radius * 0.42)

	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(Vector2(cos(a) * radii.x, sin(a) * radii.y + radius * 0.28))
	draw_colored_polygon(pts, col)


## The gun carries the aim direction that the body no longer does.
##
## A bow lived here, drawn as an arc with a string that pulled back as the draw
## built — the draw strength made a visibly moving object out of the aim. There
## is no draw any more, so this is a fixed silhouette that only rotates: a barrel
## along the aim, a body behind it, and a muzzle block at the end.
##
## Drawn from primitives rather than an SVG for the same reason the bow was:
## there is no artist and no image editor in this workflow, and a shape built
## from the aim vector is always pointing exactly where the shot will go.
##
## THE SHAPE IS THE CLASS. A long thin barrel is a Ranger; a short fat one with
## a spread of muzzles is a Skirmisher. That is the whole readout — there is no
## text anywhere in this game and colour already means team — so the proportions
## below are not decoration, they are the only way a player knows what is about
## to shoot them. Drawn on every cat, not just yours, for exactly that reason.
func _draw_gun() -> void:
	if aim == Vector2.ZERO:
		return

	var size := Tuning.get_value("gun_size")
	var centre := aim * (radius * 1.15) + Vector2(0, -radius * 0.5)
	var tangent := Vector2(-aim.y, aim.x)

	# A spread gun is stubby and wide; a single-round gun is long and thin. The
	# silhouette difference has to survive being 84 px tall on a phone in
	# daylight, so it is proportion rather than detail.
	var spread := fighter_class.pellets > 1
	var barrel_len := size * (0.85 if spread else 1.45)
	var barrel_half := size * (0.30 if spread else 0.19)
	var muzzle := centre + aim * barrel_len

	# Barrel: a quad along the aim, so it stays a rectangle at every angle
	# rather than a line whose thickness reads differently on the diagonals.
	draw_colored_polygon(
		PackedVector2Array(
			[
				centre + tangent * barrel_half,
				muzzle + tangent * barrel_half,
				muzzle - tangent * barrel_half,
				centre - tangent * barrel_half,
			]
		),
		Palette.ARROW.darkened(0.35)
	)

	# Body: shorter and deeper, sitting behind the barrel.
	var back := centre - aim * (size * 0.42)
	var body_half := size * 0.34
	draw_colored_polygon(
		PackedVector2Array(
			[
				back + tangent * body_half,
				centre + tangent * body_half,
				centre - tangent * body_half,
				back - tangent * body_half,
			]
		),
		Palette.ARROW.darkened(0.15)
	)

	# A bright muzzle tip, so which end the shot leaves from is never a question.
	# One for a single round; a row of them for a fan, spaced across the barrel's
	# width so the shape reads as "this thing sprays" without needing to be told.
	if not spread:
		draw_circle(muzzle, size * 0.24, Palette.ARROW_TIP)
		return

	var count := fighter_class.pellets
	var pitch := barrel_half * 1.35
	for i in count:
		var offset := -pitch + pitch * 2.0 * float(i) / float(maxi(count - 1, 1))
		draw_circle(muzzle + tangent * offset, size * 0.15, Palette.ARROW_TIP)
