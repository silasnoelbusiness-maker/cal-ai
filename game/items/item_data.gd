class_name ItemData
extends Resource
## Definition of one kind of item.
##
## Items are Resources so the catalogue lives in .tres files that designers can
## edit without touching code — shops, jobs and the inventory all take ItemData
## references rather than hard-coded names. Weapons, keys, phones and business
## products in later phases either extend this class or add a new category.

enum Category { FOOD, DRINK, MISC }

## Stable identifier. Used by save data and by inventory lookups, so it must not
## change once a save exists.
@export var id: StringName = &""
@export var display_name: String = "Item"
@export_multiline var description: String = ""
@export var category: Category = Category.MISC
## Shop price in whole dollars.
@export var price: int = 0
@export var max_stack: int = 5
## Placeholder icon: a flat colour swatch until real icons exist.
@export var icon_color: Color = Color(0.6, 0.6, 0.62)

@export_group("Retail")
## What a business pays its supplier for one unit. The gap between this and what
## the player charges is the whole of retail: every business system in the game
## reads these three fields rather than hard-coding a margin.
@export var wholesale_cost: int = 0
## The price a customer considers normal. Charging this sells reliably; charging
## well over it does not. Defaults to `price` when left at zero.
@export var recommended_price: int = 0
## Relative likelihood a customer walks in wanting this. 1.0 is ordinary.
@export var demand_weight: float = 1.0

@export_group("Equipment")
## Whether this can be held. Equipping is a toggle, and never consumes the item.
@export var can_equip: bool = false
## Which slot it occupies. Only "hand" is used so far; a holster, a body slot and
## a bag slot are new values here rather than new code.
@export var equipment_slot: StringName = &"hand"
## Present on weapons, absent on everything else. What holding this does in a
## fight lives in the WeaponData, not here.
@export var weapon_data: WeaponData = null

@export_group("Consumable")
@export var consumable: bool = false
@export var restores_hunger: float = 0.0
@export var restores_energy: float = 0.0
@export var restores_health: float = 0.0
## In-game minutes consuming this costs.
@export var use_minutes: int = 0


func can_use(user: Node) -> bool:
	if user == null:
		return false
	if can_equip:
		return user.has_method("equip_item")
	return consumable and user.has_method("get_stats")


## Whether using one takes it out of the bag. Equipment does not: putting a pipe
## in your hand is not eating it.
func consumes_on_use() -> bool:
	return not can_equip


func is_weapon() -> bool:
	return can_equip and weapon_data != null


## Applies the item's effect. Returns false when the item does nothing here, so
## the inventory knows not to spend it.
func use(user: Node) -> bool:
	if not can_use(user):
		return false

	# Equipment toggles in and out of the hand rather than being spent.
	if can_equip:
		return bool(user.call("equip_item", self))
	var stats: PlayerStats = user.call("get_stats")
	if stats == null:
		return false

	stats.add_hunger(restores_hunger)
	stats.add_energy(restores_energy)
	stats.add_health(restores_health)
	# Counted where it is consumed rather than where it is bought, so a pantry
	# full of tins is not a fortnight of meals.
	if restores_hunger > 0.0:
		LifeStats.add(&"meals_eaten")
	if use_minutes > 0:
		TimeManager.advance_minutes(use_minutes)
	return true


## What a customer thinks this is worth. Falls back to the shelf price so an item
## that predates the retail fields still behaves sensibly.
func get_recommended_price() -> int:
	return recommended_price if recommended_price > 0 else price


## What a business pays for one. Falls back to a little under half the shelf
## price, which is the margin the catalogue is written to.
func get_wholesale_cost() -> int:
	return wholesale_cost if wholesale_cost > 0 else maxi(1, roundi(float(price) * 0.4))


func get_category_name() -> String:
	return Category.keys()[category].capitalize()


## Short line the HUD shows after the item is used.
func get_use_summary() -> String:
	if can_equip:
		return "EQUIPPED %s" % display_name.to_upper()
	var verb := "USED"
	match category:
		Category.FOOD:
			verb = "ATE"
		Category.DRINK:
			verb = "DRANK"

	var effects: Array[String] = []
	if restores_hunger > 0.0:
		effects.append("+%d HUNGER" % roundi(restores_hunger))
	if restores_energy > 0.0:
		effects.append("+%d ENERGY" % roundi(restores_energy))
	if restores_health > 0.0:
		effects.append("+%d HEALTH" % roundi(restores_health))

	var summary := "%s %s" % [verb, display_name.to_upper()]
	if not effects.is_empty():
		summary += "\n" + "  ".join(effects)
	return summary


## One-line effect description for shop listings.
func get_effect_line() -> String:
	if is_weapon():
		return "Weapon · %d damage · %.1fm reach" % [
			roundi(weapon_data.damage), weapon_data.attack_range
		]
	var effects: Array[String] = []
	if restores_hunger > 0.0:
		effects.append("Hunger +%d" % roundi(restores_hunger))
	if restores_energy > 0.0:
		effects.append("Energy +%d" % roundi(restores_energy))
	if restores_health > 0.0:
		effects.append("Health +%d" % roundi(restores_health))
	if effects.is_empty():
		return get_category_name()
	return "%s · %s" % [get_category_name(), "  ".join(effects)]
