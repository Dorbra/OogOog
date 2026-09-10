class_name MatchScreens
extends Control
## Setup, countdown and results — one surface, drawn by hand.
##
## No text anywhere. A five-year-old cannot read "3v3" or "TEAM BLUE WINS", so
## every screen is cats, colour and numerals: pick how many cats a side by
## tapping that many cats, watch three numerals count down, then see one team
## standing and one team sitting. This is the constraint recorded in ADR-0013,
## and it is the reason these are drawn rather than assembled from Buttons —
## Godot's default theme would put grey text chrome on all three.

## The chosen side size, 1 to MAX.
signal size_chosen(size: int)

## The results screen was tapped.
signal dismissed

const BODY_PATH := "res://assets/cats/cat_body.svg"
const FACE_PATH := "res://assets/cats/cat_face.svg"

const MAX_SIZE := 3
const ICON := 132.0
const ICON_GAP := 40.0

## The class row sits above the team-size row and is drawn with the SAME cat
## icon, distinguished only by the gun in its paws. That is deliberate: the gun
## silhouette is what tells a class apart mid-fight, so the picker teaches the
## exact symbol the game then uses. A different icon here would teach a symbol
## that appears nowhere else.
const CLASS_ICON := 118.0
const CLASS_GAP := 56.0

var _state: MatchState
var _body: Texture2D
var _face: Texture2D
var _hover: int = 0


func setup(state: MatchState) -> void:
	_state = state


func _ready() -> void:
	_body = load(BODY_PATH)
	_face = load(FACE_PATH)
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)


## Give this Control a real rect.
##
## THIS IS LOAD-BEARING AND WAS MISSING. A Control parented to a CanvasLayer has
## no Control parent for anchors to resolve against, so
## `set_anchors_preset(PRESET_FULL_RECT)` left it at size (0, 0) — and a
## zero-size Control can never be hit, so `_gui_input()` never fired and the
## setup screen could not be dismissed at all. The game was stuck on its first
## screen and tapping did nothing.
##
## It drew perfectly the whole time, because `_draw()` is not clipped by the
## Control's rect and every layout here is computed from `get_viewport_rect()`.
## So every render capture looked right while the screen was completely dead,
## which is the whole lesson of ADR-0019: appearance is not behaviour.
##
## The anchors are pinned TOP_LEFT rather than FULL_RECT, and that is the only
## thing here that is about tidiness. FULL_RECT gives the node non-equal opposite
## anchors, which is Godot's signal that the layout system owns its rect — so
## assigning `size` a line later warned on every single boot, into the middle of
## the smoke test's output, where a real error could hide behind it. All four
## anchors equal means there is nothing claiming to override the rect, and the
## assignment below is its only author. Measured before and after: the rect is
## the same on every frame, resize included.
##
## `set_deferred("size", ...)`, which is what the warning itself suggests, was
## tried and is wrong on both counts. It leaves the Control at (0, 0) for the
## whole of `_ready()` — the shipped bug again, in a one-frame window that
## `verify_ui.gd` would not catch, because it waits two frames before looking.
## And it does not even silence the warning: the deferred set runs before the
## deferred callback that clears the warning flag, so it still prints.
func _fit_to_viewport() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _process(_delta: float) -> void:
	# Only the countdown animates, but redrawing unconditionally costs nothing
	# on a screen that is up for at most a few seconds at a time.
	visible = _state != null and _state.phase != MatchState.Phase.LIVE
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _state == null:
		return

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

	if _state.phase == MatchState.Phase.OVER:
		dismissed.emit()
		accept_event()
		return

	if _state.phase == MatchState.Phase.SETUP:
		# Classes first: tapping one changes the pick and leaves the screen up,
		# so a five-year-old can try both and watch the gun change before
		# committing to anything.
		for i in FighterClass.count():
			if _class_rect(i).has_point(at):
				Tuning.set_value("player_class", float(i))
				accept_event()
				return
		for i in MAX_SIZE:
			if _slot_rect(i).has_point(at):
				size_chosen.emit(i + 1)
				accept_event()
				return
		if _play_rect().has_point(at):
			size_chosen.emit(int(Tuning.get_value("bot_team_size")))
			accept_event()


# ------------------------------------------------------------------- geometry


