class_name KitchenOrder
extends RefCounted
## One ticket in a kitchen.
##
## The thing that makes a restaurant different from a counter: an order exists
## for a while between being placed and being eaten, and during that while it is
## somebody's job. Tickets are never dropped — a cook who goes home leaves the
## order sitting there unstarted, which is exactly what the player should see
## happening.
##
## Transient by design. Nothing here is saved: a reload clears the floor and the
## kitchen with it, and the business's money, stock and staff are untouched.

enum Stage { WAITING, COOKING, READY, DELIVERED, ABANDONED }

var order_id: int = 0
## Whoever is waiting for it. Held loosely — the customer may be freed.
var customer: Object = null
var recipe: ItemData = null
var order_time: float = 0.0
var stage: Stage = Stage.WAITING
var assigned_cook: EmployeeData = null
var ready_time: float = 0.0
## 0-100, decided when the cook starts it.
var quality: float = 70.0


static func make(id: int, who: Object, dish: ItemData, at: float) -> KitchenOrder:
	var order := KitchenOrder.new()
	order.order_id = id
	order.customer = who
	order.recipe = dish
	order.order_time = at
	return order


func is_open() -> bool:
	return stage == Stage.WAITING or stage == Stage.COOKING


func customer_is_gone() -> bool:
	return customer == null or not is_instance_valid(customer)


func waited_for(now: float) -> float:
	return maxf(now - order_time, 0.0)


func stage_label() -> String:
	match stage:
		Stage.COOKING:
			return "Cooking"
		Stage.READY:
			return "On the pass"
		Stage.DELIVERED:
			return "Served"
		Stage.ABANDONED:
			return "Walked out"
		_:
			return "Waiting"
