extends RefCounted
## Scoring, the win condition, and the phase gate.
##
## The whole match rule is a plain object with no nodes in it, so all of this
## runs headless — which is the point of keeping it in `src/sim/` rather than
## hanging a Timer off the HUD. Nothing here needs a display, and nothing here
## needs a phone.

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


## A match already under way, with no countdown left to burn.
func _live() -> MatchState:
	_restore()
	var m := MatchState.new()
	m.phase = MatchState.Phase.LIVE
	return m


# --------------------------------------------------------------------- scoring


func test_a_kill_scores_for_the_killer_not_the_victim() -> void:
	var m := _live()
	m.record_kill(1)
	_runner.check(m.scores[1] == 1, _fail("the killing team gains the point"))
	_runner.check(m.scores[0] == 0, _fail("and the victim's team gains nothing"))


func test_unattributed_damage_scores_for_nobody() -> void:
	# -1 is the default on apply_damage(). It has to stay inert, or any future
	# hazard would quietly hand a point to team 0 by arithmetic accident.
	var m := _live()
	m.record_kill(-1)
	m.record_kill(99)
	_runner.check(m.scores[0] == 0 and m.scores[1] == 0, _fail("no team scores"))


func test_a_kill_outside_live_does_not_count() -> void:
	# An arrow still in flight when the match ends must not change the result.
	var m := MatchState.new()
	m.phase = MatchState.Phase.OVER
	m.record_kill(0)
	_runner.check(m.scores[0] == 0, _fail("the whistle has gone"))


func test_the_world_attributes_a_real_arrow_kill() -> void:
	# The unit above tests the counter. This tests the wiring: a real arrow,
	# fired by a real team, through SimWorld.apply_damage().
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	var foe: Fighter = w.enemies_of(w.player.team)[0]

	w.apply_damage(foe, 99999.0, Vector2.RIGHT, true, w.player.team)
	_runner.check(not foe.alive(), _fail("the blow was lethal"))
	_runner.check(w.match_state.scores[w.player.team] == 1, _fail("the shooter's team scored"))


func test_a_team_never_scores_for_killing_its_own() -> void:
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	var mate: Fighter = null
	for f in w.fighters:
		if f != w.player and f.team == w.player.team:
			mate = f
			break
	_runner.check(mate != null, _fail("the player has a teammate"))

	w.apply_damage(mate, 99999.0, Vector2.RIGHT, true, w.player.team)
	_runner.check(not mate.alive(), _fail("the blow was lethal"))
	_runner.check(w.match_state.scores[w.player.team] == 0, _fail("no point for a own goal"))


# -------------------------------------------------------------- win conditions


func test_reaching_the_target_ends_the_match_for_that_team() -> void:
	var m := _live()
	_tune("match_target_kills", 3.0)

	for _i in 2:
		m.record_kill(1)
	m.tick(DT)
	_runner.check(m.phase == MatchState.Phase.LIVE, _fail("two of three is not a win"))

	m.record_kill(1)
	m.tick(DT)
	_runner.check(m.phase == MatchState.Phase.OVER, _fail("three of three ends it"))
	_runner.check(m.winner == 1, _fail("the team that got there wins"))
	_restore()


func test_the_time_cap_hands_it_to_whoever_leads() -> void:
	var m := _live()
	_tune("match_target_kills", 50.0)
	_tune("match_time_limit", 30.0)

	m.record_kill(0)
	m.elapsed = 29.99
	m.tick(DT)
	m.tick(DT)
	_runner.check(m.phase == MatchState.Phase.OVER, _fail("the clock runs out"))
	_runner.check(m.winner == 0, _fail("the leader takes it"))
	_restore()


func test_level_at_the_cap_goes_to_sudden_death_rather_than_a_draw() -> void:
	# The rule the win condition is easiest to get wrong. Asserted in both
	# directions: level does NOT end it, and the very next kill does.
	var m := _live()
	_tune("match_target_kills", 50.0)
	_tune("match_time_limit", 30.0)

	m.record_kill(0)
	m.record_kill(1)
	m.elapsed = 60.0
	for _i in 120:
		m.tick(DT)

	_runner.check(m.phase == MatchState.Phase.LIVE, _fail("a level score keeps playing"))
	_runner.check(m.sudden_death(), _fail("and says it is sudden death"))

	m.record_kill(1)
	m.tick(DT)
	_runner.check(m.phase == MatchState.Phase.OVER, _fail("the next kill settles it"))
	_runner.check(m.winner == 1, _fail("to whoever broke the tie"))
	_restore()


