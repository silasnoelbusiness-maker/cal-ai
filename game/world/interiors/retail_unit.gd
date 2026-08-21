class_name RetailUnit
extends Node3D
## An empty shop unit the player can rent, and then fill.
##
## Deliberately bare: four walls, a back room, a doorway and lights. Everything
## else — counters, shelves, racks — is bought and placed by the player, and the
## objects standing here are rebuilt from the business's own records whenever
## they change. Nothing about this room knows it is a convenience store.
##
## Two of these exist in the district, one per vacant unit, told apart by
## `property_id`. The entry and exit marker groups are derived from that id, so
## adding a third unit is another instance with another id and no new code.

signal player_entered()
signal player_exited()

## How big the unit is. Bigger rooms hold more equipment and more customers, and
## are what a dearer lease buys.
## LARGE arrived with Phase O: a gym and a venue need a room a shop does not.
enum Size { SMALL, MEDIUM, LARGE }

const WALL_HEIGHT := 3.2
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 1.4
## The pavement stub outside the door that customers walk in from.
const STREET_STUB_END := 15.0
## How far behind the front wall the store-room partition sits, per size.
const PARTITION_INSET := 3.6

## The depot palette. Named constants rather than literals buried in the
## builder, because six unexplained colours in the middle of a function is how
## a room ends up recoloured by accident.
const STEEL := Color(0.502, 0.525, 0.561)
const CRATE := Color(0.671, 0.549, 0.376)
const PAINT := Color(0.839, 0.729, 0.361)
const RECEIVING := Color(0.337, 0.463, 0.541)
const DISPATCH := Color(0.463, 0.541, 0.361)
const DESK_WOOD := Color(0.478, 0.412, 0.337)
const DESK_SCREEN := Color(0.365, 0.635, 0.741)

@export var property_id: StringName = &"unit_a"
@export var unit_name: String = "Retail Unit"
@export var size_class: Size = Size.SMALL
## Forces a dressing on a unit that will never hold a business — the company
## office. Empty means "whatever trades here", which is every other unit.
@export var interior_style: StringName = &""

## The room, derived from the size class in _ready. Everything that used to be a
## constant is now per-instance, because two units of different sizes share this
## script.
var room: Rect2 = Rect2(-7.0, -6.0, 14.0, 12.0)
var retail_area: Rect2 = Rect2(-6.4, -1.9, 12.8, 7.4)
var storage_area: Rect2 = Rect2(-6.4, -5.6, 12.8, 3.0)
## The partition between the shop floor and the store room.
var partition_z: float = -2.4
## Gap in the partition, as x bounds.
var partition_gap: Vector2 = Vector2(1.9, 4.4)

var _palette: Dictionary = {}
## Which dressing the shell currently wears, so a change of trade can be
## noticed. Empty until the room is first built.
var _style_built: StringName = &""
var _equipment_root: Node3D = null
var _sign_label: Node3D = null
var _open_light: MeshInstance3D = null
var _open_material: StandardMaterial3D = null
var _business: BusinessInstance = null
var _nodes_by_slot: Dictionary = {}
var _player_inside: bool = false


## Works out the room from the size class. One place, run before anything is
## built, so the geometry, the placement bounds and the walkable test can never
## disagree about how big the unit is.
func _measure_room() -> void:
	var size := Vector2(18.0, 15.0)
	if size_class == Size.SMALL:
		size = Vector2(14.0, 12.0)
	elif size_class == Size.LARGE:
		size = Vector2(24.0, 20.0)
	room = Rect2(-size.x * 0.5, -size.y * 0.5, size.x, size.y)
	partition_z = room.position.y + PARTITION_INSET
	partition_gap = Vector2(room.end.x - 5.1, room.end.x - 2.6)
	storage_area = Rect2(
		room.position.x + 0.6, room.position.y + 0.4,
		size.x - 1.2, PARTITION_INSET - 1.0
	)
	retail_area = Rect2(
		room.position.x + 0.6, partition_z + 0.5,
		size.x - 1.2, room.end.y - partition_z - 1.0
	)


## Puts the room up if it is not up already. Cheap to call repeatedly.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	# The palette depends on what trades here, and what trades here is only
	# known once a business has been bound — so it is chosen now rather than at
	# _ready, or a leased cafe would be dressed as a vacant unit for ever.
	_build_palette()
	_build_shell()
	_build_lighting()
	_build_signage()
	rebuild_equipment()
	_refresh_signage()
	_style_built = _style_id()


func is_built() -> bool:
	return _built


func _on_property_leased(property: CommercialProperty) -> void:
	if property != null and property.property_id == property_id:
		ensure_built()


static func entry_group_for(id: StringName) -> StringName:
	return StringName("retail_entry_%s" % id)


static func exit_group_for(id: StringName) -> StringName:
	return StringName("retail_exit_%s" % id)


## An unlet unit is an empty lot until somebody signs for it.
##
## Four of these exist and most of them are never rented. Building four rooms of
## walls, floors and lights at load cost enough frame time to be measurable, so
## the shell is put up the first time it is needed — signing the lease, or
## walking through the door — and never for a unit nobody takes.
var _built: bool = false


