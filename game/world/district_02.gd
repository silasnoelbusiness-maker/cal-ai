class_name District02
extends Node3D
## Builds "Central District", the denser half of the city.
##
## Same construction as Harbour Row — layout tables and CityKit primitives — but
## a different place: a tight grid of three streets each way, buildings twice the
## height with the setbacks halved, a pedestrian plaza in the middle of it and
## service roads round the back. Where Harbour Row has a park and a warehouse,
## this has offices and shopfronts.
##
## It shares one coordinate space with Harbour Row and extends the same nav graph
## and road network rather than building its own, so a route, a car or a police
## chase crosses the boundary without anything happening at the line.

const ROAD_HALF := 6.0
const WALK_WIDTH := 3.5
const LANE_OFFSET := 3.0
const CURB_HEIGHT := CityKit.CURB_HEIGHT
const STOP_LINE_OFFSET := 8.5

## Surface heights, kept apart from each other so nothing z-fights. The same
## ladder Harbour Row uses.
const ROAD_BASE := 0.005
const ROAD_THICKNESS := 0.02
const MARKING_BASE := 0.026
const MARKING_THICKNESS := 0.012
const PLAZA_BASE := 0.02

## The district's own patch of the world.
const BOUNDS := Rect2(-110.0, -330.0, 220.0, 200.0)
## Half-width of the driveable strip the connecting boulevard runs down. Wide
## enough for the carriageway, its verges and the gap in Harbour Row's north
## wall, and no wider: the land either side of it is undeveloped and walled off,
## not a hole. The ground carries on under it — a void beside a road the player
## drives at speed looks like a bug whether or not they can reach it.
const CORRIDOR_HALF := 15.0

## Where the connecting boulevard enters from Harbour Row.
const GATEWAY_Z := -130.0

# Street centre lines. Three each way: a proper grid rather than a crossroads.
const MARKET_ST_Z := -160.0
const KINGSTON_RD_Z := -215.0
const RIVERSIDE_DR_Z := -270.0
const CENTER_BLVD_X := 0.0
const PLAZA_ST_X := -60.0
const EXCHANGE_ST_X := 60.0

## The service roads behind the blocks — narrow, unsignalled, and the reason a
## chase in Central is not simply a straight line.
const SERVICE_HALF := 3.2
const SERVICE_WEST_X := -90.0
const SERVICE_EAST_X := 90.0

## Central Plaza: pedestrians only, bollarded, with the monument in the middle.
const PLAZA := Rect2(-45.0, -205.0, 30.0, 30.0)
const MONUMENT := Vector3(-30.0, 0.0, -190.0)

const WINDOW_GLOW := Color(0.976, 0.831, 0.545)
const LAMP_GLOW := Color(1.0, 0.878, 0.678)
const WINDOW_NIGHT_ENERGY := 0.9

const PEDESTRIAN_SCENE: PackedScene = preload("res://npc/pedestrian.tscn")
const POLICE_OFFICER_SCENE: PackedScene = preload("res://npc/police_officer.tscn")

## Denser than Harbour Row, which is the whole point of the place.
const PEDESTRIAN_COUNT := 30

var _palette: Dictionary = {}
var _geometry: Node3D = null
var _interactables: Node3D = null
var _window_materials: Array[StandardMaterial3D] = []
var _lamp_materials: Array[StandardMaterial3D] = []
var _district: DistrictData = null


func _ready() -> void:
	add_to_group(&"district")
	_register_district()
	_build_palette()

	_geometry = _make_container("Geometry")
	_interactables = _make_container("Interactables")

	_build_ground()
	_build_roads()
	_build_pavements()
	_build_blocks()
	_build_plaza()
	_build_street_furniture()
	_build_venue_doors()
	_extend_navigation()
	_build_traffic_signals()
	_build_pedestrians()
	_build_police_post()
	_build_parking()
	_build_parked_cars()
	_build_boundary()

	TimeManager.minute_passed.connect(_on_minute_passed)
	_refresh_night_lighting()


## What this place is like, for everything that asks WorldManager rather than
## looking at coordinates itself.
func _register_district() -> void:
	_district = DistrictData.make(
		&"central", "Central District", BOUNDS, "Offices, shops and no parking"
	)
	_district.traffic_density = 1.5
	_district.pedestrian_density = 1.6
	_district.commercial_demand_modifier = 1.25
	_district.commercial_rent_modifier = 1.6
	_district.residential_rent_modifier = 1.5
	_district.police_presence = 1.3
	WorldManager.register(_district)


func get_district() -> DistrictData:
	return _district


