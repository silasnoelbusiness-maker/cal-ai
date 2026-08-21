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
	preload("res://items/equipment/coffee_machine.tres"),
	preload("res://items/equipment/service_counter.tres"),
	preload("res://items/equipment/ingredient_store.tres"),
	preload("res://items/equipment/cafe_table.tres"),
	# Restaurant.
	preload("res://items/equipment/dining_table.tres"),
	preload("res://items/equipment/dining_chair.tres"),
	preload("res://items/equipment/prep_counter.tres"),
	preload("res://items/equipment/cook_station.tres"),
	preload("res://items/equipment/kitchen_fridge.tres"),
	preload("res://items/equipment/dry_store.tres"),
	preload("res://items/equipment/service_pass.tres"),
	preload("res://items/equipment/dishwasher.tres"),
	preload("res://items/equipment/trash_station.tres"),
	# Gym.
	preload("res://items/equipment/treadmill.tres"),
	preload("res://items/equipment/exercise_bike.tres"),
	preload("res://items/equipment/weight_bench.tres"),
	preload("res://items/equipment/weight_rack.tres"),
	preload("res://items/equipment/cable_machine.tres"),
	preload("res://items/equipment/reception_desk.tres"),
	preload("res://items/equipment/locker_bank.tres"),
	preload("res://items/equipment/cleaning_station.tres"),
	# Nightclub.
	preload("res://items/equipment/bar_counter.tres"),
	preload("res://items/equipment/club_table.tres"),
	preload("res://items/equipment/lounge_seat.tres"),
	preload("res://items/equipment/dance_floor.tres"),
	preload("res://items/equipment/dj_booth.tres"),
	preload("res://items/equipment/speaker_stack.tres"),
	preload("res://items/equipment/lighting_rig.tres"),
	preload("res://items/equipment/security_post.tres"),
	preload("res://items/equipment/venue_store.tres"),
]


static func by_id(id: StringName) -> EquipmentData:
	for entry in ITEMS:
		if entry.equipment_id == id:
			return entry
	return null


## Everything of one role that exists, whoever may buy it.
static func of_role(role: int) -> Array[EquipmentData]:
	var found: Array[EquipmentData] = []
	for entry in ITEMS:
		if entry.role == role:
			found.append(entry)
	return found


## Everything a given business type is allowed to buy.
static func for_business(business_type: StringName) -> Array[EquipmentData]:
	var found: Array[EquipmentData] = []
	for entry in ITEMS:
		if entry.allows(business_type):
			found.append(entry)
	return found
