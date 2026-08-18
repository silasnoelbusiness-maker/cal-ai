extends Node
## Every business the player owns, and the clock that runs them.
##
## Owns three things: the register of businesses, the boundary between the
## player's pocket and a business account, and the tick that opens the doors,
## pays the staff, serves the customers nobody is watching and closes the books.
##
## The two simulations — visible customers when the player is in the shop,
## aggregated trade when they are not — deliberately share their rules with
## CustomerDemand rather than each having their own, so a shop earns the same
## either way. See `_simulate_far_trade`.

signal business_created(business: BusinessInstance)
signal business_changed(business: BusinessInstance)
signal business_opened(business: BusinessInstance)
signal business_closed(business: BusinessInstance)
signal day_report_ready(business: BusinessInstance, report: Dictionary)
signal funds_transferred(business: BusinessInstance, amount: int)
signal candidates_refreshed()

enum TransferResult { OK, NO_BUSINESS, NOT_ENOUGH_FUNDS, INVALID_AMOUNT }
enum PurchaseResult { OK, NO_BUSINESS, NOT_ENOUGH_FUNDS, NO_SUCH_ITEM, NO_ROOM, NOT_ALLOWED }

@export var save_id: StringName = &"business_manager"

## How many candidates the hiring screen offers at a time.
@export var candidate_pool_size: int = 3
## Metres from a shop's own door beyond which its trade is simulated rather than
## acted out. The interior reports presence directly; this covers the case of a
## player stood outside their own unit.
@export var near_radius: float = 25.0

## Counters a statistics screen will read. Kept flat for the same reason as the
## crime ones: adding a counter is a key here and a call to `_tally`.
const STATISTIC_KEYS: Array[StringName] = [
	&"businesses_founded", &"employees_hired", &"products_sold",
	&"business_revenue", &"business_profit", &"highest_daily_profit",
]

var _businesses: Dictionary = {}
var _order: Array[StringName] = []
var _candidates: Array[EmployeeData] = []
var _statistics: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _next_business_number: int = 1
var _next_employee_number: int = 1
## business_id -> fractional customers owed by the far simulation.
var _pending_customers: Dictionary = {}
## business_id -> the in-game minute up to which trade has been accounted for.
## Both simulations advance it, which is what stops an hour being billed twice
## when the player walks out half way through one.
var _traded_to: Dictionary = {}
## business_id -> true while the player is inside that unit.
var _player_present: Dictionary = {}
## business_id -> Array of equipment ids bought but not yet put down.
var _unplaced_equipment: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_reset_statistics()
	add_to_group(&"saveable")
	TimeManager.minute_passed.connect(_on_minute_passed)
	TimeManager.hour_passed.connect(_on_hour_passed)
	TimeManager.day_passed.connect(_on_day_passed)
	refresh_candidates()


# --- Register ------------------------------------------------------------

func get_businesses() -> Array[BusinessInstance]:
	var found: Array[BusinessInstance] = []
	for id in _order:
		found.append(_businesses[id])
	return found


func by_id(business_id: StringName) -> BusinessInstance:
	return _businesses.get(business_id)


func business_for_property(property_id: StringName) -> BusinessInstance:
	if property_id == &"":
		return null
	for business in get_businesses():
		if business.property_id == property_id:
			return business
	return null


func owned_count() -> int:
	return _order.size()


## The one the management screen opens on when the player has not said which.
func primary_business() -> BusinessInstance:
	return _businesses.get(_order[0]) if not _order.is_empty() else null


