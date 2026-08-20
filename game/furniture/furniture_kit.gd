class_name FurnitureKit
extends RefCounted
## Draws a piece of furniture from its catalogue entry.
##
## The same arrangement the city uses: no models on disk, primitives assembled
## from numbers. PropKit already draws a sofa, a lamp, a dresser, a rug, a plant
## and a picture for the flats that come pre-dressed, so those are reused rather
## than drawn twice — what is added here is the shapes only bought furniture
## needs, and the tinting that makes a leather suite look unlike a cloth one.

## Builds one piece under `parent`, at the record's own position and rotation.
static func build(parent: Node3D, record: OwnedFurniture) -> Node3D:
	var definition := record.data()
	if definition == null:
		return null
	var holder := Node3D.new()
	holder.name = "Furniture_%s" % record.instance_id
	holder.position = record.position
	holder.rotation.y = record.rotation_y
	parent.add_child(holder)
	_draw(holder, definition)
	holder.set_meta("furniture_instance", String(record.instance_id))
	return holder


## The same piece as an unlit ghost, for the placement preview.
static func build_preview(parent: Node3D, definition: FurnitureData) -> Node3D:
	var holder := Node3D.new()
	holder.name = "FurniturePreview"
	parent.add_child(holder)
	_draw(holder, definition)
	# A nose block so the player can see which way round it is before they set
	# it down. A sofa facing the wall is a sofa nobody can sit on.
	CityKit.add_box(
		holder, "Facing",
		Vector3(0.0, definition.height + 0.08, -definition.placement_size.y * 0.5),
		Vector3(definition.placement_size.x * 0.3, 0.06, 0.24),
		CityKit.make_material(Color(0.95, 0.95, 0.95)), false, false
	)
	return holder


static func _draw(holder: Node3D, definition: FurnitureData) -> void:
	var body := CityKit.make_material(definition.body_color)
	var accent := CityKit.make_material(definition.accent_color)
	var size := definition.placement_size

	match definition.shape:
		FurnitureData.Shape.SOFA:
			_sofa(holder, definition, body, accent)
		FurnitureData.Shape.TABLE:
			_table(holder, definition, body, accent)
		FurnitureData.Shape.CHAIR:
			_chair(holder, definition, body, accent)
		FurnitureData.Shape.SCREEN:
			_screen(holder, definition, body, accent)
		FurnitureData.Shape.LAMP:
			_lamp(holder, definition, body)
		FurnitureData.Shape.CABINET:
			_cabinet(holder, definition, body, accent)
		FurnitureData.Shape.RUG:
			CityKit.add_box(
				holder, "Rug", Vector3(0.0, 0.006, 0.0),
				Vector3(size.x, 0.012, size.y), body, false, false
			)
		FurnitureData.Shape.PLANT:
			_plant(holder, definition, body, accent)
		FurnitureData.Shape.PANEL:
			_panel(holder, definition, body, accent)
		_:
			_bed(holder, definition, body, accent)


