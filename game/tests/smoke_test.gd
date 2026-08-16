extends Node
## Headless smoke test for the V0.1 prototype.
##
## Instances the real main scene and drives it with simulated input, so the
## things that are easy to break silently — spawn placement, curb climbing,
## building collision, camera framing, interaction focus — fail loudly instead.
##
##   godot --headless --path game res://tests/smoke_test.tscn
##
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := preload("res://main.tscn")

var _main: Node3D
var _player: Player
var _camera_rig: TopDownCamera
var _failures: Array[String] = []
var _checks: int = 0
var _notifications: Array[String] = []


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	GameManager.notification_posted.connect(
		func(message: String, _tone: int) -> void: _notifications.append(message)
	)
	await _run()


func _run() -> void:
	_player = _main.get_node("Player")
	_camera_rig = _main.get_node("CameraRig")
	await _settle(30)

	await _test_world_built()
	await _test_spawn_and_gravity()
	await _test_camera_framing()
	await _test_walking_and_sprinting()
	await _test_building_collision()
	await _test_curb_step_up()
	await _test_interaction()
	await _test_pause()
	await _test_day_night()
	_test_clock_and_economy()
	await _test_life_loop()
	await _test_shop_and_job_rules()
	await _test_vehicles_spawned()
	await _test_enter_and_exit()
	await _test_driving()
	await _test_vehicle_collision()
	await _test_vehicle_theft()
	await _test_camera_speed_zoom()
	await _test_vehicle_save_load()

	_report()


# --- Checks --------------------------------------------------------------

func _test_world_built() -> void:
	var district: District01 = _main.get_node("District01")
	var geometry := district.get_node("Geometry")
	var buildings := district.get_node("Buildings")
	var interactables := district.get_node("Interactables")

	_check(geometry.get_child_count() > 100, "district geometry was generated")
	_check(buildings.get_child_count() == 12, "12 buildings placed")
	_check(interactables.get_child_count() >= 9, "interaction points placed")
	_check(
		get_tree().get_nodes_in_group("street_light").size() == 44, "44 street lights registered"
	)
	_check(GameManager.player == _player, "player registered with GameManager")


func _test_spawn_and_gravity() -> void:
	await _settle(40)
	_check(_player.is_on_floor(), "player settles on the ground")
	_check(
		absf(_player.global_position.y - CityKit.CURB_HEIGHT) < 0.06,
		"player spawns standing on the sidewalk (y=%.3f)" % _player.global_position.y
	)


func _test_camera_framing() -> void:
	var camera: Camera3D = _camera_rig.camera
	_check(camera.current, "camera rig is the active camera")

	var offset := camera.global_position - _player.global_position
	_check(offset.y > 10.0, "camera sits well above the player (%.1f)" % offset.y)

	# "Behind" is the rig's local +Z, whatever the current orbit yaw is.
	var behind := _camera_rig.global_transform.basis.z
	var planar_offset := Vector3(offset.x, 0.0, offset.z)
	_check(
		planar_offset.normalized().dot(behind.normalized()) > 0.95,
		"camera sits behind the player along the rig's yaw"
	)
	_check(planar_offset.length() > 8.0, "camera stands back far enough (%.1fm)" % planar_offset.length())

	var pitch := rad_to_deg(atan2(offset.y, planar_offset.length()))
	_check(pitch > 50.0 and pitch < 70.0, "camera looks down at %.0f degrees" % pitch)

	# Every movement check below assumes forward is north, so pin the orbit.
	_camera_rig.yaw_degrees = 0.0
	await _settle(4)


func _test_walking_and_sprinting() -> void:
	await _teleport(Vector3(-60.0, 0.4, -7.5))
	var start := _player.global_position

	await _hold(["move_forward"], 40)
	var walked := _player.global_position.distance_to(start)
	_check(walked > 2.0, "player walks with W (%.1fm)" % walked)
	# Camera yaw is 0, so forward is -Z.
	_check(
		_player.global_position.z < start.z - 1.0, "W moves away from the camera, not toward it"
	)

	await _teleport(Vector3(-60.0, 0.4, -7.5))
	_player.stats.add_energy(PlayerStats.MAX_VALUE)
	var energy_before := _player.stats.energy
	start = _player.global_position
	await _hold(["move_forward", "sprint"], 40)
	var sprinted := _player.global_position.distance_to(start)
	_check(sprinted > walked * 1.2, "sprinting is faster (%.1fm vs %.1fm)" % [sprinted, walked])
	_check(_player.stats.energy < energy_before, "sprinting drains energy")

	# Deceleration: releasing input brings the player to a stop.
	await _settle(45)
	_check(_player.get_planar_speed() < 0.15, "player decelerates to a stop")