## Founds a business in a unit the player already holds the lease on. Creating a
## business is free and creates no money: the account starts empty and the player
## funds it themselves.
func create_business(
	business_name: String, type_id: StringName, property: CommercialProperty
) -> BusinessInstance:
	if property == null or not property.is_leased_by_player():
		GameManager.notify("YOU DO NOT HOLD THAT LEASE", GameManager.Tone.BAD)
		return null
	if business_for_property(property.property_id) != null:
		GameManager.notify("THAT UNIT ALREADY HAS A BUSINESS", GameManager.Tone.BAD)
		return null

	var definition := BusinessCatalogue.by_id(type_id)
	if definition == null:
		return null

	var business := BusinessInstance.new()
	business.business_id = StringName("business_%d" % _next_business_number)
	_next_business_number += 1
	business.business_name = business_name.strip_edges()
	if business.business_name.is_empty():
		business.business_name = definition.display_name
	business.type_id = definition.type_id
	business.property_id = property.property_id
	business.opening_hour = definition.default_opening_hour
	business.closing_hour = definition.default_closing_hour
	business.founded_on_day = TimeManager.day_index

	_register(business)
	_add_statistic(&"businesses_founded")
	GameManager.notify(
		"BUSINESS CREATED\n%s" % business.business_name.to_upper(), GameManager.Tone.GOOD
	)
	business_created.emit(business)
	return business


func _register(business: BusinessInstance) -> void:
	_businesses[business.business_id] = business
	if not _order.has(business.business_id):
		_order.append(business.business_id)
	business.changed.connect(_on_business_changed.bind(business))
	business.stock_low.connect(_on_stock_low.bind(business))
	business.sale_made.connect(_on_sale_made.bind(business))


# --- The money boundary --------------------------------------------------

## Player pocket -> business account. Both ledgers record it, which is what makes
## "where did my money go" answerable from either side.
func deposit_to_business(business: BusinessInstance, amount: int) -> TransferResult:
	if business == null:
		return TransferResult.NO_BUSINESS
	amount = absi(amount)
	if amount <= 0:
		return TransferResult.INVALID_AMOUNT
	if not EconomyManager.can_afford(amount):
		return TransferResult.NOT_ENOUGH_FUNDS
	EconomyManager.spend(amount, "%s — capital injection" % business.business_name)
	business.credit(amount, "Owner capital", &"capital")
	funds_transferred.emit(business, amount)
	return TransferResult.OK


## Business account -> player pocket.
func withdraw_from_business(business: BusinessInstance, amount: int) -> TransferResult:
	if business == null:
		return TransferResult.NO_BUSINESS
	amount = absi(amount)
	if amount <= 0:
		return TransferResult.INVALID_AMOUNT
	if not business.debit(amount, "Owner drawing", &"drawing"):
		return TransferResult.NOT_ENOUGH_FUNDS
	EconomyManager.deposit(amount, "%s — owner drawing" % business.business_name)
	funds_transferred.emit(business, -amount)
	return TransferResult.OK


# --- Buying --------------------------------------------------------------

## Buys a piece of equipment. It arrives as an unplaced item the player then puts
## somewhere — see PlacementController — rather than appearing on the floor.
func buy_equipment(business: BusinessInstance, equipment_id: StringName) -> PurchaseResult:
	if business == null:
		return PurchaseResult.NO_BUSINESS
	var definition := EquipmentCatalogue.by_id(equipment_id)
	if definition == null:
		return PurchaseResult.NO_SUCH_ITEM
	if not definition.allows(business.type_id):
		return PurchaseResult.NOT_ALLOWED
	if not business.debit(
		definition.purchase_price, "Equipment — %s" % definition.display_name, &"equipment"
	):
		return PurchaseResult.NOT_ENOUGH_FUNDS
	_unplaced(business).append(equipment_id)
	business_changed.emit(business)
	return PurchaseResult.OK


func _unplaced(business: BusinessInstance) -> Array:
	if not _unplaced_equipment.has(business.business_id):
		_unplaced_equipment[business.business_id] = []
	return _unplaced_equipment[business.business_id]


func unplaced_equipment(business: BusinessInstance) -> Array:
	return _unplaced(business).duplicate()


func has_unplaced(business: BusinessInstance, equipment_id: StringName) -> bool:
	return _unplaced(business).has(equipment_id)


## Takes one out of the delivery pile. Called by the placement controller the
## moment a piece is actually set down.
func consume_unplaced(business: BusinessInstance, equipment_id: StringName) -> bool:
	var pile := _unplaced(business)
	var index := pile.find(equipment_id)
	if index < 0:
		return false
	pile.remove_at(index)
	business_changed.emit(business)
	return true


