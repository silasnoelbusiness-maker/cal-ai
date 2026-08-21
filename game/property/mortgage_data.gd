class_name MortgageData
extends RefCounted
## A loan secured against a property.
##
## Shares its shape with the business loans deliberately — a principal, a rate,
## a payment and a schedule — but is kept in its own list rather than mixed in
## with them. The two are different debts against different things, the profile
## screen reports them separately, and "what do I owe on my buildings" is a
## question the player asks on its own.
##
## Fixed rate, level payment, interest first. That is the whole model: complex
## enough that paying early is worth doing and that early payments are mostly
## interest, simple enough that a player can see where their money went.

enum Status { ACTIVE, OVERDUE, PAID, AT_RISK, FORECLOSING, FORECLOSED }

## Missed payments before the mortgage is flagged as being in trouble.
const AT_RISK_MISSES := 3
## Further misses past AT_RISK before the lender actually starts foreclosing.
## Phase N stopped at the warning; Phase P carries it through, and the gap
## between the two is deliberately wide enough to notice and act on.
const FORECLOSURE_MISSES := 5
## Days between the notice and losing the property. §88 asks for time to cure,
## and a week and a half of in-game days is time to sell a car.
const CURE_DAYS := 10

var mortgage_id: StringName = &""
var property_id: StringName = &""
var original_principal: int = 0
var remaining_principal: int = 0
var down_payment: int = 0
## Per payment period, not per year. The periods are days, not months, because
## the game's calendar is days.
var interest_rate: float = 0.06
var payment_amount: int = 0
var payment_interval_days: int = 7
var next_payment_day: int = 0
var term_payments: int = 0
var payments_made: int = 0
var missed_payments: int = 0
var status: Status = Status.ACTIVE
## Running totals, so the income report can say where the money actually went.
var interest_paid: int = 0
var principal_paid: int = 0
## Day the lender takes the property if the arrears are not cleared. -1 when no
## notice is outstanding.
var foreclosure_day: int = -1


func is_settled() -> bool:
	return status == Status.PAID or remaining_principal <= 0


func payments_remaining() -> int:
	return maxi(term_payments - payments_made, 0)


func is_due(day: int) -> bool:
	return not is_settled() and day >= next_payment_day


## Interest owed for one period on the balance as it stands.
func period_interest() -> int:
	return roundi(float(remaining_principal) * period_rate())


## The rate quoted is annual; a period is a week, and the game's year is not
## real. Fifty-two periods to the year keeps the arithmetic recognisable.
func period_rate() -> float:
	return interest_rate / 52.0


## What it would take to clear the debt today.
func payoff_amount() -> int:
	return maxi(remaining_principal, 0)


func status_label() -> String:
	match status:
		Status.PAID:
			return "PAID"
		Status.OVERDUE:
			return "OVERDUE"
		Status.AT_RISK:
			return "AT RISK"
		Status.FORECLOSING:
			return "FORECLOSURE NOTICE"
		Status.FORECLOSED:
			return "FORECLOSED"
		_:
			return "ACTIVE"


## What it takes to put the mortgage back in good standing. Not the whole debt:
## §90 is explicit that curing a default means clearing the arrears, and
## demanding the entire balance would make the notice a formality.
func arrears_amount() -> int:
	return payment_amount * maxi(missed_payments, 0)


func is_foreclosing() -> bool:
	return status == Status.FORECLOSING


func days_to_cure(today: int) -> int:
	return maxi(foreclosure_day - today, 0) if foreclosure_day >= 0 else 0


## The level payment that clears `principal` over `periods` at this rate. The
## standard amortisation formula, with the zero-interest case handled so a
## debug mortgage at 0% does not divide by zero.
static func level_payment(principal: int, rate_per_period: float, periods: int) -> int:
	if periods <= 0:
		return principal
	if rate_per_period <= 0.0001:
		return maxi(roundi(float(principal) / float(periods)), 1)
	var growth := pow(1.0 + rate_per_period, float(periods))
	return maxi(roundi(float(principal) * rate_per_period * growth / (growth - 1.0)), 1)


func to_dictionary() -> Dictionary:
	return {
		"mortgage_id": String(mortgage_id),
		"property_id": String(property_id),
		"original_principal": original_principal,
		"remaining_principal": remaining_principal,
		"down_payment": down_payment,
		"interest_rate": interest_rate,
		"payment_amount": payment_amount,
		"payment_interval_days": payment_interval_days,
		"next_payment_day": next_payment_day,
		"term_payments": term_payments,
		"payments_made": payments_made,
		"missed_payments": missed_payments,
		"status": int(status),
		"interest_paid": interest_paid,
		"principal_paid": principal_paid,
		"foreclosure_day": foreclosure_day,
	}


static func from_dictionary(state: Dictionary) -> MortgageData:
	var loan := MortgageData.new()
	loan.mortgage_id = StringName(state.get("mortgage_id", ""))
	loan.property_id = StringName(state.get("property_id", ""))
	loan.original_principal = int(state.get("original_principal", 0))
	loan.remaining_principal = int(state.get("remaining_principal", 0))
	loan.down_payment = int(state.get("down_payment", 0))
	loan.interest_rate = float(state.get("interest_rate", 0.06))
	loan.payment_amount = int(state.get("payment_amount", 0))
	loan.payment_interval_days = int(state.get("payment_interval_days", 7))
	loan.next_payment_day = int(state.get("next_payment_day", 0))
	loan.term_payments = int(state.get("term_payments", 0))
	loan.payments_made = int(state.get("payments_made", 0))
	loan.missed_payments = int(state.get("missed_payments", 0))
	loan.status = int(state.get("status", int(Status.ACTIVE))) as Status
	loan.interest_paid = int(state.get("interest_paid", 0))
	loan.principal_paid = int(state.get("principal_paid", 0))
	# A Phase N save has no notice outstanding, which is the right default.
	loan.foreclosure_day = int(state.get("foreclosure_day", -1))
	return loan
