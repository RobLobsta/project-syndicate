# EXTENSION_PIPELINE.md

**Project Syndicate — System Architecture Specification, Document 13 of 13**
**Subsystem:** Asset Maturity Pipeline — Primitive Proxy to Final Mesh
**Status:** Normative.

---

## 1. Purpose and the Core Guarantee

Project Syndicate is built greybox-first. Every part in the registry exists and is fully playable from the moment its data row is written, represented by primitive geometry. Final art is swapped in later, part by part, in any order, at any time, by anyone — without touching gameplay code, without rebalancing, and without a single line of the simulation changing behaviour.

That guarantee rests on one structural fact established in `PART_DATA_SCHEMA.md` §6.2 and repeated in every document since:

> **The visual mesh and the collision geometry are separate, independently authored assets. Physics reads `ColliderProfile`. Rendering reads `PartVisualProfile`. Neither derives from the other.**

Swapping a proxy cylinder for a 4 000-triangle sculpted wheel changes what the player sees. It changes nothing the player can measure — not hit registration, not mass, not the lattice footprint, not the firing arc, not the network format. This document specifies the workflow that keeps that true.

---

## 2. The Three Maturity Stages

Every part carries a maturity stage in its `PartVisualProfile`. All three stages are shippable; the game is playable end-to-end at any mix.

| Stage | Source | Geometry | Material | Fusion support | Typical use |
|---|---|---|---|---|---|
| `STAGE_PROXY` | Procedural, generated at load | CSG-equivalent primitives (box, cylinder, capsule, sphere) built as `ArrayMesh` | Flat greybox material with class tint | None (blocky by design) | New part, day one |
| `STAGE_BLOCKOUT` | Baked from a CSG composition in the editor | Single welded `ArrayMesh`, 150–600 tris | Shared blockout material, triplanar | Partial — SDF blending on, no skirting | Silhouette locked, art not started |
| `STAGE_FINAL` | Authored `.glb` from a DCC tool | LOD chain, 400–4 800 tris at LOD0 | Atlas-based PBR through the fusion shader | Full | Shipping art |

```gdscript
class_name PartVisualProfile
extends Resource

enum Stage { PROXY = 0, BLOCKOUT = 1, FINAL = 2 }

@export var stage: Stage = Stage.PROXY

## --- STAGE_PROXY -------------------------------------------------------
@export var proxy_primitives: Array[ProxyPrimitiveDef] = []
@export var proxy_tint: Color = Color(0.55, 0.58, 0.62)

## --- STAGE_BLOCKOUT ----------------------------------------------------
@export var blockout_mesh: ArrayMesh = null

## --- STAGE_FINAL -------------------------------------------------------
@export var mesh_nominal: Mesh = null
@export var mesh_impaired: Mesh = null
@export var mesh_critical: Mesh = null
@export var lod_distances_m: PackedFloat32Array = PackedFloat32Array([18.0, 42.0, 90.0])
@export var atlas_variant: int = 0
@export var casts_shadow: bool = true

## --- Shared ------------------------------------------------------------
@export var visual_offset_m: Vector3 = Vector3.ZERO
@export var visual_scale: Vector3 = Vector3.ONE
@export var attachment_marker_names: PackedStringArray = PackedStringArray()
```

### 2.1 Proxy Generation

A `STAGE_PROXY` part's mesh is generated at load from its primitive list. Crucially, the proxy primitives default to **mirroring the `ColliderProfile`** — so a brand-new part with only collider data authored already renders as exactly the shape it collides as.

