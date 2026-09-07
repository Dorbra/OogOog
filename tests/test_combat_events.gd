extends RefCounted
## Sim events, damage funnelling, health and regen.
##
## These are the contract the entire feedback layer depends on: if a hit does
## not emit, or emits twice, or reports the wrong damage, every effect hanging
## off it is wrong too — and none of that is visible without a phone.

var _runner: Object
var _case: String

# GDScript lambdas capture locals BY VALUE, so `count += 1` inside a signal
# handler never reaches the outer variable. Accumulate into Arrays and
# Dictionaries, which are reference types and do mutate through the capture.
# This bit these tests before it could bite production code.


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _world() -> SimWorld:
	return SimWorld.new(Rect2(0, 0, 2400, 1350))


func test_hit_emits_once_with_applied_damage() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]

	var events: Array = []
	w.hit.connect(func(p, d, dmg, full): events.append({"p": p, "d": d, "dmg": dmg, "full": full}))

	w.apply_damage(target, 30.0, Vector2.RIGHT, false)

	_runner.check(events.size() == 1, _fail("exactly one hit event"))
	_runner.check_near(events[0]["dmg"], 30.0, _fail("reports damage dealt"))
	_runner.check(not events[0]["full"], _fail("full_draw flag passed through"))


func test_overkill_reports_only_damage_actually_applied() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]
	target.health.current = 12.0

	var reported: Array = []
	w.hit.connect(func(_p, _d, dmg, _f): reported.append(dmg))
	w.apply_damage(target, 999.0, Vector2.RIGHT, true)

	# A 999 damage number over a 12 HP cat would be a lie the player can see.
	_runner.check(reported.size() == 1, _fail("hit emitted for the fatal blow"))
	if reported.size() == 1:
		_runner.check_near(reported[0], 12.0, _fail("damage clamped to remaining health"))


func test_kill_emits_once_and_not_again_while_dead() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]
	target.health.current = 5.0

	var kills: Array = []
	w.killed.connect(func(_p, _d): kills.append(true))

	w.apply_damage(target, 50.0, Vector2.RIGHT, false)
	_runner.check(kills.size() == 1, _fail("kill emits on the fatal blow"))

	# Hitting a corpse must not re-trigger the kill effects.
	w.apply_damage(target, 50.0, Vector2.RIGHT, false)
	_runner.check(kills.size() == 1, _fail("no second kill event on a dead target"))


func test_damage_on_dead_target_emits_nothing() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]
	target.health.current = 0.0

	var hits: Array = []
	w.hit.connect(func(_p, _d, _dmg, _f): hits.append(true))
	w.apply_damage(target, 20.0, Vector2.RIGHT, false)
	_runner.check(hits.is_empty(), _fail("no hit event for zero applied damage"))


func test_hit_applies_knockback_along_the_arrow() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]
	target.velocity = Vector2.ZERO

	w.apply_damage(target, 10.0, Vector2.RIGHT, false)
	_runner.check(target.velocity.x > 0.0, _fail("knocked along the shot direction"))
	_runner.check_near(target.velocity.y, 0.0, _fail("no sideways knockback"))


func test_knockback_decays_to_rest() -> void:
	var w := _world()
	var target: Dummy = w.dummies[0]
	w.apply_damage(target, 10.0, Vector2.RIGHT, false)

	for _i in 300:
		target.tick(1.0 / 60.0)
	_runner.check_near(target.velocity.length(), 0.0, _fail("knockback comes to rest"))


func test_regen_waits_then_heals_to_full() -> void:
	var h := Health.new(100.0)
	h.take_damage(60.0)
	_runner.check_near(h.current, 40.0, _fail("damage applied"))

	# Inside the out-of-combat delay: nothing should come back.
	h.tick(Tuning.get_value("regen_delay") * 0.5)
	_runner.check_near(h.current, 40.0, _fail("no regen during the delay"))

	for _i in 600:
		h.tick(1.0 / 60.0)
	_runner.check_near(h.current, h.maximum, _fail("regenerates to full once clear"))


func test_taking_damage_restarts_the_regen_delay() -> void:
	var h := Health.new(100.0)
	h.take_damage(50.0)
	h.tick(Tuning.get_value("regen_delay") * 0.9)
	h.take_damage(10.0)
	var after := h.current

	# The gate is time-since-damage, so a fresh hit must push regen back out
	# rather than letting the earlier wait carry over.
	h.tick(Tuning.get_value("regen_delay") * 0.5)
	_runner.check_near(h.current, after, _fail("second hit restarts the delay"))


func test_dead_target_does_not_regenerate() -> void:
	var h := Health.new(100.0)
	h.take_damage(100.0)
	for _i in 600:
		h.tick(1.0 / 60.0)
	_runner.check(not h.alive(), _fail("a dead target stays dead"))
	_runner.check_near(h.current, 0.0, _fail("no passive resurrection"))
