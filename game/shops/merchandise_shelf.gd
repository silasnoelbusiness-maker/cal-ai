class_name MerchandiseShelf
extends Interactable
## Goods on a shelf, which the player can simply pick up.
##
## Taking something is not itself a crime — it is picking merchandise off a
## shelf, which is what shops are for. It becomes SHOPLIFTING when it leaves the
## building unpaid, and that is StoreZone's job. Keeping the two apart is what
## lets a player change their mind on the way to the till.
##
## Everything taken here is flagged stolen in the inventory. Paying happens at
## the counter, and the counter's goods are never flagged.

signal taken(item: ItemData)

@export var stock: Array[ItemData] = []
## Which of `stock` this shelf hands over. Wraps, so one shelf can hold a small
## selection without needing an interactable per product.
@export var stock_index: int = 0
## Nothing left to take once this many have gone, so a shelf is not an infinite
## supply of free goods.
@export var units_available: int = 4

var _taken: int = 0


func _ready() -> void:
	add_to_group(&"merchandise")
	_refresh_prompt()


func get_item() -> ItemData:
	if stock.is_empty():
		return null
	return stock[stock_index % stock.size()]


func _perform(interactor: Node3D) -> void:
	var item := get_item()
	if item == null or interactor == null or not interactor.has_method("get_inventory"):
		return
	var inventory: Inventory = interactor.call("get_inventory")
	if inventory == null:
		return
	if not inventory.can_add(item, 1):
		GameManager.notify("NO ROOM IN YOUR BAG", GameManager.Tone.BAD)
		return

	inventory.add(item, 1, true)
	_taken += 1
	_refresh_prompt()
	GameManager.notify(
		"TOOK %s\nUNPAID" % item.display_name.to_upper(), GameManager.Tone.INFO
	)
	taken.emit(item)


func _refresh_prompt() -> void:
	var item := get_item()
	prompt_action = "Take %s" % (item.display_name if item != null else "item")
	prompt_subtitle = "unpaid"
	available = item != null and _taken < units_available
	unavailable_prompt = "" if item == null else "EMPTY"
