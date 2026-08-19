extends Node
## Dev tool: renders the main scene to a PNG so the game can be eyeballed
## without a desktop, e.g. from CI or a headless dev box.
##
##   xvfb-run -a godot --rendering-driver opengl3 --path game \
##       res://tests/screenshot.tscn ++ out=shot.png hour=8.5 scenario=apartment
##
## Args after `++` are key=value pairs, all optional:
##   out       output PNG path
##   hour      hour of the in-game day, e.g. 22.5
##   scenario  street (default), apartment, shop, store_interior, shoplifting,
##             robbery, trespassing, carjacking, carjack_victim, melee, weapon,
##             incapacitated, three_stars, police_response, fear_crowd,
##             crime_overlay, vacant_property, property_rental, empty_store,
##             business_creation, equipment_buy, equipment_place,
##             business_storage, stocked_shelf, pricing_screen, store_open,
##             customers_browsing, checkout_queue, player_register,
##             employee_cashier, business_dashboard, daily_report, player_away,
##             driving_business, inventory, warehouse, car,
##             driving, theft, crowd, unseen_theft, witness, wanted, pursuit,
##             escaping, cleared, busted, night_chase, traffic, vehicle_types,
##             red_light, green_light, crossing, pedestrian_reacts,
##             driving_traffic, traffic_crash, pursuit_traffic, police_lights,
##             escaping_traffic, night_traffic, city_overview, harbour_row,
##             central_district, district_road, central_street, central_plaza,
##             traffic_crossing, central_pedestrians, city_map, map_filters,
##             map_route, central_property, large_interior, better_apartment,
##             courier_delivery, vehicle_roster, harbour_business,
##             central_business, city_empire, cross_district_chase, central_night
##   distance  camera distance override, for overview shots
##   yaw       camera yaw override
##   pitch     camera pitch override
##
## Note: this runs under the Compatibility renderer, so SSAO is skipped and
## lighting is close to, but not identical to, the Forward+ game.

const MAIN_SCENE := preload("res://main.tscn")
const BASIC_MEAL := preload("res://items/definitions/basic_meal.tres")
const SNACK_BAR := preload("res://items/definitions/snack_bar.tres")
const ENERGY_DRINK := preload("res://items/definitions/energy_drink.tres")
const PIPE := preload("res://items/definitions/steel_pipe.tres")
const TRAFFIC_CAR := preload("res://vehicles/cars/sedan.tscn")

var _args: Dictionary = {}


func _ready() -> void:
	_parse_args()

	# Set the clock before the scene exists so the HUD reads the right time
	# when it builds its labels.
	TimeManager.set_total_minutes(_number("hour", 9.0) * 60.0)
	TimeManager.clock_stopped = true

	var main := MAIN_SCENE.instantiate()
	add_child(main)

	var rig: TopDownCamera = main.get_node("CameraRig")
	await _wait(20)
	await _setup_scenario(main, String(_args.get("scenario", "street")))

	# Camera overrides come last so a scenario cannot undo them.
	if _args.has("distance"):
		rig.max_distance = 400.0
		rig.distance = _number("distance", rig.distance)
	if _args.has("yaw"):
		rig.yaw_degrees = _number("yaw", rig.yaw_degrees)
	if _args.has("pitch"):
		rig.pitch_degrees = _number("pitch", rig.pitch_degrees)

	await _wait(20)
	await RenderingServer.frame_post_draw

	var output_path := String(_args.get("out", "user://screenshot.png"))
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("Could not write %s (error %d)" % [output_path, error])
		get_tree().quit(1)
		return
	print("Wrote ", output_path)
	get_tree().quit(0)


