extends TestCase
## The attachment mating matrix of [code]docs/GRID_SNAPPING_LOGIC.md[/code] §7.3.
##
## This table decides what may be bolted to what, so an error in it is a
## gameplay rule change disguised as a data typo. It is asserted cell by cell
## against the document rather than against a paraphrase, because a summary of
## the matrix is exactly how the DECK row came to be wrong in the first place.


## Row-major, straight out of the document's `_POLARITY_MATRIX`. Duplicated here
## on purpose: a test that imports the table it is testing asserts only that the
## table equals itself.
const EXPECTED: Array[bool] = [
	false, true, true, false, true,  # FACE_MALE
	true, false, true, false, false,  # FACE_FEMALE
	true, true, true, false, true,  # FACE_NEUTRAL
	false, false, false, true, false,  # AXLE
	true, false, true, false, false,  # DECK
]

const NAMES: Array[String] = ["FACE_MALE", "FACE_FEMALE", "FACE_NEUTRAL", "AXLE", "DECK"]


func test_matrix_matches_the_document_cell_by_cell() -> void:
	var count := PartEnums.ATTACHMENT_POLARITY_COUNT
	for a in count:
		for b in count:
			var want: bool = EXPECTED[a * count + b]
			check_eq(
				AttachmentNodeDef.polarity_compatible(a, b),
				want,
				"%s must%s accept %s" % [NAMES[a], "" if want else " not", NAMES[b]]
			)


## §7.3: "The matrix is symmetric by construction." An asymmetric entry would
## make mating depend on which part was placed first, which breaks blueprint
## reconstruction — the same two parts would mate on load and not on rebuild.
func test_matrix_is_symmetric() -> void:
	var count := PartEnums.ATTACHMENT_POLARITY_COUNT
	for a in count:
		for b in count:
			check_eq(
				AttachmentNodeDef.polarity_compatible(a, b),
				AttachmentNodeDef.polarity_compatible(b, a),
				"%s/%s must mate the same way in both directions" % [NAMES[a], NAMES[b]]
			)


func test_axle_is_exclusive_to_axle() -> void:
	var axle := PartEnums.AttachmentPolarity.AXLE
	check_true(AttachmentNodeDef.polarity_compatible(axle, axle), "axle mates with axle")
	for other in PartEnums.ATTACHMENT_POLARITY_COUNT:
		if other == axle:
			continue
		check_false(
			AttachmentNodeDef.polarity_compatible(axle, other),
			"axle must not mate with %s" % NAMES[other]
		)


## A deck is a surface to stand something on, not a thing to stand on a surface.
func test_deck_does_not_mate_with_another_deck() -> void:
	var deck := PartEnums.AttachmentPolarity.DECK
	check_false(AttachmentNodeDef.polarity_compatible(deck, deck), "deck to deck is not a joint")
	check_true(
		AttachmentNodeDef.polarity_compatible(deck, PartEnums.AttachmentPolarity.FACE_MALE),
		"a protruding face seats on a deck"
	)
	check_true(
		AttachmentNodeDef.polarity_compatible(deck, PartEnums.AttachmentPolarity.FACE_NEUTRAL),
		"a neutral face seats on a deck"
	)
	check_false(
		AttachmentNodeDef.polarity_compatible(deck, PartEnums.AttachmentPolarity.FACE_FEMALE),
		"a recess has nothing to seat against on a deck"
	)


func test_instance_accessor_agrees_with_the_static_matrix() -> void:
	var node := AttachmentNodeDef.new()
	for a in PartEnums.ATTACHMENT_POLARITY_COUNT:
		node.polarity = a
		for b in PartEnums.ATTACHMENT_POLARITY_COUNT:
			check_eq(
				node.accepts_polarity(b),
				AttachmentNodeDef.polarity_compatible(a, b),
				"accepts_polarity must not diverge from the matrix at %s/%s" % [NAMES[a], NAMES[b]]
			)


func test_out_of_range_polarity_is_rejected_rather_than_indexing_the_matrix() -> void:
	# A corrupt .tres can hold any integer in an enum-typed field. Reading past
	# the matrix would abort the placement chain rather than reject the node.
	check_false(AttachmentNodeDef.polarity_compatible(-1, 0), "negative polarity rejected")
	check_false(
		AttachmentNodeDef.polarity_compatible(PartEnums.ATTACHMENT_POLARITY_COUNT, 0),
		"polarity past the last member rejected"
	)
	check_false(
		AttachmentNodeDef.polarity_compatible(0, PartEnums.ATTACHMENT_POLARITY_COUNT),
		"out-of-range other rejected"
	)
