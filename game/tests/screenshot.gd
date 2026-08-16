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
##             escaping, cleared, busted, night_chase
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
func _crime_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var car := _find_vehicle(false)
	var spot := Vector3(-40.0, 0.0, 3.0)

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

	if scenario != "unseen_theft":
		# One civilian, stood on the pavement, looking straight at the car.
		var civilian: Node3D = get_tree().get_nodes_in_group(&"pedestrian")[0]
		civilian.process_mode = Node.PROCESS_MODE_INHERIT
		civilian.global_position = spot + Vector3(7.0, 0.4, 5.4)
		civilian.get_node("BodyPivot").rotation.y = atan2(-7.0, -5.4)
		await _wait(6)

	car.get_node("Door").interact(player)
	await _wait(10)
	if scenario in ["unseen_theft", "witness"]:
		return

	# Let the witness call it in.
	await _wait(int((WitnessSystem.report_delay + 0.6) * 60.0))
	if scenario == "wanted":
		return

	var officers: Array = get_tree().get_nodes_in_group(&"police").filter(
		func(u: Node) -> bool: return u is PoliceOfficer
	)
	var cars: Array = get_tree().get_nodes_in_group(&"police_car")

	if scenario == "escaping" or scenario == "cleared":
		# Nobody within sight: the countdown runs on its own.
		WantedManager.escape_seconds_by_level = [0.0, 4.0, 6.0, 8.0, 10.0, 12.0]
		for unit in officers + cars:
			unit.process_mode = Node.PROCESS_MODE_INHERIT
			unit.global_position = player.global_position + Vector3(58.0, 0.0, 0.0)
		await _wait(int((WantedManager.sight_grace_seconds + 0.6) * 60.0))
		if scenario == "escaping":
			return
		await _wait(int(4.5 * 60.0))
		return

	# Pursuit and arrest: wake a patrol car and an officer near the player.
	for i in cars.size():
		var unit: Node3D = cars[i]
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		# Behind the player, in the same lane, pointing the way they went.
		unit.global_position = player.global_position + Vector3(-9.0 - float(i) * 7.0, 0.0, 0.0)
		unit.rotation_degrees.y = -90.0
		unit.halt()
	var officer: Node3D = officers[0]
	officer.process_mode = Node.PROCESS_MODE_INHERIT

	if scenario == "busted":
		officer.global_position = player.global_position + Vector3(1.8, 0.0, 0.0)
		await _wait(40)
		return

	officer.global_position = player.global_position + Vector3(13.0, 0.0, 4.0)
	# Throttle stays down: a player at speed cannot be arrested, so the capture
	# lands mid-chase rather than on the arrest that follows it.
	Input.action_press("move_forward")
	await _wait(50)


## First vehicle matching the requested ownership.
func _find_vehicle(player_owned: bool) -> Vehicle:
	for car in get_tree().get_nodes_in_group(&"vehicle"):
		if car.is_player_owned() == player_owned:
			return car
	return null


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
