extends Node
## The company's distribution: warehouses, transfers, vans and routes.
##
## Phase O gave the company branches; this gives it a backbone. The rule the
## whole file is built around is that goods are conserved. Stock is only ever in
## one of three places — standing in a warehouse, standing in a branch, or
## riding on a transfer that owns it outright — and every path between them is
## a single move with no window where it is in two of them or none.
##
## Money is conserved the same way. There is no company treasury: warehouse
## spending is drawn from a nominated funding business through the same `debit`
## every other expense uses, so a warehouse full of stock is not a second pile
## of money the net-worth sum has to be told about.

signal warehouse_leased(warehouse: WarehouseInstance)
signal warehouse_released(warehouse_id: StringName)
signal transfer_created(order: TransferOrder)
signal transfer_dispatched(order: TransferOrder)
signal transfer_delivered(order: TransferOrder)
signal transfer_failed(order: TransferOrder)
signal route_changed()
signal stock_arrived(warehouse_id: StringName, item_id: StringName, quantity: int)

enum TransferResult {
	OK, NO_SOURCE, NO_DESTINATION, SAME_PLACE, NOTHING_TO_SEND,
	NOT_ENOUGH_STOCK, NO_ROOM, NO_VEHICLE, NO_DRIVER, NOT_ALLOWED,
}

## Bulk discount bands: [units at or above, fraction off]. Modest on purpose —
## §10 warns against turning the warehouse into a buy-and-resell exploit, and
## the saving has to stay smaller than the rent it costs to have one.
const BULK_BANDS: Array = [[400, 0.08], [250, 0.06], [120, 0.03], [0, 0.0]]

## Metres a van covers per in-game minute. Slower than the player driving
## flat out, because a van on a delivery round is not being driven flat out.
const VAN_METRES_PER_MINUTE := 260.0
## Floor and ceiling on a journey, so two shops on the same street are not an
## instant transfer and a cross-city run is not an afternoon.
const MIN_TRAVEL_MINUTES := 12.0
const MAX_TRAVEL_MINUTES := 140.0
## What running a van costs per journey, per kilometre. Abstract: §46 rules out
## a fuel system, and this stands for fuel, tyres and wear together.
const VAN_COST_PER_KM := 1.4
## Chance a supplier run to the warehouse is late, and by how long.
const SUPPLIER_DELAY_CHANCE := 0.08
const SUPPLIER_DELAY_MINUTES := Vector2(60.0, 240.0)

var save_id: StringName = &"logistics"
## A save written before the depots existed had no depots, no shipments and
## no rounds. Loading one empties this rather than leaving the last game's
## warehouse standing in a city that never bought it.
var reset_on_missing_save: bool = true

## The visible half of a delivery: a van on the road when the player is near
## enough to see one. Never the authority on where the goods are.
var traffic: DeliveryTraffic = null

var _warehouses: Array[WarehouseInstance] = []
var _transfers: Array[TransferOrder] = []
var _routes: Array[DeliveryRoute] = []
var _next_transfer: int = 1
var _next_route: int = 1
var _rng := RandomNumberGenerator.new()
## Which business pays for warehouse stock and rent. No new money is created;
## the warehouse simply spends out of a branch the player nominates.
var funding_business_id: StringName = &""

## Running totals for the company statistics screen.
var units_distributed: int = 0
var shipments_completed: int = 0
var late_shipments: int = 0
var bulk_savings: int = 0
var delivery_costs: int = 0


func _ready() -> void:
	add_to_group(&"saveable")
	_rng.randomize()
	TimeManager.hour_passed.connect(_on_hour_passed)
	TimeManager.day_passed.connect(_on_day_passed)
	traffic = DeliveryTraffic.new()
	traffic.name = "DeliveryTraffic"
	add_child(traffic)
	SaveManager.game_loaded.connect(_on_game_loaded)


## Vans on the road are a view of the transfers, and the transfers have just
## been replaced wholesale. Drop them and let the review put back whatever the
## loaded game actually has in flight.
func _on_game_loaded(_slot: int) -> void:
	if traffic != null:
		traffic.clear()


# --- Warehouses ----------------------------------------------------------

func warehouses() -> Array[WarehouseInstance]:
	return _warehouses.duplicate()


func has_warehouse() -> bool:
	return not _warehouses.is_empty()


func warehouse_by_id(warehouse_id: StringName) -> WarehouseInstance:
	for warehouse in _warehouses:
		if warehouse.warehouse_id == warehouse_id:
			return warehouse
	return null


func warehouse_for_property(property_id: StringName) -> WarehouseInstance:
	for warehouse in _warehouses:
		if warehouse.property_id == property_id:
			return warehouse
	return null


