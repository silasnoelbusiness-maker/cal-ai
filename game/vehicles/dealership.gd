class_name Dealership
extends Node
## The forecourt's own state: what is on the used lot, and where a sold car is
## handed over.
##
## Lives as a node in the world rather than as an autoload because there is one
## dealership and it is a place. If a second one ever opens, it gets its own
## stock this way round and would have needed splitting apart the other.

signal stock_changed()

var save_id: StringName = &"dealership"

## How many used cars are on the lot at once, and how often they turn over.
const USED_COUNT := 4
const REFRESH_DAYS := 3

## Which models turn up second hand. The dear ones do not: a nearly-new exotic
## on a back lot at half price would undercut the whole range it sits at the top
## of, and the aspirational car should have to be bought new.
const USED_MODELS: Array[StringName] = [
	&"compact", &"hatchback", &"sedan", &"van", &"suv",
]

var _listings: Array[UsedListing] = []
var _generated_on_day: int = -999
var _rng := RandomNumberGenerator.new()
var _next_index: int = 1


func _ready() -> void:
	add_to_group(&"dealership_stock")
	add_to_group(&"saveable")
	_rng.randomize()
	TimeManager.day_passed.connect(_on_day_passed)
	refresh_stock()


func listings() -> Array[UsedListing]:
	return _listings.duplicate()


func listing_by_id(id: StringName) -> UsedListing:
	for listing in _listings:
		if listing.listing_id == id:
			return listing
	return null


## Rolls a fresh lot. Called on the refresh day, and after a used car is sold so
## the space it left does not sit empty.
func refresh_stock() -> void:
	_listings.clear()
	# The first slot is always one of the two cheap models. A forecourt with
	# nothing on it under ten thousand is no use to a player with four figures
	# in the bank, and "come back in three days" is a poor answer to that.
	var starter: Array[StringName] = [&"compact", &"hatchback"]
	for i in USED_COUNT:
		var model_id: StringName = (
			starter[_rng.randi_range(0, starter.size() - 1)] if i == 0
			else USED_MODELS[_rng.randi_range(0, USED_MODELS.size() - 1)]
		)
		var listing := UsedListing.generate(model_id, _rng, _next_index)
		_next_index += 1
		if listing != null:
			_listings.append(listing)
	_listings.sort_custom(func(a: UsedListing, b: UsedListing) -> bool: return a.price < b.price)
	_generated_on_day = TimeManager.day_index
	stock_changed.emit()


## Takes a listing off the lot. The car it described now exists as the player's,
## so the listing must not still be for sale.
func remove_listing(listing: UsedListing) -> void:
	_listings.erase(listing)
	stock_changed.emit()


func _on_day_passed(day_index: int) -> void:
	if day_index - _generated_on_day >= REFRESH_DAYS:
		refresh_stock()


# --- Collection ----------------------------------------------------------

## Where a bought car is left. The forecourt bay if it is clear, and the next
## clear bay along if it is not — a new car must never be delivered on top of
## the one bought yesterday.
func collection_transform() -> Transform3D:
	var bays := get_tree().get_nodes_in_group(DealershipInterior.COLLECTION_GROUP)
	if bays.is_empty():
		var fallback := GameManager.player
		var origin := fallback.global_position if fallback != null else Vector3.ZERO
		return Transform3D(Basis.IDENTITY, origin + Vector3(0.0, 0.4, 6.0))

	for node in bays:
		var bay := node as Node3D
		if bay == null:
			continue
		if _is_clear(bay.global_position):
			return bay.global_transform
	# Every bay taken. The first one anyway, nudged clear along the row, which
	# is still better than refusing to hand over a car somebody has paid for.
	var first := bays[0] as Node3D
	return Transform3D(first.global_transform.basis, first.global_position + Vector3(0.0, 0.0, 3.2))


## Whether anything with wheels is already standing here.
##
## Both the cars in the world and the cars on the books, because they are not
## the same set: a car the player left in this bay and then walked away from has
## no node at all, and handing the next one over on top of it would be a car
## inside a car.
func _is_clear(point: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Node3D
		if car != null and car.global_position.distance_to(point) < 3.4:
			return false
	for record in VehicleRegistry.get_fleet():
		if record.is_stored() or record.is_spawned():
			continue
		if record.position.distance_to(point) < 3.4:
			return false
	return true


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var stock: Array = []
	for listing in _listings:
		stock.append({
			"listing_id": String(listing.listing_id),
			"model_id": String(listing.model_id),
			"mileage_km": listing.mileage_km,
			"condition": listing.condition,
			"price": listing.price,
		})
	return {"listings": stock, "generated_on_day": _generated_on_day, "next_index": _next_index}


func load_state(state: Dictionary) -> void:
	_listings.clear()
	for entry: Dictionary in state.get("listings", []):
		var listing := UsedListing.new()
		listing.listing_id = StringName(entry.get("listing_id", ""))
		listing.model_id = StringName(entry.get("model_id", "compact"))
		listing.mileage_km = float(entry.get("mileage_km", 0.0))
		listing.condition = clampf(float(entry.get("condition", 80.0)), 1.0, 100.0)
		listing.price = int(entry.get("price", 0))
		if listing.data() != null:
			_listings.append(listing)
	_generated_on_day = int(state.get("generated_on_day", TimeManager.day_index))
	_next_index = int(state.get("next_index", _next_index))
	# A save from before the used lot existed comes back with nothing on it.
	if _listings.is_empty():
		refresh_stock()
	stock_changed.emit()
