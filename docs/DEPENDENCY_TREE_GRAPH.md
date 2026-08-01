# DEPENDENCY_TREE_GRAPH.md

**Project Syndicate — System Architecture Specification, Document 04 of 13**
**Subsystem:** Chassis Graph — Structural Connectivity, Strain, and Event-Driven Detachment
**Status:** Normative.

---

## 1. Purpose and the Central Design Rule

The Chassis Graph answers exactly one question: **which parts are still structurally connected to the Core Module?** Everything else — detachment, debris spawning, subtree mass, strain, downstream functional loss — falls out of that answer.

The central design rule of this subsystem, and one of the four mandatory architectural upgrades, is:

> **Connectivity is never evaluated per frame.** The graph sits completely dormant. It performs work only when a discrete structural event fires: a part's integrity reaches zero, a joint's strain exceeds its limit, or the player edits the Assembly in the garage.

Legacy implementations of this feature poll — every frame, every vehicle, every part, walking a tree to see whether anything came loose. At 32 Assemblies × 180 parts × 60 Hz that is 345 600 node visits per second of pure waste, and it scales linearly with player count on the server. Project Syndicate's graph performs **zero work** in the steady state. A twenty-minute match with no destruction costs zero graph CPU time.

---

## 2. Structure: A Tree Plus Support Edges

A part in a physically plausible Assembly usually touches several neighbours. Modelling that as a strict tree loses information (a panel bridged across two spars is much harder to shear off than one cantilevered from a single spar). Modelling it as a general graph makes "who is my parent" ill-defined for the UI, the mass solver, and the removal cascade.

Project Syndicate therefore stores **both**:

| Structure | Meaning | Used by |
|---|---|---|
| **Primary tree** (`parent_slot` / `child_slots`) | Each part's single load-bearing parent, chosen at attach time | Subtree mass, garage removal cascade, UI hierarchy, strain accounting |
| **Support edges** (`_adjacency`) | Every mated attachment pair, including the primary one | Connectivity determination, island detection, load sharing |

Connectivity — the thing that decides whether a part falls off — is always evaluated over the **support edge graph**, never over the tree. The tree is a bookkeeping convenience layered on top.

### 2.1 Core Data Layout

```gdscript
class_name ChassisGraph
extends RefCounted

const MAX := SyndicateConstants.MAX_PARTS_PER_ASSEMBLY
const INVALID := SyndicateConstants.INVALID_SLOT
const CORE := SyndicateConstants.CORE_SLOT

## --- Primary tree -----------------------------------------------------
var parent: PackedByteArray = PackedByteArray()        # slot -> parent slot
var children: Array = []                               # slot -> PackedByteArray
var depth: PackedByteArray = PackedByteArray()         # slot -> tree depth

## --- Support edge graph ----------------------------------------------
## Flat adjacency: neighbours[slot] is a PackedByteArray of mated slots.
var neighbours: Array = []
## Parallel array: joint strength (N) of the edge at the same index.
var edge_strength: Array = []                          # slot -> PackedFloat32Array
## Parallel array: accumulated strain fraction [0,1] of the edge.
var edge_strain: Array = []                            # slot -> PackedFloat32Array
## Parallel array: 1 when both nodes forming the edge bear load.
var edge_bears_load: Array = []                        # slot -> PackedByteArray

## --- Cached aggregates ------------------------------------------------
var mass_kg: PackedFloat32Array = PackedFloat32Array()  # slot -> its own mass
var subtree_mass: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()         # 1 = participating in structure

## --- Traversal scratch (reused; never reallocated in the hot path) ----
var _visit_stamp: PackedInt32Array = PackedInt32Array()
var _stamp_counter: int = 0
var _queue: PackedByteArray = PackedByteArray()

func _init() -> void:
    parent.resize(MAX);        parent.fill(INVALID)
    depth.resize(MAX);         depth.fill(0)
    alive.resize(MAX);         alive.fill(0)
    subtree_mass.resize(MAX);  subtree_mass.fill(0.0)
    _visit_stamp.resize(MAX);  _visit_stamp.fill(0)
    _queue.resize(MAX)
    children.resize(MAX)
    neighbours.resize(MAX)
    edge_strength.resize(MAX)
    edge_strain.resize(MAX)
    for i in MAX:
        children[i] = PackedByteArray()
        neighbours[i] = PackedByteArray()
        edge_strength[i] = PackedFloat32Array()
        edge_strain[i] = PackedFloat32Array()
```

Every array is fixed-size and preallocated at construction. The graph performs **no heap allocation during a match** except when growing a per-slot adjacency list at attach time, which only happens in the garage.

`edge_bears_load` was added to the parallel edge arrays after the fact. §3.2's first ordering key is whether a joint bears load on **both** sides, and that fact previously lived only on the `MateRecord` the placement produced, which is discarded once the edge is built. Re-parenting after a destruction (§5.3) has no mate records to consult, so without this array the match path would have had to rank survivors on three of §3.2's four keys while the garage ranked them on four — the exact drift `MateSelector.outranks` exists to prevent. It is maintained by `_add_edge` alongside `edge_strength` and read through `edge_bears_load_at(slot, index)`.

