class_name InventorySlot
extends RefCounted
## One stack in an Inventory. Kept as its own class so slot rules (stacking,
## capacity) live in one place instead of being scattered through Inventory.

var item: ItemData = null
var quantity: int = 0
## How many of this stack were not paid for. Metadata on the stack rather than a
## parallel "stolen inventory", so every existing path — stacking, using, the UI,
## the save — keeps working and only the things that care about provenance ask.
var stolen: int = 0


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


func has_stolen() -> bool:
	return stolen > 0


## Adds up to `amount`, returning how many actually fit.
func add(other: ItemData, amount: int, is_stolen: bool = false) -> int:
	var accepted := mini(amount, space_for(other))
	if accepted <= 0:
		return 0
	if is_empty():
		item = other
		quantity = 0
		stolen = 0
	quantity += accepted
	if is_stolen:
		stolen += accepted
	return accepted


## Removes up to `amount`, returning how many were actually removed.
##
## Legitimate goods go first. A player who bought one sandwich and stole another
## eats the one they paid for, so being arrested afterwards costs them the stolen
## one — which is the behaviour that makes the flag mean anything.
func remove(amount: int) -> int:
	if is_empty():
		return 0
	var removed := mini(amount, quantity)
	var legitimate := quantity - stolen
	var taken_from_stolen := maxi(removed - legitimate, 0)

	quantity -= removed
	stolen -= taken_from_stolen
	if quantity <= 0:
		clear()
	return removed


## Drops only the unpaid part of the stack. Returns how many were taken.
func remove_stolen() -> int:
	if is_empty() or stolen <= 0:
		return 0
	var taken := mini(stolen, quantity)
	quantity -= taken
	stolen = 0
	if quantity <= 0:
		clear()
	return taken


func clear() -> void:
	item = null
	quantity = 0
	stolen = 0
