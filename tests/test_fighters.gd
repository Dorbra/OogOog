extends RefCounted
## Teams, friendly fire, death and respawn.
##
## These are the behaviours that only exist because Actor and Dummy became one
## type. Before the merge there was no team, the player could not be hurt at
## all, and respawn lived on the target class only — so none of this could be
## asserted.

# Set by the runner via set() after a no-argument new(). Declaring an _init
# that REQUIRES the runner crashes the engine outright rather than erroring,
# which is how this file announced itself on its first run.
var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _world() -> SimWorld:
	return SimWorld.new()


func _cmd() -> InputCommand:
	return InputCommand.new()


func test_fighter_fits_through_a_one_cell_gap() -> void:
	# The radius must stay under half a cell. At 34 against a 60px grid a fighter
	# standing dead centre in a cell already overlaps its neighbours, so it gets
	# shoved on the first tick and — much worse — a one-cell gap in the arena
	# becomes impassable. Both of the other failures in this file traced back to
	# exactly that, which is why it is pinned rather than just fixed.
	var w := _world()
	var half_cell := w.arena.cell_size * 0.5
	_runner.check(
		Tuning.get_value("fighter_radius") < half_cell,
		_fail("fighter radius is under half a cell, so single-cell gaps are passable")
	)


func test_two_teams_of_three_are_built() -> void:
	var w := _world()
	_runner.check(w.fighters.size() == 6, _fail("six fighters for 3v3"))

	var team_a := 0
	var team_b := 0
	for f in w.fighters:
		if f.team == 0:
			team_a += 1
		else:
			team_b += 1
	_runner.check(team_a == 3, _fail("three on team 0"))
	_runner.check(team_b == 3, _fail("three on team 1"))
	_runner.check(w.player.team == 0, _fail("the local player is on team 0"))


func test_every_fighter_spawns_on_open_ground() -> void:
	# A fighter spawned inside a wall is stuck for the whole match, and push-out
	# cannot rescue one whose cell is fully enclosed.
	var w := _world()
	for f in w.fighters:
		var cell := w.arena.cell_at(f.position)
		_runner.check(not w.arena.is_solid(cell.x, cell.y), _fail("spawn is on open ground"))


func test_teams_start_on_opposite_sides() -> void:
	var w := _world()
	var a_max := -INF
	var b_min := INF
	for f in w.fighters:
		if f.team == 0:
			a_max = maxf(a_max, f.position.x)
		else:
			b_min = minf(b_min, f.position.x)
	_runner.check(a_max <= b_min, _fail("team 0 is entirely left of team 1"))


func test_nearest_enemy_never_returns_a_teammate() -> void:
	var w := _world()
	var found := w.nearest_enemy(w.player.position, 100000.0, w.player)
	_runner.check(found != null, _fail("an enemy exists"))
	_runner.check(found.team != w.player.team, _fail("nearest_enemy skips your own team"))


func test_friendly_fire_is_rejected() -> void:
	# The arrow must pass THROUGH a teammate rather than stopping on one —
	# otherwise your own team becomes cover, which is worse than harmless.
	var w := _world()
	var mate: Fighter = null
	for f in w.fighters:
		if f != w.player and f.team == w.player.team:
			mate = f
			break
	_runner.check(mate != null, _fail("the player has a teammate"))

	var before := mate.health.current
	var arrow: Arrow = w.arrows[0]
	var dir := (mate.position - w.player.position).normalized()
	arrow.launch(w.player.position, dir, 4000.0, 50.0, 2.0, w.player.team)

	for _i in 30:
		w._tick_arrows(1.0 / 60.0)

	_runner.check_near(mate.health.current, before, _fail("a teammate takes no damage"))


func test_an_enemy_arrow_does_damage() -> void:
	# The mirror of the above: proves the friendly-fire test is not passing
	# simply because nothing ever connects.
	var w := _world()
	var foe: Fighter = w.enemies_of(w.player.team)[0]
	var before := foe.health.current
	var arrow: Arrow = w.arrows[0]
	arrow.launch(foe.position - Vector2(60, 0), Vector2.RIGHT, 4000.0, 25.0, 2.0, w.player.team)

	for _i in 30:
		w._tick_arrows(1.0 / 60.0)

	_runner.check(foe.health.current < before, _fail("an enemy arrow connects"))


func test_death_then_respawn_restores_full_health_at_the_spawn_point() -> void:
	var w := _world()
	var foe: Fighter = w.enemies_of(w.player.team)[0]
	var spawn := foe.spawn_point

	w.apply_damage(foe, 99999.0, Vector2.RIGHT, true)
	_runner.check(not foe.alive(), _fail("lethal damage kills"))

	# Drift far away, so a respawn that failed to reposition would be obvious.
	foe.position = Vector2(10, 10)

	var step := 1.0 / 60.0
	var ticks := int(Tuning.get_value("respawn_time") / step) + 10
	for _i in ticks:
		foe.tick(_cmd(), step, w.arena)

	_runner.check(foe.alive(), _fail("respawns after respawn_time"))
	_runner.check_near(foe.health.current, foe.health.maximum, _fail("respawns at full health"))
	_runner.check(foe.position.distance_to(spawn) < 1.0, _fail("respawns at its spawn point"))


func test_a_fighter_with_no_controller_stands_still() -> void:
	# This is what makes the old practice dummy a Fighter with nobody driving,
	# and it is what keeps the combat screenshot deterministic.
	#
	# The controller has to be cleared explicitly now that every empty slot is
	# filled with a bot. That is the point rather than an inconvenience: the
	# null path is exactly what tools/screenshot.gd switches to before a
	# capture, so this asserts the mechanism that gate depends on.
	var w := _world()
	# Every controller, not just this one: a live teammate bot shooting across
	# the map could knock the subject about and turn a real assertion into a
	# coin toss. A world with nobody driving is the thing being described.
	for f in w.fighters:
		f.controller = null

	# The match must be LIVE, or this passes for entirely the wrong reason:
	# SimWorld does not tick anyone outside that phase, so a frozen world would
	# satisfy "nothing moved" while proving nothing about controllers at all.
	w.match_state.phase = MatchState.Phase.LIVE

	var idle: Fighter = w.enemies_of(w.player.team)[0]
	var start := idle.position

	for _i in 120:
		w.tick(_cmd(), 1.0 / 60.0)

	_runner.check(idle.position.is_equal_approx(start), _fail("no controller means no movement"))


func test_the_player_can_be_killed() -> void:
	# Before the merge the player had no Health at all and was literally
	# invincible. That is the headline behaviour change of this milestone.
	var w := _world()
	_runner.check(w.player.health.maximum > 0.0, _fail("the player has health"))
	w.apply_damage(w.player, w.player.health.maximum, Vector2.RIGHT, true)
	_runner.check(not w.player.alive(), _fail("the player can die"))
