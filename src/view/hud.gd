class_name Hud
extends Control
## Screen-space overlay: the build stamp, and nothing else.
##
## Ammo pips used to live here, at the bottom of the screen. They moved into
## GameView and are now drawn in world space under the player — counting rounds
## should not mean looking away from the fight. There is deliberately no
## duplicate readout: two places showing the same number is two places to drift.

var _info: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 13)
	_info.modulate = Color(1, 1, 1, 0.55)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)

	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


func _apply_safe_area() -> void:
	# The Pixel 9's cutout sits exactly where a top-left HUD line would go.
	var inset := SafeArea.margins(get_viewport_rect().size)
	_info.position = Vector2(inset.x + 12.0, inset.y + 6.0)


func _process(_delta: float) -> void:
	# No queue_redraw(): with the pips gone this node has no _draw() at all, and
	# asking for a repaint every frame of something that never paints is the kind
	# of leftover that outlives the reason for it.
	var s := BuildInfo.stamp()
	_info.text = "%s  •  %d fps" % [s.get("commit", "?"), Engine.get_frames_per_second()]
