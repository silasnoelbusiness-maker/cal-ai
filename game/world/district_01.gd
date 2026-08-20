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

## What the convenience store sells. Data, not code: adding a line here is a new
## product, and a second shop is a second list.
const MARKET_STOCK: Array[ItemData] = [
	preload("res://items/definitions/basic_meal.tres"),
	preload("res://items/definitions/snack_bar.tres"),
	preload("res://items/definitions/energy_drink.tres"),
]
const WAREHOUSE_JOB: JobData = preload("res://jobs/definitions/warehouse_worker.tres")

## Framing used inside the apartment, which is far too small for street framing.
const INTERIOR_CAMERA_DISTANCE := 11.0
const INTERIOR_CAMERA_PITCH := 74.0

## Distance from a road centre line to each traffic lane. Two moving lanes plus
## a kerbside parking bay have to share a 12m carriageway, so this is as far out
## as a lane can sit and still leave a van clear of the parked cars.
const LANE_OFFSET := 2.5
## Distance from a road centre line to the kerbside parking line. Close enough
## to the 6m kerb that a parked car is obviously parked, far enough out that
## through traffic passes it without touching.
const PARKING_OFFSET := 4.9
## Distance from a junction centre to the painted stop bar on each approach —
## just beyond the crosswalk. The signals take their stop line from the same
## constant, so the paint and the rule can never drift apart.
const STOP_LINE_OFFSET := ROAD_HALF + 3.0

# The park's paths, which pedestrians and police need to be able to route along.
const PARK_BOUNDS := Rect2(-38.0, 15.0, 25.0, 45.0)
const PARK_PATH_X := -25.5
const PARK_PATH_Z := 37.5
## The fountain sits exactly where the two paths cross, so the walkable route
## goes round it rather than through it. The ring clears the 3.2m basin by more
## than a pedestrian's width even along the diagonal shortcuts the graph's
## connect radius creates.
const FOUNTAIN_RING := 5.2
const FOUNTAIN_PLAZA_HALF := 6.5

## Distance from a road centre line to the pedestrian route on each side. Kept
## clear of the kerbside street lights, which would otherwise stand in the
## middle of the walking line and jam the crowd against them.
const PAVEMENT_OFFSET := 8.4
## Street lights sit close to the kerb so their arms overhang the carriageway.
const STREET_LIGHT_KERB_GAP := 0.8

## The kerb lip along the road edge of a pavement: how wide the band is, and how
## far it stands above the pavement so it catches the light.
const KERB_WIDTH := 0.45
const KERB_LIFT := 0.04

## Kerbs live on their own physics layer (6). Pedestrians collide with it and
## step up; vehicles do not, so a car can mount a kerb instead of being stopped
## dead by a 12cm lip. The visual cost is that a car on the pavement sits a few
## centimetres into it, which is invisible at this camera distance.
const CURB_LAYER := 1 << 5

## Which side of a pavement slab the road is on, and therefore where its kerb
## goes. Passed in rather than inferred, because the pavement at a junction
## corner faces two roads and a guess would put a kerb across the crossing.
enum Kerb { NONE, NORTH, SOUTH, EAST, WEST }

const SEDAN_SCENE: PackedScene = preload("res://vehicles/cars/sedan.tscn")
const ROAD_NETWORK_SCRIPT: Script = preload("res://traffic/road_network.gd")
const TRAFFIC_LIGHT_SCRIPT: Script = preload("res://traffic/traffic_light.gd")
const TRAFFIC_MANAGER_SCRIPT: Script = preload("res://traffic/traffic_manager.gd")
const POLICE_CAR_SCENE: PackedScene = preload("res://vehicles/cars/police_car.tscn")
const PEDESTRIAN_SCENE: PackedScene = preload("res://npc/pedestrian.tscn")
const POLICE_OFFICER_SCENE: PackedScene = preload("res://npc/police_officer.tscn")
const NAV_GRAPH_SCRIPT: Script = preload("res://npc/nav_graph.gd")

## How many civilians walk the district.
const PEDESTRIAN_COUNT := 16

var _palette: Dictionary = {}
var _foliage: Array = []
var _geometry: Node3D
var _props: Node3D
var _interactables: Node3D
var _sidewalk_index: int = 0
var _nav: NavGraph = null


## What this district is like, for everything that asks WorldManager rather than
## checking coordinates itself. Harbour Row is the baseline the rest of the city
## is described against, so most of its numbers are 1.0.
func _register_district() -> void:
	var district := DistrictData.make(
		&"harbour_row", "Harbour Row", Rect2(-EXTENT, -EXTENT, EXTENT * 2.0, EXTENT * 2.0),
		"Where you started"
	)
	district.traffic_density = 1.0
	district.pedestrian_density = 1.0
	district.commercial_demand_modifier = 1.0
	district.commercial_rent_modifier = 1.0
	district.residential_rent_modifier = 1.0
	district.police_presence = 1.0
	WorldManager.register(district)


func _ready() -> void:
	add_to_group(&"district")
	_register_district()
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
	_build_services()
	_build_street_lights()
	_build_streetscape()
	_build_warehouse_yard()
	_build_venue_doors()
	_build_notice_board()
	_build_nav_graph()
	_build_traffic()
	_build_vehicles()
	_build_pedestrians()
	_build_police()

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


## Every surface the player looks at for any length of time gets relief on it —
## see CityKit.make_surface. The detail scale is chosen per surface: asphalt is
## fine-grained, grass and foliage are coarse and clumpy, brick is on the course
## spacing, roof shingle on the row spacing. Markings, glass and lamps stay flat,
## because a crisp painted line and a pane of glass are meant to look smooth.
func _build_palette() -> void:
	_palette = {
		"ground": CityKit.make_surface(Color(0.400, 0.396, 0.376), 0.94, 9.0, 1.0, 0.20, 0.0, 11),
		"asphalt": CityKit.make_surface(Color(0.137, 0.141, 0.157), 0.88, 7.0, 1.3, 0.26, 0.0, 2),
		"sidewalk": CityKit.make_surface(Color(0.506, 0.498, 0.475), 0.90, 7.0, 0.6, 0.11, 0.0, 3),
		"marking": CityKit.make_material(Color(0.749, 0.733, 0.635), 0.8),
		"grass": CityKit.make_surface(Color(0.231, 0.345, 0.176), 0.95, 4.0, 1.8, 0.34, 0.0, 4),
		"roof": CityKit.make_surface(Color(0.235, 0.239, 0.255), 0.90, 3.0, 1.2, 0.22, 0.0, 5),
		"shingle": CityKit.make_surface(Color(0.510, 0.286, 0.180), 0.92, 1.5, 1.6, 0.28, 0.0, 6),
		"slate": CityKit.make_surface(Color(0.310, 0.325, 0.353), 0.86, 1.5, 1.5, 0.24, 0.0, 7),
		"plinth": CityKit.make_surface(Color(0.302, 0.302, 0.318), 0.90, 4.0, 0.8, 0.16, 0.0, 8),
		"metal": CityKit.make_surface(Color(0.400, 0.412, 0.443), 0.55, 2.0, 0.4, 0.09, 0.5, 9),
		"wood": CityKit.make_surface(Color(0.392, 0.271, 0.169), 0.85, 0.9, 1.2, 0.24, 0.0, 10),
		"trunk": CityKit.make_surface(Color(0.282, 0.208, 0.145), 0.95, 0.8, 1.8, 0.28, 0.0, 12),
		# Water is the one surface that must stay smooth: relief on it reads as
		# television static rather than as a fountain.
		"water": CityKit.make_material(Color(0.216, 0.376, 0.435), 0.12, 0.25),
		"kerb": CityKit.make_surface(Color(0.600, 0.592, 0.565), 0.90, 3.0, 0.7, 0.14, 0.0, 14),
		"gravel": CityKit.make_surface(Color(0.443, 0.427, 0.400), 0.96, 1.6, 2.0, 0.34, 0.0, 15),
		"hedge": CityKit.make_surface(Color(0.176, 0.294, 0.157), 0.95, 1.0, 2.0, 0.34, 0.0, 16),
		# Dark glass by day, lit from inside after dark. The albedo stays dark
		# so daylight does not blow the bands out to white; only the emission
		# is animated, by _on_daylight_changed().
		"windows": CityKit.make_emissive_material(Color(0.192, 0.224, 0.278), 0.0, WINDOW_GLOW),
		"lamp": CityKit.make_emissive_material(Color(0.180, 0.176, 0.157), 2.6, LAMP_GLOW),
		"brick_a": CityKit.make_surface(Color(0.529, 0.361, 0.306), 0.93, 2.0, 1.4, 0.22, 0.0, 20),
		"brick_b": CityKit.make_surface(Color(0.600, 0.518, 0.431), 0.93, 2.0, 1.4, 0.22, 0.0, 21),
		"concrete_a": CityKit.make_surface(Color(0.467, 0.482, 0.502), 0.90, 5.0, 0.8, 0.16, 0.0, 22),
		"concrete_b": CityKit.make_surface(Color(0.384, 0.416, 0.451), 0.90, 5.0, 0.8, 0.16, 0.0, 23),
		"teal": CityKit.make_surface(Color(0.286, 0.416, 0.400), 0.90, 3.5, 0.9, 0.18, 0.0, 24),
		"sand": CityKit.make_surface(Color(0.659, 0.584, 0.439), 0.92, 3.5, 0.9, 0.18, 0.0, 25),
		"navy": CityKit.make_surface(Color(0.208, 0.259, 0.353), 0.88, 5.0, 0.8, 0.16, 0.0, 26),
		"door": CityKit.make_material(Color(0.145, 0.157, 0.180), 0.5),
	}
	# Three shades of leaf, so a canopy is not one flat green and no two trees on
	# a street are quite the same colour.
	_foliage = [
		CityKit.make_surface(Color(0.196, 0.361, 0.184), 0.95, 1.1, 2.2, 0.36, 0.0, 30),
		CityKit.make_surface(Color(0.251, 0.427, 0.200), 0.95, 1.1, 2.2, 0.36, 0.0, 31),
		CityKit.make_surface(Color(0.157, 0.302, 0.165), 0.95, 1.1, 2.2, 0.36, 0.0, 32),
	]


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
	SurfaceMap.probe(_geometry, rect, GRASS_BASE + GRASS_THICKNESS, SurfaceMap.Surface.GRASS)


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
	# A road is a decorative slab with no collision, so footsteps get a probe
	# over it instead. Moving a street moves the sound of walking on it, because
	# both come from the same rect.
	SurfaceMap.probe(_geometry, rect, ROAD_BASE + ROAD_THICKNESS, SurfaceMap.Surface.ASPHALT)


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
			_add_stop_lines(junction_x, junction_z)


