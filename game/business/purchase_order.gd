class_name PurchaseOrder
extends RefCounted
## Stock that has been paid for and is on its way.
##
## Phase H handed goods over the moment they were ordered. They now take a few
## hours to arrive, which is what makes running out of something a mistake with
## consequences rather than an inconvenience — and what gives a manager's
## automatic ordering a reason to reorder before the shelves are bare.

enum Status { PLACED, IN_TRANSIT, DELIVERED }

var order_id: StringName = &""
var business_id: StringName = &""
var supplier_id: StringName = &"citywide"
## item id -> units.
var items: Dictionary = {}
var total_cost: int = 0
## In-game minutes.
var placed_at: float = 0.0
var arrives_at: float = 0.0
var status: Status = Status.PLACED
## Set when a manager placed it rather than the player.
var automatic: bool = false


func unit_count() -> int:
	var total := 0
	for quantity in items.values():
		total += int(quantity)
	return total


## What is on the lorry, in words. Several lines collapse to a count, because a
## purchasing list has one row per order and not one per crate.
func summary() -> String:
	var names: Array[String] = []
	for id: StringName in items:
		var item := ItemCatalogue.by_id(id)
		names.append("%s x%d" % [
			item.display_name if item != null else String(id), int(items[id])
		])
	if names.is_empty():
		return "Empty order"
	if names.size() == 1:
		return names[0]
	return "%s +%d more" % [names[0], names.size() - 1]


func is_outstanding() -> bool:
	return status != Status.DELIVERED


## Halfway through the trip it stops being paperwork and starts being a van.
func refresh_status(now_minutes: float) -> void:
	if status == Status.DELIVERED:
		return
	if now_minutes >= arrives_at:
		return
	var halfway := placed_at + (arrives_at - placed_at) * 0.5
	if now_minutes >= halfway:
		status = Status.IN_TRANSIT


func has_arrived(now_minutes: float) -> bool:
	return status != Status.DELIVERED and now_minutes >= arrives_at


func minutes_remaining(now_minutes: float) -> float:
	return maxf(arrives_at - now_minutes, 0.0)


func arrival_text() -> String:
	var minute_of_day := int(arrives_at) % 1440
	return "%02d:%02d" % [minute_of_day / 60, minute_of_day % 60]


func status_text() -> String:
	match status:
		Status.IN_TRANSIT:
			return "IN TRANSIT"
		Status.DELIVERED:
			return "DELIVERED"
		_:
			return "PLACED"


func to_dict() -> Dictionary:
	var stored := {}
	for key in items:
		stored[String(key)] = int(items[key])
	return {
		"id": String(order_id),
		"business": String(business_id),
		"supplier": String(supplier_id),
		"items": stored,
		"cost": total_cost,
		"placed_at": placed_at,
		"arrives_at": arrives_at,
		"status": int(status),
		"automatic": automatic,
	}


static func from_dict(state: Dictionary) -> PurchaseOrder:
	var order := PurchaseOrder.new()
	order.order_id = StringName(state.get("id", ""))
	order.business_id = StringName(state.get("business", ""))
	order.supplier_id = StringName(state.get("supplier", "citywide"))
	for key in state.get("items", {}):
		order.items[StringName(key)] = int(state["items"][key])
	order.total_cost = int(state.get("cost", 0))
	order.placed_at = float(state.get("placed_at", 0.0))
	order.arrives_at = float(state.get("arrives_at", 0.0))
	order.status = int(state.get("status", 0)) as Status
	order.automatic = bool(state.get("automatic", false))
	return order
