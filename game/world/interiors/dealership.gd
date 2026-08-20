class_name DealershipInterior
extends Node3D
## The car showroom.
##
## Built like every other interior — off to one side of the world, entered by
## teleport, roofless so the elevated camera can see in — but dressed to feel
## dearer than the shops: a glass frontage, a pale polished floor, lit plinths
## and the cars themselves standing on them.
##
## The cars on the floor are real models with their physics turned off. That
## matters: what the player is looking at is exactly the car they will drive out
## in, not an approximation of it built for the showroom.

const ENTRY_GROUP := &"dealership_entry"
const EXIT_GROUP := &"dealership_exit"
## Where a car the player has just bought is put down, in world space. Set by
## the district, which is the only thing that knows where its forecourt is.
const COLLECTION_GROUP := &"dealership_collection"

const ROOM := Rect2(-13.0, -9.0, 26.0, 18.0)
const WALL_HEIGHT := 4.2
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 2.0

## Which models stand on the floor, and where. Six of the ten: the cheap end,
## the middle and one of each expensive kind, so the range is legible at a
## glance without the room being a car park.
const FLOOR_PLAN: Array = [
	[&"compact", Vector2(-8.5, -5.0), 20.0],
	[&"hatchback", Vector2(-8.5, 1.0), -20.0],
	[&"sedan", Vector2(-2.6, -5.0), 12.0],
	[&"suv", Vector2(-2.6, 1.0), -12.0],
	[&"coupe", Vector2(3.4, -5.0), -8.0],
	[&"luxury_sedan", Vector2(3.4, 1.0), 8.0],
]

var _palette: Dictionary = {}


func _ready() -> void:
	add_to_group(&"interior_room")
	add_to_group(&"dealership")
	_build_palette()
	_build_shell()
	_build_floor_cars()
	_build_desk()
	_build_lighting()
	_build_markers_and_doors()


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


func _build_palette() -> void:
	_palette = {
		"surround": CityKit.make_material(Color(0.075, 0.082, 0.098)),
		"floor": CityKit.make_material(Color(0.259, 0.271, 0.298), 0.72, 0.05),
		"plinth": CityKit.make_material(Color(0.157, 0.176, 0.212)),
		"wall": CityKit.make_material(Color(0.612, 0.624, 0.647)),
		"trim": CityKit.make_material(Color(0.180, 0.196, 0.235)),
		"glass": CityKit.make_material(Color(0.510, 0.639, 0.706, 0.42), 0.85, 0.1),
		"desk": CityKit.make_material(Color(0.145, 0.216, 0.271)),
		"counter": CityKit.make_material(Color(0.847, 0.851, 0.859), 0.5, 0.2),
	}


func _build_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)

	var footprint := ROOM.grow(WALL_THICKNESS)
	var reach := 46.0
	var apron := [
		CityKit.rect_from_bounds(-reach, -reach, reach, footprint.position.y),
		CityKit.rect_from_bounds(-reach, footprint.end.y, reach, reach),
		CityKit.rect_from_bounds(-reach, footprint.position.y, footprint.position.x, footprint.end.y),
		CityKit.rect_from_bounds(footprint.end.x, footprint.position.y, reach, footprint.end.y),
	]
	for i in apron.size():
		CityKit.add_slab(shell, "Apron%d" % i, apron[i], -0.4, 0.4, _mat("surround"), true, false)

	var floor_slab := CityKit.add_slab(shell, "Floor", footprint, -0.4, 0.4, _mat("floor"))
	SurfaceMap.tag(floor_slab, SurfaceMap.Surface.TILE)

	var north := ROOM.position.y
	var south := ROOM.end.y
	var west := ROOM.position.x
	var east := ROOM.end.x

	# Three solid walls and a glass front, which is what makes it read as a
	# showroom rather than as a warehouse with cars in it.
	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, ROOM.size.x, WALL_THICKNESS))
	_add_wall(
		shell, "WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS, ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS, ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_glass(shell, "GlassWest", Rect2(west, south, -DOORWAY_HALF_WIDTH - west, WALL_THICKNESS))
	_add_glass(
		shell, "GlassEast", Rect2(DOORWAY_HALF_WIDTH, south, east - DOORWAY_HALF_WIDTH, WALL_THICKNESS)
	)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.05), 0.0, 0.30, _mat("trim"))


## A mullioned glass wall: solid at knee height and above the head, glass in
## between, with uprights every few metres.
func _add_glass(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name + "Sill", rect, 0.0, 0.55, _mat("trim"))
	CityKit.add_slab(parent, wall_name + "Head", rect, WALL_HEIGHT - 0.5, 0.5, _mat("trim"))
	CityKit.add_slab(parent, wall_name, rect, 0.55, WALL_HEIGHT - 1.05, _mat("glass"), false, false)
	var uprights := maxi(int(rect.size.x / 2.6), 1)
	for i in uprights + 1:
		var x := rect.position.x + rect.size.x * float(i) / float(uprights)
		CityKit.add_box(
			parent, "%sMullion%d" % [wall_name, i],
			Vector3(x, WALL_HEIGHT * 0.5, rect.position.y + rect.size.y * 0.5),
			Vector3(0.10, WALL_HEIGHT, rect.size.y + 0.04), _mat("trim"), false, false
		)


