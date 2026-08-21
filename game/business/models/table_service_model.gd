class_name TableServiceModel
extends OperatingModel
## Seated, ordered, cooked, carried, paid.
##
## The restaurant, and the first business in the game with two separate
## bottlenecks: the kitchen and the floor. A cook with no server has meals
## nobody carries; a server with no cook has orders nobody makes. Which of the
## two is short is the thing the player has to read off the dashboard, and the
## reason a restaurant is not a shop with tables.

## Covers one seat turns over in an hour. A seat is not a customer per hour —
## people sit for a while — and this is what stops four tables serving forty.
const SEAT_TURNS_PER_HOUR := 1.15
## Seconds of a server's time one cover costs: taking the order, carrying the
## plate, taking the money.
const SERVER_SECONDS_PER_COVER := 210.0


func customer_route() -> StringName:
	return &"table"


func serving_role() -> int:
	return EmployeeData.Role.SERVER


func serving_roles(_business: BusinessInstance) -> Array[int]:
	return [EmployeeData.Role.SERVER]


func station_role() -> int:
	return EquipmentData.Role.PASS


func cooks_on_shift(business: BusinessInstance, hour: int) -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for worker in business.employees:
		if worker.role == EmployeeData.Role.COOK and worker.is_on_shift(hour):
			found.append(worker)
	return found


func seats(business: BusinessInstance) -> int:
	var total := 0
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.role == EquipmentData.Role.SEATING:
			total += maxi(data.customer_slots, 1)
	return total


func customer_capacity(business: BusinessInstance) -> int:
	# A restaurant's capacity is its seats and nothing else. Standing customers
	# are not customers.
	return maxi(mini(seats(business), business.customer_capacity()), 0)


## The smallest of three numbers: what the kitchen can cook, what the floor can
## carry, and what the room can seat. Whichever it is, is the bottleneck.
func throughput_per_hour(business: BusinessInstance, hour: int) -> int:
	return maxi(mini(
		kitchen_throughput(business, hour),
		mini(floor_throughput(business, hour), seat_throughput(business))
	), 0)


func kitchen_throughput(business: BusinessInstance, hour: int) -> int:
	var cooks := cooks_on_shift(business, hour)
	if cooks.is_empty():
		return 0
	var stations := business.count_of_role(EquipmentData.Role.COOK_STATION)
	if stations <= 0:
		return 0
	var working := mini(cooks.size(), stations)
	var total := 0.0
	for i in working:
		total += 3600.0 / maxf(_prep_seconds(business, cooks[i]), 8.0)
	return maxi(floori(total), 0)


func floor_throughput(business: BusinessInstance, hour: int) -> int:
	var servers := servers_on_shift(business, hour)
	if servers.is_empty():
		return 0
	var total := 0.0
	for worker in servers:
		total += 3600.0 / maxf(SERVER_SECONDS_PER_COVER * worker.service_scale(), 20.0)
	return maxi(floori(total), 0)


func seat_throughput(business: BusinessInstance) -> int:
	return maxi(floori(float(seats(business)) * SEAT_TURNS_PER_HOUR), 0)


## Average seconds a dish takes this cook, across the menu.
func _prep_seconds(business: BusinessInstance, cook: EmployeeData) -> float:
	var menu := business.catalogue()
	if menu.is_empty():
		return 90.0
	var total := 0.0
	for item in menu:
		total += business.preparation_seconds(item, cook)
	# A better kitchen is a quicker one, but only a little: the cook is the
	# thing being paid for.
	var fit := 1.0 - 0.06 * float(mini(business.count_of_role(EquipmentData.Role.PREP), 3))
	return maxf(total / float(menu.size()) * fit, 8.0)


func overflow_reason() -> StringName:
	return LostReason.NO_SEATING


func extra_requirements(business: BusinessInstance) -> Array[String]:
	var missing: Array[String] = []
	if seats(business) <= 0:
		missing.append("Seating")
	return missing


