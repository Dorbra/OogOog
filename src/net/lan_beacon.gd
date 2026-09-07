class_name LanBeacon
extends Node
## Finds games on the local network by UDP broadcast, so nobody has to type an
## IP address.
##
## That is not a convenience. The players are 5 and 10 years old; "ask the adult
## for the host's IP" is not a workable join flow, and a game they cannot start
## by themselves is a game they will not start.
##
## The host shouts on the broadcast address once a second; everyone else listens
## and collects what they hear. Hosts vanish from the list when they stop
## shouting.
##
## THE RISK THIS SPIKE IS TESTING: plenty of consumer routers drop broadcast
## traffic between wireless clients ("AP isolation", or a guest network). When
## that happens ENet still connects fine by direct address, but discovery finds
## nothing. So the debug panel keeps a manual-address path as the fallback, and
## reports which one worked — because "it didn't find anything" and "it couldn't
## connect" are different problems with different fixes.

signal hosts_changed

## NetLink.GAME_PORT + 1. Separate socket, separate protocol, same family.
const BEACON_PORT := 7778
const MAGIC := "OOGOOG1"
const BROADCAST_INTERVAL := 1.0

## A host not heard from for this long is treated as gone.
const HOST_TIMEOUT := 3.5

## address -> {"name": String, "last_seen": float (seconds since start)}
var hosts: Dictionary = {}

var _socket: PacketPeerUDP = null
var _broadcasting := false
var _accum: float = 0.0
var _clock: float = 0.0


## Starts shouting. Called by the host.
func start_broadcasting() -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	var err := _socket.set_dest_address("255.255.255.255", BEACON_PORT)
	if err != OK:
		push_error("LanBeacon: set_dest_address failed: %s" % error_string(err))
		_socket = null
		return false
	_broadcasting = true
	_accum = BROADCAST_INTERVAL  # shout immediately rather than after a second
	return true


## Starts listening. Called by everyone looking for a game.
func start_listening() -> bool:
	stop()
	_socket = PacketPeerUDP.new()
	var err := _socket.bind(BEACON_PORT)
	if err != OK:
		push_error("LanBeacon: bind(%d) failed: %s" % [BEACON_PORT, error_string(err)])
		_socket = null
		return false
	_broadcasting = false
	hosts.clear()
	hosts_changed.emit()
	return true


func stop() -> void:
	if _socket != null:
		_socket.close()
		_socket = null
	_broadcasting = false


func active() -> bool:
	return _socket != null


## Addresses currently being advertised, most recently heard first.
func host_addresses() -> Array:
	var out: Array = hosts.keys()
	out.sort_custom(
		func(a: String, b: String) -> bool:
			return float(hosts[a]["last_seen"]) > float(hosts[b]["last_seen"])
	)
	return out


func _process(delta: float) -> void:
	_clock += delta
	if _socket == null:
		return

	if _broadcasting:
		_tick_broadcast(delta)
	else:
		_tick_listen()


func _tick_broadcast(delta: float) -> void:
	_accum += delta
	if _accum < BROADCAST_INTERVAL:
		return
	_accum = 0.0
	# Deliberately tiny and human-readable: a spike whose packets can be read
	# with tcpdump is a spike that can be debugged from the other side.
	var payload := "%s|%s" % [MAGIC, OS.get_model_name()]
	_socket.put_packet(payload.to_utf8_buffer())


func _tick_listen() -> void:
	var changed := false

	while _socket.get_available_packet_count() > 0:
		var raw := _socket.get_packet().get_string_from_utf8()
		var from := _socket.get_packet_ip()
		if not raw.begins_with(MAGIC) or from.is_empty():
			continue

		var parts := raw.split("|")
		var label: String = parts[1] if parts.size() > 1 else from
		if not hosts.has(from):
			changed = true
		hosts[from] = {"name": label, "last_seen": _clock}

	# Expire hosts that have gone quiet, so a closed game does not linger in the
	# list and offer a connection that will fail.
	for address: String in hosts.keys():
		if _clock - float(hosts[address]["last_seen"]) > HOST_TIMEOUT:
			hosts.erase(address)
			changed = true

	if changed:
		hosts_changed.emit()
