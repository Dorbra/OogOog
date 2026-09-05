class_name BuildInfo
extends RefCounted
## Build and device facts, surfaced in-game.
##
## With no local machine there is no `adb logcat` and no way to inspect the
## device. When something looks wrong the answer to "which build is that, and
## what is it running on?" has to come from inside the game itself.

## Written by CI at build time so a screenshot identifies the exact commit.
const STAMP_PATH := "res://data/build_stamp.json"


static func stamp() -> Dictionary:
	if not FileAccess.file_exists(STAMP_PATH):
		return {"commit": "local", "built_at": "unknown", "run": "0"}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAMP_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"commit": "unparseable", "built_at": "unknown", "run": "0"}
	return parsed


static func describe() -> String:
	var s := stamp()
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var lines := [
		"commit      %s" % s.get("commit", "?"),
		"built       %s" % s.get("built_at", "?"),
		"ci run      %s" % s.get("run", "?"),
		"",
		"engine      %s" % Engine.get_version_info().get("string", "?"),
		"platform    %s" % OS.get_name(),
		"model       %s" % OS.get_model_name(),
		"debug build %s" % OS.is_debug_build(),
		"renderer    %s" % RenderingServer.get_video_adapter_name(),
		"",
		"window      %d x %d" % [win.x, win.y],
		"safe area   %d,%d %d x %d" % [safe.position.x, safe.position.y, safe.size.x, safe.size.y],
		"fps         %d" % Engine.get_frames_per_second(),
		"phys tick   %d Hz" % Engine.physics_ticks_per_second,
		"",
		"user dir    %s" % OS.get_user_data_dir(),
	]
	return "\n".join(lines)