func _slot_rect(index: int) -> Rect2:
	var view := get_viewport_rect().size
	var span := MAX_SIZE * ICON + (MAX_SIZE - 1) * ICON_GAP
	var left := view.x * 0.5 - span * 0.5
	return Rect2(
		Vector2(left + float(index) * (ICON + ICON_GAP), view.y * 0.34), Vector2(ICON, ICON)
	)


func _class_rect(index: int) -> Rect2:
	var view := get_viewport_rect().size
	var count := maxi(FighterClass.count(), 1)
	var span := float(count) * CLASS_ICON + float(count - 1) * CLASS_GAP
	var left := view.x * 0.5 - span * 0.5
	return Rect2(
		Vector2(left + float(index) * (CLASS_ICON + CLASS_GAP), view.y * 0.06),
		Vector2(CLASS_ICON, CLASS_ICON)
	)


func _play_rect() -> Rect2:
	var view := get_viewport_rect().size
	return Rect2(Vector2(view.x * 0.5 - 90.0, view.y * 0.66), Vector2(180.0, 110.0))


# -------------------------------------------------------------------- drawing


func _draw() -> void:
	if _state == null:
		return
	match _state.phase:
		MatchState.Phase.SETUP:
			# As opaque as the results screen: at 0.72 the arena and the HUD read
			# straight through and the picker looked like a bug on top of a game
			# rather than a screen in its own right.
			_draw_dim(0.92)
			_draw_setup()
		MatchState.Phase.COUNTDOWN:
			_draw_countdown()
		MatchState.Phase.OVER:
			# Nearly opaque. At 0.6 the arena, the health bars and the quiver
			# pips all read straight through and the screen looked like a bug
			# rather than a result.
			_draw_dim(0.95)
			_draw_results()
		_:
			pass


func _draw_dim(alpha: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.05, 0.12, 0.06, alpha), true)


## Alpha is passed in rather than derived from a "faded" flag. The two callers
## want genuinely different things and a shared boolean quietly served neither:
## the results screen needs losers that look beaten but readable (0.6), while
## the picker needs unchosen cats that are obviously OFF (0.2). Tuning the flag
## for one made the other wrong.
func _draw_cat(rect: Rect2, tint: Color, alpha: float) -> void:
	draw_texture_rect(_body, rect, false, Color(tint.r, tint.g, tint.b, alpha))
	draw_texture_rect(_face, rect, false, Color(1, 1, 1, alpha))


## Tap the third cat and you get three a side. The row IS the number — there is
## nothing else to understand, and nothing to read.
func _draw_setup() -> void:
	_draw_class_row()

	var chosen := clampi(int(Tuning.get_value("bot_team_size")), 1, MAX_SIZE)
	for i in MAX_SIZE:
		var rect := _slot_rect(i)
		var lit := i < chosen
		_draw_cat(rect, Palette.TEAM_A, 1.0 if lit else 0.2)
		if lit:
			draw_arc(
				rect.get_center() + Vector2(0, 4), ICON * 0.46, 0.0, TAU, 40, Palette.ARROW, 5.0
			)

	# A play triangle: the one universally understood glyph on a phone.
	var play := _play_rect()
	var c := play.get_center()
	var h := play.size.y * 0.5
	draw_colored_polygon(
		PackedVector2Array(
			[c + Vector2(-h * 0.7, -h), c + Vector2(-h * 0.7, h), c + Vector2(h * 0.95, 0.0)]
		),
		Palette.ARROW
	)


## One cat per class, each holding its own gun, the picked one lit.
func _draw_class_row() -> void:
	var picked := clampi(int(Tuning.get_value("player_class")), 0, FighterClass.count() - 1)
	for i in FighterClass.count():
		var rect := _class_rect(i)
		var lit := i == picked
		# 0.45 rather than the team row's 0.2. Those two rows are asking
		# different questions: an unlit cat there means "not this many", and
		# reads correctly as absent. An unlit class here is still an OPTION, and
		# at 0.25 against the dimmed arena it read as a shadow rather than as
		# something to tap — which for a non-reader is the whole instruction.
		var alpha := 1.0 if lit else 0.45
		_draw_cat(rect, Palette.CAT_PLAYER, alpha)
		_draw_class_gun(FighterClass.at(i), rect, alpha)
		if lit:
			draw_arc(
				rect.get_center() + Vector2(0, 4),
				CLASS_ICON * 0.52,
				0.0,
				TAU,
				40,
				Palette.ARROW,
				5.0
			)


