extends Node
## What the company owes, whether it can pay, and what happens when it cannot.
##
## Phase P's second half. The systems that take money — rent, wages, loans,
## mortgages, utilities — were left exactly as they were; what they lacked was
## anybody asking, across all of them at once, "is this business solvent". This
## asks, every day, and moves each business through a distress lifecycle with
## enough warning that the player can always do something about it.
##
## Two rules run through the file. Nothing is ever silently forgiven: a wage
## that could not be paid becomes arrears against that person's name, and
## paying later pays them. And nothing closes without notice: CRITICAL is a
## countdown the player is told about, not a state that deletes a shop.

signal distress_changed(business: BusinessInstance, state: DistressState.State)
signal obligation_missed(business: BusinessInstance, kind: Obligation.Kind, amount: int)
signal business_closed_by_distress(business: BusinessInstance)
signal capital_injected(business: BusinessInstance, amount: int)

## How far ahead the forecast looks. A week is the cycle rent and loans fall
## on, so it is the horizon that actually tells the player something.
const FORECAST_DAYS := 7
## Emergency cover costs a little more than an ordinary shift. §57.
const BACKUP_WAGE_PREMIUM := 0.15

var save_id: StringName = &"finance"

## Statistics the company screen reports. §117.
var missed_wage_runs: int = 0
var rent_defaults: int = 0
var loan_defaults: int = 0
var businesses_closed: int = 0
var businesses_liquidated: int = 0
var properties_foreclosed: int = 0
## Businesses already warned about today, so a distress notice is one line and
## not one per hour. §103.
var _warned_today: Dictionary = {}


func _ready() -> void:
	add_to_group(&"saveable")
	TimeManager.day_passed.connect(_on_day_passed)
	PropertyManager.rent_missed.connect(_on_rent_missed)


# --- Obligations ---------------------------------------------------------

## Everything a business owes over the next `days`, built from whatever the
## paying systems already know. A view, never a ledger — see Obligation.
func obligations_for(business: BusinessInstance, days: int = FORECAST_DAYS) -> Array[Obligation]:
	var found: Array[Obligation] = []
	if business == null:
		return found
	var today := TimeManager.day_index

	# Wages: what the rota implies for the week, plus anything already owed.
	var weekly_wages := 0
	var arrears := 0
	for worker in business.employees:
		weekly_wages += worker.wage_for_hours(worker.weekly_hours())
		arrears += worker.wage_arrears
	if weekly_wages > 0 or arrears > 0:
		found.append(Obligation.make(
			Obligation.Kind.EMPLOYEE_WAGES, business.business_id, "Payroll",
			roundi(float(weekly_wages) * float(days) / 7.0), today, arrears
		))

	var unit := business.property()
	if unit != null and unit.has_landlord() and unit.rent_amount > 0:
		found.append(Obligation.make(
			Obligation.Kind.COMMERCIAL_RENT, business.business_id,
			"Rent — %s" % unit.address, unit.rent_amount, today,
			unit.arrears, unit.property_id
		))

	for loan in business.loans:
		if not loan.is_active():
			continue
		found.append(Obligation.make(
			Obligation.Kind.BUSINESS_LOAN, business.business_id, loan.display_name,
			loan.due_amount(), loan.next_payment_day,
			loan.due_amount() * loan.missed_payments, loan.loan_id
		))

	var definition := business.type_data()
	if definition != null and definition.daily_utilities > 0:
		found.append(Obligation.make(
			Obligation.Kind.UTILITIES, business.business_id, "Utilities",
			definition.daily_utilities * days, today
		))
	return found


## The same question for the whole company, plus the warehouse and the
## player's own mortgages, which no single business owes but which still have
## to be paid out of the same money.
func company_obligations(days: int = FORECAST_DAYS) -> Array[Obligation]:
	var found: Array[Obligation] = []
	for business in BusinessManager.get_businesses():
		found.append_array(obligations_for(business, days))
	var today := TimeManager.day_index
	for warehouse in LogisticsManager.warehouses():
		var unit := PropertyManager.by_id(warehouse.property_id)
		if unit != null and unit.has_landlord() and unit.rent_amount > 0:
			found.append(Obligation.make(
				Obligation.Kind.WAREHOUSE_RENT, &"", "Warehouse — %s" % unit.address,
				unit.rent_amount, today, unit.arrears, unit.property_id
			))
	for loan in RealEstate.mortgages():
		if loan.is_settled():
			continue
		found.append(Obligation.make(
			Obligation.Kind.MORTGAGE, &"", RealEstate.address_of(loan.property_id),
			loan.payment_amount, loan.next_payment_day,
			loan.payment_amount * loan.missed_payments, loan.property_id
		))
	return found


# --- Forecast ------------------------------------------------------------

