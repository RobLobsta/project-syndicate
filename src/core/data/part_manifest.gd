class_name PartManifest
extends Resource
## The append-only ordered list of part keys, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §5.2.
##
## [member PartDefinition.runtime_id] is the array index plus one; index 0 is
## reserved for [constant INVALID_PART_ID]. Order is append-only: the validator
## fails the build if any existing entry is reordered or removed, because
## [code]part_def_id[/code] values are serialised in save data and network packets.

## Reserved id meaning "no part". Never assigned to a definition.
const INVALID_PART_ID: int = 0

## Directory holding every part `.tres` and its profile side-cars.
const PARTS_DIR: String = "res://data/parts"

@export var keys: PackedStringArray = PackedStringArray()


## Stable content hash transmitted in the network handshake. A mismatch between
## client and server aborts the connection with ERR_INCOMPATIBLE_CONTENT rather
## than allowing silent desynchronisation.
##
## Deliberately order-sensitive: two peers with the same key set in a different
## order disagree about every part id and must not connect.
func compute_content_hash() -> int:
	var joined := "\n".join(keys)
	return joined.hash()


## Part id for a key, or [constant INVALID_PART_ID] when absent. Linear; used by
## tooling and blueprint import, never in a per-tick path.
func id_for_key(key: StringName) -> int:
	var idx := keys.find(String(key))
	return INVALID_PART_ID if idx < 0 else idx + 1


## On-disk path of a definition, per [code]docs/EXTENSION_PIPELINE.md[/code] §4.1.
##
## Static, and here rather than on the registry, because the tools validate the
## data on disk without an autoload in the tree. The key-to-path conversion is
## mechanical and every caller shares this one so the two forms cannot drift.
static func definition_path(key: StringName) -> String:
	var segments := String(key).split(".")
	return "%s/%s/%s.tres" % [PARTS_DIR, segments[0], String(key)]
