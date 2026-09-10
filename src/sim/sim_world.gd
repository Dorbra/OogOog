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
signal hit(position: Vector2, direction: Vector2, damage: float)
## `scoring_team` is the team that gets the point, or -1 when nobody does.
## Attribution has to travel with the event: the view can find the corpse from
## `position`, but no amount of looking at the world afterwards recovers who
## fired the bullet.
signal killed(position: Vector2, direction: Vector2, scoring_team: int)
signal fired(position: Vector2, direction: Vector2)
signal bullet_expired(position: Vector2)
## An ability went off. `kind` is the class's ability id, so the view can pick
## an effect without knowing what any of them do.
signal ability_used(position: Vector2, direction: Vector2, kind: String)

const BULLET_POOL_SIZE := 150

## Six fighters, and caltrops outlive their dropper. Twelve is two patches each
## in the air at once, which no reasonable charge rate can exceed.
const HAZARD_POOL_SIZE := 12

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
var bullets: Array[Bullet] = []
var hazards: Array[Hazard] = []
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

	bullets.resize(BULLET_POOL_SIZE)
	for i in BULLET_POOL_SIZE:
		bullets[i] = Bullet.new()

	hazards.resize(HAZARD_POOL_SIZE)
	for i in HAZARD_POOL_SIZE:
		hazards[i] = Hazard.new()

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

	# Classes are dealt round-robin from the player's pick, and BOTH TEAMS GET
	# THE SAME DEAL. Mirrored sides mean no match is decided by the draw, which
	# matters more here than variety would: the players are 5 and 10, and losing
	# to a match-up you did not choose and cannot see is the kind of unfairness
	# that ends a session. It is also deterministic, which the render captures
	# depend on.
	var first := clampi(int(Tuning.get_value("player_class")), 0, maxi(FighterClass.count() - 1, 0))

	for team in 2:
		var spots: Array[Vector2] = team_a if team == 0 else team_b
		for i in team_size:
			var f := Fighter.new()
			f.team = team
			f.fighter_class = FighterClass.at(first + i)
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

		if f_cmd.ability and f.alive():
			_try_ability(f)

	_tick_bullets(delta)
	_tick_hazards(delta)


func _command_for(f: Fighter, delta: float) -> InputCommand:
	if f.controller == null:
		return _empty_cmd
	return f.controller.think(f, self, delta)


## One shot. Every shot is the same shot.
##
## The gun itself decides whether it may fire — magazine and the fire-rate
## cooldown both live in Gun.consume() — so the player and the bots are rate
## limited by identical code. There is no path here that produces a faster or
## stronger bullet for anybody.
##
## There is also no deviation any more. A random spread on top of a fast flat
## bullet is precisely the "cant be expected" that got the bow replaced: the
## line you aim along is the line the bullet takes.
func _try_fire(shooter: Fighter, cmd: InputCommand) -> void:
	if not shooter.gun.consume():
		return

	var dir := cmd.aim
	if dir == Vector2.ZERO:
		dir = shooter.facing
	# A tap aims itself COMPLETELY, at the intercept rather than at where the
	# target stands. assisted_aim() below is a 4-degree nudge that closes a near
	# miss; this is the whole shot handed over, and it is the difference between
	# a five-year-old hitting things and not (ADR-0013).
	#
	# It is only reachable from a press-and-release that never carried a
	# direction, and one release is one bullet — so unlike the tap that existed
	# under automatic fire, it cannot be used to spray.
	if cmd.snap:
		var locked := snap_target(shooter)
		if locked != null:
			dir = _intercept(shooter, locked)
	dir = assisted_aim(shooter, dir)

	var origin := shooter.position + dir * shooter.radius
	_launch_fan(shooter, origin, dir)
	# You shot that way, so you are facing that way — and you STAY facing that
	# way, because nothing else moves facing any more.
	#
	# This is what covers the tap. _emit_shot() sends Vector2.ZERO for a tap
	# because the caller auto-aims it, so the firing tick would otherwise fall
	# through to Fighter.tick()'s movement branch and the cat would snap to face
	# where it was walking — the exact reset this change exists to remove, but
	# only on the one shot a five-year-old actually uses.
	shooter.facing = dir
	shooter.mark_aimed()

	# Shooting gives you away. Without this an ambusher in a bush is permanently
	# invisible while killing people, which is not cover — it is a cheat.
	shooter.reveal_timer = Tuning.get_value("reveal_time")
	fired.emit(origin, dir)


