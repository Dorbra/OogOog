extends SceneTree
## Headless host/client probe, used by tests/test_net_loopback.sh.
##
## Real LAN behaviour cannot be tested from a build machine — there is no second
## phone here. What CAN be tested is everything upstream of the physical
## network, and since `feat/lan` that is no longer "a Vector2 crossed". It is
## THE WHOLE ROUND TRIP:
##
##     client thumbs -> InputCommand over the wire
##                   -> the HOST's simulation acts on it
##                   -> the host's state comes back as a Snapshot
##                   -> the client draws a thing it did not decide
##
## Every link in that chain breaks differently and silently. An @rpc annotation
## with the wrong mode delivers nothing; a seat never registered drops commands
## on the floor; a snapshot whose length disagrees with its header is refused
## wholesale. None of those produce an error anybody sees on a phone — they
## produce a game where the other cats stand still, which is indistinguishable
## from a router problem. This is the gate that tells those apart.
##
## THE PROOF IS THAT NOBODY ELSE COULD HAVE DONE IT. Every controller on the
## host is nulled except the one seat the client drives, so the host's world is
## incapable of producing a bullet on its own. A bullet existing at all is the
## client's command having crossed, been acted on by the authority, and come
## back — there is no other path to one.
##
##   godot --headless --script tools/net_probe.gd -- host
##   godot --headless --script tools/net_probe.gd -- join 127.0.0.1

const TIMEOUT_SECONDS := 30.0
const SETTLE_SECONDS := 4.0

## Delay before the host seats the peer. The connection needs a moment to leave
## CONNECTING, and `_begin` is a reliable RPC that would be dropped before it.
const SEAT_DELAY := 0.75

var _net: Node
var _lan: Node

## Untyped, and loaded at runtime in _wake() rather than named here.
##
## `--script` compiles this file AND EVERYTHING IT STATICALLY REFERENCES before
## the autoloads exist, so a bare `SimWorld` type annotation drags in
## sim_world.gd, which says `Tuning.get_value(...)`, which does not compile yet:
## "Identifier not found: Tuning". The whole file then fails to load and the
## failure names sim_world.gd rather than the annotation that caused it.
##
## load() defers all of that to the first frame, when the autoloads are up. It
## is the same dodge tools/screenshot.gd makes by loading main.tscn instead of
## instancing the scene's types.
var _world = null
var _cmd = null
var _empty = null

var _mode := ""
var _address := "127.0.0.1"
var _elapsed := 0.0
var _started := false
var _connected_at := 0.0
var _saw_peer := false
var _seated := false
var _saw_bullet := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("net_probe: expected 'host' or 'join <address>'")
		quit(2)
		return

	_mode = args[0]
	if args.size() > 1:
		_address = args[1]

	# EVERYTHING is deferred to the first frame, and both halves of that have
	# already cost a debugging session each.
	#
	# The MultiplayerAPI is not live during _initialize(), so host() here fails
	# as "assignment on a null instance" rather than as anything a reader could
	# act on — the bug this test found on its own first run.
	#
	# And the autoloads are not in the tree yet either: get_node("/root/Net")
	# returns null with "Can't use get_node() with absolute paths from outside
	# the active scene tree". They must also be reached BY PATH rather than by
	# name, because this file runs as `--script` and is compiled before they are
	# registered, so a bare `Lan` is a compile error. Nothing under src/ needs
	# either dodge, which is why neither is obvious from reading the rest.


