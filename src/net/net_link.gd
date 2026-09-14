class_name NetLink
extends Node
## Local-network transport: host, join, and share state between phones.
##
## SPIKE (M3.0). The question this exists to answer is not "can Godot do
## networking" — it is "does ENet work between these actual phones on this
## actual home router, and what is the round-trip latency". Nothing in this
## environment can answer that: there is no second device here. So this ships to
## real hardware and REPORTS ON ITSELF, which is the same reason the debug
## overlay exists at all.
##
## For the spike every peer publishes its own position and everyone draws
## everyone. That is deliberately NOT the architecture the real game will use —
## M3.3 makes the host authoritative, with clients sending InputCommand and the
## host broadcasting the simulation. Proving the transport first keeps the two
## questions separate: this one is about the network, that one is about the
## simulation.
##
## Latency is the finding that decides M3.3's design. Under roughly 50 ms,
## host-authoritative with no prediction and no rollback is sufficient, which
## removes an enormous amount of work. That is a claim worth measuring rather
## than assuming.

signal peers_changed
signal status_changed

enum Role { OFFLINE, HOST, CLIENT }

## Kept in step with LanBeacon.BEACON_PORT, which is this + 1.
const GAME_PORT := 7777
const MAX_PEERS := 5

## How often each peer probes round-trip time.
const PING_INTERVAL := 1.0

var role: Role = Role.OFFLINE
var last_error: String = ""

var _peer: ENetMultiplayerPeer = null
var _ping_accum: float = 0.0

## Peer id -> last measured round-trip in milliseconds.
var _pings: Dictionary = {}


func _ready() -> void:
	var mp := _api()
	if mp == null:
		push_error("NetLink: no MultiplayerAPI — the node is not in a live tree")
		return
	mp.peer_connected.connect(_on_peer_connected)
	mp.peer_disconnected.connect(_on_peer_disconnected)
	mp.connection_failed.connect(_on_connection_failed)
	mp.server_disconnected.connect(_on_server_disconnected)


## `multiplayer` is null until the node is genuinely inside a running tree —
## notably during a SceneTree script's _initialize(), which is early enough that
## the engine reports it as "assignment on a null instance" rather than
## something a reader could act on. Every access goes through here so the
## failure names itself.
func _api() -> MultiplayerAPI:
	if not is_inside_tree():
		return null
	return multiplayer


## Starts hosting. Returns false and sets `last_error` on failure — the phone
## has no console, so an error nobody can read is the same as a silent one.
func host() -> bool:
	shutdown()

	var mp := _api()
	if mp == null:
		last_error = "not in a live scene tree yet"
		status_changed.emit()
		return false

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_PEERS)
	if err != OK:
		last_error = "create_server failed: %s" % error_string(err)
		push_error("NetLink: %s" % last_error)
		status_changed.emit()
		return false

	_peer = peer
	mp.multiplayer_peer = peer
	role = Role.HOST
	last_error = ""
	status_changed.emit()
	return true


func join(address: String) -> bool:
	shutdown()

	var mp := _api()
	if mp == null:
		last_error = "not in a live scene tree yet"
		status_changed.emit()
		return false

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, GAME_PORT)
	if err != OK:
		last_error = "create_client(%s) failed: %s" % [address, error_string(err)]
		push_error("NetLink: %s" % last_error)
		status_changed.emit()
		return false

	_peer = peer
	mp.multiplayer_peer = peer
	role = Role.CLIENT
	last_error = ""
	status_changed.emit()
	return true


func shutdown() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	# Assigning null rather than leaving a closed peer in place: the
	# MultiplayerAPI keeps polling whatever it holds.
	var mp := _api()
	if mp != null:
		mp.multiplayer_peer = null
	role = Role.OFFLINE
	_pings.clear()
	status_changed.emit()
	peers_changed.emit()


func online() -> bool:
	return role != Role.OFFLINE


func peer_ids() -> Array:
	var mp := _api()
	if not online() or mp == null:
		return []
	return mp.get_peers()


func local_id() -> int:
	var mp := _api()
	if not online() or mp == null:
		return 0
	return mp.get_unique_id()


## Round-trip time to a peer in milliseconds. -1 until the first reply lands.
##
## Measured at the application layer rather than read from ENet's own
## PEER_ROUND_TRIP_TIME statistic, for two reasons. The stat is only readable
## from the side that owns the connection, so a client could never see its ping
## to the host — half the devices in the room would show nothing. And ENet seeds
## it at 500 ms before converging, which reads as a catastrophe on a panel
## somebody is watching to decide whether the network is usable.
##
## This also measures the thing that actually matters: request to reply
## including frame scheduling, which is the delay a player feels, not the delay
## the socket sees.
func ping_ms(id: int) -> int:
	return int(_pings.get(id, -1))


## True once this peer can actually send. A client spends a moment in
## CONNECTING, and calling rpc() during it logs "Trying to call an RPC via a
## multiplayer peer which is not connected" on every attempt — harmless, but it
## would bury the real diagnostics in a log the phone reads through a panel.
func ready_to_send() -> bool:
	var mp := _api()
	if mp == null or mp.multiplayer_peer == null:
		return false
	return mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Worst ping across all peers — the number that actually decides whether
## host-authoritative-without-prediction is viable.
##
## ENet seeds round-trip time at 500 ms and converges over the first few
## seconds, so an early reading is a placeholder rather than a measurement. Read
## it after it settles, not the instant a peer appears.
func worst_ping_ms() -> int:
	var worst := -1
	for id: int in peer_ids():
		worst = maxi(worst, ping_ms(id))
	return worst


func _process(delta: float) -> void:
	# Nobody to talk to, or not connected yet — nothing worth sending either way.
	if not online() or not ready_to_send() or peer_ids().is_empty():
		return

	_tick_ping(delta)


func _tick_ping(delta: float) -> void:
	_ping_accum += delta
	if _ping_accum < PING_INTERVAL:
		return
	_ping_accum = 0.0
	# Reliable, unlike positions: a dropped probe would read as a dead link.
	_ping.rpc(Time.get_ticks_msec())


@rpc("any_peer", "reliable", "call_remote")
func _ping(sent_at: int) -> void:
	var mp := _api()
	if mp == null:
		return
	_pong.rpc_id(mp.get_remote_sender_id(), sent_at)


@rpc("any_peer", "reliable", "call_remote")
func _pong(sent_at: int) -> void:
	var mp := _api()
	if mp == null:
		return
	_pings[mp.get_remote_sender_id()] = Time.get_ticks_msec() - sent_at


func _on_peer_connected(id: int) -> void:
	_pings[id] = -1
	peers_changed.emit()
	status_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	_pings.erase(id)
	peers_changed.emit()
	status_changed.emit()


func _on_connection_failed() -> void:
	last_error = "connection failed — wrong address, or the host is not reachable"
	shutdown()


func _on_server_disconnected() -> void:
	last_error = "host went away"
	shutdown()
