class_name BusinessCatalogue
extends RefCounted
## The business types the player can found.
##
## The list is the extension point, and Phase O leaned on it hard. A restaurant,
## a gym and a nightclub are three more .tres files: a service model, an
## equipment list, a demand curve and a set of roles. No new manager, no new
## books, and the same customer code serving all five.

const TYPES: Array[BusinessTypeData] = [
	preload("res://items/business/convenience_store.tres"),
	preload("res://items/business/coffee_shop.tres"),
	preload("res://items/business/restaurant.tres"),
	preload("res://items/business/gym.tres"),
	preload("res://items/business/nightclub.tres"),
]


static func by_id(id: StringName) -> BusinessTypeData:
	for entry in TYPES:
		if entry.type_id == id:
			return entry
	return null


static func first() -> BusinessTypeData:
	return TYPES[0]


## Types the player may found in a property zoned for a given class.
static func for_property_class(property_class: StringName) -> Array[BusinessTypeData]:
	var found: Array[BusinessTypeData] = []
	for entry in TYPES:
		if entry.property_class == property_class:
			found.append(entry)
	return found
