extends RefCounted
## Camera shake and hitstop fire for what happens to YOU, not for the match.
##
## This file exists because they did not, and a playtest said so in capitals:
## "the screen doesn't stop shaking (STOP THAT SHIT!)".
##
## SimWorld emits `hit`, `killed` and `fired` for every fighter anywhere on the
## map. CameraRig added trauma for all of them and Fx called hitstop() — which
## dips Engine.time_scale GLOBALLY — for all of them too. With six fighters, five
## of every six events belonged to somebody else, somewhere else. Trauma arrived
## at roughly 0.72/s against a decay of 1.9/s and settled at a permanent jitter
## that never reached zero, and the whole game micro-froze about once a second
## because two bots traded shots off screen.
##
## Neither was expressible as a bug report from inside the code, and both are
## trivially expressible as assertions. Hence this file.

const DT := 1.0 / 60.0

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## A live match with the player parked in a corner, far from the fighting.
##
## Everyone else is left armed on purpose: the whole point is that OTHER
## people's fights must not reach the camera.
func _world_with_the_player_out_of_it() -> SimWorld:
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	# Off the map entirely. Nothing can hit the player, so every event that
	# occurs during the run is by definition somebody else's.
	w.player.position = Vector2(-100000.0, -100000.0)
	w.player.prev_position = w.player.position
	w.player.controller = null
	return w


func _rig_for(w: SimWorld) -> CameraRig:
	var rig := CameraRig.new()
	rig.target_position = w.player.position
	rig.listen_to(w)
	return rig


# ----------------------------------------------------------------- the camera


func test_other_peoples_fights_never_shake_the_camera() -> void:
	var w := _world_with_the_player_out_of_it()
	var rig := _rig_for(w)

	var events := []
	w.hit.connect(func(_p: Vector2, _d: Vector2, _dmg: float) -> void: events.append(1))

	# Thirty seconds of a real 3v3 happening somewhere the player is not.
	for _i in 1800:
		w.tick(InputCommand.new(), DT)

	_runner.check(events.size() > 0, _fail("there really was a fight to ignore"))
	_runner.check_near(rig.trauma(), 0.0, _fail("the camera never moved"), 0.0001)
	rig.free()


func test_being_hit_yourself_does_shake_the_camera() -> void:
	# The mirror. Without it the test above passes against a camera that has had
	# its shake deleted outright, which is not the same thing as a steady one.
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	var rig := _rig_for(w)
	rig.target_position = w.player.position

	w.apply_damage(w.player, 10.0, Vector2.RIGHT, 1)
	_runner.check(rig.trauma() > 0.0, _fail("a hit on you does shake"))
	rig.free()


func test_your_own_bowstring_does_not_shake_the_camera() -> void:
	# shake_fire is 0 by default. At five arrows a second this was the single
	# largest contributor to the jitter, and the reference game does not do it.
	_runner.check_near(
		Tuning.get_value("shake_fire"), 0.0, _fail("firing adds no trauma by default"), 0.0001
	)


# ---------------------------------------------------------------- the hitstop


func test_other_peoples_fights_never_freeze_the_game() -> void:
	# The worse of the two: hitstop dips Engine.time_scale globally, so a hit
	# between two bots on the far side of the map stuttered the whole game.
	var w := _world_with_the_player_out_of_it()
	var fx := Fx.new()
	fx.listen_to(w)

	# Asserted on hitstop_left(), NOT on Engine.time_scale. The time scale is
	# applied in _process(), which never runs for a node built outside the scene
	# tree — so watching it here passed happily with the filter deleted. Found by
	# negative-testing this very test.
	var worst := 0.0
	for _i in 1800:
		w.tick(InputCommand.new(), DT)
		worst = maxf(worst, fx.hitstop_left())

	_runner.check_near(worst, 0.0, _fail("the game never froze for somebody else"), 0.0001)
	fx.free()


func test_being_hit_yourself_does_freeze_the_game() -> void:
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	var fx := Fx.new()
	fx.listen_to(w)

	w.apply_damage(w.player, 10.0, Vector2.RIGHT, 1)
	_runner.check(fx.hitstop_left() > 0.0, _fail("a hit on you does freeze"))
	fx.free()


# ------------------------------------------------------------------- the bots


func test_a_bot_will_not_fire_at_something_it_cannot_reach() -> void:
	# The other half of "shooting from off screen". Before this, the only gate on
	# firing was whether a wall was in the way — so a bot happily loosed arrows
	# at targets well beyond its range. They died in mid-air and hit nothing; the
	# player just saw shots arriving from nowhere.
	var w := SimWorld.new()
	w.match_state.phase = MatchState.Phase.LIVE
	for f in w.fighters:
		f.controller = null

	var bot: Fighter = w.fighters[1]
	var foe: Fighter = w.enemies_of(bot.team)[0]
	var away := Vector2(-100000.0, -100000.0)
	for f in w.fighters:
		if f != bot and f != foe:
			f.position = away

	# bot.gun.reach(), not speed x bullet_lifetime. Those were the same number
	# while every fighter carried the same gun; with classes they are not, and
	# the hand-rolled version says 249 px for a Skirmisher that actually reaches
	# 143. Ask the gun how far it shoots.
	var reach := bot.gun.reach()

	# Sight range is widened for this test on purpose. At the shipped defaults
	# sight (230) and reach (226) are only 4 px apart, so "acquired but out of
	# range" is almost unreachable by accident — and staging the target beyond
	# BOTH made the first version of this test pass for entirely the wrong
	# reason: the bot had no target at all and so did not fire.
	#
	# The guard exists precisely for the configuration where sight exceeds reach,
	# which is what shipped and what the playtest hit. So that is what is tested.
	var saved_sight := Tuning.get_value("bot_sight_range")
	Tuning.set_value("bot_sight_range", reach * 2.0)

	bot.position = w.arena.cell_centre(2, 2)
	foe.position = bot.position + Vector2(reach * 1.5, 0.0)
	foe.reveal_timer = 999.0
	_runner.check(
		w.nearest_visible_enemy(bot.position, Tuning.get_value("bot_sight_range"), bot) == foe,
		_fail("the bot HAS acquired it, so holding fire is a real decision")
	)

	var ctrl := BotController.new(77)
	var shots := 0
	for _i in 240:
		bot.gun.magazine = bot.gun.capacity()
		if ctrl.think(bot, w, DT).fire:
			shots += 1
	_runner.check(shots == 0, _fail("no arrows wasted on an unreachable target"))
	Tuning.set_value("bot_sight_range", saved_sight)

	# And the mirror: brought inside reach, it shoots.
	foe.position = bot.position + Vector2(reach * 0.6, 0.0)
	var near_ctrl := BotController.new(78)
	var near_shots := 0
	for _i in 240:
		bot.gun.magazine = bot.gun.capacity()
		if near_ctrl.think(bot, w, DT).fire:
			near_shots += 1
	_runner.check(near_shots > 0, _fail("but it does shoot once you are in range"))
