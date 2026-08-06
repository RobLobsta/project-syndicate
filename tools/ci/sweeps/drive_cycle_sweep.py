#!/usr/bin/env python3
"""Fault sweep over the drive cycle: doc 05 §6.5, §7.7 and §15.5, and doc 11 §7.

Eighteen faults against the laws session 39 landed. The two that matter most are
the two that were *already planted* — the anti-roll couple applied inverted and
§7.7's holding brake read off the raw record — because both shipped for the life
of the project and the entire suite stayed green through them. Planting them back
is the only way to know that the new file actually defends them.

  anti-roll-inverted          §6.5's sign: the bar amplifies roll and the hull goes over
  anti-roll-removed           the bar contributing nothing at all
  anti-roll-both-ends-up      a pure vertical force instead of a couple
  holding-brake-reads-record  §7.7 back on the raw brake key: holding it is worse than not
  holding-brake-ignores-steer §7.7's tracked/ambulatory exemption removed
  brake-release-always-full   §15.5's release gone: the same key cannot reverse
  brake-release-unsigned      the release taken on speed rather than on forward speed
  steer-sign-flipped          §7.1's negation: the wheel turns the wrong way
  steer-rate-instant          the authored 140 deg/s ignored, so lock arrives in one tick
  pitch-ceiling-removed       §7.7's proportioning: a tracked build on its nose
  pad-binding-collides        doc 11 §7.1: the throttle and the trigger on one control
  pad-glyph-family-ignored    §7.2: a Switch player told to press the wrong face button
  garage-stick-orbit-removed  §7.1's garage camera on a controller
  pad-pointer-is-always-mouse §7.3: a controller cannot place a part
  pad-cursor-unclamped        the cursor leaves the view and is never seen again
  driveline-drag-removed      §7.8: releasing everything does almost nothing
  driveline-drag-never-releases  the drag fighting a throttle the driver is holding
  speed-cap-ungoverned        §7.8: the garage advertises a top speed nothing enforces

`anti-roll-removed` and `anti-roll-both-ends-up` are here because
`anti-roll-inverted` alone cannot tell "the sign is asserted" from "the term is
asserted". A test that only ever checks the hull stays upright is satisfied by a
bar that does nothing.

    python3 tools/ci/sweeps/drive_cycle_sweep.py
    python3 tools/ci/sweeps/drive_cycle_sweep.py -j1 --full anti-roll-inverted

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`. Update BASELINE in the same change as anything that moves the
check count, or every fault after it reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

MOTIVE = "src/motion/motive_system.gd"
TRACTION = "src/motion/traction_solver.gd"
SUSPENSION = "src/motion/suspension_solver.gd"
PROMPT = "src/ui/common/input_prompt.gd"
PREVIEW = "src/ui/garage/garage_preview.gd"
PROJECT = "project.godot"
SCREEN = "src/ui/garage/garage_screen.gd"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 7760

FAULTS = [
    # §6.5's sign, back to what shipped. The couple pushes the loaded side further
    # down, and once the inside contact leaves the ground there is no spring left
    # to oppose it -- so the roll diverges rather than merely being soft, and the
    # reference build finishes inverted from a walking pace.
    ("anti-roll-inverted", MOTIVE,
     "		_apply_at(left.probe.global_position, left.normal_world * f)\n"
     "		_apply_at(right.probe.global_position, right.normal_world * -f)",
     "		_apply_at(left.probe.global_position, left.normal_world * -f)\n"
     "		_apply_at(right.probe.global_position, right.normal_world * f)"),

    # The term contributing nothing. A corner assertion that only demands the hull
    # stays upright is satisfied by this, which is why it is planted beside the
    # inversion rather than instead of it.
    ("anti-roll-removed", SUSPENSION,
     "	return stiffness_n_m * ratio * (compression_left_m - compression_right_m)",
     "	return 0.0"),

    # A pure vertical force on the spine instead of a couple: both ends pushed the
    # same way, so the axle is lifted and no load is transferred across it.
    ("anti-roll-both-ends-up", MOTIVE,
     "		_apply_at(right.probe.global_position, right.normal_world * -f)",
     "		_apply_at(right.probe.global_position, right.normal_world * f)"),

    # §7.7 back on the raw record. §15.5 has already taken the service demand to
    # zero at rest, so a driver standing on the brake gets neither brake -- and
    # holding it becomes strictly worse than holding nothing.
    ("holding-brake-reads-record", MOTIVE,
     "		is_zero_approx(input.throttle)\n		and _brake_demand <= 0.0",
     "		is_zero_approx(input.throttle)\n		and is_zero_approx(input.brake)"),

    # §7.7's exemption for the two families that steer by moving. Without it a
    # tracked or walking build asked to pivot on the spot is answered with the
    # brakes.
    ("holding-brake-ignores-steer", MOTIVE,
     "		and not (_steer_moves_hull and not is_zero_approx(input.steer))",
     "		and true"),

    # §15.5's release. A brake that holds a contact at rest also holds it against
    # the reverse drive torque coming off the same key.
    ("brake-release-always-full", TRACTION,
     "	return clampf(\n"
     "		(forward_speed_mps - BRAKE_RELEASE_SPEED_MPS) / BRAKE_RELEASE_BAND_MPS, 0.0, 1.0\n"
     "	)",
     "	return 1.0"),

    # The same law asked for the wrong quantity. Unsigned, a hull already rolling
    # backwards is braked by the key that is reversing it -- which is the familiar
    # failure §15.5 was written to avoid and which reads as "reverse is weak".
    ("brake-release-unsigned", MOTIVE,
     "	var forward_speed := runtime.body.linear_velocity.dot(-runtime.body.global_transform.basis.z)",
     "	var forward_speed := runtime.body.linear_velocity.length()"),

    # §7.1's steering negation. Positive steer is right on every input device, and
    # a positive rotation about the surface normal carries the forward axis left.
    ("steer-sign-flipped", MOTIVE,
     "	var turn := Basis(c.normal_world, -deg_to_rad(_steer_deg[slot]))",
     "	var turn := Basis(c.normal_world, deg_to_rad(_steer_deg[slot]))"),

    # The authored steer rate ignored, so lock arrives in one tick. This is the
    # fault a feel claim has to catch: the geometry is identical and only the
    # transient differs.
    ("steer-rate-instant", MOTIVE,
     "	_steer_deg[slot] = move_toward(_steer_deg[slot], target, step)",
     "	_steer_deg[slot] = target"),

    # §7.7's proportioning ceiling, so the service brake demands whatever the
    # contacts can make. A short, tall build then pitches onto its nose.
    ("pitch-ceiling-removed", TRACTION,
     "	if lever_m <= 0.0:\n		return 0.0",
     "	if true:\n		return INF"),

    # Doc 11 §7.1's per-context rule, planted in the data it governs: the right
    # trigger opens the throttle and pulls the trigger at the same time, which is
    # exactly what the table published before this session.
    ("pad-binding-collides", PROJECT,
     'effector_fire_primary={\n"deadzone": 0.2,\n"events": Array[InputEvent]'
     '([Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"",'
     '"device":32,"window_id":0,"alt_pressed":false,"shift_pressed":false,'
     '"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),'
     '"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,'
     '"pressed":false,"double_click":false,"script":null)\n'
     ', Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"",'
     '"device":0,"button_index":10,"pressure":0.0,"pressed":false,"script":null)',
     'effector_fire_primary={\n"deadzone": 0.2,\n"events": Array[InputEvent]'
     '([Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"",'
     '"device":32,"window_id":0,"alt_pressed":false,"shift_pressed":false,'
     '"ctrl_pressed":false,"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),'
     '"global_position":Vector2(0, 0),"factor":1.0,"button_index":1,"canceled":false,'
     '"pressed":false,"double_click":false,"script":null)\n'
     ', Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"",'
     '"device":0,"axis":5,"axis_value":1.0,"script":null)'),

    # §7.2's family table collapsed to one naming, which is the state every
    # project that has not thought about it is in: a Switch player is told to
    # press A and the button under their thumb is B.
    ("pad-glyph-family-ignored", PROMPT,
     "	var table := PAD_BUTTONS_GENERIC\n"
     "	if family == GamepadFamily.PLAYSTATION:",
     "	var table := PAD_BUTTONS_GENERIC\n"
     "	if false:"),

    # §7.1's garage camera on a controller. A stick held at deflection emits no
    # further events, so removing the poll leaves the garage with no camera
    # control on a pad at all.
    ("garage-stick-orbit-removed", PREVIEW,
     "	var stick := Vector2(\n"
     "		ControlSystem.axis(ACTION_LOOK_LEFT, ACTION_LOOK_RIGHT),\n"
     "		ControlSystem.axis(ACTION_LOOK_UP, ACTION_LOOK_DOWN)\n"
     "	)\n"
     "	if stick.is_zero_approx():\n		return",
     "	var stick := Vector2.ZERO\n"
     "	if true:\n		return"),

    # §7.3's one substitution, undone: the placement pointer is the mouse again
    # whatever device the player is holding, which is the state the garage shipped
    # in for the life of the project.
    ("pad-pointer-is-always-mouse", SCREEN,
     "	if InputMethod.is_gamepad() and preview != null:\n		return preview.pad_cursor()",
     "	if false and preview != null:\n		return preview.pad_cursor()"),

    # The clamp. A cursor that can leave the viewport is a cursor a player loses,
    # with no way to find it again and no feedback that it has gone.
    ("pad-cursor-unclamped", PREVIEW,
     "	_pad_cursor = (_pad_cursor + stick * rate * dt).clamp(Vector2.ZERO, view)",
     "	_pad_cursor = _pad_cursor + stick * rate * dt"),

    # §7.8's driveline drag, back to rolling resistance alone -- 0.14 m/s2, so a
    # build released at four metres a second coasts for half a minute.
    ("driveline-drag-removed", TRACTION,
     "	return DRIVELINE_DRAG_FRACTION * absf(drive_capacity_nm) * lift * taper",
     "	return 0.0"),

    # The release taper, back to the bare `1 - |throttle|` that shipped for one
    # suite run: the drag then cancels the drive at a quarter throttle and a demand
    # to accelerate retards the Assembly.
    ("driveline-drag-never-releases", TRACTION,
     "	var lift := clampf(\n"
     "		1.0 - absf(throttle) / DRIVELINE_DRAG_RELEASE_THROTTLE, 0.0, 1.0\n"
     "	)",
     "	var lift := 1.0 - clampf(absf(throttle), 0.0, 1.0)"),

    # §7.8's governor. The garage publishes `speed_cap_mps` as a projected top
    # speed and the simulation ignores it, which is the state this session found.
    ("speed-cap-ungoverned", TRACTION,
     "	return clampf((cap_mps - speed_mps) / SPEED_CAP_BAND_MPS, 0.0, 1.0)",
     "	return 1.0"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
