class_name Snapshot
extends RefCounted
## Everything one device needs to draw a fight happening on another one.
##
## Pure and static: `capture()` reads a SimWorld and returns numbers,
## `apply()` takes numbers and writes a SimWorld. No sockets, no nodes, no
## signals from the network layer. That is deliberate and it is the whole reason
## this file is in src/sim/ rather than src/net/ — a snapshot is a DESCRIPTION
## OF WORLD STATE, and the fact that one is usually posted through ENet is the
## network layer's business, not the simulation's (ADR-0003).
##
## The practical payoff is that every correctness claim about the wire format is
## a headless unit test with no second process in it. `apply(w, capture(w))` is
## an identity, and that one assertion catches the defining bug of this layer: a
## field that stops being sent. Nothing about a missing field is loud — the
## receiver simply keeps the value it already had, so a cat quietly stops
## reloading, or a score freezes, and it looks like a gameplay bug on a phone
## nobody can attach a debugger to.
##
## PackedFloat32Array rather than a Dictionary or a JSON string: it is what
## ENet wants, it has no per-entry overhead, and 32-bit floats are exact enough
## for a position measured in pixels on a 1440x840 arena. The counts are floats
## too, because a mixed-type payload would need a second array and an agreement
## about which one is read first.

## Bumped whenever the layout below changes. A client running an older APK than
## the host reads garbage otherwise, and "garbage" here means cats at NaN and a
## score of 4.6 rather than an error anybody can act on. Two phones updated
## minutes apart is the NORMAL case in this project, not the exotic one — the
## user installs on three devices by hand.
const VERSION := 1

## version, fighters, bullets, hazards, phase, score0, score1, elapsed,
## countdown, winner.
const HEADER := 10

## pos.x, pos.y, facing.x, facing.y, health.current, health.maximum,
## health.hit_flash, charge, reveal_timer, magazine, class_index.
const PER_FIGHTER := 11

## pos.x, pos.y, vel.x, vel.y, life, total_life, splash_radius, arcing,
## owner_team.
const PER_BULLET := 9

## pos.x, pos.y, radius, damage_per_second, life, owner_team.
const PER_HAZARD := 6


## Reads a world into a flat array of numbers.
##
## Only what a VIEW needs. The arena, the class table and every tuning value are
## absent on purpose: both devices load them from the same APK, and sending
## 73 tuning keys 30 times a second to say they have not changed would be the
## largest thing on the wire by an order of magnitude.
##
## Note what that implies and ADR-0033 records: the host's sliders are the ones
## that decide the fight, because the host is the only device running it.
static func capture(world: SimWorld) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var live_bullets: Array[Bullet] = []
	for b in world.bullets:
		if b.active:
			live_bullets.append(b)
	var live_hazards: Array[Hazard] = []
	for h in world.hazards:
		if h.active:
			live_hazards.append(h)

	out.resize(
		(
			HEADER
			+ world.fighters.size() * PER_FIGHTER
			+ live_bullets.size() * PER_BULLET
			+ live_hazards.size() * PER_HAZARD
		)
	)

	out[0] = float(VERSION)
	out[1] = float(world.fighters.size())
	out[2] = float(live_bullets.size())
	out[3] = float(live_hazards.size())
	out[4] = float(world.match_state.phase)
	out[5] = float(world.match_state.scores[0])
	out[6] = float(world.match_state.scores[1])
	out[7] = world.match_state.elapsed
	out[8] = world.match_state.countdown
	out[9] = float(world.match_state.winner)

	var at := HEADER
	for f in world.fighters:
		out[at + 0] = f.position.x
		out[at + 1] = f.position.y
		out[at + 2] = f.facing.x
		out[at + 3] = f.facing.y
		out[at + 4] = f.health.current
		out[at + 5] = f.health.maximum
		out[at + 6] = f.health.hit_flash
		out[at + 7] = f.charge
		out[at + 8] = f.reveal_timer
		# The magazine travels because the pips under YOUR OWN cat are drawn
		# from it, and on a client the local Gun is never ticked — its cooldown
		# and reload run on the host. Without this your ammo row would sit at
		# full for the whole match.
		out[at + 9] = float(f.gun.magazine)
		out[at + 10] = float(_class_index(f.fighter_class))
		at += PER_FIGHTER

	for b in live_bullets:
		out[at + 0] = b.position.x
		out[at + 1] = b.position.y
		out[at + 2] = b.velocity.x
		out[at + 3] = b.velocity.y
		out[at + 4] = b.life
		out[at + 5] = b.total_life
		out[at + 6] = b.splash_radius
		out[at + 7] = 1.0 if b.arcing else 0.0
		out[at + 8] = float(b.owner_team)
		at += PER_BULLET

	for h in live_hazards:
		out[at + 0] = h.position.x
		out[at + 1] = h.position.y
		out[at + 2] = h.radius
		out[at + 3] = h.damage_per_second
		out[at + 4] = h.life
		out[at + 5] = float(h.owner_team)
		at += PER_HAZARD

	return out


