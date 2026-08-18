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

const ROOM := Rect2(-7.0, -6.0, 14.0, 12.0)
const WALL_HEIGHT := 3.2
const WALL_THICKNESS := 0.3
const DOORWAY_HALF_WIDTH := 1.4
## The partition between the shop floor and the store room.
const PARTITION_Z := -2.4
## Gap in the partition, as x bounds.
const PARTITION_GAP := Vector2(1.9, 4.4)
## Where equipment may stand: the shop floor, then the store room.
const RETAIL_AREA := Rect2(-6.4, -1.9, 12.8, 7.4)
const STORAGE_AREA := Rect2(-6.4, -5.6, 12.8, 3.0)
## The pavement stub outside the door that customers walk in from.
const STREET_STUB_END := 15.0

@export var property_id: StringName = &"unit_a"
@export var unit_name: String = "Retail Unit"

var _palette: Dictionary = {}
var _equipment_root: Node3D = null
var _sign_label: Node3D = null
var _open_light: MeshInstance3D = null
var _open_material: StandardMaterial3D = null
var _business: BusinessInstance = null
var _nodes_by_slot: Dictionary = {}
var _player_inside: bool = false


static func entry_group_for(id: StringName) -> StringName:
	return StringName("retail_entry_%s" % id)


static func exit_group_for(id: StringName) -> StringName:
	return StringName("retail_exit_%s" % id)


func _ready() -> void:
	add_to_group(&"retail_unit")
	_build_palette()
	_build_shell()
	_build_lighting()
	_build_markers_and_doors()
	_build_signage()
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
	rebuild_equipment()
	_refresh_signage()


func _on_business_registered(_business: BusinessInstance) -> void:
	_bind_business()


func _on_business_changed(business: BusinessInstance) -> void:
	if _business == null:
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
	return get_node_or_null("Cashier") as EmployeeAI


func _on_minute_passed(_hour: int, _minute: int) -> void:
	if _player_inside:
		_refresh_staff()


## Staff only exist as people while somebody is here to see them. Out of sight
## the same employee is a line in the far simulation, which is why walking out
## of the shop does not stop them working.
func _refresh_staff() -> void:
	var cashier := get_cashier()
	if _business == null or not _player_inside:
		if cashier != null:
			cashier.queue_free()
		return

	var rostered := _business.rostered_cashier(TimeManager.hour)
	if rostered == null:
		if cashier != null:
			cashier.end_shift()
		return
	if cashier != null:
		if cashier.employee == rostered:
			return
		cashier.queue_free()
	if first_checkout() == null:
		return

	var arrival := get_node_or_null("CustomerArrival") as Marker3D
	var threshold := get_node_or_null("Threshold") as Marker3D
	if arrival == null or threshold == null:
		return

	var worker := EmployeeAI.new()
	worker.name = "Cashier"
	add_child(worker)
	worker.setup(rostered, self, threshold.global_position, arrival.global_position)
	GameManager.notify(
		"EMPLOYEE SHIFT STARTED
%s" % rostered.employee_name.to_upper(), GameManager.Tone.INFO
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
	var cashier := get_cashier()
	if cashier != null:
		cashier.queue_free()


# --- Placement -----------------------------------------------------------

## Whether a footprint of `size` centred on `local_point` is somewhere equipment
## may legally stand. Doorways and the partition gap are excluded, so a shelf can
## never be used to seal the shop.
func is_valid_placement(local_point: Vector3, size: Vector2) -> bool:
	var half := size * 0.5
	var footprint := Rect2(
		local_point.x - half.x, local_point.z - half.y, size.x, size.y
	)
	if not (_contains(RETAIL_AREA, footprint) or _contains(STORAGE_AREA, footprint)):
		return false
	# The way in, and the way through to the back.
	var front_door := Rect2(-DOORWAY_HALF_WIDTH - 0.4, ROOM.end.y - 1.6, DOORWAY_HALF_WIDTH * 2.0 + 0.8, 2.2)
	if footprint.intersects(front_door):
		return false
	var partition_gap := Rect2(
		PARTITION_GAP.x - 0.4, PARTITION_Z - 1.0, PARTITION_GAP.y - PARTITION_GAP.x + 0.8, 2.0
	)
	return not footprint.intersects(partition_gap)


## Whether a person could stand at this spot: on the shop floor or in the store
## room, and not inside a wall. Used to pick which side of a counter or a shelf
## somebody can actually walk up to.
func is_inside_floor(local_point: Vector3) -> bool:
	var point := Vector2(local_point.x, local_point.z)
	return RETAIL_AREA.has_point(point) or STORAGE_AREA.has_point(point)


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

	CityKit.add_slab(shell, "Floor", footprint, -0.4, 0.4, _mat("floor"))
	# The store room reads as a different room from above without a doorway shot.
	CityKit.add_slab(
		shell, "BackFloor",
		CityKit.rect_from_bounds(ROOM.position.x, ROOM.position.y, ROOM.end.x, PARTITION_Z),
		0.0, 0.01, _mat("back_floor"), false, false
	)
	# A stub of pavement outside the door: customers arrive on it and walk in,
	# rather than appearing inside the shop.
	# Two centimetres proud of the apron it sits on: coplanar slabs z-fight, and
	# from this camera that reads as a shimmering rectangle outside the door.
	CityKit.add_slab(
		shell, "Pavement",
		CityKit.rect_from_bounds(-5.0, ROOM.end.y + WALL_THICKNESS, 5.0, STREET_STUB_END),
		-0.4, 0.42, _mat("pavement"), true, false
	)

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
		CityKit.rect_from_bounds(west, PARTITION_Z, PARTITION_GAP.x, PARTITION_Z + WALL_THICKNESS)
	)
	_add_wall(
		shell, "PartitionEast",
		CityKit.rect_from_bounds(PARTITION_GAP.y, PARTITION_Z, east, PARTITION_Z + WALL_THICKNESS)
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
	entry.position = Vector3(0.0, 0.4, ROOM.end.y - 1.8)
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
	threshold.position = Vector3(0.0, 0.4, ROOM.end.y - 0.6)
	add_child(threshold)

	var exit_door := Portal.new()
	exit_door.name = "FrontDoor"
	exit_door.prompt_action = "Leave"
	exit_door.destination_group = exit_group_for(property_id)
	exit_door.override_camera = false
	CityKit.attach_interactable(self, exit_door, Vector3(0.0, 1.0, ROOM.end.y - 0.4), 1.5)


func _build_signage() -> void:
	var board := Node3D.new()
	board.name = "Sign"
	board.position = Vector3(0.0, 2.4, ROOM.end.y + WALL_THICKNESS + 0.05)
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
	if _open_material == null:
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
	shape.size = Vector3(ROOM.size.x + 1.0, 4.0, ROOM.size.y + 1.0)
	var collider := CollisionShape3D.new()
	collider.name = "Volume"
	collider.shape = shape
	volume.position = Vector3(
		ROOM.position.x + ROOM.size.x * 0.5, 2.0, ROOM.position.y + ROOM.size.y * 0.5
	)
	add_child(volume)
	volume.add_child(collider)
	volume.body_entered.connect(_on_body_entered)
	volume.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body != GameManager.player:
		return
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
