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

@export_group("Consumable")
@export var consumable: bool = false
@export var restores_hunger: float = 0.0
@export var restores_energy: float = 0.0
@export var restores_health: float = 0.0
## In-game minutes consuming this costs.
@export var use_minutes: int = 0


func can_use(user: Node) -> bool:
	return consumable and user != null and user.has_method("get_stats")


## Applies the item's effect. Returns false when the item does nothing here, so
## the inventory knows not to spend it.
func use(user: Node) -> bool:
	if not can_use(user):
		return false
	var stats: PlayerStats = user.call("get_stats")
	if stats == null:
		return false

	stats.add_hunger(restores_hunger)
	stats.add_energy(restores_energy)
	stats.add_health(restores_health)
	if use_minutes > 0:
		TimeManager.advance_minutes(use_minutes)
	return true


func get_category_name() -> String:
	return Category.keys()[category].capitalize()


## Short line the HUD shows after the item is used.
func get_use_summary() -> String:
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