## Drives the real interactables rather than faking their results, so a
## screenshot cannot show something the game would not actually do.
func _setup_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	if player == null:
		return
	var district: Node3D = main.get_node("District01")

	match scenario:
		"apartment":
			var door: Portal = district.get_node("Interactables/ApartmentDoor")
			door.interact(player)
			await _wait(20)
			# Stand back from the door so the whole flat is in frame.
			player.global_position += Vector3(0.0, 0.0, -2.0)

		"shop", "store_interior", "shoplifting", "robbery":
			# Through the real doorway, so the shot is of the room the player
			# actually walks into.
			player.global_position = Vector3(-38.0, 0.5, -11.6)
			await _wait(16)
			(district.get_node("Interactables/MarketDoor") as Portal).interact(player)
			await _wait(20)
			var store: ConvenienceStoreInterior = main.get_node("Interiors/ConvenienceStore")
			var counter := store.get_shop()
			match scenario:
				"store_interior":
					player.global_position = store.global_position + Vector3(0.0, 0.5, 2.6)
				"shoplifting":
					var shelf: MerchandiseShelf = store.get_node("Shelf0")
					player.global_position = shelf.global_position + Vector3(0.0, -0.5, 0.9)
					await _wait(10)
					shelf.interact(player)
					await _wait(10)
				"robbery":
					player.global_position = counter.global_position + Vector3(0.0, 0.0, 1.0)
					await _wait(10)
					counter.rob(player)
					await _wait(70)
				_:
					player.global_position = counter.global_position + Vector3(0.0, 0.0, 1.2)
					await _wait(16)
					counter.interact(player)

		"inventory":
			var inventory: Inventory = player.call("get_inventory")
			inventory.add(BASIC_MEAL, 2)
			inventory.add(SNACK_BAR, 1)
			inventory.add(ENERGY_DRINK, 3)
			await _wait(4)
			main.get_node("HUD/InventoryPanel").open(player)

		"warehouse":
			player.global_position = Vector3(-58.0, 0.5, 13.4)

		"car":
			var car := _find_vehicle(true)
			player.global_position = car.global_transform * Vector3(-2.1, 0.5, 0.4)

		"driving", "driving_night":
			var car := _find_vehicle(true)
			# A clear eastbound run along Main Street, toward the junction.
			car.global_position = Vector3(-45.0, 0.0, 3.0)
			car.rotation_degrees.y = -90.0
			car.halt()
			await _wait(10)
			car.enter(player)
			# Throttle stays down through the capture, so the speedometer and
			# the speed zoom are both showing real values.
			Input.action_press("move_forward")
			# ~2.2s: long enough to reach top speed and for the camera's speed
			# zoom to settle, short enough to still be short of the junction.
			await _wait(130)

		"crowd":
			player.global_position = Vector3(-8.4, 0.5, 20.0)

		"unseen_theft", "witness", "wanted", "pursuit", "escaping", "cleared", \
		"busted", "night_chase":
			await _crime_scenario(main, scenario)

		"traffic":
			# Stood on the corner of the Main Street junction, looking down the
			# street the traffic manager has already filled.
			player.global_position = Vector3(-11.5, 0.5, 8.4)
			await _wait(300)

		"vehicle_types":
			# One of each body style, nose to tail in the southbound lane of the
			# quiet end of the boulevard, with the traffic cleared away so the
			# three shapes are the only thing in frame.
			var manager := _traffic_manager()
			manager.set_active(false)
			manager.clear()
			await _wait(6)
			var styles := [
				["res://vehicles/cars/sedan.tscn", 58.0, Color(0.514, 0.208, 0.196)],
				["res://vehicles/cars/hatchback.tscn", 66.0, Color(0.259, 0.310, 0.376)],
				["res://vehicles/cars/van.tscn", 74.5, Color(0.702, 0.706, 0.722)],
			]
			for entry in styles:
				var car: Vehicle = load(entry[0]).instantiate()
				car.position = Vector3(
					District01.CENTER_BLVD_X - District01.LANE_OFFSET, 0.0, float(entry[1])
				)
				# Southbound: forward is +Z, which is a half turn from the default.
				car.rotation_degrees.y = 180.0
				var tinted: VehicleData = car.data.duplicate()
				tinted.body_color = entry[2]
				car.data = tinted
				add_child(car)
			# Stood in the lane beside them, so the camera frames the three
			# shapes rather than the pavement it would centre on.
			player.global_position = Vector3(
				District01.CENTER_BLVD_X - District01.LANE_OFFSET - 3.2, 0.5, 66.0
			)

		"red_light", "green_light":
			var light := _main_street_signal()
			light.green_seconds = 600.0
			light.start_phase = (
				TrafficLight.Phase.NS_GREEN if scenario == "red_light"
				else TrafficLight.Phase.EW_GREEN
			)
			light.restart_cycle()
			# A queue approaching the junction from the west, in the eastbound
			# lane. On red they stack up at the line; on green they stream past.
			var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
			var tints := [
				Color(0.514, 0.208, 0.196),
				Color(0.259, 0.310, 0.376),
				Color(0.647, 0.549, 0.361),
			]
			for i in 3:
				_add_traffic_car(
					load("res://vehicles/cars/sedan.tscn"),
					Vector3(-26.0 - float(i) * 7.5, 0.0, lane_z),
					-90.0,
					tints[i]
				)
			player.global_position = Vector3(-13.0, 0.5, 8.4)
			await _wait(260)

		"crossing":
			# A civilian walking the painted crossing on the west arm of the
			# junction, driven by the real navigation graph.
			var walker: Pedestrian = get_tree().get_nodes_in_group(&"pedestrian")[0]
			walker.global_position = Vector3(-7.6, 0.4, 8.4)
			await _wait(6)
			walker.walk_to(Vector3(-7.6, 0.0, -8.4))
			player.global_position = Vector3(-15.0, 0.5, 8.4)
			await _wait(200)

		"pedestrian_reacts":
			# Somebody stood in the eastbound lane of Main Street with a car
			# coming, on a road cleared of everything else so the reaction is
			# the only thing happening in frame.
			var manager := _traffic_manager()
			manager.set_active(false)
			manager.clear()
			var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
			var walker: Pedestrian = get_tree().get_nodes_in_group(&"pedestrian")[0]
			# Just north of the lane centre, so they jump towards the middle of
			# the road rather than straight onto the pavement — the reaction is
			# what the shot is of, and on the pavement it no longer reads as one.
			walker.global_position = Vector3(-40.0, 0.4, lane_z - 0.9)
			walker.wait_for(60.0)
			player.global_position = Vector3(-44.0, 0.5, District01.PAVEMENT_OFFSET)
			await _wait(8)
			var car := _add_traffic_car(
				load("res://vehicles/cars/sedan.tscn"),
				Vector3(-64.0, 0.0, lane_z),
				-90.0,
				Color(0.514, 0.208, 0.196)
			)
			# Driven by hand rather than by the lane follower, so the car is
			# where the shot needs it rather than wherever its route took it.
			(car.get_node("Driver") as TrafficDriver).set_physics_process(false)
			car.set_ai_input(1.0, 0.0, false)
			# Caught part way through the jump, with the car still bearing down:
			# any later and the shot is of an empty road and a safe pedestrian.
			await _wait(100)

		"driving_traffic":
			var car := _find_vehicle(true)
			car.global_position = Vector3(-52.0, 0.0, District01.MAIN_ST_Z + District01.LANE_OFFSET)
			car.rotation_degrees.y = -90.0
			car.halt()
			await _wait(10)
			car.enter(player)
			Input.action_press("move_forward")
			await _wait(150)

		"traffic_crash":
			var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
			# One car stopped across the lane, another arriving at speed. The
			# collision is the game's, not a staged pose.
			var blocker := _add_traffic_car(
				load("res://vehicles/cars/van.tscn"),
				Vector3(-30.0, 0.0, lane_z),
				-25.0,
				Color(0.702, 0.706, 0.722)
			)
			(blocker.get_node("Driver") as TrafficDriver).set_physics_process(false)
			blocker.set_ai_input(0.0, 0.0, true)
			var runner := _add_traffic_car(
				load("res://vehicles/cars/sedan.tscn"),
				Vector3(-52.0, 0.0, lane_z),
				-90.0,
				Color(0.514, 0.208, 0.196)
			)
			# Sensors off: this shot is of the impact, not of the car avoiding it.
			(runner.get_node("Driver") as TrafficDriver).set_physics_process(false)
			runner.set_ai_input(1.0, 0.0, false)
			player.global_position = Vector3(-34.0, 0.5, 9.4)
			await _wait(112)

		"pursuit_traffic", "police_lights", "escaping_traffic", "night_traffic":
			await _crime_scenario(main, scenario, false)

		"city_overview", "harbour_row", "central_district", "district_road", \
		"central_street", "central_plaza", "traffic_crossing", "central_pedestrians", \
		"city_map", "map_filters", "map_route", "central_property", \
		"large_interior", "better_apartment", "courier_delivery", "vehicle_roster", \
		"central_night", "cross_district_chase":
			await _run_city_scenario(main, scenario)

		"harbour_business", "central_business", "city_empire":
			await _run_city_business_scenario(main, scenario)

		"commercial_properties", "portfolio", "market_operating", "coffee_empty", \
		"coffee_placement", "ingredient_order", "coffee_customers", "barista", \
		"stocker", "manager_running", "order_in_transit", "delivery_received", \
		"marketing", "upgrades", "two_businesses", "empire_finance", \
		"business_value", "loans", "net_worth", "player_away_empire":
			await _run_empire_scenario(main, scenario)

		"vacant_property", "property_rental":
			# With enough in the bank to actually sign, so the shot shows the
			# offer rather than the shortfall warning.
			EconomyManager.restore(4000)
			var door := _property_door()
			player.global_position = Vector3(-20.0, 0.5, -10.2)
			await _wait(20)
			if scenario == "property_rental":
				door.interact(player)
				await _wait(10)

		"empty_store", "business_creation":
			EconomyManager.restore(6000)
			var door := _property_door()
			PropertyManager.lease(door)
			await _wait(6)
			if scenario == "business_creation":
				player.global_position = Vector3(-20.0, 0.5, -10.2)
				await _wait(16)
				door.interact(player)
				await _wait(10)
			else:
				door.interact(player)
				await _wait(20)

		"equipment_buy", "equipment_place", "business_storage", "pricing_screen", \
		"business_dashboard", "stocked_shelf", "store_open", "customers_browsing", \
		"checkout_queue", "player_register", "employee_cashier", "daily_report", \
		"player_away", "driving_business":
			await _run_business_scenario(main, scenario)

		"trespassing":
			var store: ConvenienceStoreInterior = main.get_node("Interiors/ConvenienceStore")
			(district.get_node("Interactables/MarketDoor") as Portal).interact(player)
			await _wait(16)
			var staff: RestrictedArea = store.get_node("BehindTheCounter")
			player.global_position = staff.global_position + Vector3(0.0, -0.9, 0.0)
			# Long enough for the warning and the offence itself.
			await _wait(int(staff.grace_seconds * 60.0) + 40)

		"carjacking", "carjack_victim":
			var jacked := await _occupied_car(main, Vector3(0.0, 0.0, 26.0), 0.0)
			player.global_position = jacked.global_transform * Vector3(-2.1, 0.5, 0.2)
			await _wait(8)
			if scenario == "carjacking":
				# Stood at the door of an occupied car, prompt on screen.
				return
			jacked.get_node("Door").interact(player)
			await _wait(40)

		"melee", "weapon", "incapacitated":
			# No officers: a beating in front of a patrolling one ends in an
			# arrest half way through, which is the systems working correctly and
			# the wrong photograph.
			for unit in get_tree().get_nodes_in_group(&"police"):
				unit.process_mode = Node.PROCESS_MODE_DISABLED
			var combat: CombatController = player.get_node("Combat")
			player.global_position = Vector3(-30.0, 0.5, 12.0)
			await _wait(8)
			if scenario != "melee":
				var inventory: Inventory = player.call("get_inventory")
				inventory.add(PIPE, 1)
				player.call("equip_item", PIPE)
			var victim: Pedestrian = get_tree().get_nodes_in_group(&"pedestrian")[0]
			victim.global_position = player.global_position + player.call("get_facing") * 1.5
			victim.wait_for(60.0)
			await _wait(8)
			if scenario == "weapon":
				return
			var swings := 1 if scenario == "melee" else 5
			for i in swings:
				combat.attack()
				await _wait(int(combat.get_active_weapon().cooldown * 60.0) + 8)
				if scenario == "incapacitated" and not victim.is_incapacitated():
					victim.global_position = player.global_position + player.call("get_facing") * 1.4
					await _wait(4)

		"three_stars", "police_response", "fear_crowd":
			player.global_position = Vector3(-30.0, 0.5, 6.0)
			await _wait(8)
			for type in [
				CrimeManager.CrimeType.VEHICLE_THEFT,
				CrimeManager.CrimeType.CARJACKING,
				CrimeManager.CrimeType.STORE_ROBBERY,
			]:
				var record := CrimeManager.report_crime(type, player.global_position, player, null)
				CrimeManager.mark_witnessed(record, player)
				CrimeManager.mark_reported(record)
				WantedManager.on_crime_reported(record)
			await _wait(20 if scenario == "three_stars" else 150)

		"crime_overlay":
			main.get_node("CrimeDebug").toggle()
			main.get_node("TrafficDebug").toggle()
			var inventory: Inventory = player.call("get_inventory")
			inventory.add(PIPE, 1)
			player.call("equip_item", PIPE)
			WantedManager.add_points(55, player.global_position)
			CrimeManager.report_crime(
				CrimeManager.CrimeType.SHOPLIFTING, player.global_position, player, null
			)
			await _wait(30)

		"theft":
			var car := _find_vehicle(false)
			car.global_position = Vector3(-30.0, 0.0, 3.0)
			car.rotation_degrees.y = -90.0
			car.halt()
			await _wait(10)
			player.global_position = car.global_transform * Vector3(-2.1, 0.5, 0.4)
			await _wait(10)
			# Driven through the real door interactable, so the toast on screen
			# is the one the game actually posts.
			car.get_node("Door").interact(player)

	await _wait(20)


