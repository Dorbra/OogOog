class_name MatchState
extends RefCounted
## The score, the clock, and the rule for who wins.
##
## Pure logic on a plain object, like everything else in `src/sim/` — no nodes,
## no `Input`, no timers from the engine. That is what lets the entire win
## condition be asserted headlessly, which is where every other correctness
## claim in this project lives (ADR-0003, ADR-0008).
##
## It also decides when the world is allowed to move. The freeze during a
## countdown is a PHASE, not `get_tree().paused`: pausing the scene tree would
## take the tuning panel down with it, and adjusting sliders between rounds is
## the entire on-device workflow (ADR-0004).

## Emitted once when LIVE begins.
signal started

## Emitted exactly once per match. `winning_team` is 0 or 1 — never -1, because
## a level score does not end the match (see `_decide`).
signal ended(winning_team: int)

enum Phase {
	## Choosing team size. Nothing simulates.
	SETUP,
	## Three, two, one. The arena is visible and completely still.
	COUNTDOWN,
	## The only phase in which fighters and arrows tick.
	LIVE,
	## Somebody won. The world holds its last frame under the results screen.
	OVER,
}

const TEAM_COUNT := 2

var phase: int = Phase.SETUP
var scores: Array[int] = [0, 0]

## Counts up while LIVE. Compared against `match_time_limit` rather than
## counting down, so changing the limit mid-match on a slider cannot produce a
## negative clock.
var elapsed: float = 0.0

var countdown: float = 0.0
var winner: int = -1


func reset() -> void:
	phase = Phase.SETUP
	scores = [0, 0]
	elapsed = 0.0
	countdown = 0.0
	winner = -1


## SETUP -> COUNTDOWN. The scores are cleared here rather than on `started`, so
## the score readout shows 0-0 during the countdown instead of last round's
## result.
func begin_countdown() -> void:
	scores = [0, 0]
	elapsed = 0.0
	winner = -1
	countdown = maxf(Tuning.get_value("match_countdown"), 0.0)
	phase = Phase.COUNTDOWN


func live() -> bool:
	return phase == Phase.LIVE


## True while the world is allowed to simulate. Separate from `live()` on
## purpose: the two mean the same thing today and would not if a slow-motion
## finish or a pause menu were ever added, and the call sites read better.
func simulating() -> bool:
	return phase == Phase.LIVE


func record_kill(scoring_team: int) -> void:
	# Unattributed kills — a hazard, a suicide, an arrow with no owner — score
	# for nobody. Recorded outside LIVE too would let a stray arrow still in
	# flight when the whistle went change the result.
	if phase != Phase.LIVE:
		return
	if scoring_team < 0 or scoring_team >= TEAM_COUNT:
		return
	scores[scoring_team] += 1


func tick(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			countdown -= delta
			if countdown <= 0.0:
				countdown = 0.0
				phase = Phase.LIVE
				started.emit()
		Phase.LIVE:
			elapsed += delta
			var decided := _decide()
			if decided >= 0:
				winner = decided
				phase = Phase.OVER
				# Phase changes BEFORE the signal, so a handler that inspects
				# the state sees OVER rather than a match still nominally live.
				# The phase change is also what makes this fire exactly once.
				ended.emit(decided)
		_:
			pass


## The winning team, or -1 while the match should continue.
##
## Two conditions and one rule that is easy to miss:
##
## - A team reaching `match_target_kills` wins immediately.
## - At `match_time_limit` the leader wins.
## - **Level at the time limit does NOT end the match.** It keeps going until
##   one side leads by one. A draw is an anticlimax to hand two children, and at
##   the rate these matches actually produce kills a tiebreak resolves in
##   seconds. This is why the time check tests the difference rather than just
##   the clock.
func _decide() -> int:
	var target := int(Tuning.get_value("match_target_kills"))
	if target > 0:
		for team in TEAM_COUNT:
			if scores[team] >= target:
				return team

	var limit := Tuning.get_value("match_time_limit")
	if limit > 0.0 and elapsed >= limit and scores[0] != scores[1]:
		return 0 if scores[0] > scores[1] else 1

	return -1


## True once the clock has run out and only a tiebreak is holding the match
## open. The view uses it to say so; nothing else depends on it.
func sudden_death() -> bool:
	if phase != Phase.LIVE:
		return false
	var limit := Tuning.get_value("match_time_limit")
	return limit > 0.0 and elapsed >= limit


## Seconds left, floored at zero. Presentation only.
func remaining() -> float:
	return maxf(Tuning.get_value("match_time_limit") - elapsed, 0.0)
