class_name MultiUnitBuilding
extends Interactable
## A small block of flats: one building, four tenancies.
##
## The point of it is arithmetic the single properties cannot teach. One flat is
## let or it is not; four flats are three-quarters let, and the difference
## between a good month and a bad one is one tenant leaving. It costs more than
## a flat, earns more than a flat, and can sit half empty while the mortgage
## carries on.
##
## Deliberately four units and not forty. There is no interior, no tenant
## walking about and no lift: the units exist as entries in the owner's record,
## which is what keeps a portfolio free.

@export var building_id: StringName = &"dockside_block"
@export var address: String = "Dockside Court"
@export var district_id: StringName = &"harbour_row"
@export var unit_count: int = 4
@export var floor_area: int = 168
@export var location_quality: int = 48
@export var condition: float = 78.0
@export var owned_by_player: bool = false
@export var save_id: StringName = &"building_dockside"

## The lit windows on the front, so a let building looks lived in from the
## street. Rebuilt whenever occupancy changes.
var _windows: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"multi_unit_building")
	add_to_group(&"saveable")
	# The record is the truth and the building is a view of it, so the windows
	# follow the portfolio rather than being lit by whatever changed them. A
	# tenancy signed or ended is not an ownership change, and lighting the
	# windows only when the deeds moved meant they never lit at all.
	RealEstate.portfolio_changed.connect(refresh_state)
	refresh_state()


func record() -> PropertyRecord:
	return RealEstate.record_for(building_id)


func occupied_units() -> int:
	var held := record()
	return held.occupied_units() if held != null else 0


func refresh_state() -> void:
	_refresh_prompt()
	_refresh_windows()


func register_window(mesh: MeshInstance3D) -> void:
	_windows.append(mesh)


## One lit window per let flat, in order. A crude signal and a legible one: an
## empty block is dark, a full one is not.
func _refresh_windows() -> void:
	var lit := occupied_units()
	for i in _windows.size():
		var mesh := _windows[i]
		if not is_instance_valid(mesh):
			continue
		mesh.visible = i < lit


func _refresh_prompt() -> void:
	prompt_action = "View Building" if not owned_by_player else "Manage Building"
	var detail := address
	if owned_by_player:
		var held := record()
		detail += "  ·  %d of %d let" % [
			occupied_units(), held.unit_count() if held != null else unit_count
		]
	elif RealEstate.is_for_sale(building_id):
		detail += "  ·  FOR SALE"
	prompt_subtitle = detail


func get_prompt_text() -> String:
	_refresh_prompt()
	return super.get_prompt_text()


func _perform(interactor: Node3D) -> void:
	if owned_by_player:
		GameManager.request_screen(&"real_estate", self, interactor)
		return
	RealEstate.discover(building_id)
	GameManager.request_screen(&"property_sale", self, interactor)


func save_state() -> Dictionary:
	return {"condition": condition}


func load_state(state: Dictionary) -> void:
	condition = float(state.get("condition", condition))
	refresh_state()
