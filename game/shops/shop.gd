class_name Shop
extends Interactable
## A counter the player can buy from.
##
## Stock is a list of ItemData resources, so a new shop is a new stock list and
## a pair of opening hours — nothing about the convenience store is hard-coded.
## Restaurants, car dealers and player-owned businesses later reuse this by
## swapping the stock and overriding `get_price`.

signal purchase_made(item: ItemData, price: int)
signal purchase_failed(item: ItemData, result: Result)

enum Result { OK, CLOSED, NOT_ENOUGH_CASH, INVENTORY_FULL, NO_BUYER }

@export var shop_name: String = "Shop"
@export var stock: Array[ItemData] = []
@export_group("Opening hours")
@export_range(0, 23) var opens_hour: int = 6
@export_range(0, 24) var closes_hour: int = 23
## Multiplies the item's base price. Lets a later premium shop charge more
## without duplicating the item catalogue.
@export var price_multiplier: float = 1.0


func _ready() -> void:
	TimeManager.hour_passed.connect(_on_hour_passed)
	TimeManager.clock_synced.connect(_refresh_open_state)
	_refresh_open_state()


func is_open() -> bool:
	var hour := TimeManager.hour
	if opens_hour == closes_hour:
		return true
	if opens_hour < closes_hour:
		return hour >= opens_hour and hour < closes_hour
	# Wraps past midnight.
	return hour >= opens_hour or hour < closes_hour


func get_price(item: ItemData) -> int:
	if item == null:
		return 0
	return maxi(1, roundi(float(item.price) * price_multiplier))


## Runs a purchase end to end: checks, payment, delivery. Returns why it failed
## so the UI can say something specific.
func buy(item: ItemData, buyer: Node) -> Result:
	if not is_open():
		purchase_failed.emit(item, Result.CLOSED)
		return Result.CLOSED
	if item == null or buyer == null or not buyer.has_method("get_inventory"):
		purchase_failed.emit(item, Result.NO_BUYER)
		return Result.NO_BUYER

	var inventory: Inventory = buyer.call("get_inventory")
	if inventory == null:
		purchase_failed.emit(item, Result.NO_BUYER)
		return Result.NO_BUYER

	var price := get_price(item)
	if not EconomyManager.can_afford(price):
		purchase_failed.emit(item, Result.NOT_ENOUGH_CASH)
		return Result.NOT_ENOUGH_CASH
	# Check room before taking the money, so a full bag never costs the player.
	if not inventory.can_add(item, 1):
		purchase_failed.emit(item, Result.INVENTORY_FULL)
		return Result.INVENTORY_FULL

	if not EconomyManager.spend(price, "%s — %s" % [shop_name, item.display_name]):
		purchase_failed.emit(item, Result.NOT_ENOUGH_CASH)
		return Result.NOT_ENOUGH_CASH

	inventory.add(item, 1)
	purchase_made.emit(item, price)
	return Result.OK


static func describe_result(result: Result) -> String:
	match result:
		Result.OK:
			return ""
		Result.CLOSED:
			return "THE SHOP IS CLOSED"
		Result.NOT_ENOUGH_CASH:
			return "NOT ENOUGH CASH"
		Result.INVENTORY_FULL:
			return "NO ROOM IN YOUR BAG"
		_:
			return "CANNOT BUY THAT"


func _perform(interactor: Node3D) -> void:
	GameManager.request_screen(&"shop", self, interactor)


func _on_hour_passed(_hour: int) -> void:
	_refresh_open_state()


func _refresh_open_state() -> void:
	available = is_open()
	unavailable_prompt = "CLOSED · opens %02d:00" % opens_hour
