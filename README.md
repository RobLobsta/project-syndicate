# Project Syndicate

**Build a machine. Take it apart with someone else's machine.**

Project Syndicate is a 3D multiplayer vehicle-assembly combat game built in Godot 4. You assemble a fighting machine module by module in the garage — chassis, drive, power, weapons, armour — then take it into a match where every one of those modules can be shot off individually.

There is no health bar. There is a vehicle, and there are the parts it is made of, and each part fails on its own terms.

---

## The Loop

**Build.** Snap modules onto a fine 3D lattice. Rotate them through 24 orientations. Watch mass, power draw, mount budget, and stability update as you go. The garage tells you what your machine will actually do before you commit to it — projected top speed, the lateral acceleration at which it tips, which weapons can actually see past your own armour.

**Fight.** Drive it. Localised damage means the fight is about *where* you hit, not how much. Shoot the drive units off a runner. Punch through thin frontal plate to spall the power plant behind it. Cook a magazine and watch the whole rear section come apart.

**Watch it fall apart.** When a structural member dies, everything hanging off it that has no other path back to the Core Module tears free — with the right velocity, tumbling the right way, still wearing the same armour it had a second ago. The exposed edges stop looking welded and start looking torn.

**Rebuild.** Take what you learned back to the garage.

---

## What Makes It Different

### Damage that means something specific

Five damage channels — kinetic, blast, impact, thermal, corrosive — each resolving differently against each module. Sloped armour genuinely deflects. Penetration is a real threshold with a real cliff. Overpenetrating rounds throw spall into whatever is behind the plate they just went through.

Modules degrade in stages rather than working perfectly until they explode:

- A drive unit under 50% integrity sparks against the ground and loses 40% of its traction.
- A weapon under 30% starts to jam.
- A power plant losing integrity produces less torque, runs hotter, and eventually catches fire.
- Armour that has already absorbed hits is easier to penetrate on the next one.

You feel a machine failing before you lose it.

### Vehicles that look welded, not assembled

Parts snap to a grid, but they don't *look* like they snap to a grid. A signed-distance field of your machine's solid volume drives vertex displacement and procedural filleting along every internal join, with generated skirting geometry filling the corners a flat panel can't. Adjacent hull panels blend into one continuous welded body.

Then something shoots a hole in it, and the raw blocky structure underneath is exactly what you see.

### Four ways to move, and none of them bolted on

Wheels, tracks, rotors, and legs are the same part class, mounted through the same drive station, simulated on the same single rigid body. What changes is only how each one turns intent into force.

Rotors work by momentum theory: thrust from disc area and tip speed, a swashplate you tilt to accelerate, ground effect that lets a heavy machine lift off but not climb out, extra lift once you get moving forward, and a settling descent that drops you into your own downwash until you fly out of it. Point the disc where you want to go and the machine goes there because the thrust vector moved, not because a "fly" function moved it.

Legs walk on a spring-loaded inverted pendulum with real foot placement — plant ahead of neutral to brake, behind it to accelerate, off-axis to turn. There is no yaw torque anywhere in the walking code; a machine turns because its feet land somewhere else. Ask one to stand still and it stands on every foot instead of marching in place.

Tracks steer by driving their two sides at different rates, freely at a standstill and barely at all once you're moving, and a long track shears the ground along its whole length when you try to turn it. A heavy tracked machine is *committed*, and that is the price of everything else it gets.

And a beam blade cuts by sweeping a volume, mostly thermal, which is why it goes through light plate and struggles against composite — and why holding it lit browns out the rest of your machine.

### Ground and structures that remember

Explosions carve craters into the terrain — real bowls with raised ejecta rims, permanent for the rest of the match. Crater interiors are worse to drive through. Crater rims are cover.

Structures fracture along pre-computed fault lines into individual sections, and sections that lose their path to the ground come down. A corner can collapse while the rest of the building stands. Beam and melee weapons cut fresh geometry through fragments in real time.

### Auto-assemble

Don't want to build? Pick an archetype — skirmisher, brawler, artillery, bastion, harrier, support, rotorcraft, strider — a budget, and a tier ceiling. A constraint solver builds you a legal, competent machine from parts you actually own, using the same placement rules your cursor uses. Or lock the parts you've already placed and let it finish the job around them.

---

## Under the Hood

Project Syndicate is engineered as a deliberate answer to how construction-combat games have historically fallen apart at scale. The technical positions worth knowing about:

| Problem | Position |
|---|---|
| Vehicles that wobble, sag, and vibrate apart | **One rigid body per vehicle.** No joints between parts. Structural failure is a graph event, not a physics constraint that might fail to converge. |
| Frame drops from connectivity checks | **Event-driven structural graph.** It performs zero work until a part actually dies. A quiet match costs nothing. |
| Hit registration that fights the art | **Decoupled collision.** Physics runs on low-poly primitive boxes and cylinders. High-fidelity meshes sit inside with collision disabled and never influence the simulation. |
| Hitches when the world changes | **Everything expensive runs on worker threads** under hard per-frame commit budgets — terrain deformation, fusion bakes, geometry slicing, vehicle generation. |
| Blocky interlocking-brick aesthetics | **Procedural fusion shading and smart skirting** at the presentation layer only, with zero competitive impact. |
| Network divergence | **Server-authoritative headless simulation** with client prediction, deterministic derivation of debris and terrain from replicated events, and explicit degradation-state replication. Around 10 KB/s down. |

Full architecture — 13 documents covering data schemas, math, shaders, and pipelines — lives in [`docs/`](docs/).

