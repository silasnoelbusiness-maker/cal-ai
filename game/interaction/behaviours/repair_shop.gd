class_name RepairShop
extends Interactable
## The mechanic.
##
## Works on whichever of the player's cars is standing in the service bay. That
## is the whole rule, and it is why the shop is a place rather than a menu: a
## car has to be driven here to be fixed, which is what makes damage cost
## something more than money.

@export var shop_name: String = "Dockside Motors"
## Where a car has to be for this shop to work on it, in world space.
@export var service_point: Vector3 = Vector3.ZERO
## How far from that point still counts as "in the bay". Forgiving on purpose —
## nobody should have to park to the centimetre.
@export var bay_radius: float = 6.5


func _ready() -> void:
	add_to_group(&"repair_shop")


## The player's car currently in the bay, or null. The nearest one wins if two
## are somehow squeezed in.
func vehicle_in_bay() -> OwnedVehicle:
	var best: OwnedVehicle = null
	var best_distance := bay_radius
	for record in VehicleRegistry.get_fleet():
		if not record.is_spawned():
			continue
		var distance := record.node.global_position.distance_to(service_point)
		if distance <= best_distance:
			best = record
			best_distance = distance
	return best


func get_prompt_text() -> String:
	if vehicle_in_bay() == null:
		return "%s\nBring a vehicle you own into the bay" % shop_name.to_upper()
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"repair", self, interactor)
