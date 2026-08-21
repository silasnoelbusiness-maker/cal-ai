class_name CustomerDemand
extends RefCounted
## What one shopper wants, and whether they will pay for it.
##
## Pure functions over a BusinessInstance, and the only place the rules live.
## The customer walking the aisles and the aggregated simulation that runs while
## the player is across town both call these, which is what stops a shop earning
## differently depending on whether anybody is watching it.

## Items this shop has on a shelf right now, weighted by how much people want
## them. Returns null when the shelves are bare.
static func pick_item(business: BusinessInstance, rng: RandomNumberGenerator) -> ItemData:
	var candidates: Array[ItemData] = []
	var weights: Array[float] = []
	var total := 0.0
	for item in business.catalogue():
		if business.available_units(item) <= 0:
			continue
		var weight := maxf(item.demand_weight, 0.01)
		candidates.append(item)
		weights.append(weight)
		total += weight
	if candidates.is_empty():
		return null

	var roll := rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


## What somebody came in for, whether or not the shop has it. Used to tell a
## genuine lost sale from a customer who never wanted anything.
static func pick_wanted_item(business: BusinessInstance, rng: RandomNumberGenerator) -> ItemData:
	var stocked := pick_item(business, rng)
	if stocked != null:
		return stocked
	var list := business.catalogue()
	if list.is_empty():
		return null
	return list[rng.randi_range(0, list.size() - 1)]


static func basket_size(business: BusinessInstance, rng: RandomNumberGenerator) -> int:
	var definition := business.type_data()
	if definition == null:
		return 1
	return rng.randi_range(
		maxi(definition.basket_range.x, 1), maxi(definition.basket_range.y, 1)
	)


## The price test. Everything about how customers respond to what the player
## charges is BusinessInstance.purchase_chance; this is the roll against it.
static func will_buy(
	business: BusinessInstance, item: ItemData, rng: RandomNumberGenerator,
	archetype: StringName = &""
) -> bool:
	var chance := business.purchase_chance(item)
	if archetype != &"":
		# The same price reads differently to a student and to somebody on an
		# expense account. A sensitive customer feels the gap from a fair price
		# more; a comfortable one barely notices it.
		var shortfall := clampf(1.0 - chance, 0.0, 1.0)
		chance = clampf(
			1.0 - shortfall * CustomerArchetype.price_sensitivity(archetype), 0.0, 1.0
		)
	return rng.randf() < chance


## How many people an open shop should expect this hour.
##
## Everything that decides how busy a business is, in one product. The time of
## day and the address are given; reputation, range, advertising and the fittings
## are earned. Nothing here looks at price — that decides whether the people who
## walk in buy anything, which is a different question and lives in
## `BusinessInstance.purchase_chance`.
static func customers_per_hour(
	business: BusinessInstance, hour: int, weekday: int = -1
) -> float:
	var definition := business.type_data()
	if definition == null:
		return 0.0
	var attraction := 1.0 + business.marketing_bonus() + business.upgrade_magnitude(
		BusinessUpgrade.Effect.ATTRACTION
	)
	return (
		definition.peak_customers_per_hour
		* definition.demand_at_hour(hour)
		* weekday_factor(definition, weekday)
		* definition.district_factor(business.district_id())
		* business.reputation_multiplier()
		* range_factor(business)
		* business.location_multiplier()
		* attraction
		* business.model().demand_multiplier(business)
	)


## What a Saturday is worth to this kind of business. A nightclub's week is not
## a coffee shop's week, and neither of them knows that — the type does.
static func weekday_factor(definition: BusinessTypeData, weekday: int = -1) -> float:
	if definition == null:
		return 1.0
	var day := weekday if weekday >= 0 else TimeManager.weekday
	return definition.weekend_factor if day >= 5 else 1.0


## Passing trade by hour: quiet overnight, busy at lunch and after work.
##
## The fallback curve, used by any business type that does not supply its own
## twenty-four. Everything written before Phase O relies on it, which is why it
## is still here and still exactly what it was.
static func time_of_day_factor(hour: int) -> float:
	if hour >= 11 and hour <= 13:
		return 1.0
	if hour >= 16 and hour <= 19:
		return 0.95
	if hour >= 8 and hour <= 21:
		return 0.7
	if hour >= 6 and hour <= 23:
		return 0.35
	return 0.12


## Fraction of the shop's range that is buyable, softened so a shop with half
## its lines in stock still does most of the trade. "Buyable" means on a shelf in
## a shop and makeable in a kitchen — BusinessInstance.available_units knows the
## difference so nothing else has to.
static func range_factor(business: BusinessInstance) -> float:
	var list := business.catalogue()
	if list.is_empty():
		# A gym sells the room, not goods. Judging it on an empty shelf would
		# shut it before it opened.
		return 1.0
	var stocked := 0
	for item in list:
		if business.available_units(item) > 0:
			stocked += 1
	if stocked == 0:
		return 0.0
	return lerpf(0.45, 1.0, float(stocked) / float(list.size()))
