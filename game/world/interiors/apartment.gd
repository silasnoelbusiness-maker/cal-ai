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
## Which residence this room belongs to. The starter flat keeps the original
## group names so nothing that already looks them up has to change; a second
## apartment derives its own from its id.
@export var residence_id: StringName = &"larkspur"
## A bigger, better flat. Same room, more of it, and a proper living area.
@export var spacious: bool = false

const ENTRY_GROUP := &"apartment_interior_entry"
## Where this flat's front door sends the player back to.
const EXIT_GROUP := &"apartment_street_exit"

const ROOM := Rect2(-5.0, -4.0, 10.0, 8.0)
const ROOM_SPACIOUS := Rect2(-7.5, -6.0, 15.0, 12.0)
const WALL_HEIGHT := 2.8
const WALL_THICKNESS := 0.3
## Gap left in the south wall for the front door.
const DOORWAY_HALF_WIDTH := 1.2

var _palette: Dictionary = {}


static func entry_group_for(id: StringName) -> StringName:
	return ENTRY_GROUP if id == &"larkspur" else StringName("apartment_entry_%s" % id)


static func exit_group_for(id: StringName) -> StringName:
	return EXIT_GROUP if id == &"larkspur" else StringName("apartment_exit_%s" % id)


func room() -> Rect2:
	return ROOM_SPACIOUS if spacious else ROOM


func _ready() -> void:
	add_to_group(&"interior_room")
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
	# The better flat is dressed warmer and softer than the studio — same
	# fittings, nicer finishes, which is what the extra rent buys.
	_palette = {
		"surround": CityKit.make_material(Color(0.075, 0.082, 0.098)),
		"floor": Palette.of(&"wood_floor" if spacious else &"lino_grey"),
		"rug": Palette.tinted(
			&"carpet_warm",
			Color(0.392, 0.302, 0.259) if spacious else Color(0.325, 0.353, 0.404)
		),
		"wall": Palette.of(&"wall_warm" if spacious else &"wall_paint"),
		"trim": Palette.of(&"wood_dark"),
		"bed": Palette.tinted(&"cloth", Color(0.365, 0.427, 0.510)),
		"linen": Palette.tinted(&"cloth", Color(0.851, 0.843, 0.808)),
		"wood": Palette.of(&"wood_dark"),
		"counter": Palette.of(&"counter_top"),
		"appliance": Palette.of(&"metal_pale"),
		"door": Palette.of(&"wood_dark"),
	}


func _build_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)

	# The flat sits in open space, so a dark apron rings the floor. It stops the
	# camera seeing the void past the walls, and — more importantly — stops the
	# player falling forever if they walk out through the open doorway. Built as
	# a ring rather than one big slab so nothing is coplanar with the floor.
	var footprint := room().grow(WALL_THICKNESS)
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
	# Boards underfoot, so walking round the flat sounds like a home rather than
	# like the pavement outside it.
	SurfaceMap.tag(floor_slab, SurfaceMap.Surface.WOOD)
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

	var north := room().position.y
	var south := room().end.y
	var west := room().position.x
	var east := room().end.x

	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, room().size.x, WALL_THICKNESS))
	_add_wall(
		shell,
		"WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS,
			room().size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell,
		"WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS,
			room().size.y + WALL_THICKNESS * 2.0)
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
	bed.residence_id = residence_id
	bed.unavailable_prompt = "NOT YOUR HOME\nSet this flat as your home to sleep here"
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
	_build_living_area()


