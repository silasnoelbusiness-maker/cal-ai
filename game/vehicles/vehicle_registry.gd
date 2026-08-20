extends Node
## Everything the player owns on four wheels.
##
## The records are the truth; the cars in the street are views of them. That is
## what lets a garage exist, what lets a car stay where it was left across the
## city without being simulated there, and what makes two sedans two sedans
## rather than one sedan counted twice.
##
## Nothing stolen ever gets in here. A carjacked car belongs to whoever it
## belonged to before; parking it somewhere does not change that, and the whole
## point of buying one is that this list is the difference.

signal fleet_changed()
signal vehicle_bought(record: OwnedVehicle)
signal vehicle_sold(record: OwnedVehicle, paid: int)
signal vehicle_stored(record: OwnedVehicle, garage_id: StringName)
signal vehicle_retrieved(record: OwnedVehicle)
signal vehicle_repaired(record: OwnedVehicle, cost: int)

enum BuyResult { OK, CANNOT_AFFORD, NO_SUCH_MODEL, NOT_FOR_SALE, NO_ROOM }
enum StoreResult { OK, NO_GARAGE, GARAGE_FULL, NOT_OWNED, STOLEN_VEHICLE, ALREADY_STORED }

## What the save file calls this. Autoloads are saved the same way every
## other saveable is: by group plus id.
var save_id: StringName = &"vehicle_registry"

## How close the player has to be for a parked owned car to exist as a node, and
## how far before it is put away again. The gap between the two is hysteresis:
## a car on the edge of the range must not flicker in and out as the player
## paces up and down outside it.
const SPAWN_RANGE := 120.0
const DESPAWN_RANGE := 155.0
## How often the world is checked against the records, in seconds. Four times a
## second is far more often than a person can walk 35 metres.
const SWEEP_INTERVAL := 0.25

## Metres driven per kilometre on the odometer. The city is a few hundred metres
## across, so a one-to-one odometer would never move; this scales a lap of the
## city into a believable drive. It is a display convention, nothing more —
## everything derived from mileage uses the same scale.
const METRES_PER_KM := 40.0

## How much condition a kilometre of ordinary driving takes off. Two hundred
## kilometres of careful driving costs about a point.
const WEAR_PER_KM := 0.005
## How much of a crash carries through into long-term condition. A shunt that
## takes ten health off a car costs it about a point and a half of condition.
const CRASH_CONDITION_RATIO := 0.15

var _records: Array[OwnedVehicle] = []
var _next_number: int = 1
var _sweep_timer: float = 0.0
## Where each spawned car was last seen, so distance driven can be measured
## without the vehicle having to keep an odometer of its own.
var _last_positions: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	process_mode = Node.PROCESS_MODE_PAUSABLE


# --- The fleet -----------------------------------------------------------

func get_fleet() -> Array[OwnedVehicle]:
	return _records.duplicate()


func count() -> int:
	return _records.size()


func by_id(instance_id: StringName) -> OwnedVehicle:
	for record in _records:
		if record.instance_id == instance_id:
			return record
	return null


## The record for a car in the world, if the player owns it. This is the only
## honest way to ask "is this mine" — the node's owner_type says what it was
## built as, and the registry says what is actually on the books.
func record_for(car: Vehicle) -> OwnedVehicle:
	if car == null:
		return null
	for record in _records:
		if record.node == car:
			return record
	return null


func owns(car: Vehicle) -> bool:
	return record_for(car) != null


func stored_in(garage_id: StringName) -> Array[OwnedVehicle]:
	var found: Array[OwnedVehicle] = []
	for record in _records:
		if record.is_stored() and record.garage_id == garage_id:
			found.append(record)
	return found


## What the fleet is worth today. This is the vehicle line on the net worth
## screen, and it counts garaged cars exactly once alongside street-parked ones.
func total_value() -> int:
	var total := 0
	for record in _records:
		total += record.market_value()
	return total


## The best car the player owns, by prestige. What lifestyle reads.
func best_prestige() -> int:
	var best := 0
	for record in _records:
		best = maxi(best, VehicleCatalogue.prestige(record.model_id))
	return best


