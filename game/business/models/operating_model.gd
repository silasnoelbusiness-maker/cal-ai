class_name OperatingModel
extends RefCounted
## How a kind of business turns people into money.
##
## One of these per BusinessTypeData.ServiceModel, chosen by OperatingModels and
## shared by every branch of that kind. The class itself holds no state — a
## business is always passed in — which is what lets one instance serve nine
## shops and what makes the far simulation and the visible one provably the
## same code.
##
## This base class *is* the retail model: goods off a shelf, paid for at a till.
## The other four override the parts that differ and inherit the rest, which is
## the whole reason a restaurant did not turn BusinessManager into a switch.

## Cleanliness below which customers start to mind. Above it, a slightly
## grubby room costs nothing.
const CLEANLINESS_TOLERANCE := 55.0


## The staff role that stands between a customer and their money.
func serving_role() -> int:
	return EmployeeData.Role.CASHIER


## Every role that counts as serving. A coffee shop's barista rings up the cup
## they made, so both answer.
func serving_roles(business: BusinessInstance) -> Array[int]:
	var roles: Array[int] = [serving_role()]
	if business != null and business.serves_prepared_goods():
		roles.append(EmployeeData.Role.BARISTA)
	return roles


## Equipment role a server needs one of to work: a till, a pass, a bar.
func station_role() -> int:
	return EquipmentData.Role.CHECKOUT


## Everybody on shift who can serve, this hour.
func servers_on_shift(business: BusinessInstance, hour: int) -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	if business == null:
		return found
	for role in serving_roles(business):
		for worker in business.employees:
			if worker.role == role and worker.is_on_shift(hour) and not found.has(worker):
				found.append(worker)
	return found


## People who fit inside at once. The property sets the room; equipment sets
## what there is to do in it.
func customer_capacity(business: BusinessInstance) -> int:
	var definition := business.type_data() if business != null else null
	if definition == null:
		return 6
	var from_equipment := 0
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.holds_customers():
			from_equipment += data.customer_slots
	var total := definition.base_customer_capacity + from_equipment
	total = mini(total, definition.maximum_customer_capacity)
	# The room is the last word. A hundred chairs in a small unit is still a
	# small unit, and the property has always owned that number.
	return maxi(mini(total, business.customer_capacity()), 0)


## How many customers an hour of service can get through. Staff and stations
## both cap it, because one cashier with four tills is still one cashier.
func throughput_per_hour(business: BusinessInstance, hour: int) -> int:
	var servers := servers_on_shift(business, hour)
	if servers.is_empty():
		return 0
	var stations := maxi(business.count_of_role(station_role()), 1)
	var working := mini(servers.size(), stations)
	var total := 0
	for i in working:
		total += _server_throughput(business, servers[i])
	return maxi(total, 1)


## One member of staff, one hour.
func _server_throughput(business: BusinessInstance, worker: EmployeeData) -> int:
	var seconds := worker.checkout_seconds()
	if business.serves_prepared_goods():
		var menu := business.catalogue()
		if not menu.is_empty():
			seconds += business.preparation_seconds(menu[0], worker)
	seconds *= 1.0 - business.upgrade_magnitude(BusinessUpgrade.Effect.CHECKOUT_SPEED)
	return maxi(floori(3600.0 / maxf(seconds, 0.5)), 1)


## Whether the goods are behind the counter rather than on a shelf the customer
## can reach. A shop is false; a bar is true, and so is anything else where the
## stock never goes out on display.
func serves_from_storage() -> bool:
	return false


## Which way a customer physically walks through this kind of building. The
## visible customer switches on this rather than on the type id, so a new type
## picks an existing route by choosing a model.
func customer_route() -> StringName:
	return &"retail"


## Why somebody who arrived at a business already working flat out gave up. A
## queue in a shop, no free table in a restaurant, a full room in a venue.
func overflow_reason() -> StringName:
	return LostReason.QUEUE_TOO_LONG


## What the player's own decisions do to how many people turn up, over and
## above the type's curve: the size of a membership roll, how dear it is, how
## good the night is. One for a model whose demand is entirely the type's.
func demand_multiplier(_business: BusinessInstance) -> float:
	return 1.0


## Once a day, after the books are closed. Subscriptions are collected here.
func on_day(_business: BusinessInstance, _day_index: int) -> void:
	pass


## Anything this model needs beyond the type's equipment and stock lists, in
## words the dashboard can print. Checked on top of
## BusinessInstance.missing_requirements rather than instead of it.
func extra_requirements(_business: BusinessInstance) -> Array[String]:
	return []