## The same silhouette CatView draws in the fight, at rest pointing right.
##
## Deliberately NOT shared code with CatView. That one is a Node2D drawing in
## world space around a cat's own origin; this fills a rect on a CanvasLayer.
## Sharing them would mean a coordinate-space adapter for the sake of a dozen
## lines, and the thing that actually has to match is the PROPORTIONS — long and
## thin against short and wide — which is what a player learns to read.
func _draw_class_gun(cls: FighterClass, rect: Rect2, alpha: float) -> void:
	var size := rect.size.x * 0.30
	var origin := rect.get_center() + Vector2(rect.size.x * 0.10, rect.size.y * 0.16)
	var spread := cls.pellets > 1
	var length := size * (0.85 if spread else 1.45)
	var half := size * (0.30 if spread else 0.19)
	var muzzle := origin + Vector2(length, 0.0)

	var barrel := Palette.ARROW.darkened(0.35)
	barrel.a = alpha
	draw_colored_polygon(
		PackedVector2Array(
			[
				origin + Vector2(0.0, -half),
				muzzle + Vector2(0.0, -half),
				muzzle + Vector2(0.0, half),
				origin + Vector2(0.0, half),
			]
		),
		barrel
	)

	var tip := Palette.ARROW_TIP
	tip.a = alpha
	if not spread:
		draw_circle(muzzle, size * 0.24, tip)
		return
	var pitch := half * 1.35
	for i in cls.pellets:
		var offset := -pitch + pitch * 2.0 * float(i) / float(maxi(cls.pellets - 1, 1))
		draw_circle(muzzle + Vector2(0.0, offset), size * 0.15, tip)


func _draw_countdown() -> void:
	var seconds := int(ceil(_state.countdown))
	if seconds <= 0:
		return
	var view := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	var size := 150
	var text := str(seconds)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(view.x * 0.5 - width * 0.5, view.y * 0.5 + size * 0.35)
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 16, Color(0, 0, 0, 0.6)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.ARROW)


## Winners standing large, losers small and dimmed, and the two scores. No
## per-player statistics on purpose: publishing who died most, every round, to
## a five-year-old is the opposite of "competitive but not punishing".
func _draw_results() -> void:
	var view := get_viewport_rect().size
	var winner := _state.winner
	var win_colour := Palette.TEAM_A if winner == 0 else Palette.TEAM_B
	var lose_colour := Palette.TEAM_B if winner == 0 else Palette.TEAM_A
	var size := clampi(int(Tuning.get_value("bot_team_size")), 1, MAX_SIZE)

	var big := 200.0
	var span := float(size) * big + float(size - 1) * 30.0
	var left := view.x * 0.5 - span * 0.5
	for i in size:
		# A slow bob, so the winners read as celebrating rather than as a still.
		var bob := sin(float(Time.get_ticks_msec()) * 0.004 + float(i) * 0.9) * 14.0
		var rect := Rect2(
			Vector2(left + float(i) * (big + 30.0), view.y * 0.10 + bob), Vector2(big, big)
		)
		_draw_cat(rect, win_colour, 1.0)

	var small := 88.0
	var lose_span := float(size) * small + float(size - 1) * 18.0
	var lose_left := view.x * 0.5 - lose_span * 0.5
	for i in size:
		var rect := Rect2(
			Vector2(lose_left + float(i) * (small + 18.0), view.y * 0.72), Vector2(small, small)
		)
		_draw_cat(rect, lose_colour, 0.6)

	_draw_result_score()


## Each numeral in its own team's colour. White on both said "here are two
## numbers" and left which-is-whose to be worked out; the colours say it
## outright, which is the only way it says anything at all to a non-reader.
func _draw_result_score() -> void:
	var view := get_viewport_rect().size
	var y := view.y * 0.62
	_draw_numeral(_state.scores[0], Vector2(view.x * 0.5 - 60.0, y), Palette.TEAM_A)
	_draw_numeral(_state.scores[1], Vector2(view.x * 0.5 + 60.0, y), Palette.TEAM_B)


func _draw_numeral(value: int, centre: Vector2, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := 76
	var text := str(value)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := centre - Vector2(width * 0.5, 0.0)
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 12, Color(0, 0, 0, 0.75)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)
