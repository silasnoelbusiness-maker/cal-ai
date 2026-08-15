class_name District01
extends Node3D
## Builds the "Harbour Row" prototype district out of primitives.
##
## The whole block is generated from the layout tables below rather than being
## hand-placed in the editor, which keeps the .tscn tiny and makes the street
## grid easy to retune. Districts are self-contained and origin-relative, so a
## second district can later be instanced at an offset and connected at the
## road stubs on the district edges.
##
## Coordinate conventions:
##   * +X is east, +Z is south, Y is up.
##   * Ground (lot / plaza surface) is solid with its top at y = 0.
##   * Roads are painted on top of the ground and are not separately solid.
##   * Sidewalks are solid slabs CURB_HEIGHT tall, so curbs are a real step.

const ROAD_HALF := 6.0        # half-width of a carriageway
const WALK_WIDTH := 3.0       # sidewalk depth
const EXTENT := 88.0          # district half-size (perimeter wall)
const GROUND_EXTENT := 95.0

# Road centre lines.
const MAIN_ST_Z := 0.0
const NORTH_AVE_Z := -50.0
const CENTER_BLVD_X := 0.0

# Surface heights. Kept apart so nothing z-fights.
const ROAD_BASE := 0.005
const ROAD_THICKNESS := 0.02
const MARKING_BASE := 0.026
const MARKING_THICKNESS := 0.012
const GRASS_BASE := 0.005
const GRASS_THICKNESS := 0.015
## Park paths sit clear above the lawn rather than overlapping it, so the two
## surfaces never fight for depth.
const PARK_PATH_BASE := 0.022
const CURB_HEIGHT := CityKit.CURB_HEIGHT

# Emission colours for the two light sources that change with the clock.
const WINDOW_GLOW := Color(0.976, 0.831, 0.545)
const LAMP_GLOW := Color(1.0, 0.878, 0.678)
## Emission energy of the lit window bands at full night.
const WINDOW_NIGHT_ENERGY := 0.8

var _palette: Dictionary = {}
var _geometry: Node3D
var _props: Node3D
var _interactables: Node3D
var _sidewalk_index: int = 0


func _ready() -> void:
	_build_palette()
	_geometry = _make_container("Geometry")
	_props = _make_container("Props")
	_interactables = _make_container("Interactables")

	_build_ground()
	_build_roads()
	_build_road_markings()
	_build_sidewalks()
	_build_perimeter()
	_build_buildings()
	_build_park()
	_build_parking()
	_build_street_lights()
	_build_venue_doors()
	_build_notice_board()

	var sun := get_node_or_null("Sun") as DayNightCycle
	if sun != null:
		sun.daylight_changed.connect(_on_daylight_changed)


## Fades the shared lit-window material with the time of day. One material is
## shared by every window band, so this is a single assignment per change.
func _on_daylight_changed(amount: float) -> void:
	var material: StandardMaterial3D = _mat("windows")
	material.emission_energy_multiplier = lerpf(WINDOW_NIGHT_ENERGY, 0.0, amount)


## World transform the player should spawn at.
func get_spawn_transform() -> Transform3D:
	var marker := get_node_or_null("PlayerSpawn") as Marker3D
	if marker != null:
		return marker.global_transform
	return global_transform


