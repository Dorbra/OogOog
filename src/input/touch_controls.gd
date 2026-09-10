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
## Right half -> AUTOMATIC. Holding aims and fires; letting go stops.
##
## This is the third firing model and the simplest. A charge came first (450 ms
## of thumb before anything left the bow: "sluggish"). Then tap-to-fire, one
## round per press-release. Then:
##
##     "לדעתי נעבור למצב אוטומט, 5 כדורים"
##     ("let's switch to automatic, 5 rounds")
##
## So there is no shot EVENT any more, and no signal. Firing is a STATE — the
## thumb is down or it is not — read straight off this node once per simulation
## tick. That deletes the whole pending-shot relay in main.gd along with the
## frame-rate coupling it carried: a signal emitted per rendered frame fed a
## simulation that ticks at a fixed 60 Hz, so the two only agreed by accident.
##
## Rate is enforced in Gun.consume(), the same code that limits the bots.

const UNASSIGNED := -1

var move_vector: Vector2 = Vector2.ZERO
var aim_vector: Vector2 = Vector2.ZERO

## True while a right-hand finger is down, which now means BOTH aiming and
## firing — they stopped being separate the moment the gun went automatic.
## SimWorld reads it as `cmd.fire`; the view reads it to brighten the aim line.
var is_firing: bool = false

## True for exactly ONE tick after the ability button is tapped.
##
## An edge, unlike is_firing, because an ability is a single event and the
## charge bar is what gates repeats. Consumed by take_ability() rather than
## cleared on release, so a slow frame cannot swallow the tap and a long press
## cannot fire it twice.
var _ability_pressed: bool = false

## Finger currently held on the ability button, so a thumb resting there does
## not also steer the aim.
var _ability_finger: int = UNASSIGNED

# Finger index -> origin, for each side. -1 means "no finger on this side".
var _move_finger: int = UNASSIGNED
var _move_origin: Vector2 = Vector2.ZERO
var _move_current: Vector2 = Vector2.ZERO

var _aim_finger: int = UNASSIGNED
var _aim_origin: Vector2 = Vector2.ZERO
var _aim_current: Vector2 = Vector2.ZERO

## Both halves of the viewport size, tracked here rather than asked for on
## demand. TouchControls is a plain Node — it has no get_viewport_rect() — and
## the headless tests build one outside any tree, so reaching for the viewport
## inside a touch handler crashed two of them the moment the ability button
## started needing the screen HEIGHT as well as its width.
var _screen_width: float = 1280.0
var _screen_size: Vector2 = Vector2(1280, 720)


func _ready() -> void:
	# Without this, drag events are coalesced per frame and the draw gesture
	# feels laggy in exactly the way that is hardest to diagnose on a phone.
	Input.set_use_accumulated_input(false)
	_on_viewport_resized()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_screen_size = get_viewport().get_visible_rect().size
	_screen_width = _screen_size.x


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


## Where the ability button sits, in screen space.
##
## Bottom-right, above where the firing thumb rests, and safe-area aware — the
## Pixel 9's gesture-nav inset eats exactly this corner. It is checked BEFORE
## the aim half, or the button would be unreachable: it lives inside the right
## half, and the right half already means "aim and fire".
func ability_rect() -> Rect2:
	var view := _screen_size
	var inset := SafeArea.margins(view)
	var size := Tuning.get_value("ability_button_size")
	return Rect2(
		Vector2(view.x - inset.z - size - 24.0, view.y - inset.w - size - 150.0),
		Vector2(size, size)
	)


## Reads and clears the one-tick ability edge.
func take_ability() -> bool:
	var pressed := _ability_pressed
	_ability_pressed = false
	return pressed


func _assign_finger(index: int, position: Vector2) -> void:
	# The button first. It is inside the right half, and the right half means
	# "aim and fire" — so without this the button could never be pressed without
	# also swinging the aim to wherever the thumb happened to land.
	if ability_rect().has_point(position):
		_ability_finger = index
		_ability_pressed = true
		return

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
		is_firing = true


func _release_finger(index: int) -> void:
	if index == _ability_finger:
		_ability_finger = UNASSIGNED
		return
	if index == _move_finger:
		_move_finger = UNASSIGNED
		move_vector = Vector2.ZERO
	elif index == _aim_finger:
		_aim_finger = UNASSIGNED
		is_firing = false
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
	if event.index == _ability_finger:
		# A thumb sliding off the button steers nothing. Without this, pressing
		# the ability and then drifting would fight the aim.
		return
	if event.index == _move_finger:
		_move_current = event.position
	elif event.index == _aim_finger:
		_aim_current = event.position


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
