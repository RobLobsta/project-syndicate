class_name FusionProfile
extends Resource
## How a part participates in seam elimination, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §6.3 and consumed by
## [code]docs/PART_FUSION_SHADER.md[/code].
##
## Architectural Invariant I-7: everything declared here is presentation. None
## of it produces, modifies, or is read by collision.

## Radius of the procedural fillet applied where this part meets a neighbour.
@export var fillet_radius_m: float = 0.045
## Whether this part contributes to the assembly-wide occupancy SDF.
@export var contributes_to_sdf: bool = true
## Whether smart skirting strips may be generated along this part's exposed edges.
@export var accepts_skirting: bool = true
## Only parts sharing a family fuse seamlessly. Cross-family seams receive a
## weld-bead strip instead of a smooth fillet.
@export var fusion_family: StringName = &"plate_std"
## Index into the shared fusion material atlas.
@export var surface_variant: int = 0

## Valid range of [member surface_variant], inclusive lower, exclusive upper.
const SURFACE_VARIANT_COUNT: int = 16