## Cash in, cash out and what is left, over the forecast window. Deliberately
## plain arithmetic: §99 rules out financial modelling, and a number the player
## can check by hand is a number they will trust.
func forecast(days: int = FORECAST_DAYS) -> Dictionary:
	var due := 0
	var overdue := 0
	for entry in company_obligations(days):
		due += entry.amount
		overdue += entry.overdue

	var cash := BusinessManager.total_business_cash()
	var expected := 0
	for business in BusinessManager.get_businesses():
		if not business.is_trading():
			continue
		expected += business.average_daily_profit() * days
	var at_risk: Array[BusinessInstance] = []
	for business in BusinessManager.get_businesses():
		if DistressState.is_alarming(business.distress):
			at_risk.append(business)

	return {
		"days": days,
		"cash": cash,
		"personal_cash": EconomyManager.get_cash(),
		"due": due,
		"overdue": overdue,
		"expected_revenue": expected,
		"projected": cash + expected - due - overdue,
		"at_risk": at_risk,
		"runway_days": runway_days(),
	}


## Roughly how long the money lasts at the current burn. Returns -1 when the
## company is making money, because a runway is meaningless then.
func runway_days() -> float:
	var burn := 0.0
	for business in BusinessManager.get_businesses():
		if not business.is_trading():
			continue
		var daily := business.average_daily_profit()
		if daily < 0:
			burn += float(-daily)
	if burn <= 0.0:
		return -1.0
	return clampf(float(BusinessManager.total_business_cash()) / burn, 0.0, 999.0)


# --- Wages ---------------------------------------------------------------

## Pays somebody what they are owed, as far as the account stretches. What it
## cannot cover becomes arrears against their name rather than vanishing.
func settle_wages(business: BusinessInstance, worker: EmployeeData, due: int) -> int:
	if business == null or worker == null or due <= 0:
		return 0
	var paid := mini(due, maxi(business.cash_balance, 0))
	if paid > 0:
		business.debit(paid, "Wages — %s" % worker.employee_name, &"wages")
	var short := due - paid
	if short > 0:
		worker.wage_arrears += short
		worker.missed_pay_runs += 1
		missed_wage_runs += 1
		obligation_missed.emit(business, Obligation.Kind.EMPLOYEE_WAGES, short)
		_notify_once(business, &"wages", "WAGES OVERDUE\n%s  ·  $%s owed" % [
			business.business_name.to_upper(),
			EconomyManager.with_thousands_separator(worker.wage_arrears),
		])
	elif worker.missed_pay_runs > 0:
		worker.missed_pay_runs = 0
	return paid


## Clears what a business owes its people, largest debt first, as far as the
## money goes. The rescue action a player takes after injecting capital.
func pay_arrears(business: BusinessInstance) -> int:
	if business == null:
		return 0
	var paid := 0
	var owing := business.employees.duplicate()
	owing.sort_custom(func(a, b): return a.wage_arrears > b.wage_arrears)
	for worker in owing:
		if worker.wage_arrears <= 0:
			continue
		var affordable := mini(worker.wage_arrears, maxi(business.cash_balance, 0))
		if affordable <= 0:
			break
		if not business.debit(
			affordable, "Wage arrears — %s" % worker.employee_name, &"wages"
		):
			break
		worker.wage_arrears -= affordable
		paid += affordable
		if worker.wage_arrears <= 0:
			worker.missed_pay_runs = 0
	if paid > 0:
		GameManager.notify(
			"WAGE ARREARS PAID\n$%s" % EconomyManager.with_thousands_separator(paid),
			GameManager.Tone.GOOD
		)
		AudioManager.play(&"money", AudioBuses.SFX, -10.0)
	return paid


# --- Capital -------------------------------------------------------------

## The player's own money into a business. The one place personal cash becomes
## business cash, and it goes through both ledgers so neither is invented.
func inject_capital(business: BusinessInstance, amount: int) -> bool:
	if business == null or amount <= 0:
		return false
	if not EconomyManager.can_afford(amount):
		GameManager.notify("YOU DO NOT HAVE THAT MUCH", GameManager.Tone.BAD)
		return false
	if not EconomyManager.spend(amount, "Capital — %s" % business.business_name):
		return false
	business.credit(amount, "Capital injection", &"capital")
	capital_injected.emit(business, amount)
	GameManager.notify(
		"CAPITAL INJECTED\n%s  ·  $%s" % [
			business.business_name.to_upper(),
			EconomyManager.with_thousands_separator(amount),
		],
		GameManager.Tone.GOOD
	)
	AudioManager.play(&"money", AudioBuses.SFX, -8.0)
	var before := business.distress
	review(business)
	if before == DistressState.State.CRITICAL and business.distress != before:
		CompanyManager.note_milestone(&"branch_saved")
	return true