## Spends a full charge bar on whatever this fighter's class carries.
##
## Dispatched by NAME from the class table rather than by a type hierarchy or a
## match on the class itself. Adding the lobber's burning zone next PR is then a
## line in classes.json plus a branch here, and nothing else in the simulation
## has to learn that a third class exists.
func _try_ability(user: Fighter) -> void:
	if not user.spend_charge():
		return

	var dir := user.facing
	match user.fighter_class.ability:
		"dash":
			_do_dash(user, dir)
		"caltrops":
			_do_caltrops(user)
		_:
			# An unknown ability spends nothing, because spend_charge() already
			# took the bar. Refund it rather than silently eating the reward for
			# a whole fight's worth of damage.
			user.charge = 1.0
			push_error("SimWorld: unknown ability '%s'" % user.fighter_class.ability)
			return

	ability_used.emit(user.position, dir, user.fighter_class.ability)


## A shove along the aim, using the SAME knockback path a bullet uses.
##
## Not a teleport and not a speed buff: an impulse, which means Fighter's own
## wall push-out stops it dead at stone with no extra collision code, and the
## existing friction bleeds it off. A dash that crossed walls would be a hole in
## the arena, not an ability.
func _do_dash(user: Fighter, dir: Vector2) -> void:
	user.apply_knockback(dir, Tuning.get_value("dash_force"))


## Drops a patch of caltrops on the ground the dropper is standing on.
##
## AT THE DROPPER, not thrown ahead. A thrown one needs an aim, a travel time
## and a landing preview, and it turns a panic button into a skill shot — which
## is the wrong shape for the youngest player and the wrong shape for the class:
## a Skirmisher drops these while backing out of a fight it is losing.
func _do_caltrops(user: Fighter) -> void:
	var hazard := _free_hazard()
	if hazard == null:
		return
	hazard.arm(
		user.position,
		Tuning.get_value("caltrops_radius"),
		Tuning.get_value("caltrops_damage_per_second"),
		Tuning.get_value("caltrops_time"),
		user.team,
		user.get_instance_id()
	)


func _free_hazard() -> Hazard:
	for hazard in hazards:
		if not hazard.active:
			return hazard
	return null


## Hazards hurt whoever is standing in them, once per tick, at a rate.
func _tick_hazards(delta: float) -> void:
	for hazard in hazards:
		hazard.tick(delta)
		if not hazard.active:
			continue
		for f in fighters:
			if not f.alive() or f.team == hazard.owner_team:
				continue
			if not hazard.covers(f.position, f.radius):
				continue
			# Direction is away from the centre, so the knockback and the hit
			# effect shove a victim OUT of the patch rather than in a direction
			# that has nothing to do with why they are being hurt.
			var away := f.position - hazard.position
			var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.UP
			apply_damage(
				f, hazard.damage_per_second * delta, dir, hazard.owner_team, hazard.owner_id
			)


