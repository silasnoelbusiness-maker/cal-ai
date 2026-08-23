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
## The lender has called a loan in. Emitted once, on the miss that crosses
## the line, not every day afterwards.
signal loan_defaulted(business: BusinessInstance, loan: Loan)
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
	&"customers_served",
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
## Branches already told they have nobody to call, so the warning is once a
## day rather than once an hour. §103.
var _backup_warned: Dictionary = {}
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
	# A nightclub does not go in a thirty-metre shop. The property says what it
	# is zoned for and how big it is, and the type says what it needs.
	if not property.accepts_business(definition):
		GameManager.notify(
			"THIS UNIT IS NOT SUITABLE FOR A %s" % definition.display_name.to_upper(),
			GameManager.Tone.BAD
		)
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
	# What a type charges for access starts at what the type thinks is fair.
	# The player moves it from there; nobody has to type a number to open.
	business.membership_price = definition.default_membership_price
	business.day_pass_price = definition.default_day_pass_price
	business.entry_fee = definition.default_entry_fee

	_register(business)
	_add_statistic(&"businesses_founded")
	_reach_milestone(&"first_business")
	if owned_count() >= 2:
		_reach_milestone(&"two_businesses")
	GameManager.notify(
		"BUSINESS CREATED\n%s" % business.business_name.to_upper(), GameManager.Tone.GOOD
	)
	business_created.emit(business)
	SaveManager.autosave("founded a business")
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
	EconomyManager.deposit(
		amount, "%s — owner drawing" % business.business_name,
		EconomyManager.Source.LEGAL, EconomyManager.Stream.BUSINESS
	)
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

	# Each kind of business deals with the wholesaler that stocks what it needs,
	# so a restaurant's ingredients and a shop's groceries have their own prices
	# and their own lead times.
	var supplier := SupplierData.for_business(business)
	var cost := supplier.price_for(item, quantity)
	if not business.debit(
		cost, "Stock — %s x%d" % [item.display_name, quantity], &"inventory"
	):
		return PurchaseResult.NOT_ENOUGH_FUNDS

	var order := PurchaseOrder.new()
	order.order_id = StringName("order_%d" % _next_order_number)
	_next_order_number += 1
	order.business_id = business.business_id
	order.supplier_id = supplier.supplier_id
	order.items[item_id] = quantity
	order.total_cost = cost
	order.automatic = automatic
	order.placed_at = TimeManager.total_minutes
	order.arrives_at = order.placed_at + supplier.delivery_minutes(_rng)
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


## The wholesaler a given business deals with. Passing nothing asks for the
## general one, which is what every caller written before Phase O wanted.
func supplier_for(business: BusinessInstance) -> SupplierData:
	return SupplierData.for_business(business)


## Every branch waiting on a delivery, and every branch that has run short.
## The company-wide purchasing view, and deliberately a report rather than a
## shared pool: nothing is moved between branches by looking at this.
func purchasing_overview() -> Dictionary:
	var pending: Array[Dictionary] = []
	for order in outstanding_orders():
		var business := by_id(order.business_id)
		pending.append({
			"order": order,
			"business": business.business_name if business != null else "",
			"summary": order.summary(),
			"cost": order.total_cost,
			"arrives": order.arrival_text(),
		})
	var short: Array[Dictionary] = []
	for business in get_businesses():
		for item in business.orderable():
			if business.storage_of(item.id) > business.auto_order_minimum:
				continue
			short.append({
				"business": business.business_name,
				"business_id": business.business_id,
				"item": item.display_name,
				"held": business.storage_of(item.id),
				"incoming": _incoming(business, item.id),
			})
	return {"pending": pending, "low_stock": short}


## Puts a warehouse order on the same delivery clock as every branch order.
## LogisticsManager builds it and hands it over; there is one order list.
func register_warehouse_order(order: PurchaseOrder) -> void:
	if order == null:
		return
	_orders.append(order)
	order_placed.emit(order)


