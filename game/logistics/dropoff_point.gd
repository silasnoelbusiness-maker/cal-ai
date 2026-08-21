class_name DropoffPoint
extends Interactable

## The kerb outside wherever a shipment the player is driving has to end up.
##
## §110 and §111. It exists only while the player has a run of their own in
## progress, and there is never more than one per run, so it cannot clutter a
## street the player is not delivering to. Interacting with it hands the goods
## over — through the same LogisticsManager.complete_transfer() a company van
## would use, because the goods arriving must mean one thing regardless of who
## carried them.

const REACH := 4.0

var transfer_id: StringName = &""


func _ready() -> void:
	add_to_group(&"dropoff_point")
	prompt_action = "Unload Shipment"
	focus_priority = 4
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = REACH
	shape.shape = sphere
	add_child(shape)


func order() -> TransferOrder:
	return LogisticsManager.transfer_by_id(transfer_id)


func get_prompt_text() -> String:
	var run := order()
	if run != null:
		prompt_subtitle = "%s  ·  %s" % [
			run.cargo_text(),
			LogisticsManager.place_name(run.destination_kind, run.destination_id),
		]
	return super.get_prompt_text()


func can_interact(interactor: Node3D) -> bool:
	var run := order()
	return super.can_interact(interactor) and run != null and run.is_moving()


func _perform(_interactor: Node3D) -> void:
	var run := order()
	if run == null:
		return
	LogisticsManager.hand_over(run)