## One cover. The order is placed, the kitchen makes it out of real ingredients,
## the server carries it, and only then is anything charged for.
func serve_one(business: BusinessInstance, hour: int, rng: RandomNumberGenerator) -> ServiceResult:
	if seats(business) <= 0:
		return ServiceResult.lost(LostReason.NO_SEATING, -0.3)
	var servers := servers_on_shift(business, hour)
	if servers.is_empty():
		return ServiceResult.lost(LostReason.NO_STAFF, -0.4)
	var cooks := cooks_on_shift(business, hour)
	if cooks.is_empty():
		# The doors are open, somebody sat down, and nothing came out of the
		# kitchen. They do not pay for that.
		return ServiceResult.lost(LostReason.SERVICE_TOO_SLOW, -0.5)

	var dish := CustomerDemand.pick_item(business, rng)
	if dish == null:
		return ServiceResult.lost(LostReason.NO_STOCK, -0.35)
	if not CustomerDemand.will_buy(business, dish, rng):
		return ServiceResult.lost(LostReason.TOO_EXPENSIVE, -0.2)

	var revenue := business.record_sale(dish, 1)
	if revenue <= 0:
		return ServiceResult.lost(LostReason.NO_STOCK, -0.35)

	var cook: EmployeeData = cooks[rng.randi_range(0, cooks.size() - 1)]
	var server: EmployeeData = servers[rng.randi_range(0, servers.size() - 1)]
	cook.customers_served_today += 1
	server.customers_served_today += 1
	server.sales_processed_today += 1

	var wait := _wait_penalty(business, hour)
	var quality := food_quality(business, cook)
	return ServiceResult.sale(revenue, 1, 0.14, satisfaction_score(business, wait, quality))


## How far behind the kitchen is running, 0-1. Demand over what the kitchen can
## actually produce is the whole of it.
func _wait_penalty(business: BusinessInstance, hour: int) -> float:
	var kitchen := float(kitchen_throughput(business, hour))
	if kitchen <= 0.0:
		return 1.0
	var demand := CustomerDemand.customers_per_hour(business, hour)
	return clampf((demand - kitchen) / maxf(kitchen, 1.0), 0.0, 1.0)


## Cook, kit and nothing else. Deliberately not a culinary simulation.
func food_quality(business: BusinessInstance, cook: EmployeeData) -> float:
	var skill := float(cook.skill_cooking) if cook != null else 30.0
	var best_tier := 1
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.role == EquipmentData.Role.COOK_STATION:
			best_tier = maxi(best_tier, data.quality_tier)
	return clampf(lerpf(45.0, 92.0, skill / 100.0) + float(best_tier - 1) * 4.0, 0.0, 100.0)


func bottlenecks(business: BusinessInstance, hour: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	# The general "service cannot keep up" line is dropped: this model says
	# which of the kitchen, the floor and the tables is short, and a fourth
	# entry saying "one of those three" underneath them is noise.
	for issue in super(business, hour):
		if StringName(issue["id"]) != &"checkout":
			found.append(issue)
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var kitchen := float(kitchen_throughput(business, hour))
	var floor_rate := float(floor_throughput(business, hour))
	var seat_rate := float(seat_throughput(business))

	if kitchen <= 0.0 and business.is_open():
		found.append(_issue(
			&"no_cook", "NO COOK ON SHIFT",
			"Orders are going into a kitchen with nobody in it.", 1.0
		))
	elif demand > kitchen * 1.1:
		found.append(_issue(
			&"kitchen", "KITCHEN BACKLOG",
			"About %d covers an hour want cooking and the kitchen makes %d." % [
				roundi(demand), roundi(kitchen)
			],
			clampf((demand - kitchen) / maxf(demand, 1.0), 0.0, 1.0)
		))
	if seat_rate > 0.0 and demand > seat_rate * 1.1:
		found.append(_issue(
			&"seating", "NOT ENOUGH SEATING",
			"%d covers an hour turned away for want of a table." % roundi(demand - seat_rate),
			clampf((demand - seat_rate) / maxf(demand, 1.0), 0.0, 1.0)
		))
	if floor_rate > 0.0 and demand > floor_rate * 1.1:
		found.append(_issue(
			&"servers", "NOT ENOUGH SERVERS",
			"The floor can carry %d covers an hour." % roundi(floor_rate),
			clampf((demand - floor_rate) / maxf(demand, 1.0), 0.0, 1.0)
		))
	return found


func role_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var use := {}
	var kitchen := float(kitchen_throughput(business, hour))
	if kitchen > 0.0:
		use[EmployeeData.Role.COOK] = clampf(demand / kitchen, 0.0, 1.0)
	var floor_rate := float(floor_throughput(business, hour))
	if floor_rate > 0.0:
		use[EmployeeData.Role.SERVER] = clampf(demand / floor_rate, 0.0, 1.0)
	return use


func equipment_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var seat_rate := float(seat_throughput(business))
	if seat_rate <= 0.0:
		return {}
	var demand := CustomerDemand.customers_per_hour(business, hour)
	return {&"tables": clampf(demand / seat_rate, 0.0, 1.0)}
