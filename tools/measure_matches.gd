extends SceneTree
## Simulates full matches headlessly and reports what actually happens.
##
## This exists because three balance predictions in a row were wrong. The worst
## was `fix/resolve`, which predicted halving the heal rate would take net damage
## from 4 hp to 16 hp per exchange; it measured 1.3 -> 1.5 kills, because you
## cannot heal above maximum and total healing is capped by damage taken, not by
## rate. The sweep that replaced the reasoning found the real levers in minutes.
##
## So: any change that alters how often anyone meets anyone gets run through this
## before it ships, and the two distributions go in the PR side by side.
##
## Run: godot --headless --path . --script tools/measure_matches.gd -- [runs]
##
## Optional `key=value` arguments override tuning for the batch, so a sweep is
## one shell loop rather than a series of commits:
##
##   ... -- 24 move_speed=150 move_accel=900

const DT := 1.0 / 60.0
const DEFAULT_RUNS := 24

## MatchState.Phase.LIVE as a plain integer.
##
## Naming `MatchState` here would pull it in at COMPILE time, and it reads
## `Tuning` — an autoload that does not exist yet when a `--script` file is
## compiled. Everything under `src/` is therefore loaded by path at runtime, and
## tools/verify_ui.gd and tools/screenshot.gd carry the same workaround.
const LIVE := 2

var _tuning: Node
var _sim_world: GDScript
var _bot: GDScript
var _command: GDScript


func _initialize() -> void:
	_run()


## Deferred by one frame on purpose: at `_initialize()` time the autoloads are
## not in the tree yet, and `get_node_or_null("/root/Tuning")` fails with
## "Can't use get_node() with absolute paths from outside the active scene tree".
func _run() -> void:
	await process_frame

	_tuning = root.get_node_or_null("/root/Tuning")
	if _tuning == null:
		push_error("measure_matches: the Tuning autoload is missing")
		quit(1)
		return

	_sim_world = load("res://src/sim/sim_world.gd")
	_bot = load("res://src/ai/bot_controller.gd")
	_command = load("res://src/sim/input_command.gd")

	var runs := DEFAULT_RUNS
	for arg in OS.get_cmdline_user_args():
		if "=" in arg:
			if not _override(arg):
				quit(1)
				return
		elif arg.is_valid_int():
			runs = int(arg)

	_probe_free_range()
	_report(runs)
	quit(0)


## Applies one `key=value` argument, reporting the value that actually landed.
##
## `Tuning.set_value()` clamps to the slider's own min and max, so a sweep can
## silently measure a different number than the one asked for. Printing what
## came back rather than what went in is the only way a swept row means what it
## says.
func _override(arg: String) -> bool:
	var parts := arg.split("=", true, 1)
	var key := parts[0]
	if not _tuning.keys().has(key):
		push_error("measure_matches: no such tuning key '%s'" % key)
		return false
	_tuning.set_value(key, float(parts[1]))
	print("override %s = %.3f" % [key, _tuning.get_value(key)])
	return true


func _tuned(key: String) -> float:
	return _tuning.get_value(key)


func _report(runs: int) -> void:
	var totals: Array[int] = []
	var scorelines: Dictionary = {}
	var decided_by_target := 0
	var sudden_death := 0
	var first_kill_total := 0.0
	var first_kill_count := 0

	for run in runs:
		var result := _play(run)
		totals.append(result["total"])
		var line: String = result["line"]
		scorelines[line] = int(scorelines.get(line, 0)) + 1
		if result["by_target"]:
			decided_by_target += 1
		if result["sudden_death"]:
			sudden_death += 1
		if result["first_kill"] >= 0.0:
			first_kill_total += result["first_kill"]
			first_kill_count += 1

	totals.sort()
	var sum := 0
	for t in totals:
		sum += t

	var lines := scorelines.keys()
	lines.sort()

	print("")
	print(
		(
			"== %d matches, %.0f s limit, target %d"
			% [runs, _tuned("match_time_limit"), int(_tuned("match_target_kills"))]
		)
	)
	print("mean kills        : %.2f" % (float(sum) / float(maxi(runs, 1))))
	print("median kills      : %d" % totals[totals.size() / 2])
	print("goalless matches  : %d" % totals.count(0))
	print("decided by target : %d" % decided_by_target)
	print("sudden death      : %d" % sudden_death)
	if first_kill_count > 0:
		print(
			(
				"mean time to 1st  : %.1f s (in %d matches)"
				% [first_kill_total / float(first_kill_count), first_kill_count]
			)
		)
	print(
		(
			"scorelines        : %s"
			% ", ".join(lines.map(func(l: String) -> String: return "%s x%d" % [l, scorelines[l]]))
		)
	)