func _test_building_collision() -> void:
	# Stand in the setback in front of Larkspur Apartments and walk into it.
	await _teleport(Vector3(-60.0, 0.4, -11.0))
	await _hold(["move_forward"], 70)
	_check(
		_player.global_position.z > -12.6,
		"building wall blocks the player (z=%.2f)" % _player.global_position.z
	)


func _test_curb_step_up() -> void:
	# Start on the carriageway and walk north onto the Main Street sidewalk.
	await _teleport(Vector3(-64.0, 0.4, -3.0))
	await _settle(25)
	_check(_player.global_position.y < 0.05, "player stands on the road surface")

	await _hold(["move_forward"], 70)
	_check(
		_player.global_position.z < -6.3,
		"player crosses onto the sidewalk (z=%.2f)" % _player.global_position.z
	)
	_check(
		_player.global_position.y > CityKit.CURB_HEIGHT - 0.04,
		"player steps up the curb instead of being blocked (y=%.3f)" % _player.global_position.y
	)


func _test_interaction() -> void:
	var controller := _player.interaction
	await _teleport(Vector3(-53.0, 0.4, -5.4))
	await _settle(25)

	var focused := controller.get_focused()
	_check(focused != null, "an interactable is focused near the notice board")
	if focused == null:
		return
	_check(focused.name == "Notices", "the notice board wins focus (got %s)" % focused.name)
	_check(
		focused.get_prompt_text() == "E — Read notices",
		"prompt text is '%s'" % focused.get_prompt_text()
	)

	_notifications.clear()
	await _press_action("interact")
	await _settle(4)
	_check(_notifications.size() == 1, "interacting fires exactly one notification")

	# Walking away must clear the focus so the prompt disappears.
	await _teleport(Vector3(-53.0, 0.4, 20.0))
	await _settle(25)
	_check(controller.get_focused() == null, "focus clears when walking away")


func _test_pause() -> void:
	await _press_action("pause_menu")
	await _settle(4)
	_check(GameManager.is_paused(), "ESC pauses the game")

	var clock_at_pause := TimeManager.total_minutes
	await _settle(20)
	_check(
		is_equal_approx(TimeManager.total_minutes, clock_at_pause),
		"the clock stops while paused"
	)

	await _press_action("pause_menu")
	await _settle(10)
	_check(not GameManager.is_paused(), "ESC resumes the game")
	_check(TimeManager.total_minutes > clock_at_pause, "the clock restarts on resume")


## Regression cover: the lights-on state must be driven by the clock, including
## when the game starts at night, and the sun must actually move.
func _test_day_night() -> void:
	var sun: DayNightCycle = _main.get_node("District01/Sun")
	var lamp: OmniLight3D = get_tree().get_nodes_in_group("street_light")[0]
	var windows: StandardMaterial3D = _main.get_node("District01")._mat("windows")

	TimeManager.set_total_minutes(23.0 * 60.0)
	await _settle(4)
	_check(lamp.visible, "street lights switch on at night")
	_check(windows.emission_energy_multiplier > 0.5, "windows are lit at night")
	var night_pitch := sun.rotation_degrees.x
	var night_energy := sun.light_energy

	TimeManager.set_total_minutes(12.0 * 60.0)
	await _settle(4)
	_check(not lamp.visible, "street lights switch off during the day")
	_check(windows.emission_energy_multiplier < 0.05, "windows stop glowing by day")
	_check(sun.light_energy > night_energy * 3.0, "the sun is brighter at noon")
	_check(
		absf(sun.rotation_degrees.x - night_pitch) > 20.0, "the sun moves across the sky"
	)


