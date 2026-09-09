class_name SimWorld
extends RefCounted
## Owns the simulation and ticks it in a fixed order.
##
## Runs at a fixed 60 Hz from _physics_process. Nothing here reads Input or
## touches a node — the caller feeds it an InputCommand and reads state back out
## for rendering.

## Typed events, emitted at the MOMENT something happens.
##
## The view used to poll sim state each frame, which can express "is hurt" but
## never "was just hit, from that direction, for this much" — and every piece of
## feedback needs the latter. All damage funnels through apply_damage() so no
## code path can bypass these.
signal hit(position: Vector2, direction: Vector2, damage: float, full_draw: bool)
## `scoring_team` is the team that gets the point, or -1 when nobody does.
## Attribution has to travel with the event: the view can find the corpse from
## `position`, but no amount of looking at the world afterwards recovers who
## fired the arrow.
signal killed(position: Vector2, direction: Vector2, scoring_team: int)
signal fired(position: Vector2, direction: Vector2, draw_strength: float)
signal arrow_expired(position: Vector2)

const ARROW_POOL_SIZE := 150

## Upper bound on a side, and the number of spawn cells a team takes. The actual
## side size is the `bot_team_size` slider; this only caps what the arena's `P`
## cells can support.
const MAX_TEAM_SIZE := 3

## How many fighters a side actually fields this match, resolved once at build
## time. A slider rather than a constant so 1v1, 2v2 and 3v3 are all reachable
## on the device — the icon-based picker a five-year-old can use belongs with
## the countdown and results screens in feat/match-loop, not here.
var team_size: int = MAX_TEAM_SIZE

## Score, clock and phase. Owned by the simulation rather than the view,
## because "has anyone won" is a fact about the world and not about the screen
## ([ADR-0017](../../docs/decisions/0017-the-match-is-sim-state.md)).
var match_state := MatchState.new()

var player: Fighter
var fighters: Array[Fighter] = []
var arrows: Array[Arrow] = []
var arena: Arena
var bounds: Rect2 = Rect2(0, 0, 1280, 720)

var _rng := RandomNumberGenerator.new()
var _empty_cmd := InputCommand.new()


## The arena defines the world, not the caller. Bounds used to be a constant in
## main.gd that SimWorld, Terrain and CameraRig each had to agree on by hand;
## now editing the arena text file resizes everything at once.
func _init(from_arena: Arena = null) -> void:
	arena = from_arena if from_arena != null else Arena.new()
	bounds = arena.bounds()
	_rng.randomize()

	arrows.resize(ARROW_POOL_SIZE)
	for i in ARROW_POOL_SIZE:
		arrows[i] = Arrow.new()

	_build_teams()
	match_state.reset()


## Two teams, drawn from the arena's `P` cells and CLUSTERED.
##
## The first version simply sorted all nine spawns by x and handed the left half
## to team 0. That put teammates at opposite corners: the idle screenshot showed
## the player alone in a field with nobody else on screen, which is the wrong
## opening for a 3v3 and would read as "the game is broken" to a 5-year-old.
##
## So each team takes an anchor spawn and its two nearest neighbours. Teams
## start together, on opposite sides of the map, which reads instantly as two
## sides and makes the opening seconds an approach rather than a scramble. It is
## also deterministic, which the screenshot tests depend on.
func _build_teams() -> void:
	var points := arena.spawn_points()
	if points.is_empty():
		push_warning("Arena has no spawn points; falling back to centre")
		points = [bounds.get_center()]

	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var team_a := _take_cluster(points, points[0])
	var team_b := (
		_take_cluster(points, points[points.size() - 1]) if not points.is_empty() else team_a
	)

	team_size = clampi(int(Tuning.get_value("bot_team_size")), 1, MAX_TEAM_SIZE)

	for team in 2:
		var spots: Array[Vector2] = team_a if team == 0 else team_b
		for i in team_size:
			var f := Fighter.new()
			f.team = team
			f.spawn_point = spots[i % spots.size()]
			f.position = f.spawn_point
			f.prev_position = f.spawn_point
			fighters.append(f)

	# The local player is the first fighter on team 0. Everything else is driven
	# by a controller, or by nobody at all.
	player = fighters[0]

	# Every empty slot is a bot, so the match has the same shape whether one
	# person is playing or (from M3.3) three are. Seeded by index rather than
	# randomised: two bots sharing an RNG stream would strafe in lockstep, and a
	# seeded one keeps the headless tests repeatable.
	for i in range(1, fighters.size()):
		fighters[i].controller = BotController.new(i * 7919)


## Removes and returns the MAX_TEAM_SIZE spawns closest to `anchor`.
func _take_cluster(points: Array[Vector2], anchor: Vector2) -> Array[Vector2]:
	points.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return a.distance_squared_to(anchor) < b.distance_squared_to(anchor)
	)
	var out: Array[Vector2] = []
	for _i in mini(MAX_TEAM_SIZE, points.size()):
		out.append(points.pop_front())
	if out.is_empty():
		out.append(anchor)
	return out


