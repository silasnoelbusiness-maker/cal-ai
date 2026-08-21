class_name WarehouseData
extends RefCounted
## The warehouses that exist in the city, as data.
##
## One, in Harbour Row, because §3 asks for one and an industrial district is
## explicitly not this phase. The list is the extension point exactly as the
## business catalogue is: a second warehouse is another entry here plus a door.

## [id, property id, name, base capacity, racks it can hold]
const WAREHOUSES: Array = [
	[&"dockside_depot", &"warehouse_dock_14", "Dockside Depot", 400, 12],
]


static func all() -> Array:
	return WAREHOUSES


static func by_id(warehouse_id: StringName) -> Array:
	for entry in WAREHOUSES:
		if StringName(entry[0]) == warehouse_id:
			return entry
	return []


static func for_property(property_id: StringName) -> StringName:
	for entry in WAREHOUSES:
		if StringName(entry[1]) == property_id:
			return StringName(entry[0])
	return &""


static func display_name(warehouse_id: StringName) -> String:
	var entry := by_id(warehouse_id)
	return String(entry[2]) if entry.size() > 2 else "Warehouse"


static func base_capacity(warehouse_id: StringName) -> int:
	var entry := by_id(warehouse_id)
	return int(entry[3]) if entry.size() > 3 else 400


static func rack_limit(warehouse_id: StringName) -> int:
	var entry := by_id(warehouse_id)
	return int(entry[4]) if entry.size() > 4 else 12
