class_name NetGame
extends Node
## Puts the FIGHT on the wire, where NetLink only ever put a position.
##
## `NetLink` is the transport — it hosts, joins, tracks peers and measures ping.
## This is the layer above it that knows what a match is: who is in the roster,
## which class each of them picked, whose thumbs drive which cat, and what a
## client has to be told 30 times a second to draw a fight it is not running.
##
## HOST-AUTHORITATIVE, NO PREDICTION, NO ROLLBACK. One device runs `SimWorld`
## and everybody else draws what it says. That is the smallest design that can
## be correct, and it is only viable because LAN latency is small: at 5-20 ms
## between two phones on the same 5 GHz radio, your own cat answers your thumb
## about as fast as a television answers a games console, and nobody notices.
##
## If it turns out NOT to be small — a congested 2.4 GHz band, a phone in power
## save, a router doing something creative — this design is the wrong one and it
## will FEEL wrong rather than break: you will push the stick and your cat will
## answer late. The DBG Net tab exists so that is a number you can read to me
## rather than a feeling, and the fix is client-side prediction on movement
## only, which is a change to this file and nothing else.
##
## The asymmetry is deliberate and total:
##
##     host    runs SimWorld.tick(), broadcasts Snapshot.capture()
##     client  runs SimWorld.tick_replica(), sends its InputCommand
##
## A client has no code path that can apply damage, score, or decide anybody is
## dead. It is not prevented from doing so by a flag; it simply never calls the
## function.

signal roster_changed

## Tells `main.gd` the host has started a match, so a client leaves the lobby
## at the same moment its host does rather than when the first snapshot lands.
signal match_started_remotely

enum Role { OFFLINE, HOST, CLIENT }

## Peer id -> class index that peer picked in the lobby. The host's own choice
## is under `Tuning.player_class` like it has always been; this is everyone
## else's.
var roster: Dictionary = {}

## Peer id -> index into `world.fighters` of the cat they drive. Built once when
## the host starts the match, because a roster that changed mid-match would
## reassign cats under people's thumbs.
var seats: Dictionary = {}

## The world this is bridging. Set by main.gd on every rebuild — a new match is
## a new SimWorld (see main._rebuild_world), and a stale reference here would
## have the host broadcasting last round's fight.
var world: SimWorld = null

## Set on a client from the snapshot header, so the lobby knows the host has
## begun without waiting for a phase change to be noticed.
var started := false

## Which cat THIS device drives, as an index into `world.fighters`.
##
## Zero on a host, which is `fighters[0]` — the seat SimWorld.tick() already
## treats as the local player. On a client the host assigns it, and until it
## does a client would otherwise watch the HOST's cat while its own thumbs moved
## somebody off screen: `world.player` is what the camera follows, what the ammo
## pips and charge ring are drawn from, and what Fx uses to decide an event is
## yours. All of that has to point at the cat you are actually playing.
var local_seat: int = 0

var _send_accum: float = 0.0
var _local_cmd := InputCommand.new()
var _scratch := InputCommand.new()


func role() -> int:
	if Net == null or not Net.online():
		return Role.OFFLINE
	return Role.HOST if Net.role == NetLink.Role.HOST else Role.CLIENT


func hosting() -> bool:
	return role() == Role.HOST


## True when this device must NOT run its own simulation.
##
## Every caller in main.gd branches on this one function rather than on a role
## enum, so there is exactly one place that decides who is authoritative.
func replicating() -> bool:
	return role() == Role.CLIENT


## Number of humans in the match, this device included. The host uses it as a
## floor on team size: three people in the room and a 1v1 picked by accident
## would leave somebody with no cat.
func human_count() -> int:
	return 1 + roster.size()


func leave() -> void:
	roster.clear()
	seats.clear()
	started = false
	local_seat = 0
	if Net != null:
		Net.shutdown()
	if Beacon != null:
		Beacon.stop()
	roster_changed.emit()


# ------------------------------------------------------------------ the lobby


func start_hosting() -> bool:
	leave()
	if not Net.host():
		return false
	Beacon.start_broadcasting()
	roster_changed.emit()
	return true


func start_looking() -> void:
	leave()
	Beacon.start_listening()


func join(address: String) -> bool:
	if not Net.join(address):
		return false
	Beacon.stop()
	roster_changed.emit()
	return true


## A client tells the host which cat it wants to be. Sent on every lobby change
## rather than once, because a packet lost during the one moment it mattered
## would seat somebody as a class they did not pick with nothing to notice it.
func publish_class(index: int) -> void:
	if not replicating() or not Net.ready_to_send():
		return
	_receive_class.rpc_id(1, index)


@rpc("any_peer", "reliable", "call_remote")
func _receive_class(index: int) -> void:
	if not hosting():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	roster[sender] = clampi(index, 0, maxi(FighterClass.count() - 1, 0))
	roster_changed.emit()


