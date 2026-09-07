class_name GameView
extends Node2D
## Renders the world: terrain, cats, arrows, aim preview, health bars.
##
## Pulled out of main.gd. Reads simulation state but never writes it — anything
## here can be deleted and the game still plays identically, just blind.

const TRAIL_SAMPLES := 8

var _world: SimWorld
var _terrain: Terrain
var _controls: TouchControls
var _camera: CameraRig

var _player_view: CatView
var _dummy_views: Array[CatView] = []

## Bushes draw here rather than with the rest of the terrain, on a node ordered
## above the cats. See Terrain.draw_canopy.
var _canopy: Node2D

# Recent positions per arrow, for trails. Indexed to match the arrow pool so no
# lookup or allocation happens per frame.
var _trails: Array[Array] = []

# Chip damage: a white bar that drains toward the real value, so a big hit reads
# as big. Without it every hit looks the same size regardless of damage.
var _chip: Array[float] = []


func setup(world: SimWorld, terrain: Terrain, controls: TouchControls, camera: CameraRig) -> void:
	_world = world
	_terrain = terrain
	_controls = controls
	_camera = camera


func _ready() -> void:
	for _i in _world.arrows.size():
		_trails.append([])

	_canopy = Node2D.new()
	_canopy.z_index = 3
	_canopy.draw.connect(_draw_canopy)
	add_child(_canopy)

	for _dummy in _world.dummies:
		var view := CatView.new()
		view.tint = Palette.CAT_ENEMY
		view.show_bow = false
		view.z_index = 1
		add_child(view)
		_dummy_views.append(view)
		_chip.append(1.0)

	_player_view = CatView.new()
	_player_view.tint = Palette.CAT_PLAYER
	_player_view.z_index = 2
	add_child(_player_view)

	_world.fired.connect(
		func(_p: Vector2, _d: Vector2, draw: float) -> void:
			_player_view.punch(Tuning.get_value("squash_amount") * (0.5 + draw))
	)


func _process(delta: float) -> void:
	_sync_views(delta)
	_track_trails()
	queue_redraw()
	_canopy.queue_redraw()


func _draw_canopy() -> void:
	_terrain.draw_canopy(_canopy, _camera.view_rect(get_viewport_rect().size))


func _sync_views(delta: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	_player_view.position = _world.player.render_position(alpha)
	_player_view.radius = _world.player.radius
	_player_view.aim = _world.player.facing
	_player_view.draw_strength = _controls.draw_strength

	# Fading in cover is the only visible effect of concealment until there are
	# opponents to hide from. Partial rather than invisible: you still need to
	# see yourself to aim.
	var hidden := _world.arena.conceals(_world.player.position)
	_player_view.modulate.a = 0.55 if hidden else 1.0

	for i in _dummy_views.size():
		var dummy: Dummy = _world.dummies[i]
		var view := _dummy_views[i]
		view.position = dummy.position
		view.radius = dummy.radius
		view.flash = dummy.health.hit_flash
		view.visible = dummy.alive()

		# Chip bar chases the real health rather than snapping to it.
		var target := dummy.health.fraction()
		if target > _chip[i]:
			_chip[i] = target
		else:
			_chip[i] = maxf(_chip[i] - delta * 0.9, target)


func _track_trails() -> void:
	for i in _world.arrows.size():
		var arrow: Arrow = _world.arrows[i]
		var trail: Array = _trails[i]
		if not arrow.active:
			if not trail.is_empty():
				trail.clear()
			continue
		trail.append(arrow.position)
		while trail.size() > TRAIL_SAMPLES:
			trail.pop_front()


func _draw() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	_terrain.draw_into(self, _camera.view_rect(get_viewport_rect().size))
	_draw_aim_preview(alpha)

	for i in _dummy_views.size():
		var dummy: Dummy = _world.dummies[i]
		if dummy.alive():
			_draw_health_bar(dummy, _chip[i])

	_draw_arrows(alpha)


func _draw_arrows(alpha: float) -> void:
	var width := Tuning.get_value("arrow_width")
	var length := Tuning.get_value("arrow_length")
	var trail_len := int(Tuning.get_value("trail_length"))

	for i in _world.arrows.size():
		var arrow: Arrow = _world.arrows[i]
		if not arrow.active:
			continue

		# The trail also makes a fast arrow readable — at full draw an arrow
		# crosses a good fraction of the screen each frame.
		if trail_len > 0:
			var trail: Array = _trails[i]
			var start: int = maxi(0, trail.size() - trail_len)
			for t in range(start, trail.size() - 1):
				var fade := float(t - start + 1) / float(maxi(trail.size() - start, 1))
				draw_line(
					trail[t],
					trail[t + 1],
					Color(Palette.ARROW.r, Palette.ARROW.g, Palette.ARROW.b, fade * 0.35),
					width * fade
				)

		var tip := arrow.render_position(alpha)
		var dir := arrow.velocity.normalized()
		draw_line(tip - dir * length, tip, Palette.ARROW, width)
		draw_line(tip - dir * (length * 0.25), tip, Palette.ARROW_TIP, width)


## Dotted trajectory with a landing reticle while drawing.
##
## The most recognisably Brawl Stars element in the game, and it directly
## answers the earlier "every twitch ruins the aim, hard to hit" complaint:
## it turns aiming from guesswork into something you can see before committing.
func _draw_aim_preview(alpha: float) -> void:
	if not _controls.is_drawing or Tuning.get_value("reticle_enabled") < 0.5:
		return

	var pos := _world.player.render_position(alpha)
	var dir := _world.player.facing
	if dir == Vector2.ZERO:
		return

	var strength := _controls.draw_strength
	# Range shown is the real thing: speed x lifetime, so the preview cannot
	# lie about where the arrow actually dies.
	var reach := _world.player.bow.speed_for(strength) * Tuning.get_value("arrow_lifetime")
	reach = minf(reach, 620.0)

	var start := pos + dir * _world.player.radius
	var col := Palette.AIM.lerp(Color.WHITE, strength)
	var dots := 14
	for i in dots:
		var t := float(i) / float(dots - 1)
		var p := start + dir * reach * t
		var fade := (1.0 - t) * (0.25 + 0.55 * strength)
		draw_circle(p, lerpf(4.0, 2.0, t), Color(col.r, col.g, col.b, fade))

	var end := start + dir * reach
	draw_arc(
		end,
		lerpf(10.0, 22.0, strength),
		0.0,
		TAU,
		20,
		Color(col.r, col.g, col.b, 0.5 + 0.4 * strength),
		2.5
	)


func _draw_health_bar(dummy: Dummy, chip: float) -> void:
	# Sits just above the cat. Any further and it reads as a separate object
	# floating in space rather than as that target's health.
	var bar_width := dummy.radius * 1.6
	var origin := dummy.position + Vector2(-bar_width * 0.5, -dummy.radius * 2.05)
	draw_rect(Rect2(origin, Vector2(bar_width, 5.0)), Palette.HEALTH_BG)
	draw_rect(Rect2(origin, Vector2(bar_width * chip, 5.0)), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(origin, Vector2(bar_width * dummy.health.fraction(), 5.0)), Palette.HEALTH)