---

## Platform and Performance

| | |
|---|---|
| **Engine** | Godot 4, GDScript, Forward+ (Compatibility renderer on mobile) |
| **Platforms** | Windows, Linux, macOS, Android, iOS |
| **Multiplayer** | Dedicated headless server, 16 players, 60 Hz simulation, 30 Hz snapshots |
| **Input** | Keyboard + mouse, gamepad, touch — all fully supported, all detected automatically |
| **Interface** | Single responsive layout across four breakpoints, from phone landscape to ultrawide |

Visual quality settings scale from full fusion shading with procedural skirting down to flat greybox primitives. **None of them affect gameplay.** Hit registration, damage, mass, and handling are identical at every setting.

---

## Repository Layout

```
docs/         13 architecture specification documents
src/          All GDScript, organised by subsystem
scenes/       Godot scenes
data/         Part definitions, archetypes, themes, balance tables
assets/       Imported art
art_src/      DCC source files (never shipped)
tools/        Validators, bake scripts, CI checks
tests/        Unit, integration, physics, generation, and architecture conformance tests
CLAUDE.md     Engineering source of truth — read this before contributing
```

---

## Building and Running

```bash
# Open in the editor
godot --editor --path .

# Run the client
godot --path .

# Run a dedicated server
godot --headless --path . --main-scene res://scenes/net/dedicated_server.tscn \
      -- --port=27015 --max-players=16 --map=arena_basin

# Run the full validation suite
godot --headless --path . --script tools/ci/run_all_checks.gd
```

---

## Documentation Map

| Document | Covers |
|---|---|
| [PART_DATA_SCHEMA](docs/PART_DATA_SCHEMA.md) | The part registry, module attributes, and every mass/integrity/resistance table |
| [GRID_SNAPPING_LOGIC](docs/GRID_SNAPPING_LOGIC.md) | The build lattice, 24-orientation rotation, and placement safety checks |
| [PART_FUSION_SHADER](docs/PART_FUSION_SHADER.md) | Occupancy SDF, vertex displacement, and smart skirting meshes |
| [DEPENDENCY_TREE_GRAPH](docs/DEPENDENCY_TREE_GRAPH.md) | Structural connectivity, strain, and event-driven detachment |
| [DYNAMIC_MASS_PHYSICS](docs/DYNAMIC_MASS_PHYSICS.md) | Centre-of-mass shifting, suspension load, traction, and stutter elimination |
| [AUTO_ASSEMBLE_ALGORITHM](docs/AUTO_ASSEMBLE_ALGORITHM.md) | Constraint-based procedural vehicle generation |
| [WEAPON_TARGETING_LOGIC](docs/WEAPON_TARGETING_LOGIC.md) | Hardpoint limits, aim solving, ballistic lead, and projectile emission |
| [COMPONENT_HEALTH_DAMAGE](docs/COMPONENT_HEALTH_DAMAGE.md) | Damage channels, functional degradation, and visual damage states |
| [TERRAIN_CRATER_DEFORMER](docs/TERRAIN_CRATER_DEFORMER.md) | Permanent runtime heightfield cratering |
| [PROCEDURAL_STRUCTURE_SLICING](docs/PROCEDURAL_STRUCTURE_SLICING.md) | Structure fracture, collapse, and runtime geometry slicing |
| [RESPONSIVE_GARAGE_UI](docs/RESPONSIVE_GARAGE_UI.md) | Container layouts, breakpoints, and cross-input support |
| [HEADLESS_NETWORK_SYNC](docs/HEADLESS_NETWORK_SYNC.md) | Authority, replication, prediction, and lag compensation |
| [EXTENSION_PIPELINE](docs/EXTENSION_PIPELINE.md) | Swapping primitive proxies for final 3D models |

---

## Contributing

Read [`CLAUDE.md`](CLAUDE.md) first. It is the binding engineering contract for this repository: directory structure, naming conventions, GDScript style, the input action standard, and twelve core system invariants that code may not violate.

Then read the document in [`docs/`](docs/) that owns the subsystem you're touching. Each one specifies exact data structures, formulas, and performance budgets, and each one owns a specific set of constants that must not be duplicated elsewhere.

Automated conformance tests in `tests/arch/` enforce the non-negotiable rules — no per-frame structural polling, no mesh-derived collision, no runtime CSG, no global RNG in gameplay, no duplicated constants. They run in CI and they block merges.

---

## Terminology

Project Syndicate uses generic engineering nomenclature throughout, in code and in the interface:

| Term | What it is |
|---|---|
| **Core Module** | The command module. Root of every machine. Lose it, lose the vehicle. |
| **Structural Component** | Panels, beams, wedges, frames — the armour and skeleton. |
| **Motive Assembly** | Wheels, tracks, legs, repulsors. Whatever puts you in motion. |
| **Prime Mover** | Combustion units, turbines, reaction drives. Shaft torque. |
| **Energy Cell** | Static cells and reservoirs. Power supply, and no torque at all. |
| **Effector Module** | Weapons. Ballistic, arced, beam, guided, melee. |
| **Support Module** | Heat sinks, magazine stores, integrity fields, repair emitters. |
| **Control Surface** | Spoilers, vanes, diffusers. Downforce and drag. |
| **Assembly** | Your machine, as a whole. |
| **Dynamic Ground Array** | The terrain. Deformable, and it remembers. |
| **Static Volume** | A world structure. Fracturable, and it can fall on you. |

---

*Project Syndicate is in active architecture and development.*