## A painted bar across each approach, on that approach's own half of the
## carriageway and just outside the crosswalk, so where the traffic waiting at a
## red is waiting is legible from above.
func _add_stop_lines(junction_x: float, junction_z: float) -> void:
	var tag := "%d_%d" % [int(junction_x), int(junction_z)]
	var bar := 0.45

	# Eastbound waits west of the junction in the southern lane; westbound waits
	# east of it in the northern one.
	_add_marking(
		"StopEast%s" % tag,
		CityKit.rect_from_bounds(
			junction_x - STOP_LINE_OFFSET - bar, junction_z,
			junction_x - STOP_LINE_OFFSET, junction_z + ROAD_HALF
		)
	)
	_add_marking(
		"StopWest%s" % tag,
		CityKit.rect_from_bounds(
			junction_x + STOP_LINE_OFFSET, junction_z - ROAD_HALF,
			junction_x + STOP_LINE_OFFSET + bar, junction_z
		)
	)
	# Northbound waits south of the junction in the eastern lane; southbound
	# waits north of it in the western one.
	_add_marking(
		"StopNorth%s" % tag,
		CityKit.rect_from_bounds(
			junction_x, junction_z + STOP_LINE_OFFSET,
			junction_x + ROAD_HALF, junction_z + STOP_LINE_OFFSET + bar
		)
	)
	_add_marking(
		"StopSouth%s" % tag,
		CityKit.rect_from_bounds(
			junction_x - ROAD_HALF, junction_z - STOP_LINE_OFFSET - bar,
			junction_x, junction_z - STOP_LINE_OFFSET
		)
	)


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
			# The pavement north of the road has the carriageway on its south
			# edge, and vice versa.
			_add_sidewalk(
				CityKit.rect_from_bounds(
					span.x, road_z - ROAD_HALF - WALK_WIDTH, span.y, road_z - ROAD_HALF
				),
				Kerb.SOUTH
			)
			_add_sidewalk(
				CityKit.rect_from_bounds(
					span.x, road_z + ROAD_HALF, span.y, road_z + ROAD_HALF + WALK_WIDTH
				),
				Kerb.NORTH
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
			),
			Kerb.EAST
		)
		_add_sidewalk(
			CityKit.rect_from_bounds(
				CENTER_BLVD_X + ROAD_HALF, span.x, CENTER_BLVD_X + ROAD_HALF + WALK_WIDTH, span.y
			),
			Kerb.WEST
		)


func _add_sidewalk(rect: Rect2, kerb: Kerb = Kerb.NONE) -> void:
	if rect.size.x <= 0.01 or rect.size.y <= 0.01:
		return
	var slab := CityKit.add_slab(
		_geometry,
		"Sidewalk%d" % _sidewalk_index,
		rect,
		0.0,
		CURB_HEIGHT,
		_mat("sidewalk"),
		true,
		true,
		CURB_LAYER
	)
	SurfaceMap.tag(slab, SurfaceMap.Surface.CONCRETE)
	_add_kerb(rect, kerb)
	_sidewalk_index += 1


## The lip along the road edge of a pavement.
##
## Purely decorative — the pavement slab underneath already carries the
## collision, on the layer vehicles ignore. But from an elevated camera an
## unmarked pavement/road boundary reads as a change of paint rather than a
## step, and that single light band is most of what makes a street look built
## rather than drawn.
func _add_kerb(rect: Rect2, edge: Kerb) -> void:
	if edge == Kerb.NONE:
		return
	var strip := rect
	match edge:
		Kerb.NORTH:
			strip = CityKit.rect_from_bounds(
				rect.position.x, rect.position.y, rect.end.x, rect.position.y + KERB_WIDTH
			)
		Kerb.SOUTH:
			strip = CityKit.rect_from_bounds(
				rect.position.x, rect.end.y - KERB_WIDTH, rect.end.x, rect.end.y
			)
		Kerb.WEST:
			strip = CityKit.rect_from_bounds(
				rect.position.x, rect.position.y, rect.position.x + KERB_WIDTH, rect.end.y
			)
		Kerb.EAST:
			strip = CityKit.rect_from_bounds(
				rect.end.x - KERB_WIDTH, rect.position.y, rect.end.x, rect.end.y
			)
	CityKit.add_slab(
		_geometry,
		"Kerb%d" % _sidewalk_index,
		strip,
		0.0,
		CURB_HEIGHT + KERB_LIFT,
		_mat("kerb"),
		false
	)


