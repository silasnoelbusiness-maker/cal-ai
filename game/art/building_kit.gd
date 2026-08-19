class_name BuildingKit
extends RefCounted
## Modular facade pieces, so a building is assembled rather than sculpted.
##
## Every district already lays out its blocks as rectangles with a height. What
## was missing was everything between the wall and the roof: punched windows
## instead of a lit stripe, shopfronts that read as shops, and enough on a roof
## that looking down on one is not looking at a grey lid. All of that is here,
## driven off the same rectangle, so a new district gets it for free and an
## existing one gets it by calling three functions inside the loop it already
## has.
##
## The camera looks down. That decides what is worth building: roofs and the
## top two metres of a facade get detail, the middle of a wall gets a pattern,
## and nothing gets a doorknob.

## One shared lit-window material per district, faded by the day/night cycle.
## Handed in rather than looked up so two districts can light differently.
const WINDOW_ROWS_FROM := 4.6
const FLOOR_HEIGHT := 3.4


## A grid of windows on all four faces between two heights.
##
## Windows are inset boxes proud of the wall by a few centimetres — enough to
## catch the sun and cast a line of shadow, which is what makes a facade read as
## having depth from an elevated camera. The glass is one shared material so a
## whole district's windows light up for the cost of one write at dusk.
static func add_window_grid(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	base_y: float,
	top_y: float,
	glass: StandardMaterial3D,
	frame: StandardMaterial3D,
	spacing: float = 3.2,
	window_width: float = 1.5,
	window_height: float = 1.7
) -> void:
	if top_y - base_y < window_height + 0.6:
		return
	var floors := int(floor((top_y - base_y) / FLOOR_HEIGHT))
	if floors <= 0:
		return

	# Every window on a building goes into two MultiMeshes — one for the glass,
	# one for the surrounds — rather than into two nodes each.
	#
	# This is the difference between a city that draws and one that does not. A
	# building of eight bays and four floors on four faces is 256 windows;
	# twenty-five buildings is six thousand mesh instances and six thousand draw
	# calls, for geometry that never moves and shares one material. As
	# MultiMeshes it is fifty draws. The glass is still one shared material, so
	# the whole district still lights up at dusk for one write.
	var panes: Array[Transform3D] = []
	var surrounds: Array[Transform3D] = []

	for along_x: bool in [true, false]:
		var run: float = rect.size.x if along_x else rect.size.y
		var count := int(run / spacing)
		if count < 1:
			continue
		var step := run / float(count)
		for face: float in [-1.0, 1.0]:
			var fixed: float = (
				(rect.position.y if face < 0.0 else rect.end.y) if along_x
				else (rect.position.x if face < 0.0 else rect.end.x)
			)
			for i in count:
				var travel: float = (
					(rect.position.x if along_x else rect.position.y) + step * (float(i) + 0.5)
				)
				for level in floors:
					var y := base_y + FLOOR_HEIGHT * float(level) + window_height * 0.5 + 0.5
					if y + window_height * 0.5 > top_y:
						break
					var centre := (
						Vector3(travel, y, fixed + face * 0.06) if along_x
						else Vector3(fixed + face * 0.06, y, travel)
					)
					var pane := (
						Vector3(window_width, window_height, 0.14) if along_x
						else Vector3(0.14, window_height, window_width)
					)
					var surround := (
						Vector3(window_width + 0.28, window_height + 0.28, 0.08) if along_x
						else Vector3(0.08, window_height + 0.28, window_width + 0.28)
					)
					panes.append(Transform3D(Basis().scaled(pane), centre))
					surrounds.append(
						Transform3D(
							Basis().scaled(surround),
							centre - Vector3(
								0.0 if along_x else face * 0.02, 0.0,
								face * 0.02 if along_x else 0.0
							)
						)
					)

	if panes.is_empty():
		return
	_add_instanced(parent, "%sWindows" % node_name, panes, glass)
	_add_instanced(parent, "%sSurrounds" % node_name, surrounds, frame)


## One MultiMeshInstance3D holding a pile of identically-shaped boxes.
static func _add_instanced(
	parent: Node3D, node_name: String, transforms: Array[Transform3D], material: StandardMaterial3D
) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = CityKit.unit_box()
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])

	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = multi
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


