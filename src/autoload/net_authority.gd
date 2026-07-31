class_name NetAuthorityService
extends Node
## Autoload: [code]NetAuthority[/code]. Server/client role, peer identity, and
## the prediction flags, owned by
## [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §2.
##
## Architectural Invariant I-8: the server is authoritative for transforms,
## integrity, bands, topology, damaging projectiles, ground deformation, and
## structure failure. Clients predict only their own Assembly, and never predict
## jams or destruction.
##
## Every system that writes simulated state asks [method can_simulate] first.
## The rule the authority matrix expresses: anything that can decide a fight is
## authoritative; anything that only looks good is not.

## Bumped on any change to the snapshot format, channel layout, or quantisation.
## Checked in the handshake; a mismatch is a hard rejection.
const PROTOCOL_VERSION: int = 7

enum Role {
	## No peer. Garage, replays, and the test suite.
	STANDALONE = 0,
	## Headless dedicated server; authoritative for everything.
	SERVER = 1,
	## Remote client; authoritative for nothing but its own input.
	CLIENT = 2,
}

signal role_changed(role: Role)

var role: Role = Role.STANDALONE
## This peer's multiplayer id. 1 on a server, 0 when standalone.
var peer_id: int = 0
## Assembly this peer drives, or 0 when it drives none.
var local_assembly_id: int = 0
## Client-side prediction of the local Assembly. Disabled by the diagnostics
## overlay to make a desync reproducible.
var prediction_enabled: bool = true
## Server-side lag compensation when resolving client fire intents.
var lag_compensation_enabled: bool = true


## True when this peer owns simulated state: it may write integrity, topology,
## transforms, and deformation.
func is_authoritative() -> bool:
	return role != Role.CLIENT


## True when this peer may advance simulation for [param assembly_id].
##
## A client may advance only its own Assembly, and only while prediction is on.
## Every other Assembly it sees is replicated state it must not touch.
func can_simulate(assembly_id: int) -> bool:
	if role != Role.CLIENT:
		return true
	return prediction_enabled and assembly_id == local_assembly_id


## True when this peer may apply damage, band transitions, and destruction.
## Never true on a client: I-8 forbids predicting jams or destruction, because a
## mispredicted destruction cannot be visually undone without a worse artefact
## than the latency it was hiding.
func can_resolve_damage() -> bool:
	return role != Role.CLIENT


func set_role(new_role: Role, new_peer_id: int) -> void:
	if role == new_role and peer_id == new_peer_id:
		return
	role = new_role
	peer_id = new_peer_id
	role_changed.emit(role)


func is_headless_server() -> bool:
	return role == Role.SERVER and DisplayServer.get_name() == "headless"
