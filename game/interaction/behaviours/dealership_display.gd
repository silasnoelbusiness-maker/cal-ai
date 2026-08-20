class_name DealershipDisplay
extends Interactable
## The stand beside a car on the showroom floor.
##
## Opens the details for that one model. Everything the panel then does — the
## comparison, the confirmation, the money — belongs to the panel; this is the
## sign with the price on it.

@export var model_id: StringName = &"sedan"


func _ready() -> void:
	add_to_group(&"dealership_display")


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"dealership_vehicle", self, interactor)