func _test_clock_and_economy() -> void:
	var day_before := TimeManager.get_day_name()
	var minutes_before := TimeManager.total_minutes
	TimeManager.advance_hours(20)
	_check(TimeManager.total_minutes > minutes_before + 1190.0, "time skips forward")
	_check(TimeManager.get_day_name() != day_before, "the day rolls over")

	_check(EconomyManager.cash == EconomyManager.STARTING_CASH, "player starts with $500")
	_check(EconomyManager.spend(120, "Test"), "spending within balance succeeds")
	_check(EconomyManager.cash == 380, "balance drops to $380")
	_check(not EconomyManager.spend(9999, "Test"), "spending beyond balance is refused")
	_check(EconomyManager.cash == 380, "refused spend leaves the balance alone")
	EconomyManager.deposit(120, "Test wage")
	_check(EconomyManager.cash == 500, "wages are credited")
	# The refused spend must not appear in the ledger.
	_check(EconomyManager.get_history().size() == 2, "only completed transactions are logged")


## The whole Phase B/C loop in one pass, in the order a player would live it:
## home -> sleep -> work -> shop -> eat -> home.
func _test_life_loop() -> void:
	var apartment: Node3D = _main.get_node("Interiors/Apartment")
	var stats := _player.stats
	var inventory := _player.inventory

	# A believable starting state: late, tired, and half hungry.
	TimeManager.set_total_minutes(22.0 * 60.0 + 30.0)
	stats.restore_values(100.0, 30.0, 50.0)
	EconomyManager.restore(EconomyManager.STARTING_CASH)
	inventory.clear()
	_camera_rig.reset_view()

	# --- Outside the front door ---
	await _teleport(Vector3(-60.0, 0.5, -11.6))
	await _settle(25)
	var front_door := _player.interaction.get_focused()
	_check(front_door is Portal, "the apartment door is a working portal")
	_check(
		front_door != null and front_door.get_prompt_text() == "E — Enter Apartment",
		"apartment prompt reads '%s'" % (front_door.get_prompt_text() if front_door else "<none>")
	)

	# --- Enter the flat ---
	await _press_action("interact")
	await _settle(25)
	var inside := _player.global_position.distance_to(apartment.global_position) < 12.0
	_check(inside, "entering the door puts the player inside the apartment")
	_check(
		_camera_rig.distance < 16.0, "the camera tightens for the interior (%.0f)" % _camera_rig.distance
	)
	_check(_player.is_on_floor(), "the player lands on the apartment floor")

	# --- Sleep ---
	var bed: Bed = apartment.get_node("SleepPoint")
	await _teleport(bed.global_position - Vector3(0.0, 0.5, 0.0))
	await _settle(25)
	_check(_player.interaction.get_focused() == bed, "the bed takes interaction focus")

	var hunger_before_sleep := stats.hunger
	await _press_action("interact")
	await _settle(6)
	_check(TimeManager.hour == 7, "sleeping wakes the player at 07:00 (got %02d:00)" % TimeManager.hour)
	_check(stats.energy > 95.0, "sleeping restores energy (%.0f)" % stats.energy)
	_check(
		stats.hunger < hunger_before_sleep - 10.0,
		"hunger drains across the night (%.0f -> %.0f)" % [hunger_before_sleep, stats.hunger]
	)

	# --- Back out to the street ---
	var flat_door: Portal = apartment.get_node("FrontDoor")
	await _teleport(flat_door.global_position - Vector3(0.0, 0.5, 0.0))
	await _settle(25)
	_check(_player.interaction.get_focused() == flat_door, "the flat's own door offers a way out")
	await _press_action("interact")
	await _settle(25)
	_check(
		_player.global_position.distance_to(Vector3(-60.0, 0.0, -10.8)) < 4.0,
		"leaving puts the player back on the street outside Larkspur"
	)
	_check(
		_camera_rig.distance > 16.0, "the camera returns to street framing (%.0f)" % _camera_rig.distance
	)

	# --- Walk to work, then a full shift ---
	await _teleport(Vector3(-58.0, 0.5, 13.4))
	await _settle(25)
	var station := _player.interaction.get_focused()
	_check(station is JobStation, "the warehouse gate offers a shift")

	var cash_before := EconomyManager.cash
	var clock_before := TimeManager.total_minutes
	var energy_before_shift := stats.energy
	await _press_action("interact")
	await _settle(6)
	_check(EconomyManager.cash == cash_before + 120, "a shift pays $120 (got $%d)" % (EconomyManager.cash - cash_before))
	# The clock also ticks in real time while the test awaits frames, so allow
	# a couple of minutes of slack around the four-hour skip.
	var shift_minutes := TimeManager.total_minutes - clock_before
	_check(
		shift_minutes >= 240.0 and shift_minutes < 243.0,
		"a shift takes four hours (%.1f minutes)" % shift_minutes
	)
	_check(stats.energy < energy_before_shift - 20.0, "a shift is tiring (%.0f)" % stats.energy)

	# --- Walk to the shop, on foot, the whole way ---
	await _teleport(Vector3(-60.0, 0.5, -10.8))
	await _settle(20)
	# ~22m east along the frontage, from Larkspur's door to the market's.
	await _hold(["move_right"], 300)
	await _settle(30)
	var counter := _player.interaction.get_focused()
	_check(
		counter is Shop,
		"walking east along the frontage reaches the market counter (x=%.1f)" % _player.global_position.x
	)

	# --- Buy a meal through the real shop screen ---
	await _press_action("interact")
	await _settle(6)
	var shop_panel: Control = _main.get_node("HUD/ShopPanel")
	_check(shop_panel.is_open(), "interacting opens the shop screen")
	_check(GameManager.menu_open, "an open screen freezes the world")

	var buy_button := _find_first_button(shop_panel.get_node("%StockRows"))
	_check(buy_button != null, "the shop lists buyable stock")
	var cash_before_buy := EconomyManager.cash
	if buy_button != null:
		buy_button.pressed.emit()
		await _settle(4)
	_check(EconomyManager.cash == cash_before_buy - 15, "buying a Basic Meal costs $15")
	_check(inventory.count_of(&"basic_meal") == 1, "the meal lands in the inventory")

	GameManager.close_menus()
	await _settle(6)
	_check(not GameManager.menu_open, "closing the screen unfreezes the world")

	# --- Eat it ---
	await _press_action("inventory")
	await _settle(4)
	var bag: Control = _main.get_node("HUD/InventoryPanel")
	_check(bag.is_open(), "TAB opens the inventory")
	GameManager.close_menus()
	await _settle(4)

	var hunger_before_meal := stats.hunger
	_check(inventory.use_slot(0, _player), "the meal can be eaten")
	_check(
		stats.hunger > hunger_before_meal + 30.0,
		"eating restores hunger (%.0f -> %.0f)" % [hunger_before_meal, stats.hunger]
	)
	_check(inventory.count_of(&"basic_meal") == 0, "eating consumes the meal")

	# --- Home again ---
	await _teleport(Vector3(-60.0, 0.5, -11.6))
	await _settle(25)
	await _press_action("interact")
	await _settle(25)
	_check(
		_player.global_position.distance_to(apartment.global_position) < 12.0,
		"the player can get back home again"
	)

	# Leave the world outside, ready for the rules checks.
	await _teleport(flat_door.global_position - Vector3(0.0, 0.5, 0.0))
	await _settle(20)
	await _press_action("interact")
	await _settle(20)


