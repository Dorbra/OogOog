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
##          --script tools/screenshot.gd -- <frames> <out.png> [idle|combat]

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

	if mode == "combat":
		var world = main.get("world")
		if world == null:
			push_error("screenshot: main scene exposes no `world` to drive")
			quit(1)
			return
		if true:
			world.hit.connect(
				func(_p: Vector2, _d: Vector2, _dmg: float, _f: bool) -> void:
					_hit_seen.append(true)
			)

	for i in frames:
		if mode == "combat":
			_drive_combat(main, i)
			if not _hit_seen.is_empty():
				_frames_since_hit += 1
				if _frames_since_hit >= CAPTURE_DELAY:
					await RenderingServer.frame_post_draw
					_save(out)
					return
		await process_frame

	if mode == "combat":
		push_warning("screenshot: no hit landed in %d frames, capturing anyway" % frames)
	await RenderingServer.frame_post_draw
	_save(out)


## Fires at a target and captures shortly after impact, so the frame contains
## live particles, a damage number, a ring and an in-flight knockback.
func _drive_combat(main: Node, frame: int) -> void:
	var world = main.get("world")
	var controls = main.get("controls")
	if world == null or controls == null:
		return

	var target = world.nearest_dummy(world.player.position, 4000.0)
	if target == null:
		return

	var to_target: Vector2 = (target.position - world.player.position).normalized()

	# Point the cat at the target and hold a full draw, so the aim preview and
	# the bow string are both visible in the capture.
	controls.aim_vector = to_target
	controls.is_drawing = true
	controls.draw_strength = 1.0
	world.player.facing = to_target

	# Fire on a cadence rather than once: the capture then lands with arrows in
	# flight AND recent impacts, instead of depending on exact frame timing.
	if frame > 10 and frame % 22 == 0:
		controls.shot_released.emit(to_target, 1.0, false)


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
