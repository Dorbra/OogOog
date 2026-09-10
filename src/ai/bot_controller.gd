class_name BotController
extends RefCounted
## Drives a Fighter by producing an InputCommand, exactly as thumbs do.
##
## This is the third producer the sim/view split was built for (ADR-0003). It
## needed no change to Fighter, SimWorld.tick() or the view: the seam was
## already there, waiting, in the one branch that reads
##
##     f_cmd = _command_for(f, delta)
##
## A bot therefore cannot cheat by construction. It cannot read Input, set a
## position, or reach past the Gun to spawn a bullet — the only thing it can do
## is fill in the same fields the player fills in. When a bot out-shoots you, it
## is because it aimed better, not because it had a different gun. Rate of fire
## is enforced inside Gun for exactly that reason.

enum State { SEEK, ENGAGE, RETREAT, LURK }

## How far the skill slider can sharpen each penalty. At bot_skill 1.0 a bot
## keeps 15% of its aim error and 20% of its reaction delay rather than dropping
## to zero: a bot that never misses and answers instantly is not "hard", it is
## unpleasant, and it is the failure mode this project is most likely to ship.
const AIM_ERROR_FLOOR := 0.15
const REACTION_FLOOR := 0.2

## How far ahead to test for a wall when strafing. Roughly a third of a cell —
## far enough to turn before scraping, close enough not to dodge shadows.
const STRAFE_LOOKAHEAD := 22.0

## A waypoint counts as reached inside this fraction of a cell. Too tight and a
## bot oscillates around a point it can never stand exactly on.
const WAYPOINT_TOLERANCE := 0.45

## How close to its preferred range counts as "arrived", as a fraction of that
## range. Inside this the bot stops closing and simply holds.
const RANGE_DEADBAND := 0.12

var state: int = State.SEEK

# One command instance, refilled each tick. Allocating a new one per bot per
# tick would be 300 objects a second for nothing — and returning SimWorld's
# shared _empty_cmd instead would let one bot's aim leak into another's.
var _cmd := InputCommand.new()

# Each bot owns its RNG so aim scatter is reproducible in tests. Sharing
# SimWorld's would make a bot's aim depend on how many bullets happened to be in
# flight, which is exactly the kind of coupling that makes a failure unrepeatable.
var _rng := RandomNumberGenerator.new()

var _path := PackedVector2Array()
var _path_index: int = 0
var _repath_timer: float = 0.0
var _goal_cell := Vector2i(-1, -1)

var _reaction_timer: float = 0.0

## The instance id of the fighter being shot at, NOT a reference to it.
##
## Holding the Fighter itself makes a reference cycle — Fighter.controller keeps
## the bot alive, and the bot would keep a Fighter alive — and RefCounted cannot
## collect a cycle. The smoke test caught it immediately as eighteen leaked
## objects at exit. Only the identity is needed anyway, and only to notice that
## the target has changed; who it actually is, is a fact about this tick and is
## passed as an argument.
var _target_id: int = 0

var _strafe_sign: float = 1.0

## Where in the strafe cycle this bot is. A bot used to apply a lateral term on
## EVERY tick it could see anybody and reverse it every 1.2 s, so it never once
## stood still — six of those read as frantic darting at any movement speed, and
## no speed slider fixes it:
##
##     "characters move around too fast" (the enemies, not the player)
##
## Now each cycle is part strafe, part stand. Standing still is what makes a bot
## readable, and being readable is what makes it hittable.
var _strafe_phase: float = 0.0

## The angular error of the shot about to be taken, in radians. Re-rolled once
## per shot rather than per tick: committing to one wrong angle is how a person
## misses, and averaging a fresh error every frame would make the bot's aim
## converge on perfect while its head visibly vibrated.
var _aim_jitter: float = 0.0

var _last_known := Vector2.ZERO
var _has_last_known := false

## Which enemy spawn this bot is walking toward while it has nobody to chase.
var _patrol_index: int = 0


