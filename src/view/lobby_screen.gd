class_name LobbyScreen
extends Control
## The screen that decides whether this is one phone or three.
##
## It is the first thing anybody sees, and it is the reason `feat/lan` needed UI
## at all rather than just a transport. The M3.0 spike planned to drive hosting
## from a DBG tab; that is fine for answering a latency question and useless as
## a product, because the people joining are 5 and 10 and cannot be asked to
## open a developer overlay — nor to read the words in it.
##
## SO THERE IS NO TEXT ON THIS SCREEN. Three pictures:
##
##     a cat                one phone, against bots — the game as it was
##     a cat and a plus     be the one everybody joins
##     a cat and a lens     go and find somebody who already is
##
## and then, for whoever is looking, a row of cats — one per game found on the
## network — that you tap to join.
##
## NOTHING NAMES THOSE GAMES, and that is a real limitation rather than a
## decision: two games running in the same house are told apart only by their
## order in the row. The beacon carries a device name and this screen could draw
## it, but drawing it means text, and text is the thing this screen exists not
## to need (ADR-0013). One adult with one phone means one host, so the case is
## hypothetical today — if it ever stops being, the answer is a per-host colour,
## not a label.
##
## It draws itself on a CanvasLayer ABOVE MatchScreens rather than becoming a
## fourth phase of it. The two screens answer different questions — "who is
## playing" and "what are we playing" — and MatchScreens is already 534 lines
## carrying three states; a fourth would have made the file the thing nobody
## wants to open.

## The lobby is finished with and the local game may begin. Carries no argument:
## whether this device ends up hosting, joined or alone is Lan's business, and
## main.gd asks it rather than being told twice.
signal ready_to_play

enum Mode {
	## Nothing decided yet: the three big choices.
	CHOOSING,
	## Hosting and waiting for people. Shows who has arrived.
	HOSTING,
	## Listening for games. Shows what the beacon has heard.
	LOOKING,
	## Joined somebody. Pick a class and wait for them to start.
	WAITING,
}

const BODY_PATH := "res://assets/cats/cat_body.svg"
const FACE_PATH := "res://assets/cats/cat_face.svg"

const CHOICE_W := 300.0
const CHOICE_H := 260.0
const CHOICE_GAP := 40.0

## A row of found games, and the class row a joiner picks from.
const ROW_ICON := 96.0
const ROW_GAP := 28.0

var mode: int = Mode.CHOOSING

var _body: Texture2D
var _face: Texture2D
var _found: Array = []


func _ready() -> void:
	_body = load(BODY_PATH)
	_face = load(FACE_PATH)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	Lan.match_started_remotely.connect(_on_host_started)


## Same trap, same fix as MatchScreens._fit_to_viewport(): a Control parented to
## a CanvasLayer has no Control parent for anchors to resolve against, so a
## preset leaves it at size (0, 0) — invisible to every tap while drawing
## perfectly. That shipped once already and is what ADR-0019 is about.
func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _process(_delta: float) -> void:
	if not visible:
		return
	if mode == Mode.LOOKING:
		_found = Beacon.host_addresses()
	queue_redraw()


## The host pressed play. Leave, and let main build the world for the match.
func _on_host_started() -> void:
	visible = false
	ready_to_play.emit()


# ----------------------------------------------------------------------- input


func _gui_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	if not pressed:
		return

	var at: Vector2 = (
		(event as InputEventMouse).position
		if event is InputEventMouse
		else (event as InputEventScreenTouch).position
	)

	match mode:
		Mode.CHOOSING:
			_tap_choice(at)
		Mode.HOSTING:
			_tap_hosting(at)
		Mode.LOOKING:
			_tap_looking(at)
		Mode.WAITING:
			_tap_waiting(at)


func _tap_choice(at: Vector2) -> void:
	if _choice_rect(0).has_point(at):
		# Alone is the path that must never break: it is the game as it shipped,
		# with no socket open at all.
		Lan.leave()
		visible = false
		ready_to_play.emit()
		accept_event()
		return

	if _choice_rect(1).has_point(at):
		if Lan.start_hosting():
			mode = Mode.HOSTING
		accept_event()
		return

	if _choice_rect(2).has_point(at):
		Lan.start_looking()
		mode = Mode.LOOKING
		_found = []
		accept_event()


func _tap_hosting(at: Vector2) -> void:
	# The host's play button. Everyone connected comes along; anyone who has not
	# arrived yet is a bot, which is the same rule that fills every empty slot.
	if _go_rect().has_point(at):
		visible = false
		ready_to_play.emit()
		accept_event()
		return
	if _back_rect().has_point(at):
		Lan.leave()
		mode = Mode.CHOOSING
		accept_event()


