extends RefCounted
## Gun behaviour: one shot, a rate limit, a magazine, and swept collision.
##
## These are the parts of M1 that can be verified without a phone — which makes
## them the parts worth testing hard.

const DT := 1.0 / 60.0

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## A live world with every bot switched off, so only the player moves.
func _world() -> SimWorld:
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	for i in range(1, w.fighters.size()):
		w.fighters[i].controller = null
	return w


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


# --------------------------------------------------------- automatic fire


## Holding the thumb fires; letting go stops. That is the whole trigger.
##
## Firing stopped being an EVENT here and became a STATE — there is no
## shot_fired signal any more, and SimWorld reads `is_firing` off the controls
## once per simulation tick. So this asserts the state, not a count of emissions.
func test_holding_fires_and_releasing_stops() -> void:
	var controls := TouchControls.new()
	_runner.check(not controls.is_firing, _fail("a fresh gun is not firing"))

	controls._assign_finger(0, Vector2(900, 300))
	_runner.check(controls.is_firing, _fail("a thumb down means firing"))

	controls._release_finger(0)
	_runner.check(not controls.is_firing, _fail("and lifting it stops"))


## Firing is fed to the simulation as a plain flag, and the gun's cooldown is
## what turns a held trigger into a rate. Held down for a second, the gun must
## produce the rounds its interval allows and no more.
func test_a_held_trigger_produces_the_guns_rate_and_no_more() -> void:
	var w := _world()
	var cmd := InputCommand.new()
	cmd.aim = Vector2.RIGHT
	cmd.fire = true

	# An Array, not an int: a GDScript lambda captures by VALUE, so `shots += 1`
	# on a captured integer increments a copy and reports zero forever. This file
	# is the second place in the repo to hit it.
	var shots := []
	w.fired.connect(func(_p: Vector2, _d: Vector2) -> void: shots.append(1))
	for _i in 60:
		w.player.gun.magazine = w.player.gun.capacity()
		w.tick(cmd, DT)

	var allowed := int(1.0 / Tuning.get_value("fire_interval")) + 1
	_runner.check(shots.size() >= 1, _fail("holding the trigger fires at all"))
	_runner.check(
		shots.size() <= allowed,
		_fail("a second of holding fired %d rounds; the gun allows %d" % [shots.size(), allowed])
	)


## And the magazine still runs dry under a held trigger, rather than the hold
## bypassing ammunition entirely.
func test_a_held_trigger_still_runs_the_magazine_dry() -> void:
	var w := _world()
	var cmd := InputCommand.new()
	cmd.aim = Vector2.RIGHT
	cmd.fire = true

	var capacity := w.player.gun.capacity()
	var shots := []
	w.fired.connect(func(_p: Vector2, _d: Vector2) -> void: shots.append(1))

	var ticks := 60
	for _i in ticks:
		w.tick(cmd, DT)

	# The bound is DERIVED, and the reload is part of it: a magazine plus
	# whatever came back while the trigger was held. Writing `<= capacity` here
	# was wrong and the test caught it — over one second at a 0.55 s reload the
	# gun legitimately produces one round more than the magazine holds.
	var seconds := float(ticks) * DT
	var returned := int(seconds / Tuning.get_value("reload_time"))
	var allowed := capacity + returned + 1
	_runner.check(
		shots.size() <= allowed,
		(
			_fail("held fire spent %d rounds; a %d-round magazine plus %d reloaded allows %d")
			% [shots.size(), capacity, returned, allowed]
		)
	)
	# And far below an ungated trigger, which would fire on all 60 ticks.
	_runner.check(shots.size() < ticks / 2, _fail("ammunition still gates a held trigger"))


## A drag under the threshold is thumb noise and must not swing the aim; a drag
## over it must take it. One threshold, so there is no gap between "this counts
## as aiming" and "this counts as a shot" — there used to be two numbers here
## that disagreed by 14 px.
func test_only_a_real_drag_moves_the_aim() -> void:
	var threshold := Tuning.get_value("aim_min_drag")
	var lengths: Array[float] = [4.0, 10.0, 25.0, 27.0, 60.0, 200.0]

	for length in lengths:
		var controls := TouchControls.new()
		var origin := Vector2(900, 300)
		controls._assign_finger(0, origin)
		controls._aim_current = origin + Vector2(0, -length)
		controls._update_aim(DT)

		if length < threshold:
			_runner.check(
				controls.aim_vector == Vector2.ZERO,
				_fail("a %.0f px twitch leaves the aim alone" % length)
			)
			continue
		_runner.check(
			controls.aim_vector.distance_to(Vector2.UP) < 0.001,
			(
				_fail("a %.0f px drag points the aim where it was dragged, got %s")
				% [length, str(controls.aim_vector)]
			)
		)


