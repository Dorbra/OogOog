extends SceneTree
## Measures what a simulation tick actually costs, and where.
##
## Every feel change in this project so far has assumed the game runs at a
## steady 60 fps on the phone. Nobody has ever checked. Five feel PRs shipped in
## a row and the answer was still "the shooting is not right yet", which is
## exactly what a frame hitch mid-fight would feel like — so before another
## number gets tuned, the frame budget gets measured.
##
## It also settles the tech-debt list, which turned out to be wrong about its
## own costs in both directions. ARCHITECTURE.md called the bot cover scan
## "negligible" while it ran a full-arena raycast sweep every retreat tick, and
## called the tuning lookups a hot path without ever counting them. An adjective
## is not a measurement (ADR-0027).
##
## HEADLESS HAS NO RENDERER, so this measures the SIMULATION only — SimWorld
## .tick() and everything under it. That is the honest scope and it is where all
## three debts live. Draw cost is answered on the device, by the worst-frame
## readout in the DBG Info tab.
##
## Run: godot --headless --path . --script tools/measure_frame.gd -- [seconds]
##
## Optional `key=value` arguments override tuning for the run, same as
## tools/measure_matches.gd.

const DT := 1.0 / 60.0
const DEFAULT_SECONDS := 30.0

## One 60 Hz frame, in microseconds. The whole budget, for everything —
## simulation, rendering, input and the OS. The simulation getting a large share
## of this is the finding that would matter.
const FRAME_BUDGET_US := 16666.0

## MatchState.Phase.LIVE and BotController.State.RETREAT as plain integers.
##
## Naming either type here would pull it in at COMPILE time, and both reach
## `Tuning` — an autoload that does not exist yet when a `--script` file is
## compiled. Everything under `src/` is loaded by path at runtime instead, the
## same workaround tools/measure_matches.gd, verify_ui.gd and screenshot.gd all
## carry.
const LIVE := 2
const RETREAT := 2
const LURK := 3

## Sample count for the isolated grid-search benchmarks.
const PROBE_SAMPLES := 200

var _tuning: Node
var _sim_world: GDScript
var _bot: GDScript
var _command: GDScript


func _initialize() -> void:
	_run()


## Deferred by one frame: at `_initialize()` time the autoloads are registered
## but not yet in the tree.
func _run() -> void:
	await process_frame

	_tuning = root.get_node_or_null("/root/Tuning")
	if _tuning == null:
		push_error("measure_frame: the Tuning autoload is missing")
		quit(1)
		return

	_sim_world = load("res://src/sim/sim_world.gd")
	_bot = load("res://src/ai/bot_controller.gd")
	_command = load("res://src/sim/input_command.gd")

	var seconds := DEFAULT_SECONDS
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			if not _override(arg):
				quit(1)
				return
		elif arg.is_valid_float():
			seconds = float(arg)

	_report_tick_cost(seconds)
	_report_lookup_cost()
	_report_grid_searches()
	quit(0)


func _override(arg: String) -> bool:
	var parts := arg.split("=", true, 1)
	var key := parts[0]
	if not _tuning.keys().has(key):
		push_error("measure_frame: no such tuning key '%s'" % key)
		return false
	_tuning.set_value(key, float(parts[1]))
	print("override %s = %.3f" % [key, _tuning.get_value(key)])
	return true


# ------------------------------------------------------------ the whole tick


## Plays a real match and times every tick.
##
## The distribution matters far more than the mean. A mean of 200 us with a
## worst tick of 9000 us is a game that stutters, and it is indistinguishable
## from a smooth one if you only report the average — which is why the on-device
## readout counts slow frames rather than showing fps.
func _report_tick_cost(seconds: float) -> void:
	var world: Object = _sim_world.new()
	var fighters: Array = world.fighters
	for i in range(1, fighters.size()):
		fighters[i].controller = _bot.new(4242 + i * 7919)
	world.match_state.phase = LIVE

	var idle: Object = _command.new()
	var ticks := int(seconds * 60.0)
	var samples: Array[float] = []
	samples.resize(ticks)

	var retreat_ticks := 0
	var lurk_ticks := 0
	var before_lookups: int = _tuning.lookups

	# Split the samples by whether anybody was retreating on that tick. This is
	# the whole causal claim of this branch and it should be measured, not
	# inferred from a mean and a plausible story — that mistake has been made
	# three times in this project already (ADR-0025).
	var quiet: Array[float] = []
	var retreating: Array[float] = []

	for i in ticks:
		var started := Time.get_ticks_usec()
		world.tick(idle, DT)
		samples[i] = float(Time.get_ticks_usec() - started)
		var retreaters := 0
		for j in range(1, fighters.size()):
			var bot: Object = fighters[j].controller
			if bot == null:
				continue
			if bot.state == RETREAT:
				retreat_ticks += 1
				retreaters += 1
			elif bot.state == LURK:
				lurk_ticks += 1
		if retreaters > 0:
			retreating.append(samples[i])
		else:
			quiet.append(samples[i])

	var lookups: int = _tuning.lookups - before_lookups
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	var mean := total / float(maxi(ticks, 1))

	print("")
	print("== %d ticks (%.0f s of match) ==" % [ticks, seconds])
	print(
		(
			"mean tick     : %8.1f us   (%.2f%% of a 60 Hz frame)"
			% [mean, mean * 100.0 / FRAME_BUDGET_US]
		)
	)
	print("median        : %8.1f us" % _percentile(sorted, 0.50))
	print("p95           : %8.1f us" % _percentile(sorted, 0.95))
	print("p99           : %8.1f us" % _percentile(sorted, 0.99))
	print(
		(
			"worst         : %8.1f us   (%.2f%% of a frame)"
			% [sorted[sorted.size() - 1], sorted[sorted.size() - 1] * 100.0 / FRAME_BUDGET_US]
		)
	)
	print("over 16.6 ms  : %d tick(s)" % _count_over(samples, FRAME_BUDGET_US))
	print("over  8.0 ms  : %d tick(s)" % _count_over(samples, 8000.0))
	print("")
	print(
		(
			"bot-ticks in RETREAT : %d  (%.1f%% of all bot-ticks)"
			% [retreat_ticks, float(retreat_ticks) * 100.0 / float(maxi(ticks * 5, 1))]
		)
	)
	print("bot-ticks in LURK    : %d" % lurk_ticks)
	print("")
	print(
		(
			"ticks with NOBODY retreating : %5d, mean %8.1f us, worst %8.1f us"
			% [quiet.size(), _mean(quiet), _worst(quiet)]
		)
	)
	print(
		(
			"ticks with SOMEBODY retreating: %5d, mean %8.1f us, worst %8.1f us"
			% [retreating.size(), _mean(retreating), _worst(retreating)]
		)
	)
	print(
		(
			"tuning lookups       : %d  (%.1f per tick)"
			% [lookups, float(lookups) / float(maxi(ticks, 1))]
		)
	)


