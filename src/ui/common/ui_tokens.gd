class_name UiTokens
extends RefCounted
## The colour tokens of [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §8.3, and the
## one place they are written down.
##
## §8.3 shares three of these with the 3D placement ghost of
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §8 — [constant ACCENT_SECONDARY],
## [constant WARN], [constant DANGER] — so that the interface and the world agree
## about what "this will work" looks like. A second definition of any of them is
## the duplicated-constant defect of CLAUDE.md §1.1, not a style question: two
## greens that drift apart mean a garage that promises a placement the world then
## draws in a different colour.
##
## Doc 11 §14.3 reuses the same three in the match reticle, deliberately. In the
## garage [constant ACCENT_SECONDARY] means "this will work"; on the reticle it
## means "this shot will land", and a player learns one colour rather than two.

## ===== SURFACES ========================================================

const SURFACE_BASE := Color("#14171C")
const SURFACE_RAISED := Color("#1D2229")
const SURFACE_OVERLAY := Color("#262D36")

## ===== ACCENTS =========================================================

const ACCENT_PRIMARY := Color("#4EA8E0")
const ACCENT_SECONDARY := Color("#39D98A")
const WARN := Color("#F2C14E")
const DANGER := Color("#E0554E")

## ===== TEXT ============================================================

const TEXT_PRIMARY := Color("#E6EAF0")
const TEXT_MUTED := Color("#8D97A5")

## §6.1's threshold: a meter goes amber before it goes red, so "close to budget"
## and "over budget" are distinguishable states rather than one cliff.
const METER_WARN_RATIO: float = 0.9


## Colour for a fill ratio against its budget, matching §6.1's meter rule:
## over budget is shown rather than blocked, because the placement validator
## already refuses an illegal build and a meter in the red is information.
static func meter_colour(ratio: float) -> Color:
	if ratio > 1.0:
		return DANGER
	if ratio > METER_WARN_RATIO:
		return WARN
	return ACCENT_SECONDARY
