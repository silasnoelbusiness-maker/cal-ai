class_name ItemCatalogue
extends RefCounted
## Every item that exists, looked up by id.
##
## Save files store item ids rather than resource paths, so a definition can be
## moved or renamed without breaking saves. Preloaded rather than scanned from
## disk, because directory listings under res:// are not dependable in an
## exported build.

const ITEMS: Array[ItemData] = [
	preload("res://items/definitions/basic_meal.tres"),
	preload("res://items/definitions/snack_bar.tres"),
	preload("res://items/definitions/energy_drink.tres"),
	preload("res://items/definitions/bottled_water.tres"),
	preload("res://items/definitions/soda_can.tres"),
	preload("res://items/definitions/steel_pipe.tres"),
	# Coffee shop: the drinks it sells, then the ingredients it holds.
	preload("res://items/definitions/filter_coffee.tres"),
	preload("res://items/definitions/latte.tres"),
	preload("res://items/definitions/iced_coffee.tres"),
	preload("res://items/definitions/house_tea.tres"),
	preload("res://items/definitions/coffee_beans.tres"),
	preload("res://items/definitions/milk_carton.tres"),
	preload("res://items/definitions/paper_cup.tres"),
	preload("res://items/definitions/tea_leaves.tres"),
	# Restaurant: the menu, then the ingredients the kitchen turns into it.
	preload("res://items/definitions/dish_burger.tres"),
	preload("res://items/definitions/dish_pasta.tres"),
	preload("res://items/definitions/dish_chicken.tres"),
	preload("res://items/definitions/dish_salad.tres"),
	preload("res://items/definitions/dish_breakfast.tres"),
	preload("res://items/definitions/dish_soup.tres"),
	preload("res://items/definitions/kitchen_meat.tres"),
	preload("res://items/definitions/kitchen_bread.tres"),
	preload("res://items/definitions/kitchen_vegetables.tres"),
	preload("res://items/definitions/kitchen_pasta.tres"),
	preload("res://items/definitions/kitchen_sauce.tres"),
	preload("res://items/definitions/kitchen_chicken.tres"),
	preload("res://items/definitions/kitchen_oil.tres"),
	# Venue: consumables kept as classes rather than a drinks list.
	preload("res://items/definitions/venue_soft_drink.tres"),
	preload("res://items/definitions/venue_mocktail.tres"),
	preload("res://items/definitions/venue_premium.tres"),
	preload("res://items/definitions/venue_snacks.tres"),
]


static func by_id(id: StringName) -> ItemData:
	for item in ITEMS:
		if item.id == id:
			return item
	return null


static func all() -> Array[ItemData]:
	return ITEMS.duplicate()