## Drives the real crime loop for the screenshots, so nothing on screen is
## staged: the theft, the witness, the wanted level and the arrest are all
## produced by the same systems the player triggers.
## `quiet_streets` empties the pavements first, which the Phase E shots want so
## that exactly one witness is in play. The Phase F variants pass false: the
## whole point of those is that the city carries on around the chase.
func _crime_scenario(main: Node, scenario: String, quiet_streets: bool = true) -> void:
	var player: Node3D = GameManager.player
	var car := _find_vehicle(false)
	var spot := Vector3(-40.0, 0.0, District01.MAIN_ST_Z + District01.LANE_OFFSET)

	# The Phase F variants are the Phase E ones played out on a living street.
	var kind: String = {
		"pursuit_traffic": "pursuit",
		"police_lights": "pursuit",
		"night_traffic": "pursuit",
		"escaping_traffic": "escaping",
	}.get(scenario, scenario)

	if quiet_streets:
		# Clear the street so the scenario controls exactly who is watching.
		for npc in get_tree().get_nodes_in_group(&"pedestrian") + get_tree().get_nodes_in_group(&"police"):
			if npc is Node3D:
				npc.global_position = Vector3(400.0, 0.0, 400.0)
			npc.process_mode = Node.PROCESS_MODE_DISABLED
		await _wait(4)

	car.global_position = spot
	car.rotation_degrees.y = -90.0
	car.halt()
	player.global_position = car.global_transform * Vector3(-2.1, 0.5, 0.4)
	await _wait(8)

	if kind != "unseen_theft":
		# One civilian, stood on the pavement, looking straight at the car.
		var civilian: Pedestrian = get_tree().get_nodes_in_group(&"pedestrian")[0]
		civilian.process_mode = Node.PROCESS_MODE_INHERIT
		civilian.global_position = spot + Vector3(7.0, 0.4, 5.4)
		# Stood still and looking at the car. On a live street they would
		# otherwise stroll off between being placed and the theft happening,
		# and the shot would come back with no wanted level on it at all.
		civilian.wait_for(60.0)
		civilian.get_node("BodyPivot").rotation.y = atan2(-7.0, -5.4)
		await _wait(6)

	car.get_node("Door").interact(player)
	await _wait(10)
	if kind in ["unseen_theft", "witness"]:
		return

	# Let the witness call it in.
	await _wait(int((WitnessSystem.report_delay + 0.6) * 60.0))
	if kind == "wanted":
		return

	var officers: Array = get_tree().get_nodes_in_group(&"police").filter(
		func(u: Node) -> bool: return u is PoliceOfficer
	)
	var cars: Array = get_tree().get_nodes_in_group(&"police_car")

	if kind == "escaping" or kind == "cleared":
		# Nobody within sight: the countdown runs on its own.
		WantedManager.escape_seconds_by_level = [0.0, 4.0, 6.0, 8.0, 10.0, 12.0]
		for unit in officers + cars:
			unit.process_mode = Node.PROCESS_MODE_INHERIT
			unit.global_position = player.global_position + Vector3(58.0, 0.0, 0.0)
		if not quiet_streets:
			# Traffic and the crowd carry on; the police are the one thing that
			# has to be out of the picture, or a unit driving back into sight
			# cancels the very countdown the shot is of.
			for unit in officers + cars:
				unit.process_mode = Node.PROCESS_MODE_DISABLED
		await _wait(int((WantedManager.sight_grace_seconds + 0.6) * 60.0))
		if kind == "escaping":
			if not quiet_streets:
				# On the move, so the street around the countdown is alive too.
				Input.action_press("move_forward")
				await _wait(45)
				Input.action_release("move_forward")
				await _wait(20)
			return
		await _wait(int(4.5 * 60.0))
		return

	# Pursuit and arrest: wake a patrol car and an officer near the player.
	for i in cars.size():
		var unit: Node3D = cars[i]
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		# Behind the player, in the same lane, pointing the way they went.
		unit.global_position = player.global_position + Vector3(-7.5 - float(i) * 6.5, 0.0, 0.0)
		unit.rotation_degrees.y = -90.0
		unit.halt()
	var officer: Node3D = officers[0]
	officer.process_mode = Node.PROCESS_MODE_INHERIT

	if kind == "busted":
		officer.global_position = player.global_position + Vector3(1.8, 0.0, 0.0)
		await _wait(40)
		return

	# Far enough ahead not to make the arrest: a player at speed cannot be
	# arrested anyway, but on a live street the countdown to one is a race the
	# capture keeps losing.
	officer.global_position = player.global_position + Vector3(
		13.0 if quiet_streets else 34.0, 0.0, 4.0
	)
	# Throttle stays down, so the capture lands mid-chase rather than on the
	# arrest that follows it.
	Input.action_press("move_forward")
	await _wait(50)