func _ready() -> void:
	add_to_group(&"retail_unit")
	_measure_room()
	_build_palette()
	_build_markers_and_doors()
	_build_presence_volume()

	_equipment_root = Node3D.new()
	_equipment_root.name = "Equipment"
	add_child(_equipment_root)

	var spawner := CustomerSpawner.new()
	spawner.name = "CustomerSpawner"
	add_child(spawner)

	TimeManager.minute_passed.connect(_on_minute_passed)
	player_entered.connect(_refresh_staff)
	player_exited.connect(_clear_visible_people)

	PropertyManager.property_leased.connect(_on_property_leased)
	BusinessManager.business_created.connect(_on_business_registered)
	BusinessManager.business_changed.connect(_on_business_changed)
	BusinessManager.business_opened.connect(_on_business_state_changed)
	BusinessManager.business_closed.connect(_on_business_state_changed)
	_bind_business()


## The unit a given business trades from, wherever it is in the tree.
static func for_business(business: BusinessInstance, tree: SceneTree) -> RetailUnit:
	if business == null:
		return null
	for node in tree.get_nodes_in_group(&"retail_unit"):
		var unit := node as RetailUnit
		if unit != null and unit.property_id == business.property_id:
			return unit
	return null


# --- Business binding ----------------------------------------------------

func get_business() -> BusinessInstance:
	return _business


func is_player_inside() -> bool:
	return _player_inside


func _bind_business() -> void:
	_business = BusinessManager.business_for_property(property_id)
	if _business != null:
		ensure_built()
	# A unit is usually leased before the business that will trade from it
	# exists, so the shell gets built as a vacant one and then never changes.
	# Re-dressing on a style change is what makes a cafe look like a cafe rather
	# than like the empty unit it was let as.
	_redress_if_style_changed()
	rebuild_equipment()
	_refresh_signage()


func _redress_if_style_changed() -> void:
	if not _built or _style_built == _style_id():
		return
	for node_name in ["Shell", "Lighting", "Signage"]:
		var node := get_node_or_null(node_name)
		if node != null:
			node.name = "%sOld" % node_name
			node.queue_free()
	_build_palette()
	_build_shell()
	_build_lighting()
	_build_signage()
	_refresh_signage()
	_style_built = _style_id()


func _on_business_registered(_business: BusinessInstance) -> void:
	_bind_business()


## Anything that changes a business redraws the room, if it is this room's.
##
## The property is what decides that, not the object identity: loading a save
## replaces every BusinessInstance with a fresh one, and a unit still holding the
## old object would quietly never rebuild its shelves again.
func _on_business_changed(business: BusinessInstance) -> void:
	var current := BusinessManager.business_for_property(property_id)
	if current != _business:
		_bind_business()
		return
	if business != _business:
		return
	rebuild_equipment()
	_refresh_signage()


func _on_business_state_changed(business: BusinessInstance) -> void:
	if business == _business:
		_refresh_signage()


## Rebuilds the floor from the business's equipment records.
##
## Cheap because it only rebuilds what changed: nodes whose record is still there
## are refreshed in place, so restocking a shelf does not churn the scene tree.
func rebuild_equipment() -> void:
	if _equipment_root == null:
		return
	if _business == null:
		for child in _equipment_root.get_children():
			child.queue_free()
		_nodes_by_slot.clear()
		return

	var live := {}
	for record in _business.equipment:
		live[record.slot_id] = record

	for slot in _nodes_by_slot.keys():
		if live.has(slot):
			continue
		var stale: Node = _nodes_by_slot[slot]
		if is_instance_valid(stale):
			stale.queue_free()
		_nodes_by_slot.erase(slot)

	for slot in live:
		var record: PlacedEquipment = live[slot]
		if _nodes_by_slot.has(slot):
			var existing: BusinessEquipment = _nodes_by_slot[slot]
			if is_instance_valid(existing):
				existing.position = record.position
				existing.rotation.y = record.rotation_y
				existing.refresh()
				continue
		var node := BusinessEquipment.new()
		node.name = "Equipment%d" % slot
		_equipment_root.add_child(node)
		node.setup(_business, record, self)
		node.register_requested.connect(_on_register_requested)
		_nodes_by_slot[slot] = node


func equipment_nodes() -> Array[BusinessEquipment]:
	var found: Array[BusinessEquipment] = []
	for slot in _nodes_by_slot:
		var node = _nodes_by_slot[slot]
		if is_instance_valid(node):
			found.append(node)
	return found


## The first piece of a given kind on the floor, or null. The one lookup every
## new role and every new customer route needs, and the reason none of them
## have to know what a business is fitted with.
func first_of_role(role: int) -> BusinessEquipment:
	for node in equipment_nodes():
		if node.is_role(role):
			return node
	return null


func nodes_of_role(role: int) -> Array[BusinessEquipment]:
	var found: Array[BusinessEquipment] = []
	for node in equipment_nodes():
		if node.is_role(role):
			found.append(node)
	return found


func first_checkout() -> BusinessEquipment:
	for node in equipment_nodes():
		if node.is_checkout():
			return node
	return null


func shelf_nodes() -> Array[BusinessEquipment]:
	var found: Array[BusinessEquipment] = []
	for node in equipment_nodes():
		if node.is_shelf():
			found.append(node)
	return found


func _on_register_requested(equipment: BusinessEquipment) -> void:
	var till := get_node_or_null("CustomerSpawner") as CustomerSpawner
	if till != null:
		till.toggle_player_at_register(equipment)


# --- People --------------------------------------------------------------

func get_spawner() -> CustomerSpawner:
	return get_node_or_null("CustomerSpawner") as CustomerSpawner


func get_cashier() -> EmployeeAI:
	var till := get_node_or_null("Cashier") as EmployeeAI
	return till if till != null else get_node_or_null("Barista") as EmployeeAI