`mass_kg` was added to the cached aggregates after the fact. §3.1 calls `m_mass_of(slot)` to compute the delta it propagates, and this section originally declared no field to hold it — leaving the graph unable to compute a value its own attach path depends on. Storing it here follows the precedent of the other aggregates and keeps the graph free of a `PartRegistry` dependency, so it stays constructible in a unit test with no autoloads. `attach` therefore takes the part's mass as its final argument, and `m_mass_of(slot)` is `mass_kg[slot]`.

### 2.2 The Visit Stamp Trick

Flood fills need a "visited" set. Clearing a 255-entry boolean array is cheap, but doing it several times per destruction cascade adds up, and more importantly it makes the cost of a fill proportional to `MAX` rather than to the region actually explored.

Instead, `_visit_stamp` holds an integer per slot and `_stamp_counter` is incremented before each traversal. A slot is "visited this traversal" iff `_visit_stamp[slot] == _stamp_counter`. No clearing is ever required, and the cost of a traversal is exactly proportional to the nodes it touches.

```gdscript
func _begin_traversal() -> int:
    _stamp_counter += 1
    if _stamp_counter == 0x7FFFFFFF:        # wrap: the only time we clear
        _visit_stamp.fill(0)
        _stamp_counter = 1
    return _stamp_counter
```

---

## 3. Graph Construction

### 3.1 Attach

Called from `PlacementValidator.commit` (`GRID_SNAPPING_LOGIC.md` §9.1) and from blueprint load.

```gdscript
func attach(slot: int, primary_parent: int, mates: Array[MateRecord]) -> void:
    assert(alive[slot] == 0, "slot already live")
    alive[slot] = 1
    parent[slot] = primary_parent
    depth[slot] = 0 if primary_parent == INVALID else depth[primary_parent] + 1

    if primary_parent != INVALID:
        var kids: PackedByteArray = children[primary_parent]
        kids.push_back(slot)
        children[primary_parent] = kids

    for m in mates:
        _add_edge(slot, m.other_slot, m.joint_strength_n, m.bears_load)

    _propagate_mass_delta(slot, m_mass_of(slot))

func _add_edge(a: int, b: int, strength: float, bears_load: bool) -> void:
    var na: PackedByteArray = neighbours[a]
    var sa: PackedFloat32Array = edge_strength[a]
    var ta: PackedFloat32Array = edge_strain[a]
    na.push_back(b); sa.push_back(strength); ta.push_back(0.0)
    neighbours[a] = na; edge_strength[a] = sa; edge_strain[a] = ta

    var nb: PackedByteArray = neighbours[b]
    var sb: PackedFloat32Array = edge_strength[b]
    var tb: PackedFloat32Array = edge_strain[b]
    nb.push_back(a); sb.push_back(strength); tb.push_back(0.0)
    neighbours[b] = nb; edge_strength[b] = sb; edge_strain[b] = tb
```

Edges are stored twice (once per endpoint) so neighbour iteration is a single contiguous read with no indirection. The `edge_strain` value is kept in sync across both copies by `_set_edge_strain`, which updates both endpoints.

A `MateRecord`'s `joint_strength_n` is the **weaker** of the two mating nodes' declared strengths. A joint is a pair of mating faces and fails at whichever face yields first, so rating it by the stronger end — or by the arriving part's end — would let a part advertise a strength its partner cannot honour, and §3.2 would then select that joint as primary parent on the strength of a number describing only one side of it. `MateRecord.create` is the single place this is decided.

`_add_edge` is idempotent per pair. A wide part meeting a wide part mates across several faces, which is one physical joint; adding an edge per mating face would double-count it in every strain and connectivity sum.

### 3.2 Primary Parent Selection

When a placement mates against several existing parts, the primary parent is chosen deterministically:

1. Prefer a mate whose `AttachmentNodeDef.can_bear_load` is `true` on **both** sides.
2. Among those, prefer the highest `joint_strength_n`.
3. Among ties, prefer the mate with the **lowest tree depth** (closer to the Core Module).
4. Among remaining ties, prefer the **lowest slot index**.

This ordering is fully deterministic and identical on client and server. It is implemented in `MateSelector.choose_primary` and is covered by `tests/unit/test_mate_selector.gd`, which asserts that a shuffled input order produces an identical result.

### 3.3 Subtree Mass Maintenance

`subtree_mass[s]` is the total mass of `s` plus every descendant in the **primary tree**. It is maintained by walking to the root on each change — `O(depth)`, typically 4–9 steps — rather than by recomputation.

```gdscript
func _propagate_mass_delta(from_slot: int, delta: float) -> void:
    var s := from_slot
    var guard := 0
    while s != INVALID:
        subtree_mass[s] += delta
        s = parent[s]
        guard += 1
        assert(guard <= MAX, "cycle detected in primary tree")
    _mass_dirty = true
```

The `guard` is not defensive padding; the primary tree is an invariant that other code can violate through a bug, and a silent infinite loop inside a physics tick is far worse than an assertion.

