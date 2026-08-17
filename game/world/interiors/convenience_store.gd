class_name ConvenienceStoreInterior
extends Node3D
## Harbour Row Market, inside.
##
## Same pattern as the flat: interiors sit off to one side of the world, the
## player is teleported in, and the camera reframes. Nothing about the district
## has to make room for them.
##
## This one carries the whole shoplifting loop in miniature, and each part of it
## is a reusable component rather than something specific to this shop:
##   * shelves hand goods over unpaid (MerchandiseShelf)
##   * the counter sells them properly, and can be robbed (Shop)
##   * behind the counter is off limits (RestrictedArea)
##   * leaving with unpaid goods is the crime (StoreZone)
## A second shop is the same five nodes with a different stock list.

const ENTRY_GROUP := &"market_interior_entry"
const EXIT_GROUP := &"market_street_exit"

const STOCK: Array[ItemData] = [
	preload("res://items/definitions/basic_meal.tres"),
	preload("res://items/definitions/snack_bar.tres"),
	preload("res://items/definitions/energy_drink.tres"),
]

const ROOM := Rect2(-6.0, -5.0, 12.0, 10.0)
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 1.3
## The counter runs along the north wall; staff space is behind it.
const COUNTER_Z := -3.0

var _palette: Dictionary = {}
var _shop: Shop = null
var _cashier: StoreEmployee = null


func _ready() -> void:
	_build_palette()
	_build_shell()
	_build_shelves()
	_build_counter()
	_build_lighting()
	_build_markers_and_doors()
	_build_zones()


func get_shop() -> Shop:
	return _shop


func get_cashier() -> StoreEmployee:
	return _cashier


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


func _build_palette() -> void:
	_palette = {
		"surround": CityKit.make_material(Color(0.086, 0.094, 0.110)),
		"floor": CityKit.make_material(Color(0.647, 0.639, 0.616)),
		"wall": CityKit.make_material(Color(0.784, 0.769, 0.722)),
		"trim": CityKit.make_material(Color(0.325, 0.318, 0.302)),
		"shelf": CityKit.make_material(Color(0.435, 0.451, 0.478)),
		"counter": CityKit.make_material(Color(0.400, 0.310, 0.216)),
		"worktop": CityKit.make_material(Color(0.302, 0.294, 0.278)),
		"till": CityKit.make_material(Color(0.220, 0.235, 0.259), 0.5, 0.3),
		"door": CityKit.make_material(Color(0.247, 0.192, 0.145)),
		"staff": CityKit.make_material(Color(0.549, 0.192, 0.176)),
	}


func _build_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)

	var footprint := ROOM.grow(WALL_THICKNESS)
	var reach := 40.0
	var apron := [
		CityKit.rect_from_bounds(-reach, -reach, reach, footprint.position.y),
		CityKit.rect_from_bounds(-reach, footprint.end.y, reach, reach),
		CityKit.rect_from_bounds(-reach, footprint.position.y, footprint.position.x, footprint.end.y),
		CityKit.rect_from_bounds(footprint.end.x, footprint.position.y, reach, footprint.end.y),
	]
	for i in apron.size():
		CityKit.add_slab(shell, "Apron%d" % i, apron[i], -0.4, 0.4, _mat("surround"), true, false)

	CityKit.add_slab(shell, "Floor", footprint, -0.4, 0.4, _mat("floor"))

	var north := ROOM.position.y
	var south := ROOM.end.y
	var west := ROOM.position.x
	var east := ROOM.end.x

	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, ROOM.size.x, WALL_THICKNESS))
	_add_wall(
		shell, "WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS,
			ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS,
			ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallSouthWest", Rect2(west, south, -DOORWAY_HALF_WIDTH - west, WALL_THICKNESS)
	)
	_add_wall(
		shell, "WallSouthEast",
		Rect2(DOORWAY_HALF_WIDTH, south, east - DOORWAY_HALF_WIDTH, WALL_THICKNESS)
	)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.04), 0.0, 0.35, _mat("trim"))


## Two aisles of goods. Each unit is solid so the player walks the aisle rather
## than through it, with the interactable in front of it.
func _build_shelves() -> void:
	var holder := Node3D.new()
	holder.name = "Shelves"
	add_child(holder)

	var runs := [
		# [x centre, z centre, which product, facing offset for the prompt]
		[-3.6, 0.6, 0, Vector3(0.0, 0.0, 1.3)],
		[-3.6, 2.6, 1, Vector3(0.0, 0.0, 1.3)],
		[3.6, 0.6, 2, Vector3(0.0, 0.0, 1.3)],
		[3.6, 2.6, 0, Vector3(0.0, 0.0, 1.3)],
	]
	for i in runs.size():
		var entry: Array = runs[i]
		var centre := Vector3(float(entry[0]), 0.0, float(entry[1]))
		CityKit.add_box(
			holder, "Unit%d" % i, centre + Vector3(0.0, 0.7, 0.0),
			Vector3(2.6, 1.4, 0.7), _mat("shelf")
		)
		# Product blocks on top, so the aisle reads as stocked from above.
		var item: ItemData = STOCK[int(entry[2]) % STOCK.size()]
		for column in 4:
			CityKit.add_box(
				holder, "Goods%d_%d" % [i, column],
				centre + Vector3(-0.9 + float(column) * 0.6, 1.52, 0.0),
				Vector3(0.42, 0.24, 0.42),
				CityKit.make_material(item.icon_color, 0.8),
				false, false
			)

		var shelf := MerchandiseShelf.new()
		shelf.name = "Shelf%d" % i
		shelf.stock = STOCK
		shelf.stock_index = int(entry[2])
		shelf.focus_priority = 1
		CityKit.attach_interactable(self, shelf, centre + entry[3] + Vector3.UP, 1.5)