func _make_container(container_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = container_name
	add_child(node)
	return node


func _build_palette() -> void:
	_palette = {
		"ground": CityKit.make_material(Color(0.412, 0.408, 0.392)),
		"asphalt": CityKit.make_material(Color(0.145, 0.149, 0.165)),
		"sidewalk": CityKit.make_material(Color(0.529, 0.522, 0.498)),
		"marking": CityKit.make_material(Color(0.749, 0.733, 0.635), 0.8),
		"grass": CityKit.make_material(Color(0.239, 0.353, 0.184)),
		"roof": CityKit.make_material(Color(0.243, 0.247, 0.263)),
		"plinth": CityKit.make_material(Color(0.310, 0.310, 0.325)),
		"metal": CityKit.make_material(Color(0.400, 0.412, 0.443), 0.55, 0.5),
		"wood": CityKit.make_material(Color(0.400, 0.278, 0.176), 0.85),
		"foliage": CityKit.make_material(Color(0.196, 0.361, 0.184)),
		"trunk": CityKit.make_material(Color(0.290, 0.216, 0.153)),
		"water": CityKit.make_material(Color(0.267, 0.451, 0.510), 0.25, 0.2),
		# Dark glass by day, lit from inside after dark. The albedo stays dark
		# so daylight does not blow the bands out to white; only the emission
		# is animated, by _on_daylight_changed().
		"windows": CityKit.make_emissive_material(Color(0.114, 0.133, 0.169), 0.0, WINDOW_GLOW),
		"lamp": CityKit.make_emissive_material(Color(0.180, 0.176, 0.157), 2.6, LAMP_GLOW),
		"brick_a": CityKit.make_material(Color(0.541, 0.373, 0.318)),
		"brick_b": CityKit.make_material(Color(0.612, 0.529, 0.443)),
		"concrete_a": CityKit.make_material(Color(0.478, 0.494, 0.514)),
		"concrete_b": CityKit.make_material(Color(0.396, 0.427, 0.463)),
		"teal": CityKit.make_material(Color(0.294, 0.427, 0.412)),
		"sand": CityKit.make_material(Color(0.671, 0.596, 0.451)),
		"navy": CityKit.make_material(Color(0.216, 0.267, 0.365)),
		"door": CityKit.make_material(Color(0.145, 0.157, 0.180), 0.5),
	}


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


# --- Terrain -------------------------------------------------------------

func _build_ground() -> void:
	CityKit.add_slab(
		_geometry,
		"Ground",
		CityKit.rect_from_bounds(-GROUND_EXTENT, -GROUND_EXTENT, GROUND_EXTENT, GROUND_EXTENT),
		-2.0,
		2.0,
		_mat("ground")
	)

	# Green verges so the district is not wall-to-wall concrete.
	var verges := [
		CityKit.rect_from_bounds(-EXTENT, -EXTENT, -46.0, -59.0),
		CityKit.rect_from_bounds(50.0, -EXTENT, EXTENT, -59.0),
		CityKit.rect_from_bounds(-EXTENT, 62.0, -38.0, EXTENT),
		CityKit.rect_from_bounds(9.0, 62.0, EXTENT, EXTENT),
	]
	for i in verges.size():
		_add_grass("Verge%d" % i, verges[i])


func _add_grass(node_name: String, rect: Rect2) -> void:
	CityKit.add_slab(
		_geometry, node_name, rect, GRASS_BASE, GRASS_THICKNESS, _mat("grass"), false, false
	)


# --- Streets -------------------------------------------------------------

func _build_roads() -> void:
	# Two east-west streets running the full width of the district...
	_add_road("MainStreet", CityKit.rect_from_bounds(-EXTENT, -ROAD_HALF, EXTENT, ROAD_HALF))
	_add_road(
		"NorthAvenue",
		CityKit.rect_from_bounds(
			-EXTENT, NORTH_AVE_Z - ROAD_HALF, EXTENT, NORTH_AVE_Z + ROAD_HALF
		)
	)
	# ...and one north-south boulevard, split so it never overlaps the two
	# junctions (co-planar overlapping slabs would z-fight).
	var blvd_segments := [
		CityKit.rect_from_bounds(-ROAD_HALF, -EXTENT, ROAD_HALF, NORTH_AVE_Z - ROAD_HALF),
		CityKit.rect_from_bounds(-ROAD_HALF, NORTH_AVE_Z + ROAD_HALF, ROAD_HALF, -ROAD_HALF),
		CityKit.rect_from_bounds(-ROAD_HALF, ROAD_HALF, ROAD_HALF, EXTENT),
	]
	for i in blvd_segments.size():
		_add_road("CenterBoulevard%d" % i, blvd_segments[i])


func _add_road(node_name: String, rect: Rect2) -> void:
	CityKit.add_slab(
		_geometry, node_name, rect, ROAD_BASE, ROAD_THICKNESS, _mat("asphalt"), false, false
	)


func _build_road_markings() -> void:
	# Dashed centre lines, skipping the junction boxes.
	_add_dashes_along_x(MAIN_ST_Z, -EXTENT, EXTENT, [Vector2(-ROAD_HALF, ROAD_HALF)])
	_add_dashes_along_x(NORTH_AVE_Z, -EXTENT, EXTENT, [Vector2(-ROAD_HALF, ROAD_HALF)])
	_add_dashes_along_z(
		CENTER_BLVD_X,
		-EXTENT,
		EXTENT,
		[
			Vector2(NORTH_AVE_Z - ROAD_HALF, NORTH_AVE_Z + ROAD_HALF),
			Vector2(-ROAD_HALF, ROAD_HALF),
		]
	)

	# Crosswalks on every approach to the two junctions.
	for junction_x in [CENTER_BLVD_X]:
		for junction_z in [MAIN_ST_Z, NORTH_AVE_Z]:
			_add_crosswalk(Vector2(junction_x, junction_z - ROAD_HALF - 1.6), true)
			_add_crosswalk(Vector2(junction_x, junction_z + ROAD_HALF + 1.6), true)
			_add_crosswalk(Vector2(junction_x - ROAD_HALF - 1.6, junction_z), false)
			_add_crosswalk(Vector2(junction_x + ROAD_HALF + 1.6, junction_z), false)


func _add_marking(node_name: String, rect: Rect2) -> void:
	CityKit.add_slab(
		_geometry, node_name, rect, MARKING_BASE, MARKING_THICKNESS, _mat("marking"), false, false
	)


## `skip` holds inclusive ranges of X that must stay unpainted (junctions).
func _add_dashes_along_x(z: float, from_x: float, to_x: float, skip: Array) -> void:
	var dash := 3.0
	var gap := 3.0
	var x := from_x
	var index := 0
	while x < to_x:
		var end := minf(x + dash, to_x)
		if not _is_skipped(x, end, skip):
			_add_marking(
				"Dash_%.0f_%d" % [z, index], CityKit.rect_from_bounds(x, z - 0.16, end, z + 0.16)
			)
		x = end + gap
		index += 1


func _add_dashes_along_z(x: float, from_z: float, to_z: float, skip: Array) -> void:
	var dash := 3.0
	var gap := 3.0
	var z := from_z
	var index := 0
	while z < to_z:
		var end := minf(z + dash, to_z)
		if not _is_skipped(z, end, skip):
			_add_marking(
				"DashV_%.0f_%d" % [x, index], CityKit.rect_from_bounds(x - 0.16, z, x + 0.16, end)
			)
		z = end + gap
		index += 1


func _is_skipped(from: float, to: float, skip: Array) -> bool:
	for range_2d: Vector2 in skip:
		if to > range_2d.x and from < range_2d.y:
			return true
	return false


## `horizontal` means the stripes run across an east-west approach.
func _add_crosswalk(center: Vector2, horizontal: bool) -> void:
	var stripes := 7
	var stripe_width := 0.5
	var spacing := 1.55
	for i in stripes:
		var offset := (float(i) - float(stripes - 1) * 0.5) * spacing
		var rect: Rect2
		if horizontal:
			rect = CityKit.rect_from_bounds(
				center.x + offset - stripe_width * 0.5,
				center.y - 1.1,
				center.x + offset + stripe_width * 0.5,
				center.y + 1.1
			)
		else:
			rect = CityKit.rect_from_bounds(
				center.x - 1.1,
				center.y + offset - stripe_width * 0.5,
				center.x + 1.1,
				center.y + offset + stripe_width * 0.5
			)
		_add_marking("Crosswalk_%.0f_%.0f_%d" % [center.x, center.y, i], rect)


func _build_sidewalks() -> void:
	# East-west sidewalks own the junction corners, so the north-south strips
	# are split to stop short of them. Between them the pavement is continuous
	# with no overlapping slabs.
	var ew_spans := [
		Vector2(-EXTENT, -ROAD_HALF - WALK_WIDTH),
		Vector2(ROAD_HALF + WALK_WIDTH, EXTENT),
	]
	for road_z in [MAIN_ST_Z, NORTH_AVE_Z]:
		for span: Vector2 in ew_spans:
			_add_sidewalk(
				CityKit.rect_from_bounds(
					span.x, road_z - ROAD_HALF - WALK_WIDTH, span.y, road_z - ROAD_HALF
				)
			)
			_add_sidewalk(
				CityKit.rect_from_bounds(
					span.x, road_z + ROAD_HALF, span.y, road_z + ROAD_HALF + WALK_WIDTH
				)
			)

	var ns_spans := [
		Vector2(-EXTENT, NORTH_AVE_Z - ROAD_HALF - WALK_WIDTH),
		Vector2(NORTH_AVE_Z + ROAD_HALF + WALK_WIDTH, -ROAD_HALF - WALK_WIDTH),
		Vector2(ROAD_HALF + WALK_WIDTH, EXTENT),
	]
	for span: Vector2 in ns_spans:
		_add_sidewalk(
			CityKit.rect_from_bounds(
				CENTER_BLVD_X - ROAD_HALF - WALK_WIDTH, span.x, CENTER_BLVD_X - ROAD_HALF, span.y
			)
		)
		_add_sidewalk(
			CityKit.rect_from_bounds(
				CENTER_BLVD_X + ROAD_HALF, span.x, CENTER_BLVD_X + ROAD_HALF + WALK_WIDTH, span.y
			)
		)


func _add_sidewalk(rect: Rect2) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	CityKit.add_slab(
		_geometry, "Sidewalk%d" % _sidewalk_index, rect, 0.0, CURB_HEIGHT, _mat("sidewalk")
	)
	_sidewalk_index += 1


## A low wall marking the edge of the playable district. New districts will
## replace these with connecting road stubs.
func _build_perimeter() -> void:
	var wall_height := 2.4
	var thickness := 1.0
	var edges := [
		CityKit.rect_from_bounds(-EXTENT - thickness, -EXTENT - thickness, EXTENT + thickness, -EXTENT),
		CityKit.rect_from_bounds(-EXTENT - thickness, EXTENT, EXTENT + thickness, EXTENT + thickness),
		CityKit.rect_from_bounds(-EXTENT - thickness, -EXTENT, -EXTENT, EXTENT),
		CityKit.rect_from_bounds(EXTENT, -EXTENT, EXTENT + thickness, EXTENT),
	]
	for i in edges.size():
		CityKit.add_slab(_geometry, "Boundary%d" % i, edges[i], 0.0, wall_height, _mat("concrete_b"))


# --- Buildings -----------------------------------------------------------

## Each entry: name, [min_x, min_z, max_x, max_z], height, body material key.
func _building_table() -> Array:
	# Heights are kept at or below the camera's eye level (~18m) so the elevated
	# view looks down onto roofs instead of being walled in by facades. The one
	# taller landmark sits at the far end of the district.
	return [
		# North-west block
		["LarkspurApartments", [-70.0, -41.0, -50.0, -13.0], 11.0, "brick_a"],
		["HarbourRowMarket", [-46.0, -27.0, -30.0, -13.0], 5.5, "teal"],
		["WashHouse", [-46.0, -41.0, -30.0, -31.0], 8.0, "brick_b"],
		["NorthwestOffices", [-26.0, -41.0, -13.0, -13.0], 13.0, "concrete_a"],
		# North-east block
		["TheGalleyDiner", [13.0, -41.0, 28.0, -27.0], 6.5, "sand"],
		["EastsideOffices", [13.0, -23.0, 28.0, -13.0], 10.0, "concrete_b"],
		["MeridianTower", [32.0, -41.0, 52.0, -13.0], 20.0, "navy"],
		["QuaysideRetail", [56.0, -41.0, 72.0, -13.0], 7.5, "brick_b"],
		# South-west block
		["PierpointWarehouse", [-72.0, 15.0, -44.0, 45.0], 10.0, "concrete_a"],
		# South-east block
		["PrecinctHouse", [13.0, 15.0, 36.0, 38.0], 8.5, "concrete_b"],
		["SoutheastResidences", [42.0, 15.0, 70.0, 44.0], 12.0, "brick_a"],
		# North strip
		["CivicHall", [-40.0, -80.0, -10.0, -63.0], 11.0, "sand"],
	]


func _build_buildings() -> void:
	var container := _make_container("Buildings")
	for entry in _building_table():
		var node_name: String = entry[0]
		var bounds: Array = entry[1]
		var height: float = entry[2]
		var material: StandardMaterial3D = _mat(entry[3])
		var rect := CityKit.rect_from_bounds(bounds[0], bounds[1], bounds[2], bounds[3])
		_add_building(container, node_name, rect, height, material)


func _add_building(
	parent: Node3D, node_name: String, rect: Rect2, height: float, material: StandardMaterial3D
) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)

	CityKit.add_slab(holder, "Body", rect, 0.0, height, material)

	# Ground-floor plinth, slightly proud of the body so the two never z-fight.
	var plinth := rect.grow(0.18)
	CityKit.add_slab(holder, "Plinth", plinth, 0.0, 3.2, _mat("plinth"))

	# Parapet cap. Its top face is the roof the player looks down on.
	CityKit.add_slab(holder, "Parapet", rect.grow(0.35), height, 0.7, _mat("roof"))
	_add_rooftop_clutter(holder, node_name, rect, height + 0.7)

	# Lit window bands, so the skyline still reads after dark. Cheap: one thin
	# box per floor band rather than per window.
	var band_y := 4.9
	var bands := 0
	while band_y < height - 1.6 and bands < 6:
		CityKit.add_slab(
			holder,
			"Windows%d" % bands,
			rect.grow(0.14),
			band_y,
			0.75,
			_mat("windows"),
			false,
			false
		)
		band_y += 3.6
		bands += 1


