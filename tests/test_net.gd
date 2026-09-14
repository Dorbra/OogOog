extends RefCounted
## The network, minus the network.
##
## Everything in `feat/lan` that can be wrong without a second phone is in here:
## the wire format, the staleness rule, the replica step, and the roster. The
## socket is the loopback gate's job (tests/test_net_loopback.sh); this file is
## the part that catches the bugs, because the bugs in this layer are not
## connection failures. They are silent.
##
## A connection failure is loud — nothing happens and you can see nothing
## happening. A serialiser that quietly stops sending one field is not: the
## receiver keeps whatever it had, so a cat's ammo freezes at full or a score
## stops climbing, and on a phone with no debugger that reads as a gameplay bug
## in whichever system owns the frozen number. That is why the round-trip below
## is asserted field by field rather than as "it came back".

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


## A live world with nobody driving, so nothing moves except what a test moves.
func _world() -> SimWorld:
	var w := SimWorld.new()
	for f in w.fighters:
		f.controller = null
	w.match_state.phase = MatchState.Phase.LIVE
	return w


# ------------------------------------------------------------- the wire format


## Every field, one at a time.
##
## Deliberately NOT "the arrays are equal". A whole-payload comparison passes on
## a world where both sides are zero, and the failure it would report — "the
## snapshot differs" — names nothing. Each check below names the field, because
## the field is the bug.
func test_a_snapshot_round_trips_every_field() -> void:
	_case = "round trip"
	var src := _world()
	var dst := _world()

	# Move the source world somewhere the destination could not have guessed.
	# Identical starting states would let a codec that transmits NOTHING pass.
	for i in src.fighters.size():
		var f: Fighter = src.fighters[i]
		f.position = Vector2(100.0 + i * 37.0, 200.0 + i * 19.0)
		f.facing = Vector2(0.6, -0.8)
		f.health.current = 123.0 + i
		f.charge = 0.25 * float(i)
		f.reveal_timer = 0.5
		f.gun.magazine = 1
		f.fighter_class = FighterClass.at(i % FighterClass.count())
		# Re-set after the class setter, which rebuilds the gun at full.
		f.gun.magazine = 1

	var bullet: Bullet = src._free_bullet()
	bullet.launch(Vector2(50.0, 60.0), Vector2.RIGHT, 900.0, 12.0, 0.4, 1, 0, true, 77.0)

	var hazard: Hazard = src._free_hazard()
	hazard.arm(Vector2(300.0, 310.0), 90.0, 44.0, 3.0, 1, 0)

	src.match_state.scores[0] = 7
	src.match_state.scores[1] = 4
	src.match_state.elapsed = 61.5
	src.match_state.winner = 1

	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the snapshot is accepted"))

	for i in src.fighters.size():
		var a: Fighter = src.fighters[i]
		var b: Fighter = dst.fighters[i]
		# net_target, not position: applying a snapshot sets where a fighter is
		# EASING TO. tick_replica moves it, and the separation is the whole
		# reason the view needs no network special case.
		_runner.check(b.net_target.is_equal_approx(a.position), _fail("fighter %d position" % i))
		_runner.check(b.facing.is_equal_approx(a.facing), _fail("fighter %d facing" % i))
		_runner.check(
			absf(b.health.current - a.health.current) < 0.01, _fail("fighter %d health" % i)
		)
		_runner.check(absf(b.charge - a.charge) < 0.01, _fail("fighter %d charge" % i))
		_runner.check(absf(b.reveal_timer - a.reveal_timer) < 0.01, _fail("fighter %d reveal" % i))
		_runner.check(b.gun.magazine == a.gun.magazine, _fail("fighter %d magazine" % i))
		_runner.check(b.fighter_class.id == a.fighter_class.id, _fail("fighter %d class" % i))

	var got: Bullet = null
	for b in dst.bullets:
		if b.active:
			got = b
			break
	_runner.check(got != null, _fail("the bullet arrived"))
	if got != null:
		_runner.check(got.position.is_equal_approx(bullet.position), _fail("bullet position"))
		_runner.check(got.velocity.is_equal_approx(bullet.velocity), _fail("bullet velocity"))
		_runner.check(absf(got.life - bullet.life) < 0.01, _fail("bullet life"))
		_runner.check(absf(got.total_life - bullet.total_life) < 0.01, _fail("bullet total_life"))
		_runner.check(got.arcing == bullet.arcing, _fail("bullet arcing"))
		_runner.check(absf(got.splash_radius - bullet.splash_radius) < 0.01, _fail("bullet splash"))
		_runner.check(got.owner_team == bullet.owner_team, _fail("bullet owner team"))
		# Never a real number on a client. Only the host applies damage, and a
		# client carrying one is one refactor away from applying it twice.
		_runner.check(got.damage == 0.0, _fail("a replicated bullet carries no damage"))

	var zone: Hazard = null
	for h in dst.hazards:
		if h.active:
			zone = h
			break
	_runner.check(zone != null, _fail("the hazard arrived"))
	if zone != null:
		_runner.check(zone.position.is_equal_approx(hazard.position), _fail("hazard position"))
		_runner.check(absf(zone.radius - hazard.radius) < 0.01, _fail("hazard radius"))
		_runner.check(
			absf(zone.damage_per_second - hazard.damage_per_second) < 0.01,
			_fail("hazard damage per second")
		)
		_runner.check(zone.owner_team == hazard.owner_team, _fail("hazard owner team"))

	_runner.check(dst.match_state.scores[0] == 7, _fail("score 0"))
	_runner.check(dst.match_state.scores[1] == 4, _fail("score 1"))
	_runner.check(absf(dst.match_state.elapsed - 61.5) < 0.01, _fail("clock"))
	_runner.check(dst.match_state.winner == 1, _fail("winner"))


