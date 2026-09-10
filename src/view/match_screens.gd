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

## Smaller than the class cards, deliberately. These two rows are not equal
## decisions: which cat you are shapes the whole match, how many a side is a
## setup detail you pick once. At 132 px the size row was the loudest thing on
## the screen and the class cards read as a header above it — the importance
## inverted, which is its own kind of "not clear".
const ICON := 88.0
const ICON_GAP := 34.0

## The class row sits above the team-size row and is drawn with the SAME cat
## icon, distinguished only by the gun in its paws. That is deliberate: the gun
## silhouette is what tells a class apart mid-fight, so the picker teaches the
## exact symbol the game then uses. A different icon here would teach a symbol
## that appears nowhere else.
## A class CARD, not an icon. The first APK playtest came back with "there is no
## class selection, or am I missing something? all the icons look identical" —
## and it was right. Two copies of the same cat sprite differing by a few pixels
## of gun silhouette read as decoration, not as a choice, and nothing on the
## screen said which row meant "who am I" and which meant "how many of us".
##
## So a class is now a panel with its own name, its weapon drawn large enough to
## actually see, three comparable bars and its ability symbol.
const CARD_W := 340.0
const CARD_H := 244.0
const CARD_GAP := 44.0

## Bars, in the order they are drawn. The label is Hebrew because the ten-year-
## old and the adult both read it; the BAR is what carries the meaning for the
## five-year-old, who does not (ADR-0013). Text is the addition here, never the
## foundation.
const STAT_ROWS := [
	{"key": "reach", "label": "טווח"},
	{"key": "damage", "label": "נזק"},
	{"key": "health", "label": "חיים"},
]

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
	var area := _usable()
	var span := MAX_SIZE * ICON + (MAX_SIZE - 1) * ICON_GAP
	var left := area.position.x + area.size.x * 0.5 - span * 0.5
	var top := _class_rect(0).end.y + 62.0
	return Rect2(Vector2(left + float(index) * (ICON + ICON_GAP), top), Vector2(ICON, ICON))


## The area the setup screen may draw in.
##
## SAFE AREA, which this file did not use at all. Every other screen in the
## project does — the Pixel 9's cutout and gesture bar eat exactly the edges the
## class row was sitting against, at 6% from the top. It had not clipped the row
## yet, but it was a matter of which phone.
func _usable() -> Rect2:
	var view := get_viewport_rect().size
	var inset := SafeArea.margins(view)
	return Rect2(
		Vector2(inset.x, inset.y), Vector2(view.x - inset.x - inset.z, view.y - inset.y - inset.w)
	)


func _class_rect(index: int) -> Rect2:
	var area := _usable()
	var count := maxi(FighterClass.count(), 1)
	var span := float(count) * CARD_W + float(count - 1) * CARD_GAP
	var left := area.position.x + area.size.x * 0.5 - span * 0.5
	return Rect2(
		Vector2(left + float(index) * (CARD_W + CARD_GAP), area.position.y + area.size.y * 0.09),
		Vector2(CARD_W, CARD_H)
	)


func _play_rect() -> Rect2:
	var area := _usable()
	var top := _slot_rect(0).end.y + 26.0
	return Rect2(Vector2(area.position.x + area.size.x * 0.5 - 90.0, top), Vector2(180.0, 92.0))


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

	_draw_heading("כמה בכל קבוצה", _slot_rect(0).position.y - 28.0)

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


## Two class cards, the picked one lit and ringed.
func _draw_class_row() -> void:
	var picked := clampi(int(Tuning.get_value("player_class")), 0, FighterClass.count() - 1)
	_draw_heading("בחרו דמות", _class_rect(0).position.y - 30.0)
	for i in FighterClass.count():
		_draw_class_card(FighterClass.at(i), _class_rect(i), i == picked)


## A heading, centred, in the same warm colour as everything else selectable.
##
## Text at all is new to this game. It exists because the first playtest could
## not tell what the screen was asking — "the first window is not clear at all".
## Two rows of cats with nothing to say which was which is a puzzle, not a menu.
func _draw_heading(text: String, y: float) -> void:
	var area := _usable()
	var font := ThemeDB.fallback_font
	var size := 26
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(area.position.x + area.size.x * 0.5 - width * 0.5, y)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.8))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.82))


