class_name BusinessInstance
extends RefCounted
## One business the player owns.
##
## Everything a business *is* lives here: its money, its stock, its shelves, its
## prices, its staff and its day's trading. The world objects — the shelves the
## player walks up to, the customers, the cashier — are built from this and write
## back to it. That direction matters: it is why a shop keeps trading when nobody
## is inside it to look at, why the save file is one call, and why the far
## simulation is not a second copy of the rules.
##
## Money is deliberately separate from the player's pocket. Nothing here touches
## EconomyManager; BusinessManager moves money across the boundary so both
## ledgers see the same transfer.

signal changed()
signal opened()
signal closed()
signal sale_made(item: ItemData, quantity: int, revenue: int)
signal stock_low(item: ItemData)
signal day_finished(report: Dictionary)

## Which side of the schedule the owner has overridden, if either.
enum Override { NONE, FORCE_OPEN, FORCE_CLOSED }

## Reputation moves by at most this much per day, so one bad afternoon does not
## sink a shop and one good one does not save it.
const MAX_REPUTATION_DRIFT_PER_DAY := 8.0
## Below this many units of a product on the shelves, the owner is told.
const LOW_STOCK_THRESHOLD := 4

var business_id: StringName = &""
var business_name: String = "Business"
var type_id: StringName = &"convenience_store"
var owner_id: StringName = &"player"
var property_id: StringName = &""

var cash_balance: int = 0
var opening_hour: int = 8
var closing_hour: int = 20
var manual_override: Override = Override.NONE
var reputation: float = 50.0
## 0-100, and only meaningful on a type that says it uses it. A shop does not
## get dirty in any way the player has to manage; a kitchen and a gym do.
var cleanliness: float = 100.0
## The brand this branch trades under, if any. Empty means an independent.
var brand_id: StringName = &""

## What the player charges for access, on a type that sells it.
var membership_price: int = 40
var day_pass_price: int = 9
var entry_fee: int = 0
## People currently paying a subscription here.
var members: int = 0

var storage: Dictionary = {}
var prices: Dictionary = {}
var equipment: Array[PlacedEquipment] = []
var employees: Array[EmployeeData] = []
var upgrades: Array[StringName] = []
var campaigns: Array[MarketingCampaign] = []
var loans: Array[Loan] = []

## What the manager is allowed to do on the player's behalf. All off until a
## manager is hired and the player turns them on, because automation the player
## did not ask for spending their money is a bug however useful it is.
var auto_open: bool = false
var auto_restock: bool = false
var auto_order: bool = false
## Ceiling on what one automatic order may cost.
var auto_order_budget: int = 500
## Reorder when the store room falls below this, up to this.
var auto_order_minimum: int = 15
var auto_order_target: int = 45
## What else the manager is allowed to do. The three switches above predate
## Phase O and stay where they are; these are the ones a restaurant, a gym and
## a venue needed. Pricing is in the list and off by default on purpose — a
## manager quietly changing what the player charges is not automation, it is
## losing control of your own business.
var manager_permissions: Dictionary = {
	&"manage_cleanliness": true,
	&"staff_positioning": true,
	&"adjust_pricing": false,
}
## Cleanliness the manager works to keep the place above, when allowed.
var cleanliness_target: int = 70
## Spent by the manager today, against auto_order_budget. Reset with the day.
var manager_spent_today: int = 0

var revenue_today: int = 0
var inventory_spend_today: int = 0
var wages_today: int = 0
var rent_today: int = 0
var equipment_spend_today: int = 0
var marketing_today: int = 0
var utilities_today: int = 0
var loan_payments_today: int = 0
var other_expense_today: int = 0
## Wages the account could not cover. Nothing collects them yet; the number is
## what an unpaid-staff consequence will read, and it keeps the books honest in
## the meantime.
var wages_owed: int = 0
## Cost basis of what was actually sold today. Reported as gross margin, and
## deliberately NOT part of expenses_today — the cash for that stock was already
## counted when it was ordered. Adding both is the double count the brief warns
## about.
var cogs_today: int = 0
var customer_count_today: int = 0
var lost_sales_today: int = 0
## Lost sales broken down by LostReason, so "we lost fourteen" becomes "we lost
## fourteen for want of a table" and the player knows what to buy.
var lost_reasons_today: Dictionary = {}
## Rolling samples of how hard each role and each fitting was worked today,
## kept as [total, count] so an average survives an hour with no trade.
var role_load_today: Dictionary = {}
var equipment_load_today: Dictionary = {}
var service_revenue_today: int = 0
## Development lever (§132's "force demand"). Multiplies the arrival rate, and
## is off at zero. Not saved and never set by anything the player can reach —
## it exists so a test can create a lunch rush on purpose rather than hoping
## for one, and so a screenshot can show a room under pressure.
var demand_override: float = 0.0
var units_sold_today: int = 0

var lifetime_revenue: int = 0
var lifetime_expenses: int = 0
var lifetime_units_sold: int = 0
var lifetime_interest_paid: int = 0
## The last seven daily reports, newest last. What the weekly figures add up.
var recent_reports: Array[Dictionary] = []
var founded_on_day: int = 0
var last_report: Dictionary = {}

var _ledger: Array[Dictionary] = []
var _next_slot: int = 1
var _open: bool = false
var _low_stock_warned: Dictionary = {}
## Tickets the kitchen is working through. Transient on purpose: a reload
## clears the floor and the kitchen with it, and nothing about the business's
## money, stock or staff depends on an order that was half cooked.
var kitchen: Array[KitchenOrder] = []
var _next_order_id: int = 1


# --- Identity ------------------------------------------------------------

## How this business trades, as a strategy object. Everything a restaurant does
## differently from a shop is on the far side of this call.
func model() -> OperatingModel:
	return OperatingModels.for_business(self)


