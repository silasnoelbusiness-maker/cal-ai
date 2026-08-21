class_name BusinessTypeData
extends Resource
## What kind of business this is, as data.
##
## The whole point of Phase H's architecture: a coffee shop, a clothes shop or a
## gym is one of these plus a stock list. Nothing in BusinessInstance, the
## customer AI, the employee AI or the dashboard knows what a convenience store
## is — they read this.
##
## Phase O pushed on that. A restaurant, a gym and a nightclub are not three new
## branches inside BusinessManager; they are three of these resources plus an
## OperatingModel chosen by `service_model`. Everything a type does differently
## — what it needs to open, who it employs, how many people fit in it, when they
## turn up and what a visit is worth — is one of the fields below.

## How the business turns customers into money. The one field the rest of the
## game switches on, and the only thing that picks an OperatingModel.
##   RETAIL          — goods off a shelf, paid for at a till.
##   COUNTER_SERVICE — made to order, handed over at a counter.
##   TABLE_SERVICE   — seated, ordered, cooked, carried, paid.
##   MEMBERSHIP      — the customer buys access to the room, not a product.
##   VENUE           — entry, then drinks, with the night doing the work.
enum ServiceModel { RETAIL, COUNTER_SERVICE, TABLE_SERVICE, MEMBERSHIP, VENUE }

@export var type_id: StringName = &""
@export var display_name: String = "Business"
@export_multiline var description: String = ""
@export var service_model: ServiceModel = ServiceModel.RETAIL

@export_group("Requirements")
## Equipment ids without which the business cannot open. Checked by role, so a
## fancier counter satisfies the same requirement.
@export var required_roles: Array[int] = [
	EquipmentData.Role.CHECKOUT, EquipmentData.Role.SHELF
]
## Stock the business must have on a shelf before it can open.
@export var minimum_shelf_units: int = 1
## Staff roles that must be on shift for the business to trade properly. A
## restaurant without a cook can open its doors; it cannot serve a meal.
@export var required_staff_roles: Array[int] = []
## Roles this type has any use for. The hiring board and the staffing screen
## read this so a gym is never offered a barista.
@export var staff_roles_used: Array[int] = []
## Floor area the property needs, in square metres. A nightclub does not go in
## a thirty-metre shop.
@export var minimum_floor_area: int = 0
## What the property has to be zoned for. Matched against
## CommercialProperty.business_classes.
@export var property_class: StringName = &"retail"
## Cash the player needs before founding one, over and above the lease.
@export var startup_cost: int = 1200

@export_group("Trading")
## What this type may sell. Customers only ever ask for something on this list.
@export var catalogue: Array[ItemData] = []
## What the supplier delivers. Empty means "the same things it sells", which is
## a shop; a kitchen fills this with ingredients instead, and its menu is made
## from them rather than ordered.
@export var supply_catalogue: Array[ItemData] = []
## How each menu item is made. Empty means the goods are sold as they arrive.
@export var recipes: Array[RecipeData] = []
## Which shelf of the supplier's warehouse this type orders from.
@export var supply_category: StringName = &"retail_goods"
## Running cost per day: lights, water, the things nobody wants a system for.
@export var daily_utilities: int = 20
@export var default_opening_hour: int = 8
@export var default_closing_hour: int = 20
## Back-room capacity before any storage racks are added.
@export var base_storage_capacity: int = 60

@export_group("Membership")
## Set on a type that sells access rather than goods. The price the player sets
## is per period, and a visit spends a fraction of it.
@export var sells_memberships: bool = false
@export var default_membership_price: int = 40
@export var default_day_pass_price: int = 9
## What one walk-in is worth at the door, before anything else is bought.
@export var default_entry_fee: int = 0

@export_group("Capacity")
## People who fit inside before any equipment is bought. A shop floor holds a
## few browsers whether or not it has seating; a gym holds nobody without
## machines.
@export var base_customer_capacity: int = 6
## Hard ceiling however much equipment is crammed in, so a small room cannot
## become a stadium.
@export var maximum_customer_capacity: int = 40
## People one member of serving staff can get through in an hour.
@export var served_per_staff_hour: float = 14.0

@export_group("Customers")
## Customers per in-game hour at the busiest part of the day, at neutral
## reputation, with everything in stock and priced sensibly.
@export var peak_customers_per_hour: float = 7.0
## How many items one customer wants, inclusive.
@export var basket_range: Vector2i = Vector2i(1, 3)
## Twenty-four multipliers, one per hour, midnight first. Empty falls back to
## the general passing-trade curve. This is what makes a coffee shop a morning
## business and a nightclub a nocturnal one without a line of code knowing it.
@export var demand_by_hour: Array[float] = []
## Multiplier on the days the game treats as a weekend. Above one for the
## businesses people go out for, below one for the ones they use on the way to
## work.
@export var weekend_factor: float = 1.0
## District id to multiplier. Missing districts are 1.0. Kept modest on
## purpose: a location should tilt a business, not decide it.
@export var district_affinity: Dictionary = {}
## Customer archetype id to relative weight. Who actually comes through the
## door, which decides what they care about.
@export var archetype_weights: Dictionary = {}

@export_group("Upkeep")
## Whether the place gets dirty and somebody has to clean it.
@export var uses_cleanliness: bool = false
## Points of cleanliness lost per hour of trading, before customers are counted.
@export var soiling_per_hour: float = 0.6


## Whether this business makes what it sells to order. Derived rather than a
## flag, so a type cannot claim to be a kitchen without any recipes.
func serves_prepared_goods() -> bool:
	return not recipes.is_empty()


func recipe_for(item: ItemData) -> RecipeData:
	if item == null:
		return null
	for recipe in recipes:
		if recipe != null and recipe.product == item:
			return recipe
	return null


## What the supplier will sell this business.
func orderable() -> Array[ItemData]:
	return supply_catalogue if not supply_catalogue.is_empty() else catalogue


## The hour multiplier for this type. Falls back to the shared passing-trade
## curve, so a type written before Phase O behaves exactly as it did.
func demand_at_hour(hour: int) -> float:
	if demand_by_hour.size() < 24:
		return CustomerDemand.time_of_day_factor(hour)
	return maxf(float(demand_by_hour[posmod(hour, 24)]), 0.0)


func district_factor(district_id: StringName) -> float:
	return float(district_affinity.get(district_id, 1.0))


## Whether somebody in this role is worth putting on the payroll here.
func uses_role(role: int) -> bool:
	if staff_roles_used.is_empty():
		return true
	return staff_roles_used.has(role) or required_staff_roles.has(role)


func requires_role(role: int) -> bool:
	return required_staff_roles.has(role)


func is_seated_service() -> bool:
	return service_model == ServiceModel.TABLE_SERVICE


func model_label() -> String:
	match service_model:
		ServiceModel.COUNTER_SERVICE:
			return "Counter service"
		ServiceModel.TABLE_SERVICE:
			return "Table service"
		ServiceModel.MEMBERSHIP:
			return "Memberships"
		ServiceModel.VENUE:
			return "Venue"
		_:
			return "Retail"