## A bed: base, mattress and a pillow at the head. The head is -Z, which is the
## direction the placement nose points, so a bed placed against a wall has its
## headboard against it.
static func _bed(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var height := definition.height
	CityKit.add_box(
		holder, "Base", Vector3(0.0, height * 0.4, 0.0),
		Vector3(size.x, height * 0.8, size.y), body, true
	)
	CityKit.add_box(
		holder, "Mattress", Vector3(0.0, height * 0.88, 0.0),
		Vector3(size.x - 0.10, height * 0.22, size.y - 0.10), accent, false
	)
	CityKit.add_box(
		holder, "Headboard", Vector3(0.0, height * 1.15, -size.y * 0.5 + 0.06),
		Vector3(size.x, height * 1.0, 0.10), body, false
	)
	CityKit.add_box(
		holder, "Pillow", Vector3(0.0, height * 1.04, -size.y * 0.5 + 0.34),
		Vector3(size.x * 0.7, 0.12, 0.36), accent, false, false
	)


static func _sofa(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var height := definition.height
	CityKit.add_box(
		holder, "Base", Vector3(0.0, height * 0.26, 0.0),
		Vector3(size.x, height * 0.52, size.y), body, true
	)
	CityKit.add_box(
		holder, "Back", Vector3(0.0, height * 0.70, size.y * 0.5 - 0.11),
		Vector3(size.x, height * 0.62, 0.22), body, false
	)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Arm%d" % int(side), Vector3(side * (size.x * 0.5 - 0.10), height * 0.58, 0.0),
			Vector3(0.20, height * 0.36, size.y), body, false
		)
	var seats := maxi(int(size.x / 0.9), 2)
	for i in seats:
		var offset := (float(i) - float(seats - 1) * 0.5) * (size.x / float(seats))
		CityKit.add_box(
			holder, "Cushion%d" % i, Vector3(offset, height * 0.58, -0.04),
			Vector3(size.x / float(seats) - 0.10, 0.14, size.y - 0.28), accent, false, false
		)


static func _table(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var height := definition.height
	CityKit.add_box(
		holder, "Top", Vector3(0.0, height - 0.03, 0.0),
		Vector3(size.x, 0.06, size.y), body, true
	)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			CityKit.add_box(
				holder, "Leg%d%d" % [int(x), int(z)],
				Vector3(x * (size.x * 0.5 - 0.08), (height - 0.06) * 0.5, z * (size.y * 0.5 - 0.08)),
				Vector3(0.07, height - 0.06, 0.07), accent, false
			)


static func _chair(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var seat := definition.height * 0.5
	CityKit.add_box(
		holder, "Seat", Vector3(0.0, seat, 0.0), Vector3(size.x, 0.09, size.y), body, true
	)
	CityKit.add_box(
		holder, "Back", Vector3(0.0, seat + definition.height * 0.26, size.y * 0.5 - 0.05),
		Vector3(size.x, definition.height * 0.5, 0.08), body, false
	)
	for x: float in [-1.0, 1.0]:
		for z: float in [-1.0, 1.0]:
			CityKit.add_box(
				holder, "Leg%d%d" % [int(x), int(z)],
				Vector3(x * (size.x * 0.5 - 0.05), seat * 0.5, z * (size.y * 0.5 - 0.05)),
				Vector3(0.05, seat, 0.05), accent, false
			)


## A television on a low stand. The screen is emissive, so a furnished room at
## night has something in it that is on.
static func _screen(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var height := definition.height
	CityKit.add_box(
		holder, "Stand", Vector3(0.0, height * 0.18, 0.0),
		Vector3(size.x * 0.8, height * 0.36, size.y), body, true
	)
	CityKit.add_box(
		holder, "Bezel", Vector3(0.0, height * 0.74, 0.0),
		Vector3(size.x, height * 0.48, 0.07), body, false
	)
	CityKit.add_box(
		holder, "Screen", Vector3(0.0, height * 0.74, -0.045),
		Vector3(size.x - 0.08, height * 0.40, 0.02),
		CityKit.make_emissive_material(definition.accent_color, 0.55), false, false
	)
	CityKit.add_box(
		holder, "StandTop", Vector3(0.0, height * 0.37, 0.0),
		Vector3(size.x * 0.84, 0.03, size.y + 0.04), accent, false, false
	)


static func _lamp(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D) -> void:
	var height := definition.height
	CityKit.add_cylinder(
		holder, "Base", Vector3(0.0, 0.02, 0.0), definition.placement_size.x * 0.4, 0.04, body, false
	)
	CityKit.add_cylinder(
		holder, "Stem", Vector3(0.0, height * 0.5, 0.0), 0.035, height, body, false
	)
	CityKit.add_cylinder(
		holder, "Shade", Vector3(0.0, height + 0.10, 0.0), 0.21, 0.26,
		CityKit.make_emissive_material(definition.accent_color, 0.9), false
	)


static func _cabinet(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	var height := definition.height
	CityKit.add_box(
		holder, "Carcass", Vector3(0.0, height * 0.5, 0.0),
		Vector3(size.x, height, size.y), body, true
	)
	var drawers := clampi(int(height / 0.35), 2, 5)
	for i in drawers:
		var y := height * (float(i) + 0.5) / float(drawers)
		CityKit.add_box(
			holder, "Front%d" % i, Vector3(0.0, y, -size.y * 0.5 - 0.01),
			Vector3(size.x - 0.08, height / float(drawers) - 0.06, 0.02), accent, false, false
		)


static func _plant(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var height := definition.height
	var radius := definition.placement_size.x * 0.45
	CityKit.add_cylinder(
		holder, "Pot", Vector3(0.0, height * 0.2, 0.0), radius, height * 0.4, accent, false
	)
	CityKit.add_sphere(
		holder, "Leaves", Vector3(0.0, height * 0.72, 0.0),
		Vector3(radius * 2.6, height * 0.72, radius * 2.6), body
	)


## A framed picture. Hung rather than stood: the record's height is where the
## middle of the frame sits on the wall.
static func _panel(holder: Node3D, definition: FurnitureData, body: StandardMaterial3D,
		accent: StandardMaterial3D) -> void:
	var size := definition.placement_size
	CityKit.add_box(
		holder, "Frame", Vector3(0.0, definition.height, 0.0),
		Vector3(size.x + 0.06, size.x * 0.8 + 0.06, size.y), body, false, false
	)
	CityKit.add_box(
		holder, "Print", Vector3(0.0, definition.height, -size.y * 0.5 - 0.005),
		Vector3(size.x, size.x * 0.8, 0.01), accent, false, false
	)
