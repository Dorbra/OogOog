extends Node
## On-device developer overlay: live tuning sliders, the engine log, and build info.
##
## Without a local machine this is the ONLY channel for (a) changing how the game
## feels without a CI round trip and (b) seeing why something broke. It is built
## entirely in code — no .tscn to hand-author blind — and it is the first thing
## that must work on the phone.

const LOG_PATH := "user://logs/godot.log"
const LOG_TAIL_LINES := 200
const EDGE_MARGIN := 12.0

var _layer: CanvasLayer
var _panel: PanelContainer
var _toggle: Button
var _log_label: RichTextLabel
var _info_label: Label
var _sliders: Dictionary = {}
var _override_badge: Label
var _net_label: Label
var _address_edit: LineEdit
var _open := false

## Ticked every frame, read by the Info tab. Owned here rather than by the HUD
## because it is a developer readout, and it survives a scene change — a match
## restart must not silently reset the numbers you are in the middle of reading.
var _frames := FrameStats.new()


func _ready() -> void:
	# Release builds ship without any of this.
	if not OS.is_debug_build():
		return

	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	_build_toggle()
	_build_panel()
	_set_open(false)

	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)

	Tuning.reloaded.connect(_sync_sliders_from_tuning)


func _build_toggle() -> void:
	_toggle = Button.new()
	_toggle.text = "DBG"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle.modulate = Color(1, 1, 1, 0.55)
	_toggle.pressed.connect(func() -> void: _set_open(not _open))
	_layer.add_child(_toggle)


## Keeps the overlay clear of the camera cutout, rounded corners and the
## gesture-navigation bar. Called once both controls exist, and on resize.
func _apply_safe_area() -> void:
	# This is a plain Node, not a CanvasItem — get_viewport_rect() is not
	# available here, so go through the viewport itself.
	var inset := SafeArea.margins(get_viewport().get_visible_rect().size)

	if _toggle != null:
		_toggle.offset_left = -76.0 - inset.z
		_toggle.offset_top = inset.y
		_toggle.offset_right = -EDGE_MARGIN - inset.z
		_toggle.offset_bottom = inset.y + 56.0

	if _panel != null:
		_panel.offset_left = inset.x
		_panel.offset_top = inset.y
		_panel.offset_right = -inset.z
		_panel.offset_bottom = -inset.w


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "OogOog — debug"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: _set_open(false))
	header.add_child(close)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	tabs.add_child(_build_tuning_tab())
	tabs.add_child(_build_log_tab())
	tabs.add_child(_build_info_tab())
	tabs.add_child(_build_net_tab())


func _build_tuning_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Tuning"

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	# Above the buttons on purpose: it is the first thing to read when the game
	# is not behaving like the release notes say it should.
	_override_badge = Label.new()
	_override_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_override_badge.modulate = Color(1.0, 0.72, 0.2)
	box.add_child(_override_badge)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)

	var copy_button := Button.new()
	copy_button.text = "Copy JSON"
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.pressed.connect(_copy_tuning_json)
	buttons.add_child(copy_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(func() -> void: Tuning.save())
	buttons.add_child(save_button)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(func() -> void: Tuning.reset())
	buttons.add_child(reset_button)

	_refresh_override_badge()

	var groups := Tuning.grouped_keys()
	for group: String in groups:
		var heading := Label.new()
		heading.text = group.to_upper()
		heading.modulate = Color(0.6, 0.8, 1.0)
		box.add_child(heading)

		for key: String in groups[group]:
			box.add_child(_build_slider_row(key))

	return scroll


func _build_slider_row(key: String) -> Control:
	var row := VBoxContainer.new()

	var label := Label.new()
	label.text = "%s = %.3f" % [key, Tuning.get_value(key)]
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = Tuning.get_min(key)
	slider.max_value = Tuning.get_max(key)
	slider.step = maxf((slider.max_value - slider.min_value) / 400.0, 0.0001)
	slider.value = Tuning.get_value(key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 44)  # thumb-sized, not mouse-sized
	slider.value_changed.connect(
		func(v: float) -> void:
			Tuning.set_value(key, v)
			label.text = "%s = %.3f" % [key, v]
	)
	row.add_child(slider)

	_sliders[key] = {"slider": slider, "label": label}
	return row


## Shown only when saved on-device values are winning over the shipped ones.
##
## Without this the override is invisible: two releases were judged on values
## the device was not running, because a saved user://tuning.json silently beats
## anything shipped and survives an APK update. Reset, next to it, is the cure.
func _refresh_override_badge() -> void:
	if _override_badge == null:
		return
	var keys := Tuning.overridden_keys()
	_override_badge.visible = not keys.is_empty()
	if keys.is_empty():
		return
	_override_badge.text = (
		"%d value(s) SAVED ON THIS DEVICE, overriding the build: %s\nTap Reset to run what was shipped."
		% [keys.size(), ", ".join(keys)]
	)


func _sync_sliders_from_tuning() -> void:
	_refresh_override_badge()
	for key: String in _sliders:
		var v := Tuning.get_value(key)
		_sliders[key]["slider"].set_value_no_signal(v)
		_sliders[key]["label"].text = "%s = %.3f" % [key, v]


func _build_log_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Log"

	var buttons := HBoxContainer.new()
	box.add_child(buttons)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_refresh_log)
	buttons.add_child(refresh)

	var copy_button := Button.new()
	copy_button.text = "Copy log"
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(_read_log_tail()))
	buttons.add_child(copy_button)

	_log_label = RichTextLabel.new()
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.scroll_following = true
	_log_label.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_log_label)

	return box


