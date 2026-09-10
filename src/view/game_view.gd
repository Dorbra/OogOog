class_name GameView
extends Node2D
## Renders the world: terrain, cats, bullets, aim preview, health bars.
##
## Pulled out of main.gd. Reads simulation state but never writes it — anything
## here can be deleted and the game still plays identically, just blind.

## The ammo row spans this many radii, whatever the magazine size.
const MAGAZINE_ROW_SPAN := 3.2

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

# Recent positions per bullet, for trails. Indexed to match the bullet pool so no
# lookup or allocation happens per frame.
var _trails: Array[Array] = []

# Chip damage: a white bar that drains toward the real value, so a big hit reads
# as big. Without it every hit looks the same size regardless of damage.
var _chip: Array[float] = []


## Point the view at a world. Safe to call again with a NEW world between
## rounds: the cat views are index-matched to SimWorld.fighters, so a match with
## a different team size would otherwise leave this indexing a roster that no
## longer exists.
func setup(world: SimWorld, terrain: Terrain, controls: TouchControls, camera: CameraRig) -> void:
	_world = world
	_terrain = terrain
	_controls = controls
	_camera = camera
	if is_node_ready():
		_build()


func _ready() -> void:
	_build()


func _build() -> void:
	# Detach immediately rather than relying on queue_free(), which is deferred:
	# the old cats would otherwise still be children for a frame and draw over
	# the new roster.
	for view in _fighter_views:
		remove_child(view)
		view.queue_free()
	_fighter_views.clear()
	_chip.clear()
	_trails.clear()
	if _canopy != null:
		remove_child(_canopy)
		_canopy.queue_free()

	for _i in _world.bullets.size():
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
		view.fighter_class = f.fighter_class
		# Every cat's gun is drawn now, not just yours. It used to be yours alone
		# because the gun carried nothing but your own aim; with classes it also
		# carries WHAT that cat is, and "the thing running at me is a shotgun"
		# has to be readable without a word of text on screen.
		view.show_gun = true
		view.z_index = 2 if is_player else 1
		add_child(view)
		_fighter_views.append(view)
		_chip.append(1.0)

	_world.fired.connect(
		func(_p: Vector2, _d: Vector2) -> void:
			_fighter_views[0].punch(Tuning.get_value("squash_amount"))
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
			view.show_gun = false
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


## Caltrops, drawn on the GROUND layer so cats walk over them rather than
## behind them. A hazard that renders on top of the fighter standing in it reads
## as a thing in the air, and the whole mechanic is that it is underfoot.
func _draw_hazards() -> void:
	for hazard in _world.hazards:
		if not hazard.active:
			continue
		# Fades out as it expires, so "this is about to stop hurting" is visible
		# rather than something you have to have been counting.
		var fade: float = clampf(
			hazard.life / maxf(Tuning.get_value("caltrops_time"), 0.01), 0.0, 1.0
		)
		var tint := Palette.ARROW
		draw_circle(hazard.position, hazard.radius, Color(tint.r, tint.g, tint.b, 0.10 * fade))
		draw_arc(
			hazard.position,
			hazard.radius,
			0.0,
			TAU,
			36,
			Color(tint.r, tint.g, tint.b, 0.55 * fade),
			3.0
		)
		# A scatter of spikes, placed off the hazard's own position so a patch
		# looks the same every frame instead of shimmering.
		var seed_x := int(hazard.position.x)
		for i in 7:
			var angle := TAU * float((i * 7 + seed_x) % 7) / 7.0
			var at := hazard.position + Vector2(cos(angle), sin(angle)) * hazard.radius * 0.55
			draw_circle(at, 3.5, Color(tint.r, tint.g, tint.b, 0.8 * fade))


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
	for i in _world.bullets.size():
		var bullet: Bullet = _world.bullets[i]
		var trail: Array = _trails[i]
		if not bullet.active:
			if not trail.is_empty():
				trail.clear()
			continue
		trail.append(bullet.position)
		while trail.size() > TRAIL_SAMPLES:
			trail.pop_front()


func _draw() -> void:
	var alpha := Engine.get_physics_interpolation_fraction()

	_terrain.draw_into(self, _camera.view_rect(get_viewport_rect().size))
	# Between the ground and the aim line: caltrops are ON the terrain, and the
	# aim preview has to stay the topmost thing in the world layer because it is
	# the one element the player is actively steering.
	_draw_hazards()
	_draw_aim_preview(alpha)

	for i in _fighter_views.size():
		var f: Fighter = _world.fighters[i]
		# A health bar floating over an empty bush would give away the exact
		# thing the bush is hiding, so this asks the same question the sprite does.
		if f.alive() and _is_shown(f):
			_draw_health_bar(f, _chip[i])

	_draw_bullets(alpha)
	_draw_magazine_pips()
	_draw_charge_ring()


func _draw_bullets(alpha: float) -> void:
	var width := Tuning.get_value("bullet_width")
	var length := Tuning.get_value("bullet_length")
	var trail_len := int(Tuning.get_value("trail_length"))

	for i in _world.bullets.size():
		var bullet: Bullet = _world.bullets[i]
		if not bullet.active:
			continue

		# The trail also makes a fast bullet readable — at 1400 px/s a bullet
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

		var tip := bullet.render_position(alpha)
		var dir := bullet.velocity.normalized()
		draw_line(tip - dir * length, tip, Palette.ARROW, width)
		draw_line(tip - dir * (length * 0.25), tip, Palette.ARROW_TIP, width)


## Dotted trajectory with a landing reticle while drawing.
##
## The most recognisably Brawl Stars element in the game, and it directly
## answers the earlier "every twitch ruins the aim, hard to hit" complaint:
## it turns aiming from guesswork into something you can see before committing.
## How strongly to draw the line of fire: 1.0 while pointing, dimmer while not.
##
## Static and taking the flag as an argument so the decision can be asserted
## headlessly. The alternative was proving it through a rendered frame, and a
## capture cannot show this at all — no render mode has a thumb on the screen —
## so the choice was a testable function or no gate.
static func aim_line_strength(is_aiming: bool) -> float:
	if Tuning.get_value("reticle_enabled") < 0.5:
		return 0.0
	if is_aiming:
		return 1.0
	return clampf(Tuning.get_value("aim_line_idle_alpha"), 0.0, 1.0)


## Drawn whether or not a thumb is down.
##
## It used to return early unless a thumb was down, so the line vanished the moment
## you released — and since the aim vanished with it, there was nothing to draw.
## Now the aim persists, so the line persists too, dimmed: at any moment you can
## see the shot you would take, which is what "keep a line-of-fire" means on a
## screen. The bright version still marks the moment you are actively pointing.
func _draw_aim_preview(alpha: float) -> void:
	if Tuning.get_value("reticle_enabled") < 0.5:
		return

	# Dimmed when the thumb is up. The assist and the wall cast below run in BOTH
	# states on purpose: a faint line that lies is worse than no faint line.
	var strength := aim_line_strength(_controls.is_aiming)
	if strength <= 0.0:
		return

	var pos := _world.player.render_position(alpha)
	var dir := _world.player.facing
	if dir == Vector2.ZERO:
		return

	# The same nudge the shot itself will get. Without this the line is up to
	# aim_assist_deg away from where the bullet goes — and because the assist
	# LEADS a moving target, the gap it hides is exactly the interesting part:
	# the preview would point at the cat while the bullet flew in front of it.
	#
	# A preview that shows something other than the shot is the M3.1c bug and
	# ADR-0019 in one: what is drawn has to be what happens.
	dir = _world.assisted_aim(_world.player, dir)

	# The real thing: speed x lifetime, uncapped. This used to be clamped to
	# 620px directly under a comment claiming the preview could not lie, while
	# the projectile actually flew 2320 — so the landing ring marked a spot the
	# shot blew straight past. bullet_lifetime is tuned so the honest number fits
	# on screen, which is what made the clamp unnecessary rather than merely
	# dishonest.
	#
	# One length, one colour, every time. The line used to grow and brighten with
	# the draw; with every shot identical, a preview that still varied would be
	# animating information that no longer exists.
	var reach := _world.player.gun.reach()
	var start := pos + dir * _world.player.radius
	var end := start + dir * reach

	# Stop at the first wall, using the same cast the bullets themselves use.
	# Without this the line crosses stone and promises a shot the arena refuses.
	var wall: Dictionary = _world.arena.cast_segment(start, end)
	var blocked: bool = wall["hit"]
	if blocked:
		end = wall["point"]

	var col := Palette.AIM.lerp(Color.WHITE, 0.65)
	if blocked:
		# A blocked line reads as blocked, rather than as a shorter good one.
		col = col.lerp(Palette.WALL_TOP, 0.55)

	var span := start.distance_to(end)
	var dots := maxi(3, int(span / 34.0))
	for i in dots:
		var t := float(i) / float(maxi(dots - 1, 1))
		var p := start.lerp(end, t)
		var fade := (1.0 - t) * 0.7 * strength
		draw_circle(p, lerpf(4.5, 2.0, t), Color(col.r, col.g, col.b, fade))

	draw_arc(end, 18.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.8 * strength), 2.5)