func _init(rng_seed: int = 0) -> void:
	_rng.seed = rng_seed
	_strafe_sign = 1.0 if (rng_seed & 1) == 0 else -1.0
	# Offset into the cycle, so a team does not stop and start as one body.
	_strafe_phase = _rng.randf() * 2.0
	# Fanned out by seed rather than all starting at zero, or a team's three bots
	# would patrol in single file and search one third of the map between them.
	_patrol_index = absi(rng_seed)


## Called once per simulation tick by SimWorld._command_for().
func think(me: Fighter, world: SimWorld, delta: float) -> InputCommand:
	_cmd.clear()
	if not me.alive():
		_forget()
		return _cmd

	_tick_timers(delta)
	# The target is a fact about THIS TICK and is passed down rather than
	# stored: a controller holding a Fighter closes a reference cycle through
	# Fighter.controller that RefCounted cannot collect.
	var target := _acquire(me, world)
	state = _choose_state(me, world, target)

	match state:
		State.RETREAT:
			_do_retreat(me, world, target)
		State.LURK:
			_do_lurk(me)
		State.ENGAGE:
			_do_engage(me, world, target)
		_:
			_do_seek(me, world)

	return _cmd


func _tick_timers(delta: float) -> void:
	_repath_timer = maxf(0.0, _repath_timer - delta)
	_reaction_timer = maxf(0.0, _reaction_timer - delta)
	# One cycle = one strafe segment plus one pause. The sign flips at the top of
	# each cycle rather than on its own clock, so a bot commits to a direction
	# for a whole segment instead of reversing mid-slide.
	var period := maxf(Tuning.get_value("bot_strafe_flip_time"), 0.05)
	_strafe_phase += delta
	while _strafe_phase >= period:
		_strafe_phase -= period
		_strafe_sign = -_strafe_sign


## Finds a target and starts the reaction clock when one appears.
##
## The clock restarts only when the target CHANGES, not every tick it is
## visible — otherwise the delay would reset forever and the bot would never
## take a shot at all.
func _acquire(me: Fighter, world: SimWorld) -> Fighter:
	var found := world.nearest_visible_enemy(me.position, Tuning.get_value("bot_sight_range"), me)
	var found_id := found.get_instance_id() if found != null else 0
	if found != null and found_id != _target_id:
		_reaction_timer = _reaction_time()
	_target_id = found_id

	if found != null:
		_last_known = found.position
		_has_last_known = true
	return found


func _choose_state(me: Fighter, world: SimWorld, target: Fighter) -> int:
	if me.health.fraction() < Tuning.get_value("bot_retreat_health"):
		return State.RETREAT

	# Checked BEFORE engaging on purpose: a bot that shoots the moment it sees
	# anyone can never ambush, because the first shot is what gives it away.
	if _can_ambush(me, world):
		var range_sq := Tuning.get_value("bot_ambush_range")
		range_sq *= range_sq
		if target == null or me.position.distance_squared_to(target.position) > range_sq:
			return State.LURK

	if target != null:
		return State.ENGAGE
	return State.SEEK


## Full cover play is gated on the difficulty slider, and that is the whole
## point of the gate. Being killed from inside a bush you never saw is the most
## frustrating thing in this design for a five-year-old and the most interesting
## thing in it for a ten-year-old — so it arrives with the skill, rather than
## being on for everyone or nobody.
func _can_ambush(me: Fighter, world: SimWorld) -> bool:
	if _skill() <= Tuning.get_value("bot_cover_skill_gate"):
		return false
	if me.health.fraction() < 0.999:
		return false
	return world.arena.conceals(me.position)


# ---------------------------------------------------------------- behaviours


func _do_seek(me: Fighter, world: SimWorld) -> void:
	# Arrived at the ghost and found nobody there: forget it. Without this a bot
	# stands on the patch of grass where it last saw somebody for the rest of the
	# match, because _steer() returns a zero vector once you are on your goal.
	if _has_last_known and me.position.distance_to(_last_known) <= world.arena.cell_size:
		_has_last_known = false

	var anchor := _last_known if _has_last_known else _patrol(me, world)
	var goal := anchor
	if _skill() > Tuning.get_value("bot_cover_skill_gate"):
		var bush := _nearest_bush(world.arena, me.position, anchor)
		if bush != Vector2.INF:
			goal = bush

	_cmd.move = _steer(me, world, goal)
	if _cmd.move != Vector2.ZERO:
		_cmd.aim = _cmd.move


