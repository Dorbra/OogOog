extends RefCounted
## Classes: what makes one cat shoot differently from another.
##
## A class is a set of MULTIPLIERS over the global tuning keys rather than a
## stat block of its own (ADR-0028), which means every assertion here is really
## about the same question: does the multiplier reach the thing it multiplies,
## and does it stay reached? Most of the ways this breaks are silent — a gun
## rebuilt without its class, a fan that spends three rounds instead of one —
## and silent is what this file is for.

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


## The class with the most pellets — the one whose fan is worth testing.
func _spread_class() -> FighterClass:
	var best: FighterClass = null
	for class_id in FighterClass.all():
		var cls := FighterClass.get_class_by_id(class_id)
		if best == null or cls.pellets > best.pellets:
			best = cls
	return best


# --------------------------------------------------------------- definitions


func test_the_class_table_loads_and_is_not_all_the_same_gun() -> void:
	_case = "definitions"
	_runner.check(FighterClass.count() >= 2, _fail("at least two classes are defined"))

	# A table that parsed but left every multiplier at 1.0 would give two classes
	# that are the same gun with different names, and every other test here would
	# still pass. This is the assertion that says they actually differ.
	var differs := false
	for class_id in FighterClass.all():
		var cls := FighterClass.get_class_by_id(class_id)
		if cls.pellets != 1 or not is_equal_approx(cls.damage_mult, 1.0):
			differs = true
	_runner.check(differs, _fail("the classes are not all identical to the baseline"))


func test_an_unknown_class_falls_back_instead_of_crashing() -> void:
	_case = "unknown class"
	# A stale player_class saved on a device, or a typo in the JSON. On a phone
	# with no console a null here is an unexplained crash on launch, which is the
	# failure mode this project keeps designing against.
	var cls := FighterClass.get_class_by_id("no_such_class")
	_runner.check(cls != null, _fail("an unknown id still returns a class"))
	_runner.check(cls.id == FighterClass.all()[0], _fail("and it is the first one"))


func test_the_picker_slider_covers_exactly_the_classes_that_exist() -> void:
	_case = "player_class range"
	# The lobber lands next PR. If its max is not raised with it, the picker
	# silently cannot select it and the class ships unreachable.
	_runner.check(
		is_equal_approx(Tuning.get_max("player_class"), float(FighterClass.count() - 1)),
		_fail(
			(
				"player_class max is %.0f for %d classes"
				% [Tuning.get_max("player_class"), FighterClass.count()]
			)
		)
	)


# ---------------------------------------------------------- the gun and the class


func test_the_gun_cannot_drift_away_from_the_class() -> void:
	_case = "class setter"
	var f := Fighter.new()
	for class_id in FighterClass.all():
		var cls := FighterClass.get_class_by_id(class_id)
		f.fighter_class = cls
		_runner.check(
			f.gun.fighter_class == cls,
			_fail("setting the class to %s rebuilt the gun with it" % class_id)
		)


func test_respawning_keeps_your_class() -> void:
	_case = "respawn"
	# THE BUG THIS FILE WAS OPENED FOR. respawn() used to do a bare Gun.new(),
	# which takes the default class — so a Skirmisher fought the first three
	# seconds of a match with its own gun and the rest of the round with a
	# Ranger's, and nothing on screen said so.
	var spread := _spread_class()
	var f := Fighter.new()
	f.fighter_class = spread

	var before := f.gun.damage()
	f.health.take_damage(f.health.maximum * 2.0)
	f.respawn()

	_runner.check(
		f.gun.fighter_class == spread, _fail("the gun is still a %s's after respawn" % spread.id)
	)
	_runner.check(
		is_equal_approx(f.gun.damage(), before),
		_fail("damage %.1f survived respawn (was %.1f)" % [f.gun.damage(), before])
	)


func test_a_multiplier_actually_multiplies() -> void:
	_case = "multipliers"
	var base := Gun.new(FighterClass.at(0))
	var spread := Gun.new(_spread_class())
	# Asserted against the base gun rather than against a literal: the numbers
	# are set by measurement and will move, the relationship will not.
	_runner.check(
		spread.damage() < base.damage(),
		_fail("a %s pellet hurts less than a single round" % _spread_class().id)
	)
	_runner.check(spread.reach() < base.reach(), _fail("and it does not shoot as far"))

	# The one that is easy to get wrong: lifetime is derived from reach, so a
	# class that is FASTER and SHORTER-ranged must end up with a shorter life,
	# not a longer one.
	_runner.check(
		spread.lifetime() < base.lifetime(),
		_fail(
			(
				"a shorter, faster gun has a shorter flight (%.3f vs %.3f)"
				% [spread.lifetime(), base.lifetime()]
			)
		)
	)


# ------------------------------------------------------------------- the fan


