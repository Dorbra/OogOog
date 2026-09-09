extends RefCounted
## Bot AI: targeting, the difficulty knob, cover, and the fire cadence.
##
## Everything here drives BotController.think() directly and inspects the
## InputCommand it produces. That is the whole surface a bot has — it cannot set
## a position or spawn an arrow — so asserting on the command is asserting on
## everything a bot is able to do.
##
## Positions are found by ASKING THE ARENA for a cell that satisfies the case,
## never by hard-coded coordinates. A previous milestone shipped a screenshot
## fixture with a +360px offset that quietly landed inside a wall the moment the
## map was re-authored; the same mistake here would make these tests pass while
## testing nothing.

const DT := 1.0 / 60.0

var _runner: Object
var _case: String

var _saved := {}


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


# ------------------------------------------------------------------- fixtures


## Tuning is global and these tests move it, so every value touched is put back.
## Without this the first test to raise bot_skill would silently change the
## meaning of every test that ran after it.
func _tune(key: String, value: float) -> void:
	if not _saved.has(key):
		_saved[key] = Tuning.get_value(key)
	Tuning.set_value(key, value)


func _restore() -> void:
	for key: String in _saved:
		Tuning.set_value(key, _saved[key])
	_saved.clear()


## A world with nobody driving, so the only bot in play is the one under test.
func _world() -> SimWorld:
	_restore()
	var w := SimWorld.new()
	for f in w.fighters:
		f.controller = null
	return w


## Puts `a` and `b` roughly `distance` apart on open ground, with `want_wall`
## deciding whether stone stands between them. Returns false when the arena has
## no such pair, so a test can say so rather than assert against nonsense.
##
## Everyone else is swept off the map first. A 3v3 world has three enemies in
## it, and leaving the other two standing meant the bot kept picking a target
## the test had not staged — which is what made the first run of these tests
## fail for reasons that had nothing to do with the code under test.
## `cone_deg`, when set, also demands clear ground that far either side of the
## line. Measuring aim spread from a corner cell truncates every wide shot
## against the border and quietly compresses the very difference being measured.
func _place(
	w: SimWorld, a: Fighter, b: Fighter, distance: float, want_wall: bool, cone_deg: float = 0.0
) -> bool:
	_banish_all_but(w, a, b)
	var arena := w.arena
	for y in arena.rows:
		for x in arena.cols:
			if arena.is_solid(x, y):
				continue
			var p := arena.cell_centre(x, y)
			if arena.conceals(p):
				continue
			for step in 16:
				var angle := TAU * float(step) / 16.0
				var q := p + Vector2(cos(angle), sin(angle)) * distance
				var qc := arena.cell_at(q)
				if not arena.in_grid(qc.x, qc.y) or arena.is_solid(qc.x, qc.y):
					continue
				if arena.conceals(q):
					continue
				if arena.cast_segment(p, q)["hit"] != want_wall:
					continue
				if cone_deg > 0.0 and not _cone_is_clear(arena, p, q, cone_deg):
					continue
				a.position = p
				a.prev_position = p
				b.position = q
				b.prev_position = q
				return true
	return false


## Moves every fighter except `a` and `b` far outside the arena, so the only
## thing either of them can see is the other.
func _banish_all_but(w: SimWorld, a: Fighter, b: Fighter) -> void:
	var away := Vector2(-100000.0, -100000.0)
	for f in w.fighters:
		if f == a or f == b:
			continue
		f.position = away
		f.prev_position = away


## Every ray within `cone_deg` of p -> q reaches open ground.
func _cone_is_clear(arena: Arena, p: Vector2, q: Vector2, cone_deg: float) -> bool:
	var to := q - p
	for i in 9:
		var offset := deg_to_rad(lerpf(-cone_deg, cone_deg, float(i) / 8.0))
		if arena.cast_segment(p, p + to.rotated(offset))["hit"]:
			return false
	return true


## A staging distance that is always inside what a bot can see and shoot.
##
## Derived rather than written down. Hard-coded fixture distances have now
## broken twice: 400 px went out of sight range in the pacing pass, and 300 px
## did too — and one of those failures would have been SILENT, asserting "the
## bot held fire" against a bot that simply had no target.
func _engage_distance() -> float:
	return minf(
		Tuning.get_value("bot_sight_range") * 0.8, Tuning.get_value("bot_preferred_range") + 60.0
	)


func _bush_centre(arena: Arena) -> Vector2:
	for cell in arena.cells_in_rect(arena.bounds()):
		if cell.z == Arena.Cell.BUSH:
			return arena.cell_centre(cell.x, cell.y)
	return Vector2.INF