## The rules that stop the loop being a money printer.
func _test_shop_and_job_rules() -> void:
	var district: Node3D = _main.get_node("District01")
	var shop: Shop = district.get_node("Interactables/MarketDoor")
	var station: JobStation = district.get_node("Interactables/WarehouseGate")
	var stats := _player.stats

	TimeManager.set_total_minutes(3.0 * 60.0)
	await _settle(4)
	_check(not shop.is_open(), "the market is shut at 03:00")
	_check(not shop.available, "a shut shop cannot be interacted with")
	_check(
		shop.buy(shop.stock[0], _player) == Shop.Result.CLOSED,
		"buying from a shut shop is refused"
	)
	_check(
		station.get_refusal(_player) == JobStation.Refusal.CLOSED,
		"the warehouse turns the player away at 03:00"
	)

	TimeManager.set_total_minutes(9.0 * 60.0)
	await _settle(4)
	_check(shop.is_open(), "the market is open at 09:00")

	stats.restore_values(100.0, 5.0, 100.0)
	_check(
		station.get_refusal(_player) == JobStation.Refusal.TOO_TIRED,
		"an exhausted player cannot start a shift"
	)

	stats.restore_values(100.0, 100.0, 100.0)
	_check(station.get_refusal(_player) == JobStation.Refusal.NONE, "a rested player can work")

	# The shift cap is what stops the player grinding an infinite payday.
	var shifts := station.get_shifts_left()
	for i in shifts:
		station.interact(_player)
		stats.add_energy(100.0)
	_check(
		station.get_refusal(_player) == JobStation.Refusal.NO_SHIFTS_LEFT,
		"the warehouse runs out of shifts for the day"
	)

	# An overfull bag must never take the player's money.
	var inventory := _player.inventory
	inventory.clear()
	var filler: ItemData = shop.stock[0]
	inventory.add(filler, inventory.get_slots().size() * filler.max_stack)
	_check(not inventory.can_add(filler, 1), "the bag can be filled up")
	var cash_before := EconomyManager.cash
	_check(
		shop.buy(filler, _player) == Shop.Result.INVENTORY_FULL,
		"buying with a full bag is refused"
	)
	_check(EconomyManager.cash == cash_before, "a refused purchase costs nothing")

	inventory.clear()
	EconomyManager.restore(4)
	_check(
		shop.buy(shop.stock[0], _player) == Shop.Result.NOT_ENOUGH_CASH,
		"buying without the cash is refused"
	)