func get_staff(role_name: String) -> EmployeeAI:
	return get_node_or_null(role_name) as EmployeeAI


func _on_minute_passed(_hour: int, _minute: int) -> void:
	if _player_inside:
		_refresh_staff()


## One node per job. A room only ever grows the jobs its business has, because
## a role nobody is rostered in never spawns anybody.
const STAFF_NODES := {
	"Cashier": EmployeeData.Role.CASHIER,
	"Barista": EmployeeData.Role.BARISTA,
	"Stocker": EmployeeData.Role.STOCKER,
	"Manager": EmployeeData.Role.MANAGER,
	"Cook": EmployeeData.Role.COOK,
	"Server": EmployeeData.Role.SERVER,
	"Receptionist": EmployeeData.Role.RECEPTIONIST,
	"Cleaner": EmployeeData.Role.CLEANER,
	"Security": EmployeeData.Role.SECURITY,
	"Bartender": EmployeeData.Role.BARTENDER,
	"Entertainer": EmployeeData.Role.ENTERTAINER,
}


## Staff only exist as people while somebody is here to see them. Out of sight
## the same employee is a line in the far simulation, which is why walking out
## of the shop does not stop them working.
##
## One node per job rather than one per person: the shop needs somebody on the
## counter, somebody on the machine and somebody on the floor, and which of the
## payroll that is comes from the roster.
func _refresh_staff() -> void:
	for node_name in STAFF_NODES:
		_refresh_one(String(node_name), int(STAFF_NODES[node_name]))


func _refresh_one(node_name: String, role: int) -> void:
	var present := get_node_or_null(node_name) as EmployeeAI
	if _business == null or not _player_inside:
		if present != null:
			present.queue_free()
		return

	# A manager is on duty whenever they are employed; everybody else works to
	# the roster.
	var rostered: EmployeeData = (
		_business.manager() if role == EmployeeData.Role.MANAGER
		else _business.rostered(role, TimeManager.hour)
	)
	if rostered == null:
		if present != null:
			present.end_shift()
		return
	if present != null:
		if present.employee == rostered:
			return
		present.free()
	# Nothing on the floor at all means nowhere to stand. A half-fitted room
	# still gets its staff — they simply have fewer places to be.
	if equipment_nodes().is_empty():
		return

	var arrival := get_node_or_null("CustomerArrival") as Marker3D
	var threshold := get_node_or_null("Threshold") as Marker3D
	if arrival == null or threshold == null:
		return

	var worker := EmployeeAI.new()
	worker.name = node_name
	add_child(worker)
	worker.setup(rostered, self, threshold.global_position, arrival.global_position)
	GameManager.notify(
		"EMPLOYEE SHIFT STARTED\n%s  ·  %s" % [
			rostered.employee_name.to_upper(), rostered.get_role_name()
		],
		GameManager.Tone.INFO
	)


## The player has left: the visible crowd goes with them. Nothing is lost —
## anybody mid-purchase has either paid or not, and the far simulation picks the
## shop up from the same numbers on the next tick.
func _clear_visible_people() -> void:
	var spawner := get_spawner()
	if spawner != null:
		spawner.stop_player_working()
		for customer in spawner.active_customers():
			customer.queue_free()
	for node_name in STAFF_NODES.keys():
		var worker := get_node_or_null(node_name) as EmployeeAI
		if worker != null:
			worker.queue_free()


# --- Placement -----------------------------------------------------------

## Whether a footprint of `size` centred on `local_point` is somewhere equipment
## may legally stand. Doorways and the partition gap are excluded, so a shelf can
## never be used to seal the shop.
func is_valid_placement(local_point: Vector3, size: Vector2) -> bool:
	var half := size * 0.5
	var footprint := Rect2(
		local_point.x - half.x, local_point.z - half.y, size.x, size.y
	)
	if not (_contains(retail_area, footprint) or _contains(storage_area, footprint)):
		return false
	# The way in, and the way through to the back.
	var front_door := Rect2(-DOORWAY_HALF_WIDTH - 0.4, room.end.y - 1.6, DOORWAY_HALF_WIDTH * 2.0 + 0.8, 2.2)
	if footprint.intersects(front_door):
		return false
	var doorway := Rect2(
		partition_gap.x - 0.4, partition_z - 1.0, partition_gap.y - partition_gap.x + 0.8, 2.0
	)
	return not footprint.intersects(doorway)


## Whether a person could stand at this spot: on the shop floor or in the store
## room, and not inside a wall. Used to pick which side of a counter or a shelf
## somebody can actually walk up to.
func is_inside_floor(local_point: Vector3) -> bool:
	var point := Vector2(local_point.x, local_point.z)
	return retail_area.has_point(point) or storage_area.has_point(point)


func _contains(area: Rect2, footprint: Rect2) -> bool:
	return area.encloses(footprint)


## Where the placement preview snaps to. Half-metre grid, which is fine enough
## to line a wall with shelves and coarse enough that they line up.
func snap_point(local_point: Vector3) -> Vector3:
	return Vector3(
		roundf(local_point.x * 2.0) / 2.0, 0.0, roundf(local_point.z * 2.0) / 2.0
	)


# --- Geometry ------------------------------------------------------------

func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


## Which way a unit is dressed. A shop and a cafe are the same room with
## different floors, walls and light, which is exactly what separates them in
## real life — and it means one interior serves both without a second scene.
func _style_id() -> StringName:
	if _business != null:
		return _business.type_id
	if interior_style != &"":
		return interior_style
	return &"vacant"