func _foe_of(w: SimWorld, bot: Fighter) -> Fighter:
	return w.enemies_of(bot.team)[0]


# -------------------------------------------------------------------- targeting


func test_a_concealed_enemy_is_invisible_until_it_shoots() -> void:
	# The mechanic the whole cover pass rests on. Before this, Arena.conceals()
	# had one caller — a 55% alpha fade — so a bush hid nothing from anybody and
	# an ambush was not expressible.
	var w := _world()
	_restore()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)

	var bush := _bush_centre(w.arena)
	_runner.check(bush != Vector2.INF, _fail("the arena has a bush to hide in"))

	_banish_all_but(w, bot, foe)
	foe.position = bush
	# Far enough that proximity is not what reveals it, and clear of stone.
	bot.position = bush + Vector2(Tuning.get_value("reveal_radius") * 4.0, 0.0)
	if w.arena.cast_segment(bot.position, foe.position)["hit"]:
		bot.position = bush - Vector2(Tuning.get_value("reveal_radius") * 4.0, 0.0)

	_runner.check(not w.can_see(bot.position, foe), _fail("a cat in a bush cannot be seen"))
	_runner.check(
		w.nearest_visible_enemy(bot.position, 100000.0, bot) == null,
		_fail("and cannot be targeted")
	)

	foe.reveal_timer = 1.0
	_runner.check(w.can_see(bot.position, foe), _fail("loosing an arrow gives it away"))

	foe.reveal_timer = 0.0
	bot.position = bush + Vector2(Tuning.get_value("reveal_radius") * 0.5, 0.0)
	_runner.check(w.can_see(bot.position, foe), _fail("standing on top of it also reveals it"))


func test_line_of_sight_is_blocked_by_stone() -> void:
	# The one fixture that deliberately keeps a fixed distance. Every assertion
	# below passes an explicit range (or asks can_see(), which has none), so
	# sight range cannot be what makes them true — and a wider separation gives
	# the arena more wall-separated pairs to offer.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(_place(w, bot, foe, 400.0, true), _fail("the arena offers a blocked pair"))
	_runner.check(not w.can_see(bot.position, foe), _fail("a wall blocks sight"))
	_runner.check(
		w.nearest_visible_enemy(bot.position, 100000.0, bot) == null,
		_fail("nothing visible is nothing to target")
	)
	# The plain distance query must be UNCHANGED. It is what tools/screenshot.gd
	# stages against and what test_fighters.gd asserts non-null, so the two
	# functions existing separately is the contract — not an accident.
	_runner.check(
		w.nearest_enemy(bot.position, 100000.0, bot) == foe,
		_fail("nearest_enemy still ignores walls, as its callers expect")
	)


# ---------------------------------------------------------------------- firing


func test_the_reaction_delay_holds_the_first_shot_and_then_releases_it() -> void:
	# Asserted in BOTH directions on purpose. "It eventually fires" alone would
	# pass with no delay at all, and "it does not fire yet" alone would pass if
	# the bot were broken and never fired.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(
		_place(w, bot, foe, _engage_distance(), false), _fail("the arena offers a clear pair")
	)

	_tune("bot_skill", 0.0)
	_tune("bot_aim_error_deg", 0.0)
	_tune("bot_reaction_time", 0.5)
	_tune("draw_time_full", 0.1)

	var ctrl := BotController.new(1)
	var first_fire := -1
	for i in 120:
		bot.bow.quiver = bot.bow.capacity()
		var cmd := ctrl.think(bot, w, DT)
		if cmd.fire:
			first_fire = i
			break

	_runner.check(first_fire >= 0, _fail("the bot does eventually shoot"))
	# 0.5 s of reaction is 30 ticks; the draw then takes 0.1 s more.
	_runner.check(first_fire >= 29, _fail("it does not shoot before the reaction delay"))
	_runner.check(first_fire <= 48, _fail("and it does not dawdle once the delay is over"))
	_restore()


func test_a_bot_draws_at_a_human_rate_rather_than_emptying_its_quiver() -> void:
	# The cheat guard. SimWorld fires whenever cmd.fire is true, so a bot that
	# simply held it down would loose an arrow EVERY TICK and put five in the
	# air in 83 ms — something no thumb can do. Bots have to pull the string.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(
		_place(w, bot, foe, _engage_distance(), false), _fail("the arena offers a clear pair")
	)

	_tune("bot_skill", 1.0)
	_tune("bot_aim_error_deg", 0.0)
	_tune("bot_reaction_time", 0.0)
	_tune("draw_time_full", 0.28)

	var ctrl := BotController.new(2)
	var shots := 0
	for _i in 60:
		bot.bow.quiver = bot.bow.capacity()
		if ctrl.think(bot, w, DT).fire:
			shots += 1

	_runner.check(shots >= 1, _fail("it shoots at all"))
	# One second at a 0.28 s draw is at most four shots, never sixty.
	_runner.check(shots <= 5, _fail("it cannot outshoot a player holding the same bow"))
	_restore()


