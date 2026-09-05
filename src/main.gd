extends Node2D
## M1: drives the simulation and renders it.
##
## Everything drawn here is flat shapes on purpose. The question M1 has to answer
## is "does drawing and loosing a bow feel good in the hand?", and art cannot
## answer that — it can only disguise the answer.

## The arena is deliberately larger than the screen. Without that there is
## nothing for the camera to zoom into, which is what made the first playtest
## feel "far away and zoomed out" — the whole world was squeezed into one frame,
## so the player was a dot and a few pixels of thumb travel swung the shot
## across the entire arena.
const WORLD_SIZE := Vector2(2400, 1350)

const COL_BG := Color("0b1017")
const COL_FLOOR := Color("101820")
const COL_WALL := Color("2b3a4a")
const COL_PLAYER := Color("4fc3f7")
const COL_ARROW := Color("ffd166")
const COL_DUMMY := Color("ef5d60")
const COL_DUMMY_DEAD := Color("2a3440")
const COL_STICK := Color(1, 1, 1, 0.18)
const COL_AIM := Color("ffd166")

var _world: SimWorld
var _controls: TouchControls
var _cmd := InputCommand.new()
var _tick: int = 0

# Set for exactly one tick by the release signal, then consumed by the sim.
var _pending_shot := false
var _pending_aim := Vector2.ZERO
var _pending_draw := 0.0
var _pending_snap := false

var _camera: Camera2D
var _overlay: Node2D

@onready var _hud: Label = $HUD/Label


func _ready() -> void:
	_world = SimWorld.new(Rect2(Vector2.ZERO, WORLD_SIZE))

	_controls = TouchControls.new()
	add_child(_controls)
	_controls.shot_released.connect(_on_shot_released)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false  # smoothed manually, so it is tunable
	_camera.position = _world.player.position
	add_child(_camera)
	_camera.make_current()

	# The touch overlay must be drawn in SCREEN space while the world is drawn
	# through the camera, so it lives on its own CanvasLayer rather than here.
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_touch_overlay)
	layer.add_child(_overlay)

	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	# The Pixel 9's cutout sits exactly where a top-left HUD line would go.
	var inset := SafeArea.margins(get_viewport_rect().size)
	_hud.position = Vector2(inset.x + 12.0, inset.y + 8.0)


func _on_shot_released(aim: Vector2, draw_strength: float, snap: bool) -> void:
	_pending_shot = true
	_pending_aim = aim
	_pending_draw = draw_strength
	_pending_snap = snap


func _physics_process(delta: float) -> void:
	_tick += 1

	_cmd.clear()
	_cmd.tick = _tick
	_cmd.move = _controls.move_vector
	_cmd.aim = _controls.aim_vector
	_cmd.draw_strength = _controls.draw_strength

	if _pending_shot:
		_cmd.fire = true
		_cmd.aim = _pending_aim
		_cmd.draw_strength = _pending_draw
		_cmd.snap = _pending_snap
		_pending_shot = false

	_world.tick(_cmd, delta)


func _process(delta: float) -> void:
	_update_camera(delta)
	queue_redraw()
	_overlay.queue_redraw()

	var s := BuildInfo.stamp()
	_hud.text = (
		"%s  •  %d fps  •  quiver %d/%d  •  draw %.2f"
		% [
			s.get("commit", "?"),
			Engine.get_frames_per_second(),
			_world.player.bow.quiver,
			_world.player.bow.capacity(),
			_controls.draw_strength,
		]
	)


func _update_camera(delta: float) -> void:
	var zoom := Tuning.get_value("camera_zoom")
	_camera.zoom = Vector2(zoom, zoom)

	# Keep the camera inside the arena so the player never stares at dead space
	# beyond the wall. Half-extents shrink as zoom rises.
	var half := get_viewport_rect().size * 0.5 / zoom
	var target := _world.player.position
	if WORLD_SIZE.x > half.x * 2.0:
		target.x = clampf(target.x, half.x, WORLD_SIZE.x - half.x)
	else:
		target.x = WORLD_SIZE.x * 0.5
	if WORLD_SIZE.y > half.y * 2.0:
		target.y = clampf(target.y, half.y, WORLD_SIZE.y - half.y)
	else:
		target.y = WORLD_SIZE.y * 0.5

	var weight := 1.0 - exp(-Tuning.get_value("camera_smoothing") * delta)
	_camera.position = _camera.position.lerp(target, weight)


func _draw() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	# World space now — the camera transforms this, so no full-screen rect.
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), COL_FLOOR)
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), COL_WALL, false, 8.0)

	for dummy in _world.dummies:
		var col := COL_DUMMY if dummy.alive() else COL_DUMMY_DEAD
		if dummy.hit_flash > 0.0:
			col = col.lerp(Color.WHITE, dummy.hit_flash / 0.15)
		draw_circle(dummy.position, dummy.radius, col)
		if dummy.alive():
			_draw_health_bar(dummy)

	var width := Tuning.get_value("arrow_width")
	var length := Tuning.get_value("arrow_length")
	for arrow in _world.arrows:
		if not arrow.active:
			continue
		var tip := arrow.render_position(alpha)
		draw_line(tip - arrow.velocity.normalized() * length, tip, COL_ARROW, width)

	_draw_player(alpha)


func _draw_health_bar(dummy: Dummy) -> void:
	# Sits just above the circle. Any further and it reads as a separate object
	# floating in space rather than as that target's health.
	var bar_width := dummy.radius * 1.6
	var origin := dummy.position + Vector2(-bar_width * 0.5, -dummy.radius - 9.0)
	draw_rect(Rect2(origin, Vector2(bar_width, 6.0)), Color(0, 0, 0, 0.5))
	var frac := dummy.health / Dummy.MAX_HEALTH
	draw_rect(Rect2(origin, Vector2(bar_width * frac, 6.0)), Color("6ee7a0"))


func _draw_player(alpha: float) -> void:
	var pos := _world.player.render_position(alpha)
	var radius := _world.player.radius
	draw_circle(pos, radius, COL_PLAYER)

	# The draw indicator grows with hold time, so power is readable without
	# looking away from the fight.
	if _controls.is_drawing:
		var draw_strength := _controls.draw_strength
		var dir := _world.player.facing
		draw_line(
			pos + dir * radius,
			pos + dir * lerpf(radius + 30.0, radius + 150.0, draw_strength),
			COL_AIM.lerp(Color.WHITE, draw_strength),
			2.0 + 4.0 * draw_strength
		)
		draw_arc(pos, radius + 10.0, 0.0, TAU * draw_strength, 32, COL_AIM, 4.0)


## Drawn on a CanvasLayer in screen space: the joystick follows the thumb, not
## the world, so it must not be transformed by the camera.
func _draw_touch_overlay() -> void:
	if not _controls.has_move_finger():
		return

	var origin := _controls.move_origin()
	var radius := Tuning.get_value("stick_radius")
	_overlay.draw_arc(origin, radius, 0.0, TAU, 48, COL_STICK, 3.0)
	_overlay.draw_circle(origin, 14.0, COL_STICK)

	var knob := origin + (_controls.move_current() - origin).limit_length(radius)
	_overlay.draw_circle(knob, 26.0, Color(1, 1, 1, 0.28))