## Writes a snapshot into a world, and emits the feedback events it implies.
##
## Returns false and changes NOTHING on a payload that does not describe this
## build — a version mismatch or a length that disagrees with its own header.
## Refusing wholesale rather than applying the prefix matters: a half-applied
## snapshot is a world with three fighters at new positions and three at old
## ones, which reads as lag rather than as a mismatch and would be debugged for
## an hour.
static func apply(world: SimWorld, data: PackedFloat32Array) -> bool:
	if data.size() < HEADER or int(data[0]) != VERSION:
		return false

	var fighter_count := int(data[1])
	var bullet_count := int(data[2])
	var hazard_count := int(data[3])
	var expected := (
		HEADER + fighter_count * PER_FIGHTER + bullet_count * PER_BULLET + hazard_count * PER_HAZARD
	)
	if data.size() != expected or fighter_count != world.fighters.size():
		return false

	world.match_state.phase = int(data[4])
	world.match_state.scores[0] = int(data[5])
	world.match_state.scores[1] = int(data[6])
	world.match_state.elapsed = data[7]
	world.match_state.countdown = data[8]
	world.match_state.winner = int(data[9])

	var at := HEADER
	for i in fighter_count:
		_apply_fighter(world, world.fighters[i], data, at)
		at += PER_FIGHTER

	# The bullet set is REPLACED, never merged. A bullet that stopped existing
	# on the host — it hit someone, or expired — has no "delete" message; it is
	# simply absent from the next snapshot, and a client that merged would keep
	# drawing it forever.
	for b in world.bullets:
		b.deactivate()
	for i in bullet_count:
		var bullet := world.bullets[i] if i < world.bullets.size() else null
		if bullet == null:
			break
		bullet.position = Vector2(data[at + 0], data[at + 1])
		bullet.prev_position = bullet.position
		bullet.velocity = Vector2(data[at + 2], data[at + 3])
		bullet.life = data[at + 4]
		bullet.total_life = data[at + 5]
		bullet.splash_radius = data[at + 6]
		bullet.arcing = data[at + 7] > 0.5
		bullet.owner_team = int(data[at + 8])
		# Zero, always: only the host applies damage, and a client that carried a
		# real number here is one refactor away from applying it twice.
		bullet.damage = 0.0
		bullet.active = true
		at += PER_BULLET

	for h in world.hazards:
		h.deactivate()
	for i in hazard_count:
		var hazard := world.hazards[i] if i < world.hazards.size() else null
		if hazard == null:
			break
		hazard.position = Vector2(data[at + 0], data[at + 1])
		hazard.radius = data[at + 2]
		hazard.damage_per_second = data[at + 3]
		hazard.life = data[at + 4]
		hazard.owner_team = int(data[at + 5])
		hazard.active = true
		at += PER_HAZARD

	return true


## One fighter, plus the events its health change implies.
##
## THE FEEDBACK LAYER IS NOT ON THE WIRE, and it has to be somewhere. `Fx` and
## `CameraRig` subscribe to `hit` and `killed`, which SimWorld emits from
## apply_damage() — and a client never calls apply_damage(), so without this a
## client would get no damage numbers, no hitstop, no shake and no particles.
## That is the exact "nothing responds when you hit it" the whole M1.3 juice
## pass existed to fix, reintroduced for two players out of three.
##
## So the events are DERIVED from the health delta rather than transmitted. The
## damage is exact — it is the difference. The direction is an approximation
## (the victim's own facing, reversed, so a hit shoves the shake roughly the way
## a shot came in) and it is named as one here rather than pretended about: the
## direction drives a particle spray and a shake vector, neither of which any
## player can check, and sending a vector per hit to improve them would put the
## event stream on the wire for no gain anybody can see.
static func _apply_fighter(world: SimWorld, f: Fighter, data: PackedFloat32Array, at: int) -> void:
	var was_alive := f.alive()
	var before := f.health.current

	# The class first: its setter rebuilds the gun, which would otherwise
	# overwrite the magazine written three lines below.
	var cls := FighterClass.at(int(data[at + 10]))
	if cls != null and cls != f.fighter_class:
		f.fighter_class = cls

	# prev_position is left alone. tick_replica() owns it, and writing it here
	# would make the view interpolate from the last SNAPSHOT rather than from
	# the last frame — a 33 ms jump every time a packet lands.
	f.net_target = Vector2(data[at + 0], data[at + 1])
	f.facing = Vector2(data[at + 2], data[at + 3])
	f.health.current = data[at + 4]
	f.health.maximum = data[at + 5]
	f.health.hit_flash = data[at + 6]
	f.charge = data[at + 7]
	f.reveal_timer = data[at + 8]
	f.gun.magazine = int(data[at + 9])

	var lost := before - f.health.current
	if lost <= 0.0:
		return

	var dir := -f.facing if f.facing != Vector2.ZERO else Vector2.UP
	world.hit.emit(f.net_target, dir, lost)
	if was_alive and not f.alive():
		# -1: the snapshot carries the SCORES, which are what the readout shows.
		# Inventing an attribution here to satisfy the signal would put a second,
		# disagreeing scorekeeper on the client.
		world.killed.emit(f.net_target, dir, -1)


## Index of a class in the shared order, so the wire carries a small integer
## rather than a string. Both devices load data/classes.json from the same APK,
## which is what makes an index meaningful at all.
static func _class_index(cls: FighterClass) -> int:
	if cls == null:
		return 0
	var order := FighterClass.all()
	var found := order.find(cls.id)
	return found if found >= 0 else 0
