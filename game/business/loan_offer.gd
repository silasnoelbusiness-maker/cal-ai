class_name LoanOffer
extends RefCounted
## What the bank is willing to lend, as a small fixed menu.
##
## A menu rather than a calculator: three sizes, each with its own rate and
## weekly payment, so the player compares three concrete propositions instead of
## filling in a form. Eligibility is deliberately forgiving — the interesting
## decision is whether the payment is affordable, not whether the bank says yes.

var offer_id: StringName = &""
var display_name: String = "Loan"
var amount: int = 5000
var interest_rate: float = 0.08
var payment_amount: int = 550
var payment_interval_days: int = 7
## Reputation the business needs before this is offered at all.
var minimum_reputation: float = 0.0
## Days the business has to have been trading.
var minimum_days_trading: int = 0


static func make(
	id: StringName, display: String, amount: int, rate: float, payment: int,
	minimum_reputation: float = 0.0, minimum_days: int = 0
) -> LoanOffer:
	var offer := LoanOffer.new()
	offer.offer_id = id
	offer.display_name = display
	offer.amount = amount
	offer.interest_rate = rate
	offer.payment_amount = payment
	offer.minimum_reputation = minimum_reputation
	offer.minimum_days_trading = minimum_days
	return offer


## The three the bank offers. Bigger money costs a bigger weekly payment and
## asks for a business with some history behind it.
static func catalogue() -> Array[LoanOffer]:
	return [
		make(&"starter", "Starter Loan", 5000, 0.06, 320),
		make(&"growth", "Growth Loan", 15000, 0.08, 850, 45.0, 3),
		make(&"expansion", "Expansion Loan", 40000, 0.11, 2100, 55.0, 7),
	]


func total_repayable() -> int:
	return amount + roundi(float(amount) * interest_rate)


func payments_required() -> int:
	return ceili(float(total_repayable()) / float(maxi(payment_amount, 1)))