## Plant rooms, vents and a stair head on the roof. From an elevated top-down
## camera the roofs are most of what the player looks at, so a bare slab reads
## as unfinished. Seeded from the building name so the layout is stable between
## runs and between saves.
func _add_rooftop_clutter(
	parent: Node3D, node_name: String, rect: Rect2, roof_y: float
) -> void:
	var usable := rect.grow(-3.0)
	if usable.size.x < 3.0 or usable.size.y < 3.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_name)

	# Stair head, always present, tucked into a corner.
	var stair_size := Vector3(3.4, 2.6, 3.0)
	var stair_spot := Vector3(
		usable.position.x + stair_size.x * 0.5,
		roof_y + stair_size.y * 0.5,
		usable.position.y + stair_size.z * 0.5
	)
	CityKit.add_box(parent, "StairHead", stair_spot, stair_size, _mat("plinth"), false)

	var units := 2 + rng.randi_range(0, 2)
	for i in units:
		var size := Vector3(
			rng.randf_range(1.6, 3.4), rng.randf_range(0.8, 2.0), rng.randf_range(1.6, 3.0)
		)
		var spot := Vector3(
			rng.randf_range(usable.position.x + 4.0, usable.end.x),
			roof_y + size.y * 0.5,
			rng.randf_range(usable.position.y, usable.end.y)
		)
		var material := _mat("metal") if i % 2 == 0 else _mat("plinth")
		CityKit.add_box(parent, "RoofUnit%d" % i, spot, size, material, false)


