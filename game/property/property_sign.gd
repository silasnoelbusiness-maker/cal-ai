class_name PropertySign
extends Interactable
## The board outside a property that is on the market.
##
## Deliberately its own interaction rather than a branch inside the door. The
## door already means something — walk in, or read the letting terms — and the
## unit the player's own shop trades from is a door they use every day. A board
## on the pavement is where you go to ask about buying the building, and it can
## sit outside a shop that is open and busy without getting in the way.
##
## Built by RealEstate from the listings, so a property coming on or off the
## market puts up or takes down its own sign.

@export var property_id: StringName = &""
## FOR SALE while listed; the board is removed when it is not.
@export var headline: String = "FOR SALE"

## The board this interaction belongs to. Held directly rather than walked to
## through get_parent(), because "two levels up" is a guess about a tree that
## could change and freeing the wrong node here would take a district with it.
var board: Node3D = null


func _ready() -> void:
	add_to_group(&"property_sign")
	# Deliberately no focus bonus. A board stands next to a door the player uses
	# every day — their own front door, their own shop — and a bonus of even one
	# metre is enough for the board to answer when they press E at the door.
	focus_priority = 0
	_refresh_prompt()


func listing() -> PropertyListing:
	return RealEstate.listing_for(property_id)


func _refresh_prompt() -> void:
	var offer := listing()
	prompt_action = "View Property"
	if offer == null:
		prompt_subtitle = headline
		return
	prompt_subtitle = "%s  ·  %s  ·  $%s" % [
		offer.address, headline,
		EconomyManager.with_thousands_separator(offer.asking_price)
	]


func get_prompt_text() -> String:
	_refresh_prompt()
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	# Standing in front of it is what puts it on the market screen. The city is
	# meant to be driven around before it is browsed.
	RealEstate.discover(property_id)
	GameManager.request_screen(&"property_sale", self, interactor)


## Draws the board itself: two posts, a panel and a lit headline, in the same
## primitives everything else in the city is made of.
static func build(parent: Node3D, property_id: StringName, at: Vector3, yaw: float) -> PropertySign:
	var holder := Node3D.new()
	holder.name = "ForSaleSign_%s" % property_id
	holder.position = at
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)

	var post := CityKit.make_material(Color(0.278, 0.259, 0.235))
	var board := CityKit.make_material(Color(0.925, 0.918, 0.890))
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Post%d" % int(side), Vector3(side * 0.42, 0.62, 0.0),
			Vector3(0.07, 1.24, 0.07), post, false
		)
	CityKit.add_box(
		holder, "Board", Vector3(0.0, 1.35, 0.0), Vector3(1.05, 0.72, 0.05), board, false
	)
	CityKit.add_box(
		holder, "Headline", Vector3(0.0, 1.52, -0.035), Vector3(0.86, 0.20, 0.02),
		CityKit.make_emissive_material(Color(0.788, 0.243, 0.220), 0.55), false, false
	)
	CityKit.add_box(
		holder, "Line", Vector3(0.0, 1.22, -0.035), Vector3(0.72, 0.09, 0.02),
		CityKit.make_material(Color(0.396, 0.412, 0.443)), false, false
	)

	var sign := PropertySign.new()
	sign.name = "SignPoint"
	sign.property_id = property_id
	sign.board = holder
	CityKit.attach_interactable(holder, sign, Vector3(0.0, 0.9, 0.9), 1.8)
	return sign


## Takes the board down.
##
## Leaves the group before freeing anything. queue_free is deferred, so a board
## that is on its way out is still in the group for the rest of the frame, and
## anything rebuilding the signage in that frame would see a sign that no longer
## exists and skip putting a new one up.
func remove() -> void:
	remove_from_group(&"property_sign")
	if board != null and is_instance_valid(board):
		board.queue_free()
	else:
		queue_free()