func district_id() -> StringName:
	var unit := property()
	return unit.district_id if unit != null else &"harbour_row"


func type_data() -> BusinessTypeData:
	return BusinessCatalogue.by_id(type_id)


func catalogue() -> Array[ItemData]:
	var definition := type_data()
	return definition.catalogue if definition != null else [] as Array[ItemData]


func sells(item: ItemData) -> bool:
	return item != null and catalogue().has(item)


## What the supplier will deliver here — the same goods for a shop, ingredients
## for a kitchen.
func orderable() -> Array[ItemData]:
	var definition := type_data()
	return definition.orderable() if definition != null else [] as Array[ItemData]


## Whether staff fetch the goods rather than customers taking them off a shelf.
## True of a bar, false of a shop.
func serves_from_storage() -> bool:
	return model().serves_from_storage()


func serves_prepared_goods() -> bool:
	var definition := type_data()
	return definition != null and definition.serves_prepared_goods()


func recipe_for(item: ItemData) -> RecipeData:
	var definition := type_data()
	return definition.recipe_for(item) if definition != null else null


## How many of this the business could sell right now.
##
## The one question both kinds of business answer differently, and the only
## place that difference lives: a shop counts what is on its shelves, a kitchen
## counts how many it could make from what is in the back.
func available_units(item: ItemData) -> int:
	if item == null:
		return 0
	var recipe := recipe_for(item)
	if recipe == null:
		# Goods a customer picks up themselves come off a shelf; goods handed
		# across a bar come out of the cellar. Which of the two this is belongs
		# to the operating model, not to the item.
		return storage_of(item.id) if serves_from_storage() else shelf_stock_of(item.id)

	var possible := 999
	for i in recipe.ingredients.size():
		var ingredient: ItemData = recipe.ingredients[i]
		if ingredient == null:
			continue
		var per_unit: int = maxi(int(recipe.amounts[i]) if i < recipe.amounts.size() else 1, 1)
		possible = mini(possible, storage_of(ingredient.id) / per_unit)
	return maxi(possible, 0)


## Takes the goods for a sale out of wherever they live. Returns how many it
## could actually find.
func take_for_sale(item: ItemData, quantity: int) -> int:
	if item == null or quantity <= 0:
		return 0
	var recipe := recipe_for(item)
	if recipe == null:
		if serves_from_storage():
			return take_storage(item.id, quantity)
		return take_from_shelves(item.id, quantity)

	var possible := mini(quantity, available_units(item))
	if possible <= 0:
		return 0
	var needed := recipe.consumption(possible)
	for ingredient_id in needed:
		take_storage(ingredient_id, int(needed[ingredient_id]))
	changed.emit()
	return possible


## What one costs the business: the wholesale price of a shelf good, or the
## ingredients of a made one.
func cost_basis(item: ItemData) -> int:
	if item == null:
		return 0
	var recipe := recipe_for(item)
	return recipe.ingredient_cost() if recipe != null else item.get_wholesale_cost()


## Seconds to make one, after the barista and any upgrade are taken into
## account. Zero for anything sold off a shelf.
func preparation_seconds(item: ItemData, worker: EmployeeData = null) -> float:
	var recipe := recipe_for(item)
	if recipe == null:
		return 0.0
	var seconds := recipe.preparation_seconds
	if worker != null:
		seconds *= worker.preparation_scale()
	return seconds * (1.0 - upgrade_magnitude(BusinessUpgrade.Effect.PREPARATION_SPEED))


# --- Money ---------------------------------------------------------------

## Cash in. `category` is what the daily report groups it under.
func credit(amount: int, reason: String, category: StringName = &"revenue") -> void:
	amount = absi(amount)
	if amount == 0:
		return
	cash_balance += amount
	if category == &"revenue":
		revenue_today += amount
		lifetime_revenue += amount
	_record(category, amount, reason)
	changed.emit()


## Cash out. Returns false and changes nothing when the account is short, so a
## business can never spend money it does not have.
func debit(amount: int, reason: String, category: StringName = &"other") -> bool:
	amount = absi(amount)
	if amount > cash_balance:
		return false
	cash_balance -= amount
	lifetime_expenses += amount
	match category:
		&"inventory":
			inventory_spend_today += amount
		&"wages":
			wages_today += amount
		&"rent":
			rent_today += amount
		&"equipment":
			equipment_spend_today += amount
		&"marketing":
			marketing_today += amount
		&"utilities":
			utilities_today += amount
		&"loan":
			loan_payments_today += amount
		_:
			other_expense_today += amount
	_record(category, -amount, reason)
	changed.emit()
	return true


func expenses_today() -> int:
	return (
		inventory_spend_today + wages_today + rent_today + equipment_spend_today
		+ marketing_today + utilities_today + loan_payments_today + other_expense_today
	)


## Profit as a share of revenue. Undefined with no revenue, which is reported as
## zero rather than as a divide by zero.
func profit_margin() -> float:
	if revenue_today <= 0:
		return 0.0
	return float(profit_today()) / float(revenue_today)


func lifetime_margin() -> float:
	if lifetime_revenue <= 0:
		return 0.0
	return float(lifetime_profit()) / float(lifetime_revenue)


func profit_today() -> int:
	return revenue_today - expenses_today()


func lifetime_profit() -> int:
	return lifetime_revenue - lifetime_expenses


func get_ledger() -> Array[Dictionary]:
	return _ledger.duplicate()


# --- Stock ---------------------------------------------------------------

func storage_capacity() -> int:
	var definition := type_data()
	var total := definition.base_storage_capacity if definition != null else 60
	for placed in equipment:
		if placed.is_storage():
			total += placed.capacity()
	# Racking counts as much as a rack does.
	return total + roundi(upgrade_magnitude(BusinessUpgrade.Effect.STORAGE))