## Host only: seats every joined peer in a cat and tells them the match is on.
##
## Seats are taken from the FAR END of team 0 inward, so the host keeps
## `fighters[0]` — which `SimWorld.tick()` special-cases as the local player and
## the camera follows. Humans therefore fill one side and the bots fill in
## behind them, which is also the right thing socially: the kids are on the same
## team as the adult rather than scattered.
func seat_everyone() -> void:
	seats.clear()
	if world == null or not hosting():
		return

	var next := 1
	for peer_id: int in roster:
		# Team 0 only, and never the host's own cat.
		while next < world.fighters.size() and world.fighters[next].team != 0:
			next += 1
		if next >= world.fighters.size():
			push_warning(
				"NetGame: more humans than seats on team 0; peer %d is a spectator" % peer_id
			)
			break

		var f: Fighter = world.fighters[next]
		f.fighter_class = FighterClass.at(int(roster[peer_id]))
		f.controller = RemoteController.new(peer_id)
		seats[peer_id] = next
		# Per peer, not broadcast: each one needs a DIFFERENT seat, and the team
		# size travels with it because a client whose roster is a different size
		# from the host's would reject every snapshot it ever received — the
		# length check in Snapshot.apply() would refuse them, correctly, and the
		# symptom would be a frozen arena with a healthy connection.
		if Net.ready_to_send():
			_begin.rpc_id(peer_id, world.team_size, next)
		next += 1

	started = true


## Reliable, because missing this is missing the whole match.
@rpc("authority", "reliable", "call_remote")
func _begin(team_size: int, seat: int) -> void:
	local_seat = maxi(seat, 0)
	# The host's roster size, not this device's slider. Both worlds must hold
	# the same number of fighters or nothing can be replicated into them.
	Tuning.set_value("bot_team_size", float(clampi(team_size, 1, SimWorld.MAX_TEAM_SIZE)))
	started = true
	match_started_remotely.emit()


## Points `world.player` at the cat this device actually drives.
##
## Called by main.gd after every world build. On a host it is a no-op —
## `_build_teams()` already set `player` to `fighters[0]` — which is exactly why
## it is written as one function both roles call rather than a branch.
func take_seat() -> void:
	if world == null:
		return
	if local_seat >= 0 and local_seat < world.fighters.size():
		world.player = world.fighters[local_seat]


# ------------------------------------------------------------- the fight loop


## Called once per RENDERED frame by main.gd, after the world has been ticked.
##
## Rendered rather than simulated, because the send rate is its own clock:
## `net_snapshot_hz` is 30 against a 60 Hz simulation on purpose. Sending every
## tick would double the traffic to describe movement nobody can see the
## difference in, and the replica interpolates between what does arrive.
func pump(delta: float) -> void:
	if world == null or Net == null or not Net.online() or not Net.ready_to_send():
		return

	_send_accum += delta
	var interval := 1.0 / maxf(Tuning.get_value("net_snapshot_hz"), 1.0)
	if _send_accum < interval:
		return
	_send_accum = 0.0

	if hosting():
		if not Net.peer_ids().is_empty():
			_receive_snapshot.rpc(Snapshot.capture(world))
	else:
		_receive_command.rpc_id(
			1, _local_cmd.move, _local_cmd.aim, _local_cmd.fire, _local_cmd.snap, _local_cmd.ability
		)
		_local_cmd.clear()


## A client stores its thumbs here every SIMULATION tick, and pump() ships the
## accumulation at 30 Hz.
##
## The edges are OR-ed rather than overwritten. A release lands on one tick out
## of two, and a send that happened to read the other tick would drop the shot
## entirely — the player would tap and nothing would happen, intermittently,
## which is the worst kind of bug to be told about over the phone.
func record_local(cmd: InputCommand) -> void:
	if not replicating():
		return
	_local_cmd.move = cmd.move
	_local_cmd.aim = cmd.aim
	_local_cmd.fire = _local_cmd.fire or cmd.fire
	_local_cmd.snap = _local_cmd.snap or cmd.snap
	_local_cmd.ability = _local_cmd.ability or cmd.ability


## Unreliable: a dropped command is replaced 33 ms later by a fresher one, and
## retransmitting a stale intent would make a player fight the past.
##
## Fields rather than an object, because Godot's RPC serialiser cannot send a
## RefCounted and an Array would need an index agreed in two places.
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _receive_command(move: Vector2, aim: Vector2, fire: bool, snap: bool, ability: bool) -> void:
	if not hosting() or world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not seats.has(sender):
		return

	var index: int = seats[sender]
	if index >= world.fighters.size():
		return
	var controller = world.fighters[index].controller
	if not (controller is RemoteController):
		return

	_scratch.move = move
	_scratch.aim = aim
	_scratch.fire = fire
	_scratch.snap = snap
	_scratch.ability = ability
	controller.receive(_scratch)


@rpc("authority", "unreliable_ordered", "call_remote")
func _receive_snapshot(data: PackedFloat32Array) -> void:
	if world == null or hosting():
		return
	if not world.apply_snapshot(data):
		# Loud, once per bad packet, because the one cause that matters is two
		# phones on different APKs — and that is diagnosable from a log tail the
		# user can copy, while "the other cats do not move" is not.
		push_warning("NetGame: refused a snapshot this build cannot read")
