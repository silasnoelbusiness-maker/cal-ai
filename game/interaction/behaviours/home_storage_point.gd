class_name HomeStoragePoint
extends Interactable
## The cupboard in a flat.
##
## Somewhere to put things that is neither your pockets nor a shop's stock room.
## Only the home you actually live in opens: a flat you are merely renting out
## of habit is not where your things are.

@export var residence_id: StringName = &"larkspur"


func _ready() -> void:
	add_to_group(&"home_storage")


func can_interact(_interactor: Node3D) -> bool:
	return available and _is_leased()


func get_prompt_text() -> String:
	if not _is_leased():
		return "NOT YOUR FLAT\nRent this place to use its storage"
	return super.get_prompt_text()


func _is_leased() -> bool:
	var home := PropertyManager.residence_by_id(residence_id)
	return home != null and home.is_leased_by_player()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"home_storage", self, interactor)