func storage_used() -> int:
	var total := 0
	for quantity in storage.values():
		total += int(quantity)
	return total


func storage_room_left() -> int:
	return maxi(storage_capacity() - storage_used(), 0)


func storage_of(item_id: StringName) -> int:
	return int(storage.get(item_id, 0))


## Puts stock in the back room. Returns how many actually fitted, so an over-order
## can never conjure space that is not there.
func add_storage(item_id: StringName, quantity: int) -> int:
	var accepted := mini(quantity, storage_room_left())
	if accepted <= 0:
		return 0
	storage[item_id] = storage_of(item_id) + accepted
	changed.emit()
	return accepted


func take_storage(item_id: StringName, quantity: int) -> int:
	var taken := mini(quantity, storage_of(item_id))
	if taken <= 0:
		return 0
	storage[item_id] = storage_of(item_id) - taken
	if int(storage[item_id]) <= 0:
		storage.erase(item_id)
	changed.emit()
	return taken


# --- Equipment -----------------------------------------------------------

func place_equipment(equipment_id: StringName, position: Vector3, rotation_y: float) -> PlacedEquipment:
	var placed := PlacedEquipment.new()
	placed.slot_id = _next_slot
	_next_slot += 1
	placed.equipment_id = equipment_id
	placed.position = position
	placed.rotation_y = rotation_y
	equipment.append(placed)
	changed.emit()
	return placed


## Takes a piece off the floor. Anything on it goes back to the store room if
## there is space for it, so removing a shelf never quietly destroys stock.
func remove_equipment(slot_id: int) -> bool:
	for i in equipment.size():
		if equipment[i].slot_id != slot_id:
			continue
		var placed := equipment[i]
		if placed.stock_quantity > 0 and placed.stock_item != &"":
			add_storage(placed.stock_item, placed.stock_quantity)
		equipment.remove_at(i)
		changed.emit()
		return true
	return false


func equipment_by_slot(slot_id: int) -> PlacedEquipment:
	for placed in equipment:
		if placed.slot_id == slot_id:
			return placed
	return null


func shelves() -> Array[PlacedEquipment]:
	var found: Array[PlacedEquipment] = []
	for placed in equipment:
		if placed.is_shelf():
			found.append(placed)
	return found


func checkouts() -> Array[PlacedEquipment]:
	var found: Array[PlacedEquipment] = []
	for placed in equipment:
		if placed.is_checkout():
			found.append(placed)
	return found


func count_of_role(role: int) -> int:
	var total := 0
	for placed in equipment:
		var definition := placed.data()
		if definition != null and definition.role == role:
			total += 1
	return total


## Units of one product sitting on shelves where a customer could pick it up.
func shelf_stock_of(item_id: StringName) -> int:
	var total := 0
	for placed in shelves():
		if placed.stock_item == item_id:
			total += placed.stock_quantity
	return total


func total_shelf_units() -> int:
	var total := 0
	for placed in shelves():
		total += placed.stock_quantity
	return total


## Moves stock from the back room onto a shelf. Returns how many moved: the
## shelf's capacity and the store room's contents both cap it, which is what
## makes restocking an activity rather than a button.
func stock_shelf(slot_id: int, item_id: StringName, quantity: int) -> int:
	var placed := equipment_by_slot(slot_id)
	if placed == null or not placed.is_shelf() or quantity <= 0:
		return 0
	# A shelf holds one product. Switching it sends whatever was there back.
	if placed.stock_item != item_id and placed.stock_quantity > 0:
		add_storage(placed.stock_item, placed.stock_quantity)
		placed.stock_quantity = 0
	placed.stock_item = item_id

	var wanted := mini(quantity, placed.room_left())
	var moved := take_storage(item_id, wanted)
	placed.stock_quantity += moved
	if moved > 0:
		_low_stock_warned.erase(item_id)
	changed.emit()
	return moved


## Takes one sale's worth off the shelves, nearest-empty first so shelves clear
## rather than all draining together. Returns how many it could actually find.
func take_from_shelves(item_id: StringName, quantity: int) -> int:
	var taken := 0
	for placed in shelves():
		if taken >= quantity:
			break
		if placed.stock_item != item_id or placed.stock_quantity <= 0:
			continue
		var from_here := mini(quantity - taken, placed.stock_quantity)
		placed.stock_quantity -= from_here
		taken += from_here
	if taken > 0:
		changed.emit()
		_check_low_stock(item_id)
	return taken


# --- Pricing -------------------------------------------------------------

func price_of(item: ItemData) -> int:
	if item == null:
		return 0
	if prices.has(item.id):
		return int(prices[item.id])
	return item.get_recommended_price()


func set_price(item: ItemData, value: int) -> void:
	if item == null:
		return
	prices[item.id] = maxi(value, 0)
	changed.emit()


func margin_of(item: ItemData) -> int:
	return price_of(item) - item.get_wholesale_cost() if item != null else 0


## How willing a customer is to pay what this shop is asking, 0-1.
##
## Deliberately a plain curve rather than an economics model: at or under the
## recommended price almost everybody buys, half again is a hard sell, and double
## is a walk-out. Tuning retail pricing means editing these three numbers.
func purchase_chance(item: ItemData) -> float:
	if item == null:
		return 0.0
	var expected := maxi(item.get_recommended_price(), 1)
	var ratio := float(price_of(item)) / float(expected)
	if ratio <= 1.0:
		# Cheap is good, but nobody buys two waters because they are 20c off.
		return clampf(0.95 + (1.0 - ratio) * 0.05, 0.0, 1.0)
	# 1.0 -> 0.95, 1.5 -> ~0.45, 2.0 and up -> almost nobody.
	return clampf(0.95 - (ratio - 1.0) * 1.0, 0.02, 1.0)


# --- Opening -------------------------------------------------------------