```gdscript
class_name ProxyMeshBuilder
extends RefCounted

static func build(def: PartDefinition) -> ArrayMesh:
    var prims := def.visual_profile.proxy_primitives
    if prims.is_empty():
        prims = _mirror_collider(def.collider_profile)
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for p in prims:
        var sub := _primitive_mesh(p)
        st.append_from(sub, 0, _primitive_transform(p))
    st.generate_normals()
    st.generate_tangents()
    st.index()
    return st.commit()

static func _mirror_collider(cp: ColliderProfile) -> Array[ProxyPrimitiveDef]:
    var out: Array[ProxyPrimitiveDef] = []
    for prim in cp.primitives:
        var d := ProxyPrimitiveDef.new()
        d.kind = prim.kind
        d.half_extents_m = prim.half_extents_m
        d.radius_m = prim.radius_m
        d.height_m = prim.height_m
        d.local_offset_m = prim.local_offset_m
        d.local_basis_euler_deg = prim.local_basis_euler_deg
        out.push_back(d)
    return out

static func _primitive_mesh(p: ProxyPrimitiveDef) -> Mesh:
    match p.kind:
        ColliderPrimitiveDef.PrimitiveKind.BOX:
            var b := BoxMesh.new(); b.size = p.half_extents_m * 2.0; return b
        ColliderPrimitiveDef.PrimitiveKind.CYLINDER:
            var c := CylinderMesh.new()
            c.top_radius = p.radius_m; c.bottom_radius = p.radius_m
            c.height = p.height_m; c.radial_segments = 12; return c
        ColliderPrimitiveDef.PrimitiveKind.CAPSULE:
            var cp := CapsuleMesh.new()
            cp.radius = p.radius_m; cp.height = p.height_m
            cp.radial_segments = 12; return cp
        _:
            var s := SphereMesh.new()
            s.radius = p.radius_m; s.height = p.radius_m * 2.0
            s.radial_segments = 12; s.rings = 6; return s
```

The generated mesh is cached per `part_def_id` in `ProxyMeshCache`, so 40 instances of the same panel share one `ArrayMesh` resource. Round primitives are built at `RADIAL_SEGMENTS = 12` and `SPHERE_RINGS = 6` rather than at Godot's defaults, which are 64 radial segments on a `CylinderMesh` — five times the triangles, for geometry whose entire purpose is to be replaced.

#### Class Tints

`GreyboxMaterial.for_class` gives each part class a base tint, modulated toward the part's authored `proxy_tint` by `AUTHORED_TINT_WEIGHT = 0.35`. The weight is what keeps a class recognisable: an authored tint shifts a part *within* its class rather than out of it.

| Part class | Tint | Reads as |
|---|---|---|
| `CORE_MODULE` | `#6E7C8C` | pale steel |
| `STRUCTURAL_COMPONENT` | `#8A8F96` | neutral |
| `MOTIVE_ASSEMBLY` | `#4A4E55` | charcoal |
| `PRIME_MOVER` | `#9A7A46` | brass |
| `EFFECTOR_MODULE` | `#6B6F63` | olive gunmetal |
| `SUPPORT_MODULE` | `#5E807A` | teal |
| `CONTROL_SURFACE` | `#7E93A8` | pale blue |
| `ENERGY_CELL` | `#4F8C86` | cyan-green |
| `APPENDAGE` | `#857D74` | warm grey |

The table exists for **legibility**, not decoration. A greybox Assembly rendered in a single grey is a silhouette with no parts in it: a player cannot see where the Prime Mover they are supposed to be protecting sits, and neither can anyone reading a screenshot attached to a bug report. Nine hues that survive being small, desaturated, and lit from one direction are worth more here than nine attractive ones.

This mirroring default is worth dwelling on. It means the greybox build is *visually honest* — what you see is exactly what you hit. Divergence between visual and collider only appears deliberately, at `STAGE_FINAL`, and the validator in §7 measures and bounds it.

### 2.2 Blockout Baking

Blockouts are authored as CSG in the editor and baked with the same utility the Static Volume pipeline uses:

```gdscript
# tools/bake_part_blockout.gd — editor tool script
@tool
extends EditorScript

func _run() -> void:
    var sel := EditorInterface.get_selection().get_selected_nodes()
    for node in sel:
        if node is not CSGCombiner3D:
            push_warning("Skipping %s: not a CSGCombiner3D" % node.name)
            continue
        var mesh := node.bake_static_mesh()
        mesh = MeshOptimiser.weld_and_reduce(mesh, 600)
        var out_path := "res://data/parts/%s/blockout/%s.res" % [
            _class_dir(node), node.name]
        ResourceSaver.save(mesh, out_path)
        print("Baked blockout: %s (%d tris)" % [out_path, _tri_count(mesh)])
```

As with Static Volumes, **the CSG nodes never ship**. They live in `art_src/`, are baked to `ArrayMesh` resources, and the source scene is excluded from export presets.

---

## 3. Directory Layout