func primary_warehouse() -> WarehouseInstance:
	return _warehouses[0] if not _warehouses.is_empty() else null


## Takes a warehouse on. The lease itself is PropertyManager's, exactly as a
## shop unit is — a warehouse is a commercial property with a different class,
## not a new kind of thing to own.
func take_warehouse(property: CommercialProperty) -> WarehouseInstance:
	if property == null:
		return null
	var warehouse_id := WarehouseData.for_property(property.property_id)
	if warehouse_id == &"":
		return null
	var existing := warehouse_by_id(warehouse_id)
	if existing != null:
		return existing
	var warehouse := WarehouseInstance.make(warehouse_id, TimeManager.day_index)
	warehouse.owned_outright = not property.has_landlord()
	_warehouses.append(warehouse)
	if funding_business_id == &"":
		var first := BusinessManager.primary_business()
		funding_business_id = first.business_id if first != null else &""
	warehouse_leased.emit(warehouse)
	CompanyManager.note_milestone(&"first_warehouse")
	GameManager.notify(
		"WAREHOUSE TAKEN ON\n%s" % warehouse.display_name.to_upper(), GameManager.Tone.GOOD
	)
	AudioManager.play_ui(&"ui_confirm")
	SaveManager.autosave("took on a warehouse")
	return warehouse


func release_warehouse(warehouse_id: StringName) -> void:
	for i in _warehouses.size():
		if _warehouses[i].warehouse_id != warehouse_id:
			continue
		_warehouses.remove_at(i)
		# Anything still moving to or from it is not left pointing at nothing.
		for order in _transfers:
			if order.is_open() and (
				order.source_id == warehouse_id or order.destination_id == warehouse_id
			):
				_fail(order, "The warehouse is gone.")
		warehouse_released.emit(warehouse_id)
		return


## The business that pays for the warehouse. Never a random one: the player
## nominates it, and it is the same account the logistics screen shows.
func funding_business() -> BusinessInstance:
	var business := BusinessManager.by_id(funding_business_id)
	if business != null:
		return business
	return BusinessManager.primary_business()


func set_funding_business(business: BusinessInstance) -> void:
	if business != null:
		funding_business_id = business.business_id


# --- Bulk purchasing -----------------------------------------------------

## The discount a given size of order earns.
static func bulk_discount(units: int) -> float:
	for band in BULK_BANDS:
		if units >= int(band[0]):
			return float(band[1])
	return 0.0


func bulk_quote(item: ItemData, units: int) -> Dictionary:
	if item == null or units <= 0:
		return {"units": 0, "gross": 0, "discount": 0.0, "saved": 0, "cost": 0}
	var supplier := SupplierData.for_category(_category_for(item))
	var gross := supplier.price_for(item, units)
	var discount := bulk_discount(units)
	var saved := roundi(float(gross) * discount)
	return {
		"units": units, "gross": gross, "discount": discount,
		"saved": saved, "cost": maxi(gross - saved, 1),
		"supplier": supplier.display_name,
	}


## Which wholesaler stocks a given item, worked out from whichever business
## type buys it. A warehouse has no type of its own, so it borrows the one that
## would have ordered the goods anyway.
func _category_for(item: ItemData) -> StringName:
	for definition in BusinessCatalogue.TYPES:
		if definition.orderable().has(item):
			return definition.supply_category
	return &"retail_goods"


## Orders in bulk to a warehouse. The money leaves the funding business now and
## the goods arrive later, exactly as a branch order does.
func order_to_warehouse(
	warehouse: WarehouseInstance, item_id: StringName, units: int
) -> BusinessManager.PurchaseResult:
	if warehouse == null:
		return BusinessManager.PurchaseResult.NO_BUSINESS
	var item := ItemCatalogue.by_id(item_id)
	if item == null:
		return BusinessManager.PurchaseResult.NO_SUCH_ITEM
	var payer := funding_business()
	if payer == null:
		return BusinessManager.PurchaseResult.NO_BUSINESS
	units = mini(maxi(units, 0), warehouse.room_left() - _incoming_units(warehouse))
	if units <= 0:
		return BusinessManager.PurchaseResult.NO_ROOM

	var quote := bulk_quote(item, units)
	if not payer.debit(
		int(quote["cost"]), "Bulk — %s x%d" % [item.display_name, units], &"inventory"
	):
		return BusinessManager.PurchaseResult.NOT_ENOUGH_FUNDS
	bulk_savings += int(quote["saved"])

	var order := PurchaseOrder.new()
	order.order_id = StringName("wh_order_%d" % _next_transfer)
	_next_transfer += 1
	order.business_id = payer.business_id
	order.warehouse_id = warehouse.warehouse_id
	order.supplier_id = SupplierData.for_category(_category_for(item)).supplier_id
	order.items[item_id] = units
	order.total_cost = int(quote["cost"])
	order.placed_at = TimeManager.total_minutes
	var supplier := SupplierData.for_category(_category_for(item))
	var minutes := supplier.delivery_minutes(_rng)
	# Suppliers are mostly reliable and occasionally not, which is what makes
	# holding a buffer worth doing.
	if _rng.randf() < SUPPLIER_DELAY_CHANCE:
		minutes += _rng.randf_range(SUPPLIER_DELAY_MINUTES.x, SUPPLIER_DELAY_MINUTES.y)
		order.delayed = true
	order.arrives_at = order.placed_at + minutes
	BusinessManager.register_warehouse_order(order)

	GameManager.notify(
		"BULK ORDER PLACED\n%s x%d  ·  saved $%d" % [
			item.display_name, units, int(quote["saved"])
		],
		GameManager.Tone.INFO
	)
	AudioManager.play(&"delivery", AudioBuses.SFX, -12.0)
	return BusinessManager.PurchaseResult.OK