# --- Phase D: vehicles ---------------------------------------------------

func _test_vehicles_spawned() -> void:
	var cars := _vehicles()
	_check(cars.size() == 8, "8 vehicles parked in the district (got %d)" % cars.size())

	var owned := 0
	var npc := 0
	var healthy := true
	for car in cars:
		if car.owner_type == Vehicle.OwnerType.PLAYER:
			owned += 1
		elif car.owner_type == Vehicle.OwnerType.NPC:
			npc += 1
		if car.data == null or car.health < car.data.max_health:
			healthy = false
	_check(owned == 1, "exactly one is the player's")
	_check(npc == 7, "the rest are NPC-owned (%d)" % npc)
	_check(healthy, "every vehicle starts with full health and a data resource")
	_check(_player_car() != null, "the player's car can be found by ownership")


## TEST 1 and TEST 4: walk up, get in, get out beside the car, get back in.
func _test_enter_and_exit() -> void:
	var car := _player_car()
	await _park_for_test(car, Vector3(-56.0, 0.0, -4.0), 90.0)

	await _stand_beside(car)
	var door := _player.interaction.get_focused()
	_check(door is VehicleDoor, "standing by the car offers a door prompt")
	_check(
		door != null and door.get_prompt_text() == "F — Enter Vehicle",
		"the prompt is '%s', not an E prompt" % (door.get_prompt_text() if door else "<none>")
	)

	await _press_action("enter_vehicle")
	await _settle(8)
	_check(_player.is_driving(), "F puts the player in the driver's seat")
	_check(car.get_driver() == _player, "the car knows who is driving it")
	_check(_camera_rig.get_target() == car, "the camera hands over to the vehicle")
	_check(_player.interaction.get_focused() == null, "on-foot prompts stop while driving")
	_check(_main.get_node("HUD/Root/SpeedPanel").visible, "the speedometer appears")

	await _press_action("enter_vehicle")
	await _settle(20)
	_check(not _player.is_driving(), "F again gets the player out")
	_check(_camera_rig.get_target() == _player, "the camera comes back to the player")
	_check(not _main.get_node("HUD/Root/SpeedPanel").visible, "the speedometer goes away")

	# TEST 4: beside the car, on the ground, not inside it and not under the map.
	var offset := _player.global_position - car.global_position
	var gap := Vector2(offset.x, offset.z).length()
	_check(gap > 1.2 and gap < 4.5, "the player is put beside the car (%.1fm)" % gap)
	_check(_player.global_position.y > -0.5 and _player.global_position.y < 2.0,
		"the player is not under the map (y=%.2f)" % _player.global_position.y)
	_check(_player.is_on_floor(), "the player is standing on solid ground")

	await _settle(20)
	await _press_action("enter_vehicle")
	await _settle(8)
	_check(_player.is_driving(), "the player can get straight back in")
	await _leave_vehicle()


