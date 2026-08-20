class_name FurniturePlacement
extends Node3D
## Arranging a home.
##
## Deliberately the same mode, the same keys and the same feel as putting shop
## equipment down: the world keeps running, the mouse moves a ghost, R turns it,
## the left button sets it down and Escape gets out. A player who has fitted out
## a shop already knows how to furnish a flat.
##
## What differs is what counts as legal and what owns the result — a flat is not
## a shop, and business fittings do not belong in one. Those two rules are the
## whole difference, and they are enforced here rather than shared away.

signal placed(record: OwnedFurniture)
signal cancelled()

var _room: ApartmentInterior = null
var _record: OwnedFurniture = null
var _definition: FurnitureData = null
var _preview: Node3D = null
var _rotation: float = 0.0
var _point: Vector3 = Vector3.ZERO
var _valid: bool = false
## Set when the piece was picked up off the floor rather than taken from the
## delivery pile, so cancelling puts it back where it was.
var _moved_from: Transform3D = Transform3D.IDENTITY
var _was_placed: bool = false
var _valid_material: StandardMaterial3D = null
var _invalid_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group(&"furniture_placement")
	set_process(false)
	set_process_unhandled_input(false)
	_valid_material = _ghost_material(Color(0.35, 0.85, 0.45))
	_invalid_material = _ghost_material(Color(0.9, 0.3, 0.28))


func is_active() -> bool:
	return _record != null


## Starts placing something the player owns but has not put anywhere.
func begin(room: ApartmentInterior, record: OwnedFurniture) -> bool:
	if room == null or record == null or record.data() == null:
		return false
	if record.is_placed():
		return false
	_room = room
	_record = record
	_definition = record.data()
	_rotation = 0.0
	_was_placed = false
	_build_preview()
	GameManager.placement_active = true
	set_process(true)
	set_process_unhandled_input(true)
	GameManager.notify(
		"PLACING %s\nLEFT CLICK place · R rotate · ESC cancel" % _definition.display_name.to_upper(),
		GameManager.Tone.INFO
	)
	return true


## Picks a placed piece back up to move it. It comes off the floor at once, so
## the space it was in is free to put it back into.
func begin_move(room: ApartmentInterior, record: OwnedFurniture) -> bool:
	if room == null or record == null or not record.is_placed():
		return false
	_moved_from = Transform3D(Basis(Vector3.UP, record.rotation_y), record.position)
	HomeManager.store(record)
	if not begin(room, record):
		# Put it back rather than leaving it in limbo.
		HomeManager.place(record, room.residence_id, _moved_from.origin, _moved_from.basis.get_euler().y)
		return false
	_was_placed = true
	_rotation = rad_to_deg(_moved_from.basis.get_euler().y)
	return true


func cancel() -> void:
	if not is_active():
		return
	if _was_placed:
		# Nothing is ever lost by changing your mind: a piece picked up to be
		# moved goes back exactly where it came from.
		HomeManager.place(
			_record, _room.residence_id, _moved_from.origin, _moved_from.basis.get_euler().y
		)
	_end()
	cancelled.emit()


func _end() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null
	_record = null
	_definition = null
	_room = null
	_was_placed = false
	GameManager.placement_active = false
	set_process(false)
	set_process_unhandled_input(false)


func _process(_delta: float) -> void:
	if not is_active():
		return
	var ground: Variant = _mouse_ground_point()
	if ground == null:
		return
	_point = PlacementRules.snap(_room.to_local(ground as Vector3))
	_valid = is_legal(_point, _rotation)
	_preview.position = _point
	_preview.rotation.y = deg_to_rad(_rotation)
	_tint(_preview, _valid_material if _valid else _invalid_material)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	if event.is_action_pressed("rotate_placement"):
		_rotation = fmod(_rotation + PlacementRules.ROTATION_STEP, 360.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel_placement") or event.is_action_pressed("pause_menu"):
		cancel()
		get_viewport().set_input_as_handled()


func confirm() -> bool:
	if not is_active() or not _valid:
		GameManager.notify("CANNOT PLACE THAT THERE", GameManager.Tone.BAD)
		return false
	var record := _record
	var room := _room
	HomeManager.place(record, room.residence_id, _point, deg_to_rad(_rotation))
	HomeManager.refresh_storage_capacity(room.residence_id)
	AudioManager.play(&"interact", AudioBuses.SFX, -10.0)
	GameManager.notify("PLACED %s" % _definition.display_name.to_upper(), GameManager.Tone.GOOD)
	_end()
	placed.emit(record)
	return true


## Moves the preview to an exact spot without confirming it. What the mode looks
## like in the player's hands, and the only way a screenshot or a test can show
## that rather than the result of it.
func place_preview_at(local_point: Vector3, rotation_degrees: float) -> void:
	if not is_active():
		return
	_rotation = rotation_degrees
	_point = PlacementRules.snap(local_point)
	_valid = is_legal(_point, _rotation)
	_preview.position = _point
	_preview.rotation.y = deg_to_rad(_rotation)
	_tint(_preview, _valid_material if _valid else _invalid_material)


## Places at an exact spot without the mouse. Used by the tests, and by anything
## later that wants to suggest a layout.
func place_at(local_point: Vector3, rotation_degrees: float) -> bool:
	if not is_active():
		return false
	_rotation = rotation_degrees
	_point = PlacementRules.snap(local_point)
	_valid = is_legal(_point, _rotation)
	return confirm()


# --- Rules ---------------------------------------------------------------

## Legal means inside the room, clear of the doorway and the fitted furniture,
## and not overlapping anything already down.
func is_legal(local_point: Vector3, rotation_degrees: float) -> bool:
	if _room == null or _definition == null:
		return false
	var size := PlacementRules.rotated_size(_definition.placement_size, rotation_degrees)
	if not _room.is_valid_furniture_spot(local_point, size):
		return false
	var spaced := PlacementRules.spaced_footprint(local_point, size)
	return not HomeManager.overlaps_placed(_room.residence_id, spaced, _record)


# --- Preview -------------------------------------------------------------

func _build_preview() -> void:
	if _preview != null:
		_preview.queue_free()
	_preview = FurnitureKit.build_preview(_room, _definition)


func _tint(node: Node, material: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
		elif child is Node3D:
			_tint(child, material)


func _ghost_material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colour.r, colour.g, colour.b, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Where the mouse is pointing on the room's floor plane.
func _mouse_ground_point() -> Variant:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null
	var mouse := viewport.get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, _room.global_position.y)
	var hit: Variant = plane.intersects_ray(from, direction)
	return hit