## How wide one ammo pip may be, so the row never outgrows the cat.
##
## The width used to be a flat 9 px per pip, which meant the ROW grew with the
## magazine: at 5 rounds it was 57 px against a 58 px cat, and doubling the
## magazine to 10 took it to 117 px — a bar twice as wide as the animal it
## belongs to, reaching across the arena floor. Pips shrink now instead, so the
## row stays put and only gets denser.
##
## Static and pure so the constraint can be asserted rather than eyeballed in a
## capture — magazine_size is a slider that goes to 12.
static func magazine_pip_width(capacity: int, radius: float, gap: float) -> float:
	if capacity <= 0:
		return 0.0
	var room := radius * MAGAZINE_ROW_SPAN - float(capacity - 1) * gap
	return clampf(room / float(capacity), 1.0, 9.0)


## Ammo under the hero, in WORLD space, where Brawl Stars puts it and where the
## eye already is mid-fight. It used to sit at the bottom of the screen, which
## meant looking away from the fight to count rounds.
func _draw_magazine_pips() -> void:
	var f := _world.player
	if not f.alive():
		return

	var capacity := f.gun.capacity()
	if capacity <= 0:
		return

	var pip_h := 5.0
	var gap := 3.0
	var pip_w := magazine_pip_width(capacity, f.radius, gap)
	var total := capacity * pip_w + (capacity - 1) * gap
	var origin := f.position + Vector2(-total * 0.5, f.radius * 1.15)

	for i in capacity:
		var r := Rect2(origin + Vector2(i * (pip_w + gap), 0.0), Vector2(pip_w, pip_h))
		# Dark backing plus a light edge, so a pip reads against grass, dirt or
		# a cat standing behind it.
		draw_rect(r.grow(1.5), Color(0.05, 0.06, 0.08, 0.6))
		draw_rect(r, Color(1, 1, 1, 0.18))
		if i < f.gun.magazine:
			draw_rect(r, Palette.ARROW)