`_mass_dirty` is a plain `bool` on the graph, read through `is_mass_dirty()` and reset through `clear_mass_dirty()`. The snippet above set it before this section declared it. It is what the detachment scheduler turns into `assembly_mass_dirty` (§8.2) once the tick's structural work is finished: the mass solver runs at `PRIORITY_MASS`, one phase after detachment, and needs to know the structure moved underneath it without re-deriving that from the topology.

---

## 4. Strain

### 4.1 Model

Each support edge carries a strain fraction in `[0, 1]`:

```
strain(e) = F_edge / joint_strength_n(e)
```

where `F_edge` is the force the joint is transmitting. Rather than solve a full structural FEM (which would be per-frame work and is therefore forbidden), Project Syndicate uses a quasi-static approximation evaluated **only at recomputation events**:

```
F_edge(s → parent) = subtree_mass[s] · g · κ_dynamic + F_recoil(s) + F_impact(s)
```

| Term | Meaning | Source |
|---|---|---|
| `subtree_mass[s] · g` | Static hanging load | §3.3 |
| `κ_dynamic` | Dynamic amplification from chassis acceleration | `DYNAMIC_MASS_PHYSICS.md` §9 |
| `F_recoil(s)` | Peak recoil impulse of Effector Modules in the subtree, divided by cycle time | `WEAPON_TARGETING_LOGIC.md` §8 |
| `F_impact(s)` | Decaying impulse deposit from recent collisions | `COMPONENT_HEALTH_DAMAGE.md` §6 |

`κ_dynamic` is a single scalar per Assembly, updated at 10 Hz from the chassis acceleration magnitude:

```gdscript
const KAPPA_MIN := 1.0
const KAPPA_MAX := 3.6
const KAPPA_SMOOTHING := 0.25

func update_dynamic_factor(chassis_accel_mps2: float) -> void:
    var target := clampf(KAPPA_MIN + chassis_accel_mps2 / 9.81, KAPPA_MIN, KAPPA_MAX)
    _kappa = lerpf(_kappa, target, KAPPA_SMOOTHING)
```

10 Hz is not per-frame polling of connectivity; it is a scalar smoothing filter costing one lerp per Assembly. Connectivity itself remains untouched.

**Both deposit terms decay.** `deposit_recoil_force` (doc 07 §8) and `deposit_impact_force` (doc 08 §6.2) each record the *peak* force at a slot, and `decay_deposits(dt)` pulls both towards zero exponentially — recoil over `RECOIL_DECAY_TAU_S = 0.6`, impact over `IMPACT_DECAY_TAU_S = 0.9`. Doc 08 already decayed the impact term; doc 07 deposited recoil without ever clearing it, which would have made a single discharge a load the mounting joint carried for the rest of the match. Both are recent-load deposits and differ only in time constant. A slot whose deposits fall below `DEPOSIT_FLOOR_N = 1.0` leaves the decay set entirely, so `decay_deposits` returns immediately on an Assembly that is not being loaded, and returns `false` once nothing is.

`F_recoil(s)` and `F_impact(s)` are **subtree sums** — an Effector Module three parts up still loads the joint at the bottom of the stack. `recompute_strain` accumulates them child-to-parent in a single descending-depth sweep (a counting sort into preallocated scratch), so one pass is `O(V)` rather than a walk per slot. Strain is carried on the edge to the **primary tree parent**: §4.1 defines exactly one force per part, and §3.2 is where the decision was made about which joint that force flows through.

The stored strain value is always current. Only the `joint_strain_changed` announcement is gated, by `STRAIN_REPORT_EPSILON = 0.01` — gating the write instead lets a joint sit at a stale strain indefinitely because each individual step stayed under the epsilon.

### 4.2 Strain Failure

An edge whose strain exceeds `1.0` for longer than `STRAIN_FAILURE_DWELL_S` fails and is removed. This is one of the three events that can wake the graph.

```gdscript
const STRAIN_FAILURE_DWELL_S := 0.45

func evaluate_strain(assembly_id: int, dt: float) -> void:
    # Called ONLY from the strain evaluation event, which itself fires on
    # mass recompute, recoil discharge, or impact deposit — never on a timer.
    for slot in _strained_candidates:                 # small dirty set, not all slots
        var ns: PackedByteArray = neighbours[slot]
        var st: PackedFloat32Array = edge_strain[slot]
        for i in ns.size():
            if st[i] < 1.0:
                _dwell[slot * MAX + ns[i]] = 0.0
                continue
            var key := slot * MAX + ns[i]
            _dwell[key] = _dwell.get(key, 0.0) + dt
            if _dwell[key] >= STRAIN_FAILURE_DWELL_S:
                EventBus.joint_failed.emit(assembly_id, slot, ns[i])
```

`_strained_candidates` is a small dirty set populated when a strain value is written above `0.85`. Edges below that threshold are never revisited. It is **rebuilt** on each `recompute_strain` rather than only added to, so a joint that was briefly overloaded during a jump stops being swept once the load comes off; `recompute_strain` is the only writer of `edge_strain`, which is what makes rebuilding it correct. The set is sorted ascending so that a cascade of failures is emitted in the same order on the server and on every client replaying the same events.

**The dwell key is canonical over the unordered pair**, `min(a,b) * MAX + max(a,b)`, not the ordered `slot * MAX + other` the snippet above uses. An edge is stored at both endpoints, so an ordered key gives one physical joint two independent timers: a joint whose two ends enter the candidate set on different passes then fails later than its dwell says, and one whose ends both enter it fails twice.