## How far you can shoot a running cat WITHOUT leading it.
##
## The number that says whether aim skill matters, and it cannot be reasoned to.
## The obvious arithmetic — compare the angle you must lead by against the angle
## a cat subtends — said leading was necessary past 75% of the bow's range. Fired
## through the real tick loop it turned out an unled shot connected at every
## range in the book, because the swept collision test measures the arrow's
## CLOSEST APPROACH rather than where it ends up.
##
## Reported as a fraction of the bow's reach: 0.6 means you can point straight at
## a moving cat inside 60% of your range and still hit, and must lead beyond it.
func _probe_free_range() -> void:
	var reach := _tuned("draw_max_speed") * _tuned("arrow_lifetime")
	var free := 0.0
	for step in 20:
		var fraction := 0.05 + 0.05 * float(step)
		if _straight_shot_hits(reach * fraction):
			free = fraction
		else:
			break
	print(
		(
			"unled shots hit within %.0f%% of the %.0f px reach  (lead %.1f deg, cat %.1f deg)"
			% [
				free * 100.0,
				reach,
				rad_to_deg(atan(_tuned("move_speed") / _tuned("draw_max_speed"))),
				rad_to_deg(atan(_tuned("fighter_radius") / reach))
			]
		)
	)


## Fires one unled arrow at a cat running perpendicular `distance` away, on open
## ground with a clear line, and says whether it connects.
func _straight_shot_hits(distance: float) -> bool:
	var world: Object = _sim_world.new()
	for f in world.fighters:
		f.controller = null
	world.match_state.phase = LIVE

	var player: Object = world.player
	var target: Object = world.nearest_enemy(player.position, 100000.0, player)
	var from: Vector2 = player.position
	var placed := false
	var run := Vector2.ZERO

	for step in 32:
		var angle := TAU * float(step) / 32.0
		var spot: Vector2 = from + Vector2(cos(angle), sin(angle)) * distance
		var cell: Vector2i = world.arena.cell_at(spot)
		if world.arena.is_solid(cell.x, cell.y) or world.arena.conceals(spot):
			continue
		if world.arena.cast_segment(from, spot)["hit"]:
			continue
		run = (spot - from).normalized().orthogonal() * _tuned("move_speed")
		if world.arena.cast_segment(from, spot + run.normalized() * distance * 0.3)["hit"]:
			continue
		target.position = spot
		target.prev_position = spot
		placed = true
		break

	if not placed:
		# Nowhere open at this range says nothing about aiming, so do not let it
		# read as a miss and end the sweep early.
		return true

	var dir: Vector2 = (target.position - from).normalized()
	var hit := [false]
	world.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float, _f: bool) -> void: hit[0] = true)

	var arrow: Object = world._free_arrow()
	arrow.launch(
		from + dir * player.radius,
		dir,
		player.bow.speed_for(1.0),
		1.0,
		_tuned("arrow_lifetime"),
		player.team
	)

	for _i in int(_tuned("arrow_lifetime") * 60.0) + 4:
		target.velocity = run
		target.prev_position = target.position
		target.position += run * DT
		world._tick_arrows(DT)
		if hit[0]:
			return true
	return false


## One match, played to its own conclusion by bots on both sides.
##
## The player slot is driven by an empty command — standing still — rather than
## by a bot. That is deliberately the pessimistic case: it measures whether a
## match resolves when one participant contributes nothing, which is close to
## what a five-year-old's first minute looks like, and it is the same shape as
## the floor pinned by test_match.gd::test_matches_actually_resolve.
func _play(run: int) -> Dictionary:
	var world: Object = _sim_world.new()
	var fighters: Array = world.fighters
	for i in range(1, fighters.size()):
		fighters[i].controller = _bot.new(1000 + run * 131 + i * 7919)
	world.match_state.phase = LIVE

	var idle: Object = _command.new()
	var ticks := 0
	var first_kill := -1.0
	var cap := int((_tuned("match_time_limit") + 180.0) * 60.0)

	while world.match_state.phase == LIVE and ticks < cap:
		world.tick(idle, DT)
		ticks += 1
		if first_kill < 0.0 and world.match_state.scores[0] + world.match_state.scores[1] > 0:
			first_kill = world.match_state.elapsed

	var scores: Array = world.match_state.scores
	var target := int(_tuned("match_target_kills"))
	return {
		"total": scores[0] + scores[1],
		"line": "%d-%d" % [maxi(scores[0], scores[1]), mini(scores[0], scores[1])],
		"by_target": target > 0 and maxi(scores[0], scores[1]) >= target,
		# Genuine sudden death — level AT the cap, so the match ran on until
		# somebody led by one. Every match that reaches the limit overshoots it by
		# a tick or two, so a bare `elapsed > limit` would report all of them and
		# say nothing.
		"sudden_death": world.match_state.elapsed > _tuned("match_time_limit") + 0.5,
		"first_kill": first_kill,
	}
