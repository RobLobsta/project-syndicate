class_name RenderLayers
extends RefCounted
## Visual instance layer assignments, owned by [code]CLAUDE.md[/code] §5.2.
##
## Values are bit masks ready to assign to
## [code]VisualInstance3D.layers[/code] or [code]Camera3D.cull_mask[/code].

const LAYER_WORLD: int = 1 << 0  # ground, Static Volumes, skybox-adjacent
const LAYER_ASSEMBLY_VISUAL: int = 1 << 1  # part meshes, skirting, decals
const LAYER_DEBRIS_VISUAL: int = 1 << 2  # detached islands and fragments
const LAYER_VFX: int = 1 << 3  # particles, tracers, beams
const LAYER_GARAGE_ONLY: int = 1 << 4  # lattice grid, ghost preview, gizmos
const LAYER_ICON_RENDER: int = 1 << 19  # isolated layer for the icon SubViewport

## What a match camera renders: everything except garage furniture and the
## isolated icon-render layer.
const CULL_MATCH_CAMERA: int = LAYER_WORLD | LAYER_ASSEMBLY_VISUAL | LAYER_DEBRIS_VISUAL | LAYER_VFX

## What the garage camera renders: no debris, plus the build gizmos.
const CULL_GARAGE_CAMERA: int = (
	LAYER_WORLD | LAYER_ASSEMBLY_VISUAL | LAYER_VFX | LAYER_GARAGE_ONLY
)

## The part-icon SubViewport camera sees nothing but the isolated layer, so a
## live match in the background can never bleed into a catalogue thumbnail.
const CULL_ICON_CAMERA: int = LAYER_ICON_RENDER