func _tap_looking(at: Vector2) -> void:
	for i in _found.size():
		if _row_rect(i).has_point(at):
			if Lan.join(str(_found[i])):
				mode = Mode.WAITING
				Lan.publish_class(int(Tuning.get_value("player_class")))
			accept_event()
			return
	if _back_rect().has_point(at):
		Lan.leave()
		mode = Mode.CHOOSING
		accept_event()


func _tap_waiting(at: Vector2) -> void:
	# A joiner picks a class here rather than on the setup screen, because the
	# setup screen belongs to whoever is hosting — they choose the team size and
	# they press start. This is the one decision a joiner owns.
	for i in FighterClass.count():
		if _row_rect(i).has_point(at):
			Tuning.set_value("player_class", float(i))
			Lan.publish_class(i)
			accept_event()
			return
	if _back_rect().has_point(at):
		Lan.leave()
		mode = Mode.CHOOSING
		accept_event()


# -------------------------------------------------------------------- geometry


func _usable() -> Rect2:
	var view := get_viewport_rect().size
	var inset := SafeArea.margins(view)
	return Rect2(
		Vector2(inset.x, inset.y), Vector2(view.x - inset.x - inset.z, view.y - inset.y - inset.w)
	)


func _choice_rect(index: int) -> Rect2:
	var area := _usable()
	var span := 3.0 * CHOICE_W + 2.0 * CHOICE_GAP
	var left := area.position.x + area.size.x * 0.5 - span * 0.5
	var top := area.position.y + area.size.y * 0.5 - CHOICE_H * 0.5
	return Rect2(
		Vector2(left + float(index) * (CHOICE_W + CHOICE_GAP), top), Vector2(CHOICE_W, CHOICE_H)
	)


## One entry in whichever row this mode is showing — found games, or classes.
func _row_rect(index: int) -> Rect2:
	var area := _usable()
	var count := maxi(_row_count(), 1)
	var span := float(count) * ROW_ICON + float(count - 1) * ROW_GAP
	var left := area.position.x + area.size.x * 0.5 - span * 0.5
	var top := area.position.y + area.size.y * 0.42
	return Rect2(
		Vector2(left + float(index) * (ROW_ICON + ROW_GAP), top), Vector2(ROW_ICON, ROW_ICON)
	)


func _row_count() -> int:
	match mode:
		Mode.LOOKING:
			return _found.size()
		Mode.WAITING:
			return FighterClass.count()
		Mode.HOSTING:
			return maxi(Lan.human_count(), 1)
		_:
			return 0


## The host's start button. Big, central, and the same green arrow the setup
## screen uses, so "this one starts things" is learned once.
func _go_rect() -> Rect2:
	var area := _usable()
	return Rect2(
		Vector2(area.position.x + area.size.x * 0.5 - 100.0, area.position.y + area.size.y * 0.66),
		Vector2(200.0, 104.0)
	)


func _back_rect() -> Rect2:
	var area := _usable()
	return Rect2(area.position + Vector2(8.0, 8.0), Vector2(96.0, 84.0))


# --------------------------------------------------------------------- drawing


func _draw() -> void:
	# Opaque, not a wash. At 0.94 the match HUD underneath bled through and drew
	# a score before any match had been played — two numerals that mean nothing
	# yet, on the first screen a five-year-old sees.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.08, 0.05, 1.0))
	match mode:
		Mode.CHOOSING:
			_draw_choices()
		Mode.HOSTING:
			_draw_hosting()
		Mode.LOOKING:
			_draw_looking()
		Mode.WAITING:
			_draw_waiting()


func _draw_choices() -> void:
	for i in 3:
		var rect := _choice_rect(i)
		_draw_frame(rect, i == 0)
		var centre := rect.get_center() + Vector2(0.0, -18.0)
		# The joiner's cat is CAT_REMOTE blue — "another person, not a bot" — and
		# emphatically not TEAM_B red, which is the enemy tint everywhere else in
		# the game. A card that says "go and find your family" must not be
		# coloured like the people you shoot.
		#
		# That colour was defined for the spike's remote cats and lost its only
		# reader when they were deleted this branch; this is the right home for
		# it rather than a constant nothing uses.
		_draw_cat(centre, 112.0, Palette.CAT_PLAYER if i < 2 else Palette.CAT_REMOTE)
		match i:
			1:
				_draw_plus(Vector2(rect.end.x - 58.0, rect.position.y + 58.0), 26.0)
			2:
				_draw_lens(Vector2(rect.end.x - 58.0, rect.position.y + 58.0), 24.0)
			_:
				pass


