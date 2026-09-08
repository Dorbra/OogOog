extends RefCounted
## Arena parsing, wall collision, and line-of-fire.
##
## All pure maths with no Godot physics involved, which is exactly why it can be
## verified here rather than by installing a build and walking into a wall.

var _runner: Object
var _case: String


func _fail(label: String) -> String:
	return "%s: %s" % [_case, label]


func _arena() -> Arena:
	return Arena.new()


func test_grid_parses_with_expected_shape() -> void:
	var a := _arena()
	_runner.check(a.cols > 0 and a.rows > 0, _fail("grid has extent"))
	_runner.check(a.cell_size > 0.0, _fail("cell size loaded from legend"))
	_runner.check_near(
		a.bounds().size.x, a.cols * a.cell_size, _fail("world width derives from the grid")
	)
	_runner.check_near(
		a.bounds().size.y, a.rows * a.cell_size, _fail("world height derives from the grid")
	)


func test_border_is_solid_and_outside_counts_as_solid() -> void:
	var a := _arena()
	_runner.check(a.is_solid(0, 0), _fail("corner is wall"))
	_runner.check(a.is_solid(a.cols - 1, a.rows - 1), _fail("far corner is wall"))
	# Treating off-grid as solid means nothing can leave the map even if a row
	# is short — the parser tolerates ragged input, so this has to hold.
	_runner.check(a.is_solid(-1, 5), _fail("outside the grid is solid"))
	_runner.check(a.is_solid(a.cols + 10, 5), _fail("far outside is solid"))


func test_spawn_points_are_all_on_open_ground() -> void:
	var a := _arena()
	var points := a.spawn_points()
	_runner.check(points.size() >= 4, _fail("arena provides several spawns"))

	var bad := 0
	for p: Vector2 in points:
		var c := a.cell_at(p)
		if a.is_solid(c.x, c.y):
			bad += 1
	_runner.check(bad == 0, _fail("no spawn is inside a wall"))


