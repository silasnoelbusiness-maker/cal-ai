class_name Portal
extends Interactable
## A doorway that moves the player between two places.
##
## Destinations are found by group rather than by NodePath, so an interior can
## live in a different scene from the door that leads to it without either side
## knowing where the other sits in the tree. The same component handles going
## in and coming back out — an interior's exit door is just another Portal
## pointing the other way.

signal travelled(destination: Node3D)

## The destination marker's group, e.g. &"apartment_interior_entry".
@export var destination_group: StringName = &""
## In-game minutes the trip costs (stairs, lifts, walking through a lobby).
@export var travel_minutes: int = 0

@export_group("Camera")
## Interiors need a tighter, steeper view than the street does.
@export var override_camera: bool = false
@export var camera_distance: float = 13.0
@export var camera_pitch: float = 74.0


func can_interact(interactor: Node3D) -> bool:
	if not super.can_interact(interactor):
		return false
	return _find_destination() != null


func _perform(interactor: Node3D) -> void:
	var destination := _find_destination()
	if destination == null:
		push_warning("Portal '%s' has no destination in group '%s'." % [name, destination_group])
		return

	if travel_minutes > 0:
		TimeManager.advance_minutes(travel_minutes)

	GameManager.teleport_player(destination.global_transform)
	_apply_camera_view()
	travelled.emit(destination)


func _find_destination() -> Node3D:
	if destination_group == &"":
		return null
	return get_tree().get_first_node_in_group(destination_group) as Node3D


## Interiors are small; the street is not. Portals carry the view they lead
## into, and reset it when they lead back outside.
func _apply_camera_view() -> void:
	var rig := get_tree().get_first_node_in_group(&"camera_rig") as TopDownCamera
	if rig == null:
		return
	if override_camera:
		rig.apply_view(camera_distance, camera_pitch)
	else:
		rig.reset_view()