func _incoming_units(warehouse: WarehouseInstance) -> int:
	var total := 0
	for order in BusinessManager.outstanding_orders():
		if order.warehouse_id == warehouse.warehouse_id:
			total += order.unit_count()
	return total


## Called by BusinessManager when a supplier run reaches a warehouse rather
## than a shop. Anything that will not fit stays undelivered rather than
## evaporating.
func receive_supplier_delivery(order: PurchaseOrder) -> int:
	var warehouse := warehouse_by_id(order.warehouse_id)
	if warehouse == null:
		return 0
	var landed := 0
	for id: StringName in order.items:
		var took := warehouse.add(id, int(order.items[id]))
		landed += took
		if took > 0:
			stock_arrived.emit(warehouse.warehouse_id, id, took)
	return landed


# --- Transfers -----------------------------------------------------------

func transfers() -> Array[TransferOrder]:
	return _transfers.duplicate()


func open_transfers() -> Array[TransferOrder]:
	var found: Array[TransferOrder] = []
	for order in _transfers:
		if order.is_open():
			found.append(order)
	return found


func transfer_by_id(transfer_id: StringName) -> TransferOrder:
	for order in _transfers:
		if order.transfer_id == transfer_id:
			return order
	return null


func transfers_for(business_id: StringName) -> Array[TransferOrder]:
	var found: Array[TransferOrder] = []
	for order in _transfers:
		if order.destination_id == business_id or order.source_id == business_id:
			found.append(order)
	return found


## Books a move and reserves the cargo at the source in one step.
##
## Reservation happens here rather than at dispatch because the gap between
## "the player asked for it" and "a van is free" can be hours, and stock that
## can be sold during that gap is stock that will be promised twice.
func request_transfer(
	source_kind: TransferOrder.Place, source_id: StringName,
	destination_kind: TransferOrder.Place, destination_id: StringName,
	wanted: Dictionary, priority: TransferOrder.Priority = TransferOrder.Priority.NORMAL,
	allow_partial: bool = true
) -> Dictionary:
	if source_kind == destination_kind and source_id == destination_id:
		return {"result": TransferResult.SAME_PLACE, "order": null}
	if not _place_exists(source_kind, source_id):
		return {"result": TransferResult.NO_SOURCE, "order": null}
	if not _place_exists(destination_kind, destination_id):
		return {"result": TransferResult.NO_DESTINATION, "order": null}
	if wanted.is_empty():
		return {"result": TransferResult.NOTHING_TO_SEND, "order": null}

	var order := TransferOrder.make(
		StringName("transfer_%d" % _next_transfer), source_kind, source_id,
		destination_kind, destination_id, TimeManager.total_minutes
	)
	_next_transfer += 1
	order.priority = priority

	# Reserve what is really there, and no more than will fit at the far end.
	# A request for fifty against twenty either ships twenty or ships nothing,
	# and never creates thirty; a request for more than the destination's back
	# room holds is trimmed here rather than driven across the city and
	# brought back again.
	var room := _room_at(destination_kind, destination_id)
	if room <= 0:
		# Nothing wrong with the stock — there is simply nowhere to put it.
		# Saying "not enough stock" here would send the player to the wrong
		# problem entirely.
		return {"result": TransferResult.NO_ROOM, "order": null}
	var short := false
	for id: StringName in wanted:
		var asked := mini(int(wanted[id]), room)
		if asked <= 0:
			short = short or int(wanted[id]) > 0
			continue
		var promised := _reserve_at(source_kind, source_id, id, asked)
		room -= promised
		if promised < asked:
			short = true
		if promised > 0:
			order.items[id] = promised
	if short and not allow_partial:
		_release_all(order)
		return {"result": TransferResult.NOT_ENOUGH_STOCK, "order": null}
	if order.items.is_empty():
		return {"result": TransferResult.NOT_ENOUGH_STOCK, "order": null}

	order.status = TransferOrder.Status.QUEUED
	if short:
		order.note = "Part of what was asked for."
	_transfers.append(order)
	transfer_created.emit(order)
	AudioManager.play_ui(&"ui_click")
	return {"result": TransferResult.OK, "order": order}