## The bullet set is replaced, not merged.
##
## There is no "this bullet stopped existing" message and there must not be one:
## a bullet that hit somebody is simply absent from the next snapshot. A client
## that merged would draw it for the rest of the match.
func test_bullets_that_stopped_existing_stop_being_drawn() -> void:
	_case = "replace not merge"
	var src := _world()
	var dst := _world()

	for i in 4:
		var b: Bullet = dst._free_bullet()
		b.launch(Vector2(i * 10.0, 0.0), Vector2.RIGHT, 900.0, 10.0, 1.0, 0, 0)
	_runner.check(_live_bullets(dst) == 4, _fail("the client starts with four in the air"))

	var kept: Bullet = src._free_bullet()
	kept.launch(Vector2(500.0, 500.0), Vector2.UP, 900.0, 10.0, 1.0, 0, 0)

	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the snapshot is accepted"))
	_runner.check(
		_live_bullets(dst) == 1, _fail("one left, not five (got %d)" % _live_bullets(dst))
	)

	# And the empty case, which is the one that actually bites: the last bullet
	# landing produces a snapshot with NO bullets in it, and that has to clear
	# the screen rather than change nothing.
	for b in src.bullets:
		b.deactivate()
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the empty snapshot too"))
	_runner.check(_live_bullets(dst) == 0, _fail("an empty snapshot clears the sky"))


func _live_bullets(w: SimWorld) -> int:
	var n := 0
	for b in w.bullets:
		if b.active:
			n += 1
	return n


## A payload this build cannot read changes nothing at all.
##
## Two phones updated minutes apart is the NORMAL case here — the user installs
## an APK on three devices by hand — so a version mismatch is a thing that will
## happen, not a thing that might. Applying the prefix of a payload we half
## understand would put three cats at new positions and three at old ones, which
## reads as lag rather than as a mismatch.
func test_a_payload_this_build_cannot_read_is_refused_whole() -> void:
	_case = "refusal"
	var src := _world()
	var dst := _world()
	src.fighters[0].position = Vector2(999.0, 999.0)

	var wrong_version := Snapshot.capture(src)
	wrong_version[0] = float(Snapshot.VERSION + 1)
	_runner.check(not dst.apply_snapshot(wrong_version), _fail("a future version is refused"))
	_runner.check(dst.fighters[0].net_target == Vector2.ZERO, _fail("and nothing was written"))

	var truncated := Snapshot.capture(src)
	truncated.resize(truncated.size() - 3)
	_runner.check(not dst.apply_snapshot(truncated), _fail("a short payload is refused"))
	_runner.check(
		dst.fighters[0].net_target == Vector2.ZERO, _fail("and still nothing was written")
	)

	_runner.check(not dst.apply_snapshot(PackedFloat32Array()), _fail("an empty one too"))


