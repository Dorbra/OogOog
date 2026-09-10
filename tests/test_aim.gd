extends RefCounted
## The player's auto-aim has to predict, or it is worse than nothing.
##
## This file exists because both `SimWorld._try_fire()`'s snap branch and the
## aim assist pointed at the target's CURRENT position. Against a 250 px/s walk
## and a 780 px/s arrow that can only connect inside 90 px, while
## `autoaim_radius` was 235 — so past a third of its own radius the assist took a
## shot the player had led correctly and bent it back onto a miss. The bots have
## led their targets since `feat/bots`; the player never did.
##
## The tests fire REAL arrows through the real tick loop rather than checking
## angles. An angle assertion would have passed on the shipped build: the old
## direction was a perfectly good unit vector pointing straight at a cat. Only
## the arrow arriving proves anything (ADR-0019).

# Set by the runner via set() after a no-argument new().
var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _world() -> SimWorld:
	var w := SimWorld.new()
	# Nobody else moves or shoots: these tests are about one arrow and one
	# target, and a live roster would put stray arrows in the air.
	for f in w.fighters:
		f.controller = null
	w.match_state.phase = MatchState.Phase.LIVE
	return w


## The enemy of the player, put somewhere `distance` away that the player can
## actually shoot, running perpendicular to the shot at walking speed.
##
## It ASKS THE ARENA rather than using an offset. The first version parked the
## target at `player.position + (distance, 0)`, which on this map is inside a
## wall — so every arrow struck stone and both hit tests failed for a reason that
## had nothing to do with aiming. tools/screenshot.gd learned the same lesson the
## same way, and its comment records the same fix.
##
## The corridor the target RUNS down has to be clear too, not just the line to
## where it starts. A shot led into stone misses exactly like a shot that was
## never led, and the test could not tell the two apart.
func _stage(w: SimWorld, distance: float) -> Fighter:
	var target := w.nearest_enemy(w.player.position, 100000.0, w.player)
	var from := w.player.position
	var drift := Tuning.get_value("move_speed") * Tuning.get_value("bullet_lifetime")

	for step in 32:
		var angle := TAU * float(step) / 32.0
		var spot := from + Vector2(cos(angle), sin(angle)) * distance
		var cell := w.arena.cell_at(spot)
		if w.arena.is_solid(cell.x, cell.y) or w.arena.conceals(spot):
			continue
		if w.arena.cast_segment(from, spot)["hit"]:
			continue
		var run := (spot - from).normalized().orthogonal()
		if w.arena.cast_segment(from, spot + run * drift * 1.5)["hit"]:
			continue

		target.position = spot
		target.prev_position = spot
		target.velocity = run * Tuning.get_value("move_speed")
		return target

	# Loud rather than silent. A fixture that cannot place its target must not
	# leave the target on its spawn and let the test report whatever happens.
	_runner.check(false, _fail("found nowhere open to stage a target %.0f px away" % distance))
	return target


## Fires one arrow along `dir` and ticks the world until it dies. Returns true if
## the target took damage.
##
## The target is re-driven every tick with a constant velocity so it keeps
## running in a straight line: `Fighter.tick()` applies friction to a fighter
## with no input, which would quietly stop it dead and turn a leading test into a
## stationary one that any aim direction passes.
func _fire_and_run(w: SimWorld, shooter: Fighter, target: Fighter, dir: Vector2) -> bool:
	var hit := [false]
	w.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float) -> void: hit[0] = true)

	var bullet := w._free_bullet()
	bullet.launch(
		shooter.position + dir * shooter.radius,
		dir,
		shooter.gun.speed(),
		shooter.gun.damage(),
		Tuning.get_value("bullet_lifetime"),
		shooter.team
	)

	var run := target.velocity
	var ticks := int(Tuning.get_value("bullet_lifetime") * 60.0) + 4
	for _i in ticks:
		target.velocity = run
		target.prev_position = target.position
		target.position += run * (1.0 / 60.0)
		w._tick_bullets(1.0 / 60.0)
		if hit[0]:
			return true
	return hit[0]


