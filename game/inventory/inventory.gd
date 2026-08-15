class_name Inventory
extends Node
## A fixed-size, stacking inventory.
##
## Lives as a child of whoever owns it, so NPCs, shops or vehicle boots can all
## reuse it later. It knows nothing about UI — it emits `changed` and the panel
## redraws.

signal changed()
signal item_added(item: ItemData, quantity: int)
signal item_removed(item: ItemData, quantity: int)
signal item_used(item: ItemData)
## Emitted when an add could not fit, so callers can refund or warn.
signal add_rejected(item: ItemData, quantity: int)

@export var slot_count: int = 8

var _slots: Array[InventorySlot] = []


func _ready() -> void:
	_rebuild_slots()


func _rebuild_slots() -> void:
	_slots.clear()
	for i in maxi(slot_count, 1):
		_slots.append(InventorySlot.new())


func get_slots() -> Array[InventorySlot]:
	if _slots.is_empty():
		_rebuild_slots()
	return _slots


func get_slot(index: int) -> InventorySlot:
	var slots := get_slots()
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## How many of `item` would fit right now.
func space_for(item: ItemData) -> int:
	if item == null:
		return 0
	var total := 0
	for slot in get_slots():
		total += slot.space_for(item)
	return total


func can_add(item: ItemData, quantity: int = 1) -> bool:
	return space_for(item) >= quantity


## Adds as much as fits. Returns how many were actually stored; emits
## `add_rejected` with the remainder when the inventory ran out of room.
func add(item: ItemData, quantity: int = 1) -> int:
	if item == null or quantity <= 0:
		return 0

	var remaining := quantity
	# Top up existing stacks before opening a new slot.
	for slot in get_slots():
		if remaining <= 0:
			break
		if slot.holds(item):
			remaining -= slot.add(item, remaining)
	for slot in get_slots():
		if remaining <= 0:
			break
		if slot.is_empty():
			remaining -= slot.add(item, remaining)

	var stored := quantity - remaining
	if stored > 0:
		item_added.emit(item, stored)
		changed.emit()
	if remaining > 0:
		add_rejected.emit(item, remaining)
	return stored


func remove_from_slot(index: int, quantity: int = 1) -> int:
	var slot := get_slot(index)
	if slot == null or slot.is_empty():
		return 0
	var item := slot.item
	var removed := slot.remove(quantity)
	if removed > 0:
		item_removed.emit(item, removed)
		changed.emit()
	return removed


## Uses one item from a slot, consuming it only if the use had an effect.
func use_slot(index: int, user: Node) -> bool:
	var slot := get_slot(index)
	if slot == null or slot.is_empty():
		return false

	var item := slot.item
	if not item.use(user):
		return false

	slot.remove(1)
	item_used.emit(item)
	item_removed.emit(item, 1)
	changed.emit()
	return true


func count_of(item_id: StringName) -> int:
	var total := 0
	for slot in get_slots():
		if not slot.is_empty() and slot.item.id == item_id:
			total += slot.quantity
	return total


func total_items() -> int:
	var total := 0
	for slot in get_slots():
		total += slot.quantity
	return total


func is_empty() -> bool:
	return total_items() == 0


func clear() -> void:
	for slot in get_slots():
		slot.clear()
	changed.emit()