## A civilian car with somebody at the wheel, parked and held still, so the shot
## is of a carjacking rather than of a car driving off mid-frame.
func _occupied_car(main: Node, at: Vector3, yaw_degrees: float) -> Vehicle:
	var car: Vehicle = TRAFFIC_CAR.instantiate()
	car.controller = Vehicle.Controller.TRAFFIC_AI
	car.owner_type = Vehicle.OwnerType.NPC
	car.owner_id = &"traffic"
	car.driver_type = Vehicle.DriverType.CIVILIAN
	car.driver_state = Vehicle.DriverState.SEATED
	car.driver_id = &"shot_driver"
	car.driver_color = Color(0.545, 0.400, 0.353)
	car.position = at
	car.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	main.add_child(car)

	var driver := TrafficDriver.new()
	driver.name = "Driver"
	car.add_child(driver)
	await _wait(4)
	driver.set_physics_process(false)
	car.set_ai_input(0.0, 0.0, true)
	car.halt()
	await _wait(6)
	return car


## Builds the two-business empire the Phase I shots are of, driving the real
## systems: the leases are signed, the equipment is bought and placed, the stock
## is ordered and delivered, the staff are hired, and both shops open.
func _run_empire_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	EconomyManager.restore(60000)

	if scenario == "commercial_properties":
		# Stood in the middle of Main Street, with the units either side.
		player.global_position = Vector3(10.0, 0.5, -8.0)
		await _wait(16)
		return

	# --- Silas Market ---
	var market_door := _property_door()
	PropertyManager.lease(market_door)
	var market := BusinessManager.create_business("Silas Market", &"convenience_store", market_door)
	BusinessManager.deposit_to_business(market, 8000)
	market_door.interact(player)
	await _wait(16)
	var market_unit: RetailUnit = main.get_node("Interiors/MainStreetUnit")
	var controller: PlacementController = main.get_node("PlacementController")
	var dashboard: Control = main.get_node("HUD/BusinessDashboard")
	var empire: Control = main.get_node("HUD/EmpireDashboard")

	for id in [&"checkout_counter", &"retail_shelf", &"retail_shelf", &"storage_rack"]:
		BusinessManager.buy_equipment(market, id)
	controller.begin(market, market_unit, &"checkout_counter")
	controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0)
	controller.begin(market, market_unit, &"retail_shelf")
	controller.place_at(Vector3(-4.0, 0.0, 2.0), 90.0)
	controller.begin(market, market_unit, &"retail_shelf")
	controller.place_at(Vector3(4.0, 0.0, 2.0), 90.0)
	controller.begin(market, market_unit, &"storage_rack")
	controller.place_at(Vector3(0.0, 0.0, -4.0), 0.0)
	BusinessManager.order_stock(market, &"bottled_water", 40)
	BusinessManager.order_stock(market, &"soda_can", 40)
	BusinessManager.order_stock(market, &"snack_bar", 30)
	BusinessManager.deliver_now(market)

	BusinessManager.refresh_candidates()
	var till: EmployeeData = BusinessManager.get_candidates()[1]
	BusinessManager.hire(market, till, EmployeeData.Role.CASHIER)
	till.shift_start_hour = 0
	till.shift_end_hour = 23
	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	await _wait(8)

	if scenario == "stocker":
		# Shelves bare, a stocker on shift, and the player watching them work.
		BusinessManager.refresh_candidates()
		var hand: EmployeeData = BusinessManager.get_candidates()[2]
		BusinessManager.hire(market, hand, EmployeeData.Role.STOCKER)
		hand.shift_start_hour = 0
		hand.shift_end_hour = 23
		for shelf in market.shelves():
			shelf.stock_quantity = 0
		market.changed.emit()
		player.global_position = market_unit.global_position + Vector3(3.0, 0.5, 3.0)
		await _wait(10)
		market_unit.call("_refresh_staff")
		await _wait(320)
		return

	for shelf in market.shelves():
		market.stock_shelf(shelf.slot_id, &"bottled_water" if shelf.slot_id % 2 == 0 else &"soda_can", 20)

	if scenario == "market_operating":
		var spawner := market_unit.get_spawner()
		player.global_position = market_unit.global_position + Vector3(0.0, 0.5, 4.0)
		await _wait(10)
		market_unit.call("_refresh_staff")
		for i in 3:
			spawner.spawn_customer_now()
			await _wait(40)
		await _wait(200)
		return

	if scenario == "manager_running":
		BusinessManager.refresh_candidates()
		var boss: EmployeeData = BusinessManager.get_candidates()[2]
		BusinessManager.hire(market, boss, EmployeeData.Role.MANAGER)
		market.auto_open = true
		market.auto_restock = true
		market.auto_order = true
		player.global_position = market_unit.global_position + Vector3(0.0, 0.5, 4.0)
		await _wait(10)
		market_unit.call("_refresh_staff")
		await _wait(60)
		dashboard.open(market)
		dashboard.show_tab(4)
		await _wait(6)
		return

	# --- Noel Coffee ---
	var coffee_door := PropertyManager.by_id(&"unit_harbour_42")
	PropertyManager.lease(coffee_door)
	var coffee := BusinessManager.create_business("Noel Coffee", &"coffee_shop", coffee_door)
	BusinessManager.deposit_to_business(coffee, 8000)
	var coffee_unit: RetailUnit = main.get_node("Interiors/HarbourAvenueUnit")
	coffee_unit.ensure_built()
	player.global_position = coffee_unit.global_position + Vector3(0.0, 0.5, 4.0)
	await _wait(16)

	if scenario == "coffee_empty":
		return

	for id in [&"service_counter", &"coffee_machine", &"ingredient_store"]:
		BusinessManager.buy_equipment(coffee, id)

	if scenario == "coffee_placement":
		controller.begin(coffee, coffee_unit, &"coffee_machine")
		await _wait(10)
		return

	controller.begin(coffee, coffee_unit, &"service_counter")
	controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0)
	controller.begin(coffee, coffee_unit, &"coffee_machine")
	controller.place_at(Vector3(-3.4, 0.0, 1.0), 180.0)
	controller.begin(coffee, coffee_unit, &"ingredient_store")
	controller.place_at(Vector3(0.0, 0.0, -5.0), 0.0)
	await _wait(8)

	if scenario == "ingredient_order":
		dashboard.open(coffee)
		dashboard.show_tab(1)
		await _wait(6)
		return

	if scenario == "order_in_transit":
		for ingredient in [&"coffee_beans", &"milk_carton", &"paper_cup"]:
			BusinessManager.order_stock(coffee, ingredient, 30)
		dashboard.open(coffee)
		dashboard.show_tab(1)
		await _wait(6)
		return

	for ingredient in [&"coffee_beans", &"milk_carton", &"paper_cup", &"tea_leaves"]:
		BusinessManager.order_stock(coffee, ingredient, 30)
	BusinessManager.deliver_now(coffee)

	if scenario == "delivery_received":
		BusinessManager.order_stock(coffee, &"coffee_beans", 20)
		BusinessManager.deliver_now(coffee)
		dashboard.open(coffee)
		dashboard.show_tab(1)
		await _wait(6)
		return

	BusinessManager.refresh_candidates()
	var barista: EmployeeData = BusinessManager.get_candidates()[2]
	BusinessManager.hire(coffee, barista, EmployeeData.Role.BARISTA)
	barista.shift_start_hour = 0
	barista.shift_end_hour = 23
	coffee.manual_override = BusinessInstance.Override.FORCE_OPEN
	coffee.set_open(true)
	await _wait(8)

	match scenario:
		"marketing":
			dashboard.open(coffee)
			dashboard.show_tab(5)
			await _wait(6)
			return
		"upgrades":
			BusinessManager.start_campaign(coffee, &"social")
			dashboard.open(coffee)
			dashboard.show_tab(5)
			await _wait(6)
			return
		"business_value":
			for i in 4:
				BusinessManager.simulate_hour_now(market, 12)
				BusinessManager.simulate_hour_now(coffee, 12)
			market.end_day(TimeManager.day_index)
			coffee.end_day(TimeManager.day_index)
			for i in 3:
				BusinessManager.simulate_hour_now(coffee, 12)
			dashboard.open(coffee)
			dashboard.show_tab(0)
			await _wait(6)
			return
		"loans":
			BusinessManager.take_loan(market, &"starter")
			empire.open()
			empire.show_tab(4)
			await _wait(6)
			return

	# Everything from here wants a couple of hours of trading behind it, on a
	# fresh day: day one is all fit-out costs and shows nothing about how the
	# businesses actually run.
	market.end_day(TimeManager.day_index)
	coffee.end_day(TimeManager.day_index)
	for i in 5:
		BusinessManager.simulate_hour_now(market, 12)
		BusinessManager.simulate_hour_now(coffee, 12)

	match scenario:
		"portfolio":
			empire.open()
			empire.show_tab(1)
			await _wait(6)
			return
		"empire_finance":
			empire.open()
			empire.show_tab(3)
			await _wait(6)
			return
		"net_worth":
			BusinessManager.take_loan(market, &"starter")
			empire.open()
			empire.show_tab(0)
			await _wait(6)
			return
		"player_away_empire":
			GameManager.teleport_player(
				Transform3D(Basis(), Vector3(-30.0, 0.5, 8.4))
			)
			await _wait(20)
			for i in 2:
				BusinessManager.simulate_hour_now(market, 13)
				BusinessManager.simulate_hour_now(coffee, 13)
			return

	# "coffee_customers", "barista" and "two_businesses": in the coffee shop
	# with people in it.
	var coffee_spawner := coffee_unit.get_spawner()
	player.global_position = coffee_unit.global_position + Vector3(2.0, 0.5, 4.0)
	await _wait(10)
	coffee_unit.call("_refresh_staff")
	await _wait(60)
	for i in 4:
		coffee_spawner.spawn_customer_now()
		await _wait(35)
	await _wait(240)


