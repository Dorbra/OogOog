class_name Gun
extends RefCounted
## Magazine, reload and rate of fire. One shot, always the same shot.
##
## Deliberately free of nodes, rendering and input so it can be unit tested
## headless — which is the only verification available without a phone in hand.
##
## THIS REPLACED A BOW, and the reason is worth keeping. Draw strength — hold
## time driving speed, damage and deviation together — was the game's whole
## shooting mechanic, chosen because the gesture and the fiction were the same
## action. In the hand it read as a 450 ms delay in front of every shot, on a
## projectile slow enough that where it would land was guesswork:
##
##     "the Arrow shooting is sluggish and cant be expected,
##      lets change back to GUNS! with a clear line-of-fire"
##
## So the curve is gone rather than turned down. What it bought — a reason for
## one shot to differ from another — now has to come from class asymmetry in
## feat/classes, which is where Brawl Stars keeps it anyway. That debt is real
## and is named in ADR-0022.
##
## The rate limit lives HERE rather than in the input layer, so the player and
## the bots are gated by the same code. A bot cannot out-shoot you because it
## fires the same gun.
##
## SINCE feat/classes every number below is a global tuning key TIMES this gun's
## class multiplier. The multiplier is the only thing a class owns; the key is
## still the one slider on the phone that moves the whole game. That is what
## keeps the on-device workflow alive with more than one gun in play — see
## ADR-0028 and FighterClass.

## Rounds available right now.
var magazine: int = 0

## What this gun is. Never null: a gun with no class is a gun with no numbers,
## and that would surface as a silent zero rather than as an error.
var fighter_class: FighterClass = null

var _reload_accum: float = 0.0

## Seconds until this gun will fire again. Counted down in tick().
var _cooldown: float = 0.0


func _init(of_class: FighterClass = null) -> void:
	fighter_class = of_class if of_class != null else FighterClass.at(0)
	magazine = capacity()


## Bullets per trigger pull. One consume() covers the whole fan — a three-pellet
## shot spends one round, not three.
func pellets() -> int:
	return fighter_class.pellets


func pellet_angle(index: int) -> float:
	return fighter_class.pellet_angle(index)


## At least one round, whatever the multiplier rounds to. A magazine of zero is
## a cat that cannot shoot at all, which reads on a phone as the game being
## broken rather than as a balance choice.
func capacity() -> int:
	return maxi(1, int(round(Tuning.get_value("magazine_size") * fighter_class.magazine_mult)))


func speed() -> float:
	return Tuning.get_value("bullet_speed") * fighter_class.speed_mult


func damage() -> float:
	return Tuning.get_value("bullet_damage") * fighter_class.damage_mult


func fire_interval() -> float:
	return Tuning.get_value("fire_interval") * fighter_class.fire_interval_mult


func reload_time() -> float:
	return Tuning.get_value("reload_time") * fighter_class.reload_mult


## How long a bullet from this gun lives.
##
## Derived from reach rather than the other way round, because reach is the
## number a reader and a slider both care about — how far this gun shoots —
## while a lifetime means nothing until it has been divided by a speed. A class
## that is faster AND shorter-ranged (the Skirmisher is both) would otherwise
## need its two multipliers reasoned about together to know where its bullets
## land.
func lifetime() -> float:
	if speed() <= 0.0:
		return 0.0
	return reach() / speed()


## How far a bullet gets before it expires. Pinned under the visible half-view
## by test_screen_budget.gd, FOR EVERY CLASS: if something can hit you, you can
## see it coming (ADR-0016).
func reach() -> float:
	return (
		Tuning.get_value("bullet_speed")
		* Tuning.get_value("bullet_lifetime")
		* fighter_class.reach_mult
	)


## The range at which this gun's WHOLE shot lands on a cat.
##
## For a single round that is just its reach. For a fan it is where the outer
## pellets clear a target's edge — beyond that only the centre pellet connects
## and the gun does a third of its damage while still calling itself in range.
##
## This exists because the Skirmisher lost every match-up and the reason was not
## the numbers on it. Bots held station at reach x 0.62 = 105 px, and a 46 degree
## fan opens past a 29 px cat at 74 px — so a Skirmisher bot stood exactly where
## its shotgun stopped being a shotgun, and got shot by Rangers the whole time.
## A bot has to fight where its gun works, not where its bullets merely arrive.
func effective_range() -> float:
	var half := deg_to_rad(fighter_class.spread_deg) * 0.5
	if fighter_class.pellets <= 1 or half <= 0.0:
		return reach()
	return minf(reach(), Tuning.get_value("fighter_radius") / sin(half))


func can_fire() -> bool:
	return magazine > 0 and _cooldown <= 0.0


## Spends one round and starts the cooldown. Returns false and changes nothing
## when the magazine is empty or the gun is still between shots.
func consume() -> bool:
	if not can_fire():
		return false
	magazine -= 1
	_cooldown = fire_interval()
	return true


## Call once per simulation tick.
func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_tick_reload(delta)


func _tick_reload(delta: float) -> void:
	var cap := capacity()
	if magazine >= cap:
		# Sitting at full must not bank progress toward an instant future reload.
		_reload_accum = 0.0
		return

	var per_round := reload_time()
	if per_round <= 0.0:
		magazine = cap
		return

	_reload_accum += delta
	while _reload_accum >= per_round and magazine < cap:
		_reload_accum -= per_round
		magazine += 1

	if magazine >= cap:
		_reload_accum = 0.0
