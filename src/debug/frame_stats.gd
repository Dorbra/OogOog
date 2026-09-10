class_name FrameStats
extends RefCounted
## How many frames were slow, and how slow the worst one was.
##
## The HUD has always shown fps, and fps is the wrong number. A mean of 60 with
## a 40 ms spike every time three bots panic reads as "60 fps" and feels like a
## stutter — and a stutter mid-fight is indistinguishable from a trigger that
## does not respond. Five feel PRs shipped in a row against an assumption nobody
## had ever checked, because there was no way to check it: no PC, no profiler,
## no adb logcat.
##
## So this counts the frames that missed instead of averaging the ones that did
## not. Pure logic, no nodes, so it is testable headless like everything else
## that makes a claim (ADR-0003).

## A 60 Hz frame is 16.7 ms. 20 ms is "missed the frame"; 33 ms is "dropped a
## whole one and the eye can see it".
const SLOW_MS := 20.0
const DROPPED_MS := 33.3

## Frames to discard at the start of a measurement.
##
## Loading the arena, rasterising the cat SVGs and building the debug panel all
## land in the first handful of frames. Without this, EVERY session reports a
## 300 ms worst frame from startup and the number becomes furniture nobody
## reads — which is the failure mode of most in-game performance readouts.
const WARMUP_FRAMES := 30

## Size of the rolling window, so the panel can answer "was it bad JUST NOW"
## as well as "was it bad at any point". Five seconds at 60 Hz.
const WINDOW := 300

var frames: int = 0
var slow: int = 0
var dropped: int = 0
var worst_ms: float = 0.0

var _warmup: int = 0
var _window: PackedFloat32Array = PackedFloat32Array()
var _window_at: int = 0


func _init() -> void:
	_window.resize(WINDOW)


## Call once per rendered frame with the frame's duration in seconds.
func record(delta: float) -> void:
	if _warmup < WARMUP_FRAMES:
		_warmup += 1
		return

	var ms := delta * 1000.0
	frames += 1
	worst_ms = maxf(worst_ms, ms)
	if ms >= DROPPED_MS:
		dropped += 1
	elif ms >= SLOW_MS:
		slow += 1

	_window[_window_at] = ms
	_window_at = (_window_at + 1) % WINDOW


## Worst frame in the last WINDOW frames, or 0.0 before any have been recorded.
func recent_worst_ms() -> float:
	var worst := 0.0
	for ms in _window:
		worst = maxf(worst, ms)
	return worst


## Clears everything EXCEPT the warm-up, which has already been served. Pressing
## reset on the phone means "start measuring from this fight", not "wait another
## half second first".
func reset() -> void:
	frames = 0
	slow = 0
	dropped = 0
	worst_ms = 0.0
	_window.fill(0.0)
	_window_at = 0


func describe() -> String:
	if frames == 0:
		return "frames      (warming up)"
	return (
		"\n"
		. join(
			[
				"frames      %d since reset" % frames,
				(
					"over 20 ms  %d  (%.2f%%)"
					% [slow + dropped, float(slow + dropped) * 100.0 / float(frames)]
				),
				"over 33 ms  %d  (%.2f%%)" % [dropped, float(dropped) * 100.0 / float(frames)],
				"worst       %.1f ms" % worst_ms,
				"worst (5 s) %.1f ms" % recent_worst_ms(),
			]
		)
	)