```
project-syndicate/
├── art_src/                              ← NOT exported; DCC sources and CSG scenes
│   ├── parts/
│   │   ├── str_panel_medium_t2/
│   │   │   ├── str_panel_medium_t2.blend
│   │   │   ├── blockout.tscn             (CSGCombiner3D composition)
│   │   │   └── textures_src/
│   │   └── ...
│   └── static_volumes/
├── assets/                               ← exported; imported by Godot
│   ├── parts/
│   │   ├── core/
│   │   ├── str/
│   │   │   └── str_panel_medium_t2/
│   │   │       ├── str_panel_medium_t2.glb
│   │   │       ├── str_panel_medium_t2.glb.import
│   │   │       └── str_panel_medium_t2_dmg.glb
│   │   ├── mot/  pwr/  eff/  sup/  ctl/
│   ├── atlases/
│   │   ├── hull_albedo_atlas.ktx2
│   │   ├── hull_orm_atlas.ktx2
│   │   └── hull_normal_atlas.ktx2
│   └── materials/
├── data/
│   └── parts/
│       ├── registry_manifest.tres
│       └── str/
│           ├── str.panel.medium.t2.tres              (PartDefinition)
│           ├── str.panel.medium.t2.visual.tres       (PartVisualProfile)
│           ├── str.panel.medium.t2.collider.tres     (ColliderProfile)
│           └── str.panel.medium.t2.fusion.tres       (FusionProfile)
└── tools/
    ├── validate_part_registry.gd
    ├── validate_part_visuals.gd
    ├── bake_part_blockout.gd
    └── promote_part_stage.gd
```

The separation of `art_src/` from `assets/` is enforced by the export preset's exclude filter. Nothing in `art_src/` reaches a build; a `.blend` file accidentally placed in `assets/` fails CI.

---

## 4. Naming Conventions

### 4.1 Files

| Artefact | Pattern | Example |
|---|---|---|
| Source scene | `art_src/parts/<snake_key>/<snake_key>.blend` | `art_src/parts/eff_ballistic_autocannon_30_t3/eff_ballistic_autocannon_30_t3.blend` |
| Exported mesh | `assets/parts/<class>/<snake_key>/<snake_key>.glb` | `assets/parts/eff/eff_ballistic_autocannon_30_t3/eff_ballistic_autocannon_30_t3.glb` |
| Damage variant | `<snake_key>_dmg_<band>.glb` | `..._dmg_impaired.glb`, `..._dmg_critical.glb` |
| Definition | `data/parts/<class>/<dotted_key>.tres` | `data/parts/eff/eff.ballistic.autocannon_30.t3.tres` |

`snake_key` is `part_key` with `.` replaced by `_`. The conversion is mechanical and is performed by `PartRegistry._path_for_key` and by every tool script, so the two forms never drift.

### 4.2 Nodes Inside a `.glb`

| Node name pattern | Meaning | Consumed by |
|---|---|---|
| `MESH_lod0` … `MESH_lod3` | LOD levels | Import LOD assignment |
| `SOCKET_muzzle_<n>` | Muzzle position and forward axis | `EffectorModuleProfile.muzzle_offsets_m` verification |
| `SOCKET_yaw` | Yaw pivot origin | Hardpoint node construction |
| `SOCKET_pitch` | Pitch pivot origin | Hardpoint node construction |
| `SOCKET_contact` | Motive contact centre | `MotiveAssemblyProfile.contact_radius_m` verification |
| `SOCKET_vfx_<name>` | VFX attachment | `VfxPool` binding |
| `REF_collider_<n>` | **Reference only**; visualises the authored collider primitive | Validator comparison — never imported as collision |
| `-noimp` suffix | Godot skips this node on import | Blocking-out helpers left in the source |

`REF_collider_*` nodes exist so artists can see the collision volume they must stay within. They are stripped at import (`-noimp` behaviour is applied by the import script) and can never become collision geometry.

### 4.3 Materials

Final meshes use exactly one material slot, named `M_hull_fusion`, replaced at import by the shared fusion `ShaderMaterial`. Multi-material parts are not permitted: they would break the one-material-per-Assembly rule that keeps the fusion system to a single shader instance (`PART_FUSION_SHADER.md` §2.4).

Surface variation is expressed through `atlas_variant` (0–15) selecting an atlas cell, not through separate materials.

---

## 5. DCC Export Contract

### 5.1 Units and Orientation

