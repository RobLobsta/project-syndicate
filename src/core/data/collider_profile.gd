class_name ColliderProfile
extends Resource
## The complete physics geometry of a part, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §6.2.
##
## Architectural Invariant I-1 in full: physics never touches a visual mesh.
## Colliders do not change with damage state, visual LOD, hardpoint rotation,
## animation, or fusion displacement — a part's physical footprint is fixed from
## placement to destruction.

## Hard ceiling. The registry validator rejects any profile exceeding this.
const MAX_PRIMITIVES_PER_PART: int = 3

## Union of primitives must cover at least this fraction of the part's occupancy
## volume. Prevents "phantom gap" exploits where shots pass through a part.
const MIN_COVERAGE_RATIO: float = 0.82

## ...and at most this, preventing oversized invisible hitboxes.
const MAX_COVERAGE_RATIO: float = 1.18

@export var primitives: Array[ColliderPrimitiveDef] = []


## Summed primitive volume in cubic metres. Overlap between primitives is not
## subtracted; the coverage band in §6.2 is calibrated against this measure.
func total_volume_m3() -> float:
	var sum := 0.0
	for p in primitives:
		sum += p.volume_m3()
	return sum