## Puts a piece back in the pile — used when equipment is picked up again.
func return_unplaced(business: BusinessInstance, equipment_id: StringName) -> void:
	_unplaced(business).append(equipment_id)
	business_changed.emit(business)


## Orders stock at wholesale. Money leaves the business account and the goods
## land in the back room; anything the store room has no space for is not
## ordered and not charged for.
func order_stock(business: BusinessInstance, item_id: StringName, quantity: int) -> PurchaseResult:
	if business == null:
		return PurchaseResult.NO_BUSINESS
	var item := ItemCatalogue.by_id(item_id)
	if item == null or not business.sells(item):
		return PurchaseResult.NO_SUCH_ITEM
	quantity = mini(maxi(quantity, 0), business.storage_room_left())
	if quantity <= 0:
		return PurchaseResult.NO_ROOM

	var cost := item.get_wholesale_cost() * quantity
	if not business.debit(
		cost, "Stock — %s x%d" % [item.display_name, quantity], &"inventory"
	):
		return PurchaseResult.NOT_ENOUGH_FUNDS
	business.add_storage(item_id, quantity)
	business_changed.emit(business)
	return PurchaseResult.OK


static func describe_purchase(result: PurchaseResult) -> String:
	match result:
		PurchaseResult.NOT_ENOUGH_FUNDS:
			return "NOT ENOUGH BUSINESS FUNDS"
		PurchaseResult.NO_ROOM:
			return "NO ROOM IN THE STORE ROOM"
		PurchaseResult.NO_SUCH_ITEM:
			return "NOT SOMETHING YOU SELL"
		PurchaseResult.NOT_ALLOWED:
			return "NOT FOR THIS BUSINESS"
		PurchaseResult.NO_BUSINESS:
			return "NO BUSINESS"
		_:
			return ""


# --- Hiring --------------------------------------------------------------

func get_candidates() -> Array[EmployeeData]:
	return _candidates.duplicate()


func refresh_candidates() -> void:
	_candidates.clear()
	for i in candidate_pool_size:
		_candidates.append(
			EmployeeData.generate(_rng, StringName("worker_%d" % _next_employee_number))
		)
		_next_employee_number += 1
	candidates_refreshed.emit()


func hire(business: BusinessInstance, candidate: EmployeeData) -> bool:
	if business == null or candidate == null:
		return false
	business.hire(candidate)
	_candidates.erase(candidate)
	_add_statistic(&"employees_hired")
	GameManager.notify(
		"HIRED %s\n$%d/hour" % [candidate.employee_name.to_upper(), candidate.hourly_wage],
		GameManager.Tone.GOOD
	)
	business_changed.emit(business)
	return true


# --- Presence ------------------------------------------------------------

## Told by the interior when the player walks in or out. Presence decides which
## simulation runs, and nothing else.
func set_player_present(business_id: StringName, present: bool) -> void:
	if present:
		_player_present[business_id] = true
	else:
		_player_present.erase(business_id)


func is_player_present(business: BusinessInstance) -> bool:
	return business != null and _player_present.has(business.business_id)


func simulation_mode(business: BusinessInstance) -> String:
	return "NEAR" if is_player_present(business) else "FAR"


# --- The clock -----------------------------------------------------------

func _on_minute_passed(hour: int, _minute: int) -> void:
	for business in get_businesses():
		_update_open_state(business, hour)


## The hour is the unit the far simulation works in.
##
## Not the minute: the clock jumps whole hours when the player sleeps or works a
## shift, and `minute_passed` fires once for the whole jump. Settling by the hour
## means a shop left open trades through a skipped afternoon exactly as it would
## have traded through a watched one.
func _on_hour_passed(hour: int) -> void:
	for business in get_businesses():
		_update_open_state(business, hour)
		_accrue_wages(business, hour)
		_settle_trade(business)


func _on_day_passed(day_index: int) -> void:
	for business in get_businesses():
		# Anybody still clocked on is paid off before the books close.
		_pay_off_all(business)
		var report := business.end_day(day_index)
		_tally_report(report)
		day_report_ready.emit(business, report)
		GameManager.notify(
			"DAILY REPORT READY\n%s  profit $%d" % [
				business.business_name.to_upper(), int(report.get("profit", 0))
			],
			GameManager.Tone.INFO
		)
		if business.cash_balance < 100:
			GameManager.notify(
				"LOW BUSINESS FUNDS\n%s" % business.business_name.to_upper(), GameManager.Tone.BAD
			)