func _build_palette() -> void:
	var style := _style_id()
	var floor_mat := Palette.of(&"tile_floor")
	var wall_mat := Palette.of(&"wall_paint")
	var trim_mat := Palette.of(&"metal_mid")
	match style:
		&"coffee_shop":
			floor_mat = Palette.of(&"wood_floor")
			wall_mat = Palette.of(&"wall_warm")
			trim_mat = Palette.of(&"wood_dark")
		&"convenience_store":
			floor_mat = Palette.of(&"tile_checker")
			wall_mat = Palette.of(&"wall_paint")
			trim_mat = Palette.of(&"metal_mid")
		&"restaurant":
			# Warmer and darker than the cafe: a room people sit down in for an
			# hour rather than lean on a counter in for five minutes.
			floor_mat = Palette.of(&"wood_floor")
			wall_mat = CityKit.make_material(Color(0.286, 0.216, 0.192))
			trim_mat = Palette.of(&"wood_dark")
		&"gym":
			# Rubber floor and painted block, not a basement. The first pass at
			# this was as dark as the venue, which is not what a gym at six in
			# the morning looks like.
			floor_mat = CityKit.make_material(Color(0.310, 0.333, 0.365))
			wall_mat = CityKit.make_material(Color(0.522, 0.553, 0.592))
			trim_mat = Palette.of(&"metal_mid")
		&"warehouse":
			# Sealed concrete and painted block. A working building rather than
			# a shop: nothing here is meant to look inviting.
			floor_mat = Palette.of(&"concrete")
			wall_mat = CityKit.make_material(Color(0.478, 0.494, 0.522))
			trim_mat = Palette.of(&"metal_mid")
		&"office":
			floor_mat = Palette.of(&"wood_floor")
			wall_mat = CityKit.make_material(Color(0.808, 0.796, 0.769))
			trim_mat = Palette.of(&"metal_mid")
		&"nightclub":
			# Dark enough that the fittings are what light the room, light
			# enough that there is a room to see. Two passes at this were too
			# black to read; a venue floor is not the same thing as no floor.
			floor_mat = CityKit.make_material(Color(0.243, 0.216, 0.290))
			wall_mat = CityKit.make_material(Color(0.278, 0.243, 0.337))
			trim_mat = CityKit.make_material(Color(0.396, 0.325, 0.478))
		_:
			# Vacant: bare but finished. An empty unit is a rental, not a
			# debug room, so it gets a real floor and a real skirting.
			floor_mat = Palette.of(&"lino_grey")
			wall_mat = Palette.of(&"wall_paint")
			trim_mat = Palette.of(&"concrete_dark")

	_palette = {
		"surround": CityKit.make_material(Color(0.075, 0.082, 0.098)),
		"floor": floor_mat,
		"back_floor": Palette.of(&"concrete"),
		"wall": wall_mat,
		"trim": trim_mat,
		"door": Palette.of(&"wood_dark"),
		"pavement": Palette.of(&"sidewalk"),
		"sign": Palette.of(&"panel_navy"),
		"glass": Palette.of(&"glass_shop"),
		"metal": Palette.of(&"metal_pale"),
	}


