class_name WarehouseTerminal
extends Interactable
## The desk in the depot.
##
## Opens the logistics screen from inside the building, the same way the office
## terminal opens the company screen. Neither is a gate: §114 is explicit that
## remote management stays available, so this is a shortcut for a player who
## happens to be standing there rather than a trip they are made to take.

func _ready() -> void:
	add_to_group(&"warehouse_terminal")
	prompt_action = "Open Logistics"
	focus_priority = 2


func get_prompt_text() -> String:
	var warehouse := LogisticsManager.primary_warehouse()
	if warehouse != null:
		prompt_subtitle = "%s  ·  %d of %d units" % [
			warehouse.display_name, warehouse.used(), warehouse.capacity()
		]
	else:
		prompt_subtitle = "Nothing stored here yet"
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"logistics", self, interactor)