## Backs off to somewhere the threat cannot shoot, and keeps shooting on the way
## out. Out-of-combat regen does the actual healing, so all a retreat has to do
## is break the line and survive the trip.
func _do_retreat(me: Fighter, world: SimWorld, target: Fighter) -> void:
	var threat := _last_known if _has_last_known else me.position
	var cover := _nearest_cover(world.arena, me.position, threat)
	if cover != Vector2.INF:
		_cmd.move = _steer(me, world, cover)
	elif _has_last_known:
		_cmd.move = (me.position - threat).normalized()

	if target != null:
		_aim_and_fire(me, world, target)
	elif _cmd.move != Vector2.ZERO:
		_cmd.aim = _cmd.move


## Stand still in cover and wait. No movement, no shooting, no path — a lurking
## bot is deliberately doing nothing, because anything else reveals it.
func _do_lurk(me: Fighter) -> void:
	_forget_path()
	if _has_last_known:
		_cmd.aim = (_last_known - me.position).normalized()
	else:
		_cmd.aim = me.facing


func _do_engage(me: Fighter, world: SimWorld, target: Fighter) -> void:
	var to_target := target.position - me.position
	var distance := to_target.length()
	if distance < 0.001:
		_aim_and_fire(me, world, target)
		return

	var forward := to_target / distance
	var preferred := preferred_range(me)

	# Close if too far, back off if too near. Proportional rather than a hard
	# toward/away, so a bot settles at its preferred range instead of jittering
	# across it — and so it genuinely STOPS once it is there.
	var radial := clampf((distance - preferred) / maxf(preferred, 1.0), -1.0, 1.0)

	# A deadband, so a bot that has ARRIVED at its range stops there instead of
	# creeping back and forth across it forever. Without it the radial term is
	# never quite zero and a bot can never be still, which defeats the strafe
	# pause below: the pause would only stop the circling, and the bot would go
	# on shuffling toward and away from you the whole fight.
	if absf(radial) < RANGE_DEADBAND:
		radial = 0.0

	var tangent := Vector2(-forward.y, forward.x) * _strafe_sign

	# The lateral term applies only during the strafe part of the cycle. It used
	# to apply on every tick, at 0.85, which is why six bots read as frantic
	# darting: nothing ever stood still long enough to be looked at, let alone
	# aimed at. Standing still is what makes a bot readable, and being readable
	# is what makes it hittable.
	var weight := Tuning.get_value("bot_strafe_weight") if _is_strafing() else 0.0
	var move := forward * radial + tangent * weight
	if move.length_squared() > 0.0001:
		move = move.normalized()
		# Strafing is unpathed, so a bot circling into a wall would grind along
		# it for as long as the fight lasted. Flipping on contact turns that
		# into the pacing it was meant to be.
		var ahead := me.position + move * (me.radius + STRAFE_LOOKAHEAD)
		var cell := world.arena.cell_at(ahead)
		if world.arena.is_solid(cell.x, cell.y):
			_strafe_sign = -_strafe_sign
			# Restart the cycle so the bot commits to the new direction for a
			# full segment rather than scraping back into the same wall.
			_strafe_phase = 0.0
			tangent = -tangent
			move = (forward * radial + tangent * weight).normalized()
		_cmd.move = move

	_aim_and_fire(me, world, target)


# --------------------------------------------------------------------- firing


