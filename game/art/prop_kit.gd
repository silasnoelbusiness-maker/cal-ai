class_name PropKit
extends RefCounted
## The reusable things that fill a city: street furniture outside, fittings
## inside.
##
## Every one takes a parent, a name and a spot, and returns the node it made.
## They are deliberately small — a bench is six boxes — because what makes a
## street feel inhabited is *how many* things are on it, not how good any one of
## them is, and anything expensive per instance would cap the count.
##
## Collision is chosen per prop, not per phase. Anything a person could
## reasonably walk into is solid; anything on a pavement route (planting, signs,
## litter) is not, because a prop in a walking lane is a jam rather than detail.

# --- Street ---------------------------------------------------------------

## A bench: slatted seat, back, two cast ends.
static func bench(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)

	var timber := Palette.of(&"wood_pale")
	var iron := Palette.of(&"metal_dark")
	for i in 3:
		CityKit.add_box(
			holder, "Slat%d" % i, Vector3(0.0, 0.45, -0.20 + float(i) * 0.20),
			Vector3(1.75, 0.06, 0.16), timber, false, false
		)
	for i in 3:
		CityKit.add_box(
			holder, "Back%d" % i, Vector3(0.0, 0.62 + float(i) * 0.16, 0.28),
			Vector3(1.75, 0.11, 0.06), timber, false, false
		)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "End%d" % int(side), Vector3(side * 0.82, 0.24, 0.02),
			Vector3(0.09, 0.48, 0.62), iron, false, false
		)
	return holder


## A litter bin, on its own post.
static func bin(parent: Node3D, node_name: String, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Body", Vector3(0.0, 0.46, 0.0), 0.26, 0.76, Palette.of(&"metal_dark"), false
	)
	CityKit.add_cylinder(
		holder, "Lid", Vector3(0.0, 0.88, 0.0), 0.29, 0.08, Palette.of(&"metal_mid"), false
	)
	return holder


