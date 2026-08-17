class_name VehicleDoor
extends Interactable
## The "F — Enter Vehicle" prompt attached to a Vehicle.
##
## A thin adapter, so the vehicle needs no knowledge of the interaction system
## and the interaction system needs none of vehicles. It uses the existing
## Interactable contract with a different input action, which is exactly the
## hook `input_action` was added for — E stays reserved for everything on foot.

var _vehicle: Vehicle = null


func _init() -> void:
	super()
	input_action = "enter_vehicle"
	key_hint = "F"
	prompt_action = "Enter Vehicle"


func setup(vehicle: Vehicle) -> void:
	_vehicle = vehicle
	_refresh_prompt()
	vehicle.driver_exited.connect(_on_driver_exited)


func can_interact(interactor: Node3D) -> bool:
	if not super.can_interact(interactor):
		return false
	if _vehicle == null:
		return false
	return _vehicle.can_be_entered_by(interactor) or _vehicle.can_be_carjacked_by(interactor)


func _perform(interactor: Node3D) -> void:
	if _vehicle == null:
		return
	# One key, two acts. Which one it is depends on whether anybody is sat in it,
	# and the prompt says so before the player commits.
	if _vehicle.can_be_carjacked_by(interactor):
		_vehicle.carjack(interactor)
		_refresh_prompt()
		return
	_vehicle.enter(interactor)


## Built fresh each frame the prompt is shown, because whether a car can be
## taken off its driver depends on how fast it is going right now.
func get_prompt_text() -> String:
	if not available:
		return unavailable_prompt
	if _vehicle != null and _vehicle.has_occupant():
		if _vehicle.can_be_carjacked_by(GameManager.player):
			return "%s — Carjack" % key_hint
		return "%s — Occupied" % key_hint
	return super.get_prompt_text()


func _on_driver_exited(_driver: Node3D) -> void:
	_refresh_prompt()


## Names the car, and says plainly when it is not the player's — the player
## should know they are about to steal something before they press F.
func _refresh_prompt() -> void:
	if _vehicle == null:
		return
	var label := _vehicle.get_display_name()
	if _vehicle.owner_type == Vehicle.OwnerType.PLAYER:
		label += " · yours"
	elif _vehicle.owner_type == Vehicle.OwnerType.NPC:
		label += " · not yours"
	prompt_subtitle = label
	unavailable_prompt = "WRECKED" if _vehicle.is_disabled() else ""