func _build_shell() -> void:
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)

	var footprint := room.grow(WALL_THICKNESS)
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
	# A shop is tiled and a cafe is boarded, and the floor sounds like whichever
	# it is — the cheapest possible reinforcement that these are different kinds
	# of business.
	SurfaceMap.tag(
		floor_slab,
		SurfaceMap.Surface.WOOD if _style_id() == &"coffee_shop" else SurfaceMap.Surface.TILE
	)
	# The store room reads as a different room from above without a doorway shot.
	CityKit.add_slab(
		shell, "BackFloor",
		CityKit.rect_from_bounds(room.position.x, room.position.y, room.end.x, partition_z),
		0.0, 0.01, _mat("back_floor"), false, false
	)
	# A stub of pavement outside the door: customers arrive on it and walk in,
	# rather than appearing inside the shop.
	# Two centimetres proud of the apron it sits on: coplanar slabs z-fight, and
	# from this camera that reads as a shimmering rectangle outside the door.
	CityKit.add_slab(
		shell, "Pavement",
		CityKit.rect_from_bounds(-5.0, room.end.y + WALL_THICKNESS, 5.0, STREET_STUB_END),
		-0.4, 0.42, _mat("pavement"), true, false
	)

	var north := room.position.y
	var south := room.end.y
	var west := room.position.x
	var east := room.end.x

	_add_wall(shell, "WallNorth", Rect2(west, north - WALL_THICKNESS, room.size.x, WALL_THICKNESS))
	_add_wall(
		shell, "WallWest",
		Rect2(west - WALL_THICKNESS, north - WALL_THICKNESS, WALL_THICKNESS, room.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallEast",
		Rect2(east, north - WALL_THICKNESS, WALL_THICKNESS, room.size.y + WALL_THICKNESS * 2.0)
	)
	_add_wall(
		shell, "WallSouthWest",
		CityKit.rect_from_bounds(west, south, -DOORWAY_HALF_WIDTH, south + WALL_THICKNESS)
	)
	_add_wall(
		shell, "WallSouthEast",
		CityKit.rect_from_bounds(DOORWAY_HALF_WIDTH, south, east, south + WALL_THICKNESS)
	)

	_build_shopfront(shell)
	_build_store_room_dressing(shell)
	_build_trade_dressing(shell)

	# Partition, with a gap through to the store room.
	_add_wall(
		shell, "PartitionWest",
		CityKit.rect_from_bounds(west, partition_z, partition_gap.x, partition_z + WALL_THICKNESS)
	)
	_add_wall(
		shell, "PartitionEast",
		CityKit.rect_from_bounds(partition_gap.y, partition_z, east, partition_z + WALL_THICKNESS)
	)


## The street wall, from the inside: glazing either side of the doorway, a stall
## riser under it and a header above. Without it the front of a shop is a blank
## wall, which is the single strongest reason the old interiors read as boxes.
func _build_shopfront(parent: Node3D) -> void:
	var south := room.end.y
	var west := room.position.x
	var east := room.end.x
	for pair in [
		["West", west + 0.4, -DOORWAY_HALF_WIDTH - 0.2],
		["East", DOORWAY_HALF_WIDTH + 0.2, east - 0.4],
	]:
		var from := float(pair[1])
		var to := float(pair[2])
		if to - from < 0.6:
			continue
		var mid := (from + to) * 0.5
		var width := to - from
		CityKit.add_box(
			parent, "Riser%s" % pair[0], Vector3(mid, 0.30, south + 0.02),
			Vector3(width, 0.60, 0.10), _mat("trim"), false, false
		)
		CityKit.add_box(
			parent, "Glazing%s" % pair[0], Vector3(mid, 1.75, south + 0.02),
			Vector3(width, 2.30, 0.08), _mat("glass"), false, false
		)
		# Mullions, so a two-metre pane is not one flat sheet.
		var bays := maxi(int(width / 1.6), 1)
		for i in range(1, bays):
			CityKit.add_box(
				parent, "Mullion%s%d" % [pair[0], i],
				Vector3(from + width * float(i) / float(bays), 1.75, south + 0.04),
				Vector3(0.08, 2.30, 0.12), _mat("trim"), false, false
			)


## What the room has that the player did not buy: the fittings a business of
## this kind comes with rather than fits out. A cafe gets seating, a menu board
## and a plant; a shop gets a chiller cabinet against the wall.
##
## Kept clear of the customer routes — a table in the walk-up lane is a queue of
## stuck customers rather than a table — by hugging the side walls.
func _build_trade_dressing(parent: Node3D) -> void:
	var style := _style_id()
	match style:
		&"warehouse":
			_dress_warehouse(parent)
			return
		&"office":
			_dress_office(parent)
			return
		&"restaurant":
			_dress_restaurant(parent)
			return
		&"gym":
			_dress_gym(parent)
			return
		&"nightclub":
			_dress_nightclub(parent)
			return
	if style != &"coffee_shop" and style != &"convenience_store":
		return
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)

	var west := room.position.x + 1.25
	var east := room.end.x - 1.25

	if style == &"coffee_shop":
		# Seating down the west wall, out of the line between the door and the
		# counter.
		var seats := clampi(int(retail_area.size.y / 2.6), 2, 4)
		for i in seats:
			PropKit.cafe_table(
				holder, "CafeTable%d" % i,
				Vector3(
					west, 0.0,
					retail_area.position.y + 1.6 + float(i) * (retail_area.size.y - 3.2)
						/ float(maxi(seats - 1, 1))
				)
			)
		PropKit.menu_board(
			holder, "MenuBoard",
			Vector3(0.0, 2.05, partition_z + WALL_THICKNESS + 0.08),
			["ESPRESSO      2.60", "FLAT WHITE    3.20", "TEA           2.40", "PASTRY        2.90"]
		)
		PropKit.pot_plant(holder, "CafePlant", Vector3(east, 0.0, retail_area.end.y - 1.4), 1.1)
		PropKit.pot_plant(holder, "CafePlantB", Vector3(east, 0.0, retail_area.position.y + 1.2), 0.9)
	else:
		# A chiller run against the east wall: the thing a convenience store has
		# that a cafe does not, and the clearest way to tell the two apart from
		# above.
		var cabinets := clampi(int(retail_area.size.y / 2.0), 1, 3)
		for i in cabinets:
			PropKit.chiller(
				holder, "Chiller%d" % i,
				Vector3(
					east, 0.0,
					retail_area.position.y + 1.4 + float(i) * 1.85
				),
				-90.0
			)
		PropKit.menu_board(
			holder, "PriceBoard",
			Vector3(0.0, 2.05, partition_z + WALL_THICKNESS + 0.08),
			["TODAY", "WATER   1.60", "SODA    1.90", "SNACKS  1.40"]
		)




## The bits of a restaurant nobody buys: the menu on the wall, a service station
## against the side, and the plants that make a room look like it has been open
## for a while. The tables and the kitchen are equipment the player places.
func _dress_restaurant(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)
	var east := room.end.x - 1.2

	PropKit.menu_board(
		holder, "MenuBoard",
		Vector3(0.0, 2.05, partition_z + WALL_THICKNESS + 0.08),
		["BURGER MEAL   14", "PASTA BOWL    12", "CHICKEN       16", "SALAD          9"]
	)
	PropKit.pot_plant(holder, "DiningPlant", Vector3(east, 0.0, retail_area.end.y - 1.3), 1.2)
	PropKit.pot_plant(holder, "DiningPlantB", Vector3(east, 0.0, retail_area.position.y + 1.3), 1.0)
	# A pass-through hatch in the partition, so the kitchen reads as a kitchen
	# from the dining side even before the equipment is bought.
	CityKit.add_box(
		holder, "Hatch", Vector3(2.4, 1.35, partition_z + WALL_THICKNESS * 0.5),
		Vector3(2.2, 1.1, WALL_THICKNESS + 0.1),
		CityKit.make_material(Color(0.129, 0.106, 0.098)), false, false
	)
	CityKit.add_box(
		holder, "HatchLight", Vector3(2.4, 1.86, partition_z + WALL_THICKNESS * 0.5 - 0.12),
		Vector3(2.0, 0.07, 0.06),
		CityKit.make_emissive_material(Color(0.980, 0.808, 0.545), 0.9), false, false
	)


