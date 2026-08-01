class_name InertiaSolver
extends RefCounted
## Rotational inertia of an Assembly and of the islands severed from it, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §3.3.
##
## Split out of [MassSolver] — which §3.3 writes it into — because the Assembly
## tensor and [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6's island tensor are
## the same arithmetic over different slot sets, and CLAUDE.md §2 names this file
## for it. [MassSolver] owns the mass and centre-of-mass reduction and calls in
## here per part.
##
## [b]Every part is a uniform-density box.[/b] That is deliberate rather than an
## approximation waiting to be improved: the authored [ColliderProfile]
## primitives describe a part's physical footprint, not its density
## distribution, so integrating over three overlapping primitives would produce a
## tensor no more truthful than the box at several times the cost.
## [member PartDefinition.inertia_box_half_extents_m] is the author's override
## for the parts where the lattice bounds are the wrong shape.

## The 1/12 of the uniform rectangular prism's tensor. Not a tunable.
const BOX_TENSOR_DENOM: float = 12.0


## Half-extents of the box standing in for [param def], in metres.
##
## The authored override wins where it is set; otherwise the part's own lattice
## bounds are the box, which is exact for the panels and blocks that make up most
## of an Assembly.
static func half_extents(def: PartDefinition) -> Vector3:
	if def.inertia_box_half_extents_m != Vector3.ZERO:
		return def.inertia_box_half_extents_m
	return Vector3(def.bounds_size_cells) * SyndicateConstants.LATTICE_UNIT_M * 0.5


## Diagonal of a uniform box's tensor about its own centre, in part-local axes.
static func box_tensor(mass_kg: float, h: Vector3) -> Vector3:
	var w := h + h  # full extents
	var k := mass_kg / BOX_TENSOR_DENOM
	return Vector3(
		k * (w.y * w.y + w.z * w.z),
		k * (w.x * w.x + w.z * w.z),
		k * (w.x * w.x + w.y * w.y)
	)


## Tensor of one part about a reference point [param offset] away from that
## part's own centre of mass, expressed in assembly-local axes.
##
## Both halves of §3.3 in one call: the part-local box tensor rotated into
## assembly axes by [code]R · I · Rᵀ[/code], plus the parallel-axis shift that
## moves it to the Assembly centre of mass.
static func part_tensor(def: PartDefinition, orientation_index: int, offset: Vector3) -> Basis:
	var diag := box_tensor(def.mass_kg, half_extents(def))
	var r := OrientationTable.basis_for(orientation_index)
	var local := Basis(
		Vector3(diag.x, 0.0, 0.0), Vector3(0.0, diag.y, 0.0), Vector3(0.0, 0.0, diag.z)
	)
	return add(r * local * r.transposed(), parallel_axis(def.mass_kg, offset))


## The parallel-axis term [code]m · ((d·d)·I₃ − d ⊗ d)[/code].
static func parallel_axis(mass_kg: float, d: Vector3) -> Basis:
	var dd := d.dot(d)
	return Basis(
		Vector3(mass_kg * (dd - d.x * d.x), mass_kg * (-d.x * d.y), mass_kg * (-d.x * d.z)),
		Vector3(mass_kg * (-d.y * d.x), mass_kg * (dd - d.y * d.y), mass_kg * (-d.y * d.z)),
		Vector3(mass_kg * (-d.z * d.x), mass_kg * (-d.z * d.y), mass_kg * (dd - d.z * d.z))
	)


## Element-wise sum. [Basis] has no operator for this because it models a
## transform rather than a matrix, and composing two tensors is multiplication.
static func add(a: Basis, b: Basis) -> Basis:
	return Basis(a.x + b.x, a.y + b.y, a.z + b.z)


## The additive identity, which is [b]not[/b] [code]Basis()[/code] — that is the
## identity matrix, and accumulating onto it adds a spurious unit tensor.
static func zero() -> Basis:
	return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)


## Principal diagonal, which is what [member RigidBody3D.inertia] accepts.
## [member Basis.x] is a column, so [code]t.x.x[/code] is element (0,0).
static func diagonal_of(t: Basis) -> Vector3:
	return Vector3(t.x.x, t.y.y, t.z.z)


## Diagonal tensor of a severed island about its own centre of mass, for
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6's debris body.
##
## [b]Deviation from §6 as written.[/b] §6 calls this with the whole
## [code]AssemblyRuntime[/code] and reads only its state array. Taking the array
## keeps the mass layer independent of the runtime layer — the same reason
## [ChassisGraph] takes a part's mass rather than reaching into [PartRegistry] —
## and makes the function testable without a node in a tree. §6 records the
## signature.
static func island_inertia(
	states: Array[PartInstanceState], island: PackedByteArray, island_com_local: Vector3
) -> Vector3:
	var acc := zero()
	for s in island:
		var slot := int(s)
		if slot < 0 or slot >= states.size():
			continue
		var st: PartInstanceState = states[slot]
		if st == null:
			continue
		var def := PartRegistry.definition(st.part_def_id)
		var d := MassSolver.part_com_local(st, def) - island_com_local
		acc = add(acc, part_tensor(def, st.orientation_index, d))
	return diagonal_of(acc)