The dwell comparison carries a tolerance of `EPSILON_LINEAR`. Dwell is a sum of sixtieths of a second and cannot represent `0.45` exactly, so a bare `>=` grants the joint one extra tick — and the exact tick a joint fails on is replicated, so a server and a client accumulating in a different order would disagree about it.

### 4.3 Strain Feedback

Strain is surfaced to the player before it becomes a failure:

- Edges above `0.70` render a subtle stress decal on the skirt run bridging them (vertex colour channel driven by `SkirtRun.strain`).
- Edges above `0.90` emit an intermittent metal-groan audio cue positioned at the joint midpoint, rate-limited to one cue per Assembly per 1.2 s.
- The garage inspector shows predicted static strain per joint, computed once on structural change.

---

## 5. Detachment: The Core Algorithm

### 5.1 Trigger

Detachment evaluation is invoked from exactly three signals and no others:

```gdscript
func _ready() -> void:
    EventBus.part_destroyed.connect(_on_part_destroyed)   # integrity reached 0
    EventBus.joint_failed.connect(_on_joint_failed)       # strain exceeded
    EventBus.part_removed.connect(_on_part_removed)       # garage edit
```

There is no `_process`, no `_physics_process`, and no timer in `ChassisGraph` or in `DetachmentSolver`. This is verified by `tests/arch/test_no_polling.gd`, which parses every script under `src/assembly/graph/` and fails the build if either process callback is declared.

### 5.2 The Naive Approach and Why It Is Rejected

The obvious algorithm on losing part `X` is: flood-fill from the Core Module across the remaining graph, then detach everything not reached. This is `O(V + E)` — roughly 180 nodes and 400 edges — which is only about 15 µs. That would be acceptable once. It is **not** acceptable during a cascade, where losing a spar can destroy twelve parts across four ticks, each triggering a full fill, and where 32 Assemblies may be under fire simultaneously.

Project Syndicate instead uses **local reverse-reachability with early-out**, which almost always terminates after visiting a handful of nodes.

### 5.3 Local Reverse-Reachability

When part `X` is removed, only parts that were reaching the Core Module *through* `X` can possibly be orphaned. Those are, at most, `X`'s direct neighbours and whatever hangs off them. So: start a search from each surviving neighbour of `X` and ask "can I still reach the Core Module?" The instant a search touches the Core Module, or touches a node already proven connected in this same evaluation, it stops.

```gdscript
class_name DetachmentSolver
extends RefCounted

## Returns an Array[PackedByteArray]: one entry per severed island.
static func solve(graph: ChassisGraph, removed_slot: int) -> Array:
    var islands: Array = []
    var seeds: PackedByteArray = graph.neighbours[removed_slot].duplicate()

    graph.remove_node(removed_slot)

    var proven_connected := graph._begin_traversal()
    # Mark the core as proven so any search reaching it terminates immediately.
    graph._visit_stamp[ChassisGraph.CORE] = proven_connected

    for seed in seeds:
        if graph.alive[seed] == 0:
            continue
        if graph._visit_stamp[seed] == proven_connected:
            continue                              # already proven this pass
        var result := _search_from(graph, seed, proven_connected)
        if result.connected:
            # Mark every node explored as proven; they all reach the core.
            for s in result.visited:
                graph._visit_stamp[s] = proven_connected
        else:
            islands.push_back(result.visited)     # this component is severed
    return islands

static func _search_from(graph: ChassisGraph, seed: int,
                         proven_stamp: int) -> SearchResult:
    var visited := PackedByteArray()
    var head := 0
    var q := graph._queue
    q[0] = seed
    var tail := 1
    var local_stamp := graph._begin_traversal()
    graph._visit_stamp[seed] = local_stamp

    while head < tail:
        var cur := q[head]; head += 1
        visited.push_back(cur)
        if cur == ChassisGraph.CORE:
            return SearchResult.new(true, visited)
        var ns: PackedByteArray = graph.neighbours[cur]
        for n in ns:
            if graph.alive[n] == 0:
                continue
            # Early-out: this neighbour was already proven connected.
            if graph._visit_stamp[n] == proven_stamp:
                visited.push_back(n)
                return SearchResult.new(true, visited)
            if graph._visit_stamp[n] == local_stamp:
                continue
            graph._visit_stamp[n] = local_stamp
            q[tail] = n; tail += 1
    return SearchResult.new(false, visited)
```

`remove_node(slot)` is defined here, having been called above without being declared. It orphans the slot's primary children and then detaches it, returning the orphans. `detach` cannot serve on its own: it requires a childless slot, which a destroyed part in the middle of a hull never is.

**Surviving orphans are re-parented.** A part whose tree parent was destroyed but which still reaches the Core Module through another support edge stays on the Assembly, and it must be given a new tree parent — a live part with `parent == INVALID` keeps its mass out of every ancestor's `subtree_mass` and out of every strain figure computed from it, silently and permanently. `MateSelector.choose_support_parent(graph, slot)` picks it, ranking the surviving edges on §3.2's four keys read straight off the graph.

