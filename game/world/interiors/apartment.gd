class_name ApartmentInterior
extends Node3D
## The player's starter flat.
##
## Interiors live off to one side of the world rather than inside the building
## shell — the exterior stays loaded, the player is teleported here, and the
## camera reframes for the smaller space. That keeps doors instant and means a
## district and its interiors never have to fit inside each other geometrically.
##
## Built with the same CityKit primitives as the district, and deliberately
## roofless so the elevated camera can look down into the room.

## Where the district's apartment door sends the player.
const ENTRY_GROUP := &"apartment_interior_entry"
## Where this flat's front door sends the player back to.
const EXIT_GROUP := &"apartment_street_exit"

const ROOM := Rect2(-5.0, -4.0, 10.0, 8.0)
const WALL_HEIGHT := 2.8
const WALL_THICKNESS := 0.3
## Gap left in the south wall for the front door.
const DOORWAY_HALF_WIDTH := 1.2

var _palette: Dictionary = {}


func _ready() -> void:
	_build_palette()
	_build_shell()
	_build_bed()
	_build_kitchen()
	_build_furniture()
	_build_lighting()
	_build_markers_and_doors()


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


func _build_palette() -> void:
	_palette = {
		"surround": CityKit.make_material(Color(0.086, 0.094, 0.110)),
		"floor": CityKit.make_material(Color(0.361, 0.286, 0.216)),
		"rug": CityKit.make_material(Color(0.290, 0.325, 0.376)),
		"wall": CityKit.make_material(Color(0.612, 0.588, 0.545)),
		"trim": CityKit.make_material(Color(0.325, 0.318, 0.302)),
		"bed": CityKit.make_material(Color(0.416, 0.475, 0.549)),
		"linen": CityKit.make_material(Color(0.796, 0.788, 0.741)),
		"wood": CityKit.make_material(Color(0.400, 0.278, 0.176)),
		"counter": CityKit.make_material(Color(0.478, 0.494, 0.514)),
		"appliance": CityKit.make_material(Color(0.643, 0.659, 0.678), 0.5, 0.4),
		"door": CityKit.make_material(Color(0.247, 0.192, 0.145)),
	}


func _build_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)

	# The flat sits in open space, so a dark apron rings the floor. It stops the
	# camera seeing the void past the walls, and — more importantly — stops the
	# player falling forever if they walk out through the open doorway. Built as
	# a ring rather than one big slab so nothing is coplanar with the floor.
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
	CityKit.add_slab(
		shell,
		"Rug",
		Rect2(-2.4, -1.0, 5.0, 4.0),
		0.0,
		0.02,
		_mat("rug"),
		false,
		false
	)

	var north := ROOM.position.y
	var south := ROOM.end.y
	var west := ROOM.position.x
	var east := ROOM.end.x

	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, ROOM.size.x, WALL_THICKNESS))
	_add_wall(
		shell,
		"WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS,
			ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell,
		"WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS,
			ROOM.size.y + WALL_THICKNESS * 2.0)
	)
	# South wall, split around the front doorway.
	_add_wall(
		shell, "WallSouthWest", Rect2(west, south, -DOORWAY_HALF_WIDTH - west, WALL_THICKNESS)
	)
	_add_wall(
		shell,
		"WallSouthEast",
		Rect2(DOORWAY_HALF_WIDTH, south, east - DOORWAY_HALF_WIDTH, WALL_THICKNESS)
	)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	# A skirting band, so the walls are not one flat colour from above.
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.04), 0.0, 0.35, _mat("trim"))


func _build_bed() -> void:
	var holder := Node3D.new()
	holder.name = "Bed"
	holder.position = Vector3(-3.4, 0.0, -2.2)
	add_child(holder)

	CityKit.add_box(holder, "Frame", Vector3(0.0, 0.22, 0.0), Vector3(2.1, 0.44, 1.5), _mat("wood"))
	CityKit.add_box(
		holder, "Mattress", Vector3(0.0, 0.58, 0.0), Vector3(1.95, 0.3, 1.4), _mat("bed"), false
	)
	CityKit.add_box(
		holder, "Pillow", Vector3(-0.72, 0.8, 0.0), Vector3(0.45, 0.16, 1.0), _mat("linen"), false
	)
	CityKit.add_box(
		holder, "Nightstand", Vector3(1.5, 0.28, -0.5), Vector3(0.6, 0.56, 0.6), _mat("wood")
	)

	var bed := Bed.new()
	bed.name = "SleepPoint"
	bed.prompt_action = "Sleep"
	bed.prompt_subtitle = "until 07:00"
	bed.focus_priority = 1
	CityKit.attach_interactable(self, bed, holder.position + Vector3(0.0, 0.9, 1.5), 1.7)