## A low wall marking the edge of the district, with a gap at the north end of
## Center Boulevard where the road carries on into the Central District.
##
## The gap is the join: the carriageway, the pavements and both graphs run
## straight through it, so nothing happens at the boundary except the buildings
## getting taller.
func _build_perimeter() -> void:
	var wall_height := 2.4
	var thickness := 1.0
	var gateway_half := ROAD_HALF + WALK_WIDTH + 1.0
	var edges := [
		# North wall, in two pieces either side of the gateway.
		CityKit.rect_from_bounds(
			-EXTENT - thickness, -EXTENT - thickness,
			CENTER_BLVD_X - gateway_half, -EXTENT
		),
		CityKit.rect_from_bounds(
			CENTER_BLVD_X + gateway_half, -EXTENT - thickness,
			EXTENT + thickness, -EXTENT
		),
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
	# Roof style is the fifth column, and it is what decides whether a building
	# reads as a block or as a place: a flat parapet for the offices and the
	# apartment slabs, a pitched roof for everything low enough that you look
	# down onto it. Sixth column is the roof material.
	return [
		# North-west block
		["LarkspurApartments", [-70.0, -41.0, -50.0, -13.0], 11.0, "brick_a", "flat", "roof"],
		["HarbourRowMarket", [-46.0, -27.0, -30.0, -13.0], 5.5, "teal", "hip", "shingle"],
		["WashHouse", [-46.0, -41.0, -30.0, -31.0], 8.0, "brick_b", "hip", "slate"],
		["NorthwestOffices", [-26.0, -41.0, -13.0, -13.0], 13.0, "concrete_a", "flat", "roof"],
		# North-east block
		["TheGalleyDiner", [13.0, -41.0, 28.0, -27.0], 6.5, "sand", "hip", "shingle"],
		["EastsideOffices", [13.0, -23.0, 28.0, -13.0], 10.0, "concrete_b", "flat", "roof"],
		["MeridianTower", [32.0, -41.0, 52.0, -13.0], 20.0, "navy", "flat", "roof"],
		["QuaysideRetail", [56.0, -41.0, 72.0, -13.0], 7.5, "brick_b", "hip", "slate"],
		# South-west block
		["PierpointWarehouse", [-72.0, 15.0, -44.0, 45.0], 10.0, "concrete_a", "ridge", "roof"],
		# South-east block
		["PrecinctHouse", [13.0, 15.0, 36.0, 38.0], 8.5, "concrete_b", "hip", "slate"],
		["SoutheastResidences", [42.0, 15.0, 70.0, 44.0], 12.0, "brick_a", "flat", "roof"],
		# North strip
		["CivicHall", [-40.0, -80.0, -10.0, -63.0], 11.0, "sand", "hip", "slate"],
	]


func _build_buildings() -> void:
	var container := _make_container("Buildings")
	for entry in _building_table():
		var node_name: String = entry[0]
		var bounds: Array = entry[1]
		var height: float = entry[2]
		var material: StandardMaterial3D = _mat(entry[3])
		var rect := CityKit.rect_from_bounds(bounds[0], bounds[1], bounds[2], bounds[3])
		_add_building(container, node_name, rect, height, material, entry[4], _mat(entry[5]))


func _add_building(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	height: float,
	material: StandardMaterial3D,
	roof_style: String,
	roof_material: StandardMaterial3D
) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	parent.add_child(holder)

	CityKit.add_slab(holder, "Body", rect, 0.0, height, material)

	# Ground-floor plinth, slightly proud of the body so the two never z-fight.
	var plinth := rect.grow(0.18)
	CityKit.add_slab(holder, "Plinth", plinth, 0.0, 3.2, _mat("plinth"))

	var top := height
	if roof_style == "flat":
		# Parapet cap. Its top face is the roof the player looks down on.
		CityKit.add_slab(holder, "Parapet", rect.grow(0.35), height, 0.7, _mat("roof"))
		_add_rooftop_clutter(holder, node_name, rect, height + 0.7)
		_add_facade_relief(holder, rect, height, material)
		top = height + 0.7
	else:
		top = _add_pitched_roof(holder, node_name, rect, height, roof_style, roof_material)

	# Punched windows on a grid rather than a continuous lit stripe. The lit
	# material is still shared and still faded by the day/night cycle, so the
	# skyline reads after dark for the same cost — but by day a facade now has
	# windows in it instead of a band of dark paint.
	BuildingKit.add_window_grid(
		holder, node_name, rect, 4.2, height - 1.2,
		_mat("windows"), _mat("plinth"), 3.4, 1.5, 1.8
	)

	# The roof the camera actually looks at.
	if roof_style == "flat":
		var roof_rng := RandomNumberGenerator.new()
		roof_rng.seed = hash(node_name) + 7
		BuildingKit.add_roof_kit(holder, node_name, rect, top, roof_rng)


## A cornice and vertical bays on the long faces of a flat-roofed block.
##
## The pitched roofs took care of the low buildings, but a twenty-metre office
## slab is still a box, and from an elevated camera a box is given away by having
## exactly one silhouette. Splitting the facade into bays gives the sun something
## to cast small shadows down, which is what a facade actually looks like.
func _add_facade_relief(
	parent: Node3D, rect: Rect2, height: float, material: StandardMaterial3D
) -> void:
	# Cornice: a band under the parapet, proud of the wall.
	CityKit.add_slab(
		parent, "Cornice", rect.grow(0.42), height - 0.75, 0.55, _mat("plinth"), false
	)

	var along_x := rect.size.x >= rect.size.y
	var run: float = rect.size.x if along_x else rect.size.y
	var bays := clampi(int(run / 6.5), 2, 7)
	var base := 3.2
	var bay_height := height - 0.9 - base
	if bay_height < 1.5:
		return

	for face in [-1.0, 1.0]:
		var fixed: float = (
			(rect.position.y if face < 0.0 else rect.end.y) if along_x
			else (rect.position.x if face < 0.0 else rect.end.x)
		)
		for i in bays + 1:
			var travel: float = (
				(rect.position.x if along_x else rect.position.y)
				+ run * float(i) / float(bays)
			)
			# Pull the end pilasters in so they sit on the wall, not past its corner.
			travel = clampf(
				travel,
				(rect.position.x if along_x else rect.position.y) + 0.5,
				(rect.end.x if along_x else rect.end.y) - 0.5
			)
			var centre := (
				Vector3(travel, base + bay_height * 0.5, fixed) if along_x
				else Vector3(fixed, base + bay_height * 0.5, travel)
			)
			var size := (
				Vector3(0.7, bay_height, 0.34) if along_x else Vector3(0.34, bay_height, 0.7)
			)
			CityKit.add_box(
				parent, "Pilaster%s%d" % ["N" if face < 0.0 else "S", i],
				centre, size, material, false, false
			)


## A pitched roof with eaves, a fascia band under them and a chimney. Returns the
## ridge height.
##
## "hip" is a proper hipped roof, which is what a house or a civic building has.
## "ridge" is a long shallow one, for the warehouse — the ridge runs almost the
## full length, so it reads as a shed rather than a cottage.
func _add_pitched_roof(
	parent: Node3D,
	node_name: String,
	rect: Rect2,
	base_y: float,
	style: String,
	material: StandardMaterial3D
) -> float:
	var short_side := minf(rect.size.x, rect.size.y)
	# A shallow roof reads as a tilted lid; the pitch has to be steep enough to
	# throw a shadow down one slope before it reads as a roof at all.
	var pitch := clampf(short_side * (0.14 if style == "ridge" else 0.34), 2.2, 6.5)
	var overhang := 0.6

	# Fascia: a thin band at the eaves line. Without it the slopes appear to
	# grow straight out of the wall, which is the one thing that gives a
	# primitive roof away from above.
	CityKit.add_slab(
		parent, "Fascia", rect.grow(overhang), base_y - 0.26, 0.3, _mat("roof")
	)
	CityKit.add_roof(
		parent,
		"Roof",
		rect,
		base_y,
		pitch,
		material,
		0.82 if style == "ridge" else 0.4,
		overhang
	)

	# One chimney, on the ridge, placed from the building's name so it lands in
	# the same spot every run.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_name)
	var along_x := rect.size.x >= rect.size.y
	var centre := rect.position + rect.size * 0.5
	var travel := (rect.size.x if along_x else rect.size.y) * 0.28
	var offset := rng.randf_range(-travel, travel)
	var stack := Vector3(
		centre.x + (offset if along_x else 0.0),
		base_y + pitch * 0.72,
		centre.y + (0.0 if along_x else offset)
	)
	CityKit.add_box(
		parent, "Chimney", stack, Vector3(1.1, pitch * 1.5, 1.1), _mat("brick_b"), false
	)
	return base_y + pitch


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

## Harbour Row's own landmark, so the map has an anchor at this end of the city
## as well as in Central.
func _add_park_landmark(parent: Node3D) -> void:
	var landmark := Marker3D.new()
	landmark.name = "HarbourParkLandmark"
	landmark.position = Vector3(PARK_PATH_X, 0.4, PARK_PATH_Z)
	landmark.set_meta("label", "Harbour Park")
	landmark.add_to_group(&"landmark")
	parent.add_child(landmark)


func _build_park() -> void:
	var container := _make_container("Park")
	_add_park_landmark(container)
	var park := CityKit.rect_from_bounds(-38.0, 15.0, -13.0, 60.0)
	CityKit.add_slab(
		container, "Lawn", park, GRASS_BASE, GRASS_THICKNESS, _mat("grass"), false, false
	)

	# A paved square under the fountain, so walking round the basin is walking on
	# the path rather than across the grass.
	CityKit.add_slab(
		container,
		"FountainPlaza",
		CityKit.rect_from_bounds(
			PARK_PATH_X - FOUNTAIN_PLAZA_HALF,
			PARK_PATH_Z - FOUNTAIN_PLAZA_HALF,
			PARK_PATH_X + FOUNTAIN_PLAZA_HALF,
			PARK_PATH_Z + FOUNTAIN_PLAZA_HALF
		),
		PARK_PATH_BASE,
		GRASS_THICKNESS,
		_mat("sidewalk"),
		false,
		false
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
		Vector2(-30.5, 17.5), Vector2(-21.0, 26.0), Vector2(-35.5, 40.0),
		Vector2(-16.0, 41.0), Vector2(-31.0, 58.5), Vector2(-20.5, 57.5),
		Vector2(-35.0, 51.0), Vector2(-16.5, 33.0),
	]
	for i in tree_spots.size():
		_add_tree(container, "Tree%d" % i, tree_spots[i], 1.0 + float(i % 3) * 0.14)

	var bush_rng := RandomNumberGenerator.new()
	bush_rng.seed = hash("HarbourRowParkPlanting")
	var bush_spots := [
		Vector2(-36.0, 22.5), Vector2(-15.5, 24.0), Vector2(-36.5, 33.0),
		Vector2(-15.0, 48.0), Vector2(-33.0, 44.0), Vector2(-19.0, 53.0),
		Vector2(-28.0, 19.0), Vector2(-22.5, 58.0),
	]
	for i in bush_spots.size():
		CityKit.add_hedge(
			container,
			"ParkBush%d" % i,
			bush_spots[i],
			bush_spots[i] + Vector2(bush_rng.randf_range(-2.2, 2.2), bush_rng.randf_range(-2.2, 2.2)),
			bush_rng.randf_range(0.8, 1.4),
			_mat("hedge"),
			bush_rng
		)

	_add_fountain(container, Vector2(-25.5, 37.5))

	var bench_spots := [
		[Vector2(-29.5, 24.0), 0.0],
		[Vector2(-21.5, 45.0), 180.0],
		[Vector2(-29.5, 52.0), 0.0],
	]
	for i in bench_spots.size():
		_add_bench(container, "Bench%d" % i, bench_spots[i][0], bench_spots[i][1])


## Seeded per tree from its name, so the crooked one is crooked in the same way
## on every run and in every screenshot.
func _add_tree(
	parent: Node3D,
	node_name: String,
	spot: Vector2,
	scale_factor: float,
	solid_trunk: bool = true
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_name)
	CityKit.add_tree(
		parent,
		node_name,
		Vector3(spot.x, 0.0, spot.y),
		scale_factor * rng.randf_range(0.9, 1.25),
		_mat("trunk"),
		_foliage,
		rng,
		solid_trunk
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


## The service quarter behind the civic hall: somewhere to keep a car and
## somewhere to get one fixed, both fronting onto the car park that is already
## there so a car can be driven right up to them.
func _build_services() -> void:
	var materials := {
		"wall": _mat("concrete_a"), "trim": _mat("metal"), "deck": _mat("asphalt"),
	}

	var garage := ServiceKit.build_garage(
		_geometry, _props, "HarbourGarage",
		CityKit.rect_from_bounds(10.0, -92.0, 34.0, -82.0), -82.0, 3, 0.0, materials
	)
	garage.garage_id = &"harbour_garage"
	garage.display_name = "Harbour Garage"
	garage.address = "Dock Road"
	garage.district_id = &"harbour_row"
	garage.capacity = 3
	garage.rent_amount = 260
	garage.deposit = 300
	garage.prompt_subtitle = "Harbour Garage"
	CityKit.attach_interactable(
		_interactables, garage, Vector3(22.0, 1.0, -79.5), 4.5
	)

	var shop := ServiceKit.build_repair_shop(
		_geometry, _props, "DocksideMotors",
		CityKit.rect_from_bounds(44.0, -92.0, 70.0, -82.0), -82.0, materials
	)
	shop.shop_name = "Dockside Motors"
	shop.prompt_action = "Vehicle Service"
	shop.prompt_subtitle = "Dockside Motors"
	CityKit.attach_interactable(
		_interactables, shop, shop.service_point + Vector3(0.0, 1.0, 2.6), 3.4
	)


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
	# The inner pair light the junction approaches, which are the darkest and
	# most important places to see from a moving car.
	for x in [-72.0, -48.0, -24.0, -12.0, 12.0, 24.0, 48.0, 72.0]:
		for road_z in [MAIN_ST_Z, NORTH_AVE_Z]:
			_add_street_light(
				container, index, Vector3(x, 0.0, road_z - ROAD_HALF - STREET_LIGHT_KERB_GAP), Vector3.BACK
			)
			index += 1
			_add_street_light(
				container, index, Vector3(x, 0.0, road_z + ROAD_HALF + STREET_LIGHT_KERB_GAP), Vector3.FORWARD
			)
			index += 1
	for z in [-74.0, -30.0, -12.0, 12.0, 30.0, 74.0]:
		_add_street_light(
			container, index, Vector3(-ROAD_HALF - STREET_LIGHT_KERB_GAP, 0.0, z), Vector3.RIGHT
		)
		index += 1
		_add_street_light(
			container, index, Vector3(ROAD_HALF + STREET_LIGHT_KERB_GAP, 0.0, z), Vector3.LEFT
		)
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


## Dressing for the job location, so it reads as somewhere you go to work
## rather than a blank wall with a prompt on it.
func _build_warehouse_yard() -> void:
	var yard := _make_container("WarehouseYard")

	# Loading dock beside the gate, with steps up so it is not a dead end.
	CityKit.add_slab(
		yard, "Dock", CityKit.rect_from_bounds(-72.0, 11.0, -63.0, 15.0), 0.0, 1.0, _mat("plinth")
	)
	# Steps down off the east end of the dock, tallest nearest the platform, so
	# the dock is not a ledge the player can climb onto but never leave.
	for i in 3:
		var step_x := -63.0 + float(i) * 0.7
		CityKit.add_slab(
			yard,
			"DockStep%d" % i,
			CityKit.rect_from_bounds(step_x, 11.6, step_x + 0.7, 14.4),
			0.0,
			1.0 - float(i + 1) * 0.25,
			_mat("plinth")
		)

	# Roller shutters on the facade, either side of the gate.
	for x in [-68.0, -50.0]:
		CityKit.add_box(
			yard,
			"Shutter%.0f" % x,
			Vector3(x, 1.75, 14.86),
			Vector3(4.0, 3.5, 0.28),
			_mat("metal"),
			false
		)

	# Pallets and crates stacked in the corner of the yard. Kept east of the gate
	# approach and clear of the Main Street sidewalk (which ends at z = 9), so
	# they dress the yard without blocking the walk to work. Seeded so the
	# layout is stable between runs.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("PierpointYard")
	for i in 7:
		var size := Vector3(
			rng.randf_range(1.1, 1.9), rng.randf_range(0.9, 1.7), rng.randf_range(1.1, 1.9)
		)
		var spot := Vector3(
			rng.randf_range(-53.0, -45.5), size.y * 0.5, rng.randf_range(10.5, 13.2)
		)
		var material := _mat("wood") if i % 3 != 0 else _mat("sand")
		CityKit.add_box(yard, "Crate%d" % i, spot, size, material)


# --- Interaction points --------------------------------------------------

## Doors and markers for the district's venues.
##
## Each entry: name, interaction point, outward facing (away from the wall),
## prompt verb, kind, message. `kind` selects which component the door gets:
## "portal" into an interior, "shop", "job", or "message" for venues whose
## systems arrive in a later phase.
func _venue_table() -> Array:
	return [
		[
			"ApartmentDoor", Vector3(-60.0, 1.2, -12.4), Vector3.BACK, "Enter Apartment",
			"portal", "",
		],
		[
			"MarketDoor", Vector3(-38.0, 1.2, -12.4), Vector3.BACK, "Enter the shop",
			"market", "",
		],
		[
			"DinerDoor", Vector3(20.5, 1.2, -26.4), Vector3.BACK, "Enter Diner",
			"message", "THE GALLEY DINER\nSit-down meals arrive with the restaurant system.",
		],
		[
			# On the north face, so the gate is visible from Main Street rather
			# than hidden round the back of the block.
			"WarehouseGate", Vector3(-58.0, 1.2, 14.4), Vector3.FORWARD, "Start shift",
			"job", "",
		],
		[
			"PrecinctDoor", Vector3(24.5, 1.2, 38.6), Vector3.BACK, "Enter Precinct",
			"message", "PRECINCT HOUSE\nStaffed once the police and wanted systems are in.",
		],
		# Two empty shop units, to let. The message column carries the property id
		# so the door and its interior can find each other.
		[
			"MainStreetUnit", Vector3(-20.0, 1.2, -12.4), Vector3.BACK, "View Property",
			"property", "unit_main_18",
		],
		[
			"QuaysideUnit", Vector3(64.0, 1.2, -12.4), Vector3.BACK, "View Property",
			"property", "unit_quay_40",
		],
		[
			"HarbourAvenueUnit", Vector3(20.0, 1.2, -12.4), Vector3.BACK, "View Property",
			"property", "unit_harbour_42",
		],
		[
			"CentralPlazaUnit", Vector3(42.0, 1.2, -12.4), Vector3.BACK, "View Property",
			"property", "unit_plaza_07",
		],
	]


func _build_venue_doors() -> void:
	for entry in _venue_table():
		var node_name: String = entry[0]
		var point: Vector3 = entry[1]
		var facing: Vector3 = entry[2]
		var prompt: String = entry[3]
		var kind: String = entry[4]
		var message: String = entry[5]

		var door: Interactable
		match kind:
			"portal":
				door = _make_apartment_portal(point, facing)
			"market":
				door = _make_market_portal(point, facing)
			"job":
				door = _make_warehouse_station()
			"property":
				door = _make_commercial_property(point, facing, StringName(message))
				(door as CommercialProperty).sign_yaw = rad_to_deg(
					atan2(facing.x, facing.z)
				)
			_:
				var notice := MessagePoint.new()
				notice.message = message
				door = notice

		door.name = node_name
		door.prompt_action = prompt
		CityKit.attach_interactable(_interactables, door, point, 2.6)

		_add_door_panel(node_name, point, facing)


## The front door of Larkspur Apartments, plus the marker the flat's own door
## sends the player back to.
func _make_apartment_portal(point: Vector3, facing: Vector3) -> ResidenceProperty:
	var street_marker := Marker3D.new()
	street_marker.name = "ApartmentStreetExit"
	street_marker.position = point + facing * 1.6 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(ApartmentInterior.EXIT_GROUP)
	_interactables.add_child(street_marker)

	# The starter flat is a residence whose lease is already signed and which is
	# already home, so nothing has to special-case where the player begins.
	var portal := ResidenceProperty.new()
	portal.residence_id = &"larkspur"
	portal.address = "Larkspur Apartments"
	portal.display_name = "Studio Flat"
	portal.district_id = &"harbour_row"
	portal.size_label = "Studio"
	portal.amenities = "Bed · Wardrobe · Shared entrance"
	portal.rent_amount = 220
	portal.deposit = 200
	portal.leased_by_player = true
	portal.is_home = true
	portal.destination_group = ApartmentInterior.ENTRY_GROUP
	portal.prompt_subtitle = "Larkspur Apartments"
	# Climbing the stairs costs a couple of minutes.
	portal.travel_minutes = 2
	portal.override_camera = true
	portal.camera_distance = INTERIOR_CAMERA_DISTANCE
	portal.camera_pitch = INTERIOR_CAMERA_PITCH
	return portal


## The market is a room now rather than a counter on the pavement. The counter
## moved inside with the shelves, the cashier and the staff-only area, because
## shoplifting needs an inside to walk out of.
func _make_market_portal(point: Vector3, facing: Vector3) -> Portal:
	var street_marker := Marker3D.new()
	street_marker.name = "MarketStreetExit"
	street_marker.position = point + facing * 1.8 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(ConvenienceStoreInterior.EXIT_GROUP)
	_interactables.add_child(street_marker)

	var portal := Portal.new()
	portal.destination_group = ConvenienceStoreInterior.ENTRY_GROUP
	portal.prompt_subtitle = "Harbour Row Market"
	portal.override_camera = true
	portal.camera_distance = 14.0
	portal.camera_pitch = 70.0
	return portal


## An empty shop unit and the pavement outside it. Vacant it shows the letting
## details; once the player holds the lease it is the door to their own shop.
##
## Terms live here rather than in the interior because the unit is a thing on a
## street with an address, and the room behind it is an implementation detail.
func _make_commercial_property(
	point: Vector3, facing: Vector3, id: StringName
) -> CommercialProperty:
	var street_marker := Marker3D.new()
	street_marker.name = "PropertyStreetExit_%s" % id
	street_marker.position = point + facing * 1.8 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(RetailUnit.exit_group_for(id))
	_interactables.add_child(street_marker)

	var unit := CommercialProperty.new()
	unit.property_id = id
	unit.destination_group = RetailUnit.entry_group_for(id)
	unit.override_camera = true
	unit.camera_distance = 16.0
	unit.camera_pitch = 68.0

	# Four units, deliberately unalike. Rent buys floor space and passing trade,
	# and the cheapest pitch is cheap for a reason — which is the whole of the
	# expansion decision until property can be bought outright.
	match id:
		&"unit_quay_40":
			unit.address = "40 Quayside"
			unit.property_type = "Retail Unit"
			unit.size_class = CommercialProperty.SizeClass.SMALL
			unit.floor_area = 44
			unit.rent_amount = 480
			unit.deposit = 400
			unit.customer_capacity = 5
			unit.queue_capacity = 3
			unit.location_demand_modifier = 0.8
		&"unit_harbour_42":
			unit.address = "42 Harbour Avenue"
			unit.property_type = "Retail Unit"
			unit.size_class = CommercialProperty.SizeClass.MEDIUM
			unit.floor_area = 76
			unit.rent_amount = 1100
			unit.deposit = 900
			unit.customer_capacity = 9
			unit.queue_capacity = 6
			unit.location_demand_modifier = 1.1
		&"unit_plaza_07":
			unit.address = "7 Anchor Plaza"
			unit.property_type = "Premium Retail"
			unit.size_class = CommercialProperty.SizeClass.MEDIUM
			unit.floor_area = 84
			unit.rent_amount = 1800
			unit.deposit = 1400
			unit.customer_capacity = 12
			unit.queue_capacity = 7
			unit.location_demand_modifier = 1.3
		_:
			unit.address = "18 Main Street"
			unit.property_type = "Retail Unit"
			unit.size_class = CommercialProperty.SizeClass.SMALL
			unit.floor_area = 48
			unit.rent_amount = 650
			unit.deposit = 500
			unit.customer_capacity = 6
			unit.queue_capacity = 4
			unit.location_demand_modifier = 1.0
	return unit


func _make_warehouse_station() -> JobStation:
	var station := JobStation.new()
	station.job = WAREHOUSE_JOB
	station.prompt_subtitle = "Pierpoint Warehouse"
	return station


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


# --- Streetscape ---------------------------------------------------------

## The small stuff: hedges, overhead lines, bins, hydrants, road repairs and
## driveways.
##
## Nothing here is solid. Every one of these is within a metre or so of the
## pedestrian walking line, and a crowd wedged against a litter bin is a bug the
## player can see — whereas a bin they clip through is something nobody notices
## from this camera. The street lights that already exist are the exception,
## because they were placed before this rule and are far enough back.
func _build_streetscape() -> void:
	var container := _make_container("Streetscape")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("HarbourRowStreetscape")

	_add_park_hedges(container, rng)
	_add_street_trees(container)
	_add_overhead_lines(container)
	_add_street_clutter(container, rng)
	_add_road_repairs(container, rng)
	_add_driveways(container)


## Hedge along the park's two street frontages, broken at the gates so the
## entrances the navigation graph uses are visibly entrances.
func _add_park_hedges(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var gate := 3.0
	# North frontage, onto Main Street's pavement.
	CityKit.add_hedge(
		parent, "ParkHedgeNW",
		Vector2(PARK_BOUNDS.position.x, PARK_BOUNDS.position.y),
		Vector2(PARK_PATH_X - gate, PARK_BOUNDS.position.y),
		1.1, _mat("hedge"), rng
	)
	CityKit.add_hedge(
		parent, "ParkHedgeNE",
		Vector2(PARK_PATH_X + gate, PARK_BOUNDS.position.y),
		Vector2(PARK_BOUNDS.end.x, PARK_BOUNDS.position.y),
		1.1, _mat("hedge"), rng
	)
	# East frontage, onto the boulevard.
	CityKit.add_hedge(
		parent, "ParkHedgeEN",
		Vector2(PARK_BOUNDS.end.x, PARK_BOUNDS.position.y + 1.5),
		Vector2(PARK_BOUNDS.end.x, PARK_PATH_Z - gate),
		1.1, _mat("hedge"), rng
	)
	CityKit.add_hedge(
		parent, "ParkHedgeES",
		Vector2(PARK_BOUNDS.end.x, PARK_PATH_Z + gate),
		Vector2(PARK_BOUNDS.end.x, PARK_BOUNDS.end.y),
		1.1, _mat("hedge"), rng
	)


## Trees along the streets, standing on the lot strip just past the pavement so
## their canopies overhang it without their trunks ever standing in the walking
## line. Spots are listed rather than generated: the strip is interrupted by
## doorways, parking bays and the warehouse gate, and a rule that avoided all of
## them would be longer than the list.
func _add_street_trees(parent: Node3D) -> void:
	# Hard against the pavement edge. The strip further back is the frontage the
	# player walks along to reach the doorways — planting there put a tree across
	# the route to the market, which is exactly the kind of thing that only shows
	# up when something walks it.
	var verge := ROAD_HALF + WALK_WIDTH + 0.9
	var spots := [
		# Main Street, north side.
		Vector2(-66.0, MAIN_ST_Z - verge), Vector2(-54.0, MAIN_ST_Z - verge),
		Vector2(-34.0, MAIN_ST_Z - verge), Vector2(20.0, MAIN_ST_Z - verge),
		Vector2(34.0, MAIN_ST_Z - verge), Vector2(48.0, MAIN_ST_Z - verge),
		Vector2(62.0, MAIN_ST_Z - verge),
		# Main Street, south side.
		Vector2(-20.0, MAIN_ST_Z + verge), Vector2(-9.0, MAIN_ST_Z + verge),
		Vector2(40.0, MAIN_ST_Z + verge), Vector2(52.0, MAIN_ST_Z + verge),
		Vector2(66.0, MAIN_ST_Z + verge),
		# North Avenue, north side only: the buildings come right up to the
		# pavement on the other one.
		Vector2(-60.0, NORTH_AVE_Z - verge), Vector2(-44.0, NORTH_AVE_Z - verge),
		Vector2(-6.0, NORTH_AVE_Z - verge), Vector2(30.0, NORTH_AVE_Z - verge),
		Vector2(46.0, NORTH_AVE_Z - verge), Vector2(62.0, NORTH_AVE_Z - verge),
		# Center Boulevard, both sides.
		Vector2(CENTER_BLVD_X - verge, -32.0), Vector2(CENTER_BLVD_X - verge, -20.0),
		Vector2(CENTER_BLVD_X - verge, 24.0), Vector2(CENTER_BLVD_X - verge, 46.0),
		Vector2(CENTER_BLVD_X - verge, 64.0),
		Vector2(CENTER_BLVD_X + verge, -30.0), Vector2(CENTER_BLVD_X + verge, -18.0),
		Vector2(CENTER_BLVD_X + verge, 44.0), Vector2(CENTER_BLVD_X + verge, 62.0),
	]
	# A square of lawn under each one. Trees standing on bare concrete was the
	# last thing that read as "props placed on a plan" rather than as planting;
	# a patch per tree rather than a continuous verge keeps it clear of the
	# doorways and parking bays that interrupt the strip.
	var patch := 1.5
	for i in spots.size():
		var spot: Vector2 = spots[i]
		CityKit.add_slab(
			parent,
			"TreeLawn%d" % i,
			CityKit.rect_from_bounds(spot.x - patch, spot.y - patch, spot.x + patch, spot.y + patch),
			GRASS_BASE,
			GRASS_THICKNESS,
			_mat("grass"),
			false,
			false
		)
		_add_tree(parent, "StreetTree%d" % i, spot, 0.9, false)


## Timber poles and strung cable down both long streets, set back onto the lots
## so they are clear of the pavement entirely.
func _add_overhead_lines(parent: Node3D) -> void:
	# Street-light height, and no taller. A tall pole close to the camera splays
	# hard toward the corner of the frame at this field of view, and a thick one
	# with a long crossarm read as fallen timber lying across the pavement. The
	# street lights have always had the same perspective and never looked wrong,
	# because they are thin — so the poles match them.
	var pole_height := 6.2
	# Behind the tree line, or the canopies swallow the poles.
	var setback := ROAD_HALF + WALK_WIDTH + 2.4
	var spacing := 32.0
	var reach := EXTENT - 8.0
	var count := int(reach * 2.0 / spacing)
	var runs := [
		# [fixed coordinate, does the run go along X?]
		[MAIN_ST_Z + setback, true],
		[NORTH_AVE_Z - setback, true],
		[CENTER_BLVD_X + setback, false],
	]
	for run_index in runs.size():
		var fixed: float = runs[run_index][0]
		var along_x: bool = runs[run_index][1]
		var previous := Vector3.ZERO
		var have_previous := false
		for i in count + 1:
			var travel := -reach + float(i) * spacing
			var base := (
				Vector3(travel, 0.0, fixed) if along_x else Vector3(fixed, 0.0, travel)
			)
			# Skip the junction mouths, where a pole would stand in the crossing.
			if absf(base.x) < ROAD_HALF + WALK_WIDTH + 2.0 and along_x:
				have_previous = false
				continue
			if not along_x and (
				absf(base.z - MAIN_ST_Z) < ROAD_HALF + WALK_WIDTH + 2.0
				or absf(base.z - NORTH_AVE_Z) < ROAD_HALF + WALK_WIDTH + 2.0
			):
				have_previous = false
				continue

			var holder := Node3D.new()
			holder.name = "Pole%d_%d" % [run_index, i]
			holder.position = base
			parent.add_child(holder)
			CityKit.add_cylinder(
				holder, "Post", Vector3(0.0, pole_height * 0.5, 0.0),
				0.1, pole_height, _mat("wood"), false
			)
			CityKit.add_box(
				holder, "CrossArm", Vector3(0.0, pole_height - 0.45, 0.0),
				Vector3(1.3 if along_x else 0.11, 0.09, 0.11 if along_x else 1.3),
				_mat("wood"), false, false
			)

			var top := base + Vector3(0.0, pole_height - 0.5, 0.0)
			if have_previous:
				CityKit.add_wire(
					parent, "Wire%d_%d" % [run_index, i], previous, top,
					1.1, 0.05, _mat("metal")
				)
			previous = top
			have_previous = true


## Bins, hydrants and post boxes along the kerb line, in the gap between the
## kerb and the walking line.
func _add_street_clutter(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var band := ROAD_HALF + 1.05
	var spots: Array = []
	for road_z in [MAIN_ST_Z, NORTH_AVE_Z]:
		for x in [-64.0, -37.0, -19.0, 21.0, 44.0, 63.0]:
			spots.append(Vector3(x, 0.0, road_z - band))
			spots.append(Vector3(x + 9.0, 0.0, road_z + band))
	for z in [-70.0, -33.0, 22.0, 52.0, 74.0]:
		spots.append(Vector3(CENTER_BLVD_X - band, 0.0, z))
		spots.append(Vector3(CENTER_BLVD_X + band, 0.0, z + 7.0))

	for i in spots.size():
		var spot: Vector3 = spots[i]
		if absf(spot.x) > EXTENT - 4.0 or absf(spot.z) > EXTENT - 4.0:
			continue
		match i % 3:
			0:
				_add_litter_bin(parent, "Bin%d" % i, spot, rng)
			1:
				_add_hydrant(parent, "Hydrant%d" % i, spot)
			_:
				_add_post_box(parent, "PostBox%d" % i, spot)


func _add_litter_bin(
	parent: Node3D, node_name: String, spot: Vector3, rng: RandomNumberGenerator
) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot + Vector3(0.0, CURB_HEIGHT, 0.0)
	holder.rotation.y = rng.randf_range(0.0, TAU)
	parent.add_child(holder)
	CityKit.add_cylinder(
		holder, "Body", Vector3(0.0, 0.42, 0.0), 0.3, 0.84, _mat("metal"), false
	)
	CityKit.add_cylinder(
		holder, "Lid", Vector3(0.0, 0.9, 0.0), 0.33, 0.1, _mat("plinth"), false
	)


func _add_hydrant(parent: Node3D, node_name: String, spot: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot + Vector3(0.0, CURB_HEIGHT, 0.0)
	parent.add_child(holder)
	var paint := CityKit.make_material(Color(0.671, 0.161, 0.129), 0.6)
	CityKit.add_cylinder(holder, "Barrel", Vector3(0.0, 0.34, 0.0), 0.14, 0.68, paint, false)
	CityKit.add_sphere(holder, "Cap", Vector3(0.0, 0.72, 0.0), Vector3(0.3, 0.22, 0.3), paint)
	CityKit.add_box(
		holder, "Arms", Vector3(0.0, 0.5, 0.0), Vector3(0.52, 0.11, 0.11), paint, false, false
	)


func _add_post_box(parent: Node3D, node_name: String, spot: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = spot + Vector3(0.0, CURB_HEIGHT, 0.0)
	parent.add_child(holder)
	var paint := CityKit.make_material(Color(0.176, 0.267, 0.408), 0.55)
	CityKit.add_box(holder, "Box", Vector3(0.0, 0.72, 0.0), Vector3(0.5, 0.62, 0.4), paint, false)
	CityKit.add_cylinder(holder, "Leg", Vector3(0.0, 0.2, 0.0), 0.08, 0.4, _mat("metal"), false)


## Patched-over repairs in the carriageway. A road with no history on it is the
## last thing that reads as painted-on from above.
func _add_road_repairs(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var patch := CityKit.make_surface(
		Color(0.180, 0.180, 0.192), 0.82, 2.0, 1.0, 0.2, 0.0, 40
	)
	var lanes := [
		Vector3(-52.0, 0.0, MAIN_ST_Z - 3.0), Vector3(-18.0, 0.0, MAIN_ST_Z + 3.4),
		Vector3(34.0, 0.0, MAIN_ST_Z - 2.6), Vector3(58.0, 0.0, MAIN_ST_Z + 2.8),
		Vector3(-29.0, 0.0, NORTH_AVE_Z + 3.2), Vector3(41.0, 0.0, NORTH_AVE_Z - 3.0),
		Vector3(CENTER_BLVD_X - 2.8, 0.0, 27.0), Vector3(CENTER_BLVD_X + 3.0, 0.0, -68.0),
		Vector3(CENTER_BLVD_X - 3.2, 0.0, 61.0),
	]
	for i in lanes.size():
		var spot: Vector3 = lanes[i]
		var size := Vector2(rng.randf_range(2.2, 4.6), rng.randf_range(1.6, 3.2))
		CityKit.add_slab(
			parent,
			"RoadPatch%d" % i,
			Rect2(spot.x - size.x * 0.5, spot.z - size.y * 0.5, size.x, size.y),
			MARKING_BASE - 0.008,
			0.01,
			patch,
			false,
			false
		)


## Aprons where a vehicle crossing leaves the carriageway. They are what stops
## the parking bays and the yard gate looking like cars simply drove over a kerb.
func _add_driveways(parent: Node3D) -> void:
	var apron := ROAD_HALF + WALK_WIDTH
	var crossings := [
		# [centre along the street, road coordinate, along X?, width]
		[15.0, MAIN_ST_Z + apron, true, 7.0],     # civic lot / precinct side
		[-58.0, MAIN_ST_Z + apron, true, 9.0],    # warehouse yard gate
		[-36.0, MAIN_ST_Z - apron, true, 6.0],    # market service door
		[15.0, NORTH_AVE_Z - apron, true, 8.0],   # car park entrance
		[-30.0, NORTH_AVE_Z + apron, true, 6.0],
	]
	for i in crossings.size():
		var entry: Array = crossings[i]
		var centre: float = entry[0]
		var edge: float = entry[1]
		var width: float = entry[3]
		var near := minf(edge, edge - signf(edge) * WALK_WIDTH)
		var far := maxf(edge, edge - signf(edge) * WALK_WIDTH)
		CityKit.add_slab(
			parent,
			"Driveway%d" % i,
			CityKit.rect_from_bounds(centre - width * 0.5, near, centre + width * 0.5, far),
			CURB_HEIGHT + KERB_LIFT + 0.001,
			0.012,
			_mat("gravel"),
			false,
			false
		)


# --- Navigation ----------------------------------------------------------

## The pavement and road networks, sampled from the same street centre lines the
## district is drawn from. Pavement lines run the full width including the
## junctions, because the crossings there are painted crosswalks — so a
## pedestrian route over a carriageway is always a legal crossing.
func _build_nav_graph() -> void:
	var nav: NavGraph = NAV_GRAPH_SCRIPT.new()
	nav.name = "NavGraph"
	add_child(nav)

	var reach := EXTENT - 3.0
	var walk_offset := PAVEMENT_OFFSET
	var walk_lines := [
		[Vector2(-reach, MAIN_ST_Z - walk_offset), Vector2(reach, MAIN_ST_Z - walk_offset)],
		[Vector2(-reach, MAIN_ST_Z + walk_offset), Vector2(reach, MAIN_ST_Z + walk_offset)],
		[Vector2(-reach, NORTH_AVE_Z - walk_offset), Vector2(reach, NORTH_AVE_Z - walk_offset)],
		[Vector2(-reach, NORTH_AVE_Z + walk_offset), Vector2(reach, NORTH_AVE_Z + walk_offset)],
		[Vector2(CENTER_BLVD_X - walk_offset, -reach), Vector2(CENTER_BLVD_X - walk_offset, reach)],
		[Vector2(CENTER_BLVD_X + walk_offset, -reach), Vector2(CENTER_BLVD_X + walk_offset, reach)],
	]
	# The park's own paths, plus the two entrances that join them to the street
	# network. Without these the park is a hole in the graph: an officer sent to
	# the fountain routed to the nearest pavement node and stopped there, and a
	# pedestrian could never choose anywhere inside the park to walk to.
	var ring_north := PARK_PATH_Z - FOUNTAIN_RING
	var ring_south := PARK_PATH_Z + FOUNTAIN_RING
	var ring_west := PARK_PATH_X - FOUNTAIN_RING
	var ring_east := PARK_PATH_X + FOUNTAIN_RING
	walk_lines.append_array([
		# The two paths, each stopping at the fountain plaza...
		[Vector2(PARK_PATH_X, PARK_BOUNDS.position.y), Vector2(PARK_PATH_X, ring_north)],
		[Vector2(PARK_PATH_X, ring_south), Vector2(PARK_PATH_X, PARK_BOUNDS.end.y)],
		[Vector2(PARK_BOUNDS.position.x, PARK_PATH_Z), Vector2(ring_west, PARK_PATH_Z)],
		[Vector2(ring_east, PARK_PATH_Z), Vector2(PARK_BOUNDS.end.x, PARK_PATH_Z)],
		# ...and a square round the basin joining the four stubs back up.
		[Vector2(ring_west, ring_north), Vector2(ring_east, ring_north)],
		[Vector2(ring_west, ring_south), Vector2(ring_east, ring_south)],
		[Vector2(ring_west, ring_north), Vector2(ring_west, ring_south)],
		[Vector2(ring_east, ring_north), Vector2(ring_east, ring_south)],
		# North gate, onto Main Street's south pavement.
		[
			Vector2(PARK_PATH_X, PARK_BOUNDS.position.y),
			Vector2(PARK_PATH_X, MAIN_ST_Z + walk_offset),
		],
		# East gate, onto Center Boulevard's west pavement.
		[
			Vector2(PARK_BOUNDS.end.x, PARK_PATH_Z),
			Vector2(CENTER_BLVD_X - walk_offset, PARK_PATH_Z),
		],
	])
	# Road routing uses centre lines. Lane discipline is not worth the
	# complexity while the only AI drivers are police in a hurry.
	var road_lines := [
		[Vector2(-reach, MAIN_ST_Z), Vector2(reach, MAIN_ST_Z)],
		[Vector2(-reach, NORTH_AVE_Z), Vector2(reach, NORTH_AVE_Z)],
		[Vector2(CENTER_BLVD_X, -reach), Vector2(CENTER_BLVD_X, reach)],
	]
	nav.build(walk_lines, road_lines)
	_nav = nav


# --- Traffic -------------------------------------------------------------

## The lane network, the signals and the population manager.
##
## Lanes are described once, as directed strands down the middle of each one,
## and everything else — which way a car may turn at a junction, where it is
## legal to spawn, which route it takes — falls out of that. Right-hand traffic:
## a driver's own lane is the one to the right of the centre line.
func _build_traffic() -> void:
	var container := _make_container("Traffic")
	var reach := EXTENT - 3.0

	var network: RoadNetwork = ROAD_NETWORK_SCRIPT.new()
	network.name = "RoadNetwork"
	container.add_child(network)
	network.build([
		# Main Street.
		[Vector2(-reach, MAIN_ST_Z + LANE_OFFSET), Vector2(reach, MAIN_ST_Z + LANE_OFFSET)],
		[Vector2(reach, MAIN_ST_Z - LANE_OFFSET), Vector2(-reach, MAIN_ST_Z - LANE_OFFSET)],
		# North Avenue.
		[Vector2(-reach, NORTH_AVE_Z + LANE_OFFSET), Vector2(reach, NORTH_AVE_Z + LANE_OFFSET)],
		[Vector2(reach, NORTH_AVE_Z - LANE_OFFSET), Vector2(-reach, NORTH_AVE_Z - LANE_OFFSET)],
		# Center Boulevard. Northbound is -Z, so it runs from the south edge up.
		[
			Vector2(CENTER_BLVD_X + LANE_OFFSET, reach),
			Vector2(CENTER_BLVD_X + LANE_OFFSET, -reach),
		],
		[
			Vector2(CENTER_BLVD_X - LANE_OFFSET, -reach),
			Vector2(CENTER_BLVD_X - LANE_OFFSET, reach),
		],
	])

	# One signal per junction. The two are deliberately out of phase so the
	# district never turns green all at once, and so a car let through one
	# junction usually meets a red at the next — which is what makes the street
	# look busy rather than synchronised.
	var junctions := [
		["MainStreetSignal", Vector3(CENTER_BLVD_X, 0.0, MAIN_ST_Z), TrafficLight.Phase.EW_GREEN, 0.0],
		["NorthAvenueSignal", Vector3(CENTER_BLVD_X, 0.0, NORTH_AVE_Z), TrafficLight.Phase.NS_GREEN, 5.0],
	]
	for entry in junctions:
		var light: TrafficLight = TRAFFIC_LIGHT_SCRIPT.new()
		light.name = entry[0]
		light.position = entry[1]
		light.start_phase = entry[2]
		light.start_offset_seconds = entry[3]
		light.stop_line_distance = STOP_LINE_OFFSET
		container.add_child(light)

	var manager: TrafficManager = TRAFFIC_MANAGER_SCRIPT.new()
	manager.name = "TrafficManager"
	container.add_child(manager)
	# Filled before the first frame, so the player never watches the streets
	# populate themselves.
	manager.prime()


# --- People --------------------------------------------------------------

func _build_pedestrians() -> void:
	var container := _make_container("Pedestrians")
	# Anything that creates a civilian mid-game — a carjacking victim, for now —
	# looks this group up rather than parenting people to whatever spawned them.
	container.add_to_group(&"crowd")
	# Seeded so a run is reproducible and a failing test can be re-run.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("HarbourRowCrowd")

	var palette := [
		Color(0.549, 0.396, 0.353), Color(0.400, 0.451, 0.510),
		Color(0.427, 0.475, 0.400), Color(0.596, 0.545, 0.427),
		Color(0.478, 0.404, 0.494), Color(0.353, 0.478, 0.494),
	]

	for i in PEDESTRIAN_COUNT:
		var walker: Pedestrian = PEDESTRIAN_SCENE.instantiate()
		walker.name = "Pedestrian%d" % i
		walker.body_color = palette[i % palette.size()]
		walker.walk_speed = rng.randf_range(2.0, 2.9)
		var spot := _nav.random_point(NavGraph.Layer.WALK, rng)
		walker.position = spot + Vector3.UP * 0.4
		container.add_child(walker)


## Officers on foot at the three places a player is most likely to be seen, and
## two patrol cars at the precinct. Cars do the chasing once the player is in a
## vehicle; an officer on foot can never catch a car.
func _build_police() -> void:
	var container := _make_container("Police")

	var posts := [
		["PrecinctOfficer", Vector3(20.0, 0.4, 9.5)],
		["MainStreetOfficer", Vector3(-16.0, 0.4, 7.5)],
		# On the park path south of the fountain — the old post was the fountain's
		# own position, which stood the officer inside the basin.
		["ParkOfficer", Vector3(PARK_PATH_X, 0.4, PARK_PATH_Z + 8.0)],
	]
	for post in posts:
		var officer: PoliceOfficer = POLICE_OFFICER_SCENE.instantiate()
		officer.name = post[0]
		officer.position = post[1]
		officer.post_position = post[1]
		container.add_child(officer)

	var car_spots := [
		["PatrolCarA", Vector3(14.0, 0.0, 3.0), -90.0],
		["PatrolCarB", Vector3(24.0, 0.0, 3.0), -90.0],
	]
	for spot in car_spots:
		var car: Vehicle = POLICE_CAR_SCENE.instantiate()
		car.name = spot[0]
		car.position = spot[1]
		car.rotation_degrees.y = spot[2]
		container.add_child(car)

	# Where an arrested player is released. Outside the precinct door, on the
	# open ground the door already faces.
	var release := Marker3D.new()
	release.name = "PrecinctRelease"
	release.position = Vector3(24.5, 0.4, 41.5)
	release.add_to_group(&"bust_release_point")
	container.add_child(release)


# --- Parked vehicles -----------------------------------------------------

## Where the district's cars start. Each entry: node name, save id, position on
## the ground plane, heading in degrees, owner type, owner id, body colour.
##
## Yaw 90 faces west, -90 faces east, 180 faces south. Every spot is on the
## carriageway or in a marked bay, clear of doorways, crosswalks, the junctions
## and the sidewalk interaction points.
func _vehicle_table() -> Array:
	return [
		[
			"PlayerSedan", &"vehicle_player_sedan", Vector2(-56.0, -PARKING_OFFSET), 90.0,
			Vehicle.OwnerType.PLAYER, &"player", Color(0.243, 0.376, 0.494),
		],
		# Main Street kerbside bays, between the flat and the market.
		[
			"NpcSedanMarket", &"vehicle_npc_market", Vector2(-43.0, -PARKING_OFFSET), 90.0,
			Vehicle.OwnerType.NPC, &"npc_market", Color(0.639, 0.612, 0.529),
		],
		[
			"NpcSedanMain", &"vehicle_npc_main", Vector2(-32.0, -PARKING_OFFSET), 90.0,
			Vehicle.OwnerType.NPC, &"npc_main", Color(0.400, 0.451, 0.376),
		],
		[
			"NpcSedanBlvd", &"vehicle_npc_blvd", Vector2(-21.0, -PARKING_OFFSET), 90.0,
			Vehicle.OwnerType.NPC, &"npc_blvd", Color(0.541, 0.259, 0.243),
		],
		# South kerb of Main Street, across from the warehouse gate.
		[
			"NpcSedanWarehouse", &"vehicle_npc_warehouse", Vector2(-60.0, PARKING_OFFSET), -90.0,
			Vehicle.OwnerType.NPC, &"npc_warehouse", Color(0.298, 0.310, 0.345),
		],
		# Civic hall car park, north of North Avenue.
		[
			"NpcSedanLotA", &"vehicle_npc_lot_a", Vector2(12.3, -73.0), 180.0,
			Vehicle.OwnerType.NPC, &"npc_lot_a", Color(0.647, 0.522, 0.310),
		],
		[
			"NpcSedanLotB", &"vehicle_npc_lot_b", Vector2(17.7, -73.0), 180.0,
			Vehicle.OwnerType.NPC, &"npc_lot_b", Color(0.208, 0.286, 0.322),
		],
		# North Avenue kerbside.
		[
			"NpcSedanNorth", &"vehicle_npc_north", Vector2(30.0, NORTH_AVE_Z + PARKING_OFFSET), -90.0,
			Vehicle.OwnerType.NPC, &"npc_north", Color(0.475, 0.404, 0.478),
		],
	]


func _build_vehicles() -> void:
	var container := _make_container("Vehicles")

	for entry in _vehicle_table():
		var car: Vehicle = SEDAN_SCENE.instantiate()
		car.name = entry[0]
		car.save_id = entry[1]
		car.owner_type = entry[4]
		car.owner_id = entry[5]

		# One VehicleData per model is shared, so recolouring an individual car
		# needs its own copy. Everything else still comes from the shared model.
		var tinted: VehicleData = car.data.duplicate()
		tinted.body_color = entry[6]
		car.data = tinted

		var spot: Vector2 = entry[2]
		car.position = Vector3(spot.x, 0.0, spot.y)
		car.rotation_degrees.y = entry[3]
		container.add_child(car)


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
		+ "WASD move  ·  SHIFT sprint  ·  E interact  ·  TAB bag\n"
		+ "Q / ARROWS or RIGHT-DRAG orbit  ·  WHEEL zoom  ·  ESC pause\n"
		+ "Sleep at home, work the warehouse gate, eat from the market."
	)
	CityKit.attach_interactable(
		_interactables, notice, holder.position + Vector3(0.0, 1.1, 0.9), 2.2
	)