func test_a_bot_will_not_fire_into_stone() -> void:
	# Staged with a revealed target behind a wall, which is the only way this
	# guard is reachable: without the reveal the bot cannot see the target at
	# all and would hold fire for the wrong reason, passing the test while
	# proving nothing.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(
		_place(w, bot, foe, _engage_distance(), true), _fail("the arena offers a blocked pair")
	)

	foe.reveal_timer = 999.0
	_runner.check(w.can_see(bot.position, foe), _fail("the target IS acquired through the wall"))
	# Belt and braces: can_see() ignores range, but the bot acquires through
	# nearest_visible_enemy(), which does not. Out past bot_sight_range this
	# test would assert "no shots" against a bot that had no target at all —
	# green, and testing nothing.
	_runner.check(
		w.nearest_visible_enemy(bot.position, Tuning.get_value("bot_sight_range"), bot) == foe,
		_fail("and it is within sight range, so holding fire is a real decision")
	)

	_tune("bot_skill", 1.0)
	_tune("bot_aim_error_deg", 0.0)
	_tune("bot_reaction_time", 0.0)
	_tune("draw_time_full", 0.05)

	var ctrl := BotController.new(3)
	var shots := 0
	for _i in 120:
		bot.bow.quiver = bot.bow.capacity()
		if ctrl.think(bot, w, DT).fire:
			shots += 1

	_runner.check(shots == 0, _fail("not one arrow is wasted on the wall"))
	_restore()


# ------------------------------------------------------------------ difficulty


func test_the_skill_slider_measurably_narrows_the_spread() -> void:
	# A difficulty knob that does nothing is the most likely way this feature
	# ships broken: everything still runs, the bots still fight, and the slider
	# is decoration. So it is measured rather than assumed.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(
		_place(w, bot, foe, _engage_distance(), false, 35.0),
		_fail("the arena offers a wide-open pair")
	)

	_tune("bot_aim_error_deg", 30.0)
	_tune("bot_reaction_time", 0.0)
	_tune("draw_time_full", 0.05)

	var clumsy := _mean_aim_error(w, bot, foe, 0.0)
	var sharp := _mean_aim_error(w, bot, foe, 1.0)

	_runner.check(clumsy > 0.02, _fail("a low-skill bot really does miss"))
	_runner.check(sharp < clumsy * 0.5, _fail("a high-skill bot aims materially straighter"))
	_restore()


## Mean absolute angle, in radians, between where the bot shoots and where the
## target actually is, sampled over many shots at one skill level.
func _mean_aim_error(w: SimWorld, bot: Fighter, foe: Fighter, skill: float) -> float:
	_tune("bot_skill", skill)
	var truth := (foe.position - bot.position).angle()
	var ctrl := BotController.new(int(skill * 100.0) + 11)

	var total := 0.0
	var shots := 0
	for _i in 1200:
		bot.bow.quiver = bot.bow.capacity()
		var cmd := ctrl.think(bot, w, DT)
		if cmd.fire:
			total += absf(angle_difference(truth, cmd.aim.angle()))
			shots += 1

	return total / float(maxi(shots, 1))


func test_leading_puts_the_shot_ahead_of_a_moving_target() -> void:
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	# Inside bot_sight_range. The old 400 px fixture silently stopped acquiring a
	# target when the pacing pass pulled sight range inside the visible screen —
	# the test failed loudly, which is the only reason it is not still passing
	# with the bot aiming at nothing.
	_runner.check(
		_place(w, bot, foe, _engage_distance(), false), _fail("the arena offers a clear pair")
	)

	_tune("bot_skill", 1.0)
	_tune("bot_aim_error_deg", 0.0)
	_tune("bot_reaction_time", 0.0)

	# Straight across the line of fire, which is where leading matters most.
	var across := (foe.position - bot.position).normalized().orthogonal()
	foe.velocity = across * 400.0

	_tune("bot_lead_factor", 1.0)
	var leading := BotController.new(21).think(bot, w, DT).aim

	_tune("bot_lead_factor", 0.0)
	var straight := BotController.new(22).think(bot, w, DT).aim

	_runner.check(leading.dot(across) > 0.05, _fail("a leading bot aims ahead of the target"))
	_runner.check(
		absf(straight.dot(across)) < 0.02, _fail("with leading off it aims at the target itself")
	)
	_restore()


