class_name NetChannels
extends RefCounted
## ENet channel layout, owned by
## [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §3.
##
## Snapshots are unreliable because a lost snapshot is superseded within 33 ms;
## retransmitting stale state is worse than skipping it. Events are reliable
## because losing a [code]part_destroyed[/code] would leave a client rendering a
## part the server considers gone, and no later snapshot would correct it —
## snapshots carry state, not topology.

## Reliable ordered: handshake, blueprint upload, match state, disconnects.
const CH_CONTROL: int = 0
## Unreliable: per-tick world snapshots.
const CH_SNAPSHOT: int = 1
## Reliable ordered: destruction, detachment, ground deform, section failure.
const CH_EVENT: int = 2
## Unreliable sequenced: client input frames.
const CH_INPUT: int = 3

const CHANNEL_COUNT: int = 4


static func configure(peer: ENetMultiplayerPeer) -> void:
	peer.set_transfer_channel(CH_CONTROL)


## Transfer mode a channel must be sent with. Passing the wrong mode for a
## channel is the single most common cause of a protocol bug that only appears
## under packet loss, so callers route through here rather than remembering it.
static func transfer_mode_for(channel: int) -> MultiplayerPeer.TransferMode:
	match channel:
		CH_CONTROL, CH_EVENT:
			return MultiplayerPeer.TRANSFER_MODE_RELIABLE
		CH_INPUT:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
		CH_SNAPSHOT:
			return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE
