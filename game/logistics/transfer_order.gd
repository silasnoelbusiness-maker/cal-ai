class_name TransferOrder
extends RefCounted
## Goods moving from one place the company owns to another.
##
## This is both the request and the shipment. The brief names them separately
## and there is a case for two objects, but a shipment that is a *copy* of an
## order is exactly how cargo gets counted twice — one crate on the order, one
## on the shipment, and a failure path that returns both. So there is one
## object, it owns its cargo outright once dispatched, and the only question
## ever asked is what state it is in.
##
## The lifecycle is the whole safety argument:
##   REQUESTED  — somebody wants stock. Nothing has moved or been promised.
##   QUEUED     — cargo is reserved at the source. It cannot be sold twice.
##   READY      — a van and a driver are on it.
##   IN_TRANSIT — the cargo has *left* the source and belongs to this order.
##   DELIVERED  — the destination has it. The order is finished.
##   FAILED     — something went wrong; the cargo goes back where it came from.
##   CANCELLED  — called off before dispatch; the reservation is released.
##
## At no point do the goods exist in two places, and at no point can they cease
## to exist. §20 is emphatic about that and it is the easiest thing to get wrong.

enum Status { REQUESTED, QUEUED, READY, IN_TRANSIT, DELIVERED, FAILED, CANCELLED }
enum Place { WAREHOUSE, BUSINESS }
enum Priority { LOW, NORMAL, HIGH, CRITICAL }

const STATUS_NAMES := {
	Status.REQUESTED: "Requested",
	Status.QUEUED: "Reserved",
	Status.READY: "Ready to go",
	Status.IN_TRANSIT: "In transit",
	Status.DELIVERED: "Delivered",
	Status.FAILED: "Failed",
	Status.CANCELLED: "Cancelled",
}

const PRIORITY_NAMES := {
	Priority.LOW: "Low", Priority.NORMAL: "Normal",
	Priority.HIGH: "High", Priority.CRITICAL: "Critical",
}

var transfer_id: StringName = &""
var source_kind: Place = Place.WAREHOUSE
var source_id: StringName = &""
var destination_kind: Place = Place.BUSINESS
var destination_id: StringName = &""
## item id -> units. Once IN_TRANSIT this is the cargo itself and exists
## nowhere else in the game.
var items: Dictionary = {}
var created_minute: float = 0.0
var dispatch_minute: float = 0.0
var arrival_minute: float = 0.0
var assigned_vehicle_id: StringName = &""
var assigned_driver_id: StringName = &""
var status: Status = Status.REQUESTED
var priority: Priority = Priority.NORMAL
## Set when the player is driving it themselves, so no wage or van cost applies
## and the arrival is decided by them reaching the door rather than by a clock.
var player_driven: bool = false
## What went wrong, for the screen to show.
var note: String = ""


static func make(
	transfer_id: StringName, source_kind: Place, source_id: StringName,
	destination_kind: Place, destination_id: StringName, now: float
) -> TransferOrder:
	var order := TransferOrder.new()
	order.transfer_id = transfer_id
	order.source_kind = source_kind
	order.source_id = source_id
	order.destination_kind = destination_kind
	order.destination_id = destination_id
	order.created_minute = now
	return order


func unit_count() -> int:
	var total := 0
	for quantity in items.values():
		total += int(quantity)
	return total


func is_open() -> bool:
	return status == Status.REQUESTED or status == Status.QUEUED \
		or status == Status.READY or status == Status.IN_TRANSIT


## Whether the cargo is currently spoken for at the source but has not left.
## This is the window in which cancelling is safe and free.
func is_reserved() -> bool:
	return status == Status.QUEUED or status == Status.READY


func is_moving() -> bool:
	return status == Status.IN_TRANSIT


## §135: once the van has gone, it has gone. Cancelling mid-journey would mean
## deciding where the cargo lands, and "wherever it started" is a lie once the
## van is halfway across the city.
func can_cancel() -> bool:
	return status == Status.REQUESTED or status == Status.QUEUED or status == Status.READY


func status_name() -> String:
	return String(STATUS_NAMES.get(status, "Unknown"))


func priority_name() -> String:
	return String(PRIORITY_NAMES.get(priority, "Normal"))


func minutes_remaining(now: float) -> float:
	return maxf(arrival_minute - now, 0.0)


func eta_text(now: float) -> String:
	if status == Status.DELIVERED:
		return "Delivered"
	if not is_moving():
		return status_name()
	var minutes := minutes_remaining(now)
	if minutes < 1.0:
		return "Arriving"
	if minutes < 60.0:
		return "%d min" % roundi(minutes)
	return "%.1f hours" % (minutes / 60.0)


func cargo_text() -> String:
	var names: Array[String] = []
	for id: StringName in items:
		var item := ItemCatalogue.by_id(id)
		names.append("%s x%d" % [
			item.display_name if item != null else String(id), int(items[id])
		])
	if names.is_empty():
		return "Empty"
	if names.size() == 1:
		return names[0]
	return "%s +%d more" % [names[0], names.size() - 1]


func to_dict() -> Dictionary:
	var cargo := {}
	for id: StringName in items:
		cargo[String(id)] = int(items[id])
	return {
		"id": String(transfer_id),
		"source_kind": int(source_kind),
		"source": String(source_id),
		"destination_kind": int(destination_kind),
		"destination": String(destination_id),
		"items": cargo,
		"created": created_minute,
		"dispatch": dispatch_minute,
		"arrival": arrival_minute,
		"vehicle": String(assigned_vehicle_id),
		"driver": String(assigned_driver_id),
		"status": int(status),
		"priority": int(priority),
		"player_driven": player_driven,
		"note": note,
	}


static func from_dict(state: Dictionary) -> TransferOrder:
	var order := TransferOrder.new()
	order.transfer_id = StringName(state.get("id", ""))
	order.source_kind = int(state.get("source_kind", 0)) as Place
	order.source_id = StringName(state.get("source", ""))
	order.destination_kind = int(state.get("destination_kind", 1)) as Place
	order.destination_id = StringName(state.get("destination", ""))
	for key in state.get("items", {}):
		order.items[StringName(key)] = int(state["items"][key])
	order.created_minute = float(state.get("created", 0.0))
	order.dispatch_minute = float(state.get("dispatch", 0.0))
	order.arrival_minute = float(state.get("arrival", 0.0))
	order.assigned_vehicle_id = StringName(state.get("vehicle", ""))
	order.assigned_driver_id = StringName(state.get("driver", ""))
	order.status = int(state.get("status", 0)) as Status
	order.priority = int(state.get("priority", 1)) as Priority
	order.player_driven = bool(state.get("player_driven", false))
	order.note = String(state.get("note", ""))
	return order