## Aims at where the target will be, scatters the shot by the difficulty error,
## and refuses to shoot into stone.
func _aim_and_fire(me: Fighter, world: SimWorld, target: Fighter) -> void:
	if target == null:
		return

	# Aim is set whatever happens below, so a bot that is reloading, out of
	# range or blocked still faces its target rather than staring into space.
	var aim := _lead(me, target)
	_cmd.aim = aim

	if _reaction_timer > 0.0:
		return

	# Do not shoot at something the bullet cannot physically reach.
	#
	# This is half of "the bots shoot at me from out-of-screen": a bot could
	# acquire a target well beyond its own range and fire anyway, because the
	# only gate below is whether a wall is in the way. The shots died in mid-air,
	# so nothing was ever hit by them — the player just saw fire arriving from
	# somewhere off screen for no reason.
	if me.position.distance_to(target.position) > me.gun.reach():
		return

	# Gun.consume() will refuse anyway; asking first avoids rolling an aim error
	# for a shot that is not going to happen.
	if not me.gun.can_fire():
		return

	# Rolled once per shot, at the instant of firing. There is no draw to hold it
	# across any more, which is exactly why this is simpler than it was: a bot
	# commits to one wrong angle per bullet, which is how a person misses, and
	# the aim it DISPLAYS between shots stays clean so its head does not vibrate.
	var error := deg_to_rad(_aim_error_deg())
	if error > 0.0:
		_aim_jitter = _rng.randf_range(-error, error)
		aim = aim.rotated(_aim_jitter)
		_cmd.aim = aim

	# The same wall question the bullet itself will ask a tick from now. Firing
	# into cover wastes the round AND the reload, which at five rounds is most of
	# a fight's worth of ammunition.
	var origin := me.position + aim * me.radius
	var to := origin + aim * minf(me.gun.reach(), me.position.distance_to(target.position))
	if world.arena.cast_segment(origin, to)["hit"]:
		# Simply do not fire. Next tick re-rolls the error against a fresh angle,
		# so a blocked shot costs a tick rather than freezing the bot forever —
		# which is what the old version did when it held one rolled angle against
		# the same wall indefinitely.
		return

	_cmd.fire = true


## Where to point so a travelling bullet and a moving target arrive together.
##
## The prediction itself lives in Aim.intercept(), shared with the player's
## auto-aim. It used to live here and ONLY here, which is how the player's assist
## came to aim at where a target already was — see the header of src/sim/aim.gd.
##
## How much of the prediction a bot actually applies is the difficulty knob: at
## bot_skill 0 the lead is zero and the bot shoots where you are.
func _lead(me: Fighter, target: Fighter) -> Vector2:
	return Aim.intercept(
		me.position,
		me.gun.speed(),
		target.position,
		target.velocity,
		Tuning.get_value("bot_lead_factor") * _skill(),
		me.facing
	)


# ------------------------------------------------------------------ movement


## Path to `goal` and return a unit vector toward the next waypoint.
##
## Repaths on a timer or when the goal moves to a different cell, never per
## tick: a target walking across a cell boundary is the only event that can
## change the route, and A* every frame for six bots is work spent to get the
## same answer back.
func _steer(me: Fighter, world: SimWorld, goal: Vector2) -> Vector2:
	var arena := world.arena
	var goal_cell := arena.cell_at(goal)
	if _repath_timer <= 0.0 or _path.is_empty() or goal_cell != _goal_cell:
		_path = GridPath.find_path(arena, me.position, goal)
		_path_index = 0
		_goal_cell = goal_cell
		_repath_timer = Tuning.get_value("bot_repath_interval")

	var tolerance := arena.cell_size * WAYPOINT_TOLERANCE
	while _path_index < _path.size():
		if me.position.distance_to(_path[_path_index]) > tolerance:
			break
		_path_index += 1

	# Off the end of the path, or no path at all: walk straight at the goal.
	# Push-out will scrape a bot along a wall rather than let it stand still,
	# which is a better failure than freezing where the player can farm it.
	var waypoint := _path[_path_index] if _path_index < _path.size() else goal
	var delta := waypoint - me.position
	if delta.length_squared() < 0.0001:
		return Vector2.ZERO
	return delta.normalized()


