extends Node
## Player finances.
##
## Every money movement in the game goes through deposit()/spend() so there is
## one audit trail. Businesses, rent, fines and wages added in later phases just
## call the same two methods with a different reason string.

signal cash_changed(new_balance: int, delta: int)
signal transaction_recorded(entry: Dictionary)
signal purchase_failed(amount: int, reason: String)

enum Category { INCOME, EXPENSE }
## Where the money came from. Recorded on every entry so a statistics screen can
## later separate what the player earned from what they took, without either side
## of the game needing to know the other exists.
enum Source { LEGAL, CRIME }

const STARTING_CASH := 500
## Transactions kept in memory. The rest is dropped so long sessions stay flat.
const MAX_HISTORY := 200

var cash: int = STARTING_CASH
var total_income: int = 0
var total_expenses: int = 0
## The part of total_income that came from crime.
var illegal_income: int = 0

var _history: Array[Dictionary] = []


func can_afford(amount: int) -> bool:
	return amount <= cash


## Returns false and leaves the balance untouched if the player is short.
func spend(amount: int, reason: String = "Purchase", source: Source = Source.LEGAL) -> bool:
	amount = absi(amount)
	if not can_afford(amount):
		purchase_failed.emit(amount, reason)
		return false
	cash -= amount
	total_expenses += amount
	_record(Category.EXPENSE, amount, reason, source)
	cash_changed.emit(cash, -amount)
	return true


func deposit(amount: int, reason: String = "Income", source: Source = Source.LEGAL) -> void:
	amount = absi(amount)
	if amount == 0:
		return
	cash += amount
	total_income += amount
	if source == Source.CRIME:
		illegal_income += amount
	_record(Category.INCOME, amount, reason, source)
	cash_changed.emit(cash, amount)


func get_cash_string() -> String:
	return "$%s" % _with_thousands_separator(cash)


func get_history() -> Array[Dictionary]:
	return _history.duplicate()


## Used by the save system (added in a later phase) to restore a balance
## without generating a bogus transaction.
func restore(balance: int, income: int = 0, expenses: int = 0) -> void:
	var delta := balance - cash
	cash = balance
	total_income = income
	total_expenses = expenses
	_history.clear()
	cash_changed.emit(cash, delta)


func _record(category: Category, amount: int, reason: String, source: Source) -> void:
	var entry := {
		"category": category,
		"source_type": source,
		"amount": amount,
		"reason": reason,
		"balance": cash,
		"day": TimeManager.day_index,
		"time": TimeManager.get_time_string(),
	}
	_history.append(entry)
	if _history.size() > MAX_HISTORY:
		_history.remove_at(0)
	transaction_recorded.emit(entry)


func _with_thousands_separator(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
