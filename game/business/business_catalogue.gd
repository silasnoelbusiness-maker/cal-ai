class_name BusinessCatalogue
extends RefCounted
## The business types the player can found.
##
## Two entries. The list is the extension point, and the second one proved it:
## the coffee shop is a .tres with a menu, a set of recipes and a required
## workstation — no new manager, no new customer AI, no new books.

const TYPES: Array[BusinessTypeData] = [
	preload("res://items/business/convenience_store.tres"),
	preload("res://items/business/coffee_shop.tres"),
]


static func by_id(id: StringName) -> BusinessTypeData:
	for entry in TYPES:
		if entry.type_id == id:
			return entry
	return null


static func first() -> BusinessTypeData:
	return TYPES[0]