func _update_open_state(business: BusinessInstance, hour: int) -> void:
	var wanted := business.should_be_open(hour)
	if wanted == business.is_open():
		return
	business.set_open(wanted)
	if wanted:
		GameManager.notify("BUSINESS OPEN\n%s" % business.business_name.to_upper(), GameManager.Tone.GOOD)
		business_opened.emit(business)
	else:
		GameManager.notify("BUSINESS CLOSED\n%s" % business.business_name.to_upper(), GameManager.Tone.INFO)
		business_closed.emit(business)


# --- Wages ---------------------------------------------------------------

## An hour on shift is an hour owed. The money only moves when the shift ends,
## so the ledger reads as one wage payment rather than eight.
func _accrue_wages(business: BusinessInstance, hour: int) -> void:
	for worker in business.employees:
		if worker.is_on_shift(hour):
			worker.hours_worked_today += 1.0
			worker.hours_unpaid += 1.0
		elif worker.hours_unpaid > 0.0:
			_pay(business, worker)


func _pay_off_all(business: BusinessInstance) -> void:
	for worker in business.employees:
		if worker.hours_unpaid > 0.0:
			_pay(business, worker)


func _pay(business: BusinessInstance, worker: EmployeeData) -> void:
	var due := worker.wage_for_hours(worker.hours_unpaid)
	worker.hours_unpaid = 0.0
	if due <= 0:
		return
	# An account too short for the wage bill still owes it: the shift is worked
	# either way, so it goes on as an expense the account can carry into the red
	# of its own reporting rather than silently vanishing.
	if not business.debit(due, "Wages — %s" % worker.employee_name, &"wages"):
		business.debit(business.cash_balance, "Wages — %s (part)" % worker.employee_name, &"wages")
		GameManager.notify(
			"COULD NOT COVER WAGES\n%s" % worker.employee_name.to_upper(), GameManager.Tone.BAD
		)
	GameManager.notify(
		"EMPLOYEE SHIFT ENDED\n%s  -$%d" % [worker.employee_name.to_upper(), due],
		GameManager.Tone.INFO
	)


# --- Far simulation ------------------------------------------------------

## Marks trade as accounted for up to now. Called by the visible simulation every
## minute it runs, so the far simulation never re-bills a period the player was
## stood in the shop for.
func note_visible_trade(business: BusinessInstance) -> void:
	if business != null:
		_traded_to[business.business_id] = TimeManager.total_minutes


## Trade while nobody is watching.
##
## Same arrival rate and same purchase rules as the visible customers — the only
## thing missing is the walking. A shop left running across town therefore earns
## what it would have earned with the player stood in it, which is the property
## the brief asks for and the reason both paths call CustomerDemand.
##
## Whole hours are settled one at a time so a skipped day is simulated hour by
## hour against the shop's own opening times, rather than as one lump at
## whatever hour the player happened to wake up.
func _settle_trade(business: BusinessInstance) -> void:
	var now := TimeManager.total_minutes
	if is_player_present(business):
		_traded_to[business.business_id] = now
		return

	var settled: float = float(_traded_to.get(business.business_id, now))
	# A save loaded from days ago, or a first tick: start from now rather than
	# simulating a week of trading in one frame.
	if now - settled > 60.0 * 48.0:
		settled = now - 60.0
	var guard := 0
	while settled + 60.0 <= now and guard < 48:
		guard += 1
		settled += 60.0
		var hour := int(settled / 60.0) % 24
		if business.should_be_open(hour):
			_simulate_far_hour(business, hour)
	_traded_to[business.business_id] = settled


func _simulate_far_hour(business: BusinessInstance, hour: int) -> void:
	var owed := (
		float(_pending_customers.get(business.business_id, 0.0))
		+ CustomerDemand.customers_per_hour(business, hour)
	)
	while owed >= 1.0:
		owed -= 1.0
		_resolve_remote_visit(business, hour)
	_pending_customers[business.business_id] = owed


