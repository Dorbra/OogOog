extends Node2D
## M1: drives the simulation and renders it.
##
## Everything drawn here is flat shapes on purpose. The question M1 has to answer
## is "does drawing and loosing a bow feel good in the hand?", and art cannot
## answer that — it can only disguise the answer.

const COL_BG := Color("101820")
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

@onready var _hud: Label = $HUD/Label


func _ready() -> void:
	var size := get_viewport_rect().size
	_world = SimWorld.new(Rect2(Vector2.ZERO, size))

	_controls = TouchControls.new()
	add_child(_controls)
	_controls.shot_released.connect(_on_shot_released)


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
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()
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


func _draw() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), COL_BG)

	for dummy in _world.dummies:
		var col := COL_DUMMY if dummy.alive() else COL_DUMMY_DEAD
		if dummy.hit_flash > 0.0:
			col = col.lerp(Color.WHITE, dummy.hit_flash / 0.15)
		draw_circle(dummy.position, dummy.radius, col)
		if dummy.alive():
			_draw_health_bar(dummy)

	for arrow in _world.arrows:
		if not arrow.active:
			continue
		var tip := arrow.render_position(alpha)
		draw_line(tip - arrow.velocity.normalized() * 18.0, tip, COL_ARROW, 3.0)

	_draw_player(alpha)
	_draw_controls()


func _draw_health_bar(dummy: Dummy) -> void:
	var width := dummy.radius * 2.0
	var origin := dummy.position + Vector2(-dummy.radius, -dummy.radius - 12.0)
	draw_rect(Rect2(origin, Vector2(width, 5.0)), Color(0, 0, 0, 0.5))
	var frac := dummy.health / Dummy.MAX_HEALTH
	draw_rect(Rect2(origin, Vector2(width * frac, 5.0)), Color("6ee7a0"))


func _draw_player(alpha: float) -> void:
	var pos := _world.player.render_position(alpha)
	draw_circle(pos, _world.player.radius, COL_PLAYER)

	# The draw indicator grows with hold time: the player has to be able to see
	# their power building without looking away from the fight.
	if _controls.is_drawing:
		var draw_strength := _controls.draw_strength
		var length := lerpf(40.0, 150.0, draw_strength)
		var dir := _world.player.facing
		draw_line(
			pos,
			pos + dir * length,
			COL_AIM.lerp(Color.WHITE, draw_strength),
			2.0 + 3.0 * draw_strength
		)
		draw_arc(pos, _world.player.radius + 8.0, 0.0, TAU * draw_strength, 32, COL_AIM, 3.0)


func _draw_controls() -> void:
	if not _controls.has_move_finger():
		return

	var origin := _controls.move_origin()
	var radius := Tuning.get_value("stick_radius")
	draw_arc(origin, radius, 0.0, TAU, 48, COL_STICK, 3.0)
	draw_circle(origin + _world.player.velocity.normalized() * 0.0, 14.0, COL_STICK)

	var knob := origin + (_controls.move_current() - origin).limit_length(radius)
	draw_circle(knob, 26.0, Color(1, 1, 1, 0.28))
