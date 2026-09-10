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
var _match_hud: MatchHud
var _screens: MatchScreens
var _view: GameView
var _overlay: Node2D

var _cmd := InputCommand.new()
var _tick: int = 0


func _ready() -> void:
	var arena := Arena.new()
	world = SimWorld.new(arena)
	_terrain = Terrain.new(arena)

	controls = TouchControls.new()
	add_child(controls)

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

	_match_hud = MatchHud.new()
	_match_hud.setup(world.match_state)
	layer.add_child(_match_hud)

	# Above the HUD: the setup and results screens are modal, and the countdown
	# has to sit over everything including the score.
	var screen_layer := CanvasLayer.new()
	screen_layer.layer = 2
	add_child(screen_layer)

	_screens = MatchScreens.new()
	_screens.setup(world.match_state)
	_screens.size_chosen.connect(_on_size_chosen)
	_screens.dismissed.connect(_on_results_dismissed)
	screen_layer.add_child(_screens)


## Chosen on the setup screen. Team size is a simulation parameter read when the
## world is built, so a new size means a new world rather than a resize — which
## also gives every round a clean arena, full quivers and everyone on their
## spawn.
func _on_size_chosen(size: int) -> void:
	Tuning.set_value("bot_team_size", float(size))
	_rebuild_world()
	world.match_state.begin_countdown()


func _on_results_dismissed() -> void:
	_rebuild_world()
	world.match_state.begin_countdown()


func _rebuild_world() -> void:
	world = SimWorld.new(_terrain.arena if _terrain != null else null)
	_camera.listen_to(world)
	_fx.listen_to(world)
	_view.setup(world, _terrain, controls, _camera)
	_match_hud.setup(world.match_state)
	_screens.setup(world.match_state)
	_camera.position = world.player.position
	_camera.target_position = world.player.position


func _physics_process(delta: float) -> void:
	_tick += 1

	_cmd.clear()
	_cmd.tick = _tick
	_cmd.move = controls.move_vector
	_cmd.aim = controls.aim_vector

	# Read straight off the controls once per SIMULATION tick. This used to be a
	# signal relayed through a one-tick pending flag, which meant a per-rendered-
	# frame event driving a fixed 60 Hz simulation — two clocks that agreed only
	# by accident. Firing is a state now, so the state is what gets read.
	_cmd.fire = controls.is_firing
	# take_ability() CONSUMES the edge, so one tap is one ability however many
	# rendered frames pass before the next simulation tick. Reading a boolean
	# without clearing it would fire on every tick the thumb stayed down.
	_cmd.ability = controls.take_ability()

	world.tick(_cmd, delta)


func _process(delta: float) -> void:
	_camera.target_position = world.player.position
	_camera.follow(delta, get_viewport_rect().size)

	# LAN spike: publish where this player is, so other devices can draw them.
	# The transport decides how often it actually transmits.
	Net.set_local_position(world.player.position)

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