# ------------------------------------------------- the aim outlives the shot


## THE COMPLAINT, AS AN ASSERTION.
##
## Releasing used to zero the aim, and Fighter.tick() falls through to the
## MOVEMENT direction when the aim is zero — so the cat swung to face wherever it
## was walking the instant you shot, and the gun barrel swung with it.
func test_the_aim_survives_the_shot_and_walking_does_not_move_it() -> void:
	var w := _world()
	var cmd := InputCommand.new()

	cmd.aim = Vector2.LEFT
	cmd.fire = true
	w.tick(cmd, DT)
	_runner.check(
		w.player.facing.distance_to(Vector2.LEFT) < 0.01,
		_fail("firing points the cat where it fired, got %s" % str(w.player.facing))
	)

	cmd.clear()
	cmd.move = Vector2.RIGHT
	for _i in 60:
		w.tick(cmd, DT)

	_runner.check(
		w.player.facing.distance_to(Vector2.LEFT) < 0.01,
		_fail("a second of walking right leaves facing at %s" % str(w.player.facing))
	)


## The line of fire stays on screen after the shot.
##
## Half of "keep a line-of-fire" is the cat still pointing that way; the other
## half is being able to SEE it. The preview used to return early unless a thumb
## was down, so the moment you released there was nothing on screen telling you
## where the next shot would go.
##
## Asserted through GameView.aim_line_strength() rather than a rendered frame:
## no render mode has a thumb on the screen, so a capture cannot distinguish
## "drawn dim" from "not drawn at all".
func test_the_line_of_fire_stays_on_screen_after_the_shot() -> void:
	_runner.check(
		is_equal_approx(GameView.aim_line_strength(true), 1.0),
		_fail("pointing draws the line at full strength")
	)

	var idle := GameView.aim_line_strength(false)
	_runner.check(idle > 0.0, _fail("and it is still drawn with the thumb up, got %.2f" % idle))
	_runner.check(idle < 1.0, _fail("but dimmer than while pointing, got %.2f" % idle))

	# The off switch still switches it off, in both states.
	var was := Tuning.get_value("reticle_enabled")
	Tuning.set_value("reticle_enabled", 0.0)
	_runner.check(
		GameView.aim_line_strength(true) == 0.0 and GameView.aim_line_strength(false) == 0.0,
		_fail("reticle_enabled 0 draws nothing either way")
	)
	Tuning.set_value("reticle_enabled", was)


## The ammo row must never outgrow the cat, at any magazine size.
##
## Pips were a flat 9 px each, so the ROW grew with the magazine: 57 px at five
## rounds against a 58 px cat, and 117 px at ten — a bar twice as wide as the
## animal it belongs to. Pips shrink now instead. magazine_size is a slider that
## goes to 12, so this is checked across the whole range rather than at the one
## value that happens to ship.
func test_the_ammo_row_never_outgrows_the_cat() -> void:
	var radius := Tuning.get_value("fighter_radius")
	var gap := 3.0
	var limit := radius * GameView.MAGAZINE_ROW_SPAN

	for capacity in range(1, 13):
		var w := GameView.magazine_pip_width(capacity, radius, gap)
		var total := float(capacity) * w + float(capacity - 1) * gap
		_runner.check(
			total <= limit + 0.01,
			_fail("%d rounds span %.0f px, limit is %.0f" % [capacity, total, limit])
		)
		_runner.check(w > 0.0, _fail("%d rounds still have a visible pip" % capacity))

	# And a small magazine keeps the original chunky pip rather than stretching
	# to fill the row — the fix is a cap, not a rescale.
	_runner.check(
		is_equal_approx(GameView.magazine_pip_width(5, radius, gap), 9.0),
		_fail("five rounds keep the 9 px pip they always had")
	)
