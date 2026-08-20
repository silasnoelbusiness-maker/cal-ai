class_name UsedListing
extends RefCounted
## One second-hand car on the forecourt.
##
## Generated rather than authored: a model, a plausible history and a price that
## follows from both. That is what makes the cheap end of the range worth
## looking at early — a used compact is the first car most players can afford,
## and it comes with somebody else's mileage on it.
##
## Deliberately not a market simulation. The listings refresh every few days and
## that is the whole of it; tracking prices over time would be a different game.

var listing_id: StringName = &""
var model_id: StringName = &"compact"
var mileage_km: float = 0.0
var condition: float = 80.0
var price: int = 0


func data() -> VehicleData:
	return VehicleCatalogue.data_for(model_id)


func display_name() -> String:
	return VehicleCatalogue.display_name(model_id)


func condition_label() -> String:
	if condition >= 92.0:
		return "Immaculate"
	if condition >= 75.0:
		return "Good"
	if condition >= 55.0:
		return "Worn"
	return "Rough"


func mileage_label() -> String:
	return "%s km" % EconomyManager.with_thousands_separator(roundi(mileage_km))


## Builds one listing for a model. The history comes first and the price follows
## from it, so a listing can never be cheap for no reason — and the floor on
## both mileage and condition is what stops the generator producing a car with
## negative miles or a condition of zero.
static func generate(model_id: StringName, rng: RandomNumberGenerator, index: int) -> UsedListing:
	var definition := VehicleCatalogue.data_for(model_id)
	if definition == null:
		return null
	var listing := UsedListing.new()
	listing.listing_id = StringName("used_%s_%d" % [model_id, index])
	listing.model_id = model_id
	listing.mileage_km = float(rng.randi_range(8, 145)) * 1000.0
	listing.condition = clampf(rng.randf_range(52.0, 94.0), 1.0, 100.0)

	# The same valuation the player's own cars use, so a used car bought today
	# and valued tomorrow does not jump. The forecourt then adds its margin.
	var base := float(definition.resale_value)
	var by_condition := lerpf(0.45, 1.0, listing.condition / 100.0)
	var by_mileage := clampf(1.0 - listing.mileage_km / 200000.0 * 0.4, 0.6, 1.0)
	listing.price = maxi(roundi(base * by_condition * by_mileage * 1.15), 500)
	return listing