## Sends it. From here the cargo belongs to the order and to nothing else.
func dispatch_transfer(
	order: TransferOrder, vehicle: OwnedVehicle = null, driver: EmployeeData = null,
	by_player: bool = false
) -> TransferResult:
	if order == null or not order.is_reserved():
		return TransferResult.NOT_ALLOWED
	if not by_player:
		if vehicle == null:
			vehicle = CompanyFleet.free_van()
		if vehicle == null:
			order.note = "No van available."
			return TransferResult.NO_VEHICLE
		if driver == null:
			driver = CompanyFleet.free_driver(TimeManager.hour)
		if driver == null:
			order.note = "No driver on shift."
			return TransferResult.NO_DRIVER
	var warehouse := warehouse_by_id(order.source_id)
	if warehouse != null and warehouse.dispatch_room() < order.unit_count():
		order.note = "The warehouse cannot get any more out today."
		return TransferResult.NOT_ALLOWED

	# The goods leave the source now. This is the one moment they move, and it
	# is the same call whoever is driving.
	for id: StringName in order.items:
		_take_at(order.source_kind, order.source_id, id, int(order.items[id]))
	if warehouse != null:
		warehouse.note_dispatch(order.unit_count())

	order.player_driven = by_player
	order.assigned_vehicle_id = vehicle.instance_id if vehicle != null else &""
	order.assigned_driver_id = driver.employee_id if driver != null else &""
	order.dispatch_minute = TimeManager.total_minutes
	order.status = TransferOrder.Status.IN_TRANSIT
	order.note = ""

	if by_player:
		# The player's own run has no clock: it arrives when they get there.
		order.arrival_minute = order.dispatch_minute + MAX_TRAVEL_MINUTES * 4.0
	else:
		var minutes := travel_minutes(order, vehicle, driver)
		order.arrival_minute = order.dispatch_minute + minutes
		_charge_delivery(order, minutes, vehicle)
		CompanyFleet.set_vehicle_busy(vehicle, order.transfer_id)

	transfer_dispatched.emit(order)
	AudioManager.play(&"car_door", AudioBuses.SFX, -14.0)
	return TransferResult.OK


# --- The player's own runs -----------------------------------------------

## How close the player has to get before they can unload.
const DROPOFF_REACH := 6.0


## Shipments the player is driving themselves.
func player_runs() -> Array[TransferOrder]:
	var found: Array[TransferOrder] = []
	for order in _transfers:
		if order.player_driven and order.is_moving():
			found.append(order)
	return found


func active_player_run() -> TransferOrder:
	var runs := player_runs()
	return runs[0] if not runs.is_empty() else null


## Takes a booked shipment out yourself. §110: no van and no driver are used
## up, no delivery cost is charged, and no clock runs — it arrives when the
## player gets there. What it costs instead is the player's own time.
func take_run(order: TransferOrder) -> TransferResult:
	if order == null or not order.is_reserved():
		return TransferResult.NOT_ALLOWED
	if not player_runs().is_empty():
		order.note = "You are already out on a delivery."
		return TransferResult.NOT_ALLOWED
	var result := dispatch_transfer(order, null, null, true)
	if result == TransferResult.OK:
		_plant_dropoff(order)
		GameManager.notify(
			"SHIPMENT LOADED\n%s  ·  %s" % [
				order.cargo_text(),
				place_name(order.destination_kind, order.destination_id).to_upper(),
			],
			GameManager.Tone.GOOD
		)
	return result


## Whether the player is standing close enough to unload. The drop-off point
## enforces this itself through its own reach; this is for the screen, which
## has to say why the button is greyed out.
func can_hand_over(order: TransferOrder) -> bool:
	if order == null or not order.player_driven or not order.is_moving():
		return false
	var player := GameManager.player
	if player == null:
		return false
	var where := _place_position(order.destination_kind, order.destination_id)
	return player.global_position.distance_to(where) <= DROPOFF_REACH * 2.0


## Unloading. The same completion a van gets, because the goods arriving is
## one event however it got there.
func hand_over(order: TransferOrder) -> bool:
	if order == null or not order.player_driven or not order.is_moving():
		return false
	complete_transfer(order)
	_clear_dropoffs()
	return true