# --- Phase J: the wider city ---------------------------------------------

## The shots of the expanded world. Nothing here fakes a view: the districts are
## the ones the game builds, the map is the real map with the real markers on
## it, and the police chase is the wanted system doing what it does.
func _run_city_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: CanvasLayer = main.get_node("HUD")
	var central := WorldManager.by_id(&"central")
	var centre := Vector3(0.0, 0.5, -215.0) if central == null else Vector3(
		central.center_position.x, 0.5, central.center_position.z
	)

	match scenario:
		"city_overview":
			# Halfway between the two districts, looking down on all of it. The
			# camera distance comes from the command line. The wait is long
			# enough for the district banner to fade off the top of the frame.
			player.global_position = Vector3(0.0, 0.5, -140.0)
			await _wait(260)

		"harbour_row":
			player.global_position = Vector3(0.0, 0.5, -10.0)
			await _wait(180)

		"central_district", "central_night":
			player.global_position = centre
			await _wait(240)

		"district_road":
			# On the connecting boulevard, with Harbour Row's gateway behind and
			# Central ahead.
			player.global_position = Vector3(
				District02.CENTER_BLVD_X + 3.0, 0.5, District02.GATEWAY_Z + 6.0
			)
			await _wait(180)

		"central_street":
			player.global_position = Vector3(
				-20.0, 0.5, District02.MARKET_ST_Z - District02.WALK_WIDTH - 3.0
			)
			await _wait(320)

		"central_plaza":
			player.global_position = District02.MONUMENT + Vector3(9.0, 0.5, 9.0)
			await _wait(180)

		"traffic_crossing":
			# Cars put onto the boulevard either side of the district line, then
			# left to drive it under their own AI.
			_traffic_manager().prime()
			for i in 3:
				var lane := District02.CENTER_BLVD_X - District02.LANE_OFFSET
				_add_traffic_car(
					load("res://vehicles/cars/hatchback.tscn"),
					Vector3(lane, 0.0, District02.GATEWAY_Z + 26.0 - float(i) * 13.0),
					180.0,
					Color(0.514, 0.463, 0.361)
				)
			player.global_position = Vector3(
				District02.CENTER_BLVD_X + 12.0, 0.5, District02.GATEWAY_Z + 4.0
			)
			await _wait(220)

		"central_pedestrians":
			player.global_position = Vector3(
				District02.PLAZA_ST_X + 12.0, 0.5, District02.KINGSTON_RD_Z - 9.0
			)
			await _wait(400)

		"city_map", "map_filters", "map_route":
			player.global_position = centre
			await _wait(60)
			if scenario == "map_route":
				MapManager.set_destination(_marker_named("Silas Market", "18 Main Street"))
			if scenario == "map_filters":
				MapManager.set_category_shown(MapMarker.Category.SHOP, false)
				MapManager.set_category_shown(MapMarker.Category.POLICE, false)
			var map: Control = hud.get_node("CityMap")
			map.open()
			await _wait(10)

		"central_property":
			EconomyManager.restore(12000)
			var unit := PropertyManager.by_id(&"unit_plaza_03")
			player.global_position = unit.global_position + Vector3(0.0, 0.5, 3.2)
			await _wait(20)
			unit.interact(player)
			await _wait(12)

		"large_interior":
			EconomyManager.restore(12000)
			var unit := PropertyManager.by_id(&"unit_plaza_03")
			PropertyManager.lease(unit)
			await _wait(6)
			unit.interact(player)
			await _wait(24)
			var room: RetailUnit = main.get_node("Interiors/PlazaUnit")
			player.global_position = room.global_position + Vector3(0.0, 0.5, 4.0)
			await _wait(20)

		"better_apartment":
			EconomyManager.restore(4000)
			var flat := PropertyManager.residence_by_id(&"meridian")
			PropertyManager.lease_residence(flat)
			flat.set_as_home()
			await _wait(6)
			flat.interact(player)
			await _wait(24)
			player.global_position += Vector3(0.0, 0.0, -2.0)
			await _wait(12)

		"courier_delivery":
			# A real run: the job picks its own destination and the HUD shows
			# the distance to it.
			player.global_position = centre
			await _wait(20)
			CourierJob.offer_run()
			await _wait(10)
			var car := _find_vehicle(true)
			car.global_position = centre + Vector3(0.0, 0.0, 4.0)
			car.rotation_degrees.y = 180.0
			car.halt()
			await _wait(10)
			car.enter(player)
			Input.action_press("move_forward")
			await _wait(90)

		"vehicle_roster":
			# One of each civilian model, nose to tail down the quiet end of
			# Central Boulevard with the traffic cleared away. Parked by hand and
			# given no driver, so they are still there when the shot is taken.
			var manager := _traffic_manager()
			manager.set_active(false)
			manager.clear()
			await _wait(6)
			var lane := District02.CENTER_BLVD_X - District02.LANE_OFFSET
			var ids := VehicleCatalogue.ids()
			var spacing := 7.0
			var first := District02.RIVERSIDE_DR_Z + 22.0
			for i in ids.size():
				var model: Vehicle = VehicleCatalogue.scene_for(ids[i]).instantiate()
				model.name = "Roster_%s" % ids[i]
				model.position = Vector3(lane, 0.0, first - float(i) * spacing)
				# Southbound: forward is +Z, which is a half turn from default.
				model.rotation_degrees.y = 180.0
				var tinted: VehicleData = model.data.duplicate()
				tinted.body_color = Color(0.62, 0.64, 0.67)
				model.data = tinted
				add_child(model)
			# Stood in the next lane along, level with the middle of the row.
			player.global_position = Vector3(
				lane - 3.4, 0.5, first - float(ids.size() - 1) * spacing * 0.5
			)
			# Long enough for the district banner to have faded off the top.
			await _wait(220)

		"cross_district_chase":
			await _cross_district_chase(main)