# --- Park ----------------------------------------------------------------

func _build_park() -> void:
	var container := _make_container("Park")
	var park := CityKit.rect_from_bounds(-38.0, 15.0, -13.0, 60.0)
	CityKit.add_slab(
		container, "Lawn", park, GRASS_BASE, GRASS_THICKNESS, _mat("grass"), false, false
	)

	# A crossing pair of paths.
	CityKit.add_slab(
		container,
		"PathNS",
		CityKit.rect_from_bounds(-27.5, 15.0, -23.5, 60.0),
		PARK_PATH_BASE,
		GRASS_THICKNESS,
		_mat("sidewalk"),
		false,
		false
	)
	CityKit.add_slab(
		container,
		"PathEW",
		CityKit.rect_from_bounds(-38.0, 35.5, -13.0, 39.5),
		PARK_PATH_BASE,
		GRASS_THICKNESS,
		_mat("sidewalk"),
		false,
		false
	)

	var tree_spots := [
		Vector2(-34.0, 20.0), Vector2(-18.0, 20.0), Vector2(-34.0, 30.0),
		Vector2(-18.0, 30.0), Vector2(-34.0, 46.0), Vector2(-18.0, 46.0),
		Vector2(-34.0, 55.0), Vector2(-18.0, 55.0),
	]
	for i in tree_spots.size():
		_add_tree(container, "Tree%d" % i, tree_spots[i], 1.0 + float(i % 3) * 0.14)

	_add_fountain(container, Vector2(-25.5, 37.5))

	var bench_spots := [
		[Vector2(-29.5, 24.0), 0.0],
		[Vector2(-21.5, 45.0), 180.0],
		[Vector2(-29.5, 52.0), 0.0],
	]
	for i in bench_spots.size():
		_add_bench(container, "Bench%d" % i, bench_spots[i][0], bench_spots[i][1])