## Everything stopping the shop opening right now, as readable lines. Empty
## means it can trade.
func missing_requirements() -> Array[String]:
	var missing: Array[String] = []
	var definition := type_data()
	if definition == null:
		return ["Unknown business type"]
	for role in definition.required_roles:
		if count_of_role(int(role)) <= 0:
			var label := String(EquipmentData.Role.keys()[int(role)]).capitalize()
			missing.append(label)
	# Whatever this kind of business needs that no equipment role describes —
	# seats in a restaurant, somewhere to stand in a venue.
	for line in model().extra_requirements(self):
		if not missing.has(line):
			missing.append(line)

	# What "having stock" means depends on the business. A shop needs goods on a
	# shelf where somebody can pick them up; a kitchen needs enough in the back
	# to make at least one thing on its menu.
	if serves_prepared_goods():
		var can_make_something := false
		for item in catalogue():
			if available_units(item) > 0:
				can_make_something = true
				break
		if not can_make_something:
			missing.append("Ingredients")
	elif total_shelf_units() < definition.minimum_shelf_units:
		missing.append("Stocked shelf")
	return missing


func can_open() -> bool:
	return missing_requirements().is_empty()


func within_opening_hours(hour: int) -> bool:
	if opening_hour == closing_hour:
		return true
	if opening_hour < closing_hour:
		return hour >= opening_hour and hour < closing_hour
	return hour >= opening_hour or hour < closing_hour


## Whether the doors should be open at this hour, taking the owner's manual
## override into account. Requirements always win: a shop with nothing on the
## shelves cannot be forced open.
func should_be_open(hour: int) -> bool:
	if manual_override == Override.FORCE_CLOSED:
		return false
	if not can_open():
		return false
	if manual_override == Override.FORCE_OPEN:
		return true
	return within_opening_hours(hour)


func is_open() -> bool:
	return _open


func set_open(value: bool) -> void:
	if _open == value:
		return
	_open = value
	if _open:
		opened.emit()
	else:
		closed.emit()
	changed.emit()


func status_text() -> String:
	if _open:
		return "OPEN"
	if not can_open():
		return "NOT READY"
	if manual_override == Override.FORCE_CLOSED:
		return "CLOSED"
	return "CLOSED"


# --- Staff ---------------------------------------------------------------

func hire(worker: EmployeeData) -> void:
	worker.assigned_business = business_id
	employees.append(worker)
	changed.emit()


func fire(employee_id: StringName) -> bool:
	for i in employees.size():
		if employees[i].employee_id == employee_id:
			employees.remove_at(i)
			changed.emit()
			return true
	return false


func employee_by_id(employee_id: StringName) -> EmployeeData:
	for worker in employees:
		if worker.employee_id == employee_id:
			return worker
	return null


## Whoever should be doing a given job at this hour, if anybody.
func rostered(role: int, hour: int) -> EmployeeData:
	for worker in employees:
		if worker.role == role and worker.is_on_shift(hour):
			return worker
	return null


## Everybody in that job at this hour. Two cooks are twice a kitchen, and
## Phase O is the point at which that started to matter.
func rostered_all(role: int, hour: int) -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for worker in employees:
		if worker.role == role and worker.is_on_shift(hour):
			found.append(worker)
	return found


## Staff roles the type says it needs, that nobody is covering right now.
func unstaffed_roles(hour: int) -> Array[int]:
	var definition := type_data()
	if definition == null:
		return []
	var missing: Array[int] = []
	for role in definition.required_staff_roles:
		if rostered(int(role), hour) == null:
			missing.append(int(role))
	return missing


## Whoever is serving customers at this hour.
##
## A coffee shop's barista takes the order as well as making it — one person
## behind one counter — so the two roles answer the same question here rather
## than needing two members of staff to sell a cup of tea.
func rostered_cashier(hour: int) -> EmployeeData:
	var cashier := rostered(EmployeeData.Role.CASHIER, hour)
	if cashier != null:
		return cashier
	if serves_prepared_goods():
		return rostered(EmployeeData.Role.BARISTA, hour)
	return null


func rostered_stocker(hour: int) -> EmployeeData:
	return rostered(EmployeeData.Role.STOCKER, hour)


func rostered_barista(hour: int) -> EmployeeData:
	return rostered(EmployeeData.Role.BARISTA, hour)


## The manager, if one is employed. Managers are not rostered by the hour: they
## are the reason the business runs when nobody is looking.
func manager() -> EmployeeData:
	for worker in employees:
		if worker.is_manager():
			return worker
	return null


func has_manager() -> bool:
	return manager() != null


## How much of the manager's automation actually works. A poor manager gets
## most of it right; a good one gets nearly all of it.
func management_quality() -> float:
	var boss := manager()
	return boss.management_quality() if boss != null else 0.0


# --- Trading -------------------------------------------------------------

## One completed sale. The single place stock, money and the day's figures move
## together, so near simulation, far simulation and a player-run till cannot
## disagree about what a sale is worth.
func record_sale(item: ItemData, quantity: int) -> int:
	if item == null or quantity <= 0:
		return 0
	var sold := take_for_sale(item, quantity)
	if sold <= 0:
		return 0
	var unit_price := price_of(item)
	var revenue := unit_price * sold
	cogs_today += cost_basis(item) * sold
	units_sold_today += sold
	lifetime_units_sold += sold
	credit(revenue, "%s x%d" % [item.display_name, sold], &"revenue")
	sale_made.emit(item, sold, revenue)
	return revenue


## Money taken for something that is not an item off a list: a membership, a
## day pass, a fee at the door. Goes through the same ledger and the same
## day's figures as a sale, because to the books it is one.
func record_service_sale(amount: int, reason: String, units: int = 0) -> int:
	if amount <= 0:
		return 0
	service_revenue_today += amount
	units_sold_today += units
	lifetime_units_sold += units
	credit(amount, reason, &"revenue")
	changed.emit()
	return amount