# ---------------------------------------------------------------------- cover


func test_ambushes_are_gated_on_the_difficulty_slider() -> void:
	# The reconciliation of "full cover play" with "one global difficulty".
	# Being shot from a bush you never saw is the least fair thing in this
	# design, so it arrives with skill rather than being on for everyone.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var bush := _bush_centre(w.arena)
	_runner.check(bush != Vector2.INF, _fail("the arena has a bush to hide in"))

	bot.position = bush
	bot.prev_position = bush
	for f in w.fighters:
		if f.team != bot.team:
			# Out of sight, so the decision is about cover and nothing else.
			f.position = Vector2(-100000.0, -100000.0)

	_tune("bot_cover_skill_gate", 0.5)
	_tune("bot_skill", 0.2)
	var timid := BotController.new(31)
	timid.think(bot, w, DT)
	_runner.check(timid.state != BotController.State.LURK, _fail("a low-skill bot never lurks"))

	_tune("bot_skill", 0.9)
	var sneaky := BotController.new(32)
	sneaky.think(bot, w, DT)
	_runner.check(
		sneaky.state == BotController.State.LURK, _fail("a high-skill bot lies in wait in cover")
	)
	_restore()


func test_a_lurking_bot_holds_perfectly_still() -> void:
	# Standing still is the mechanic, not an accident of having nowhere to go:
	# movement is what would give an ambusher away before it strikes.
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var bush := _bush_centre(w.arena)
	_runner.check(bush != Vector2.INF, _fail("the arena has a bush to hide in"))

	bot.position = bush
	bot.prev_position = bush
	for f in w.fighters:
		if f.team != bot.team:
			f.position = Vector2(-100000.0, -100000.0)

	_tune("bot_cover_skill_gate", 0.0)
	_tune("bot_skill", 1.0)
	var ctrl := BotController.new(41)
	var cmd := ctrl.think(bot, w, DT)

	_runner.check(ctrl.state == BotController.State.LURK, _fail("it is lurking"))
	_runner.check(cmd.move == Vector2.ZERO, _fail("it does not move"))
	_runner.check(not cmd.fire, _fail("and it does not shoot"))
	_restore()


func test_a_hurt_bot_retreats_and_breaks_the_line_of_sight() -> void:
	var w := _world()
	var bot: Fighter = w.fighters[1]
	var foe := _foe_of(w, bot)
	_runner.check(
		_place(w, bot, foe, _engage_distance(), false), _fail("the arena offers a clear pair")
	)

	_tune("bot_retreat_health", 0.35)
	_tune("bot_skill", 1.0)
	_tune("bot_reaction_time", 0.0)

	bot.health.set_maximum(Tuning.get_value("fighter_health"))
	bot.health.current = bot.health.maximum * 0.15
	# Keeps it "in combat" so out-of-combat regen does not heal it back above
	# the retreat threshold mid-test and quietly change what is being measured.
	bot.health.since_damage = 0.0

	var ctrl := BotController.new(51)
	var start := bot.position
	_runner.check(w.can_see(foe.position, bot), _fail("it starts out in the open"))

	var retreated := false
	for _i in 300:
		bot.health.current = bot.health.maximum * 0.15
		bot.health.since_damage = 0.0
		var cmd := ctrl.think(bot, w, DT)
		bot.tick(cmd, DT, w.arena)
		if ctrl.state == BotController.State.RETREAT:
			retreated = true

	_runner.check(retreated, _fail("low health sends it into a retreat"))
	_runner.check(bot.position.distance_to(start) > 1.0, _fail("it actually goes somewhere"))
	_runner.check(not w.can_see(foe.position, bot), _fail("and ends up where it cannot be shot"))
	_restore()


# ------------------------------------------------------------------ end to end


