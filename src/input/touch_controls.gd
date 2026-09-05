class_name TouchControls
extends Node
## Routes multi-touch into an InputCommand.
##
## THE bug in mobile twin-stick controls is two thumbs stealing each other's
## events. The rule that prevents it: a finger is assigned to a side ONCE, when
## it first touches down, and keeps that assignment until it lifts — no matter
## where it subsequently drags. Routing by current position instead of by the
## stored finger index is what makes controls "randomly" break when your right
## thumb crosses the screen midpoint mid-drag.
##
## Left half  -> floating joystick (movement).
## Right half -> aim by drag, draw by hold, loose on release.

## Emitted on release. `snap` marks the fast, weak, auto-aimed shot.
signal shot_released(aim: Vector2, draw_strength: float, snap: bool)

const UNASSIGNED := -1

var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO
var draw_strength: float = 0.0
var is_drawing: bool = false

# Finger index -> origin, for each side. -1 means "no finger on this side".
var _move_finger: int = UNASSIGNED
var _move_origin: Vector2 = Vector2.ZERO
var _move_current: Vector2 = Vector2.ZERO

var _aim_finger: int = UNASSIGNED
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_current: Vector2 = Vector2.ZERO
var _aim_hold_time: float = 0.0

var _screen_width: float = 1280.0


func _ready() -> void:
	# Without this, drag events are coalesced per frame and the draw gesture
	# feels laggy in exactly the way that is hardest to diagnose on a phone.
	Input.set_use_accumulated_input(false)
	_screen_width = get_viewport().get_visible_rect().size.x
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_screen_width = get_viewport().get_visible_rect().size.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_drag(event as InputEventScreenDrag)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_assign_finger(event.index, event.position)
	else:
		_release_finger(event.index)


func _assign_finger(index: int, position: Vector2) -> void:
	var is_left := position.x < _screen_width * 0.5
	if is_left:
		if _move_finger == UNASSIGNED:
			_move_finger = index
			_move_origin = position
			_move_current = position
	elif _aim_finger == UNASSIGNED:
		_aim_finger = index
		_aim_origin = position
		_aim_current = position
		_aim_hold_time = 0.0
		is_drawing = true


func _release_finger(index: int) -> void:
	if index == _move_finger:
		_move_finger = UNASSIGNED
		move_vector = Vector2.ZERO
	elif index == _aim_finger:
		_emit_shot()
		_aim_finger = UNASSIGNED
		is_drawing = false
		draw_strength = 0.0
		aim_vector = Vector2.ZERO


func _handle_drag(event: InputEventScreenDrag) -> void:
	# Position is irrelevant here — only which finger this is.
	if event.index == _move_finger:
		_move_current = event.position
	elif event.index == _aim_finger:
		_aim_current = event.position


func _emit_shot() -> void:
	var drag := _aim_current - _aim_origin
	var is_snap := (
		drag.length() < Tuning.get_value("snap_max_drag")
		and _aim_hold_time < Tuning.get_value("snap_max_hold")
	)
	# A snap shot carries no direction of its own — the caller auto-aims it.
	var dir := Vector2.ZERO if is_snap else drag.normalized()
	shot_released.emit(dir, draw_strength, is_snap)


func _process(delta: float) -> void:
	_update_move()
	_update_aim(delta)


func _update_move() -> void:
	if _move_finger == UNASSIGNED:
		move_vector = Vector2.ZERO
		return

	var radius := Tuning.get_value("stick_radius")
	var offset := _move_current - _move_origin
	var magnitude := minf(offset.length(), radius)
	var normalized := magnitude / radius if radius > 0.0 else 0.0

	if normalized < Tuning.get_value("stick_deadzone"):
		move_vector = Vector2.ZERO
		return

	move_vector = offset.normalized() * normalized


func _update_aim(delta: float) -> void:
	if _aim_finger == UNASSIGNED:
		return

	_aim_hold_time += delta

	var full := Tuning.get_value("draw_time_full")
	draw_strength = clampf(_aim_hold_time / full, 0.0, 1.0) if full > 0.0 else 1.0

	_update_aim_direction(delta)

	# Auto-repeat: holding keeps firing once each draw completes, so the quiver
	# and its refill rate-limit the player instead of their thumb. Without it,
	# every shot costs a full press-hold-release gesture, which reads as
	# sluggish however fast the draw itself is.
	if Tuning.get_value("auto_repeat") >= 0.5 and draw_strength >= 1.0:
		shot_released.emit(aim_vector, 1.0, false)
		_aim_hold_time = 0.0
		draw_strength = 0.0


func _update_aim_direction(delta: float) -> void:
	var offset := _aim_current - _aim_origin

	# Below the threshold the drag vector is mostly thumb noise: a 10px offset
	# carries the same authority as a 200px one once normalised, which is what
	# made small movements swing the shot wildly. Hold the last direction.
	if offset.length() < Tuning.get_value("aim_min_drag"):
		return

	var target := offset.normalized()
	if aim_vector == Vector2.ZERO:
		aim_vector = target
		return

	# Frame-rate independent smoothing, so aim settles instead of snapping.
	var weight := 1.0 - exp(-Tuning.get_value("aim_smoothing") * delta)
	aim_vector = aim_vector.lerp(target, weight).normalized()


## Where the left thumb went down, for drawing the floating stick. Only
## meaningful while `has_move_finger()` is true.
func move_origin() -> Vector2:
	return _move_origin


func move_current() -> Vector2:
	return _move_current


func has_move_finger() -> bool:
	return _move_finger != UNASSIGNED


func aim_origin() -> Vector2:
	return _aim_origin


func aim_current() -> Vector2:
	return _aim_current
