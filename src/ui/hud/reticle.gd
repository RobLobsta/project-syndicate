class_name Reticle
extends Control
## The match reticle, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.3.
##
## Drawn rather than assembled from textures, because the whole thing is four
## brackets and a dot and an atlas fetch would cost more than the draw does.
##
## §10 rule 5: colour is never the only carrier of meaning. Each of the five
## states has a distinct [i]shape[/i] as well as a distinct token, so the reticle
## is readable to a colour-blind player and in a screenshot that has been through
## a lossy encoder.
##
## §14.3 separates [constant HudFrame.ReticleState.SEEKING] from
## [constant HudFrame.ReticleState.TRACKING] because doc 07 §4.3.1's
## [code]solution_in_arc[/code] distinguishes them and the player needs that
## distinction to act: a mount that cannot physically reach the target is a
## driving problem — turn the hull — and a mount still slewing is a waiting
## problem. One state for both would tell a player to do nothing in exactly the
## case where they must do something.

## Half-width of the reticle at its widest, in logical units.
const SPREAD_MAX_PX: float = 26.0
## Half-width when a solution has converged.
const SPREAD_MIN_PX: float = 10.0
const BRACKET_LENGTH_PX: float = 9.0
const CENTRE_DOT_RADIUS_PX: float = 2.0
const LINE_WIDTH_PX: float = 2.0
## Rate at which the brackets draw in and out. Hertz, exponential, for the reason
## doc 11 §13.5 gives.
const SPREAD_LAG_HZ: float = 11.0

## §14.3's target bracket: half-width of the four corner ticks drawn outside the
## reticle when the aim ray is on a hull. Outside the brackets rather than
## replacing them, because the two answer different questions and a player needs
## both at once — "my gun is ready" and "I am pointing it at something".
const TARGET_BRACKET_SPREAD_PX: float = 34.0
const TARGET_BRACKET_LENGTH_PX: float = 7.0

var state: HudFrame.ReticleState = HudFrame.ReticleState.NO_EFFECTOR
## Whether the aim ray ended on an Assembly hull. See [member HudFrame.target_acquired].
var target_acquired: bool = false

var _spread_px: float = SPREAD_MAX_PX


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	var target := SPREAD_MAX_PX if _is_open() else SPREAD_MIN_PX
	var next := lerpf(_spread_px, target, 1.0 - exp(-SPREAD_LAG_HZ * maxf(dt, 0.0)))
	if is_equal_approx(next, _spread_px):
		return
	_spread_px = next
	queue_redraw()


## Applies [param next], redrawing only on a change. The reticle is redrawn every
## frame the brackets are moving and never when they are not.
func set_state(next: HudFrame.ReticleState) -> void:
	if next == state:
		return
	state = next
	queue_redraw()


## Applies [param next], redrawing only on a change, exactly as
## [method set_state] does. Separate from the state because it is a separate
## question: doc 07 §4.3.1's answers are about the mount and this one is about
## what is under the crosshair.
func set_target_acquired(next: bool) -> void:
	if next == target_acquired:
		return
	target_acquired = next
	queue_redraw()


## Token for [param s], §14.3's table.
static func colour_for(s: HudFrame.ReticleState) -> Color:
	match s:
		HudFrame.ReticleState.NO_EFFECTOR:
			return UiTokens.TEXT_MUTED
		HudFrame.ReticleState.SEEKING:
			return UiTokens.TEXT_PRIMARY
		HudFrame.ReticleState.TRACKING:
			return UiTokens.WARN
		HudFrame.ReticleState.ON_TARGET:
			return UiTokens.ACCENT_SECONDARY
		HudFrame.ReticleState.NO_AMMO:
			return UiTokens.DANGER
	return UiTokens.TEXT_MUTED


func _draw() -> void:
	var c := size * 0.5
	var col := colour_for(state)

	if target_acquired:
		# Drawn before the reticle and in its own token, so that "there is a hull
		# under the crosshair" is legible whatever the mount is doing — including
		# in the state a player most needs it, an empty store over a live target.
		_draw_target_bracket(c)

	if state == HudFrame.ReticleState.NO_EFFECTOR:
		# A dot and nothing else. An Assembly with no Effector Module has nothing
		# to aim, and drawing brackets it can never close would promise a shot it
		# cannot take.
		draw_circle(c, CENTRE_DOT_RADIUS_PX, col)
		return

	var s := _spread_px
	var l := BRACKET_LENGTH_PX
	# Four corner brackets. Horizontal arm then vertical arm, per corner.
	for sx: int in [-1, 1] as Array[int]:
		for sy: int in [-1, 1] as Array[int]:
			var corner := c + Vector2(sx * s, sy * s)
			draw_line(corner, corner - Vector2(sx * l, 0.0), col, LINE_WIDTH_PX)
			draw_line(corner, corner - Vector2(0.0, sy * l), col, LINE_WIDTH_PX)

	if state == HudFrame.ReticleState.ON_TARGET:
		draw_circle(c, CENTRE_DOT_RADIUS_PX, col)
	elif state == HudFrame.ReticleState.NO_AMMO:
		# A diagonal bar through the middle: the one state a player must not
		# mistake for a firing solution, and the one that must survive being read
		# in greyscale.
		var d := Vector2(s, s) * 0.7
		draw_line(c - d, c + d, col, LINE_WIDTH_PX)


## §14.3's target bracket. Four corner ticks in [constant UiTokens.ACCENT_PRIMARY]
## — the one accent the reticle does not already use, so it cannot be read as any
## of the five mount states.
func _draw_target_bracket(c: Vector2) -> void:
	var s := TARGET_BRACKET_SPREAD_PX
	var l := TARGET_BRACKET_LENGTH_PX
	for sx: int in [-1, 1] as Array[int]:
		for sy: int in [-1, 1] as Array[int]:
			var corner := c + Vector2(sx * s, sy * s)
			draw_line(
				corner, corner - Vector2(sx * l, 0.0), UiTokens.ACCENT_PRIMARY, LINE_WIDTH_PX
			)
			draw_line(
				corner, corner - Vector2(0.0, sy * l), UiTokens.ACCENT_PRIMARY, LINE_WIDTH_PX
			)


## Wide brackets mean "no solution yet"; drawn-in brackets mean converged.
func _is_open() -> bool:
	return state == HudFrame.ReticleState.SEEKING or state == HudFrame.ReticleState.NO_EFFECTOR