func _read_log_tail() -> String:
	if not FileAccess.file_exists(LOG_PATH):
		return "(no log file at %s — file logging may be disabled)" % LOG_PATH

	var text := FileAccess.get_file_as_string(LOG_PATH)
	var lines := text.split("\n")
	var start: int = maxi(0, lines.size() - LOG_TAIL_LINES)
	return "\n".join(lines.slice(start))


func _refresh_log() -> void:
	_log_label.text = _read_log_tail()


func _build_info_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Info"

	_info_label = Label.new()
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_info_label)

	var copy_button := Button.new()
	copy_button.text = "Copy info"
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(_info_label.text))
	box.add_child(copy_button)

	# The measurement that matters is "during a fight", not "since I launched
	# the game and stood in the setup screen". Without a reset the counts are
	# dominated by whatever happened before you started paying attention.
	var reset_button := Button.new()
	reset_button.text = "Reset frame stats"
	reset_button.focus_mode = Control.FOCUS_NONE
	reset_button.pressed.connect(func() -> void: _frames.reset())
	box.add_child(reset_button)

	return box


## The tab docs/LAN_SPIKE.md has told people to open since M3.0, which until now
## did not exist.
##
## That was found while planning this branch and is recorded rather than quietly
## fixed: the spike's four questions have been "awaiting a verdict from real
## hardware" for five milestones with no build in which they could be answered,
## because the flow the document described was never built.
##
## THE NUMBER THAT MATTERS HERE IS THE PING. `feat/lan` is host-authoritative
## with no prediction and no rollback, which is the right design if a LAN
## round-trip is 5-20 ms and the wrong one if it is 200. That was assumed rather
## than measured — a deliberate choice, to avoid a whole spike PR ahead of a
## working game — so this readout is what makes the assumption falsifiable in
## ten seconds instead of leaving "it feels laggy" as the only evidence. Read it
## during a real fight, not in the lobby.
##
## ENet seeds round-trip time at 500 ms and converges over a few seconds, so the
## first reading after somebody joins is a placeholder. Give it five seconds.
func _build_net_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Net"

	_net_label = Label.new()
	_net_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_net_label)

	# The manual address, and the reason it is HERE rather than on the lobby:
	# LanBeacon's own header names AP isolation — consumer routers that drop
	# broadcast traffic between wireless clients — as the likely discovery
	# failure. When that happens ENet still connects fine by direct address, so
	# this is the fallback that turns "it found nothing" into a game. Typing an
	# IP is an adult's job, which is exactly what a developer overlay is for.
	var row := HBoxContainer.new()
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "192.168.x.x"
	_address_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_address_edit)

	var join := Button.new()
	join.text = "Join"
	join.focus_mode = Control.FOCUS_NONE
	join.pressed.connect(func() -> void: Lan.join(_address_edit.text.strip_edges()))
	row.add_child(join)
	box.add_child(row)

	var leave := Button.new()
	leave.text = "Leave"
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(func() -> void: Lan.leave())
	box.add_child(leave)

	var copy_button := Button.new()
	copy_button.text = "Copy net status"
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.pressed.connect(func() -> void: DisplayServer.clipboard_set(_net_label.text))
	box.add_child(copy_button)

	return box


## One block of text somebody can read out or paste into a chat.
##
## Every line is here because it distinguishes two failures that look identical
## on a phone: "nothing is happening" has at least four causes, and without this
## they are indistinguishable from each other.
func _describe_net() -> String:
	if Net == null or not Net.online():
		return "OFFLINE\n\nnothing is connected.\nfound on the network: %d" % _beacon_count()

	var lines: Array[String] = []
	lines.append("HOST" if Lan.hosting() else "CLIENT")
	lines.append("id      %d" % Net.local_id())
	lines.append("peers   %s" % str(Net.peer_ids()))
	# THE headline. Against the 50 ms above which this design stops being the
	# right one, so the reading carries its own verdict rather than needing one.
	var worst := Net.worst_ping_ms()
	lines.append(
		(
			"ping    %s"
			% (
				"waiting"
				if worst < 0
				else "%d ms  %s" % [worst, "OK" if worst <= 50 else "TOO HIGH — tell Claude"]
			)
		)
	)
	lines.append("seat    %d" % Lan.local_seat)
	lines.append("roster  %s" % str(Lan.roster))
	lines.append("started %s" % str(Lan.started))
	lines.append("found   %d" % _beacon_count())
	if not Net.last_error.is_empty():
		lines.append("")
		lines.append("last error: %s" % Net.last_error)
	return "\n".join(lines)


func _beacon_count() -> int:
	return Beacon.host_addresses().size() if Beacon != null else 0


func _copy_tuning_json() -> void:
	DisplayServer.clipboard_set(Tuning.to_json())


func _process(delta: float) -> void:
	# Recorded unconditionally, not only while the panel is open: the frames
	# worth knowing about are the ones during a fight, and the panel is shut
	# then. Opening it to look would otherwise reset what you came to measure.
	_frames.record(delta)

	if _open and _info_label != null:
		_info_label.text = "%s\n\n%s" % [BuildInfo.describe(), _frames.describe()]
	if _open and _log_label != null and _log_label.text.is_empty():
		_refresh_log()
	if _open and _net_label != null:
		_net_label.text = _describe_net()


func _set_open(open: bool) -> void:
	_open = open
	_panel.visible = open
	_toggle.visible = not open
	if open:
		_refresh_log()
