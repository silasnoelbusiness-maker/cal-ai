class_name ItemCatalogue
extends RefCounted
## Every item that exists, looked up by id.
##
## Save files store item ids rather than resource paths, so a definition can be
## moved or renamed without breaking saves. Preloaded rather than scanned from
## disk, because directory listings under res:// are not dependable in an
## exported build.

const ITEMS: Array[ItemData] = [
	preload("res://items/definitions/basic_meal.tres"),
	preload("res://items/definitions/snack_bar.tres"),
	preload("res://items/definitions/energy_drink.tres"),
	preload("res://items/definitions/bottled_water.tres"),
	preload("res://items/definitions/soda_can.tres"),
	preload("res://items/definitions/steel_pipe.tres"),
]


static func by_id(id: StringName) -> ItemData:
	for item in ITEMS:
		if item.id == id:
			return item
	return null


static func all() -> Array[ItemData]:
	return ITEMS.duplicate()
