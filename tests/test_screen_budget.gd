extends RefCounted
## Nothing may reach further than the camera shows.
##
## This file exists because that invariant was violated in the shipped build and
## nothing noticed. In M3.1c the arrow's range was cut to 652 px and compared
## against the 711 px visible width — but the player sits at the CENTRE of the
## view, so the number that mattered was the half-width, 356. Shots out-ranged
## what you could see by 1.8x, bots held station at 380 px on purpose, and the
## first real playtest was "the bots shot at me from out-of-screen and I'm dead
## in a second. UNPLAYABLE."
##
## Every value here is a live slider, which is exactly why this is pinned: a
## tuning pass that fixes the feel and quietly breaks the geometry again is the
## expected failure, not an unlikely one.

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


## The world rectangle actually on screen, from the real project settings rather
## than a remembered 1280x720.
func _visible_half() -> Vector2:
	var w := float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	var h := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	var zoom := maxf(Tuning.get_value("camera_zoom"), 0.01)
	return Vector2(w / zoom, h / zoom) * 0.5


func _reach() -> float:
	return Tuning.get_value("bullet_speed") * Tuning.get_value("bullet_lifetime")


func test_a_bullet_cannot_out_range_the_visible_screen() -> void:
	# The headline rule: if something can hit you, you can see it coming.
	# Against the SMALLER half — the vertical one, because the view is landscape.
	# Testing the width alone leaves a band where a bot directly above you is out
	# of frame and still in range, which is 7% of firing opportunities by
	# measurement. The guarantee is worth more than the extra range.
	var half := _visible_half()
	var tightest := minf(half.x, half.y)
	_runner.check(
		_reach() <= tightest,
		_fail(
			"bullet reach %.0f fits the %.0f px half-view in EVERY direction" % [_reach(), tightest]
		)
	)


func test_bots_fight_inside_the_visible_box() -> void:
	# Against the HEIGHT, not the width. The view is landscape, so the vertical
	# half is the tight axis — a bot holding station 300 px directly above you
	# is off screen even though the same distance sideways is fine.
	var half := _visible_half()
	_runner.check(
		Tuning.get_value("bot_preferred_range") <= half.y,
		_fail("bots hold station within the %.0f px vertical half-view" % half.y)
	)
	_runner.check(
		Tuning.get_value("bot_ambush_range") <= half.y, _fail("and ambush from inside it too")
	)


func test_nothing_targets_beyond_what_the_gun_can_reach() -> void:
	# Auto-aim locking onto something out of range is a promise the bow cannot
	# keep — the same reasoning that cut autoaim_radius in M3.1c, now asserted
	# rather than remembered. The 15% headroom is for a target walking in.
	_runner.check(
		Tuning.get_value("autoaim_radius") <= _reach() * 1.15,
		_fail("autoaim stays within gun range")
	)


## A bot may not acquire a target it cannot see on screen.
##
## This assertion existed and was WRONG: it bounded sight range by `reach * 1.5`,
## an invented proxy, which let 280 px through against a 200 px vertical
## half-view. The result was exactly the bug the file was written to prevent —
## bots targeting and shooting from off screen — and the second playtest reported
## it in the same words as the first.
##
## ADR-0016 says the bound is the CAMERA. Anything else is a number that happens
## to be nearby, and a gate measuring the wrong thing is worse than no gate,
## because it is also reassuring.
func test_bots_cannot_see_you_from_off_screen() -> void:
	var half := _visible_half()
	var tightest := minf(half.x, half.y)
	_runner.check(
		Tuning.get_value("bot_sight_range") <= tightest,
		(
			_fail("bot sight %.0f is within the %.0f px half-view")
			% [Tuning.get_value("bot_sight_range"), tightest]
		)
	)


## Nothing may move faster than the eye can follow on a 6" screen.
##
## In body-lengths per second, which is the one measure of "how fast does this
## look" that survives a change of zoom. Brawl Stars runs its brawlers at about
## 2.4 of their own size per second. This shipped at 4.3 and the report was "the
## characters are fast and the movement is too sharp, there's no chance to aim
## and hit like this".
##
## Against the fighter's own diameter rather than the sprite's texture box. The
## cat drawn inside cat_body.svg is 62 px tall and 36 px wide against a 58 px
## hurtbox; the 128 px texture it sits in is mostly transparent margin. Measuring
## that texture overstates the cat by 20% and makes this gate lenient by the same
## amount — and believing the texture box was the cat is what briefly convinced
## me the hurtbox needed widening, when it was already 1.6x the visible animal.
func test_cats_move_at_a_speed_you_can_read() -> void:
	var body := Tuning.get_value("fighter_radius") * 2.0
	var lengths := Tuning.get_value("move_speed") / maxf(body, 0.01)
	_runner.check(
		lengths <= 3.0,
		_fail("cats cross %.2f of their own length per second (Brawl Stars ~2.4)" % lengths)
	)


## A kill must stay chunky enough to read, and slow enough to react to.
##
## This was a hit-count floor alone — "at least four hits" — and the fire rate
## made that a proxy rather than a measure. When fire_interval fell 0.35 -> 0.18
## the wall-clock time to kill went 2.50 s -> 0.90 s while the hit count barely
## moved, so the gate went on passing while the thing it was written to protect
## against got two and a half times worse. The same failure as the sight-range
## bound in this file's own history: a number that happens to be nearby is not
## the number that matters.
##
## So both halves are pinned now, and the second one is the real gate.
func test_a_fighter_survives_more_than_a_moment() -> void:
	var hits := Tuning.get_value("fighter_health") / maxf(Tuning.get_value("bullet_damage"), 0.01)
	var interval := Tuning.get_value("fire_interval")

	# Three hits is the floor the user set: "3-5 good shots are enough for a
	# kill". Below it a kill is one or two taps and there is nothing to read.
	_runner.check(hits >= 3.0, _fail("a kill takes at least three hits, got %.1f" % hits))

	# And the one that actually says "not dead in a second": how long a fighter
	# survives someone shooting PERFECTLY. Deliberately well under the 0.90 s the
	# chosen values measure — this pins the disaster, not the balance, and the
	# balance is settled with thumbs. Doubling bullet_damage from here trips it.
	_runner.check(
		hits * interval >= 0.6,
		(
			_fail("perfect fire needs %.2fs to kill (%.1f hits x %.2fs), floor is 0.60s")
			% [hits * interval, hits, interval]
		)
	)