## Whether taking money out would leave the business unable to pay what is
## already coming. §98 asks for a warning rather than a refusal.
func withdrawal_warning(business: BusinessInstance, amount: int) -> String:
	if business == null:
		return ""
	var due := 0
	for entry in obligations_for(business):
		due += entry.amount_due_by(TimeManager.day_index + FORECAST_DAYS)
	if business.cash_balance - amount >= due:
		return ""
	return "WITHDRAWAL MAY LEAVE %s UNABLE TO PAY UPCOMING EXPENSES" % (
		business.business_name.to_upper()
	)


# --- Distress ------------------------------------------------------------

## Re-reads where a business stands and moves it if the answer changed.
##
## Never closes anything itself. A business that has been CRITICAL for several
## days is closed by `_on_day_passed`, after it has been told so each day.
func review(business: BusinessInstance) -> DistressState.State:
	if business == null or business.is_closed():
		return DistressState.State.CLOSED
	var arrears := business.total_arrears()
	var misses := business.missed_payment_count()
	var due := 0
	for entry in obligations_for(business):
		due += entry.amount
	var state := DistressState.evaluate(arrears, misses, business.cash_balance, due)
	if state == business.distress:
		return state
	var worsened := state > business.distress
	business.distress = state
	if state != DistressState.State.CRITICAL:
		business.days_critical = 0
	distress_changed.emit(business, state)
	if worsened and DistressState.is_alarming(state):
		_notify_once(business, &"distress", "%s\n%s" % [
			"BUSINESS AT RISK" if state == DistressState.State.CRITICAL
				else "CASH FLOW WARNING",
			business.business_name.to_upper(),
		])
	business.changed.emit()
	return state


func review_all() -> void:
	for business in BusinessManager.get_businesses():
		review(business)


func _on_day_passed(_day_index: int) -> void:
	_warned_today.clear()
	for business in BusinessManager.get_businesses():
		if business.is_closed():
			continue
		review(business)
		if business.distress != DistressState.State.CRITICAL:
			continue
		business.days_critical += 1
		var left := DistressState.DAYS_AT_CRITICAL_BEFORE_CLOSURE - business.days_critical
		if left > 0:
			GameManager.notify(
				"BUSINESS AT RISK\n%s  ·  %d day%s to put it right" % [
					business.business_name.to_upper(), left, "" if left == 1 else "s"
				],
				GameManager.Tone.BAD
			)
			continue
		# The warnings ran out. §79: the branch closes, the company does not.
		BusinessManager.close_business_for_distress(business)
		businesses_closed += 1
		business_closed_by_distress.emit(business)


func _on_rent_missed(property: CommercialProperty, arrears: int) -> void:
	rent_defaults += 1
	var business := BusinessManager.business_for_property(property.property_id)
	if business == null:
		return
	obligation_missed.emit(business, Obligation.Kind.COMMERCIAL_RENT, arrears)
	_notify_once(business, &"rent", "RENT OVERDUE\n%s  ·  $%s" % [
		business.business_name.to_upper(),
		EconomyManager.with_thousands_separator(arrears),
	])
	review(business)


## How far into a lease default a business is, in words. §73's progression,
## read off the arrears the property already tracks rather than counted twice.
func lease_default_stage(business: BusinessInstance) -> String:
	var unit := business.property() if business != null else null
	if unit == null or not unit.has_landlord() or unit.arrears <= 0:
		return ""
	var missed := int(float(unit.arrears) / float(maxi(unit.rent_amount, 1)))
	if missed >= 3:
		return "LEASE AT RISK"
	if missed == 2:
		return "DEFAULT NOTICE"
	return "RENT OVERDUE"


func _notify_once(business: BusinessInstance, key: StringName, message: String) -> void:
	var id := "%s/%s" % [business.business_id, key]
	if _warned_today.has(id):
		return
	_warned_today[id] = true
	GameManager.notify(message, GameManager.Tone.BAD)


# --- Save ----------------------------------------------------------------

func clear() -> void:
	missed_wage_runs = 0
	rent_defaults = 0
	loan_defaults = 0
	businesses_closed = 0
	businesses_liquidated = 0
	properties_foreclosed = 0
	_warned_today.clear()


func save_state() -> Dictionary:
	return {
		"missed_wage_runs": missed_wage_runs,
		"rent_defaults": rent_defaults,
		"loan_defaults": loan_defaults,
		"businesses_closed": businesses_closed,
		"businesses_liquidated": businesses_liquidated,
		"properties_foreclosed": properties_foreclosed,
	}


func load_state(state: Dictionary) -> void:
	clear()
	missed_wage_runs = int(state.get("missed_wage_runs", 0))
	rent_defaults = int(state.get("rent_defaults", 0))
	loan_defaults = int(state.get("loan_defaults", 0))
	businesses_closed = int(state.get("businesses_closed", 0))
	businesses_liquidated = int(state.get("businesses_liquidated", 0))
	properties_foreclosed = int(state.get("properties_foreclosed", 0))
