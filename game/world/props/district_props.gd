class_name DistrictProps
extends RefCounted

## Small street furniture the two districts share, and the lookups that go with
## it.
##
## Both districts had grown their own copies of the same three helpers. This is
## where the shared ones live now, so a change to what a vending machine looks
## like is one edit rather than two that drift apart.


## Reads a venue kind out of a table line. Unknown names fall back to a cafe
## rather than failing the build: a mistyped table entry should give the player
## a slightly wrong shop, not a district with a hole in it.
static func service_kind(name: String) -> ServiceCatalogue.Kind:
	match name.strip_edges().to_upper():
		"DINER":
			return ServiceCatalogue.Kind.DINER
		"GYM":
			return ServiceCatalogue.Kind.GYM
		"BAR":
			return ServiceCatalogue.Kind.BAR
	return ServiceCatalogue.Kind.CAFE


## A drinks machine on the pavement, facing the way it is told.
##
## Machines carry a short stock list rather than the shop's whole catalogue:
## three things behind glass is what a machine is.
static func vending_machine(
	stock: Array[ItemData], at: Vector3, yaw_degrees: float, colour: Color
) -> VendingMachine:
	var machine := VendingMachine.new()
	machine.stock = stock
	machine.save_id = StringName("vending_%d_%d" % [roundi(at.x), roundi(at.z)])
	machine.position = at
	machine.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	machine.build_body(colour)
	return machine


## The three things a machine sells. Loaded rather than preloaded so this file
## stays a leaf: a const preload here would pull the item resources into every
## script that mentions a district.
static func machine_stock() -> Array[ItemData]:
	var stock: Array[ItemData] = []
	for path in [
		"res://items/definitions/bottled_water.tres",
		"res://items/definitions/energy_drink.tres",
		"res://items/definitions/basic_meal.tres",
	]:
		var item: ItemData = load(path)
		if item != null:
			stock.append(item)
	return stock
