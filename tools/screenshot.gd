extends SceneTree
## Renders the real main scene offscreen and saves a PNG.
##
## Nobody on this project can run the game locally, so without this the render
## path has zero verification: the headless smoke test never calls _draw().
##
## `--action` drives the player through the simulation before capturing. That
## matters for combat feedback specifically: hitstop, particles, damage numbers
## and knockback only exist for a fraction of a second around an impact, so an
## idle screenshot cannot see any of them. Scripted input turns the whole juice
## pass from unverifiable-without-a-phone into something checkable locally.
##
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 \
##          --script tools/screenshot.gd -- <frames> <out.png> [idle|combat|results|setup]

const DEFAULT_FRAMES := 90
const DEFAULT_OUT := "res://build/shot.png"

## How long after an impact to capture. Long enough for particles to spread and
## the number to rise clear of the target, short enough that nothing has faded.
const CAPTURE_DELAY := 7

## An Array, not an int. GDScript lambdas capture by value, so a plain counter
## assigned inside the signal handler below never reaches this scope — a trap
## that has now bitten this project three times. Arrays are reference types and
## mutate through the capture.
var _hit_seen: Array = []
var _frames_since_hit: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames: int = int(args[0]) if args.size() > 0 else DEFAULT_FRAMES
	var out: String = args[1] if args.size() > 1 else DEFAULT_OUT
	var mode: String = args[2] if args.size() > 2 else "idle"

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("screenshot: could not load main scene")
		quit(1)
		return

	var main: Node = scene.instantiate()
	root.add_child(main)
	_run(main, frames, out, mode)


func _run(main: Node, frames: int, out: String, mode: String) -> void:
	# _ready() has not run yet at _initialize() time, so `world` is still null
	# here. Waiting one frame is the difference between wiring the hit signal
	# and silently skipping it.
	await process_frame

	# Both captures, not just the combat one: bots walk toward the middle of the
	# map from the first tick, so a live roster would make even the idle frame
	# depend on how long the container took to boot.
	_disarm_bots(main.get("world"))

	# The game opens on the setup screen, where nothing simulates. Every capture
	# would otherwise be a picture of a menu — including the combat one, which
	# would then time out having never fired a shot.
	_force_phase(main.get("world"), mode)

	if mode == "combat":
		var world = main.get("world")
		if world == null:
			push_error("screenshot: main scene exposes no `world` to drive")
			quit(1)
			return
		_stage_target(world)
		world.hit.connect(
			func(_p: Vector2, _d: Vector2, _dmg: float) -> void: _hit_seen.append(true)
		)

	for i in frames:
		if mode == "combat":
			_drive_combat(main)
			if not _hit_seen.is_empty():
				_frames_since_hit += 1
				if _frames_since_hit >= CAPTURE_DELAY:
					# Says WHY it captured. Without this a combat run that never
					# landed a hit still writes a plausible-looking screenshot
					# and reports success — the capture would silently stop
					# testing the feedback layer while still going green.
					print("screenshot: combat captured ON HIT")
					await RenderingServer.frame_post_draw
					_save(out)
					return
		await process_frame

	if mode == "combat":
		print("screenshot: combat capture TIMED OUT WITHOUT A HIT")
		push_warning("screenshot: no hit landed in %d frames, capturing anyway" % frames)
	await RenderingServer.frame_post_draw
	_save(out)


## Reads a tuning value by NODE LOOKUP rather than by the `Tuning` global.
##
## This file runs as `--script`, so it is compiled before the project's
## autoloads are registered and a bare `Tuning.get_value(...)` is a compile
## error — "Identifier not found: Tuning". Everything under `src/` is loaded
## after they exist, which is why nothing else in the project needs this.
func _tuned(key: String, fallback: float) -> float:
	var node := root.get_node_or_null("/root/Tuning")
	if node == null:
		push_warning("screenshot: Tuning autoload missing, using fallback for '%s'" % key)
		return fallback
	return node.get_value(key)


## Puts the match into the phase this capture needs.
##
## `results` fakes a finished match rather than playing one out: a real one takes
## two minutes of wall time and lands on whatever score the bots happened to
## produce, which is neither fast nor repeatable. The screen being tested is the
## drawing, and the drawing only reads `winner` and `scores`.
func _force_phase(world, mode: String) -> void:
	if world == null:
		return
	var state = world.match_state
	if mode == "results":
		state.phase = 3  # MatchState.Phase.OVER
		state.winner = 0
		# Element-wise: MatchState.scores is Array[int], and assigning an
		# untyped literal to it from this dynamically-typed script is refused
		# at runtime.
		state.scores[0] = 4
		state.scores[1] = 2
		print("screenshot: staged a finished match, team 0 wins 4-2")
		return

	if mode == "setup":
		# The screen a five-year-old has to get past before they can play, and
		# the only one that cannot be checked any other way from here.
		state.phase = 0  # MatchState.Phase.SETUP
		print("screenshot: holding the setup screen")
		return

	state.phase = 2  # MatchState.Phase.LIVE
	state.scores[0] = 2
	state.scores[1] = 1
	state.elapsed = 45.0
	print("screenshot: forced the match live so the world actually simulates")


