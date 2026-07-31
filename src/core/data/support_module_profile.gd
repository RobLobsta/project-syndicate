class_name SupportModuleProfile
extends Resource
## Support Module payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.5.

enum SupportRole {
	HEAT_SINK = 0,
	MAGAZINE_STORE = 1,
	INTEGRITY_FIELD = 2,
	SIGNATURE_DAMPER = 3,
	REPAIR_EMITTER = 4,
}

@export var role: SupportRole = SupportRole.HEAT_SINK
@export var effect_magnitude: float = 1.0
## 0 means assembly-wide.
@export var effect_radius_m: float = 0.0
@export var activation_cooldown_s: float = 0.0
@export var active_duration_s: float = 0.0
@export var volatile_on_destruction: bool = false