## Gives up partway. The cargo goes back where it came from rather than
## evaporating: it is still the company's stock, it is just back on the shelf
## it left.
func abandon_run(order: TransferOrder) -> bool:
	if order == null or not order.player_driven or not order.is_moving():
		return false
	# _fail already knows how to put cargo back without losing any of it,
	# including when the shelf it came from has filled up in the meantime.
	_fail(order, "You turned back.")
	_clear_dropoffs()
	return true


func _plant_dropoff(order: TransferOrder) -> void:
	_clear_dropoffs()
	var where := _place_position(order.destination_kind, order.destination_id)
	if where == Vector3.ZERO:
		return
	var point := DropoffPoint.new()
	point.transfer_id = order.transfer_id
	point.name = "Dropoff_%s" % String(order.transfer_id)
	var world := get_tree().current_scene
	if world == null:
		return
	world.add_child(point)
	point.global_position = where


func _clear_dropoffs() -> void:
	for point in get_tree().get_nodes_in_group(&"dropoff_point"):
		# Leave the group now rather than when the free actually happens:
		# queue_free is deferred, and anything asking "is there still a
		# drop-off?" this frame would otherwise be told yes.
		point.remove_from_group(&"dropoff_point")
		point.queue_free()


## How long the journey takes. Distance is the bulk of it; the driver shaves a
## little off. Both near and far simulation use this, so a van does not get
## faster because nobody is looking at it.
func travel_minutes(
	order: TransferOrder, _vehicle: OwnedVehicle, driver: EmployeeData
) -> float:
	var from_point := _place_position(order.source_kind, order.source_id)
	var to_point := _place_position(order.destination_kind, order.destination_id)
	var metres := from_point.distance_to(to_point)
	var minutes := metres / VAN_METRES_PER_MINUTE
	if driver != null:
		# A good driver knows the way. Modestly: §30 says the skill matters a
		# little, not that it halves the city.
		minutes *= lerpf(1.15, 0.85, clampf(float(driver.skill_logistics) / 100.0, 0.0, 1.0))
	return clampf(minutes, MIN_TRAVEL_MINUTES, MAX_TRAVEL_MINUTES)


func _charge_delivery(order: TransferOrder, minutes: float, vehicle: OwnedVehicle) -> void:
	var payer := funding_business()
	if payer == null:
		return
	var km := minutes * VAN_METRES_PER_MINUTE / 1000.0
	var cost := maxi(roundi(km * VAN_COST_PER_KM), 1)
	if payer.debit(cost, "Delivery run", &"other"):
		delivery_costs += cost
	if vehicle != null:
		# The van wears like any other vehicle, through the registry that
		# already knows how. No second condition system.
		VehicleRegistry.add_mileage(vehicle, km)