| Property | Required value |
|---|---|
| Unit scale | 1 Blender unit = 1 metre |
| Forward axis | `-Z` |
| Up axis | `+Y` |
| Origin | Centre of the part's pivot cell (`occupancy_cells[0]`) |
| Transform | Applied (scale 1,1,1; rotation 0,0,0) on export |
| Normals | Custom split normals exported |
| Tangents | Exported (required for normal mapping) |
| UVs | UV0 for atlas mapping; UV1 unused (triplanar handles detail) |
| Vertex colours | Optional; R channel = wear mask multiplier |

### 5.2 Blender Export Settings

```python
# art_src/_pipeline/export_part.py — run from Blender
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_yup=True,
    export_apply=True,               # applies modifiers
    export_normals=True,
    export_tangents=True,
    export_materials='EXPORT',
    export_cameras=False,
    export_lights=False,
    export_extras=True,              # carries custom properties for sockets
    use_selection=True,
    export_animations=False,
)
```

Animation export is disabled. Part visuals are never skeletally animated; hardpoint motion is node rotation driven by `HardpointState` (`WEAPON_TARGETING_LOGIC.md` §2), and damage states are mesh swaps. This keeps the runtime free of `AnimationPlayer` instances per part, which at 180 parts per Assembly would be a significant cost for no benefit.

### 5.3 Mandatory Fusion Topology

`PART_FUSION_SHADER.md` §5 defines the topology requirements for seam blending. Restated here as the artist-facing contract:

1. **Inset edge loop.** Every face that can abut another part carries an edge loop inset `0.03–0.06 m` from the border. This loop is what the vertex shader displaces into the fillet. A face without it will not fuse and will show a hard seam.
2. **Maximum edge length `0.125 m`** on abutting faces, so the displaced fillet is smooth rather than faceted.
3. **Smooth shading across the inset loop**, hard shading elsewhere. Mark the inset loop's edges as smooth and the outer border as sharp.
4. **No geometry outside the lattice footprint.** The visual may be *smaller* than the occupancy but never larger — an overhang would visually intersect a legally placed neighbour.

### 5.4 Triangle Budgets

| Part class | LOD0 | LOD1 | LOD2 | LOD3 |
|---|---|---|---|---|
| `STRUCTURAL_COMPONENT` | 400 | 180 | 80 | 24 |
| `CONTROL_SURFACE` | 500 | 220 | 90 | 24 |
| `SUPPORT_MODULE` | 900 | 400 | 160 | 40 |
| `PRIME_MOVER` | 1 400 | 600 | 240 | 60 |
| `MOTIVE_ASSEMBLY` | 1 600 | 700 | 280 | 70 |
| `EFFECTOR_MODULE` | 3 200 | 1 300 | 500 | 120 |
| `CORE_MODULE` | 4 800 | 2 000 | 800 | 180 |

At the 180-part reference Assembly these budgets produce roughly 96 000 triangles at LOD0 — comfortable for twelve visible Assemblies on the reference target once distance LOD engages.

---

## 6. Import Configuration

### 6.1 Import Preset

Every part `.glb` uses the shared preset in `assets/parts/.gdignore_import_defaults`, applied by the import hook:

```gdscript
# addons/syndicate_pipeline/part_import_plugin.gd
@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
    _strip_reference_nodes(scene)
    _clear_all_collision(scene)
    _assign_fusion_material(scene)
    _extract_sockets(scene)
    _configure_lods(scene)
    return scene

## Removes REF_collider_* helpers and anything suffixed -noimp.
func _strip_reference_nodes(node: Node) -> void:
    for child in node.get_children():
        if child.name.begins_with("REF_collider_") or child.name.ends_with("-noimp"):
            child.free()
            continue
        _strip_reference_nodes(child)

## THE critical step: no imported part mesh may ever carry collision.
func _clear_all_collision(node: Node) -> void:
    for child in node.get_children():
        if child is CollisionShape3D or child is CollisionObject3D:
            push_error("Part mesh contains collision node '%s'. \
                        Colliders come from ColliderProfile only." % child.name)
            child.free()
            continue
        if child is MeshInstance3D:
            child.set_meta("_edit_lock_", true)
            child.layers = RenderLayers.LAYER_ASSEMBLY_VISUAL
        _clear_all_collision(child)
```

`_clear_all_collision` raises an error rather than silently deleting, because a collision node in a part mesh means the artist used a `-col`/`-convcol` suffix, which is a workflow misunderstanding worth surfacing loudly.