## One trigger pull, however many pellets the class fires.
##
## The fan is DETERMINISTIC: fixed angles across the arc, so point blank all
## three of a Skirmisher's pellets connect and at range they open. It is not
## random, and that is deliberate rather than lazy — random spread on a fast
## flat bullet is exactly the "cant be expected" that got the bow deleted
## (ADR-0022), and it would make every headless assertion about where a shot
## goes unrepeatable as well.
##
## Note what is NOT here: a second Gun.consume(). The magazine was already spent
## by the caller, once, for the whole fan. Spending a round per pellet would
## empty a Skirmisher three times as fast as its magazine multiplier says, which
## is the kind of thing that reads as "this class is terrible" rather than as a
## bug.
func _launch_fan(shooter: Fighter, origin: Vector2, dir: Vector2) -> void:
	var gun := shooter.gun
	for i in gun.pellets():
		var bullet := _free_bullet()
		# Pool exhausted. Firing what is left beats dropping the whole shot: a
		# missing pellet is invisible, a missing trigger pull is not.
		if bullet == null:
			return
		bullet.launch(
			origin,
			dir.rotated(gun.pellet_angle(i)),
			gun.speed(),
			gun.damage(),
			gun.lifetime(),
			shooter.team,
			shooter.get_instance_id()
		)


## Who a tap shot locks onto: the nearest enemy this shooter can actually see,
## inside auto-aim range.
##
## Public so the view can draw the lock before the thumb comes up — a tap that
## silently picks a target the player did not expect is the preview lying again
## (ADR-0019), and here the player has a whole hold in which to notice.
func snap_target(shooter: Fighter) -> Fighter:
	return nearest_visible_enemy(shooter.position, Tuning.get_value("autoaim_radius"), shooter)


## A narrow magnetic nudge on aimed shots, toward the INTERCEPT rather than
## toward where the target currently stands.
##
## Public because the aim preview has to draw the shot that will actually be
## fired. It read `player.facing` and applied no assist at all, so the dotted
## line was already up to `aim_assist_deg` away from where the bullet went — and a
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


## Where `shooter` must point to hit `target`.
func _intercept(shooter: Fighter, target: Fighter) -> Vector2:
	return Aim.intercept(
		shooter.position, shooter.gun.speed(), target.position, target.velocity, 1.0, shooter.facing
	)


func _free_bullet() -> Bullet:
	for bullet in bullets:
		if not bullet.active:
			return bullet
	return null


func _tick_bullets(delta: float) -> void:
	for bullet in bullets:
		if not bullet.active:
			continue

		var was_active := bullet.active
		var from := bullet.position
		bullet.tick(delta, bounds)
		if not bullet.active:
			if was_active:
				bullet_expired.emit(bullet.position)
			continue

		# Walls are checked BEFORE targets, and the bullet's segment is shortened
		# to the impact point first — otherwise a target standing behind a wall
		# would still be hit by a shot that should have been stopped by it.
		var wall: Dictionary = arena.cast_segment(from, bullet.position)
		if wall["hit"]:
			bullet.position = wall["point"]

		for f in fighters:
			if not f.alive():
				continue
			# Friendly fire is off. Checked here rather than in apply_damage so
			# the bullet flies THROUGH a teammate rather than stopping dead on
			# one, which would make your own team into cover.
			if f.team == bullet.owner_team:
				continue
			if bullet.hits_circle(f.position, f.radius):
				apply_damage(
					f,
					bullet.damage,
					bullet.velocity.normalized(),
					bullet.owner_team,
					bullet.owner_id
				)
				bullet.deactivate()
				break

		if bullet.active and wall["hit"]:
			bullet.deactivate()
			bullet_expired.emit(bullet.position)


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
	target: Fighter,
	amount: float,
	direction: Vector2,
	attacker_team: int = -1,
	attacker_id: int = 0
) -> void:
	var applied := target.take_damage(amount)
	if applied <= 0.0:
		return

	# Charge is paid HERE because this is the single funnel every damage path
	# already goes through — bullets, caltrops, and whatever comes next. Paying
	# it at each call site instead would mean a future damage source that
	# silently earns nothing, and nobody would notice for a milestone.
	#
	# Never for friendly fire, and never for hurting yourself: an ability you can
	# charge by shooting your own team is not an ability, it is a chore.
	var attacker := instance_from_id(attacker_id) as Fighter if attacker_id != 0 else null
	if attacker != null and attacker != target and attacker.team != target.team:
		attacker.add_charge(applied)

	target.apply_knockback(direction, Tuning.get_value("knockback_force"))
	hit.emit(target.position, direction, applied)

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
