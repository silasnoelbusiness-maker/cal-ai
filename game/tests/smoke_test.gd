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
		get_tree().get_nodes_in_group("street_light").size() == 32, "32 street lights registered"
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
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint"]:
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