## Mirrors down one wall and a rubber-mat strip down the middle: the two things
## that say gym from above without a single machine in the room.
func _dress_gym(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)
	var west := room.position.x + 0.22

	var mirror := CityKit.make_material(Color(0.616, 0.678, 0.729))
	mirror.metallic = 0.7
	mirror.roughness = 0.12
	var panels := clampi(int(retail_area.size.y / 2.4), 2, 5)
	for i in panels:
		CityKit.add_box(
			holder, "Mirror%d" % i,
			Vector3(
				west, 1.55,
				retail_area.position.y + 1.4 + float(i) * (retail_area.size.y - 2.8)
					/ float(maxi(panels - 1, 1))
			),
			Vector3(0.06, 1.9, 2.0), mirror, false, false
		)
	CityKit.add_box(
		holder, "FloorMat", Vector3(0.0, 0.02, retail_area.get_center().y),
		Vector3(retail_area.size.x - 2.4, 0.03, 2.2),
		CityKit.make_material(Color(0.239, 0.267, 0.298)), false, false
	)
	PropKit.menu_board(
		holder, "PriceBoard",
		Vector3(0.0, 2.05, partition_z + WALL_THICKNESS + 0.08),
		["MEMBERSHIP", "PER WEEK", "DAY PASS", "OPEN 06-22"]
	)


## The room is the effect. Everything here is emissive and small, because a
## venue lit by its own fittings reads at a glance and costs nothing to draw.
func _dress_nightclub(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)

	var strip_colours: Array[Color] = [
		Color(0.541, 0.286, 0.878), Color(0.196, 0.749, 0.831),
		Color(0.910, 0.361, 0.541),
	]
	var west := room.position.x + 0.25
	var east := room.end.x - 0.25
	var strips := clampi(int(retail_area.size.y / 2.0), 2, 5)
	for i in strips:
		var z := retail_area.position.y + 1.2 + float(i) * (retail_area.size.y - 2.4) \
			/ float(maxi(strips - 1, 1))
		var tint: Color = strip_colours[i % strip_colours.size()]
		for side: float in [west, east]:
			CityKit.add_box(
				holder, "Strip%d_%d" % [i, int(side * 10.0)],
				Vector3(side, 2.35, z), Vector3(0.08, 0.10, 1.6),
				CityKit.make_emissive_material(tint, 1.6), false, false
			)
	# A band of light across the back wall behind where the booth goes.
	CityKit.add_box(
		holder, "BackWash", Vector3(0.0, 2.10, partition_z + WALL_THICKNESS + 0.06),
		Vector3(retail_area.size.x * 0.6, 0.14, 0.05),
		CityKit.make_emissive_material(strip_colours[0], 1.9), false, false
	)


## The company office: a desk, a computer, a meeting table and the name on the
## wall. Built rather than bought, because the office is not a business — it is
## somewhere to run the ones you have from, and nothing here is for sale.
func _dress_office(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)

	var wood := CityKit.make_material(Color(0.478, 0.412, 0.337))
	var dark := CityKit.make_material(Color(0.271, 0.286, 0.322))
	var centre := retail_area.get_center()

	CityKit.add_box(
		holder, "Desk", Vector3(centre.x - 3.4, 0.36, centre.y - 1.0),
		Vector3(1.8, 0.72, 0.85), wood, true
	)
	CityKit.add_box(
		holder, "DeskScreen", Vector3(centre.x - 3.4, 0.95, centre.y - 1.15),
		Vector3(0.56, 0.36, 0.05),
		CityKit.make_emissive_material(Color(0.365, 0.635, 0.741), 0.7), false, false
	)
	CityKit.add_box(
		holder, "DeskStand", Vector3(centre.x - 3.4, 0.76, centre.y - 1.05),
		Vector3(0.10, 0.14, 0.10), dark, false, false
	)
	CityKit.add_box(
		holder, "MeetingTable", Vector3(centre.x + 2.2, 0.36, centre.y + 0.6),
		Vector3(2.6, 0.72, 1.3), wood, true
	)
	for i in 4:
		CityKit.add_box(
			holder, "MeetingChair%d" % i,
			Vector3(
				centre.x + 1.2 + float(i % 2) * 2.0, 0.24,
				centre.y + 0.6 + (1.05 if i < 2 else -1.05)
			),
			Vector3(0.5, 0.48, 0.5), dark, false
		)
	# The company name, in whatever colour the company happens to use.
	var accent := Color(0.353, 0.612, 0.788)
	var first_brand := CompanyManager.brands()
	if not first_brand.is_empty():
		accent = first_brand[0].brand_color
	CityKit.add_box(
		holder, "CompanySign", Vector3(0.0, 2.15, partition_z + WALL_THICKNESS + 0.06),
		Vector3(2.6, 0.34, 0.06), CityKit.make_emissive_material(accent, 0.55), false, false
	)

	var terminal := CompanyTerminal.new()
	terminal.name = "CompanyTerminal"
	CityKit.attach_interactable(
		holder, terminal, Vector3(centre.x - 3.4, 0.9, centre.y - 1.0), 2.0
	)


