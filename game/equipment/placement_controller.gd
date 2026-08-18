class_name PlacementController
extends Node3D
## Putting bought equipment down on a shop floor.
##
## A mode rather than a screen: the world keeps running, the player moves the
## preview with the mouse, turns it with R and sets it down with the left button.
## Everything about whether a spot is legal is asked of the unit itself, so a
## different room shape needs no changes here.

signal placed(slot_id: int)
signal cancelled()

## Degrees per press of R.
@export var rotation_step: float = 90.0
## Clearance kept between two pieces of equipment, in metres.
@export var separation: float = 0.15

var _business: BusinessInstance = null
var _unit: RetailUnit = null
var _definition: EquipmentData = null
var _preview: Node3D = null
var _rotation: float = 0.0
var _point: Vector3 = Vector3.ZERO
var _valid: bool = false
## Set when moving an existing piece rather than placing a bought one, so
## cancelling puts it back rather than losing it.
var _moving_slot: int = -1
## Stock carried on a piece that is being moved, so it goes back on afterwards.
var _carried_item: StringName = &""
var _carried_quantity: int = 0
var _valid_material: StandardMaterial3D = null
var _invalid_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"placement_controller")
	set_process(false)
	set_process_unhandled_input(false)
	_valid_material = _ghost_material(Color(0.35, 0.85, 0.45))
	_invalid_material = _ghost_material(Color(0.9, 0.3, 0.28))


func is_active() -> bool:
	return _definition != null


## Starts placing a piece the business has bought but not put down.
func begin(business: BusinessInstance, unit: RetailUnit, equipment_id: StringName) -> bool:
	if business == null or unit == null:
		return false
	var definition := EquipmentCatalogue.by_id(equipment_id)
	if definition == null:
		return false
	if not BusinessManager.has_unplaced(business, equipment_id):
		GameManager.notify("NOTHING TO PLACE", GameManager.Tone.BAD)
		return false

	_business = business
	_unit = unit
	_definition = definition
	_moving_slot = -1
	_rotation = 0.0
	_build_preview()
	GameManager.placement_active = true
	set_process(true)
	set_process_unhandled_input(true)
	GameManager.notify(
		"PLACING %s\nLEFT CLICK place · R rotate · ESC cancel" % definition.display_name.to_upper(),
		GameManager.Tone.INFO
	)
	return true


## Picks an existing piece back up to move it. It comes off the floor
## immediately, so the space it was in is free to put it back into.
func begin_move(business: BusinessInstance, unit: RetailUnit, slot_id: int) -> bool:
	var record := business.equipment_by_slot(slot_id) if business != null else null
	if record == null:
		return false
	var equipment_id := record.equipment_id
	var kept_item := record.stock_item
	var kept_quantity := record.stock_quantity
	# Taken off the floor without returning its stock to the store room: it is
	# going straight back down, and a move must not quietly restock the shop.
	record.stock_quantity = 0
	business.remove_equipment(slot_id)
	BusinessManager.return_unplaced(business, equipment_id)

	if not begin(business, unit, equipment_id):
		return false
	_moving_slot = slot_id
	_carried_item = kept_item
	_carried_quantity = kept_quantity
	return true


func cancel() -> void:
	if not is_active():
		return
	# Anything picked up to be moved goes back into the delivery pile, where the
	# player can place it again. Nothing is ever destroyed by cancelling.
	if _carried_quantity > 0 and _carried_item != &"":
		_business.add_storage(_carried_item, _carried_quantity)
	_carried_item = &""
	_carried_quantity = 0
	_end()
	cancelled.emit()


func _end() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_definition = null
	_moving_slot = -1
	GameManager.placement_active = false
	set_process(false)
	set_process_unhandled_input(false)


