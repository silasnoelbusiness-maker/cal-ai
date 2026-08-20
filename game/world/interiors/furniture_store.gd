class_name FurnitureStoreInterior
extends Node3D
## Kingston Furnishings.
##
## A small shop rather than a warehouse: a few room sets laid out on the floor
## so the player can see what they are buying standing up, and a counter to buy
## it from. What they buy is delivered home — nobody carries a sofa out.
##
## The room sets are drawn with the same FurnitureKit that draws the furniture
## once it is in a flat, so the display sofa and the sofa the player owns are
## the same object.

const ENTRY_GROUP := &"furniture_store_entry"
const EXIT_GROUP := &"furniture_store_exit"

const ROOM := Rect2(-9.0, -7.0, 18.0, 14.0)
const WALL_HEIGHT := 3.6
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 1.4

## What stands on the shop floor, and where. Chosen to show one of each thing
## worth seeing at scale — a bed, a suite, a table and the storage — rather than
## the whole catalogue laid out in rows.
const DISPLAY: Array = [
	[&"bed_kingsize", Vector2(-5.6, -3.6), 0.0],
	[&"dresser_premium", Vector2(-7.4, -0.4), 90.0],
	[&"sofa_premium", Vector2(0.4, -3.8), 0.0],
	[&"table_premium", Vector2(0.6, 0.6), 0.0],
	[&"chair_premium", Vector2(-1.8, 0.6), 90.0],
	[&"tv_premium", Vector2(0.4, 3.0), 180.0],
	[&"storage_wardrobe", Vector2(6.2, -4.0), 0.0],
	[&"lamp_premium", Vector2(6.6, -1.2), 0.0],
	[&"plant_large", Vector2(6.8, 1.6), 0.0],
	[&"rug_premium", Vector2(0.5, -1.6), 0.0],
]

var _palette: Dictionary = {}


func _ready() -> void:
	add_to_group(&"interior_room")
	add_to_group(&"furniture_store")
	_build_palette()
	_build_shell()
	_build_displays()
	_build_counter()
	_build_lighting()
	_build_markers_and_doors()


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


func _build_palette() -> void:
	_palette = {
		"surround": CityKit.make_material(Color(0.075, 0.082, 0.098)),
		"floor": CityKit.make_material(Color(0.639, 0.573, 0.482)),
		"wall": CityKit.make_material(Color(0.902, 0.886, 0.855)),
		"trim": CityKit.make_material(Color(0.353, 0.294, 0.235)),
		"counter": CityKit.make_material(Color(0.400, 0.294, 0.204)),
		"top": CityKit.make_material(Color(0.847, 0.827, 0.792), 0.5, 0.2),
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

	var floor_slab := CityKit.add_slab(shell, "Floor", footprint, -0.4, 0.4, _mat("floor"))
	SurfaceMap.tag(floor_slab, SurfaceMap.Surface.WOOD)

	var north := ROOM.position.y
	var south := ROOM.end.y
	var west := ROOM.position.x
	var east := ROOM.end.x

	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, ROOM.size.x, WALL_THICKNESS))
	_add_wall(
		shell, "WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS, ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS, ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(shell, "WallSouthWest", Rect2(west, south, -DOORWAY_HALF_WIDTH - west, WALL_THICKNESS))
	_add_wall(
		shell, "WallSouthEast",
		Rect2(DOORWAY_HALF_WIDTH, south, east - DOORWAY_HALF_WIDTH, WALL_THICKNESS)
	)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.04), 0.0, 0.32, _mat("trim"))


## The room sets. Each is a real catalogue entry drawn at full size, with a
## small stand beside it the player can walk up to and buy from.
func _build_displays() -> void:
	var holder := Node3D.new()
	holder.name = "Displays"
	add_child(holder)

	for entry in DISPLAY:
		var furniture_id: StringName = entry[0]
		var spot: Vector2 = entry[1]
		var yaw: float = entry[2]
		var definition := FurnitureCatalogue.by_id(furniture_id)
		if definition == null:
			continue
		var piece := OwnedFurniture.new()
		piece.instance_id = StringName("display_%s" % furniture_id)
		piece.furniture_id = furniture_id
		piece.position = Vector3(spot.x, 0.0, spot.y)
		piece.rotation_y = deg_to_rad(yaw)
		FurnitureKit.build(holder, piece)


## The counter. Everything the shop sells is bought from here, not from the
## displays: the displays are what things look like, the counter is the shop.
func _build_counter() -> void:
	var holder := Node3D.new()
	holder.name = "Counter"
	holder.position = Vector3(6.4, 0.0, 4.4)
	add_child(holder)

	CityKit.add_box(holder, "Base", Vector3(0.0, 0.52, 0.0), Vector3(3.0, 1.04, 0.9), _mat("counter"))
	CityKit.add_box(
		holder, "Top", Vector3(0.0, 1.07, 0.0), Vector3(3.2, 0.06, 1.05), _mat("top"), false
	)
	CityKit.add_box(
		holder, "Backboard", Vector3(0.0, 1.7, -1.1), Vector3(3.6, 2.2, 0.14), _mat("trim"), false
	)
	CityKit.add_box(
		holder, "Sign", Vector3(0.0, 2.25, -1.02), Vector3(2.8, 0.6, 0.05),
		CityKit.make_emissive_material(Color(0.855, 0.686, 0.451), 0.6), false, false
	)

	var till := FurnitureStorePoint.new()
	till.name = "SalesPoint"
	till.prompt_action = "Browse Furniture"
	till.prompt_subtitle = "Kingston Furnishings"
	till.focus_priority = 1
	CityKit.attach_interactable(self, till, holder.position + Vector3(0.0, 0.9, 1.5), 2.0)


func _build_lighting() -> void:
	for spot: Vector3 in [
		Vector3(-5.0, 2.9, -2.0), Vector3(1.0, 2.9, -2.0), Vector3(6.0, 2.9, -1.0),
		Vector3(-2.0, 2.9, 3.0), Vector3(4.0, 2.9, 3.5),
	]:
		var light := OmniLight3D.new()
		light.name = "ShopLight"
		light.position = spot
		light.light_color = Color(1.0, 0.949, 0.882)
		light.light_energy = 2.2
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
		self, "FrontDoorPanel", Vector3(0.0, 1.35, ROOM.end.y + WALL_THICKNESS * 0.5),
		Vector3(DOORWAY_HALF_WIDTH * 2.0, 2.7, WALL_THICKNESS + 0.06), _mat("trim"), false
	)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave store"
	exit_door.destination_group = EXIT_GROUP
	exit_door.travel_minutes = 1
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, ROOM.end.y - 0.6), 1.6)