## TEST 2: throttle, brake, reverse, handbrake, steering.
func _test_driving() -> void:
	var car := _player_car()
	# A long clear run north up Center Boulevard, well away from parked cars,
	# the junctions and the park.
	var line := Vector3(0.0, 0.0, 78.0)
	await _park_for_test(car, line, 0.0)
	await _drive(car)

	var start := car.global_position
	await _hold(["move_forward"], 90)
	_check(car.get_forward_speed() > 8.0, "the throttle builds speed (%.1f m/s)" % car.get_forward_speed())
	_check(
		car.get_forward_speed() <= car.data.max_speed + 0.01,
		"speed is capped at the model's maximum"
	)
	_check(car.global_position.distance_to(start) > 8.0, "the car actually moves")
	_check(
		car.global_position.z < start.z - 5.0, "the car drives forward, along its own nose"
	)

	# Coasting: no input bleeds speed off without stopping dead.
	var coasting_from := car.get_forward_speed()
	await _settle(30)
	_check(
		car.get_forward_speed() < coasting_from and car.get_forward_speed() > 0.0,
		"lifting off coasts down rather than stopping dead (%.1f m/s)" % car.get_forward_speed()
	)

	# Braking is sharper than coasting.
	var brake_from := car.get_forward_speed()
	await _hold(["move_back"], 15)
	var braked := brake_from - car.get_forward_speed()
	_check(braked > 0.5, "the brake pulls speed off (%.1f m/s in a quarter second)" % braked)

	# Reverse, from a standstill.
	await _reposition(car, line, 0.0)
	var before_reverse := car.global_position
	await _hold(["move_back"], 70)
	_check(car.get_forward_speed() < -2.0, "holding S from rest reverses (%.1f m/s)" % car.get_forward_speed())
	_check(
		car.global_position.z > before_reverse.z + 1.0, "reversing moves the car backwards"
	)
	_check(
		absf(car.get_forward_speed()) <= car.data.max_reverse_speed + 0.01,
		"reverse has its own, lower speed cap"
	)

	# Handbrake.
	await _reposition(car, line, 0.0)
	await _hold(["move_forward"], 70)
	var handbrake_from := car.get_forward_speed()
	await _hold(["handbrake"], 20)
	_check(
		car.get_forward_speed() < handbrake_from - 3.0,
		"the handbrake hauls it down (%.1f -> %.1f m/s)" % [handbrake_from, car.get_forward_speed()]
	)

	# Steering, and the fact that it tightens at low speed.
	await _reposition(car, line, 0.0)
	var still_yaw := car.rotation.y
	await _hold(["move_left"], 30)
	_check(
		is_equal_approx(car.rotation.y, still_yaw),
		"a stationary car cannot pivot on the spot"
	)

	await _reposition(car, line, 0.0)
	var slow_turn := await _measure_turn(car, 25, 30)
	await _reposition(car, line, 0.0)
	var fast_turn := await _measure_turn(car, 110, 30)
	_check(slow_turn > 0.05, "the car steers while moving (%.2f rad)" % slow_turn)
	_check(
		fast_turn < slow_turn,
		"steering tightens up at speed (%.2f rad fast vs %.2f slow)" % [fast_turn, slow_turn]
	)

	await _leave_vehicle()


## TEST 3: a building is a wall, not a suggestion.
func _test_vehicle_collision() -> void:
	var car := _player_car()
	# North up the empty westmost bay, straight at the Larkspur frontage. Clear
	# of the parked cars, the notice board and the street lights.
	await _park_for_test(car, Vector3(-68.0, 0.0, 0.0), 0.0)
	await _drive(car)

	var health_before := car.health
	await _hold(["move_forward"], 120)
	await _settle(20)

	# The plinth face is at z = -12.82; a 4.3m car stopped against it sits at
	# about -10.7. Anything past the facade means it drove through.
	_check(
		car.global_position.z > -11.3,
		"the car cannot drive through a building (z=%.2f)" % car.global_position.z
	)
	_check(
		absf(car.get_forward_speed()) < 4.0,
		"the impact scrubs speed instead of grinding (%.1f m/s)" % car.get_forward_speed()
	)
	_check(car.health < health_before, "a solid hit damages the car (%.0f)" % car.health)
	_check(car.health > 0.0, "one crash does not write it off")

	car.repair()
	await _leave_vehicle()