func _process(_delta: float) -> void:
	if not is_active():
		return
	var ground: Variant = _mouse_ground_point()
	if ground == null:
		return
	_point = _unit.snap_point(_unit.to_local(ground as Vector3))
	_valid = _is_legal(_point)

	_preview.position = _point
	_preview.rotation.y = deg_to_rad(_rotation)
	for child in _preview.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = (
				_valid_material if _valid else _invalid_material
			)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("rotate_placement"):
		_rotation = fmod(_rotation + rotation_step, 360.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		# Left button places. Combat is suppressed while a placement is running.
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel_placement") or event.is_action_pressed("pause"):
		cancel()
		get_viewport().set_input_as_handled()


func confirm() -> bool:
	if not is_active() or not _valid:
		GameManager.notify("CANNOT PLACE THAT THERE", GameManager.Tone.BAD)
		return false
	if not BusinessManager.consume_unplaced(_business, _definition.equipment_id):
		return false

	var record := _business.place_equipment(
		_definition.equipment_id, _point, deg_to_rad(_rotation)
	)
	# A piece being moved keeps whatever was on it.
	if _carried_quantity > 0:
		record.stock_item = _carried_item
		record.stock_quantity = _carried_quantity
		_carried_item = &""
		_carried_quantity = 0

	GameManager.notify("PLACED %s" % _definition.display_name.to_upper(), GameManager.Tone.GOOD)
	var slot := record.slot_id
	_end()
	placed.emit(slot)
	return true


## Places at an exact spot without the mouse. Used by the tests, and by any
## later "suggest a layout" helper.
func place_at(local_point: Vector3, rotation_degrees: float) -> bool:
	if not is_active():
		return false
	_rotation = rotation_degrees
	_point = _unit.snap_point(local_point)
	_valid = _is_legal(_point)
	return confirm()


# --- Rules ---------------------------------------------------------------

## Legal means inside the shop's floor areas, clear of the doorways, and not
## overlapping anything already down.
func _is_legal(local_point: Vector3) -> bool:
	var size := _rotated_size()
	if not _unit.is_valid_placement(local_point, size):
		return false
	return not _overlaps_existing(local_point, size)


func _rotated_size() -> Vector2:
	var size := _definition.placement_size
	var quarter_turned := int(round(_rotation / 90.0)) % 2 != 0
	return Vector2(size.y, size.x) if quarter_turned else size


func _overlaps_existing(local_point: Vector3, size: Vector2) -> bool:
	var footprint := Rect2(
		local_point.x - size.x * 0.5, local_point.z - size.y * 0.5, size.x, size.y
	).grow(separation)
	for record in _business.equipment:
		if record.slot_id == _moving_slot:
			continue
		var other := record.data()
		if other == null:
			continue
		var other_size := other.placement_size
		var quarter_turned := int(round(rad_to_deg(record.rotation_y) / 90.0)) % 2 != 0
		if quarter_turned:
			other_size = Vector2(other_size.y, other_size.x)
		var other_rect := Rect2(
			record.position.x - other_size.x * 0.5,
			record.position.z - other_size.y * 0.5,
			other_size.x, other_size.y
		)
		if footprint.intersects(other_rect):
			return true
	return false


# --- Preview -------------------------------------------------------------

func _build_preview() -> void:
	if _preview != null:
		_preview.queue_free()
	_preview = Node3D.new()
	_preview.name = "PlacementPreview"
	_unit.add_child(_preview)

	var mesh := MeshInstance3D.new()
	mesh.name = "Ghost"
	var box := BoxMesh.new()
	box.size = Vector3(
		_definition.placement_size.x, _definition.height, _definition.placement_size.y
	)
	mesh.mesh = box
	mesh.position = Vector3(0.0, _definition.height * 0.5, 0.0)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.add_child(mesh)

	# A nose block, so the player can see which way round it is before they
	# commit — a counter facing the wall is a shop nobody can pay in.
	var nose := MeshInstance3D.new()
	nose.name = "Facing"
	var marker := BoxMesh.new()
	marker.size = Vector3(_definition.placement_size.x * 0.35, 0.1, 0.35)
	nose.mesh = marker
	nose.position = Vector3(0.0, _definition.height + 0.1, -_definition.placement_size.y * 0.5)
	nose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.add_child(nose)


func _ghost_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.45)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Where the mouse is pointing on the shop floor, or null when it is off it.
func _mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _unit == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, _unit.global_position.y)
	var hit: Variant = plane.intersects_ray(from, direction)
	return hit