## One customer, start to finish. The money moves inside here.
func serve_one(business: BusinessInstance, hour: int, rng: RandomNumberGenerator) -> ServiceResult:
	var servers := servers_on_shift(business, hour)
	if servers.is_empty():
		return ServiceResult.lost(LostReason.NO_STAFF, -0.35)

	var bought := 0
	var revenue := 0
	var wanted_something := false
	for i in CustomerDemand.basket_size(business, rng):
		var item := CustomerDemand.pick_item(business, rng)
		if item == null:
			break
		wanted_something = true
		if not CustomerDemand.will_buy(business, item, rng):
			continue
		var takings := business.record_sale(item, 1)
		if takings > 0:
			bought += 1
			revenue += takings

	if bought > 0:
		var worker := servers[rng.randi_range(0, servers.size() - 1)]
		worker.customers_served_today += 1
		worker.sales_processed_today += bought
		return ServiceResult.sale(revenue, bought, 0.12, satisfaction_score(business, 0.0))
	if not wanted_something:
		return ServiceResult.lost(LostReason.NO_STOCK, -0.25)
	return ServiceResult.lost(LostReason.TOO_EXPENSIVE, -0.25)


## What a served customer thought of it, 0-100. `wait_penalty` is however long
## they were kept, expressed as 0-1 of their patience.
func satisfaction_score(business: BusinessInstance, wait_penalty: float, quality: float = 70.0) -> float:
	var score := quality
	score -= clampf(wait_penalty, 0.0, 1.0) * 35.0
	var definition := business.type_data()
	if definition != null and definition.uses_cleanliness:
		var shortfall := maxf(CLEANLINESS_TOLERANCE - business.cleanliness, 0.0)
		score -= shortfall * 0.45
	return clampf(score, 0.0, 100.0)


## Cleanliness one visit costs, from the type's own rate plus whatever they
## touched on the way through.
func visit_soiling(business: BusinessInstance) -> float:
	var definition := business.type_data()
	if definition == null or not definition.uses_cleanliness:
		return 0.0
	var worst := 0.0
	for placed in business.equipment:
		var data := placed.data()
		if data != null:
			worst = maxf(worst, data.soiling_per_use)
	return worst


## What is actually holding this business back today, worst first. Each entry
## is {"id", "headline", "detail", "severity"} with severity 0-1.
func bottlenecks(business: BusinessInstance, hour: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if business == null:
		return found

	if servers_on_shift(business, hour).is_empty() and business.is_open():
		found.append(_issue(
			&"no_server", "NOBODY ON THE TILL",
			"The doors are open and there is no one to take money.", 1.0
		))
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var throughput := float(throughput_per_hour(business, hour))
	if throughput > 0.0 and demand > throughput * 1.1:
		found.append(_issue(
			&"checkout", "CHECKOUT BOTTLENECK",
			"About %d people an hour want serving and %d can be." % [
				roundi(demand), roundi(throughput)
			],
			clampf((demand - throughput) / maxf(demand, 1.0), 0.0, 1.0)
		))
	var bare := _bare_lines(business)
	if bare > 0:
		found.append(_issue(
			&"low_stock", "LOW STOCK",
			"%d of the range cannot be sold." % bare,
			clampf(float(bare) / float(maxi(business.catalogue().size(), 1)), 0.0, 1.0)
		))
	var definition := business.type_data()
	if definition != null and definition.uses_cleanliness and business.cleanliness < CLEANLINESS_TOLERANCE:
		found.append(_issue(
			&"dirty", "THE PLACE NEEDS CLEANING",
			"Cleanliness is down to %d%%." % roundi(business.cleanliness),
			clampf((CLEANLINESS_TOLERANCE - business.cleanliness) / CLEANLINESS_TOLERANCE, 0.0, 1.0)
		))
	return found


func _bare_lines(business: BusinessInstance) -> int:
	var bare := 0
	for item in business.catalogue():
		if business.available_units(item) <= 0:
			bare += 1
	return bare


func _issue(id: StringName, headline: String, detail: String, severity: float) -> Dictionary:
	return {
		"id": id, "headline": headline, "detail": detail,
		"severity": clampf(severity, 0.0, 1.0),
	}


## How busy each role was kept, as role -> 0-1. Read by the operations tab so
## the player can see whether the next hire is a cook or a server.
func role_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var servers := servers_on_shift(business, hour)
	if servers.is_empty():
		return {}
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var throughput := maxf(float(throughput_per_hour(business, hour)), 1.0)
	return {serving_role(): clampf(demand / throughput, 0.0, 1.0)}


## Equipment kept busy, as equipment id -> 0-1. Empty for a type whose fittings
## nobody queues for.
func equipment_utilisation(_business: BusinessInstance, _hour: int) -> Dictionary:
	return {}
