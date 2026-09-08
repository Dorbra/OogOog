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

## One per fighter, index-matched to SimWorld.fighters. The player is simply
## fighters[0] — there is no separate player view any more, which is the view
## side of the Actor/Dummy unification.
var _fighter_views: Array[CatView] = []

## Bushes draw here rather than with the rest of the terrain, on a node ordered
## above the cats. See Terrain.draw_canopy.
var _canopy: Node2D

## Peer id -> the cat drawn for that remote player (LAN spike).
var _remote_views: Dictionary = {}

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

	for f in _world.fighters:
		var view := CatView.new()
		var is_player := f == _world.player
		# You are always ginger. Teammates and opponents carry the team colour,
		# so "which of these is me" never depends on reading a team colour.
		view.tint = Palette.CAT_PLAYER if is_player else _team_tint(f.team)
		view.show_bow = is_player
		view.z_index = 2 if is_player else 1
		add_child(view)
		_fighter_views.append(view)
		_chip.append(1.0)

	_world.fired.connect(
		func(_p: Vector2, _d: Vector2, draw: float) -> void:
			_fighter_views[0].punch(Tuning.get_value("squash_amount") * (0.5 + draw))
	)


## Remote players from the LAN spike, drawn as cats so a connection is obvious
## at a glance rather than being a number on a debug panel. Created on demand
## because peers arrive and leave at runtime.
##
## Separate from the fighter views on purpose: a remote peer is not yet a
## Fighter in this simulation. M3.3 makes the host authoritative and remote
## players become ordinary fighters, at which point this goes away.
func _sync_remote_views() -> void:
	for id: int in Net.peer_positions:
		if not _remote_views.has(id):
			var view := CatView.new()
			view.tint = Palette.CAT_REMOTE
			view.show_bow = false
			view.z_index = 1
			add_child(view)
			_remote_views[id] = view
		var remote: CatView = _remote_views[id]
		remote.position = Net.peer_positions[id]
		remote.radius = Tuning.get_value("fighter_radius")

	for id: int in _remote_views.keys():
		if not Net.peer_positions.has(id):
			_remote_views[id].queue_free()
			_remote_views.erase(id)


static func _team_tint(team: int) -> Color:
	return Palette.TEAM_A if team == 0 else Palette.TEAM_B


func _process(delta: float) -> void:
	_sync_remote_views()
	_sync_views(delta)
	_track_trails()
	queue_redraw()
	_canopy.queue_redraw()


func _draw_canopy() -> void:
	_terrain.draw_canopy(_canopy, _camera.view_rect(get_viewport_rect().size))


func _sync_views(delta: float) -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	for i in _fighter_views.size():
		var f: Fighter = _world.fighters[i]
		var view := _fighter_views[i]
		view.position = f.render_position(alpha)
		view.radius = f.radius
		view.flash = f.health.hit_flash
		view.aim = f.facing
		view.visible = f.alive() and _is_shown(f)

		if f == _world.player:
			view.draw_strength = _controls.draw_strength

		# Your own side fades in cover; an enemy in cover is not drawn at all
		# (see _is_shown). Fading a teammate rather than hiding them is
		# deliberate: losing track of your own team is not a mechanic, it is
		# just confusing, and in a game for a five-year-old that matters more
		# than the symmetry does.
		if f.team == _world.player.team:
			view.modulate.a = 0.55 if _world.arena.conceals(f.position) else 1.0

		# Chip bar chases the real health rather than snapping to it.
		var target := f.health.fraction()
		if target > _chip[i]:
			_chip[i] = target
		else:
			_chip[i] = maxf(_chip[i] - delta * 0.9, target)


## Whether the local player can see this fighter at all.
##
## The view asks the SIMULATION rather than reading Arena.conceals() itself, so
## the bots and the screen agree on who is hidden. A cat the AI has lost track
## of but that you can still see would make cover unreadable.
func _is_shown(f: Fighter) -> bool:
	if f.team == _world.player.team:
		return true
	return _world.can_see(_world.player.position, f)


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

	for i in _fighter_views.size():
		var f: Fighter = _world.fighters[i]
		# A health bar floating over an empty bush would give away the exact
		# thing the bush is hiding, so this asks the same question the sprite does.
		if f.alive() and _is_shown(f):
			_draw_health_bar(f, _chip[i])

	_draw_arrows(alpha)
	_draw_quiver_pips()


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
	# The real thing: speed x lifetime, uncapped. This used to be clamped to
	# 620px directly under a comment claiming the preview could not lie, while
	# an arrow actually flew 2320 — so the landing ring marked a spot the shot
	# blew straight past. arrow_lifetime is now tuned so the honest number fits
	# on screen, which is what made the clamp unnecessary rather than merely
	# dishonest.
	var reach := _world.player.bow.speed_for(strength) * Tuning.get_value("arrow_lifetime")
	var start := pos + dir * _world.player.radius
	var end := start + dir * reach

	# Stop at the first wall, using the same cast the arrows themselves use.
	# Without this the line crosses stone and promises a shot the arena refuses.
	var wall: Dictionary = _world.arena.cast_segment(start, end)
	var blocked: bool = wall["hit"]
	if blocked:
		end = wall["point"]

	var col := Palette.AIM.lerp(Color.WHITE, strength)
	if blocked:
		# A blocked line reads as blocked, rather than as a shorter good one.
		col = col.lerp(Palette.WALL_TOP, 0.55)

	var span := start.distance_to(end)
	var dots := maxi(3, int(span / 34.0))
	for i in dots:
		var t := float(i) / float(maxi(dots - 1, 1))
		var p := start.lerp(end, t)
		var fade := (1.0 - t) * (0.25 + 0.55 * strength)
		draw_circle(p, lerpf(4.5, 2.0, t), Color(col.r, col.g, col.b, fade))

	draw_arc(
		end,
		lerpf(10.0, 22.0, strength),
		0.0,
		TAU,
		20,
		Color(col.r, col.g, col.b, 0.5 + 0.4 * strength),
		2.5
	)


## Ammo under the hero, in WORLD space, where Brawl Stars puts it and where the
## eye already is mid-fight. It used to sit at the bottom of the screen, which
## meant looking away from the fight to count arrows.
func _draw_quiver_pips() -> void:
	var f := _world.player
	if not f.alive():
		return

	var capacity := f.bow.capacity()
	if capacity <= 0:
		return

	var pip_w := 9.0
	var pip_h := 5.0
	var gap := 3.0
	var total := capacity * pip_w + (capacity - 1) * gap
	var origin := f.position + Vector2(-total * 0.5, f.radius * 1.15)

	for i in capacity:
		var r := Rect2(origin + Vector2(i * (pip_w + gap), 0.0), Vector2(pip_w, pip_h))
		# Dark backing plus a light edge, so a pip reads against grass, dirt or
		# a cat standing behind it.
		draw_rect(r.grow(1.5), Color(0.05, 0.06, 0.08, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.18))
		if i < f.bow.quiver:
			draw_rect(r, Palette.ARROW)


func _draw_health_bar(f: Fighter, chip: float) -> void:
	# Sits just above the cat. Any further and it reads as a separate object
	# floating in space rather than as that target's health.
	var bar_width := f.radius * 1.6
	var origin := f.position + Vector2(-bar_width * 0.5, -f.radius * 2.05)
	draw_rect(Rect2(origin, Vector2(bar_width, 5.0)), Palette.HEALTH_BG)
	draw_rect(Rect2(origin, Vector2(bar_width * chip, 5.0)), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(origin, Vector2(bar_width * f.health.fraction(), 5.0)), Palette.HEALTH)
