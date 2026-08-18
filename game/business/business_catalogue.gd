class_name BusinessCatalogue
extends RefCounted
## The business types the player can found.
##
## One entry today. The list is the extension point: a coffee shop is a new
## .tres here and a stock list, not a new system.

const TYPES: Array[BusinessTypeData] = [
	preload("res://items/business/convenience_store.tres"),
]


static func by_id(id: StringName) -> BusinessTypeData:
	for entry in TYPES:
		if entry.type_id == id:
			return entry
	return null


static func first() -> BusinessTypeData:
	return TYPES[0]