## A car stolen in Harbour Row, driven north over the district line with the
## police still on it. Everything here is the wanted system's own doing: the
## crime is reported through CrimeManager and the officers respond to it.
func _cross_district_chase(_main: Node) -> void:
	var player: Node3D = GameManager.player
	var car := _find_vehicle(false)
	# Northbound in the correct lane, with enough of a run-up to be travelling
	# too fast to be pulled out of the car before it reaches the district line.
	# The northbound lane, which is the one that leaves town: vehicles face -Z,
	# so northbound is yaw 0 and the lane is east of the centre line.
	var lane := District02.CENTER_BLVD_X + District02.LANE_OFFSET
	# Started on the approach to the connecting stretch, which is the one piece
	# of road with nothing parked on it: a stolen car that rear-ends a parked one
	# stops dead and the shot comes back as an arrest instead of a chase.
	car.global_position = Vector3(lane, 0.0, District02.GATEWAY_Z + 45.0)
	car.rotation_degrees.y = 0.0
	car.halt()
	player.global_position = car.global_transform * Vector3(-2.1, 0.5, 0.4)
	await _wait(10)
	car.enter(player)
	await _wait(10)

	var record := CrimeManager.report_crime(
		CrimeManager.CrimeType.VEHICLE_THEFT, player.global_position, player, car
	)
	CrimeManager.mark_witnessed(record, player)
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)
	await _wait(10)

	# The patrol cars start behind, in Harbour Row, and follow over the line.
	var patrols := get_tree().get_nodes_in_group(&"police_car")
	for i in patrols.size():
		var unit: Node3D = patrols[i]
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		unit.global_position = Vector3(
			lane, 0.0, car.global_position.z + 28.0 + float(i) * 12.0
		)
		unit.rotation_degrees.y = 0.0
	await _wait(10)

	Input.action_press("move_forward")
	await _wait(200)


