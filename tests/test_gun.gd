extends RefCounted
## Gun behaviour: one shot, a rate limit, a magazine, and swept collision.
##
## These are the parts of M1 that can be verified without a phone — which makes
## them the parts worth testing hard.

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## Every shot is identical, and that is the property worth pinning.
##
## A draw-strength curve used to live here: hold time drove speed, damage and
## deviation together, and four tests covered its shape. The charge turned out to
## BE the sluggishness the game was reported for, so the curve is gone rather
## than turned down — and what replaces it is the assertion that nothing varies
## between one shot and the next.
func test_every_shot_is_the_same_shot() -> void:
	var gun := Gun.new()
	_runner.check(gun.speed() == Tuning.get_value("bullet_speed"), _fail("one bullet speed"))
	_runner.check(gun.damage() == Tuning.get_value("bullet_damage"), _fail("one damage value"))
	_runner.check(
		is_equal_approx(gun.reach(), gun.speed() * Tuning.get_value("bullet_lifetime")),
		_fail("reach is speed x lifetime, with nothing else in it")
	)


## The rate limit lives in the gun, so the player and the bots are gated by the
## same code. Firing twice in one instant is the thing tap-to-fire would
## otherwise allow: an empty magazine in five frames.
func test_the_gun_will_not_fire_faster_than_its_interval() -> void:
	var gun := Gun.new()
	var interval := Tuning.get_value("fire_interval")

	_runner.check(gun.consume(), _fail("the first shot fires"))
	_runner.check(not gun.can_fire(), _fail("and the gun is immediately on cooldown"))
	_runner.check(not gun.consume(), _fail("a second shot in the same instant is refused"))

	gun.tick(interval * 0.9)
	_runner.check(not gun.can_fire(), _fail("still refused just short of the interval"))

	gun.tick(interval * 0.2)
	_runner.check(gun.can_fire(), _fail("and allowed once the interval has passed"))


## A refused shot must cost nothing. If the cooldown consumed a round anyway, a
## fast tapper would empty the magazine without a single bullet leaving.
func test_a_refused_shot_costs_no_ammunition() -> void:
	var gun := Gun.new()
	gun.consume()
	var left := gun.magazine
	for _i in 10:
		gun.consume()
	_runner.check(gun.magazine == left, _fail("ten refused taps spend nothing"))


func test_magazine_depletes_and_blocks() -> void:
	var gun := Gun.new()
	var cap := gun.capacity()
	_runner.check(gun.magazine == cap, _fail("starts full"))
	_runner.check(gun.consume(), _fail("a full gun fires"))
	_runner.check(gun.magazine == cap - 1, _fail("and that costs exactly one round"))

	# The empty state is set directly rather than reached by firing the magazine
	# dry. Draining it would mean ticking the cooldown between shots, and ticking
	# also runs the reload — five shots at a 0.35 s interval is 1.75 s against a
	# 1.1 s reload, so the loop would hand rounds back and this would quietly
	# become a test of the reload instead of the block.
	gun.magazine = 0
	gun.tick(Tuning.get_value("fire_interval"))
	_runner.check(not gun.can_fire(), _fail("an empty magazine cannot fire"))
	_runner.check(not gun.consume(), _fail("consume on empty returns false"))
	_runner.check(gun.magazine == 0, _fail("the magazine never goes negative"))


func test_magazine_refills_over_time() -> void:
	var gun := Gun.new()
	var refill := Tuning.get_value("reload_time")
	gun.consume()
	gun.tick(Tuning.get_value("fire_interval"))
	gun.consume()
	var after_use := gun.magazine

	# Just short of one reload period from here: nothing yet. The fire_interval
	# already ticked above is deliberately small against reload_time, and the
	# 0.9/0.2 split leaves room for it.
	gun.tick(refill * 0.9 - Tuning.get_value("fire_interval"))
	_runner.check(gun.magazine == after_use, _fail("no round before the reload period elapses"))

	gun.tick(refill * 0.2)
	_runner.check(gun.magazine == after_use + 1, _fail("one round after the period elapses"))


func test_magazine_does_not_bank_progress_while_full() -> void:
	var gun := Gun.new()
	var refill := Tuning.get_value("reload_time")

	# Sit at full for a long time, then fire. The next round must take a full
	# period — otherwise idling grants a free instant reload.
	gun.tick(refill * 10.0)
	gun.consume()
	gun.tick(refill * 0.5)
	_runner.check(gun.magazine == gun.capacity() - 1, _fail("time at full capacity is not banked"))


func test_magazine_never_exceeds_capacity() -> void:
	var gun := Gun.new()
	gun.consume()
	gun.tick(Tuning.get_value("reload_time") * 50.0)
	_runner.check(gun.magazine == gun.capacity(), _fail("refill stops at capacity"))


