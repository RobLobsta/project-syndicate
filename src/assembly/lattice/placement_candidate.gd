class_name PlacementCandidate
extends RefCounted
## One proposed placement, carried through the check chain of
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §7 and into
## [method PlacementValidator.commit].
##
## The three authored fields — [member definition], [member origin_cell],
## [member orientation_index] — are the whole placement. Everything else is
## derived from them by [method resolve] and is a cache, not state: two
## candidates with equal authored fields are interchangeable.
##
## [member mates] and [member parent_slot] are the exception. They are filled by
## [code]PlacementValidator._check_mating[/code] because deciding them requires
## the lattice, which the candidate does not have. Nothing else may write them —
## a candidate that carries a parent it was not validated against would commit a
## joint that does not exist.

## ===== AUTHORED ========================================================

var definition: PartDefinition = null
## Cell the part's pivot cell (0,0,0) lands on.
var origin_cell: Vector3i = Vector3i.ZERO
## 0..23. See [code]docs/GRID_SNAPPING_LOGIC.md[/code] §4.
var orientation_index: int = 0

## ===== DERIVED BY resolve() ============================================

## Assembly-frame cells this placement would occupy.
var cells: PackedVector3Array = PackedVector3Array()
## Assembly-frame attachment nodes.
var nodes: Array[ResolvedNode] = []

## ===== FILLED BY THE VALIDATOR =========================================

## Every accepted attachment pair, in ascending order of the mated slot.
var mates: Array[MateRecord] = []
## Primary tree parent chosen by [method MateSelector.choose_primary_slot], or
## [constant SyndicateConstants.INVALID_SLOT] for the Core Module.
var parent_slot: int = SyndicateConstants.INVALID_SLOT
## A limit the placement exceeds that Sandbox mode permits anyway. Drives the
## amber ghost of §8 and the [constant PartFlags.FLAG_STRAINED] set at commit.
## [constant PlacementValidator.Reject.NONE] when the placement is clean.
var soft_reject: int = 0


static func create(
	def: PartDefinition, origin: Vector3i, orientation: int
) -> PlacementCandidate:
	var cand := PlacementCandidate.new()
	cand.definition = def
	cand.origin_cell = origin
	cand.orientation_index = orientation
	cand.resolve()
	return cand


## Recomputes [member cells] and [member nodes] from the authored fields.
##
## Clears the validator-filled fields too: a candidate that moved has not been
## validated at its new position, and leaving a stale parent behind is how a
## dragged ghost commits against the part it was next to two frames ago.
func resolve() -> void:
	assert(definition != null, "candidate has no definition")
	assert(
		orientation_index >= 0 and orientation_index < SyndicateConstants.ORIENTATION_COUNT,
		"orientation_index %d outside [0, 24)" % orientation_index
	)
	FootprintSolver.resolve(definition, origin_cell, orientation_index, cells)
	nodes = FootprintSolver.resolve_nodes(definition, origin_cell, orientation_index)
	mates = []
	parent_slot = SyndicateConstants.INVALID_SLOT
	soft_reject = 0


## Transform of the part in Assembly-local metres.
##
## The pivot cell's centre is the translation, so a collider primitive's
## [member ColliderPrimitiveDef.local_offset_m] composes onto it directly. The
## build proxies committed parts contribute use this same function, which is
## what makes the interpenetration query of §7.7 compare like with like.
func local_transform() -> Transform3D:
	return Transform3D(
		OrientationTable.basis_for(orientation_index), LatticeMath.cell_to_local(origin_cell)
	)


## The chosen primary mate, or null for the Core Module.
func primary_mate() -> MateRecord:
	for m in mates:
		if m.other_slot == parent_slot:
			return m
	return null