func _reach() -> float:
	return Tuning.get_value("bullet_speed") * Tuning.get_value("bullet_lifetime")


# ------------------------------------------------------------------ the bug


## Point straight at a cat and shoot, without leading it at all.
func _straight_shot_hits(distance: float) -> bool:
	var w := _world()
	var target := _stage(w, distance)
	return _fire_and_run(w, w.player, target, (target.position - w.player.position).normalized())


## A CLEAR LINE OF FIRE, as an assertion.
##
## This replaces a gate that asserted the opposite, and the reversal is the
## point rather than an accident.
##
## The old pair said: an unled shot must hit up close and must MISS at the range
## bots hold station — "aim skill has to matter", encoded as a test. It was
## honest about the arithmetic and wrong about the design, and the person playing
## the game said so:
##
##     "the Arrow shooting is sluggish and cant be expected,
##      lets change back to GUNS! with a clear line-of-fire"
##
## A gun at 1400 px/s crosses its whole range in 165 ms. Point at a cat and the
## bullet arrives where you pointed — at every range, which is exactly what was
## asked for. Keeping the old floor would have meant slowing the bullet back down
## to protect a belief the user had already overruled.
##
## What is still worth pinning is that pointing WORKS. Measured by firing a real
## bullet through the real tick loop, never by comparing angles: the angle
## version of this assertion was wrong once already, because the swept collision
## test scores closest approach rather than where the shot lands.
func test_pointing_at_a_cat_is_enough_at_every_range() -> void:
	# Typed explicitly: an untyped Array literal yields Variant elements, and
	# `:=` cannot infer a type from one.
	var fractions: Array[float] = [0.4, 0.7, 0.95]
	for fraction in fractions:
		var distance := _reach() * fraction
		_runner.check(
			_straight_shot_hits(distance),
			(
				_fail("an unled shot at %.0f px (%.0f%% of reach) connects")
				% [distance, fraction * 100.0]
			)
		)


func test_and_leading_it_properly_connects() -> void:
	# The mirror, and it is not optional: without it the test above could pass on
	# a game where the shot simply teleports. It also keeps Aim.intercept honest
	# now that pointing straight works — a leading solver that returned nonsense
	# would no longer be caught by anything else in this file.
	var w := _world()
	var target := _stage(w, Tuning.get_value("bot_preferred_range"))
	var led := Aim.intercept(
		w.player.position, w.player.gun.speed(), target.position, target.velocity, 1.0
	)
	_runner.check(
		_fire_and_run(w, w.player, target, led), _fail("a properly led shot at the same range hits")
	)


## The tap shot that used to live here is gone with automatic fire, but the
## thing it proved is not: the ASSIST leads, and it is now the only leading path
## the player has. A nudge that pointed at where a cat already stands cannot hit
## one that is moving, which was the whole bug in ADR-0020.
func test_held_fire_is_assisted_toward_the_intercept() -> void:
	var w := _world()
	var target := _stage(w, minf(_reach() * 0.85, Tuning.get_value("autoaim_radius") * 0.9))
	var run := target.velocity

	var straight := (target.position - w.player.position).normalized()
	var assisted := w.assisted_aim(w.player, straight)

	var intercept := Aim.intercept(
		w.player.position, w.player.gun.speed(), target.position, run, 1.0, w.player.facing
	)

	# Stated as a DISTANCE to the true intercept, not as the sign of an angle.
	# The sign version was my first attempt and it compared two angles with no
	# fixed relationship to each other, so it failed on correct code.
	_runner.check(
		straight.distance_to(intercept) > 0.0001,
		_fail("the cat really is moving, so there is a lead to find")
	)
	_runner.check(
		assisted.distance_to(intercept) < straight.distance_to(intercept),
		(
			_fail("the assist moves the shot toward the intercept: got %s, straight %s, want %s")
			% [str(assisted), str(straight), str(intercept)]
		)
	)