## TEST 5: theft is recorded, and nothing else happens yet.
func _test_vehicle_theft() -> void:
	CrimeManager.clear_history()
	_notifications.clear()

	var target: Vehicle = null
	for car in _vehicles():
		if car.owner_type == Vehicle.OwnerType.NPC:
			target = car
			break
	_check(target != null, "there is an NPC car to steal")
	if target == null:
		return

	await _park_for_test(target, Vector3(0.0, 0.0, 60.0), 0.0)
	await _stand_beside(target)
	var door := _player.interaction.get_focused()
	_check(
		door is VehicleDoor and door.prompt_subtitle.ends_with("not yours"),
		"the prompt warns the car is not the player's"
	)

	await _press_action("enter_vehicle")
	await _settle(8)
	_check(_player.is_driving(), "the player can still take it")

	var record := CrimeManager.get_last_crime()
	_check(not record.is_empty(), "a crime was filed")
	_check(
		record.get("type") == CrimeManager.CrimeType.VEHICLE_THEFT,
		"it is filed as vehicle theft"
	)
	_check(record.get("target") == target, "the record names the stolen vehicle")
	_check(record.get("perpetrator") == _player, "the record names the player")
	_check(int(record.get("severity", 0)) == 2, "vehicle theft carries its severity")
	_check(record.has("position") and record.has("day") and record.has("time"),
		"the record carries where and when, for the witness system later")
	_check(record.get("witnessed") == false, "nothing witnessed it — no witnesses exist yet")
	_check(
		_notifications.any(func(m: String) -> bool: return m.begins_with("VEHICLE THEFT")),
		"the player is told a theft happened"
	)

	# The brief is explicit: no police response in this phase.
	_check(
		not GameManager.has_method("set_wanted_level"),
		"no wanted level was wired up"
	)

	# Driving a stolen car is still driving.
	await _hold(["move_forward"], 40)
	_check(target.get_forward_speed() > 3.0, "the stolen car drives away")

	# Getting back into the same car must not re-file the same crime.
	await _leave_vehicle()
	var crimes_before := CrimeManager.get_history().size()
	await _stand_beside(target)
	await _press_action("enter_vehicle")
	await _settle(8)
	_check(
		CrimeManager.get_history().size() == crimes_before,
		"re-entering an already-stolen car does not re-file it"
	)
	await _leave_vehicle()
	# Leave the boulevard clear: a car abandoned mid-road here would be an
	# obstacle the later driving tests would silently crash into.
	await _park_for_test(target, Vector3(60.0, 0.0, 72.0), 0.0)


## TEST 6: the view opens up with speed and comes back in.
func _test_camera_speed_zoom() -> void:
	var car := _player_car()
	await _park_for_test(car, Vector3(0.0, 0.0, 78.0), 0.0)
	await _drive(car)
	await _settle(40)

	var parked_view := _camera_rig.get_effective_distance()
	await _hold(["move_forward"], 150)
	var fast_view := _camera_rig.get_effective_distance()
	# Asserted so an obstacle in the run-up fails here, loudly, rather than
	# quietly turning into a "camera did not widen" result.
	_check(
		car.get_forward_speed() > 12.0,
		"the car got up to speed for this test (%.1f m/s)" % car.get_forward_speed()
	)
	_check(
		fast_view > parked_view + 2.0,
		"the camera widens at speed (%.1f -> %.1f)" % [parked_view, fast_view]
	)
	_check(
		fast_view < parked_view * 1.6,
		"but not excessively (%.1f from %.1f)" % [fast_view, parked_view]
	)

	await _stop_vehicle(car)
	await _settle(120)
	_check(
		_camera_rig.get_effective_distance() < parked_view + 1.0,
		"slowing down brings it back in (%.1f)" % _camera_rig.get_effective_distance()
	)
	await _leave_vehicle()


## TEST 7: the player's car survives a save and load.
func _test_vehicle_save_load() -> void:
	var slot := 99
	var car := _player_car()

	await _park_for_test(car, Vector3(-20.0, 0.0, 30.0), 45.0)
	car.apply_damage(30.0)
	await _teleport(Vector3(-24.0, 0.5, 30.0))
	EconomyManager.restore(742)
	_player.inventory.clear()
	_player.inventory.add(ItemCatalogue.by_id(&"snack_bar"), 2)
	await _settle(6)

	var saved_position := car.global_position
	var saved_yaw := car.rotation.y
	var saved_health := car.health
	_check(SaveManager.save_to_slot(slot), "the game saves")
	_check(SaveManager.has_save(slot), "the save file exists")

	# Move everything somewhere else so a no-op load would be obvious.
	await _park_for_test(car, Vector3(40.0, 0.0, -20.0), 0.0)
	car.repair()
	await _teleport(Vector3(30.0, 0.5, 20.0))
	EconomyManager.restore(1)
	_player.inventory.clear()
	await _settle(6)

	_check(SaveManager.load_from_slot(slot), "the game loads")
	await _settle(10)

	_check(
		car.global_position.distance_to(saved_position) < 0.6,
		"the car is back where it was saved (%.2fm off)" % car.global_position.distance_to(saved_position)
	)
	_check(absf(car.rotation.y - saved_yaw) < 0.05, "its heading is restored")
	_check(is_equal_approx(car.health, saved_health), "its damage is restored (%.0f)" % car.health)
	_check(EconomyManager.cash == 742, "the player's cash is restored")
	_check(_player.inventory.count_of(&"snack_bar") == 2, "the inventory is restored")
	_check(
		_player.global_position.distance_to(Vector3(-24.0, 0.5, 30.0)) < 2.0,
		"the player is back where they were saved"
	)

	# An unknown future version must be refused rather than half-applied.
	var path := SaveManager.get_slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": SaveManager.SAVE_VERSION + 5}))
	file.close()
	_check(not SaveManager.load_from_slot(slot), "a newer save format is refused, not half-read")

	# A save missing whole sections must not crash the load.
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": SaveManager.SAVE_VERSION}))
	file.close()
	_check(SaveManager.load_from_slot(slot), "a save with missing sections still loads")

	SaveManager.delete_slot(slot)
	_check(not SaveManager.has_save(slot), "the test save is cleaned up")


