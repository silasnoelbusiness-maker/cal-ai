class_name MembershipModel
extends OperatingModel
## The customer buys access to the room, not a product.
##
## The gym. Nothing comes off a shelf and nothing is cooked, so the two numbers
## that decide whether it works are how many people can be in there at once and
## how many of them keep paying. Machines are the capacity; the membership is
## the revenue; the cleaner is the reason the membership renews.

## Weekly membership fee, spread across the days so the books read evenly
## rather than spiking once a week.
const MEMBERSHIP_DAYS := 7.0
## Members lost per day at worst, as a fraction of the roll.
const MAX_DAILY_LAPSE := 0.09
## Crowding above which members start to give up on the place.
const CROWDING_TOLERANCE := 0.85


func customer_route() -> StringName:
	return &"membership"


func serving_role() -> int:
	return EmployeeData.Role.RECEPTIONIST


func serving_roles(_business: BusinessInstance) -> Array[int]:
	return [EmployeeData.Role.RECEPTIONIST]


func station_role() -> int:
	return EquipmentData.Role.RECEPTION


## Stations across every machine on the floor. This is the gym.
func machine_capacity(business: BusinessInstance) -> int:
	var total := 0
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.role == EquipmentData.Role.MACHINE:
			total += maxi(data.customer_slots, 1)
	return total


func customer_capacity(business: BusinessInstance) -> int:
	return maxi(mini(machine_capacity(business), business.customer_capacity()), 0)


## A workout takes about an hour, so the room turns over once. Without anybody
## on the desk people still get in, but fewer of them and none of them happily.
func throughput_per_hour(business: BusinessInstance, hour: int) -> int:
	var capacity := machine_capacity(business)
	if capacity <= 0:
		return 0
	if servers_on_shift(business, hour).is_empty():
		return maxi(floori(float(capacity) * 0.55), 0)
	return capacity


func overflow_reason() -> StringName:
	return LostReason.BUSINESS_FULL


func extra_requirements(business: BusinessInstance) -> Array[String]:
	var missing: Array[String] = []
	if machine_capacity(business) <= 0:
		missing.append("Workout equipment")
	return missing


## Members bring their own traffic, and a dear membership puts people off. Both
## end up here rather than in the demand curve, because both are the player's
## decisions rather than the type's.
func demand_multiplier(business: BusinessInstance) -> float:
	var from_members := 1.0 + clampf(float(business.members) * 0.018, 0.0, 1.4)
	return from_members * price_appeal(business)


## How the asking price sits against what the type says is normal.
func price_appeal(business: BusinessInstance) -> float:
	var definition := business.type_data()
	if definition == null or definition.default_membership_price <= 0:
		return 1.0
	var ratio := float(business.membership_price) / float(definition.default_membership_price)
	return clampf(1.55 - ratio * 0.55, 0.25, 1.35)


func crowding(business: BusinessInstance, hour: int) -> float:
	var capacity := float(machine_capacity(business))
	if capacity <= 0.0:
		return 1.0
	return clampf(CustomerDemand.customers_per_hour(business, hour) / capacity, 0.0, 2.0)


## One check-in. A member is already paid for; anybody else either joins or
## buys a day pass on the way in.
func serve_one(business: BusinessInstance, hour: int, rng: RandomNumberGenerator) -> ServiceResult:
	if machine_capacity(business) <= 0:
		return ServiceResult.lost(LostReason.BUSINESS_FULL, -0.3)
	# Nobody walks out of a filthy gym quietly; they walk out and they do not
	# come back, which is what the reputation hit is for.
	if business.cleanliness < 35.0 and rng.randf() < (35.0 - business.cleanliness) / 60.0:
		return ServiceResult.lost(LostReason.TOO_DIRTY, -0.45)

	var desk := servers_on_shift(business, hour)
	var member_share := clampf(float(business.members) / float(business.members + 14), 0.0, 0.92)
	var revenue := 0
	var units := 0
	if rng.randf() < member_share:
		# A member's money arrived with the subscription; the visit itself is
		# free, and its whole job is to decide whether they renew.
		units = 0
	elif desk.is_empty():
		# There is nobody to sign anybody up. They use the place and pay
		# nothing, which is exactly the hole a receptionist plugs.
		return ServiceResult.lost(LostReason.NO_STAFF, -0.3)
	elif rng.randf() < join_chance(business):
		revenue = business.record_service_sale(
			business.membership_price, "Membership", 1
		)
		business.members += 1
		units = 1
	else:
		revenue = business.record_service_sale(business.day_pass_price, "Day pass", 1)
		units = 1

	if not desk.is_empty():
		var host: EmployeeData = desk[rng.randi_range(0, desk.size() - 1)]
		host.customers_served_today += 1

	var press := clampf((crowding(business, hour) - CROWDING_TOLERANCE) / 0.6, 0.0, 1.0)
	var quality := lerpf(58.0, 88.0, clampf(float(best_tier(business) - 1) / 2.0, 0.0, 1.0))
	if desk.is_empty():
		quality -= 12.0
	return ServiceResult.sale(revenue, units, 0.1, satisfaction_score(business, press, quality))


