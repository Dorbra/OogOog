extends Node2D
## Thin orchestrator: builds the world, pumps input, wires signals.
##
## Camera, HUD and combat feedback each live in their own node now. This file
## had grown to 237 lines doing all of it at once, and the juice pass would have
## roughly doubled that.
##
## World size is no longer a constant here: it comes from the arena text file,
## so a layout edit resizes the world without three systems needing to agree on
## a number by hand.
var world: SimWorld
var controls: TouchControls

var _terrain: Terrain
var _camera: CameraRig
var _fx: Fx
var _hud: Hud
var _view: GameView
var _overlay: Node2D

var _cmd := InputCommand.new()
var _tick: int = 0

# Set for exactly one tick by the release signal, then consumed by the sim.
var _pending_shot := false
var _pending_aim := Vector2.ZERO
var _pending_draw := 0.0
var _pending_snap := false


func _ready() -> void:
	var arena := Arena.new()
	world = SimWorld.new(arena)
	_terrain = Terrain.new(arena)

	controls = TouchControls.new()
	add_child(controls)
	controls.shot_released.connect(_on_shot_released)

	_camera = CameraRig.new()
	_camera.world_size = arena.bounds().size
	_camera.position = world.player.position
	_camera.target_position = world.player.position
	add_child(_camera)
	_camera.make_current()
	_camera.listen_to(world)

	_view = GameView.new()
	_view.setup(world, _terrain, controls, _camera)
	add_child(_view)

	_fx = Fx.new()
	add_child(_fx)
	_fx.listen_to(world)

	# The touch overlay and HUD are drawn in SCREEN space while the world goes
	# through the camera, so they need their own CanvasLayer.
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	_overlay = Node2D.new()
	_overlay.draw.connect(_draw_touch_overlay)
	layer.add_child(_overlay)

	_hud = Hud.new()
	layer.add_child(_hud)


func _on_shot_released(aim: Vector2, draw_strength: float, snap: bool) -> void:
	_pending_shot = true
	_pending_aim = aim
	_pending_draw = draw_strength
	_pending_snap = snap


func _physics_process(delta: float) -> void:
	_tick += 1

	_cmd.clear()
	_cmd.tick = _tick
	_cmd.move = controls.move_vector
	_cmd.aim = controls.aim_vector
	_cmd.draw_strength = controls.draw_strength

	if _pending_shot:
		_cmd.fire = true
		_cmd.aim = _pending_aim
		_cmd.draw_strength = _pending_draw
		_cmd.snap = _pending_snap
		_pending_shot = false

	world.tick(_cmd, delta)


func _process(delta: float) -> void:
	_camera.target_position = world.player.position
	_camera.follow(delta, get_viewport_rect().size)

	_hud.quiver = world.player.bow.quiver
	_hud.capacity = world.player.bow.capacity()
	_hud.draw_strength = controls.draw_strength

	_overlay.queue_redraw()


## Drawn on a CanvasLayer in screen space: the joystick follows the thumb, not
## the world, so it must not be transformed by the camera.
func _draw_touch_overlay() -> void:
	if not controls.has_move_finger():
		return

	var origin := controls.move_origin()
	var radius := Tuning.get_value("stick_radius")
	_overlay.draw_arc(origin, radius, 0.0, TAU, 48, Palette.STICK, 3.0)
	_overlay.draw_circle(origin, 14.0, Palette.STICK)

	var knob := origin + (controls.move_current() - origin).limit_length(radius)
	_overlay.draw_circle(knob, 26.0, Palette.STICK_KNOB)