func _draw_class_card(cls: FighterClass, rect: Rect2, lit: bool) -> void:
	var alpha := 1.0 if lit else 0.5

	# A panel behind each class, which is most of what makes this read as a
	# CHOICE rather than as scenery. Two loose cats on a background do not.
	var fill := Color(0.10, 0.16, 0.11, 0.92 if lit else 0.55)
	draw_rect(rect, fill, true)
	draw_rect(
		rect,
		Color(Palette.ARROW.r, Palette.ARROW.g, Palette.ARROW.b, 0.9 if lit else 0.25),
		false,
		4.0
	)

	# The cat, left, at a size where its weapon is legible.
	var cat := Rect2(rect.position + Vector2(16.0, 14.0), Vector2(104.0, 104.0))
	_draw_cat(cat, Palette.CAT_PLAYER, alpha)
	_draw_class_gun(cls, cat, alpha)

	# The name, right of the cat, on its own line.
	var font := ThemeDB.fallback_font
	var name_at := Vector2(rect.position.x + 138.0, rect.position.y + 62.0)
	var name_colour := Palette.ARROW if lit else Color(1, 1, 1, 0.55)
	draw_string_outline(
		font, name_at, cls.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 7, Color(0, 0, 0, 0.85)
	)
	draw_string(font, name_at, cls.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, name_colour)

	_draw_ability_glyph(cls, Vector2(rect.end.x - 46.0, rect.position.y + 44.0), alpha)
	_draw_stat_bars(cls, rect, alpha)


## Three bars per class, each scaled against the BEST class on that row.
##
## Comparable by construction: a full bar means "the most of this in the game",
## so two cards side by side can be read against each other without any numbers.
## That is what makes this work for somebody who cannot read the labels.
func _draw_stat_bars(cls: FighterClass, rect: Rect2, alpha: float) -> void:
	var font := ThemeDB.fallback_font
	var bar_w := rect.size.x - 132.0
	var x := rect.position.x + 118.0
	var y := rect.position.y + 128.0

	for row: Dictionary in STAT_ROWS:
		var key: String = row["key"]
		var value := _stat_of(cls, key)
		var best := 0.0
		for other_id in FighterClass.all():
			best = maxf(best, _stat_of(FighterClass.get_class_by_id(other_id), key))
		var fraction: float = clampf(value / maxf(best, 0.001), 0.0, 1.0)

		var label: String = row["label"]
		var label_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(
			font,
			Vector2(rect.position.x + 110.0 - label_w, y + 13.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(1, 1, 1, 0.6 * alpha)
		)

		var track := Rect2(Vector2(x, y), Vector2(bar_w, 14.0))
		draw_rect(track, Color(0, 0, 0, 0.45 * alpha), true)
		draw_rect(
			Rect2(track.position, Vector2(bar_w * fraction, track.size.y)),
			Color(Palette.ARROW.r, Palette.ARROW.g, Palette.ARROW.b, 0.9 * alpha),
			true
		)
		y += 26.0


func _stat_of(cls: FighterClass, key: String) -> float:
	match key:
		"reach":
			return cls.reach_mult
		"damage":
			return cls.burst_damage_mult()
		"health":
			return cls.health_mult
		_:
			return 0.0


## The ability, as a shape rather than a word.
##
## A dash is a pair of chevrons pointing the way you go; caltrops are a ring of
## spikes. Neither needs reading, and both are the same shapes the ability draws
## in the fight, so the card teaches what the game then shows.
func _draw_ability_glyph(cls: FighterClass, centre: Vector2, alpha: float) -> void:
	var tint := Palette.ARROW_TIP
	tint.a = alpha
	match cls.ability:
		"dash":
			for i in 2:
				var ox := -10.0 + float(i) * 14.0
				draw_colored_polygon(
					PackedVector2Array(
						[
							centre + Vector2(ox - 6.0, -14.0),
							centre + Vector2(ox + 8.0, 0.0),
							centre + Vector2(ox - 6.0, 14.0),
							centre + Vector2(ox - 1.0, 0.0),
						]
					),
					tint
				)
		"caltrops":
			draw_arc(centre, 17.0, 0.0, TAU, 28, Color(tint.r, tint.g, tint.b, 0.45 * alpha), 2.5)
			for i in 6:
				var angle := TAU * float(i) / 6.0
				draw_circle(centre + Vector2(cos(angle), sin(angle)) * 10.0, 3.6, tint)
		_:
			pass


## The same silhouette CatView draws in the fight, drawn LARGE.
##
## Deliberately not shared code with CatView: that one is a Node2D drawing in
## world space around a cat's own origin, this fills a rect on a CanvasLayer.
## What has to match is the PROPORTIONS — long and thin against short and wide
## with a row of muzzles — because that is the symbol a player learns to read
## across a battlefield.
func _draw_class_gun(cls: FighterClass, rect: Rect2, alpha: float) -> void:
	var size := rect.size.x * 0.40
	var origin := rect.get_center() + Vector2(rect.size.x * 0.12, rect.size.y * 0.14)
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