## A bot with nobody to fight must keep looking, not stand where it is.
##
## The bug this pins hung a real match. `_do_seek` walked to the middle of the
## map, which is a point a bot can ARRIVE at — and once there `_steer()` returns
## a zero vector and it stops. After every fighter had died once and lost contact,
## both teams did exactly that on opposite sides of an empty arena: a 3-3 match
## ran for ten more minutes without a single shot. On a phone that is the results
## screen never appearing.
##
## The bot is placed exactly ON the old fallback goal, because standing on your
## goal is the only state in which the bug shows. A bot walking toward the centre
## looks perfectly healthy right up until it gets there.
func test_a_bot_with_nothing_to_fight_keeps_moving() -> void:
	var w := _world()
	var bot := w.fighters[1]
	bot.controller = BotController.new(11)
	# Nobody to see: every enemy is dead, so _acquire returns null and the bot is
	# in SEEK with no last known position.
	for f in w.fighters:
		if f.team != bot.team:
			f.health.take_damage(100000.0)

	bot.position = w.arena.bounds().get_center()
	bot.prev_position = bot.position
	var start := bot.position

	for _i in 180:
		var cmd: InputCommand = bot.controller.think(bot, w, DT)
		bot.tick(cmd, DT, w.arena)

	_runner.check(
		bot.position.distance_to(start) > 60.0,
		(
			_fail("a bot standing on the old fallback goal walks off it (moved %.0f px)")
			% bot.position.distance_to(start)
		)
	)


## And the same for the ghost: arriving where you last saw somebody, and finding
## nobody, has to end the search rather than end the bot.
func test_a_bot_forgets_a_last_known_position_it_has_reached() -> void:
	var w := _world()
	var bot := w.fighters[1]
	bot.controller = BotController.new(13)
	var enemy := w.nearest_enemy(bot.position, 100000.0, bot)

	# Let it actually SEE the enemy, so _last_known is set the way the game sets
	# it, rather than by poking at the controller's internals.
	enemy.position = bot.position + Vector2(Tuning.get_value("bot_sight_range") * 0.4, 0.0)
	enemy.prev_position = enemy.position
	bot.controller.think(bot, w, DT)

	# Then the enemy is gone and the bot is standing on the ghost.
	enemy.health.take_damage(100000.0)
	bot.position = enemy.position
	bot.prev_position = bot.position
	var start := bot.position

	for _i in 180:
		var cmd: InputCommand = bot.controller.think(bot, w, DT)
		bot.tick(cmd, DT, w.arena)

	_runner.check(
		bot.position.distance_to(start) > 60.0,
		(
			_fail("a bot standing on a stale last-known position moves on (moved %.0f px)")
			% bot.position.distance_to(start)
		)
	)


func test_a_full_3v3_actually_produces_a_fight() -> void:
	# Every other test in this file drives think() directly with fighters placed
	# by hand. That verifies the parts and would happily stay green if bots were
	# never wired into SimWorld at all, or if they wandered the map without ever
	# finding each other. This runs thirty seconds of the REAL match loop and
	# asserts that a fight breaks out.
	#
	# Deterministic despite the world seeding its own RNG: bots carry seeded
	# generators, and they always loose at full draw, where Bow.deviation_for()
	# is zero. Verified by running it repeatedly and getting identical counts.
	var w := SimWorld.new()
	var start := {}
	for i in w.fighters.size():
		start[i] = w.fighters[i].position

	# Arrays rather than ints: a GDScript lambda captures by VALUE, so `n += 1`
	# on a captured integer increments a copy and reports zero forever. This
	# exact trap made the first run of this check report a silent, fightless
	# match that had in fact killed two cats.
	var shots := []
	var hits := []
	w.fired.connect(func(_p: Vector2, _d: Vector2, _s: float) -> void: shots.append(1))
	w.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float, _f: bool) -> void: hits.append(1))

	# The match has to be started now: SimWorld does not tick fighters outside
	# MatchState.Phase.LIVE. That this test failed the moment the phase gate
	# landed is the gate working — a world that simulates during a countdown
	# would have sailed through unchanged.
	w.match_state.phase = MatchState.Phase.LIVE

	# The FURTHEST each fighter ever got from its spawn, not where it happened to
	# be standing at the end. A bot that crosses the map, fights, and walks back
	# reads as "never left" under the end-position check this used to do — which
	# it duly did the first time the movement speed changed, reporting a bot that
	# had travelled 541 px as having moved 53.
	var idle := InputCommand.new()
	var furthest := {}
	for i in w.fighters.size():
		furthest[i] = 0.0
	for _i in 1800:
		w.tick(idle, DT)
		for i in w.fighters.size():
			furthest[i] = maxf(furthest[i], w.fighters[i].position.distance_to(start[i]))

	var moved := 0
	for i in w.fighters.size():
		if furthest[i] > 60.0:
			moved += 1

	# Five bots and one motionless player, so five is the whole roster moving.
	_runner.check(moved >= 5, _fail("every bot leaves its spawn"))
	_runner.check(shots.size() > 10, _fail("bots find each other and shoot"))
	_runner.check(hits.size() > 0, _fail("and some of those arrows connect"))
