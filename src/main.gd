extends Node2D
## Drives the simulation and renders the garden.
##
## The world is deliberately larger than the screen; without that there is
## nothing for the camera to zoom into, which is what made the first playtest
## feel "far away and zoomed out".
const WORLD_SIZE := Vector2(2400, 1350)

var _world: SimWorld
var _controls: TouchControls
var _terrain: Terrain
var _cmd := InputCommand.new()
var _tick: int = 0

# Set for exactly one tick by the release signal, then consumed by the sim.
var _pending_shot := false
var _pending_aim := Vector2.ZERO
var _pending_draw := 0.0
var _pending_snap := false

var _camera: Camera2D
var _overlay: Node2D
var _player_view: CatView
var _dummy_views: Array[CatView] = []

@onready var _hud: Label = $HUD/Label


func _ready() -> void:
	_world = SimWorld.new(Rect2(Vector2.ZERO, WORLD_SIZE))
	_terrain = Terrain.new(Rect2(Vector2.ZERO, WORLD_SIZE))

	_controls = TouchControls.new()
	add_child(_controls)
	_controls.shot_released.connect(_on_shot_released)

	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = false  # smoothed manually, so it is tunable
	_camera.position = _world.player.position
	add_child(_camera)
	_camera.make_current()

	_build_cats()

	# The touch overlay is drawn in SCREEN space while the world goes through
	# the camera, so it needs its own CanvasLayer.
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_touch_overlay)
	layer.add_child(_overlay)

	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _build_cats() -> void:
	# Targets are cats too, not red circles: M3 turns them into bots, so giving
	# them the real visual language now avoids drawing throwaway art twice.
	for dummy in _world.dummies:
		var view := CatView.new()
		view.tint = Palette.CAT_ENEMY
		view.show_bow = false
		view.z_index = 1
		add_child(view)
		_dummy_views.append(view)

	_player_view = CatView.new()
	_player_view.tint = Palette.CAT_PLAYER
	_player_view.z_index = 2
	add_child(_player_view)


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
	_sync_cat_views()
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


func _sync_cat_views() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	_player_view.position = _world.player.render_position(alpha)
	_player_view.radius = _world.player.radius
	_player_view.aim = _world.player.facing
	_player_view.draw_strength = _controls.draw_strength
	_player_view.show_bow = true

	for i in _dummy_views.size():
		var dummy: Dummy = _world.dummies[i]
		var view := _dummy_views[i]
		view.position = dummy.position
		view.radius = dummy.radius
		view.flash = clampf(dummy.hit_flash / 0.15, 0.0, 1.0)
		view.visible = dummy.alive()


func _update_camera(delta: float) -> void:
	var zoom := Tuning.get_value("camera_zoom")
	_camera.zoom = Vector2(zoom, zoom)

	# Keep the camera inside the arena so the player never stares at dead space
	# beyond the hedge. Half-extents shrink as zoom rises.
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


## The camera's world rect, used to cull terrain scatter. Padded so props do not
## pop in at the screen edge.
func _view_rect() -> Rect2:
	var zoom := maxf(Tuning.get_value("camera_zoom"), 0.01)
	var size := get_viewport_rect().size / zoom
	return Rect2(_camera.position - size * 0.5, size).grow(120.0)


func _draw() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	_terrain.draw_into(self, _view_rect())

	for dummy in _world.dummies:
		if dummy.alive():
			_draw_health_bar(dummy)

	var width := Tuning.get_value("arrow_width")
	var length := Tuning.get_value("arrow_length")
	for arrow in _world.arrows:
		if not arrow.active:
			continue
		var tip := arrow.render_position(alpha)
		var tail := tip - arrow.velocity.normalized() * length
		draw_line(tail, tip, Palette.ARROW, width)
		draw_line(
			tip - arrow.velocity.normalized() * (length * 0.25), tip, Palette.ARROW_TIP, width
		)

	_draw_aim_line(alpha)


func _draw_health_bar(dummy: Dummy) -> void:
	# Sits just above the cat. Any further and it reads as a separate object
	# floating in space rather than as that target's health.
	var bar_width := dummy.radius * 1.6
	var origin := dummy.position + Vector2(-bar_width * 0.5, -dummy.radius * 2.05)
	draw_rect(Rect2(origin, Vector2(bar_width, 5.0)), Palette.HEALTH_BG)
	var frac := dummy.health / Dummy.MAX_HEALTH
	draw_rect(Rect2(origin, Vector2(bar_width * frac, 6.0)), Palette.HEALTH)


## Ground-projected aim, complementing the bow on the cat itself. Drawn beneath
## the sprites so it never covers the character.
func _draw_aim_line(alpha: float) -> void:
	if not _controls.is_drawing:
		return

	var pos := _world.player.render_position(alpha)
	var dir := _world.player.facing
	var strength := _controls.draw_strength
	var reach := lerpf(70.0, 210.0, strength)
	draw_line(
		pos + dir * _world.player.radius,
		pos + dir * reach,
		Palette.AIM.lerp(Color.WHITE, strength) * Color(1, 1, 1, 0.55),
		2.0 + 3.0 * strength
	)


## Drawn on a CanvasLayer in screen space: the joystick follows the thumb, not
## the world, so it must not be transformed by the camera.
func _draw_touch_overlay() -> void:
	if not _controls.has_move_finger():
		return

	var origin := _controls.move_origin()
	var radius := Tuning.get_value("stick_radius")
	_overlay.draw_arc(origin, radius, 0.0, TAU, 48, Palette.STICK, 3.0)
	_overlay.draw_circle(origin, 14.0, Palette.STICK)

	var knob := origin + (_controls.move_current() - origin).limit_length(radius)
	_overlay.draw_circle(knob, 26.0, Palette.STICK_KNOB)
