class_name VenueService
extends RefCounted

## One thing you can buy at a counter and consume on the spot.
##
## An everyday activity is a price, a few minutes, and an effect on how the
## player feels. That is the whole of it — no preparation, no quality, no
## ingredients. You order, you wait, you feel better.
##
## Nothing here is an item. A meal eaten at a table never enters the inventory,
## which is the difference between eating out and doing the shopping.

var service_id: StringName = &""
var label: String = "Order"
var detail: String = ""
var price: int = 5
## In-game minutes it takes. The clock is the cost that makes a sit-down meal
## different from a sandwich out of the bag.
var minutes: int = 10
var hunger: float = 0.0
var energy: float = 0.0
var health: float = 0.0


static func make(
	id: StringName, name: String, text: String, cost: int, takes: int,
	fills: float = 0.0, wakes: float = 0.0, mends: float = 0.0
) -> VenueService:
	var service := VenueService.new()
	service.service_id = id
	service.label = name
	service.detail = text
	service.price = cost
	service.minutes = takes
	service.hunger = fills
	service.energy = wakes
	service.health = mends
	return service


## What it does, in the words the counter uses.
func effect_line() -> String:
	var parts := PackedStringArray()
	if hunger > 0.0:
		parts.append("+%d food" % roundi(hunger))
	elif hunger < 0.0:
		parts.append("%d food" % roundi(hunger))
	if energy > 0.0:
		parts.append("+%d energy" % roundi(energy))
	elif energy < 0.0:
		parts.append("%d energy" % roundi(energy))
	if health > 0.0:
		parts.append("+%d health" % roundi(health))
	parts.append("%d min" % minutes)
	return "  ·  ".join(parts)