func _add_tree(parent: Node3D, node_name: String, spot: Vector2, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)
	var trunk_height := 3.2 * scale_factor
	CityKit.add_cylinder(
		holder,
		"Trunk",
		Vector3(spot.x, trunk_height * 0.5, spot.y),
		0.28 * scale_factor,
		trunk_height,
		_mat("trunk")
	)
	var canopy := 4.0 * scale_factor
	CityKit.add_sphere(
		holder,
		"Canopy",
		Vector3(spot.x, trunk_height + canopy * 0.32, spot.y),
		Vector3(canopy, canopy * 0.9, canopy),
		_mat("foliage")
	)


func _add_fountain(parent: Node3D, spot: Vector2) -> void:
	var holder := Node3D.new()
	holder.name = "Fountain"
	parent.add_child(holder)
	CityKit.add_cylinder(holder, "Basin", Vector3(spot.x, 0.45, spot.y), 3.2, 0.9, _mat("sidewalk"))
	CityKit.add_cylinder(
		holder, "Water", Vector3(spot.x, 0.92, spot.y), 2.8, 0.06, _mat("water"), false
	)
	CityKit.add_cylinder(
		holder, "Spout", Vector3(spot.x, 1.4, spot.y), 0.35, 1.8, _mat("sidewalk")
	)

	var drink := RestoreSpot.new()
	drink.name = "DrinkInteractable"
	drink.prompt_action = "Drink"
	drink.hunger = 6.0
	drink.energy = 4.0
	drink.cooldown_seconds = 6.0
	drink.unavailable_prompt = ""
	drink.success_message = "REFRESHED"
	CityKit.attach_interactable(
		_interactables, drink, Vector3(spot.x, 1.0, spot.y + 3.6), 2.6
	)


