class_name PartVisualProfile
extends Resource
## Presentation payload of a part, owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.
##
## Architectural Invariant I-1: nothing here is ever read by the simulation. A
## part may sit at [constant Stage.PROXY] forever without changing a single
## simulated quantity, which is what makes the asset maturity pipeline safe to
## run in parallel with gameplay work.

enum Stage { PROXY = 0, BLOCKOUT = 1, FINAL = 2 }

@export var stage: Stage = Stage.PROXY

## ===== STAGE_PROXY =====================================================
@export var proxy_primitives: Array[ProxyPrimitiveDef] = []
@export var proxy_tint: Color = Color(0.55, 0.58, 0.62)

## ===== STAGE_BLOCKOUT ==================================================
@export var blockout_mesh: ArrayMesh = null

## ===== STAGE_FINAL =====================================================
@export var mesh_nominal: Mesh = null
@export var mesh_impaired: Mesh = null
@export var mesh_critical: Mesh = null
@export var lod_distances_m: PackedFloat32Array = PackedFloat32Array([18.0, 42.0, 90.0])
@export var atlas_variant: int = 0
@export var casts_shadow: bool = true

## ===== SHARED ==========================================================
@export var visual_offset_m: Vector3 = Vector3.ZERO
@export var visual_scale: Vector3 = Vector3.ONE
@export var attachment_marker_names: PackedStringArray = PackedStringArray()


## Mesh to display for an integrity band, falling back down the chain when the
## damaged variants have not been authored yet. Returns null at PROXY stage,
## where the visual is built from [member proxy_primitives] instead.
func mesh_for_band(band: PartEnums.IntegrityBand) -> Mesh:
	if stage == Stage.BLOCKOUT:
		return blockout_mesh
	if stage != Stage.FINAL:
		return null
	if band >= PartEnums.IntegrityBand.CRITICAL and mesh_critical != null:
		return mesh_critical
	if band >= PartEnums.IntegrityBand.IMPAIRED and mesh_impaired != null:
		return mesh_impaired
	return mesh_nominal
