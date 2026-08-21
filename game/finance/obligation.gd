class_name Obligation
extends RefCounted
## Money a business has promised somebody, and when.
##
## Phase P did not replace the systems that already take payments — rent, wages,
## loans, mortgages and utilities all still charge themselves exactly as they
## did. What was missing was any way to ask "what does this business owe over
## the next week, and what has it already failed to pay", because each of those
## systems only knew about itself.
##
## So this is a *view* rather than a ledger: built on demand from whatever the
## existing systems say is due, and never the thing that moves the money. That
## matters — two places that both think they are charging rent is exactly the
## bug this phase must not introduce.

enum Kind {
	EMPLOYEE_WAGES, COMMERCIAL_RENT, WAREHOUSE_RENT, GARAGE_RENT,
	BUSINESS_LOAN, MORTGAGE, MAINTENANCE, UTILITIES, SUPPLIER_INVOICE,
}

const KIND_NAMES := {
	Kind.EMPLOYEE_WAGES: "Wages",
	Kind.COMMERCIAL_RENT: "Rent",
	Kind.WAREHOUSE_RENT: "Warehouse rent",
	Kind.GARAGE_RENT: "Garage rent",
	Kind.BUSINESS_LOAN: "Loan payment",
	Kind.MORTGAGE: "Mortgage",
	Kind.MAINTENANCE: "Maintenance",
	Kind.UTILITIES: "Utilities",
	Kind.SUPPLIER_INVOICE: "Supplier",
}

var kind: Kind = Kind.EMPLOYEE_WAGES
## Which business owes it. Empty for something the player owes personally, such
## as a mortgage on a property no business trades from.
var business_id: StringName = &""
var label: String = ""
var amount: int = 0
## Day index it falls due. Anything at or before today is already owed.
var due_day: int = 0
## What is already unpaid on it, if the paying system tracks that.
var overdue: int = 0
## Whatever the underlying system calls the thing — a loan id, a property id.
var source_id: StringName = &""


static func make(
	kind: Kind, business_id: StringName, label: String, amount: int,
	due_day: int, overdue: int = 0, source_id: StringName = &""
) -> Obligation:
	var entry := Obligation.new()
	entry.kind = kind
	entry.business_id = business_id
	entry.label = label
	entry.amount = amount
	entry.due_day = due_day
	entry.overdue = overdue
	entry.source_id = source_id
	return entry


func kind_name() -> String:
	return String(KIND_NAMES.get(kind, "Payment"))


func is_overdue() -> bool:
	return overdue > 0


func days_away(today: int) -> int:
	return due_day - today


## What it costs to be square on this one right now: what is already late plus
## whatever falls due today.
func amount_due_by(today: int) -> int:
	var total := overdue
	if due_day <= today:
		total += amount
	return total
