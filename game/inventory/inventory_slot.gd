class_name InventorySlot
extends RefCounted
## One stack in an Inventory. Kept as its own class so slot rules (stacking,
## capacity) live in one place instead of being scattered through Inventory.

var item: ItemData = null
var quantity: int = 0


func is_empty() -> bool:
	return item == null or quantity <= 0


func holds(other: ItemData) -> bool:
	return not is_empty() and other != null and item.id == other.id


## How many more of `other` this slot could take.
func space_for(other: ItemData) -> int:
	if other == null:
		return 0
	if is_empty():
		return maxi(other.max_stack, 1)
	if not holds(other):
		return 0
	return maxi(item.max_stack, 1) - quantity


## Adds up to `amount`, returning how many actually fit.
func add(other: ItemData, amount: int) -> int:
	var accepted := mini(amount, space_for(other))
	if accepted <= 0:
		return 0
	if is_empty():
		item = other
		quantity = 0
	quantity += accepted
	return accepted


## Removes up to `amount`, returning how many were actually removed.
func remove(amount: int) -> int:
	if is_empty():
		return 0
	var removed := mini(amount, quantity)
	quantity -= removed
	if quantity <= 0:
		clear()
	return removed


func clear() -> void:
	item = null
	quantity = 0