## A planter: a stone tub with soil and a shrub in it.
static func planter(
	parent: Node3D, node_name: String, spot: Vector3, size: float = 1.2
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	CityKit.add_box(
		holder, "Tub", Vector3(0.0, 0.28, 0.0), Vector3(size, 0.56, size),
		Palette.of(&"stone_trim"), false
	)
	CityKit.add_box(
		holder, "Soil", Vector3(0.0, 0.56, 0.0), Vector3(size * 0.84, 0.06, size * 0.84),
		Palette.of(&"soil"), false, false
	)
	CityKit.add_sphere(
		holder, "Shrub", Vector3(0.0, 0.80, 0.0),
		Vector3(size * 0.86, 0.62, size * 0.86), Palette.of(&"foliage_mid")
	)
	return holder


## A bollard. Solid, because keeping cars out is what it is for.
static func bollard(parent: Node3D, node_name: String, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Post", Vector3(0.0, 0.42, 0.0), 0.11, 0.84, Palette.of(&"metal_dark"), true
	)
	CityKit.add_cylinder(
		holder, "Band", Vector3(0.0, 0.72, 0.0), 0.125, 0.07,
		Palette.tinted(&"metal_pale", Palette.WARNING), false
	)
	return holder


## A fire hydrant.
static func hydrant(parent: Node3D, node_name: String, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	var red := Palette.tinted(&"metal_mid", Color(0.671, 0.180, 0.161))
	CityKit.add_cylinder(holder, "Body", Vector3(0.0, 0.32, 0.0), 0.15, 0.64, red, false)
	CityKit.add_sphere(holder, "Cap", Vector3(0.0, 0.68, 0.0), Vector3(0.28, 0.22, 0.28), red)
	for side: float in [-1.0, 1.0]:
		CityKit.add_cylinder(
			holder, "Outlet%d" % int(side), Vector3(side * 0.17, 0.44, 0.0), 0.07, 0.12,
			Palette.of(&"metal_mid"), false
		)
	return holder


## A street sign on a post. `label` is drawn on both faces.
static func street_sign(
	parent: Node3D, node_name: String, spot: Vector3, label: String, yaw: float = 0.0
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Post", Vector3(0.0, 1.15, 0.0), 0.045, 2.3, Palette.of(&"metal_dark"), false
	)
	CityKit.add_box(
		holder, "Plate", Vector3(0.0, 2.18, 0.0), Vector3(1.5, 0.32, 0.05),
		Palette.of(&"metal_pale"), false, false
	)
	for face: float in [0.0, 180.0]:
		var text := Label3D.new()
		text.name = "Text%d" % int(face)
		text.text = label
		text.font_size = 40
		text.pixel_size = 0.006
		text.modulate = Color(0.153, 0.176, 0.216)
		text.double_sided = false
		text.position = Vector3(0.0, 2.18, 0.0 if face == 0.0 else 0.0)
		text.rotation_degrees.y = face
		text.position.z = 0.04 if face == 0.0 else -0.04
		holder.add_child(text)
	return holder


## A parking meter.
static func parking_meter(parent: Node3D, node_name: String, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Post", Vector3(0.0, 0.55, 0.0), 0.04, 1.1, Palette.of(&"metal_dark"), false
	)
	CityKit.add_box(
		holder, "Head", Vector3(0.0, 1.22, 0.0), Vector3(0.20, 0.34, 0.14),
		Palette.of(&"metal_mid"), false, false
	)
	CityKit.add_box(
		holder, "Screen", Vector3(0.0, 1.26, -0.08), Vector3(0.13, 0.13, 0.02),
		Palette.glow(Palette.CALM, 0.6), false, false
	)
	return holder


## A bike rack: two hoops.
static func bike_rack(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var iron := Palette.of(&"metal_mid")
	for i in 2:
		var x := -0.5 + float(i) * 1.0
		CityKit.add_box(
			holder, "Hoop%dTop" % i, Vector3(x, 0.72, 0.0), Vector3(0.06, 0.06, 0.70), iron,
			false, false
		)
		for side: float in [-1.0, 1.0]:
			CityKit.add_box(
				holder, "Hoop%dLeg%d" % [i, int(side)], Vector3(x, 0.36, side * 0.32),
				Vector3(0.06, 0.72, 0.06), iron, false, false
			)
	return holder


## A bus-stop style shelter: roof, back panel, a bench inside.
static func shelter(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var iron := Palette.of(&"metal_dark")
	var glass := Palette.of(&"glass_shop")
	CityKit.add_box(
		holder, "Roof", Vector3(0.0, 2.42, 0.0), Vector3(3.8, 0.12, 1.5),
		Palette.of(&"metal_mid"), false
	)
	CityKit.add_box(
		holder, "Back", Vector3(0.0, 1.25, 0.68), Vector3(3.7, 2.3, 0.06), glass, false, false
	)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Post%d" % int(side), Vector3(side * 1.82, 1.2, -0.66),
			Vector3(0.09, 2.4, 0.09), iron, false
		)
	bench(holder, "Seat", Vector3(0.0, 0.0, 0.42), 180.0)
	return holder


# --- Retail interior ------------------------------------------------------

## A stack of stock boxes, for a store room.
static func crate_stack(
	parent: Node3D, node_name: String, spot: Vector3, rng: RandomNumberGenerator
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	var card := Palette.of(&"panel_sand")
	var tape := Palette.of(&"wood_pale")
	var height := 0.0
	for i in rng.randi_range(2, 4):
		var size := Vector3(rng.randf_range(0.42, 0.60), 0.32, rng.randf_range(0.38, 0.54))
		CityKit.add_box(
			holder, "Box%d" % i,
			Vector3(rng.randf_range(-0.06, 0.06), height + size.y * 0.5, rng.randf_range(-0.06, 0.06)),
			size, card, false, false
		)
		CityKit.add_box(
			holder, "Tape%d" % i, Vector3(0.0, height + size.y + 0.005, 0.0),
			Vector3(size.x * 0.18, 0.01, size.z), tape, false, false
		)
		height += size.y
	return holder


## Grouped goods on a shelf: coloured blocks standing for drinks, snacks and
## general lines. One box per row rather than per item, which is the only way a
## shop full of stock stays cheap.
static func goods_row(
	parent: Node3D,
	node_name: String,
	spot: Vector3,
	length: float,
	kind: StringName,
	rng: RandomNumberGenerator
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)

	var palette: Array[Color] = []
	var item_height := 0.20
	var item_width := 0.09
	match kind:
		&"drinks":
			palette = [Color(0.243, 0.510, 0.729), Color(0.322, 0.667, 0.518), Color(0.851, 0.851, 0.878)]
			item_height = 0.24
		&"snacks":
			palette = [Color(0.898, 0.663, 0.239), Color(0.788, 0.361, 0.271), Color(0.678, 0.541, 0.353)]
			item_height = 0.16
			item_width = 0.12
		&"chilled":
			palette = [Color(0.788, 0.831, 0.878), Color(0.639, 0.769, 0.788), Color(0.878, 0.855, 0.749)]
			item_height = 0.22
		_:
			palette = [Color(0.612, 0.616, 0.639), Color(0.545, 0.498, 0.435), Color(0.463, 0.522, 0.573)]

	var count := maxi(int(length / (item_width + 0.03)), 1)
	for i in count:
		var colour: Color = palette[rng.randi_range(0, palette.size() - 1)]
		CityKit.add_box(
			holder, "Item%d" % i,
			Vector3(-length * 0.5 + (float(i) + 0.5) * (length / float(count)), item_height * 0.5, 0.0),
			Vector3(item_width, item_height, item_width * 1.6),
			Palette.tinted(&"cloth", colour), false, false
		)
	return holder


## A glass-fronted chiller cabinet.
## `solid` is off by default on purpose. Indoors, a cabinet the customer AI has
## to path around is a shop that stops selling — and from a camera directly
## above, a shopper clipping the corner of a fridge is invisible while a queue
## of stuck shoppers is not.
static func chiller(
	parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0, solid: bool = false
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)

	var shell := Palette.of(&"metal_pale")
	CityKit.add_box(holder, "Shell", Vector3(0.0, 0.95, 0.0), Vector3(1.6, 1.9, 0.72), shell, solid)
	CityKit.add_box(
		holder, "Glass", Vector3(0.0, 1.02, -0.37), Vector3(1.42, 1.52, 0.06),
		Palette.of(&"glass_shop"), false, false
	)
	# The cold light inside is what makes a chiller a chiller from across a shop.
	CityKit.add_box(
		holder, "Interior", Vector3(0.0, 1.02, -0.30), Vector3(1.36, 1.46, 0.04),
		Palette.glow(Color(0.792, 0.878, 0.949), 0.55), false, false
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_name)
	for i in 3:
		goods_row(
			holder, "Chilled%d" % i, Vector3(0.0, 0.42 + float(i) * 0.44, -0.16), 1.3,
			&"chilled", rng
		)
	return holder


## A menu board on a wall.
static func menu_board(
	parent: Node3D, node_name: String, spot: Vector3, lines: Array, yaw: float = 0.0
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	CityKit.add_box(
		holder, "Board", Vector3.ZERO, Vector3(1.7, 1.0, 0.06),
		Palette.tinted(&"wood_dark", Color(0.145, 0.161, 0.176)), false, false
	)
	var text := Label3D.new()
	text.name = "Text"
	text.text = "\n".join(lines)
	text.font_size = 34
	text.pixel_size = 0.0055
	text.modulate = Color(0.933, 0.914, 0.851)
	text.position = Vector3(0.0, 0.0, -0.05)
	text.rotation_degrees.y = 180.0
	holder.add_child(text)
	return holder


## A cafe table with two stools.
## Same rule as the chiller: solid outdoors where there is room to walk round
## it, decoration indoors where there is not.
static func cafe_table(
	parent: Node3D, node_name: String, spot: Vector3, solid: bool = false
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	var timber := Palette.of(&"wood_floor")
	var iron := Palette.of(&"metal_dark")
	CityKit.add_cylinder(holder, "Column", Vector3(0.0, 0.36, 0.0), 0.06, 0.72, iron, false)
	CityKit.add_cylinder(holder, "Foot", Vector3(0.0, 0.03, 0.0), 0.28, 0.06, iron, false)
	CityKit.add_cylinder(holder, "Top", Vector3(0.0, 0.74, 0.0), 0.44, 0.05, timber, solid)
	for side: float in [-1.0, 1.0]:
		var stool := Node3D.new()
		stool.name = "Stool%d" % int(side)
		stool.position = Vector3(side * 0.78, 0.0, 0.0)
		holder.add_child(stool)
		CityKit.add_cylinder(stool, "Seat", Vector3(0.0, 0.46, 0.0), 0.20, 0.06, timber, solid)
		CityKit.add_cylinder(stool, "Leg", Vector3(0.0, 0.23, 0.0), 0.05, 0.46, iron, false)
	return holder


## An espresso machine.
static func coffee_machine(parent: Node3D, node_name: String, spot: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	var steel := Palette.of(&"metal_pale")
	var dark := Palette.of(&"metal_dark")
	CityKit.add_box(holder, "Body", Vector3(0.0, 0.28, 0.0), Vector3(0.86, 0.56, 0.52), steel, false)
	CityKit.add_box(holder, "Head", Vector3(0.0, 0.60, -0.02), Vector3(0.86, 0.10, 0.48), dark, false)
	for side: float in [-1.0, 1.0]:
		CityKit.add_cylinder(
			holder, "Group%d" % int(side), Vector3(side * 0.24, 0.44, -0.24), 0.05, 0.16, dark, false
		)
	CityKit.add_box(
		holder, "Cups", Vector3(0.0, 0.68, 0.10), Vector3(0.60, 0.06, 0.30),
		Palette.of(&"wall_paint"), false, false
	)
	return holder


# --- Residential ----------------------------------------------------------

## A sofa.
static func sofa(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var fabric := Palette.tinted(&"cloth", Color(0.404, 0.427, 0.475))
	var cushion := Palette.tinted(&"cloth", Color(0.475, 0.494, 0.541))
	CityKit.add_box(holder, "Base", Vector3(0.0, 0.20, 0.0), Vector3(1.95, 0.40, 0.85), fabric, true)
	CityKit.add_box(holder, "Back", Vector3(0.0, 0.55, 0.34), Vector3(1.95, 0.55, 0.20), fabric, false)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Arm%d" % int(side), Vector3(side * 0.92, 0.44, 0.0),
			Vector3(0.18, 0.30, 0.85), fabric, false
		)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "Cushion%d" % int(side), Vector3(side * 0.44, 0.44, -0.04),
			Vector3(0.82, 0.14, 0.70), cushion, false, false
		)
	return holder


## A floor or table lamp: a stand, a shade, and a warm glow inside it.
static func lamp(
	parent: Node3D, node_name: String, spot: Vector3, tall: bool = true
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	var height := 1.45 if tall else 0.42
	CityKit.add_cylinder(
		holder, "Stem", Vector3(0.0, height * 0.5, 0.0), 0.035, height,
		Palette.of(&"metal_dark"), false
	)
	CityKit.add_cylinder(
		holder, "Base", Vector3(0.0, 0.02, 0.0), 0.16, 0.04, Palette.of(&"metal_dark"), false
	)
	CityKit.add_cylinder(
		holder, "Shade", Vector3(0.0, height + 0.10, 0.0), 0.20, 0.24,
		Palette.glow(Color(0.996, 0.914, 0.769), 0.85), false
	)
	return holder


## A kitchen run: counter, worktop, upper cabinets, sink and a hob.
static func kitchen_run(
	parent: Node3D, node_name: String, spot: Vector3, length: float, yaw: float = 0.0
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)

	var carcass := Palette.tinted(&"wall_paint", Color(0.784, 0.792, 0.808))
	var worktop := Palette.of(&"counter_top")
	CityKit.add_box(holder, "Carcass", Vector3(0.0, 0.44, 0.0), Vector3(length, 0.88, 0.62), carcass, true)
	CityKit.add_box(holder, "Worktop", Vector3(0.0, 0.90, 0.0), Vector3(length + 0.04, 0.05, 0.66), worktop, false)
	CityKit.add_box(
		holder, "Uppers", Vector3(0.0, 1.72, 0.18), Vector3(length * 0.82, 0.62, 0.34),
		carcass, false
	)
	CityKit.add_box(
		holder, "Sink", Vector3(-length * 0.26, 0.925, 0.0), Vector3(0.52, 0.04, 0.42),
		Palette.of(&"metal_pale"), false, false
	)
	CityKit.add_box(
		holder, "Hob", Vector3(length * 0.26, 0.93, 0.0), Vector3(0.52, 0.02, 0.44),
		Palette.of(&"metal_dark"), false, false
	)
	# Handles, which is most of what tells you it is a kitchen from above.
	for i in 4:
		CityKit.add_box(
			holder, "Handle%d" % i,
			Vector3(-length * 0.36 + float(i) * length * 0.24, 0.80, -0.32),
			Vector3(length * 0.14, 0.03, 0.03), Palette.of(&"metal_mid"), false, false
		)
	return holder


## A fridge.
static func fridge(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var shell := Palette.of(&"metal_pale")
	CityKit.add_box(holder, "Shell", Vector3(0.0, 0.85, 0.0), Vector3(0.66, 1.70, 0.64), shell, true)
	CityKit.add_box(
		holder, "Split", Vector3(0.0, 1.12, -0.33), Vector3(0.64, 0.02, 0.02),
		Palette.of(&"metal_dark"), false, false
	)
	CityKit.add_box(
		holder, "Handle", Vector3(0.24, 1.30, -0.35), Vector3(0.03, 0.36, 0.03),
		Palette.of(&"metal_mid"), false, false
	)
	return holder


## A chest of drawers / dresser.
static func dresser(parent: Node3D, node_name: String, spot: Vector3, yaw: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	var timber := Palette.of(&"wood_dark")
	CityKit.add_box(holder, "Carcass", Vector3(0.0, 0.44, 0.0), Vector3(1.05, 0.88, 0.48), timber, true)
	for i in 3:
		CityKit.add_box(
			holder, "Drawer%d" % i, Vector3(0.0, 0.18 + float(i) * 0.27, -0.25),
			Vector3(0.94, 0.22, 0.02), Palette.of(&"wood_pale"), false, false
		)
		CityKit.add_box(
			holder, "Pull%d" % i, Vector3(0.0, 0.18 + float(i) * 0.27, -0.28),
			Vector3(0.22, 0.03, 0.03), Palette.of(&"metal_mid"), false, false
		)
	return holder


## A rug. Flat, and it does more for a room reading as lived-in than any object.
static func rug(
	parent: Node3D, node_name: String, spot: Vector3, size: Vector2, colour: Color
) -> Node3D:
	return CityKit.add_box(
		parent, node_name, spot + Vector3(0.0, 0.006, 0.0),
		Vector3(size.x, 0.012, size.y), Palette.tinted(&"carpet_warm", colour), false, false
	)


## A potted plant.
static func pot_plant(parent: Node3D, node_name: String, spot: Vector3, scale: float = 1.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Pot", Vector3(0.0, 0.16 * scale, 0.0), 0.17 * scale, 0.32 * scale,
		Palette.tinted(&"stone_trim", Color(0.588, 0.400, 0.310)), false
	)
	CityKit.add_sphere(
		holder, "Leaves", Vector3(0.0, 0.56 * scale, 0.0),
		Vector3(0.56 * scale, 0.72 * scale, 0.56 * scale), Palette.of(&"foliage_mid")
	)
	return holder


## A framed picture for a wall.
static func wall_art(
	parent: Node3D, node_name: String, spot: Vector3, size: Vector2, colour: Color, yaw: float = 0.0
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot
	holder.rotation_degrees.y = yaw
	parent.add_child(holder)
	CityKit.add_box(
		holder, "Frame", Vector3.ZERO, Vector3(size.x + 0.06, size.y + 0.06, 0.04),
		Palette.of(&"wood_dark"), false, false
	)
	CityKit.add_box(
		holder, "Print", Vector3(0.0, 0.0, -0.03), Vector3(size.x, size.y, 0.01),
		Palette.tinted(&"wall_paint", colour), false, false
	)
	return holder


## A ceiling light: a flat panel with a glow. Deliberately not a real light —
## a room full of OmniLights is the fastest way to lose a frame budget. The
## emissive panel plus the interior's own fill is what sells it.
static func ceiling_light(
	parent: Node3D, node_name: String, spot: Vector3, size: Vector2, warm: bool = false
) -> Node3D:
	var colour := Color(0.996, 0.933, 0.827) if warm else Color(0.925, 0.949, 0.976)
	var holder := CityKit.add_box(
		parent, node_name, spot, Vector3(size.x, 0.06, size.y),
		Palette.glow(colour, 1.15), false, false
	)
	CityKit.add_box(
		parent, "%sHousing" % node_name, spot + Vector3(0.0, 0.05, 0.0),
		Vector3(size.x + 0.10, 0.06, size.y + 0.10), Palette.of(&"metal_pale"), false, false
	)
	return holder
