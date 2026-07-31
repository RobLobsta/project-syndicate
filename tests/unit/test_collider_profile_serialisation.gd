extends TestCase
## Regression guard for the [ColliderProfile] round trip.
##
## [b]Why this test exists.[/b] [code]docs/PART_DATA_SCHEMA.md[/code] §6.2
## originally declared [code]PrimitiveDef[/code] as an inner class of
## [ColliderProfile]. Godot 4 cannot serialise an inner-class [Resource]: saving
## writes the element script as an empty [code]sub_resource type="GDScript"[/code]
## carrying no source, and on load every element fails typed-array validation and
## is dropped. A profile saved with three primitives loads back with zero, with
## no error surfaced to the caller.
##
## The consequence would have been every part in the game shipping with an empty
## collider set — no hit registration at all — from a change that looks like a
## code-organisation preference. [ColliderPrimitiveDef] is therefore a top-level
## type, and this test fails if anything moves it back.

const SCRATCH_PATH: String = "user://test_collider_profile_round_trip.tres"


func after_all() -> void:
	if FileAccess.file_exists(SCRATCH_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_PATH))


func test_primitive_def_is_a_top_level_class() -> void:
	# A top-level class resolves through the global class registry; an inner
	# class does not.
	check_true(
		ClassDB.class_exists("Resource"),
		"sanity: ClassDB is available"
	)
	var script: Script = ColliderPrimitiveDef.new().get_script() as Script
	check_not_null(script, "ColliderPrimitiveDef must carry a script")
	if script != null:
		check_eq(
			script.get_global_name(),
			&"ColliderPrimitiveDef",
			"ColliderPrimitiveDef must be registered as a global class, not an inner class"
		)


func test_profile_round_trips_through_tres_without_losing_primitives() -> void:
	var profile := ColliderProfile.new()
	profile.primitives.append(_make(ColliderPrimitiveDef.PrimitiveKind.BOX, 0.5))
	profile.primitives.append(_make(ColliderPrimitiveDef.PrimitiveKind.CYLINDER, 0.25))
	profile.primitives.append(_make(ColliderPrimitiveDef.PrimitiveKind.SPHERE, 0.125))

	var save_err := ResourceSaver.save(profile, SCRATCH_PATH)
	if not check_eq(save_err, OK, "ColliderProfile must save"):
		return

	var loaded := ResourceLoader.load(
		SCRATCH_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	) as ColliderProfile
	if not check_not_null(loaded, "ColliderProfile must load back"):
		return

	check_eq(loaded.primitives.size(), 3, "every primitive must survive the round trip")
	if loaded.primitives.size() != 3:
		return
	check_eq(
		loaded.primitives[0].kind,
		ColliderPrimitiveDef.PrimitiveKind.BOX,
		"primitive 0 kind survives"
	)
	check_approx(loaded.primitives[1].radius_m, 0.25, "primitive 1 radius survives")
	check_approx(loaded.primitives[2].local_offset_m.y, 0.125, "primitive 2 offset survives")


func test_every_primitive_kind_builds_a_permitted_shape() -> void:
	var expected := {
		ColliderPrimitiveDef.PrimitiveKind.BOX: "BoxShape3D",
		ColliderPrimitiveDef.PrimitiveKind.CYLINDER: "CylinderShape3D",
		ColliderPrimitiveDef.PrimitiveKind.CAPSULE: "CapsuleShape3D",
		ColliderPrimitiveDef.PrimitiveKind.SPHERE: "SphereShape3D",
	}
	for kind: int in expected:
		var prim := _make(kind as ColliderPrimitiveDef.PrimitiveKind, 0.3)
		var shape := prim.build_shape()
		if not check_not_null(shape, "kind %d must build a shape" % kind):
			continue
		check_eq(shape.get_class(), expected[kind], "kind %d shape class" % kind)


func test_primitive_volumes_are_positive_and_ordered() -> void:
	# A sphere of radius r fits inside a cube of half-extent r, so for equal
	# characteristic size the box volume must exceed the sphere volume. Catches a
	# transposed radius/diameter, which would silently halve or double coverage.
	var box := _make(ColliderPrimitiveDef.PrimitiveKind.BOX, 0.4)
	box.half_extents_m = Vector3(0.4, 0.4, 0.4)
	var sphere := _make(ColliderPrimitiveDef.PrimitiveKind.SPHERE, 0.4)
	check_true(box.volume_m3() > 0.0, "box volume is positive")
	check_true(sphere.volume_m3() > 0.0, "sphere volume is positive")
	check_true(box.volume_m3() > sphere.volume_m3(), "a cube contains its inscribed sphere")


func test_capsule_volume_accounts_for_its_caps() -> void:
	# Godot's CapsuleShape3D height spans the whole capsule including both caps,
	# so a capsule whose height equals its diameter is exactly a sphere.
	var capsule := _make(ColliderPrimitiveDef.PrimitiveKind.CAPSULE, 0.3)
	capsule.height_m = 0.6
	var sphere := _make(ColliderPrimitiveDef.PrimitiveKind.SPHERE, 0.3)
	check_approx(
		capsule.volume_m3(),
		sphere.volume_m3(),
		"a capsule of height 2r is a sphere",
		1e-6
	)


func test_coverage_band_matches_the_schema() -> void:
	check_approx(ColliderProfile.MIN_COVERAGE_RATIO, 0.82, "minimum coverage ratio")
	check_approx(ColliderProfile.MAX_COVERAGE_RATIO, 1.18, "maximum coverage ratio")


func _make(kind: ColliderPrimitiveDef.PrimitiveKind, size: float) -> ColliderPrimitiveDef:
	var p := ColliderPrimitiveDef.new()
	p.kind = kind
	p.radius_m = size
	p.height_m = size * 2.0
	p.half_extents_m = Vector3(size, size, size)
	p.local_offset_m = Vector3(0.0, size, 0.0)
	return p
