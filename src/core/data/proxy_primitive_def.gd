class_name ProxyPrimitiveDef
extends Resource
## One primitive of a stage-PROXY visual, owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.
##
## Field-for-field a mirror of [ColliderPrimitiveDef], deliberately kept as a
## separate type: a proxy visual is generated from the collider once, at
## promotion time, and thereafter the two evolve independently. Sharing one type
## would let an art edit silently move a hitbox, which Architectural Invariant
## I-1 exists to prevent.

@export var kind: ColliderPrimitiveDef.PrimitiveKind = ColliderPrimitiveDef.PrimitiveKind.BOX
@export var half_extents_m: Vector3 = Vector3(0.125, 0.125, 0.125)
@export var radius_m: float = 0.125
@export var height_m: float = 0.25
@export var local_offset_m: Vector3 = Vector3.ZERO
@export var local_basis_euler_deg: Vector3 = Vector3.ZERO


## Builds the display mesh for this primitive. Never a collision shape.
func build_mesh() -> Mesh:
	match kind:
		ColliderPrimitiveDef.PrimitiveKind.BOX:
			var box := BoxMesh.new()
			box.size = half_extents_m * 2.0
			return box
		ColliderPrimitiveDef.PrimitiveKind.CYLINDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = radius_m
			cyl.bottom_radius = radius_m
			cyl.height = height_m
			return cyl
		ColliderPrimitiveDef.PrimitiveKind.CAPSULE:
			var cap := CapsuleMesh.new()
			cap.radius = radius_m
			cap.height = height_m
			return cap
		ColliderPrimitiveDef.PrimitiveKind.SPHERE:
			var sph := SphereMesh.new()
			sph.radius = radius_m
			sph.height = radius_m * 2.0
			return sph
	return null


## Local transform of this primitive relative to the part pivot.
func local_transform() -> Transform3D:
	var b := Basis.from_euler(
		Vector3(
			deg_to_rad(local_basis_euler_deg.x),
			deg_to_rad(local_basis_euler_deg.y),
			deg_to_rad(local_basis_euler_deg.z)
		)
	)
	return Transform3D(b, local_offset_m)
