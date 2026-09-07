extends SceneTree
## Headless host/client probe, used by tests/test_net_loopback.sh.
##
## Real LAN behaviour cannot be tested from a build machine — there is no second
## phone here. What CAN be tested is everything upstream of the physical
## network: that a server starts, that a client connects, that RPCs arrive, and
## that positions actually move from one process into the other. Two Godot
## processes over 127.0.0.1 exercise the whole path except the radio.
##
## That catches the ordinary failures — a renamed API, a wrong RPC annotation, a
## peer never polled — and leaves exactly one class of question for real
## hardware: does this router carry the packets. Which is the question the spike
## is for.
##
##   godot --headless --script tools/net_probe.gd -- host
##   godot --headless --script tools/net_probe.gd -- join 127.0.0.1

const TIMEOUT_SECONDS := 25.0
const MOVE_SPEED := 120.0
const SETTLE_SECONDS := 4.0

var _link: NetLink
var _mode := ""
var _address := "127.0.0.1"
var _elapsed := 0.0
var _started := false
var _connected_at := 0.0
var _saw_peer := false
var _saw_position := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("net_probe: expected 'host' or 'join <address>'")
		quit(2)
		return

	_mode = args[0]
	if args.size() > 1:
		_address = args[1]

	_link = NetLink.new()
	root.add_child(_link)
	# Connecting is deferred to the first frame on purpose: during _initialize()
	# the node is in the tree but the MultiplayerAPI is not live yet, and calling
	# host() here fails in a way the engine reports as a null-instance
	# assignment. This is the exact bug this test found on its first run.


func _process(delta: float) -> bool:
	_elapsed += delta

	if not _started:
		_started = true
		var ok := _link.host() if _mode == "host" else _link.join(_address)
		if not ok:
			push_error("net_probe: %s failed: %s" % [_mode, _link.last_error])
			quit(1)
			return true
		print("net_probe: %s started (id=%d)" % [_mode, _link.local_id()])

	# Move, so the position being received is demonstrably changing rather than
	# a zero that would look identical to nothing having arrived at all.
	_link.set_local_position(Vector2(_elapsed * MOVE_SPEED, _elapsed * MOVE_SPEED))

	if not _link.peer_ids().is_empty() and not _saw_peer:
		_saw_peer = true
		# Settle is timed from the CONNECTION, not from process start. The host
		# is launched several seconds before the client, so timing it from start
		# left the host barely a second of connected life — not enough for a
		# ping round trip, which made a timing artefact look like a broken ping.
		_connected_at = _elapsed
		print("net_probe: peer connected, peers=%s" % str(_link.peer_ids()))

	for id: int in _link.peer_positions:
		var pos: Vector2 = _link.peer_positions[id]
		if pos != Vector2.ZERO and not _saw_position:
			_saw_position = true
			print("net_probe: received position from %d: %s" % [id, str(pos)])

	# Hold on for a few seconds before reporting, so the ping printed is a real
	# measurement rather than ENet's 500 ms seed value.
	if _saw_peer and _saw_position and (_elapsed - _connected_at) > SETTLE_SECONDS:
		print("net_probe: %s OK (ping=%dms)" % [_mode, _link.worst_ping_ms()])
		_link.shutdown()
		quit(0)
		return true

	if _elapsed > TIMEOUT_SECONDS:
		push_error(
			(
				"net_probe: %s timed out after %.0fs (peer=%s position=%s)"
				% [_mode, _elapsed, str(_saw_peer), str(_saw_position)]
			)
		)
		_link.shutdown()
		quit(1)
		return true

	return false