## Hits and kills are DERIVED on the client, because the events are not sent.
##
## Fx and CameraRig subscribe to `hit` and `killed`, which only apply_damage()
## emits — and a client never calls apply_damage(). Without deriving them, two
## players out of three would get no damage numbers, no hitstop, no shake and no
## particles: the exact "nothing responds when you hit it" the whole M1.3 juice
## pass existed to fix.
func test_a_client_still_feels_being_shot() -> void:
	_case = "derived feedback"
	var src := _world()
	var dst := _world()
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("a first snapshot lands"))

	var hits: Array = []
	var kills: Array = []
	dst.hit.connect(func(_p: Vector2, _d: Vector2, dmg: float) -> void: hits.append(dmg))
	dst.killed.connect(func(_p: Vector2, _d: Vector2, _t: int) -> void: kills.append(1))

	var victim: Fighter = src.fighters[1]
	victim.health.current -= 40.0
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the damaged snapshot lands"))
	_runner.check(hits.size() == 1, _fail("one hit event, got %d" % hits.size()))
	# The damage is EXACT even though the event was never sent: it is the
	# difference between two health values that were.
	_runner.check(absf(float(hits[0]) - 40.0) < 0.01, _fail("and it carries the real damage"))
	_runner.check(kills.is_empty(), _fail("nobody died yet"))

	victim.health.current = 0.0
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the fatal snapshot lands"))
	_runner.check(kills.size() == 1, _fail("one kill event, got %d" % kills.size()))

	# And it must not fire again while the corpse stays a corpse — otherwise
	# every snapshot for the next three seconds restages the death.
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("a later snapshot lands"))
	_runner.check(kills.size() == 1, _fail("a corpse does not die twice"))

	# Healing is not a hit. Regen ticks constantly, and a sign error here would
	# fire a damage number every snapshot for every fighter out of combat.
	var before := hits.size()
	victim.health.current = 50.0
	_runner.check(dst.apply_snapshot(Snapshot.capture(src)), _fail("the healing snapshot lands"))
	_runner.check(hits.size() == before, _fail("regen is not an injury"))


# ---------------------------------------------------------------- the replica


## A client eases toward the host's truth and stops there.
func test_the_replica_converges_without_overshooting() -> void:
	_case = "replica"
	_tune("net_smoothing", 18.0)
	var w := _world()
	var f: Fighter = w.fighters[0]
	f.position = Vector2.ZERO
	f.prev_position = Vector2.ZERO
	f.net_target = Vector2(300.0, 0.0)

	var previous := 0.0
	for i in 60:
		w.tick_replica(DT)
		var travelled := f.position.x
		_runner.check(travelled >= previous - 0.001, _fail("it never goes backwards"))
		_runner.check(travelled <= 300.001, _fail("and never past the target"))
		previous = travelled

	_runner.check(f.position.distance_to(f.net_target) < 1.0, _fail("it arrives within a second"))

	# The pair the view interpolates between must actually be a PAIR while the
	# cat is moving: prev_position holding last tick's position and position
	# holding this one. Without that, Engine.get_physics_interpolation_fraction()
	# interpolates between a value and itself and running the replica at 60 Hz
	# buys nothing — which is the entire reason it is not applied at 30.
	#
	# Checked from a standing start toward a distant target rather than after the
	# loop above: once a cat has ARRIVED the two are equal, and correctly so.
	var fresh := _world()
	var g: Fighter = fresh.fighters[0]
	g.position = Vector2(10.0, 10.0)
	g.prev_position = g.position
	g.net_target = Vector2(400.0, 10.0)
	fresh.tick_replica(DT)
	_runner.check(
		g.prev_position.is_equal_approx(Vector2(10.0, 10.0)), _fail("prev holds last tick")
	)
	_runner.check(g.position.x > 10.0, _fail("and position holds this one"))
	_runner.check(
		g.position != g.prev_position, _fail("so the view has two points to draw between")
	)

	_restore()


## The client does not simulate. This is that sentence as an assertion.
##
## Expressed as an outcome rather than by inspecting for a flag: over a second
## of replica ticks with every fighter holding a full charge, an armed gun and
## an enemy in range, NOTHING may happen that only a host may decide.
func test_a_client_never_decides_anything() -> void:
	_case = "no authority"
	var w := _world()
	w.match_state.scores[0] = 0
	w.match_state.scores[1] = 0

	var shots: Array = []
	var damage: Array = []
	w.fired.connect(func(_p: Vector2, _d: Vector2) -> void: shots.append(1))
	w.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float) -> void: damage.append(1))

	# Everyone loaded, charged, and standing on top of each other: a ticking
	# world would produce carnage within a few frames.
	for f in w.fighters:
		f.position = w.arena.bounds().get_center()
		f.net_target = f.position
		f.charge = 1.0
		f.gun.magazine = f.gun.capacity()

	var health_before: Array[float] = []
	for f in w.fighters:
		health_before.append(f.health.current)

	# A live bullet from the host, mid-flight, pointed straight at everybody.
	var bullet: Bullet = w._free_bullet()
	bullet.launch(w.arena.bounds().get_center(), Vector2.RIGHT, 900.0, 65.0, 1.0, 1, 0)
	bullet.damage = 0.0

	for _i in 60:
		w.tick_replica(DT)

	_runner.check(shots.is_empty(), _fail("no gun goes off"))
	_runner.check(damage.is_empty(), _fail("no damage is applied"))
	for i in w.fighters.size():
		_runner.check(
			absf(w.fighters[i].health.current - health_before[i]) < 0.01,
			_fail("fighter %d is untouched" % i)
		)
	_runner.check(w.match_state.scores[0] == 0, _fail("team 0 scores nothing"))
	_runner.check(w.match_state.scores[1] == 0, _fail("team 1 scores nothing"))

	# The mirror, so none of the above passes on a world that simply cannot
	# fight: the SAME setup ticked properly does produce damage.
	var live := _world()
	for f in live.fighters:
		f.position = live.arena.bounds().get_center()
		f.prev_position = f.position
	var real_damage: Array = []
	live.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float) -> void: real_damage.append(1))
	live.apply_damage(live.fighters[1], 10.0, Vector2.RIGHT, 0, 0)
	_runner.check(not real_damage.is_empty(), _fail("but a real world still takes damage"))