### 6.2 LOD Configuration

Godot 4 generates LODs automatically from a single mesh, but auto-generated LODs frequently destroy the inset fusion loop, which breaks seam blending exactly where it is most visible. Project Syndicate therefore uses **authored LODs** where the mesh participates in fusion:

```gdscript
func _configure_lods(scene: Node) -> void:
    var lods := _collect_named_lods(scene)      # MESH_lod0..MESH_lod3
    if lods.is_empty():
        # No authored LODs: allow auto-generation, but keep the fusion band dense.
        for mi in _all_mesh_instances(scene):
            mi.mesh.lightmap_size_hint = Vector2i.ZERO
            (mi.mesh as ImporterMesh).generate_lods(25.0, 60.0, [])
        return
    var root_mi: MeshInstance3D = lods[0]
    root_mi.visibility_range_end = _profile.lod_distances_m[0]
    for i in range(1, lods.size()):
        var mi: MeshInstance3D = lods[i]
        mi.visibility_range_begin = _profile.lod_distances_m[i - 1]
        mi.visibility_range_end = _profile.lod_distances_m[i] \
            if i < _profile.lod_distances_m.size() else 0.0
        mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
```

`generate_lods(25.0, 60.0, [])` passes a `normal_merge_angle` of 25° — tighter than the default — specifically to preserve the smooth-shaded fusion band.

### 6.3 Texture Import

Atlases are `.ktx2` with BasisU compression, imported as:

| Atlas | Format | Mipmaps | sRGB |
|---|---|---|---|
| `hull_albedo_atlas` | `BPTC_RGBA` / ASTC on mobile | Yes | Yes |
| `hull_orm_atlas` | `BPTC_RGBA` / ASTC | Yes | No |
| `hull_normal_atlas` | `BPTC_RGBA`, normal-map hint | Yes | No |

Atlas cells are 4×4 = 16 slots at 1024×1024 each, giving a 4096×4096 atlas per channel. `atlas_variant` indexes the cell, and the fusion shader's `variant` computation (`PART_FUSION_SHADER.md` §3.1) reads it from `INSTANCE_CUSTOM.z`.

---

## 7. Validation

`tools/validate_part_visuals.gd` runs in CI and as an editor action. It is the gate that keeps the swap guarantee true.

```gdscript
class_name PartVisualValidator
extends RefCounted

const COLLIDER_CONTAINMENT_TOLERANCE_M := 0.06
const MAX_VISUAL_OVERHANG_M := 0.02

func validate(def: PartDefinition) -> ValidationReport:
    var r := ValidationReport.new(def.part_key)
    var vp := def.visual_profile
    if vp == null:
        return r.fail("missing visual profile")

    match vp.stage:
        PartVisualProfile.Stage.PROXY:
            _validate_proxy(def, r)
        PartVisualProfile.Stage.BLOCKOUT:
            _validate_blockout(def, r)
        PartVisualProfile.Stage.FINAL:
            _validate_final(def, r)
    _validate_shared(def, r)
    return r

func _validate_final(def: PartDefinition, r: ValidationReport) -> void:
    var vp := def.visual_profile
    if vp.mesh_nominal == null:
        return r.fail("STAGE_FINAL with no mesh_nominal")

    # 1. Triangle budget.
    var tris := MeshUtil.triangle_count(vp.mesh_nominal)
    var budget: int = TRI_BUDGET[def.part_class]
    if tris > budget:
        r.fail("LOD0 %d tris exceeds budget %d" % [tris, budget])

    # 2. No collision data of any kind.
    if MeshUtil.has_collision_metadata(vp.mesh_nominal):
        r.fail("mesh carries collision metadata")

    # 3. Visual must not overhang the lattice footprint.
    var footprint := _footprint_aabb(def)
    var mesh_aabb := vp.mesh_nominal.get_aabb()
    var overhang := _max_overhang(mesh_aabb, footprint)
    if overhang > MAX_VISUAL_OVERHANG_M:
        r.fail("visual overhangs footprint by %.3f m" % overhang)

    # 4. Collider must be broadly contained by the visual, or the part will
    #    appear to be hit through empty space.
    var containment := _collider_containment(def, vp.mesh_nominal)
    if containment < 1.0 - COLLIDER_CONTAINMENT_TOLERANCE_M:
        r.warn("collider protrudes beyond visual by up to %.3f m"
               % (1.0 - containment))

    # 5. Fusion topology.
    if def.fusion_profile != null and def.fusion_profile.contributes_to_sdf:
        var topo := FusionTopologyChecker.check(vp.mesh_nominal)
        if not topo.has_inset_loops:
            r.fail("no inset edge loop on abutting faces; fusion will seam")
        if topo.max_edge_length_m > 0.125:
            r.fail("max edge length %.3f m exceeds 0.125 m on abutting faces"
                   % topo.max_edge_length_m)
        if not topo.smooth_across_inset:
            r.warn("inset loop is not smooth-shaded; fillet will facet")

    # 6. Sockets required by the class profile.
    _validate_sockets(def, r)

    # 7. Material slot count.
    if vp.mesh_nominal.get_surface_count() != 1:
        r.fail("expected exactly 1 surface, found %d"
               % vp.mesh_nominal.get_surface_count())

    # 8. LOD chain monotonic.
    _validate_lod_chain(vp, r)

func _validate_shared(def: PartDefinition, r: ValidationReport) -> void:
    # The collider is authoritative and must not have changed with the art.
    var hash_now := ColliderHasher.hash(def.collider_profile)
    var hash_recorded := ColliderBaseline.recorded_for(def.part_key)
    if hash_recorded != 0 and hash_now != hash_recorded:
        r.fail("ColliderProfile changed during a visual promotion. \
                Collider changes require an explicit balance review.")
```