## Ability charge, as an arc around the player's feet.
##
## In WORLD space beside the ammo pips for the same reason they are: counting
## your charge must not mean looking away from the fight. An arc rather than a
## bar because it is unmistakably a different quantity from the ammo row two
## pixels below it, and because "the ring closed" is readable at a glance by
## somebody who cannot read a number.
func _draw_charge_ring() -> void:
	var f := _world.player
	if not f.alive():
		return

	var centre := f.position
	var radius := f.radius * 1.34
	# The empty track, so the ring is visibly a thing that FILLS rather than
	# appearing from nowhere at 100%.
	draw_arc(centre, radius, 0.0, TAU, 44, Color(0.05, 0.06, 0.08, 0.45), 4.0)
	if f.charge <= 0.0:
		return

	# Starts at the top and sweeps clockwise, which is the direction every dial
	# a child has seen turns.
	var start := -PI * 0.5
	var colour := Palette.ARROW if f.charge >= 1.0 else Palette.ARROW.darkened(0.25)
	draw_arc(centre, radius, start, start + TAU * f.charge, 44, colour, 4.0)


func _draw_health_bar(f: Fighter, chip: float) -> void:
	# Sits just above the cat. Any further and it reads as a separate object
	# floating in space rather than as that target's health.
	var bar_width := f.radius * 1.6
	var origin := f.position + Vector2(-bar_width * 0.5, -f.radius * 2.05)
	draw_rect(Rect2(origin, Vector2(bar_width, 5.0)), Palette.HEALTH_BG)
	draw_rect(Rect2(origin, Vector2(bar_width * chip, 5.0)), Color(1, 1, 1, 0.55))
	draw_rect(Rect2(origin, Vector2(bar_width * f.health.fraction(), 5.0)), Palette.HEALTH)
