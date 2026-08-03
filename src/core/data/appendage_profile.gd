class_name AppendageProfile
extends Resource
## The class payload for [constant PartEnums.PartClass.APPENDAGE], owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §7.8.
##
## An Appendage is an articulated arm that [i]carries[/i] an Effector Module
## rather than bolting it to structure. It is not a Motive Assembly: it does not
## propel the Assembly, has no locomotion family, and is never handed to a solver
## in [code]docs/DYNAMIC_MASS_PHYSICS.md[/code]. It is not a Structural Component
## either, because a bracket cannot swing what it carries and cannot be graded on
## how well it holds it.
##
## [b]It adds no joint.[/b] Architectural Invariant I-3 holds exactly as it does
## for an ambulatory limb: the arm's articulation is inverse kinematics under
## [code]VisualRoot[/code] and its collider is authored, fixed, and never moves
## from placement to destruction. What actually swings is the melee sweep query
## of doc 07 §15.3, which is a query and not a body — the same distinction that
## lets a hardpoint rotate without I-1 noticing.
##
## Every field here has a live consumer. The unarmed capabilities an arm
## obviously wants — block, punch, grab, throw — are deliberately [b]not[/b]
## present: doc 07 §16 records the design and CLAUDE.md §10 rule 16 forbids
## authoring the parameters before anything reads them.

## ===== GRIP ============================================================

## Static load the hand transmits before the joint is over-rated, in newtons.
##
## Read by validator rule 25, which refuses a build whose held Effector Module
## weighs more than the arm can hold. This is the number that makes a heavy
## weapon a real choice rather than a free upgrade: a bigger edge needs a bigger
## arm, and the arm costs mass on the same Assembly.
@export var grip_rating_n: float = 9000.0

## Distance from the shoulder cell to the hand, in metres.
##
## Read by [method held_edge_origin_offset] and through it by the melee sweep,
## which starts the edge at the hand rather than at the module's own pivot. An
## arm that reaches further puts the same edge further from the hull, which is
## the whole mechanical point of holding a weapon instead of bolting it on.
@export var reach_m: float = 1.60


## ===== DEGRADATION =====================================================

## Whether damage to this Appendage degrades the Effector Module it holds.
##
## True on every shipped arm. It exists as a field rather than as an assumption
## because doc 08 §8.2's Appendage row is a property of the [i]arm[/i], and a
## fixed pylon that merely carries a pod should not slow the pod down when it is
## dented. Read by [EffectorSystem] when it resolves a held module's holder.
@export var degrades_held_effector: bool = true


## Offset from the Appendage's pivot cell to the hand, along the arm's own
## forward axis.
##
## The melee edge is authored along local -Z (doc 07 §7.2's muzzle convention,
## which §15.2 shares), so the hand sits one reach along -Z. Returning a
## [Vector3] rather than the bare float keeps the convention in one place instead
## of in every caller that has to remember which way an arm points.
func held_edge_origin_offset() -> Vector3:
	return Vector3(0.0, 0.0, -reach_m)