## Silas Market in Harbour Row, a second shop in Central, and the dashboard that
## shows both. Built through the real systems, same as the Phase I shots.
func _run_city_business_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	EconomyManager.restore(80000)

	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	var central := _open_shop_at(
		main, &"unit_central_88", "Interiors/CentralBoulevardUnit", "Silas Market — Central"
	)

	var unit: RetailUnit = main.get_node(
		"Interiors/MainStreetUnit" if scenario == "harbour_business"
		else "Interiors/CentralBoulevardUnit"
	)

	if scenario == "city_empire":
		market.end_day(TimeManager.day_index)
		central.end_day(TimeManager.day_index)
		for i in 5:
			BusinessManager.simulate_hour_now(market, 12)
			BusinessManager.simulate_hour_now(central, 12)
		var empire: Control = main.get_node("HUD/EmpireDashboard")
		empire.open()
		empire.show_tab(1)
		await _wait(8)
		return

	var spawner := unit.get_spawner()
	player.global_position = unit.global_position + Vector3(0.0, 0.5, 4.0)
	await _wait(10)
	unit.call("_refresh_staff")
	for i in 3:
		spawner.spawn_customer_now()
		await _wait(40)
	await _wait(200)


## Leases a unit, fits it out, stocks it, staffs it and opens it. The same steps
## the player takes, in the order the systems expect them.
func _open_shop_at(
	main: Node, property_id: StringName, interior_path: String, shop_name: String
) -> BusinessInstance:
	var door := PropertyManager.by_id(property_id)
	PropertyManager.lease(door)
	var business := BusinessManager.create_business(shop_name, &"convenience_store", door)
	BusinessManager.deposit_to_business(business, 9000)

	var unit: RetailUnit = main.get_node(interior_path)
	unit.ensure_built()
	var controller: PlacementController = main.get_node("PlacementController")
	for id in [&"checkout_counter", &"retail_shelf", &"retail_shelf", &"storage_rack"]:
		BusinessManager.buy_equipment(business, id)
	controller.begin(business, unit, &"checkout_counter")
	controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0)
	controller.begin(business, unit, &"retail_shelf")
	controller.place_at(Vector3(-4.0, 0.0, 2.0), 90.0)
	controller.begin(business, unit, &"retail_shelf")
	controller.place_at(Vector3(4.0, 0.0, 2.0), 90.0)
	controller.begin(business, unit, &"storage_rack")
	controller.place_at(Vector3(0.0, 0.0, -4.0), 0.0)

	for id in [&"bottled_water", &"soda_can", &"snack_bar"]:
		BusinessManager.order_stock(business, id, 40)
	BusinessManager.deliver_now(business)
	for shelf in business.shelves():
		business.stock_shelf(
			shelf.slot_id, &"bottled_water" if shelf.slot_id % 2 == 0 else &"soda_can", 20
		)

	BusinessManager.refresh_candidates()
	var candidates := BusinessManager.get_candidates()
	BusinessManager.hire(business, candidates[0], EmployeeData.Role.CASHIER)
	candidates[0].shift_start_hour = 0
	candidates[0].shift_end_hour = 23
	business.manual_override = BusinessInstance.Override.FORCE_OPEN
	business.set_open(true)
	return business


## Finds one of the real map markers by name, for a shot of a route to it.
func _marker_named(label: String, fallback_detail: String) -> MapMarker:
	var markers := MapManager.collect_markers()
	for marker in markers:
		if marker.label == label or marker.detail == fallback_detail:
			return marker
	return markers[0] if not markers.is_empty() else null


func _property_door() -> CommercialProperty:
	return PropertyManager.by_id(&"unit_main_18")