func test_bullet_swept_collision_catches_fast_shots() -> void:
	var bullet := Bullet.new()
	# A fast bullet that jumps clean past a target between ticks. Testing only
	# the end point would miss this, and shots would silently pass through.
	bullet.prev_position = Vector2(0, 0)
	bullet.position = Vector2(400, 0)

	_runner.check(bullet.hits_circle(Vector2(200, 0), 20.0), _fail("swept test catches tunnelling"))
	_runner.check(
		not bullet.hits_circle(Vector2(200, 300), 20.0), _fail("misses target far off the path")
	)
	_runner.check(
		not bullet.hits_circle(Vector2(-100, 0), 20.0), _fail("does not hit behind the start")
	)
	_runner.check(
		not bullet.hits_circle(Vector2(600, 0), 20.0), _fail("does not hit beyond the end")
	)


func test_bullet_expires() -> void:
	var bullet := Bullet.new()
	var bounds := Rect2(0, 0, 2000, 2000)
	bullet.launch(Vector2(100, 100), Vector2.RIGHT, 100.0, 10.0, 0.5)
	_runner.check(bullet.active, _fail("active after launch"))

	bullet.tick(0.4, bounds)
	_runner.check(bullet.active, _fail("still alive before lifetime"))

	bullet.tick(0.2, bounds)
	_runner.check(not bullet.active, _fail("expires after lifetime"))


func test_bullet_deactivates_outside_bounds() -> void:
	var bullet := Bullet.new()
	var bounds := Rect2(0, 0, 500, 500)
	bullet.launch(Vector2(490, 250), Vector2.RIGHT, 1000.0, 10.0, 5.0)
	bullet.tick(0.1, bounds)
	_runner.check(not bullet.active, _fail("deactivates when it leaves the arena"))


# ------------------------------------------------------------- tap to fire


## A press alone fires nothing; the RELEASE is the shot.
##
## The whole complaint that produced this weapon was a 450 ms hold in front of
## every shot. What replaced it has to be checked for the opposite failure —
## firing on touch-down would mean a shot leaves before you have aimed it, which
## is a different way of taking the aim out of the player's hands.
func test_a_press_fires_nothing_and_the_release_fires_once() -> void:
	var controls := TouchControls.new()
	var shots: Array = []
	controls.shot_fired.connect(func(aim: Vector2, snap: bool): shots.append([aim, snap]))

	controls._assign_finger(0, Vector2(900, 300))
	_runner.check(shots.is_empty(), _fail("touching down fires nothing"))

	controls._release_finger(0)
	_runner.check(shots.size() == 1, _fail("releasing fires exactly one shot"))


## A release that barely moved is a tap: no direction of its own, auto-aimed by
## the caller. That is the five-year-old's shot and it must not need a drag.
func test_a_bare_tap_is_flagged_for_auto_aim() -> void:
	var controls := TouchControls.new()
	var shots: Array = []
	controls.shot_fired.connect(func(aim: Vector2, snap: bool): shots.append([aim, snap]))

	controls._assign_finger(0, Vector2(900, 300))
	controls._aim_current = Vector2(903, 302)
	controls._release_finger(0)

	_runner.check(shots.size() == 1, _fail("the tap fired"))
	_runner.check(shots[0][1], _fail("and is flagged as a tap"))
	_runner.check(shots[0][0] == Vector2.ZERO, _fail("carrying no direction of its own"))


## Drag far enough and the shot goes where you dragged, untouched.
func test_a_dragged_release_goes_where_it_was_dragged() -> void:
	var controls := TouchControls.new()
	var shots: Array = []
	controls.shot_fired.connect(func(aim: Vector2, snap: bool): shots.append([aim, snap]))

	var origin := Vector2(900, 300)
	controls._assign_finger(0, origin)
	controls._aim_current = origin + Vector2(0, -200)
	controls._release_finger(0)

	_runner.check(shots.size() == 1, _fail("the dragged release fired"))
	_runner.check(not shots[0][1], _fail("and is NOT a tap"))
	_runner.check(
		(shots[0][0] as Vector2).distance_to(Vector2.UP) < 0.001,
		_fail("pointing where it was dragged, got %s" % str(shots[0][0]))
	)


## Classified on drag alone, however long the thumb rested.
##
## A hold threshold used to be half of this decision: a careful player lining up
## a shot had it silently reclassified as a tap once they took too long, so the
## game auto-aimed a shot they were in the middle of aiming themselves.
func test_a_long_careful_drag_is_still_an_aimed_shot() -> void:
	var controls := TouchControls.new()
	var shots: Array = []
	controls.shot_fired.connect(func(aim: Vector2, snap: bool): shots.append([aim, snap]))

	var origin := Vector2(900, 300)
	controls._assign_finger(0, origin)
	controls._aim_current = origin + Vector2(0, -200)
	# Ten seconds of deliberation, which the old classifier would have called a
	# tap the moment it passed snap_max_hold.
	for _i in 600:
		controls._update_aim(1.0 / 60.0)
	controls._release_finger(0)

	_runner.check(shots.size() == 1, _fail("it still fires on release"))
	_runner.check(not shots[0][1], _fail("and is still an aimed shot, not a tap"))
