class_name GridPath
extends RefCounted
## A* over the arena's cell grid.
##
## Not NavigationAgent2D. The grid already exists, an arena is a few hundred
## cells, and staying pure maths keeps the simulation node-free and testable
## without a display — the same reasoning as ADR-0008. A navigation mesh would
## mean baking a resource the CI has no editor to bake, for a search that costs
## microseconds by hand.
##
## Every function is static: pathfinding holds no state, and a bot that owned a
## searcher object would be storing nothing worth keeping between calls.

## Straight-line cost is 1.0, so a diagonal is the hypotenuse. Using 1.0 for
## both makes A* treat a staircase and a diagonal as equal and produces visibly
## silly zig-zags.
const DIAGONAL_COST := 1.4142135624

## A hard stop on the search. An arena is a few hundred cells, so this is never
## reached in practice — it exists so that a malformed grid cannot hang the
## simulation, which on a phone looks exactly like the game freezing.
const MAX_EXPANSIONS := 4096

const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


## Cell centres from the step after `from` through to the cell containing `to`.
##
## Empty means "no route", which callers must treat as a real answer rather than
## an error: a sealed pocket and an already-arrived bot both return empty.
static func find_path(arena: Arena, from: Vector2, to: Vector2) -> PackedVector2Array:
	var start := arena.cell_at(from)
	var goal := arena.cell_at(to)

	if start == goal:
		return PackedVector2Array()
	if not arena.in_grid(goal.x, goal.y) or arena.is_solid(goal.x, goal.y):
		return PackedVector2Array()

	# The start cell is walkable by definition even when it is solid. A fighter
	# shoved into geometry by knockback would otherwise find no route out of the
	# cell it is standing in and stop moving for the rest of the match.
	var came_from := {}
	var g_score := {start: 0.0}
	var open: Array[Vector2i] = [start]
	var f_score := {start: _heuristic(start, goal)}

	var expansions := 0
	while not open.is_empty() and expansions < MAX_EXPANSIONS:
		expansions += 1
		var current := _pop_lowest(open, f_score)
		if current == goal:
			return _rebuild(arena, came_from, current)

		for step in NEIGHBOURS:
			var next := current + step
			if not _passable(arena, current, next):
				continue

			var step_cost := DIAGONAL_COST if step.x != 0 and step.y != 0 else 1.0
			var tentative: float = float(g_score[current]) + step_cost
			if g_score.has(next) and tentative >= float(g_score[next]):
				continue

			came_from[next] = current
			g_score[next] = tentative
			f_score[next] = tentative + _heuristic(next, goal)
			if not open.has(next):
				open.append(next)

	return PackedVector2Array()


## True when a fighter can actually walk `from` -> `to`.
##
## The corner rule is load-bearing, not a nicety: fighter_radius is 29 against a
## half-cell of 30, so a diagonal that squeezes between two walls is a move the
## collision push-out will refuse every single tick. Allowing it produces a bot
## that walks confidently into a corner and vibrates there.
static func _passable(arena: Arena, from: Vector2i, to: Vector2i) -> bool:
	if not arena.in_grid(to.x, to.y) or arena.is_solid(to.x, to.y):
		return false
	if from.x == to.x or from.y == to.y:
		return true
	return not arena.is_solid(to.x, from.y) and not arena.is_solid(from.x, to.y)


## Octile distance — the exact cost of an unobstructed path under this move set,
## so it never overestimates and A* stays optimal.
static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	var dx := absf(float(a.x - b.x))
	var dy := absf(float(a.y - b.y))
	return maxf(dx, dy) + (DIAGONAL_COST - 1.0) * minf(dx, dy)


## Linear scan for the cheapest open node. A binary heap would be the textbook
## answer and is not worth it here: an arena is a few hundred cells and a bot
## repaths twice a second, so the whole search is far below the noise floor of a
## single frame. Revisit only if arenas grow by an order of magnitude.
static func _pop_lowest(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best := 0
	var best_f: float = float(f_score[open[0]])
	for i in range(1, open.size()):
		var f: float = float(f_score[open[i]])
		if f < best_f:
			best_f = f
			best = i
	var node: Vector2i = open[best]
	open.remove_at(best)
	return node


## Walks the parent chain back to the start, then drops the start itself — the
## caller is standing there and steering toward it would mean walking backwards.
static func _rebuild(arena: Arena, came_from: Dictionary, goal: Vector2i) -> PackedVector2Array:
	var cells: Array[Vector2i] = [goal]
	var node := goal
	while came_from.has(node):
		node = came_from[node]
		cells.append(node)

	var out := PackedVector2Array()
	for i in range(cells.size() - 2, -1, -1):
		var c: Vector2i = cells[i]
		out.append(arena.cell_centre(c.x, c.y))
	return out
