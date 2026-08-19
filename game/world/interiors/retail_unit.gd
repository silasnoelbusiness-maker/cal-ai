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
enum Size { SMALL, MEDIUM }

const WALL_HEIGHT := 3.2
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 1.4
## The pavement stub outside the door that customers walk in from.
const STREET_STUB_END := 15.0
## How far behind the front wall the store-room partition sits, per size.
const PARTITION_INSET := 3.6

@export var property_id: StringName = &"unit_a"
@export var unit_name: String = "Retail Unit"
@export var size_class: Size = Size.SMALL

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
	var size := Vector2(14.0, 12.0) if size_class == Size.SMALL else Vector2(18.0, 15.0)
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
	_build_shell()
	_build_lighting()
	_build_signage()
	rebuild_equipment()
	_refresh_signage()


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
	rebuild_equipment()
	_refresh_signage()


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


## Staff only exist as people while somebody is here to see them. Out of sight
## the same employee is a line in the far simulation, which is why walking out
## of the shop does not stop them working.
##
## One node per job rather than one per person: the shop needs somebody on the
## counter, somebody on the machine and somebody on the floor, and which of the
## payroll that is comes from the roster.
func _refresh_staff() -> void:
	var jobs := {
		"Cashier": EmployeeData.Role.CASHIER,
		"Barista": EmployeeData.Role.BARISTA,
		"Stocker": EmployeeData.Role.STOCKER,
		"Manager": EmployeeData.Role.MANAGER,
	}
	for node_name in jobs:
		_refresh_one(String(node_name), int(jobs[node_name]))


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
	if first_checkout() == null:
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
	for node_name in ["Cashier", "Barista", "Stocker", "Manager"]:
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


func _build_palette() -> void:
	_palette = {
		"surround": CityKit.make_material(Color(0.086, 0.094, 0.110)),
		"floor": CityKit.make_material(Color(0.604, 0.600, 0.588)),
		"back_floor": CityKit.make_material(Color(0.400, 0.404, 0.408)),
		"wall": CityKit.make_material(Color(0.816, 0.804, 0.769)),
		"trim": CityKit.make_material(Color(0.325, 0.318, 0.302)),
		"door": CityKit.make_material(Color(0.247, 0.192, 0.145)),
		"pavement": CityKit.make_material(Color(0.678, 0.675, 0.663)),
		"sign": CityKit.make_material(Color(0.161, 0.176, 0.208)),
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

	CityKit.add_slab(shell, "Floor", footprint, -0.4, 0.4, _mat("floor"))
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

	# Partition, with a gap through to the store room.
	_add_wall(
		shell, "PartitionWest",
		CityKit.rect_from_bounds(west, partition_z, partition_gap.x, partition_z + WALL_THICKNESS)
	)
	_add_wall(
		shell, "PartitionEast",
		CityKit.rect_from_bounds(partition_gap.y, partition_z, east, partition_z + WALL_THICKNESS)
	)


func _add_wall(parent: Node3D, wall_name: String, rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(parent, wall_name, rect, 0.0, WALL_HEIGHT, _mat("wall"))
	CityKit.add_slab(parent, wall_name + "Trim", rect.grow(0.04), 0.0, 0.35, _mat("trim"))


func _build_lighting() -> void:
	for spot in [
		Vector3(-3.5, 2.9, 1.5), Vector3(3.5, 2.9, 1.5),
		Vector3(0.0, 2.9, -4.2), Vector3(0.0, 2.9, 4.6),
	]:
		var light := OmniLight3D.new()
		light.name = "CeilingLight"
		light.position = spot
		light.light_color = Color(0.98, 0.98, 0.94)
		light.light_energy = 3.0
		light.omni_range = 13.0
		light.shadow_enabled = false
		add_child(light)


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