## Anybody on the payroll, anywhere in the company, by id.
func employee_by_id(employee_id: StringName) -> EmployeeData:
	if employee_id == &"":
		return null
	for business in get_businesses():
		var worker := business.employee_by_id(employee_id)
		if worker != null:
			return worker
	return null


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
		order.status = PurchaseOrder.Status.DELIVERED
		_orders.erase(order)
		# A bulk run goes to the warehouse floor rather than a shop's back
		# room. Same order, same supplier, same clock — only the door differs.
		if order.goes_to_warehouse():
			var landed := LogisticsManager.receive_supplier_delivery(order)
			GameManager.notify(
				"WAREHOUSE DELIVERY\n%d units received" % landed, GameManager.Tone.GOOD
			)
			order_delivered.emit(order)
			continue
		var business := by_id(order.business_id)
		if business == null:
			continue
		var delivered := 0
		for item_id in order.items:
			delivered += business.add_storage(item_id, int(order.items[item_id]))
		GameManager.notify(
			"DELIVERY ARRIVED\n%s  ·  %d items received" % [
				business.business_name.to_upper(), delivered
			],
			GameManager.Tone.GOOD, GameManager.Priority.LOW
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
	# §43 — the same rule as a mortgage, asked in the same place. Loans already
	# drawn are untouched; only new borrowing is harder.
	if not bool(LegalManager.lender_view()["accepted"]):
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
				var was_defaulted := loan.is_defaulted()
				loan.miss_payment()
				GameManager.notify(
					"PAYMENT MISSED\n%s  %s" % [
						business.business_name.to_upper(), loan.display_name
					],
					GameManager.Tone.BAD
				)
				if loan.is_defaulted() and not was_defaulted:
					GameManager.notify(
						"LOAN IN DEFAULT\n%s  ·  %s" % [
							business.business_name.to_upper(), loan.display_name
						],
						GameManager.Tone.BAD
					)
					loan_defaulted.emit(business, loan)
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
	# §48 and §49 — a notorious owner puts some people off, modestly, and never
	# all of them. Existing staff are not touched by any of this: nobody
	# resigns over the owner's record.
	var pool := candidate_pool_size
	if LegalManager.hiring_penalty() >= 0.3 and pool > 1:
		pool -= 1
	for i in pool:
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
	_backup_warned.clear()
	_settle_backup_shifts()
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
		business.model().on_day(business, day_index)
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


## Cover is for a day. Anybody who came in to help is paid for it — at a small
## premium, because being rung up on a day off is worth something — and then
## goes back to their own branch.
func _settle_backup_shifts() -> void:
	for worker in backup_assignments():
		var covered := by_id(worker.backup_business_id)
		var home := by_id(worker.assigned_business)
		if covered != null and worker.hours_unpaid > 0.0:
			var due := roundi(
				float(worker.wage_for_hours(worker.hours_unpaid))
				* (1.0 + FinanceManager.BACKUP_WAGE_PREMIUM)
			)
			# The branch that got the help pays for it, not the one that lent
			# the person out.
			FinanceManager.settle_wages(covered, worker, due)
			worker.hours_unpaid = 0.0
		worker.clear_backup()
		if home != null:
			home.changed.emit()


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
	if business.may(&"manage_cleanliness"):
		_manager_clean(business)
	if business.may(&"call_backup"):
		_manager_call_backup(business, hour)
	_manager_position_staff(business, hour)


## The manager finds a critical job uncovered and rings round the company for
## somebody to come in. Phase O shipped this permission with nothing behind it;
## this is the behind it.
##
## Nobody is conjured. Every candidate is a real employee of another branch who
## is off shift and can do the job, and if there is nobody the shift stays
## uncovered and the business takes the consequences. §60.
func _manager_call_backup(business: BusinessInstance, hour: int) -> void:
	for role in business.short_handed_roles(hour):
		# Somebody already on the way here counts as covered.
		if backup_covering(business.business_id, role, hour) != null:
			continue
		if _backup_incoming(business.business_id, role):
			continue
		var worker := BackupPool.best_for(business, role, hour)
		if worker == null:
			_notify_no_backup(business, role)
			continue
		assign_backup(business, worker, role, hour)


func _backup_incoming(business_id: StringName, role: int) -> bool:
	for other in get_businesses():
		for worker in other.employees:
			if worker.backup_business_id == business_id and worker.backup_role == role:
				return true
	return false


func _notify_no_backup(business: BusinessInstance, role: int) -> void:
	var key := "%s/nobackup/%d" % [business.business_id, role]
	if _backup_warned.has(key):
		return
	_backup_warned[key] = true
	GameManager.notify(
		"NO BACKUP STAFF AVAILABLE\n%s  ·  %s" % [
			business.business_name.to_upper(), EmployeeData.name_of_role(role)
		],
		GameManager.Tone.BAD
	)


## Sends somebody to cover a shift somewhere else. They travel, they arrive,
## and they are paid a little over the odds for the inconvenience.
func assign_backup(
	business: BusinessInstance, worker: EmployeeData, role: int, hour: int
) -> bool:
	if business == null or worker == null:
		return false
	if not BackupPool.is_eligible(worker, business, role, hour):
		return false
	var travel := BackupPool.travel_minutes(worker, business)
	worker.backup_business_id = business.business_id
	worker.backup_role = role
	worker.backup_until_hour = business.closing_hour
	worker.backup_arrives_minute = TimeManager.total_minutes + travel
	GameManager.notify(
		"BACKUP %s ASSIGNED\n%s  ·  %s arrives %s" % [
			EmployeeData.name_of_role(role).to_upper(),
			business.business_name.to_upper(), worker.employee_name,
			worker.backup_arrival_text(),
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play_ui(&"ui_confirm")
	business_changed.emit(business)
	return true


## Whoever is standing in at a branch, in a job, this hour.
func backup_covering(
	business_id: StringName, role: int, hour: int
) -> EmployeeData:
	for business in get_businesses():
		for worker in business.employees:
			if worker.is_covering(business_id, role, hour):
				return worker
	return null


## Everybody currently away covering somewhere else.
func backup_assignments() -> Array[EmployeeData]:
	var found: Array[EmployeeData] = []
	for business in get_businesses():
		for worker in business.employees:
			if worker.has_backup_shift():
				found.append(worker)
	return found


## Moves a spare pair of hands onto a job nobody is doing.
##
## The one thing a manager can do about a rota gap without the player being
## there. Only ever moves somebody the business has more than one of, only ever
## into a role the type actually needs, and only for as long as they are on
## shift — so a restaurant with two servers and no cook ends up with one of
## each rather than a dining room full of orders nobody is making.
func _manager_position_staff(business: BusinessInstance, hour: int) -> void:
	if not business.may(&"staff_positioning"):
		return
	var uncovered := business.unstaffed_roles(hour)
	if uncovered.is_empty():
		return
	var definition := business.type_data()
	for role in uncovered:
		var moved := false
		for worker in business.employees:
			if moved:
				break
			if not worker.is_on_shift(hour) or worker.is_manager():
				continue
			# Never strip the last person off a job the business also needs.
			if definition.requires_role(int(worker.role)) \
					and business.rostered_all(int(worker.role), hour).size() <= 1:
				continue
			worker.assign_role(role as EmployeeData.Role)
			for slot in worker.shifts:
				if slot.covers(hour, TimeManager.weekday):
					slot.role = role
			moved = true
			GameManager.notify(
				"MOVED ONTO %s\n%s  ·  %s" % [
					EmployeeData.name_of_role(role).to_upper(),
					business.business_name.to_upper(), worker.employee_name,
				],
				GameManager.Tone.INFO
			)
		if moved:
			business.changed.emit()


## A manager who is allowed to keep the place clean calls somebody in when it
## drops below the mark. It costs money, it comes out of the same allowance as
## the stock, and a business with no cleaner and no allowance simply gets
## dirty — which is the player's problem to notice.
func _manager_clean(business: BusinessInstance) -> void:
	if not business.uses_cleanliness():
		return
	if business.cleanliness >= float(business.cleanliness_target):
		return
	# Nothing to do if somebody is already on the rota to do it.
	if not business.rostered_all(EmployeeData.Role.CLEANER, TimeManager.hour).is_empty():
		return
	var shortfall := float(business.cleanliness_target) - business.cleanliness
	var points := minf(shortfall, 12.0)
	var cost := maxi(roundi(points * 3.5), 1)
	if cost > business.manager_budget_left():
		return
	if not business.debit(cost, "Cleaning", &"other"):
		return
	business.note_manager_spend(cost)
	business.clean(points)


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
	# The allowance, less whatever the manager has already spent today, and
	# never more than the business actually holds. One number, checked once.
	var budget := business.manager_budget_left()
	for item in business.orderable():
		if budget <= 0:
			return
		# Something already on its way is not reordered, however little of it is
		# coming. Topping up an order every hour until it lands is how a manager
		# quietly spends a week's budget on one afternoon's beans.
		if _incoming(business, item.id) > 0:
			continue
		# A kitchen gets through its vegetables faster than its pasta, so the
		# targets follow the menu rather than treating every line alike.
		var definition := business.type_data()
		var weight := definition.ingredient_usage(item) if definition != null else 1.0
		var held := business.storage_of(item.id)
		if held >= roundi(float(business.auto_order_minimum) * weight):
			continue
		var wanted := roundi(float(business.auto_order_target) * weight) - held
		if wanted <= 0:
			continue
		var affordable := budget / maxi(item.get_wholesale_cost(), 1)
		var quantity := mini(wanted, affordable)
		if quantity <= 0:
			continue
		if order_stock(business, item.id, quantity, true) != PurchaseResult.OK:
			continue
		var spent := item.get_wholesale_cost() * quantity
		budget -= spent
		business.note_manager_spend(spent)
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
	# Anybody out covering another branch is on that branch's clock, and is
	# paid by them when the day closes. Counting the hour here as well would
	# pay one person twice for one hour.
	for worker in business.employees:
		if worker.has_backup_shift():
			if worker.is_covering(worker.backup_business_id, worker.backup_role, hour):
				worker.hours_worked_today += 1.0
				worker.hours_unpaid += 1.0
			continue
		# Somebody who has not been paid for weeks stops coming in. That is the
		# whole of Phase P's morale model, and enough of one. §70.
		if not worker.will_work():
			continue
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
	# An account too short for the wage bill still owes it. Phase P is where
	# that shortfall stopped evaporating: whatever cannot be covered becomes
	# arrears against this person's name, and paying later pays them. §69.
	var paid := FinanceManager.settle_wages(business, worker, due)
	GameManager.notify(
		"EMPLOYEE SHIFT ENDED\n%s  -$%d" % [worker.employee_name.to_upper(), paid],
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
	var model := business.model()
	var owed := (
		float(_pending_customers.get(business.business_id, 0.0))
		+ CustomerDemand.customers_per_hour(business, hour)
	)
	# However many people want serving, only so many can be served: one counter,
	# one kitchen, one hour. The rest walk out, which is what makes a bigger
	# unit, another cook and a quicker cashier worth paying for.
	var servable := model.throughput_per_hour(business, hour)
	var overflow := model.overflow_reason()
	var served := 0
	while owed >= 1.0:
		owed -= 1.0
		business.record_customer_visit()
		if served >= servable:
			business.record_lost_sale(overflow)
			business.add_satisfaction(-0.4)
			continue
		served += 1
		_resolve_remote_visit(business, model, hour)
	_pending_customers[business.business_id] = owed
	_note_hour_load(business, model, hour)
	_soil_and_clean(business, model, hour, served)


## How hard the hour worked everybody and everything, kept so the operations
## screen can name which of them is the problem rather than guess.
func _note_hour_load(business: BusinessInstance, model: OperatingModel, hour: int) -> void:
	var roles := model.role_utilisation(business, hour)
	for role: int in roles:
		business.note_role_load(role, float(roles[role]))
	var fittings := model.equipment_utilisation(business, hour)
	for id: StringName in fittings:
		business.note_equipment_load(id, float(fittings[id]))


## An hour of trading makes a mess; whoever is on the rota to clean it, cleans
## it. Both halves are skipped entirely by a type that does not model dirt.
func _soil_and_clean(
	business: BusinessInstance, model: OperatingModel, hour: int, served: int
) -> void:
	if not business.uses_cleanliness():
		return
	var definition := business.type_data()
	business.soil(definition.soiling_per_hour + model.visit_soiling(business) * float(served))
	for cleaner in business.rostered_all(EmployeeData.Role.CLEANER, hour):
		business.clean(cleaner.cleaning_rate())


## How many customers one hour of service can get through. A thin call through
## to the operating model, kept so a screen or a test can still ask directly.
func servable_per_hour(business: BusinessInstance, hour: int) -> int:
	return business.model().throughput_per_hour(business, hour)


## Development and testing entry point: trades one hour right now, without
## waiting for the clock.
func simulate_hour_now(business: BusinessInstance, hour: int = -1) -> void:
	if business == null:
		return
	_simulate_far_hour(business, hour if hour >= 0 else TimeManager.hour)


## One visit, resolved as data.
##
## What a customer is worth now lives in the operating model, so a restaurant
## cover, a gym check-in and a shopping trip are the same call with different
## arithmetic behind it — and the visible customers walking the floor run the
## identical code, which is what keeps near and far honest with each other.
func _resolve_remote_visit(
	business: BusinessInstance, model: OperatingModel, hour: int
) -> void:
	var result := model.serve_one(business, hour, _rng)
	if not result.served:
		business.record_lost_sale(result.lost_reason)
	business.add_satisfaction(result.satisfaction)


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
## What the player's cars are worth, from the registry rather than from whatever
## happens to be spawned. That distinction is the whole point of the registry: a
## car in a garage across the city has no node at all and is still an asset, and
## counting nodes would have quietly written it off.
func vehicle_value() -> int:
	return VehicleRegistry.total_value()


## Everything owned less everything owed.
##
## Leases are not assets — the player rents their units, so the unit is not
## theirs to count. What is theirs is the cash, the cars and the businesses,
## and the businesses are already net of their own debt.
func net_worth() -> int:
	return (
		EconomyManager.cash + vehicle_value() + total_business_value()
		+ HomeManager.furniture_resale_value() + RealEstate.total_equity()
	)


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
		"property_value": RealEstate.total_market_value(),
		"property_equity": RealEstate.total_equity(),
		"mortgage_debt": RealEstate.total_mortgage_debt(),
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
## Shuts the doors without giving anything up. The branch keeps its stock, its
## fittings, its lease and its debts — it simply stops trading, which is what
## makes this a way of stopping the bleeding rather than a way of quitting.
func close_business(business: BusinessInstance, reason: String = "") -> void:
	if business == null or business.is_closed():
		return
	business.manual_override = BusinessInstance.Override.FORCE_CLOSED
	business.auto_open = false
	business.set_open(false)
	business.distress = DistressState.State.CLOSED
	business.closed_on_day = TimeManager.day_index
	_stand_down(business)
	GameManager.notify(
		"BUSINESS CLOSED\n%s%s" % [
			business.business_name.to_upper(),
			"  ·  %s" % reason if not reason.is_empty() else "  ·  rent still due",
		],
		GameManager.Tone.INFO
	)
	business_changed.emit(business)


## Opens a temporarily closed branch again. Wages and customers resume; nothing
## was lost while it was shut.
func reopen_business(business: BusinessInstance) -> bool:
	if business == null or not business.is_closed():
		return false
	business.manual_override = BusinessInstance.Override.NONE
	business.closed_on_day = -1
	business.distress = DistressState.State.HEALTHY
	FinanceManager.review(business)
	GameManager.notify(
		"BUSINESS REOPENED\n%s" % business.business_name.to_upper(), GameManager.Tone.GOOD
	)
	business_changed.emit(business)
	return true


## The landlord took the premises. §5 and §6: the branch closes and loses its
## address, and keeps everything else — stock, fittings, staff, brand, history
## and whatever is in the till. What it needs is somewhere to go.
##
## Deliberately not liquidation. Winding the branch up is a decision with money
## attached and it stays the player's to make; losing a lease is something that
## happens to them, and it must not also spend their assets for them.
func evict_business(business: BusinessInstance) -> void:
	if business == null:
		return
	var unit := business.property()
	close_business(business, "the landlord took the unit back")
	# The address goes; nothing else does. `property_id` empty is what makes
	# `needs_premises()` true and keeps the branch out of every sweep that
	# walks the city looking for a room.
	business.property_id = &""
	if unit != null:
		unit.business_id = &""
		PropertyManager.end_lease(unit)
	GameManager.notify(
		"BUSINESS HAS NO PREMISES\n%s  ·  everything it owns is kept" % (
			business.business_name.to_upper()
		),
		GameManager.Tone.BAD
	)
	business_changed.emit(business)


## Moves a homeless branch into a unit the player has taken on. The other half
## of eviction: a business that can never trade again is a deletion with extra
## steps, and §6 asks for relocation rather than that.
func relocate_business(
	business: BusinessInstance, property: CommercialProperty
) -> bool:
	if business == null or property == null:
		return false
	if not business.needs_premises():
		return false
	if not property.is_leased_by_player() or property.business_id != &"":
		return false
	if business_for_property(property.property_id) != null:
		return false
	var definition := business.type_data()
	if definition != null and not property.accepts_business(definition):
		GameManager.notify(
			"THAT UNIT IS NOT ZONED FOR %s" % definition.display_name.to_upper(),
			GameManager.Tone.BAD
		)
		return false
	business.property_id = property.property_id
	property.business_id = business.business_id
	# Still shut: relocating gives it an address, not a fit-out. The player
	# reopens it once it has what it needs, exactly as they would a new one.
	GameManager.notify(
		"BUSINESS RELOCATED\n%s  ·  %s" % [
			business.business_name.to_upper(), property.address
		],
		GameManager.Tone.GOOD
	)
	business_changed.emit(business)
	return true


## Closure the player did not choose, after the warnings ran out.
func close_business_for_distress(business: BusinessInstance) -> void:
	close_business(business, "could not meet its obligations")
	GameManager.notify(
		"BUSINESS FAILED\n%s" % business.business_name.to_upper(), GameManager.Tone.BAD
	)
	AudioManager.play_ui(&"ui_error")


## Everything that has to stop when a branch shuts: the floor empties, the
## rota stops accruing, and anything on its way here is turned around. §132
## and §133 — no stuck queues and no ghost deliveries.
func _stand_down(business: BusinessInstance) -> void:
	var unit := RetailUnit.for_business(business, get_tree())
	if unit != null:
		var spawner := unit.get_spawner()
		if spawner != null:
			for customer in spawner.active_customers():
				customer.call("_leave")
	# Supplier runs still coming here are refunded rather than delivered into
	# a shop that is shut.
	for order in _orders.duplicate():
		if order.business_id != business.business_id or order.goes_to_warehouse():
			continue
		business.credit(order.total_cost, "Cancelled order", &"revenue")
		_orders.erase(order)
	# Transfers pointed at it go back where they came from.
	for order in LogisticsManager.transfers_for(business.business_id):
		if order.is_open():
			LogisticsManager.call("_fail", order, "The branch closed.")


## Winds a branch up: sells what it has, pays what it owes, ends the lease and
## takes it off the books. The order is fixed and every step is reported. §81.
func liquidate_business(business: BusinessInstance) -> Dictionary:
	if business == null:
		return {}
	var report := Liquidation.quote(business)
	business.distress = DistressState.State.LIQUIDATING
	close_business(business, "liquidated")

	# Sell the stock and the fittings into the business's own account first,
	# so the money is there to pay what the business owes.
	business.credit(
		int(report.get("stock_recovered", 0)), "Liquidated stock", &"revenue"
	)
	business.credit(
		int(report.get("equipment_recovered", 0)), "Liquidated equipment", &"revenue"
	)
	business.storage.clear()
	business.reserved_stock.clear()
	business.equipment.clear()

	# Wages first: people who worked are paid before anything else.
	FinanceManager.pay_arrears(business)
	var settled := int(report.get("owed", 0)) - business.total_arrears()

	# Whatever is left goes to the player, and any shortfall simply stands.
	var left := maxi(business.cash_balance, 0)
	if left > 0:
		business.debit(left, "Wound up", &"other")
		EconomyManager.deposit(left, "Liquidated %s" % business.business_name)

	# The lease ends only once the place is empty and the books are settled.
	var unit := business.property()
	if unit != null and unit.has_landlord():
		PropertyManager.end_lease(unit)

	# Staff are not deleted with the shop: they go to the company pool so the
	# player can move them somewhere. §130.
	var released := business.employees.size()
	for worker in business.employees.duplicate():
		worker.assigned_business = &""
		worker.available_for_backup = true
	business.employees.clear()

	CompanyManager.detach_branch(business)
	_remove(business)
	FinanceManager.businesses_liquidated += 1
	report["settled"] = settled
	report["returned"] = left
	report["released_staff"] = released
	GameManager.notify(
		"BRANCH LIQUIDATED\n%s  ·  $%s recovered" % [
			business.business_name.to_upper(),
			EconomyManager.with_thousands_separator(left),
		],
		GameManager.Tone.INFO
	)
	AudioManager.play(&"money", AudioBuses.SFX, -10.0)
	SaveManager.autosave("liquidated a branch")
	return report


## Takes a business off the register. Selling and liquidating both end here.
func _remove(business: BusinessInstance) -> void:
	_businesses.erase(business.business_id)
	_order.erase(business.business_id)
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
	_add_statistic(&"customers_served", int(report.get("customers", 0)))
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
		GameManager.Tone.BAD, GameManager.Priority.LOW
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
	_milestones_reached.clear()
	_traded_to.clear()

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

	# Deliveries keep their remaining time: a save made with a van an hour out
	# reloads with the van still an hour out, and never delivers twice.
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