## Builds a player-owned shop up to the stage a shot needs, driving the real
## systems rather than faking a picture of them: the lease is signed, the
## equipment is bought and placed, the stock is ordered and shelved, and the
## customers walk in on their own.
func _run_business_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var door := _property_door()
	EconomyManager.restore(8000)
	PropertyManager.lease(door)
	var business := BusinessManager.create_business("Silas Market", &"convenience_store", door)
	BusinessManager.deposit_to_business(business, 4000)

	# Inside, so the unit counts the player as present and the equipment exists.
	door.interact(player)
	await _wait(16)
	var unit: RetailUnit = main.get_node("Interiors/MainStreetUnit")
	var dashboard: Control = main.get_node("HUD/BusinessDashboard")

	if scenario == "equipment_buy":
		BusinessManager.buy_equipment(business, &"checkout_counter")
		dashboard.open(business)
		dashboard.show_tab(3)
		await _wait(6)
		return

	var controller: PlacementController = main.get_node("PlacementController")
	for id in [&"checkout_counter", &"retail_shelf", &"retail_shelf", &"storage_rack"]:
		BusinessManager.buy_equipment(business, id)

	if scenario == "equipment_place":
		# Left mid-placement, so the shot is of the preview and its prompt.
		player.global_position = unit.global_position + Vector3(0.0, 0.5, 3.4)
		await _wait(10)
		controller.begin(business, unit, &"retail_shelf")
		await _wait(10)
		return

	controller.begin(business, unit, &"checkout_counter")
	controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0)
	controller.begin(business, unit, &"retail_shelf")
	controller.place_at(Vector3(-4.0, 0.0, 2.0), 90.0)
	controller.begin(business, unit, &"retail_shelf")
	controller.place_at(Vector3(4.0, 0.0, 2.0), 90.0)
	controller.begin(business, unit, &"storage_rack")
	controller.place_at(Vector3(0.0, 0.0, -4.0), 0.0)
	await _wait(8)

	BusinessManager.order_stock(business, &"bottled_water", 40)
	BusinessManager.order_stock(business, &"soda_can", 40)
	BusinessManager.order_stock(business, &"snack_bar", 20)

	if scenario == "business_storage":
		dashboard.open(business)
		dashboard.show_tab(1)
		await _wait(6)
		return

	var shelves := business.shelves()
	business.stock_shelf(shelves[0].slot_id, &"bottled_water", 20)
	business.stock_shelf(shelves[1].slot_id, &"soda_can", 20)
	await _wait(8)

	if scenario == "pricing_screen":
		dashboard.open(business)
		dashboard.show_tab(2)
		await _wait(6)
		return
	if scenario == "stocked_shelf":
		player.global_position = unit.global_position + Vector3(-2.4, 0.5, 2.0)
		await _wait(10)
		return

	business.manual_override = BusinessInstance.Override.FORCE_OPEN
	business.set_open(true)
	await _wait(6)

	if scenario == "store_open":
		# Outside, looking at the sign over the door.
		GameManager.teleport_player(
			Transform3D(Basis(), unit.global_position + Vector3(0.0, 0.5, 11.0))
		)
		await _wait(16)
		return

	var spawner := unit.get_spawner()
	var till := unit.first_checkout()

	# Anything that wants trading figures needs somebody on the till: an
	# unstaffed shop is all lost sales, which is correct and photographs badly.
	if scenario in [
		"employee_cashier", "player_away", "driving_business",
		"business_dashboard", "daily_report",
	]:
		BusinessManager.refresh_candidates()
		var worker: EmployeeData = BusinessManager.get_candidates()[0]
		BusinessManager.hire(business, worker)
		worker.shift_start_hour = 0
		worker.shift_end_hour = 23

		if scenario == "business_dashboard" or scenario == "daily_report":
			for i in 5:
				BusinessManager.simulate_hour_now(business, 12)
			player.global_position = unit.global_position + Vector3(0.0, 0.5, 3.5)
			await _wait(10)
			dashboard.open(business)
			dashboard.show_tab(5 if scenario == "daily_report" else 0)
			await _wait(6)
			return

		player.global_position = unit.global_position + Vector3(0.0, 0.5, 3.5)
		await _wait(10)
		unit.call("_refresh_staff")
		for i in 4:
			spawner.spawn_customer_now()
			await _wait(20)
		await _wait(140)

		if scenario == "employee_cashier":
			return
		# Out of the shop entirely, and the shop keeps trading.
		BusinessManager.simulate_hour_now(business, 12)
		if scenario == "driving_business":
			var car := _find_vehicle(true)
			GameManager.teleport_player(
				Transform3D(Basis(), car.global_transform * Vector3(-2.1, 0.5, 0.4))
			)
			await _wait(10)
			car.get_node("Door").interact(player)
			await _wait(6)
			Input.action_press("move_forward")
			await _wait(90)
			Input.action_release("move_forward")
			return
		GameManager.teleport_player(
			Transform3D(Basis(), Vector3(-30.0, 0.5, 8.4))
		)
		await _wait(20)
		return

	# The customer shots. The queue shot deliberately leaves the till unmanned
	# until the end: somebody serving is what stops a queue forming.
	player.global_position = till.staff_point()
	await _wait(10)
	if scenario == "customers_browsing":
		spawner.toggle_player_at_register(till)
		for i in 3:
			spawner.spawn_customer_now()
			await _wait(45)
		await _wait(120)
		return

	for i in 4:
		spawner.spawn_customer_now()
		await _wait(30)
	# Long enough for them to work through a basket and line up at the counter.
	await _wait(900)
	if scenario == "player_register":
		spawner.toggle_player_at_register(till)
		await _wait(60)


## First *parked* vehicle matching the requested ownership. Moving traffic and
## patrol cars share the group and must not be picked.
func _find_vehicle(player_owned: bool) -> Vehicle:
	for car in get_tree().get_nodes_in_group(&"vehicle"):
		if car.is_in_group(&"traffic") or car.is_in_group(&"police"):
			continue
		if car.is_player_owned() == player_owned:
			return car
	return null


func _traffic_manager() -> TrafficManager:
	return get_tree().get_first_node_in_group(&"traffic_manager") as TrafficManager


func _main_street_signal() -> TrafficLight:
	for node in get_tree().get_nodes_in_group(&"traffic_light"):
		if absf((node as Node3D).global_position.z - District01.MAIN_ST_Z) < 1.0:
			return node
	return null


## A civilian car under AI control, placed by hand. Used where a screenshot
## needs a specific car in a specific place.
func _add_traffic_car(scene: PackedScene, at: Vector3, yaw_degrees: float, tint: Color) -> Vehicle:
	var car: Vehicle = scene.instantiate()
	car.controller = Vehicle.Controller.TRAFFIC_AI
	car.owner_type = Vehicle.OwnerType.NPC
	car.owner_id = &"traffic"
	car.position = at
	car.rotation_degrees.y = yaw_degrees
	var tinted: VehicleData = car.data.duplicate()
	tinted.body_color = tint
	car.data = tinted
	add_child(car)
	var driver := TrafficDriver.new()
	driver.name = "Driver"
	car.add_child(driver)
	return car


## Waits on physics frames, not render frames. Physics runs at a fixed 60Hz
## regardless of how slow the renderer is, so a scenario takes the same amount
## of game time under a software rasteriser as it does on a GPU. Counting draw
## calls instead let a car drive the length of the district before capture.
func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := String(arg).split("=", true, 1)
		if pair.size() == 2:
			_args[pair[0]] = pair[1]


func _number(key: String, fallback: float) -> float:
	if not _args.has(key):
		return fallback
	return String(_args[key]).to_float()