## Whether a walk-in signs up rather than paying at the door. Reputation and a
## fair price do the work.
func join_chance(business: BusinessInstance) -> float:
	var standing := clampf(business.reputation / 100.0, 0.0, 1.0)
	return clampf(0.10 + standing * 0.30, 0.02, 0.55) * clampf(price_appeal(business), 0.2, 1.3)


func best_tier(business: BusinessInstance) -> int:
	var tier := 1
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.role == EquipmentData.Role.MACHINE:
			tier = maxi(tier, data.quality_tier)
	return tier


## Subscriptions, collected daily, and the members who have had enough.
func on_day(business: BusinessInstance, _day_index: int) -> void:
	if business.members <= 0:
		return
	var daily := float(business.membership_price) / MEMBERSHIP_DAYS
	var takings := roundi(daily * float(business.members))
	if takings > 0:
		business.record_service_sale(takings, "Memberships", 0)

	# Why people leave: a dirty gym, a crowded one, or a bad reputation. Each
	# is something the player can do something about.
	var lapse := 0.012
	if business.cleanliness < OperatingModel.CLEANLINESS_TOLERANCE:
		lapse += (OperatingModel.CLEANLINESS_TOLERANCE - business.cleanliness) / 100.0 * 0.10
	lapse += clampf((50.0 - business.reputation) / 100.0, 0.0, 0.5) * 0.06
	var lost := floori(float(business.members) * clampf(lapse, 0.0, MAX_DAILY_LAPSE))
	business.members = maxi(business.members - lost, 0)


func bottlenecks(business: BusinessInstance, hour: int) -> Array[Dictionary]:
	var found := super(business, hour)
	var capacity := machine_capacity(business)
	if capacity <= 0:
		found.append(_issue(
			&"no_machines", "NOT ENOUGH GYM MACHINES",
			"There is nothing in here to work out on.", 1.0
		))
	else:
		var press := crowding(business, hour)
		if press > 1.0:
			found.append(_issue(
				&"crowding", "NOT ENOUGH GYM MACHINES",
				"About %d people an hour for %d stations." % [
					roundi(CustomerDemand.customers_per_hour(business, hour)), capacity
				],
				clampf(press - 1.0, 0.0, 1.0)
			))
	if servers_on_shift(business, hour).is_empty() and business.is_open():
		found.append(_issue(
			&"no_reception", "NO RECEPTIONIST ON SHIFT",
			"Nobody is signing anybody up, so walk-ins pay nothing.", 0.9
		))
	return found


func role_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var use := {}
	var capacity := float(machine_capacity(business))
	if capacity > 0.0:
		use[EmployeeData.Role.RECEPTIONIST] = clampf(
			CustomerDemand.customers_per_hour(business, hour) / capacity, 0.0, 1.0
		)
	return use


func equipment_utilisation(business: BusinessInstance, hour: int) -> Dictionary:
	var use := {}
	var demand := CustomerDemand.customers_per_hour(business, hour)
	var totals := {}
	for placed in business.equipment:
		var data := placed.data()
		if data == null or data.role != EquipmentData.Role.MACHINE:
			continue
		totals[data.equipment_id] = int(totals.get(data.equipment_id, 0)) + maxi(data.customer_slots, 1)
	var capacity := float(machine_capacity(business))
	if capacity <= 0.0:
		return use
	for id: StringName in totals:
		# Demand spreads across the floor in proportion to what is on it, so a
		# gym with one treadmill and six benches queues for the treadmill.
		use[id] = clampf(demand / capacity, 0.0, 1.0)
	return use