This is not the garage's re-parenting of §9.1. There is no confirmation prompt, nothing is *kept* that the support edges do not already hold up, and no candidate is re-derived from the lattice — after a destruction the mating is already settled and the surviving edges are exactly the legal parents. What the two share is the ordering, deliberately: a part must not land under one parent when placed and a different one when the part holding it up is shot away.

Re-parenting runs **after** the islands are severed, not before. Severing an island orphans any survivor whose tree parent was in it, so the orphan set is not complete until the islands are gone — and once they are, a leaving part can no longer be picked as a new parent, because it is no longer alive.

Removal order *within* an island does not matter and deliberately so, since `remove_node` lifts a slot's children off it before detaching it. A part is never asked to leave while something still hangs from it.

There is a subtlety worth stating explicitly, because it is easy to get wrong: `_search_from` allocates a **new** local stamp on each seed, while `proven_stamp` is a stamp from an earlier `_begin_traversal()` call. Since `_stamp_counter` only increments, the proven stamp is strictly less than every local stamp, and the two comparisons cannot alias. `_begin_traversal` is therefore called `1 + seeds.size()` times per evaluation, which is why the wrap check in §2.2 exists.

### 5.4 Complexity in Practice

| Scenario | Nodes visited | Measured |
|---|---|---|
| Destroyed part was a leaf | 0 (no surviving neighbours orphaned; first seed hits core in 1–3 hops) | 1.2 µs |
| Destroyed panel mid-hull | 3–8 | 3.9 µs |
| Destroyed load-bearing spar, 14-part island severed | 22–40 | 18.5 µs |
| Pathological: Core Module destroyed | Full graph | 61.0 µs (once, at Assembly death) |

Against the naive full-fill's constant ~15 µs, the common cases are 4–12× cheaper, and the cost now scales with the *size of the damage* rather than the size of the Assembly.

### 5.5 Cascade Batching

Multiple parts frequently die in the same physics tick — a blast damages six panels at once. Evaluating detachment six times produces six island sets, some of which are subsets of others, and six debris spawns where one is correct.

Destruction events are therefore accumulated into a per-Assembly pending set and resolved **once at the end of the tick**, in the `EventBus.tick_resolved` phase:

```gdscript
class_name DetachmentScheduler
extends Node

var _pending: Dictionary = {}       # assembly_id -> PackedByteArray of destroyed slots
var _reentrancy_guard: bool = false

func _ready() -> void:
    EventBus.part_destroyed.connect(_queue)
    EventBus.joint_failed.connect(_queue_joint)
    EventBus.tick_resolved.connect(_resolve_all)

func _queue(assembly_id: int, slot: int) -> void:
    var set: PackedByteArray = _pending.get(assembly_id, PackedByteArray())
    if not set.has(slot):
        set.push_back(slot)
    _pending[assembly_id] = set

func _resolve_all() -> void:
    if _pending.is_empty():
        return                                   # the overwhelmingly common path
    assert(not _reentrancy_guard, "detachment re-entered")
    _reentrancy_guard = true
    var ids := _pending.keys()
    ids.sort()                                   # deterministic order for the network
    for assembly_id in ids:
        var slots: PackedByteArray = _pending[assembly_id]
        var sorted := Array(slots); sorted.sort() # deterministic within assembly
        _resolve_assembly(assembly_id, PackedByteArray(sorted))
    _pending.clear()
    _reentrancy_guard = false
```

`_resolve_assembly` removes **all** destroyed slots first, collects the union of their surviving neighbours as seeds, and then runs a single reverse-reachability pass. One pass, one island set, one debris spawn per island.

The pending sets are **swapped out before resolution begins**, not cleared after it. `_pending.clear()` at the end of the pass would wipe exactly the secondary deaths §5.6 exists to defer — the ones queued *during* resolution, which must survive into the next tick.

A failed joint is queued separately from a destroyed part. `joint_failed` severs the edge immediately and queues the part the joint was holding up; that part is intact and merely unsupported, so it must not go into the destroyed set. If it turns out to still reach the Core Module through another edge it simply re-parents; if it does not, it is *itself* the island, along with everything still attached to it, and `DetachmentSolver.sever_unsupported` is what severs that component. Passing it to `solve` instead would treat it as a part that has ceased to exist, search outwards from the neighbours it leaves behind, and quietly delete an unsupported leaf without reporting an island for it.

Turning a severed island into a `RigidBody3D` is §6 and is reached through the scheduler's `island_sink`. The scheduler resolves topology — which parts stopped being attached, and what the Assembly looks like afterwards — and announces each island on its own `island_severed` signal, which is the authoritative structural fact and is true whether or not a debris body is spawned to represent it. `EventBus.island_detached` (§8.2) is emitted by §6, once a body exists to carry an id.

The deterministic sort of both assembly ids and slot indices is not cosmetic. It guarantees the server and every client that replays the same event set produce identical island decompositions and identical debris body ordering, which the network layer relies on (`HEADLESS_NETWORK_SYNC.md` §7.3).

### 5.6 Re-entrancy

Detaching an island can itself destroy parts — a severed Power Plant detonates (`PART_DATA_SCHEMA.md` §7.3), damaging nearby parts, some of which may die. Those deaths must **not** recursively re-enter the solver mid-pass.