# --- Vehicle helpers -----------------------------------------------------

func _vehicles() -> Array:
	return get_tree().get_nodes_in_group(&"vehicle")


func _player_car() -> Vehicle:
	for car in _vehicles():
		if car.owner_type == Vehicle.OwnerType.PLAYER:
			return car
	return null


## Moves a car to a clear test spot and lets it settle.
func _park_for_test(car: Vehicle, spot: Vector3, yaw_degrees: float) -> void:
	if car.has_driver():
		await _leave_vehicle()
	car.global_position = spot
	car.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	car.velocity = Vector3.ZERO
	await _settle(12)


func _stand_beside(car: Vehicle) -> void:
	await _teleport(car.global_transform * Vector3(-2.0, 0.5, 0.0))
	await _settle(20)


func _drive(car: Vehicle) -> void:
	if _player.is_driving():
		await _leave_vehicle()
	await _stand_beside(car)
	car.enter(_player)
	await _settle(6)


func _leave_vehicle() -> void:
	_release_all()
	var car := _player.get_vehicle() as Vehicle
	if car == null:
		return
	car.exit_driver(true)
	await _settle(12)


## Moves a car without ejecting its driver, and zeroes its motion, so each
## driving measurement starts from an identical, obstacle-free state.
func _reposition(car: Vehicle, spot: Vector3, yaw_degrees: float) -> void:
	_release_all()
	car.global_position = spot
	car.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	car.halt()
	await _settle(10)


## Holds the handbrake until the car is genuinely stopped, rather than for a
## fixed number of frames that may not be enough from top speed.
func _stop_vehicle(car: Vehicle) -> void:
	_release_all()
	Input.action_press("handbrake")
	var frames := 0
	while absf(car.get_forward_speed()) > 0.05 and frames < 400:
		await get_tree().physics_frame
		frames += 1
	Input.action_release("handbrake")
	await _settle(10)


## Drives forward for `run_up` frames, then measures how far the car turns over
## `turn_frames` of steering — the comparison that proves steering scales with
## speed.
func _measure_turn(car: Vehicle, run_up: int, turn_frames: int) -> float:
	await _hold(["move_forward"], run_up)
	Input.action_press("move_forward")
	var before := car.rotation.y
	await _hold(["move_left"], turn_frames)
	Input.action_release("move_forward")
	return absf(angle_difference(before, car.rotation.y))


func _find_first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child in node.get_children():
		var found := _find_first_button(child)
		if found != null:
			return found
	return null


# --- Harness -------------------------------------------------------------

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", description)
	else:
		print("  FAIL  ", description)
		_failures.append(description)


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame


func _teleport(where: Vector3) -> void:
	_release_all()
	_player.velocity = Vector3.ZERO
	_player.global_position = where
	await _settle(12)


func _hold(actions: Array, frames: int) -> void:
	for action: String in actions:
		Input.action_press(action)
	await _settle(frames)
	_release_all()


func _release_all() -> void:
	for action in [
		"move_forward", "move_back", "move_left", "move_right", "sprint", "handbrake"
	]:
		Input.action_release(action)


func _press_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame


func _report() -> void:
	print("")
	if _failures.is_empty():
		print("SMOKE TEST PASSED — %d checks" % _checks)
		get_tree().quit(0)
		return
	print("SMOKE TEST FAILED — %d of %d checks failed:" % [_failures.size(), _checks])
	for failure in _failures:
		print("  - ", failure)
	get_tree().quit(1)
