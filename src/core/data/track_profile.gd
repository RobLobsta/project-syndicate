class_name TrackProfile
extends Resource
## Tracked Motive Assembly payload, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §7.2.3.
##
## Carried by a [MotiveAssemblyProfile] whose [member MotiveAssemblyProfile.kind]
## is [constant PartEnums.MotiveKind.TRACKED_SEGMENT], and by no other. The
## semantics are owned by [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §14.
##
## A track is not a wheel that cannot steer. Three things genuinely differ, and
## each of them is why this is its own locomotion family rather than a flag on
## the ground one:
##
## 1. Its contact is a [b]patch[/b], carried on several road stations along the
##    hull, not a point under a hub. Load transfer along the patch is what lets
##    a tracked Assembly cross a ditch a wheel drops into.
## 2. It steers by [b]differential drive[/b]. Both tracked rows in §10.3 author
##    [member MotiveAssemblyProfile.max_steer_angle_deg] as zero, and the
##    validator requires it: a track that steered by angling would be a wheel.
## 3. Turning costs it grip. Slewing a long patch across the ground shears the
##    surface along its whole length, which is real, expensive, and the reason a
##    tracked Assembly turns better in place than at speed.

## ===== CONTACT PATCH ===================================================

## Length of the ground contact patch along the part's rolling axis, in metres.
@export var patch_length_m: float = 1.90
## Road stations distributed along the patch. Each carries one suspension probe
## and one traction contact, so this is the multiplier on a tracked Motive
## Assembly's per-tick cost and is bounded by [constant MAX_ROAD_STATIONS].
@export var road_stations: int = 4
## Fraction of the part's rated load one station carries before the others take
## up the difference. Below 1/road_stations the patch is deliberately soft at
## the ends, which is what makes a track conform to a rise.
@export var station_load_share: float = 0.25

## ===== DRIVE ===========================================================

## Angular rate of the drive sprocket at full throttle, in rad/s. Converted to
## patch speed through [member MotiveAssemblyProfile.contact_radius_m].
@export var sprocket_rad_s: float = 22.0
## Fraction of drive torque one side may take while the other takes the rest.
## 1.0 permits a full counter-rotating pivot; 0.5 permits only a skid turn.
@export var differential_authority: float = 1.0
## Speed above which differential authority tapers to zero, in m/s. A tracked
## Assembly pivots freely at rest and steers progressively less sharply as it
## gains speed, which is what a real transmission does and what stops a fast
## tracked build spinning on the spot.
@export var pivot_taper_mps: float = 9.0

## ===== SHEAR ===========================================================

## Resistance to slewing the patch across the ground, as a torque per metre of
## patch length per newton of normal load. The "bulldozing" term: a long track
## resists turning harder than a short one, at the same weight.
@export var slew_resistance_nm_per_n_m: float = 0.42
## Lateral friction multiplier applied on top of the part's traction
## coefficient. A track resists sliding sideways far better than it resists
## being driven forwards, and above 1.0 is the normal case.
@export var lateral_grip_ratio: float = 1.35
## Fraction of drive force lost to the track's own internal friction. Charged
## before any of it reaches the ground, which is why a tracked Assembly is
## slower than a wheeled one of the same power.
@export var internal_loss: float = 0.08

## Hard ceiling on [member road_stations]. Four Motive Assemblies at eight
## stations each is 32 shape casts on one Assembly, which is already twice what
## a wheeled build of the same part count costs; the validator rejects more.
const MAX_ROAD_STATIONS: int = 8


## Longitudinal offsets of the road stations from the part's pivot, in metres,
## fore to aft.
##
## Evenly spaced across the patch and symmetric about its centre, so a
## four-station patch on a 1.9 m track sits at -0.7125, -0.2375, +0.2375,
## +0.7125. Derived rather than authored: an asymmetric station list would move
## the part's effective contact centre away from its collider without anything
## saying so.
func station_offsets_m() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := maxi(road_stations, 1)
	out.resize(n)
	if n == 1:
		out[0] = 0.0
		return out
	var spacing := patch_length_m / float(n)
	var first := -0.5 * patch_length_m + 0.5 * spacing
	for i in n:
		out[i] = first + spacing * float(i)
	return out


## Differential steering authority available at [param speed_mps].
##
## Tapers linearly from [member differential_authority] at rest to zero at
## [member pivot_taper_mps]. The taper is what separates a pivot from a skid
## turn without either being a special case.
func authority_at_speed(speed_mps: float) -> float:
	if pivot_taper_mps <= 0.0:
		return differential_authority
	var t := clampf(absf(speed_mps) / pivot_taper_mps, 0.0, 1.0)
	return differential_authority * (1.0 - t)
