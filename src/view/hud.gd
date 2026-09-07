class_name Hud
extends Control
## Glanceable combat UI: quiver pips and build info.
##
## Ammo was previously a line of debug text, which is unreadable mid-fight. Pips
## are the Brawl Stars solution and they work because they are countable at a
## glance without reading.

var quiver: int = 0
var capacity: int = 3
var draw_strength: float = 0.0

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
	var s := BuildInfo.stamp()
	_info.text = "%s  •  %d fps" % [s.get("commit", "?"), Engine.get_frames_per_second()]
	queue_redraw()


func _draw() -> void:
	_draw_quiver()


func _draw_quiver() -> void:
	var inset := SafeArea.margins(get_viewport_rect().size)
	var size := get_viewport_rect().size
	var pip_w := 26.0
	var pip_h := 8.0
	var gap := 6.0
	var total := capacity * pip_w + (capacity - 1) * gap
	var origin := Vector2((size.x - total) * 0.5, size.y - inset.w - 30.0)

	for i in capacity:
		var r := Rect2(origin + Vector2(i * (pip_w + gap), 0.0), Vector2(pip_w, pip_h))
		# Dark fill plus a light outline, so a pip reads against grass, dirt or
		# a cat standing behind it.
		draw_rect(r.grow(2.0), Color(0.05, 0.06, 0.08, 0.55))
		draw_rect(r, Color(1, 1, 1, 0.16))
		if i < quiver:
			draw_rect(r, Palette.ARROW)
		draw_rect(r.grow(2.0), Color(1, 1, 1, 0.35), false, 1.5)