# --- Buying and selling --------------------------------------------------

## Buys a car out of the player's own pocket. Personal money, never a business
## account: a company car is a different thing and does not exist yet.
##
## `used` builds it with the mileage and condition of the listing it came from,
## which is what makes the cheap end of the forecourt worth looking at.
func buy(
	model_id: StringName, at: Transform3D, price: int = -1,
	mileage_km: float = 0.0, condition: float = 100.0, paint: Color = Color(0, 0, 0, 0)
) -> BuyResult:
	var definition := VehicleCatalogue.data_for(model_id)
	if definition == null:
		return BuyResult.NO_SUCH_MODEL
	if not definition.purchasable:
		return BuyResult.NOT_FOR_SALE
	var cost := price if price >= 0 else definition.price_new
	if not EconomyManager.can_afford(cost):
		return BuyResult.CANNOT_AFFORD
	if not EconomyManager.spend(cost, "%s — purchase" % definition.display_name):
		return BuyResult.CANNOT_AFFORD

	var record := _make_record(model_id)
	record.purchase_price = cost
	record.purchase_day = TimeManager.day_index
	record.mileage_km = maxf(mileage_km, 0.0)
	record.condition = clampf(condition, 1.0, 100.0)
	record.health = record.max_health() * lerpf(0.7, 1.0, record.condition / 100.0)
	record.bought_used = mileage_km > 0.0 or condition < 100.0
	record.paint_color = paint if paint.a > 0.0 else definition.body_color
	record.position = at.origin
	record.yaw = at.basis.get_euler().y
	record.district_id = _district_at(record.position)
	_records.append(record)

	GameManager.notify(
		"VEHICLE PURCHASED\n%s  -$%s" % [
			definition.display_name.to_upper(), EconomyManager.with_thousands_separator(cost)
		],
		GameManager.Tone.GOOD
	)
	vehicle_bought.emit(record)
	fleet_changed.emit()
	_sweep()
	SaveManager.autosave("bought a vehicle")
	return BuyResult.OK


## Sells one back. The dealer's offer is what gets paid, and the car goes —
## node, record and all — so nothing is left on the map pointing at it.
func sell(record: OwnedVehicle) -> int:
	if record == null or not _records.has(record):
		return 0
	var paid := record.dealer_offer()
	_despawn(record)
	_records.erase(record)
	EconomyManager.deposit(paid, "%s — sale" % record.display_name())
	GameManager.notify(
		"VEHICLE SOLD\n%s  +$%s" % [
			record.display_name().to_upper(), EconomyManager.with_thousands_separator(paid)
		],
		GameManager.Tone.GOOD
	)
	vehicle_sold.emit(record, paid)
	fleet_changed.emit()
	SaveManager.autosave("sold a vehicle")
	return paid


## Buying one and selling another in the same breath. Kept as one call rather
## than a buy followed by a sale so the money moves exactly once: the player
## pays the difference, and a trade-in worth more than the new car pays out
## rather than charging a negative amount.
func trade_in(
	model_id: StringName, at: Transform3D, price: int, traded: OwnedVehicle,
	mileage_km: float = 0.0, condition: float = 100.0
) -> BuyResult:
	if traded == null or not _records.has(traded):
		return buy(model_id, at, price, mileage_km, condition)
	var allowance := traded.dealer_offer()
	var due := price - allowance
	if due > 0 and not EconomyManager.can_afford(due):
		return BuyResult.CANNOT_AFFORD

	# The old car leaves the books first, so its value cannot be counted on both
	# sides of the same deal.
	_despawn(traded)
	_records.erase(traded)
	if due > 0:
		EconomyManager.spend(due, "%s — part exchange" % VehicleCatalogue.display_name(model_id))
	elif due < 0:
		EconomyManager.deposit(-due, "%s — part exchange" % traded.display_name())

	var result := _create_owned(model_id, at, price, mileage_km, condition)
	GameManager.notify(
		"TRADED IN\n%s for %s" % [
			traded.display_name().to_upper(), VehicleCatalogue.display_name(model_id).to_upper()
		],
		GameManager.Tone.GOOD
	)
	vehicle_sold.emit(traded, allowance)
	fleet_changed.emit()
	SaveManager.autosave("traded a vehicle")
	return result


