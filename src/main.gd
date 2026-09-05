extends Node2D
## M0 pipeline proof.
##
## Deliberately trivial gameplay: a box bouncing at `move_speed`. Its job is to
## prove three things end-to-end before any real game code exists —
##   1. CI produces an artifact that runs on the device and in the browser,
##   2. the build on screen is identifiably the commit you just pushed,
##   3. dragging a slider in the debug overlay changes behaviour LIVE.
## (3) is the one that matters most: it is the difference between a 10-minute
## iteration loop and a 10-second one.

const BOX_SIZE := Vector2(96, 96)

var _pos := Vector2(200, 200)
var _dir := Vector2(1, 0.7).normalized()
var _speed := 320.0

@onready var _hud: Label = $HUD/Label


func _ready() -> void:
	_speed = Tuning.get_value("move_speed")
	Tuning.changed.connect(_on_tuning_changed)
	Tuning.reloaded.connect(func() -> void: _speed = Tuning.get_value("move_speed"))


func _on_tuning_changed(key: String, value: float) -> void:
	if key == "move_speed":
		_speed = value


func _physics_process(delta: float) -> void:
	var bounds := get_viewport_rect().size
	_pos += _dir * _speed * delta

	# Reflect off the viewport edges, clamping so a large speed can't tunnel out.
	if _pos.x < 0.0 or _pos.x + BOX_SIZE.x > bounds.x:
		_dir.x = -_dir.x
		_pos.x = clampf(_pos.x, 0.0, maxf(bounds.x - BOX_SIZE.x, 0.0))
	if _pos.y < 0.0 or _pos.y + BOX_SIZE.y > bounds.y:
		_dir.y = -_dir.y
		_pos.y = clampf(_pos.y, 0.0, maxf(bounds.y - BOX_SIZE.y, 0.0))

	queue_redraw()


func _process(_delta: float) -> void:
	var s := BuildInfo.stamp()
	_hud.text = (
		"OogOog M0  •  %s  •  %d fps  •  move_speed %.0f"
		% [s.get("commit", "?"), Engine.get_frames_per_second(), _speed]
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("101820"))
	draw_rect(Rect2(_pos, BOX_SIZE), Color("4fc3f7"))