## Somewhere to look when there is nobody to chase — and, more importantly,
## somewhere that is never a place to STOP.
##
## This used to be the middle of the map, which is a point a bot can arrive at.
## Once there `_steer()` returns a zero vector and it stands still. After every
## fighter had died once and lost contact, both teams did exactly that on
## opposite sides of an empty arena: a 3-3 match ran for ten more minutes without
## a single shot fired. On a phone that is the results screen never appearing,
## which is indistinguishable from the game hanging.
##
## So a bot with nothing to do patrols the ENEMY's spawn cells in rotation and
## advances the moment it reaches one. Enemies keep coming back to those, and
## both teams end up crossing the arena in opposite directions, so contact
## re-establishes itself instead of depending on luck.
##
## Spawn cells are map knowledge, not sight — the same thing any player learns in
## one round. The bot is not being told where anybody currently is, and nothing
## here touches how it aims.
func _patrol(me: Fighter, world: SimWorld) -> Vector2:
	var spawns := _enemy_spawns(me, world)
	if spawns.is_empty():
		return world.arena.bounds().get_center()

	var goal: Vector2 = spawns[_patrol_index % spawns.size()]
	if me.position.distance_to(goal) <= world.arena.cell_size:
		_patrol_index += 1
		goal = spawns[_patrol_index % spawns.size()]
	return goal


## The other side's spawn cells, deduplicated and in a stable order.
##
## Deduplicated because a team fields more fighters than the arena has spawns for
## when `bot_team_size` exceeds the cluster, and `_build_teams()` wraps — three
## copies of one point would make the rotation stand still, which is the exact
## failure this is here to prevent.
func _enemy_spawns(me: Fighter, world: SimWorld) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for f in world.fighters:
		if f.team == me.team or out.has(f.spawn_point):
			continue
		out.append(f.spawn_point)
	return out


# ------------------------------------------------------------- grid searches


