class_name OwnedVehicle
extends RefCounted
## One car the player owns, as a record rather than as a node.
##
## The record is the truth and the car in the street is a view of it. That is
## the same arrangement businesses and their equipment already use, and it is
## what makes a garage possible at all: a stored car has no node anywhere, and
## a car parked across the city has no node either until the player walks back
## to it, but both are still demonstrably the same individual car with the same
## mileage on it.
##
## Two sedans are two records. Nothing here is keyed on the model — the model is
## a field, and the identity is `instance_id`.

## Where the car is when nobody is looking at it.
##   STREET  — parked somewhere in the city, at `position`.
##   GARAGE  — in a bay at `garage_id`, with no node in the world.
enum Location { STREET, GARAGE }

var instance_id: StringName = &""
var model_id: StringName = &"sedan"
var owner_id: StringName = &"player"

## What was paid for it, kept for the record and for the profile screen. Never
## used as a valuation — see market_value().
var purchase_price: int = 0
## The in-game day it was bought, for the small age component of depreciation.
var purchase_day: int = 0
## Distance driven, in kilometres. Only ever goes up, and only while moving.
var mileage_km: float = 0.0
## 0-100. The long-term state of the car: paint, panels, mechanical order. Falls
## slowly with use and sharply with a bad crash, and only a bill puts it back.
var condition: float = 100.0
## Current mechanical damage, in the same units as Vehicle.health. Separate from
## condition on purpose: health is what a crash does this minute, condition is
## what the car has been through.
var health: float = 100.0

var location: Location = Location.STREET
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var district_id: StringName = &"harbour_row"
## Which garage holds it, when it is in one.
var garage_id: StringName = &""
var paint_color: Color = Color(0.243, 0.376, 0.494)

## Set for a car bought second hand, so the showroom and the profile can say so.
var bought_used: bool = false
## Kept deliberately: the registry only ever holds legally owned vehicles, so
## this is always false today. It exists because "is this car actually yours"
## is a question an impound or a police seizure will need to ask, and the answer
## should not have to be invented then.
var stolen: bool = false

## The node in the world, when there is one. Never saved.
var node: Vehicle = null


func data() -> VehicleData:
	return VehicleCatalogue.data_for(model_id)


func display_name() -> String:
	return VehicleCatalogue.display_name(model_id)


func max_health() -> float:
	var definition := data()
	return definition.max_health if definition != null else 100.0


func is_stored() -> bool:
	return location == Location.GARAGE


func is_spawned() -> bool:
	return node != null and is_instance_valid(node)


# --- Value ---------------------------------------------------------------

## What the car is worth, from the model's base price and this car's own
## history. Deliberately a short formula the player could work out: a clean car
## with no miles on it is worth what the model is worth, and everything below
## that is condition and use.
##
##   value = base × condition × mileage × age
func market_value() -> int:
	var base := VehicleCatalogue.base_value(model_id)
	return maxi(roundi(float(base) * condition_modifier() * mileage_modifier() * age_modifier()), 0)


## A perfect car keeps all of its value; a wreck keeps not quite half. Nothing
## is ever worth nothing, because a scrap car is still worth its metal.
func condition_modifier() -> float:
	return lerpf(0.45, 1.0, clampf(condition / 100.0, 0.0, 1.0))


## Straight-line down to 60% at 200,000km, and no further. Real depreciation is
## a curve; this is a line because the player has to be able to see it coming.
func mileage_modifier() -> float:
	return clampf(1.0 - mileage_km / 200000.0 * 0.4, 0.6, 1.0)


## A small, slow drift for time alone, floored at 85%. It exists so a car left
## untouched in a garage for a season is worth slightly less than the day it
## went in — not enough to punish keeping one.
func age_modifier() -> float:
	var days := maxi(TimeManager.day_index - purchase_day, 0)
	return clampf(1.0 - float(days) * 0.002, 0.85, 1.0)


## What a dealer will actually hand over. They have to sell it again, so there
## is a margin in it — which is also what stops buy-and-sell being free money.
func dealer_offer() -> int:
	return maxi(roundi(float(market_value()) * 0.85), 0)


# --- Condition -----------------------------------------------------------

func health_fraction() -> float:
	return clampf(health / maxf(max_health(), 1.0), 0.0, 1.0)


## How the car reads on a listing or in the vehicle list.
func condition_label() -> String:
	if condition >= 92.0:
		return "Immaculate"
	if condition >= 75.0:
		return "Good"
	if condition >= 55.0:
		return "Worn"
	if condition >= 35.0:
		return "Rough"
	return "Poor"


## Mileage as the dashboard says it.
func mileage_label() -> String:
	return "%s km" % EconomyManager.with_thousands_separator(roundi(mileage_km))


# --- Save ----------------------------------------------------------------

func to_dictionary() -> Dictionary:
	return {
		"instance_id": String(instance_id),
		"model_id": String(model_id),
		"owner_id": String(owner_id),
		"purchase_price": purchase_price,
		"purchase_day": purchase_day,
		"mileage_km": mileage_km,
		"condition": condition,
		"health": health,
		"location": int(location),
		"position": [position.x, position.y, position.z],
		"yaw": yaw,
		"district_id": String(district_id),
		"garage_id": String(garage_id),
		"paint_color": [paint_color.r, paint_color.g, paint_color.b],
		"bought_used": bought_used,
		"stolen": stolen,
	}


## Rebuilt from a save. Every field has a default that makes sense for a car
## saved before that field existed, which is what lets a Phase L save carry its
## cars forward instead of losing them.
static func from_dictionary(state: Dictionary) -> OwnedVehicle:
	var record := OwnedVehicle.new()
	record.instance_id = StringName(state.get("instance_id", ""))
	record.model_id = StringName(state.get("model_id", "sedan"))
	record.owner_id = StringName(state.get("owner_id", "player"))
	record.purchase_price = int(state.get("purchase_price", 0))
	record.purchase_day = int(state.get("purchase_day", 0))
	record.mileage_km = float(state.get("mileage_km", 0.0))
	record.condition = clampf(float(state.get("condition", 100.0)), 0.0, 100.0)
	record.health = float(state.get("health", record.max_health()))
	record.location = int(state.get("location", int(Location.STREET))) as Location
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		record.position = Vector3(raw[0], raw[1], raw[2])
	record.yaw = float(state.get("yaw", 0.0))
	record.district_id = StringName(state.get("district_id", "harbour_row"))
	record.garage_id = StringName(state.get("garage_id", ""))
	var paint: Array = state.get("paint_color", [])
	if paint.size() == 3:
		record.paint_color = Color(paint[0], paint[1], paint[2])
	record.bought_used = bool(state.get("bought_used", false))
	record.stolen = bool(state.get("stolen", false))
	return record
