extends RefCounted
## Abilities: charged by damage dealt, spent once, and unable to cheat.
##
## The charge economy is the part worth guarding. It is paid inside
## SimWorld.apply_damage(), the single funnel every damage path already goes
## through — so the ways it goes wrong are all "somebody got paid who should not
## have been", and every one of them is invisible in play until a match feels
## unfair for a reason nobody can name.

const DT := 1.0 / 60.0

var _runner: Object
var _case: String

var _saved := {}


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _tune(key: String, value: float) -> void:
	if not _saved.has(key):
		_saved[key] = Tuning.get_value(key)
	Tuning.set_value(key, value)


func _restore() -> void:
	for key: String in _saved:
		Tuning.set_value(key, _saved[key])
	_saved.clear()


func _world() -> SimWorld:
	var w := SimWorld.new()
	for f in w.fighters:
		f.controller = null
	w.match_state.phase = MatchState.Phase.LIVE
	return w


func _enemy_of(w: SimWorld, f: Fighter) -> Fighter:
	return w.enemies_of(f.team)[0]


func _mate_of(w: SimWorld, f: Fighter) -> Fighter:
	for other in w.fighters:
		if other != f and other.team == f.team:
			return other
	return null


func _class_with_ability(ability: String) -> FighterClass:
	for class_id in FighterClass.all():
		var cls := FighterClass.get_class_by_id(class_id)
		if cls.ability == ability:
			return cls
	return null


# ------------------------------------------------------------------ charging


func test_charge_is_paid_for_damage_dealt_not_taken() -> void:
	_case = "charge"
	var w := _world()
	var attacker := w.player
	var victim := _enemy_of(w, attacker)

	w.apply_damage(victim, 50.0, Vector2.RIGHT, attacker.team, attacker.get_instance_id())

	_runner.check(attacker.charge > 0.0, _fail("the attacker was paid (%.3f)" % attacker.charge))
	# The mirror, and the one that matters: being shot must not charge you, or
	# the losing player farms an ability by standing in the open.
	_runner.check(victim.charge == 0.0, _fail("the victim was NOT paid (%.3f)" % victim.charge))


func test_friendly_fire_and_self_harm_pay_nothing() -> void:
	_case = "no free charge"
	var w := _world()
	var attacker := w.player
	var mate := _mate_of(w, attacker)
	_runner.check(mate != null, _fail("the roster has a teammate to test against"))

	w.apply_damage(mate, 80.0, Vector2.RIGHT, attacker.team, attacker.get_instance_id())
	_runner.check(attacker.charge == 0.0, _fail("shooting a teammate charges nothing"))

	w.apply_damage(attacker, 80.0, Vector2.RIGHT, attacker.team, attacker.get_instance_id())
	_runner.check(attacker.charge == 0.0, _fail("hurting yourself charges nothing"))


func test_the_bar_fills_at_the_advertised_rate_and_stops_at_full() -> void:
	_case = "charge rate"
	var w := _world()
	_tune("ability_charge_damage", 100.0)
	var attacker := w.player
	var victim := _enemy_of(w, attacker)

	w.apply_damage(victim, 50.0, Vector2.RIGHT, attacker.team, attacker.get_instance_id())
	_runner.check(
		is_equal_approx(attacker.charge, 0.5),
		_fail("half the damage is half a bar (%.3f)" % attacker.charge)
	)

	# Overkill must not bank. Otherwise a big last hit buys the NEXT ability too.
	victim.health.revive()
	w.apply_damage(victim, 400.0, Vector2.RIGHT, attacker.team, attacker.get_instance_id())
	_runner.check(
		is_equal_approx(attacker.charge, 1.0),
		_fail("the bar caps at full (%.3f)" % attacker.charge)
	)
	_restore()


func test_charge_survives_dying() -> void:
	_case = "charge after death"
	# Deliberate, not an oversight. Losing your charge on death punishes the
	# player who is already losing, hardest at the moment they need the comeback
	# most — the opposite of "competitive but not punishing" (ADR-0013).
	var f := Fighter.new()
	f.charge = 1.0
	f.health.take_damage(f.health.maximum * 2.0)
	f.respawn()
	_runner.check(f.charge == 1.0, _fail("charge is still %.2f after respawn" % f.charge))


# ------------------------------------------------------------------ spending


func test_an_ability_costs_the_whole_bar_and_a_half_bar_buys_nothing() -> void:
	_case = "spending"
	var f := Fighter.new()

	f.charge = 0.99
	_runner.check(not f.ability_ready(), _fail("a nearly-full bar is not ready"))
	_runner.check(not f.spend_charge(), _fail("and spending it fails"))
	_runner.check(is_equal_approx(f.charge, 0.99), _fail("leaving the bar untouched"))

	f.charge = 1.0
	_runner.check(f.spend_charge(), _fail("a full bar spends"))
	_runner.check(f.charge == 0.0, _fail("and empties (%.2f)" % f.charge))
	_runner.check(not f.spend_charge(), _fail("and cannot be spent twice"))


func test_a_dead_fighter_cannot_use_an_ability() -> void:
	_case = "dead"
	var f := Fighter.new()
	f.charge = 1.0
	f.health.take_damage(f.health.maximum * 2.0)
	_runner.check(not f.ability_ready(), _fail("a corpse is not ready"))
	_runner.check(not f.spend_charge(), _fail("and cannot spend"))


# ---------------------------------------------------------------------- dash