# --- The kitchen ---------------------------------------------------------

## Puts a ticket in. Nothing is taken from the store and nothing is charged
## for until a cook picks it up.
func place_order(who: Object, dish: ItemData, at: float) -> KitchenOrder:
	if dish == null:
		return null
	var order := KitchenOrder.make(_next_order_id, who, dish, at)
	_next_order_id += 1
	kitchen.append(order)
	changed.emit()
	return order


func open_orders() -> Array[KitchenOrder]:
	var found: Array[KitchenOrder] = []
	for order in kitchen:
		if order.is_open():
			found.append(order)
	return found


func orders_waiting() -> int:
	var count := 0
	for order in kitchen:
		if order.stage == KitchenOrder.Stage.WAITING:
			count += 1
	return count


## The oldest ticket nobody has started. First in, first cooked.
func next_unstarted_order() -> KitchenOrder:
	for order in kitchen:
		if order.stage == KitchenOrder.Stage.WAITING:
			return order
	return null


func next_ready_order() -> KitchenOrder:
	for order in kitchen:
		if order.stage == KitchenOrder.Stage.READY:
			return order
	return null


## Forgets everything settled or walked out on, so the list stays the kitchen
## rather than the day's history.
func tidy_kitchen() -> void:
	for i in range(kitchen.size() - 1, -1, -1):
		var order := kitchen[i]
		if order.stage == KitchenOrder.Stage.DELIVERED or order.stage == KitchenOrder.Stage.ABANDONED:
			kitchen.remove_at(i)


func clear_kitchen() -> void:
	kitchen.clear()