## Looks up the autoloads and builds the world. First frame only.
func _wake() -> bool:
	_net = root.get_node_or_null("/root/Net")
	_lan = root.get_node_or_null("/root/Lan")
	if _net == null or _lan == null:
		push_error("net_probe: the Net/Lan autoloads are missing")
		quit(2)
		return false

	var world_script := load("res://src/sim/sim_world.gd")
	var command_script := load("res://src/sim/input_command.gd")
	if world_script == null or command_script == null:
		push_error("net_probe: could not load the simulation scripts")
		quit(2)
		return false
	_cmd = command_script.new()
	_empty = command_script.new()

	# Both ends build the SAME world, because Snapshot.apply() refuses a payload
	# whose fighter count disagrees with the world receiving it — correctly, and
	# the symptom would be a silent nothing.
	_world = world_script.new()
	# The literal, for the same reason the types are loaded: naming
	# MatchState.Phase.LIVE here would pull match_state.gd into this file's
	# compile. tools/screenshot.gd writes the same 2 for the same reason.
	_world.match_state.phase = 2
	for f in _world.fighters:
		f.controller = null
	_lan.world = _world
	return true


func _process(delta: float) -> bool:
	_elapsed += delta

	if not _started:
		_started = true
		if not _wake():
			return true
		var ok: bool = _net.host() if _mode == "host" else _net.join(_address)
		if not ok:
			push_error("net_probe: %s failed: %s" % [_mode, _net.last_error])
			quit(1)
			return true
		print("net_probe: %s started (id=%d)" % [_mode, _net.local_id()])

	if not _net.peer_ids().is_empty() and not _saw_peer:
		_saw_peer = true
		# Settle is timed from the CONNECTION, not from process start. The host
		# is launched several seconds before the client, so timing it from start
		# left the host barely a second of connected life — not enough for a
		# ping round trip, which made a timing artefact look like a broken ping.
		_connected_at = _elapsed
		print("net_probe: peer connected, peers=%s" % str(_net.peer_ids()))

	if _mode == "host":
		_tick_host(delta)
	else:
		_tick_client(delta)

	if _saw_peer and _saw_bullet and (_elapsed - _connected_at) > SETTLE_SECONDS:
		print("net_probe: %s OK (ping=%dms)" % [_mode, _net.worst_ping_ms()])
		_net.shutdown()
		quit(0)
		return true

	if _elapsed > TIMEOUT_SECONDS:
		push_error(
			(
				"net_probe: %s timed out after %.0fs (peer=%s seated=%s bullet=%s)"
				% [_mode, _elapsed, str(_saw_peer), str(_seated), str(_saw_bullet)]
			)
		)
		_net.shutdown()
		quit(1)
		return true

	return false


## The authority. Seats the peer, runs the real simulation, ships snapshots.
func _tick_host(delta: float) -> void:
	if _saw_peer and not _seated and (_elapsed - _connected_at) > SEAT_DELAY:
		for id: int in _net.peer_ids():
			_lan.roster[id] = 0
		_lan.seat_everyone()
		_seated = true
		print("net_probe: seated %d peer(s) -> %s" % [_lan.roster.size(), str(_lan.seats)])

	# The empty command: the HOST is not playing. Every controller is null and
	# the host's own thumbs send nothing, so this world has no way to produce a
	# bullet other than the seat the client is driving.
	_world.tick(_empty, delta)
	_lan.pump(delta)

	if not _saw_bullet and _live_bullets() > 0:
		_saw_bullet = true
		print("net_probe: the client's command reached the authority and spawned a bullet")


## The client. Sends thumbs, draws what comes back, decides nothing.
func _tick_client(delta: float) -> void:
	# Aimed and firing every tick. RemoteController consumes the edge at the
	# tick boundary and Gun.consume() paces the rest, so this is a held trigger
	# rather than an impossible rate — exactly what a bot does.
	_cmd.move = Vector2.ZERO
	_cmd.aim = Vector2.RIGHT
	_cmd.fire = true
	_lan.record_local(_cmd)

	_world.tick_replica(delta)
	_lan.pump(delta)

	# A bullet in THIS world can only have arrived in a snapshot: tick_replica()
	# has no code path that creates one.
	if not _saw_bullet and _live_bullets() > 0:
		_saw_bullet = true
		print("net_probe: a snapshot arrived carrying a bullet this process did not simulate")


func _live_bullets() -> int:
	var n := 0
	for b in _world.bullets:
		if b.active:
			n += 1
	return n
