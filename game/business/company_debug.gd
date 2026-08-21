class_name CompanyDebug
extends RefCounted
## Dev shortcuts for the Phase O systems.
##
## Static helpers rather than another overlay: the three new business types take
## a lease, a type, six pieces of equipment, a supplier order and four members
## of staff before they do anything at all, and typing that out is the same
## twenty lines in the debug overlay, the tests and the screenshot tool. It
## lives here so all three call the same thing and none of them can quietly
## stand up a restaurant the player could not have built.

## Equipment each type gets stood up with, in the order it is placed.
const FITTINGS := {
	&"restaurant": [
		&"cook_station", &"prep_counter", &"kitchen_fridge", &"dry_store",
		&"service_pass", &"dining_table", &"dining_table", &"dining_table",
	],
	&"gym": [
		&"reception_desk", &"treadmill", &"treadmill", &"exercise_bike",
		&"weight_bench", &"weight_rack", &"locker_bank", &"cleaning_station",
	],
	&"nightclub": [
		&"bar_counter", &"dance_floor", &"dj_booth", &"speaker_stack",
		&"lighting_rig", &"security_post", &"venue_store", &"club_table",
	],
}

## Who each type needs on the rota before it can trade properly.
const CREW := {
	&"restaurant": [EmployeeData.Role.COOK, EmployeeData.Role.SERVER],
	&"gym": [EmployeeData.Role.RECEPTIONIST],
	&"nightclub": [
		EmployeeData.Role.BARTENDER, EmployeeData.Role.SECURITY,
		EmployeeData.Role.ENTERTAINER,
	],
}


## Leases a unit, opens a business of the given type in it, funds it, fits it
## out and fills the store room. Returns the business, or null if the unit will
## not take that kind of trade.
static func found(
	property_id: StringName, type_id: StringName, business_name: String,
	funding: int = 20000
) -> BusinessInstance:
	var property := _property(property_id)
	if property == null:
		return null
	var definition := BusinessCatalogue.by_id(type_id)
	if definition == null or not property.accepts_business(definition):
		return null
	if property.is_vacant():
		PropertyManager.lease(property)
	var business := BusinessManager.business_for_property(property_id)
	if business == null:
		business = BusinessManager.create_business(business_name, type_id, property)
	if business == null:
		return null
	BusinessManager.deposit_to_business(business, funding)
	return business


## Buys and places everything the type needs. Placement walks the shop floor in
## a grid, which is crude and is only ever used by tools.
static func fit_out(business: BusinessInstance, unit: RetailUnit) -> int:
	if business == null or unit == null:
		return 0
	unit.ensure_built()
	var placed := 0
	var spot := 0
	for id: StringName in FITTINGS.get(business.type_id, []):
		if BusinessManager.buy_equipment(business, id) != BusinessManager.PurchaseResult.OK:
			continue
		var data := EquipmentCatalogue.by_id(id)
		var point := _grid_point(unit, spot, data)
		spot += 1
		if not BusinessManager.consume_unplaced(business, id):
			continue
		business.place_equipment(id, point, 0.0)
		placed += 1
	unit.rebuild_equipment()
	return placed


## A spot on the floor for the nth piece. Kitchen equipment goes in the store
## room, everything else on the trading floor, which is roughly where a player
## would put them and is enough for a tool.
static func _grid_point(unit: RetailUnit, index: int, data: EquipmentData) -> Vector3:
	var back_of_house := data != null and (
		data.role == EquipmentData.Role.COOK_STATION
		or data.role == EquipmentData.Role.PREP
		or data.role == EquipmentData.Role.COLD_STORE
		or data.role == EquipmentData.Role.STORAGE
	)
	var area := unit.storage_area if back_of_house else unit.retail_area
	var columns := maxi(int(area.size.x / 3.0), 1)
	var column := index % columns
	var row := index / columns
	if back_of_house:
		# Laid out from the gap in the partition westward, so whoever works
		# back here has a short clear walk to their station rather than a
		# route round three other pieces of kitchen.
		return Vector3(
			clampf(
				unit.partition_gap.x - 1.0 - float(column) * 2.6,
				area.position.x + 1.0, area.end.x - 1.0
			),
			0.0,
			area.end.y - 1.0 - float(row) * 1.8
		)
	return Vector3(
		area.position.x + 1.4 + float(column) * 2.8,
		0.0,
		area.position.y + 1.2 + float(row) * 2.4
	)


