class_name SupplierData
extends RefCounted
## Who the stock is bought from.
##
## One per category rather than one in the world, which is what Phase O needed:
## a kitchen buys food from a food wholesaler and a venue buys its consumables
## from somebody else, and each has its own prices and its own lead time. The
## shape is still the one Phase H set — a slower, cheaper wholesaler against a
## fast, dear one is a second entry in CATEGORIES, not a new system.

var supplier_id: StringName = &"citywide"
var display_name: String = "Citywide Wholesale"
## Hours between placing an order and it turning up, inclusive.
var delivery_hours: Vector2 = Vector2(2.0, 6.0)
## Multiplies every wholesale price.
var price_modifier: float = 1.0
## Orders below this are not worth their while.
var minimum_order: int = 0
## Which shelf of the warehouse this is. Matched against
## BusinessTypeData.supply_category.
var category: StringName = &"retail_goods"
## 0-1. How often a delivery runs late. Recorded rather than acted on for now —
## the field is here so lateness is a supplier's property when it arrives, not
## a new column bolted onto orders later.
var reliability: float = 0.95


## [id, name, category, min delivery hours, max, price modifier, reliability]
##
## Food comes quicker and dearer because it will not keep; venue consumables
## come on a slower run because nobody needs them before eight in the evening.
const CATEGORIES: Array = [
	[&"citywide", "Citywide Wholesale", &"retail_goods", 2.0, 6.0, 1.0, 0.95],
	[&"harvest_row", "Harvest Row Produce", &"food_ingredients", 1.5, 4.0, 1.08, 0.93],
	[&"tidewater", "Tidewater Supply", &"venue_consumables", 3.0, 8.0, 0.96, 0.9],
	[&"forge_works", "Forge Works Equipment", &"gym_supplies", 4.0, 10.0, 1.0, 0.97],
]


static func default_supplier() -> SupplierData:
	return for_category(&"retail_goods")


## The wholesaler that serves a given kind of goods. Falls back to the general
## one, so a type that names a category nobody supplies still trades.
static func for_category(category_id: StringName) -> SupplierData:
	for entry in CATEGORIES:
		if StringName(entry[2]) != category_id:
			continue
		var supplier := SupplierData.new()
		supplier.supplier_id = StringName(entry[0])
		supplier.display_name = String(entry[1])
		supplier.category = category_id
		supplier.delivery_hours = Vector2(float(entry[3]), float(entry[4]))
		supplier.price_modifier = float(entry[5])
		supplier.reliability = float(entry[6])
		return supplier
	if category_id != &"retail_goods":
		return for_category(&"retail_goods")
	return SupplierData.new()


## The wholesaler a given business deals with, from its type's category.
static func for_business(business: BusinessInstance) -> SupplierData:
	var definition := business.type_data() if business != null else null
	return for_category(definition.supply_category if definition != null else &"retail_goods")


func price_for(item: ItemData, quantity: int) -> int:
	if item == null:
		return 0
	return maxi(roundi(float(item.get_wholesale_cost()) * price_modifier), 1) * quantity


func delivery_minutes(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(delivery_hours.x, delivery_hours.y) * 60.0