func _build_kitchen() -> void:
	var holder := Node3D.new()
	holder.name = "Kitchen"
	holder.position = Vector3(3.1, 0.0, -3.0)
	add_child(holder)

	CityKit.add_box(
		holder, "Counter", Vector3(0.0, 0.46, 0.0), Vector3(3.4, 0.92, 0.7), _mat("counter")
	)
	CityKit.add_box(
		holder, "Worktop", Vector3(0.0, 0.95, 0.0), Vector3(3.5, 0.06, 0.78), _mat("trim"), false
	)
	CityKit.add_box(
		holder, "Fridge", Vector3(-2.1, 0.85, 0.05), Vector3(0.75, 1.7, 0.7), _mat("appliance")
	)
	CityKit.add_box(
		holder, "Sink", Vector3(0.8, 1.0, 0.0), Vector3(0.7, 0.12, 0.5), _mat("appliance"), false
	)

	# The tap is free: it takes the edge off, but it is no substitute for food.
	var tap := RestoreSpot.new()
	tap.name = "KitchenTap"
	tap.prompt_action = "Drink from the tap"
	tap.hunger = 8.0
	tap.energy = 3.0
	tap.time_cost_minutes = 2
	tap.cooldown_seconds = 6.0
	tap.success_message = "DRANK SOME WATER"
	CityKit.attach_interactable(
		self, tap, holder.position + Vector3(0.8, 1.0, 1.1), 1.5
	)


func _build_furniture() -> void:
	var holder := Node3D.new()
	holder.name = "Furniture"
	holder.position = Vector3(0.6, 0.0, 1.2)
	add_child(holder)

	CityKit.add_box(
		holder, "TableTop", Vector3(0.0, 0.74, 0.0), Vector3(1.6, 0.08, 0.9), _mat("wood")
	)
	for i in 4:
		var offset := Vector3(
			0.7 if i % 2 == 0 else -0.7, 0.37, 0.35 if i < 2 else -0.35
		)
		CityKit.add_box(
			holder, "TableLeg%d" % i, offset, Vector3(0.08, 0.74, 0.08), _mat("wood"), false
		)
	CityKit.add_box(
		holder, "Chair", Vector3(-1.2, 0.45, 0.0), Vector3(0.5, 0.9, 0.5), _mat("wood")
	)


func _build_lighting() -> void:
	# Interiors are lit independently of the day/night cycle, so the flat stays
	# usable at 03:00 without the sun reaching in.
	for spot in [Vector3(-2.5, 2.5, -1.0), Vector3(2.5, 2.5, 1.5)]:
		var light := OmniLight3D.new()
		light.name = "CeilingLight"
		light.position = spot
		light.light_color = Color(1.0, 0.925, 0.82)
		light.light_energy = 3.4
		light.omni_range = 11.0
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		add_child(light)


func _build_markers_and_doors() -> void:
	# Just inside the front door.
	var entry := Marker3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(0.0, 0.4, 2.6)
	entry.add_to_group(ENTRY_GROUP)
	add_child(entry)

	CityKit.add_box(
		self,
		"FrontDoorPanel",
		Vector3(0.0, 1.35, ROOM.end.y + WALL_THICKNESS * 0.5),
		Vector3(DOORWAY_HALF_WIDTH * 2.0, 2.7, WALL_THICKNESS + 0.06),
		_mat("door"),
		false
	)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave apartment"
	exit_door.destination_group = EXIT_GROUP
	exit_door.travel_minutes = 1
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, ROOM.end.y - 0.6), 1.6)