## Fills the back room with everything the type buys, paid for out of the
## business's own account through the ordinary supplier.
static func stock_up(business: BusinessInstance, quantity: int = 40) -> int:
	if business == null:
		return 0
	var definition := business.type_data()
	var lines := business.orderable()
	if lines.is_empty():
		return 0
	# Room is finite and the list is ordered, so ordering greedily down it
	# leaves whatever is last with nothing — and a menu where every dish needs
	# one of the last three lines is a kitchen that cannot cook anything. The
	# room is divided by how hard each line is used instead.
	var weights: Array[float] = []
	var total_weight := 0.0
	for item in lines:
		var weight := definition.ingredient_usage(item) if definition != null else 1.0
		weights.append(weight)
		total_weight += weight
	var room := BusinessManager.room_left_after_orders(business)
	var ordered := 0
	for i in lines.size():
		var share := int(float(room) * weights[i] / maxf(total_weight, 0.01))
		var wanted := mini(maxi(roundi(float(quantity) * weights[i]), 1), maxi(share, 1))
		if BusinessManager.order_stock(business, lines[i].id, wanted) == BusinessManager.PurchaseResult.OK:
			ordered += 1
	BusinessManager.deliver_now(business)
	return ordered


## Hires whoever the type cannot trade without, plus a manager, all on a shift
## that covers the whole day so a tool never has to think about the clock.
static func staff_up(
	business: BusinessInstance, extra_roles: Array[int] = [], calibre: float = 0.8
) -> Array[EmployeeData]:
	var hired: Array[EmployeeData] = []
	if business == null:
		return hired
	var wanted: Array[int] = []
	for role: int in CREW.get(business.type_id, []):
		wanted.append(int(role))
	for role in extra_roles:
		if not wanted.has(int(role)):
			wanted.append(int(role))
	for role in wanted:
		var worker := hire(business, role, calibre)
		if worker != null:
			hired.append(worker)
	return hired


## One person, in one job, on shift around the clock.
static func hire(
	business: BusinessInstance, role: int, calibre: float = 0.8
) -> EmployeeData:
	if business == null:
		return null
	BusinessManager.refresh_candidates()
	var candidates := BusinessManager.get_candidates()
	if candidates.is_empty():
		return null
	var worker: EmployeeData = candidates[0]
	# A tool wants somebody who can do the job, not whoever walked past.
	var key: StringName = EmployeeData.ROLE_SKILL.get(role, &"checkout")
	worker.set_skill_named(key, clampi(roundi(calibre * 100.0), 10, 98))
	if not BusinessManager.hire(business, worker, role):
		return null
	# Round the clock, every day: a tool should never fail because of what
	# time it happens to be.
	worker.clear_shifts()
	worker.shift_start_hour = 0
	worker.shift_end_hour = 24
	return worker


## The whole errand in one call: lease, found, fit, stock and staff.
static func stand_up(
	property_id: StringName, type_id: StringName, business_name: String,
	tree: SceneTree, funding: int = 20000
) -> BusinessInstance:
	var business := found(property_id, type_id, business_name, funding)
	if business == null:
		return null
	var unit := RetailUnit.for_business(business, tree)
	fit_out(business, unit)
	stock_up(business)
	staff_up(business)
	return business


static func _property(property_id: StringName) -> CommercialProperty:
	for node in Engine.get_main_loop().get_nodes_in_group(&"commercial_property"):
		var unit := node as CommercialProperty
		if unit != null and unit.property_id == property_id:
			return unit
	return null


# --- Single-purpose pokes -------------------------------------------------

## Forces a rush, or clears one. §132 asks for this; nothing else sets it.
static func force_demand(business: BusinessInstance, multiplier: float) -> void:
	if business != null:
		business.demand_override = maxf(multiplier, 0.0)


static func set_cleanliness(business: BusinessInstance, value: float) -> void:
	if business != null:
		business.cleanliness = clampf(value, 0.0, 100.0)


static func add_members(business: BusinessInstance, count: int) -> void:
	if business != null:
		business.members = maxi(business.members + count, 0)


## Trades a whole day, hour by hour, against the business's own opening times.
static func advance_business_day(business: BusinessInstance) -> void:
	if business == null:
		return
	for hour in range(24):
		if business.should_be_open(hour):
			BusinessManager.simulate_hour_now(business, hour)


## Fills every seat, machine or stretch of floor, so the "we are full" paths
## can be seen without waiting for a rush.
static func fill_to_capacity(business: BusinessInstance, unit: RetailUnit) -> int:
	if business == null or unit == null:
		return 0
	var taken := 0
	for node in unit.equipment_nodes():
		while node.has_room():
			node.take_slot()
			taken += 1
	return taken