## The depot: racking down both sides, a marked aisle between them, a bay by
## the door where deliveries land and a dispatch square where they go out.
##
## Everything here is built rather than bought. The racks the player pays for
## add capacity to the warehouse record, not objects to this room — a hundred
## individually placed pallets would be a placement puzzle nobody asked for,
## and the stock the racks hold is a number on the logistics screen.
func _dress_warehouse(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "TradeDressing"
	parent.add_child(holder)

	var steel := CityKit.make_material(STEEL)
	var crate := CityKit.make_material(CRATE)
	var paint := CityKit.make_material(PAINT)

	# Racking down both long walls, leaving a clear aisle between them.
	var bays := clampi(int(retail_area.size.y / 3.0), 2, 6)
	for side: float in [-1.0, 1.0]:
		for i in bays:
			var z := retail_area.position.y + 2.0 + float(i) * (retail_area.size.y - 4.0) \
				/ float(maxi(bays - 1, 1))
			var x := side * (room.size.x * 0.5 - 1.5)
			CityKit.add_box(
				holder, "Rack%d_%d" % [int(side), i], Vector3(x, 1.35, z),
				Vector3(1.6, 2.7, 2.2), steel
			)
			# Two shelves of pallets, so the racking reads as full from above.
			for level in 2:
				CityKit.add_box(
					holder, "Pallet%d_%d_%d" % [int(side), i, level],
					Vector3(x, 0.75 + float(level) * 1.1, z),
					Vector3(1.3, 0.5, 1.8), crate, false, false
				)

	# The aisle, painted on the floor.
	CityKit.add_box(
		holder, "Aisle", Vector3(0.0, 0.02, retail_area.get_center().y),
		Vector3(2.6, 0.03, retail_area.size.y - 1.0), paint, false, false
	)

	# Receiving, by the shutter, and dispatch at the far end. Marked squares
	# rather than machinery: the player needs to know which end is which.
	CityKit.add_box(
		holder, "ReceivingBay", Vector3(0.0, 0.03, retail_area.end.y - 2.2),
		Vector3(5.0, 0.04, 3.2), CityKit.make_material(RECEIVING), false, false
	)
	CityKit.add_box(
		holder, "DispatchBay", Vector3(0.0, 0.03, retail_area.position.y + 2.2),
		Vector3(5.0, 0.04, 3.2), CityKit.make_material(DISPATCH), false, false
	)
	PropKit.menu_board(
		holder, "DepotBoard",
		Vector3(0.0, 2.05, partition_z + WALL_THICKNESS + 0.08),
		["RECEIVING", "DISPATCH", "AISLE 1", "AISLE 2"]
	)

	# A desk in the corner for whoever is running the place.
	CityKit.add_box(
		holder, "Desk", Vector3(room.position.x + 2.2, 0.36, partition_z + 1.6),
		Vector3(1.6, 0.72, 0.8), CityKit.make_material(DESK_WOOD), true
	)
	CityKit.add_box(
		holder, "DeskScreen", Vector3(room.position.x + 2.2, 0.95, partition_z + 1.45),
		Vector3(0.5, 0.34, 0.05),
		CityKit.make_emissive_material(DESK_SCREEN, 0.6), false, false
	)

	var terminal := WarehouseTerminal.new()
	terminal.name = "WarehouseTerminal"
	CityKit.attach_interactable(
		holder, terminal, Vector3(room.position.x + 2.2, 0.9, partition_z + 1.6), 2.2
	)


## The back of house. A vacant unit gets an empty room with a rack in it; a
## trading one gets the boxes and pallets a stock room actually has.
func _build_store_room_dressing(parent: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "StoreRoomDressing"
	parent.add_child(holder)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(property_id)) + 11
	var back := Rect2(
		room.position.x + 0.7, room.position.y + 0.7,
		room.size.x - 1.4, maxf(partition_z - room.position.y - 1.4, 0.5)
	)
	if back.size.y < 1.0:
		return

	# A steel rack against the back wall. Not solid: the stocker walks this room
	# on a route the shelves do not know about, and a rack in the way of it
	# stops the shop restocking itself.
	var rack_z := back.position.y + 0.4
	CityKit.add_box(
		holder, "Rack", Vector3(back.get_center().x, 1.0, rack_z),
		Vector3(back.size.x * 0.72, 2.0, 0.55), _mat("metal"), false
	)
	for level in 3:
		CityKit.add_box(
			holder, "RackShelf%d" % level,
			Vector3(back.get_center().x, 0.45 + float(level) * 0.62, rack_z - 0.06),
			Vector3(back.size.x * 0.70, 0.05, 0.60), _mat("trim"), false, false
		)
	if _business != null:
		for level in 3:
			PropKit.goods_row(
				holder, "RackGoods%d" % level,
				Vector3(back.get_center().x, 0.48 + float(level) * 0.62, rack_z - 0.06),
				back.size.x * 0.62, [&"drinks", &"snacks", &"general"][level], rng
			)
		for i in 3:
			PropKit.crate_stack(
				holder, "Crates%d" % i,
				Vector3(
					rng.randf_range(back.position.x + 0.5, back.end.x - 0.5), 0.0,
					rng.randf_range(rack_z + 1.0, back.end.y - 0.4)
				),
				rng
			)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.04), 0.0, 0.35, _mat("trim"))


