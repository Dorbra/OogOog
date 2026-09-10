extends SceneTree
## Asserts that the on-screen controls can actually be TOUCHED.
##
## This exists because a build shipped where the setup screen could not be
## dismissed at all — the game was stuck on its first screen and tapping did
## nothing. The cause was a Control parented to a CanvasLayer: it has no Control
## parent for anchors to resolve against, so `set_anchors_preset(FULL_RECT)` left
## it at size (0, 0), and a zero-size Control can never be hit.
##
## Every existing gate passed. The unit tests do not build a scene tree; the
## render captures draw the screen perfectly, because `_draw()` is not clipped by
## the Control's rect and every layout here is computed from the viewport. So the
## pictures looked right while the thing was completely dead.
##
## The lesson, and the reason this file is separate from the render test:
## **appearance is not behaviour.** A capture proves it drew. Only delivering an
## input proves it works.
##
## Must run under a real display (xvfb). Headless gives a square viewport and
## does not route GUI input, so a tap there proves nothing.
##
## Run: xvfb-run -a godot --path . --rendering-driver opengl3 \
##          --script tools/verify_ui.gd

## Phase values as plain integers. Naming MatchState here would pull it in at
## COMPILE time, and it reads `Tuning` — an autoload that does not exist yet when
## a `--script` file is compiled. tools/screenshot.gd carries the same workaround
## for the same reason.
const SETUP := 0
const OVER := 3

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("verify_ui: could not load the main scene")
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	_run(main)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)


func _find(node: Node, needle: String) -> Node:
	var script: Variant = node.get_script()
	if script != null and needle in str(script.resource_path):
		return node
	for child in node.get_children():
		var found := _find(child, needle)
		if found != null:
			return found
	return null


