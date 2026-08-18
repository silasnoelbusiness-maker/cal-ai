class_name EquipmentCatalogue
extends RefCounted
## Every piece of business equipment that exists, looked up by id.
##
## Same shape and the same reasoning as ItemCatalogue: saves store ids, and
## preloading beats scanning res:// because directory listings are not
## dependable in an exported build.

const ITEMS: Array[EquipmentData] = [
	preload("res://items/equipment/checkout_counter.tres"),
	preload("res://items/equipment/retail_shelf.tres"),
	preload("res://items/equipment/storage_rack.tres"),
]


static func by_id(id: StringName) -> EquipmentData:
	for entry in ITEMS:
		if entry.equipment_id == id:
			return entry
	return null


## Everything a given business type is allowed to buy.
static func for_business(business_type: StringName) -> Array[EquipmentData]:
	var found: Array[EquipmentData] = []
	for entry in ITEMS:
		if entry.allows(business_type):
			found.append(entry)
	return found