## Takes the ingredients for one order out of the store without charging for
## it. The money follows when the plate reaches the table, which is the whole
## reason a restaurant sale is two steps and a shop sale is one.
func reserve_for_order(item: ItemData, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return 0
	var taken := take_for_sale(item, quantity)
	if taken > 0:
		cogs_today += cost_basis(item) * taken
	return taken


## The plate is on the table and paid for. The stock went when it was cooked.
func record_prepared_sale(item: ItemData, quantity: int) -> int:
	if item == null or quantity <= 0:
		return 0
	var revenue := price_of(item) * quantity
	units_sold_today += quantity
	lifetime_units_sold += quantity
	credit(revenue, "%s x%d" % [item.display_name, quantity], &"revenue")
	sale_made.emit(item, quantity, revenue)
	return revenue


func record_customer_visit() -> void:
	customer_count_today += 1
	changed.emit()


func record_lost_sale(reason: StringName = &"") -> void:
	lost_sales_today += 1
	if reason != &"":
		lost_reasons_today[reason] = int(lost_reasons_today.get(reason, 0)) + 1
	changed.emit()


## The day's lost customers, worst reason first.
func lost_reason_breakdown() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for reason: StringName in lost_reasons_today:
		rows.append({
			"reason": reason,
			"label": LostReason.label(reason),
			"count": int(lost_reasons_today[reason]),
		})
	rows.sort_custom(func(a, b): return int(a["count"]) > int(b["count"]))
	return rows


# --- The manager ---------------------------------------------------------

func may(permission: StringName) -> bool:
	return bool(manager_permissions.get(permission, false))


func set_permission(permission: StringName, allowed: bool) -> void:
	manager_permissions[permission] = allowed
	changed.emit()


## What is left of today's allowance. A manager may never spend past it, and
## never past what the business actually holds — the tighter of the two wins,
## which is why this is one number rather than two checks at the call site.
func manager_budget_left() -> int:
	return maxi(mini(auto_order_budget - manager_spent_today, cash_balance), 0)


func note_manager_spend(amount: int) -> void:
	manager_spent_today += maxi(amount, 0)


# --- Cleanliness ---------------------------------------------------------

func uses_cleanliness() -> bool:
	var definition := type_data()
	return definition != null and definition.uses_cleanliness


## Dirt. Silently ignored on a type that does not model it, so the caller never
## has to ask first.
func soil(amount: float) -> void:
	if amount <= 0.0 or not uses_cleanliness():
		return
	cleanliness = clampf(cleanliness - amount, 0.0, 100.0)


func clean(amount: float) -> void:
	if amount <= 0.0:
		return
	cleanliness = clampf(cleanliness + amount, 0.0, 100.0)


func cleanliness_label() -> String:
	if not uses_cleanliness():
		return "n/a"
	if cleanliness >= 85.0:
		return "Spotless"
	if cleanliness >= 65.0:
		return "Clean"
	if cleanliness >= 45.0:
		return "Tired"
	if cleanliness >= 25.0:
		return "Dirty"
	return "Filthy"


# --- Load ----------------------------------------------------------------

## Notes how hard something was worked this hour. Averages rather than the last
## reading, so a quiet hour does not wipe out a busy morning.
func note_load(store: Dictionary, key: Variant, value: float) -> void:
	var entry: Array = store.get(key, [0.0, 0])
	store[key] = [float(entry[0]) + clampf(value, 0.0, 1.0), int(entry[1]) + 1]


func note_role_load(role: int, value: float) -> void:
	note_load(role_load_today, role, value)


func note_equipment_load(id: StringName, value: float) -> void:
	note_load(equipment_load_today, id, value)


static func average_load(store: Dictionary, key: Variant) -> float:
	var entry: Array = store.get(key, [0.0, 0])
	var count := int(entry[1])
	return float(entry[0]) / float(count) if count > 0 else 0.0


# --- Upgrades ------------------------------------------------------------

func has_upgrade(upgrade_id: StringName) -> bool:
	return upgrades.has(upgrade_id)


## Records a bought upgrade. The money is BusinessManager's to move; this is the
## business remembering it owns the thing.
func add_upgrade(upgrade_id: StringName) -> bool:
	if has_upgrade(upgrade_id):
		return false
	upgrades.append(upgrade_id)
	changed.emit()
	return true


## The total effect of everything bought, by kind. Upgrades are looked up by
## what they *do* rather than by name, so a second, better sign later adds to
## the same number instead of needing a special case.
func upgrade_magnitude(effect: int) -> float:
	var total := 0.0
	for id in upgrades:
		var upgrade := BusinessUpgrade.by_id(id)
		if upgrade != null and upgrade.effect == effect:
			total += upgrade.magnitude
	return total


## Reputation cannot drift below whatever the fittings justify.
func reputation_floor() -> float:
	var floors := 0.0
	for id in upgrades:
		var upgrade := BusinessUpgrade.by_id(id)
		if upgrade != null and upgrade.effect == BusinessUpgrade.Effect.REPUTATION_FLOOR:
			floors = maxf(floors, upgrade.magnitude)
	return floors


# --- Marketing -----------------------------------------------------------

func start_campaign(campaign: MarketingCampaign) -> void:
	if campaign == null:
		return
	campaign.start(TimeManager.day_index)
	campaigns.append(campaign)
	changed.emit()


func active_campaigns() -> Array[MarketingCampaign]:
	var running: Array[MarketingCampaign] = []
	for campaign in campaigns:
		if campaign.is_running(TimeManager.day_index):
			running.append(campaign)
	return running


## Drops anything that has run its course. Called on the day rollover, so a
## campaign expires on the clock rather than when somebody happens to look.
func expire_campaigns() -> int:
	var before := campaigns.size()
	campaigns = active_campaigns()
	if campaigns.size() != before:
		changed.emit()
	return before - campaigns.size()


## How much more trade the advertising is buying, as a multiplier.
func marketing_bonus() -> float:
	var bonus := 0.0
	for campaign in active_campaigns():
		bonus += campaign.demand_bonus
	return bonus


# --- Loans ---------------------------------------------------------------

func add_loan(loan: Loan) -> void:
	loans.append(loan)
	changed.emit()


func active_loans() -> Array[Loan]:
	var live: Array[Loan] = []
	for loan in loans:
		if loan.is_active():
			live.append(loan)
	return live


func total_debt() -> int:
	var total := 0
	for loan in active_loans():
		total += loan.remaining_balance
	return total


func has_overdue_loan() -> bool:
	for loan in active_loans():
		if loan.missed_payments > 0:
			return true
	return false


# --- Worth ---------------------------------------------------------------

## What the equipment on the floor would fetch. Second hand, so half of what it
## cost — enough that fitting a shop out is not simply money burnt.
func equipment_value() -> int:
	var total := 0
	for placed in equipment:
		var definition := placed.data()
		if definition != null:
			total += roundi(float(definition.purchase_price) * 0.5)
	return total


## Stock at what it cost, wherever it is sitting.
func inventory_value() -> int:
	var total := 0
	for item_id in storage:
		var item := ItemCatalogue.by_id(item_id)
		if item != null:
			total += item.get_wholesale_cost() * int(storage[item_id])
	for placed in shelves():
		var shelf_item := placed.item()
		if shelf_item != null:
			total += shelf_item.get_wholesale_cost() * placed.stock_quantity
	return total


## What the business is worth.
##
## Assets plus a multiple of what it earns, adjusted for how well it is thought
## of, less what it owes. The earnings multiple is what makes a profitable shop
## worth more than the sum of its shelves, and the reputation factor is what
## makes a well-run one worth more than a neglected one with the same stock.
func estimated_value() -> int:
	var assets := cash_balance + equipment_value() + inventory_value()
	# A fortnight of recent daily profit, annualised in game terms.
	var goodwill := roundi(float(average_daily_profit()) * 14.0)
	var standing := lerpf(0.75, 1.25, clampf(reputation / 100.0, 0.0, 1.0))
	var value := roundi(float(assets + maxi(goodwill, 0)) * standing) - total_debt()
	return maxi(value, 0)


## What the player would actually be paid for it. A buyer wants a discount, and
## the debt comes off the top.
func sale_price() -> int:
	return maxi(roundi(float(estimated_value()) * 0.85), 0)


## Mean daily profit across the reports kept. Zero before the first full day, so
## a shop opened this morning is worth its assets and nothing more.
func average_daily_profit() -> int:
	if recent_reports.is_empty():
		return 0
	var total := 0
	for report in recent_reports:
		total += int(report.get("profit", 0))
	return roundi(float(total) / float(recent_reports.size()))


## A rough tier, for display. Nothing is locked behind it.
func level() -> int:
	if lifetime_revenue >= 25000 and reputation >= 60.0:
		return 3
	return 2 if lifetime_revenue >= 6000 else 1


# --- Reputation ----------------------------------------------------------

## Customer satisfaction feeds in as small nudges; the day's total movement is
## clamped so a shop drifts rather than swings.
func add_satisfaction(delta: float) -> void:
	reputation = clampf(reputation + clampf(delta, -1.5, 1.5), reputation_floor(), 100.0)


## Multiplier on how many customers turn up, from reputation. Kept narrow on
## purpose: a bad shop is quieter, not dead.
func reputation_multiplier() -> float:
	return lerpf(0.6, 1.35, clampf(reputation / 100.0, 0.0, 1.0))


## The unit this trades from, or null. Looked up rather than held, so a lease
## that ends cannot leave a business pointing at a property it no longer has.
func property() -> CommercialProperty:
	return PropertyManager.by_id(property_id)


## What the address itself is worth in trade: the pitch and the part of town.
##
## Two factors rather than one number per unit, because they answer different
## questions. The unit's own modifier is the address within its district — a
## back street against the main road against the plaza — and the district's is
## how busy that part of the city is at all. A premium Central pitch therefore
## earns both, which is what makes its rent worth paying.
func location_multiplier() -> float:
	var unit := property()
	if unit == null:
		return 1.0
	var district := WorldManager.by_id(unit.district_id)
	var district_factor := district.commercial_demand_modifier if district != null else 1.0
	return unit.location_demand_modifier * district_factor


## How many customers may be inside at once, and how long a queue they will
## stand in. Both come from the property: a small unit is a small shop.
func customer_capacity() -> int:
	var unit := property()
	return unit.customer_capacity if unit != null else 6


func queue_capacity() -> int:
	var unit := property()
	return unit.queue_capacity if unit != null else 4


# --- The day -------------------------------------------------------------

## Closes the books. Returns the report and resets the daily counters; lifetime
## totals and the ledger carry on.
func end_day(day_index: int) -> Dictionary:
	var report := {
		"day": day_index,
		"business": business_name,
		"customers": customer_count_today,
		"revenue": revenue_today,
		"inventory": inventory_spend_today,
		"wages": wages_today,
		"rent": rent_today,
		"equipment": equipment_spend_today,
		"marketing": marketing_today,
		"utilities": utilities_today,
		"loans": loan_payments_today,
		"other": other_expense_today,
		"expenses": expenses_today(),
		"profit": profit_today(),
		"margin": profit_margin(),
		"cogs": cogs_today,
		"gross_margin": revenue_today - cogs_today,
		"units_sold": units_sold_today,
		"lost_sales": lost_sales_today,
		"lost_reasons": lost_reasons_today.duplicate(),
		"service_revenue": service_revenue_today,
		"members": members,
		"cleanliness": roundi(cleanliness),
		"reputation": roundi(reputation),
		"cash": cash_balance,
		"value": estimated_value(),
	}
	last_report = report
	recent_reports.append(report)
	# A week of history: enough for the weekly figures and for the earnings
	# multiple the valuation uses, and it never grows.
	while recent_reports.size() > 7:
		recent_reports.remove_at(0)
	day_finished.emit(report)

	revenue_today = 0
	inventory_spend_today = 0
	wages_today = 0
	rent_today = 0
	equipment_spend_today = 0
	marketing_today = 0
	utilities_today = 0
	loan_payments_today = 0
	other_expense_today = 0
	cogs_today = 0
	customer_count_today = 0
	lost_sales_today = 0
	units_sold_today = 0
	service_revenue_today = 0
	manager_spent_today = 0
	lost_reasons_today.clear()
	role_load_today.clear()
	equipment_load_today.clear()
	for worker in employees:
		worker.hours_worked_today = 0.0
		worker.customers_served_today = 0
		worker.sales_processed_today = 0
	_low_stock_warned.clear()
	changed.emit()
	return report


## The last seven days added up. Weekly is the horizon a small business actually
## plans on: rent and loan payments both fall on that cycle.
func weekly_report() -> Dictionary:
	var totals := {
		"days": recent_reports.size(), "revenue": 0, "cogs": 0, "wages": 0,
		"rent": 0, "marketing": 0, "utilities": 0, "loans": 0, "inventory": 0,
		"equipment": 0, "other": 0, "expenses": 0, "profit": 0, "customers": 0,
		"units_sold": 0, "lost_sales": 0,
	}
	for report in recent_reports:
		for key in totals:
			if key == "days":
				continue
			totals[key] = int(totals[key]) + int(report.get(key, 0))
	totals["margin"] = (
		float(totals["profit"]) / float(totals["revenue"]) if int(totals["revenue"]) > 0 else 0.0
	)
	totals["average_sale"] = (
		float(totals["revenue"]) / float(totals["customers"]) if int(totals["customers"]) > 0 else 0.0
	)
	return totals


# --- Internals -----------------------------------------------------------

func _check_low_stock(item_id: StringName) -> void:
	if _low_stock_warned.has(item_id):
		return
	if shelf_stock_of(item_id) > LOW_STOCK_THRESHOLD:
		return
	_low_stock_warned[item_id] = true
	var item := ItemCatalogue.by_id(item_id)
	if item != null:
		stock_low.emit(item)


func _record(category: StringName, amount: int, reason: String) -> void:
	_ledger.append({
		"category": String(category),
		"amount": amount,
		"reason": reason,
		"balance": cash_balance,
		"day": TimeManager.day_index,
		"time": TimeManager.get_time_string(),
	})
	if _ledger.size() > 200:
		_ledger.remove_at(0)


# --- Save ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var placed_equipment: Array = []
	for placed in equipment:
		placed_equipment.append(placed.to_dict())
	var staff: Array = []
	for worker in employees:
		staff.append(worker.to_dict())
	var stored := {}
	for key in storage:
		stored[String(key)] = int(storage[key])
	var priced := {}
	for key in prices:
		priced[String(key)] = int(prices[key])

	var bought: Array = []
	for id in upgrades:
		bought.append(String(id))
	var running: Array = []
	for campaign in campaigns:
		running.append(campaign.to_dict())
	var borrowed: Array = []
	for loan in loans:
		borrowed.append(loan.to_dict())

	return {
		"id": String(business_id),
		"name": business_name,
		"type": String(type_id),
		"owner": String(owner_id),
		"property": String(property_id),
		"cash": cash_balance,
		"upgrades": bought,
		"campaigns": running,
		"loans": borrowed,
		"auto_open": auto_open,
		"auto_restock": auto_restock,
		"auto_order": auto_order,
		"auto_order_budget": auto_order_budget,
		"auto_order_minimum": auto_order_minimum,
		"auto_order_target": auto_order_target,
		"manager_permissions": manager_permissions.duplicate(),
		"cleanliness_target": cleanliness_target,
		"wages_owed": wages_owed,
		"lifetime_interest_paid": lifetime_interest_paid,
		"recent_reports": recent_reports,
		"opening_hour": opening_hour,
		"closing_hour": closing_hour,
		"override": int(manual_override),
		"reputation": reputation,
		"cleanliness": cleanliness,
		"brand": String(brand_id),
		"membership_price": membership_price,
		"day_pass_price": day_pass_price,
		"entry_fee": entry_fee,
		"members": members,
		"storage": stored,
		"prices": priced,
		"equipment": placed_equipment,
		"employees": staff,
		"next_slot": _next_slot,
		"founded_on_day": founded_on_day,
		"lifetime_revenue": lifetime_revenue,
		"lifetime_expenses": lifetime_expenses,
		"lifetime_units_sold": lifetime_units_sold,
		"revenue_today": revenue_today,
		"inventory_today": inventory_spend_today,
		"wages_today": wages_today,
		"rent_today": rent_today,
		"equipment_today": equipment_spend_today,
		"other_today": other_expense_today,
		"cogs_today": cogs_today,
		"marketing_today": marketing_today,
		"utilities_today": utilities_today,
		"loans_today": loan_payments_today,
		"customers_today": customer_count_today,
		"lost_sales_today": lost_sales_today,
		"lost_reasons_today": lost_reasons_today.duplicate(),
		"service_revenue_today": service_revenue_today,
		"units_today": units_sold_today,
		"last_report": last_report,
	}


static func from_dict(state: Dictionary) -> BusinessInstance:
	var business := BusinessInstance.new()
	business.business_id = StringName(state.get("id", ""))
	business.business_name = String(state.get("name", "Business"))
	business.type_id = StringName(state.get("type", "convenience_store"))
	business.owner_id = StringName(state.get("owner", "player"))
	business.property_id = StringName(state.get("property", ""))
	business.cash_balance = int(state.get("cash", 0))
	business.opening_hour = int(state.get("opening_hour", 8))
	business.closing_hour = int(state.get("closing_hour", 20))
	business.manual_override = int(state.get("override", 0)) as Override
	business.reputation = float(state.get("reputation", 50.0))
	# A save written before cleanliness existed describes a business nobody had
	# to clean, so it loads spotless rather than filthy. §123 is about not
	# resetting a business that *does* track it, and it does not.
	business.cleanliness = clampf(float(state.get("cleanliness", 100.0)), 0.0, 100.0)
	business.brand_id = StringName(state.get("brand", ""))
	business.membership_price = int(state.get("membership_price", 40))
	business.day_pass_price = int(state.get("day_pass_price", 9))
	business.entry_fee = int(state.get("entry_fee", 0))
	business.members = int(state.get("members", 0))
	business.founded_on_day = int(state.get("founded_on_day", 0))
	business._next_slot = int(state.get("next_slot", 1))

	for key in state.get("storage", {}):
		business.storage[StringName(key)] = int(state["storage"][key])
	for key in state.get("prices", {}):
		business.prices[StringName(key)] = int(state["prices"][key])
	for entry in state.get("equipment", []):
		business.equipment.append(PlacedEquipment.from_dict(entry))
	for entry in state.get("employees", []):
		business.employees.append(EmployeeData.from_dict(entry))

	business.lifetime_revenue = int(state.get("lifetime_revenue", 0))
	business.lifetime_expenses = int(state.get("lifetime_expenses", 0))
	business.lifetime_units_sold = int(state.get("lifetime_units_sold", 0))
	business.revenue_today = int(state.get("revenue_today", 0))
	business.inventory_spend_today = int(state.get("inventory_today", 0))
	business.wages_today = int(state.get("wages_today", 0))
	business.rent_today = int(state.get("rent_today", 0))
	business.equipment_spend_today = int(state.get("equipment_today", 0))
	business.other_expense_today = int(state.get("other_today", 0))
	business.marketing_today = int(state.get("marketing_today", 0))
	business.utilities_today = int(state.get("utilities_today", 0))
	business.loan_payments_today = int(state.get("loans_today", 0))
	business.cogs_today = int(state.get("cogs_today", 0))
	business.customer_count_today = int(state.get("customers_today", 0))
	business.lost_sales_today = int(state.get("lost_sales_today", 0))
	for key in state.get("lost_reasons_today", {}):
		business.lost_reasons_today[StringName(key)] = int(state["lost_reasons_today"][key])
	business.service_revenue_today = int(state.get("service_revenue_today", 0))
	business.units_sold_today = int(state.get("units_today", 0))
	business.last_report = state.get("last_report", {})

	for id in state.get("upgrades", []):
		business.upgrades.append(StringName(id))
	for entry in state.get("campaigns", []):
		var campaign := MarketingCampaign.from_dict(entry)
		if campaign != null:
			business.campaigns.append(campaign)
	for entry in state.get("loans", []):
		business.loans.append(Loan.from_dict(entry))
	for entry in state.get("recent_reports", []):
		business.recent_reports.append(entry)

	# Absent from a Phase H save, and off is the right answer for one: nothing
	# should start spending the player's money because they loaded a game.
	business.auto_open = bool(state.get("auto_open", false))
	business.auto_restock = bool(state.get("auto_restock", false))
	business.auto_order = bool(state.get("auto_order", false))
	business.auto_order_budget = int(state.get("auto_order_budget", 500))
	business.auto_order_minimum = int(state.get("auto_order_minimum", 15))
	business.auto_order_target = int(state.get("auto_order_target", 45))
	for key in state.get("manager_permissions", {}):
		business.manager_permissions[StringName(key)] = bool(state["manager_permissions"][key])
	business.cleanliness_target = int(state.get("cleanliness_target", 70))
	business.wages_owed = int(state.get("wages_owed", 0))
	business.lifetime_interest_paid = int(state.get("lifetime_interest_paid", 0))
	return business