## Finds a wall cell that has at least one open neighbour.
##
## Deliberately not the border corner: that cell is enclosed by other walls, so
## there is no open face to leave through and no correct answer exists. The case
## worth testing is the one that can actually happen in play.
func _wall_with_an_exit(a: Arena) -> Vector2i:
	for y in range(1, a.rows - 1):
		for x in range(1, a.cols - 1):
			if not a.is_solid(x, y):
				continue
			for n: Vector2i in [
				Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)
			]:
				if not a.is_solid(n.x, n.y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func test_circle_is_pushed_out_of_a_wall() -> void:
	var a := _arena()
	var cell := _wall_with_an_exit(a)
	_runner.check(cell.x >= 0, _fail("arena has an interior wall to test against"))
	if cell.x < 0:
		return

	var inside := a.cell_centre(cell.x, cell.y)
	var out := a.resolve_circle(inside, 26.0)
	_runner.check(not out.is_equal_approx(inside), _fail("a circle in a wall is moved"))

	var c := a.cell_at(out)
	_runner.check(not a.is_solid(c.x, c.y), _fail("and ends up on open ground"))


func test_circle_overlapping_a_wall_edge_is_pushed_clear() -> void:
	var a := _arena()
	var cell := _wall_with_an_exit(a)
	if cell.x < 0:
		return

	# The common real case: standing next to a wall and pressing into it, so the
	# centre is outside but the radius overlaps.
	var edge := a.cell_centre(cell.x, cell.y) - Vector2(a.cell_size * 0.5 + 4.0, 0.0)
	var out := a.resolve_circle(edge, 20.0)
	var rect := Rect2(Vector2(cell.x, cell.y) * a.cell_size, Vector2(a.cell_size, a.cell_size))
	var closest := Vector2(
		clampf(out.x, rect.position.x, rect.end.x), clampf(out.y, rect.position.y, rect.end.y)
	)
	_runner.check(
		out.distance_to(closest) >= 20.0 - 0.01, _fail("pushed clear of the wall surface")
	)


func test_open_ground_is_left_alone() -> void:
	var a := _arena()
	# A spawn point, which the test above proves is open.
	var p: Vector2 = a.spawn_points()[0]
	_runner.check(
		a.resolve_circle(p, 20.0).is_equal_approx(p), _fail("open ground needs no correction")
	)


func test_corner_resolves_rather_than_wedging() -> void:
	var a := _arena()
	# The inside corner of the border: overlapping BOTH the top and left walls.
	# One resolution pass fixes one axis and leaves the circle still inside the
	# other, which in play reads as sticking to geometry.
	var corner := Vector2(a.cell_size, a.cell_size)
	var out := a.resolve_circle(corner, 28.0)

	var min_c := a.cell_at(out - Vector2(28.0, 28.0))
	var max_c := a.cell_at(out + Vector2(28.0, 28.0))
	var overlaps := 0
	for y in range(min_c.y, max_c.y + 1):
		for x in range(min_c.x, max_c.x + 1):
			if a.is_solid(x, y):
				overlaps += 1
	_runner.check(overlaps == 0, _fail("corner leaves no residual wall overlap"))


func test_clear_line_reports_no_hit() -> void:
	var a := _arena()
	var p: Vector2 = a.spawn_points()[0]
	var r: Dictionary = a.cast_segment(p, p + Vector2(a.cell_size * 0.4, 0.0))
	_runner.check(not r["hit"], _fail("a short hop on open ground is clear"))


func test_cast_stops_at_the_first_wall_not_the_nearest_to_the_target() -> void:
	var a := _arena()
	# Fire from just inside the left border, all the way across the map. The
	# arena has interior walls, so the first one struck must be well short of
	# the far side.
	var from := Vector2(a.cell_size * 1.5, a.cell_size * 2.5)
	var to := Vector2(a.bounds().end.x, a.cell_size * 2.5)
	var r: Dictionary = a.cast_segment(from, to)

	_runner.check(r["hit"], _fail("a full-width shot hits something"))
	var point: Vector2 = r["point"]
	_runner.check(point.x > from.x, _fail("impact is ahead of the shooter"))
	_runner.check(point.x < to.x, _fail("impact is short of the far wall"))


func test_fast_arrow_cannot_tunnel_a_wall() -> void:
	var a := _arena()
	# A single tick's travel that starts open and ends open, with a wall in
	# between. Point-sampling the endpoints would report a clear path; this is
	# the exact bug the DDA walk exists to prevent.
	var y := a.cell_size * 0.5  # the solid top border row
	var from := Vector2(a.cell_size * 0.5, y)
	var to := Vector2(a.cell_size * 8.5, y)
	var r: Dictionary = a.cast_segment(from, to)
	_runner.check(r["hit"], _fail("a shot along a wall row is blocked"))


func test_conceals_only_inside_a_bush() -> void:
	var a := _arena()
	var bush_found := false
	for y in a.rows:
		for x in a.cols:
			if a.cell(x, y) == Arena.Cell.BUSH:
				bush_found = true
				_runner.check(a.conceals(a.cell_centre(x, y)), _fail("bush conceals"))
				break
		if bush_found:
			break

	_runner.check(bush_found, _fail("the arena contains bushes at all"))
	_runner.check(not a.conceals(a.spawn_points()[0]), _fail("open ground does not conceal"))


func test_world_spawns_player_and_targets_on_open_ground() -> void:
	var w := SimWorld.new()
	var c := w.arena.cell_at(w.player.position)
	_runner.check(not w.arena.is_solid(c.x, c.y), _fail("player spawns on open ground"))
	_runner.check(w.fighters.size() > 0, _fail("fighters are placed"))

	var bad := 0
	for d in w.fighters:
		var dc := w.arena.cell_at(d.position)
		if w.arena.is_solid(dc.x, dc.y):
			bad += 1
	_runner.check(bad == 0, _fail("no target spawns inside a wall"))


func test_actor_cannot_walk_through_a_wall() -> void:
	var w := SimWorld.new()
	var cmd := InputCommand.new()
	cmd.move = Vector2.LEFT

	# Drive hard into the left border for a full second.
	for _i in 60:
		w.tick(cmd, 1.0 / 60.0)

	var c := w.arena.cell_at(w.player.position)
	_runner.check(not w.arena.is_solid(c.x, c.y), _fail("player never ends up inside a wall"))
	_runner.check(w.player.position.x > 0.0, _fail("player stays inside the arena"))


func test_every_spawn_is_reachable_from_every_other() -> void:
	# A hand-edited map can seal a team behind stone with one stray '#', and
	# nothing else notices: the spawn-on-open-ground check is satisfied by a
	# walled-in pocket. A flood fill is the cheap way to rule it out, and the
	# arena format exists precisely so layouts get edited casually.
	var a := Arena.new()
	var spawns := a.spawn_points()
	_runner.check(spawns.size() >= 2, _fail("the arena has spawns to connect"))
	if spawns.size() < 2:
		return

	var start := a.cell_at(spawns[0])
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + step
			if seen.has(n) or not a.in_grid(n.x, n.y) or a.is_solid(n.x, n.y):
				continue
			seen[n] = true
			stack.append(n)

	var unreachable := 0
	for point: Vector2 in spawns:
		if not seen.has(a.cell_at(point)):
			unreachable += 1
	_runner.check(unreachable == 0, _fail("every spawn is reachable from every other"))
