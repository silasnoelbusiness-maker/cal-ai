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

var storage: Dictionary = {}
var prices: Dictionary = {}
var equipment: Array[PlacedEquipment] = []
var employees: Array[EmployeeData] = []

var revenue_today: int = 0
var inventory_spend_today: int = 0
var wages_today: int = 0
var rent_today: int = 0
var equipment_spend_today: int = 0
var other_expense_today: int = 0
## Cost basis of what was actually sold today. Reported as gross margin, and
## deliberately NOT part of expenses_today — the cash for that stock was already
## counted when it was ordered. Adding both is the double count the brief warns
## about.
var cogs_today: int = 0
var customer_count_today: int = 0
var lost_sales_today: int = 0
var units_sold_today: int = 0

var lifetime_revenue: int = 0
var lifetime_expenses: int = 0
var lifetime_units_sold: int = 0
var founded_on_day: int = 0
var last_report: Dictionary = {}

var _ledger: Array[Dictionary] = []
var _next_slot: int = 1
var _open: bool = false
var _low_stock_warned: Dictionary = {}


# --- Identity ------------------------------------------------------------

func type_data() -> BusinessTypeData:
	return BusinessCatalogue.by_id(type_id)


func catalogue() -> Array[ItemData]:
	var definition := type_data()
	return definition.catalogue if definition != null else [] as Array[ItemData]


func sells(item: ItemData) -> bool:
	return item != null and catalogue().has(item)


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
		_:
			other_expense_today += amount
	_record(category, -amount, reason)
	changed.emit()
	return true


func expenses_today() -> int:
	return (
		inventory_spend_today + wages_today + rent_today
		+ equipment_spend_today + other_expense_today
	)


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
	return total


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
	if total_shelf_units() < definition.minimum_shelf_units:
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


## The cashier who should be behind the register at this hour, if any.
func rostered_cashier(hour: int) -> EmployeeData:
	for worker in employees:
		if worker.role == EmployeeData.Role.CASHIER and worker.is_on_shift(hour):
			return worker
	return null


# --- Trading -------------------------------------------------------------

## One completed sale. The single place stock, money and the day's figures move
## together, so near simulation, far simulation and a player-run till cannot
## disagree about what a sale is worth.
func record_sale(item: ItemData, quantity: int) -> int:
	if item == null or quantity <= 0:
		return 0
	var sold := take_from_shelves(item.id, quantity)
	if sold <= 0:
		return 0
	var unit_price := price_of(item)
	var revenue := unit_price * sold
	cogs_today += item.get_wholesale_cost() * sold
	units_sold_today += sold
	lifetime_units_sold += sold
	credit(revenue, "%s x%d" % [item.display_name, sold], &"revenue")
	sale_made.emit(item, sold, revenue)
	return revenue


func record_customer_visit() -> void:
	customer_count_today += 1
	changed.emit()


func record_lost_sale() -> void:
	lost_sales_today += 1
	changed.emit()


# --- Reputation ----------------------------------------------------------

## Customer satisfaction feeds in as small nudges; the day's total movement is
## clamped so a shop drifts rather than swings.
func add_satisfaction(delta: float) -> void:
	reputation = clampf(reputation + clampf(delta, -1.5, 1.5), 0.0, 100.0)


## Multiplier on how many customers turn up, from reputation. Kept narrow on
## purpose: a bad shop is quieter, not dead.
func reputation_multiplier() -> float:
	return lerpf(0.6, 1.35, clampf(reputation / 100.0, 0.0, 1.0))


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
		"other": other_expense_today,
		"expenses": expenses_today(),
		"profit": profit_today(),
		"cogs": cogs_today,
		"gross_margin": revenue_today - cogs_today,
		"units_sold": units_sold_today,
		"lost_sales": lost_sales_today,
		"reputation": roundi(reputation),
		"cash": cash_balance,
	}
	last_report = report
	day_finished.emit(report)

	revenue_today = 0
	inventory_spend_today = 0
	wages_today = 0
	rent_today = 0
	equipment_spend_today = 0
	other_expense_today = 0
	cogs_today = 0
	customer_count_today = 0
	lost_sales_today = 0
	units_sold_today = 0
	for worker in employees:
		worker.hours_worked_today = 0.0
		worker.customers_served_today = 0
		worker.sales_processed_today = 0
	_low_stock_warned.clear()
	changed.emit()
	return report


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

	return {
		"id": String(business_id),
		"name": business_name,
		"type": String(type_id),
		"owner": String(owner_id),
		"property": String(property_id),
		"cash": cash_balance,
		"opening_hour": opening_hour,
		"closing_hour": closing_hour,
		"override": int(manual_override),
		"reputation": reputation,
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
		"customers_today": customer_count_today,
		"lost_sales_today": lost_sales_today,
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
	business.cogs_today = int(state.get("cogs_today", 0))
	business.customer_count_today = int(state.get("customers_today", 0))
	business.lost_sales_today = int(state.get("lost_sales_today", 0))
	business.units_sold_today = int(state.get("units_today", 0))
	business.last_report = state.get("last_report", {})
	return business
