class_name Liquidation
extends RefCounted
## Winding a branch up without losing anything.
##
## The rule §128 sets is that nothing is ever silently deleted, and liquidation
## is where that is hardest: a failed shop has stock, fittings, people, a lease,
## debts and possibly a van, and every one of them has to end up somewhere the
## player can account for. So this runs in a fixed order and reports what it
## did at each step.
##
## Recovery rates are deliberately unkind. Stock goes back at close to what it
## cost because somebody else will sell it; fittings go for about half, because
## a second-hand cook station is worth much less than a new one. Failing should
## cost money — it simply should not cost *everything*, and it should never
## cost the rest of the company.

## What the player gets back, as a fraction of value. §82.
const INVENTORY_RECOVERY := 0.8
const EQUIPMENT_RECOVERY := 0.5


## What winding this branch up would raise and settle, without doing any of it.
## The screen shows this before the player commits.
static func quote(business: BusinessInstance) -> Dictionary:
	if business == null:
		return {}
	var stock_value := 0
	for id: StringName in business.storage:
		var item := ItemCatalogue.by_id(id)
		if item != null:
			stock_value += item.get_wholesale_cost() * int(business.storage[id])
	for placed in business.equipment:
		var data := placed.data()
		if data != null and data.is_shelf():
			var shelf_item := ItemCatalogue.by_id(placed.stock_item)
			if shelf_item != null:
				stock_value += shelf_item.get_wholesale_cost() * placed.stock_quantity

	var equipment_value := 0
	for placed in business.equipment:
		var data := placed.data()
		if data != null:
			equipment_value += data.purchase_price

	var stock_recovered := roundi(float(stock_value) * INVENTORY_RECOVERY)
	var equipment_recovered := roundi(float(equipment_value) * EQUIPMENT_RECOVERY)
	var owed := business.total_arrears()
	var raised := stock_recovered + equipment_recovered + maxi(business.cash_balance, 0)
	return {
		"stock_value": stock_value,
		"stock_recovered": stock_recovered,
		"equipment_value": equipment_value,
		"equipment_recovered": equipment_recovered,
		"cash": maxi(business.cash_balance, 0),
		"raised": raised,
		"owed": owed,
		"left_over": raised - owed,
		"employees": business.employees.size(),
		"leased": business.property() != null and business.property().has_landlord(),
	}


## Moves whatever is left in the back room to a warehouse instead of selling
## it. The other half of §129's choice, and usually the better one.
static func move_stock_to_warehouse(
	business: BusinessInstance, warehouse: WarehouseInstance
) -> int:
	if business == null or warehouse == null:
		return 0
	var moved := 0
	for id: StringName in business.storage.keys():
		var units := business.storage_of(id)
		if units <= 0:
			continue
		var took := warehouse.add(id, units)
		if took > 0:
			business.take_storage(id, took)
			moved += took
	return moved
