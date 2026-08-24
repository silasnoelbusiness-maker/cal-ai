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

## Names for the NPC-run shops along Central's parades. Original, generic and
## short enough to read from the elevated camera.
const NPC_SHOP_NAMES: Array[String] = [
	"MERIDIAN NEWS", "KETTLE & CO", "THE PAPER ROOM", "FOLD",
	"NORTHGATE PHARMACY", "SALT & SODA", "CIVIC BOOKS", "TRAM CAFE",
	"HARBOUR OPTICS", "GREENLINE GROCER", "PLAZA FLORIST", "EXCHANGE DELI",
]

## Sign colours, drawn from the palette's accents so a parade of shops is varied
## without any one of them being lurid.
const SIGN_COLOURS: Array[Color] = [
	Color(0.180, 0.286, 0.404), Color(0.400, 0.239, 0.235),
	Color(0.216, 0.361, 0.318), Color(0.400, 0.341, 0.220),
	Color(0.286, 0.243, 0.361), Color(0.196, 0.220, 0.259),
]

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
	_build_street_dressing()
	_build_blocks()
	_build_plaza()
	_build_street_furniture()
	_build_street_props()
	_build_broker_alley()
	_build_venue_doors()
	_build_vending_machines()
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


## The one address in Central that is not on the street.
##
## A service alley between two blocks with a door at the end of it. §127 asks
## for a few locations rather than new geography, and this is the smallest kind
## there is: a gap, a bin, a light, a door. The broker works out of it because
## Central is where the money is, and because a player who has done a couple of
## jobs on the docks has a reason to come north.
func _build_broker_alley() -> void:
	var holder := _make_container("BrokerAlley")
	var at := Vector3(58.0, 0.0, -246.0)
	var wall := _mat("brick")
	var slate := _mat("slate")

	# Two walls making the alley, and a dead end at the far side of it.
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			holder, "AlleyWall%d" % int(side),
			at + Vector3(side * 4.0, 3.6, 0.0),
			Vector3(0.9, 7.2, 16.0), wall, true
		)
	CityKit.add_box(
		holder, "AlleyEnd", at + Vector3(0.0, 3.6, -8.4),
		Vector3(8.0, 7.2, 0.9), slate, true
	)
	CityKit.add_slab(
		holder, "AlleyFloor",
		CityKit.rect_from_bounds(at.x - 3.6, at.z - 8.0, at.x + 3.6, at.z + 8.0),
		0.0, 0.05, _mat("paving")
	)

	# The door itself, and the light over it that is the only reason anybody
	# would look down here twice.
	CityKit.add_box(
		holder, "BrokerDoor", at + Vector3(0.0, 1.25, -7.9),
		Vector3(1.3, 2.5, 0.18), _mat("door"), false
	)
	CityKit.add_box(
		holder, "BrokerLamp", at + Vector3(0.0, 2.9, -7.7),
		Vector3(0.5, 0.16, 0.34),
		CityKit.make_emissive_material(Color(0.937, 0.816, 0.596), 1.5), false, false
	)
	for i in 2:
		CityKit.add_box(
			holder, "AlleyBin%d" % i,
			at + Vector3(-2.6 + float(i) * 5.2, 0.6, -4.0 + float(i) * 2.0),
			Vector3(1.0, 1.2, 0.9), _mat("metal"), false
		)
	var light := OmniLight3D.new()
	light.name = "AlleyLight"
	light.position = at + Vector3(0.0, 2.8, -6.6)
	light.light_color = Color(0.988, 0.878, 0.706)
	light.light_energy = 2.6
	light.omni_range = 11.0
	light.shadow_enabled = false
	holder.add_child(light)

	var door := CriminalContactPoint.new()
	door.name = "BrokerContact"
	door.contact_id = &"the_broker"
	CityKit.attach_interactable(holder, door, at + Vector3(0.0, 1.1, -6.6), 2.8)


