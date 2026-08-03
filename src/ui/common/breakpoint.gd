class_name Breakpoint
extends RefCounted
## The layout tiers of [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §3.1, and the
## one place their thresholds are written down.
##
## [b]Height participates in the compact test.[/b] A phone in landscape has ample
## width and very little height, and a rule that only looked at width would give
## it a catalogue two rows tall. That is the whole reason this is a function of a
## [Vector2] rather than of a float.
##
## The tier is a function of [member UiScaleService.logical_size] — logical units
## after the content scale, never pixels — so a high-DPI display gets the layout
## its physical size deserves rather than the one its pixel count implies. It is
## orthogonal to [code]InputMethod[/code]: a keyboard on a tablet gives a compact
## layout with a desktop interaction model, and the code treats those as separate
## axes because they are.

enum Tier { COMPACT = 0, MEDIUM = 1, EXPANDED = 2, ULTRAWIDE = 3 }

const COMPACT_MAX_W: float = 900.0
const MEDIUM_MAX_W: float = 1400.0
const EXPANDED_MAX_W: float = 2100.0
const SHORT_MAX_H: float = 620.0

## Catalogue columns per tier, indexed by [enum Tier].
##
## [b]Amendment to §3.2.[/b] That table is 2/2/3/4, and it is written for the
## icon-first [PartCard] of §5.3 — a card whose readable content is a rendered
## thumbnail with a short name under it. There is no [code]PartIconCache[/code],
## so the shipped card is text-first, and a text-first card in a 220-unit dock at
## two columns is 106 units wide: it showed "Compac" and "Medium" when it was
## first looked at. One fewer column per tier until the icon lands.
const CATALOGUE_COLUMNS: Array[int] = [1, 1, 2, 3]
## Catalogue dock width in logical units per tier. The compact tier docks
## nothing — it uses the bottom sheet — and its entry is never read.
const CATALOGUE_DOCK_W: Array[float] = [0.0, 250.0, 320.0, 380.0]
## Right-hand dock width in logical units per tier.
const INSPECTOR_DOCK_W: Array[float] = [0.0, 250.0, 300.0, 340.0]


static func tier_for(logical: Vector2) -> Tier:
	if logical.x < COMPACT_MAX_W or logical.y < SHORT_MAX_H:
		return Tier.COMPACT
	if logical.x < MEDIUM_MAX_W:
		return Tier.MEDIUM
	if logical.x < EXPANDED_MAX_W:
		return Tier.EXPANDED
	return Tier.ULTRAWIDE


## Whether [param tier] docks its catalogue and inspector at the sides. The
## compact tier does not: §3.2 gives it a bottom sheet and a modal inspector.
static func is_docked(tier: Tier) -> bool:
	return tier != Tier.COMPACT


## Whether [param tier] shows the stat dock.
##
## [b]§3.2 and §3.3 disagree and the table is right.[/b] The table gives the
## medium tier a stat panel "docked below inspector"; the code beside it writes
## `stat_dock.visible = t >= Tier.EXPANDED`, which hides it. Hiding wins nothing:
## a 1600×900 window is the medium tier, it is the commonest window there is, and
## a player in it was shown a garage with no mass, no power and no rollover
## figure at all. Only the compact tier collapses them, and there they belong to
## a bottom sheet that is not built.
static func shows_stat_dock(tier: Tier) -> bool:
	return tier >= Tier.MEDIUM


static func catalogue_columns(tier: Tier) -> int:
	return CATALOGUE_COLUMNS[int(tier)]


static func catalogue_dock_width(tier: Tier) -> float:
	return CATALOGUE_DOCK_W[int(tier)]


static func inspector_dock_width(tier: Tier) -> float:
	return INSPECTOR_DOCK_W[int(tier)]