## Puts a car on the books without any money moving. The debug tools and the
## migration of an old save both need this; buying is the only route a player
## has to it.
func grant(
	model_id: StringName, at: Transform3D, mileage_km: float = 0.0, condition: float = 100.0
) -> OwnedVehicle:
	if VehicleCatalogue.data_for(model_id) == null:
		return null
	_create_owned(model_id, at, 0, mileage_km, condition)
	return _records.back()


func _create_owned(
	model_id: StringName, at: Transform3D, price: int, mileage_km: float, condition: float
) -> BuyResult:
	var definition := VehicleCatalogue.data_for(model_id)
	var record := _make_record(model_id)
	record.purchase_price = price
	record.purchase_day = TimeManager.day_index
	record.mileage_km = maxf(mileage_km, 0.0)
	record.condition = clampf(condition, 1.0, 100.0)
	record.health = record.max_health() * lerpf(0.7, 1.0, record.condition / 100.0)
	record.bought_used = mileage_km > 0.0 or condition < 100.0
	record.paint_color = definition.body_color
	record.position = at.origin
	record.yaw = at.basis.get_euler().y
	record.district_id = _district_at(record.position)
	_records.append(record)
	_sweep()
	return BuyResult.OK


func _make_record(model_id: StringName) -> OwnedVehicle:
	var record := OwnedVehicle.new()
	record.instance_id = StringName("owned_%d" % _next_number)
	_next_number += 1
	record.model_id = model_id
	return record


# --- Garages -------------------------------------------------------------

## Puts a car into a bay. The node goes; the record stays and remembers which
## garage has it, which is the whole reason storing one is worth doing.
func store(record: OwnedVehicle, garage_id: StringName) -> StoreResult:
	if record == null or not _records.has(record):
		return StoreResult.NOT_OWNED
	if record.stolen:
		return StoreResult.STOLEN_VEHICLE
	if record.is_stored():
		return StoreResult.ALREADY_STORED
	var garage := GarageProperty.by_id(get_tree(), garage_id)
	if garage == null or not garage.is_leased_by_player():
		return StoreResult.NO_GARAGE
	if stored_in(garage_id).size() >= garage.capacity:
		return StoreResult.GARAGE_FULL

	_sync(record)
	_despawn(record)
	record.location = OwnedVehicle.Location.GARAGE
	record.garage_id = garage_id
	vehicle_stored.emit(record, garage_id)
	fleet_changed.emit()
	return StoreResult.OK


## Takes it out again, at the bay the garage nominates. The same car comes back
## — same mileage, same dents — because it never stopped being the same record.
func retrieve(record: OwnedVehicle, at: Transform3D) -> bool:
	if record == null or not _records.has(record) or not record.is_stored():
		return false
	record.location = OwnedVehicle.Location.STREET
	record.garage_id = &""
	record.position = at.origin
	record.yaw = at.basis.get_euler().y
	record.district_id = _district_at(record.position)
	_sweep()
	vehicle_retrieved.emit(record)
	fleet_changed.emit()
	return true


# --- Repair --------------------------------------------------------------

## What a garage would charge to put the mechanical damage right.
func repair_quote(record: OwnedVehicle) -> int:
	if record == null:
		return 0
	var missing := 1.0 - record.health_fraction()
	if missing <= 0.001:
		return 0
	# Priced off what the car is worth rather than what it cost: a dent in a
	# Solstice is a Solstice's dent. The floor stops a scratch costing nothing.
	var bill := roundi(float(VehicleCatalogue.base_value(record.model_id)) * missing * 0.09)
	return maxi(bill, 60)


## And to put the years right, which is dearer and only ever partial: bodywork
## and a service bring a car back most of the way, never to showroom new.
func restore_quote(record: OwnedVehicle) -> int:
	if record == null:
		return 0
	var missing := 1.0 - clampf(record.condition / 100.0, 0.0, 1.0)
	if missing <= 0.005:
		return 0
	var bill := roundi(float(VehicleCatalogue.base_value(record.model_id)) * missing * 0.30)
	return maxi(bill, 120)


