extends RefCounted
## A* over the arena grid.
##
## Every case here is built from a purpose-made grid rather than the real arena,
## because the interesting inputs are the ones a hand-edited map produces by
## accident: a sealed pocket, a diagonal that looks open and is not, a goal
## inside stone. Writing the fixture through the real parser rather than
## constructing an Arena by hand means these also fail if parsing regresses.

const FIXTURE := "user://test_grid_path_fixture.txt"

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _arena_from(rows: Array) -> Arena:
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	file.store_string("\n".join(rows))
	file.close()
	return Arena.new(FIXTURE)


## True when no step of the path stands in a wall — the property that matters,
## since a path is only useful if a fighter can physically walk it.
func _never_crosses_stone(a: Arena, path: PackedVector2Array) -> bool:
	for p: Vector2 in path:
		var c := a.cell_at(p)
		if a.is_solid(c.x, c.y):
			return false
	return true


func test_finds_a_route_across_open_ground() -> void:
	var a := _arena_from(["#####", "#...#", "#...#", "#####"])
	var path := GridPath.find_path(a, a.cell_centre(1, 1), a.cell_centre(3, 2))
	_runner.check(not path.is_empty(), _fail("an open route is found"))
	_runner.check(_never_crosses_stone(a, path), _fail("no step lands in stone"))
	_runner.check(
		path[path.size() - 1].is_equal_approx(a.cell_centre(3, 2)),
		_fail("the path ends on the goal cell")
	)


func test_routes_around_a_wall_rather_than_through_it() -> void:
	# The only way from the left pocket to the right one is down through row 3.
	var a := _arena_from(["#######", "#..#..#", "#..#..#", "#.....#", "#######"])
	var path := GridPath.find_path(a, a.cell_centre(1, 1), a.cell_centre(5, 1))
	_runner.check(not path.is_empty(), _fail("a route around the wall exists"))
	_runner.check(_never_crosses_stone(a, path), _fail("no step lands in stone"))

	var used_the_gap := false
	for p: Vector2 in path:
		if a.cell_at(p).y == 3:
			used_the_gap = true
	_runner.check(used_the_gap, _fail("the route goes the long way, through row 3"))


func test_a_sealed_cell_returns_no_path_instead_of_hanging() -> void:
	# The centre cell is walled in on all four sides. The honest answer is "no
	# route"; the dangerous answer is a search that never terminates, which on a
	# phone is indistinguishable from the game freezing.
	var a := _arena_from(["#####", "#...#", "#.#.#", "#...#", "#####"])
	var sealed := _arena_from(["#####", "#...#", "#.#.#", "#...#", "#####"])
	_runner.check(sealed.is_solid(2, 2), _fail("the fixture really is sealed"))

	var path := GridPath.find_path(a, a.cell_centre(1, 1), a.cell_centre(2, 2))
	_runner.check(path.is_empty(), _fail("a goal inside stone yields no path"))


func test_a_diagonal_that_would_cut_a_corner_is_refused() -> void:
	# (1,1) and (2,2) are open and diagonally adjacent, but (2,1) and (1,2) are
	# both walls. A naive eight-way A* slides straight between them. A fighter
	# cannot: its radius is 29 against a half-cell of 30, so push-out rejects
	# that move on every tick and the bot grinds into the corner forever.
	var a := _arena_from(["####", "#.##", "##.#", "####"])
	_runner.check(not a.is_solid(1, 1), _fail("start is open"))
	_runner.check(not a.is_solid(2, 2), _fail("goal is open"))
	_runner.check(a.is_solid(2, 1) and a.is_solid(1, 2), _fail("both corners are stone"))

	var path := GridPath.find_path(a, a.cell_centre(1, 1), a.cell_centre(2, 2))
	_runner.check(path.is_empty(), _fail("the corner cut is refused"))


func test_a_reachable_diagonal_is_still_allowed() -> void:
	# The mirror of the case above: proves the corner rule rejects the illegal
	# move rather than rejecting diagonals altogether, which would quietly make
	# every bot walk in staircases.
	var a := _arena_from(["####", "#..#", "#..#", "####"])
	var path := GridPath.find_path(a, a.cell_centre(1, 1), a.cell_centre(2, 2))
	_runner.check(path.size() == 1, _fail("an open diagonal is a single step"))


func test_standing_on_the_goal_yields_an_empty_path() -> void:
	var a := _arena_from(["#####", "#...#", "#...#", "#####"])
	var path := GridPath.find_path(a, a.cell_centre(2, 1), a.cell_centre(2, 1))
	_runner.check(path.is_empty(), _fail("already there means nothing to walk"))


func test_a_fighter_shoved_into_stone_can_still_find_its_way_out() -> void:
	# Knockback can push a fighter into a wall cell for a tick. If the search
	# refused to start from a solid cell, that fighter would stop moving for the
	# rest of the match — a bug that only shows up after someone gets hit.
	var a := _arena_from(["#####", "#...#", "#.#.#", "#...#", "#####"])
	var path := GridPath.find_path(a, a.cell_centre(2, 2), a.cell_centre(1, 1))
	_runner.check(not path.is_empty(), _fail("a route out of stone is found"))
	_runner.check(_never_crosses_stone(a, path), _fail("the escape route is walkable"))
