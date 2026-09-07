class_name CatView
extends Node2D
## Draws one cat: shadow, tinted body, untinted face, and an orbiting bow.
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
var draw_strength: float = 0.0
var show_bow: bool = true
var flash: float = 0.0

var _body: Sprite2D
var _face: Sprite2D
var _facing_right := true

## Squash-and-stretch impulse, decaying to rest. Loosing an arrow punches the
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


## Kick the squash-and-stretch. Called when this cat looses an arrow.
func punch(amount: float) -> void:
	_punch = clampf(maxf(_punch, amount), 0.0, 0.9)


func _draw() -> void:
	_draw_shadow()
	if show_bow:
		_draw_bow()


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


## The bow carries the aim direction that the body no longer does — and it makes
## "this is an archer" legible, which a coloured circle never did.
func _draw_bow() -> void:
	if aim == Vector2.ZERO:
		return

	var size := Tuning.get_value("bow_size")
	var centre := aim * (radius * 1.35) + Vector2(0, -radius * 0.5)
	var angle := aim.angle()

	# Arc opening away from the cat, so it reads as a bow being aimed outward.
	draw_arc(centre, size, angle - 1.15, angle + 1.15, 16, Palette.ARROW.darkened(0.25), 4.0)

	# String, pulled back as the draw builds.
	var pull := lerpf(0.0, size * 0.62, draw_strength)
	var tangent := Vector2(-aim.y, aim.x)
	var top := centre + tangent * size * 0.88 - aim * size * 0.18
	var bottom := centre - tangent * size * 0.88 - aim * size * 0.18
	var nock := centre - aim * pull
	draw_line(top, nock, Palette.ARROW_TIP, 1.8)
	draw_line(bottom, nock, Palette.ARROW_TIP, 1.8)

	if draw_strength > 0.05:
		draw_line(nock, nock + aim * (size * 1.5), Palette.ARROW, 3.0)