func test_the_match_ends_exactly_once() -> void:
	# The phase change is what makes this true. Emitting from a condition that
	# stays true would fire the results screen on every tick forever.
	var m := _live()
	_tune("match_target_kills", 1.0)

	var endings := []
	m.ended.connect(func(_team: int) -> void: endings.append(1))

	m.record_kill(0)
	for _i in 300:
		m.tick(DT)

	_runner.check(endings.size() == 1, _fail("ended fires once, not once per tick"))
	_restore()


# ------------------------------------------------------------- the phase gate


func test_the_countdown_freezes_the_world_and_then_releases_it() -> void:
	# Both directions. "Nothing moved" is worthless on its own — a world that
	# never simulates at all would satisfy it.
	var w := SimWorld.new()
	_tune("match_countdown", 1.0)
	w.match_state.begin_countdown()

	var bot: Fighter = w.fighters[1]
	var start := bot.position
	var idle := InputCommand.new()

	for _i in 30:
		w.tick(idle, DT)
	_runner.check(w.match_state.phase == MatchState.Phase.COUNTDOWN, _fail("still counting down"))
	_runner.check(bot.position.is_equal_approx(start), _fail("nobody moves during a countdown"))

	for _i in 300:
		w.tick(idle, DT)
	_runner.check(w.match_state.live(), _fail("the countdown releases into a live match"))
	_runner.check(not bot.position.is_equal_approx(start), _fail("and then the bots actually move"))
	_restore()


func test_no_arrow_flies_while_the_match_is_over() -> void:
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	var arrow: Arrow = w.arrows[0]
	arrow.launch(w.player.position, Vector2.RIGHT, 1200.0, 25.0, 5.0, w.player.team)
	var launched := arrow.position

	w.match_state.phase = MatchState.Phase.OVER
	for _i in 60:
		w.tick(InputCommand.new(), DT)

	_runner.check(arrow.position.is_equal_approx(launched), _fail("arrows hold their place"))


func test_a_new_match_starts_from_zero() -> void:
	var m := _live()
	m.record_kill(0)
	m.record_kill(0)
	m.begin_countdown()
	_runner.check(m.scores[0] == 0 and m.scores[1] == 0, _fail("last round's score is cleared"))
	_runner.check(m.elapsed == 0.0, _fail("and so is the clock"))
	_runner.check(m.phase == MatchState.Phase.COUNTDOWN, _fail("a countdown begins"))


func test_a_match_always_ends() -> void:
	# Sudden death has no clock of its own: a level score keeps the match open
	# until somebody scores. Measured over 24 simulated matches, 6 reached it
	# and 2 of those were 0-0 — so "the tiebreak resolves quickly" is an
	# assumption about kill rate, and kill rate is a slider. If it ever stops
	# being true the match never ends and the results screen never appears,
	# which on a phone is indistinguishable from the game hanging.
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE

	var idle := InputCommand.new()
	var limit := Tuning.get_value("match_time_limit")
	# The cap plus a generous overtime. Deliberately loose: this is a liveness
	# check, not a balance assertion.
	var ticks := int((limit + 180.0) * 60.0)
	var ended := false
	for _i in ticks:
		w.tick(idle, DT)
		if w.match_state.phase == MatchState.Phase.OVER:
			ended = true
			break

	_runner.check(ended, _fail("the match resolves rather than running forever"))
	_runner.check(w.match_state.winner >= 0, _fail("and it names a winner"))


func test_the_team_size_picker_actually_changes_the_roster() -> void:
	# What the setup screen does, asserted at the seam it does it through.
	# The picker writes bot_team_size and rebuilds the world; if SimWorld ever
	# stopped reading that key the screen would still look like it worked.
	for size in [1, 2, 3]:
		_tune("bot_team_size", float(size))
		var w := SimWorld.new()
		_runner.check(
			w.fighters.size() == size * 2,
			_fail("a side of %d makes %d fighters, got %d" % [size, size * 2, w.fighters.size()])
		)
		var team_a := 0
		for f in w.fighters:
			if f.team == 0:
				team_a += 1
		_runner.check(team_a == size, _fail("%d of them on team 0" % size))
	_restore()


func test_every_fighter_still_spawns_on_open_ground_at_any_team_size() -> void:
	# The arena has three spawn cells a side. A smaller roster takes a subset,
	# and a subset chosen wrongly could put two cats on one cell or one inside
	# stone — neither of which the size test above would notice.
	for size in [1, 2, 3]:
		_tune("bot_team_size", float(size))
		var w := SimWorld.new()
		var seen := {}
		for f in w.fighters:
			var cell := w.arena.cell_at(f.position)
			_runner.check(
				not w.arena.is_solid(cell.x, cell.y), _fail("spawn is open at size %d" % size)
			)
			seen[f.position] = true
		_runner.check(seen.size() == w.fighters.size(), _fail("no two share a spawn"))
	_restore()