func _build_palette() -> void:
	_palette = {
		"ground": CityKit.make_surface(Color(0.286, 0.294, 0.306), 0.6),
		"asphalt": CityKit.make_surface(Color(0.176, 0.180, 0.196), 0.9),
		"paving": CityKit.make_surface(Color(0.541, 0.541, 0.529), 0.78, 1.1, 0.8, 0.13, 0.0, 3),
		"plaza": CityKit.make_surface(Color(0.498, 0.486, 0.458), 0.80, 1.2, 1.0, 0.16, 0.0, 8),
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
		# A probe for footsteps, same as Harbour Row's roads.
		SurfaceMap.probe(
			_geometry, rect, ROAD_BASE + ROAD_THICKNESS, SurfaceMap.Surface.ASPHALT
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
			var walk := CityKit.add_slab(
				_geometry, "Walk_%s_%d_%d" % [
					"EW" if east_west else "NS", int(centre), int(side)
				],
				rect, 0.0, CURB_HEIGHT, _mat("paving"), true, false, 1 << 5
			)
			SurfaceMap.tag(walk, SurfaceMap.Surface.CONCRETE)


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

		# Plant, ducting, a tank and a mast on the roof. From an elevated camera
		# a roof is the largest face a building has, and a bare one is the last
		# thing that still reads as a box.
		var roof_rng := RandomNumberGenerator.new()
		roof_rng.seed = hash(block_name) + 13
		var roof_rect := rect.grow(-6.4) if style == "tower" else rect
		var roof_y := (height + height * 0.28) if style == "tower" else height + 0.7
		BuildingKit.add_roof_kit(container, block_name, roof_rect, roof_y, roof_rng)


## Lit bands up each face. One material per building, so the whole district's
## windows come on together at dusk for the cost of a handful of writes.
func _add_window_bands(parent: Node3D, block_name: String, rect: Rect2, height: float) -> void:
	var glow := CityKit.make_emissive_material(
		Color(0.278, 0.310, 0.361), 0.0, WINDOW_GLOW
	)
	_window_materials.append(glow)
	# Punched windows on a grid: a Central tower now has a facade of individual
	# lit panes rather than five painted stripes, and lights up at dusk for the
	# same one write per district.
	BuildingKit.add_window_grid(
		parent, block_name, rect, 4.4, height - 1.4, glow, _mat("trim"), 3.0, 1.4, 1.9
	)
	# The tallest blocks get a crown band as well, so the skyline is not four
	# identical parapets.
	if height > 16.0:
		CityKit.add_slab(
			parent, "%sCrown" % block_name, rect.grow(0.30), height - 1.1, 0.6,
			_mat("stone"), false, false
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
	# Shopfront glass gets its own lit material, joined to the district's night
	# switch: an office tower with its windows on and dark shops underneath it
	# reads as a city with the ground floor missing, and street-level glow is
	# most of what makes a night street look inhabited.
	var shop_glow := CityKit.make_emissive_material(
		Color(0.325, 0.353, 0.400), 0.0, Color(0.996, 0.906, 0.729)
	)
	_window_materials.append(shop_glow)

	# Real shopfronts down the long faces: glazing, mullions, a sign band and an
	# awning. Names come from the district's own list, so a Central street reads
	# as a parade of shops rather than as glazing with nothing behind it.
	var along_x := rect.size.x >= rect.size.y
	var run: float = rect.size.x if along_x else rect.size.y
	var units := clampi(int(run / 11.0), 1, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(block_name)
	for face: float in [-1.0, 1.0]:
		for i in units:
			var start: float = (
				(rect.position.x if along_x else rect.position.y) + run * float(i) / float(units)
			)
			var finish := start + run / float(units)
			BuildingKit.add_storefront(
				parent, "%s%d_%d" % [block_name, int(face), i], rect, along_x, face,
				start + 1.2, finish - 1.2,
				NPC_SHOP_NAMES[rng.randi_range(0, NPC_SHOP_NAMES.size() - 1)],
				SIGN_COLOURS[rng.randi_range(0, SIGN_COLOURS.size() - 1)],
				shop_glow, _mat("trim"), _mat("stone")
			)


# --- Central Plaza -------------------------------------------------------

## Benches round the monument and room to stand between them.
##
## Central had a plaza that nobody used: the routines send people to a park in
## the afternoon and there was nothing here for them to be sent to, so everyone
## in the district went and stood in a doorway instead.
func _build_plaza_life(container: Node3D) -> void:
	var wood := _mat("wood") if _palette.has("wood") else _mat("stone")
	var metal := _mat("metal")
	var benches := [
		["PlazaBenchN", Vector3(MONUMENT.x, PLAZA_BASE, MONUMENT.z + 8.5), 180.0],
		["PlazaBenchS", Vector3(MONUMENT.x, PLAZA_BASE, MONUMENT.z - 8.5), 0.0],
		["PlazaBenchE", Vector3(MONUMENT.x + 9.5, PLAZA_BASE, MONUMENT.z), 270.0],
		["PlazaBenchW", Vector3(MONUMENT.x - 9.5, PLAZA_BASE, MONUMENT.z), 90.0],
	]
	for entry in benches:
		container.add_child(DistrictProps.bench(entry[0], entry[1], entry[2], wood, metal))
	var spots := [
		Vector3(MONUMENT.x + 6.0, PLAZA_BASE, MONUMENT.z + 5.0),
		Vector3(MONUMENT.x - 6.0, PLAZA_BASE, MONUMENT.z - 5.0),
		Vector3(MONUMENT.x + 12.0, PLAZA_BASE, MONUMENT.z - 9.0),
		Vector3(MONUMENT.x - 12.0, PLAZA_BASE, MONUMENT.z + 9.0),
	]
	for i in spots.size():
		container.add_child(DistrictProps.park_spot("PlazaSpot%d" % i, spots[i]))

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

	_build_plaza_life(container)

	# The monument: a stepped plinth and a column, tall enough to see down the
	# boulevard and act as the thing people navigate by.
	CityKit.add_cylinder(
		container, "PlinthLower", MONUMENT + Vector3(0.0, 0.3, 0.0), 4.2, 0.6, _mat("stone")
	)
	CityKit.add_cylinder(
		container, "PlinthUpper", MONUMENT + Vector3(0.0, 0.9, 0.0), 3.0, 0.6, _mat("stone")
	)
	# A tapered column rather than a pipe: three drums of falling radius, a
	# banded collar and a lantern on top. From the elevated camera a plain
	# cylinder reads as scaffolding, and this is the thing the district is meant
	# to be navigated by.
	CityKit.add_cylinder(
		container, "ColumnBase", MONUMENT + Vector3(0.0, 1.5, 0.0), 1.35, 0.6, _mat("stone")
	)
	CityKit.add_cylinder(
		container, "ColumnLower", MONUMENT + Vector3(0.0, 3.6, 0.0), 1.15, 3.6, _mat("pale")
	)
	CityKit.add_cylinder(
		container, "ColumnUpper", MONUMENT + Vector3(0.0, 7.3, 0.0), 0.92, 3.8, _mat("pale")
	)
	CityKit.add_cylinder(
		container, "Collar", MONUMENT + Vector3(0.0, 9.3, 0.0), 1.30, 0.42, _mat("stone")
	)
	var finial := CityKit.make_emissive_material(Color(0.729, 0.663, 0.478), 0.0, LAMP_GLOW)
	_lamp_materials.append(finial)
	CityKit.add_cylinder(
		container, "Lantern", MONUMENT + Vector3(0.0, 10.1, 0.0), 0.72, 1.2, finial, false
	)
	CityKit.add_cylinder(
		container, "LanternCap", MONUMENT + Vector3(0.0, 10.85, 0.0), 0.86, 0.24, _mat("metal")
	)
	CityKit.add_sphere(
		container, "Finial", MONUMENT + Vector3(0.0, 11.25, 0.0), Vector3(0.5, 0.7, 0.5),
		_mat("metal")
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
	# An actual light, not only a glowing head.
	#
	# Central's lamps have been emissive material and nothing else since the
	# district was built, so the whole half of the city went to a black void
	# after dark while the harbour's forty-four lamps lit their pavements. The
	# lamp looked lit; the street it stood on did not.
	#
	# No shadows, as in the harbour: a hundred shadow-casting street lamps is
	# not a lighting pass, it is a frame rate.
	var light := OmniLight3D.new()
	light.name = lamp_name + "Light"
	light.position = base + Vector3(0.0, 4.55, 0.0)
	# Cooler and a shade tighter than the harbour's sodium. Central is newer,
	# and the two districts should not be lit by the same lamp.
	light.light_color = Color(0.925, 0.945, 1.0)
	light.light_energy = 5.8
	light.omni_range = 16.0
	light.omni_attenuation = 1.1
	light.shadow_enabled = false
	light.add_to_group(&"street_light")
	parent.add_child(light)


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
	# Phase S — how many of the pool are on the street is the hour's business.
	var director := CrowdDirector.new()
	director.name = "CrowdDirector"
	director.district_id = &"central"
	container.add_child(director)
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
		# Phase S — everybody belongs to a district, which decides which
		# archetypes they can be. A harbour worker does not commute to the
		# Central plaza to stand about (§23, §26).
		walker.routine_district = &"central"
		walker.name = "CentralPedestrian%d" % i
		walker.body_color = palette[i % palette.size()]
		walker.walk_speed = rng.randf_range(2.1, 3.0)
		# Placed on this district's own pavements rather than anywhere in the
		# city, so Central starts busy and Harbour Row stays as it was.
		walker.position = _random_local_walk_point(nav, rng)
		container.add_child(walker)
		director.register(walker)


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
		[
			"VaultStreetUnit", Vector3(74.0, 1.2, -279.6), Vector3.BACK,
			"View Property", "property", "unit_vault_03",
		],
		[
			"ExchangeCourtOffice", Vector3(-88.0, 1.2, -224.6), Vector3.BACK,
			"View Office", "property", "office_exchange_11",
		],
		# NPC-run places, so the district reads as occupied rather than as a set
		# of empty units waiting for the player.
		[
			"ExchangeLobby", Vector3(30.0, 1.2, -279.6), Vector3.BACK, "Order a coffee",
			"service", "Exchange Coffee House|CAFE|6|19",
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
		# The second shift job in the city. Central had a depot and no work of
		# its own, so a player without a car had no reason to be here before
		# they could afford a lease.
		[
			"ArcadeCleaning", Vector3(-44.0, 1.2, -224.6), Vector3.BACK, "Start shift",
			"job", "night_cleaner",
		],
		[
			"MeridianHeights", Vector3(-60.0, 1.2, -153.4), Vector3.FORWARD, "View Apartment",
			"residence", "meridian",
		],
		# The showroom takes the ground floor of Meridian Tower, on Riverside
		# Drive — the dearest frontage in the city, which is where a car
		# dealership would actually be.
		[
			"NorthlineMotors", Vector3(-88.0, 1.2, -279.6), Vector3.BACK, "Enter Showroom",
			"dealership", "",
		],
		# Flats above the chambers opposite. The top of the residential ladder.
		[
			"CentralHeights", Vector3(88.0, 1.2, -279.6), Vector3.BACK, "View Apartment",
			"residence", "central_heights",
		],
		[
			"KingstonFurnishings", Vector3(74.0, 1.2, -224.6), Vector3.BACK, "Enter Store",
			"furniture", "",
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
			"service":
				door = _make_service_point(payload)
			"courier":
				door = _make_courier_depot()
			"job":
				door = _make_job_station(payload)
			"residence":
				door = _make_residence(point, facing, StringName(payload))
			"dealership":
				door = _make_dealership_door(point, facing)
			"furniture":
				door = _make_furniture_door(point, facing)
			_:
				var notice := MessagePoint.new()
				notice.message = payload
				door = notice

		door.name = node_name
		door.prompt_action = prompt
		# Phase S — every façade door is somewhere a routine can send somebody,
		# which is what makes §13's "enter a building" and §14's "leave by the
		# same door" possible without tagging each venue by hand.
		door.add_to_group(&"building_entrance")
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
	unit.sign_yaw = rad_to_deg(atan2(facing.x, facing.z))

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
		&"unit_vault_03":
			# A basement off Vault Street. No windows, one door, and the only
			# licence in Central that runs past midnight.
			unit.address = "3 Vault Street"
			unit.property_type = "Large Commercial"
			unit.size_class = CommercialProperty.SizeClass.LARGE
			unit.floor_area = 168
			unit.rent_amount = 3200
			unit.deposit = 2600
			unit.customer_capacity = 40
			unit.queue_capacity = 10
			unit.location_demand_modifier = 1.3
			unit.business_classes = [&"large_commercial"]
		&"office_exchange_11":
			# Two rooms above the Exchange. Not a business — somewhere to run
			# the ones you already have from.
			unit.address = "11 Exchange Court"
			unit.property_type = "Office"
			unit.size_class = CommercialProperty.SizeClass.SMALL
			unit.floor_area = 38
			unit.rent_amount = 700
			unit.deposit = 600
			unit.customer_capacity = 4
			unit.queue_capacity = 2
			unit.location_demand_modifier = 1.0
			unit.business_classes = [&"office"]
		&"unit_plaza_03":
			unit.address = "3 Central Plaza"
			unit.property_type = "Premium Retail"
			unit.business_classes = [&"retail", &"food_service"]
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
			# It has always been called a food service unit. Phase O is where
			# that started to mean something.
			unit.business_classes = [&"retail", &"food_service"]
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
	home.district_id = &"central"
	home.leased_by_player = false
	home.destination_group = ApartmentInterior.entry_group_for(id)
	home.travel_minutes = 2
	home.override_camera = true

	if id == &"central_heights":
		# The top of the ladder. Dear enough that moving in is a decision, and
		# worth twice the middle flat to the lifestyle score.
		home.address = "1 Riverside Drive"
		home.display_name = "Central Heights"
		home.size_label = "Two bedroom · Top floor"
		home.amenities = "Kingsize room · Open living space · Private bay · Concierge"
		home.rent_amount = 2100
		home.deposit = 2400
		home.lifestyle_value = 78
		home.parking_slots = 1
		# The premium flat is half as big again as the middle one, so the camera
		# has to stand further back to hold it.
		home.camera_distance = 21.0
		home.camera_pitch = 74.0
		_add_private_bay(point)
	else:
		home.address = "5 Kingston Road"
		home.display_name = "Meridian Heights"
		home.size_label = "One bedroom"
		home.amenities = "Double bed · Kitchen · Living area · Street parking"
		home.rent_amount = 640
		home.deposit = 600
		home.lifestyle_value = 42
		home.camera_distance = 12.0
		home.camera_pitch = 74.0
	return home


## The premium flat's own parking space, marked out on the kerb beside its door.
## Nothing enforces it — it is somewhere obvious to leave your car, which is
## exactly what a private bay is worth.
func _add_private_bay(point: Vector3) -> void:
	var centre := Vector3(point.x - 5.0, 0.0, RIVERSIDE_DR_Z - 4.9)
	var rect := CityKit.rect_from_bounds(centre.x - 2.6, centre.z - 1.8, centre.x + 2.6, centre.z + 1.8)
	CityKit.add_slab(
		_geometry, "PrivateBay", rect, MARKING_BASE, MARKING_THICKNESS,
		CityKit.make_material(Color(0.847, 0.780, 0.545)), false, false
	)
	var marker := Marker3D.new()
	marker.name = "CentralHeightsParking"
	marker.position = centre + Vector3(0.0, 0.4, 0.0)
	marker.rotation_degrees.y = -90.0
	marker.add_to_group(&"residence_parking")
	_interactables.add_child(marker)


## The showroom door, plus the kerbside bays a bought car is handed over in and
## the signage over the frontage. The showroom itself is an interior off to one
## side, like every other room the player walks into.
func _make_dealership_door(point: Vector3, facing: Vector3) -> Portal:
	var street_marker := Marker3D.new()
	street_marker.name = "DealershipStreetExit"
	street_marker.position = point + facing * 2.2 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(DealershipInterior.EXIT_GROUP)
	_interactables.add_child(street_marker)

	# Where a car the player has just bought is left: three kerbside bays on
	# Riverside Drive, right outside the door. Facing east, along the road.
	var bays := Node3D.new()
	bays.name = "DealershipCollection"
	_interactables.add_child(bays)
	for i in 3:
		var bay := Marker3D.new()
		bay.name = "CollectionBay%d" % i
		bay.position = Vector3(point.x + 4.0 + float(i) * 6.5, 0.4, RIVERSIDE_DR_Z - 4.9)
		bay.rotation_degrees.y = -90.0
		bay.add_to_group(DealershipInterior.COLLECTION_GROUP)
		bays.add_child(bay)
		_add_collection_bay_markings(bay.position)

	_add_dealership_signage(point, facing)

	var door := Portal.new()
	door.destination_group = DealershipInterior.ENTRY_GROUP
	door.travel_minutes = 1
	door.override_camera = true
	door.camera_distance = 20.0
	door.camera_pitch = 66.0
	door.prompt_subtitle = "Northline Motors"
	return door


func _add_collection_bay_markings(centre: Vector3) -> void:
	var rect := CityKit.rect_from_bounds(centre.x - 2.6, centre.z - 1.8, centre.x + 2.6, centre.z + 1.8)
	var line := 0.16
	for edge in [
		CityKit.rect_from_bounds(rect.position.x, rect.position.y, rect.position.x + line, rect.end.y),
		CityKit.rect_from_bounds(rect.end.x - line, rect.position.y, rect.end.x, rect.end.y),
	]:
		CityKit.add_slab(
			_geometry, "CollectionMark_%d_%d" % [int(centre.x), int(edge.position.x)],
			edge, MARKING_BASE, MARKING_THICKNESS, _mat("marking"), false, false
		)


## Signage and a lit glass frontage, so the showroom is obvious from the street
## rather than being another door in a wall.
func _add_dealership_signage(point: Vector3, facing: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "DealershipFrontage"
	_geometry.add_child(holder)

	var along := Vector3(absf(facing.z), 0.0, absf(facing.x))
	var front := point - facing * 0.5
	CityKit.add_box(
		holder, "Glazing", Vector3(front.x, 2.1, front.z), along * 13.0 + Vector3(0.0, 4.0, 0.0) + facing.abs() * 0.2,
		CityKit.make_material(Color(0.478, 0.596, 0.667, 0.40), 0.8, 0.1), false, false
	)
	CityKit.add_box(
		holder, "SignBoard", Vector3(front.x, 5.2, front.z),
		along * 11.0 + Vector3(0.0, 1.5, 0.0) + facing.abs() * 0.3,
		CityKit.make_material(Color(0.129, 0.161, 0.220)), false, false
	)
	CityKit.add_box(
		holder, "SignText", Vector3(front.x, 5.2, front.z - facing.z * 0.2 - facing.x * 0.2),
		along * 8.6 + Vector3(0.0, 0.55, 0.0) + facing.abs() * 0.1,
		CityKit.make_emissive_material(Color(0.906, 0.831, 0.588), 0.85), false, false
	)
	for i in 4:
		CityKit.add_box(
			holder, "Bollard%d" % i,
			Vector3(point.x - 6.0 + float(i) * 4.0, 0.45, point.z - facing.z * 2.6),
			Vector3(0.22, 0.9, 0.22), _mat("metal"), false, false
		)


## The furniture shop's door. A shopfront rather than a showroom: the interior
## behind it is small and full of things to look at.
func _make_furniture_door(point: Vector3, facing: Vector3) -> Portal:
	var street_marker := Marker3D.new()
	street_marker.name = "FurnitureStreetExit"
	street_marker.position = point + facing * 2.0 - Vector3(0.0, 0.8, 0.0)
	street_marker.add_to_group(FurnitureStoreInterior.EXIT_GROUP)
	_interactables.add_child(street_marker)

	var holder := Node3D.new()
	holder.name = "FurnitureFrontage"
	_geometry.add_child(holder)
	var along := Vector3(absf(facing.z), 0.0, absf(facing.x))
	var front := point - facing * 0.5
	CityKit.add_box(
		holder, "Window", Vector3(front.x, 1.9, front.z),
		along * 8.0 + Vector3(0.0, 2.6, 0.0) + facing.abs() * 0.2,
		CityKit.make_material(Color(0.545, 0.596, 0.612, 0.45), 0.7, 0.1), false, false
	)
	CityKit.add_box(
		holder, "SignBoard", Vector3(front.x, 3.7, front.z),
		along * 7.0 + Vector3(0.0, 1.1, 0.0) + facing.abs() * 0.3,
		CityKit.make_emissive_material(Color(0.741, 0.549, 0.353), 0.7), false, false
	)

	var door := Portal.new()
	door.destination_group = FurnitureStoreInterior.ENTRY_GROUP
	door.travel_minutes = 1
	door.override_camera = true
	door.camera_distance = 15.0
	door.camera_pitch = 70.0
	door.prompt_subtitle = "Kingston Furnishings"
	return door


## A door slab on the facade, so the prompt has something to point at.
func _add_door_panel(node_name: String, point: Vector3, facing: Vector3) -> void:
	var centre := point - facing * 0.6
	centre.y = 1.35
	var along := Vector3(absf(facing.z), 0.0, absf(facing.x))
	var size := along * 2.6 + Vector3(0.0, 2.8, 0.0) + facing.abs() * 0.3
	CityKit.add_box(_geometry, "DoorPanel_%s" % node_name, centre, size, _mat("door"), false)


## Everything that makes a pavement a place rather than a surface: seating,
## bins, planters, racks, meters, a shelter and the street names on posts.
##
## Placed off the walking routes on purpose. Nothing here is on a pavement lane
## the navigation graph uses — a bench in a walking lane is a queue of jammed
## pedestrians rather than a bench — so props sit against the kerb or against
## the buildings, and only the bollards and the shelter posts are solid.
func _build_street_props() -> void:
	var container := _make_container("StreetProps")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("CentralStreetProps")
	var kerb := ROAD_HALF + 1.1

	# Street names at the signalled junctions, so the map's road names exist in
	# the world as well.
	var junctions := [
		[Vector3(CENTER_BLVD_X + 8.0, 0.0, MARKET_ST_Z - 8.0), "MARKET ST"],
		[Vector3(CENTER_BLVD_X + 8.0, 0.0, KINGSTON_RD_Z - 8.0), "KINGSTON RD"],
		[Vector3(CENTER_BLVD_X + 8.0, 0.0, RIVERSIDE_DR_Z - 8.0), "RIVERSIDE DR"],
		[Vector3(PLAZA_ST_X - 8.0, 0.0, MARKET_ST_Z + 8.0), "PLAZA ST"],
		[Vector3(EXCHANGE_ST_X + 8.0, 0.0, KINGSTON_RD_Z + 8.0), "EXCHANGE ST"],
	]
	for entry in junctions:
		PropKit.street_sign(
			container, "Sign_%s" % String(entry[1]).replace(" ", ""),
			entry[0] as Vector3, String(entry[1]), rng.randf_range(-8.0, 8.0)
		)

	# Kerbside furniture down the three main streets, alternating so no stretch
	# is a row of the same object.
	var index := 0
	for road_z: float in [MARKET_ST_Z, KINGSTON_RD_Z, RIVERSIDE_DR_Z]:
		for x: float in [-96.0, -78.0, -54.0, -34.0, 20.0, 40.0, 62.0, 84.0, 100.0]:
			for side: float in [-1.0, 1.0]:
				var spot := Vector3(x, 0.0, road_z + side * kerb)
				if not BOUNDS.has_point(Vector2(spot.x, spot.z)):
					continue
				match index % 6:
					0:
						PropKit.bin(container, "Bin%d" % index, spot)
					1:
						PropKit.planter(
							container, "Planter%d" % index, spot, rng.randf_range(1.0, 1.35)
						)
					2:
						PropKit.parking_meter(container, "Meter%d" % index, spot)
					3:
						PropKit.bench(
							container, "Bench%d" % index, spot, 0.0 if side < 0.0 else 180.0
						)
					4:
						PropKit.hydrant(container, "Hydrant%d" % index, spot)
					_:
						PropKit.bike_rack(
							container, "Rack%d" % index, spot, 90.0
						)
				index += 1

	# A shelter on the boulevard, where somebody would actually wait.
	PropKit.shelter(
		container, "BoulevardShelter",
		Vector3(CENTER_BLVD_X + kerb + 1.4, 0.0, KINGSTON_RD_Z + 22.0), 90.0
	)

	# Outdoor seating on the plaza edge: three tables under the shopfronts,
	# which is the cue that Central is where people sit outside.
	for i in 3:
		PropKit.cafe_table(
			container, "PlazaTable%d" % i,
			Vector3(PLAZA.end.x + 3.2, 0.0, PLAZA.position.y + 5.0 + float(i) * 6.0),
			true
		)


# --- Parking -------------------------------------------------------------

## The private garage at the north end of the west car park. Six bays, twice
## Harbour Row's rent, and reached off the service road that is already there.
func _build_central_garage() -> void:
	var materials := {
		"wall": _mat("concrete"), "trim": _mat("metal"), "deck": _mat("asphalt"),
	}
	var garage := ServiceKit.build_garage(
		_geometry, _geometry, "CentralGarage",
		CityKit.rect_from_bounds(-114.0, -258.0, -98.0, -248.0), -248.0, 6, 180.0, materials
	)
	garage.garage_id = &"central_garage"
	garage.display_name = "Central Private Garage"
	garage.address = "Riverside Yard"
	garage.district_id = &"central"
	garage.capacity = 6
	garage.rent_amount = 620
	garage.deposit = 700
	garage.prompt_subtitle = "Central Private Garage"
	CityKit.attach_interactable(_interactables, garage, Vector3(-106.0, 1.0, -245.5), 4.5)


## Two surface car parks, behind the service roads and against the edge of the
## district. Central's kerbs are almost all double-yellow — "offices, shops and
## no parking" is what the district tells the player on the way in — so this is
## where a car goes while its owner is in a shop.
const CAR_PARK_ROWS := 5


func _build_parking() -> void:
	_build_central_garage()
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


## A counter built from one table line: "Name|KIND|opens|closes". Same shape as
## the harbour's, deliberately — the two districts share the venue table format
## and this is the half of it that reads a service.
func _make_service_point(payload: String) -> ServicePoint:
	var parts := payload.split("|")
	var point := ServicePoint.new()
	if parts.size() > 0:
		point.venue_name = parts[0]
	if parts.size() > 1:
		point.venue_kind = DistrictProps.service_kind(parts[1])
	if parts.size() > 2:
		point.opens_hour = int(parts[2])
	if parts.size() > 3:
		point.closes_hour = int(parts[3])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.4, 3.0)
	shape.shape = box
	point.add_child(shape)
	return point


## Two machines in Central: one on the plaza, one outside the depot.
##
## Central charges Central prices for everything else, and the machines are no
## different — the markup is the machine's, not the district's, so the two
## districts sell the same tin for the same money. That is deliberate: the
## thing that is expensive about Central is the rent, not the drink.
func _build_vending_machines() -> void:
	var stock := DistrictProps.machine_stock()
	var table := [
		# Mid-block, both of them. A machine parked in front of a letting board
		# hides the board and answers for it, which is worse than useless.
		["PlazaMachine", Vector3(-56.0, CityKit.CURB_HEIGHT, -167.2), 0.0, "Market Street"],
		["DepotMachine", Vector3(48.0, CityKit.CURB_HEIGHT, -222.2), 0.0, "Kingston Road"],
	]
	for entry in table:
		var machine := DistrictProps.vending_machine(
			stock, entry[1], entry[2], Color(0.36, 0.38, 0.42)
		)
		machine.name = entry[0]
		machine.shop_name = "Machine — %s" % entry[3]
		_interactables.add_child(machine)


## A shift job from one table line, named by its resource.
func _make_job_station(job_id: String) -> JobStation:
	var station := JobStation.new()
	station.job = load("res://jobs/definitions/%s.tres" % job_id)
	if station.job != null:
		station.prompt_subtitle = station.job.employer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 2.4, 3.0)
	shape.shape = box
	station.add_child(shape)
	return station


## Furniture down every pavement in the district.
##
## Central's streets were, at the Phase T2 camera, mostly blank light grey — a
## planting line and a frontage zone are what turn that into a street. Read off
## `street_lines()` so the two never disagree about where a pavement is.
func _build_street_dressing() -> void:
	var container := _make_container("StreetDressing")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5CD2
	var kit := _dressing_kit()
	# Everything that must stay walkable up to: doors, boards, job stations.
	var keep_clear: Array = []
	for group in [&"building_entrance", &"interactable", &"job_station"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is Node3D:
				keep_clear.append((node as Node3D).global_position)

	var index := 0
	for entry in street_lines():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from_v: float = entry[2]
		var to_v: float = entry[3]
		var half: float = entry[4]
		# Service roads are back lanes; they get nothing but the odd bin, which
		# `dress_run` gives them anyway by being short.
		for side: float in [-1.0, 1.0]:
			var kerb := centre + side * half
			var a: Vector3
			var b: Vector3
			var inward: Vector3
			if east_west:
				a = Vector3(from_v + 6.0, CURB_HEIGHT, kerb)
				b = Vector3(to_v - 6.0, CURB_HEIGHT, kerb)
				inward = Vector3(0.0, 0.0, side)
			else:
				a = Vector3(kerb, CURB_HEIGHT, from_v + 6.0)
				b = Vector3(kerb, CURB_HEIGHT, to_v - 6.0)
				inward = Vector3(side, 0.0, 0.0)
			StreetDressing.dress_run(
				container, "Run%d" % index, a, b, inward, WALK_WIDTH, rng, kit, keep_clear
			)
			index += 1


## The materials the dressing draws with, in this district's own palette.
func _dressing_kit() -> Dictionary:
	return {
		"soil": Palette.of(&"soil"),
		"kerb": Palette.of(&"kerb"),
		"bark": Palette.of(&"bark"),
		"foliage": [
			Palette.of(&"foliage_mid"),
			Palette.of(&"foliage_deep"),
			Palette.of(&"foliage_light"),
		],
		"metal": Palette.of(&"metal_mid"),
		"metal_dark": Palette.of(&"metal_dark"),
		"glass": Palette.of(&"glass_dark"),
		"stone": Palette.of(&"stone_trim"),
		"wood": Palette.of(&"wood_dark"),
	}
