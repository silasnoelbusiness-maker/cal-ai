class_name VehicleCatalogue
extends RefCounted
## Every civilian car that exists, and which districts they turn up in.
##
## One list, so adding a model is an entry here rather than an edit to the
## traffic manager and to every street that parks cars. The district weights are
## what make Harbour Row look like Harbour Row from the driver's seat: vans and
## saloons down there, small cars and the occasional expensive one in Central.

const SCENES := {
	&"compact": preload("res://vehicles/cars/compact.tscn"),
	&"sedan": preload("res://vehicles/cars/sedan.tscn"),
	&"hatchback": preload("res://vehicles/cars/hatchback.tscn"),
	&"van": preload("res://vehicles/cars/van.tscn"),
	&"suv": preload("res://vehicles/cars/suv.tscn"),
	&"coupe": preload("res://vehicles/cars/coupe.tscn"),
}

## Spawn odds per district. Anything missing from a district's table simply does
## not appear there.
const DISTRICT_WEIGHTS := {
	&"harbour_row": {&"sedan": 4, &"hatchback": 4, &"van": 3, &"compact": 2, &"suv": 1},
	&"central": {&"compact": 4, &"hatchback": 3, &"suv": 3, &"sedan": 2, &"coupe": 1},
}


static func ids() -> Array:
	return SCENES.keys()


static func scene_for(id: StringName) -> PackedScene:
	return SCENES.get(id)


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
