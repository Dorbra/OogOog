class_name RemoteController
extends RefCounted
## Drives a Fighter from a command that arrived over the network.
##
## The FOURTH producer of an InputCommand, after thumbs, bots, and the empty
## command a dummy gets. src/sim/input_command.gd predicted this one in M1 and
## was exactly right:
##
##     "if same-WiFi multiplayer ever happens, the network becomes a third
##      producer and the simulation does not change at all."
##
## It did not. SimWorld.tick() reads `f_cmd = _command_for(f, delta)` for every
## fighter that is not the local player, and `_command_for` reads
## `f.controller.think(...)`. A person on another phone is a controller. That is
## the whole integration — no new branch in the sim, no network type reachable
## from src/sim/, and every rule that binds a bot binds a remote player too.
##
## It lives in src/ai/ rather than src/net/ for that reason. Putting it under
## the network layer would say the simulation knows a socket exists, which is
## the one thing ADR-0003 is for. Nothing here imports anything from src/net/:
## commands are PUSHED in by NetGame.
##
## THE RULE THAT MATTERS IS STALENESS. A phone that locks its screen, walks out
## of WiFi range, or simply drops a run of packets stops sending. Repeating the
## last command would leave its cat sprinting into a wall and firing forever,
## which on a five-year-old's screen is indistinguishable from the game being
## broken — and worse, it would keep SCORING. So a command has an age, and past
## net_stale_ticks this hands back an empty one and the cat stands still.

## Sent by the peer this controller speaks for. Zero on a controller that has
## never received anything, which is a legitimate state: a phone can be in the
## roster a tick before its first packet lands.
var peer_id: int = 0

## Ticks since `receive()` was last called. Counted up by think(), reset by
## receive(), and compared against `net_stale_ticks`.
var age: int = 0

## The last thing this peer asked for. Never handed out directly — think()
## returns either this or _empty, and the caller must not be able to mutate what
## the next tick will read.
var _latest := InputCommand.new()

## Handed back once the peer has gone quiet. A separate instance from SimWorld's
## own shared empty command: returning that one would let a stale peer's tick
## number leak into a world other fighters read.
var _empty := InputCommand.new()

## What think() hands back. A second buffer rather than `_latest` itself, so the
## edges below can be cleared on `_latest` without clearing what was just
## returned. Reused rather than allocated, like BotController's.
var _out := InputCommand.new()

## True once anything at all has arrived.
var _ever := false


func _init(from_peer: int = 0) -> void:
	peer_id = from_peer


## Takes one command off the wire. Called by NetGame, never by the simulation.
##
## Copied field by field rather than stored by reference, because the caller
## deserialises into a scratch command it will reuse next packet — keeping the
## reference would mean this controller's "last command" silently became the
## next one to arrive, for any peer.
func receive(cmd: InputCommand) -> void:
	_latest.tick = cmd.tick
	_latest.move = cmd.move
	_latest.aim = cmd.aim
	_latest.fire = cmd.fire
	_latest.snap = cmd.snap
	_latest.ability = cmd.ability
	age = 0
	_ever = true


## True while this peer's last packet is recent enough to act on.
func fresh() -> bool:
	return _ever and age <= int(Tuning.get_value("net_stale_ticks"))


func think(_self_fighter: Fighter, _world: SimWorld, _delta: float) -> InputCommand:
	age += 1
	if not fresh():
		return _empty

	_out.tick = _latest.tick
	_out.move = _latest.move
	_out.aim = _latest.aim
	_out.fire = _latest.fire
	_out.snap = _latest.snap
	_out.ability = _latest.ability

	# fire, snap and ability are EDGES, not states: one release is one bullet.
	# The simulation runs at 60 Hz against packets at 30, so without this the
	# same command is read twice and one release becomes two bullets — a remote
	# player would quietly shoot at double the rate of the person hosting.
	#
	# Consuming the edge HERE is the same contract TouchControls.take_fire()
	# gives the local player, applied at the same place: a tick boundary. Move
	# and aim are states and are deliberately left alone — a peer holding a
	# direction means to keep holding it between packets.
	_latest.fire = false
	_latest.snap = false
	_latest.ability = false
	return _out