## How far a full restoration gets: most of the way back, never all of it.
func restored_condition(record: OwnedVehicle) -> float:
	if record == null:
		return 0.0
	return clampf(record.condition + (100.0 - record.condition) * 0.8, 0.0, 100.0)


func repair(record: OwnedVehicle, restore_condition: bool) -> int:
	if record == null or not _records.has(record):
		return 0
	var cost := repair_quote(record) + (restore_quote(record) if restore_condition else 0)
	if cost <= 0:
		return 0
	if not EconomyManager.spend(cost, "%s — repairs" % record.display_name()):
		GameManager.notify("NOT ENOUGH CASH FOR THAT", GameManager.Tone.BAD)
		return 0

	record.health = record.max_health()
	if restore_condition:
		record.condition = restored_condition(record)
	if record.is_spawned():
		record.node.restore_health()
	vehicle_repaired.emit(record, cost)
	fleet_changed.emit()
	return cost


# --- The world -----------------------------------------------------------

func _process(delta: float) -> void:
	_sweep_timer -= delta
	_track_movement(delta)
	if _sweep_timer > 0.0:
		return
	_sweep_timer = SWEEP_INTERVAL
	_sweep()


## Brings the world into line with the records: spawn what is near, put away
## what is not, and never touch the car the player is sitting in.
func _sweep() -> void:
	var player := GameManager.player
	for record in _records:
		if record.is_stored():
			if record.is_spawned():
				_despawn(record)
			continue
		if not record.is_spawned():
			if player == null or record.position.distance_to(player.global_position) <= SPAWN_RANGE:
				_spawn(record)
			continue
		_sync(record)
		if player == null or record.node.has_driver():
			continue
		if record.position.distance_to(player.global_position) > DESPAWN_RANGE:
			_despawn(record)


## Distance driven, taken from how far the node actually moved. Measuring the
## world rather than reading the throttle means a car being pushed, towed or
## shoved down a hill still puts miles on — and, more to the point, a parked
## car cannot put miles on however long it idles.
func _track_movement(_delta: float) -> void:
	for record in _records:
		if not record.is_spawned():
			continue
		var here := record.node.global_position
		var previous: Variant = _last_positions.get(record.instance_id)
		_last_positions[record.instance_id] = here
		if previous == null:
			continue
		var moved := here.distance_to(previous as Vector3)
		# A stationary body still jitters a few millimetres against the ground.
		if moved < 0.02:
			continue
		var km := moved / METRES_PER_KM
		record.mileage_km += km
		record.condition = maxf(record.condition - km * WEAR_PER_KM, 1.0)


func _spawn(record: OwnedVehicle) -> void:
	var scene := VehicleCatalogue.scene_for(record.model_id)
	if scene == null:
		return
	var host := _fleet_container()
	if host == null:
		return
	var car: Vehicle = scene.instantiate()
	car.name = "Owned_%s" % record.instance_id
	car.owner_type = Vehicle.OwnerType.PLAYER
	car.owner_id = record.owner_id
	# Deliberately not in the saveable group: the registry saves the whole fleet
	# as records, and a car that saved itself as well would come back twice.
	car.save_id = &""

	# One VehicleData per model is shared, so an individual car's paint needs a
	# copy of it. Everything else still comes from the shared model.
	var tinted: VehicleData = car.data.duplicate()
	tinted.body_color = record.paint_color
	car.data = tinted

	car.position = record.position
	car.rotation = Vector3(0.0, record.yaw, 0.0)
	host.add_child(car)
	car.set_health(record.health)
	record.node = car
	_last_positions[record.instance_id] = car.global_position
	car.collided.connect(_on_owned_collision.bind(record))


func _despawn(record: OwnedVehicle) -> void:
	if not record.is_spawned():
		record.node = null
		return
	_sync(record)
	record.node.queue_free()
	record.node = null
	_last_positions.erase(record.instance_id)


