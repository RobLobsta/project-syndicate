class_name ColliderPrimitiveDef
extends Resource
## One authored physics primitive belonging to a [ColliderProfile].
##
## Architectural Invariant I-1: this, and only this, is the geometry the physics
## server ever sees for an Assembly part. No collision shape is ever derived
## from a visual mesh.
##
## [b]Deviation from docs/PART_DATA_SCHEMA.md §6.2 as originally written.[/b]
## The document declared this type as an inner class of [ColliderProfile].
## Godot 4 cannot serialise an inner-class [Resource] into a [code].tres[/code]:
## it writes the element script as an empty [code]sub_resource type="GDScript"[/code]
## with no source, and on load every element fails typed-array validation and is
## dropped — silently, leaving each part with an empty collider set. The type is
## therefore top-level. §6.2 records this and
## [code]tests/unit/test_collider_profile_serialisation.gd[/code] guards it.

enum PrimitiveKind { BOX = 0, CYLINDER = 1, CAPSULE = 2, SPHERE = 3 }

@export var kind: PrimitiveKind = PrimitiveKind.BOX
## Used by [constant PrimitiveKind.BOX].
@export var half_extents_m: Vector3 = Vector3(0.125, 0.125, 0.125)
## Used by CYLINDER, CAPSULE and SPHERE.
@export var radius_m: float = 0.125
## Used by CYLINDER and CAPSULE.
@export var height_m: float = 0.25
@export var local_offset_m: Vector3 = Vector3.ZERO
## Components must be multiples of [constant EULER_STEP_DEG] so that oriented
## primitives stay reproducible across platforms.
@export var local_basis_euler_deg: Vector3 = Vector3.ZERO

## Authored rotations are quantised to this step by the registry validator.
const EULER_STEP_DEG: float = 15.0


## Volume of this primitive in cubic metres, used by the registry validator's
## occupancy coverage check.
func volume_m3() -> float:
	match kind:
		PrimitiveKind.BOX:
			return 8.0 * half_extents_m.x * half_extents_m.y * half_extents_m.z
		PrimitiveKind.CYLINDER:
			return PI * radius_m * radius_m * height_m
		PrimitiveKind.CAPSULE:
			# Cylindrical mid-section plus the two hemispherical caps. Godot's
			# CapsuleShape3D height is the total span including both caps.
			var mid := maxf(0.0, height_m - 2.0 * radius_m)
			return PI * radius_m * radius_m * mid + (4.0 / 3.0) * PI * pow(radius_m, 3.0)
		PrimitiveKind.SPHERE:
			return (4.0 / 3.0) * PI * pow(radius_m, 3.0)
	return 0.0


## Builds the physics shape this primitive describes. Callers own the result.
func build_shape() -> Shape3D:
	match kind:
		PrimitiveKind.BOX:
			var box := BoxShape3D.new()
			box.size = half_extents_m * 2.0
			return box
		PrimitiveKind.CYLINDER:
			var cyl := CylinderShape3D.new()
			cyl.radius = radius_m
			cyl.height = height_m
			return cyl
		PrimitiveKind.CAPSULE:
			var cap := CapsuleShape3D.new()
			cap.radius = radius_m
			cap.height = height_m
			return cap
		PrimitiveKind.SPHERE:
			var sph := SphereShape3D.new()
			sph.radius = radius_m
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
