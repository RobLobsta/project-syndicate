class_name MeleeSolver
extends RefCounted
## Melee strike resolution, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §15.
##
## Pure statics over a [MeleeProfile] and a [MeleeStrikeState]. The physics query
## itself belongs to the effector system, which owns the space; everything that
## decides [i]where[/i] the edge is, [i]whether[/i] a strike lands, and
## [i]what[/i] it delivers is here, because that is the part a test can reach.
##
## A melee module emits no projectile. §15.1 records why a two-metre projectile
## is the wrong implementation and stays wrong every time it looks attractive:
## a projectile is a ray between two positions and an edge is a volume swept
## along an arc, so the ray passes between two adjacent parts of a lattice-built
## Assembly and reports a clean miss where the edge would have cut both.


## Advances the stage machine by one tick and returns the stage now current.
##
## [param cycle_multiplier] is [constant DegradationTable.EFF_CYCLE] at the
## module's band, which scales the whole cycle rather than any one stage: a
## CRITICAL edge swings at 1/1.60 of its rate throughout, wind-up included.
## READY has no arm of the match below and therefore advances nowhere, which is
## the whole guard: an early return for it was removable without a test noticing
## and has been deleted rather than kept as an untested line. The timer that goes
## on accumulating while READY is cleared by [method MeleeStrikeState.begin].
##
## [param hold] is §15.5's sustained contact: true when the module authors
## [member MeleeProfile.sustained] and the trigger is still held. The arc runs
## exactly as it does for a discrete strike and then [b]stays where it ended[/b]
## rather than recovering, which is what "a SWINGING stage that does not advance"
## means and is the whole of the sustained path in this function. Releasing the
## trigger drops the edge into recovery on the next tick, so an edge is never
## stuck alight by a stage machine that has nothing left to advance into.
static func advance(
	state: MeleeStrikeState,
	profile: MeleeProfile,
	cycle_multiplier: float,
	dt: float,
	hold: bool
) -> int:
	state.stage_timer_s += dt
	var scale := maxf(cycle_multiplier, SyndicateConstants.EPSILON_LINEAR)

	match state.stage:
		MeleeStrikeState.Stage.WIND_UP:
			if state.stage_timer_s >= profile.wind_up_s * scale:
				state.stage = MeleeStrikeState.Stage.SWINGING
				state.stage_timer_s = 0.0
				state.swing_t = 0.0
		MeleeStrikeState.Stage.SWINGING:
			var duration := maxf(
				profile.swing_duration_s * scale, SyndicateConstants.EPSILON_LINEAR
			)
			# Not clamped here. The timer only ever rises from zero, so the ratio
			# cannot go negative, and the branch below is what pins an
			# overshooting tick to exactly 1.0 — it is the one owner, and a clamp
			# on this line was removable without a test noticing.
			state.swing_t = state.stage_timer_s / duration
			if state.stage_timer_s >= duration:
				state.swing_t = 1.0
				if hold and profile.sustained:
					# §15.5. The timer is pinned rather than left to accumulate,
					# so the tick the trigger is released is a tick that leaves
					# the swing at once whatever it had run up to.
					state.stage_timer_s = duration
					state.energised = true
				else:
					state.stage = MeleeStrikeState.Stage.RECOVERING
					state.stage_timer_s = 0.0
					state.energised = false
		MeleeStrikeState.Stage.RECOVERING:
			if state.stage_timer_s >= profile.recovery_s * scale:
				state.stage = MeleeStrikeState.Stage.READY
				state.stage_timer_s = 0.0
	return state.stage


## Yaw angle of the edge, in radians, at swing progress [param t].
##
## Sweeps from one end of the authored arc to the other. A profile authoring an
## arc of zero returns zero at every [param t], which is a fixed edge that does
## not swing — what a ram is, with no special case in the caller.
static func swing_yaw_rad(profile: MeleeProfile, t: float) -> float:
	var half := deg_to_rad(profile.swing_arc_deg) * 0.5
	return lerpf(-half, half, clampf(t, 0.0, 1.0))


