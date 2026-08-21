class_name VenueModel
extends OperatingModel
## Entry, then drinks, with the night doing the work.
##
## The nightclub. Its whole character is that the same room is worthless at two
## in the afternoon and rammed at midnight, which is the demand curve doing its
## job rather than a special case. What the player buys is capacity; what they
## staff is the door and the bar; what they are actually selling is the room
## being worth queueing for, and that is the entertainer.

## What the door is allowed to hold without anybody working it. A venue with no
## security does not close — it runs at a fraction, which is the operational
## cost of not paying for it.
const UNSECURED_CAPACITY_FRACTION := 0.55
## Drinks one customer buys across a night, inclusive.
const DRINKS_RANGE := Vector2i(1, 3)


func serves_from_storage() -> bool:
	return true


func customer_route() -> StringName:
	return &"venue"


func serving_role() -> int:
	return EmployeeData.Role.BARTENDER


func serving_roles(_business: BusinessInstance) -> Array[int]:
	return [EmployeeData.Role.BARTENDER]


func station_role() -> int:
	return EquipmentData.Role.BAR


func security_on_shift(business: BusinessInstance, hour: int) -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for worker in business.employees:
		if worker.role == EmployeeData.Role.SECURITY and worker.is_on_shift(hour):
			found.append(worker)
	return found


func entertainer_on_shift(business: BusinessInstance, hour: int) -> EmployeeData:
	return business.rostered(EmployeeData.Role.ENTERTAINER, hour)


## Everything the room can hold: the floor it is standing on and the seats
## round the edge.
func venue_capacity(business: BusinessInstance) -> int:
	var definition := business.type_data()
	var total := definition.base_customer_capacity if definition != null else 0
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.holds_customers():
			total += maxi(data.customer_slots, 1)
	if definition != null:
		total = mini(total, definition.maximum_customer_capacity)
	return maxi(total, 0)


## The number the door actually works to. Unsecured, it is a fraction of the
## room, because letting a full house in with nobody watching it is the thing
## the licence does not allow.
func customer_capacity(business: BusinessInstance) -> int:
	var room := mini(venue_capacity(business), business.customer_capacity())
	if security_on_shift(business, TimeManager.hour).is_empty():
		room = floori(float(room) * UNSECURED_CAPACITY_FRACTION)
	return maxi(room, 0)


## The bar is the throttle. A full room that cannot get a drink is a bad night.
func throughput_per_hour(business: BusinessInstance, hour: int) -> int:
	var bar := servers_on_shift(business, hour)
	if bar.is_empty():
		return 0
	var definition := business.type_data()
	var per_hour := definition.served_per_staff_hour if definition != null else 20.0
	var stations := maxi(business.count_of_role(EquipmentData.Role.BAR), 1)
	var working := mini(bar.size(), stations)
	var total := 0.0
	for i in working:
		total += per_hour / maxf(bar[i].service_scale(), 0.3)
	# Nobody can be served faster than they can get through the door.
	return maxi(mini(floori(total), customer_capacity(business) * 2), 0)


func overflow_reason() -> StringName:
	return LostReason.BUSINESS_FULL


func extra_requirements(business: BusinessInstance) -> Array[String]:
	var missing: Array[String] = []
	if venue_capacity(business) <= 0:
		missing.append("Somewhere to stand")
	if business.count_of_role(EquipmentData.Role.BAR) <= 0:
		missing.append("Bar")
	# A venue with an empty cellar has nothing to sell. Said in the same words
	# a kitchen with no ingredients uses, because it is the same problem.
	var stocked := false
	for item in business.catalogue():
		if business.available_units(item) > 0:
			stocked = true
			break
	if not stocked:
		missing.append("Stock behind the bar")
	return missing


## 0-100. A booth with nobody in it is a room with music nobody chose.
func entertainment_quality(business: BusinessInstance, hour: int) -> float:
	var booths := business.count_of_role(EquipmentData.Role.DJ_BOOTH)
	if booths <= 0:
		return 25.0
	var dj := entertainer_on_shift(business, hour)
	if dj == null:
		return 42.0
	var rig := mini(business.count_of_role(EquipmentData.Role.LIGHTING), 4)
	return clampf(lerpf(50.0, 94.0, float(dj.skill_entertainment) / 100.0) + float(rig) * 2.5, 0.0, 100.0)


