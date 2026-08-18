class_name SupplierData
extends RefCounted
## Who the stock is bought from.
##
## One supplier today. The shape is here so a second is a new entry rather than a
## new system: a slower, cheaper wholesaler and a fast, dear one is the decision
## this exists to make possible.

var supplier_id: StringName = &"citywide"
var display_name: String = "Citywide Wholesale"
## Hours between placing an order and it turning up, inclusive.
var delivery_hours: Vector2 = Vector2(2.0, 6.0)
## Multiplies every wholesale price.
var price_modifier: float = 1.0
## Orders below this are not worth their while.
var minimum_order: int = 0


static func default_supplier() -> SupplierData:
	return SupplierData.new()


func price_for(item: ItemData, quantity: int) -> int:
	if item == null:
		return 0
	return maxi(roundi(float(item.get_wholesale_cost()) * price_modifier), 1) * quantity


func delivery_minutes(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(delivery_hours.x, delivery_hours.y) * 60.0