## Transform of the striking edge at swing progress [param t].
##
## [param mount] is the hardpoint's world transform. The capsule is authored
## along local -Z at [member MeleeProfile.reach_m], matching the muzzle
## convention of §7.2 so that an edge and a barrel agree on which way forward is.
static func edge_transform(profile: MeleeProfile, mount: Transform3D, t: float) -> Transform3D:
	var yawed := mount.rotated_local(Vector3.UP, swing_yaw_rad(profile, t))
	return yawed.translated_local(Vector3(0.0, 0.0, -profile.reach_m * 0.5))


## The [param profile]'s sweep sample points across one swing, as progress
## values in [0, 1].
##
## Fixes the query cost of a swing rather than letting it follow how fast the arc
## happens to travel. Consecutive capsules overlap at every radius the reach
## covers, so there is no gap for a target to sit in.
static func sample_progress(profile: MeleeProfile) -> PackedFloat32Array:
	var count := clampi(profile.swing_samples, 2, MAX_SWING_SAMPLES)
	var out := PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		out[i] = float(i) / float(count - 1)
	return out


## Hard ceiling on sweep segments, mirroring CLAUDE.md §6 I-12.
const MAX_SWING_SAMPLES: int = 16

## Hard ceiling on targets per swing, mirroring CLAUDE.md §6 I-12.
const MAX_TARGETS_PER_SWING: int = 8


## Damage delivered to one channel by one strike.
##
## One packet is submitted per non-zero share rather than one packet carrying a
## blend: document 08's resolver applies resistance per channel, and a blended
## packet would need a second resistance path that does not exist.
static func channel_damage(profile: MeleeProfile, channel: int) -> float:
	if channel < 0 or channel >= profile.channel_mix.size():
		return 0.0
	return profile.strike_damage * profile.channel_mix[channel]


## Damage delivered to one channel over [param dt] of sustained contact.
static func sustained_channel_damage(profile: MeleeProfile, channel: int, dt: float) -> float:
	if not profile.sustained or channel < 0 or channel >= profile.channel_mix.size():
		return 0.0
	return profile.sustained_damage_s * profile.channel_mix[channel] * dt


## True when a strike against a target closing at [param closing_speed_mps]
## should resolve.
##
## A ram authors a positive minimum and does nothing to a target it is not
## driving into; a powered edge authors zero and cuts from a standstill.
static func closing_speed_satisfied(profile: MeleeProfile, closing_speed_mps: float) -> bool:
	return closing_speed_mps >= profile.min_closing_speed_mps


## Impulse delivered to the struck Assembly, along the edge's travel direction.
## An edge with no travel direction delivers nothing. That falls out of
## [method Vector3.normalized], which returns the zero vector rather than a NaN
## for a zero input; the explicit guard this used to carry was dead and fault
## injection said so.
static func strike_impulse(profile: MeleeProfile, travel: Vector3) -> Vector3:
	return travel.normalized() * profile.strike_impulse_ns


## Impulse applied back to the wielder.
##
## What stops melee being a free weapon. A 2800 N·s strike at a reaction ratio of
## 0.35 shoves the wielder back with 980 N·s, which on a light build is a real
## loss of position and on a heavy one is nothing — so melee rewards mass, the
## correct incentive for a weapon whose premise is closing to contact.
static func reaction_impulse(profile: MeleeProfile, travel: Vector3) -> Vector3:
	return -strike_impulse(profile, travel) * clampf(profile.reaction_ratio, 0.0, 1.0)


## Power drawn by the module this tick, in PU.
##
## An edge on an Assembly that cannot afford it is not refused: the emission loop
## already skips a module carrying [constant PartFlags.FLAG_POWER_STARVED], so
## bringing an edge up browns out the rest of the Assembly. That is a decision
## the player makes and feels rather than a message they read.
static func draw_pu(profile: MeleeProfile, energised: bool) -> float:
	return profile.energised_draw_pu if energised else 0.0