func _add_bench(parent: Node3D, node_name: String, spot: Vector2, yaw_degrees: float) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = Vector3(spot.x, 0.0, spot.y)
	holder.rotation_degrees.y = yaw_degrees
	parent.add_child(holder)

	CityKit.add_box(holder, "Seat", Vector3(0.0, 0.46, 0.0), Vector3(2.2, 0.12, 0.6), _mat("wood"))
	CityKit.add_box(
		holder, "Back", Vector3(0.0, 0.78, -0.26), Vector3(2.2, 0.5, 0.1), _mat("wood")
	)
	CityKit.add_box(
		holder, "LegL", Vector3(-0.9, 0.23, 0.0), Vector3(0.12, 0.46, 0.55), _mat("metal")
	)
	CityKit.add_box(
		holder, "LegR", Vector3(0.9, 0.23, 0.0), Vector3(0.12, 0.46, 0.55), _mat("metal")
	)

	var rest := RestoreSpot.new()
	rest.name = "%sRest" % node_name
	rest.prompt_action = "Sit and rest"
	rest.energy = 18.0
	rest.time_cost_minutes = 15
	rest.cooldown_seconds = 8.0
	rest.unavailable_prompt = ""
	rest.success_message = "RESTED  +18 ENERGY"
	# Placed just in front of the bench, in world space.
	var forward := Vector3(sin(deg_to_rad(yaw_degrees)), 0.0, cos(deg_to_rad(yaw_degrees)))
	var world_spot := Vector3(spot.x, 1.0, spot.y) + forward * 1.1
	CityKit.attach_interactable(_interactables, rest, world_spot, 2.2)


