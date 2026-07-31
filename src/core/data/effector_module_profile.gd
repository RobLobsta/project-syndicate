class_name EffectorModuleProfile
extends Resource
## Effector Module payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.4.
## Full firing semantics are in [code]docs/WEAPON_TARGETING_LOGIC.md[/code].

@export var kind: PartEnums.EffectorKind = PartEnums.EffectorKind.BALLISTIC_DIRECT

## ===== HARDPOINT =======================================================
## The two-DOF rotational mount internal to this module. This is the only
## permitted use of the term "hardpoint".
@export var yaw_limit_deg: Vector2 = Vector2(-180.0, 180.0)
@export var pitch_limit_deg: Vector2 = Vector2(-8.0, 34.0)
@export var yaw_rate_deg_s: float = 65.0
@export var pitch_rate_deg_s: float = 48.0

## ===== EMISSION ========================================================
@export var muzzle_offsets_m: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0.6)])
@export var projectile_key: StringName = &"proj.kinetic.ap_30"
@export var muzzle_velocity_mps: float = 940.0
@export var cycle_time_s: float = 0.14
## 0 means continuous fire.
@export var burst_count: int = 0
@export var burst_recovery_s: float = 0.0
## 0 means no magazine model.
@export var magazine_rounds: int = 0
@export var reload_time_s: float = 0.0

## ===== DISPERSION AND RECOIL ===========================================
@export var spread_base_deg: float = 0.25
@export var spread_bloom_deg: float = 0.09
@export var spread_decay_deg_s: float = 0.55
@export var recoil_impulse_ns: float = 1450.0

## ===== THERMAL =========================================================
@export var heat_per_shot_hu: float = 7.5
@export var jam_clear_time_s: float = 1.6
