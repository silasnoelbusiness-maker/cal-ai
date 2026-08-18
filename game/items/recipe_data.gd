class_name RecipeData
extends Resource
## How one prepared product is made.
##
## The difference between a shop and a kitchen, as data. A convenience store
## sells what is on its shelves; a coffee shop holds beans, milk and cups and
## turns them into a drink when somebody orders one. Both go through the same
## sale, the same queue and the same books — only this resource stands between
## them.

@export var product: ItemData
## What one of them costs to make. Parallel arrays rather than a Dictionary
## because a .tres can hold typed resource arrays and cannot hold typed keys.
@export var ingredients: Array[ItemData] = []
@export var amounts: Array[int] = []
## Seconds to make one, before the barista's skill is applied.
@export var preparation_seconds: float = 6.0


## What one costs in ingredients at today's wholesale prices. The margin the
## player sees on the menu is derived from this rather than typed in twice.
func ingredient_cost() -> int:
	var total := 0
	for i in ingredients.size():
		if ingredients[i] == null:
			continue
		total += ingredients[i].get_wholesale_cost() * _amount(i)
	return total


func _amount(index: int) -> int:
	return maxi(int(amounts[index]) if index < amounts.size() else 1, 1)


## Whether a business is holding enough to make `quantity` of these.
func can_make(storage: Callable, quantity: int = 1) -> bool:
	for i in ingredients.size():
		if ingredients[i] == null:
			continue
		if int(storage.call(ingredients[i].id)) < _amount(i) * quantity:
			return false
	return true


## What making `quantity` consumes, as ingredient id -> units.
func consumption(quantity: int = 1) -> Dictionary:
	var needed := {}
	for i in ingredients.size():
		if ingredients[i] == null:
			continue
		var id: StringName = ingredients[i].id
		needed[id] = int(needed.get(id, 0)) + _amount(i) * quantity
	return needed