## Development and testing entry point: trades one hour right now, without
## waiting for the clock.
func simulate_hour_now(business: BusinessInstance, hour: int = -1) -> void:
	if business == null:
		return
	_simulate_far_hour(business, hour if hour >= 0 else TimeManager.hour)


## One shopping trip, resolved as data. Without somebody on the till the visit
## is a lost sale however good the shop is, which is the whole reason to hire.
func _resolve_remote_visit(business: BusinessInstance, hour: int) -> void:
	business.record_customer_visit()

	var cashier := business.rostered_cashier(hour)
	if cashier == null:
		business.record_lost_sale()
		business.add_satisfaction(-0.35)
		return

	var bought := 0
	for i in CustomerDemand.basket_size(business, _rng):
		var item := CustomerDemand.pick_item(business, _rng)
		if item == null:
			break
		if not CustomerDemand.will_buy(business, item, _rng):
			continue
		if business.record_sale(item, 1) > 0:
			bought += 1

	if bought > 0:
		cashier.customers_served_today += 1
		cashier.sales_processed_today += bought
		business.add_satisfaction(0.12)
	else:
		business.record_lost_sale()
		business.add_satisfaction(-0.25)


# --- Statistics ----------------------------------------------------------

func get_statistics() -> Dictionary:
	var stats := _statistics.duplicate()
	stats[&"businesses_owned"] = owned_count()
	return stats


func get_statistic(key: StringName) -> int:
	return int(_statistics.get(key, 0))


func _reset_statistics() -> void:
	_statistics = {}
	for key in STATISTIC_KEYS:
		_statistics[key] = 0


func _add_statistic(key: StringName, amount: int = 1) -> void:
	if _statistics.has(key):
		_statistics[key] = int(_statistics[key]) + amount


func _raise_statistic(key: StringName, value: int) -> void:
	if _statistics.has(key) and value > int(_statistics[key]):
		_statistics[key] = value


func _tally_report(report: Dictionary) -> void:
	_add_statistic(&"business_revenue", int(report.get("revenue", 0)))
	_add_statistic(&"business_profit", int(report.get("profit", 0)))
	_raise_statistic(&"highest_daily_profit", int(report.get("profit", 0)))


func _on_sale_made(_item: ItemData, quantity: int, _revenue: int, _business: BusinessInstance) -> void:
	_add_statistic(&"products_sold", quantity)


func _on_business_changed(business: BusinessInstance) -> void:
	business_changed.emit(business)


func _on_stock_low(item: ItemData, business: BusinessInstance) -> void:
	GameManager.notify(
		"LOW STOCK\n%s — %s" % [business.business_name.to_upper(), item.display_name],
		GameManager.Tone.BAD
	)


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var records: Array = []
	for business in get_businesses():
		records.append(business.to_dict())
	var pending := {}
	for key in _unplaced_equipment:
		pending[String(key)] = (_unplaced_equipment[key] as Array).map(
			func(id: Variant) -> String: return String(id)
		)
	var stats := {}
	for key in _statistics:
		stats[String(key)] = int(_statistics[key])

	return {
		"businesses": records,
		"unplaced": pending,
		"statistics": stats,
		"next_business": _next_business_number,
		"next_employee": _next_employee_number,
	}


func load_state(state: Dictionary) -> void:
	_businesses.clear()
	_order.clear()
	_unplaced_equipment.clear()
	_pending_customers.clear()

	for record in state.get("businesses", []):
		_register(BusinessInstance.from_dict(record))
	for key in state.get("unplaced", {}):
		var pile: Array = []
		for id in state["unplaced"][key]:
			pile.append(StringName(id))
		_unplaced_equipment[StringName(key)] = pile

	_reset_statistics()
	for key in state.get("statistics", {}):
		if _statistics.has(StringName(key)):
			_statistics[StringName(key)] = int(state["statistics"][key])

	_next_business_number = int(state.get("next_business", _next_business_number))
	_next_employee_number = int(state.get("next_employee", _next_employee_number))

	for business in get_businesses():
		business_changed.emit(business)