## The floor itself: a lit plinth per car, the car on it, and a stand beside it
## the player can walk up to and read.
func _build_floor_cars() -> void:
	var holder := Node3D.new()
	holder.name = "Floor"
	add_child(holder)

	for entry in FLOOR_PLAN:
		var model_id: StringName = entry[0]
		var spot: Vector2 = entry[1]
		var yaw: float = entry[2]
		var definition := VehicleCatalogue.data_for(model_id)
		if definition == null:
			continue

		var centre := Vector3(spot.x, 0.0, spot.y)
		CityKit.add_box(
			holder, "Plinth_%s" % model_id, centre + Vector3(0.0, 0.06, 0.0),
			Vector3(definition.body_length + 1.2, 0.12, definition.body_width + 1.4),
			_mat("plinth"), false, false
		)
		CityKit.add_box(
			holder, "PlinthEdge_%s" % model_id, centre + Vector3(0.0, 0.13, 0.0),
			Vector3(definition.body_length + 1.7, 0.03, definition.body_width + 1.9),
			CityKit.make_emissive_material(Color(0.933, 0.831, 0.588), 0.45), false, false
		)

		var car: Vehicle = VehicleCatalogue.scene_for(model_id).instantiate()
		car.name = "Display_%s" % model_id
		car.display_only = true
		car.position = centre + Vector3(0.0, 0.14, 0.0)
		car.rotation_degrees.y = yaw
		holder.add_child(car)

		var stand := DealershipDisplay.new()
		stand.name = "Stand_%s" % model_id
		stand.model_id = model_id
		stand.prompt_action = "View Vehicle"
		stand.prompt_subtitle = "%s  ·  $%s" % [
			definition.display_name, EconomyManager.with_thousands_separator(definition.price_new)
		]
		CityKit.attach_interactable(
			holder, stand, centre + Vector3(0.0, 0.9, definition.body_width * 0.5 + 1.1), 1.9
		)


## The sales desk. No haggling and nobody to haggle with — the panel is the
## salesperson — but a showroom with no desk in it reads as a car park.
func _build_desk() -> void:
	var holder := Node3D.new()
	holder.name = "SalesDesk"
	holder.position = Vector3(9.6, 0.0, -4.0)
	add_child(holder)

	CityKit.add_box(holder, "Desk", Vector3(0.0, 0.52, 0.0), Vector3(3.2, 1.04, 1.0), _mat("desk"))
	CityKit.add_box(
		holder, "Top", Vector3(0.0, 1.07, 0.0), Vector3(3.4, 0.06, 1.15), _mat("counter"), false
	)
	CityKit.add_box(
		holder, "Screen", Vector3(-0.8, 1.32, 0.1), Vector3(0.6, 0.42, 0.05),
		CityKit.make_emissive_material(Color(0.451, 0.694, 0.831), 0.4), false, false
	)
	CityKit.add_box(
		holder, "Backboard", Vector3(0.0, 1.9, -1.4), Vector3(4.6, 2.6, 0.16), _mat("trim"), false
	)
	CityKit.add_box(
		holder, "Sign", Vector3(0.0, 2.35, -1.30), Vector3(3.6, 0.7, 0.06),
		CityKit.make_emissive_material(Color(0.882, 0.812, 0.612), 0.55), false, false
	)

	var desk := DealershipDesk.new()
	desk.name = "SalesPoint"
	desk.prompt_action = "Sales Desk"
	desk.prompt_subtitle = "Buy, sell or part exchange"
	desk.focus_priority = 1
	CityKit.attach_interactable(self, desk, holder.position + Vector3(0.0, 0.9, 1.6), 2.0)


func _build_lighting() -> void:
	for spot: Vector3 in [
		Vector3(-8.0, 3.4, -2.0), Vector3(0.0, 3.4, -2.0), Vector3(8.0, 3.4, -2.0),
		Vector3(-4.0, 3.4, 4.0), Vector3(4.0, 3.4, 4.0),
	]:
		var light := OmniLight3D.new()
		light.name = "ShowroomLight"
		light.position = spot
		light.light_color = Color(1.0, 0.965, 0.918)
		light.light_energy = 0.85
		light.omni_range = 13.0
		light.shadow_enabled = false
		add_child(light)

	var strip := CityKit.make_emissive_material(Color(0.996, 0.961, 0.898), 0.35)
	for row: float in [-6.0, 0.0, 6.0]:
		CityKit.add_box(
			self, "Batten%d" % int(row), Vector3(0.0, WALL_HEIGHT - 0.22, row),
			Vector3(ROOM.size.x - 2.0, 0.08, 0.22), strip, false, false
		)


func _build_markers_and_doors() -> void:
	var entry := Marker3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(0.0, 0.4, ROOM.end.y - 1.8)
	entry.add_to_group(ENTRY_GROUP)
	add_child(entry)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave showroom"
	exit_door.destination_group = EXIT_GROUP
	exit_door.travel_minutes = 1
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, ROOM.end.y - 0.7), 1.8)