## What turns a room with a bed in it into somewhere somebody lives: a sofa
## facing a rug, a lamp beside it, a chest of drawers, plants and something on
## the wall. All from the shared prop library, so the two flats are the same
## furniture arranged differently rather than two hand-built rooms.
func _build_living_area() -> void:
	var holder := Node3D.new()
	holder.name = "Living"
	add_child(holder)

	var bounds := room()
	var west := bounds.position.x
	var east := bounds.end.x
	var north := bounds.position.y
	var south := bounds.end.y

	if spacious:
		PropKit.rug(
			holder, "LivingRug", Vector3(east - 3.6, 0.0, south - 3.4),
			Vector2(3.6, 2.6), Color(0.416, 0.325, 0.278)
		)
		PropKit.sofa(holder, "Sofa", Vector3(east - 3.6, 0.0, south - 2.0), 180.0)
		PropKit.lamp(holder, "FloorLamp", Vector3(east - 1.4, 0.0, south - 2.2))
		PropKit.dresser(holder, "Dresser", Vector3(west + 1.0, 0.0, south - 2.4), 90.0)
		PropKit.pot_plant(holder, "Plant", Vector3(east - 1.2, 0.0, north + 1.2), 1.15)
		PropKit.pot_plant(holder, "PlantSmall", Vector3(west + 0.9, 0.0, north + 3.4), 0.85)
		PropKit.wall_art(
			holder, "Art", Vector3(0.0, 1.85, north + 0.06), Vector2(1.5, 1.0),
			Color(0.396, 0.451, 0.510)
		)
		PropKit.wall_art(
			holder, "ArtSmall", Vector3(east - 0.08, 1.80, south - 4.4), Vector2(0.9, 1.2),
			Color(0.545, 0.435, 0.361), 90.0
		)
		# A bathroom door on the back wall. No room behind it, but a flat with
		# no bathroom door at all reads as a bedsit however big it is.
		CityKit.add_box(
			holder, "BathroomDoor", Vector3(west + 2.2, 1.05, north + 0.10),
			Vector3(0.90, 2.10, 0.08), _mat("door"), false, false
		)
	else:
		PropKit.rug(
			holder, "LivingRug", Vector3(1.2, 0.0, 1.6), Vector2(2.6, 1.9),
			Color(0.325, 0.353, 0.404)
		)
		PropKit.lamp(holder, "TableLamp", Vector3(-3.6, 0.78, -2.4), false)
		PropKit.dresser(holder, "Dresser", Vector3(west + 0.8, 0.0, 0.6), 90.0)
		PropKit.pot_plant(holder, "Plant", Vector3(east - 0.9, 0.0, north + 0.9), 0.9)
		PropKit.wall_art(
			holder, "Art", Vector3(-1.4, 1.80, north + 0.06), Vector2(1.1, 0.8),
			Color(0.451, 0.412, 0.353)
		)


func _build_lighting() -> void:
	# Interiors are lit independently of the day/night cycle, so the flat stays
	# usable at 03:00 without the sun reaching in.
	var bounds := room()
	var spots := (
		[Vector3(-3.5, 2.5, -2.0), Vector3(3.0, 2.5, 2.5), Vector3(0.0, 2.5, 0.0)] if spacious
		else [Vector3(-2.5, 2.5, -1.0), Vector3(2.5, 2.5, 1.5)]
	)
	for spot in spots:
		var light := OmniLight3D.new()
		light.name = "CeilingLight"
		light.position = spot
		light.light_color = Color(1.0, 0.937, 0.847)
		light.light_energy = 2.4
		light.omni_range = 12.0
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		add_child(light)

	# Fittings for those lights to come from: a warm panel tight against the top
	# of each side wall, which is what makes a flat glow at night from above.
	var strip := Palette.glow(Color(0.996, 0.925, 0.808), 0.5)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			self, "LightStrip%d" % int(side),
			Vector3(
				side * (bounds.size.x * 0.5 - 0.16), WALL_HEIGHT - 0.26,
				bounds.get_center().y
			),
			Vector3(0.10, 0.07, bounds.size.y * 0.80), strip, false, false
		)


func _build_markers_and_doors() -> void:
	# Just inside the front door.
	var entry := Marker3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(0.0, 0.4, 2.6)
	entry.add_to_group(entry_group_for(residence_id))
	add_child(entry)

	CityKit.add_box(
		self,
		"FrontDoorPanel",
		Vector3(0.0, 1.35, room().end.y + WALL_THICKNESS * 0.5),
		Vector3(DOORWAY_HALF_WIDTH * 2.0, 2.7, WALL_THICKNESS + 0.06),
		_mat("door"),
		false
	)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave apartment"
	exit_door.destination_group = exit_group_for(residence_id)
	exit_door.travel_minutes = 1
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, room().end.y - 0.6), 1.6)