# --- Parking and street furniture ---------------------------------------

func _build_parking() -> void:
	var container := _make_container("Parking")

	# Kerbside bays on the north side of Main Street, outside the apartments
	# (north is -Z). Sized so a car fits once vehicles arrive in Phase D.
	for i in 5:
		var x := -70.0 + float(i) * 11.0
		_add_bay(container, "MainBay%d" % i, CityKit.rect_from_bounds(x, -5.9, x + 10.0, -2.2))

	# An off-street lot behind the civic hall.
	var lot := CityKit.rect_from_bounds(8.0, -80.0, 48.0, -62.0)
	CityKit.add_slab(
		container, "CivicLot", lot, ROAD_BASE, ROAD_THICKNESS, _mat("asphalt"), false, false
	)
	for i in 7:
		var x := 10.0 + float(i) * 5.4
		_add_bay(container, "CivicBay%d" % i, CityKit.rect_from_bounds(x, -78.0, x + 4.6, -68.0))


func _add_bay(parent: Node3D, node_name: String, rect: Rect2) -> void:
	var line := 0.16
	var edges := [
		CityKit.rect_from_bounds(rect.position.x, rect.position.y, rect.position.x + line, rect.end.y),
		CityKit.rect_from_bounds(rect.end.x - line, rect.position.y, rect.end.x, rect.end.y),
		CityKit.rect_from_bounds(rect.position.x, rect.end.y - line, rect.end.x, rect.end.y),
	]
	for i in edges.size():
		CityKit.add_slab(
			parent,
			"%s_%d" % [node_name, i],
			edges[i],
			MARKING_BASE,
			MARKING_THICKNESS,
			_mat("marking"),
			false,
			false
		)


func _build_street_lights() -> void:
	var container := _make_container("StreetLights")
	var index := 0
	for x in [-72.0, -48.0, -24.0, 24.0, 48.0, 72.0]:
		for road_z in [MAIN_ST_Z, NORTH_AVE_Z]:
			_add_street_light(
				container, index, Vector3(x, 0.0, road_z - ROAD_HALF - 1.5), Vector3.BACK
			)
			index += 1
			_add_street_light(
				container, index, Vector3(x, 0.0, road_z + ROAD_HALF + 1.5), Vector3.FORWARD
			)
			index += 1
	for z in [-74.0, -30.0, 30.0, 74.0]:
		_add_street_light(
			container, index, Vector3(-ROAD_HALF - 1.5, 0.0, z), Vector3.RIGHT
		)
		index += 1
		_add_street_light(container, index, Vector3(ROAD_HALF + 1.5, 0.0, z), Vector3.LEFT)
		index += 1