The guard in `_resolve_all` asserts against re-entry, and `_queue` remains safe to call during resolution: newly destroyed parts land in `_pending` for the **next** tick's resolution. A chain reaction therefore unfolds over successive ticks — which is both correct and visually superior to resolving instantaneously.

---

## 6. Island Conversion to Debris

A severed island stops being part of the Assembly and becomes an independent `RigidBody3D`.

```gdscript
class_name IslandDetacher
extends RefCounted

const DEBRIS_LIFETIME_S := 22.0
const DEBRIS_MIN_PARTS_FOR_BODY := 1

static func detach(
    runtime: AssemblyRuntime, island: PackedByteArray, pool: DebrisPool
) -> DebrisBodyRef:
    var total_mass := 0.0
    var weighted := Vector3.ZERO
    var carried := PackedByteArray()

    # --- Aggregate mass properties in assembly-local space -----------------
    for slot in island:
        var st := runtime.state(slot)
        if st == null:
            continue                            # reported; §5.3 severed it already
        assert(not runtime.graph.is_alive(slot))
        var def := PartRegistry.definition(st.part_def_id)
        var p := MassSolver.part_com_local(st, def)
        total_mass += def.mass_kg
        weighted += p * def.mass_kg
        carried.append(slot)
    if carried.size() < DEBRIS_MIN_PARTS_FOR_BODY:
        return null
    var island_com_local := weighted / maxf(total_mass, MassSolver.MASS_FLOOR_KG)

    # --- Re-register colliders, rebased onto the island COM ----------------
    var body := pool.acquire()
    body.source_assembly_id = runtime.assembly_id
    body.slots = carried
    for slot in carried:
        runtime.states[slot].flags |= PartFlags.FLAG_DETACHED
        runtime.detach_colliders_to(body, slot, island_com_local)

    var mp := MassSolver.MassProperties.new()
    mp.total_mass = total_mass
    mp.com_local = Vector3.ZERO                 # already re-centred on the island COM
    mp.inertia_diag = InertiaSolver.island_inertia(runtime.states, carried, island_com_local)
    MassSolver.apply_mass_properties(body, mp)

    body.global_transform = runtime.body.global_transform \
                          * Transform3D(Basis(), island_com_local)

    # --- Inherit the velocity the island actually had at its own COM -------
    var r := runtime.body.global_transform.basis * island_com_local
    body.linear_velocity = runtime.body.linear_velocity \
                         + runtime.body.angular_velocity.cross(r)
    body.angular_velocity = runtime.body.angular_velocity

    pool.reaper.schedule(body, DEBRIS_LIFETIME_S)
    EventBus.island_detached.emit(runtime.assembly_id, carried, body.get_instance_id())
    return body
```

`island_inertia` takes the state array rather than the `AssemblyRuntime` this section originally passed it. It reads nothing else from the runtime, and taking the array keeps the mass layer independent of the runtime layer — the same reason `ChassisGraph.attach` takes a part's mass rather than reaching into `PartRegistry` for it. It is implemented in `DYNAMIC_MASS_PHYSICS.md` §3.3.

The velocity inheritance term `ω × r` is essential. Without it, a panel shorn off a spinning Assembly drops straight down while the Assembly rotates away — a tell-tale artefact of naive detachment implementations. With it, the panel flies off tangentially, exactly as it should.

**Six amendments**, none of which changes what this section decides:

1. **`DebrisPool` and `DebrisReaper` are instances, passed in.** This section originally called them as globals. `CLAUDE.md` §4 freezes the autoload list at eight, so the pool is an ordinary `Node` owned by the match scene; it constructs and owns the reaper, because a reaper pointed at no pool is not a meaningful object.

2. **The graph writes belong to §5.3, not here.** This section wrote `assembly.graph.alive[slot] = 0`, which `ChassisGraph.remove_node` has already done by the time an island is announced. Two owners of the one fact this whole subsystem turns on is worse than either alone: neither would be load-bearing, and either could be deleted silently. §6 asserts the slot is already dead instead.

3. **Colliders are re-registered on the debris body, not moved to it.** A body's shape indices are assignment order, so removing one renumbers every later index and repoints the shape-index to slot map of `COMPONENT_HEALTH_DAMAGE.md` §5.4 for every part placed after the island — one severed panel becoming mis-attributed hits across the rest of the hull. The island's primitives are therefore registered on the debris body — the *same* `Shape3D` resources, shared rather than rebuilt, which is what §6.1 means by reusing the authored primitives — and the Assembly's copies are disabled where they stand, exactly as `AssemblyRuntime.release_part` disables them.

4. **`detach_visual_to` is absent.** No Assembly has meshes yet; `EXTENSION_PIPELINE.md` §9 owns their spawn, and the visual half of detachment lands with it.

5. **The mass properties go through `MassSolver.apply_mass_properties`.** Writing `body.mass` and `body.inertia` directly here would be a second place that has to know Godot refuses a zero mass and reads a zero inertia as "derive it from the collision shapes" — the exact coupling Architectural Invariant I-1 forbids. `DYNAMIC_MASS_PHYSICS.md` §3.5 owns those floors.