## A venue people want to be in fills up; one they do not, does not.
func demand_multiplier(business: BusinessInstance) -> float:
	var pull := entertainment_quality(business, TimeManager.hour) / 60.0
	return clampf(0.45 + pull * 0.75, 0.35, 1.6)


## One person through the door: they pay to get in, then they drink.
func serve_one(business: BusinessInstance, hour: int, rng: RandomNumberGenerator) -> ServiceResult:
	var bar := servers_on_shift(business, hour)
	if bar.is_empty():
		return ServiceResult.lost(LostReason.NO_STAFF, -0.35)
	if customer_capacity(business) <= 0:
		return ServiceResult.lost(LostReason.BUSINESS_FULL, -0.3)

	var revenue := 0
	var units := 0
	if business.entry_fee > 0:
		revenue += business.record_service_sale(business.entry_fee, "Entry", 0)

	var wanted := rng.randi_range(DRINKS_RANGE.x, DRINKS_RANGE.y)
	var served_any := false
	for i in wanted:
		var drink := CustomerDemand.pick_item(business, rng)
		if drink == null:
			break
		served_any = true
		if not CustomerDemand.will_buy(business, drink, rng):
			continue
		var takings := business.record_sale(drink, 1)
		if takings > 0:
			revenue += takings
			units += 1

	var host: EmployeeData = bar[rng.randi_range(0, bar.size() - 1)]
	host.customers_served_today += 1
	host.sales_processed_today += units

	if revenue <= 0:
		return ServiceResult.lost(
			LostReason.NO_STOCK if not served_any else LostReason.TOO_EXPENSIVE, -0.28
		)

	var press := clampf(
		CustomerDemand.customers_per_hour(business, hour)
			/ maxf(float(throughput_per_hour(business, hour)), 1.0) - 1.0,
		0.0, 1.0
	)
	if security_on_shift(business, hour).is_empty():
		press = minf(press + 0.25, 1.0)
	return ServiceResult.sale(
		revenue, units, 0.15,
		satisfaction_score(business, press, entertainment_quality(business, hour))
	)


func bottlenecks(business: BusinessInstance, hour: int) -> Array[Dictionary]:
	var found := super(business, hour)
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var room := float(customer_capacity(business))
	if room > 0.0 and demand > room * 1.1:
		found.append(_issue(
			&"entry_queue", "ENTRY QUEUE TOO LONG",
			"About %d want in and the room holds %d." % [roundi(demand), roundi(room)],
			clampf((demand - room) / maxf(demand, 1.0), 0.0, 1.0)
		))
	if security_on_shift(business, hour).is_empty() and business.is_open():
		found.append(_issue(
			&"no_security", "NO SECURITY TONIGHT",
			"The door is unworked, so the venue runs at %d%% capacity."
				% roundi(UNSECURED_CAPACITY_FRACTION * 100.0),
			0.85
		))
	if entertainer_on_shift(business, hour) == null and business.is_open():
		found.append(_issue(
			&"no_dj", "NO ENTERTAINMENT BOOKED",
			"Nobody is playing, and it shows in what people will queue for.", 0.5
		))
	return found


func role_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var use := {}
	var throughput := float(throughput_per_hour(business, hour))
	var demand := CustomerDemand.customers_per_hour(business, hour)
	if throughput > 0.0:
		use[EmployeeData.Role.BARTENDER] = clampf(demand / throughput, 0.0, 1.0)
	var room := float(customer_capacity(business))
	if room > 0.0 and not security_on_shift(business, hour).is_empty():
		use[EmployeeData.Role.SECURITY] = clampf(demand / room, 0.0, 1.0)
	return use


func equipment_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var room := float(customer_capacity(business))
	if room <= 0.0:
		return {}
	return {
		&"venue": clampf(CustomerDemand.customers_per_hour(business, hour) / room, 0.0, 1.0),
	}