## Light, and something to see it coming from.
##
## The room has no ceiling — it cannot, with a camera directly above it — so the
## fittings run along the tops of the walls instead: an emissive strip that
## reads from above as a lit room, plus a handful of omnis doing the actual
## work. Warm in a cafe, cool in a shop, which is most of what makes the two
## feel like different businesses before you look at what is in them.
func _build_lighting() -> void:
	var style := _style_id()
	var warm := style == &"coffee_shop" or style == &"restaurant"
	var venue := style == &"nightclub"
	var tone := Color(0.996, 0.925, 0.808) if warm else Color(0.945, 0.965, 0.988)
	if venue:
		# Coloured rather than white, because a venue lit like a shop is a shop
		# with the lights off.
		tone = Color(0.663, 0.545, 0.878)
	var strip := Palette.glow(tone, 0.55)

	var holder := Node3D.new()
	holder.name = "Lighting"
	add_child(holder)

	# Tight against the tops of the side walls. Any wider or further in and,
	# from a camera directly overhead, a light fitting reads as a white stripe
	# painted down the middle of the shop floor.
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Strip%d" % int(side),
			Vector3(side * (room.size.x * 0.5 - 0.18), WALL_HEIGHT - 0.30, room.get_center().y),
			Vector3(0.12, 0.08, room.size.y * 0.86), strip, false, false
		)

	# Spread across whatever size the room actually is. These used to be four
	# fixed points chosen for a small unit, which left the corners of a large
	# one — a gym, a venue — in the dark.
	var centre := room.get_center()
	var span_x := room.size.x * 0.26
	var span_z := room.size.y * 0.26
	var spots: Array[Vector3] = [
		Vector3(centre.x - span_x, 2.9, centre.y - span_z),
		Vector3(centre.x + span_x, 2.9, centre.y - span_z),
		Vector3(centre.x - span_x, 2.9, centre.y + span_z),
		Vector3(centre.x + span_x, 2.9, centre.y + span_z),
	]
	if room.size.x > 20.0:
		spots.append(Vector3(centre.x, 2.9, centre.y))
	for spot in spots:
		var light := OmniLight3D.new()
		light.name = "CeilingLight"
		light.position = spot
		light.light_color = tone
		# A venue is dim, not invisible. Dark surfaces reflect little, so the
		# fittings need to throw *more* at them rather than less — the first
		# pass turned the energy down and rendered a black rectangle.
		light.light_energy = 1.35 if venue else (0.8 if warm else 0.95)
		light.omni_range = maxf(room.size.x, room.size.y) * 0.9
		light.shadow_enabled = false
		holder.add_child(light)


func _build_markers_and_doors() -> void:
	var entry := Marker3D.new()
	entry.name = "EntryPoint"
	entry.position = Vector3(0.0, 0.4, room.end.y - 1.8)
	entry.add_to_group(entry_group_for(property_id))
	add_child(entry)

	# Where customers arrive, and the threshold they walk through to get in. Two
	# points rather than one so they path through the doorway instead of into the
	# wall beside it.
	var arrival := Marker3D.new()
	arrival.name = "CustomerArrival"
	arrival.position = Vector3(0.0, 0.4, STREET_STUB_END - 2.5)
	add_child(arrival)

	var threshold := Marker3D.new()
	threshold.name = "Threshold"
	threshold.position = Vector3(0.0, 0.4, room.end.y - 0.6)
	add_child(threshold)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave"
	exit_door.destination_group = exit_group_for(property_id)
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, room.end.y - 0.4), 1.5)


func _build_signage() -> void:
	var board := Node3D.new()
	board.name = "Sign"
	board.position = Vector3(0.0, 2.4, room.end.y + WALL_THICKNESS + 0.05)
	add_child(board)
	CityKit.add_box(
		board, "Board", Vector3.ZERO, Vector3(5.0, 0.9, 0.16), _mat("sign"), false, false
	)

	_open_material = CityKit.make_emissive_material(
		Color(0.25, 0.30, 0.35), 0.0, Color(0.35, 0.95, 0.45)
	)
	var plate := MeshInstance3D.new()
	plate.name = "OpenLight"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.5, 0.42, 0.1)
	plate.mesh = mesh
	plate.material_override = _open_material
	plate.position = Vector3(1.6, 0.0, 0.14)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	board.add_child(plate)
	_open_light = plate
	_sign_label = board


func _refresh_signage() -> void:
	if not _built or _open_material == null:
		return
	var open := _business != null and _business.is_open()
	_open_material.emission = Color(0.35, 0.95, 0.45) if open else Color(0.85, 0.28, 0.24)
	_open_material.emission_energy_multiplier = 2.4 if open else 0.9


func _build_presence_volume() -> void:
	var volume := Area3D.new()
	volume.name = "Presence"
	volume.collision_layer = 0
	# The player layer (2) only.
	volume.collision_mask = 1 << 1
	volume.monitoring = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(room.size.x + 1.0, 4.0, room.size.y + 1.0)
	var collider := CollisionShape3D.new()
	collider.name = "Volume"
	collider.shape = shape
	volume.position = Vector3(
		room.position.x + room.size.x * 0.5, 2.0, room.position.y + room.size.y * 0.5
	)
	add_child(volume)
	volume.add_child(collider)
	volume.body_entered.connect(_on_body_entered)
	volume.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body != GameManager.player:
		return
	ensure_built()
	_player_inside = true
	if _business != null:
		BusinessManager.set_player_present(_business.business_id, true)
	player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body != GameManager.player:
		return
	_player_inside = false
	if _business != null:
		BusinessManager.set_player_present(_business.business_id, false)
	player_exited.emit()
