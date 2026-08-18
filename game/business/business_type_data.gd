class_name BusinessTypeData
extends Resource
## What kind of business this is, as data.
##
## The whole point of Phase H's architecture: a coffee shop, a clothes shop or a
## gym is one of these plus a stock list. Nothing in BusinessInstance, the
## customer AI, the employee AI or the dashboard knows what a convenience store
## is — they read this.

@export var type_id: StringName = &""
@export var display_name: String = "Business"
@export_multiline var description: String = ""

@export_group("Requirements")
## Equipment ids without which the business cannot open. Checked by role, so a
## fancier counter satisfies the same requirement.
@export var required_roles: Array[int] = [
	EquipmentData.Role.CHECKOUT, EquipmentData.Role.SHELF
]
## Stock the business must have on a shelf before it can open.
@export var minimum_shelf_units: int = 1

@export_group("Trading")
## What this type may sell. Customers only ever ask for something on this list.
@export var catalogue: Array[ItemData] = []
## What the supplier delivers. Empty means "the same things it sells", which is
## a shop; a kitchen fills this with ingredients instead, and its menu is made
## from them rather than ordered.
@export var supply_catalogue: Array[ItemData] = []
## How each menu item is made. Empty means the goods are sold as they arrive.
@export var recipes: Array[RecipeData] = []
## Running cost per day: lights, water, the things nobody wants a system for.
@export var daily_utilities: int = 20
@export var default_opening_hour: int = 8
@export var default_closing_hour: int = 20
## Back-room capacity before any storage racks are added.
@export var base_storage_capacity: int = 60

@export_group("Customers")
## Customers per in-game hour at the busiest part of the day, at neutral
## reputation, with everything in stock and priced sensibly.
@export var peak_customers_per_hour: float = 7.0
## How many items one customer wants, inclusive.
@export var basket_range: Vector2i = Vector2i(1, 3)


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
