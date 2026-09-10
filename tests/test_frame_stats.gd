extends RefCounted
## The on-device frame readout, which is the only profiler this project has.
##
## Nobody involved can attach a debugger to the phone, so if this counter is
## wrong there is no second opinion — a silently broken performance readout is
## worse than none, because it is trusted. Hence assertions on the boundaries
## rather than on "it produces a number".

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## Feeds `count` frames of `ms` each, past the warm-up.
func _warmed() -> FrameStats:
	var stats := FrameStats.new()
	for _i in FrameStats.WARMUP_FRAMES:
		stats.record(0.016)
	return stats


func test_warmup_frames_are_discarded() -> void:
	_case = "warm-up"
	var stats := FrameStats.new()
	# Startup frames are enormous — loading the arena, rasterising the cats,
	# building the panel. Counting them makes every session report a disaster.
	for _i in FrameStats.WARMUP_FRAMES:
		stats.record(0.400)

	_runner.check(stats.frames == 0, _fail("counted %d warm-up frames" % stats.frames))
	_runner.check(stats.worst_ms == 0.0, _fail("warm-up set worst to %.1f" % stats.worst_ms))

	stats.record(0.010)
	_runner.check(stats.frames == 1, _fail("the first real frame was not counted"))


func test_slow_and_dropped_are_counted_in_the_right_buckets() -> void:
	_case = "buckets"
	var stats := _warmed()

	stats.record(0.016)  # fine
	stats.record(0.025)  # slow
	stats.record(0.050)  # dropped

	_runner.check(stats.frames == 3, _fail("counted %d frames, expected 3" % stats.frames))
	# A dropped frame must not also be counted as slow, or the two columns
	# double-count and "over 20 ms" reads higher than reality.
	_runner.check(stats.slow == 1, _fail("slow = %d, expected 1" % stats.slow))
	_runner.check(stats.dropped == 1, _fail("dropped = %d, expected 1" % stats.dropped))
	_runner.check(
		is_equal_approx(stats.worst_ms, 50.0), _fail("worst = %.1f, expected 50" % stats.worst_ms)
	)


func test_a_frame_exactly_on_the_threshold_counts_as_slow() -> void:
	_case = "threshold"
	var stats := _warmed()
	stats.record(FrameStats.SLOW_MS / 1000.0)
	# Asserted in both directions: a strict > would leave a whole class of
	# missed frames invisible, and only the boundary case can tell.
	_runner.check(stats.slow == 1, _fail("20.0 ms was not counted as slow"))

	var under := _warmed()
	under.record((FrameStats.SLOW_MS - 0.1) / 1000.0)
	_runner.check(under.slow == 0, _fail("19.9 ms was wrongly counted as slow"))


func test_the_rolling_window_forgets_an_old_spike() -> void:
	_case = "rolling window"
	var stats := _warmed()
	stats.record(0.500)
	_runner.check(
		is_equal_approx(stats.recent_worst_ms(), 500.0), _fail("the spike was not in the window")
	)

	for _i in FrameStats.WINDOW:
		stats.record(0.016)

	_runner.check(
		stats.recent_worst_ms() < 20.0,
		_fail(
			(
				"the window still reports %.1f ms after %d clean frames"
				% [stats.recent_worst_ms(), FrameStats.WINDOW]
			)
		)
	)
	# The since-reset worst must NOT forget it. Two different questions, and a
	# window that overwrote the all-time worst would answer neither.
	_runner.check(
		is_equal_approx(stats.worst_ms, 500.0),
		_fail("the all-time worst was forgotten: %.1f" % stats.worst_ms)
	)


func test_reset_clears_the_counts_but_not_the_warmup() -> void:
	_case = "reset"
	var stats := _warmed()
	stats.record(0.500)
	stats.reset()

	_runner.check(stats.frames == 0, _fail("frames = %d after reset" % stats.frames))
	_runner.check(stats.worst_ms == 0.0, _fail("worst = %.1f after reset" % stats.worst_ms))
	_runner.check(stats.recent_worst_ms() == 0.0, _fail("the window survived reset"))

	# Pressing reset means "measure from this fight", not "sit out another half
	# second first" — so the very next frame must land.
	stats.record(0.030)
	_runner.check(stats.frames == 1, _fail("reset re-armed the warm-up"))


func test_describe_says_it_is_warming_up_rather_than_reporting_zeroes() -> void:
	_case = "describe"
	var stats := FrameStats.new()
	_runner.check(
		"warming up" in stats.describe(),
		_fail("describe() before any frame: %s" % stats.describe())
	)

	var warmed := _warmed()
	warmed.record(0.040)
	var text := warmed.describe()
	_runner.check("40.0 ms" in text, _fail("the worst frame is not in the readout: %s" % text))
