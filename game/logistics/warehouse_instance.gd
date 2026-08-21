class_name WarehouseInstance
extends RefCounted
## A warehouse the player holds, and what is in it.
##
## Its own inventory, deliberately separate from a branch's store room, the
## player's pockets and the cupboard at home. What makes it a warehouse rather
## than a very large store room is that nothing is *sold* from here: stock
## arrives in bulk and leaves on a van, and the only way it becomes revenue is
## by reaching a branch that sells it.
##
## Reservation is the part worth being careful about. A transfer that has been
## prepared but not yet dispatched has already spoken for its cargo, and the
## same crate must not also be promised to a second branch — so `available` is
## what the warehouse holds *less* what is spoken for, and every caller asks
## that rather than the raw count.

var warehouse_id: StringName = &""
var property_id: StringName = &""
var display_name: String = "Warehouse"
## item id -> units actually standing on the floor.
var stock: Dictionary = {}
## item id -> units promised to a transfer that has not left yet. Always a
## subset of `stock`.
var reserved: Dictionary = {}
## Racks bought and placed, each adding capacity.
var racks: int = 0
var leased_on_day: int = 0
## Set when the player bought the building rather than renting it, so the
## logistics screen can say which and the rent run can skip it.
var owned_outright: bool = false

## Units the warehouse can get out of the door in a day. Without this a company
## with one van could dispatch its entire stock every morning.
const DISPATCH_PER_DAY := 900
var dispatched_today: int = 0


static func make(warehouse_id: StringName, day: int) -> WarehouseInstance:
	var entry := WarehouseData.by_id(warehouse_id)
	var warehouse := WarehouseInstance.new()
	warehouse.warehouse_id = warehouse_id
	warehouse.property_id = StringName(entry[1]) if entry.size() > 1 else &""
	warehouse.display_name = WarehouseData.display_name(warehouse_id)
	warehouse.leased_on_day = day
	return warehouse


# --- Capacity ------------------------------------------------------------

func capacity() -> int:
	return WarehouseData.base_capacity(warehouse_id) + racks * RACK_CAPACITY


## What one rack adds. A warehouse is mostly racking, so this is the number
## that actually decides how much the place holds.
const RACK_CAPACITY := 120


func used() -> int:
	var total := 0
	for quantity in stock.values():
		total += int(quantity)
	return total


func room_left() -> int:
	return maxi(capacity() - used(), 0)


func fullness() -> float:
	var limit := capacity()
	return clampf(float(used()) / float(maxi(limit, 1)), 0.0, 1.0)


func is_full() -> bool:
	return room_left() <= 0


func can_add_racks() -> bool:
	return racks < WarehouseData.rack_limit(warehouse_id)


# --- Stock ---------------------------------------------------------------

func held(item_id: StringName) -> int:
	return int(stock.get(item_id, 0))


func reserved_of(item_id: StringName) -> int:
	return int(reserved.get(item_id, 0))


## What may actually be promised to something: what is here, less what is
## already spoken for.
func available(item_id: StringName) -> int:
	return maxi(held(item_id) - reserved_of(item_id), 0)


## Puts goods in. Returns how many fitted, which is not always how many were
## offered — a full warehouse is a real constraint and the caller has to cope.
func add(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var taken := mini(quantity, room_left())
	if taken <= 0:
		return 0
	stock[item_id] = held(item_id) + taken
	return taken


## Takes goods out for good. Only ever called once a shipment is really going.
func take(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var moved := mini(quantity, held(item_id))
	if moved <= 0:
		return 0
	stock[item_id] = held(item_id) - moved
	if int(stock[item_id]) <= 0:
		stock.erase(item_id)
	# Whatever left was presumably reserved for the thing that took it.
	release(item_id, moved)
	return moved


## Speaks for stock without moving it. Returns how much it could promise.
func reserve(item_id: StringName, quantity: int) -> int:
	if quantity <= 0:
		return 0
	var promised := mini(quantity, available(item_id))
	if promised <= 0:
		return 0
	reserved[item_id] = reserved_of(item_id) + promised
	return promised


func release(item_id: StringName, quantity: int) -> void:
	if quantity <= 0:
		return
	var left := reserved_of(item_id) - quantity
	if left <= 0:
		reserved.erase(item_id)
	else:
		reserved[item_id] = left


func lines() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: StringName in stock:
		var item := ItemCatalogue.by_id(id)
		rows.append({
			"item_id": id,
			"name": item.display_name if item != null else String(id),
			"held": held(id),
			"reserved": reserved_of(id),
			"available": available(id),
		})
	rows.sort_custom(func(a, b): return int(a["held"]) > int(b["held"]))
	return rows


## Value of everything standing in it, at what it cost. Feeds company value.
func stock_value() -> int:
	var total := 0
	for id: StringName in stock:
		var item := ItemCatalogue.by_id(id)
		if item != null:
			total += item.get_wholesale_cost() * held(id)
	return total


func dispatch_room() -> int:
	return maxi(DISPATCH_PER_DAY - dispatched_today, 0)


func note_dispatch(units: int) -> void:
	dispatched_today += maxi(units, 0)


func reset_day() -> void:
	dispatched_today = 0


func to_dict() -> Dictionary:
	var held_out := {}
	for id: StringName in stock:
		held_out[String(id)] = int(stock[id])
	var reserved_out := {}
	for id: StringName in reserved:
		reserved_out[String(id)] = int(reserved[id])
	return {
		"id": String(warehouse_id),
		"property": String(property_id),
		"name": display_name,
		"stock": held_out,
		"reserved": reserved_out,
		"racks": racks,
		"leased_on_day": leased_on_day,
		"owned_outright": owned_outright,
		"dispatched_today": dispatched_today,
	}


static func from_dict(state: Dictionary) -> WarehouseInstance:
	var warehouse := WarehouseInstance.new()
	warehouse.warehouse_id = StringName(state.get("id", ""))
	warehouse.property_id = StringName(state.get("property", ""))
	warehouse.display_name = String(state.get("name", "Warehouse"))
	for key in state.get("stock", {}):
		warehouse.stock[StringName(key)] = int(state["stock"][key])
	for key in state.get("reserved", {}):
		warehouse.reserved[StringName(key)] = int(state["reserved"][key])
	warehouse.racks = int(state.get("racks", 0))
	warehouse.leased_on_day = int(state.get("leased_on_day", 0))
	warehouse.owned_outright = bool(state.get("owned_outright", false))
	warehouse.dispatched_today = int(state.get("dispatched_today", 0))
	return warehouse