# ------------------------------------------------------------ remote commands


func test_a_remote_command_drives_a_fighter_like_thumbs_do() -> void:
	_case = "remote input"
	var w := _world()
	var f: Fighter = w.fighters[1]
	var remote := RemoteController.new(42)
	f.controller = remote

	# Nothing received yet: a fighter in the roster before its first packet
	# stands still rather than inheriting somebody else's intent.
	_runner.check(not remote.fresh(), _fail("a peer that never spoke is not fresh"))
	var idle := remote.think(f, w, DT)
	_runner.check(idle.move == Vector2.ZERO, _fail("and produces nothing"))

	var cmd := InputCommand.new()
	cmd.move = Vector2.RIGHT
	cmd.aim = Vector2.UP
	remote.receive(cmd)

	var out := remote.think(f, w, DT)
	_runner.check(out.move == Vector2.RIGHT, _fail("the move arrives"))
	_runner.check(out.aim == Vector2.UP, _fail("and the aim"))

	# Copied, not referenced. The caller deserialises into a scratch command it
	# reuses for the NEXT packet, from any peer — holding the reference would let
	# one peer's input become another's.
	cmd.move = Vector2.LEFT
	_runner.check(
		remote.think(f, w, DT).move == Vector2.RIGHT, _fail("mutating the source changes nothing")
	)


## One release is one bullet, at 30 Hz packets against a 60 Hz simulation.
##
## `fire` is an EDGE. Read twice because two ticks elapse between packets, it
## becomes two bullets — a remote player quietly shooting at double the rate of
## the person hosting. TouchControls.take_fire() solves this for the local
## player by consuming the edge at a tick boundary; this is the same contract in
## the same place.
func test_one_release_is_one_bullet_however_many_ticks_pass() -> void:
	_case = "edge"
	var w := _world()
	var f: Fighter = w.fighters[1]
	var remote := RemoteController.new(42)

	var cmd := InputCommand.new()
	cmd.move = Vector2.RIGHT
	cmd.fire = true
	cmd.ability = true
	remote.receive(cmd)

	var fires := 0
	var abilities := 0
	for _i in 6:
		var out := remote.think(f, w, DT)
		if out.fire:
			fires += 1
		if out.ability:
			abilities += 1
		# The state fields are NOT consumed: holding a direction between packets
		# is what a held thumb means.
		_runner.check(out.move == Vector2.RIGHT, _fail("the held direction persists"))

	_runner.check(fires == 1, _fail("one fire edge, got %d" % fires))
	_runner.check(abilities == 1, _fail("one ability edge, got %d" % abilities))


## A phone that goes quiet leaves its cat standing.
##
## Locked screen, out of range, a run of dropped packets — the peer simply stops
## sending. Repeating the last command would leave a cat sprinting into a wall
## and firing forever, and worse, still scoring.
func test_a_peer_that_goes_quiet_stops_moving() -> void:
	_case = "staleness"
	_tune("net_stale_ticks", 10.0)
	var w := _world()
	var f: Fighter = w.fighters[1]
	var remote := RemoteController.new(42)

	var cmd := InputCommand.new()
	cmd.move = Vector2.RIGHT
	remote.receive(cmd)

	# Asserted in BOTH directions. "It goes quiet eventually" alone passes on a
	# controller that never worked at all.
	for i in 10:
		_runner.check(
			remote.think(f, w, DT).move == Vector2.RIGHT, _fail("still moving at tick %d" % i)
		)

	for _i in 5:
		remote.think(f, w, DT)
	_runner.check(not remote.fresh(), _fail("a quiet peer goes stale"))
	_runner.check(remote.think(f, w, DT).move == Vector2.ZERO, _fail("and its cat stands still"))

	# And it recovers: the phone comes back and so does the cat.
	remote.receive(cmd)
	_runner.check(remote.fresh(), _fail("a returning peer is fresh again"))
	_runner.check(remote.think(f, w, DT).move == Vector2.RIGHT, _fail("and moves again"))

	_restore()