## Fighters on the other side, still alive.
func enemies_of(team: int) -> Array[Fighter]:
	var out: Array[Fighter] = []
	for f in fighters:
		if f.team != team and f.alive():
			out.append(f)
	return out


func tick(cmd: InputCommand, delta: float) -> void:
	match_state.tick(delta)

	# The countdown and the results screen freeze the world by simply not
	# ticking it. Deliberately NOT get_tree().paused: pausing the scene tree
	# would take the tuning panel with it, and adjusting sliders between rounds
	# is the whole on-device workflow (ADR-0004). It also keeps the freeze
	# inside the simulation, where it is testable without a display.
	if not match_state.simulating():
		return

	for f in fighters:
		# The player's command comes from thumbs; everyone else's from their
		# controller, or an empty command when nobody is driving. That single
		# branch is the entire difference between a player, a bot and a dummy.
		var f_cmd := cmd
		if f != player:
			f_cmd = _command_for(f, delta)
		f.tick(f_cmd, delta, arena)

		if f_cmd.fire and f.alive():
			_try_fire(f, f_cmd)

	_tick_arrows(delta)


func _command_for(f: Fighter, delta: float) -> InputCommand:
	if f.controller == null:
		return _empty_cmd
	return f.controller.think(f, self, delta)


func _try_fire(shooter: Fighter, cmd: InputCommand) -> void:
	if not shooter.bow.consume():
		return

	var dir := cmd.aim
	if cmd.snap:
		# The snap shot is the fast, fully assisted option: it aims itself, and
		# it LEADS. A tap that points at where the target already is cannot hit
		# anything that is moving, which is the whole reason a five-year-old taps
		# in the first place.
		var target := nearest_visible_enemy(
			shooter.position, Tuning.get_value("autoaim_radius"), shooter
		)
		dir = _intercept(shooter, target) if target != null else shooter.facing
	if dir == Vector2.ZERO:
		dir = shooter.facing

	if not cmd.snap:
		dir = assisted_aim(shooter, dir)

	dir = shooter.bow.apply_deviation(dir, cmd.draw_strength, _rng)

	var arrow := _free_arrow()
	if arrow == null:
		return

	var origin := shooter.position + dir * shooter.radius
	arrow.launch(
		origin,
		dir,
		shooter.bow.speed_for(cmd.draw_strength),
		shooter.bow.damage_for(cmd.draw_strength, cmd.snap),
		Tuning.get_value("arrow_lifetime"),
		shooter.team
	)
	# A snap shot is never a "full draw" however long the thumb happened to rest.
	arrow.full_draw = cmd.draw_strength >= 0.98 and not cmd.snap
	# Shooting gives you away. Without this an ambusher in a bush is permanently
	# invisible while killing people, which is not cover — it is a cheat.
	shooter.reveal_timer = Tuning.get_value("reveal_time")
	fired.emit(origin, dir, cmd.draw_strength)


## A narrow magnetic nudge on aimed shots, toward the INTERCEPT rather than
## toward where the target currently stands.
##
## Public because the aim preview has to draw the shot that will actually be
## fired. It read `player.facing` and applied no assist at all, so the dotted
## line was already up to `aim_assist_deg` away from where the arrow went — and a
## leading assist widens that gap rather than closing it. The preview must not
## lie (ADR-0019), so it calls this.
##
## Narrow on purpose, and BOUNDED rather than snapping. Drag-to-aim is where the
## player's skill lives: the assist closes a near miss, it does not lead for you.
func assisted_aim(shooter: Fighter, dir: Vector2) -> Vector2:
	var max_angle := deg_to_rad(Tuning.get_value("aim_assist_deg"))
	if max_angle <= 0.0:
		return dir

	var target := nearest_visible_enemy(
		shooter.position, Tuning.get_value("autoaim_radius"), shooter
	)
	if target == null:
		return dir

	# Admission is judged against where the target IS, not where it is going:
	# what the player is pointing at is a thing on screen, and gating on the
	# intercept would refuse to help exactly when leading is hardest.
	var to_target := (target.position - shooter.position).normalized()
	if to_target == Vector2.ZERO or absf(dir.angle_to(to_target)) > max_angle:
		return dir

	# Rotate TOWARD the intercept by at most the cone, rather than onto it. That
	# difference is the whole design. The lead a player owes at these speeds is
	# about 16 degrees, so a 4 degree gate granting an unbounded turn would be a
	# lock-on: point at the cat and the game does all the leading, and the skill
	# the aiming is meant to reward evaporates.
	var want := dir.angle_to(_intercept(shooter, target))
	return dir.rotated(clampf(want, -max_angle, max_angle))


