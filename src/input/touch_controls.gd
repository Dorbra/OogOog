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
## Right half -> aim by drag, FIRE ON RELEASE. No charge.
##
## Hold time used to be a power axis: 450 ms of thumb before any shot left the
## bow. That read as lag, not commitment —
##
##     "the Arrow shooting is sluggish and cant be expected"
##
## — so releasing fires immediately and every shot is identical. The rate limit
## lives in Gun, not here, so the player and the bots are gated by one piece of
## code and a fast tapper simply has shots refused rather than queued. Queueing
## would turn quick fingers back into lag, which is the thing being removed.

## Emitted the instant a shot is fired. `snap` marks a tap: auto-aimed and
## leading, with no damage penalty.
signal shot_fired(aim: Vector2, snap: bool)

const UNASSIGNED := -1

var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO

## True while a right-hand finger is down. The aim preview reads this — it is
## the "clear line of fire" the shot will actually take.
var is_aiming: bool = false

# Finger index -> origin, for each side. -1 means "no finger on this side".
var _move_finger: int = UNASSIGNED
var _move_origin: Vector2 = Vector2.ZERO
var _move_current: Vector2 = Vector2.ZERO

var _aim_finger: int = UNASSIGNED
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_current: Vector2 = Vector2.ZERO

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
		is_aiming = true


func _release_finger(index: int) -> void:
	if index == _move_finger:
		_move_finger = UNASSIGNED
		move_vector = Vector2.ZERO
	elif index == _aim_finger:
		_emit_shot()
		_aim_finger = UNASSIGNED
		is_aiming = false
		# aim_vector DELIBERATELY SURVIVES.
		#
		# It used to be zeroed here, and Fighter.tick() falls through to the
		# MOVEMENT direction when the aim is zero — so the cat swung to face
		# wherever it was walking the instant you released, and CatView draws the
		# gun along facing, so the barrel visibly snapped away on every shot:
		#
		#     "the Player can keep a line-of-fire, and not 'reset' after every
		#      shoot... Think about FPS games on Mobile"
		#
		# Keeping it makes the velocity fallback correct rather than dead: it now
		# fires only before the player has ever aimed, which is the one moment
		# there is no line to keep.


func _handle_drag(event: InputEventScreenDrag) -> void:
	# Position is irrelevant here — only which finger this is.
	if event.index == _move_finger:
		_move_current = event.position
	elif event.index == _aim_finger:
		_aim_current = event.position


## Classified on DRAG ALONE, not on how long the thumb rested.
##
## A hold threshold used to be half of this decision, which meant a careful
## player lining up a shot got it silently reclassified as a tap the moment they
## took too long. Distance is the whole question now: did you point somewhere, or
## did you just tap?
##
## `snap_max_drag` is the ONLY threshold. There used to be a second one,
## `aim_min_drag` at 40 px, below which the aim refused to update — while this
## function called anything over 26 px an aimed shot. A drag landing in that
## 26-40 px gap was fired as an aimed shot along an aim nothing had updated and
## the preview had never drawn. One number makes that gap unrepresentable rather
## than merely fixed.
##
## The shot goes along `aim_vector`, NOT along the raw drag. aim_vector is the
## smoothed direction the preview actually drew; firing the raw drag meant a
## quick flick left the bullet somewhere the dotted line had never pointed, which
## is ADR-0019's lesson reintroduced by the PR that removed the charge. Preview
## and shot are now the same value rather than two values that agree.
func _emit_shot() -> void:
	var drag := _aim_current - _aim_origin
	var is_snap := drag.length() < Tuning.get_value("snap_max_drag")
	# A tap carries no direction of its own — the caller auto-aims and leads it.
	var dir := Vector2.ZERO if is_snap else aim_vector
	shot_fired.emit(dir, is_snap)


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

	_update_aim_direction(delta)

	# Optional and OFF by default: the user asked for tap-to-fire. When it is on,
	# emitting every frame is deliberate — Gun's cooldown is the single source of
	# fire rate, so duplicating that timing here could only ever disagree with it.
	if Tuning.get_value("auto_repeat") >= 0.5 and aim_vector != Vector2.ZERO:
		shot_fired.emit(aim_vector, false)


func _update_aim_direction(delta: float) -> void:
	var offset := _aim_current - _aim_origin

	# Below the threshold the drag vector is mostly thumb noise: a 10px offset
	# carries the same authority as a 200px one once normalised, which is what
	# made small movements swing the shot wildly. Hold the last direction.
	#
	# The SAME threshold _emit_shot() classifies on, deliberately: any drag long
	# enough to count as an aimed shot is long enough to have moved the aim.
	if offset.length() < Tuning.get_value("snap_max_drag"):
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
