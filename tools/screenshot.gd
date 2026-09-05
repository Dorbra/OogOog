extends SceneTree
## Renders the real main scene offscreen and saves a PNG.
##
## Nobody on this project can run the game locally, so until now the render path
## had zero verification: the headless smoke test never calls _draw(), and CI
## only proved the APK builds. This boots the actual scene under a virtual
## display with software OpenGL, lets it run, and writes an image that can be
## looked at — turning "it compiled" into "here is what it looks like".
##
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 \
##          --script tools/screenshot.gd -- <frames> <output.png>

const DEFAULT_FRAMES := 90
const DEFAULT_OUT := "res://build/shot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var frames: int = int(args[0]) if args.size() > 0 else DEFAULT_FRAMES
	var out: String = args[1] if args.size() > 1 else DEFAULT_OUT

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("screenshot: could not load main scene")
		quit(1)
		return

	root.add_child(scene.instantiate())
	_capture_after(frames, out)


func _capture_after(frames: int, out: String) -> void:
	for _i in frames:
		await process_frame

	# One extra frame so the just-drawn content is present in the backbuffer.
	await RenderingServer.frame_post_draw

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
