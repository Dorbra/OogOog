class_name FighterClass
extends RefCounted
## What makes one cat shoot differently from another.
##
## A class is a set of MULTIPLIERS over the global tuning keys, never a stat
## block of its own. That is the whole design decision and it is not about
## tidiness: giving each class absolute values would take the DBG panel from 62
## sliders to roughly 180 and end the on-device tuning workflow ADR-0004 exists
## to protect. You cannot drag "damage" and feel the result when there are three
## of them. Every slider still moves the whole game; a class says only how it
## differs from that. Recorded as ADR-0028.
##
## Loaded once from data/classes.json and shared. A class is immutable at
## runtime — it is a description, not state — so every Fighter of a class holds
## the same instance rather than a copy.

const PATH := "res://data/classes.json"

## Ordered ids, which is also the order the picker draws them in.
static var _order: Array[String] = []
static var _by_id: Dictionary = {}
static var _loaded := false

var id: String = "ranger"

## What the picker calls this class, in Hebrew. Data rather than code because a
## name is content, and because the next class should not need a view file
## edited to be nameable.
var label: String = ""

## Which icon the picker draws. An index rather than a path: a five-year-old
## picks by shape, and the shapes are drawn in code, not loaded as art.
var icon: int = 0

## Which ability this class carries. Dispatched by name in SimWorld.
var ability: String = ""

## Bullets per trigger pull, and the total arc they are spread across.
##
## THE FAN IS DETERMINISTIC. Pellets sit at fixed angles across the arc, so
## point blank they all connect and at range they open — legible, and identical
## every time the same shot is fired. Random spread on a fast flat bullet is
## precisely the "cant be expected" that got the bow deleted (ADR-0022), and it
## would make the headless tests unrepeatable as well.
var pellets: int = 1
var spread_deg: float = 0.0

var damage_mult: float = 1.0
var fire_interval_mult: float = 1.0
var reach_mult: float = 1.0
var magazine_mult: float = 1.0
var reload_mult: float = 1.0
var speed_mult: float = 1.0

## How fast this cat WALKS, as a multiple of move_speed.
##
## Added because measurement demanded it rather than because it seemed nice: a
## short-ranged class has to be able to close, and at equal speed the Skirmisher
## simply could not. Measured over 12 seeded matches per match-up it took 12% of
## the kills against a Ranger team where its own mirror gave it 27% — not a
## match-up, a class that does not work.
var move_mult: float = 1.0

## How much punishment this cat takes, as a multiple of fighter_health.
##
## The last lever the Skirmisher needed, and the reason is arithmetic rather
## than taste: it has to cross about 107 px of open ground to reach the range
## its shotgun works at, which takes 0.6 s under 222 DPS of Ranger fire — two
## thirds of its health spent before it can return a shot. Measured, that lost
## it 67-70% of the kills in both directions of the match-up. A short-ranged
## class has to be able to survive the walk in.
var health_mult: float = 1.0


## Every class, in picker order. The array is shared, not copied.
static func all() -> Array[String]:
	_ensure_loaded()
	return _order


static func count() -> int:
	return all().size()


## The class with this id, or the first one when it is unknown.
##
## Never null. An unknown id is a stale saved value or a typo, and returning
## null would turn that into a crash on a phone with no console — the failure
## mode this project keeps designing against.
static func get_class_by_id(class_id: String) -> FighterClass:
	_ensure_loaded()
	if _by_id.has(class_id):
		return _by_id[class_id]
	push_error("FighterClass: unknown class '%s'" % class_id)
	return _by_id[_order[0]]


## The class at `index` in picker order, wrapped. Used for dealing classes
## round-robin across a team and for reading the player's picked index.
static func at(index: int) -> FighterClass:
	_ensure_loaded()
	if _order.is_empty():
		return null
	return _by_id[_order[posmod(index, _order.size())]]


## Loaded on first use rather than in a _ready(), for the same reason Tuning is:
## under `--script` there is no tree and no autoload lifecycle, and a silent
## zero would be the worst possible failure for a table of multipliers.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true

	var text := FileAccess.get_file_as_string(PATH)
	if text.is_empty():
		push_error("FighterClass: could not read %s" % PATH)
		return

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("FighterClass: %s is not a JSON object" % PATH)
		return

	var root: Dictionary = parsed
	var defs: Dictionary = root.get("classes", {})
	for class_id: String in root.get("order", []):
		if not defs.has(class_id):
			push_error("FighterClass: '%s' is in order but has no definition" % class_id)
			continue
		_order.append(class_id)
		_by_id[class_id] = _from_dictionary(class_id, defs[class_id])


static func _from_dictionary(class_id: String, entry: Dictionary) -> FighterClass:
	var out := FighterClass.new()
	out.id = class_id
	out.icon = int(entry.get("icon", 0))
	out.label = String(entry.get("label", class_id))
	out.ability = String(entry.get("ability", ""))
	# At least one pellet, always. A class that fires nothing is not a class a
	# five-year-old can diagnose.
	out.pellets = maxi(1, int(entry.get("pellets", 1)))
	out.spread_deg = float(entry.get("spread_deg", 0.0))
	out.damage_mult = float(entry.get("damage", 1.0))
	out.fire_interval_mult = float(entry.get("fire_interval", 1.0))
	out.reach_mult = float(entry.get("reach", 1.0))
	out.magazine_mult = float(entry.get("magazine", 1.0))
	out.reload_mult = float(entry.get("reload", 1.0))
	out.speed_mult = float(entry.get("speed", 1.0))
	out.move_mult = float(entry.get("move", 1.0))
	out.health_mult = float(entry.get("health", 1.0))
	return out


## Damage of one fully-connecting shot, relative to the baseline class.
##
## pellets x damage, NOT damage alone. A Skirmisher pellet does 0.42 of a Ranger
## round, which makes the class look feeble in a table; three of them landing
## together do 1.26 of it, which is what the player actually experiences and
## therefore what the picker has to show. Showing per-pellet damage would be
## true and misleading at the same time.
func burst_damage_mult() -> float:
	return float(pellets) * damage_mult


## The angle offset of pellet `index`, in radians, for a shot of `pellets`.
##
## Centred on the aim: one pellet goes dead straight, three go -half, 0, +half.
## Lives here rather than in SimWorld so the tests can assert the fan without
## building a world, and so the view could draw it later without duplicating
## the arithmetic.
func pellet_angle(index: int) -> float:
	if pellets <= 1 or spread_deg <= 0.0:
		return 0.0
	var step := deg_to_rad(spread_deg) / float(pellets - 1)
	return -deg_to_rad(spread_deg) * 0.5 + step * float(index)