## Nearest open cell from which `threat` cannot be seen. Vector2.INF when the
## whole neighbourhood is exposed, which on an open map is the honest answer.
##
## MEASURED AT 478 us A CALL, against a mean simulation tick of 226 us — and
## _do_retreat() calls it EVERY TICK a bot is retreating, with no cache and no
## timer. Ticks with somebody retreating cost 536 us against 226 us for the
## rest: this one function was 2.4x the cost of a frame's simulation, on 30% of
## the frames in a match. ARCHITECTURE.md called it "negligible on 24x14", which
## is what an unmeasured adjective is worth (ADR-0027).
##
## The cost was never the grid walk, it was the raycast per cell. The rewrite
## below changes only the ORDER cells are visited, and that is safe precisely
## because the answer does not depend on order — the loop keeps a running
## minimum, so any order returns the same cell. Order decides only how early the
## distance test starts pruning.
##
## So it walks outward from the bot in square rings instead of scanning
## row-major from the arena's top-left corner. Cover is usually a cell or two
## away, and every ring beyond the one that found it is skipped whole: once the
## best distance beats the closest any further ring could possibly be, there is
## nothing left to check.
##
## The row-major tie-break is preserved deliberately, and honestly it is the one
## line here with no evidence behind it: 800 probes across this arena, half of
## them from exact cell centres where symmetry would bite, never once produced
## two cover cells at exactly equal distance. Removing it keeps every test green.
##
## It stays because it costs two comparisons on the rare accepted cell and it is
## what makes the equivalence an ARGUMENT rather than an observation — order
## cannot change the answer, ties included, on this map or the next one. A gate
## that passes on one hand-authored arena is not a proof about the algorithm,
## and more arenas are coming.
func _nearest_cover(arena: Arena, from: Vector2, threat: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_dist := INF
	var best_index := 0x7FFFFFFF

	var origin := arena.cell_at(from)
	var max_ring := maxi(
		maxi(origin.x, arena.cols - 1 - origin.x), maxi(origin.y, arena.rows - 1 - origin.y)
	)

	for ring in max_ring + 1:
		# A cell on ring `ring` sits at least (ring - 1) cells away from `from`,
		# wherever inside its own cell `from` happens to be. Deliberately one
		# ring slacker than the tight bound: cheap, and it cannot cut the search
		# short of the true nearest.
		if ring > 1:
			var floor_dist := float(ring - 1) * arena.cell_size
			if best_dist <= floor_dist * floor_dist:
				break

		for dy in range(-ring, ring + 1):
			var y := origin.y + dy
			if y < 0 or y >= arena.rows:
				continue
			# Only the top and bottom rows of a ring are solid runs; the rows
			# between them contribute just their two end cells.
			var step := 1 if (ring == 0 or absi(dy) == ring) else ring * 2
			var dx := -ring
			while dx <= ring:
				var x := origin.x + dx
				dx += step
				if x < 0 or x >= arena.cols or arena.is_solid(x, y):
					continue

				var index := y * arena.cols + x
				var centre := arena.cell_centre(x, y)
				var dist := from.distance_squared_to(centre)
				# `>` then the index test, rather than `>=`: an exact tie must
				# resolve to the row-major-earlier cell, as the old loop did.
				if dist > best_dist or (dist == best_dist and index >= best_index):
					continue
				if not arena.cast_segment(centre, threat)["hit"]:
					continue
				best_dist = dist
				best_index = index
				best = centre

	return best


## The bush closest to `toward` — somewhere to lie in wait that is on the way to
## the fight rather than in a corner of the map nobody walks past.
## Bushes never move, so the list is built once by the arena and read here.
## This used to call cells_in_rect(bounds()), which allocates an array of all
## 108 non-open cells on every call in order to look at the 16 that are bushes —
## 141 us a call, and the allocation churn ADR-0009 exists about.
func _nearest_bush(arena: Arena, from: Vector2, toward: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_score := INF
	for centre in arena.bush_centres():
		# Weighted toward the anchor, but not blind to distance: a perfect bush
		# on the far side of the map is worse than a good one underfoot.
		var score := centre.distance_to(toward) + 0.35 * centre.distance_to(from)
		if score < best_score:
			best_score = score
			best = centre
	return best


# -------------------------------------------------------------------- skill


## The distance this bot wants to hold, SCALED BY ITS OWN GUN.
##
## The global key is 170 px against a Ranger's 231 px reach — about three
## quarters of it. Read raw, a Skirmisher (62% reach, so 143 px) would stand at
## 170 and hold station beyond the range it can actually shoot: permanently
## backing off, never firing, never still. That is not a tuning subtlety, it is
## a class that does not work, and it showed up as a bot standing still 0% of a
## fight.
##
## Scaling by the class multiplier keeps the same three-quarters relationship
## for every gun, and it is what makes the Skirmisher a brawler that closes
## rather than a Ranger that misses.
## PUBLIC and static because the tests have to stage a bot at a distance it
## actually wants to fight from, and computing that themselves is how three
## fixtures ended up asserting against a station no bot stands at.
static func preferred_range(me: Fighter) -> float:
	return minf(
		Tuning.get_value("bot_preferred_range") * me.fighter_class.reach_mult,
		me.gun.effective_range() * 0.85
	)


## Is this bot in the moving part of its strafe cycle?
##
## `bot_strafe_duty` is the fraction of each cycle spent sliding sideways; the
## remainder is spent standing. At 1.0 this reduces exactly to the old
## always-strafing behaviour, which is what makes the duty cycle testable by
## turning it off.
func _is_strafing() -> bool:
	var period := maxf(Tuning.get_value("bot_strafe_flip_time"), 0.05)
	var duty := clampf(Tuning.get_value("bot_strafe_duty"), 0.0, 1.0)
	return _strafe_phase < period * duty


func _skill() -> float:
	return clampf(Tuning.get_value("bot_skill"), 0.0, 1.0)


func _aim_error_deg() -> float:
	var full := Tuning.get_value("bot_aim_error_deg")
	return lerpf(full, full * AIM_ERROR_FLOOR, _skill())


func _reaction_time() -> float:
	var full := Tuning.get_value("bot_reaction_time")
	return lerpf(full, full * REACTION_FLOOR, _skill())


func _forget_path() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_goal_cell = Vector2i(-1, -1)


func _forget() -> void:
	_forget_path()
	_target_id = 0
	_has_last_known = false
	_reaction_timer = 0.0
