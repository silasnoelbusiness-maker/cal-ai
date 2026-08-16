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
##   scenario  street (default), apartment, shop, inventory, warehouse, car,
##             driving, theft, crowd, unseen_theft, witness, wanted, pursuit,
##             escaping, cleared, busted, night_chase, traffic, vehicle_types,
##             red_light, green_light, crossing, pedestrian_reacts,
##             driving_traffic, traffic_crash, pursuit_traffic, police_lights,
##             escaping_traffic, night_traffic
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

		"shop":
			player.global_position = Vector3(-38.0, 0.5, -11.6)
			await _wait(20)
			var shop: Shop = district.get_node("Interactables/MarketDoor")
			shop.interact(player)

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
