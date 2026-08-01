class_name DegradationTable
extends RefCounted
## The canonical functional-degradation table, owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §8.3.
##
## Architectural Invariant I-5: every subsystem indexes this table by the cached
## [member PartInstanceState.integrity_band] integer. No subsystem defines its
## own thresholds or curves, and no hot loop reads integrity or computes a band.
##
## Every array is length [constant PartEnums.INTEGRITY_BAND_COUNT], indexed by
## [enum PartEnums.IntegrityBand], and terminates at zero on DESTROYED — a
## destroyed part contributes nothing, and the terminal zero is what lets a
## degradation multiplier be applied without a branch on destruction.
##
## The two mandated behaviours of the design brief are here verbatim: a Motive
## Assembly below 50% integrity is IMPAIRED and loses 40% of its traction
## ([constant MOTIVE_TRACTION] index 2 is 0.60), and an Effector Module below 30%
## is CRITICAL and gains an 18% per-shot jam chance ([constant EFF_JAM] index 3).

## ===== MOTIVE ASSEMBLY =================================================
## Read by every locomotion family, not only the ground one. A rotor at
## IMPAIRED loses 40% of its thrust and a limb 40% of its foot grip, both
## through [constant MOTIVE_TRACTION]. Splitting the table per family so the
## four could drift apart would be a balance liability, not a modelling gain.

const MOTIVE_TRACTION: Array[float] = [1.00, 0.88, 0.60, 0.35, 0.00]
const MOTIVE_ROLLING: Array[float] = [1.00, 1.00, 1.35, 1.90, 0.00]
const MOTIVE_STEER: Array[float] = [1.00, 1.00, 1.00, 0.50, 0.00]
const MOTIVE_SUSP_DAMP: Array[float] = [1.00, 1.00, 1.00, 0.60, 0.00]

## ===== EFFECTOR MODULE =================================================

const EFF_SLEW: Array[float] = [1.00, 0.92, 0.74, 0.45, 0.00]
const EFF_CYCLE: Array[float] = [1.00, 1.06, 1.22, 1.60, 0.00]
const EFF_SPREAD: Array[float] = [1.00, 1.15, 1.45, 2.10, 0.00]
const EFF_JAM: Array[float] = [0.00, 0.00, 0.00, 0.18, 0.00]

## ===== POWER PLANT =====================================================

const POWER_TORQUE: Array[float] = [1.00, 0.90, 0.68, 0.38, 0.00]
const POWER_SUPPLY: Array[float] = [1.00, 0.94, 0.75, 0.45, 0.00]
const POWER_HEAT: Array[float] = [1.00, 1.12, 1.38, 1.85, 0.00]

## ===== SUPPORT, CONTROL, CORE, STRUCTURE ===============================

const SUPPORT_MAGNITUDE: Array[float] = [1.00, 0.88, 0.62, 0.30, 0.00]
const CONTROL_COEFF: Array[float] = [1.00, 0.85, 0.55, 0.20, 0.00]
const CORE_AUTHORITY: Array[float] = [1.00, 0.95, 0.82, 0.60, 0.00]
const CORE_SPEED_CAP: Array[float] = [1.00, 1.00, 0.90, 0.72, 0.00]
const STRUCT_LOAD: Array[float] = [1.00, 0.90, 0.65, 0.30, 0.00]
const STRUCT_JOINT: Array[float] = [1.00, 0.92, 0.70, 0.35, 0.00]

## ===== ALL CLASSES =====================================================
## Armour degrades with integrity across every class, so a battered panel
## becomes progressively easier to penetrate. The first hits are absorbed and
## later ones go through, which is the escalation the damage model wants.

const ARMOUR_RATING: Array[float] = [1.00, 0.94, 0.80, 0.58, 0.00]


## Every table in the file, paired with its name, for
## [code]tests/unit/test_degradation_table.gd[/code].
##
## A table absent from this list is a table nothing checks the length,
## monotonicity, or terminal zero of, so the test asserts the list's own size
## against the count below. Adding a table without listing it fails the suite.
static func all_tables() -> Dictionary:
	return {
		&"MOTIVE_TRACTION": MOTIVE_TRACTION,
		&"MOTIVE_ROLLING": MOTIVE_ROLLING,
		&"MOTIVE_STEER": MOTIVE_STEER,
		&"MOTIVE_SUSP_DAMP": MOTIVE_SUSP_DAMP,
		&"EFF_SLEW": EFF_SLEW,
		&"EFF_CYCLE": EFF_CYCLE,
		&"EFF_SPREAD": EFF_SPREAD,
		&"EFF_JAM": EFF_JAM,
		&"POWER_TORQUE": POWER_TORQUE,
		&"POWER_SUPPLY": POWER_SUPPLY,
		&"POWER_HEAT": POWER_HEAT,
		&"SUPPORT_MAGNITUDE": SUPPORT_MAGNITUDE,
		&"CONTROL_COEFF": CONTROL_COEFF,
		&"CORE_AUTHORITY": CORE_AUTHORITY,
		&"CORE_SPEED_CAP": CORE_SPEED_CAP,
		&"STRUCT_LOAD": STRUCT_LOAD,
		&"STRUCT_JOINT": STRUCT_JOINT,
		&"ARMOUR_RATING": ARMOUR_RATING,
	}


## Number of tables [method all_tables] must report.
const TABLE_COUNT: int = 18

## Tables that rise with damage rather than falling. Every other table is
## non-increasing; these describe a cost, not a capability, and a longer cycle
## time or a higher jam chance at a lower band is the intended direction.
const NON_DECREASING: Array[StringName] = [
	&"MOTIVE_ROLLING",
	&"POWER_HEAT",
	&"EFF_CYCLE",
	&"EFF_SPREAD",
	&"EFF_JAM",
]


## Multiplier from [param table] at [param band], with the band clamped into
## range.
##
## The clamp exists because a band arriving from the network is a 3-bit field
## (doc 01 §13.2) and a corrupt packet must degrade a part rather than crash a
## server. Gameplay code that already holds a validated band should index the
## array directly; this is for the boundaries.
static func multiplier(table: Array[float], band: int) -> float:
	return table[clampi(band, 0, PartEnums.INTEGRITY_BAND_COUNT - 1)]
