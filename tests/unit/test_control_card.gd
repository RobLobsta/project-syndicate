extends TestCase
## [ControlCard]'s dwell and stand-down, from
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.6.
##
## The card is the first thing a player sees in a match and it was, for two
## sessions, the thing they saw *instead of* the match: centred, opaque, and up
## for eleven seconds across the band of screen three opponents approach through.
## Neither the placement nor the dwell moved a single check.
##
## Both halves are asserted here. The placement is geometry and reads as a
## triviality until you notice that nothing else in the repository could have
## caught it — the capture did. The stand-down is behaviour, and it is driven
## through the real [InputMap] rather than through a flag, because §14.6's rule is
## about what the player pressed and a test that set a boolean would assert the
## boolean (LEARNED_FACTS.md §1 fact 40).
##
## No tree and no viewport: [method ControlCard.age] and the anchors are readable
## on a node that has never been added to anything, and putting a [Control] under
## the autoload root to look at four floats would be the more fragile test.

## §14.4's event feed is the top right and §14.2's status panel the bottom left,
## so the card must not reach into either. Quoted by value from §14.6 rather than
## imported: a test that read [constant ControlCard.BAND_RIGHT] back out of the
## source would move with it and assert nothing.
const DOC_BAND_RIGHT: float = 0.34
const DOC_BAND_BOTTOM: float = 0.66

var _card: ControlCard = null


func before_all() -> void:
	_card = ControlCard.new()


func after_all() -> void:
	if _card != null:
		_card.free()
		_card = null


## Released at the top of every test rather than the bottom: the runner sorts
## methods, and a test that failed part-way through would otherwise leave a key
## held for the next one (LEARNED_FACTS.md §1 fact 40).
func _release_all() -> void:
	for action: StringName in ControlCard.ACTED_ACTIONS:
		Input.action_release(action)


func test_the_card_sits_in_the_upper_left_and_leaves_the_other_corners_alone() -> void:
	_release_all()
	check_approx(_card.anchor_left, 0.0, "flush to the left edge, before its inset")
	check_approx(_card.anchor_top, 0.0, "and to the top")
	check_approx(_card.anchor_right, DOC_BAND_RIGHT, "a third of the width, per §14.6")
	check_approx(_card.anchor_bottom, DOC_BAND_BOTTOM, "and two thirds of the height")
	# The assertion that carries the finding: whatever the band is, it must not be
	# the middle of the screen, because that is where the opponents come from.
	check_true(
		_card.anchor_right < 0.5,
		"the card clears the centre of the screen horizontally, which is the whole "
			+ "point of §14.6's placement amendment"
	)
	check_true(_card.offset_left > 0.0, "and is inset from the edge rather than flush")


func test_the_dwell_runs_out_for_a_player_who_does_nothing() -> void:
	_release_all()
	_card.raise()
	check_true(_card.is_raised(), "raising it puts it up")
	# One second short of the dwell, in one-second steps: a player sitting still
	# keeps the card for the whole of it.
	for i: int in int(ControlCard.DWELL_S) - 1:
		_card.age(1.0)
	check_true(_card.is_raised(), "and it is still up a second before the dwell expires")
	_card.age(2.0)
	check_false(_card.is_raised(), "and down after it")


## §14.6's stand-down. The card goes when the player takes hold of the machine,
## which is almost always long before eleven seconds.
func test_driving_takes_the_card_down_without_waiting_for_the_dwell() -> void:
	_release_all()
	_card.raise()
	_card.age(0.5)
	check_true(_card.is_raised(), "half a second in, the card is up")

	Input.action_press(ControlCard.ACTION_THROTTLE)
	check_true(_card.player_has_acted(), "the throttle counts as having acted")
	_card.age(0.01)
	check_true(
		_card.is_raised(),
		"the card does not vanish on the frame the key goes down; it fades"
	)
	_card.age(ControlCard.FADE_S)
	check_false(
		_card.is_raised(),
		"and is gone one fade later, not %.1f seconds later" % ControlCard.DWELL_S
	)
	_release_all()


## Every action in §14.6's list, one at a time. A list that had lost an entry
## would pass a test that only pressed the throttle.
func test_every_acted_action_stands_the_card_down() -> void:
	_release_all()
	for action: StringName in ControlCard.ACTED_ACTIONS:
		_card.raise()
		_card.age(0.5)
		Input.action_press(action)
		_card.age(0.01)
		_card.age(ControlCard.FADE_S)
		check_false(_card.is_raised(), "%s takes the card down" % action)
		Input.action_release(action)


## The exclusions are a decision and not an oversight — §14.6 says why — so they
## are asserted, or the list could quietly grow to every action in the map.
func test_the_rows_a_player_cannot_guess_do_not_stand_it_down() -> void:
	_release_all()
	for action: StringName in [
		ControlCard.ACTION_CAMERA,
		ControlCard.ACTION_ZOOM_IN,
		ControlCard.ACTION_RELEASE_MOUSE,
	] as Array[StringName]:
		_card.raise()
		Input.action_press(action)
		_card.age(0.01)
		_card.age(ControlCard.FADE_S)
		check_true(
			_card.is_raised(),
			"%s is a row a player is least likely to find alone; pressing it is not "
				% action + "evidence they have read the rest"
		)
		Input.action_release(action)
	_card.dismiss()


## The toggle is the way back to it, and it must survive the stand-down: a player
## who pressed the throttle and then wants the card again presses
## [constant ControlCard.ACTION_TOGGLE_CARD] and gets a full dwell.
func test_the_toggle_restores_a_full_dwell_after_a_stand_down() -> void:
	_release_all()
	_card.raise()
	Input.action_press(ControlCard.ACTION_THROTTLE)
	_card.age(0.01)
	_card.age(ControlCard.FADE_S)
	check_false(_card.is_raised(), "the card stood down")
	Input.action_release(ControlCard.ACTION_THROTTLE)

	_card.toggle()
	check_true(_card.is_raised(), "and the toggle brings it back")
	for i: int in int(ControlCard.DWELL_S) - 1:
		_card.age(1.0)
	check_true(_card.is_raised(), "with the whole dwell on it again")
	_card.dismiss()