6. **`DEBRIS_MIN_PARTS_FOR_BODY` is tested against the parts that resolved**, not against the argument. With the minimum at one the two agree, so testing both would leave neither load-bearing.

### 6.1 Debris Colliders

Debris reuses the **same authored `ColliderProfile` primitives** as the parent Assembly. Nothing is generated from mesh geometry, and nothing is convex-decomposed. The colliders are simply re-registered against the new body with transforms rebased to the island COM. This keeps Architectural Invariant #1 intact through detachment.

Debris on `LAYER_DEBRIS` does **not** collide with other debris (mask excludes its own layer). This is a deliberate simplification: debris-vs-debris contacts are visually irrelevant, contribute nothing to gameplay, and are the largest single source of contact-pair explosion during a multi-Assembly destruction event.

### 6.2 Debris Budget

`DebrisPool` maintains a fixed pool of 96 `RigidBody3D` instances. When exhausted, the oldest debris body is recycled immediately (fading out over 0.25 s). Bodies also sleep aggressively:

```gdscript
body.sleeping = false
body.can_sleep = true
body.linear_damp = 0.35
body.angular_damp = 0.55
```

`DebrisReaper` additionally freezes any debris body that has been asleep for more than 4 s (`freeze_mode = FREEZE_MODE_STATIC`), removing it from the solver entirely while keeping it visible until its lifetime expires.

**Three amendments.**

**Both deadlines are tick counts, not accumulated seconds.** 22 s is 1320 additions of `PHYSICS_DT`, which does not land on a round number, so a float countdown expires a tick early or late depending on how the additions happened to round. The tick a body disappears on is replicated (`HEADLESS_NETWORK_SYNC.md` §5), so the server and a client accumulating in a different order would disagree about it. `DebrisReaper` stores `expires_at_tick` and `asleep_since_tick` on the body and compares integers. The same reasoning produced §4.2's dwell epsilon; here the problem can be removed rather than tolerated.

**Shape nodes are reused, never freed.** A body returning to the pool disables its `CollisionShape3D` children and rewinds a cursor; the next island overwrites them in place and appends only if it needs more. Freeing them would mean removing nodes from a body inside a physics callback — the reaper runs on `MatchClock.tick_started` — and, worse, `queue_free` would leave the recycling path above handing out a body still carrying the last island's geometry for the rest of the frame.

**The 0.25 s recycle fade is not implemented.** It is presentation, and debris has no meshes to fade until `EXTENSION_PIPELINE.md` §9 lands. A recycled body currently disappears on the tick it is taken.

---

## 7. Downstream Functional Consequences

Detachment is structural. Functional loss is a separate, immediate consequence computed when an island is severed or a part is destroyed:

| Lost part class | Downstream effect | Handled in |
|---|---|---|
| `MOTIVE_ASSEMBLY` | Suspension ray removed; mass and COM recomputed; drive torque redistributed across remaining driven wheels | `DYNAMIC_MASS_PHYSICS.md` §5, §7 |
| `POWER_PLANT` | Assembly power supply drops; modules exceeding budget are flagged `FLAG_POWER_STARVED` in ascending priority order | §7.1 |
| `EFFECTOR_MODULE` | Removed from the targeting set; any in-flight guided ordnance it owns goes ballistic | `WEAPON_TARGETING_LOGIC.md` §10 |
| `SUPPORT_MODULE` | Its effect is subtracted from the Assembly aggregate; volatile modules detonate | `PART_DATA_SCHEMA.md` §7.5 |
| `CONTROL_SURFACE` | Aerodynamic contribution removed | `DYNAMIC_MASS_PHYSICS.md` §8 |
| `CORE_MODULE` | Assembly destroyed; all remaining parts become debris islands | §7.2 |

### 7.1 Power Starvation Ordering

When supply drops below draw, modules are starved deterministically — never randomly, never by iteration order:

1. Descending `power_draw_pu` (shed the biggest consumer first).
2. Ties broken by descending slot index.

Shedding continues until the budget balances. Starved modules are restored in exact reverse order when supply recovers. The ordering rule is normative because client-side prediction reproduces it locally, and any divergence would show as a weapon that fires on the client but not on the server.

### 7.2 Core Module Loss

Losing the Core Module ends the Assembly. Rather than running the reachability solver (every part is orphaned by definition), `_resolve_assembly` short-circuits:

```gdscript
if destroyed_slots.has(ChassisGraph.CORE):
    AssemblyTerminator.terminate(assembly)
    return
```

`AssemblyTerminator` partitions the remaining live parts into connected components using a single full flood fill — the one place a full fill is correct, because every node genuinely must be classified — and emits one debris body per component, capped at 8 bodies with the remainder merged into the largest.

The partition is `DetachmentSolver.partition_live_components`, and the cap is `MAX_TERMINAL_COMPONENTS = 8`. Merging is by descending component size, ties broken on the lowest slot, so which component absorbs the remainder never depends on traversal order and no slot is ever dropped.

Every slot destroyed in the same tick — the Core Module included — is removed **before** the partition runs. Those parts are gone, not debris; partitioning first would put the destroyed Core Module into a component and spawn a body for a part that no longer exists.

