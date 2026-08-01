class_name SyndicateConstants
extends RefCounted
## Global constants owned by [code]docs/PART_DATA_SCHEMA.md[/code] §3.
##
## No subsystem may redefine any value here locally. Every dimension in the part
## tables is expressed in lattice cells, never metres; metre values are derived
## at load time by multiplication so that a future rescale of the lattice is a
## one-constant change.

## ===== SPATIAL LATTICE ================================================

## Edge length of one Build Lattice cell, in metres. An exact binary fraction,
## so cell/metre conversions round-trip without accumulating error.
const LATTICE_UNIT_M: float = 0.25

## Lattice dimensions in cells: 12.0 m x 8.0 m x 12.0 m.
const LATTICE_EXTENT: Vector3i = Vector3i(48, 32, 48)

## Cell holding the Assembly origin. Offset below centre in Y to leave headroom
## above and clearance below for Motive Assemblies.
const LATTICE_ORIGIN_CELL: Vector3i = Vector3i(24, 4, 24)

## Size of the proper octahedral rotation group. See docs/GRID_SNAPPING_LOGIC.md §4.
const ORIENTATION_COUNT: int = 24

## ===== ASSEMBLY LIMITS ================================================

const MAX_PARTS_PER_ASSEMBLY: int = 255  # slots 0..254
const INVALID_SLOT: int = 255
const CORE_SLOT: int = 0
const MAX_EFFECTORS_PER_ASSEMBLY: int = 16
const MAX_MOTIVE_PER_ASSEMBLY: int = 24

## ===== SIMULATION CADENCE =============================================

## Gravitational acceleration used by every simulated system, in m/s^2.
##
## Declared here rather than read from [code]ProjectSettings[/code] because the
## strain model, the suspension load split, and the ballistic solver must all
## agree on it exactly, and a project setting can be changed by an editor action
## that touches no code.
const GRAVITY_MPS2: float = 9.81

const PHYSICS_HZ: int = 60
const PHYSICS_DT: float = 1.0 / 60.0
const NET_SNAPSHOT_HZ: int = 30
const NET_INPUT_HZ: int = 60

## ===== INTEGRITY BANDS ================================================
## Fractions of maximum structural integrity at which a part changes band.

const BAND_STRESSED: float = 0.75
const BAND_IMPAIRED: float = 0.50
const BAND_CRITICAL: float = 0.30
const BAND_DESTROYED: float = 0.0

## ===== NUMERIC HYGIENE ================================================

const EPSILON_LINEAR: float = 0.0001
const EPSILON_ANGULAR: float = 0.00017453  # ~0.01 degrees in radians
