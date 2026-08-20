class_name FurnishingPoint
extends Interactable
## Where furnishing a flat starts.
##
## The screen it opens lists what the player owns and is not currently using,
## and hands off to the placement mode. Deliberately a spot in the room rather
## than a key anywhere in the world: furnishing is something you do at home.

@export var residence_id: StringName = &"larkspur"


func _ready() -> void:
	add_to_group(&"furnishing_point")


func can_interact(_interactor: Node3D) -> bool:
	return available and _is_leased()


func get_prompt_text() -> String:
	if not _is_leased():
		return "NOT YOUR FLAT\nRent this place to furnish it"
	return super.get_prompt_text()


func _is_leased() -> bool:
	var home := PropertyManager.residence_by_id(residence_id)
	return home != null and home.is_leased_by_player()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"furnishing", self, interactor)
