class_name GreyboxMaterial
extends RefCounted
## Flat materials for stage-PROXY and stage-BLOCKOUT parts, owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.1.
##
## Architectural Invariant I-1: nothing here is ever read by the simulation. The
## class tint decides what a part looks like and decides nothing else.
##
## Materials are cached per class so that forty panels on one Assembly share one
## [StandardMaterial3D] rather than allocating forty. The cache key is the class
## and the authored tint together, because [member PartVisualProfile.proxy_tint]
## is per-part data and two parts of one class may legitimately differ.

## Per-class base tint, doc 13 §2.1's table.
##
## The point of the table is [b]legibility[/b], not decoration. A greybox
## Assembly in a single grey is a shape with no parts in it: a player cannot see
## where the Prime Mover they are meant to protect actually is, and neither can
## anyone reading a screenshot of a bug. Nine hues that survive being small,
## desaturated, and lit from one direction are worth more here than nine pretty
## ones.
const CLASS_TINT: Array[Color] = [
	Color(0.431, 0.486, 0.549),  # CORE_MODULE          — pale steel
	Color(0.541, 0.561, 0.588),  # STRUCTURAL_COMPONENT — neutral
	Color(0.290, 0.306, 0.333),  # MOTIVE_ASSEMBLY      — charcoal
	Color(0.604, 0.478, 0.275),  # PRIME_MOVER          — brass
	Color(0.420, 0.435, 0.388),  # EFFECTOR_MODULE      — olive gunmetal
	Color(0.369, 0.502, 0.478),  # SUPPORT_MODULE       — teal
	Color(0.494, 0.576, 0.659),  # CONTROL_SURFACE      — pale blue
	Color(0.310, 0.549, 0.525),  # ENERGY_CELL          — cyan-green
	Color(0.522, 0.490, 0.455),  # APPENDAGE            — warm grey
]

## How strongly the authored per-part tint modulates the class tint. A part that
## leaves [member PartVisualProfile.proxy_tint] at its default reads as its
## class; one that authors a tint shifts within the class rather than leaving it,
## so the class stays recognisable at a glance whatever an artist does.
const AUTHORED_TINT_WEIGHT: float = 0.35

const ROUGHNESS: float = 0.82
const METALLIC: float = 0.05

static var _cache: Dictionary = {}


## Shared material for [param part_class], modulated by the part's authored
## [param tint]. Never null: an out-of-range class falls back to the structural
## grey rather than returning nothing, because a part with no material renders
## as unlit white and reads as a bug in the lighting rather than in the data.
static func for_class(part_class: PartEnums.PartClass, tint: Color) -> StandardMaterial3D:
	var key := "%d:%08x" % [int(part_class), tint.to_rgba32()]
	var cached: StandardMaterial3D = _cache.get(key, null)
	if cached != null:
		return cached

	var index := int(part_class)
	var base := CLASS_TINT[PartEnums.PartClass.STRUCTURAL_COMPONENT]
	if index >= 0 and index < CLASS_TINT.size():
		base = CLASS_TINT[index]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = base.lerp(tint, AUTHORED_TINT_WEIGHT)
	mat.roughness = ROUGHNESS
	mat.metallic = METALLIC
	# Greybox geometry is closed convex primitives, so the back faces are never
	# seen and culling them halves the fragment work for free.
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_cache[key] = mat
	return mat


## Drops the shared materials. For tests, which must not carry a cache built
## against one fixture's data into the next file.
static func clear_cache() -> void:
	_cache.clear()