## A shop at street level on one face of a block: glazing, mullions, a stall
## riser, a sign band with the name on it, and an awning.
##
## `along_x` picks which pair of faces; `face` is -1 for the low side, +1 for the
## high. `from`/`to` are the span along the face. The whole thing is decoration —
## nothing here is solid, because the block behind it already is.
static func add_storefront(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	along_x: bool,
	face: float,
	from: float,
	to: float,
	shop_name: String,
	sign_colour: Color,
	glass: StandardMaterial3D,
	frame: StandardMaterial3D,
	awning: StandardMaterial3D
) -> void:
	var holder := Node3D.new()
	holder.name = "%sShopfront" % node_name
	parent.add_child(holder)

	var fixed: float = (
		(rect.position.y if face < 0.0 else rect.end.y) if along_x
		else (rect.position.x if face < 0.0 else rect.end.x)
	)
	var width := absf(to - from)
	var mid := (from + to) * 0.5
	var glass_top := 3.0
	var out := face * 0.10

	# Glazing, sat on a low stall riser.
	_face_box(holder, "Riser", along_x, fixed + out * 0.5, mid, 0.22, width, 0.44, 0.22, frame)
	_face_box(
		holder, "Glass", along_x, fixed + out, mid,
		0.44 + (glass_top - 0.44) * 0.5, width * 0.98, glass_top - 0.44, 0.10, glass
	)
	# Mullions every couple of metres, which is what stops a shopfront being one
	# dark rectangle.
	var bays := maxi(int(width / 2.1), 1)
	for i in range(1, bays):
		_face_box(
			holder, "Mullion%d" % i, along_x, fixed + out * 1.3,
			from + (to - from) * float(i) / float(bays),
			(0.44 + glass_top) * 0.5, 0.10, glass_top - 0.44, 0.14, frame
		)
	# The door: a darker panel with a frame, at one end of the run.
	var door_at := from + (to - from) * 0.22
	_face_box(
		holder, "Door", along_x, fixed + out * 1.4, door_at, 1.15, 1.1, 2.3, 0.12, frame
	)

	# Sign band above the glass, and the name on it.
	var band_y := glass_top + 0.62
	_face_box(
		holder, "SignBand", along_x, fixed + out * 1.2, mid, band_y, width, 0.92, 0.16,
		Palette.tinted(&"panel_navy", sign_colour)
	)
	if not shop_name.is_empty():
		var label := Label3D.new()
		label.name = "SignText"
		label.text = shop_name
		label.font_size = 64
		label.pixel_size = 0.011
		label.modulate = Color(0.965, 0.961, 0.937)
		label.outline_size = 0
		label.double_sided = false
		label.position = (
			Vector3(mid, band_y, fixed + out * 2.2) if along_x
			else Vector3(fixed + out * 2.2, band_y, mid)
		)
		if along_x:
			label.rotation_degrees.y = 0.0 if face > 0.0 else 180.0
		else:
			label.rotation_degrees.y = 90.0 if face > 0.0 else -90.0
		holder.add_child(label)

	# Awning: a sloped strip below the sign. Cheap depth on an otherwise flat
	# wall, and the thing that most makes a row of shops read as a high street.
	var awning_node := _face_box(
		holder, "Awning", along_x, fixed + face * 0.62, mid, glass_top + 0.10,
		width * 0.96, 0.10, 1.05, awning
	)
	awning_node.rotation.x = (-0.22 if face > 0.0 else 0.22) if along_x else 0.0
	if not along_x:
		awning_node.rotation.z = 0.22 if face > 0.0 else -0.22


## Places a box on a face, taking "along the face" and "out from the face"
## rather than world x/z, so a caller does not write the same swap five times.
static func _face_box(
	parent: Node3D,
	node_name: String,
	along_x: bool,
	fixed: float,
	travel: float,
	y: float,
	length: float,
	height: float,
	depth: float,
	material: StandardMaterial3D
) -> Node3D:
	var centre := Vector3(travel, y, fixed) if along_x else Vector3(fixed, y, travel)
	var size := (
		Vector3(length, height, depth) if along_x else Vector3(depth, height, length)
	)
	return CityKit.add_box(parent, node_name, centre, size, material, false, false)


## What a flat roof carries. Plant, ducts, a stair head, a tank and an aerial —
## the things that, seen from above, are the difference between a building and a
## grey lid.
static func add_roof_kit(
	parent: Node3D, node_name: String, rect: Rect2, roof_y: float, rng: RandomNumberGenerator
) -> void:
	var usable := rect.grow(-2.2)
	if usable.size.x < 4.0 or usable.size.y < 4.0:
		return
	var holder := Node3D.new()
	holder.name = "%sRoofKit" % node_name
	parent.add_child(holder)

	var metal := Palette.of(&"metal_mid")
	var dark := Palette.of(&"metal_dark")
	var pale := Palette.of(&"concrete")

	# Air handling units, each on a low plinth so it does not look painted on.
	var units := 2 + rng.randi_range(0, 2)
	for i in units:
		var size := Vector3(
			rng.randf_range(1.8, 3.2), rng.randf_range(0.9, 1.6), rng.randf_range(1.4, 2.4)
		)
		var spot := Vector3(
			rng.randf_range(usable.position.x, usable.end.x),
			roof_y,
			rng.randf_range(usable.position.y, usable.end.y)
		)
		CityKit.add_box(
			holder, "Plant%dBase" % i, spot + Vector3(0.0, 0.06, 0.0),
			Vector3(size.x + 0.4, 0.12, size.z + 0.4), dark, false, false
		)
		CityKit.add_box(
			holder, "Plant%d" % i, spot + Vector3(0.0, 0.12 + size.y * 0.5, 0.0),
			size, metal, false
		)
		# Fan grille on top, which is what makes it read as plant rather than a
		# crate somebody left up there.
		CityKit.add_cylinder(
			holder, "Fan%d" % i, spot + Vector3(0.0, 0.12 + size.y + 0.04, 0.0),
			minf(size.x, size.z) * 0.28, 0.08, dark, false
		)

	# A duct run between two of them.
	if units >= 2:
		var duct_y := roof_y + 0.55
		CityKit.add_box(
			holder, "Duct",
			Vector3(usable.get_center().x, duct_y, usable.position.y + usable.size.y * 0.35),
			Vector3(usable.size.x * 0.55, 0.42, 0.42), metal, false
		)

	# Water tank on legs.
	var tank := Vector3(
		usable.end.x - 1.6, roof_y + 1.9, usable.position.y + 1.6
	)
	CityKit.add_cylinder(holder, "Tank", tank, 0.95, 1.5, pale, false)
	for corner: Vector2 in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.6, 0.6)]:
		CityKit.add_box(
			holder, "TankLeg%d_%d" % [int(corner.x * 10), int(corner.y * 10)],
			Vector3(tank.x + corner.x, roof_y + 0.58, tank.z + corner.y),
			Vector3(0.12, 1.16, 0.12), dark, false, false
		)

	# Aerial mast.
	CityKit.add_box(
		holder, "Mast",
		Vector3(usable.position.x + 1.2, roof_y + 2.4, usable.end.y - 1.2),
		Vector3(0.10, 4.8, 0.10), dark, false, false
	)
