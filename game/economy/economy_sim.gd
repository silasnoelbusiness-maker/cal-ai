class_name EconomySim
extends RefCounted

## Projects what each way of making a living actually earns, from the real
## data, so a balance decision can be argued rather than guessed.
##
## Every number here is read from the thing that owns it — job pay from the
## job resource, rent from the property, illegal work from the reward table.
## Nothing is restated. That is the whole point: a tool that carries its own
## copy of the numbers agrees with itself and with nothing else, and stops
## telling the truth the first time somebody edits a .tres.
##
## It models a day, not a session: no travel, no bad luck, no getting caught.
## Read it as a ceiling on each path rather than as a forecast.

## In-game minutes in a day, and the fraction of one a player realistically
## spends earning rather than sleeping, eating and travelling.
const DAY_MINUTES := 1440
const WORKING_FRACTION := 0.45

## What living costs a day, before anything ambitious: two meals and a bed.
const MEALS_PER_DAY := 2


## Every path, as rows the debug screen and the tests can read.
static func project() -> Array[Dictionary]:
	return [
		_wages(), _courier(), _shopkeeper(), _landlord(), _underworld(),
	]


static func by_name(label: String) -> Dictionary:
	for row in project():
		if String(row["path"]) == label:
			return row
	return {}


## Cost of simply existing for a day: food and a roof.
static func daily_living_cost() -> int:
	var meal := 15
	var item: ItemData = load("res://items/definitions/basic_meal.tres")
	if item != null:
		meal = item.price
	# A studio's weekly rent, spread over the week. Read from the cheapest
	# residence in the world rather than restated, so making the flats dearer
	# moves this figure with them.
	var weekly := 220
	for node in Engine.get_main_loop().get_nodes_in_group(&"residence"):
		var amount: Variant = node.get("rent_amount")
		if amount != null:
			weekly = mini(weekly, int(amount)) if weekly > 0 else int(amount)
	return meal * MEALS_PER_DAY + int(round(float(weekly) / 7.0))


static func _row(
	path: String, gross: int, minutes: int, note: String = ""
) -> Dictionary:
	var costs := daily_living_cost()
	return {
		"path": path,
		"gross_per_day": gross,
		"net_per_day": gross - costs,
		"minutes_per_day": minutes,
		"per_hour": int(round(float(gross) / maxf(float(minutes) / 60.0, 0.01))),
		"note": note,
	}


## Shift work, at whatever the stations in the world actually pay.
static func _wages() -> Dictionary:
	var gross := 0
	var minutes := 0
	var stations := 0
	for node in Engine.get_main_loop().get_nodes_in_group(&"job_station"):
		var job: JobData = node.get("job")
		if job == null:
			continue
		stations += 1
		gross += job.pay * job.shifts_per_day
		minutes += int(job.shift_hours * 60.0) * job.shifts_per_day
	if stations == 0:
		# No world loaded: fall back to the resource's own defaults so the tool
		# still says something sensible in a bare test scene.
		var default := JobData.new()
		gross = default.pay * default.shifts_per_day
		minutes = int(default.shift_hours * 60.0) * default.shifts_per_day
	# A player cannot work every station in the city in one day.
	var cap := int(float(DAY_MINUTES) * WORKING_FRACTION)
	if minutes > cap and minutes > 0:
		gross = int(round(float(gross) * float(cap) / float(minutes)))
		minutes = cap
	return _row("Wages", gross, minutes, "%d station%s" % [
		stations, "" if stations == 1 else "s"
	])


## Delivery runs, at the depot's own fee schedule.
static func _courier() -> Dictionary:
	var per_run := CourierJob.base_fee + CourierJob.fee_per_hundred_metres * 6
	# Eight minutes of clock per run plus the drive itself.
	var minutes_per_run := 8 + 6
	var runs := int(float(DAY_MINUTES) * WORKING_FRACTION) / minutes_per_run
	runs = mini(runs, 24)
	return _row("Courier", per_run * runs, runs * minutes_per_run, "%d runs" % runs)


## One well-run convenience store, from the type's own demand curve.
static func _shopkeeper() -> Dictionary:
	var type := BusinessCatalogue.by_id(&"convenience_store")
	if type == null:
		return _row("Shopkeeper", 0, 0, "no catalogue")
	var business := BusinessManager.primary_business()
	if business != null and business.lifetime_revenue > 0:
		var days := maxi(TimeManager.day_index, 1)
		return _row(
			"Shopkeeper",
			int(business.lifetime_revenue / days),
			120,
			"measured from %s" % business.business_name
		)
	# Nothing trading yet: what the type's own demand curve says a full day
	# ought to look like — peak footfall, an average basket, opening hours.
	var hours := type.default_closing_hour - type.default_opening_hour
	var basket := float(type.basket_range.x + type.basket_range.y) * 0.5
	# Averaged across the day rather than at the peak, which no shop holds.
	var customers := type.peak_customers_per_hour * 0.6 * float(maxi(hours, 1))
	return _row(
		"Shopkeeper", int(round(customers * basket * 6.0)), 120,
		"modelled from the type"
	)


## Rent from let property, which is the one income that needs no time at all.
static func _landlord() -> Dictionary:
	var weekly := 0
	for record in RealEstate.portfolio():
		for tenant in RealEstate.tenants_in(record.property_id):
			weekly += tenant.rent_amount
	return _row("Landlord", int(weekly / 7), 0, "%d propert%s" % [
		RealEstate.portfolio().size(),
		"y" if RealEstate.portfolio().size() == 1 else "ies"
	])


## Illegal work at the middle of the ladder, before anything goes wrong.
static func _underworld() -> Dictionary:
	var reward := int(IllegalJobFactory.BASE_REWARD.get(IllegalJobData.Risk.MEDIUM, 2600))
	# Contacts hold a job back between offers, so this is not a tap.
	var jobs_per_day := 2
	return _row(
		"Underworld", reward * jobs_per_day, 90,
		"medium risk, nothing goes wrong"
	)


## The lines the debug overlay prints.
static func report() -> String:
	var lines := PackedStringArray()
	lines.append("%-12s %10s %10s %8s  %s" % [
		"PATH", "GROSS/DAY", "NET/DAY", "$/HOUR", "NOTE"
	])
	for row in project():
		lines.append("%-12s %10d %10d %8d  %s" % [
			row["path"], row["gross_per_day"], row["net_per_day"],
			row["per_hour"], row["note"],
		])
	lines.append("living costs %d a day" % daily_living_cost())
	return "\n".join(lines)
