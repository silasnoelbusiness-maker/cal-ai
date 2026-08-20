class_name DealershipDesk
extends Interactable
## The sales desk.
##
## The whole showroom in one screen: the range, what the player already owns,
## the used listings and the paperwork. Selling is only possible here, which is
## why it exists as a place rather than as a key — a car has to be brought in.


func _ready() -> void:
	add_to_group(&"dealership_desk")


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"dealership", self, interactor)