## Takes every bot off the controls, so a render captures a staged scene rather
## than a race.
##
## The combat capture is this project's most valuable gate — it is the only
## thing that looks at the feedback layer without a phone — and a gate that
## sometimes fails for reasons unrelated to the code is worse than no gate at
## all (ADR-0012). Six fighters manoeuvring and shooting would make the frame a
## coin toss.
##
## This needs no bot-side "passive" flag: a null controller already means nobody
## is driving, SimWorld._command_for() already returns the empty command for it,
## and test_a_fighter_with_no_controller_stands_still already pins that. The
## practice dummy behaviour never went away — it just stopped being a type.
func _disarm_bots(world) -> void:
	if world == null:
		return
	var disarmed := 0
	for f in world.fighters:
		if f.controller != null:
			f.controller = null
			disarmed += 1
	print("screenshot: disarmed %d bot(s) for a deterministic capture" % disarmed)


## Fires at a target and captures shortly after impact, so the frame contains
## live particles, a damage number, a ring and an in-flight knockback.
## Puts one enemy at a fixed, in-frame distance before driving the shot.
##
## Teams now start at opposite ends of the arena, which is right for a match and
## useless for a screenshot: the nearest enemy is beyond both the camera and the
## bullet's range, so the capture would show a shot sailing into empty grass. The
## arrangement is deliberate and stated rather than hidden — this is a test
## fixture, not gameplay.
func _stage_target(world) -> void:
	var target = world.nearest_enemy(world.player.position, 100000.0, world.player)
	if target == null:
		return

	# A fixed offset is not good enough: +360 on the x axis drops the target
	# inside the wall block beside the left spawn, so every shot struck stone
	# and the capture silently stopped showing a hit at all. Ask the arena
	# instead — an open cell with a clear line of fire, whatever the map looks
	# like. This survives the arena being re-authored, which it just was.
	# Distances are derived from how far a bullet ACTUALLY flies, not written
	# down. The previous list started at 300 px; the pacing pass cut the gun's
	# reach to 195 and every staged shot then died in mid-air. The capture said
	# TIMED OUT WITHOUT A HIT rather than writing a plausible screenshot, which
	# is the gate working (ADR-0012) — but a fixture that has to be re-tuned by
	# hand every time a number moves is a fixture that will be wrong again.
	var from: Vector2 = world.player.position
	var reach: float = _tuned("bullet_speed", 1400.0) * _tuned("bullet_lifetime", 0.165)
	for fraction in [0.65, 0.5, 0.8, 0.35]:
		var distance: float = reach * fraction
		for step in 16:
			var angle := TAU * float(step) / 16.0
			var spot: Vector2 = from + Vector2(cos(angle), sin(angle)) * distance
			var cell: Vector2i = world.arena.cell_at(spot)
			if world.arena.is_solid(cell.x, cell.y):
				continue
			if world.arena.cast_segment(from, spot)["hit"]:
				continue
			target.position = spot
			target.prev_position = spot
			target.spawn_point = spot
			print(
				(
					"screenshot: staged target at %s (%.0fpx away, %.0f%% of the gun's %.0fpx reach)"
					% [str(spot), distance, fraction * 100.0, reach]
				)
			)
			return

	push_warning("screenshot: found nowhere open to stage a target")


func _drive_combat(main: Node) -> void:
	var world = main.get("world")
	var controls = main.get("controls")
	if world == null or controls == null:
		return

	var target = world.nearest_enemy(world.player.position, 100000.0, world.player)
	if target == null:
		return

	var to_target: Vector2 = (target.position - world.player.position).normalized()

	# Point the cat at the target and keep a finger down, so the aim preview and
	# the muzzle are both visible in the capture.
	controls.aim_vector = to_target
	controls.is_aiming = true
	world.player.facing = to_target

	# Holding aims; letting go shoots. The capture needs a stream of shots to be
	# sure of landing on an impact, so it arms the release edge every frame and
	# lets Gun.consume()'s cooldown pace them — which is exactly how a bot fires.
	# is_aiming stays true alongside it so the bright line of fire and the muzzle
	# are both in frame.
	controls.set("_fire_pressed", true)
	controls.set("_fire_was_tap", false)


func _save(out: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("screenshot: viewport produced no image")
		quit(1)
		return

	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	var err := image.save_png(path)
	if err != OK:
		push_error("screenshot: save_png failed (%d) for %s" % [err, path])
		quit(1)
		return

	print("screenshot: wrote %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	quit(0)
