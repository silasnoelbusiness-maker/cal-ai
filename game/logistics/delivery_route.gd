class_name DeliveryRoute
extends RefCounted
## A van, a driver, and a list of shops to call at.
##
## The point of a route is that the player stops thinking about individual
## transfers. Once a route exists, the branches on it get topped up to their own
## targets on the days it runs, and the only decisions left are which shops are
## on it and when it leaves.
##
## Deliberately not an optimiser. It visits its stops in the order they are
## listed, because a route the player arranged is one they understand, and §34
## is explicit that this is not the phase for logistics planning software.

var route_id: StringName = &""
var display_name: String = "Route"
var warehouse_id: StringName = &""
var vehicle_id: StringName = &""
var driver_id: StringName = &""
## Business ids, called at in this order.
var stop_business_ids: Array[StringName] = []
var departure_hour: int = 8
## Weekday indices it runs, 0 for Monday. Empty means every day.
var days_of_week: Array[int] = []
var priority: TransferOrder.Priority = TransferOrder.Priority.NORMAL
var enabled: bool = true
## Day index it last went out, so a route runs once per day and not once per
## hourly tick that happens to land on its departure hour.
var last_run_day: int = -1


static func make(route_id: StringName, warehouse_id: StringName) -> DeliveryRoute:
	var route := DeliveryRoute.new()
	route.route_id = route_id
	route.warehouse_id = warehouse_id
	route.display_name = "Route %s" % String(route_id).to_upper()
	return route


func runs_on(weekday: int) -> bool:
	return days_of_week.is_empty() or days_of_week.has(weekday)


func is_due(day: int, weekday: int, hour: int) -> bool:
	if not enabled or stop_business_ids.is_empty():
		return false
	if last_run_day == day:
		return false
	return runs_on(weekday) and hour >= departure_hour


func stop_count() -> int:
	return stop_business_ids.size()


func add_stop(business_id: StringName) -> bool:
	if business_id == &"" or stop_business_ids.has(business_id):
		return false
	stop_business_ids.append(business_id)
	return true


func remove_stop(business_id: StringName) -> bool:
	var index := stop_business_ids.find(business_id)
	if index < 0:
		return false
	stop_business_ids.remove_at(index)
	return true


func days_text() -> String:
	if days_of_week.is_empty():
		return "Every day"
	var names: Array[String] = []
	for day in days_of_week:
		names.append(TimeManager.DAY_NAMES[clampi(day, 0, 6)].substr(0, 3).capitalize())
	return ", ".join(names)


func schedule_text() -> String:
	return "%02d:00  ·  %s" % [departure_hour, days_text()]


func to_dict() -> Dictionary:
	var stops: Array = []
	for id in stop_business_ids:
		stops.append(String(id))
	return {
		"id": String(route_id),
		"name": display_name,
		"warehouse": String(warehouse_id),
		"vehicle": String(vehicle_id),
		"driver": String(driver_id),
		"stops": stops,
		"departure_hour": departure_hour,
		"days": days_of_week.duplicate(),
		"priority": int(priority),
		"enabled": enabled,
		"last_run_day": last_run_day,
	}


static func from_dict(state: Dictionary) -> DeliveryRoute:
	var route := DeliveryRoute.new()
	route.route_id = StringName(state.get("id", ""))
	route.display_name = String(state.get("name", "Route"))
	route.warehouse_id = StringName(state.get("warehouse", ""))
	route.vehicle_id = StringName(state.get("vehicle", ""))
	route.driver_id = StringName(state.get("driver", ""))
	for id in state.get("stops", []):
		route.stop_business_ids.append(StringName(id))
	route.departure_hour = int(state.get("departure_hour", 8))
	for day in state.get("days", []):
		route.days_of_week.append(int(day))
	route.priority = int(state.get("priority", 1)) as TransferOrder.Priority
	route.enabled = bool(state.get("enabled", true))
	route.last_run_day = int(state.get("last_run_day", -1))
	return route
