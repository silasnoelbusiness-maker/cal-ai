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
signal order_placed(order: PurchaseOrder)
signal order_delivered(order: PurchaseOrder)
signal loan_taken(business: BusinessInstance, loan: Loan)
signal loan_payment_made(business: BusinessInstance, loan: Loan, amount: int)
signal business_sold(business_name: String, proceeds: int)
signal milestone_reached(milestone: StringName, description: String)

enum TransferResult { OK, NO_BUSINESS, NOT_ENOUGH_FUNDS, INVALID_AMOUNT }
enum LoanResult { OK, NO_BUSINESS, NOT_ELIGIBLE, ALREADY_OVERDUE, UNKNOWN_OFFER }
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
	&"businesses_founded", &"businesses_sold", &"employees_hired", &"employees_fired",
	&"products_sold", &"drinks_sold", &"business_revenue", &"business_profit",
	&"highest_daily_profit", &"highest_business_value", &"highest_net_worth",
	&"loan_interest_paid",
]

## Milestones, in the order they are checked. Each is a line the player crosses
## once; nothing is awarded for it beyond being told.
const MILESTONES: Array = [
	[&"first_business", "FIRST BUSINESS", "Found a business"],
	[&"first_employee", "FIRST EMPLOYEE", "Put somebody on the payroll"],
	[&"first_manager", "FIRST MANAGER", "Hire a manager"],
	[&"two_businesses", "BUSINESS EMPIRE", "Own two businesses"],
	[&"ten_thousand_revenue", "$10K TAKEN", "Ten thousand dollars through the tills"],
	[&"fifty_thousand_net_worth", "$50K NET WORTH", "Fifty thousand dollars to your name"],
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
## Every order that has not yet been delivered, oldest first.
var _orders: Array[PurchaseOrder] = []
var _next_order_number: int = 1
var _next_loan_number: int = 1
var _supplier := SupplierData.default_supplier()
var _milestones_reached: Dictionary = {}
## The player's own company name, shown over the portfolio.
var company_name: String = "My Company"


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
	_reach_milestone(&"first_business")
	if owned_count() >= 2:
		_reach_milestone(&"two_businesses")
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


## Orders stock at wholesale.
##
## The money leaves now and the goods arrive later — see PurchaseOrder. Space is
## checked against what is already on order as well as what is on the shelf, so
## three orders in a row cannot conjure a store room twice the size.
func order_stock(
	business: BusinessInstance, item_id: StringName, quantity: int, automatic: bool = false
) -> PurchaseResult:
	if business == null:
		return PurchaseResult.NO_BUSINESS
	var item := ItemCatalogue.by_id(item_id)
	if item == null or not business.orderable().has(item):
		return PurchaseResult.NO_SUCH_ITEM
	quantity = mini(maxi(quantity, 0), room_left_after_orders(business))
	if quantity <= 0:
		return PurchaseResult.NO_ROOM

	var cost := _supplier.price_for(item, quantity)
	if not business.debit(
		cost, "Stock — %s x%d" % [item.display_name, quantity], &"inventory"
	):
		return PurchaseResult.NOT_ENOUGH_FUNDS

	var order := PurchaseOrder.new()
	order.order_id = StringName("order_%d" % _next_order_number)
	_next_order_number += 1
	order.business_id = business.business_id
	order.supplier_id = _supplier.supplier_id
	order.items[item_id] = quantity
	order.total_cost = cost
	order.automatic = automatic
	order.placed_at = TimeManager.total_minutes
	order.arrives_at = order.placed_at + _supplier.delivery_minutes(_rng)
	_orders.append(order)

	GameManager.notify(
		"ORDER PLACED\n%s x%d  ·  arriving %s" % [
			item.display_name, quantity, order.arrival_text()
		],
		GameManager.Tone.INFO
	)
	order_placed.emit(order)
	business_changed.emit(business)
	return PurchaseResult.OK


## Space left after everything already on its way is accounted for.
func room_left_after_orders(business: BusinessInstance) -> int:
	var incoming := 0
	for order in _orders:
		if order.business_id == business.business_id and order.is_outstanding():
			incoming += order.unit_count()
	return maxi(business.storage_room_left() - incoming, 0)


func outstanding_orders(business: BusinessInstance = null) -> Array[PurchaseOrder]:
	var found: Array[PurchaseOrder] = []
	for order in _orders:
		if not order.is_outstanding():
			continue
		if business == null or order.business_id == business.business_id:
			found.append(order)
	return found


func get_supplier() -> SupplierData:
	return _supplier


## Moves every outstanding order along, and hands over the ones that have
## arrived. Driven by the clock rather than by a frame timer, so a skipped
## afternoon delivers everything it should have.
func _advance_deliveries() -> void:
	var now := TimeManager.total_minutes
	var arrived: Array[PurchaseOrder] = []
	for order in _orders:
		order.refresh_status(now)
		if order.has_arrived(now):
			arrived.append(order)

	for order in arrived:
		var business := by_id(order.business_id)
		order.status = PurchaseOrder.Status.DELIVERED
		_orders.erase(order)
		if business == null:
			continue
		var delivered := 0
		for item_id in order.items:
			delivered += business.add_storage(item_id, int(order.items[item_id]))
		GameManager.notify(
			"DELIVERY ARRIVED\n%s  ·  %d items received" % [
				business.business_name.to_upper(), delivered
			],
			GameManager.Tone.GOOD
		)
		order_delivered.emit(order)
		business_changed.emit(business)


## Development and testing entry point: brings everything on order in now.
func deliver_now(business: BusinessInstance = null) -> int:
	var count := 0
	for order in outstanding_orders(business):
		order.arrives_at = TimeManager.total_minutes
		count += 1
	_advance_deliveries()
	return count


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


# --- Marketing, upgrades and debt ----------------------------------------

## Buys an advertising campaign. It raises how many people walk in and nothing
## else — see MarketingCampaign for why that distinction matters.
func start_campaign(business: BusinessInstance, campaign_id: StringName) -> PurchaseResult:
	if business == null:
		return PurchaseResult.NO_BUSINESS
	var campaign := MarketingCampaign.by_id(campaign_id)
	if campaign == null:
		return PurchaseResult.NO_SUCH_ITEM
	if not business.debit(campaign.cost, "Marketing — %s" % campaign.display_name, &"marketing"):
		return PurchaseResult.NOT_ENOUGH_FUNDS
	business.start_campaign(campaign)
	GameManager.notify(
		"CAMPAIGN STARTED\n%s  ·  %d days" % [campaign.display_name.to_upper(), campaign.duration_days],
		GameManager.Tone.GOOD
	)
	business_changed.emit(business)
	return PurchaseResult.OK


func buy_upgrade(business: BusinessInstance, upgrade_id: StringName) -> PurchaseResult:
	if business == null:
		return PurchaseResult.NO_BUSINESS
	var upgrade := BusinessUpgrade.by_id(upgrade_id)
	if upgrade == null:
		return PurchaseResult.NO_SUCH_ITEM
	if not upgrade.business_types.is_empty() and not upgrade.business_types.has(business.type_id):
		return PurchaseResult.NOT_ALLOWED
	if business.has_upgrade(upgrade_id):
		return PurchaseResult.NOT_ALLOWED
	if not business.debit(upgrade.cost, "Upgrade — %s" % upgrade.display_name, &"equipment"):
		return PurchaseResult.NOT_ENOUGH_FUNDS
	business.add_upgrade(upgrade_id)
	GameManager.notify("UPGRADE FITTED\n%s" % upgrade.display_name.to_upper(), GameManager.Tone.GOOD)
	business_changed.emit(business)
	return PurchaseResult.OK


# --- Borrowing -----------------------------------------------------------

func loan_offers() -> Array[LoanOffer]:
	return LoanOffer.catalogue()


## Whether the bank would lend this. Deliberately forgiving — the interesting
## decision is whether the payment is affordable, not whether the bank says yes.
func is_eligible(business: BusinessInstance, offer: LoanOffer) -> bool:
	if business == null or offer == null:
		return false
	if business.has_overdue_loan():
		return false
	if business.reputation < offer.minimum_reputation:
		return false
	return TimeManager.day_index - business.founded_on_day >= offer.minimum_days_trading


## Draws a loan. The money lands in the business account, and the repayment
## schedule starts one interval from now.
func take_loan(business: BusinessInstance, offer_id: StringName) -> LoanResult:
	if business == null:
		return LoanResult.NO_BUSINESS
	var offer: LoanOffer = null
	for candidate in loan_offers():
		if candidate.offer_id == offer_id:
			offer = candidate
	if offer == null:
		return LoanResult.UNKNOWN_OFFER
	if business.has_overdue_loan():
		return LoanResult.ALREADY_OVERDUE
	if not is_eligible(business, offer):
		return LoanResult.NOT_ELIGIBLE

	var loan := Loan.create(
		StringName("loan_%d" % _next_loan_number), business.business_id, offer.display_name,
		offer.amount, offer.interest_rate, offer.payment_amount, offer.payment_interval_days
	)
	_next_loan_number += 1
	business.add_loan(loan)
	business.credit(offer.amount, "%s drawn" % offer.display_name, &"financing")
	GameManager.notify(
		"LOAN APPROVED\n%s  +$%d" % [offer.display_name.to_upper(), offer.amount],
		GameManager.Tone.GOOD
	)
	loan_taken.emit(business, loan)
	business_changed.emit(business)
	return LoanResult.OK


static func describe_loan(result: LoanResult) -> String:
	match result:
		LoanResult.NOT_ELIGIBLE:
			return "THE BANK WILL NOT LEND THAT YET"
		LoanResult.ALREADY_OVERDUE:
			return "SETTLE THE OVERDUE LOAN FIRST"
		LoanResult.UNKNOWN_OFFER:
			return "NO SUCH LOAN"
		LoanResult.NO_BUSINESS:
			return "NO BUSINESS"
		_:
			return ""


## Pays whatever the player asks off a loan, now. Never more than is owed, and
## never more than the account holds.
func repay_loan(business: BusinessInstance, loan_id: StringName, amount: int) -> int:
	if business == null:
		return 0
	for loan in business.loans:
		if loan.loan_id != loan_id or not loan.is_active():
			continue
		var wanted := clampi(amount, 0, mini(loan.remaining_balance, business.cash_balance))
		if wanted <= 0:
			return 0
		if not business.debit(wanted, "%s — repayment" % loan.display_name, &"loan"):
			return 0
		var paid := loan.apply_payment(wanted)
		_record_interest(business, loan, paid)
		if loan.status == Loan.Status.PAID:
			GameManager.notify("LOAN PAID OFF\n%s" % loan.display_name.to_upper(), GameManager.Tone.GOOD)
		loan_payment_made.emit(business, loan, paid)
		business_changed.emit(business)
		return paid
	return 0


func total_debt() -> int:
	var total := 0
	for business in get_businesses():
		total += business.total_debt()
	return total


## The scheduled payments. Anything the account cannot cover is missed rather
## than forced, which is what stops a loan pushing a business into the red.
func _collect_loan_payments() -> void:
	for business in get_businesses():
		for loan in business.active_loans():
			if not loan.is_due(TimeManager.day_index):
				continue
			var due := loan.due_amount()
			if business.debit(due, "%s — payment" % loan.display_name, &"loan"):
				var paid := loan.apply_payment(due)
				_record_interest(business, loan, paid)
				loan.advance_schedule()
				GameManager.notify(
					"LOAN PAYMENT\n%s  -$%d" % [business.business_name.to_upper(), paid],
					GameManager.Tone.INFO
				)
				loan_payment_made.emit(business, loan, paid)
			else:
				loan.miss_payment()
				GameManager.notify(
					"PAYMENT MISSED\n%s  %s" % [
						business.business_name.to_upper(), loan.display_name
					],
					GameManager.Tone.BAD
				)
		business_changed.emit(business)


## Interest is charged up front, so every payment is part capital and part
## interest in the same proportion. Split here purely so the statistics can say
## what the borrowing actually cost.
func _record_interest(business: BusinessInstance, loan: Loan, paid: int) -> void:
	var total := loan.principal + loan.total_interest()
	if total <= 0:
		return
	var interest := roundi(float(paid) * float(loan.total_interest()) / float(total))
	loan.interest_paid += interest
	business.lifetime_interest_paid += interest
	_add_statistic(&"loan_interest_paid", interest)


# --- Hiring --------------------------------------------------------------

func get_candidates() -> Array[EmployeeData]:
	return _candidates.duplicate()


## Three people, deliberately unalike: somebody cheap and green, somebody
## middling, somebody good and dear. A pool of three interchangeable workers is
## not a hiring decision.
func refresh_candidates() -> void:
	_candidates.clear()
	var bands := [0.05, 0.45, 0.85]
	for i in candidate_pool_size:
		var band: float = bands[i % bands.size()]
		_candidates.append(
			EmployeeData.generate(
				_rng, StringName("worker_%d" % _next_employee_number),
				EmployeeData.Role.CASHIER, band
			)
		)
		_next_employee_number += 1
	candidates_refreshed.emit()


## Takes somebody on, in a named role. Their wage follows the role rather than
## the advert, so hiring a manager costs manager money.
func hire(
	business: BusinessInstance, candidate: EmployeeData,
	role: int = EmployeeData.Role.CASHIER
) -> bool:
	if business == null or candidate == null:
		return false
	candidate.assign_role(role as EmployeeData.Role)
	business.hire(candidate)
	_candidates.erase(candidate)
	_add_statistic(&"employees_hired")
	GameManager.notify(
		"HIRED %s\n%s  ·  $%d/hour" % [
			candidate.employee_name.to_upper(), candidate.get_role_name(), candidate.hourly_wage
		],
		GameManager.Tone.GOOD
	)
	if candidate.is_manager():
		_reach_milestone(&"first_manager")
	_reach_milestone(&"first_employee")
	business_changed.emit(business)
	return true


## Lets somebody go. Any hours they have worked and not been paid for are
## settled first: dismissal is not a way to avoid a wage bill.
func fire(business: BusinessInstance, employee_id: StringName) -> bool:
	if business == null:
		return false
	var worker := business.employee_by_id(employee_id)
	if worker == null:
		return false
	if worker.hours_unpaid > 0.0:
		_pay(business, worker)
	business.fire(employee_id)
	_add_statistic(&"employees_fired")
	GameManager.notify("%s HAS LEFT" % worker.employee_name.to_upper(), GameManager.Tone.INFO)
	business_changed.emit(business)
	return true


## Everybody on the books, across every business.
func all_employees() -> Array[EmployeeData]:
	var staff: Array[EmployeeData] = []
	for business in get_businesses():
		for worker in business.employees:
			staff.append(worker)
	return staff


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
	_advance_deliveries()
	for business in get_businesses():
		_run_manager(business, hour)
		_update_open_state(business, hour)
		_accrue_wages(business, hour)
		_work_the_stock_room(business, hour)
		_settle_trade(business)


func _on_day_passed(day_index: int) -> void:
	_collect_loan_payments()
	for business in get_businesses():
		# Anybody still clocked on is paid off before the books close.
		_pay_off_all(business)
		_charge_utilities(business)
		var expired := business.expire_campaigns()
		if expired > 0:
			GameManager.notify(
				"CAMPAIGN ENDED\n%s" % business.business_name.to_upper(), GameManager.Tone.INFO
			)
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
		_raise_statistic(&"highest_business_value", business.estimated_value())
	_raise_statistic(&"highest_net_worth", net_worth())
	_check_milestones()


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


## The lights, the water, the things nobody wants a separate system for. Charged
## once a day, whether or not the doors opened.
func _charge_utilities(business: BusinessInstance) -> void:
	var definition := business.type_data()
	if definition == null or definition.daily_utilities <= 0:
		return
	if not business.debit(definition.daily_utilities, "Utilities", &"utilities"):
		business.wages_owed += definition.daily_utilities


# --- The manager ---------------------------------------------------------

## What the manager does with the hour.
##
## This is the whole value of hiring one: opening up, keeping the shelves full
## and reordering before the shop runs dry, whether or not the player is in the
## building — or in the city. Everything is gated on a permission the player
## turned on, and on money the business actually has.
func _run_manager(business: BusinessInstance, hour: int) -> void:
	var boss := business.manager()
	if boss == null:
		return
	boss.hours_worked_today += 1.0
	boss.hours_unpaid += 1.0
	boss.add_experience(1.0)

	if business.auto_open:
		# The manager works the published hours. Overriding them is the player's
		# business, and the manager does not argue.
		if business.manual_override != BusinessInstance.Override.NONE:
			business.manual_override = BusinessInstance.Override.NONE

	if business.auto_restock:
		_manager_restock(business, boss)
	if business.auto_order:
		_manager_reorder(business, boss)


## Fills the shelves from the store room. A better manager gets more of it done;
## a poor one leaves gaps, which is what the wage difference buys.
func _manager_restock(business: BusinessInstance, boss: EmployeeData) -> int:
	if business.serves_prepared_goods():
		return 0
	var budget := roundi(lerpf(20.0, 60.0, boss.management_quality()))
	return _restock_shelves(business, budget)


## Moves stock onto whichever shelf has room, product by product. Shared by the
## manager and by the stocker, so both mean the same thing by "restocking".
func _restock_shelves(business: BusinessInstance, unit_budget: int) -> int:
	var moved := 0
	for placed in business.shelves():
		if moved >= unit_budget:
			break
		var wanted: StringName = placed.stock_item
		if wanted == &"" or business.storage_of(wanted) <= 0:
			wanted = _best_restock_item(business)
		if wanted == &"":
			continue
		var room := placed.room_left() if placed.stock_item == wanted else placed.capacity()
		var take := mini(room, unit_budget - moved)
		if take <= 0:
			continue
		moved += business.stock_shelf(placed.slot_id, wanted, take)
	return moved


## Whatever there is most of in the back, so a manager fills the shelf with
## something rather than staring at an empty one.
func _best_restock_item(business: BusinessInstance) -> StringName:
	var best: StringName = &""
	var most := 0
	for item in business.catalogue():
		var held := business.storage_of(item.id)
		if held > most:
			most = held
			best = item.id
	return best


## Reorders anything that has fallen below the player's threshold, inside the
## budget the player set. One order per product at a time — the check counts what
## is already on its way, so a manager cannot order the same thing every hour.
func _manager_reorder(business: BusinessInstance, boss: EmployeeData) -> void:
	var budget := business.auto_order_budget
	for item in business.orderable():
		if budget <= 0:
			return
		# Something already on its way is not reordered, however little of it is
		# coming. Topping up an order every hour until it lands is how a manager
		# quietly spends a week's budget on one afternoon's beans.
		if _incoming(business, item.id) > 0:
			continue
		var held := business.storage_of(item.id)
		if held >= business.auto_order_minimum:
			continue
		var wanted := business.auto_order_target - held
		if wanted <= 0:
			continue
		var affordable := budget / maxi(item.get_wholesale_cost(), 1)
		var quantity := mini(wanted, affordable)
		if quantity <= 0:
			continue
		if order_stock(business, item.id, quantity, true) != PurchaseResult.OK:
			continue
		budget -= item.get_wholesale_cost() * quantity
		GameManager.notify(
			"MANAGER ORDERED\n%s  ·  %s x%d" % [
				business.business_name.to_upper(), item.display_name, quantity
			],
			GameManager.Tone.INFO
		)


func _incoming(business: BusinessInstance, item_id: StringName) -> int:
	var total := 0
	for order in outstanding_orders(business):
		total += int(order.items.get(item_id, 0))
	return total


## A stocker on shift moves stock onto the shelves for an hour. Unlike the
## manager they only work their roster, and they only move what is already in
## the back — nothing here creates inventory.
func _work_the_stock_room(business: BusinessInstance, hour: int) -> void:
	var stocker := business.rostered_stocker(hour)
	if stocker == null:
		return
	stocker.hours_worked_today += 1.0
	stocker.hours_unpaid += 1.0
	stocker.add_experience(1.0)
	if business.serves_prepared_goods():
		return
	# While the player is in the shop the stocker is a person walking stock out
	# of the back, and doing it here as well would fill the shelves twice.
	if is_player_present(business):
		return
	_restock_shelves(business, roundi(stocker.stocking_rate() * 60.0 / 10.0))


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
	# The clock can also go *backwards* — loading a save, or a test winding it on
	# — and an hour that has not happened yet must not be owed for.
	if settled > now:
		settled = now
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
	# However many people want serving, only so many can be served: one counter,
	# one member of staff, one hour. The rest walk out, which is what makes a
	# bigger unit and a quicker cashier worth paying for.
	var servable := _servable_per_hour(business, hour)
	var served := 0
	while owed >= 1.0:
		owed -= 1.0
		if served >= servable:
			business.record_customer_visit()
			business.record_lost_sale()
			business.add_satisfaction(-0.4)
			continue
		served += 1
		_resolve_remote_visit(business, hour)
	_pending_customers[business.business_id] = owed


## How many customers one hour of service can get through, from whoever is on
## the till and whatever the shop has been fitted with.
func _servable_per_hour(business: BusinessInstance, hour: int) -> int:
	var cashier := business.rostered_cashier(hour)
	if cashier == null:
		return 0
	var seconds := cashier.checkout_seconds()
	# A drink has to be made as well as rung up.
	if business.serves_prepared_goods():
		seconds += business.preparation_seconds(business.catalogue()[0], cashier)
	seconds *= 1.0 - business.upgrade_magnitude(BusinessUpgrade.Effect.CHECKOUT_SPEED)
	return maxi(floori(3600.0 / maxf(seconds, 0.5)), 1)


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


# --- The portfolio -------------------------------------------------------

## Everything the businesses are worth together.
func total_business_value() -> int:
	var total := 0
	for business in get_businesses():
		total += business.estimated_value()
	return total


func total_business_cash() -> int:
	var total := 0
	for business in get_businesses():
		total += business.cash_balance
	return total


func total_employees() -> int:
	var count := 0
	for business in get_businesses():
		count += business.employees.size()
	return count


## What the player's vehicles would fetch. Their own car counts; a stolen one
## does not, because it is not theirs to sell.
func vehicle_value() -> int:
	var total := 0
	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Vehicle
		if car == null or not car.is_player_owned() or car.data == null:
			continue
		# A wreck is worth less than a clean one, in proportion to the damage.
		var condition := clampf(car.health / maxf(car.data.max_health, 1.0), 0.25, 1.0)
		total += roundi(float(car.data.resale_value) * condition)
	return total


## Everything owned less everything owed.
##
## Leases are not assets — the player rents their units, so the unit is not
## theirs to count. What is theirs is the cash, the cars and the businesses,
## and the businesses are already net of their own debt.
func net_worth() -> int:
	return EconomyManager.cash + vehicle_value() + total_business_value()


## One line per business plus the totals, for the portfolio screen and the
## debug overlay.
func portfolio_summary() -> Dictionary:
	var revenue := 0
	var expenses := 0
	var profit := 0
	var customers := 0
	for business in get_businesses():
		revenue += business.revenue_today
		expenses += business.expenses_today()
		profit += business.profit_today()
		customers += business.customer_count_today
	return {
		"company": company_name,
		"businesses": owned_count(),
		"employees": total_employees(),
		"revenue_today": revenue,
		"expenses_today": expenses,
		"profit_today": profit,
		"customers_today": customers,
		"business_value": total_business_value(),
		"business_cash": total_business_cash(),
		"personal_cash": EconomyManager.cash,
		"vehicles": vehicle_value(),
		"debt": total_debt(),
		"net_worth": net_worth(),
	}


# --- Selling and closing -------------------------------------------------

## Sells a business on. The buyer takes the fittings, the stock and the lease;
## the player takes what is left after the debt is settled.
##
## Deliberately not reversible and deliberately not one click — the dashboard
## asks twice. Everything is torn down in one place so a sold business cannot
## leave staff on the payroll or a shop trading with no owner.
func sell_business(business: BusinessInstance) -> int:
	if business == null:
		return 0
	var proceeds := business.sale_price()
	var name := business.business_name

	# Anybody owed for hours worked is paid before the doors close.
	for worker in business.employees.duplicate():
		if worker.hours_unpaid > 0.0:
			_pay(business, worker)
	business.employees.clear()

	var unit := PropertyManager.by_id(business.property_id)
	if unit != null:
		unit.end_lease()

	for order in outstanding_orders(business):
		_orders.erase(order)

	_businesses.erase(business.business_id)
	_order.erase(business.business_id)
	_unplaced_equipment.erase(business.business_id)
	_pending_customers.erase(business.business_id)
	_traded_to.erase(business.business_id)
	_player_present.erase(business.business_id)

	EconomyManager.deposit(proceeds, "%s — sold" % name)
	_add_statistic(&"businesses_sold")
	GameManager.notify(
		"BUSINESS SOLD\n%s  +$%d" % [name.to_upper(), proceeds], GameManager.Tone.GOOD
	)
	business_sold.emit(name, proceeds)
	return proceeds


## Stops trading without giving the business up. The lease and its rent carry on,
## which is the difference between closing for a while and getting out.
func close_business(business: BusinessInstance) -> void:
	if business == null:
		return
	business.manual_override = BusinessInstance.Override.FORCE_CLOSED
	business.auto_open = false
	business.set_open(false)
	GameManager.notify(
		"BUSINESS CLOSED\n%s  ·  rent still due" % business.business_name.to_upper(),
		GameManager.Tone.INFO
	)
	business_changed.emit(business)


# --- Milestones ----------------------------------------------------------

func reached_milestones() -> Array:
	return _milestones_reached.keys()


func _reach_milestone(id: StringName) -> void:
	if _milestones_reached.has(id):
		return
	for entry in MILESTONES:
		if entry[0] != id:
			continue
		_milestones_reached[id] = true
		GameManager.notify("MILESTONE\n%s\n%s" % [entry[1], entry[2]], GameManager.Tone.GOOD)
		milestone_reached.emit(id, entry[2])
		return


## The ones that depend on a running total rather than on a single act.
func _check_milestones() -> void:
	if owned_count() >= 1:
		_reach_milestone(&"first_business")
	if owned_count() >= 2:
		_reach_milestone(&"two_businesses")
	if get_statistic(&"business_revenue") >= 10000:
		_reach_milestone(&"ten_thousand_revenue")
	if net_worth() >= 50000:
		_reach_milestone(&"fifty_thousand_net_worth")


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


func _on_sale_made(item: ItemData, quantity: int, _revenue: int, business: BusinessInstance) -> void:
	_add_statistic(&"products_sold", quantity)
	if business != null and business.recipe_for(item) != null:
		_add_statistic(&"drinks_sold", quantity)


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

	var deliveries: Array = []
	for order in _orders:
		deliveries.append(order.to_dict())
	var milestones: Array = []
	for id in _milestones_reached:
		milestones.append(String(id))

	return {
		"businesses": records,
		"unplaced": pending,
		"statistics": stats,
		"orders": deliveries,
		"milestones": milestones,
		"company_name": company_name,
		"next_business": _next_business_number,
		"next_employee": _next_employee_number,
		"next_order": _next_order_number,
		"next_loan": _next_loan_number,
	}


func load_state(state: Dictionary) -> void:
	_businesses.clear()
	_order.clear()
	_unplaced_equipment.clear()
	_pending_customers.clear()
	_orders.clear()
	_traded_to.clear()
	_milestones_reached.clear()

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

	for entry in state.get("orders", []):
		_orders.append(PurchaseOrder.from_dict(entry))
	for id in state.get("milestones", []):
		_milestones_reached[StringName(id)] = true
	company_name = String(state.get("company_name", company_name))

	_next_business_number = int(state.get("next_business", _next_business_number))
	_next_employee_number = int(state.get("next_employee", _next_employee_number))
	_next_order_number = int(state.get("next_order", _next_order_number))
	_next_loan_number = int(state.get("next_loan", _next_loan_number))

	for business in get_businesses():
		business_changed.emit(business)