func test_the_fan_is_centred_and_symmetric() -> void:
	_case = "fan geometry"
	var cls := _spread_class()
	_runner.check(cls.pellets >= 3, _fail("the spread class fires at least three pellets"))

	var first := cls.pellet_angle(0)
	var last := cls.pellet_angle(cls.pellets - 1)
	_runner.check(
		is_equal_approx(first, -last),
		_fail("the fan is symmetric about the aim (%.3f, %.3f)" % [first, last])
	)
	_runner.check(
		is_equal_approx(rad_to_deg(last - first), cls.spread_deg),
		_fail("and spans exactly %.1f degrees" % cls.spread_deg)
	)
	# A single-pellet class must not be quietly given an offset.
	_runner.check(
		is_equal_approx(FighterClass.at(0).pellet_angle(0), 0.0),
		_fail("a one-pellet gun fires dead straight")
	)


func test_the_fan_is_deterministic() -> void:
	_case = "fan determinism"
	# Random spread on a fast flat bullet is exactly the "cant be expected" that
	# got the bow deleted (ADR-0022). Two identical shots must produce identical
	# directions, and no RNG anywhere may touch them.
	var w := _world()
	w.player.fighter_class = _spread_class()

	var first := _fire_and_collect(w)
	var second := _fire_and_collect(w)

	_runner.check(first.size() >= 3, _fail("the shot produced a fan (%d bullets)" % first.size()))
	_runner.check(first.size() == second.size(), _fail("both shots fired the same count"))
	for i in first.size():
		_runner.check(
			first[i].is_equal_approx(second[i]),
			_fail("pellet %d went the same way twice (%s vs %s)" % [i, first[i], second[i]])
		)


func test_a_whole_fan_costs_one_round() -> void:
	_case = "magazine"
	# Spending a round per pellet would empty a three-pellet magazine three times
	# too fast, which reads as "this class is terrible" rather than as a bug.
	var w := _world()
	w.player.fighter_class = _spread_class()
	var before := w.player.gun.magazine
	_runner.check(before >= 1, _fail("the gun starts loaded"))

	var cmd := InputCommand.new()
	cmd.fire = true
	cmd.aim = Vector2.RIGHT
	w.tick(cmd, DT)

	_runner.check(
		w.player.gun.magazine == before - 1,
		_fail("one round spent, not %d" % (before - w.player.gun.magazine))
	)


func test_the_spread_connects_close_and_opens_up_far() -> void:
	_case = "spread"
	# The whole bargain of a shotgun, asserted in BOTH directions. "It hits close"
	# alone would pass on a gun with no spread at all, and "it misses far" alone
	# would pass on a gun that never hits anything.
	var cls := _spread_class()
	var gun := Gun.new(cls)
	var radius := Tuning.get_value("fighter_radius")

	var near := gun.reach() * 0.12
	var far := gun.reach()
	var near_hits := _pellets_on_target(cls, near, radius)
	var far_hits := _pellets_on_target(cls, far, radius)

	_runner.check(
		near_hits == cls.pellets,
		_fail("all %d pellets land at point blank (%d did)" % [cls.pellets, near_hits])
	)
	_runner.check(
		far_hits < cls.pellets,
		_fail("and the fan has opened past the target at full range (%d still land)" % far_hits)
	)


## Fires one shot from the player and returns the directions that went out.
func _fire_and_collect(w: SimWorld) -> Array[Vector2]:
	for b in w.bullets:
		b.deactivate()
	# A FRESH gun, not just a refilled magazine. consume() leaves a cooldown
	# behind, so the second shot in this test fired nothing at all and the
	# comparison was between a fan and an empty array.
	w.player.gun = Gun.new(w.player.fighter_class)

	var cmd := InputCommand.new()
	cmd.fire = true
	cmd.aim = Vector2.RIGHT
	w.tick(cmd, DT)

	var out: Array[Vector2] = []
	for b in w.bullets:
		if b.active:
			out.append(b.velocity.normalized())
	return out


## How many pellets of `cls` would strike a target of `radius` at `distance`,
## measured off the fan geometry rather than by firing — the flight is straight,
## so the answer is the perpendicular offset at that range.
func _pellets_on_target(cls: FighterClass, distance: float, radius: float) -> int:
	var hits := 0
	for i in cls.pellets:
		if absf(sin(cls.pellet_angle(i)) * distance) <= radius:
			hits += 1
	return hits


# ----------------------------------------------------------------- the roster


func test_both_teams_get_the_same_classes() -> void:
	_case = "mirrored teams"
	# No match may be decided by the draw. The players are 5 and 10, and losing
	# to a match-up you did not choose and cannot see is how a session ends.
	_tune("bot_team_size", 3.0)
	var w := SimWorld.new()

	var team_a: Array[String] = []
	var team_b: Array[String] = []
	for f in w.fighters:
		if f.team == 0:
			team_a.append(f.fighter_class.id)
		else:
			team_b.append(f.fighter_class.id)

	_runner.check(team_a.size() == 3 and team_b.size() == 3, _fail("both sides fielded three"))
	_runner.check(team_a == team_b, _fail("the sides mirror: %s vs %s" % [team_a, team_b]))
	_restore()


func test_the_picker_decides_what_the_player_fights_as() -> void:
	_case = "player_class"
	for index in FighterClass.count():
		_tune("player_class", float(index))
		var w := SimWorld.new()
		_runner.check(
			w.player.fighter_class.id == FighterClass.at(index).id,
			_fail("picking %d gave the player a %s" % [index, w.player.fighter_class.id])
		)
	_restore()
