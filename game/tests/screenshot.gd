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
##   scenario  street (default), apartment, shop, inventory, warehouse
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
