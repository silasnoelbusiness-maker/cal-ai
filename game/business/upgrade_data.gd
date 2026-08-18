class_name BusinessUpgrade
extends RefCounted
## A permanent operational improvement, bought once per business.
##
## Not equipment: nothing is placed and nothing takes up floor space. An upgrade
## is a number that changes how the business runs, which is why they are looked
## up by effect (`Effect`) rather than by id — a second signage upgrade later is
## a new entry with the same effect and a bigger value.

enum Effect { ATTRACTION, REPUTATION_FLOOR, CHECKOUT_SPEED, STORAGE, PREPARATION_SPEED }

var upgrade_id: StringName = &""
var display_name: String = "Upgrade"
var description: String = ""
var cost: int = 300
var effect: Effect = Effect.ATTRACTION
var magnitude: float = 0.05
## Empty means any business type may buy it.
var business_types: Array[StringName] = []


static func make(
	id: StringName, display: String, description: String, cost: int,
	effect: Effect, magnitude: float, types: Array[StringName] = []
) -> BusinessUpgrade:
	var upgrade := BusinessUpgrade.new()
	upgrade.upgrade_id = id
	upgrade.display_name = display
	upgrade.description = description
	upgrade.cost = cost
	upgrade.effect = effect
	upgrade.magnitude = magnitude
	upgrade.business_types = types
	return upgrade


static func catalogue() -> Array[BusinessUpgrade]:
	return [
		make(
			&"better_signage", "Better Signage",
			"A lit sign people notice from across the street. +8% customers.",
			400, Effect.ATTRACTION, 0.08
		),
		make(
			&"improved_lighting", "Improved Lighting",
			"A pleasanter room. Reputation will not drift below 40.",
			300, Effect.REPUTATION_FLOOR, 40.0
		),
		make(
			&"fast_checkout", "Better Checkout System",
			"Scanners and a card reader. Serving is 20% quicker.",
			600, Effect.CHECKOUT_SPEED, 0.2
		),
		make(
			&"storage_expansion", "Storage Expansion",
			"Racking to the ceiling. +60 units of store room.",
			500, Effect.STORAGE, 60.0
		),
		make(
			&"second_grinder", "Second Grinder",
			"Two drinks at once. Preparation is 25% quicker.",
			550, Effect.PREPARATION_SPEED, 0.25, [&"coffee_shop"] as Array[StringName]
		),
	]


static func by_id(id: StringName) -> BusinessUpgrade:
	for upgrade in catalogue():
		if upgrade.upgrade_id == id:
			return upgrade
	return null


static func available_for(type_id: StringName) -> Array[BusinessUpgrade]:
	var found: Array[BusinessUpgrade] = []
	for upgrade in catalogue():
		if upgrade.business_types.is_empty() or upgrade.business_types.has(type_id):
			found.append(upgrade)
	return found