## Delivers it. The only place cargo becomes branch or warehouse stock.
func complete_transfer(order: TransferOrder) -> void:
	if order == null or not order.is_moving():
		return
	var landed := 0
	var leftover := {}
	for id: StringName in order.items:
		var wanted := int(order.items[id])
		var took := _add_at(order.destination_kind, order.destination_id, id, wanted)
		landed += took
		if took < wanted:
			leftover[id] = wanted - took
	order.status = TransferOrder.Status.DELIVERED
	order.arrival_minute = TimeManager.total_minutes
	units_distributed += landed
	shipments_completed += 1

	# Whatever would not fit goes back rather than disappearing. §20 is the
	# whole reason this branch exists.
	if not leftover.is_empty():
		order.note = "Some of it would not fit and went back."
		for id: StringName in leftover:
			_add_at(order.source_kind, order.source_id, id, int(leftover[id]))
	CompanyFleet.clear_vehicle_task(order.assigned_vehicle_id)
	transfer_delivered.emit(order)
	GameManager.notify(
		"DELIVERY ARRIVED\n%s  ·  %d units" % [
			_place_name(order.destination_kind, order.destination_id), landed
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"delivery", AudioBuses.SFX, -10.0)


## Calls a transfer off before it goes. The reservation is released and nothing
## has moved, so there is nothing to put back.
func cancel_transfer(order: TransferOrder) -> bool:
	if order == null or not order.can_cancel():
		return false
	_release_all(order)
	order.status = TransferOrder.Status.CANCELLED
	order.items.clear()
	AudioManager.play_ui(&"ui_back")
	return true


## Something went wrong mid-journey. The cargo goes back where it came from —
## it is still real, and the one thing that must never happen is it ceasing to
## exist because of a failure path.
func _fail(order: TransferOrder, reason: String) -> void:
	if order == null or not order.is_open():
		return
	if order.is_moving():
		for id: StringName in order.items:
			var returned := _add_at(order.source_kind, order.source_id, id, int(order.items[id]))
			if returned < int(order.items[id]):
				# Even the source is full. It waits at the destination's door
				# rather than being thrown away.
				_add_at(
					order.destination_kind, order.destination_id, id,
					int(order.items[id]) - returned
				)
	else:
		_release_all(order)
	order.status = TransferOrder.Status.FAILED
	order.note = reason
	CompanyFleet.clear_vehicle_task(order.assigned_vehicle_id)
	transfer_failed.emit(order)


func _release_all(order: TransferOrder) -> void:
	for id: StringName in order.items:
		_release_at(order.source_kind, order.source_id, id, int(order.items[id]))


# --- Where things are ----------------------------------------------------
#
# One pair of accessors for both kinds of place, so every path through this
# file moves stock the same way whether the thing at the end of it is a
# warehouse or a shop. Adding a third kind of place later is another branch
# here and nothing else.

func _place_exists(kind: TransferOrder.Place, id: StringName) -> bool:
	if kind == TransferOrder.Place.WAREHOUSE:
		return warehouse_by_id(id) != null
	return BusinessManager.by_id(id) != null


## The human name of a place. Public for the same reason place_position is:
## the screens and the drop-off marker have to name the same end of the run
## the manager is moving goods between.
func place_name(kind: TransferOrder.Place, id: StringName) -> String:
	return _place_name(kind, id)


func _place_name(kind: TransferOrder.Place, id: StringName) -> String:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.display_name if warehouse != null else "Warehouse"
	var business := BusinessManager.by_id(id)
	return business.business_name if business != null else "Branch"


## Where a place stands in the world. Public because the visible delivery
## layer needs the same two points the abstract journey is measured between —
## the van must drive the run the clock is timing, not a different one.
func place_position(kind: TransferOrder.Place, id: StringName) -> Vector3:
	return _place_position(kind, id)


func _place_position(kind: TransferOrder.Place, id: StringName) -> Vector3:
	var property_id := &""
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		property_id = warehouse.property_id if warehouse != null else &""
	else:
		var business := BusinessManager.by_id(id)
		property_id = business.property_id if business != null else &""
	var unit := PropertyManager.by_id(property_id)
	return unit.global_position if unit != null else Vector3.ZERO


func _reserve_at(kind: TransferOrder.Place, id: StringName, item: StringName, units: int) -> int:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.reserve(item, units) if warehouse != null else 0
	var business := BusinessManager.by_id(id)
	return business.reserve_stock(item, units) if business != null else 0


func _release_at(kind: TransferOrder.Place, id: StringName, item: StringName, units: int) -> void:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		if warehouse != null:
			warehouse.release(item, units)
		return
	var business := BusinessManager.by_id(id)
	if business != null:
		business.release_stock(item, units)


func _take_at(kind: TransferOrder.Place, id: StringName, item: StringName, units: int) -> int:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.take(item, units) if warehouse != null else 0
	var business := BusinessManager.by_id(id)
	if business == null:
		return 0
	business.release_stock(item, units)
	return business.take_storage(item, units)


func _add_at(kind: TransferOrder.Place, id: StringName, item: StringName, units: int) -> int:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.add(item, units) if warehouse != null else 0
	var business := BusinessManager.by_id(id)
	return business.add_storage(item, units) if business != null else 0


## Room at the far end, so nothing is sent that cannot be put away.
func _room_at(kind: TransferOrder.Place, id: StringName) -> int:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.room_left() if warehouse != null else 0
	var business := BusinessManager.by_id(id)
	return business.storage_room_left() if business != null else 0


func available_at(kind: TransferOrder.Place, id: StringName, item: StringName) -> int:
	if kind == TransferOrder.Place.WAREHOUSE:
		var warehouse := warehouse_by_id(id)
		return warehouse.available(item) if warehouse != null else 0
	var business := BusinessManager.by_id(id)
	return business.available_storage(item) if business != null else 0


# --- Routes --------------------------------------------------------------

func routes() -> Array[DeliveryRoute]:
	return _routes.duplicate()


func route_by_id(route_id: StringName) -> DeliveryRoute:
	for route in _routes:
		if route.route_id == route_id:
			return route
	return null


func create_route(warehouse: WarehouseInstance, route_name: String = "") -> DeliveryRoute:
	if warehouse == null:
		return null
	var route := DeliveryRoute.make(
		StringName("route_%d" % _next_route), warehouse.warehouse_id
	)
	_next_route += 1
	if not route_name.strip_edges().is_empty():
		route.display_name = route_name.strip_edges().left(32)
	else:
		route.display_name = "Route %d" % _routes.size()
	_routes.append(route)
	route_changed.emit()
	CompanyManager.note_milestone_if(&"five_routes", _routes.size() >= 5)
	return route


func delete_route(route: DeliveryRoute) -> void:
	var index := _routes.find(route)
	if index >= 0:
		_routes.remove_at(index)
		route_changed.emit()


## Runs whatever routes are due. Each stop is topped up to its own target from
## whatever the warehouse can spare, worst-off branch first.
func run_due_routes(day: int, weekday: int, hour: int) -> int:
	var sent := 0
	for route in _routes:
		if not route.is_due(day, weekday, hour):
			continue
		route.last_run_day = day
		var warehouse := warehouse_by_id(route.warehouse_id)
		if warehouse == null:
			continue
		for business_id in route.stop_business_ids:
			var business := BusinessManager.by_id(business_id)
			if business == null or not business.is_trading():
				continue
			var wanted := shortfall_for(business)
			if wanted.is_empty():
				continue
			var made := request_transfer(
				TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
				TransferOrder.Place.BUSINESS, business_id, wanted, route.priority
			)
			var order: TransferOrder = made["order"]
			if order == null:
				continue
			var vehicle := CompanyFleet.vehicle_by_id(route.vehicle_id)
			var driver := BusinessManager.employee_by_id(route.driver_id)
			if dispatch_transfer(order, vehicle, driver) == TransferResult.OK:
				sent += 1
			# A route that cannot go keeps its reservation and waits for a van
			# rather than throwing the request away.
	return sent


## What a branch is short of, against its own minimums and targets.
func shortfall_for(business: BusinessInstance) -> Dictionary:
	var wanted := {}
	if business == null:
		return wanted
	var definition := business.type_data()
	for item in business.orderable():
		var weight := definition.ingredient_usage(item) if definition != null else 1.0
		var minimum := roundi(float(business.auto_order_minimum) * weight)
		var target := roundi(float(business.auto_order_target) * weight)
		var held := business.storage_of(item.id)
		if held >= minimum:
			continue
		var gap := target - held - _incoming_to(business.business_id, item.id)
		if gap > 0:
			wanted[item.id] = gap
	return wanted


func _incoming_to(business_id: StringName, item_id: StringName) -> int:
	var total := 0
	for order in _transfers:
		if order.destination_id != business_id or not order.is_open():
			continue
		total += int(order.items.get(item_id, 0))
	return total


# --- The clock -----------------------------------------------------------

func _on_hour_passed(hour: int) -> void:
	advance_deliveries()
	run_due_routes(TimeManager.day_index, TimeManager.weekday, hour)


func _on_day_passed(_day_index: int) -> void:
	for warehouse in _warehouses:
		warehouse.reset_day()


## Moves every in-flight transfer along. Called hourly and by the visible
## delivery when it arrives, so both paths end at the same `complete_transfer`.
func advance_deliveries() -> int:
	var now := TimeManager.total_minutes
	var landed := 0
	for order in _transfers.duplicate():
		if not order.is_moving() or order.player_driven:
			continue
		if now < order.arrival_minute:
			continue
		complete_transfer(order)
		landed += 1
	_forget_settled()
	return landed


## Keeps the list to what is live plus a short tail of history, so a company
## running four routes a day does not accumulate a thousand delivered orders.
func _forget_settled() -> void:
	var settled: Array[TransferOrder] = []
	for order in _transfers:
		if not order.is_open():
			settled.append(order)
	while settled.size() > 30:
		var oldest: TransferOrder = settled.pop_front()
		_transfers.erase(oldest)


# --- Bottlenecks ---------------------------------------------------------

## Logistics problems, in the shape Phase O's bottleneck report already uses so
## they appear in the same list as a kitchen backlog rather than in a second
## warning system nobody reads.
func bottlenecks() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for warehouse in _warehouses:
		if warehouse.is_full():
			found.append(_issue(
				&"warehouse_full", "WAREHOUSE FULL", warehouse.display_name,
				"Nothing more will fit until stock goes out.", 0.7
			))
		elif warehouse.used() == 0:
			found.append(_issue(
				&"warehouse_empty", "WAREHOUSE EMPTY", warehouse.display_name,
				"There is nothing here to send anywhere.", 0.55
			))
	if has_warehouse():
		if CompanyFleet.company_vans().is_empty():
			found.append(_issue(
				&"no_vehicle", "NO COMPANY VAN", "Logistics",
				"A warehouse with nothing to deliver in is a store room.", 0.75
			))
		elif CompanyFleet.free_van() == null:
			found.append(_issue(
				&"vans_busy", "EVERY VAN IS OUT", "Logistics",
				"Shipments are waiting for one to come back.", 0.5
			))
		if CompanyFleet.drivers().is_empty():
			found.append(_issue(
				&"no_driver", "NO DELIVERY DRIVER", "Logistics",
				"Nobody is employed to drive the van.", 0.7
			))

	var waiting := 0
	var late := 0
	var now := TimeManager.total_minutes
	for order in _transfers:
		if order.is_reserved():
			waiting += 1
		elif order.is_moving() and now > order.arrival_minute + 120.0:
			late += 1
	if waiting >= 4:
		found.append(_issue(
			&"delivery_backlog", "DELIVERY BACKLOG", "Logistics",
			"%d shipments are loaded and waiting to go." % waiting,
			clampf(float(waiting) / 10.0, 0.0, 1.0)
		))
	if late > 0:
		found.append(_issue(
			&"late", "LATE SHIPMENTS", "Logistics",
			"%d are running behind." % late, 0.45
		))

	for business in BusinessManager.get_businesses():
		if not business.is_trading():
			continue
		var bare := 0
		for item in business.orderable():
			if business.storage_of(item.id) <= 0:
				bare += 1
		if bare > 0 and bare == business.orderable().size():
			found.append(_issue(
				&"stockout", "BRANCH STOCKOUT", business.business_name,
				"The store room is empty.", 0.8
			))
	return found


func _issue(
	id: StringName, headline: String, where: String, detail: String, severity: float
) -> Dictionary:
	return {
		"id": id, "headline": headline, "business_name": where,
		"detail": detail, "severity": clampf(severity, 0.0, 1.0), "business": null,
	}


# --- Reporting -----------------------------------------------------------

func summary() -> Dictionary:
	var stock := 0
	var capacity := 0
	var value := 0
	for warehouse in _warehouses:
		stock += warehouse.used()
		capacity += warehouse.capacity()
		value += warehouse.stock_value()
	var moving := 0
	var queued := 0
	for order in _transfers:
		if order.is_moving():
			moving += 1
		elif order.is_reserved():
			queued += 1
	return {
		"warehouses": _warehouses.size(),
		"stock_units": stock,
		"capacity": capacity,
		"fullness": float(stock) / float(maxi(capacity, 1)),
		"stock_value": value,
		"in_transit": moving,
		"queued": queued,
		"routes": _routes.size(),
		"vans": CompanyFleet.company_vans().size(),
		"drivers": CompanyFleet.drivers().size(),
		"units_distributed": units_distributed,
		"shipments_completed": shipments_completed,
		"late_shipments": late_shipments,
		"bulk_savings": bulk_savings,
		"delivery_costs": delivery_costs,
	}


func clear() -> void:
	_warehouses.clear()
	_transfers.clear()
	_routes.clear()
	_next_transfer = 1
	_next_route = 1
	funding_business_id = &""
	units_distributed = 0
	shipments_completed = 0
	late_shipments = 0
	bulk_savings = 0
	delivery_costs = 0


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var stored: Array = []
	for warehouse in _warehouses:
		stored.append(warehouse.to_dict())
	var moving: Array = []
	for order in _transfers:
		# Settled orders are history the save does not need; anything still
		# live is written exactly as it stands, ETA included, so a reload does
		# not deliver it twice or lose the cargo. §146.
		if order.is_open():
			moving.append(order.to_dict())
	var scheduled: Array = []
	for route in _routes:
		scheduled.append(route.to_dict())
	return {
		"warehouses": stored,
		"transfers": moving,
		"routes": scheduled,
		"next_transfer": _next_transfer,
		"next_route": _next_route,
		"funding_business": String(funding_business_id),
		"units_distributed": units_distributed,
		"shipments_completed": shipments_completed,
		"late_shipments": late_shipments,
		"bulk_savings": bulk_savings,
		"delivery_costs": delivery_costs,
	}


func load_state(state: Dictionary) -> void:
	clear()
	for entry in state.get("warehouses", []):
		_warehouses.append(WarehouseInstance.from_dict(entry))
	for entry in state.get("transfers", []):
		_transfers.append(TransferOrder.from_dict(entry))
	for entry in state.get("routes", []):
		_routes.append(DeliveryRoute.from_dict(entry))
	_next_transfer = int(state.get("next_transfer", _transfers.size() + 1))
	_next_route = int(state.get("next_route", _routes.size() + 1))
	funding_business_id = StringName(state.get("funding_business", ""))
	units_distributed = int(state.get("units_distributed", 0))
	shipments_completed = int(state.get("shipments_completed", 0))
	late_shipments = int(state.get("late_shipments", 0))
	bulk_savings = int(state.get("bulk_savings", 0))
	delivery_costs = int(state.get("delivery_costs", 0))
