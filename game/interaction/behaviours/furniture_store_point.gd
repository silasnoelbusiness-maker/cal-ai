class_name FurnitureStorePoint
extends Interactable
## The counter at the furniture shop.
##
## Opens the catalogue. Everything bought here is delivered to the home the
## player is currently living in, so there is nothing to carry and nothing to
## choose about where it goes until it arrives.


func _ready() -> void:
	add_to_group(&"furniture_store_point")


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"furniture_store", self, interactor)