func _make_container(container_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = container_name
	add_child(node)
	return node


func _mat(key: String) -> StandardMaterial3D:
	return _palette[key]


func _build_palette() -> void:
	_palette = {
		"ground": CityKit.make_surface(Color(0.286, 0.294, 0.306), 0.6),
		"asphalt": CityKit.make_surface(Color(0.176, 0.180, 0.196), 0.9),
		"paving": CityKit.make_surface(Color(0.612, 0.608, 0.596), 0.7),
		"plaza": CityKit.make_surface(Color(0.678, 0.659, 0.620), 0.8),
		"marking": CityKit.make_material(Color(0.878, 0.878, 0.855)),
		"kerb": CityKit.make_material(Color(0.545, 0.545, 0.537)),
		"glass": CityKit.make_material(Color(0.243, 0.290, 0.337), 0.25, 0.4),
		"concrete": CityKit.make_surface(Color(0.588, 0.592, 0.600), 0.55),
		"pale": CityKit.make_surface(Color(0.706, 0.694, 0.663), 0.55),
		"brick": CityKit.make_surface(Color(0.451, 0.310, 0.267), 0.6),
		"slate": CityKit.make_surface(Color(0.310, 0.322, 0.353), 0.6),
		"trim": CityKit.make_material(Color(0.208, 0.216, 0.235)),
		"stone": CityKit.make_material(Color(0.639, 0.627, 0.596)),
		"water": CityKit.make_material(Color(0.310, 0.478, 0.545), 0.25, 0.1),
		"metal": CityKit.make_material(Color(0.400, 0.412, 0.435), 0.45, 0.5),
		"door": CityKit.make_material(Color(0.235, 0.188, 0.157)),
		"scrub": CityKit.make_surface(Color(0.290, 0.353, 0.239), 0.95, 4.0, 1.6, 0.30, 0.0, 4),
		"trunk": CityKit.make_material(Color(0.361, 0.278, 0.204)),
	}


# --- Ground and streets --------------------------------------------------

## The district's ground, carried south far enough to meet Harbour Row's.
##
## It stops exactly where Harbour Row's begins rather than short of it: the gap
## between them was where the connecting road runs, and anything driving between
## the districts fell through it — which is what the traffic test caught. Edge to
## edge rather than overlapping, because two coplanar ground planes fighting for
## depth is the striped mess this project has already had once.
func _build_ground() -> void:
	CityKit.add_slab(
		_geometry, "Ground",
		CityKit.rect_from_bounds(
			BOUNDS.position.x - 8.0, BOUNDS.position.y - 8.0,
			BOUNDS.end.x + 8.0, -District01.GROUND_EXTENT
		),
		-1.0, 1.0, _mat("ground")
	)


func street_lines() -> Array:
	# [is east-west, centre, from, to, half width]
	return [
		[true, MARKET_ST_Z, BOUNDS.position.x, BOUNDS.end.x, ROAD_HALF],
		[true, KINGSTON_RD_Z, BOUNDS.position.x, BOUNDS.end.x, ROAD_HALF],
		[true, RIVERSIDE_DR_Z, BOUNDS.position.x, BOUNDS.end.x, ROAD_HALF],
		[false, CENTER_BLVD_X, BOUNDS.position.y, GATEWAY_Z + 2.0, ROAD_HALF],
		[false, PLAZA_ST_X, BOUNDS.position.y, MARKET_ST_Z, ROAD_HALF],
		[false, EXCHANGE_ST_X, BOUNDS.position.y, MARKET_ST_Z, ROAD_HALF],
		[false, SERVICE_WEST_X, RIVERSIDE_DR_Z, MARKET_ST_Z, SERVICE_HALF],
		[false, SERVICE_EAST_X, RIVERSIDE_DR_Z, MARKET_ST_Z, SERVICE_HALF],
	]


func _build_roads() -> void:
	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from: float = entry[2]
		var to: float = entry[3]
		var half: float = entry[4]
		var rect := (
			CityKit.rect_from_bounds(from, centre - half, to, centre + half) if east_west
			else CityKit.rect_from_bounds(centre - half, from, centre + half, to)
		)
		CityKit.add_slab(
			_geometry, "Road_%s_%d" % ["EW" if east_west else "NS", int(centre)],
			rect, ROAD_BASE, ROAD_THICKNESS, _mat("asphalt"), false, false
		)
		if half > SERVICE_HALF:
			_paint_centre_line(east_west, centre, from, to)

	# The connector down to Harbour Row: the same carriageway, carrying on south
	# past the district boundary until it meets the old perimeter.
	CityKit.add_slab(
		_geometry, "GatewayRoad",
		CityKit.rect_from_bounds(
			CENTER_BLVD_X - ROAD_HALF, GATEWAY_Z, CENTER_BLVD_X + ROAD_HALF, -86.0
		),
		ROAD_BASE, ROAD_THICKNESS, _mat("asphalt"), false, false
	)
	_paint_centre_line(false, CENTER_BLVD_X, GATEWAY_Z, -88.0)


## Dashes down the middle, skipped across the junctions so the box stays clear.
func _paint_centre_line(east_west: bool, centre: float, from: float, to: float) -> void:
	var step := 8.0
	var dash := 4.0
	var crossings := (
		[CENTER_BLVD_X, PLAZA_ST_X, EXCHANGE_ST_X] if east_west
		else [MARKET_ST_Z, KINGSTON_RD_Z, RIVERSIDE_DR_Z]
	)
	var start := minf(from, to)
	var end := maxf(from, to)
	var at := start
	var index := 0
	while at < end:
		var finish := minf(at + dash, end)
		var middle := (at + finish) * 0.5
		var clear := true
		for crossing in crossings:
			if absf(middle - float(crossing)) < ROAD_HALF + 2.0:
				clear = false
		if clear:
			var rect := (
				CityKit.rect_from_bounds(at, centre - 0.16, finish, centre + 0.16) if east_west
				else CityKit.rect_from_bounds(centre - 0.16, at, centre + 0.16, finish)
			)
			CityKit.add_slab(
				_geometry, "Dash_%s_%d_%d" % ["EW" if east_west else "NS", int(centre), index],
				rect, MARKING_BASE, MARKING_THICKNESS, _mat("marking"), false, false
			)
		at += step
		index += 1


## Wide pavements on every street, which is most of what makes the place read as
## a city centre rather than a road with buildings beside it.
func _build_pavements() -> void:
	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from: float = entry[2]
		var to: float = entry[3]
		var half: float = entry[4]
		if half <= SERVICE_HALF:
			continue
		for side: float in [-1.0, 1.0]:
			var near: float = centre + side * half
			var far: float = centre + side * (half + WALK_WIDTH)
			var rect := (
				CityKit.rect_from_bounds(from, minf(near, far), to, maxf(near, far)) if east_west
				else CityKit.rect_from_bounds(minf(near, far), from, maxf(near, far), to)
			)
			CityKit.add_slab(
				_geometry, "Walk_%s_%d_%d" % [
					"EW" if east_west else "NS", int(centre), int(side)
				],
				rect, 0.0, CURB_HEIGHT, _mat("paving"), true, false, 1 << 5
			)


# --- Blocks --------------------------------------------------------------

## Each entry: name, [min_x, min_z, max_x, max_z], height, wall material, style.
##
## Taller and tighter than Harbour Row: the setbacks are half as deep and the
## heights run to twenty-two metres, so the streets read as canyons from the
## elevated camera instead of as open ground with boxes on it.
func _block_table() -> Array:
	return [
		# North row, between Riverside Drive and the district's north edge.
		["MeridianTower", [-105.0, -320.0, -72.0, -281.0], 22.0, "glass", "tower"],
		["ExchangeHouse", [-48.0, -320.0, -12.0, -281.0], 18.0, "concrete", "office"],
		["NorthgateOffices", [12.0, -320.0, 48.0, -281.0], 16.0, "slate", "office"],
		["RiversideChambers", [72.0, -320.0, 105.0, -281.0], 19.0, "pale", "office"],
		# Between Riverside Drive and Kingston Road. The outer blocks of this row
		# and the next stop short of the service roads at x = +/-90: a building
		# laid across a lane is a hole for anything driving it, which is exactly
		# what the traffic test caught the first time this table was written.
		["KingstonOffices", [-83.0, -258.0, -66.0, -226.0], 15.0, "pale", "office"],
		["CentralArcade", [-48.0, -258.0, -12.0, -226.0], 12.0, "brick", "shopfront"],
		["PlazaEast", [12.0, -258.0, 48.0, -226.0], 17.0, "glass", "tower"],
		["MarketTerrace", [66.0, -258.0, 83.0, -226.0], 13.0, "brick", "shopfront"],
		# Between Kingston Road and Market Street. The middle of this row is
		# Central Plaza, so there is nothing built between the two ends of it.
		["PlazaWest", [-83.0, -203.0, -66.0, -171.0], 14.0, "brick", "shopfront"],
		["MarketEast", [12.0, -203.0, 48.0, -171.0], 16.0, "concrete", "shopfront"],
		["MarketFar", [66.0, -203.0, 83.0, -171.0], 11.0, "pale", "shopfront"],
		# South row, facing Harbour Row across the gateway.
		["CentralResidences", [-105.0, -152.0, -12.0, -138.0], 19.0, "brick", "office"],
		["SouthgateOffices", [12.0, -152.0, 105.0, -138.0], 14.0, "concrete", "office"],
	]


func _build_blocks() -> void:
	var container := _make_container("Blocks")
	for entry in _block_table():
		var block_name: String = entry[0]
		var bounds: Array = entry[1]
		var height: float = entry[2]
		var material_key: String = entry[3]
		var style: String = entry[4]
		var rect := CityKit.rect_from_bounds(bounds[0], bounds[1], bounds[2], bounds[3])

		CityKit.add_slab(container, block_name, rect, 0.0, height, _mat(material_key))
		# A parapet, so a flat roof has an edge to it from above.
		CityKit.add_slab(
			container, block_name + "Parapet", rect.grow(0.35), height, 0.7, _mat("trim"), false
		)
		_add_window_bands(container, block_name, rect, height)
		if style == "shopfront":
			_add_shopfronts(container, block_name, rect)
		elif style == "tower":
			# A setback upper storey: the cheapest way to make a tower read as a
			# tower rather than as a taller box.
			CityKit.add_slab(
				container, block_name + "Crown", rect.grow(-6.0), height, height * 0.28,
				_mat(material_key)
			)


## Lit bands up each face. One material per building, so the whole district's
## windows come on together at dusk for the cost of a handful of writes.
func _add_window_bands(parent: Node3D, block_name: String, rect: Rect2, height: float) -> void:
	var glow := CityKit.make_emissive_material(
		Color(0.278, 0.310, 0.361), 0.0, WINDOW_GLOW
	)
	_window_materials.append(glow)
	var floors := maxi(int(height / 3.4), 2)
	for level in range(1, floors):
		var band := 0.35 + float(level) * (height / float(floors))
		if band > height - 1.0:
			break
		CityKit.add_slab(
			parent, "%sBand%d" % [block_name, level], rect.grow(0.12), band, 0.9, glow,
			false, false
		)


## Ground-floor glazing and a canopy, which is what tells the player a block has
## shops in it rather than offices.
func _add_shopfronts(parent: Node3D, block_name: String, rect: Rect2) -> void:
	CityKit.add_slab(
		parent, block_name + "Glazing", rect.grow(0.18), 0.4, 2.6, _mat("glass"), false, false
	)
	CityKit.add_slab(
		parent, block_name + "Canopy", rect.grow(1.4), 3.3, 0.25, _mat("trim"), false, false
	)


# --- Central Plaza -------------------------------------------------------

## The landmark, and the one place in the city a car cannot go.
func _build_plaza() -> void:
	var container := _make_container("Plaza")
	CityKit.add_slab(
		container, "PlazaFloor", PLAZA, PLAZA_BASE, 0.02, _mat("plaza"), false, false
	)
	# The thing people navigate by, and the map's anchor for this half of the
	# city. A marker rather than a mesh: the monument below is what is seen.
	var landmark := Marker3D.new()
	landmark.name = "CentralPlazaLandmark"
	landmark.position = MONUMENT
	landmark.set_meta("label", "Central Plaza")
	landmark.add_to_group(&"landmark")
	container.add_child(landmark)
	# Bollards along the two open sides. Vehicles are stopped by geometry rather
	# than by a rule, which is the only kind of barrier that cannot be argued
	# with by a police car in a hurry.
	var step := 3.0
	var at := PLAZA.position.x
	var index := 0
	while at <= PLAZA.end.x:
		for edge in [PLAZA.position.y, PLAZA.end.y]:
			CityKit.add_cylinder(
				container, "Bollard%d_%d" % [index, int(edge)],
				Vector3(at, 0.5, edge), 0.16, 1.0, _mat("metal")
			)
		at += step
		index += 1

	# The monument: a stepped plinth and a column, tall enough to see down the
	# boulevard and act as the thing people navigate by.
	CityKit.add_cylinder(
		container, "PlinthLower", MONUMENT + Vector3(0.0, 0.3, 0.0), 4.2, 0.6, _mat("stone")
	)
	CityKit.add_cylinder(
		container, "PlinthUpper", MONUMENT + Vector3(0.0, 0.9, 0.0), 3.0, 0.6, _mat("stone")
	)
	CityKit.add_cylinder(
		container, "Column", MONUMENT + Vector3(0.0, 5.5, 0.0), 1.1, 8.6, _mat("pale")
	)
	var finial := CityKit.make_emissive_material(Color(0.729, 0.663, 0.478), 0.0, LAMP_GLOW)
	_lamp_materials.append(finial)
	CityKit.add_sphere(
		container, "Finial", MONUMENT + Vector3(0.0, 10.4, 0.0), Vector3(1.5, 1.5, 1.5), finial
	)
	# A basin round the foot of it, so the plaza has something in it besides
	# paving from directly above.
	CityKit.add_cylinder(
		container, "Basin", MONUMENT + Vector3(0.0, 0.12, 0.0), 8.0, 0.24, _mat("water"), false
	)

	# Four trees at the corners, non-solid like every other piece of street
	# planting: anything within a stride of a walking route becomes a jam.
	var trunk := CityKit.make_material(Color(0.361, 0.278, 0.204))
	var foliage := [
		CityKit.make_material(Color(0.290, 0.412, 0.267)),
		CityKit.make_material(Color(0.243, 0.361, 0.239)),
	]
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = hash("CentralPlazaTrees")
	for corner: Vector2 in [
		Vector2(PLAZA.position.x + 3.0, PLAZA.position.y + 3.0),
		Vector2(PLAZA.end.x - 3.0, PLAZA.position.y + 3.0),
		Vector2(PLAZA.position.x + 3.0, PLAZA.end.y - 3.0),
		Vector2(PLAZA.end.x - 3.0, PLAZA.end.y - 3.0),
	]:
		CityKit.add_tree(
			container, "PlazaTree_%d_%d" % [int(corner.x), int(corner.y)],
			Vector3(corner.x, 0.0, corner.y), 1.1, trunk, foliage, tree_rng, false
		)


# --- Street furniture ----------------------------------------------------

## Lamps down every signalled street, and a scattering of trees. Nothing here is
## solid: anything within a stride of a pavement route becomes a jam.
func _build_street_furniture() -> void:
	var container := _make_container("StreetFurniture")
	var lamp_glass := CityKit.make_emissive_material(
		Color(0.404, 0.376, 0.298), 0.0, LAMP_GLOW
	)
	_lamp_materials.append(lamp_glass)

	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from: float = entry[2]
		var to: float = entry[3]
		var half: float = entry[4]
		if half <= SERVICE_HALF:
			continue
		var verge := half + WALK_WIDTH - 0.8
		var at := minf(from, to) + 14.0
		var limit := maxf(from, to) - 14.0
		var index := 0
		while at < limit:
			for side: float in [-1.0, 1.0]:
				var base: Vector3 = (
					Vector3(at, 0.0, centre + side * verge) if east_west
					else Vector3(centre + side * verge, 0.0, at)
				)
				_add_lamp(container, "Lamp_%d_%d_%d" % [int(centre), index, int(side)], base, lamp_glass)
			at += 26.0
			index += 1


func _add_lamp(
	parent: Node3D, lamp_name: String, base: Vector3, glass: StandardMaterial3D
) -> void:
	CityKit.add_cylinder(
		parent, lamp_name + "Post", base + Vector3(0.0, 2.4, 0.0), 0.09, 4.8,
		_mat("metal"), false
	)
	CityKit.add_box(
		parent, lamp_name + "Head", base + Vector3(0.0, 4.85, 0.0),
		Vector3(0.5, 0.18, 0.28), glass, false, false
	)


# --- Navigation ----------------------------------------------------------

## Hands this district's pavements and lanes to the city's existing graphs.
##
## Extending rather than building is the whole trick: there is one nav graph and
## one road network for the whole city, so a route from a Harbour Row pavement to
## a Central one is an ordinary path, and a car that reaches the boundary finds
## the next lane waiting rather than running out of road.
func _extend_navigation() -> void:
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	var network := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if nav == null or network == null:
		push_error("District02 found no city graphs to extend.")
		return

	nav.extend(walk_lines(), foot_road_lines())
	network.extend(lane_strands())


## Pavement centre lines, plus the plaza and the walk down the gateway road that
## joins the two districts on foot.
func walk_lines() -> Array:
	var lines: Array = []
	var offset := ROAD_HALF + WALK_WIDTH * 0.5
	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from: float = entry[2]
		var to: float = entry[3]
		if float(entry[4]) <= SERVICE_HALF:
			continue
		for side: float in [-1.0, 1.0]:
			var line: float = centre + side * offset
			lines.append(
				[Vector2(from, line), Vector2(to, line)] if east_west
				else [Vector2(line, from), Vector2(line, to)]
			)

	# The plaza: a ring and a cross, so somebody can walk over it rather than
	# round it, and the monument has paths meeting at it.
	lines.append_array([
		[Vector2(PLAZA.position.x + 2.0, PLAZA.position.y + 2.0), Vector2(PLAZA.end.x - 2.0, PLAZA.position.y + 2.0)],
		[Vector2(PLAZA.position.x + 2.0, PLAZA.end.y - 2.0), Vector2(PLAZA.end.x - 2.0, PLAZA.end.y - 2.0)],
		[Vector2(PLAZA.position.x + 2.0, PLAZA.position.y + 2.0), Vector2(PLAZA.position.x + 2.0, PLAZA.end.y - 2.0)],
		[Vector2(PLAZA.end.x - 2.0, PLAZA.position.y + 2.0), Vector2(PLAZA.end.x - 2.0, PLAZA.end.y - 2.0)],
		# ...and the two gates joining it to the streets either side.
		[Vector2(PLAZA.get_center().x, PLAZA.position.y + 2.0), Vector2(PLAZA.get_center().x, KINGSTON_RD_Z - ROAD_HALF - WALK_WIDTH * 0.5)],
		[Vector2(PLAZA.get_center().x, PLAZA.end.y - 2.0), Vector2(PLAZA.get_center().x, MARKET_ST_Z + ROAD_HALF + WALK_WIDTH * 0.5)],
	])

	# The gateway: the pavement carries on south to Harbour Row's north edge, so
	# the two districts are joined for somebody on foot as well as in a car.
	for side: float in [-1.0, 1.0]:
		var line: float = CENTER_BLVD_X + side * offset
		lines.append([Vector2(line, GATEWAY_Z + 4.0), Vector2(line, -85.0)])
	return lines


## Route lines for the pedestrian graph's road layer — the centre of each
## carriageway, used for routing rather than for driving.
func foot_road_lines() -> Array:
	var lines: Array = []
	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		lines.append(
			[Vector2(entry[2], centre), Vector2(entry[3], centre)] if east_west
			else [Vector2(centre, entry[2]), Vector2(centre, entry[3])]
		)
	lines.append([Vector2(CENTER_BLVD_X, GATEWAY_Z), Vector2(CENTER_BLVD_X, -85.0)])
	return lines


## Directed lanes for the traffic network. Right-hand traffic: a driver's own
## lane is the one to the right of the centre line.
func lane_strands() -> Array:
	var strands: Array = []
	var west := BOUNDS.position.x + 4.0
	var east := BOUNDS.end.x - 4.0
	var north := BOUNDS.position.y + 4.0

	for z in [MARKET_ST_Z, KINGSTON_RD_Z, RIVERSIDE_DR_Z]:
		strands.append([Vector2(west, z + LANE_OFFSET), Vector2(east, z + LANE_OFFSET)])
		strands.append([Vector2(east, z - LANE_OFFSET), Vector2(west, z - LANE_OFFSET)])

	# Center Boulevard runs the length of the district and carries on south
	# through the gateway into Harbour Row, which is the join.
	strands.append([
		Vector2(CENTER_BLVD_X + LANE_OFFSET, -84.0),
		Vector2(CENTER_BLVD_X + LANE_OFFSET, north),
	])
	strands.append([
		Vector2(CENTER_BLVD_X - LANE_OFFSET, north),
		Vector2(CENTER_BLVD_X - LANE_OFFSET, -84.0),
	])

	for x in [PLAZA_ST_X, EXCHANGE_ST_X]:
		strands.append([Vector2(x + LANE_OFFSET, MARKET_ST_Z), Vector2(x + LANE_OFFSET, north)])
		strands.append([Vector2(x - LANE_OFFSET, north), Vector2(x - LANE_OFFSET, MARKET_ST_Z)])

	# The service roads: one lane each way, and the reason the grid is not the
	# only way through Central.
	for x in [SERVICE_WEST_X, SERVICE_EAST_X]:
		strands.append([Vector2(x + 1.4, MARKET_ST_Z), Vector2(x + 1.4, RIVERSIDE_DR_Z)])
		strands.append([Vector2(x - 1.4, RIVERSIDE_DR_Z), Vector2(x - 1.4, MARKET_ST_Z)])
	return strands


# --- Signals -------------------------------------------------------------

## Three signalled junctions, deliberately out of phase with each other and with
## Harbour Row's, so the grid never turns green all at once.
func _build_traffic_signals() -> void:
	var container := _make_container("Traffic")
	var junctions := [
		["CentralMarketSignal", Vector3(CENTER_BLVD_X, 0.0, MARKET_ST_Z), TrafficLight.Phase.NS_GREEN, 0.0],
		["CentralKingstonSignal", Vector3(CENTER_BLVD_X, 0.0, KINGSTON_RD_Z), TrafficLight.Phase.EW_GREEN, 3.5],
		["PlazaMarketSignal", Vector3(PLAZA_ST_X, 0.0, MARKET_ST_Z), TrafficLight.Phase.EW_GREEN, 7.0],
	]
	for entry in junctions:
		var light := TrafficLight.new()
		light.name = entry[0]
		light.position = entry[1]
		light.start_phase = entry[2]
		light.start_offset_seconds = entry[3]
		light.stop_line_distance = STOP_LINE_OFFSET
		container.add_child(light)


# --- People and cars -----------------------------------------------------

## Central's own crowd. They are ordinary pedestrians on the city's one nav
## graph, so nothing stops them wandering down to Harbour Row — they simply
## start here, and there are more of them.
func _build_pedestrians() -> void:
	var container := _make_container("Pedestrians")
	container.add_to_group(&"crowd")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("CentralDistrictCrowd")

	var palette := [
		Color(0.361, 0.376, 0.427), Color(0.478, 0.451, 0.431),
		Color(0.290, 0.353, 0.400), Color(0.514, 0.443, 0.396),
		Color(0.400, 0.396, 0.463), Color(0.302, 0.412, 0.388),
	]
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	if nav == null:
		return

	for i in PEDESTRIAN_COUNT:
		var walker: Pedestrian = PEDESTRIAN_SCENE.instantiate()
		walker.name = "CentralPedestrian%d" % i
		walker.body_color = palette[i % palette.size()]
		walker.walk_speed = rng.randf_range(2.1, 3.0)
		# Placed on this district's own pavements rather than anywhere in the
		# city, so Central starts busy and Harbour Row stays as it was.
		walker.position = _random_local_walk_point(nav, rng)
		container.add_child(walker)


## A pavement node inside this district. The graph covers the whole city, so the
## sample is repeated until it lands in the right half of it.
func _random_local_walk_point(nav: NavGraph, rng: RandomNumberGenerator) -> Vector3:
	for attempt in 40:
		var point := nav.random_point(NavGraph.Layer.WALK, rng)
		if BOUNDS.has_point(Vector2(point.x, point.z)):
			return point + Vector3.UP * 0.4
	return Vector3(PLAZA.get_center().x, 0.4, PLAZA.get_center().y)


## A police post, so Central is covered without a second precinct. Officers here
## answer the same calls as everybody else — WantedManager knows nothing about
## districts.
func _build_police_post() -> void:
	var container := _make_container("Police")
	var posts := [
		["CentralPlazaOfficer", Vector3(PLAZA.end.x + 8.0, 0.4, PLAZA.get_center().y)],
		["KingstonOfficer", Vector3(CENTER_BLVD_X + 12.0, 0.4, KINGSTON_RD_Z + 11.0)],
	]
	for post in posts:
		var officer: PoliceOfficer = POLICE_OFFICER_SCENE.instantiate()
		officer.name = post[0]
		officer.position = post[1]
		officer.post_position = post[1]
		container.add_child(officer)


# --- Doors ---------------------------------------------------------------

## Commercial units and NPC venues. The units are ordinary CommercialProperty
## doors — the same component Harbour Row uses — so leasing, business creation
## and the interiors behind them need nothing district-specific.
func _venue_table() -> Array:
	return [
		# [name, point, facing, prompt, kind, payload]
		[
			"CentralBoulevardUnit", Vector3(-30.0, 1.2, -279.6), Vector3.BACK,
			"View Property", "property", "unit_central_88",
		],
		[
			"MarketStreetUnit", Vector3(-74.0, 1.2, -169.6), Vector3.BACK,
			"View Property", "property", "unit_market_12",
		],
		[
			"PlazaUnit", Vector3(30.0, 1.2, -169.6), Vector3.BACK,
			"View Property", "property", "unit_plaza_03",
		],
		[
			"KingstonRoadUnit", Vector3(-30.0, 1.2, -224.6), Vector3.BACK,
			"View Property", "property", "unit_kingston_40",
		],
		# NPC-run places, so the district reads as occupied rather than as a set
		# of empty units waiting for the player.
		[
			"ExchangeLobby", Vector3(30.0, 1.2, -279.6), Vector3.BACK, "Enter Lobby",
			"message", "EXCHANGE HOUSE\nOffices. Nothing in here for you yet.",
		],
		[
			"PlazaCoffee", Vector3(74.0, 1.2, -169.6), Vector3.BACK, "Buy a drink",
			"shop", "Plaza Coffee",
		],
		[
			"CentralGrocer", Vector3(-74.0, 1.2, -224.6), Vector3.BACK, "Buy food",
			"shop", "Kingston Grocer",
		],
		[
			"CentralDepot", Vector3(30.0, 1.2, -224.6), Vector3.BACK, "Start deliveries",
			"courier", "",
		],
		[
			"MeridianHeights", Vector3(-60.0, 1.2, -153.4), Vector3.FORWARD, "View Apartment",
			"residence", "meridian",
		],
	]


func _build_venue_doors() -> void:
	for entry in _venue_table():
		var node_name: String = entry[0]
		var point: Vector3 = entry[1]
		var facing: Vector3 = entry[2]
		var prompt: String = entry[3]
		var kind: String = entry[4]
		var payload: String = entry[5]

		var door: Interactable
		match kind:
			"property":
				door = _make_commercial_property(point, facing, StringName(payload))
			"shop":
				door = _make_npc_shop(payload)
			"courier":
				door = _make_courier_depot()
			"residence":
				door = _make_residence(point, facing, StringName(payload))
			_:
				var notice := MessagePoint.new()
				notice.message = payload
				door = notice

		door.name = node_name
		door.prompt_action = prompt
		CityKit.attach_interactable(_interactables, door, point, 2.6)
		_add_door_panel(node_name, point, facing)


## A Central unit. Rents are half again what Harbour Row asks and the pitches are
## better, which is the trade the district exists to offer.
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
	unit.district_id = &"central"

	match id:
		&"unit_central_88":
			unit.address = "88 Central Boulevard"
			unit.property_type = "Retail Unit"
			unit.size_class = CommercialProperty.SizeClass.MEDIUM
			unit.floor_area = 78
			unit.rent_amount = 1500
			unit.deposit = 1200
			unit.customer_capacity = 10
			unit.queue_capacity = 6
			unit.location_demand_modifier = 1.2
		&"unit_market_12":
			unit.address = "12 Market Street"
			unit.property_type = "Retail Unit"
			unit.size_class = CommercialProperty.SizeClass.SMALL
			unit.floor_area = 50
			unit.rent_amount = 950
			unit.deposit = 750
			unit.customer_capacity = 7
			unit.queue_capacity = 4
			unit.location_demand_modifier = 1.05
		&"unit_plaza_03":
			unit.address = "3 Central Plaza"
			unit.property_type = "Premium Retail"
			unit.size_class = CommercialProperty.SizeClass.MEDIUM
			unit.floor_area = 88
			unit.rent_amount = 2400
			unit.deposit = 1900
			unit.customer_capacity = 14
			unit.queue_capacity = 8
			unit.location_demand_modifier = 1.35
		_:
			unit.address = "40 Kingston Road"
			unit.property_type = "Food Service Unit"
			unit.size_class = CommercialProperty.SizeClass.SMALL
			unit.floor_area = 54
			unit.rent_amount = 1100
			unit.deposit = 900
			unit.customer_capacity = 8
			unit.queue_capacity = 5
			unit.location_demand_modifier = 1.15
	return unit


## An NPC-run counter on the pavement. Central sells the same goods the rest of
## the city does; the point is that the player does not have to drive home to
## buy a sandwich.
func _make_npc_shop(shop_name: String) -> Shop:
	var shop := Shop.new()
	shop.shop_name = shop_name
	shop.prompt_subtitle = shop_name
	shop.opens_hour = 6
	shop.closes_hour = 22
	shop.stock = [
		ItemCatalogue.by_id(&"bottled_water"),
		ItemCatalogue.by_id(&"soda_can"),
		ItemCatalogue.by_id(&"snack_bar"),
		ItemCatalogue.by_id(&"basic_meal"),
	]
	return shop


func _make_courier_depot() -> Interactable:
	var depot := CourierDepot.new()
	depot.prompt_subtitle = "Central Depot"
	return depot


## The better flat. Dearer than the starter studio and in the middle of
## everything, which is what the money buys.
func _make_residence(point: Vector3, facing: Vector3, id: StringName) -> ResidenceProperty:
	var street_marker := Marker3D.new()
	street_marker.name = "ResidenceStreetExit_%s" % id
	street_marker.position = point + facing * 1.8 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(ApartmentInterior.exit_group_for(id))
	_interactables.add_child(street_marker)

	var home := ResidenceProperty.new()
	home.residence_id = id
	home.address = "5 Kingston Road"
	home.display_name = "Meridian Heights"
	home.district_id = &"central"
	home.size_label = "One bedroom"
	home.amenities = "Double bed · Kitchen · Living area · Street parking"
	home.rent_amount = 640
	home.deposit = 600
	home.leased_by_player = false
	home.destination_group = ApartmentInterior.entry_group_for(id)
	home.travel_minutes = 2
	home.override_camera = true
	home.camera_distance = 12.0
	home.camera_pitch = 74.0
	return home


## A door slab on the facade, so the prompt has something to point at.
func _add_door_panel(node_name: String, point: Vector3, facing: Vector3) -> void:
	var centre := point - facing * 0.6
	centre.y = 1.35
	var along := Vector3(absf(facing.z), 0.0, absf(facing.x))
	var size := along * 2.6 + Vector3(0.0, 2.8, 0.0) + facing.abs() * 0.3
	CityKit.add_box(_geometry, "DoorPanel_%s" % node_name, centre, size, _mat("door"), false)


# --- Parking -------------------------------------------------------------

## Two surface car parks, behind the service roads and against the edge of the
## district. Central's kerbs are almost all double-yellow — "offices, shops and
## no parking" is what the district tells the player on the way in — so this is
## where a car goes while its owner is in a shop.
const CAR_PARK_ROWS := 5


func _build_parking() -> void:
	var container := _make_container("Parking")
	for side: float in [-1.0, 1.0]:
		var name_part := "East" if side > 0.0 else "West"
		var inner := (SERVICE_EAST_X if side > 0.0 else SERVICE_WEST_X) + side * 7.0
		var outer := (BOUNDS.end.x + 6.0) if side > 0.0 else (BOUNDS.position.x - 6.0)
		var rect := CityKit.rect_from_bounds(
			minf(inner, outer), RIVERSIDE_DR_Z + 14.0,
			maxf(inner, outer), MARKET_ST_Z - 14.0
		)
		CityKit.add_slab(
			container, "CarPark%s" % name_part, rect,
			ROAD_BASE, ROAD_THICKNESS, _mat("asphalt")
		)
		# Bay lines down the long axis, which is what makes it read as a car
		# park from above rather than as a patch of tarmac.
		for i in range(1, CAR_PARK_ROWS):
			var z := rect.position.y + rect.size.y * float(i) / float(CAR_PARK_ROWS)
			CityKit.add_slab(
				container, "CarPark%sBay%d" % [name_part, i],
				CityKit.rect_from_bounds(rect.position.x + 0.6, z - 0.1, rect.end.x - 0.6, z + 0.1),
				MARKING_BASE, MARKING_THICKNESS, _mat("marking")
			)


# --- The edge of the city ------------------------------------------------

## What stops the player driving off the north end of the world.
##
## Not an invisible wall: hoardings and a closed-road barrier across the top of
## Central Boulevard, which reads as a city that carries on past the bit that is
## built rather than as a map that ends. The road behind them is real geometry
## and the sign says where it goes, so when a third district is built the
## hoarding comes down and nothing else has to change.
const NORTH_EDGE := -330.0
const FUTURE_ROAD_SIGN := "NORTHGATE — ROAD CLOSED"


func _build_boundary() -> void:
	var container := _make_container("Boundary")
	var thickness := 1.2
	var height := 3.2
	var min_x := BOUNDS.position.x - 8.0
	var max_x := BOUNDS.end.x + 8.0

	# North: hoarding either side of the boulevard, with the boulevard itself
	# barriered rather than walled.
	var gap := ROAD_HALF + 2.0
	for piece: Array in [
		[min_x, CENTER_BLVD_X - gap], [CENTER_BLVD_X + gap, max_x],
	]:
		CityKit.add_slab(
			container, "NorthHoarding_%d" % int(piece[0]),
			CityKit.rect_from_bounds(piece[0], NORTH_EDGE - thickness, piece[1], NORTH_EDGE),
			0.0, height, _mat("metal")
		)

	_build_closed_road(container)
	_build_undeveloped_land(container)

	# East and west: the district is walled in by the backs of the next blocks
	# along, which have not been built yet.
	for side: float in [-1.0, 1.0]:
		var x := (max_x if side > 0.0 else min_x)
		CityKit.add_slab(
			container, "SideWall_%s" % ("East" if side > 0.0 else "West"),
			CityKit.rect_from_bounds(
				x - (thickness if side > 0.0 else 0.0),
				NORTH_EDGE - thickness,
				x + (0.0 if side > 0.0 else thickness),
				GATEWAY_Z
			),
			0.0, height, _mat("concrete")
		)
		# And down the sides of the connecting stretch, so the boulevard is a
		# road out of town rather than an invitation to drive across a field.
		var edge := CENTER_BLVD_X + side * CORRIDOR_HALF
		var suffix := "East" if side > 0.0 else "West"
		CityKit.add_slab(
			container, "GatewayWall_%s" % suffix,
			CityKit.rect_from_bounds(
				edge - (thickness if side > 0.0 else 0.0),
				GATEWAY_Z,
				edge + (0.0 if side > 0.0 else thickness),
				-District01.GROUND_EXTENT
			),
			0.0, height, _mat("concrete")
		)
		# The two returns that close the undeveloped land either side of it, at
		# the district end and at Harbour Row's.
		for z: float in [GATEWAY_Z, -District01.GROUND_EXTENT]:
			CityKit.add_slab(
				container, "GatewayReturn_%s_%d" % [suffix, int(z)],
				CityKit.rect_from_bounds(
					(edge if side > 0.0 else min_x), z - thickness,
					(max_x if side > 0.0 else edge), z
				),
				0.0, height, _mat("concrete")
			)


## The land either side of the connecting boulevard. Not built on, not driveable,
## and not a hole: rough grass behind the wall, which is what an approach road
## into a city centre actually looks like and costs four slabs and six trees.
func _build_undeveloped_land(container: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("GatewayScrub")
	var foliage := [
		CityKit.make_material(Color(0.290, 0.412, 0.267)),
		CityKit.make_material(Color(0.243, 0.361, 0.239)),
	]
	for side: float in [-1.0, 1.0]:
		var suffix := "East" if side > 0.0 else "West"
		var inner := CENTER_BLVD_X + side * (CORRIDOR_HALF + 1.4)
		var outer := (BOUNDS.end.x + 6.0) if side > 0.0 else (BOUNDS.position.x - 6.0)
		var rect := CityKit.rect_from_bounds(
			minf(inner, outer), GATEWAY_Z,
			maxf(inner, outer), -District01.GROUND_EXTENT - 1.2
		)
		CityKit.add_slab(
			container, "GatewayScrub_%s" % suffix, rect, 0.0, PLAZA_BASE, _mat("scrub")
		)
		for i in 3:
			var spot := Vector3(
				rng.randf_range(rect.position.x + 6.0, rect.end.x - 6.0),
				0.0,
				rng.randf_range(rect.position.y + 6.0, rect.end.y - 6.0)
			)
			CityKit.add_tree(
				container, "GatewayTree_%s_%d" % [suffix, i], spot,
				rng.randf_range(0.9, 1.3), _mat("trunk"), foliage, rng, false
			)


## The barriers across the top of Central Boulevard, and the sign saying what is
## behind them. This is the seam a later district opens along.
func _build_closed_road(container: Node3D) -> void:
	var y := NORTH_EDGE + 1.0
	for i in 5:
		var x := CENTER_BLVD_X - ROAD_HALF + 1.6 + float(i) * (ROAD_HALF * 2.0 - 3.2) / 4.0
		CityKit.add_box(
			container, "RoadBarrier%d" % i, Vector3(x, 0.55, y),
			Vector3(2.4, 1.1, 0.5), _mat("marking")
		)
		CityKit.add_box(
			container, "BarrierFoot%d" % i, Vector3(x, 0.12, y),
			Vector3(2.4, 0.24, 1.1), _mat("trim")
		)

	var sign_post := Vector3(CENTER_BLVD_X, 0.0, y + 2.4)
	CityKit.add_box(
		container, "ClosureSignPost", sign_post + Vector3(0.0, 1.4, 0.0),
		Vector3(0.16, 2.8, 0.16), _mat("metal")
	)
	CityKit.add_box(
		container, "ClosureSign", sign_post + Vector3(0.0, 3.0, 0.0),
		Vector3(5.0, 1.2, 0.16), _mat("marking"), false
	)
	var label := Label3D.new()
	label.name = "ClosureSignText"
	label.text = FUTURE_ROAD_SIGN
	label.font_size = 96
	label.pixel_size = 0.006
	label.modulate = Color(0.180, 0.196, 0.235)
	label.position = sign_post + Vector3(0.0, 3.0, 0.1)
	label.rotation_degrees.y = 180.0
	container.add_child(label)


# --- Parked cars ---------------------------------------------------------

## Kerbside parking down the quieter streets. Central's mix leans towards small
## cars and the occasional expensive one, which is a cheap way to make the two
## districts feel different from the driver's seat.
func _build_parked_cars() -> void:
	var container := _make_container("ParkedVehicles")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("CentralParking")

	var spots := [
		# In the west car park, nose-in off the service road.
		[Vector3(-102.0, 0.0, -240.0), 90.0],
		[Vector3(-102.0, 0.0, -224.0), 90.0],
		[Vector3(102.0, 0.0, -208.0), -90.0],
		[Vector3(24.0, 0.0, KINGSTON_RD_Z + 8.6), 180.0],
		[Vector3(32.0, 0.0, KINGSTON_RD_Z + 8.6), 180.0],
		[Vector3(SERVICE_WEST_X, 0.0, -240.0), 90.0],
		[Vector3(SERVICE_EAST_X, 0.0, -196.0), -90.0],
		[Vector3(-8.6, 0.0, -300.0), 90.0],
		[Vector3(8.6, 0.0, -252.0), -90.0],
		[Vector3(-8.6, 0.0, -196.0), 90.0],
	]
	for i in spots.size():
		var scene: PackedScene = VehicleCatalogue.pick_for_district(&"central", rng)
		var car: Vehicle = scene.instantiate()
		car.name = "CentralParked%d" % i
		car.position = spots[i][0]
		car.rotation_degrees.y = spots[i][1]
		car.owner_type = Vehicle.OwnerType.NPC
		car.owner_id = &"central_resident"
		container.add_child(car)


# --- Lighting ------------------------------------------------------------

func _on_minute_passed(_hour: int, _minute: int) -> void:
	_refresh_night_lighting()


## Windows and lamps come up together as the sun goes down. One write per shared
## material rather than per building, which is why every block on a street can
## light up for almost nothing.
func _refresh_night_lighting() -> void:
	var hour := TimeManager.hour
	var night := hour >= 19 or hour < 6
	var dusk := hour == 18 or hour == 6
	var energy := WINDOW_NIGHT_ENERGY if night else (WINDOW_NIGHT_ENERGY * 0.4 if dusk else 0.0)
	for material in _window_materials:
		material.emission_energy_multiplier = energy
	for material in _lamp_materials:
		material.emission_energy_multiplier = 2.6 if night or dusk else 0.0
