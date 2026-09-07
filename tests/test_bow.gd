extends RefCounted
## Bow curves, quiver economy, and swept arrow collision.
##
## These are the parts of M1 that can be verified without a phone — which makes
## them the parts worth testing hard.

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func test_draw_curves_scale_between_min_and_max() -> void:
	var bow := Bow.new()

	_runner.check_near(
		bow.speed_for(0.0), Tuning.get_value("draw_min_speed"), _fail("zero draw = min speed")
	)
	_runner.check_near(
		bow.speed_for(1.0), Tuning.get_value("draw_max_speed"), _fail("full draw = max speed")
	)
	_runner.check_near(
		bow.damage_for(0.0, false),
		Tuning.get_value("draw_min_damage"),
		_fail("zero draw = min dmg")
	)
	_runner.check_near(
		bow.damage_for(1.0, false),
		Tuning.get_value("draw_max_damage"),
		_fail("full draw = max dmg")
	)

	# Monotonic: a longer draw must never be worse than a shorter one.
	_runner.check(bow.speed_for(0.5) > bow.speed_for(0.1), _fail("speed increases with draw"))
	_runner.check(
		bow.damage_for(0.5, false) > bow.damage_for(0.1, false), _fail("dmg rises w/ draw")
	)


func test_draw_strength_is_clamped() -> void:
	var bow := Bow.new()
	# Out-of-range input must not extrapolate into absurd speeds.
	_runner.check_near(bow.speed_for(5.0), bow.speed_for(1.0), _fail("draw > 1 clamps"))
	_runner.check_near(bow.speed_for(-3.0), bow.speed_for(0.0), _fail("draw < 0 clamps"))


func test_full_draw_is_dead_straight() -> void:
	var bow := Bow.new()
	_runner.check_near(bow.deviation_for(1.0), 0.0, _fail("full draw has no deviation"))
	_runner.check(bow.deviation_for(0.0) > 0.0, _fail("rushed shot deviates"))
	_runner.check(
		bow.deviation_for(0.2) > bow.deviation_for(0.8), _fail("deviation shrinks as draw grows")
	)


## The snap multiplier is APPLIED, whatever it is set to — that is the invariant.
##
## It used to also assert the snap shot was weaker. That assertion encoded a
## design decision rather than a property of the code, and the decision changed:
## the audience is now a 5-year-old, auto-aim is the mechanic that makes the
## game playable for them, and taxing it punished the one thing they can do.
## Brawl Stars charges nothing for tap-to-auto-aim either. The multiplier stays
## as a slider so the trade can be re-introduced by turning a dial rather than
## by editing a test.
func test_snap_multiplier_is_applied() -> void:
	var bow := Bow.new()
	var normal := bow.damage_for(0.5, false)
	var snap := bow.damage_for(0.5, true)
	_runner.check_near(
		snap, normal * Tuning.get_value("snap_damage_mult"), _fail("snap multiplier applied")
	)
	_runner.check(snap <= normal, _fail("snap is never STRONGER than an aimed shot"))


func test_quiver_depletes_and_blocks() -> void:
	var bow := Bow.new()
	var cap := bow.capacity()
	_runner.check(bow.quiver == cap, _fail("starts full"))

	for i in cap:
		_runner.check(bow.consume(), _fail("consume %d succeeds" % i))

	_runner.check(not bow.can_fire(), _fail("empty quiver cannot fire"))
	_runner.check(not bow.consume(), _fail("consume on empty returns false"))
	_runner.check(bow.quiver == 0, _fail("quiver never goes negative"))


func test_quiver_refills_over_time() -> void:
	var bow := Bow.new()
	var refill := Tuning.get_value("quiver_refill_time")
	bow.consume()
	bow.consume()
	var after_use := bow.quiver

	# Just short of one refill period: nothing yet.
	bow.tick(refill * 0.9)
	_runner.check(bow.quiver == after_use, _fail("no arrow before the refill period elapses"))

	bow.tick(refill * 0.2)
	_runner.check(bow.quiver == after_use + 1, _fail("one arrow after the period elapses"))


func test_quiver_does_not_bank_progress_while_full() -> void:
	var bow := Bow.new()
	var refill := Tuning.get_value("quiver_refill_time")

	# Sit at full for a long time, then fire. The next arrow must take a full
	# period — otherwise idling grants a free instant reload.
	bow.tick(refill * 10.0)
	bow.consume()
	bow.tick(refill * 0.5)
	_runner.check(bow.quiver == bow.capacity() - 1, _fail("time at full capacity is not banked"))


func test_quiver_never_exceeds_capacity() -> void:
	var bow := Bow.new()
	bow.consume()
	bow.tick(Tuning.get_value("quiver_refill_time") * 50.0)
	_runner.check(bow.quiver == bow.capacity(), _fail("refill stops at capacity"))


func test_arrow_swept_collision_catches_fast_shots() -> void:
	var arrow := Arrow.new()
	# A fast arrow that jumps clean past a target between ticks. Testing only
	# the end point would miss this, and shots would silently pass through.
	arrow.prev_position = Vector2(0, 0)
	arrow.position = Vector2(400, 0)

	_runner.check(arrow.hits_circle(Vector2(200, 0), 20.0), _fail("swept test catches tunnelling"))
	_runner.check(
		not arrow.hits_circle(Vector2(200, 300), 20.0), _fail("misses target far off the path")
	)
	_runner.check(
		not arrow.hits_circle(Vector2(-100, 0), 20.0), _fail("does not hit behind the start")
	)
	_runner.check(
		not arrow.hits_circle(Vector2(600, 0), 20.0), _fail("does not hit beyond the end")
	)


func test_arrow_expires() -> void:
	var arrow := Arrow.new()
	var bounds := Rect2(0, 0, 2000, 2000)
	arrow.launch(Vector2(100, 100), Vector2.RIGHT, 100.0, 10.0, 0.5)
	_runner.check(arrow.active, _fail("active after launch"))

	arrow.tick(0.4, bounds)
	_runner.check(arrow.active, _fail("still alive before lifetime"))

	arrow.tick(0.2, bounds)
	_runner.check(not arrow.active, _fail("expires after lifetime"))


func test_arrow_deactivates_outside_bounds() -> void:
	var arrow := Arrow.new()
	var bounds := Rect2(0, 0, 500, 500)
	arrow.launch(Vector2(490, 250), Vector2.RIGHT, 1000.0, 10.0, 5.0)
	arrow.tick(0.1, bounds)
	_runner.check(not arrow.active, _fail("deactivates when it leaves the arena"))