Check 8 in `_validate_shared` is the enforcement mechanism for the whole document's premise. `ColliderBaseline` records a hash of every part's `ColliderProfile` at the moment it first ships. A pull request that promotes a part from `STAGE_BLOCKOUT` to `STAGE_FINAL` **and** modifies its collider fails CI, and the failure message states exactly why. Collider changes are legitimate — but they are balance changes, they go through a separate review path, and they may never ride along invisibly with an art commit.

### 7.1 Socket Requirements

| Part class | Required sockets |
|---|---|
| `EFFECTOR_MODULE` | `SOCKET_yaw`, `SOCKET_pitch`, `SOCKET_muzzle_0` … `SOCKET_muzzle_(n−1)` matching `muzzle_offsets_m.size()` |
| `MOTIVE_ASSEMBLY` | `SOCKET_contact` |
| `PRIME_MOVER` | `SOCKET_vfx_exhaust` (at least one) |
| Others | none |

Socket positions are validated against the corresponding profile values with a `0.04 m` tolerance. A mismatch is a failure, not a warning: a muzzle socket 20 cm from where `muzzle_offsets_m` says it is produces projectiles visibly emerging from the wrong place.

---

## 8. The Promotion Workflow

Promoting a single part from proxy to final art. This is the workflow the whole document exists to make routine.

```
1. Pick a part.                    tools/promote_part_stage.gd --list-proxy
2. Export the reference.           tools/promote_part_stage.gd --export-ref <key>
      Writes art_src/parts/<snake_key>/reference.glb containing:
        - the lattice footprint as a wireframe cage
        - REF_collider_* primitives from ColliderProfile
        - attachment node positions and face normals as empties
3. Model in the DCC tool.          Stay inside the cage. Respect Section 5.3.
4. Export.                         art_src/_pipeline/export_part.py
                                   -> assets/parts/<class>/<snake_key>/<snake_key>.glb
5. Promote the profile.            tools/promote_part_stage.gd --promote <key> --stage final
      Sets stage = FINAL, wires mesh_nominal, populates lod_distances_m,
      leaves ColliderProfile and every gameplay field untouched.
6. Validate.                       tools/validate_part_visuals.gd --key <key>
7. Visual diff.                    tools/promote_part_stage.gd --compare <key>
      Renders proxy vs final side by side at 8 orientations, writes a
      contact sheet to .build/promotion/<key>.png
8. Commit.                         Art files + one .visual.tres. Nothing else.
```

Step 5 is a one-field data change. Step 8's constraint — "nothing else" — is enforced by a CI check that inspects the diff:

```gdscript
# tools/ci/check_promotion_scope.gd
const ALLOWED_PROMOTION_PATHS := [
    "assets/parts/", "art_src/", "data/parts/*.visual.tres",
]

func check(changed_files: PackedStringArray) -> bool:
    if not _is_promotion_pr():
        return true
    for f in changed_files:
        if not _matches_any(f, ALLOWED_PROMOTION_PATHS):
            push_error("Promotion PR touches non-visual file: %s" % f)
            return false
    return true
```