func _draw_hosting() -> void:
	_draw_back()
	# Everyone in the room, as cats. The row growing by one when a phone joins is
	# the entire feedback that joining worked, and it needs no words.
	for i in _row_count():
		var rect := _row_rect(i)
		_draw_frame(rect, true)
		_draw_cat(rect.get_center(), ROW_ICON * 0.86, Palette.TEAM_A)
	_draw_go()


func _draw_looking() -> void:
	_draw_back()
	if _found.is_empty():
		# A pulsing lens rather than "searching…". Nothing else on this screen is
		# written down and this is the moment a five-year-old is most likely to
		# be looking at it.
		var beat := 1.0 + 0.12 * sin(float(Time.get_ticks_msec()) * 0.005)
		_draw_lens(_usable().get_center(), 54.0 * beat)
		return

	for i in _found.size():
		var rect := _row_rect(i)
		_draw_frame(rect, true)
		_draw_cat(rect.get_center(), ROW_ICON * 0.86, Palette.TEAM_A)


func _draw_waiting() -> void:
	_draw_back()
	var chosen := int(Tuning.get_value("player_class"))
	for i in FighterClass.count():
		var rect := _row_rect(i)
		_draw_frame(rect, i == chosen)
		_draw_cat(rect.get_center(), ROW_ICON * 0.86, Palette.TEAM_A)

	# Three dots breathing under the row: the host has not started yet. Again no
	# words — this is the state a joiner sits in longest.
	var area := _usable()
	var at := Vector2(area.position.x + area.size.x * 0.5, area.position.y + area.size.y * 0.70)
	for i in 3:
		var phase := float(Time.get_ticks_msec()) * 0.004 + float(i) * 0.7
		var lift := sin(phase) * 9.0
		draw_circle(at + Vector2(float(i - 1) * 34.0, lift), 9.0, Palette.ARROW)


func _draw_back() -> void:
	var rect := _back_rect()
	var mid := rect.get_center()
	# A left chevron. The one gesture every phone user already knows.
	var arm := rect.size.y * 0.28
	draw_line(mid + Vector2(arm * 0.6, -arm), mid + Vector2(-arm * 0.4, 0.0), Palette.ARROW, 7.0)
	draw_line(mid + Vector2(-arm * 0.4, 0.0), mid + Vector2(arm * 0.6, arm), Palette.ARROW, 7.0)


func _draw_go() -> void:
	var rect := _go_rect()
	var mid := rect.get_center()
	var w := rect.size.x * 0.26
	var h := rect.size.y * 0.34
	draw_colored_polygon(
		PackedVector2Array([mid + Vector2(-w, -h), mid + Vector2(w, 0.0), mid + Vector2(-w, h)]),
		Palette.ARROW
	)


func _draw_frame(rect: Rect2, lit: bool) -> void:
	draw_rect(rect, Color(0.07, 0.13, 0.09, 0.92))
	draw_rect(rect, Palette.ARROW if lit else Palette.ARROW.darkened(0.55), false, 3.0)


## The same two-layer cat the rest of the game draws: a tinted body with an
## untinted face over it. Reused rather than redrawn so the animal on this
## screen is recognisably the animal in the fight.
func _draw_cat(centre: Vector2, height: float, tint: Color) -> void:
	if _body == null or _face == null:
		return
	var scale_factor := height / 128.0
	var box := Vector2(128.0, 128.0) * scale_factor
	var at := Rect2(centre - box * 0.5, box)
	draw_texture_rect(_body, at, false, tint)
	draw_texture_rect(_face, at, false, Color.WHITE)


func _draw_plus(centre: Vector2, arm: float) -> void:
	draw_line(centre - Vector2(arm, 0.0), centre + Vector2(arm, 0.0), Palette.ARROW, 8.0)
	draw_line(centre - Vector2(0.0, arm), centre + Vector2(0.0, arm), Palette.ARROW, 8.0)


func _draw_lens(centre: Vector2, radius: float) -> void:
	draw_arc(centre, radius, 0.0, TAU, 36, Palette.ARROW, 7.0)
	var off := Vector2(0.7071, 0.7071) * radius
	draw_line(centre + off, centre + off * 1.7, Palette.ARROW, 8.0)
