class_name MateRecord
extends RefCounted
## One accepted attachment pair between a candidate placement and a part already
## committed to the lattice, consumed by [method ChassisGraph.attach] per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §3.1.
##
## Produced by [code]PlacementValidator._check_mating[/code], which is the only
## code permitted to decide that two nodes mate. Everything downstream — primary
## parent selection, support edge construction, strain — reads these records
## rather than re-deriving the pairing, so there is exactly one implementation of
## the mating rule (CLAUDE.md §10 rule 8).

## Slot of the already-committed part on the other side of the joint.
var other_slot: int = SyndicateConstants.INVALID_SLOT
## Rated tensile strength of the joint the two nodes form together.
##
## The weaker of the two declared node strengths. A joint is a pair of mating
## faces and fails at whichever face yields first, so taking the maximum — or
## the candidate's own value — would let a part advertise a strength its partner
## cannot honour. [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §3.1 records this.
var joint_strength_n: float = 0.0
## True only when [b]both[/b] nodes declare [member
## AttachmentNodeDef.can_bear_load]. This is the first key in the primary-parent
## ordering of §3.2, and a joint only bears load when neither end refuses to.
var bears_load: bool = false
## The candidate's node in this pair. Retained for diagnostics and for the
## garage's joint inspector; never mutated.
var own_node: ResolvedNode = null
## The committed part's node in this pair.
var other_node: ResolvedNode = null


## Builds a record from an accepted pair. The strength and load-bearing rules
## live here rather than at the call site so that the auto-assembler and the
## blueprint loader cannot construct a record that disagrees with the garage's.
static func create(
	other_slot_id: int, own: ResolvedNode, other: ResolvedNode
) -> MateRecord:
	var rec := MateRecord.new()
	rec.other_slot = other_slot_id
	rec.own_node = own
	rec.other_node = other
	rec.joint_strength_n = minf(own.source.joint_strength_n, other.source.joint_strength_n)
	rec.bears_load = own.source.can_bear_load and other.source.can_bear_load
	return rec