### 8.1 Reference Export

```gdscript
func export_reference(def: PartDefinition, out_path: String) -> void:
    var root := Node3D.new()
    root.name = "REFERENCE_" + String(def.part_key).replace(".", "_")

    # Lattice footprint cage.
    var cage := MeshInstance3D.new()
    cage.name = "REF_footprint_cage-noimp"
    cage.mesh = _build_cage_mesh(def.occupancy_cells)
    root.add_child(cage)

    # Collider primitives, exactly as physics sees them.
    for i in def.collider_profile.primitives.size():
        var prim := def.collider_profile.primitives[i]
        var mi := MeshInstance3D.new()
        mi.name = "REF_collider_%d" % i
        mi.mesh = ProxyMeshBuilder._primitive_mesh(prim)
        mi.transform = ColliderProfile.local_transform(prim)
        root.add_child(mi)

    # Attachment nodes as oriented empties.
    for node in def.attachment_nodes:
        var marker := Node3D.new()
        marker.name = "REF_node_%s-noimp" % node.node_name
        marker.position = LatticeMath.cell_to_local(node.cell) \
                        + Vector3(node.face_normal) \
                        * (SyndicateConstants.LATTICE_UNIT_M * 0.5)
        marker.look_at_from_position(marker.position,
            marker.position + Vector3(node.face_normal), Vector3.UP)
        root.add_child(marker)

    GltfExporter.write(root, out_path)
    root.free()
```

Exporting the collider as visible reference geometry is the practical device that makes the decoupled-collision architecture workable for artists. They are not asked to imagine an invisible box; they see it, and they model around it.

---

## 9. Runtime Stage Handling

The runtime is stage-agnostic. `AssemblyRuntime.spawn_visual` branches once, at spawn:

```gdscript
func spawn_visual(slot: int) -> void:
    var st: PartInstanceState = states[slot]
    var def := PartRegistry.definition(st.part_def_id)
    var vp := def.visual_profile

    var mi := MeshInstance3D.new()
    mi.name = "part_s%03d" % slot
    match vp.stage:
        PartVisualProfile.Stage.PROXY:
            mi.mesh = ProxyMeshCache.get_or_build(def)
            mi.material_override = GreyboxMaterial.for_class(def.part_class,
                                                             vp.proxy_tint)
        PartVisualProfile.Stage.BLOCKOUT:
            mi.mesh = vp.blockout_mesh
            mi.material_override = BlockoutMaterial.shared()
        PartVisualProfile.Stage.FINAL:
            mi.mesh = vp.mesh_nominal
            mi.material_override = _fusion_material          # shared per Assembly

    mi.transform = Transform3D(
        OrientationTable.basis_for(st.orientation_index).scaled(vp.visual_scale),
        LatticeMath.cell_to_local(st.origin_cell) + vp.visual_offset_m)
    mi.layers = RenderLayers.LAYER_ASSEMBLY_VISUAL
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vp.casts_shadow \
                     else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mi.collision_layer = 0                 # belt and braces; MeshInstance3D has none
    mi.collision_mask = 0
    visual_root.add_child(mi)
    FusionInstanceWriter.write(mi, st, def)
    st.visual_node_path = visual_root.get_path_to(mi)
```

`spawn_colliders` is a completely separate function reading `ColliderProfile`, called from the same commit path but sharing no data with `spawn_visual`. They can be read side by side and there is no line where one influences the other.

### 9.1 Mixed-Stage Assemblies

An Assembly may contain parts at all three stages simultaneously. Consequences:

- `STAGE_PROXY` and `STAGE_BLOCKOUT` parts use their own materials and do not participate in the shared fusion material. They still contribute to the occupancy SDF (if `contributes_to_sdf` is true), so a `STAGE_FINAL` neighbour still fillets correctly against them — the fillet simply has nothing to blend *into* on the proxy side.
- Skirt runs spanning a proxy and a final part are generated only if both sides have `accepts_skirting = true`. Proxies default to `false`.
- Nothing about mass, integrity, collision, or network state differs.

The visual result during development is a vehicle that is partly finished art and partly grey primitives, seamlessly playable. That is the intended state for most of the project's life.