## `toward` points from the pole to the road, so the lamp head overhangs it.
func _add_street_light(parent: Node3D, index: int, base: Vector3, toward: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "StreetLight%d" % index
	holder.position = base + Vector3.UP * CURB_HEIGHT
	parent.add_child(holder)

	var pole_height := 6.4
	CityKit.add_cylinder(
		holder, "Pole", Vector3(0.0, pole_height * 0.5, 0.0), 0.13, pole_height, _mat("metal")
	)

	var arm_length := 1.8
	var arm_center := toward * (arm_length * 0.5) + Vector3.UP * pole_height
	var arm_size := Vector3(
		maxf(absf(toward.x) * arm_length, 0.14), 0.14, maxf(absf(toward.z) * arm_length, 0.14)
	)
	CityKit.add_box(holder, "Arm", arm_center, arm_size, _mat("metal"), false)

	var head_position := toward * arm_length + Vector3.UP * (pole_height - 0.16)
	CityKit.add_box(
		holder, "Head", head_position, Vector3(0.52, 0.2, 0.52), _mat("lamp"), false, false
	)

	var light := OmniLight3D.new()
	light.name = "Lamp"
	light.position = head_position + Vector3.DOWN * 0.3
	light.light_color = Color(1.0, 0.878, 0.678)
	light.light_energy = 5.0
	light.omni_range = 18.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	light.visible = false
	light.add_to_group("street_light")
	holder.add_child(light)


# --- Interaction points --------------------------------------------------

## Doors and markers for the venues that get their interiors and systems in
## later phases. The prompts, positions and detection volumes are final; only
## what happens after the prompt changes.
##
## Each entry: name, interaction point, outward facing (away from the wall),
## prompt verb, message.
func _venue_table() -> Array:
	return [
		[
			"ApartmentDoor", Vector3(-60.0, 1.2, -12.4), Vector3.BACK, "Enter Apartment",
			"LARKSPUR APARTMENTS\nYour flat is upstairs — interiors arrive with the apartment system.",
		],
		[
			"MarketDoor", Vector3(-38.0, 1.2, -12.4), Vector3.BACK, "Shop",
			"HARBOUR ROW MARKET\nOpens with the shop and inventory systems.",
		],
		[
			"DinerDoor", Vector3(20.5, 1.2, -26.4), Vector3.BACK, "Enter Diner",
			"THE GALLEY DINER\nHot food goes on sale with the shop system.",
		],
		[
			"WarehouseGate", Vector3(-58.0, 1.2, 45.6), Vector3.BACK, "Work",
			"PIERPOINT WAREHOUSE\nShifts open with the job system.",
		],
		[
			"PrecinctDoor", Vector3(24.5, 1.2, 38.6), Vector3.BACK, "Enter Precinct",
			"PRECINCT HOUSE\nStaffed once the police and wanted systems are in.",
		],
	]


func _build_venue_doors() -> void:
	for entry in _venue_table():
		var node_name: String = entry[0]
		var point: Vector3 = entry[1]
		var facing: Vector3 = entry[2]
		var prompt: String = entry[3]
		var message: String = entry[4]

		var door := MessagePoint.new()
		door.name = node_name
		door.prompt_action = prompt
		door.message = message
		CityKit.attach_interactable(_interactables, door, point, 2.6)

		_add_door_panel(node_name, point, facing)


## A visible door slab on the facade, so the prompt has something to point at.
## Pushed back from the interaction volume toward the wall it belongs to.
func _add_door_panel(node_name: String, interaction_point: Vector3, facing: Vector3) -> void:
	var panel_center := interaction_point - facing * 0.5
	panel_center.y = 1.35
	var along := Vector3(absf(facing.z), 0.0, absf(facing.x))
	var size := along * 2.4 + Vector3(0.0, 2.7, 0.0) + facing.abs() * 0.3
	CityKit.add_box(
		_geometry, "DoorPanel_%s" % node_name, panel_center, size, _mat("door"), false
	)


func _build_notice_board() -> void:
	var holder := Node3D.new()
	holder.name = "NoticeBoard"
	holder.position = Vector3(-53.0, CURB_HEIGHT, -7.6)
	_props.add_child(holder)

	CityKit.add_box(
		holder, "PostL", Vector3(-0.75, 0.9, 0.0), Vector3(0.12, 1.8, 0.12), _mat("metal")
	)
	CityKit.add_box(
		holder, "PostR", Vector3(0.75, 0.9, 0.0), Vector3(0.12, 1.8, 0.12), _mat("metal")
	)
	CityKit.add_box(
		holder, "Board", Vector3(0.0, 1.75, 0.0), Vector3(1.9, 1.2, 0.1), _mat("wood")
	)

	var notice := MessagePoint.new()
	notice.name = "Notices"
	notice.prompt_action = "Read notices"
	notice.focus_priority = 1
	notice.message = (
		"HARBOUR ROW — CONTROLS\n"
		+ "WASD move  ·  SHIFT sprint  ·  E interact\n"
		+ "Q / ARROWS or RIGHT-DRAG orbit  ·  WHEEL zoom  ·  ESC pause"
	)
	CityKit.attach_interactable(
		_interactables, notice, holder.position + Vector3(0.0, 1.1, 0.9), 2.2
	)