func _tap(at: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = at
	down.index = 0
	Input.parse_input_event(down)


func _run(main: Node) -> void:
	await process_frame
	await process_frame

	var screens: Node = _find(main, "match_screens")
	_check(screens != null, "the match screens exist in the scene")
	if screens == null:
		_report()
		return

	var view: Vector2 = root.get_visible_rect().size

	# The bug, stated directly: a Control with no size cannot be touched.
	_check(screens.size.x > 0.0 and screens.size.y > 0.0, "the screen has a non-zero rect")
	_check(
		is_equal_approx(screens.size.x, view.x) and is_equal_approx(screens.size.y, view.y),
		"and it covers the whole viewport"
	)
	_check(screens.mouse_filter != Control.MOUSE_FILTER_IGNORE, "and it accepts input at all")

	var world: Variant = main.get("world")
	_check(world != null, "the main scene exposes its world")
	if world == null:
		_report()
		return

	var chosen := []
	screens.size_chosen.connect(func(n: int) -> void: chosen.append(n))

	# Each cat in the row must pick that many a side. Phase is forced back to
	# SETUP between taps because choosing one starts a countdown.
	#
	# `world` is re-read from the scene every time on purpose: choosing a size
	# REBUILDS the world, so a cached reference goes stale and the phase would be
	# set on a SimWorld nothing is looking at any more. The first version of this
	# cached it and reported three failures that were entirely its own.
	for i in 3:
		main.get("world").match_state.phase = SETUP
		await process_frame
		var slot: Rect2 = screens._slot_rect(i)
		_tap(slot.get_center())
		await process_frame
		await process_frame
		_check(
			chosen.size() == i + 1 and chosen[i] == i + 1,
			"tapping cat %d picks a side of %d (got %s)" % [i + 1, i + 1, str(chosen)]
		)

	# The play button.
	main.get("world").match_state.phase = SETUP
	await process_frame
	var before := chosen.size()
	_tap(screens._play_rect().get_center())
	await process_frame
	await process_frame
	_check(chosen.size() > before, "tapping play starts a match")

	_check_setup_layout(screens)
	await _check_class_picker(main, screens)
	_check_ability_button(main)
	_check_override_badge()
	_check_frame_readout()

	# And the results screen must be dismissable, or a finished round traps you
	# exactly as the setup screen did.
	var dismissed := []
	screens.dismissed.connect(func() -> void: dismissed.append(1))
	main.get("world").match_state.phase = OVER
	main.get("world").match_state.winner = 0
	await process_frame
	_tap(view * 0.5)
	await process_frame
	await process_frame
	_check(dismissed.size() > 0, "tapping the results screen starts the next round")

	_report()


## The stale-tuning badge must actually be ON SCREEN, not merely constructed.
##
## A saved user://tuning.json overrides the shipped defaults key by key and
## survives an APK update, so two releases were judged on values the device was
## not running. The badge is the only thing that says so. Testing
## Tuning.overridden_keys() proves the DATA is right and proves nothing about
## whether anybody can see it — which is the exact gap that shipped an untappable
## setup screen (ADR-0019).
## Everything on the setup screen has to be ON the screen, and not on top of
## anything else.
##
## This is the gate for the failure the first APK playtest hit: the screen was
## simply not legible as a menu. Two of its causes are geometric and therefore
## checkable — a row drifting under the device's cutout, and two rows growing
## into each other as their contents change. The third cause, "these two icons
## look the same", is not geometry and is answered by looking at the render.
##
## The safe area is the specific trap. Every other screen in this project
## applies it; match_screens.gd did not, and the class row sat at 6% from the
## top — exactly where a phone puts its cutout.
func _check_setup_layout(screens: Node) -> void:
	var usable: Rect2 = screens.call("_usable")
	_check(usable.size.x > 0.0 and usable.size.y > 0.0, "the setup screen has a usable area")

	var rects: Array[Rect2] = []
	var names: Array[String] = []
	for i in int(FighterClass.count()):
		rects.append(screens.call("_class_rect", i))
		names.append("class card %d" % i)
	for i in 3:
		rects.append(screens.call("_slot_rect", i))
		names.append("size cat %d" % i)
	rects.append(screens.call("_play_rect"))
	names.append("play button")

	for i in rects.size():
		_check(
			usable.encloses(rects[i]),
			"%s is inside the safe area (%s in %s)" % [names[i], rects[i], usable]
		)

	# Nothing may sit on top of anything else: two overlapping tap targets mean
	# one of them is unreachable, and which one depends on check order.
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			_check(
				not rects[i].intersects(rects[j]), "%s does not overlap %s" % [names[i], names[j]]
			)


## Tapping a class must actually change the gun the player fights with.
##
## The data half of this is already covered by test_classes.gd. What that cannot
## prove is that a thumb landing on the icon reaches the code at all — which is
## exactly the gap that shipped a setup screen nobody could dismiss (ADR-0019).
## For a five-year-old who cannot read, an unreachable picker is not a degraded
## experience, it is the whole game stuck on one class.
func _check_class_picker(main: Node, screens: Node) -> void:
	var tuning: Node = root.get_node_or_null("Tuning")
	if tuning == null:
		return

	var count := int(FighterClass.count())
	_check(count >= 2, "there are at least two classes to pick between")
	if count < 2:
		return

	for i in count:
		main.get("world").match_state.phase = SETUP
		await process_frame
		_tap(screens._class_rect(i).get_center())
		await process_frame
		_check(
			int(tuning.call("get_value", "player_class")) == i,
			(
				"tapping class icon %d selects it (got %d)"
				% [i, int(tuning.call("get_value", "player_class"))]
			)
		)

	# And the choice has to survive into the built world, not merely into a
	# tuning value nothing reads.
	tuning.call("set_value", "player_class", 1.0)
	main.get("world").match_state.phase = SETUP
	await process_frame
	_tap(screens._play_rect().get_center())
	await process_frame
	await process_frame
	var built: Variant = main.get("world")
	_check(
		built.player.fighter_class.id == FighterClass.at(1).id,
		"the picked class reaches the fight (player is a %s)" % built.player.fighter_class.id
	)
	tuning.call("set_value", "player_class", 0.0)


## The ability button has to be reachable, and must NOT steer the aim.
##
## Its whole risk is where it lives: inside the right half of the screen, which
## already means "aim and fire". A button there that fell through to the aim
## router would fire the ability AND swing the gun to the bottom-right corner
## every time it was pressed.
func _check_ability_button(main: Node) -> void:
	var controls: Variant = main.get("controls")
	_check(controls != null, "the main scene exposes its touch controls")
	if controls == null:
		return

	var rect: Rect2 = controls.call("ability_rect")
	var view: Vector2 = root.get_visible_rect().size
	_check(rect.size.x > 40.0, "the ability button is big enough for a thumb")
	_check(
		Rect2(Vector2.ZERO, view).encloses(rect),
		"and it is fully on screen (%s in %s)" % [rect, view]
	)

	var aim_before: Vector2 = controls.get("aim_vector")
	controls.call("_assign_finger", 7, rect.get_center())
	_check(controls.call("take_ability"), "pressing it raises the ability edge")
	_check(not controls.call("take_ability"), "and the edge is consumed, so one tap is one ability")
	_check(controls.get("aim_vector") == aim_before, "and pressing it does not steer the aim")
	_check(not controls.get("is_aiming"), "and does not start aiming")
	controls.call("_release_finger", 7)


func _check_override_badge() -> void:
	var overlay: Node = root.get_node_or_null("DebugOverlay")
	_check(overlay != null, "the debug overlay exists")
	if overlay == null:
		return

	var badge: Variant = overlay.get("_override_badge")
	_check(badge != null, "the tuning panel has an override badge")
	if badge == null:
		return

	# Reached through the tree, never named directly. Writing `Tuning` here would
	# resolve at COMPILE time, and a --script file compiles before autoloads
	# exist — the same reason SETUP and OVER above are plain integers.
	var tuning: Node = root.get_node_or_null("Tuning")
	_check(tuning != null, "the tuning autoload is reachable")
	if tuning == null:
		return

	# Clean build: nothing saved, so the badge must be silent rather than
	# crying wolf every launch.
	tuning.call("reset")
	overlay.call("_refresh_override_badge")
	_check(not badge.visible, "with nothing saved the badge is hidden")

	# Now the case it exists for.
	var speed: float = tuning.call("get_value", "move_speed")
	tuning.call("set_value", "move_speed", speed + 13.0)
	tuning.call("save")
	overlay.call("_refresh_override_badge")
	_check(badge.visible, "after a Save the badge is visible")
	_check(
		"move_speed" in String(badge.text),
		"and it names the overridden key (got %s)" % String(badge.text)
	)

	# Leave the machine as it was found: this writes a real user:// file.
	tuning.call("reset")
	overlay.call("_refresh_override_badge")
	_check(not badge.visible, "and Reset makes it go away again")


## The frame readout has to be ON SCREEN, not merely correct.
##
## tests/test_frame_stats.gd proves the counting; it cannot prove anybody can
## read it. This project has shipped a screen that drew perfectly and could not
## be tapped, and a tuning override that was applied correctly and invisibly —
## both times the data was right and the person holding the phone learned
## nothing (ADR-0019). A performance readout nobody can see is the same bug in a
## third place, and it matters more here because this readout is the only
## profiler that exists for the device.
func _check_frame_readout() -> void:
	var overlay: Node = root.get_node_or_null("DebugOverlay")
	if overlay == null:
		# Already reported by _check_override_badge().
		return

	var stats: Variant = overlay.get("_frames")
	_check(stats != null, "the debug overlay tracks frame times")
	if stats == null:
		return

	# Past the warm-up, with one deliberately terrible frame in it, so the
	# readout has something real to say rather than "warming up".
	for _i in 40:
		stats.call("record", 0.016)
	stats.call("record", 0.045)

	overlay.call("_set_open", true)
	overlay.call("_process", 0.016)

	var label: Variant = overlay.get("_info_label")
	_check(label != null, "the Info tab has a label")
	if label == null:
		return

	var text := String(label.get("text"))
	_check("worst" in text, "the Info tab shows the worst frame (got %d chars)" % text.length())
	_check("45.0 ms" in text, "and the worst frame is the 45 ms one, not an average")
	_check("over 33 ms  1" in text, "and the dropped frame is counted")
	# The build stamp must still be there: appending the frame lines must not
	# have replaced what the tab was already for.
	_check("commit" in text, "and the build stamp is still shown")

	overlay.call("_set_open", false)


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("PASS — %d interaction checks" % _checks)
		quit(0)
		return
	print("FAIL — %d of %d interaction checks:" % [_failures.size(), _checks])
	for f in _failures:
		print("  x %s" % f)
	quit(1)