## Copies the world back into the record. Called before anything that loses the
## node, and every sweep while it exists.
func _sync(record: OwnedVehicle) -> void:
	if not record.is_spawned():
		return
	record.position = record.node.global_position
	record.yaw = record.node.rotation.y
	record.health = record.node.health
	record.district_id = _district_at(record.position)


## A crash costs health now and a little condition for good. The ratio is what
## makes a chase expensive: the panel work is cheap, the car never being quite
## right again is not.
func _on_owned_collision(impact_speed: float, record: OwnedVehicle) -> void:
	if not record.is_spawned():
		return
	var definition := record.data()
	if definition == null or impact_speed <= definition.damage_speed_threshold:
		return
	var lost := (impact_speed - definition.damage_speed_threshold) * definition.damage_per_impact_speed
	record.condition = maxf(record.condition - lost * CRASH_CONDITION_RATIO, 1.0)
	record.health = record.node.health


func _fleet_container() -> Node:
	var main := get_tree().current_scene
	if main == null:
		return null
	var existing := main.get_node_or_null("OwnedVehicles")
	if existing != null:
		return existing
	var host := Node3D.new()
	host.name = "OwnedVehicles"
	main.add_child(host)
	return host


func _district_at(position: Vector3) -> StringName:
	var district := WorldManager.district_at(position)
	return district.district_id if district != null else &"harbour_row"


# --- Adoption and migration ----------------------------------------------

## Takes the world's own player-owned cars onto the books.
##
## The starter sedan is placed by the district, not bought, and saves written
## before any of this existed describe it as a scene node with a save id. Both
## become records the first time they are seen, with safe defaults for the
## fields they never had — which is what §157 means by not losing them.
func adopt_scene_vehicles() -> void:
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Vehicle
		if car == null or car.owner_type != Vehicle.OwnerType.PLAYER or car.data == null:
			continue
		if owns(car):
			continue
		if _adopted_before(car):
			# Already on the books from a save; the node is the old view of it
			# and the registry will spawn its own.
			car.queue_free()
			continue
		var record := _make_record(car.data.id)
		record.purchase_price = car.data.resale_value
		record.purchase_day = TimeManager.day_index
		record.condition = 100.0
		record.health = car.health
		record.position = car.global_position
		record.yaw = car.rotation.y
		record.district_id = _district_at(record.position)
		record.paint_color = car.data.body_color
		record.node = car
		_last_positions[record.instance_id] = car.global_position
		# It stops saving itself: the registry now speaks for it.
		car.save_id = &""
		car.remove_from_group(&"saveable")
		car.collided.connect(_on_owned_collision.bind(record))
		_records.append(record)
	fleet_changed.emit()


## Whether a scene-placed car describes a vehicle the registry already holds.
## Position is the only thing the two have in common on a freshly loaded save.
func _adopted_before(car: Vehicle) -> bool:
	for record in _records:
		if record.model_id == car.data.id and record.position.distance_to(car.global_position) < 1.0:
			return true
	return false


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	for record in _records:
		_sync(record)
	var fleet: Array = []
	for record in _records:
		fleet.append(record.to_dictionary())
	return {"fleet": fleet, "next_number": _next_number}


func load_state(state: Dictionary) -> void:
	for record in _records:
		_despawn(record)
	_records.clear()
	_last_positions.clear()
	for entry: Dictionary in state.get("fleet", []):
		var record := OwnedVehicle.from_dictionary(entry)
		if record.instance_id == &"":
			record.instance_id = StringName("owned_%d" % _next_number)
			_next_number += 1
		_records.append(record)
	_next_number = maxi(int(state.get("next_number", _next_number)), _highest_number() + 1)
	fleet_changed.emit()
	_sweep()


func _highest_number() -> int:
	var highest := 0
	for record in _records:
		var digits := String(record.instance_id).trim_prefix("owned_")
		if digits.is_valid_int():
			highest = maxi(highest, int(digits))
	return highest


## Wipes the fleet. Only the test harness and a new game need this.
func clear() -> void:
	for record in _records:
		_despawn(record)
	_records.clear()
	_last_positions.clear()
	_next_number = 1
	fleet_changed.emit()
