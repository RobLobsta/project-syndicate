class_name AiContext
extends RefCounted
## Everything the AI layer is allowed to know about the match, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §10.1.
##
## One of these belongs to each [AiDriver] and is rebuilt on that section's scan
## interval rather than per tick. It exists so that [AiTargetSelector] is a pure
## function of a record: a selector that reached into the [AssemblyRegistry]
## itself would be untestable without a match, and would be free to read state —
## integrity, bands, hardpoint angles — that Invariant I-5 keeps out of per-tick
## paths and that nothing in the AI layer has any business reading at all.
##
## [b]The roster is data this object carries, not a field on anything the damage
## path touches.[/b] Nothing in [code]src/combat/[/code] knows what a team is:
## [DamagePacket] names a source Assembly and [DamageResolver] never asks whose
## side it is on, so friendly fire is decided by which hull the ray reaches
## first. The AI layer is the first consumer of the concept and holds it here,
## which keeps the resolver's ignorance of it a deliberate property rather than
## something the next system to want teams has to unpick.

## One candidate, as of the last scan. §10.1: four fields sampled off an
## [AssemblyRuntime] and discarded at the next scan, which is why this is an
## inner class and not a type of its own.
class TargetHandle:
	extends RefCounted

	var id: int = 0
	var team: int = 0
	## The Core Module's world position. Also the aim point the driver hands
	## [EffectorSystem]: Invariant I-2 makes that part the thing worth shooting
	## at, and a second point to aim at would be a second answer to one question.
	var position: Vector3 = Vector3.ZERO
	## The Core Module's, not the whole Assembly's. §10.1: how close a target is
	## to being finished is a question about one part, and a whole-Assembly figure
	## reads "wounded" for a build that has lost a Motive Assembly and is
	## otherwise intact.
	var integrity_fraction: float = 1.0


## The Assembly this context belongs to, and the side it is on.
var assembly_id: int = 0
var team: int = 0
## Where it is, in world space. The body origin rather than the Core Module,
## because this is the point ranges are measured from and the driver already
## holds the body.
var position: Vector3 = Vector3.ZERO
## Whoever last landed a packet on it, or 0. §10's retaliation term.
var last_attacker_id: int = 0

## Candidates as of the last scan. Rebuilt in registry order, which is ascending
## (Invariant I-9), so two drivers scanning on the same tick break score ties the
## same way.
##
## [b]There is no visibility test.[/b] The name is doc 07 §10's and it is
## aspirational: every live Assembly is a candidate. Closing that is a line of
## sight query §10 does not specify, and pretending otherwise here would be a
## worse gap than the honest one.
var visible_assemblies: Array[TargetHandle] = []

## The mount §10.2's arc cost is asked about, and the slot it sits in. Set once
## by the driver; a context for an Assembly with no Effector Module leaves them
## null and [constant SyndicateConstants.INVALID_SLOT], and every candidate then
## costs nothing to reach.
var effectors: EffectorSystem = null
var effector_slot: int = SyndicateConstants.INVALID_SLOT


## Rebuilds [member visible_assemblies] and [member position] from the live
## registry. §10.1's scan.
##
## [param roster] maps assembly id to team. An Assembly the roster does not name
## is skipped rather than defaulted onto a side: a candidate whose team is a
## guess is one an AI may shoot at because nobody said not to.
func rescan(registry: AssemblyRegistry, roster: Dictionary) -> void:
	visible_assemblies.clear()
	var own := registry.get_runtime(assembly_id)
	if own != null:
		position = own.body.global_position
	for id: int in registry.ids():
		if id == assembly_id or not roster.has(id):
			continue
		var runtime := registry.get_runtime(id)
		if runtime == null:
			continue
		var handle := _handle_for(runtime, int(roster[id]))
		if handle != null:
			visible_assemblies.append(handle)


## A handle for [param runtime], or null when its Core Module is gone — which
## Invariant I-2 makes the end of the Assembly and therefore the end of its
## candidacy. Read from the part rather than from a flag the AI keeps, so that
## nothing here can disagree with [DamageResolver].
static func _handle_for(runtime: AssemblyRuntime, team_id: int) -> TargetHandle:
	var st := runtime.state(SyndicateConstants.CORE_SLOT)
	if st == null or st.has_flag(PartFlags.FLAG_DESTROYED):
		return null
	var def := runtime.definition_at(SyndicateConstants.CORE_SLOT)
	if def == null:
		return null
	var handle := TargetHandle.new()
	handle.id = runtime.assembly_id
	handle.team = team_id
	handle.position = runtime.part_world_position(SyndicateConstants.CORE_SLOT)
	handle.integrity_fraction = st.integrity_fraction(def)
	return handle


## The candidate with [param id], or null. The driver holds a target across
## scans by id rather than by reference, so that a handle from a previous scan
## can never be aimed at after the Assembly it names has been destroyed.
func handle_for_id(id: int) -> TargetHandle:
	for handle: TargetHandle in visible_assemblies:
		if handle.id == id:
			return handle
	return null
