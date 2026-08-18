class_name PlacedEquipment
extends RefCounted
## One piece of equipment standing on a business's floor.
##
## The record is the truth, not the node. The interior builds a BusinessEquipment
## node for each of these when the player is inside and throws them away when
## they leave, so a shop keeps its shelves and their stock whether or not anybody
## is looking at it — which is also what makes far simulation and save/load
## nothing more than reading this list.

var slot_id: int = 0
var equipment_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
## Shelves only: which product is on it and how many.
var stock_item: StringName = &""
var stock_quantity: int = 0


func data() -> EquipmentData:
	return EquipmentCatalogue.by_id(equipment_id)


func capacity() -> int:
	var definition := data()
	return definition.capacity if definition != null else 0


func room_left() -> int:
	return maxi(capacity() - stock_quantity, 0)


func is_shelf() -> bool:
	var definition := data()
	return definition != null and definition.is_shelf()


func is_checkout() -> bool:
	var definition := data()
	return definition != null and definition.is_checkout()


func is_storage() -> bool:
	var definition := data()
	return definition != null and definition.is_storage()


func item() -> ItemData:
	return ItemCatalogue.by_id(stock_item) if stock_item != &"" else null


func to_dict() -> Dictionary:
	return {
		"slot": slot_id,
		"equipment": String(equipment_id),
		"position": [position.x, position.y, position.z],
		"rotation": rotation_y,
		"stock_item": String(stock_item),
		"stock_quantity": stock_quantity,
	}


static func from_dict(state: Dictionary) -> PlacedEquipment:
	var placed := PlacedEquipment.new()
	placed.slot_id = int(state.get("slot", 0))
	placed.equipment_id = StringName(state.get("equipment", ""))
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		placed.position = Vector3(raw[0], raw[1], raw[2])
	placed.rotation_y = float(state.get("rotation", 0.0))
	placed.stock_item = StringName(state.get("stock_item", ""))
	placed.stock_quantity = int(state.get("stock_quantity", 0))
	return placed
