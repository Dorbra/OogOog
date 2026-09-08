class_name MatchHud
extends Control
## Score and clock, top-centre.
##
## Readable without reading. The two scores are numerals — a five-year-old can
## count pips and compare two digits long before they can read "ROUND OVER" —
## and the clock is a draining bar rather than a number, because "the bar is
## nearly gone" needs no arithmetic at all.
##
## Separate from Hud, which keeps the build stamp and nothing else. Two nodes
## showing one number is two places to drift.

const BAR_WIDTH := 260.0
const BAR_HEIGHT := 14.0
const SCORE_GAP := 54.0

var _state: MatchState


func setup(state: MatchState) -> void:
	_state = state


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _state == null:
		return
	# Nothing to report before a match starts, and nothing to add after one
	# ends: the setup and results screens own those moments, and a live clock
	# ticking behind a finished match is just noise on top of the result.
	if _state.phase == MatchState.Phase.SETUP or _state.phase == MatchState.Phase.OVER:
		return

	var view := get_viewport_rect().size
	var inset := SafeArea.margins(view)
	var centre := view.x * 0.5
	var top := inset.y + 10.0

	_draw_clock(Vector2(centre - BAR_WIDTH * 0.5, top + 20.0))
	_draw_score(
		_state.scores[0], Vector2(centre - BAR_WIDTH * 0.5 - SCORE_GAP, top), Palette.TEAM_A
	)
	_draw_score(
		_state.scores[1], Vector2(centre + BAR_WIDTH * 0.5 + SCORE_GAP, top), Palette.TEAM_B
	)


func _draw_score(value: int, at: Vector2, colour: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := 46
	var text := str(value)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	# Outlined, because the arena underneath is mid-green and a thin glyph on it
	# is unreadable in daylight on a phone.
	draw_string_outline(
		font,
		at + Vector2(-width * 0.5, size),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		6,
		Color(0, 0, 0, 0.55)
	)
	draw_string(
		font, at + Vector2(-width * 0.5, size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour
	)


## A bar that drains, not a number that counts down. During sudden death it
## turns solid and pulses instead: the clock has stopped meaning anything, and
## showing an empty bar forever would just look broken.
func _draw_clock(at: Vector2) -> void:
	var rect := Rect2(at, Vector2(BAR_WIDTH, BAR_HEIGHT))
	draw_rect(rect.grow(3.0), Color(0, 0, 0, 0.45), true)

	if _state.sudden_death():
		var pulse := 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.006)
		draw_rect(rect, Palette.ARROW * Color(1, 1, 1, pulse), true)
		return

	var limit := maxf(Tuning.get_value("match_time_limit"), 0.01)
	var fraction := clampf(_state.remaining() / limit, 0.0, 1.0)
	draw_rect(Rect2(at, Vector2(BAR_WIDTH * fraction, BAR_HEIGHT)), Palette.ARROW, true)