func test_the_dash_moves_you_and_stops_at_stone() -> void:
	_case = "dash"
	var cls := _class_with_ability("dash")
	_runner.check(cls != null, _fail("some class carries a dash"))

	var w := _world()
	var f := w.player
	f.fighter_class = cls
	f.charge = 1.0

	# Somewhere with clear ground ahead, asked of the arena rather than assumed.
	var arena := w.arena
	var open := arena.open_centres()
	var from := open[open.size() / 2]
	f.position = from
	f.prev_position = from
	f.facing = Vector2.RIGHT

	var cmd := InputCommand.new()
	cmd.ability = true
	w.tick(cmd, DT)
	for _i in 20:
		w.tick(InputCommand.new(), DT)

	var travelled := f.position.distance_to(from)
	_runner.check(travelled > 10.0, _fail("the dash actually moved the cat (%.1f px)" % travelled))

	# And it is not a teleport through geometry. Every cell the cat passed
	# through has to be walkable — checked by asking the arena to resolve the
	# final position, which is where a dash into stone would have ended up.
	var resolved := arena.resolve_circle(f.position, f.radius)
	_runner.check(
		resolved.is_equal_approx(f.position),
		_fail("the cat did not end up inside a wall (%s vs %s)" % [f.position, resolved])
	)
	_restore()


func test_a_dash_cannot_cross_a_wall() -> void:
	_case = "dash into stone"
	var cls := _class_with_ability("dash")
	var w := _world()
	var f := w.player
	f.fighter_class = cls
	f.charge = 1.0

	# Find an open cell with stone directly to its right, and aim into it.
	var arena := w.arena
	var placed := false
	for y in arena.rows:
		for x in arena.cols:
			if arena.is_solid(x, y) or not arena.is_solid(x + 1, y):
				continue
			f.position = arena.cell_centre(x, y)
			f.prev_position = f.position
			f.facing = Vector2.RIGHT
			placed = true
			break
		if placed:
			break

	_runner.check(placed, _fail("the arena has an open cell with stone beside it"))
	if not placed:
		return

	var wall_x := f.position.x + arena.cell_size * 0.5
	var cmd := InputCommand.new()
	cmd.ability = true
	w.tick(cmd, DT)
	for _i in 30:
		w.tick(InputCommand.new(), DT)

	_runner.check(
		f.position.x < wall_x + f.radius,
		_fail("the dash stopped at the wall (x %.1f, wall %.1f)" % [f.position.x, wall_x])
	)


# ------------------------------------------------------------------ caltrops


func test_caltrops_hurt_an_enemy_standing_in_them() -> void:
	_case = "caltrops"
	var cls := _class_with_ability("caltrops")
	_runner.check(cls != null, _fail("some class carries caltrops"))

	var w := _world()
	var dropper := w.player
	dropper.fighter_class = cls
	dropper.charge = 1.0

	var victim := _enemy_of(w, dropper)
	var mate := _mate_of(w, dropper)

	var cmd := InputCommand.new()
	cmd.ability = true
	w.tick(cmd, DT)

	var armed := 0
	for h in w.hazards:
		if h.active:
			armed += 1
	_runner.check(armed == 1, _fail("exactly one patch was dropped (%d)" % armed))

	# Stand both an enemy and a teammate in it.
	victim.position = dropper.position
	victim.prev_position = victim.position
	if mate != null:
		mate.position = dropper.position
		mate.prev_position = mate.position

	var before := victim.health.current
	var mate_before := mate.health.current if mate != null else 0.0
	for _i in 30:
		w.tick(InputCommand.new(), DT)

	_runner.check(
		victim.health.current < before,
		_fail("the enemy was hurt (%.1f -> %.1f)" % [before, victim.health.current])
	)
	# The mirror. A hazard that hurts your own side is not an ability.
	#
	# ">= before", not "== before". A teammate standing in caltrops taking no
	# damage is also a teammate OUT of combat, so out-of-combat regen ticks and
	# its health goes UP — the first version of this asserted equality and failed
	# on 101 -> 132, which is the mechanic working, not the hazard leaking.
	if mate != null:
		_runner.check(
			mate.health.current >= mate_before,
			_fail("the teammate lost no health (%.1f -> %.1f)" % [mate_before, mate.health.current])
		)


func test_caltrops_expire() -> void:
	_case = "caltrops expiry"
	var cls := _class_with_ability("caltrops")
	_tune("caltrops_time", 0.5)

	var w := _world()
	var dropper := w.player
	dropper.fighter_class = cls
	dropper.charge = 1.0

	var cmd := InputCommand.new()
	cmd.ability = true
	w.tick(cmd, DT)

	for _i in 60:
		w.tick(InputCommand.new(), DT)

	for h in w.hazards:
		_runner.check(not h.active, _fail("every patch has expired"))
	_restore()


func test_the_pool_is_never_exceeded() -> void:
	_case = "hazard pool"
	# A hazard allocated per use would be the allocation churn ADR-0009 exists
	# about, and it lands during a fight. Asserted by dropping far more than the
	# pool holds and checking nothing was created.
	var cls := _class_with_ability("caltrops")
	var w := _world()
	var dropper := w.player
	dropper.fighter_class = cls

	var size := w.hazards.size()
	for _i in size * 3:
		dropper.charge = 1.0
		var cmd := InputCommand.new()
		cmd.ability = true
		w.tick(cmd, DT)

	_runner.check(
		w.hazards.size() == size,
		_fail("the pool is still %d entries (%d)" % [size, w.hazards.size()])
	)