func test_lead_zero_reproduces_the_old_behaviour() -> void:
	# What makes the BotController extraction provably behaviour-preserving: at
	# bot_skill 0 the lead term is zero and Aim.intercept must return exactly the
	# direction the old code did.
	var from := Vector2(100, 100)
	var pos := Vector2(400, 100)
	var vel := Vector2(0, 300)
	var expected := (pos - from).normalized()
	var got := Aim.intercept(from, 800.0, pos, vel, 0.0)
	_runner.check(
		got.is_equal_approx(expected), _fail("lead 0 aims at the target's current position")
	)


func test_a_stationary_target_needs_no_lead() -> void:
	# The lead term must VANISH, not merely shrink: a shot that misses something
	# standing still is the most obvious possible bug.
	var from := Vector2(100, 100)
	var pos := Vector2(400, 260)
	var got := Aim.intercept(from, 800.0, pos, Vector2.ZERO, 1.0)
	_runner.check(
		got.is_equal_approx((pos - from).normalized()), _fail("a still target is aimed at directly")
	)


func test_the_intercept_actually_intercepts() -> void:
	# Solve it, then walk both the arrow and the target forward and check they
	# arrive at the same place. This is the maths on its own, without the arena.
	var from := Vector2.ZERO
	var speed := 800.0
	var pos := Vector2(300, 0)
	var vel := Vector2(0, 250)
	var dir := Aim.intercept(from, speed, pos, vel, 1.0)

	var flight := from.distance_to(pos + vel * (from.distance_to(pos) / speed)) / speed
	var arrow_at := from + dir * speed * flight
	var target_at := pos + vel * flight
	_runner.check(
		arrow_at.distance_to(target_at) < 12.0,
		_fail("arrow and target converge (%.1f px apart)") % arrow_at.distance_to(target_at)
	)


func test_a_degenerate_target_returns_the_fallback() -> void:
	# A target standing on top of the shooter. A zero vector fired as a direction
	# sends the arrow nowhere at all, so this has to return something usable.
	var got := Aim.intercept(Vector2(50, 50), 800.0, Vector2(50, 50), Vector2.ZERO, 1.0, Vector2.UP)
	_runner.check(
		got == Vector2.UP, _fail("a degenerate solve falls back rather than returning zero")
	)


# ------------------------------------------------------------- the assist cone


func test_a_shot_outside_the_cone_is_left_alone() -> void:
	var w := _world()
	var target := _stage(w, _reach() * 0.6)
	var to_target := (target.position - w.player.position).normalized()
	var cone := deg_to_rad(Tuning.get_value("aim_assist_deg"))

	var wild := to_target.rotated(cone * 3.0)
	_runner.check(
		w.assisted_aim(w.player, wild).is_equal_approx(wild),
		_fail("a shot outside the cone is not touched")
	)


func test_the_assist_never_turns_a_shot_further_than_its_cone() -> void:
	# What stops the assist being a lock-on, and it is a real risk rather than a
	# theoretical one: the lead a player owes at these speeds is about 16 degrees,
	# so an assist that gated on 4 degrees and then snapped onto the intercept
	# would silently do all of the leading. The cone has to bound the CORRECTION,
	# not just admission to it.
	var w := _world()
	var target := _stage(w, _reach() * 0.6)
	var cone := deg_to_rad(Tuning.get_value("aim_assist_deg"))
	var straight := (target.position - w.player.position).normalized()

	var turned := absf(straight.angle_to(w.assisted_aim(w.player, straight)))
	_runner.check(
		turned <= cone + 0.0001,
		(
			_fail("the assist turned the shot %.1f deg, cone is %.1f deg")
			% [rad_to_deg(turned), rad_to_deg(cone)]
		)
	)
	_runner.check(turned > 0.0, _fail("and it does something rather than nothing"))


func test_no_visible_target_means_no_assist() -> void:
	# nearest_visible_enemy already refuses through stone; this pins that the
	# assist returns the player's own aim untouched rather than a fallback.
	var w := _world()
	for f in w.fighters:
		if f != w.player:
			f.health.take_damage(100000.0)
	var mine := Vector2(0.6, 0.8).normalized()
	_runner.check(
		w.assisted_aim(w.player, mine).is_equal_approx(mine),
		_fail("with nothing to lock onto, your aim is your own")
	)