---

## 10. Static Volume and Ground Extension

The same maturity model applies beyond parts.

### 10.1 Static Volumes

| Stage | Composition | Fracture |
|---|---|---|
| `PROXY` | Untextured `CSGBox3D` massing in the editor | Sections only, no fragment decomposition |
| `BLOCKOUT` | Full CSG composition with cutouts | Full Voronoi fragment bake |
| `FINAL` | CSG composition + authored detail meshes merged at bake | Full bake, with authored interior materials for cut faces |

Promotion follows the same rule: the fracture bake output — Section partition, support graph, collider hulls — is regenerated, but the **Section boundaries and support graph topology are diffed** and a change requires review, because those determine how the structure collapses and therefore how it plays as cover.

### 10.2 Ground Arrays

Ground materials promote independently of heightfield data. The splat map, surface classification, and `SurfaceTable` values are gameplay data authored in the map file; the albedo/ORM/normal textures they blend are art. Replacing a `SURFACE_LOOSE` texture set changes appearance only; changing which samples are classified `SURFACE_LOOSE` changes traction and goes through balance review.

### 10.3 VFX and Audio

| Stage | VFX | Audio |
|---|---|---|
| `PROXY` | Coloured `GPUParticles3D` with default quad material | Placeholder tones, correct duration and 3D falloff |
| `FINAL` | Authored particle materials, meshes, and trail curves | Final samples, bussed and mixed |

Placeholder audio uses correct durations and attenuation curves from day one, because timing and spatialisation are gameplay-relevant even when the sound itself is a sine tone. Swapping the sample is a data change with no code impact.

---

## 11. CI Gates

The pipeline is enforced by five checks, all of which block merge:

| Gate | Script | Fails on |
|---|---|---|
| Registry integrity | `validate_part_registry.gd` | Any of the 16 rules in `PART_DATA_SCHEMA.md` §14 |
| Visual validation | `validate_part_visuals.gd` | Any check in §7 |
| Promotion scope | `ci/check_promotion_scope.gd` | A promotion PR touching non-visual files |
| Collider baseline | `ci/check_collider_baseline.gd` | Any `ColliderProfile` hash change without a `balance-review` label |
| Source containment | `ci/check_asset_dirs.gd` | A DCC source file inside `assets/`, or a `CSGShape3D` in an exported scene |

The last gate deserves note. It parses every `.tscn` in the export set and fails if any contains a `CSGShape3D` node, which is the mechanical enforcement of the "no runtime CSG" rule from `PROCEDURAL_STRUCTURE_SLICING.md` §1.

```gdscript
# tools/ci/check_asset_dirs.gd
const FORBIDDEN_IN_EXPORT := ["CSGBox3D", "CSGSphere3D", "CSGCylinder3D",
                              "CSGTorus3D", "CSGPolygon3D", "CSGMesh3D",
                              "CSGCombiner3D"]

func check_scenes(export_scene_paths: PackedStringArray) -> bool:
    var ok := true
    for path in export_scene_paths:
        var text := FileAccess.get_file_as_string(path)
        for cls in FORBIDDEN_IN_EXPORT:
            if text.contains('type="%s"' % cls):
                push_error("Exported scene %s contains %s" % [path, cls])
                ok = false
    return ok
```

---

## 12. Invariants

1. `PartVisualProfile` and `ColliderProfile` are separate resources. Neither is derived from the other at runtime.
2. Promoting a part's visual stage never modifies `ColliderProfile`, `occupancy_cells`, `attachment_nodes`, or any gameplay field. CI enforces this through the collider baseline hash.
3. Imported part meshes carry no collision nodes and no collision metadata. The import plugin errors on any it finds.
4. Every part is playable at every maturity stage; an Assembly may mix stages freely.
5. `STAGE_PROXY` geometry defaults to mirroring `ColliderProfile`, so greybox visuals are honest about hitboxes.
6. DCC source files live in `art_src/` and never reach a build.
7. No `CSGShape3D` exists in any exported scene; CSG is confined to authoring and offline bakes.
8. Final meshes have exactly one surface and use the shared fusion material; variation is by atlas cell.
9. Socket positions are validated against their profile values within `0.04 m`.
10. LODs on fusion-participating meshes are authored or generated with a `25°` normal merge angle, to preserve the inset fusion loop.
