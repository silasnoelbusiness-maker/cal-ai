class_name VehicleCatalogue
extends RefCounted
## Every model of car that exists: what it is, what it costs, where it turns up
## in traffic and whether the dealership will sell you one.
##
## One list, so adding a model is an entry here rather than an edit to the
## traffic manager, to every street that parks cars, and to the showroom. The
## district weights are what make Harbour Row look like Harbour Row from the
## driver's seat: vans and saloons down there, small cars and the occasional
## expensive one in Central.
##
## The commercial side of a model — price, marque, prestige — lives on its
## VehicleData resource beside the physics rather than in a second table here.
## A car that is quick in the driver's seat is quick on the showroom board by
## construction, and there is no second roster to drift out of step.

const SCENES := {
	&"compact": preload("res://vehicles/cars/compact.tscn"),
	&"sedan": preload("res://vehicles/cars/sedan.tscn"),
	&"hatchback": preload("res://vehicles/cars/hatchback.tscn"),
	&"van": preload("res://vehicles/cars/van.tscn"),
	&"suv": preload("res://vehicles/cars/suv.tscn"),
	&"coupe": preload("res://vehicles/cars/coupe.tscn"),
	&"performance_sedan": preload("res://vehicles/cars/performance_sedan.tscn"),
	&"luxury_sedan": preload("res://vehicles/cars/luxury_sedan.tscn"),
	&"luxury_suv": preload("res://vehicles/cars/luxury_suv.tscn"),
	&"exotic": preload("res://vehicles/cars/exotic.tscn"),
}

## Spawn odds per district. Anything missing from a district's table simply does
## not appear there, which is what keeps the Solstice off Harbour Row and rare
## everywhere: one weight against Central's thirty is roughly one car in thirty.
const DISTRICT_WEIGHTS := {
	&"harbour_row": {
		&"sedan": 8, &"hatchback": 8, &"van": 6, &"compact": 5, &"suv": 2,
	},
	&"central": {
		&"compact": 6, &"hatchback": 5, &"suv": 5, &"sedan": 4, &"coupe": 2,
		&"luxury_sedan": 2, &"performance_sedan": 2, &"luxury_suv": 1, &"exotic": 1,
	},
}

## The same models again, as their definitions. A parallel literal rather than
## reflection over the scenes: the showroom asks a lot of questions about every
## model on the floor, and "load the scene and hunt for its data property" is
## both slower and easier to get quietly wrong than saying it outright.
const DATA := {
	&"compact": preload("res://vehicles/cars/compact_data.tres"),
	&"sedan": preload("res://vehicles/cars/sedan_data.tres"),
	&"hatchback": preload("res://vehicles/cars/hatchback_data.tres"),
	&"van": preload("res://vehicles/cars/van_data.tres"),
	&"suv": preload("res://vehicles/cars/suv_data.tres"),
	&"coupe": preload("res://vehicles/cars/coupe_data.tres"),
	&"performance_sedan": preload("res://vehicles/cars/performance_sedan_data.tres"),
	&"luxury_sedan": preload("res://vehicles/cars/luxury_sedan_data.tres"),
	&"luxury_suv": preload("res://vehicles/cars/luxury_suv_data.tres"),
	&"exotic": preload("res://vehicles/cars/exotic_data.tres"),
}


static func ids() -> Array:
	return SCENES.keys()


static func scene_for(id: StringName) -> PackedScene:
	return SCENES.get(id)


## The model's definition — stats, prices, marque. The same resource the spawned
## car carries, so there is exactly one description of a model in the project.
static func data_for(id: StringName) -> VehicleData:
	return DATA.get(id)


## What the dealership can sell, cheapest first — which is also the order a
## player meets them in as they earn.
static func purchasable_ids() -> Array[StringName]:
	var found: Array[StringName] = []
	for id: StringName in SCENES:
		var data := data_for(id)
		if data != null and data.purchasable:
			found.append(id)
	found.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return data_for(a).price_new < data_for(b).price_new
	)
	return found


static func is_purchasable(id: StringName) -> bool:
	var data := data_for(id)
	return data != null and data.purchasable


static func display_name(id: StringName) -> String:
	var data := data_for(id)
	return data.display_name if data != null else String(id).capitalize()


## "Kestrel · Saloon", the line under a model's name on the showroom board.
static func subtitle(id: StringName) -> String:
	var data := data_for(id)
	if data == null:
		return ""
	return "%s  ·  %s" % [data.manufacturer, data.vehicle_class]


static func price_new(id: StringName) -> int:
	var data := data_for(id)
	return data.price_new if data != null else 0


## What a clean used one is worth before this particular car's history is
## taken into account. See OwnedVehicle.market_value for the rest.
static func base_value(id: StringName) -> int:
	var data := data_for(id)
	return data.resale_value if data != null else 0


static func prestige(id: StringName) -> int:
	var data := data_for(id)
	return data.prestige if data != null else 0


## Every marque with something on the floor, in the order they first appear.
static func manufacturers() -> Array[String]:
	var found: Array[String] = []
	for id in purchasable_ids():
		var make := data_for(id).manufacturer
		if not found.has(make):
			found.append(make)
	return found


static func weights_for(district_id: StringName) -> Dictionary:
	return DISTRICT_WEIGHTS.get(district_id, DISTRICT_WEIGHTS[&"harbour_row"])


## Picks a model for a district, by weight.
static func pick_for_district(district_id: StringName, rng: RandomNumberGenerator) -> PackedScene:
	return scene_for(pick_id_for_district(district_id, rng))


static func pick_id_for_district(district_id: StringName, rng: RandomNumberGenerator) -> StringName:
	var weights := weights_for(district_id)
	var total := 0
	for weight in weights.values():
		total += int(weight)
	if total <= 0:
		return &"sedan"
	var roll := rng.randi_range(1, total)
	for id in weights:
		roll -= int(weights[id])
		if roll <= 0:
			return id
	return &"sedan"