func _build_counter() -> void:
	var holder := Node3D.new()
	holder.name = "Counter"
	add_child(holder)

	CityKit.add_box(
		holder, "Desk", Vector3(0.0, 0.5, COUNTER_Z), Vector3(5.0, 1.0, 0.8), _mat("counter")
	)
	CityKit.add_box(
		holder, "Worktop", Vector3(0.0, 1.03, COUNTER_Z),
		Vector3(5.2, 0.08, 0.92), _mat("worktop"), false
	)
	CityKit.add_box(
		holder, "Till", Vector3(-1.4, 1.24, COUNTER_Z),
		Vector3(0.7, 0.35, 0.5), _mat("till"), false
	)
	# A painted line on the floor marking the staff side.
	CityKit.add_slab(
		holder, "StaffLine",
		CityKit.rect_from_bounds(-2.6, COUNTER_Z - 1.9, 2.6, COUNTER_Z - 1.82),
		0.0, 0.015, _mat("staff"), false, false
	)

	_shop = Shop.new()
	_shop.name = "MarketCounter"
	_shop.save_id = &"shop_harbour_row_market"
	_shop.shop_name = "Harbour Row Market"
	_shop.stock = STOCK
	_shop.opens_hour = 6
	_shop.closes_hour = 23
	_shop.prompt_action = "Shop"
	_shop.prompt_subtitle = "Harbour Row Market"
	_shop.robbable = true
	CityKit.attach_interactable(self, _shop, Vector3(0.0, 1.0, COUNTER_Z + 1.5), 1.8)

	_cashier = StoreEmployee.new()
	_cashier.name = "Cashier"
	_cashier.body_color = Color(0.318, 0.396, 0.502)
	_cashier.accent_color = Color(0.204, 0.259, 0.337)
	_cashier.post_position = Vector3(0.0, 0.4, COUNTER_Z - 1.1)
	_cashier.post_facing = Vector3.BACK
	_cashier.position = _cashier.post_position
	add_child(_cashier)
	_shop.employee_path = _shop.get_path_to(_cashier)


func _build_lighting() -> void:
	for spot in [Vector3(-3.0, 2.7, -1.0), Vector3(3.0, 2.7, -1.0), Vector3(0.0, 2.7, 3.0)]:
		var light := OmniLight3D.new()
		light.name = "CeilingLight"
		light.position = spot
		light.light_color = Color(0.98, 0.98, 0.94)
		light.light_energy = 3.2
		light.omni_range = 12.0
		light.shadow_enabled = false
		add_child(light)


func _build_markers_and_doors() -> void:
	var entry := Marker3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(0.0, 0.4, ROOM.end.y - 1.6)
	entry.add_to_group(ENTRY_GROUP)
	add_child(entry)

	CityKit.add_box(
		self, "FrontDoorPanel",
		Vector3(0.0, 1.5, ROOM.end.y + WALL_THICKNESS * 0.5),
		Vector3(DOORWAY_HALF_WIDTH * 2.0, 3.0, WALL_THICKNESS + 0.06),
		_mat("door"), false
	)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave the shop"
	exit_door.destination_group = EXIT_GROUP
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, ROOM.end.y - 0.5), 1.5)


## The two volumes that make the crime side work: behind the counter is off
## limits, and the shop floor is what "inside" means for shoplifting.
func _build_zones() -> void:
	var staff := RestrictedArea.new()
	staff.name = "BehindTheCounter"
	staff.area_name = "STAFF ONLY"
	staff.grace_seconds = 4.0
	var staff_shape := BoxShape3D.new()
	staff_shape.size = Vector3(5.4, 2.6, 1.9)
	var staff_collider := CollisionShape3D.new()
	staff_collider.name = "Volume"
	staff_collider.shape = staff_shape
	staff.position = Vector3(0.0, 1.3, COUNTER_Z - 1.0)
	add_child(staff)
	staff.add_child(staff_collider)

	var zone := StoreZone.new()
	zone.name = "ShopFloor"
	zone.store_name = "Harbour Row Market"
	var zone_shape := BoxShape3D.new()
	zone_shape.size = Vector3(ROOM.size.x + 1.0, 3.4, ROOM.size.y + 1.0)
	var zone_collider := CollisionShape3D.new()
	zone_collider.name = "Volume"
	zone_collider.shape = zone_shape
	zone.position = Vector3(
		ROOM.position.x + ROOM.size.x * 0.5, 1.7, ROOM.position.y + ROOM.size.y * 0.5
	)
	add_child(zone)
	zone.add_child(zone_collider)
	zone.shop_path = zone.get_path_to(_shop)