func _mean(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for s in samples:
		total += s
	return total / float(samples.size())


func _worst(samples: Array[float]) -> float:
	var worst := 0.0
	for s in samples:
		worst = maxf(worst, s)
	return worst


func _percentile(sorted: Array[float], fraction: float) -> float:
	if sorted.is_empty():
		return 0.0
	var index := int(round(fraction * float(sorted.size() - 1)))
	return sorted[clampi(index, 0, sorted.size() - 1)]


func _count_over(samples: Array[float], threshold: float) -> int:
	var n := 0
	for s in samples:
		if s > threshold:
			n += 1
	return n


# --------------------------------------------------------------- the lookups


## Times Tuning.get_value() in isolation, so its share of a tick is arithmetic
## rather than a guess.
##
## The debt row says "dictionary lookup in hot paths" and proposes caching in
## four files. Caching a tuning value is four new places for a slider to
## silently stop working — the failure ADR-0021 exists about — so the bar for
## doing it should be a measured share of the frame, not the fact that it is
## called often.
func _report_lookup_cost() -> void:
	var iterations := 200000
	var started := Time.get_ticks_usec()
	for _i in iterations:
		_tuning.get_value("move_speed")
	var elapsed := float(Time.get_ticks_usec() - started)

	print("")
	print("== Tuning.get_value() ==")
	print(
		(
			"%.3f us per call  (%d calls in %.1f ms)"
			% [elapsed / float(iterations), iterations, elapsed / 1000.0]
		)
	)


# --------------------------------------------------------- the grid searches


## Times the two full-arena scans in BotController, at real positions.
##
## _nearest_cover() is called EVERY TICK a bot is retreating, with no cache and
## no timer, and casts a ray per open cell. Its distance early-out prunes hard
## once cover has been found nearby and prunes NOTHING when there is no cover at
## all — so the spread between best and worst case is the whole story, and a
## mean would hide it.
func _report_grid_searches() -> void:
	var world: Object = _sim_world.new()
	var arena: Object = world.arena
	var bot: Object = _bot.new(1)
	var open := _open_cells(arena)
	if open.size() < 2:
		push_error("measure_frame: the arena has no open cells")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260910

	var cover := _time_search(bot, "_nearest_cover", arena, open, rng)
	var bush := _time_search(bot, "_nearest_bush", arena, open, rng)
	var path := _time_pathfind(arena, open, rng)

	print("")
	print("== full-arena searches ==")
	print("open cells: %d of %d" % [open.size(), arena.rows * arena.cols])
	_print_search("_nearest_cover  ", cover)
	_print_search("_nearest_bush   ", bush)
	_print_search("GridPath.find_path", path)


func _time_search(
	bot: Object, method: String, arena: Object, open: Array[Vector2], rng: RandomNumberGenerator
) -> Array[float]:
	var samples: Array[float] = []
	for _i in PROBE_SAMPLES:
		var from: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		var threat: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		var started := Time.get_ticks_usec()
		bot.call(method, arena, from, threat)
		samples.append(float(Time.get_ticks_usec() - started))
	samples.sort()
	return samples


## A* between two random open cells.
##
## Included because the SINGLE WORST tick in the run above landed on a tick with
## nobody retreating, so the cover scan cannot be the only thing that spikes.
## Chasing the biggest number and stopping is how the last three wrong findings
## in this project happened.
func _time_pathfind(
	arena: Object, open: Array[Vector2], rng: RandomNumberGenerator
) -> Array[float]:
	var grid_path: GDScript = load("res://src/ai/grid_path.gd")
	var samples: Array[float] = []
	for _i in PROBE_SAMPLES:
		var from: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		var to: Vector2 = open[rng.randi_range(0, open.size() - 1)]
		var started := Time.get_ticks_usec()
		grid_path.find_path(arena, from, to)
		samples.append(float(Time.get_ticks_usec() - started))
	samples.sort()
	return samples


func _print_search(label: String, samples: Array[float]) -> void:
	var total := 0.0
	for s in samples:
		total += s
	var mean := total / float(maxi(samples.size(), 1))
	var worst: float = samples[samples.size() - 1]
	print(
		(
			"%s : mean %7.1f us, p95 %7.1f us, worst %7.1f us  (worst = %.1f%% of a frame)"
			% [label, mean, _percentile(samples, 0.95), worst, worst * 100.0 / FRAME_BUDGET_US]
		)
	)


func _open_cells(arena: Object) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for y in arena.rows:
		for x in arena.cols:
			if not arena.is_solid(x, y):
				out.append(arena.cell_centre(x, y))
	return out