## Where `shooter` must point to hit `target`, at full draw.
##
## Full draw rather than the current draw strength: under `auto_repeat` every
## player shot is a full draw, and a snap shot is loosed the instant the thumb
## lifts with no draw to read. Using a partial speed here would lead by too much
## on the one shot that is hardest to place.
func _intercept(shooter: Fighter, target: Fighter) -> Vector2:
	return Aim.intercept(
		shooter.position,
		shooter.bow.speed_for(1.0),
		target.position,
		target.velocity,
		1.0,
		shooter.facing
	)


func _free_arrow() -> Arrow:
	for arrow in arrows:
		if not arrow.active:
			return arrow
	return null


func _tick_arrows(delta: float) -> void:
	for arrow in arrows:
		if not arrow.active:
			continue

		var was_active := arrow.active
		var from := arrow.position
		arrow.tick(delta, bounds)
		if not arrow.active:
			if was_active:
				arrow_expired.emit(arrow.position)
			continue

		# Walls are checked BEFORE targets, and the arrow's segment is shortened
		# to the impact point first — otherwise a target standing behind a wall
		# would still be hit by a shot that should have been stopped by it.
		var wall: Dictionary = arena.cast_segment(from, arrow.position)
		if wall["hit"]:
			arrow.position = wall["point"]

		for f in fighters:
			if not f.alive():
				continue
			# Friendly fire is off. Checked here rather than in apply_damage so
			# the arrow flies THROUGH a teammate rather than stopping dead on
			# one, which would make your own team into cover.
			if f.team == arrow.owner_team:
				continue
			if arrow.hits_circle(f.position, f.radius):
				apply_damage(
					f, arrow.damage, arrow.velocity.normalized(), arrow.full_draw, arrow.owner_team
				)
				arrow.deactivate()
				break

		if arrow.active and wall["hit"]:
			arrow.deactivate()
			arrow_expired.emit(arrow.position)


## The single funnel for every point of damage in the game.
##
## Keeping this as the only entry point is what guarantees the view never misses
## a hit: there is no second path that damages something quietly.
## `attacker_team` defaults to -1, meaning nobody gets the credit. That default
## is doing real work rather than being a convenience: it keeps every existing
## caller compiling, and it is the honest answer for damage with no author —
## which is what any future hazard or fall damage would be. A kill only ever
## scores for a team that actually earned it.
func apply_damage(
	target: Fighter, amount: float, direction: Vector2, full_draw: bool, attacker_team: int = -1
) -> void:
	var applied := target.take_damage(amount)
	if applied <= 0.0:
		return

	target.apply_knockback(direction, Tuning.get_value("knockback_force"))
	hit.emit(target.position, direction, applied, full_draw)

	if target.health.died_this_tick:
		target.health.died_this_tick = false
		# A team never scores for killing itself, however the damage was routed.
		var scoring := attacker_team if attacker_team != target.team else -1
		match_state.record_kill(scoring)
		killed.emit(target.position, direction, scoring)


## Can a fighter standing at `from` see `target`?
##
## The single rule both the bots and the view read, so "hidden" cannot mean one
## thing to the AI and another on screen. Until this existed, Arena.conceals()
## had exactly one caller — a 55% alpha fade — and bushes hid nothing from
## anybody. Concealment being cosmetic is what made ambush impossible.
##
## Order matters: the two reveals are checked BEFORE concealment, because both
## are meant to defeat it.
func can_see(from: Vector2, target: Fighter) -> bool:
	if not target.alive():
		return false
	if target.reveal_timer > 0.0:
		return true
	if from.distance_squared_to(target.position) <= _reveal_radius_squared():
		return true
	if arena.conceals(target.position):
		return false
	return not arena.cast_segment(from, target.position)["hit"]


func _reveal_radius_squared() -> float:
	var r := Tuning.get_value("reveal_radius")
	return r * r


## Nearest enemy of `seeker` that `seeker` can actually see, or null.
##
## Deliberately a second function rather than line-of-sight added to
## nearest_enemy(): that one is called by tools/screenshot.gd and asserted
## non-null by test_nearest_enemy_never_returns_a_teammate, and team spawns sit
## across the map behind stone — so filtering it here would break a test for
## reasons that have nothing to do with what it is testing.
func nearest_visible_enemy(from: Vector2, max_range: float, seeker: Fighter) -> Fighter:
	var best: Fighter = null
	var best_dist := max_range * max_range

	for f in fighters:
		if f.team == seeker.team or not f.alive():
			continue
		var dist := from.distance_squared_to(f.position)
		if dist >= best_dist:
			continue
		if not can_see(from, f):
			continue
		best_dist = dist
		best = f

	return best


## Nearest living enemy of `seeker` within range, or null.
func nearest_enemy(from: Vector2, max_range: float, seeker: Fighter) -> Fighter:
	var best: Fighter = null
	var best_dist := max_range * max_range

	for f in fighters:
		if f.team == seeker.team or not f.alive():
			continue
		var dist := from.distance_squared_to(f.position)
		if dist < best_dist:
			best_dist = dist
			best = f

	return best
