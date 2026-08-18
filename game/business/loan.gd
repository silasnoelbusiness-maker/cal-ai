class_name Loan
extends RefCounted
## Borrowed money and what it costs.
##
## Deliberately simple arithmetic rather than an amortisation schedule: a fixed
## payment every so many days until the balance is gone, with the interest added
## up front. The player needs to be able to see whether the payment is affordable
## at a glance, and a real repayment table is not that.

enum Status { ACTIVE, PAID, DEFAULTED }

var loan_id: StringName = &""
var business_id: StringName = &""
var display_name: String = "Business Loan"
var principal: int = 0
## Annualish rate, applied once to the whole principal when the loan is drawn.
var interest_rate: float = 0.08
var payment_amount: int = 0
var payment_interval_days: int = 7
var remaining_balance: int = 0
var next_payment_day: int = 0
var missed_payments: int = 0
var interest_paid: int = 0
var status: Status = Status.ACTIVE


## Draws a loan. The interest is added to what has to be repaid, so a $10,000
## loan at 8% is $10,800 back — visible, and impossible to misread.
static func create(
	id: StringName, owner_business: StringName, loan_name: String,
	amount: int, rate: float, payment: int, interval_days: int
) -> Loan:
	var loan := Loan.new()
	loan.loan_id = id
	loan.business_id = owner_business
	loan.display_name = loan_name
	loan.principal = amount
	loan.interest_rate = rate
	loan.remaining_balance = amount + roundi(float(amount) * rate)
	loan.payment_amount = payment
	loan.payment_interval_days = interval_days
	loan.next_payment_day = TimeManager.day_index + interval_days
	return loan


func total_interest() -> int:
	return roundi(float(principal) * interest_rate)


func is_active() -> bool:
	return status == Status.ACTIVE and remaining_balance > 0


func is_due(day_index: int) -> bool:
	return is_active() and day_index >= next_payment_day


## What is actually owed this time round: the scheduled payment, or whatever is
## left if that is less. Never more than the balance, so a loan cannot be
## overpaid into a negative.
func due_amount() -> int:
	return mini(payment_amount, remaining_balance)


## Applies a payment. Returns what was actually taken off the balance.
func apply_payment(amount: int) -> int:
	var paid := clampi(amount, 0, remaining_balance)
	remaining_balance -= paid
	if remaining_balance <= 0:
		remaining_balance = 0
		status = Status.PAID
	return paid


func advance_schedule() -> void:
	next_payment_day = TimeManager.day_index + payment_interval_days


## A missed payment costs a little more and is remembered. Nothing repossesses
## anything yet; the count is what a later consequence will read.
func miss_payment() -> void:
	missed_payments += 1
	remaining_balance += maxi(roundi(float(payment_amount) * 0.05), 5)
	advance_schedule()


func status_text() -> String:
	if status == Status.PAID:
		return "PAID"
	if missed_payments > 0:
		return "OVERDUE (%d missed)" % missed_payments
	return "ACTIVE"


func to_dict() -> Dictionary:
	return {
		"id": String(loan_id),
		"business": String(business_id),
		"name": display_name,
		"principal": principal,
		"rate": interest_rate,
		"payment": payment_amount,
		"interval": payment_interval_days,
		"remaining": remaining_balance,
		"next_payment_day": next_payment_day,
		"missed": missed_payments,
		"interest_paid": interest_paid,
		"status": int(status),
	}


static func from_dict(state: Dictionary) -> Loan:
	var loan := Loan.new()
	loan.loan_id = StringName(state.get("id", ""))
	loan.business_id = StringName(state.get("business", ""))
	loan.display_name = String(state.get("name", "Business Loan"))
	loan.principal = int(state.get("principal", 0))
	loan.interest_rate = float(state.get("rate", 0.08))
	loan.payment_amount = int(state.get("payment", 0))
	loan.payment_interval_days = int(state.get("interval", 7))
	loan.remaining_balance = int(state.get("remaining", 0))
	loan.next_payment_day = int(state.get("next_payment_day", 0))
	loan.missed_payments = int(state.get("missed", 0))
	loan.interest_paid = int(state.get("interest_paid", 0))
	loan.status = int(state.get("status", 0)) as Status
	return loan