---

## 8. Event Contract

Every signal the graph consumes or emits, with its exact payload. These are declared on the `EventBus` autoload (`src/autoload/event_bus.gd`).

### 8.1 Consumed

| Signal | Payload | Emitted by |
|---|---|---|
| `part_destroyed` | `(assembly_id: int, slot: int, cause: int)` | `DamageResolver` when integrity reaches 0 |
| `joint_failed` | `(assembly_id: int, slot_a: int, slot_b: int)` | `ChassisGraph.evaluate_strain` |
| `part_removed` | `(assembly_id: int, slot: int)` | Garage build commands |
| `part_attached` | `(assembly_id: int, slot: int)` | Garage build commands, blueprint load |
| `tick_resolved` | `()` | `MatchClock`, end of each physics tick |

### 8.2 Emitted

| Signal | Payload | Consumed by |
|---|---|---|
| `assembly_structure_changed` | `(assembly_id: int)` | SDF baker, skirting system, mass solver, UI stat panel |
| `island_detached` | `(assembly_id: int, slots: PackedByteArray, body_id: int)` | Network replication, audio, VFX, scoring |
| `assembly_mass_dirty` | `(assembly_id: int)` | `MassSolver` |
| `assembly_terminated` | `(assembly_id: int, killer_id: int)` | Match state, scoring, respawn |
| `island_severed` | `(assembly_id: int, slots: PackedByteArray)` | `IslandDetacher` (§6), tests |
| `joint_strain_changed` | `(assembly_id: int, slot_a: int, slot_b: int, strain: float)` | Skirt stress decals, audio groan cue |

`island_severed` is declared on `DetachmentScheduler` rather than on the `EventBus`, because it is the handoff between two halves of one subsystem and not a cross-system signal. `island_detached` remains the `EventBus` signal, carrying the debris body id §6 produces.

`killer_id` is a peer id, and is `0` when the termination is unattributed. Only the damage layer knows who fired the packet that reached zero; the graph sees a `part_destroyed` carrying a damage channel, not an attacker. Until attribution is recorded, terminations report `0`.

### 8.3 Ordering Guarantee

Within `tick_resolved`, handlers run in a fixed registration order enforced by `EventBus` priority groups:

```
PRIORITY_DAMAGE      = 100   # integrity writes complete
PRIORITY_DETACHMENT  = 200   # islands determined, debris spawned
PRIORITY_MASS        = 300   # mass/COM/inertia recomputed
PRIORITY_FUNCTIONAL  = 400   # power, traction, targeting sets updated
PRIORITY_PRESENTATION= 500   # SDF/skirt/UI marked dirty
PRIORITY_NETWORK     = 600   # snapshot assembled
```

A handler registered at a lower priority may never observe state produced by a higher one within the same tick. This ordering is what makes the whole event-driven design tractable to reason about, and it is asserted by `tests/integration/test_tick_ordering.gd`.

---

## 9. Garage-Mode Differences

In the garage there is no combat, no strain, and no debris. Graph behaviour differs in three ways:

1. `part_removed` triggers **re-parenting before cascade** (`GRID_SNAPPING_LOGIC.md` §9.2). Orphans that can find an alternate parent are kept.
2. Cascade removal requires explicit player confirmation, showing the exact count and highlighting the affected parts in `#E0554E`.
3. Strain is displayed as a static prediction (using `κ_dynamic = 1.0`) but never fails a joint.

---

## 10. Diagnostics

`ChassisGraph.debug_report()` produces a deterministic textual dump used by tests and by the in-match developer overlay:

```gdscript
func debug_report() -> String:
    var sb := PackedStringArray()
    sb.push_back("slot parent depth alive mass_kg subtree_kg neighbours")
    for s in MAX:
        if alive[s] == 0 and parent[s] == INVALID:
            continue
        sb.push_back("%4d %6d %5d %5d %7.1f %10.1f  %s" % [
            s, parent[s], depth[s], alive[s], m_mass_of(s), subtree_mass[s],
            String(",").join(Array(neighbours[s]))])
    return String("\n").join(sb)
```

The overlay additionally renders support edges as coloured lines — green below 0.5 strain, amber to 0.9, red above — using a single `ImmediateMesh` rebuilt only when `joint_strain_changed` fires.

---

## 11. Invariants

1. `ChassisGraph` and `DetachmentSolver` declare no `_process` and no `_physics_process`. Connectivity work occurs only in response to `part_destroyed`, `joint_failed`, `part_removed`, or `part_attached`.
2. Slot 0 is the Core Module, is the primary-tree root, and has `parent == INVALID`.
3. Connectivity is evaluated over support edges, never over the primary tree.
4. The primary tree is acyclic; `_propagate_mass_delta` asserts this on every write.
5. Detachment resolution is batched to once per tick per Assembly, with deterministic ordering by assembly id then slot index.
6. Detachment never re-enters itself; secondary destruction resolves on the following tick.
7. Debris reuses authored collider primitives. No mesh-derived collision shape is ever created.
8. Island velocity inheritance includes the `ω × r` tangential term.
9. All traversal scratch is preallocated; no heap allocation occurs in the detachment path during a match.
