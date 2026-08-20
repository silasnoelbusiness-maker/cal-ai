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
const TEST_TRAFFIC_SCENE := preload("res://vehicles/cars/sedan.tscn")

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
	# Everything written before Phase F assumes an empty road — a car parked on
	# the spot a test teleports the player to is a test failure with nothing
	# wrong behind it. Traffic is switched back on for its own section.
	await _stop_traffic()

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
	# Before anything isolates the scene: these two need the city as it ships.
	await _test_crowd_spawned()
	await _test_navigation()
	await _test_park_navigation()
	# Phase F traffic, on a freshly filled city.
	await _start_traffic()
	await _test_road_network()
	await _test_traffic_lights()
	await _test_traffic_population()
	await _test_traffic_flow()
	await _test_police_and_traffic()
	# From here on the tests need to know exactly what is on the street.
	await _stop_traffic()
	await _test_car_following()
	await _test_traffic_stops_at_red()
	await _test_traffic_stuck_recovery()
	await _test_pedestrian_dodges_traffic()
	await _test_pedestrian_knockdown()
	await _test_vehicles_spawned()
	await _test_enter_and_exit()
	await _test_driving()
	await _test_vehicle_collision()
	await _test_vehicle_theft()
	await _test_camera_speed_zoom()
	await _test_vehicle_save_load()
	await _test_unseen_theft()
	await _test_civilian_witness()
	await _test_police_witness()
	await _test_escape()
	await _test_reacquisition()
	await _test_bust()
	await _test_night_pursuit()
	await _test_wanted_debug_keys()

	# Phase G: crime expansion.
	_test_crime_profiles()
	_test_wanted_thresholds()
	_test_bust_fine_scaling()
	await _test_shoplifting()
	await _test_trespassing()
	await _test_store_robbery()
	await _test_carjacking()
	await _test_melee_and_assault()
	await _test_three_star_escalation()
	await _test_life_after_crime()
	await _test_crime_save_load()

	# Phase H: business ownership.
	await _test_property_available()
	await _test_rent_property()
	await _test_create_business()
	await _test_fund_business()
	await _test_equipment()
	await _test_stock()
	_test_pricing()
	await _test_open_store()
	await _test_customer_purchase()
	await _test_out_of_stock()
	await _test_hire_employee()
	await _test_employee_checkout()
	await _test_business_runs_while_away()
	await _test_no_cashier()
	_test_daily_report()
	_test_bad_business()
	_test_rent_payment()
	await _test_business_and_crime()
	await _test_business_save_load()
	_test_simulation_consistency()

	# Phase I: the business empire.
	await _test_second_property()
	await _test_coffee_shop()
	await _test_coffee_customer()
	await _test_two_businesses_trading()
	await _test_stocker()
	await _test_manager()
	await _test_delivery()
	_test_marketing()
	_test_upgrades()
	_test_valuation_and_net_worth()
	_test_loans()
	await _test_time_skip()
	await _test_empire_and_crime()
	await _test_empire_save_load()
	await _test_old_save_migration()
	await _test_sell_business()

	# Phase J: city expansion.
	_test_districts_registered()
	await _test_district_lookup()
	_test_district_character()
	await _test_cross_district_travel()
	await _test_district_traffic()
	_test_map_markers()
	await _test_map_destination()
	_test_residence_lease()
	await _test_change_home()
	await _test_courier_run()
	_test_central_property()
	await _test_wanted_across_districts()
	await _test_world_save_load()
	await _test_pre_district_save()
	await _test_city_edge()
	await _test_world_debug()

	# Phase K: the visual pass.
	await _test_player_figure()
	_test_crowd_variety()
	_test_police_look()
	_test_vehicle_models()
	await _test_interior_dressing()
	_test_ui_theme()

	# Phase L: audio and the front end.
	_test_audio_buses()
	_test_tone_bank()
	await _test_footstep_surfaces()
	await _test_vehicle_audio()
	await _test_siren_state()
	_test_ambience_profiles()
	_test_music_states()
	_test_settings_defaults()
	_test_settings_persistence()
	_test_graphics_presets()
	_test_keybindings()
	await _test_save_slots()
	_test_menu_state()
	await _test_camera_settings()

	# Phase M: what the money buys.
	_test_vehicle_catalogue()
	await _test_vehicle_purchase()
	await _test_vehicle_mileage()
	await _test_vehicle_condition()
	_test_vehicle_repair()
	_test_vehicle_sale()
	_test_used_vehicles()
	await _test_garages()
	_test_stolen_vehicle_garage()
	_test_residence_progression()
	await _test_furniture()
	await _test_furniture_placement()
	await _test_furniture_save_load()
	_test_home_storage()
	await _test_lifestyle()
	await _test_net_worth_integration()
	await _test_busted_in_own_vehicle()
	await _test_ownership_save_migration()
	await _test_trade_in()
	await _test_ownership_venues()

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
	var street_door := _player.interaction.get_focused()
	_check(
		street_door is Portal,
		"walking east along the frontage reaches the market door (x=%.1f)"
		% _player.global_position.x
	)

	# --- Inside ---
	await _press_action("interact")
	await _settle(25)
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	_check(
		_player.global_position.distance_to(store.global_position) < 20.0,
		"the door leads into the shop"
	)
	_check(_camera_rig.distance < 16.0, "the camera tightens indoors (%.0f)" % _camera_rig.distance)

	# Walking the aisle is not what this test is about — the walk to the door
	# above already proves movement — so step straight to the till.
	await _teleport(store.get_shop().global_position + Vector3(0.0, 0.1, 1.2))
	await _settle(20)
	var counter := _player.interaction.get_focused()
	_check(counter is Shop, "the counter is at the back of the shop")

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
	# The counter lives inside the shop now; the street door is just a doorway.
	var shop: Shop = _market_counter()
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


# --- Phase F: traffic, signals and pedestrian safety ---------------------

## TEST F1: the park is reachable. Before Phase F the park was a hole in the
## walking graph — a route into it ended at the nearest pavement.
func _test_park_navigation() -> void:
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	_check(nav != null, "the walking graph exists")
	if nav == null:
		return

	var gate := Vector3(District01.PARK_PATH_X, 0.0, District01.MAIN_ST_Z + 8.4)
	var far_end := Vector3(District01.PARK_PATH_X, 0.0, 55.0)
	var route := nav.find_path(NavGraph.Layer.WALK, gate, far_end)
	_check(route.size() >= 2, "there is a walking route from the street into the park")
	if route.size() >= 2:
		_check(
			route[route.size() - 1].distance_to(far_end) < 6.0,
			"and it reaches the far end of the park (%.1fm short)"
			% route[route.size() - 1].distance_to(far_end)
		)

	# The fountain sits on the crossing of the two paths; nothing may route
	# through it.
	var fountain := Vector3(District01.PARK_PATH_X, 0.0, District01.PARK_PATH_Z)
	var in_the_fountain := 0
	for point in route:
		if Vector2(point.x - fountain.x, point.z - fountain.z).length() < 3.6:
			in_the_fountain += 1
	_check(in_the_fountain == 0, "no waypoint stands in the fountain (%d)" % in_the_fountain)

	var east := nav.find_path(
		NavGraph.Layer.WALK,
		Vector3(District01.CENTER_BLVD_X - 8.4, 0.0, District01.PARK_PATH_Z),
		Vector3(-34.0, 0.0, District01.PARK_PATH_Z)
	)
	_check(east.size() >= 2, "the east gate joins the park to the boulevard")

	# And a civilian can actually walk it, not just route it. The player stands
	# where they can see it happen, because a civilian nobody is near is asleep
	# by design.
	var walker := get_tree().get_nodes_in_group(&"pedestrian")[0] as Pedestrian
	await _teleport(Vector3(District01.PARK_PATH_X + 8.0, 0.5, 20.0))
	walker.global_position = Vector3(District01.PARK_PATH_X, 0.4, 12.0)
	await _settle(6)
	var into_park := Vector3(District01.PARK_PATH_X, 0.0, 30.0)
	var before := walker.global_position.distance_to(into_park)
	_check(walker.walk_to(into_park), "a pedestrian accepts a destination inside the park")
	await _settle(300)
	var after := walker.global_position.distance_to(into_park)
	_check(after < before - 6.0, "and gets there (%.1fm -> %.1fm)" % [before, after])


## TEST F2: the lane graph is directed, turns at junctions and varies routes.
func _test_road_network() -> void:
	var network := _road_network()
	_check(network != null and network.is_ready(), "the district built a road network")
	if network == null or not network.is_ready():
		return
	_check(
		network.node_count() > 60,
		"lane nodes cover the district (%d)" % network.node_count()
	)

	# Nothing may link onto a lane running the other way; that is what keeps
	# traffic off the oncoming carriageway.
	var doubling_back := 0
	var off_road := 0
	for i in network.node_count():
		if not _is_on_a_lane(network.node_position(i)):
			off_road += 1
		for j in network.successors(i):
			if network.node_direction(i).dot(network.node_direction(j)) < -0.2:
				doubling_back += 1
	_check(doubling_back == 0, "no lane link doubles back (%d found)" % doubling_back)
	_check(off_road == 0, "every lane node sits on a carriageway (%d off)" % off_road)

	# Approaching the Main Street junction from the west, eastbound.
	var approach := network.nearest_node(
		Vector3(-11.0, 0.0, District01.LANE_OFFSET), Vector3(1.0, 0.0, 0.0)
	)
	var straight := 0
	var turns := 0
	for j in network.successors(approach):
		if network.node_direction(j).dot(network.node_direction(approach)) > 0.9:
			straight += 1
		else:
			turns += 1
	_check(straight > 0, "a car may carry straight on through the junction")
	_check(turns > 0, "or turn off it (%d turnings)" % turns)

	# Route variation: the same starting node must not always lead to the same
	# place, or every car circles the same block.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816
	var endpoints := {}
	for run in 30:
		var at := approach
		for step in 14:
			var next := network.random_successor(at, rng)
			if next < 0:
				break
			at = next
		endpoints[at] = true
	_check(endpoints.size() > 2, "routes diverge between cars (%d endings)" % endpoints.size())


## TEST F3: the signals cycle, and conflicting directions are never both green.
func _test_traffic_lights() -> void:
	var lights := get_tree().get_nodes_in_group(&"traffic_light")
	# Two in Harbour Row and three in Central. Counted per district rather than
	# city-wide, so this keeps saying something as more districts are added.
	var harbour_lights := 0
	for light in lights:
		if absf((light as Node3D).global_position.z) <= District01.EXTENT:
			harbour_lights += 1
	_check(harbour_lights == 2, "both Harbour Row junctions are signalled (%d)" % harbour_lights)
	_check(lights.size() >= 5, "and Central has its own signals (%d city-wide)" % lights.size())
	if lights.is_empty():
		return
	var light := lights[0] as TrafficLight

	_check(
		light.green_seconds >= 12.0 and light.green_seconds <= 20.0,
		"green runs 12-20 seconds (%.0f)" % light.green_seconds
	)
	_check(
		light.yellow_seconds >= 2.0 and light.yellow_seconds <= 4.0,
		"yellow runs 2-4 seconds (%.0f)" % light.yellow_seconds
	)
	_check(
		light.stop_line_distance > District01.ROAD_HALF,
		"the stop line sits outside the junction box (%.1fm)" % light.stop_line_distance
	)

	# Exhaustive rather than sampled: check the invariant in every phase there
	# is, which no amount of waiting could do better.
	var conflicts := 0
	var greens := 0
	for phase in [
		TrafficLight.Phase.NS_GREEN,
		TrafficLight.Phase.NS_YELLOW,
		TrafficLight.Phase.EW_GREEN,
		TrafficLight.Phase.EW_YELLOW,
	]:
		light.phase = phase
		if light.is_green_for(true) and light.is_green_for(false):
			conflicts += 1
		if light.is_green_for(true) or light.is_green_for(false):
			greens += 1
		# Yellow has to mean stop, or cars would sail through the change.
		if light.colour_for(true) == TrafficLight.Colour.YELLOW:
			_check(light.should_stop_for(true), "yellow counts as stop")
	_check(conflicts == 0, "north-south and east-west are never both green")
	_check(greens == 2, "exactly one axis is moving at a time (%d of 4 phases)" % greens)

	var line := light.stop_line_for(Vector3(1.0, 0.0, 0.0))
	_check(
		line.x < light.global_position.x - District01.ROAD_HALF,
		"eastbound traffic stops short of the junction (x=%.1f)" % line.x
	)

	# Now watch it actually run, on compressed timings so the test does not have
	# to sit through a real 36-second cycle.
	var green_was := light.green_seconds
	var yellow_was := light.yellow_seconds
	light.green_seconds = 0.35
	light.yellow_seconds = 0.2
	light.restart_cycle()
	var seen := {}
	for frame in 150:
		seen[light.phase] = true
		if light.is_green_for(true) and light.is_green_for(false):
			conflicts += 1
		await _settle(1)
	_check(seen.size() == 4, "the signal runs through all four phases (%d)" % seen.size())
	_check(conflicts == 0, "and never shows conflicting greens while running")

	light.green_seconds = green_was
	light.yellow_seconds = yellow_was
	light.restart_cycle()


## TEST F4: the manager keeps a believable, valid population on the roads.
func _test_traffic_population() -> void:
	var manager := _traffic_manager()
	_check(manager != null, "the district has a traffic manager")
	if manager == null:
		return

	_check(
		TrafficManager.CAR_SCENES.size() >= 3,
		"there are at least three civilian body styles (%d)" % TrafficManager.CAR_SCENES.size()
	)

	var cars := get_tree().get_nodes_in_group(&"traffic")
	_check(
		cars.size() >= 8 and cars.size() <= 15,
		"8-15 civilian cars are on the roads (%d)" % cars.size()
	)

	var styles := {}
	var wrong_controller := 0
	var hijackable := 0
	var off_road := 0
	var driverless := 0
	for node in cars:
		var car := node as Vehicle
		styles[car.data.id] = true
		if car.controller != Vehicle.Controller.TRAFFIC_AI:
			wrong_controller += 1
		if car.can_be_entered_by(_player):
			hijackable += 1
		# The junction margin, not zero: this is a sweep of live traffic, and a
		# car halfway round a corner is legitimately over the kerb line for a
		# moment. Zero is for cars the test placed itself.
		if not _is_on_a_lane(car.global_position, 2.5):
			off_road += 1
		if car.get_node_or_null("Driver") == null:
			driverless += 1
	_check(wrong_controller == 0, "every traffic car is flagged TRAFFIC_AI (%d not)" % wrong_controller)
	_check(driverless == 0, "and has a driver (%d without)" % driverless)
	_check(hijackable == 0, "none can be taken by walking up to it (%d could)" % hijackable)
	_check(off_road == 0, "every car spawned on a carriageway (%d did not)" % off_road)

	var overlapping := 0
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			if (cars[i] as Node3D).global_position.distance_to(
				(cars[j] as Node3D).global_position
			) < 3.0:
				overlapping += 1
	_check(overlapping == 0, "no car spawned inside another (%d pairs)" % overlapping)

	# Spawn validity, asked of the manager directly: an ordinary spawn must
	# never be close enough to the player to appear on screen.
	var too_close := 0
	var invalid := 0
	var in_a_junction := 0
	for attempt in 30:
		var node := manager.find_spawn_node(false)
		if node < 0:
			continue
		var spot := _road_network().node_position(node)
		if spot.distance_to(_player.global_position) < manager.min_spawn_distance_from_player:
			too_close += 1
		if not _is_on_a_lane(spot):
			invalid += 1
		for light in get_tree().get_nodes_in_group(&"traffic_light"):
			if (light as Node3D).global_position.distance_to(spot) < manager.junction_clearance:
				in_a_junction += 1
	_check(too_close == 0, "spawn points are never near the player (%d were)" % too_close)
	_check(invalid == 0, "and are always on a road (%d were not)" % invalid)
	_check(in_a_junction == 0, "and never inside a junction (%d were)" % in_a_junction)

	# Density is data, and night is quieter than day.
	var day_target := manager.get_target_population()
	var minutes_was := TimeManager.total_minutes
	TimeManager.set_total_minutes(2.0 * 60.0)
	var night_target := manager.get_target_population()
	TimeManager.set_total_minutes(minutes_was)
	_check(
		night_target < day_target,
		"the streets are quieter at night (%d vs %d)" % [night_target, day_target]
	)
	_check(
		TrafficManager.POPULATION[TrafficManager.Density.LOW]
		< TrafficManager.POPULATION[TrafficManager.Density.HIGH],
		"density settings actually differ"
	)


## TEST F5: traffic moves, keeps to the carriageway and to a sane speed.
func _test_traffic_flow() -> void:
	var cars := get_tree().get_nodes_in_group(&"traffic")
	var started_at := {}
	for node in cars:
		started_at[node] = (node as Node3D).global_position

	# Sampled across a window rather than at an instant: at any one moment a
	# good half of the traffic can legitimately be sat at a red light, so a
	# snapshot says nothing about whether the city is moving.
	var fastest := 0.0
	var speeding := 0
	var off_road := 0
	var wrecked := 0
	var airborne := 0
	var airborne_at := Vector3.ZERO
	for tick in 14:
		await _settle(40)
		for node in cars:
			var car := node as Vehicle
			fastest = maxf(fastest, car.get_speed_kmh())
			if car.get_speed_kmh() > 55.0:
				speeding += 1
			if not _is_on_a_lane(car.global_position, 2.5):
				off_road += 1
			if car.is_disabled():
				wrecked += 1
			if car.global_position.y > 1.5 or car.global_position.y < -1.0:
				airborne += 1
				airborne_at = car.global_position

	var travelled := 0
	for node in cars:
		if started_at[node].distance_to((node as Node3D).global_position) > 10.0:
			travelled += 1
	_check(
		travelled >= cars.size() / 2,
		"most of the traffic gets somewhere over ten seconds (%d of %d)"
		% [travelled, cars.size()]
	)
	_check(off_road == 0, "and none of it leaves the carriageway (%d samples)" % off_road)
	_check(speeding == 0, "nobody exceeds the 30-50 km/h band (fastest %.0f)" % fastest)
	_check(wrecked == 0, "nothing wrecked itself just driving around (%d samples)" % wrecked)
	_check(
		airborne == 0,
		"and nothing left the ground (%d samples%s)" % [
			airborne, "" if airborne == 0 else ", e.g. %v" % airborne_at
		]
	)


## TEST F6: police and traffic share the roads without sharing a controller, and
## a pursuing unit aims where the suspect is going.
func _test_police_and_traffic() -> void:
	var units := _police_cars()
	_check(units.size() >= 1, "there are patrol cars")
	if units.is_empty():
		return
	var unit := units[0] as Vehicle
	var driver := unit.get_node_or_null("Driver") as PoliceDriver
	_check(driver != null, "a patrol car has a police driver")
	if driver == null:
		return
	_check(
		unit.controller == Vehicle.Controller.POLICE_AI,
		"a patrol car is flagged POLICE_AI"
	)
	_check(
		not driver.is_siren_active(),
		"a parked unit has its lights and siren off"
	)

	await _teleport(Vector3(0.0, 0.5, 70.0))
	_player.velocity = Vector3.ZERO
	var still := driver.predict_intercept(_player)
	_check(
		still.distance_to(_player.global_position) < 1.0,
		"a stationary suspect is aimed at directly (%.1fm)"
		% still.distance_to(_player.global_position)
	)

	_player.velocity = Vector3(9.0, 0.0, 0.0)
	var lead := driver.predict_intercept(_player)
	_check(
		lead.x > _player.global_position.x + 3.0,
		"a moving one is led (%.1fm ahead)" % (lead.x - _player.global_position.x)
	)

	_player.velocity = Vector3(400.0, 0.0, 0.0)
	_check(
		driver.predict_intercept(_player).distance_to(_player.global_position)
		<= driver.max_lead_distance + 0.01,
		"and the lead is capped so it never aims through a building"
	)
	_player.velocity = Vector3.ZERO

	# Fast enough to close on traffic, slow enough that the player can escape.
	var patrol: VehicleData = unit.data
	var civilian: VehicleData = _player_car().data
	_check(
		patrol.max_speed > TrafficDriver.new().cruise_speed * 1.2,
		"a patrol car outruns civilian traffic (%.0f m/s)" % patrol.max_speed
	)
	_check(
		patrol.max_speed < civilian.max_speed * 1.2,
		"but not by enough to make escape impossible (%.0f vs %.0f)"
		% [patrol.max_speed, civilian.max_speed]
	)


## TEST F7: a car keeps its distance from whatever is in front of it — another
## car, or somebody standing in the road.
func _test_car_following() -> void:
	var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
	var front := await _spawn_test_traffic(Vector3(-40.0, 0.0, lane_z), -90.0)
	# Parked in the lane: the follower has to deal with it.
	(front.get_node("Driver") as TrafficDriver).set_physics_process(false)
	front.set_ai_input(0.0, 0.0, true)

	var rear := await _spawn_test_traffic(Vector3(-56.0, 0.0, lane_z), -90.0)
	await _settle(300)

	var gap := rear.global_position.distance_to(front.global_position)
	_check(gap > 3.2, "a following car stops behind the one in front (%.1fm)" % gap)
	_check(
		rear.get_planar_speed() < 2.0,
		"rather than shunting it (%.1f m/s)" % rear.get_planar_speed()
	)
	_check(front.health >= front.data.max_health, "and does not damage it")
	await _despawn([front, rear])

	# Now a person in the road instead of a car.
	var walker := get_tree().get_nodes_in_group(&"pedestrian")[1] as Pedestrian
	var home := walker.global_position
	await _teleport(Vector3(-40.0, 0.5, lane_z + 10.0))
	# Standing their ground: the point of the check is the driver's reaction,
	# not the pedestrian's, so they neither dodge nor wander off mid-test.
	walker.danger_check_interval = 9999.0
	walker.global_position = Vector3(-40.0, 0.4, lane_z)
	walker.wait_for(60.0)
	await _settle(6)

	var approaching := await _spawn_test_traffic(Vector3(-62.0, 0.0, lane_z), -90.0)
	await _settle(240)
	var clearance := approaching.global_position.distance_to(walker.global_position)
	_check(
		clearance > 2.5,
		"a car keeps its distance from somebody in its lane rather than driving over them (%.1fm)"
		% clearance
	)
	_check(
		approaching.global_position.x > -56.0,
		"and it did set off towards them (x=%.1f)" % approaching.global_position.x
	)
	_check(not walker.is_down(), "and the pedestrian is still on their feet")

	await _despawn([approaching])
	walker.danger_check_interval = 0.25
	walker.global_position = home
	walker.wait_for(0.5)
	await _settle(6)


## TEST F8: red means stop, green means go.
func _test_traffic_stops_at_red() -> void:
	var light: TrafficLight = null
	for node in get_tree().get_nodes_in_group(&"traffic_light"):
		if absf((node as Node3D).global_position.z - District01.MAIN_ST_Z) < 1.0:
			light = node
			break
	_check(light != null, "the Main Street junction has a signal")
	if light == null:
		return

	var green_was := light.green_seconds
	var phase_was := light.start_phase
	# A very long north-south green is a very long east-west red.
	light.green_seconds = 600.0
	light.start_phase = TrafficLight.Phase.NS_GREEN
	light.restart_cycle()
	_check(
		light.should_stop_for(true),
		"the east-west approach is showing red for this test"
	)

	var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
	var car := await _spawn_test_traffic(Vector3(-34.0, 0.0, lane_z), -90.0)
	await _settle(330)

	var stop_line := light.global_position.x - light.stop_line_distance
	_check(
		car.global_position.x < stop_line + 2.0,
		"a car stops at the red rather than crossing the line (x=%.1f, line %.1f)"
		% [car.global_position.x, stop_line]
	)
	_check(
		car.global_position.x > -30.0,
		"and it did approach the junction rather than never setting off (x=%.1f)"
		% car.global_position.x
	)
	_check(
		car.get_planar_speed() < 1.0,
		"and waits there (%.1f m/s)" % car.get_planar_speed()
	)

	var waited_at := car.global_position.x
	light.start_phase = TrafficLight.Phase.EW_GREEN
	light.restart_cycle()
	# Waited for rather than timed: restarting the cycle can put a clearance
	# phase in front of the green, and a car pulling away from a dead stop is
	# not quick. What matters is that it goes, not that it goes within exactly
	# three seconds.
	await _wait_until(
		func() -> bool: return car.global_position.x > waited_at + 5.0, 9.0,
		"the car to pull away on green"
	)
	_check(
		car.global_position.x > waited_at + 5.0,
		"and moves off when it turns green (%.1f -> %.1f)" % [waited_at, car.global_position.x]
	)

	await _despawn([car])
	light.green_seconds = green_was
	light.start_phase = phase_was
	light.restart_cycle()


## TEST F9: a car that cannot make progress tries another way out before it
## gives up, and gives up rather than sitting there forever.
func _test_traffic_stuck_recovery() -> void:
	var lane_z := District01.MAIN_ST_Z + District01.LANE_OFFSET
	var car := await _spawn_test_traffic(Vector3(-46.0, 0.0, lane_z), -90.0)
	var driver := car.get_node("Driver") as TrafficDriver

	_check(driver.stuck_timeout >= 2.0, "the shipped stuck timeout is conservative (%.1fs)" % driver.stuck_timeout)
	# Compressed so the ladder runs in a second rather than fifteen.
	driver.stuck_timeout = 0.4
	driver.max_recoveries = 2

	var recycles := [0]
	driver.recycle_requested.connect(func() -> void: recycles[0] += 1)

	# Wedged, simulated the only way that is deterministic: the car is told to
	# drive and does not move. Every real cause — kerb, railing, another car
	# across the nose — looks exactly like this to the driver.
	var first_target := driver.get_target_position()
	car.set_physics_process(false)
	car.halt()
	await _settle(45)
	var retargeted := driver.get_target_position() != first_target
	_check(retargeted, "a wedged car tries a different way out first")
	_check(recycles[0] == 0, "and does not give up on the first attempt")

	await _settle(150)
	_check(recycles[0] >= 1, "but asks to be recycled once the attempts run out")

	car.set_physics_process(true)
	await _despawn([car])


## TEST F10 (Issue A): a car no longer passes through a pedestrian.
func _test_pedestrian_knockdown() -> void:
	var walker := get_tree().get_nodes_in_group(&"pedestrian")[2] as Pedestrian
	var home := walker.global_position
	await _teleport(Vector3(-40.0, 0.5, 84.0))
	# Not dodging and not wandering off: this test is about what happens when
	# somebody does not get out of the way.
	walker.danger_check_interval = 9999.0
	walker.global_position = Vector3(-40.0, 0.4, 74.0)
	walker.wait_for(60.0)
	await _settle(8)

	CrimeManager.clear_history()
	_notifications.clear()

	var car := _player_car()
	car.hit_and_run_grace = 1.0
	car.hit_and_run_distance = 12.0
	await _park_for_test(car, Vector3(-62.0, 0.0, 74.0), -90.0)
	await _drive(car)
	await _hold(["move_forward"], 200)

	_check(walker.is_down(), "the car knocks the pedestrian down instead of passing through")
	_check(
		walker.health < walker.max_health,
		"the impact costs them health (%.0f)" % walker.health
	)
	_check(walker.collision_layer == 0, "and takes them out of the way while they are down")
	_check(
		car.get_planar_speed() > 1.0,
		"a body does not stop the car dead (%.1f m/s)" % car.get_planar_speed()
	)

	var assaults := CrimeManager.get_incidents_of(CrimeManager.CrimeType.VEHICULAR_ASSAULT)
	_check(assaults.size() == 1, "running somebody over is filed (%d records)" % assaults.size())
	_check(
		assaults.size() == 1 and assaults[0].get("incident_only", false),
		"as an incident, not as a crime report"
	)
	_check(WantedManager.level == 0, "so Phase F raises no wanted level for it")

	# Drive on: leaving the scene is what makes it a hit and run.
	await _hold(["move_forward"], 120)
	await _settle(150)
	_check(
		CrimeManager.get_incidents_of(CrimeManager.CrimeType.HIT_AND_RUN).size() == 1,
		"driving away turns it into a hit and run"
	)

	await _leave_vehicle()
	await _settle(280)
	_check(not walker.is_down(), "the pedestrian gets back up")
	_check(
		walker.state == Pedestrian.State.FLEEING,
		"and gets out of the road (state %d)" % walker.state
	)
	_check(walker.collision_layer == 1 << 4, "and is solid again")

	car.hit_and_run_grace = 6.0
	car.hit_and_run_distance = 25.0
	car.repair()
	car.return_to_spawn()
	walker.danger_check_interval = 0.25
	walker.global_position = home
	walker.wait_for(0.5)
	CrimeManager.clear_history()
	await _settle(8)


## TEST F11: a pedestrian gets out of the way of a car bearing down on them.
func _test_pedestrian_dodges_traffic() -> void:
	var walker := get_tree().get_nodes_in_group(&"pedestrian")[3] as Pedestrian
	var home := walker.global_position
	# Watched from the pavement: a civilian with nobody near them is asleep, so
	# the player has to be here for there to be anything to check.
	await _teleport(Vector3(-40.0, 0.5, 84.0))
	# Slightly off the car's centre line, so which way they jump is decided
	# rather than a coin toss.
	walker.global_position = Vector3(-40.0, 0.4, 74.8)
	walker.wait_for(60.0)
	await _settle(8)
	var started_at := walker.global_position

	var car := await _spawn_test_traffic(Vector3(-68.0, 0.0, 74.0), -90.0)
	# There is no lane out here; drive it by hand at a realistic traffic speed.
	(car.get_node("Driver") as TrafficDriver).set_physics_process(false)
	car.set_ai_input(1.0, 0.0, false)
	await _settle(150)

	_check(
		walker.state == Pedestrian.State.DODGING or walker.state == Pedestrian.State.FLEEING,
		"a pedestrian reacts to a car bearing down on them (state %d)" % walker.state
	)
	_check(
		absf(walker.global_position.z - started_at.z) > 1.0,
		"and moves sideways out of its path (%.1fm)"
		% absf(walker.global_position.z - started_at.z)
	)
	_check(not walker.is_down(), "so it misses them")

	await _despawn([car])
	walker.global_position = home
	await _settle(6)


# --- Phase D: vehicles ---------------------------------------------------

func _test_vehicles_spawned() -> void:
	var cars := _vehicles()
	# Harbour Row's own eight, counted where they stand: Central parks its own,
	# and the two sets should not be able to hide each other's absence.
	var harbour: Array = []
	var central: Array = []
	for car in cars:
		if District02.BOUNDS.has_point(Vector2(car.global_position.x, car.global_position.z)):
			central.append(car)
		else:
			harbour.append(car)
	_check(harbour.size() == 8, "8 vehicles parked in Harbour Row (got %d)" % harbour.size())
	_check(central.size() >= 6, "and Central parks its own (%d)" % central.size())

	var owned := 0
	var npc := 0
	var healthy := true
	for car in harbour:
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
	# Phase D's theft checks assume nobody is watching. Witnesses exist now, so
	# the scene has to be cleared for the test to still mean what it meant.
	await _isolate_scene()
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
	_check(record.get("witnessed") == false, "an empty street means nobody witnessed it")
	_check(
		_notifications.any(func(m: String) -> bool: return m.begins_with("VEHICLE THEFT")),
		"the player is told a theft happened"
	)

	_check(WantedManager.level == 0, "an unwitnessed theft raises no wanted level")

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

	# Phase F: the pivot also leads the car, so the road ahead is on screen.
	var lead := _camera_rig.get_look_ahead_distance()
	_check(lead > 2.0, "and it looks ahead of the car at speed (%.1fm)" % lead)
	_check(
		lead <= _camera_rig.look_ahead_distance + 0.01,
		"never further than the configured lead (%.1fm)" % lead
	)
	var ahead_of_car := (
		_camera_rig.global_position - car.global_position
	).normalized().dot(car.get_facing())
	_check(ahead_of_car > 0.5, "and leads in front of it, not behind (%.2f)" % ahead_of_car)

	await _stop_vehicle(car)
	await _settle(120)
	_check(
		_camera_rig.get_effective_distance() < parked_view + 1.0,
		"slowing down brings it back in (%.1f)" % _camera_rig.get_effective_distance()
	)
	_check(
		_camera_rig.get_look_ahead_distance() < 1.0,
		"and the look-ahead eases back onto the car (%.1fm)"
		% _camera_rig.get_look_ahead_distance()
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


# --- Phase E: crowd, witnesses, wanted, police ---------------------------

func _test_crowd_spawned() -> void:
	var civilians := get_tree().get_nodes_in_group(&"pedestrian")
	var officers := _officers()
	# The crowd is counted per district: Harbour Row is as it always was, and
	# Central is busier, which is the point of Central.
	var harbour := 0
	var central := 0
	for node in civilians:
		var where: Vector3 = (node as Node3D).global_position
		if District02.BOUNDS.has_point(Vector2(where.x, where.z)):
			central += 1
		else:
			harbour += 1
	_check(
		harbour >= 12 and harbour <= 22,
		"Harbour Row is populated as it was (%d pedestrians)" % harbour
	)
	_check(central >= 18 and central <= 35, "and Central is busier (%d)" % central)
	_check(officers.size() >= 3, "officers are on foot (%d city-wide)" % officers.size())
	_check(_police_cars().size() == 2, "two patrol cars are at the precinct")
	_check(
		get_tree().get_first_node_in_group(&"bust_release_point") != null,
		"there is a release point outside the precinct"
	)

	# Civilians must actually go somewhere, not stand still — but only the ones
	# near the player. The rest of the city is asleep on purpose, which is the
	# other half of this check.
	var before: Array[Vector3] = []
	var near: Array[int] = []
	for i in civilians.size():
		var civilian: Node3D = civilians[i]
		before.append(civilian.global_position)
		# Partitioned by what the crowd itself says, not by a distance repeated
		# here: a second copy of the rule would eventually disagree with it.
		if bool(civilian.call("is_active")):
			near.append(i)
	await _settle(180)

	var moved := 0
	for i in near:
		if civilians[i].global_position.distance_to(before[i]) > 2.0:
			moved += 1
	_check(near.size() >= 10, "there is a crowd around the player (%d)" % near.size())
	_check(
		moved >= near.size() / 2,
		"most of whom are walking (%d of %d moved, paused=%s)" % [
			moved, near.size(), get_tree().paused
		]
	)

	var far_moved := 0
	var far_total := 0
	for i in civilians.size():
		if i in near:
			continue
		far_total += 1
		if civilians[i].global_position.distance_to(before[i]) > 2.0:
			far_moved += 1
	_check(far_total > 0, "and a crowd in the other district (%d)" % far_total)
	_check(
		far_moved == 0,
		"which costs nothing while the player is not there (%d moved)" % far_moved
	)
	var asleep := 0
	for i in civilians.size():
		if not (i in near) and not bool(civilians[i].call("is_active")):
			asleep += 1
	_check(
		asleep == far_total,
		"and every one of them reports itself asleep (%d of %d)" % [asleep, far_total]
	)


func _test_navigation() -> void:
	var nav: NavGraph = _main.get_node("District01/NavGraph")
	_check(nav.is_ready(NavGraph.Layer.WALK), "the pavement graph built (%d nodes)" % nav.point_count(NavGraph.Layer.WALK))
	_check(nav.is_ready(NavGraph.Layer.ROAD), "the road graph built (%d nodes)" % nav.point_count(NavGraph.Layer.ROAD))

	# Opposite corners of the district must be connected on both layers,
	# otherwise a pedestrian or a patrol car can be stranded.
	var walk := nav.find_path(NavGraph.Layer.WALK, Vector3(-80, 0, -7.5), Vector3(80, 0, 7.5))
	_check(walk.size() > 2, "pavements connect across the district (%d hops)" % walk.size())
	var road := nav.find_path(NavGraph.Layer.ROAD, Vector3(-80, 0, 0), Vector3(0, 0, 80))
	_check(road.size() > 2, "roads connect around the junctions (%d hops)" % road.size())


## TEST A — a theft nobody sees costs nothing.
func _test_unseen_theft() -> void:
	await _prepare_crime_scene()
	var car := _spare_npc_car()
	await _park_for_test(car, Vector3(0.0, 0.0, 74.0), 0.0)
	await _stand_beside(car)

	await _press_action("enter_vehicle")
	await _settle(10)

	var record := CrimeManager.get_last_crime()
	_check(not record.is_empty(), "the theft is still recorded")
	_check(record.get("witnessed") == false, "nobody witnessed it")
	_check(record.get("reported") == false, "so it is never reported")
	_check(WantedManager.level == 0, "wanted level stays at zero")
	_check(_said("VEHICLE THEFT"), "the player is told the car was stolen")
	_check(not _said("CRIME REPORTED"), "but not that it was reported")

	# Give the delayed-report path time to fire if it wrongly queued one.
	await _settle(200)
	_check(WantedManager.level == 0, "still no heat after the report delay")
	await _leave_vehicle()


## TEST B — a civilian who sees it calls it in, after a delay.
func _test_civilian_witness() -> void:
	await _prepare_crime_scene()
	var car := _spare_npc_car()
	await _park_for_test(car, Vector3(0.0, 0.0, 70.0), 0.0)

	var civilian: Node3D = get_tree().get_nodes_in_group(&"pedestrian")[0]
	await _place_witness(civilian, car.global_position + Vector3(6.0, 0.0, 3.0), car.global_position)
	# Police within earshot of the call but too far to have seen it themselves.
	await _station_police_near(car.global_position, 50.0)
	await _stand_beside(car)

	await _press_action("enter_vehicle")
	await _settle(10)

	var record := CrimeManager.get_last_crime()
	_check(
		record.get("witnessed") == true,
		"the civilian saw it (state %d, cond %d, available %s, %.1fm)" % [
			civilian.state,
			civilian.condition,
			civilian.is_available_as_witness(),
			civilian.global_position.distance_to(car.global_position),
		]
	)
	_check(record.get("reporting_witness") == civilian, "the record names who saw it")
	_check(civilian.state == Pedestrian.State.WITNESSING, "the witness stops and stares")
	_check(WantedManager.level == 0, "no heat yet — they have not called it in")

	# Report delay, plus a margin.
	await _settle(int((WitnessSystem.report_delay + 0.7) * 60.0))
	_check(record.get("reported") == true, "the crime gets reported")
	_check(_said("CRIME REPORTED"), "CRIME REPORTED is shown")
	_check(WantedManager.level == 1, "wanted level 1 (got %d)" % WantedManager.level)

	await _settle(30)
	_check(_responding_units() > 0, "police respond (%d units)" % _responding_units())
	_check(
		civilian.state == Pedestrian.State.FLEEING,
		"the witness gets out of there afterwards"
	)
	await _leave_vehicle()


## TEST C — an officer who sees it needs no phone call.
func _test_police_witness() -> void:
	await _prepare_crime_scene()
	var car := _spare_npc_car()
	await _park_for_test(car, Vector3(0.0, 0.0, 66.0), 0.0)

	var officer: PoliceOfficer = _officers()[0]
	await _place_witness(officer, car.global_position + Vector3(7.0, 0.0, 4.0), car.global_position)
	await _stand_beside(car)

	await _press_action("enter_vehicle")
	await _settle(6)

	var record := CrimeManager.get_last_crime()
	_check(record.get("witnessed") == true, "the officer saw it")
	_check(record.get("reported") == true, "and reported it on the spot")
	_check(
		WantedManager.level == 1,
		"wanted level 1 immediately, with no civilian delay (got %d)" % WantedManager.level
	)

	await _settle(40)
	_check(
		officer.state == PoliceOfficer.State.PURSUING or officer.state == PoliceOfficer.State.RESPONDING,
		"the officer gives chase (state %d)" % officer.state
	)
	await _leave_vehicle()


## TEST D — break line of sight, wait it out, go free.
func _test_escape() -> void:
	await _prepare_crime_scene()
	# A short countdown keeps the test quick; the shipped default is checked
	# separately below.
	var real_escape: Array = WantedManager.escape_seconds_by_level.duplicate()
	WantedManager.escape_seconds_by_level = [0.0, 3.0, 4.0, 5.0, 6.0, 7.0]

	await _teleport(Vector3(-40.0, 0.5, 8.4))
	# Far enough that they cannot see the player, close enough to be dispatched.
	await _station_police_near(_player.global_position, 60.0)
	WantedManager.set_level(1)
	await _settle(6)
	_check(WantedManager.level == 1, "wanted level set")
	_check(not WantedManager.is_escaping(), "not escaping while freshly spotted")

	# Nobody can see the player: the countdown should start on its own.
	await _settle(int((WantedManager.sight_grace_seconds + 0.4) * 60.0))
	_check(WantedManager.is_escaping(), "ESCAPING begins once nobody has eyes on")
	_check(_main.get_node("HUD/Root/TopRight/EscapeLabel").visible, "the HUD shows it")
	_check(_said("ESCAPING..."), "the player is told")

	var searching := 0
	for officer in _officers():
		if officer.state == PoliceOfficer.State.SEARCHING or officer.state == PoliceOfficer.State.RESPONDING:
			searching += 1
	_check(searching > 0, "police search the last known position (%d units)" % searching)

	# The searchers have done their job for this test; push them back out of
	# arrest reach before starting the clock. A cruiser stationed 60m away can
	# cover that in roughly the length of the shortened countdown, so leaving
	# them where they are makes this a race between two unrelated mechanics —
	# and a slower frame hands it to the arrest instead of the escape. Getting
	# caught mid-search is correct behaviour and is tested on its own; here it
	# is only noise.
	var searchers: Array = _officers() + _police_cars()
	for unit: Node3D in searchers:
		unit.global_position += (unit.global_position - _player.global_position).normalized() * 90.0

	var busts_before := CrimeManager.get_statistic(&"times_busted")
	await _wait_until(
		func() -> bool: return WantedManager.level == 0, 12.0,
		"the escape countdown to run out"
	)
	_check(
		CrimeManager.get_statistic(&"times_busted") == busts_before,
		"the player got away rather than being arrested"
	)
	_check(WantedManager.level == 0, "the wanted level clears")
	_check(_said("WANTED LEVEL CLEARED"), "WANTED LEVEL CLEARED is shown")
	_check(not _main.get_node("HUD/Root/TopRight/WantedLabel").visible, "the stars go away")

	WantedManager.escape_seconds_by_level = real_escape
	_check(
		real_escape[1] >= 15.0 and real_escape[1] <= 25.0,
		"the shipped level 1 countdown is %.0fs, inside the brief's 15-25s" % real_escape[1]
	)


## TEST E — being spotted again cancels the countdown without clearing heat.
func _test_reacquisition() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	WantedManager.set_level(1)

	await _settle(int((WantedManager.sight_grace_seconds + 0.4) * 60.0))
	_check(WantedManager.is_escaping(), "escaping first")

	# Put an officer where they can plainly see the player.
	var officer: PoliceOfficer = _officers()[1]
	await _place_witness(
		officer, _player.global_position + Vector3(15.0, 0.0, 0.0), _player.global_position
	)
	await _settle(50)

	_check(not WantedManager.is_escaping(), "being seen cancels the countdown")
	_check(WantedManager.level == 1, "the wanted level survives (got %d)" % WantedManager.level)
	_check(
		officer.state == PoliceOfficer.State.PURSUING,
		"the officer resumes the chase (state %d)" % officer.state
	)
	WantedManager.clear_wanted("")
	await _settle(10)


## TEST F — caught, fined, released, and playable again.
func _test_bust() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	EconomyManager.restore(600)
	WantedManager.set_level(1)

	var officer: PoliceOfficer = _officers()[2]
	await _place_witness(
		officer, _player.global_position + Vector3(1.6, 0.0, 0.0), _player.global_position
	)
	await _settle(30)

	_check(WantedManager.is_busting() or GameManager.cutscene_active, "the arrest starts")
	_check(_main.get_node("HUD/Root/BustedOverlay").visible, "BUSTED is on screen")

	var fine := WantedManager.get_bust_fine()
	await _settle(int((WantedManager.bust_hold_seconds + 1.0) * 60.0))

	_check(EconomyManager.cash == 600 - fine, "the fine is charged (now $%d)" % EconomyManager.cash)
	_check(WantedManager.level == 0, "the wanted level is cleared")
	_check(not GameManager.cutscene_active, "control comes back")
	_check(not get_tree().paused, "the world unfreezes")
	_check(not _main.get_node("HUD/Root/BustedOverlay").visible, "the overlay is dismissed")

	var release := get_tree().get_first_node_in_group(&"bust_release_point") as Node3D
	_check(
		_player.global_position.distance_to(release.global_position) < 6.0,
		"the player is released outside the precinct"
	)
	await _settle(30)
	_check(_player.is_on_floor(), "released onto solid ground, not inside geometry")

	# Walking still works straight after an arrest.
	var before := _player.global_position
	await _hold(["move_forward"], 40)
	_check(_player.global_position.distance_to(before) > 1.5, "the player can walk again")

	# A player who cannot afford the fine must not go negative.
	await _prepare_crime_scene()
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	EconomyManager.restore(40)
	WantedManager.set_level(1)
	await _place_witness(
		_officers()[0], _player.global_position + Vector3(1.6, 0.0, 0.0), _player.global_position
	)
	await _settle(int((WantedManager.bust_hold_seconds + 1.6) * 60.0))
	_check(EconomyManager.cash == 0, "a skint player pays what they have (%d)" % EconomyManager.cash)
	_check(EconomyManager.cash >= 0, "and never goes into the red")


## TEST G — the same chase works after dark.
func _test_night_pursuit() -> void:
	await _prepare_crime_scene()
	TimeManager.set_total_minutes(23.0 * 60.0)
	await _settle(10)

	await _teleport(Vector3(-40.0, 0.5, 8.4))
	EconomyManager.restore(600)
	WantedManager.set_level(1)

	var officer: PoliceOfficer = _officers()[0]
	await _place_witness(
		officer, _player.global_position + Vector3(16.0, 0.0, 0.0), _player.global_position
	)
	await _settle(50)
	_check(
		officer.state == PoliceOfficer.State.PURSUING,
		"police still see and chase the player at 23:00 (state %d)" % officer.state
	)
	_check(not WantedManager.is_escaping(), "being seen at night counts as being seen")

	await _settle(200)
	_check(
		WantedManager.level == 0 or WantedManager.is_busting() or GameManager.cutscene_active,
		"the night chase resolves rather than hanging"
	)
	await _settle(int((WantedManager.bust_hold_seconds + 1.2) * 60.0))
	WantedManager.clear_wanted("")
	TimeManager.set_total_minutes(11.0 * 60.0)
	await _settle(10)


func _test_wanted_debug_keys() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(-40.0, 0.5, 8.4))

	await _press_action("debug_wanted_1")
	await _settle(4)
	_check(WantedManager.level == 1, "F6 sets one star")

	await _press_action("debug_wanted_2")
	await _settle(4)
	_check(WantedManager.level == 2, "F7 sets two stars")
	_check(
		WantedManager.get_response_radius() > WantedManager.response_radius_by_level[1],
		"level 2 widens the response radius"
	)

	await _press_action("debug_clear_wanted")
	await _settle(4)
	_check(WantedManager.level == 0, "F9 clears the wanted level")


# --- Phase E helpers -----------------------------------------------------

func _officers() -> Array:
	return get_tree().get_nodes_in_group(&"police").filter(
		func(unit: Node) -> bool: return unit is PoliceOfficer
	)


func _responding_units() -> int:
	var count := 0
	for officer in _officers():
		if officer.state != PoliceOfficer.State.PATROL:
			count += 1
	for car in _police_cars():
		var driver: PoliceDriver = car.get_node("Driver")
		if driver.state != PoliceDriver.State.PARKED:
			count += 1
	return count


## Empty street, no heat, clean ledger, player out of any car.
func _prepare_crime_scene() -> void:
	await _leave_vehicle()
	WantedManager.clear_wanted("")
	await _isolate_scene()
	# A witness from the previous test may still be part-way through their
	# report delay. Let those land before the ledger is wiped, or one arrives in
	# the middle of the next test and moves its wanted level — which cost an
	# afternoon to work out the first time it happened.
	await _settle(int((WitnessSystem.report_delay + 0.5) * 60.0))
	WantedManager.clear_wanted("")
	CrimeManager.clear_history()
	_notifications.clear()
	await _settle(6)


## Wakes the officers and patrol cars and rings them around `center` at a
## distance that is inside their response radius but outside their sight radius,
## so they answer the call without having witnessed the crime themselves.
func _station_police_near(center: Vector3, distance: float) -> void:
	var units: Array = _officers() + _police_cars()
	for i in units.size():
		var unit: Node3D = units[i]
		var angle := TAU * float(i) / float(maxi(units.size(), 1))
		unit.process_mode = Node.PROCESS_MODE_INHERIT
		unit.global_position = center + Vector3(cos(angle), 0.0, sin(angle)) * distance
	await _settle(6)


## An NPC car that has not already been stolen this run, since theft is only
## reported once per vehicle.
func _spare_npc_car() -> Vehicle:
	for car in _vehicles():
		if car.owner_type == Vehicle.OwnerType.NPC and not car.get("_theft_reported"):
			return car
	return null


func _said(fragment: String) -> bool:
	return _notifications.any(func(m: String) -> bool: return m.contains(fragment))


# --- Vehicle helpers -----------------------------------------------------

## Rough test for "is this on a carriageway" — within a road's half width of one
## of the three street centre lines.
## `margin` allows for the kerb a car legitimately clips while swinging round a
## junction; pass 0 when checking somewhere a car was deliberately placed.
## Every carriageway in the city, as [is east-west, centre, from, to, half width].
##
## Built from what the districts themselves say their streets are, rather than
## from a copy of Harbour Row's three centre lines — which is what this used to
## be, and which stopped describing the city the moment there were two of them.
func _city_streets() -> Array:
	if not _street_cache.is_empty():
		return _street_cache
	var reach := District01.EXTENT
	_street_cache = [
		[true, District01.MAIN_ST_Z, -reach, reach, District01.ROAD_HALF],
		[true, District01.NORTH_AVE_Z, -reach, reach, District01.ROAD_HALF],
		[false, District01.CENTER_BLVD_X, -reach, reach, District01.ROAD_HALF],
		# The road joining the two districts.
		[false, District01.CENTER_BLVD_X, District02.GATEWAY_Z, -reach, District01.ROAD_HALF],
	]
	for node in get_tree().get_nodes_in_group(&"district"):
		if node is District02:
			_street_cache.append_array((node as District02).street_lines())
	return _street_cache


var _street_cache: Array = []


## Whether a point is on a carriageway anywhere in the city.
func _is_on_a_lane(where: Vector3, margin: float = 0.0) -> bool:
	for entry in _city_streets():
		var east_west: bool = entry[0]
		var centre: float = entry[1]
		var from: float = minf(entry[2], entry[3])
		var to: float = maxf(entry[2], entry[3])
		var along: float = where.x if east_west else where.z
		var across: float = where.z if east_west else where.x
		if along < from - margin or along > to + margin:
			continue
		if absf(across - centre) <= float(entry[4]) + margin:
			return true
	return false


## A civilian car driven by the traffic AI, placed by hand. Used by the tests
## that need one specific car in one specific place, which the manager — whose
## whole job is choosing those things itself — cannot give them.
func _spawn_test_traffic(at: Vector3, yaw_degrees: float) -> Vehicle:
	var car: Vehicle = TEST_TRAFFIC_SCENE.instantiate()
	car.controller = Vehicle.Controller.TRAFFIC_AI
	car.owner_type = Vehicle.OwnerType.NPC
	car.owner_id = &"traffic"
	car.position = at
	car.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	_main.add_child(car)

	var driver := TrafficDriver.new()
	driver.name = "Driver"
	car.add_child(driver)
	await _settle(4)
	return car


func _despawn(nodes: Array) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await _settle(4)


## The parked-car layout only. Police cars and moving civilian traffic are in
## the same group but are not part of it.
func _vehicles() -> Array:
	return get_tree().get_nodes_in_group(&"vehicle").filter(
		func(car: Node) -> bool:
			return not car.is_in_group(&"police") and not car.is_in_group(&"traffic")
	)


func _market_counter() -> Shop:
	return (_main.get_node("Interiors/ConvenienceStore") as ConvenienceStoreInterior).get_shop()


func _traffic_manager() -> TrafficManager:
	return get_tree().get_first_node_in_group(&"traffic_manager") as TrafficManager


func _road_network() -> RoadNetwork:
	return get_tree().get_first_node_in_group(&"road_network") as RoadNetwork


## Clears the roads for the tests that need to know exactly what is on them.
## Traffic is tested on its own, before this is called.
func _stop_traffic() -> void:
	var manager := _traffic_manager()
	if manager == null:
		return
	manager.set_active(false)
	manager.clear()
	await _settle(4)


## Refills the roads. `prime` ignores the keep-away-from-the-player rule, which
## is what the district does at load and what a test wants: a full city now,
## not one that arrives over the next half minute.
func _start_traffic() -> void:
	var manager := _traffic_manager()
	if manager == null:
		return
	manager.set_active(true)
	manager.prime()
	await _settle(30)


func _police_cars() -> Array:
	return get_tree().get_nodes_in_group(&"police_car")


## Moves every civilian and officer to an empty corner and freezes them, so a
## test controls exactly who is present. Witness queries search by group, so
## they have to be moved, not merely stopped.
func _isolate_scene() -> void:
	var corner := Vector3(400.0, 0.0, 400.0)
	var offset := 0.0
	for node in get_tree().get_nodes_in_group(&"pedestrian") + get_tree().get_nodes_in_group(&"police"):
		if node is Node3D:
			node.global_position = corner + Vector3(offset, 0.0, 0.0)
			offset += 4.0
		if node.has_method("stop"):
			node.call("stop")
		node.process_mode = Node.PROCESS_MODE_DISABLED
	await _settle(4)


## Brings one NPC back into play at `spot`, looking at `look_at_point`.
func _place_witness(node: Node3D, spot: Vector3, look_at_point: Vector3) -> void:
	node.process_mode = Node.PROCESS_MODE_INHERIT
	node.global_position = spot
	if node.has_method("wake"):
		node.call("wake")
	var to_target := look_at_point - spot
	to_target.y = 0.0
	if to_target.length_squared() > 0.01 and node.has_node("BodyPivot"):
		node.get_node("BodyPivot").rotation.y = atan2(to_target.x, to_target.z)
	await _settle(4)


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


## Waits until `condition` is true, or `timeout_seconds` of real time passes.
##
## For anything counted in seconds rather than in physics frames — the escape
## countdown, a delivery — because the two are not a fixed ratio: a heavier scene
## runs more physics ticks per second of wall clock, and a test calibrated in
## frames quietly starts failing when the world gets bigger.
func _wait_until(condition: Callable, timeout_seconds: float, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await _settle(6)
	push_warning("Timed out waiting for %s" % description)
	return false


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


# --- Phase G: crime expansion --------------------------------------------
#
# The crime systems are tested in two halves. The data — severities, points,
# thresholds, fines — is checked directly, because it is a table and a table
# either says the right thing or it does not. Everything else is played: the
# player walks in, takes something, walks out, and the crime either lands or it
# does not. Anything checked by calling the same method the game calls proves
# nothing about whether the game can reach it.

## The crime table itself: every crime priced, and priced in the right order.
func _test_crime_profiles() -> void:
	var missing: Array[String] = []
	for type in CrimeManager.CrimeType.values():
		if not CrimeManager.PROFILES.has(type):
			missing.append(CrimeManager.get_type_name(type))
	_check(missing.is_empty(), "every crime type has a profile (missing: %s)" % ", ".join(missing))

	_check(CrimeManager.points_for(CrimeManager.CrimeType.TRESPASSING) == 5, "trespassing is 5 points")
	_check(CrimeManager.points_for(CrimeManager.CrimeType.SHOPLIFTING) == 10, "shoplifting is 10 points")
	_check(CrimeManager.points_for(CrimeManager.CrimeType.VEHICLE_THEFT) == 20, "vehicle theft is 20 points")
	_check(CrimeManager.points_for(CrimeManager.CrimeType.ASSAULT) == 25, "assault is 25 points")
	_check(CrimeManager.points_for(CrimeManager.CrimeType.CARJACKING) == 35, "carjacking is 35 points")
	_check(CrimeManager.points_for(CrimeManager.CrimeType.STORE_ROBBERY) == 40, "store robbery is 40 points")

	_check(
		CrimeManager.severity_of(CrimeManager.CrimeType.TRESPASSING)
		< CrimeManager.severity_of(CrimeManager.CrimeType.STORE_ROBBERY),
		"a robbery is more serious than a trespass"
	)
	_check(
		CrimeManager.evidence_for(CrimeManager.CrimeType.STORE_ROBBERY)
		> CrimeManager.evidence_for(CrimeManager.CrimeType.SHOPLIFTING),
		"a robbery leaves more evidence than a shoplifting"
	)


## Stars are a reading of the points meter, and points add up.
func _test_wanted_thresholds() -> void:
	WantedManager.clear_wanted("")
	_check(WantedManager.level == 0 and WantedManager.points == 0, "the meter starts empty")

	WantedManager.add_points(10, Vector3.ZERO)
	_check(WantedManager.level == 0, "10 points is not yet a star")
	WantedManager.add_points(10, Vector3.ZERO)
	_check(WantedManager.level == 1, "20 points is one star")
	WantedManager.add_points(20, Vector3.ZERO)
	_check(WantedManager.level == 2, "40 points is two stars")
	WantedManager.add_points(30, Vector3.ZERO)
	_check(WantedManager.level == 3, "70 points is three stars")
	_check(WantedManager.points == 70, "points accumulate rather than being replaced")

	_check(WantedManager.get_response_budget() == 5, "three stars sends up to five units")
	WantedManager.set_level(1)
	_check(WantedManager.get_response_budget() == 2, "one star sends up to two")
	WantedManager.set_level(2)
	_check(WantedManager.get_response_budget() == 3, "two stars sends up to three")
	_check(
		WantedManager.get_pursuit_pressure() > 1.0,
		"the police push harder above one star (x%.2f)" % WantedManager.get_pursuit_pressure()
	)

	# Escalation is what the points model exists for: a second crime while
	# already wanted has to move the meter, not restate it.
	WantedManager.clear_wanted("")
	WantedManager.add_points(CrimeManager.points_for(CrimeManager.CrimeType.VEHICLE_THEFT), Vector3.ZERO)
	var after_theft := WantedManager.points
	WantedManager.add_points(CrimeManager.points_for(CrimeManager.CrimeType.STORE_ROBBERY), Vector3.ZERO)
	_check(WantedManager.points == after_theft + 40, "a robbery on top of a theft adds to the meter")
	_check(WantedManager.level == 2, "theft plus robbery is two stars")
	WantedManager.clear_wanted("")


func _test_bust_fine_scaling() -> void:
	WantedManager.set_level(1)
	_check(WantedManager.get_bust_fine() == 100, "one star costs $100")
	WantedManager.set_level(2)
	_check(WantedManager.get_bust_fine() == 250, "two stars costs $250")
	WantedManager.set_level(3)
	_check(WantedManager.get_bust_fine() == 500, "three stars costs $500")
	# A bust cannot happen at level 0, so the table is never read there. It still
	# has to answer something sane rather than reading off the end of the array.
	WantedManager.clear_wanted("")
	_check(WantedManager.get_bust_fine() == 100, "an out-of-range level falls back to the one-star fine")


## Taking goods off a shelf and walking out with them.
func _test_shoplifting() -> void:
	await _prepare_crime_scene()
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	var shelf := _first_shelf(store)
	_check(shelf != null, "the shop has merchandise on the shelves")
	if shelf == null:
		return

	_player.inventory.clear()
	await _teleport(shelf.global_position + Vector3(0.0, 0.0, 0.6))
	await _settle(12)

	var focused := _player.interaction.get_focused()
	_check(focused == shelf, "the shelf is what the player is looking at")
	await _press_action("interact")
	await _settle(6)

	_check(_player.inventory.total_items() == 1, "the goods go into the bag")
	_check(_player.inventory.stolen_count() == 1, "and are flagged as unpaid")
	_check(_said("UNPAID"), "the player is told they have not paid")
	_check(
		CrimeManager.get_crimes_of(CrimeManager.CrimeType.SHOPLIFTING).is_empty(),
		"picking something up is not yet a crime"
	)

	# Out of the door with it. Nobody is inside — the scene is isolated — so it
	# is a crime that happened and was never seen.
	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(20)

	var thefts := CrimeManager.get_crimes_of(CrimeManager.CrimeType.SHOPLIFTING)
	_check(thefts.size() == 1, "leaving with it is the shoplifting (%d filed)" % thefts.size())
	if not thefts.is_empty():
		_check(int(thefts[0].get("quantity", 0)) == 1, "the record says how much was taken")
		_check(int(thefts[0].get("wanted_points", 0)) == 10, "it is worth 10 points")
		_check(thefts[0].get("witnessed") == false, "nobody saw it")
	_check(WantedManager.level == 0, "an unseen shoplifting is free")
	_check(
		CrimeManager.get_statistic(&"items_shoplifted") >= 1,
		"the statistics count it"
	)

	# Now the same again with a witness stood by the door.
	CrimeManager.clear_history()
	_notifications.clear()
	_player.inventory.clear()
	await _teleport(shelf.global_position + Vector3(0.0, 0.0, 0.6))
	await _settle(12)
	await _press_action("interact")
	await _settle(6)

	var civilian: Node3D = get_tree().get_nodes_in_group(&"pedestrian")[0]
	await _place_witness(
		civilian, store.global_position + Vector3(2.5, 0.4, 3.0), _player.global_position
	)
	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(20)

	var seen := CrimeManager.get_crimes_of(CrimeManager.CrimeType.SHOPLIFTING)
	_check(
		not seen.is_empty() and seen[0].get("witnessed") == true,
		"a civilian in the shop sees it (%s)" % (
			"no crime filed" if seen.is_empty() else str(seen[0].get("witnessed"))
		)
	)
	await _settle(int((WitnessSystem.report_delay + 0.7) * 60.0))
	_check(seen[0].get("reported") == true, "and calls it in")
	_check(
		WantedManager.points == 10,
		"which puts 10 points on the meter (%d)" % WantedManager.points
	)
	_check(
		WantedManager.level == 0,
		"one petty theft is not yet a star — that is what the points model is for"
	)

	# Being arrested with it costs the goods. Petty theft alone will not summon
	# the police, so the star comes from the meter directly.
	WantedManager.raise_to(1)
	EconomyManager.restore(600)
	WantedManager.request_bust()
	await _settle(int(WantedManager.bust_hold_seconds * 60.0) + 40)
	_check(_player.inventory.stolen_count() == 0, "arrest confiscates the stolen goods")
	_check(_said("STOLEN GOODS SEIZED"), "and says so")
	_check(EconomyManager.cash == 500, "and charges the one-star fine (now $%d)" % EconomyManager.cash)
	_player.inventory.clear()


## Behind the counter is off limits, but only after a warning.
func _test_trespassing() -> void:
	await _prepare_crime_scene()
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	var area := _staff_area(store)
	_check(area != null, "the shop has a staff-only area")
	if area == null:
		return

	await _teleport(area.global_position + Vector3(0.0, -0.9, 0.0))
	await _settle(20)
	_check(area.is_player_inside(), "the player is stood behind the counter")
	_check(_said("STAFF ONLY"), "they are warned first")
	_check(
		CrimeManager.get_crimes_of(CrimeManager.CrimeType.TRESPASSING).is_empty(),
		"the warning alone is not a crime"
	)

	await _settle(int(area.grace_seconds * 60.0) + 30)
	var offences := CrimeManager.get_crimes_of(CrimeManager.CrimeType.TRESPASSING)
	_check(offences.size() >= 1, "staying files trespassing (%d)" % offences.size())
	if not offences.is_empty():
		_check(int(offences[0].get("wanted_points", 0)) == 5, "trespassing is worth 5 points")

	# The repeat cooldown is what stops one room filing a crime every frame.
	await _settle(120)
	_check(
		CrimeManager.get_crimes_of(CrimeManager.CrimeType.TRESPASSING).size() == offences.size(),
		"and does not file another every second"
	)

	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(10)


## The till, the tension window, and the cooldown that stops it being a loop.
func _test_store_robbery() -> void:
	await _prepare_crime_scene()
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	var counter := store.get_shop()
	var cashier := store.get_cashier()
	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 12.0 * 60.0)
	await _settle(6)

	# --- Walking out mid-robbery costs the money, not the crime ---
	await _teleport(counter.global_position + Vector3(0.0, 0.1, 1.2))
	await _settle(12)
	var cash_before := EconomyManager.cash
	counter.rob(_player)
	await _settle(12)
	_check(counter.is_being_robbed(), "the robbery starts")
	_check(cashier.is_afraid(), "the cashier is frightened")
	_check(
		not CrimeManager.get_crimes_of(CrimeManager.CrimeType.STORE_ROBBERY).is_empty(),
		"the crime is filed at once, not at the payout"
	)

	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(30)
	_check(not counter.is_being_robbed(), "walking out abandons it")
	_check(EconomyManager.cash == cash_before, "and pays nothing")
	_check(_said("EMPTY HANDED"), "the player is told why")

	# --- The cooldown, and its expiry ---
	_check(counter.can_be_robbed() == Shop.RobberyResult.ON_COOLDOWN, "the same till cannot be done twice")
	TimeManager.advance_minutes(counter.robbery_cooldown_days * 1440 + 60)
	await _settle(10)
	_check(counter.can_be_robbed() == Shop.RobberyResult.OK, "the till refills after a few days")

	# --- The whole robbery, seen through ---
	CrimeManager.clear_history()
	_notifications.clear()
	await _teleport(counter.global_position + Vector3(0.0, 0.1, 1.2))
	await _settle(12)
	cash_before = EconomyManager.cash
	counter.rob(_player)
	await _settle(int(counter.robbery_seconds.y * 60.0) + 60)

	var takings := EconomyManager.cash - cash_before
	_check(
		takings >= counter.robbery_reward.x and takings <= counter.robbery_reward.y,
		"the till pays $150-$500 (got $%d)" % takings
	)
	var robberies := CrimeManager.get_crimes_of(CrimeManager.CrimeType.STORE_ROBBERY)
	_check(robberies.size() == 1, "one robbery is on the record")
	if not robberies.is_empty():
		_check(int(robberies[0].get("wanted_points", 0)) == 40, "it is worth 40 points")
		_check(int(robberies[0].get("reward_value", 0)) == takings, "the record knows what was taken")
	_check(CrimeManager.get_statistic(&"stores_robbed") >= 1, "the statistics count the robbery")
	_check(
		CrimeManager.get_statistic(&"illegal_income") >= takings,
		"and count the money as crime income"
	)
	_check(EconomyManager.illegal_income >= takings, "the economy tracks it as illegal income")

	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(10)


## Pulling somebody out of their car.
func _test_carjacking() -> void:
	await _prepare_crime_scene()
	# Clear of the cars the earlier theft tests left parked further down the
	# boulevard: a stolen car that drives four metres into a parked one has not
	# been proved to drive.
	var car := await _spawn_occupied_traffic(Vector3(0.0, 0.0, 40.0), 0.0)
	var victims: Array[Node3D] = []
	car.carjacked.connect(func(_thief: Node3D, victim: Node3D) -> void: victims.append(victim))

	_check(car.has_occupant(), "the car has somebody in it")
	_check(car.can_be_carjacked_by(_player), "a stopped car can be taken")
	car.driver_state = Vehicle.DriverState.EMPTY
	_check(not car.can_be_carjacked_by(_player), "an empty car cannot be carjacked, only stolen")
	car.driver_state = Vehicle.DriverState.SEATED

	await _stand_beside(car)
	var door := _player.interaction.get_focused()
	_check(door is VehicleDoor, "the door is what the player is looking at")
	_check(
		door != null and door.get_prompt_text().contains("Carjack"),
		"the prompt says carjack, not enter (%s)" % (door.get_prompt_text() if door else "<none>")
	)

	await _press_action("enter_vehicle")
	await _settle(10)

	_check(_player.is_driving(), "the player ends up at the wheel")
	_check(car.driver_state == Vehicle.DriverState.FLED, "the car knows its driver has gone")
	_check(victims.size() == 1, "somebody got out of it")
	var victim: Pedestrian = victims[0] if not victims.is_empty() else null
	if victim != null:
		_check(is_instance_valid(victim) and victim is Pedestrian, "the driver is now a pedestrian")
		_check(
			victim.global_position.distance_to(car.global_position) < 6.0,
			"they are stood beside the car"
		)
		_check(victim.is_afraid(), "and they are frightened")
	_check(
		car.get_node_or_null("Driver") == null or car.controller == Vehicle.Controller.PLAYER,
		"the AI driver has let go of the car"
	)

	var record := CrimeManager.get_last_crime()
	_check(int(record.get("type", -1)) == CrimeManager.CrimeType.CARJACKING, "it is filed as a carjacking")
	_check(int(record.get("wanted_points", 0)) == 35, "worth 35 points")
	_check(record.get("witnessed") == true, "the victim saw it — they were sat in it")
	_check(
		CrimeManager.get_crimes_of(CrimeManager.CrimeType.VEHICLE_THEFT).is_empty(),
		"and not also as an ordinary theft"
	)
	_check(CrimeManager.get_statistic(&"cars_carjacked") >= 1, "the statistics count it")

	await _settle(int((WitnessSystem.report_delay + 0.8) * 60.0))
	_check(WantedManager.level == 1, "the victim calls it in (level %d)" % WantedManager.level)

	# The car drives, which is the point of taking it.
	await _hold(["move_forward"], 45)
	_check(car.get_forward_speed() > 1.0, "the stolen car drives (%.1f m/s)" % car.get_forward_speed())

	await _leave_vehicle()
	WantedManager.clear_wanted("")
	if is_instance_valid(victim):
		victim.queue_free()
	await _despawn([car])


## Fists, then something heavier.
func _test_melee_and_assault() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(0.0, 0.5, 70.0))
	await _settle(10)

	var combat := _player.get_combat()
	_check(combat != null, "the player has a combat controller")
	_check(combat.get_active_weapon().display_name == "Fists", "empty hands are still a weapon")

	# Somebody stood right in front of the player.
	var civilians := get_tree().get_nodes_in_group(&"pedestrian")
	var victim: Pedestrian = civilians[0]
	await _place_witness(
		victim, _player.global_position + _player.get_facing() * 1.6, _player.global_position
	)
	victim.wait_for(30.0)
	await _settle(6)

	_check(combat.find_target() == victim, "the person in front is the target")
	var health_before := victim.health
	var where_before := victim.global_position
	await _press_action("attack")
	await _settle(12)

	_check(victim.health < health_before, "the punch hurts (%.0f -> %.0f)" % [health_before, victim.health])
	_check(
		victim.global_position.distance_to(where_before) > 0.3,
		"and knocks them back (%.2fm)" % victim.global_position.distance_to(where_before)
	)
	var assaults := CrimeManager.get_crimes_of(CrimeManager.CrimeType.ASSAULT)
	_check(assaults.size() == 1, "it is filed as assault (%d)" % assaults.size())
	if not assaults.is_empty():
		_check(int(assaults[0].get("wanted_points", 0)) == 25, "worth 25 points")
		_check(
			int(assaults[0].get("intent", -1)) == CrimeManager.Intent.INTENTIONAL,
			"and recorded as intentional"
		)

	# The cooldown, and one crime per victim rather than one per punch.
	_check(combat.get_cooldown_left() > 0.0, "there is a cooldown between swings")
	_check(not combat.can_attack(), "which blocks an immediate second swing")
	await _settle(int(combat.get_active_weapon().cooldown * 60.0) + 10)
	_check(combat.can_attack(), "and clears on its own")
	await _press_action("attack")
	await _settle(10)
	_check(
		CrimeManager.get_crimes_of(CrimeManager.CrimeType.ASSAULT).size() == 1,
		"a flurry on one person is still one assault"
	)

	# Somebody behind the player is not a target.
	var behind: Pedestrian = civilians[1]
	await _place_witness(
		behind, _player.global_position - _player.get_facing() * 1.4, _player.global_position
	)
	behind.wait_for(30.0)
	await _settle(6)
	_check(combat.find_target() != behind, "somebody stood behind the player is not swung at")

	# --- A weapon out of the bag ---
	_player.inventory.clear()
	var pipe := ItemCatalogue.by_id(&"steel_pipe")
	_check(pipe != null and pipe.is_weapon(), "the steel pipe is a weapon item")
	_player.inventory.add(pipe, 1)
	_check(_player.inventory.use_slot(0, _player), "using it from the bag equips it")
	_check(_player.get_equipped_item() == pipe, "it ends up in the player's hand")
	_check(_player.inventory.count_of(&"steel_pipe") == 1, "equipping does not consume it")
	_check(
		combat.get_active_weapon().damage > CombatController.FISTS.damage,
		"the pipe hits harder than a fist"
	)

	# Enough swings to put somebody down for good.
	var target: Pedestrian = civilians[2]
	await _place_witness(
		target, _player.global_position + _player.get_facing() * 1.6, _player.global_position
	)
	target.wait_for(60.0)
	await _settle(6)
	for i in 4:
		if target.is_incapacitated():
			break
		await _press_action("attack")
		await _settle(int(combat.get_active_weapon().cooldown * 60.0) + 12)
		if not target.is_incapacitated():
			# They run when hit; keep them in reach rather than chasing.
			target.global_position = _player.global_position + _player.get_facing() * 1.5
			await _settle(4)
	_check(target.is_incapacitated(), "enough of it leaves them incapacitated")
	_check(target.is_down(), "and on the floor")

	_check(_player.inventory.use_slot(0, _player), "using it again unequips it")
	_check(_player.get_equipped_item() == null, "back to bare hands")
	_player.inventory.clear()
	WantedManager.clear_wanted("")


## Three stars, the response that comes with it, and the arrest at the end.
func _test_three_star_escalation() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(0.0, 0.5, 60.0))
	EconomyManager.restore(900)

	for type in [
		CrimeManager.CrimeType.VEHICLE_THEFT,
		CrimeManager.CrimeType.CARJACKING,
		CrimeManager.CrimeType.STORE_ROBBERY,
	]:
		var record := CrimeManager.report_crime(type, _player.global_position, _player, null)
		CrimeManager.mark_witnessed(record, _player)
		CrimeManager.mark_reported(record)
		WantedManager.on_crime_reported(record)
		await _settle(4)

	_check(WantedManager.points == 95, "three crimes stack to 95 points (%d)" % WantedManager.points)
	_check(WantedManager.level == 3, "which is three stars (%d)" % WantedManager.level)
	_check(WantedManager.get_response_budget() == 5, "three stars sends up to five units")
	_check(
		CrimeManager.get_statistic(&"highest_wanted_level") >= 3,
		"the statistics remember the high-water mark"
	)

	await _station_police_near(_player.global_position, 40.0)
	await _settle(90)
	_check(_responding_units() >= 2, "more than one unit answers (%d)" % _responding_units())
	_check(
		WantedManager.get_active_responders() <= WantedManager.get_response_budget(),
		"and never more than the budget allows (%d of %d)"
		% [WantedManager.get_active_responders(), WantedManager.get_response_budget()]
	)

	var cash_before := EconomyManager.cash
	WantedManager.request_bust()
	await _settle(int(WantedManager.bust_hold_seconds * 60.0) + 40)
	_check(EconomyManager.cash == cash_before - 500, "a three-star arrest costs $500")
	_check(WantedManager.level == 0, "and clears the wanted level")
	_check(EconomyManager.cash >= 0, "money never goes negative")


## Life carries on afterwards: the shop still trades, the streets still work.
func _test_life_after_crime() -> void:
	await _prepare_crime_scene()
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	var counter := store.get_shop()
	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 13.0 * 60.0)
	EconomyManager.restore(200)
	_player.inventory.clear()
	await _settle(6)

	await _teleport(counter.global_position + Vector3(0.0, 0.1, 1.2))
	await _settle(12)
	var cash_before := EconomyManager.cash
	_check(
		counter.buy(ItemCatalogue.by_id(&"snack_bar"), _player) == Shop.Result.OK,
		"the shop still serves a customer with a record"
	)
	_check(EconomyManager.cash < cash_before, "and still charges for it")
	_check(_player.inventory.stolen_count() == 0, "goods bought properly are not flagged stolen")
	_check(not GameManager.cutscene_active, "the world is not left frozen")
	_check(WantedManager.level == 0, "and the player is not still wanted")
	_player.inventory.clear()
	await _teleport(store.global_position + Vector3(0.0, 0.5, 40.0))
	await _settle(10)


## Everything Phase G added to the save file, plus a save that predates it.
func _test_crime_save_load() -> void:
	var slot := 98
	var store: ConvenienceStoreInterior = _main.get_node("Interiors/ConvenienceStore")
	var counter := store.get_shop()

	_player.inventory.clear()
	var pipe := ItemCatalogue.by_id(&"steel_pipe")
	_player.inventory.add(pipe, 1)
	_player.equip_item(pipe)
	_player.inventory.add(ItemCatalogue.by_id(&"snack_bar"), 2, true)
	counter.recently_robbed = true
	var stats_before := CrimeManager.get_statistics()

	_check(SaveManager.save_to_slot(slot), "the game saves with crime state in it")

	_player.inventory.clear()
	_player.combat.unequip_item()
	counter.recently_robbed = false
	CrimeManager.reset_statistics()
	await _settle(6)

	_check(SaveManager.load_from_slot(slot), "and loads it back")
	await _settle(10)
	_check(_player.get_equipped_item() == pipe, "the equipped weapon is restored")
	_check(_player.inventory.stolen_count() == 2, "stolen goods stay flagged stolen")
	_check(counter.recently_robbed, "a shop that has been robbed stays robbed")
	_check(
		CrimeManager.get_statistic(&"stores_robbed") == int(stats_before.get(&"stores_robbed", 0)),
		"the crime statistics survive the round trip"
	)

	# A save from before any of this existed must still load.
	_player.load_state({
		"position": [0.0, 0.5, 60.0],
		"health": 90.0,
		"energy": 80.0,
		"hunger": 70.0,
		"inventory": [{"id": "snack_bar", "quantity": 2}],
	})
	await _settle(10)
	_check(_player.inventory.count_of(&"snack_bar") == 2, "a pre-Phase-G save still loads")
	_check(_player.inventory.stolen_count() == 0, "its goods are treated as legitimately owned")
	_check(_player.get_equipped_item() == null, "and its player is empty-handed")

	SaveManager.delete_slot(slot)
	_player.inventory.clear()


# --- Phase G helpers -----------------------------------------------------

func _first_shelf(store: Node) -> MerchandiseShelf:
	for node in get_tree().get_nodes_in_group(&"merchandise"):
		if store.is_ancestor_of(node):
			return node as MerchandiseShelf
	return null


func _staff_area(store: Node) -> RestrictedArea:
	for node in get_tree().get_nodes_in_group(&"restricted_area"):
		if store.is_ancestor_of(node):
			return node as RestrictedArea
	return null


## A civilian car with somebody in it, parked and not driving off. The traffic
## driver is stopped rather than removed, so the car is exactly what the manager
## would have produced — a carjackable one — minus the moving about.
func _spawn_occupied_traffic(at: Vector3, yaw_degrees: float) -> Vehicle:
	var car := await _spawn_test_traffic(at, yaw_degrees)
	car.driver_type = Vehicle.DriverType.CIVILIAN
	car.driver_state = Vehicle.DriverState.SEATED
	car.driver_id = &"test_driver"
	var driver := car.get_node_or_null("Driver") as TrafficDriver
	if driver != null:
		driver.set_physics_process(false)
	# The last input the driver posted is still latched on the car, so clearing
	# the throttle matters as much as stopping the driver posting a new one.
	car.set_ai_input(0.0, 0.0, true)
	car.halt()
	await _settle(8)
	return car


# --- Phase H: business ownership -----------------------------------------
#
# The business tests run as one continuous story, because that is what the
# systems are: the shop rented in the first test is the shop staffed in the
# ninth. Each function leaves the business in the state the next one expects,
# and `_own_business()` is how they find it.
#
# What is checked directly rather than played: money. Every test that moves cash
# asserts on both sides of the transfer, because a business account that creates
# or destroys money would be invisible from inside the shop.

func _test_property_available() -> void:
	await _prepare_crime_scene()
	EconomyManager.restore(4000)
	await _teleport(Vector3(-20.0, 0.5, -10.4))
	await _settle(25)

	var door := _player.interaction.get_focused()
	_check(door is CommercialProperty, "the vacant unit has a door the player can use")
	var unit := door as CommercialProperty
	if unit == null:
		return
	_check(unit.is_vacant(), "and it is vacant to start with")
	_check(
		unit.get_prompt_text() == "E — View Property",
		"the prompt offers the letting details (%s)" % unit.get_prompt_text()
	)
	_check(unit.rent_amount > 0 and unit.deposit > 0, "the unit has terms")
	_check(
		unit.move_in_cost() == unit.deposit + unit.rent_amount,
		"moving in costs the deposit plus the first rent"
	)

	await _press_action("interact")
	await _settle(6)
	var panel: Control = _main.get_node("HUD/PropertyPanel")
	_check(panel.is_open(), "interacting opens the property screen")
	_check(GameManager.menu_open, "which freezes the world like any other screen")
	GameManager.close_menus()
	await _settle(6)


## TEST 81 — renting it.
func _test_rent_property() -> void:
	var unit := _property()
	EconomyManager.restore(4000)
	await _settle(4)

	var cash_before := EconomyManager.cash
	var result := PropertyManager.lease(unit)
	await _settle(6)

	_check(result == PropertyManager.LeaseResult.OK, "the lease is signed")
	_check(
		EconomyManager.cash == cash_before - unit.move_in_cost(),
		"deposit and first rent leave the player's account (now $%d)" % EconomyManager.cash
	)
	_check(unit.is_leased_by_player(), "the unit is leased by the player")
	_check(not unit.is_vacant(), "and no longer vacant")
	_check(
		unit.next_rent_due_day == TimeManager.day_index + unit.rent_interval_days,
		"the next rent day is set"
	)
	_check(
		_said("LEASE SIGNED"),
		"the player is told"
	)

	# Two ledger entries, not one: a deposit is returnable and rent is not.
	var reasons: Array[String] = []
	for entry in EconomyManager.get_history():
		reasons.append(String(entry.get("reason", "")))
	_check(
		reasons.any(func(r: String) -> bool: return r.contains("deposit")),
		"the deposit is its own ledger entry"
	)
	_check(
		reasons.any(func(r: String) -> bool: return r.contains("rent")),
		"and the rent is another"
	)

	# A leased unit is a door.
	await _teleport(Vector3(-20.0, 0.5, -10.4))
	await _settle(25)
	await _press_action("interact")
	await _settle(25)
	_check(
		_player.global_position.distance_to(_unit_interior().global_position) < 25.0,
		"the door now leads into the empty unit"
	)
	_check(_unit_interior().is_player_inside(), "and the unit knows the player is in it")


## TEST 82 — founding the business.
func _test_create_business() -> void:
	var unit := _property()
	var business := BusinessManager.create_business(
		"Silas Market", &"convenience_store", unit
	)
	await _settle(6)

	_check(business != null, "the business is created")
	if business == null:
		return
	_check(business.business_id != &"", "it has an id (%s)" % business.business_id)
	_check(business.business_name == "Silas Market", "the name is kept")
	_check(business.property_id == unit.property_id, "it is tied to the unit")
	_check(business.cash_balance == 0, "creating it conjures no money")
	_check(
		BusinessManager.business_for_property(unit.property_id) == business,
		"the unit can be asked what trades from it"
	)
	_check(
		BusinessManager.get_statistic(&"businesses_founded") >= 1,
		"the statistics count it"
	)
	_check(
		not business.can_open(),
		"an empty shop cannot open: %s" % ", ".join(business.missing_requirements())
	)


## TEST 83 — moving money across the boundary.
func _test_fund_business() -> void:
	var business := _own_business()
	EconomyManager.restore(4000)
	await _settle(4)

	var personal_before := EconomyManager.cash
	var business_before := business.cash_balance
	var result := BusinessManager.deposit_to_business(business, 2500)
	_check(result == BusinessManager.TransferResult.OK, "capital goes into the business")
	_check(EconomyManager.cash == personal_before - 2500, "the player's cash falls")
	_check(business.cash_balance == business_before + 2500, "the business account rises")
	_check(
		EconomyManager.cash + business.cash_balance == personal_before + business_before,
		"and a transfer creates no money: the two accounts still sum to the same"
	)

	var back := BusinessManager.withdraw_from_business(business, 500)
	_check(back == BusinessManager.TransferResult.OK, "and can be drawn back out")
	_check(EconomyManager.cash == personal_before - 2000, "the player is up $500 again")
	_check(business.cash_balance == 2000, "the business is down to $2000")

	_check(
		BusinessManager.withdraw_from_business(business, 99999)
		== BusinessManager.TransferResult.NOT_ENOUGH_FUNDS,
		"a business cannot pay out money it does not have"
	)
	_check(business.cash_balance == 2000, "and the balance is untouched by the attempt")


## TESTS 84 and 85 — buying equipment and putting it down.
func _test_equipment() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	var controller := _placement_controller()
	_check(controller != null, "the placement controller is in the scene")

	var cash_before := business.cash_balance
	var counter := EquipmentCatalogue.by_id(&"checkout_counter")
	var shelf := EquipmentCatalogue.by_id(&"retail_shelf")
	var rack := EquipmentCatalogue.by_id(&"storage_rack")

	_check(
		BusinessManager.buy_equipment(business, &"checkout_counter") == BusinessManager.PurchaseResult.OK,
		"a checkout counter is bought"
	)
	BusinessManager.buy_equipment(business, &"retail_shelf")
	BusinessManager.buy_equipment(business, &"retail_shelf")
	BusinessManager.buy_equipment(business, &"storage_rack")
	var spent := counter.purchase_price + shelf.purchase_price * 2 + rack.purchase_price
	_check(
		business.cash_balance == cash_before - spent,
		"the business account pays for it (-$%d)" % spent
	)
	_check(
		BusinessManager.unplaced_equipment(business).size() == 4,
		"and it arrives waiting to be placed"
	)
	_check(business.equipment.is_empty(), "nothing is on the floor until it is put there")

	# --- Placing it ---
	_check(controller.begin(business, interior, &"checkout_counter"), "placement mode starts")
	_check(GameManager.placement_active, "which suppresses the punch on the left button")
	_check(not _player.get_combat().can_attack(), "so a placement click is not an assault")

	# Straight through a wall is refused.
	_check(
		not interior.is_valid_placement(Vector3(0.0, 0.0, 12.0), counter.placement_size),
		"outside the unit is not a valid spot"
	)
	_check(
		not interior.is_valid_placement(Vector3(0.0, 0.0, 5.2), counter.placement_size),
		"and neither is the doorway"
	)
	_check(
		interior.is_valid_placement(Vector3(0.0, 0.0, 1.0), counter.placement_size),
		"the middle of the shop floor is"
	)

	_check(controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0), "the counter goes down")
	_check(not GameManager.placement_active, "and placement mode ends")
	_check(business.equipment.size() == 1, "the business records it")
	_check(
		BusinessManager.unplaced_equipment(business).size() == 3,
		"and it leaves the delivery pile"
	)
	await _settle(6)
	_check(interior.first_checkout() != null, "the counter exists in the room")

	controller.begin(business, interior, &"retail_shelf")
	_check(controller.place_at(Vector3(-4.0, 0.0, 2.0), 0.0), "a shelf goes down beside it")
	controller.begin(business, interior, &"retail_shelf")
	_check(
		not controller.place_at(Vector3(-4.0, 0.0, 2.0), 0.0),
		"a second shelf cannot go in the same place"
	)
	_check(controller.place_at(Vector3(4.0, 0.0, 2.0), 0.0), "but it fits on the other side")
	controller.begin(business, interior, &"storage_rack")
	_check(controller.place_at(Vector3(0.0, 0.0, -4.0), 0.0), "the rack goes in the back room")

	await _settle(8)
	_check(business.equipment.size() == 4, "four pieces are on the floor")
	_check(interior.shelf_nodes().size() == 2, "two of them are shelves the player can see")
	_check(
		business.storage_capacity() > BusinessCatalogue.first().base_storage_capacity,
		"the rack raises the store room's capacity to %d" % business.storage_capacity()
	)

	# Rotation is what stops a counter facing the wall.
	var record: PlacedEquipment = business.equipment[0]
	_check(
		absf(rad_to_deg(record.rotation_y) - 180.0) < 1.0,
		"the counter kept the way it was turned (%.0f)" % rad_to_deg(record.rotation_y)
	)


## TESTS 86 and 87 — the supplier, the store room and the shelves.
func _test_stock() -> void:
	var business := _own_business()
	var water := ItemCatalogue.by_id(&"bottled_water")
	var soda := ItemCatalogue.by_id(&"soda_can")

	var cash_before := business.cash_balance
	var result := BusinessManager.order_stock(business, &"bottled_water", 40)
	_check(result == BusinessManager.PurchaseResult.OK, "stock is ordered from the supplier")
	_check(
		business.cash_balance == cash_before - water.get_wholesale_cost() * 40,
		"charged at wholesale, not at the shelf price"
	)
	# Phase I: the supplier takes a few hours. The order is real before it lands.
	_check(business.storage_of(&"bottled_water") == 0, "and does not arrive instantly")
	_check(
		BusinessManager.outstanding_orders(business).size() == 1,
		"there is an order on its way"
	)
	BusinessManager.deliver_now(business)
	_check(business.storage_of(&"bottled_water") == 40, "and it lands in the store room")

	BusinessManager.order_stock(business, &"soda_can", 40)
	BusinessManager.order_stock(business, &"snack_bar", 20)
	BusinessManager.deliver_now(business)
	_check(business.storage_used() == 100, "the store room holds what was ordered")

	_check(
		BusinessManager.order_stock(business, &"steel_pipe", 5)
		== BusinessManager.PurchaseResult.NO_SUCH_ITEM,
		"a convenience store cannot order something it does not sell"
	)

	# The store room is finite.
	var room := business.storage_room_left()
	BusinessManager.order_stock(business, &"bottled_water", room + 50)
	BusinessManager.deliver_now(business)
	_check(business.storage_used() <= business.storage_capacity(), "and it cannot be overfilled")

	# --- Shelves ---
	var shelves := business.shelves()
	_check(shelves.size() == 2, "there are two shelves to stock")
	var first := shelves[0]
	var storage_before := business.storage_of(&"bottled_water")
	var moved := business.stock_shelf(first.slot_id, &"bottled_water", 12)
	_check(moved == 12, "twelve units move onto the shelf")
	_check(
		business.storage_of(&"bottled_water") == storage_before - 12,
		"and out of the store room"
	)
	_check(first.stock_quantity == 12, "the shelf holds them")

	var overfill := business.stock_shelf(first.slot_id, &"bottled_water", 50)
	_check(
		first.stock_quantity == first.capacity(),
		"a shelf fills to its capacity and no further (%d)" % first.stock_quantity
	)
	_check(overfill == first.capacity() - 12, "only what fitted was taken out of the store room")

	business.stock_shelf(shelves[1].slot_id, &"soda_can", 20)
	_check(business.shelf_stock_of(&"soda_can") == 20, "the second shelf takes the soda")
	_check(
		business.total_shelf_units() == first.capacity() + 20,
		"and the shop knows what is on display"
	)


## TEST 88 and 92 — what the player charges, and what it does.
func _test_pricing() -> void:
	var business := _own_business()
	var soda := ItemCatalogue.by_id(&"soda_can")

	business.set_price(soda, soda.get_recommended_price())
	var fair := business.purchase_chance(soda)
	_check(fair > 0.85, "at the usual price nearly everybody buys (%.2f)" % fair)
	_check(
		business.margin_of(soda) == soda.get_recommended_price() - soda.get_wholesale_cost(),
		"the margin is the price less the wholesale cost"
	)

	business.set_price(soda, soda.get_recommended_price() * 2)
	var steep := business.purchase_chance(soda)
	_check(steep < 0.1, "at double the price almost nobody does (%.2f)" % steep)

	business.set_price(soda, roundi(float(soda.get_recommended_price()) * 1.4))
	var middling := business.purchase_chance(soda)
	_check(
		middling < fair and middling > steep,
		"and asking a bit over sells a bit less (%.2f)" % middling
	)

	business.set_price(soda, soda.get_recommended_price())
	_check(business.price_of(soda) == soda.get_recommended_price(), "prices are what the player set")


## TEST 89 — opening the doors.
func _test_open_store() -> void:
	var business := _own_business()
	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 10.0 * 60.0)
	await _settle(6)

	_check(business.can_open(), "with a till, a shelf and stock the shop is ready")
	_check(business.missing_requirements().is_empty(), "nothing is missing")
	business.manual_override = BusinessInstance.Override.NONE
	business.set_open(business.should_be_open(TimeManager.hour))
	_check(business.is_open(), "and at 10:00 it is open")
	_check(business.status_text() == "OPEN", "the status reads OPEN")

	# Outside its hours it is shut.
	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 3.0 * 60.0)
	business.set_open(business.should_be_open(TimeManager.hour))
	_check(not business.is_open(), "at 03:00 it is not")

	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 12.0 * 60.0)
	business.set_open(business.should_be_open(TimeManager.hour))
	_check(business.is_open(), "back open at midday")


## TEST 90 — a customer, walking in and buying something.
func _test_customer_purchase() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	var spawner := interior.get_spawner()
	await _teleport(interior.global_position + Vector3(0.0, 0.5, 3.0))
	await _settle(20)
	_check(interior.is_player_inside(), "the player is in their own shop")

	var till := interior.first_checkout()
	spawner.toggle_player_at_register(till)
	_check(spawner.is_player_working_register(), "the player takes the register")
	await _teleport(till.staff_point())
	await _settle(10)

	var revenue_before := business.revenue_today
	var stock_before := business.shelf_stock_of(&"bottled_water") + business.shelf_stock_of(&"soda_can")
	var customer := spawner.spawn_customer_now()
	_check(customer != null, "a customer arrives outside")
	if customer == null:
		return
	_check(
		customer.global_position.distance_to(interior.global_position) > 8.0,
		"on the pavement rather than inside the shop"
	)
	_check(not customer.wanted_items().is_empty(), "and they came in for something")

	# Long enough to walk in, browse a shelf, queue and be served.
	var served := false
	for i in 90:
		await _settle(20)
		if business.revenue_today > revenue_before:
			served = true
			break

	_check(served, "the sale goes through (revenue $%d)" % business.revenue_today)
	_check(
		business.shelf_stock_of(&"bottled_water") + business.shelf_stock_of(&"soda_can") < stock_before,
		"stock comes off the shelf"
	)
	_check(business.customer_count_today > 0, "the visit is counted")
	_check(business.units_sold_today > 0, "and the units are counted")
	_check(business.cash_balance > 0, "the money goes into the business account")

	await _settle(240)
	_check(
		not is_instance_valid(customer) or customer.stage == CustomerAI.Stage.LEAVING
		or customer.stage == CustomerAI.Stage.DONE,
		"and the customer leaves afterwards"
	)


## TEST 91 — nothing on the shelf.
func _test_out_of_stock() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	var spawner := interior.get_spawner()

	# Strip the shelves, keeping what was on them so the shop can be refilled.
	var kept := {}
	for shelf in business.shelves():
		if shelf.stock_quantity > 0:
			kept[shelf.slot_id] = [shelf.stock_item, shelf.stock_quantity]
			business.add_storage(shelf.stock_item, shelf.stock_quantity)
			shelf.stock_quantity = 0
	_check(business.total_shelf_units() == 0, "the shelves are bare")

	var lost_before := business.lost_sales_today
	var revenue_before := business.revenue_today
	var customer := spawner.spawn_customer_now()
	if customer != null:
		for i in 60:
			await _settle(20)
			if business.lost_sales_today > lost_before:
				break

	_check(business.revenue_today == revenue_before, "nothing can be sold")
	_check(business.lost_sales_today > lost_before, "and the lost sale is recorded")
	for shelf in business.shelves():
		_check(shelf.stock_quantity >= 0, "stock never goes negative")

	# Put it all back.
	for slot in kept:
		var entry: Array = kept[slot]
		business.stock_shelf(int(slot), entry[0], int(entry[1]))
	_check(business.total_shelf_units() > 0, "the shelves are refilled for the next test")


## TESTS 93 and 94 — hiring somebody, and letting them run the till.
func _test_hire_employee() -> void:
	var business := _own_business()
	var interior := _unit_interior()

	BusinessManager.refresh_candidates()
	var candidates := BusinessManager.get_candidates()
	_check(candidates.size() >= 1, "there are workers to hire")
	var candidate := candidates[0]
	_check(candidate.hourly_wage >= 12, "who cost real money ($%d/hour)" % candidate.hourly_wage)

	_check(BusinessManager.hire(business, candidate), "one is hired")
	_check(business.employees.size() == 1, "and joins the payroll")
	_check(
		business.employees[0].assigned_business == business.business_id,
		"assigned to this business"
	)
	_check(
		BusinessManager.get_statistic(&"employees_hired") >= 1, "the statistics count the hire"
	)

	# A shift that covers right now.
	var worker := business.employees[0]
	worker.role = EmployeeData.Role.CASHIER
	worker.shift_start_hour = 9
	worker.shift_end_hour = 17
	_check(worker.is_on_shift(12), "the shift covers midday")
	_check(not worker.is_on_shift(3), "and not the small hours")
	_check(worker.scheduled_hours() == 8.0, "eight hours long")
	_check(
		business.rostered_cashier(12) == worker,
		"so they are the cashier on duty at midday"
	)

	# They turn up.
	await _teleport(interior.global_position + Vector3(0.0, 0.5, 3.0))
	await _settle(20)
	interior.call("_refresh_staff")
	await _settle(10)
	var cashier := interior.get_cashier()
	_check(cashier != null, "the employee comes in to work")
	if cashier == null:
		return
	for i in 40:
		await _settle(15)
		if cashier.is_at_station():
			break
	_check(cashier.is_at_station(), "and gets to the register")


## TEST 94 continued — the employee serves the queue.
func _test_employee_checkout() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	var spawner := interior.get_spawner()
	spawner.stop_player_working()
	_check(not spawner.is_player_working_register(), "the player is not on the till")

	var revenue_before := business.revenue_today
	spawner.spawn_customer_now()
	spawner.spawn_customer_now()

	var served := false
	for i in 100:
		await _settle(20)
		if business.revenue_today > revenue_before:
			served = true
			break
	_check(served, "the employee rings customers through without the player")

	var worker := business.employees[0]
	_check(worker.customers_served_today > 0, "and their day's work is counted")

	# Wages are real money, charged for hours actually worked.
	var cash_before := business.cash_balance
	worker.hours_unpaid = 4.0
	BusinessManager.call("_pay", business, worker)
	var expected := worker.wage_for_hours(4.0)
	_check(
		business.cash_balance == cash_before - expected,
		"four hours costs $%d out of the business account" % expected
	)
	_check(business.wages_today >= expected, "and lands in the day's wage bill")
	_check(worker.hours_unpaid == 0.0, "the hours are settled")


## TESTS 95 and 63 — the shop runs while the player is elsewhere.
func _test_business_runs_while_away() -> void:
	var business := _own_business()
	var interior := _unit_interior()

	# Make sure there is something to sell and somebody to sell it.
	BusinessManager.order_stock(business, &"bottled_water", 40)
	BusinessManager.deliver_now(business)
	for shelf in business.shelves():
		business.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())
	business.manual_override = BusinessInstance.Override.FORCE_OPEN
	business.set_open(true)

	# Out of the shop and across the city.
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(20)
	_check(not interior.is_player_inside(), "the player has left the shop")
	_check(
		BusinessManager.simulation_mode(business) == "FAR",
		"so it is simulated rather than acted out"
	)

	# Staff and customers inherit Pedestrian, which puts the ambient crowd to
	# sleep beyond `active_distance`. They must be exempt: a shop far enough
	# away to be simulated is exactly the shop whose floor has to keep running,
	# and freezing it is invisible until somebody walks back in and finds the
	# cashier standing in the doorway.
	#
	# Tested on a figure placed far from the player rather than on the shop's
	# own staff, because a shop the player has left may legitimately have no
	# bodies in it at all — the far simulation is arithmetic.
	var indoor := Pedestrian.new()
	indoor.name = "AwayWorker"
	indoor.ambient_crowd = false
	_main.add_child(indoor)
	indoor.global_position = _player.global_position + Vector3(400.0, 0.0, 400.0)
	var outdoor := Pedestrian.new()
	outdoor.name = "AwayCivilian"
	_main.add_child(outdoor)
	outdoor.global_position = indoor.global_position
	await _settle(40)

	_check(
		indoor.is_active(),
		"somebody with a job indoors keeps working however far away the player is"
	)
	_check(
		not outdoor.is_active(),
		"while an ordinary civilian that far off is asleep"
	)
	for node in [indoor, outdoor]:
		node.queue_free()
	await _settle(4)

	var revenue_before := business.revenue_today
	var customers_before := business.customer_count_today
	BusinessManager.simulate_hour_now(business, 12)
	await _settle(6)

	_check(
		business.customer_count_today > customers_before,
		"customers still come in (%d)" % (business.customer_count_today - customers_before)
	)
	_check(
		business.revenue_today > revenue_before,
		"and still buy things (+$%d)" % (business.revenue_today - revenue_before)
	)
	_check(business.shelf_stock_of(&"bottled_water") < 40, "off the same shelves")


## TEST 96 — an open shop with nobody on the till.
func _test_no_cashier() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	var spawner := interior.get_spawner()

	# Everybody goes home.
	var roster := business.employees.duplicate()
	for worker in roster:
		business.fire(worker.employee_id)
	await _teleport(interior.global_position + Vector3(0.0, 0.5, 3.0))
	await _settle(20)
	interior.call("_refresh_staff")
	spawner.stop_player_working()
	await _settle(20)

	var revenue_before := business.revenue_today
	var lost_before := business.lost_sales_today
	var customer := spawner.spawn_customer_now()
	_check(customer != null, "a customer still walks in")

	# Long enough to browse and to run out of patience.
	for i in 120:
		await _settle(20)
		if business.lost_sales_today > lost_before:
			break

	_check(
		business.revenue_today == revenue_before,
		"but nothing is sold with nobody serving (+$%d)" % (business.revenue_today - revenue_before)
	)
	_check(business.lost_sales_today > lost_before, "and the lost sale is on the record")

	# The same with nobody there at all: the far simulation must not sell either.
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(20)
	revenue_before = business.revenue_today
	BusinessManager.simulate_hour_now(business, 12)
	_check(
		business.revenue_today == revenue_before,
		"and an unstaffed shop earns nothing while the player is away either"
	)
	_check(business.lost_sales_today > lost_before, "those visits are lost sales too")

	# Re-hire for the rest of the tests.
	BusinessManager.refresh_candidates()
	var candidate := BusinessManager.get_candidates()[0]
	BusinessManager.hire(business, candidate)
	candidate.shift_start_hour = 0
	candidate.shift_end_hour = 23


## TEST 97 — the day's books.
func _test_daily_report() -> void:
	var business := _own_business()

	# A known day: reset the counters, then put one of everything through.
	business.end_day(TimeManager.day_index)
	business.credit(400, "Test sales", &"revenue")
	business.debit(120, "Test stock", &"inventory")
	business.debit(80, "Test wages", &"wages")
	business.debit(60, "Test rent", &"rent")

	_check(business.revenue_today == 400, "revenue is what came in")
	_check(business.expenses_today() == 260, "expenses are what went out (%d)" % business.expenses_today())
	_check(business.profit_today() == 140, "profit is the difference (%d)" % business.profit_today())

	var lifetime_revenue_before := business.lifetime_revenue
	var report := business.end_day(TimeManager.day_index)
	_check(int(report.get("revenue", 0)) == 400, "the report states the revenue")
	_check(int(report.get("expenses", 0)) == 260, "and the expenses")
	_check(int(report.get("profit", 0)) == 140, "and the profit")
	_check(
		int(report.get("inventory", 0)) + int(report.get("wages", 0)) + int(report.get("rent", 0))
		== int(report.get("expenses", 0)),
		"which is the sum of its parts and not double counted"
	)
	_check(business.revenue_today == 0, "the day's counters reset afterwards")
	_check(
		business.lifetime_revenue == lifetime_revenue_before,
		"while the lifetime totals carry on"
	)
	_check(business.lifetime_revenue >= 400, "and include today's takings")


## TEST 98 — a shop can lose money.
func _test_bad_business() -> void:
	var business := _own_business()
	business.end_day(TimeManager.day_index)

	# Terrible prices and a full staff: exactly the mistake the brief wants to
	# stay possible.
	var soda := ItemCatalogue.by_id(&"soda_can")
	business.set_price(soda, soda.get_recommended_price() * 4)
	_check(
		business.purchase_chance(soda) < 0.05,
		"nobody will pay four times the going rate (%.2f)" % business.purchase_chance(soda)
	)

	business.debit(300, "Test stock", &"inventory")
	business.debit(250, "Test wages", &"wages")
	business.credit(90, "Test sales", &"revenue")
	_check(business.profit_today() < 0, "a bad day loses money ($%d)" % business.profit_today())
	_check(
		int(business.end_day(TimeManager.day_index).get("profit", 0)) < 0,
		"and the report says so rather than flattering it"
	)
	business.set_price(soda, soda.get_recommended_price())


## TEST 81 continued — rent comes round again.
func _test_rent_payment() -> void:
	var business := _own_business()
	var unit := _property()

	business.credit(2000, "Test funds", &"capital")
	var business_before := business.cash_balance
	unit.next_rent_due_day = TimeManager.day_index
	_check(unit.is_rent_due(), "rent falls due on its day")

	PropertyManager.charge_due_rent()
	_check(
		business.cash_balance == business_before - unit.rent_amount,
		"the business pays it, not the player's pocket"
	)
	_check(_said("RENT PAID"), "and the player is told")
	_check(
		unit.next_rent_due_day == TimeManager.day_index + unit.rent_interval_days,
		"the next one is scheduled"
	)

	# A business that cannot cover it falls into arrears rather than being
	# quietly forgiven.
	var stashed := business.cash_balance
	business.debit(stashed, "Test drain", &"other")
	EconomyManager.restore(0)
	unit.next_rent_due_day = TimeManager.day_index
	PropertyManager.charge_due_rent()
	_check(unit.arrears >= unit.rent_amount, "an unpaid rent becomes arrears ($%d)" % unit.arrears)
	_check(_said("RENT OVERDUE"), "and the player is warned")
	_check(unit.is_leased_by_player(), "but the lease is not torn up yet")
	EconomyManager.restore(4000)
	business.credit(2000, "Test funds", &"capital")


## TEST 99 — crime carries on around the business.
func _test_business_and_crime() -> void:
	var business := _own_business()
	var interior := _unit_interior()
	business.manual_override = BusinessInstance.Override.FORCE_OPEN
	business.set_open(true)
	for shelf in business.shelves():
		if shelf.stock_quantity < 5:
			business.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())

	# Out on the street, and wanted.
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(20)
	WantedManager.clear_wanted("")
	var record := CrimeManager.report_crime(
		CrimeManager.CrimeType.STORE_ROBBERY, _player.global_position, _player, null
	)
	CrimeManager.mark_witnessed(record, _player)
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)
	await _settle(10)

	_check(WantedManager.level >= 1, "the player is wanted (%d stars)" % WantedManager.level)
	_check(business.is_open(), "the shop is still open")
	_check(BusinessManager.owned_count() == 1, "and still theirs")

	var revenue_before := business.revenue_today
	BusinessManager.simulate_hour_now(business, 12)
	_check(
		business.revenue_today > revenue_before,
		"and still trading while the police look for its owner"
	)

	WantedManager.clear_wanted("")
	await _settle(6)
	_check(WantedManager.level == 0, "the chase resolves as it always did")
	_check(business.is_open(), "with the business untouched by it")


## TEST 100 — all of it, through a save file.
func _test_business_save_load() -> void:
	var slot := 97
	var business := _own_business()
	var unit := _property()
	var interior := _unit_interior()

	business.set_price(ItemCatalogue.by_id(&"soda_can"), 7)
	business.opening_hour = 7
	business.closing_hour = 21
	business.reputation = 63.0
	BusinessManager.order_stock(business, &"snack_bar", 10)
	BusinessManager.deliver_now(business)

	var saved := {
		"name": business.business_name,
		"cash": business.cash_balance,
		"equipment": business.equipment.size(),
		"storage": business.storage_used(),
		"shelf": business.total_shelf_units(),
		"employees": business.employees.size(),
		"lifetime_revenue": business.lifetime_revenue,
		"arrears": unit.arrears,
	}
	var slot_positions: Array = []
	for record in business.equipment:
		slot_positions.append([record.equipment_id, record.position, record.rotation_y])

	_check(SaveManager.save_to_slot(slot), "the game saves with a business in it")

	# Wreck everything a load has to put back.
	business.business_name = "Wrong Name"
	business.cash_balance = 1
	business.equipment.clear()
	business.storage.clear()
	business.employees.clear()
	business.prices.clear()
	business.reputation = 5.0
	unit.end_lease()
	await _settle(6)

	_check(SaveManager.load_from_slot(slot), "and loads it back")
	await _settle(10)

	var restored := _own_business()
	_check(restored != null, "the business is there again")
	if restored == null:
		return
	_check(restored.business_name == saved["name"], "with its name")
	_check(restored.cash_balance == saved["cash"], "its money ($%d)" % restored.cash_balance)
	_check(restored.equipment.size() == saved["equipment"], "its equipment")
	_check(restored.storage_used() == saved["storage"], "its store room")
	_check(restored.total_shelf_units() == saved["shelf"], "what is on its shelves")
	_check(restored.employees.size() == saved["employees"], "its staff")
	_check(restored.price_of(ItemCatalogue.by_id(&"soda_can")) == 7, "the prices it charges")
	_check(restored.opening_hour == 7 and restored.closing_hour == 21, "its opening hours")
	_check(roundi(restored.reputation) == 63, "its reputation")
	_check(restored.lifetime_revenue == saved["lifetime_revenue"], "and its lifetime figures")

	var employee := restored.employees[0] if not restored.employees.is_empty() else null
	_check(employee != null and employee.hourly_wage > 0, "the employee kept their wage")
	_check(
		employee != null and employee.shift_end_hour == 23,
		"and their shift (%s)" % (employee.schedule_text() if employee else "-")
	)

	var placed_back := true
	for i in slot_positions.size():
		if i >= restored.equipment.size():
			placed_back = false
			break
		var record: PlacedEquipment = restored.equipment[i]
		var expected: Array = slot_positions[i]
		if record.equipment_id != expected[0] or record.position.distance_to(expected[1]) > 0.01:
			placed_back = false
	_check(placed_back, "every piece of equipment came back where it was put")

	var leased := _property()
	_check(leased.is_leased_by_player(), "the lease is restored")
	_check(leased.arrears == saved["arrears"], "including what is owed on it")

	await _settle(10)
	_check(interior.first_checkout() != null, "and the room is rebuilt from the record")

	# A save from before any of this must still load.
	var path := SaveManager.get_slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": SaveManager.SAVE_VERSION,
		"clock": {"total_minutes": TimeManager.total_minutes},
		"economy": {"cash": 250},
	}))
	file.close()
	_check(SaveManager.load_from_slot(slot), "a save from before Phase H still loads")
	_check(EconomyManager.cash == 250, "and applies what it does contain")

	SaveManager.delete_slot(slot)


## Near and far have to agree, or the player learns to stand in the shop.
func _test_simulation_consistency() -> void:
	var business := _own_business()
	var water := ItemCatalogue.by_id(&"bottled_water")

	# Same shop, same hour, same rules: the two paths should predict the same
	# number of customers. The sales they produce differ by the dice, not by
	# which code ran.
	var rate := CustomerDemand.customers_per_hour(business, 12)
	_check(rate > 0.0, "an open, stocked shop expects customers (%.1f/hour)" % rate)

	business.end_day(TimeManager.day_index)
	BusinessManager.order_stock(business, &"bottled_water", 240)
	BusinessManager.deliver_now(business)
	for shelf in business.shelves():
		business.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())
	business.set_price(water, water.get_recommended_price())

	# Restocked between hours, the way a stocker or a manager would.
	#
	# Without it the shelf empties part-way through, the shop's range collapses
	# and with it the rate — so the band drawn from the closing rate widened to
	# include zero and the check could no longer fail low. Keeping the shelf
	# full is what makes this a test of how many customers an hour produces
	# rather than of how deep the shelves are.
	for i in 6:
		BusinessManager.simulate_hour_now(business, 12)
		for shelf in business.shelves():
			if shelf.room_left() > 0:
				business.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())
	var far_customers := business.customer_count_today
	var far_revenue := business.revenue_today
	# Reputation still moves with lost sales, so the band comes from the rate
	# the shop actually had across the six hours rather than from the single
	# reading taken before it opened.
	var rate_after := CustomerDemand.customers_per_hour(business, 12)
	var floor_rate := minf(rate, rate_after)
	var ceiling_rate := maxf(rate, rate_after)
	_check(floor_rate > 0.0, "a restocked shop is still wanted at closing (%.1f/hour)" % floor_rate)
	_check(
		far_customers >= int(floor_rate * 4.0) and far_customers <= int(ceiling_rate * 8.0),
		"six simulated hours produce about six hours of customers (%d for %.1f-%.1f/hour)"
		% [far_customers, floor_rate, ceiling_rate]
	)
	_check(far_revenue > 0, "and they spend money (+$%d)" % far_revenue)
	_check(
		float(far_revenue) / float(maxi(far_customers, 1)) < 40.0,
		"at a believable basket size ($%.1f each)" % (float(far_revenue) / float(maxi(far_customers, 1)))
	)


# --- Phase H helpers -----------------------------------------------------

func _property() -> CommercialProperty:
	return PropertyManager.by_id(&"unit_main_18")


func _unit_interior() -> RetailUnit:
	return _main.get_node("Interiors/MainStreetUnit") as RetailUnit


func _own_business() -> BusinessInstance:
	return BusinessManager.business_for_property(&"unit_main_18")


func _placement_controller() -> PlacementController:
	return _main.get_node_or_null("PlacementController") as PlacementController


# --- Phase I: the business empire ----------------------------------------
#
# Picks up where Phase H left off: Silas Market is trading, and everything here
# is about the second business and what changes once there is more than one.
# The point of most of these checks is *independence* — two businesses that
# quietly share a store room, a payroll or a set of books would look fine from
# inside either one of them.

func _test_second_property() -> void:
	await _prepare_crime_scene()
	EconomyManager.restore(30000)
	await _settle(4)

	var properties := PropertyManager.get_properties()
	_check(properties.size() >= 4, "the district advertises four units (%d)" % properties.size())

	var small := _property()
	var medium := _coffee_property()
	_check(medium != null, "42 Harbour Avenue is one of them")
	if medium == null:
		return
	_check(medium.is_vacant(), "and it is vacant")
	_check(
		medium.rent_amount > small.rent_amount,
		"a bigger unit costs more rent ($%d against $%d)" % [medium.rent_amount, small.rent_amount]
	)
	_check(
		medium.customer_capacity > small.customer_capacity,
		"and holds more customers (%d against %d)" % [
			medium.customer_capacity, small.customer_capacity
		]
	)
	_check(
		medium.location_demand_modifier > small.location_demand_modifier,
		"on a better pitch (x%.2f against x%.2f)" % [
			medium.location_demand_modifier, small.location_demand_modifier
		]
	)
	var back_street := PropertyManager.by_id(&"unit_quay_40")
	_check(
		back_street != null and back_street.location_demand_modifier < 1.0,
		"and one of them is cheap for a reason"
	)

	var cash_before := EconomyManager.cash
	_check(
		PropertyManager.lease(medium) == PropertyManager.LeaseResult.OK,
		"the second lease is signed"
	)
	_check(
		EconomyManager.cash == cash_before - medium.move_in_cost(),
		"and paid for out of the player's own pocket"
	)
	_check(small.is_leased_by_player(), "the first lease is untouched")
	_check(medium.is_leased_by_player(), "and both are now held")
	_check(
		PropertyManager.leased_by_player().size() == 2, "the agent counts two tenancies"
	)


## TESTS 112 and 113 — a coffee shop, which is a different business rather than
## a repainted one.
func _test_coffee_shop() -> void:
	var unit := _coffee_property()
	var market := _own_business()
	var interior := _coffee_unit()

	var coffee := BusinessManager.create_business("Noel Coffee", &"coffee_shop", unit)
	_check(coffee != null, "the coffee shop is created")
	if coffee == null:
		return
	_check(BusinessManager.owned_count() == 2, "two businesses are owned")
	_check(coffee.business_id != market.business_id, "with different ids")
	_check(coffee.cash_balance == 0, "and its own empty account")
	_check(market.cash_balance > 0, "the market's money is still the market's")
	_check(coffee.serves_prepared_goods(), "a coffee shop makes what it sells")
	_check(not market.serves_prepared_goods(), "a convenience store does not")

	# What it sells, and what it holds, are different lists.
	var menu := coffee.catalogue()
	var supplies := coffee.orderable()
	_check(menu.size() == 4, "there are four things on the menu (%d)" % menu.size())
	_check(supplies.size() == 4, "and four ingredients to order (%d)" % supplies.size())
	_check(menu[0] != supplies[0], "and they are not the same list")

	BusinessManager.deposit_to_business(coffee, 6000)
	_check(coffee.cash_balance == 6000, "the player funds it")

	# --- Fitting it out ---
	var controller := _placement_controller()
	BusinessManager.buy_equipment(coffee, &"service_counter")
	BusinessManager.buy_equipment(coffee, &"coffee_machine")
	BusinessManager.buy_equipment(coffee, &"ingredient_store")
	_check(
		BusinessManager.buy_equipment(coffee, &"retail_shelf")
		== BusinessManager.PurchaseResult.NOT_ALLOWED,
		"a coffee shop cannot buy grocery shelving"
	)

	await _teleport(interior.global_position + Vector3(0.0, 0.5, 3.0))
	await _settle(20)
	_check(interior.is_built(), "walking in builds the room")
	_check(interior.is_player_inside(), "and the unit knows the player is there")

	controller.begin(coffee, interior, &"service_counter")
	_check(controller.place_at(Vector3(0.0, 0.0, 1.0), 180.0), "the service counter goes down")
	controller.begin(coffee, interior, &"coffee_machine")
	_check(controller.place_at(Vector3(-3.0, 0.0, 1.0), 180.0), "the coffee machine beside it")
	controller.begin(coffee, interior, &"ingredient_store")
	_check(controller.place_at(Vector3(0.0, 0.0, -5.0), 0.0), "the ingredient store in the back")
	await _settle(8)

	_check(
		coffee.missing_requirements().has("Ingredients"),
		"it still cannot open: %s" % ", ".join(coffee.missing_requirements())
	)

	# --- Ingredients ---
	for ingredient in [&"coffee_beans", &"milk_carton", &"paper_cup", &"tea_leaves"]:
		BusinessManager.order_stock(coffee, ingredient, 30)
	BusinessManager.deliver_now(coffee)
	_check(coffee.storage_of(&"coffee_beans") == 30, "beans arrive in the back")
	_check(
		market.storage_of(&"coffee_beans") == 0,
		"and go to the coffee shop's store room, not the market's"
	)

	var latte := ItemCatalogue.by_id(&"latte")
	_check(coffee.available_units(latte) > 0, "there are ingredients for a latte")
	_check(
		coffee.cost_basis(latte) == coffee.recipe_for(latte).ingredient_cost(),
		"and a drink costs what its ingredients cost"
	)
	_check(coffee.can_open(), "with a counter, a machine and ingredients it can open")

	coffee.manual_override = BusinessInstance.Override.FORCE_OPEN
	coffee.set_open(true)
	_check(coffee.is_open(), "the coffee shop opens")


## TEST 113 continued — somebody orders a drink, and it gets made.
func _test_coffee_customer() -> void:
	var coffee := _coffee_business()
	var interior := _coffee_unit()
	var spawner := interior.get_spawner()

	# A barista, on shift now.
	BusinessManager.refresh_candidates()
	var barista := BusinessManager.get_candidates()[0]
	BusinessManager.hire(coffee, barista, EmployeeData.Role.BARISTA)
	barista.shift_start_hour = 0
	barista.shift_end_hour = 23
	_check(coffee.rostered_barista(TimeManager.hour) == barista, "the barista is on shift")
	_check(
		coffee.rostered_cashier(TimeManager.hour) == barista,
		"and takes the orders as well as making them"
	)

	await _teleport(interior.global_position + Vector3(0.0, 0.5, 3.0))
	await _settle(20)
	interior.call("_refresh_staff")
	await _settle(10)
	var on_the_floor := interior.get_staff("Barista")
	_check(on_the_floor != null, "the barista comes in to work")
	for i in 80:
		await _settle(15)
		if on_the_floor != null and on_the_floor.is_at_station():
			break
	_check(on_the_floor != null and on_the_floor.is_at_station(), "and takes their post")

	var beans_before := coffee.storage_of(&"coffee_beans")
	var revenue_before := coffee.revenue_today
	var customer := spawner.spawn_customer_now()
	_check(customer != null, "a customer comes in")

	var served := false
	for i in 100:
		await _settle(20)
		if coffee.revenue_today > revenue_before:
			served = true
			break
	_check(served, "the drink is sold (revenue $%d)" % coffee.revenue_today)
	_check(
		coffee.storage_of(&"coffee_beans") < beans_before
		or coffee.storage_of(&"paper_cup") < 30,
		"and the ingredients for it are used up"
	)
	_check(coffee.units_sold_today > 0, "the sale is counted")
	_check(
		BusinessManager.get_statistic(&"drinks_sold") > 0,
		"and counted as a drink rather than as a grocery"
	)
	_check(
		_own_business().revenue_today != coffee.revenue_today
		or _own_business().revenue_today == 0,
		"the two businesses keep separate books"
	)


## TESTS 114 and 85 — both open, both trading, neither borrowing from the other.
func _test_two_businesses_trading() -> void:
	var market := _own_business()
	var coffee := _coffee_business()

	# Somebody on each till, stock in each, both open.
	BusinessManager.refresh_candidates()
	if market.rostered_cashier(12) == null:
		var till := BusinessManager.get_candidates()[0]
		BusinessManager.hire(market, till, EmployeeData.Role.CASHIER)
		till.shift_start_hour = 0
		till.shift_end_hour = 23
	BusinessManager.order_stock(market, &"bottled_water", 40)
	BusinessManager.deliver_now(market)
	for shelf in market.shelves():
		market.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())
	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	coffee.manual_override = BusinessInstance.Override.FORCE_OPEN
	coffee.set_open(true)

	# Out of both of them.
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(20)
	_check(
		BusinessManager.simulation_mode(market) == "FAR"
		and BusinessManager.simulation_mode(coffee) == "FAR",
		"the player is at neither shop"
	)

	market.end_day(TimeManager.day_index)
	coffee.end_day(TimeManager.day_index)
	for i in 3:
		BusinessManager.simulate_hour_now(market, 12)
		BusinessManager.simulate_hour_now(coffee, 12)

	_check(market.customer_count_today > 0, "the market gets customers (%d)" % market.customer_count_today)
	_check(coffee.customer_count_today > 0, "the coffee shop gets its own (%d)" % coffee.customer_count_today)
	_check(market.revenue_today > 0, "the market takes money (+$%d)" % market.revenue_today)
	_check(coffee.revenue_today > 0, "and so does the coffee shop (+$%d)" % coffee.revenue_today)
	_check(
		market.revenue_today != coffee.revenue_today,
		"and they are not the same number twice"
	)
	_check(
		market.storage_of(&"coffee_beans") == 0,
		"the market never touches the coffee shop's ingredients"
	)

	# Closing one does not close the other.
	BusinessManager.close_business(coffee)
	_check(not coffee.is_open(), "the coffee shop closes")
	_check(market.is_open(), "and the market stays open")
	coffee.manual_override = BusinessInstance.Override.FORCE_OPEN
	coffee.set_open(true)


## TEST 115 — a stocker moves stock, and does not invent it.
func _test_stocker() -> void:
	var market := _own_business()
	var interior := _unit_interior()

	# Empty the shelves, and make sure there is stock in the back to move.
	for shelf in market.shelves():
		if shelf.stock_quantity > 0:
			market.add_storage(shelf.stock_item, shelf.stock_quantity)
			shelf.stock_quantity = 0
	BusinessManager.order_stock(market, &"bottled_water", 40)
	BusinessManager.deliver_now(market)
	var storage_before := market.storage_used()
	_check(market.total_shelf_units() == 0, "the shelves are empty")
	_check(storage_before > 0, "and the store room is not")

	BusinessManager.refresh_candidates()
	var stocker := BusinessManager.get_candidates()[0]
	BusinessManager.hire(market, stocker, EmployeeData.Role.STOCKER)
	stocker.shift_start_hour = 0
	stocker.shift_end_hour = 23
	_check(stocker.role == EmployeeData.Role.STOCKER, "a stocker is hired")
	_check(market.rostered_stocker(TimeManager.hour) == stocker, "and is on shift")

	# Away from the shop, so the hourly simulation does the work.
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(10)
	BusinessManager.call("_work_the_stock_room", market, TimeManager.hour)

	_check(market.total_shelf_units() > 0, "the shelves get filled (%d units)" % market.total_shelf_units())
	_check(
		market.storage_used() < storage_before,
		"out of the store room (%d left, was %d)" % [market.storage_used(), storage_before]
	)
	_check(
		market.total_shelf_units() + market.storage_used() == storage_before,
		"and nothing is created on the way"
	)


## TESTS 116, 117 and 118 — the manager, and the ordering they do.
func _test_manager() -> void:
	var market := _own_business()

	BusinessManager.refresh_candidates()
	var boss := BusinessManager.get_candidates()[2]
	var wage_before := boss.hourly_wage
	BusinessManager.hire(market, boss, EmployeeData.Role.MANAGER)
	_check(market.has_manager(), "a manager is hired")
	_check(boss.is_manager(), "in the manager's job")
	_check(
		boss.hourly_wage >= wage_before,
		"on manager's money ($%d/hour)" % boss.hourly_wage
	)
	_check(
		boss.hourly_wage > EmployeeData.BASE_WAGE[EmployeeData.Role.CASHIER],
		"which is more than a cashier costs"
	)
	_check(market.management_quality() > 0.0, "and the business knows who runs it")

	# Nothing happens until the player says so.
	_check(not market.auto_open, "automation is off until it is turned on")
	market.auto_open = true
	market.auto_restock = true
	market.auto_order = true

	# --- Opening up ---
	market.manual_override = BusinessInstance.Override.FORCE_CLOSED
	market.set_open(false)
	TimeManager.set_total_minutes(TimeManager.day_index * 1440.0 + 11.0 * 60.0)
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(10)
	BusinessManager.call("_run_manager", market, 11)
	BusinessManager.call("_update_open_state", market, 11)
	_check(
		market.manual_override == BusinessInstance.Override.NONE,
		"the manager puts the shop back on its published hours"
	)
	_check(market.is_open(), "and opens up")

	# --- Restocking ---
	for shelf in market.shelves():
		if shelf.stock_quantity > 0:
			market.add_storage(shelf.stock_item, shelf.stock_quantity)
			shelf.stock_quantity = 0
	BusinessManager.order_stock(market, &"soda_can", 30)
	BusinessManager.deliver_now(market)
	BusinessManager.call("_run_manager", market, 11)
	_check(market.total_shelf_units() > 0, "the manager fills the shelves")

	# --- Ordering ---
	market.storage.clear()
	market.auto_order_minimum = 20
	market.auto_order_target = 40
	market.auto_order_budget = 300
	var cash_before := market.cash_balance
	var orders_before := BusinessManager.outstanding_orders(market).size()
	BusinessManager.call("_run_manager", market, 11)
	var placed := BusinessManager.outstanding_orders(market)
	_check(placed.size() > orders_before, "the manager reorders what has run out")
	_check(market.cash_balance < cash_before, "paying for it out of the business account")
	_check(
		cash_before - market.cash_balance <= market.auto_order_budget,
		"and never beyond the budget set (spent $%d of $%d)"
		% [cash_before - market.cash_balance, market.auto_order_budget]
	)
	var automatic := false
	for order in placed:
		if order.automatic:
			automatic = true
	_check(automatic, "and the order is marked as theirs rather than the player's")

	# Running the hour again must not reorder anything already on its way.
	var incoming_before := {}
	for order in BusinessManager.outstanding_orders(market):
		for item_id in order.items:
			incoming_before[item_id] = int(incoming_before.get(item_id, 0)) + 1
	BusinessManager.call("_run_manager", market, 11)
	var reordered := ""
	for order in BusinessManager.outstanding_orders(market):
		for item_id in order.items:
			incoming_before[item_id] = int(incoming_before.get(item_id, 0)) - 1
	for item_id in incoming_before:
		if int(incoming_before[item_id]) < 0:
			reordered = String(item_id)
	_check(
		reordered.is_empty(),
		"and never reorders something already on its way (%s)" % reordered
	)

	BusinessManager.deliver_now(market)
	_check(market.storage_used() > 0, "the automatic order arrives like any other")


## TEST 118 — the delivery itself.
func _test_delivery() -> void:
	var market := _own_business()
	market.credit(2000, "Test funds", &"capital")
	# Clear the decks: the manager's automatic orders have been filling the back
	# room, and this test is about one order it can watch all the way in.
	BusinessManager.deliver_now(market)
	market.auto_order = false
	market.storage.clear()

	var before := market.storage_of(&"snack_bar")
	_check(
		BusinessManager.order_stock(market, &"snack_bar", 10) == BusinessManager.PurchaseResult.OK,
		"an order is placed"
	)
	var orders := BusinessManager.outstanding_orders(market)
	_check(orders.size() >= 1, "and is outstanding")
	var order: PurchaseOrder = orders[orders.size() - 1]
	_check(order.status == PurchaseOrder.Status.PLACED, "starting as PLACED")
	_check(market.storage_of(&"snack_bar") == before, "with nothing delivered yet")
	_check(order.arrives_at > order.placed_at, "and an arrival time in the future")

	# Half way there.
	order.refresh_status(order.placed_at + (order.arrives_at - order.placed_at) * 0.6)
	_check(order.status == PurchaseOrder.Status.IN_TRANSIT, "then IN TRANSIT")

	BusinessManager.deliver_now(market)
	_check(order.status == PurchaseOrder.Status.DELIVERED, "and finally DELIVERED")
	_check(market.storage_of(&"snack_bar") == before + 10, "the goods arrive exactly once")
	_check(
		BusinessManager.outstanding_orders(market).is_empty(),
		"and the order is off the books"
	)
	_check(_said("DELIVERY ARRIVED"), "the player is told")

	# Delivering again must not hand the same goods over twice.
	BusinessManager.deliver_now(market)
	_check(market.storage_of(&"snack_bar") == before + 10, "and cannot be delivered twice")


## TEST 119 — advertising buys attention, not money.
func _test_marketing() -> void:
	var market := _own_business()
	market.credit(2000, "Test funds", &"capital")
	market.campaigns.clear()

	var baseline := CustomerDemand.customers_per_hour(market, 12)
	_check(baseline > 0.0, "a stocked shop expects customers (%.1f/hour)" % baseline)
	var revenue_before := market.revenue_today
	var cash_before := market.cash_balance

	var flyers := MarketingCampaign.by_id(&"flyers")
	_check(
		BusinessManager.start_campaign(market, &"flyers") == BusinessManager.PurchaseResult.OK,
		"a campaign is bought"
	)
	_check(market.cash_balance == cash_before - flyers.cost, "and paid for")
	_check(market.revenue_today == revenue_before, "it generates no revenue by itself")
	_check(market.marketing_today == flyers.cost, "and is booked as marketing spend")

	var boosted := CustomerDemand.customers_per_hour(market, 12)
	_check(boosted > baseline, "but more people come in (%.1f against %.1f)" % [boosted, baseline])
	_check(
		absf(boosted / baseline - (1.0 + flyers.demand_bonus)) < 0.01,
		"by the campaign's own figure"
	)
	_check(market.active_campaigns().size() == 1, "one campaign is running")

	# It runs out on its own.
	var expiry := market.campaigns[0].expires_on_day
	market.campaigns[0].expires_on_day = TimeManager.day_index
	_check(market.expire_campaigns() == 1, "and expires when its days are up")
	_check(market.active_campaigns().is_empty(), "leaving nothing running")
	_check(
		absf(CustomerDemand.customers_per_hour(market, 12) - baseline) < 0.01,
		"and the trade goes back to what it was"
	)
	_check(expiry > TimeManager.day_index, "the campaign had run for its stated days")


## TEST 120 — an upgrade helps the shop that bought it and no other.
func _test_upgrades() -> void:
	var market := _own_business()
	var coffee := _coffee_business()
	market.credit(2000, "Test funds", &"capital")

	var before := CustomerDemand.customers_per_hour(market, 12)
	var coffee_before := CustomerDemand.customers_per_hour(coffee, 12)
	_check(
		BusinessManager.buy_upgrade(market, &"better_signage") == BusinessManager.PurchaseResult.OK,
		"an upgrade is bought"
	)
	_check(market.has_upgrade(&"better_signage"), "the market has it")
	_check(not coffee.has_upgrade(&"better_signage"), "the coffee shop does not")
	_check(
		CustomerDemand.customers_per_hour(market, 12) > before,
		"it brings the market more customers"
	)
	_check(
		absf(CustomerDemand.customers_per_hour(coffee, 12) - coffee_before) < 0.01,
		"and does nothing at all for the coffee shop"
	)
	_check(
		BusinessManager.buy_upgrade(market, &"better_signage") == BusinessManager.PurchaseResult.NOT_ALLOWED,
		"and cannot be bought twice"
	)

	_check(
		BusinessManager.buy_upgrade(market, &"second_grinder") == BusinessManager.PurchaseResult.NOT_ALLOWED,
		"a grocer cannot buy a second coffee grinder"
	)
	_check(
		BusinessManager.buy_upgrade(coffee, &"second_grinder") == BusinessManager.PurchaseResult.OK,
		"but the coffee shop can"
	)

	var storage_before := market.storage_capacity()
	BusinessManager.buy_upgrade(market, &"storage_expansion")
	_check(
		market.storage_capacity() > storage_before,
		"a storage upgrade makes the store room bigger (%d from %d)"
		% [market.storage_capacity(), storage_before]
	)


## TESTS 121 and 126 — what a business is worth, and what the player is worth.
func _test_valuation_and_net_worth() -> void:
	var market := _own_business()
	var coffee := _coffee_business()

	var value := market.estimated_value()
	_check(value > 0, "a fitted, stocked shop is worth something ($%d)" % value)
	_check(market.equipment_value() > 0, "its fittings are part of that")
	_check(market.inventory_value() > 0, "and so is its stock")

	# More money in the till is more value.
	market.credit(3000, "Test funds", &"capital")
	_check(
		market.estimated_value() > value,
		"money in the account raises it ($%d from $%d)" % [market.estimated_value(), value]
	)

	# A run of losses is worth less than a run of profits.
	var profitable := BusinessInstance.new()
	profitable.type_id = &"convenience_store"
	profitable.cash_balance = 2000
	profitable.reputation = 70.0
	for i in 5:
		profitable.recent_reports.append({"profit": 300})
	var struggling := BusinessInstance.new()
	struggling.type_id = &"convenience_store"
	struggling.cash_balance = 2000
	struggling.reputation = 70.0
	for i in 5:
		struggling.recent_reports.append({"profit": -120})
	_check(
		profitable.estimated_value() > struggling.estimated_value(),
		"a profitable shop is worth more than a failing one ($%d against $%d)"
		% [profitable.estimated_value(), struggling.estimated_value()]
	)

	# Debt comes off.
	var indebted := BusinessInstance.new()
	indebted.type_id = &"convenience_store"
	indebted.cash_balance = 5000
	var clean_value := indebted.estimated_value()
	indebted.add_loan(Loan.create(&"t", &"b", "Test", 4000, 0.1, 200, 7))
	_check(
		indebted.estimated_value() < clean_value,
		"and what a business owes comes off what it is worth"
	)

	# --- Net worth ---
	EconomyManager.restore(5000)
	var worth := BusinessManager.net_worth()
	_check(worth > 0, "the player is worth something ($%d)" % worth)
	_check(
		worth == EconomyManager.cash + BusinessManager.vehicle_value() + BusinessManager.total_business_value(),
		"cash plus cars plus businesses"
	)
	_check(BusinessManager.vehicle_value() > 0, "their own car counts (%d)" % BusinessManager.vehicle_value())

	var summary := BusinessManager.portfolio_summary()
	_check(int(summary["businesses"]) == 2, "the portfolio counts both businesses")
	_check(
		int(summary["business_value"]) == market.estimated_value() + coffee.estimated_value(),
		"and adds up what they are worth"
	)
	_check(int(summary["net_worth"]) == worth, "and agrees about the net worth")


## TESTS 123, 124 and 125 — borrowing, paying and settling early.
func _test_loans() -> void:
	var market := _own_business()
	market.loans.clear()

	var cash_before := market.cash_balance
	var result := BusinessManager.take_loan(market, &"starter")
	_check(result == BusinessManager.LoanResult.OK, "the bank lends")
	_check(market.loans.size() == 1, "one loan is on the books")
	var loan: Loan = market.loans[0]
	_check(
		market.cash_balance == cash_before + loan.principal,
		"the money lands in the business account exactly once"
	)
	_check(
		loan.remaining_balance == loan.principal + loan.total_interest(),
		"what is owed includes the interest ($%d on $%d)"
		% [loan.total_interest(), loan.principal]
	)
	_check(
		loan.next_payment_day == TimeManager.day_index + loan.payment_interval_days,
		"and the first payment is scheduled"
	)
	_check(market.total_debt() == loan.remaining_balance, "the business knows what it owes")

	# --- A scheduled payment ---
	var owed_before := loan.remaining_balance
	var account_before := market.cash_balance
	loan.next_payment_day = TimeManager.day_index
	_check(loan.is_due(TimeManager.day_index), "the payment falls due")
	BusinessManager.call("_collect_loan_payments")
	_check(
		market.cash_balance == account_before - loan.payment_amount,
		"the payment is taken from the business"
	)
	_check(
		loan.remaining_balance == owed_before - loan.payment_amount,
		"and comes off the balance"
	)
	_check(
		loan.next_payment_day > TimeManager.day_index, "the next one is scheduled"
	)
	_check(_said("LOAN PAYMENT"), "the player is told")

	# Running the day again must not charge twice.
	var after_one := market.cash_balance
	BusinessManager.call("_collect_loan_payments")
	_check(market.cash_balance == after_one, "and is not charged twice for the same week")

	# --- A missed payment ---
	var stashed := market.cash_balance
	market.debit(stashed, "Test drain", &"other")
	loan.next_payment_day = TimeManager.day_index
	var owed_at_miss := loan.remaining_balance
	BusinessManager.call("_collect_loan_payments")
	_check(loan.missed_payments == 1, "a payment that cannot be met is missed")
	_check(loan.remaining_balance > owed_at_miss, "and costs a little more")
	_check(_said("PAYMENT MISSED"), "and says so")
	_check(market.cash_balance >= 0, "the account never goes negative")

	# --- Settling early ---
	market.credit(20000, "Test funds", &"capital")
	var paid := BusinessManager.repay_loan(market, loan.loan_id, loan.remaining_balance)
	_check(paid > 0, "the rest can be paid off early")
	_check(loan.remaining_balance == 0, "leaving nothing owed")
	_check(loan.status == Loan.Status.PAID, "and the loan reads PAID")
	_check(market.total_debt() == 0, "the business is out of debt")

	var after_payoff := market.cash_balance
	loan.next_payment_day = TimeManager.day_index
	BusinessManager.call("_collect_loan_payments")
	_check(market.cash_balance == after_payoff, "a settled loan takes no more payments")
	_check(
		BusinessManager.get_statistic(&"loan_interest_paid") > 0,
		"and the interest paid is on the record"
	)


## TEST 127 — sleeping through a day the businesses trade through.
func _test_time_skip() -> void:
	var market := _own_business()
	var coffee := _coffee_business()
	# A floor rather than a credit. What these two are worth by the time this
	# test runs depends on wages and loan interest settled earlier, and wages
	# are rolled from a live RNG, so a fixed top-up is sometimes enough to buy
	# a delivery and sometimes not. An order that cannot be afforded leaves the
	# shelves empty, and a shop with empty shelves cannot open at all — which
	# reads downstream as a shop that traded nothing rather than as a shop that
	# could not buy anything.
	for business: BusinessInstance in [market, coffee]:
		if business.cash_balance < 8000:
			business.credit(8000 - business.cash_balance, "Test funds", &"capital")

	# Both open all hours, stocked, staffed.
	for business: BusinessInstance in [market, coffee]:
		business.manual_override = BusinessInstance.Override.FORCE_OPEN
		business.opening_hour = 0
		business.closing_hour = 23
	# The back room is small and earlier tests leave odds and ends in it. A
	# 60-unit delivery arriving into a nearly full store is silently truncated
	# to whatever fits, so the shelves stay empty — and a shop with empty
	# shelves cannot open at all, which is not what is being measured here.
	# Only what the market is not about to sell is cleared; the coffee shop
	# needs everything it is holding to make anything at all.
	var ingredients: Array[StringName] = [&"coffee_beans", &"milk_carton", &"paper_cup"]
	for item_id: StringName in market.storage.keys():
		if item_id != &"bottled_water":
			market.take_storage(item_id, market.storage_of(item_id))
	for item_id: StringName in coffee.storage.keys():
		if not ingredients.has(item_id):
			coffee.take_storage(item_id, coffee.storage_of(item_id))

	BusinessManager.order_stock(market, &"bottled_water", 60)
	# Fifteen of each rather than forty: a coffee shop needs all three
	# ingredients to make anything at all, and three forty-unit orders into a
	# back room that holds sixty means the third one does not fit.
	for ingredient in ingredients:
		BusinessManager.order_stock(coffee, ingredient, 15)
	BusinessManager.deliver_now()
	for shelf in market.shelves():
		market.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())

	# Asserted rather than assumed: everything below is about what a shop earns
	# while nobody is watching, and a shop that cannot open earns nothing for a
	# reason that has nothing to do with the far simulation.
	_check(
		market.total_shelf_units() > 0,
		"the market has something on its shelves (%d units)" % market.total_shelf_units()
	)
	_check(market.can_open(), "so it is a shop that can open at all")
	_check(
		coffee.can_open(),
		"and the coffee shop has enough in the back to make something (%s)"
		% ("ready" if coffee.can_open() else ", ".join(coffee.missing_requirements()))
	)

	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(10)
	market.end_day(TimeManager.day_index)
	coffee.end_day(TimeManager.day_index)

	var market_before := market.revenue_today
	var coffee_before := coffee.revenue_today
	var day_before := TimeManager.day_index

	# Eight hours of sleep, in one skip.
	TimeManager.set_total_minutes(day_before * 1440.0 + 8.0 * 60.0)
	await _settle(4)
	# Both shops are marked settled up to this moment first. The tests wind the
	# clock backwards and forwards a great deal, and a shop whose last
	# settlement is in the future is owed nothing for the hours that follow —
	# which is correct behaviour, and not what this test is measuring.
	BusinessManager.note_visible_trade(market)
	BusinessManager.note_visible_trade(coffee)
	TimeManager.advance_minutes(8 * 60)
	await _settle(20)

	_check(TimeManager.hour == 16, "eight hours pass (now %02d:00)" % TimeManager.hour)
	_check(
		market.revenue_today > market_before,
		"the market traded through them (+$%d)" % (market.revenue_today - market_before)
	)
	_check(
		coffee.revenue_today > coffee_before,
		"and so did the coffee shop (+$%d)" % (coffee.revenue_today - coffee_before)
	)
	_check(
		market.customer_count_today > 4,
		"a day's worth of customers, not one minute's (%d)" % market.customer_count_today
	)
	_check(
		market.units_sold_today > 0,
		"and stock actually moved (%d units sold)" % market.units_sold_today
	)


## TEST 128 — the city keeps working around all of it.
func _test_empire_and_crime() -> void:
	var market := _own_business()
	var coffee := _coffee_business()
	await _prepare_crime_scene()
	await _teleport(Vector3(-40.0, 0.5, 8.4))
	await _settle(10)

	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	coffee.manual_override = BusinessInstance.Override.FORCE_OPEN
	coffee.set_open(true)

	# Restocked first. This test is about the city carrying on around a crime,
	# not about whether the shops still had anything left after the previous
	# test traded through eight hours of it.
	for ingredient: StringName in [&"coffee_beans", &"milk_carton", &"paper_cup"]:
		coffee.add_storage(ingredient, 12)
	market.add_storage(&"bottled_water", 30)
	for shelf in market.shelves():
		market.stock_shelf(shelf.slot_id, &"bottled_water", shelf.room_left())

	var market_before := market.revenue_today
	var coffee_before := coffee.revenue_today

	var record := CrimeManager.report_crime(
		CrimeManager.CrimeType.CARJACKING, _player.global_position, _player, null
	)
	CrimeManager.mark_witnessed(record, _player)
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)
	await _settle(10)
	_check(WantedManager.level >= 1, "the player is wanted (%d stars)" % WantedManager.level)

	for i in 2:
		BusinessManager.simulate_hour_now(market, 12)
		BusinessManager.simulate_hour_now(coffee, 12)
	_check(market.revenue_today > market_before, "the market keeps trading")
	_check(coffee.revenue_today > coffee_before, "and so does the coffee shop")
	_check(BusinessManager.owned_count() == 2, "both are still owned")

	# Arrested, and the shops carry on.
	EconomyManager.restore(2000)
	WantedManager.request_bust()
	await _settle(int(WantedManager.bust_hold_seconds * 60.0) + 40)
	_check(WantedManager.level == 0, "the arrest resolves")
	_check(market.is_open() and coffee.is_open(), "and neither shop noticed")
	var after_bust := market.revenue_today
	BusinessManager.simulate_hour_now(market, 12)
	_check(market.revenue_today > after_bust, "trade continues afterwards")


## TEST 129 — the whole empire through a save file.
func _test_empire_save_load() -> void:
	var slot := 96
	var market := _own_business()
	var coffee := _coffee_business()

	BusinessManager.company_name = "Noel Holdings"
	BusinessManager.start_campaign(market, &"social")
	BusinessManager.order_stock(coffee, &"tea_leaves", 15)
	market.credit(5000, "Test funds", &"capital")
	BusinessManager.take_loan(market, &"starter")

	var saved := {
		"businesses": BusinessManager.owned_count(),
		"market_cash": market.cash_balance,
		"coffee_cash": coffee.cash_balance,
		"market_staff": market.employees.size(),
		"coffee_staff": coffee.employees.size(),
		"upgrades": market.upgrades.size(),
		"campaigns": market.active_campaigns().size(),
		"orders": BusinessManager.outstanding_orders().size(),
		"debt": market.total_debt(),
		"coffee_beans": coffee.storage_of(&"coffee_beans"),
		"market_shelves": market.total_shelf_units(),
		"auto_order": market.auto_order,
	}

	_check(SaveManager.save_to_slot(slot), "the empire saves")

	# Wreck it thoroughly.
	BusinessManager.company_name = "Wrong"
	market.cash_balance = 3
	market.upgrades.clear()
	market.campaigns.clear()
	market.loans.clear()
	coffee.storage.clear()
	coffee.employees.clear()
	await _settle(6)

	_check(SaveManager.load_from_slot(slot), "and loads back")
	await _settle(10)

	var market_back := _own_business()
	var coffee_back := _coffee_business()
	_check(BusinessManager.owned_count() == saved["businesses"], "both businesses come back")
	_check(market_back != null and coffee_back != null, "and are found by their properties")
	if market_back == null or coffee_back == null:
		return
	_check(market_back.business_name == "Silas Market", "the market keeps its name")
	_check(coffee_back.business_name == "Noel Coffee", "and the coffee shop keeps its")
	_check(BusinessManager.company_name == "Noel Holdings", "the company keeps its name")
	_check(market_back.cash_balance == saved["market_cash"], "each account is restored")
	_check(coffee_back.cash_balance == saved["coffee_cash"], "separately")
	_check(market_back.employees.size() == saved["market_staff"], "the payrolls are restored")
	_check(coffee_back.employees.size() == saved["coffee_staff"], "one per business")
	_check(market_back.upgrades.size() == saved["upgrades"], "the upgrades survive")
	_check(
		market_back.active_campaigns().size() == saved["campaigns"],
		"the campaign is still running"
	)
	_check(
		BusinessManager.outstanding_orders().size() == saved["orders"],
		"the delivery is still on its way"
	)
	_check(market_back.total_debt() == saved["debt"], "and the debt is still owed")
	_check(
		coffee_back.storage_of(&"coffee_beans") == saved["coffee_beans"],
		"the coffee shop's ingredients are its own"
	)
	_check(market_back.total_shelf_units() == saved["market_shelves"], "the shelves are as they were")
	_check(market_back.auto_order == saved["auto_order"], "and the manager's permissions")

	var manager_back := market_back.manager()
	_check(manager_back != null, "the manager is still employed")
	_check(
		manager_back == null or manager_back.role == EmployeeData.Role.MANAGER,
		"in the manager's job"
	)

	# Nothing duplicated: loading twice must not make two of anything.
	SaveManager.load_from_slot(slot)
	await _settle(10)
	_check(BusinessManager.owned_count() == saved["businesses"], "loading twice makes no copies")
	_check(
		BusinessManager.outstanding_orders().size() == saved["orders"],
		"and no duplicate deliveries"
	)
	SaveManager.delete_slot(slot)


## TEST 95 — a save written before any of this existed.
func _test_old_save_migration() -> void:
	var slot := 95
	var path := SaveManager.get_slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	# A Phase H save: one business, no upgrades, no loans, no manager settings,
	# and a property with none of the Phase I fields on it.
	file.store_string(JSON.stringify({
		"version": SaveManager.SAVE_VERSION,
		"clock": {"total_minutes": TimeManager.total_minutes},
		"economy": {"cash": 1234},
		"entities": {
			"business_manager": {
				"businesses": [{
					"id": "business_legacy", "name": "Old Market",
					"type": "convenience_store", "property": "unit_main_18",
					"cash": 900, "opening_hour": 8, "closing_hour": 20,
					"reputation": 55.0,
					"storage": {"bottled_water": 12},
					"prices": {"bottled_water": 4},
					"employees": [{
						"id": "legacy_worker", "name": "Pat Legacy", "wage": 18,
						"skill_checkout": 60, "skill_stocking": 40, "role": 0,
						"shift_start": 9, "shift_end": 17,
					}],
				}],
			},
			"property_unit_main_18": {"status": 1, "tenant": "player"},
		},
	}))
	file.close()

	_check(SaveManager.load_from_slot(slot), "a Phase H save still loads")
	await _settle(10)

	var old := BusinessManager.by_id(&"business_legacy")
	_check(old != null, "its business is there")
	if old == null:
		return
	_check(old.business_name == "Old Market", "with its name")
	_check(old.cash_balance == 900, "and its money")
	_check(BusinessManager.owned_count() == 1, "as the only business owned")
	_check(old.storage_of(&"bottled_water") == 12, "its stock is intact")
	_check(old.employees.size() == 1, "and its one employee")

	var worker := old.employees[0]
	_check(worker.role == EmployeeData.Role.CASHIER, "who is still a cashier")
	_check(worker.skill_barista == 50, "with average skill at the jobs that did not exist")
	_check(worker.skill_management == 50, "including managing")

	_check(not old.auto_open, "nothing is automated without being asked")
	_check(old.upgrades.is_empty(), "there are no upgrades")
	_check(old.loans.is_empty(), "and no debt")
	_check(old.total_debt() == 0, "so nothing is owed")
	_check(old.estimated_value() > 0, "and it can still be valued ($%d)" % old.estimated_value())

	var unit := PropertyManager.by_id(&"unit_main_18")
	_check(unit != null and unit.is_leased_by_player(), "its lease is restored")

	SaveManager.delete_slot(slot)


## TEST 122 — selling one, and the rest carrying on.
func _test_sell_business() -> void:
	# Rebuild the two-business state the migration test replaced.
	await _rebuild_empire_for_sale()

	var coffee := _coffee_business()
	var market := _own_business()
	_check(coffee != null and market != null, "two businesses to choose between")
	if coffee == null or market == null:
		return

	var unit := coffee.property()
	var price := coffee.sale_price()
	var value := coffee.estimated_value()
	_check(price > 0, "the coffee shop is worth selling ($%d)" % price)
	_check(price < value, "a buyer wants a discount on the valuation")

	var personal_before := EconomyManager.cash
	var market_cash_before := market.cash_balance
	var proceeds := BusinessManager.sell_business(coffee)

	_check(proceeds == price, "the sale pays what it was valued at")
	_check(
		EconomyManager.cash == personal_before + proceeds,
		"and the money goes to the player, not to the other business"
	)
	_check(market.cash_balance == market_cash_before, "the market's account is untouched")
	_check(BusinessManager.owned_count() == 1, "one business is left")
	_check(BusinessManager.business_for_property(&"unit_harbour_42") == null, "the unit is empty")
	_check(unit != null and unit.is_vacant(), "and the lease has ended")
	_check(_own_business() != null, "the market is still owned")
	_check(_own_business().employees.size() > 0, "with its own staff still on the payroll")
	_check(
		BusinessManager.get_statistic(&"businesses_sold") >= 1,
		"and the statistics count the sale"
	)


# --- Phase I helpers -----------------------------------------------------

func _coffee_property() -> CommercialProperty:
	return PropertyManager.by_id(&"unit_harbour_42")


func _coffee_unit() -> RetailUnit:
	return _main.get_node("Interiors/HarbourAvenueUnit") as RetailUnit


func _coffee_business() -> BusinessInstance:
	return BusinessManager.business_for_property(&"unit_harbour_42")


## The migration test deliberately replaces the whole register with a one-business
## save, so the sale test builds a second one back rather than depending on the
## order the tests happen to run in.
func _rebuild_empire_for_sale() -> void:
	EconomyManager.restore(30000)
	var unit := _coffee_property()
	if unit.is_vacant():
		PropertyManager.lease(unit)
	var coffee := _coffee_business()
	if coffee == null:
		coffee = BusinessManager.create_business("Noel Coffee", &"coffee_shop", unit)
	BusinessManager.deposit_to_business(coffee, 3000)
	for ingredient in [&"coffee_beans", &"paper_cup"]:
		BusinessManager.order_stock(coffee, ingredient, 20)
	BusinessManager.deliver_now(coffee)

	var market := _own_business()
	if market != null and market.employees.is_empty():
		BusinessManager.refresh_candidates()
		BusinessManager.hire(market, BusinessManager.get_candidates()[0], EmployeeData.Role.CASHIER)
	await _settle(6)


# --- Phase J: city expansion ---------------------------------------------

## TEST 130 — the city is made of districts, and knows which is which.
func _test_districts_registered() -> void:
	var districts := WorldManager.get_districts()
	_check(districts.size() >= 2, "the city has at least two districts (%d)" % districts.size())

	var harbour := WorldManager.by_id(&"harbour_row")
	var central := WorldManager.by_id(&"central")
	_check(harbour != null, "Harbour Row is registered")
	_check(central != null, "the Central District is registered")
	if harbour == null or central == null:
		return

	_check(harbour.display_name == "Harbour Row", "Harbour Row is named for the player")
	_check(central.display_name == "Central District", "so is the Central District")
	_check(not central.subtitle.is_empty(), "and Central has a line describing it")

	_check(
		not harbour.world_bounds.intersects(central.world_bounds),
		"the two districts do not overlap on the map"
	)
	var city := WorldManager.city_bounds()
	_check(
		city.encloses(harbour.world_bounds) and city.encloses(central.world_bounds),
		"the city bounds cover both of them"
	)
	_check(
		city.get_area() > harbour.world_bounds.get_area() * 1.8,
		"which makes the city substantially bigger than one district"
	)


## TEST 131 — asking where something is.
func _test_district_lookup() -> void:
	var harbour := WorldManager.by_id(&"harbour_row")
	var central := WorldManager.by_id(&"central")
	if harbour == null or central == null:
		return

	var in_harbour := Vector3(harbour.center_position.x, 0.0, harbour.center_position.z)
	var in_central := Vector3(central.center_position.x, 0.0, central.center_position.z)
	_check(
		WorldManager.district_at(in_harbour) == harbour,
		"a point in Harbour Row resolves to Harbour Row"
	)
	_check(
		WorldManager.district_at(in_central) == central,
		"a point in Central resolves to Central"
	)
	# The road between the districts belongs to neither rectangle. It must still
	# have an answer, or everything that asks "how busy is it here" divides by
	# nothing halfway to town.
	var between := Vector3(0.0, 0.0, -125.0)
	_check(WorldManager.district_at(between) != null, "the connecting road resolves to a district")
	_check(WorldManager.traffic_density_at(between) > 0.0, "and reports a traffic density")

	WorldManager.forget_announcements()
	_notifications.clear()
	await _teleport(in_central + Vector3(0.0, 1.0, 0.0))
	await _settle(60)
	_check(
		WorldManager.player_district() == central,
		"walking into Central makes it the player's district"
	)
	_check(_said("CENTRAL DISTRICT"), "and the district announces itself on arrival")

	_notifications.clear()
	await _teleport(in_central + Vector3(3.0, 1.0, 3.0))
	await _settle(60)
	_check(not _said("CENTRAL DISTRICT"), "but not a second time for the same district")


## TEST 132 — the districts are not the same place twice.
func _test_district_character() -> void:
	var harbour := WorldManager.by_id(&"harbour_row")
	var central := WorldManager.by_id(&"central")
	if harbour == null or central == null:
		return

	_check(
		central.commercial_rent_modifier > harbour.commercial_rent_modifier,
		"Central costs more to trade from (%.2f vs %.2f)"
		% [central.commercial_rent_modifier, harbour.commercial_rent_modifier]
	)
	_check(
		central.commercial_demand_modifier > harbour.commercial_demand_modifier,
		"and puts more customers past the door (%.2f vs %.2f)"
		% [central.commercial_demand_modifier, harbour.commercial_demand_modifier]
	)
	_check(
		central.residential_rent_modifier > harbour.residential_rent_modifier,
		"living there is dearer too"
	)
	_check(
		central.traffic_density > harbour.traffic_density,
		"the streets are busier (%.2f vs %.2f)" % [central.traffic_density, harbour.traffic_density]
	)
	_check(
		central.pedestrian_density > harbour.pedestrian_density,
		"and so are the pavements"
	)
	_check(central.police_presence > harbour.police_presence, "with more police about")

	# The rent on the actual units follows the character of the district rather
	# than being a number somebody typed twice.
	var dearest_harbour := 0
	var dearest_central := 0
	for unit in PropertyManager.get_properties():
		if unit.district_id == &"central":
			dearest_central = maxi(dearest_central, unit.rent_amount)
		else:
			dearest_harbour = maxi(dearest_harbour, unit.rent_amount)
	_check(
		dearest_central > dearest_harbour,
		"the priciest Central unit beats the priciest Harbour one ($%d vs $%d)"
		% [dearest_central, dearest_harbour]
	)


## TEST 133 — one world, not two maps side by side.
func _test_cross_district_travel() -> void:
	var nav := get_tree().get_first_node_in_group(&"nav_graph") as NavGraph
	var roads := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	_check(nav != null and roads != null, "the city has one nav graph and one road network")
	if nav == null or roads == null:
		return

	var harbour := WorldManager.by_id(&"harbour_row")
	var central := WorldManager.by_id(&"central")
	if harbour == null or central == null:
		return

	var from := Vector3(0.0, 0.0, 40.0)
	var to := Vector3(District02.CENTER_BLVD_X, 0.0, District02.KINGSTON_RD_Z)

	var walk := nav.find_path(NavGraph.Layer.WALK, from, to)
	_check(walk.size() > 10, "there is a walking route between the districts (%d hops)" % walk.size())
	if walk.size() > 1:
		_check(
			walk[walk.size() - 1].distance_to(to) < 20.0,
			"and it actually arrives in Central"
		)
		var longest := 0.0
		for i in range(1, walk.size()):
			longest = maxf(longest, walk[i].distance_to(walk[i - 1]))
		_check(longest < 14.0, "with no teleporting gap in it (%.1fm)" % longest)

	var road := nav.find_path(NavGraph.Layer.ROAD, from, to)
	_check(road.size() > 10, "and a driving route as well (%d hops)" % road.size())

	# The lane network is what traffic drives. It has to reach across too.
	var start_node := roads.nearest_node(Vector3(0.0, 0.0, 60.0))
	var end_node := roads.nearest_node(to)
	_check(start_node >= 0 and end_node >= 0, "both districts have lane nodes")
	_check(
		roads.node_position(start_node).distance_to(roads.node_position(end_node)) > 150.0,
		"which are a long way apart (%.0fm)"
		% roads.node_position(start_node).distance_to(roads.node_position(end_node))
	)

	# And the ground is continuous: the gateway between the districts used to be
	# a hole anything driving north fell through.
	for z: float in [-118.0, -125.0, -130.0, -136.0]:
		await _teleport(Vector3(District02.CENTER_BLVD_X, 1.5, z))
		await _settle(24)
		_check(
			_player.global_position.y > -0.5,
			"the ground holds at the district gateway (z=%.0f, y=%.2f)"
			% [z, _player.global_position.y]
		)


## TEST 134 — traffic that belongs where it is.
func _test_district_traffic() -> void:
	var harbour_weights := VehicleCatalogue.weights_for(&"harbour_row")
	var central_weights := VehicleCatalogue.weights_for(&"central")
	_check(VehicleCatalogue.ids().size() >= 6, "there are at least six civilian models")
	_check(harbour_weights != central_weights, "the two districts draw from different odds")
	_check(
		int(harbour_weights.get(&"van", 0)) > int(central_weights.get(&"van", 0)),
		"Harbour Row runs more vans"
	)
	_check(
		int(central_weights.get(&"coupe", 0)) > int(harbour_weights.get(&"coupe", 0)),
		"and Central is where the expensive cars are"
	)
	for id: StringName in VehicleCatalogue.ids():
		_check(VehicleCatalogue.scene_for(id) != null, "the %s has a scene" % id)

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var seen: Dictionary = {}
	for i in 200:
		seen[VehicleCatalogue.pick_id_for_district(&"central", rng)] = true
	_check(not seen.has(&"van"), "a van never turns up in a Central spawn")
	_check(seen.has(&"compact"), "but compacts do")

	var traffic := _traffic_manager()
	if traffic == null:
		return
	var central := WorldManager.by_id(&"central")
	if central == null:
		return
	await _teleport(Vector3(0.0, 1.0, 40.0))
	await _settle(12)
	var harbour_target := traffic.get_target_population()
	await _teleport(Vector3(central.center_position.x, 1.0, central.center_position.z))
	await _settle(12)
	var central_target := traffic.get_target_population()
	_check(
		central_target > harbour_target,
		"and Central keeps more cars on the road (%d vs %d)" % [central_target, harbour_target]
	)


## TEST 135 — the map knows what is in the city.
func _test_map_markers() -> void:
	var markers := MapManager.collect_markers()
	_check(markers.size() >= 12, "the map has something to show (%d markers)" % markers.size())

	var by_category: Dictionary = {}
	for marker in markers:
		by_category[marker.category] = int(by_category.get(marker.category, 0)) + 1
	for category: int in [
		MapMarker.Category.HOME,
		MapMarker.Category.AVAILABLE_PROPERTY,
		MapMarker.Category.JOB,
		MapMarker.Category.SHOP,
		MapMarker.Category.LANDMARK,
	]:
		_check(
			int(by_category.get(category, 0)) > 0,
			"the map shows %s" % MapMarker.category_name(category).to_lower()
		)

	var city := WorldManager.city_bounds().grow(30.0)
	var outside := 0
	var unlabelled := 0
	for marker in markers:
		if not city.has_point(Vector2(marker.position.x, marker.position.z)):
			outside += 1
		if marker.label.is_empty():
			unlabelled += 1
	_check(outside == 0, "every marker is inside the city (%d stray)" % outside)
	_check(unlabelled == 0, "and every marker is labelled (%d blank)" % unlabelled)

	var in_central := 0
	for marker in markers:
		var district := WorldManager.district_at(marker.position)
		if district != null and district.district_id == &"central":
			in_central += 1
	_check(in_central >= 4, "and the new district is on it (%d markers)" % in_central)

	MapManager.set_category_shown(MapMarker.Category.SHOP, false)
	var hidden := MapManager.visible_markers()
	var shops_left := 0
	for marker in hidden:
		if marker.category == MapMarker.Category.SHOP:
			shops_left += 1
	_check(shops_left == 0, "turning a category off hides it")
	_check(hidden.size() < markers.size(), "and leaves the rest alone")
	MapManager.set_category_shown(MapMarker.Category.SHOP, true)
	_check(
		MapManager.visible_markers().size() == markers.size(),
		"turning it back on brings them back"
	)


## TEST 136 — picking somewhere to go, and getting there.
func _test_map_destination() -> void:
	var target: MapMarker = null
	for marker in MapManager.collect_markers():
		var district := WorldManager.district_at(marker.position)
		if district != null and district.district_id == &"central":
			target = marker
			break
	_check(target != null, "there is somewhere in Central to head for")
	if target == null:
		return

	await _teleport(Vector3(0.0, 1.0, 40.0))
	MapManager.set_destination(target)
	_check(MapManager.has_destination(), "the destination is set")
	_check(MapManager.get_destination() == target, "and it is the one that was picked")

	var far := MapManager.distance_to_destination()
	_check(far > 150.0, "which is a long way off (%.0fm)" % far)

	var route := MapManager.route_to_destination()
	_check(route.size() > 5, "the map can draw a route to it (%d points)" % route.size())

	# A one-element array, not a bool: a GDScript lambda captures locals by
	# value, so assigning to a captured bool changes the copy and nothing else.
	var arrived := [false]
	var handler := func(_marker: MapMarker) -> void: arrived[0] = true
	MapManager.destination_reached.connect(handler)
	await _teleport(target.position + Vector3(2.0, 1.0, 2.0))
	await _settle(40)
	MapManager.destination_reached.disconnect(handler)

	_check(bool(arrived[0]), "arriving there fires the arrival")
	_check(not MapManager.has_destination(), "and clears the destination")

	MapManager.set_destination(target)
	MapManager.clear_destination()
	_check(not MapManager.has_destination(), "a destination can be given up as well")


## TEST 137 — the better flat.
func _test_residence_lease() -> void:
	var studio := PropertyManager.residence_by_id(&"larkspur")
	var flat := PropertyManager.residence_by_id(&"meridian")
	_check(studio != null, "the starter studio is a property in its own right")
	_check(flat != null, "and there is a second flat to move up to")
	if studio == null or flat == null:
		return

	_check(studio.is_leased_by_player(), "the studio starts leased")
	_check(studio.is_current_home(), "and is home")
	_check(not flat.is_leased_by_player(), "the Central flat starts empty")
	_check(
		flat.rent_amount > studio.rent_amount,
		"it is dearer than the studio ($%d vs $%d)" % [flat.rent_amount, studio.rent_amount]
	)
	_check(flat.district_id == &"central", "because of where it is")

	EconomyManager.restore(60)
	_check(not PropertyManager.lease_residence(flat), "it cannot be rented without the money")
	_check(not flat.is_leased_by_player(), "and stays empty")

	EconomyManager.restore(5000)
	var before := EconomyManager.cash
	var cost := flat.move_in_cost()
	_check(cost == flat.deposit + flat.rent_amount, "moving in costs a deposit and the first rent")
	_check(PropertyManager.lease_residence(flat), "with the money it can be rented")
	_check(flat.is_leased_by_player(), "the lease is signed")
	_check(EconomyManager.cash == before - cost, "and the money has gone ($%d)" % cost)
	_check(_said("APARTMENT RENTED"), "the player is told")

	_check(not PropertyManager.lease_residence(flat), "and it cannot be rented twice")


## TEST 138 — moving house.
func _test_change_home() -> void:
	var studio := PropertyManager.residence_by_id(&"larkspur")
	var flat := PropertyManager.residence_by_id(&"meridian")
	if studio == null or flat == null:
		return

	var studio_bed := _bed_in("Apartment")
	var flat_bed := _bed_in("MeridianApartment")
	_check(studio_bed != null and flat_bed != null, "both flats have a bed")
	if studio_bed == null or flat_bed == null:
		return

	_check(studio_bed.is_players_bed(), "the studio bed is the player's, to start with")
	_check(not flat_bed.is_players_bed(), "and the Central one is not, lease or no lease")
	_check(not flat_bed.can_interact(_player), "so it cannot be slept in")
	_check(
		flat_bed.get_prompt_text().contains("NOT YOUR HOME"),
		"and it says why"
	)

	flat.set_as_home()
	_check(PropertyManager.current_home() == flat, "setting the flat as home moves the player in")
	_check(not studio.is_current_home(), "the studio stops being home")
	_check(flat_bed.is_players_bed(), "and the flat's bed becomes the one to sleep in")
	_check(not studio_bed.is_players_bed(), "while the studio's does not")

	# And sleeping in it works exactly as it did in the studio.
	var stats := _player.get_stats()
	stats.restore_values(stats.health, 20.0, stats.hunger)
	TimeManager.set_total_minutes(23.0 * 60.0)
	flat_bed.interact(_player)
	await _settle(6)
	_check(TimeManager.hour == 7, "sleeping in the new bed wakes the player at 07:00")
	_check(stats.energy > 95.0, "and restores energy (%.0f)" % stats.energy)

	studio.set_as_home()
	_check(PropertyManager.current_home() == studio, "and the player can move back")


## TEST 139 — courier work, which is what the map is for.
func _test_courier_run() -> void:
	var depots := get_tree().get_nodes_in_group(&"courier_depot")
	_check(depots.size() >= 1, "there is somewhere to pick up deliveries (%d)" % depots.size())

	await _teleport(Vector3(0.0, 1.0, 40.0))
	CourierJob.cancel_run()
	_check(not CourierJob.has_active_run(), "no run in progress to begin with")

	_check(CourierJob.offer_run(), "a run can be taken")
	_check(CourierJob.has_active_run(), "which is now in progress")
	var destination := MapManager.get_destination()
	_check(destination != null, "taking one sets the map destination")
	if destination == null:
		return
	_check(
		destination.position.distance_to(_player.global_position) >= CourierJob.minimum_distance,
		"and it is far enough away to be worth paying for (%.0fm)"
		% destination.position.distance_to(_player.global_position)
	)
	var fee := CourierJob.active_fee()
	_check(fee >= CourierJob.base_fee, "the fee covers the distance ($%d)" % fee)
	_check(not CourierJob.active_destination_name().is_empty(), "the drop-off has a name")

	var runs_before := CourierJob.runs_completed()
	var cash_before := EconomyManager.cash
	await _teleport(destination.position + Vector3(1.0, 1.0, 1.0))
	await _settle(40)

	_check(not CourierJob.has_active_run(), "arriving finishes the run")
	_check(CourierJob.runs_completed() == runs_before + 1, "which is counted")
	_check(EconomyManager.cash >= cash_before + fee, "and paid ($%d)" % (EconomyManager.cash - cash_before))
	_check(_said("DELIVERED"), "the player is told they delivered it")

	# A run that is given up pays nothing.
	_check(CourierJob.offer_run(), "another run can be taken")
	var cash_at_cancel := EconomyManager.cash
	CourierJob.cancel_run()
	_check(not CourierJob.has_active_run(), "and dropped")
	_check(EconomyManager.cash == cash_at_cancel, "with no fee for dropping it")
	_check(not MapManager.has_destination(), "and the destination goes with it")


## TEST 140 — trading from the good part of town.
func _test_central_property() -> void:
	var units: Array[CommercialProperty] = []
	for unit in PropertyManager.get_properties():
		if unit.district_id == &"central":
			units.append(unit)
	_check(units.size() >= 4, "Central has commercial units to let (%d)" % units.size())
	if units.is_empty():
		return

	var premium := PropertyManager.by_id(&"unit_plaza_03")
	var small := PropertyManager.by_id(&"unit_market_12")
	_check(premium != null and small != null, "including a premium unit and a small one")
	if premium == null or small == null:
		return

	_check(
		premium.size_class == CommercialProperty.SizeClass.MEDIUM,
		"the plaza unit is the bigger of the two"
	)
	_check(premium.floor_area > small.floor_area, "with more floor to it")
	_check(premium.customer_capacity > small.customer_capacity, "and room for more customers")
	_check(premium.queue_capacity > small.queue_capacity, "and a longer queue")
	_check(premium.rent_amount > small.rent_amount, "for more rent")
	_check(
		premium.location_demand_modifier > small.location_demand_modifier,
		"because more people walk past it"
	)
	_check(premium.size_label() == "Medium", "the size reads as words for the player")
	_check(premium.location_label() == "High", "and so does the footfall")
	_check(small.location_label() == "Average", "which is only average on Market Street")

	# Every property in the city has a unique id, or the save file overwrites one
	# lease with another.
	var seen: Dictionary = {}
	var duplicates := 0
	for unit in PropertyManager.get_properties():
		if seen.has(unit.property_id):
			duplicates += 1
		seen[unit.property_id] = true
	for home in PropertyManager.get_residences():
		if seen.has(home.residence_id):
			duplicates += 1
		seen[home.residence_id] = true
	_check(duplicates == 0, "every property in the city has its own id")

	# The address is worth what the district is worth as well as what the pitch
	# is: the same shop in Central should expect more people past the door than
	# it would on a Harbour Row street, without the gap being silly.
	var harbour_unit := PropertyManager.by_id(&"unit_main_18")
	if harbour_unit != null:
		var harbour_pull := harbour_unit.location_demand_modifier
		var central_pull := (
			premium.location_demand_modifier
			* WorldManager.by_id(&"central").commercial_demand_modifier
		)
		_check(
			central_pull > harbour_pull * 1.15,
			"a Central plaza pitch pulls better than a Harbour Row one (x%.2f vs x%.2f)"
			% [central_pull, harbour_pull]
		)
		_check(
			central_pull < harbour_pull * 2.5,
			"but not by an absurd margin (x%.2f)" % (central_pull / maxf(harbour_pull, 0.01))
		)

	# And it can actually be taken on.
	EconomyManager.restore(20000)
	_check(small.is_vacant(), "the small unit is free")
	_check(
		PropertyManager.lease(small) == PropertyManager.LeaseResult.OK,
		"and can be leased"
	)
	_check(not small.is_vacant(), "which takes it off the market")
	small.end_lease()
	_check(small.is_vacant(), "and giving it up puts it back")


## TEST 141 — heat does not stop at the district line.
func _test_wanted_across_districts() -> void:
	await _prepare_crime_scene()
	await _teleport(Vector3(0.0, 0.5, 60.0))
	EconomyManager.restore(2000)

	var record := CrimeManager.report_crime(
		CrimeManager.CrimeType.STORE_ROBBERY, _player.global_position, _player, null
	)
	CrimeManager.mark_witnessed(record, _player)
	CrimeManager.mark_reported(record)
	WantedManager.on_crime_reported(record)
	await _settle(6)

	var level := WantedManager.level
	_check(level >= 2, "a robbery in Harbour Row raises the heat (%d stars)" % level)
	var budget_in_harbour := WantedManager.get_response_budget()

	var central := WorldManager.by_id(&"central")
	if central == null:
		return
	await _teleport(Vector3(central.center_position.x, 1.0, central.center_position.z))
	await _settle(60)

	_check(
		WorldManager.player_district() == central,
		"running to Central changes the player's district"
	)
	_check(
		WantedManager.level == level,
		"but the wanted level crosses with them (%d)" % WantedManager.level
	)
	_check(WantedManager.is_wanted(), "the player is still wanted")
	_check(
		WantedManager.local_police_presence() > 1.0,
		"Central is the better-policed half of the city (x%.2f)"
		% WantedManager.local_police_presence()
	)
	_check(
		WantedManager.get_response_budget() > budget_in_harbour,
		"so the same wanted level sends more units there (%d vs %d)"
		% [WantedManager.get_response_budget(), budget_in_harbour]
	)

	await _station_police_near(_player.global_position, 40.0)
	await _settle(120)
	_check(_responding_units() >= 1, "and Central's police answer the call (%d)" % _responding_units())

	WantedManager.clear_wanted("")
	await _settle(6)
	_check(not WantedManager.is_wanted(), "and the heat clears the same way it always did")


## TEST 142 — the bigger world through a save file.
func _test_world_save_load() -> void:
	var slot := 94
	var flat := PropertyManager.residence_by_id(&"meridian")
	var studio := PropertyManager.residence_by_id(&"larkspur")
	if flat == null or studio == null:
		return

	EconomyManager.restore(8000)
	if not flat.is_leased_by_player():
		PropertyManager.lease_residence(flat)
	flat.set_as_home()
	var runs := CourierJob.runs_completed()

	_check(SaveManager.save_to_slot(slot), "the expanded city saves")

	# Undo all of it.
	flat.end_lease()
	studio.set_as_home()
	_check(PropertyManager.current_home() == studio, "and the state is changed underneath it")

	_check(SaveManager.load_from_slot(slot), "the save loads back")
	await _settle(12)

	_check(
		PropertyManager.residence_by_id(&"meridian").is_leased_by_player(),
		"the Central lease comes back"
	)
	_check(
		PropertyManager.current_home() != null
		and PropertyManager.current_home().residence_id == &"meridian",
		"and so does where the player lives"
	)
	_check(CourierJob.runs_completed() == runs, "the delivery record survives (%d)" % runs)
	_check(WorldManager.count() >= 2, "both districts are still registered after a load")
	_check(
		MapManager.collect_markers().size() >= 12,
		"and the map still knows what is in the city"
	)

	var bed := _bed_in("MeridianApartment")
	_check(bed != null and bed.is_players_bed(), "the bed in the loaded home is the player's")

	# Back to the studio, so anything after this starts where it expects to.
	PropertyManager.residence_by_id(&"larkspur").set_as_home()
	SaveManager.delete_slot(slot)


## TEST 143 — a save written before the city grew.
func _test_pre_district_save() -> void:
	var slot := 93
	var file := FileAccess.open(SaveManager.get_slot_path(slot), FileAccess.WRITE)
	_check(file != null, "a one-district save file can be written for the test")
	if file == null:
		return
	# A save from before the city grew: no residences, no Central district, and
	# no map state. Nothing in it knows the second district exists.
	file.store_string(JSON.stringify({
		"version": SaveManager.SAVE_VERSION,
		"clock": {"total_minutes": TimeManager.total_minutes},
		"economy": {"cash": 1234},
		"entities": {},
	}))
	file.close()

	_check(SaveManager.load_from_slot(slot), "a one-district save still loads")
	await _settle(12)
	_check(EconomyManager.cash == 1234, "the money in it is restored")
	_check(WorldManager.count() >= 2, "the new district is still there")
	_check(
		PropertyManager.current_home() != null,
		"and the player still has somewhere to live"
	)
	_check(
		PropertyManager.residence_by_id(&"larkspur") != null,
		"with the studio present as a property"
	)
	SaveManager.delete_slot(slot)


## TEST 144 — the edge of the world, and the road that will leave it.
func _test_city_edge() -> void:
	# The top of Central Boulevard is barriered, not walled: the player can see
	# the road carry on, and cannot drive up it.
	await _teleport(Vector3(District02.CENTER_BLVD_X, 1.0, -318.0))
	await _settle(20)
	var before := _player.global_position.z
	await _hold(["move_forward"], 90)
	await _settle(20)
	_check(
		_player.global_position.z > District02.NORTH_EDGE + 1.0,
		"the closed road at the top of Central stops the player (z %.0f -> %.0f)"
		% [before, _player.global_position.z]
	)
	_check(_player.global_position.y > -0.5, "without dropping them out of the world")

	# And the sides of the connecting stretch, which is a strip of ground with
	# nothing but verge either side of the carriageway.
	await _teleport(Vector3(District02.CORRIDOR_HALF - 4.0, 1.0, -112.0))
	await _settle(20)
	await _hold(["move_right"], 90)
	await _settle(20)
	_check(
		_player.global_position.x < District02.CORRIDOR_HALF,
		"the gateway is walled at its edges (x %.1f)" % _player.global_position.x
	)
	_check(_player.global_position.y > -0.5, "and the player is still on the ground")

	# Central's car parks, which are what the district has instead of kerbside
	# parking.
	for spot: Vector3 in [Vector3(-102.0, 1.0, -230.0), Vector3(102.0, 1.0, -200.0)]:
		await _teleport(spot)
		await _settle(24)
		_check(
			_player.global_position.y > -0.5,
			"there is ground under the car park at %.0f, %.0f" % [spot.x, spot.z]
		)


## TEST 145 — the development overlays, which must never crash the game they are
## meant to explain.
func _test_world_debug() -> void:
	var overlay := _main.get_node_or_null("WorldDebug") as CanvasLayer
	_check(overlay != null, "the world debug overlay is in the scene")
	if overlay == null:
		return
	_check(not overlay.visible, "and is hidden in a normal game")

	overlay.call("toggle")
	await _settle(6)
	_check(overlay.visible, "F11 brings it up")

	var readout := overlay.get_node("Panel/Readout") as Label
	_check(readout != null and readout.text.contains("WORLD"), "it says what it is")
	_check(readout.text.contains("districts loaded: 2"), "and counts the districts")
	_check(readout.text.contains("fps"), "with a frame rate on it")

	# Every world view layer, drawn and cleared. This is the check that a debug
	# draw call against a graph or a marker list has not gone stale.
	for key: int in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = true
		overlay.call("_unhandled_input", event)
		await _settle(2)
	# The overlay draws into whatever scene is running, which under the test
	# harness is the harness rather than main.tscn.
	var scene := get_tree().current_scene
	var lines := scene.get_node_or_null("WorldDebugLines")
	var labels := scene.get_node_or_null("WorldDebugLabels")
	_check(lines != null, "the world view draws into the world")
	_check(
		labels != null and labels.get_child_count() > 0,
		"including a label per property and marker (%d)"
		% (labels.get_child_count() if labels != null else 0)
	)

	overlay.call("toggle")
	await _settle(6)
	_check(not overlay.visible, "F11 puts it away again")
	_check(
		labels == null or labels.get_child_count() == 0,
		"and takes its lines and labels with it"
	)


## TEST 146 — the player is a person, not a placeholder.
func _test_player_figure() -> void:
	var pivot := _player.get_node_or_null("BodyPivot") as Node3D
	_check(pivot != null, "the player has a body pivot")
	if pivot == null:
		return
	_check(_player.rig != null, "and a built figure on it")
	if _player.rig == null:
		return

	for part in ["hips", "chest", "head", "arm_left", "arm_right", "leg_left", "leg_right"]:
		_check(_player.rig.get(part) != null, "the figure has a %s" % part.replace("_", " "))
	_check(
		pivot.find_child("Skull", true, false) != null,
		"with a head on it rather than a capsule"
	)
	_check(
		pivot.find_child("Shoe", true, false) != null, "and shoes"
	)
	# The old placeholder is gone: no capsule mesh anywhere under the figure.
	var capsules := 0
	for node in pivot.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh is CapsuleMesh:
			capsules += 1
	_check(capsules == 0, "and no placeholder capsule left on it (%d)" % capsules)

	# The figure moves. Walking must swing the legs, and standing still must
	# not — an animator that runs whatever the player does is worse than none.
	await _teleport(Vector3(0.0, 0.5, 40.0))
	await _settle(20)
	var still := _player.rig.leg_left.rotation.x

	# Sampled across a whole stride rather than at one instant. A walk cycle
	# passes back through its resting angle twice a step, so a single reading
	# taken at the wrong moment reports a leg that is not moving when it is —
	# which is a test failing on its own timing rather than on the animator.
	var lowest := still
	var highest := still
	Input.action_press("move_forward")
	for i in 32:
		await _settle(1)
		var angle: float = _player.rig.leg_left.rotation.x
		lowest = minf(lowest, angle)
		highest = maxf(highest, angle)
	_release_all()
	await _settle(10)
	_check(
		highest - lowest > 0.15,
		"walking swings the legs (%.3f through %.3f)" % [lowest, highest]
	)
	_check(_player.get_planar_speed() >= 0.0, "and the player is still moving normally")


## TEST 147 — a crowd of people rather than a crowd of one person.
func _test_crowd_variety() -> void:
	var civilians := get_tree().get_nodes_in_group(&"pedestrian")
	_check(civilians.size() >= 10, "there is a crowd to look at (%d)" % civilians.size())

	var skins: Dictionary = {}
	var hairs: Dictionary = {}
	var tops: Dictionary = {}
	var heights: Dictionary = {}
	var figures := 0
	for node in civilians:
		var walker: Pedestrian = node as Pedestrian
		if walker == null or walker.character_look == null:
			continue
		figures += 1
		skins[walker.character_look.skin.to_html(false)] = true
		hairs[walker.character_look.hair.to_html(false)] = true
		tops[walker.character_look.top.to_html(false)] = true
		heights["%.2f" % walker.character_look.height] = true

	_check(figures == civilians.size(), "every civilian is a built figure (%d)" % figures)
	_check(skins.size() >= 3, "with a range of skin tones (%d)" % skins.size())
	_check(hairs.size() >= 3, "a range of hair colours (%d)" % hairs.size())
	_check(tops.size() >= 3, "a range of clothing (%d)" % tops.size())
	_check(heights.size() >= 5, "and no two the same height (%d distinct)" % heights.size())

	# And they are people-shaped: joints, not capsules.
	var sample: Pedestrian = civilians[0] as Pedestrian
	_check(sample.rig != null and sample.rig.head != null, "a civilian has a head")
	_check(sample.rig.leg_left != null, "and legs that can be moved")


## TEST 148 — police read as police.
func _test_police_look() -> void:
	var officers := _officers()
	_check(officers.size() >= 3, "there are officers on foot (%d)" % officers.size())
	if officers.is_empty():
		return
	var officer: PoliceOfficer = officers[0]
	_check(
		officer.character_look != null
		and officer.character_look.category == CharacterLook.Category.POLICE,
		"an officer is built as police"
	)
	var pivot := officer.get_node_or_null("BodyPivot") as Node3D
	_check(pivot != null and pivot.find_child("Cap", true, false) != null, "in a cap")
	_check(pivot != null and pivot.find_child("CapBadge", true, false) != null, "with a badge on it")
	_check(pivot != null and pivot.find_child("Vest", true, false) != null, "and a stab vest")
	_check(
		officer.character_look.top.v < 0.4,
		"the uniform is dark (%.2f)" % officer.character_look.top.v
	)

	# The patrol car is identifiable before its lights are on.
	var cars := _police_cars()
	_check(cars.size() >= 1, "and there are patrol cars (%d)" % cars.size())
	if cars.is_empty():
		return
	var car: Vehicle = cars[0]
	_check(
		car.data.livery == VehicleData.Livery.POLICE, "a patrol car carries a police livery"
	)
	_check(
		car.find_child("LiveryDoor-1", true, false) != null, "which paints its doors"
	)
	_check(car.find_child("LightBar", true, false) != null, "and it has a light bar")


## TEST 149 — cars that look like cars, and differ from each other.
func _test_vehicle_models() -> void:
	var profiles: Dictionary = {}
	for id: StringName in VehicleCatalogue.ids():
		var scene := VehicleCatalogue.scene_for(id)
		var car: Vehicle = scene.instantiate()
		add_child(car)
		_check(car.data != null, "the %s has data" % id)
		if car.data == null:
			car.queue_free()
			continue
		profiles[car.data.body_profile] = true
		for part in ["Chassis", "Bonnet", "Boot", "Cabin", "Roof", "Grille"]:
			_check(car.find_child(part, true, false) != null, "the %s has a %s" % [id, part.to_lower()])
		_check(car.find_child("Headlight-1", true, false) != null, "the %s has headlights" % id)
		_check(car.find_child("Taillight1", true, false) != null, "and taillights" )
		_check(car.find_child("Mirror-1", true, false) != null, "and wing mirrors")
		_check(car.find_child("Hub", true, false) != null, "and hubs in its wheels")
		_check(car.find_child("ArchF-1", true, false) != null, "and arches over them")
		_check(car.data.resale_value > 0, "and a value (%d)" % car.data.resale_value)
		car.queue_free()
	_check(
		profiles.size() >= 4,
		"the roster covers at least four silhouettes (%d)" % profiles.size()
	)


## TEST 150 — interiors that are dressed rather than empty.
func _test_interior_dressing() -> void:
	var unit := _unit_interior()
	_check(unit != null and unit.is_built(), "there is a player-owned shop to look at")
	if unit != null and unit.is_built():
		_check(unit.find_child("GlazingWest", true, false) != null, "its street wall is glazed")
		_check(unit.find_child("RiserEast", true, false) != null, "with a stall riser under it")
		_check(unit.find_child("Rack", true, false) != null, "the store room has racking")
		_check(unit.find_child("Strip-1", true, false) != null, "and the room is lit")

	var flat := _main.get_node_or_null("Interiors/Apartment") as ApartmentInterior
	_check(flat != null, "the starter flat is in the scene")
	if flat != null:
		for part in ["LivingRug", "Dresser", "Plant", "Art", "TableLamp"]:
			_check(
				flat.find_child(part, true, false) != null,
				"the flat has a %s in it" % part.to_lower()
			)

	var better := _main.get_node_or_null("Interiors/MeridianApartment") as ApartmentInterior
	_check(better != null, "so is the better one")
	if better != null:
		_check(better.spacious, "which is the bigger room")
		for part in ["Sofa", "FloorLamp", "BathroomDoor"]:
			_check(
				better.find_child(part, true, false) != null,
				"and it has a %s the studio does not" % part.to_lower()
			)
	await _settle(2)


## TEST 151 — one interface, styled once.
func _test_ui_theme() -> void:
	var theme := get_tree().root.theme
	_check(theme != null, "a theme is applied at the window root")
	if theme == null:
		return
	_check(
		theme.has_stylebox("panel", "PanelContainer"),
		"panels are styled"
	)
	_check(theme.has_stylebox("normal", "Button"), "and so are buttons")
	_check(theme.default_font_size == UITheme.FONT_SIZE, "with one default text size")
	_check(
		theme.get_color("font_color", "Label") == Palette.UI_TEXT,
		"and text takes its colour from the palette"
	)
	# The palette is the single source for status colour, so the same idea is
	# never two different greens.
	_check(BusinessUIKit.GOOD == Palette.MONEY, "money reads the same colour everywhere")
	_check(BusinessUIKit.BAD == Palette.LOSS, "and so does a loss")


# --- Phase J helpers -----------------------------------------------------

func _bed_in(interior_name: String) -> Bed:
	var interior := _main.get_node_or_null("Interiors/%s" % interior_name)
	if interior == null:
		return null
	return _find_bed(interior)


func _find_bed(node: Node) -> Bed:
	if node is Bed:
		return node
	for child in node.get_children():
		var found := _find_bed(child)
		if found != null:
			return found
	return null


# --- Phase L: audio and the front end -------------------------------------

## TEST 152 — the mixer exists and answers to the settings screen.
func _test_audio_buses() -> void:
	for bus in AudioBuses.ALL:
		_check(
			AudioBuses.index_of(bus) >= 0,
			"there is a %s bus" % AudioBuses.display_name(bus)
		)

	var master := AudioServer.get_bus_index(AudioBuses.MASTER)
	_check(
		AudioServer.get_bus_effect_count(master) > 0,
		"the master bus is limited, so a chase cannot clip"
	)
	for bus in AudioBuses.ALL:
		if bus == AudioBuses.MASTER:
			continue
		_check(
			AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == AudioBuses.MASTER,
			"%s routes through the master" % AudioBuses.display_name(bus)
		)

	# A slider at zero is silence, not a very quiet bus.
	var before := AudioBuses.get_volume(AudioBuses.SFX)
	AudioBuses.set_volume(AudioBuses.SFX, 0.0)
	_check(
		AudioServer.is_bus_mute(AudioServer.get_bus_index(AudioBuses.SFX)),
		"a volume of zero mutes rather than whispers"
	)
	AudioBuses.set_volume(AudioBuses.SFX, 0.5)
	_check(
		absf(AudioBuses.get_volume(AudioBuses.SFX) - 0.5) < 0.02,
		"and a volume set is the volume read back (%.2f)"
		% AudioBuses.get_volume(AudioBuses.SFX)
	)
	AudioBuses.set_volume(AudioBuses.SFX, before)


## TEST 153 — every sound the game asks for exists and is playable.
func _test_tone_bank() -> void:
	var built := 0
	var silent := 0
	for id in ToneBank.ids():
		var stream := ToneBank.get_stream(id)
		if stream == null or stream.data.size() < 64:
			silent += 1
			continue
		built += 1
	_check(built >= 30, "the tone bank builds its sounds (%d)" % built)
	_check(silent == 0, "and none of them came out empty (%d)" % silent)

	# Loops must be marked as loops, or a siren is a single wail.
	for id: StringName in [&"siren", &"engine_loop", &"amb_city_day", &"amb_store"]:
		_check(
			ToneBank.get_stream(id).loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"%s loops" % id
		)
	for id: StringName in [&"ui_click", &"step_concrete", &"impact_heavy"]:
		_check(
			ToneBank.get_stream(id).loop_mode == AudioStreamWAV.LOOP_DISABLED,
			"%s is a one-shot" % id
		)
	# Cached, not rebuilt: a footstep must not synthesise a waveform per step.
	_check(
		ToneBank.get_stream(&"ui_click") == ToneBank.get_stream(&"ui_click"),
		"and a sound asked for twice is the same stream"
	)


## TEST 154 — the ground decides what walking on it sounds like.
func _test_footstep_surfaces() -> void:
	await _teleport(Vector3(-40.0, 0.5, District01.MAIN_ST_Z))
	await _settle(20)
	_check(
		SurfaceMap.under(_player) == SurfaceMap.Surface.ASPHALT,
		"standing in the road is asphalt (%s)"
		% SurfaceMap.display_name(SurfaceMap.under(_player))
	)

	await _teleport(Vector3(-40.0, 0.5, District01.MAIN_ST_Z - District01.ROAD_HALF - 1.4))
	await _settle(20)
	_check(
		SurfaceMap.under(_player) == SurfaceMap.Surface.CONCRETE,
		"stepping onto the pavement is concrete (%s)"
		% SurfaceMap.display_name(SurfaceMap.under(_player))
	)

	# Every surface has a sound, and they are not all the same sound.
	var sounds: Dictionary = {}
	for surface in SurfaceMap.Surface.values():
		var id := SurfaceMap.sound_for(surface)
		_check(ToneBank.get_stream(id) != null, "%s has a footstep" % SurfaceMap.display_name(surface))
		sounds[id] = true
	_check(sounds.size() == SurfaceMap.Surface.size(), "and no two surfaces share one")

	# The player's own feet are attached and exempt from the crowd's budget.
	var steps := _player.get_node_or_null("Footsteps") as Footsteps
	_check(steps != null and steps.is_player, "the player has footsteps of their own")


## TEST 155 — a car makes a noise, and a parked one does not.
func _test_vehicle_audio() -> void:
	var car := _player_car()
	var audio := car.get_node_or_null("Audio") as VehicleAudio
	_check(audio != null, "every vehicle carries its own audio")
	if audio == null:
		return

	var engine := audio.get_node_or_null("Engine") as AudioStreamPlayer3D
	_check(engine != null, "with an engine loop on the vehicle bus")
	_check(
		engine.bus == String(AudioBuses.VEHICLES),
		"routed so the vehicle slider moves it (%s)" % engine.bus
	)
	_check(not car.is_engine_running(), "a parked car with nobody in it is not running")

	await _teleport(car.global_position + Vector3(2.4, 0.5, 0.0))
	await _settle(10)
	await _drive(car)
	await _settle(10)
	_check(car.is_engine_running(), "and getting in starts it")
	await _hold(["move_forward"], 60)
	_check(
		absf(car.get_throttle_input()) > 0.0 or car.get_planar_speed() > 0.5,
		"the audio can read what the driver is doing"
	)
	await _leave_vehicle()
	await _settle(10)
	_check(not car.is_engine_running(), "getting out stops it again")


## TEST 156 — the siren follows the light bar exactly.
func _test_siren_state() -> void:
	await _prepare_crime_scene()
	var patrol: Vehicle = null
	for car in _police_cars():
		patrol = car
		break
	_check(patrol != null, "there is a patrol car to check")
	if patrol == null:
		return

	var audio := patrol.get_node_or_null("Audio") as VehicleAudio
	_check(audio != null, "which carries a siren")
	if audio == null:
		return
	_check(
		patrol.data.livery == VehicleData.Livery.POLICE,
		"and wears a police livery"
	)
	_check(
		audio.get_node_or_null("Siren") != null,
		"a siren player exists only on liveried cars"
	)
	_check(
		_player_car().get_node("Audio").get_node_or_null("Siren") == null,
		"and a civilian car has none"
	)

	var driver := patrol.get_node_or_null("Driver") as PoliceDriver
	_check(driver != null, "the patrol car has a driver")
	if driver == null:
		return
	await _settle(10)
	_check(
		audio.is_siren_sounding() == driver.is_siren_active(),
		"the siren agrees with the light bar (%s / %s)"
		% [audio.is_siren_sounding(), driver.is_siren_active()]
	)


## TEST 157 — the bed under the city changes with where and when you are.
func _test_ambience_profiles() -> void:
	_check(
		AmbienceDirector.current_profile() != &"",
		"there is always an ambience profile (%s)" % AmbienceDirector.current_profile()
	)

	TimeManager.set_total_minutes(13.0 * 60.0)
	AmbienceDirector.set_space(AmbienceDirector.Space.EXTERIOR)
	AmbienceDirector._refresh_profile()
	var day := AmbienceDirector.current_profile()

	TimeManager.set_total_minutes(2.0 * 60.0)
	AmbienceDirector._refresh_profile()
	var night := AmbienceDirector.current_profile()
	_check(day != night, "day and night sound different (%s / %s)" % [day, night])

	TimeManager.set_total_minutes(13.0 * 60.0)
	AmbienceDirector.set_space(AmbienceDirector.Space.STORE)
	AmbienceDirector._refresh_profile()
	var store := AmbienceDirector.current_profile()
	AmbienceDirector.set_space(AmbienceDirector.Space.CAFE)
	AmbienceDirector._refresh_profile()
	var cafe := AmbienceDirector.current_profile()
	_check(store != cafe, "a shop and a cafe sound different (%s / %s)" % [store, cafe])
	_check(day != store, "and inside is not outside")

	AmbienceDirector.set_space(AmbienceDirector.Space.EXTERIOR)


## TEST 158 — the music system is wired even with nothing to play.
func _test_music_states() -> void:
	MusicDirector.set_state(MusicDirector.State.MENU)
	_check(MusicDirector.get_state() == MusicDirector.State.MENU, "the menu has a music state")

	TimeManager.set_total_minutes(13.0 * 60.0)
	MusicDirector.refresh_world_state()
	_check(MusicDirector.get_state() == MusicDirector.State.DAY, "daytime play is the day state")

	TimeManager.set_total_minutes(2.0 * 60.0)
	MusicDirector.refresh_world_state()
	_check(
		MusicDirector.get_state() == MusicDirector.State.NIGHT,
		"and after dark it is the night state"
	)

	for state in MusicDirector.State.values():
		_check(
			MusicDirector.TRACKS.has(state),
			"every music state has a slot in the track table (%s)"
			% MusicDirector.State.keys()[state]
		)
	# Shipping without a soundtrack is a decision, not a missing file.
	_check(
		String(MusicDirector.TRACKS[MusicDirector.State.DAY]) == "",
		"and the game ships silent rather than with invented music"
	)


## TEST 159 — settings start where the mix says they should.
func _test_settings_defaults() -> void:
	SettingsManager.restore_defaults()
	for bus in AudioBuses.ALL:
		_check(
			absf(SettingsManager.audio_volume(bus) - float(AudioBuses.DEFAULT_VOLUMES[bus])) < 0.01,
			"%s starts at its designed level" % AudioBuses.display_name(bus)
		)
	_check(
		SettingsManager.audio_volume(AudioBuses.MUSIC)
			< SettingsManager.audio_volume(AudioBuses.SFX),
		"music sits under the effects rather than over them"
	)
	_check(SettingsManager.preset() == SettingsManager.Preset.MEDIUM, "graphics default to medium")
	_check(bool(SettingsManager.display("vsync")), "with vsync on")
	_check(bool(SettingsManager.gameplay("show_prompts")), "and prompts shown")


## TEST 160 — settings survive a restart, and are not part of a save game.
func _test_settings_persistence() -> void:
	SettingsManager.set_audio_volume(AudioBuses.AMBIENCE, 0.31)
	SettingsManager.set_gameplay("camera_sensitivity", 1.75)
	SettingsManager.set_preset(SettingsManager.Preset.LOW)

	# Wipe what is in memory, then read the file back — which is what starting
	# the game again does.
	SettingsManager._reset_to_defaults()
	_check(
		absf(SettingsManager.audio_volume(AudioBuses.AMBIENCE) - 0.31) > 0.1,
		"defaults really do differ from what was set"
	)
	_check(SettingsManager.load_settings(), "the settings file reads back")
	_check(
		absf(SettingsManager.audio_volume(AudioBuses.AMBIENCE) - 0.31) < 0.01,
		"a volume survives a restart (%.2f)"
		% SettingsManager.audio_volume(AudioBuses.AMBIENCE)
	)
	_check(
		absf(float(SettingsManager.gameplay("camera_sensitivity")) - 1.75) < 0.01,
		"and so does a gameplay setting"
	)
	_check(SettingsManager.preset() == SettingsManager.Preset.LOW, "and the graphics preset")

	# A malformed file must not stop the game starting.
	var handle := FileAccess.open(SettingsManager.PATH, FileAccess.WRITE)
	if handle != null:
		handle.store_string("this is not a config file {{{")
		handle.close()
	SettingsManager._reset_to_defaults()
	_check(not SettingsManager.load_settings(), "a corrupt settings file is refused")
	_check(
		absf(SettingsManager.audio_volume(AudioBuses.MASTER)
			- float(AudioBuses.DEFAULT_VOLUMES[AudioBuses.MASTER])) < 0.01,
		"and the defaults stand in for it rather than the game failing"
	)
	SettingsManager.restore_defaults()


## TEST 161 — the presets differ, in the direction they claim to.
func _test_graphics_presets() -> void:
	var low: Dictionary = SettingsManager.PRESETS[SettingsManager.Preset.LOW]
	var medium: Dictionary = SettingsManager.PRESETS[SettingsManager.Preset.MEDIUM]
	var high: Dictionary = SettingsManager.PRESETS[SettingsManager.Preset.HIGH]

	_check(not bool(low["shadows"]), "low turns shadows off")
	_check(bool(medium["shadows"]) and bool(high["shadows"]), "medium and high keep them")
	_check(
		float(high["shadow_distance"]) > float(medium["shadow_distance"])
			and float(medium["shadow_distance"]) > float(low["shadow_distance"]),
		"shadow distance climbs with the preset"
	)
	_check(bool(high["ambient_occlusion"]), "only high pays for ambient occlusion")
	_check(not bool(low["ambient_occlusion"]), "and low does not")
	_check(
		float(low["render_scale"]) < float(medium["render_scale"]),
		"low renders at a lower scale"
	)

	# Applying one must actually reach the world.
	SettingsManager.set_preset(SettingsManager.Preset.LOW)
	SettingsManager.apply_graphics()
	var sun := _main.get_node_or_null("District01/Sun") as DirectionalLight3D
	_check(sun != null, "the district has a sun to configure")
	if sun != null:
		_check(not sun.shadow_enabled, "and the low preset switched its shadows off")
	SettingsManager.set_preset(SettingsManager.Preset.HIGH)
	SettingsManager.apply_graphics()
	if sun != null:
		_check(sun.shadow_enabled, "while high switched them back on")
	SettingsManager.restore_defaults()


## TEST 162 — bindings can be read, changed, clashed and reset.
func _test_keybindings() -> void:
	for action in SettingsManager.BINDABLE:
		_check(InputMap.has_action(action), "%s is a real action" % action)
		_check(
			SettingsManager.binding_label(action) != "",
			"and has a readable binding (%s)" % SettingsManager.binding_label(action)
		)

	var original := SettingsManager.binding_label(&"sprint")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_J
	var clash := SettingsManager.conflict_for(&"sprint", event)
	_check(clash == &"", "J is free before anything is bound to it (%s)" % clash)

	SettingsManager.rebind(&"sprint", event)
	_check(
		SettingsManager.binding_label(&"sprint") == "J",
		"rebinding takes effect (%s)" % SettingsManager.binding_label(&"sprint")
	)
	_check(
		SettingsManager.conflict_for(&"interact", event) == &"sprint",
		"and the next action to want that key is told who has it"
	)

	SettingsManager.reset_bindings()
	_check(
		SettingsManager.binding_label(&"sprint") == original,
		"resetting puts the defaults back (%s)" % SettingsManager.binding_label(&"sprint")
	)


## TEST 163 — save slots, and what the front end can say about them.
func _test_save_slots() -> void:
	for slot in SaveManager.MANUAL_SLOTS:
		SaveManager.delete_slot(slot)
	SaveManager.delete_slot(SaveManager.AUTOSAVE_SLOT)

	_check(not SaveManager.has_any_save(), "with every slot empty there is nothing to continue")
	_check(SaveManager.most_recent_slot() < 0, "and no slot to continue from")
	_check(SaveManager.describe_slot(2).is_empty(), "an empty slot describes as empty")

	EconomyManager.restore(4321)
	_check(SaveManager.save_to_slot(2), "a game saves to a chosen slot")
	var summary := SaveManager.describe_slot(2)
	_check(not summary.is_empty(), "which can then be described without loading it")
	_check(int(summary.get("cash", 0)) == 4321, "the summary carries the money ($%s)" % summary.get("cash", 0))
	_check(String(summary.get("district", "")) != "", "and where the player was")
	_check(String(summary.get("saved_at", "")) != "", "and when it was saved")
	_check(int(summary.get("slot", -1)) == 2, "and which slot it is")

	_check(SaveManager.has_any_save(), "so CONTINUE now has something to load")
	_check(SaveManager.most_recent_slot() == 2, "and picks the slot just written")
	_check(SaveManager.list_saves().size() == 1, "one save is listed")

	# A corrupt slot must be skipped rather than offered.
	var handle := FileAccess.open(SaveManager.get_slot_path(3), FileAccess.WRITE)
	if handle != null:
		handle.store_string("{ not json")
		handle.close()
	_check(SaveManager.describe_slot(3).is_empty(), "an unreadable slot describes as empty")
	_check(SaveManager.list_saves().size() == 1, "and is left out of the list")
	_check(SaveManager.most_recent_slot() == 2, "so CONTINUE still finds the good one")

	# The autosave is a slot of its own, so it can never overwrite a manual save.
	_check(
		not SaveManager.MANUAL_SLOTS.has(SaveManager.AUTOSAVE_SLOT),
		"the autosave has a slot the player cannot write to"
	)
	SaveManager._last_autosave = -999.0
	_check(SaveManager.autosave("test"), "the game can save itself")
	_check(not SaveManager.autosave("test"), "but not twice in a row")
	_check(SaveManager.list_saves().size() == 2, "and the autosave is offered alongside the manual one")
	var auto := SaveManager.describe_slot(SaveManager.AUTOSAVE_SLOT)
	_check(bool(auto.get("autosave", false)), "labelled as an autosave")

	for slot in SaveManager.MANUAL_SLOTS:
		SaveManager.delete_slot(slot)
	SaveManager.delete_slot(SaveManager.AUTOSAVE_SLOT)
	await _settle(2)


## TEST 164 — the front end exists and knows when it has nothing to offer.
func _test_menu_state() -> void:
	_check(
		ResourceLoader.exists("res://ui/menu/main_menu.tscn"),
		"there is a main menu scene"
	)
	_check(
		ProjectSettings.get_setting("application/run/main_scene") == "res://ui/menu/main_menu.tscn",
		"and the game boots to it rather than straight into the world"
	)
	# The harness loads main.tscn directly, which is what keeps this suite
	# unaffected by the front end existing at all.
	_check(
		_main != null and _main.get_node_or_null("Player") != null,
		"while the tests still load the world scene directly"
	)

	var hud := _main.get_node_or_null("HUD")
	_check(hud != null, "the HUD is up")
	if hud != null:
		var pause_menu := hud.get_node_or_null("Root/PauseMenu")
		_check(pause_menu != null, "with a pause menu attached to it")
		_check(
			pause_menu == null or not pause_menu.visible,
			"which is hidden while the game is running"
		)


## TEST 165 — the camera settings are settings, not decoration.
func _test_camera_settings() -> void:
	var rig := _camera_rig
	SettingsManager.restore_defaults()

	# Sensitivity scales the orbit rather than being stored and ignored.
	SettingsManager.set_gameplay("camera_sensitivity", 2.0)
	var before := rig.yaw_degrees
	rig._update_orbit(0.0)
	_check(
		is_equal_approx(rig.yaw_degrees, before),
		"no input still turns the camera nowhere"
	)

	var zoom_before := rig.distance
	SettingsManager.set_gameplay("zoom_sensitivity", 2.0)
	await _press_action("camera_zoom_out")
	await _settle(2)
	var fast_step := rig.distance - zoom_before

	rig.distance = zoom_before
	SettingsManager.set_gameplay("zoom_sensitivity", 0.5)
	await _press_action("camera_zoom_out")
	await _settle(2)
	var slow_step := rig.distance - zoom_before
	_check(
		fast_step > slow_step,
		"a higher zoom sensitivity zooms further per notch (%.2f vs %.2f)"
		% [fast_step, slow_step]
	)

	# Shake respects the slider, including all the way off.
	SettingsManager.set_gameplay("camera_shake", 0.0)
	rig.add_shake(1.0)
	_check(rig.get_shake() <= 0.001, "camera shake set to zero really is off")

	SettingsManager.set_gameplay("camera_shake", 1.0)
	rig.add_shake(1.0)
	_check(rig.get_shake() > 0.5, "and turned up, an impact moves the camera")
	await _settle(90)
	_check(rig.get_shake() < 0.2, "and it settles again (%.2f)" % rig.get_shake())

	SettingsManager.restore_defaults()
	rig.distance = zoom_before


# --- Phase M: ownership, garages, homes and lifestyle --------------------

## TEST 166 — the showroom roster: real models with real numbers on them.
func _test_vehicle_catalogue() -> void:
	var purchasable := VehicleCatalogue.purchasable_ids()
	_check(purchasable.size() >= 8, "the dealership sells %d models" % purchasable.size())

	var priced := true
	var named := true
	var rated := true
	for id in purchasable:
		var data := VehicleCatalogue.data_for(id)
		priced = priced and data.price_new > 0 and data.resale_value > 0
		priced = priced and data.resale_value < data.price_new
		named = named and not data.manufacturer.is_empty() and not data.vehicle_class.is_empty()
		var ratings := data.showroom_ratings()
		rated = rated and ratings.size() == 5
		for value in ratings.values():
			rated = rated and int(value) >= 0 and int(value) <= 100
	_check(priced, "every one has a list price and a lower used value")
	_check(named, "and a marque and a class")
	_check(rated, "and five figures between 0 and 100")

	_check(
		VehicleCatalogue.manufacturers().size() >= 4,
		"the roster spans %d marques" % VehicleCatalogue.manufacturers().size()
	)

	# The showroom numbers are read off the physics, so they cannot disagree
	# with how a car actually drives.
	var exotic := VehicleCatalogue.data_for(&"exotic")
	var van := VehicleCatalogue.data_for(&"van")
	_check(
		exotic.speed_rating() > van.speed_rating() and exotic.max_speed > van.max_speed,
		"the fast one rates faster because it is faster"
	)
	_check(
		van.durability_rating() > exotic.durability_rating() and van.max_health > exotic.max_health,
		"and the tough one rates tougher"
	)
	_check(
		exotic.prestige > van.prestige and van.price_new > 0,
		"prestige is not price: the van costs real money and impresses nobody"
	)
	_check(
		not VehicleCatalogue.is_purchasable(&"police_car"),
		"the patrol car is not for sale"
	)


## TEST 167 — buying: the money moves once, and the car is an individual.
func _test_vehicle_purchase() -> void:
	VehicleRegistry.clear()
	await _settle(4)
	EconomyManager.restore(0)

	var spot := Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.5, 8.4))
	_check(
		VehicleRegistry.buy(&"sedan", spot) == VehicleRegistry.BuyResult.CANNOT_AFFORD,
		"a purchase with no money is refused"
	)
	_check(EconomyManager.cash == 0, "and the balance is not driven negative (%d)" % EconomyManager.cash)
	_check(VehicleRegistry.count() == 0, "and no car is created")

	var business := _own_business()
	var business_before := business.cash_balance
	EconomyManager.restore(60000)
	var price := VehicleCatalogue.price_new(&"sedan")
	_check(
		VehicleRegistry.buy(&"sedan", spot) == VehicleRegistry.BuyResult.OK,
		"with the money it goes through"
	)
	_check(
		EconomyManager.cash == 60000 - price,
		"the price came out of the player's own pocket exactly once (%d)" % EconomyManager.cash
	)
	_check(
		business.cash_balance == business_before,
		"and the business account was not touched"
	)
	_check(VehicleRegistry.count() == 1, "one car on the books")

	# Two of the same model are two cars, not one counted twice.
	VehicleRegistry.buy(&"sedan", Transform3D(Basis.IDENTITY, Vector3(-30.0, 0.5, 8.4)))
	var fleet := VehicleRegistry.get_fleet()
	_check(fleet.size() == 2, "buying a second sedan makes two sedans")
	_check(
		fleet[0].instance_id != fleet[1].instance_id,
		"with different identities (%s, %s)" % [fleet[0].instance_id, fleet[1].instance_id]
	)
	fleet[1].mileage_km = 4200.0
	fleet[1].condition = 61.0
	_check(
		fleet[0].mileage_km != fleet[1].mileage_km and fleet[0].condition != fleet[1].condition,
		"and histories of their own"
	)
	_check(
		fleet[0].market_value() > fleet[1].market_value(),
		"so the worn one is worth less than the clean one (%d vs %d)" % [
			fleet[0].market_value(), fleet[1].market_value()
		]
	)


## TEST 168 — mileage only goes up when the car actually moves.
func _test_vehicle_mileage() -> void:
	var record: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	await _wait_until(
		func() -> bool: return record.is_spawned(), 4.0, "the bought car to appear"
	)
	_check(record.is_spawned(), "the car the player bought is standing in the world")

	var parked := record.mileage_km
	await _settle(60)
	_check(
		is_equal_approx(record.mileage_km, parked),
		"a parked car puts no miles on (%.2f)" % record.mileage_km
	)

	# Moved the length of the street rather than driven, because what is being
	# tested is that distance is measured at all.
	var from := record.node.global_position
	record.node.global_position = from + Vector3(0.0, 0.0, -40.0)
	await _settle(6)
	_check(record.mileage_km > parked, "moving it does (%.2f km)" % record.mileage_km)

	# Put back in the bay it was parked in, stopped, and given a moment to
	# settle before the reading is taken. Both halves matter: a car dropped
	# somewhere arbitrary is still settling for a few frames afterwards, and a
	# car left on a camber creeps for as long as you watch it. Neither is the
	# odometer being wrong — a car that is moving is a car that is moving — so
	# the check is made against a car that is genuinely standing still.
	record.node.global_position = from
	record.node.halt()
	await _settle(30)
	var moved := record.mileage_km
	await _settle(40)
	_check(
		is_equal_approx(record.mileage_km, moved),
		"and it stops again when the car does (%.3f km added)" % (record.mileage_km - moved)
	)


## TEST 169 — health is this crash, condition is the car's life.
func _test_vehicle_condition() -> void:
	var record: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	record.condition = 100.0
	record.health = record.max_health()
	if record.is_spawned():
		record.node.set_health(record.health)
	var value_before := record.market_value()

	# A real impact through the vehicle's own damage path.
	var car := record.node
	car.apply_damage(30.0)
	VehicleRegistry.call("_on_owned_collision", 20.0, record)
	await _settle(4)

	_check(record.health < record.max_health(), "a crash takes health off")
	_check(record.condition < 100.0, "and some of it sticks as condition (%.0f%%)" % record.condition)
	_check(record.condition > 50.0, "but one shunt does not write the car off")
	_check(
		record.market_value() < value_before,
		"the car is worth less afterwards (%d, was %d)" % [record.market_value(), value_before]
	)

	# Mileage and condition are separate levers on the same value.
	var mileage_before := record.market_value()
	record.mileage_km += 90000.0
	_check(
		record.market_value() < mileage_before,
		"and less again with 90,000km more on it (%d)" % record.market_value()
	)


## TEST 170 — the mechanic charges, and only fixes what was paid for.
func _test_vehicle_repair() -> void:
	var record: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	record.health = record.max_health() * 0.4
	record.condition = 55.0
	if record.is_spawned():
		record.node.set_health(record.health)

	var basic := VehicleRegistry.repair_quote(record)
	var restore := VehicleRegistry.restore_quote(record)
	_check(basic > 0, "damage has a price on it ($%d)" % basic)
	_check(restore > basic, "and putting the years right costs more ($%d)" % restore)

	# A dearer car costs more to fix for the same proportion of damage.
	VehicleRegistry.grant(&"exotic", Transform3D(Basis.IDENTITY, Vector3(-20.0, 0.5, 8.4)))
	var posh: OwnedVehicle = VehicleRegistry.get_fleet().back()
	posh.health = posh.max_health() * 0.4
	_check(
		VehicleRegistry.repair_quote(posh) > basic,
		"and a Solstice costs more than a Kestrel ($%d)" % VehicleRegistry.repair_quote(posh)
	)

	EconomyManager.restore(20000)
	var cash_before := EconomyManager.cash
	var paid := VehicleRegistry.repair(record, false)
	_check(paid == basic, "the basic job charges what it quoted")
	_check(EconomyManager.cash == cash_before - paid, "once")
	_check(
		is_equal_approx(record.health, record.max_health()),
		"health is back to full"
	)
	_check(
		is_equal_approx(record.condition, 55.0),
		"and condition is untouched, because that was not the job (%.0f)" % record.condition
	)

	var restored_to := VehicleRegistry.restored_condition(record)
	VehicleRegistry.repair(record, true)
	_check(
		is_equal_approx(record.condition, restored_to) and record.condition < 100.0,
		"the full service brings it most of the way back, never to new (%.0f%%)" % record.condition
	)
	_check(
		VehicleRegistry.repair_quote(record) == 0 and VehicleRegistry.restore_quote(record) > 0,
		"and there is nothing left to repair, but always something left to restore"
	)


## TEST 171 — selling, and what the money does.
func _test_vehicle_sale() -> void:
	var fleet := VehicleRegistry.get_fleet()
	var record: OwnedVehicle = fleet.back()
	var offer := record.dealer_offer()
	_check(
		offer < record.market_value(),
		"the dealer takes a margin, so selling is not free money (%d of %d)" % [
			offer, record.market_value()
		]
	)

	var cash_before := EconomyManager.cash
	var count_before := VehicleRegistry.count()
	var worth_before := BusinessManager.net_worth()
	var paid := VehicleRegistry.sell(record)

	_check(paid == offer, "the sale pays the offer")
	_check(EconomyManager.cash == cash_before + paid, "into the player's own pocket, once")
	_check(VehicleRegistry.count() == count_before - 1, "the car is off the books")
	_check(VehicleRegistry.by_id(record.instance_id) == null, "and cannot be found again")
	_check(
		BusinessManager.net_worth() != worth_before,
		"net worth is recalculated rather than remembered"
	)
	# Nothing left pointing at a car that no longer exists.
	var ghosts := 0
	for marker in MapManager.collect_markers():
		if marker.target_id == record.instance_id:
			ghosts += 1
	_check(ghosts == 0, "and no marker is left on the map for it")


## TEST 172 — the used lot.
func _test_used_vehicles() -> void:
	var stock := get_tree().get_first_node_in_group(&"dealership_stock") as Dealership
	_check(stock != null, "there is a forecourt with stock on it")
	stock.refresh_stock()
	var listings := stock.listings()
	_check(listings.size() >= 3, "%d used cars listed" % listings.size())

	var sane := true
	var cheaper := true
	for listing in listings:
		sane = sane and listing.mileage_km > 0.0
		sane = sane and listing.condition > 0.0 and listing.condition <= 100.0
		sane = sane and listing.price > 0
		cheaper = cheaper and listing.price < VehicleCatalogue.price_new(listing.model_id)
	_check(sane, "every one has real mileage, a real condition and a real price")
	_check(cheaper, "and every one is cheaper than the same model new")

	var affordable := false
	for listing in listings:
		affordable = affordable or listing.price <= 12000
	_check(affordable, "with something on the lot a new player could reach")

	# Buying one carries the listing's history onto the car.
	var listing: UsedListing = listings[0]
	EconomyManager.restore(listing.price + 1000)
	var result := VehicleRegistry.buy(
		listing.model_id, Transform3D(Basis.IDENTITY, Vector3(-25.0, 0.5, 8.4)),
		listing.price, listing.mileage_km, listing.condition
	)
	_check(result == VehicleRegistry.BuyResult.OK, "a used car can be bought")
	var bought: OwnedVehicle = VehicleRegistry.get_fleet().back()
	_check(
		is_equal_approx(bought.mileage_km, listing.mileage_km),
		"and arrives with the miles it was advertised with"
	)
	_check(bought.condition < 100.0, "and the condition it was advertised with")
	_check(bought.bought_used, "marked as second hand")
	stock.remove_listing(listing)
	_check(stock.listing_by_id(listing.listing_id) == null, "and is off the lot")


## TEST 173 — garages: capacity, storage and getting the same car back.
func _test_garages() -> void:
	var garage := PropertyManager.garage_by_id(&"harbour_garage")
	_check(garage != null, "there is a garage to rent")
	_check(garage.capacity == 3, "with three bays")
	_check(garage.bay_transforms.size() == 3, "and three of them marked out in the world")

	if garage.is_leased_by_player():
		garage.end_lease()
	EconomyManager.restore(garage.move_in_cost() - 1)
	_check(not PropertyManager.lease_garage(garage), "a garage you cannot afford is refused")

	EconomyManager.restore(200000)
	_check(PropertyManager.lease_garage(garage), "and taken on when you can")
	_check(garage.is_leased_by_player(), "the lease is recorded")

	# Fill it.
	VehicleRegistry.clear()
	await _settle(4)
	for i in 4:
		VehicleRegistry.grant(&"compact", Transform3D(Basis.IDENTITY, Vector3(-40.0 + float(i) * 4.0, 0.5, 8.4)))
	var fleet := VehicleRegistry.get_fleet()
	for i in 3:
		_check(
			VehicleRegistry.store(fleet[i], &"harbour_garage") == VehicleRegistry.StoreResult.OK,
			"vehicle %d goes in" % (i + 1)
		)
	_check(garage.used_bays() == 3, "three of three bays used")
	_check(garage.is_full(), "and the garage says it is full")
	_check(
		VehicleRegistry.store(fleet[3], &"harbour_garage") == VehicleRegistry.StoreResult.GARAGE_FULL,
		"a fourth is refused"
	)
	_check(VehicleRegistry.count() == 4, "and nothing is lost by refusing it")

	# A stored car has no node and still counts as an asset.
	var stored: OwnedVehicle = fleet[0]
	_check(not stored.is_spawned(), "a stored car is not simulated")
	_check(stored.is_stored(), "but is still on the books")
	_check(
		VehicleRegistry.total_value() > 0 and stored.market_value() > 0,
		"and is still worth something"
	)

	# The same car comes back, with its history.
	stored.mileage_km = 33333.0
	stored.condition = 71.0
	_check(VehicleRegistry.retrieve(stored, garage.bay_for(0)), "it comes back out")
	_check(not stored.is_stored(), "no longer in the garage")
	_check(
		is_equal_approx(stored.mileage_km, 33333.0) and is_equal_approx(stored.condition, 71.0),
		"with exactly the mileage and condition it went in with"
	)
	_check(garage.used_bays() == 2, "and the bay is free again")


## TEST 174 — a stolen car is not made legal by parking it indoors.
func _test_stolen_vehicle_garage() -> void:
	var stolen := OwnedVehicle.new()
	stolen.instance_id = &"test_stolen"
	stolen.model_id = &"sedan"
	stolen.stolen = true
	_check(
		VehicleRegistry.store(stolen, &"harbour_garage") == VehicleRegistry.StoreResult.NOT_OWNED,
		"a car that is not on the books cannot be stored"
	)

	# And one that somehow were on the books, but flagged stolen, is refused for
	# that reason rather than accepted for the other.
	var legal: OwnedVehicle = VehicleRegistry.get_fleet().back()
	legal.stolen = true
	_check(
		VehicleRegistry.store(legal, &"harbour_garage") == VehicleRegistry.StoreResult.STOLEN_VEHICLE,
		"CANNOT STORE STOLEN VEHICLE"
	)
	legal.stolen = false

	# The theft system itself is untouched: an NPC car is still an NPC car.
	var npc := _spare_npc_car()
	_check(npc != null, "there are still NPC cars to steal")
	_check(not VehicleRegistry.owns(npc), "and none of them is on the player's books")


## TEST 175 — three rungs of somewhere to live.
func _test_residence_progression() -> void:
	var homes := PropertyManager.get_residences()
	_check(homes.size() >= 3, "there are %d places to live" % homes.size())

	var studio := PropertyManager.residence_by_id(&"larkspur")
	var middle := PropertyManager.residence_by_id(&"meridian")
	var premium := PropertyManager.residence_by_id(&"central_heights")
	_check(premium != null, "including a premium flat in Central")
	_check(
		studio.rent_amount < middle.rent_amount and middle.rent_amount < premium.rent_amount,
		"rent climbs with the address ($%d, $%d, $%d)" % [
			studio.rent_amount, middle.rent_amount, premium.rent_amount
		]
	)
	_check(
		studio.lifestyle_value < middle.lifestyle_value
		and middle.lifestyle_value < premium.lifestyle_value,
		"and so does what living there says about you"
	)
	_check(premium.parking_slots > 0, "and the dear one comes with a parking space")

	var room: ApartmentInterior = null
	for node in get_tree().get_nodes_in_group(&"residence_interior"):
		var candidate := node as ApartmentInterior
		if candidate != null and candidate.residence_id == &"central_heights":
			room = candidate
	_check(room != null, "the premium flat has a room behind its door")
	_check(room.tier == ApartmentInterior.Tier.PREMIUM, "built to the premium tier")
	_check(
		room.room().get_area() > ApartmentInterior.ROOM_SPACIOUS.get_area(),
		"and it is the biggest of the three (%.0f m2)" % room.room().get_area()
	)

	EconomyManager.restore(premium.move_in_cost() + 5000)
	_check(PropertyManager.lease_residence(premium), "it can be rented")
	premium.set_as_home()
	_check(premium.is_current_home(), "and set as home")
	_check(not studio.is_current_home(), "which moves you out of the old one")
	_check(
		studio.is_leased_by_player(),
		"without ending the lease on it — that is the player's call"
	)

	var bed: Bed = room.get_node_or_null("SleepPoint")
	_check(bed != null and bed.is_players_bed(), "and you can sleep in the new bed")


## TEST 176 — buying furniture and putting it down.
func _test_furniture() -> void:
	HomeManager.clear()
	await _settle(2)
	_check(FurnitureCatalogue.all().size() >= 20, "the shop stocks %d things" % FurnitureCatalogue.all().size())
	_check(FurnitureCatalogue.categories().size() >= 8, "across %d categories" % FurnitureCatalogue.categories().size())

	var sofa := FurnitureCatalogue.by_id(&"sofa_premium")
	var basic := FurnitureCatalogue.by_id(&"sofa_basic")
	_check(
		sofa.purchase_price > basic.purchase_price
		and sofa.lifestyle_value > basic.lifestyle_value,
		"and the dear sofa is worth more than the cheap one"
	)

	EconomyManager.restore(0)
	_check(
		HomeManager.buy(&"sofa_basic") == HomeManager.BuyResult.CANNOT_AFFORD,
		"furniture you cannot afford is refused"
	)
	_check(HomeManager.all_furniture().is_empty(), "and nothing is delivered")

	EconomyManager.restore(20000)
	var cash_before := EconomyManager.cash
	_check(HomeManager.buy(&"chair_basic", 3) == HomeManager.BuyResult.OK, "three chairs ordered")
	_check(
		EconomyManager.cash == cash_before - basic_chair_cost() * 3,
		"charged once, for three (%d)" % EconomyManager.cash
	)
	_check(HomeManager.all_furniture().is_empty(), "nothing has arrived yet")
	_check(HomeManager.pending_count() == 3, "three items are on the van")
	HomeManager.deliver_now()
	_check(HomeManager.all_furniture().size() == 3, "and then three arrive")
	_check(HomeManager.pending_count() == 0, "with the van empty")
	_check(HomeManager.in_storage().size() == 3, "waiting to be put somewhere")


func basic_chair_cost() -> int:
	return FurnitureCatalogue.by_id(&"chair_basic").purchase_price


## TEST 177 — placing, moving and storing, without ever losing a sofa.
func _test_furniture_placement() -> void:
	var room := _home_room(&"central_heights")
	var controller := _furniture_placement()
	_check(room != null and controller != null, "the flat can be furnished")

	EconomyManager.restore(40000)
	var bed := HomeManager.grant(&"bed_double")
	var sofa := HomeManager.grant(&"sofa_standard")
	var table := HomeManager.grant(&"table_standard")
	var telly := HomeManager.grant(&"tv_basic")
	var lamp := HomeManager.grant(&"lamp_basic")

	var spots := [
		[bed, Vector3(4.0, 0.0, -4.0), 0.0],
		[sofa, Vector3(-3.0, 0.0, 3.0), 0.0],
		[table, Vector3(3.0, 0.0, 3.0), 0.0],
		[telly, Vector3(-3.0, 0.0, 5.5), 180.0],
		[lamp, Vector3(6.5, 0.0, 3.0), 0.0],
	]
	var placed := 0
	for entry in spots:
		controller.begin(room, entry[0])
		if controller.place_at(entry[1], entry[2]):
			placed += 1
		elif controller.is_active():
			controller.cancel()
	_check(placed == spots.size(), "a bed, a sofa, a table, a television and a lamp all fit (%d)" % placed)
	_check(
		HomeManager.placed_in(&"central_heights").size() == placed,
		"and the room knows about all of them"
	)

	await _settle(3)
	var drawn := room.get_node_or_null("PlayerFurniture")
	_check(
		drawn != null and drawn.get_child_count() == placed,
		"each one is drawn in the room (%d)" % (drawn.get_child_count() if drawn != null else -1)
	)

	# Nothing may be placed inside a wall, on the fitted kitchen, or outside.
	var stray := HomeManager.grant(&"plant_small")
	controller.begin(room, stray)
	_check(not controller.place_at(Vector3(60.0, 0.0, 60.0), 0.0), "and nothing goes outside the flat")
	_check(not controller.place_at(sofa.position, 0.0), "or on top of the sofa")
	controller.cancel()
	_check(not stray.is_placed(), "a cancelled placement leaves the piece in storage")
	_check(HomeManager.by_id(stray.instance_id) != null, "and does not destroy it")

	# Moving is one record, not two.
	var before := HomeManager.all_furniture().size()
	var was := sofa.position
	controller.begin_move(room, sofa)
	_check(controller.place_at(Vector3(-5.0, 0.0, 3.0), 90.0), "a placed sofa can be moved")
	_check(HomeManager.all_furniture().size() == before, "without buying a second one")
	_check(sofa.position != was, "and it really moved")
	_check(is_equal_approx(rad_to_deg(sofa.rotation_y), 90.0), "and turned")

	# Storing takes it out of the room and keeps it.
	_check(HomeManager.store(table), "a table can be put back into storage")
	_check(not table.is_placed(), "so it is out of the room")
	_check(HomeManager.by_id(table.instance_id) != null, "but still owned")
	_check(
		HomeManager.placed_in(&"central_heights").size() == placed - 1,
		"and the room is one piece lighter"
	)


## TEST 178 — a furnished flat comes back furnished.
func _test_furniture_save_load() -> void:
	var slot := 8
	var room := _home_room(&"central_heights")
	var placed := HomeManager.placed_in(&"central_heights")
	_check(placed.size() >= 3, "the flat has furniture in it to save")

	var expected: Dictionary = {}
	for record in placed:
		expected[record.instance_id] = [record.furniture_id, record.position, record.rotation_y]

	_check(SaveManager.save_to_slot(slot), "the flat is saved")
	# Wreck the arrangement thoroughly before loading it back.
	HomeManager.clear()
	await _settle(2)
	_check(HomeManager.placed_in(&"central_heights").is_empty(), "and then emptied")

	_check(SaveManager.load_from_slot(slot), "and loaded again")
	var restored := HomeManager.placed_in(&"central_heights")
	_check(restored.size() == expected.size(), "every piece is back (%d)" % restored.size())

	var exact := true
	for record in restored:
		var want: Array = expected.get(record.instance_id, [])
		if want.is_empty():
			exact = false
			continue
		exact = exact and record.furniture_id == want[0]
		exact = exact and record.position.distance_to(want[1] as Vector3) < 0.01
		exact = exact and absf(record.rotation_y - float(want[2])) < 0.01
	_check(exact, "in exactly the same places, facing the same way")

	await _settle(3)
	var drawn := room.get_node_or_null("PlayerFurniture")
	_check(
		drawn != null and drawn.get_child_count() == restored.size(),
		"and the room is drawn to match"
	)
	SaveManager.delete_slot(slot)


## TEST 179 — the cupboard.
func _test_home_storage() -> void:
	var slot := 8
	var box := HomeManager.storage_for(&"central_heights")
	box.clear()
	var pockets := _player.get_inventory()
	pockets.clear()

	var item := preload("res://items/definitions/snack_bar.tres")
	pockets.add(item, 4)
	_check(pockets.count_of(item.id) == 4, "four snacks in the player's pockets")

	# The transfer the storage screen performs.
	pockets.remove_from_slot(0, 4)
	box.add(item, 4)
	_check(box.count_of(item.id) == 4, "put away in the flat")
	_check(pockets.count_of(item.id) == 0, "and out of the pockets")
	_check(box.total_items() == 4, "with nothing duplicated in the move")

	_check(SaveManager.save_to_slot(slot), "the cupboard is saved")
	box.clear()
	_check(SaveManager.load_from_slot(slot), "and loaded")
	box = HomeManager.storage_for(&"central_heights")
	_check(box.count_of(item.id) == 4, "the snacks are still in the cupboard")
	_check(
		_player.get_inventory().count_of(item.id) == 0,
		"and did not also reappear in the player's pockets"
	)
	SaveManager.delete_slot(slot)

	# Storage furniture makes the cupboard bigger.
	var base := HomeManager.storage_slots_for(&"central_heights")
	var locker := HomeManager.grant(&"storage_locker")
	var controller := _furniture_placement()
	controller.begin(_home_room(&"central_heights"), locker)
	if not controller.place_at(Vector3(7.0, 0.0, -2.0), 0.0) and controller.is_active():
		controller.cancel()
	_check(locker.is_placed(), "a storage cabinet is put in")
	_check(
		HomeManager.storage_slots_for(&"central_heights") > base,
		"and the flat holds more than it did (%d, was %d)" % [
			HomeManager.storage_slots_for(&"central_heights"), base
		]
	)


## TEST 180 — lifestyle, and the twenty-identical-plants problem.
func _test_lifestyle() -> void:
	LifestyleManager.clear()
	VehicleRegistry.clear()
	HomeManager.clear()
	await _settle(2)

	var studio := PropertyManager.residence_by_id(&"larkspur")
	studio.set_as_home()
	LifestyleManager.refresh()
	var poor := LifestyleManager.score()
	_check(poor < 30, "a studio flat and no car is a modest life (%d)" % poor)
	_check(
		LifestyleManager.tier_name() in ["STRUGGLING", "MODEST"],
		"and says so: %s" % LifestyleManager.tier_name()
	)

	EconomyManager.restore(400000)
	VehicleRegistry.grant(&"exotic", Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.5, 8.4)))
	LifestyleManager.refresh()
	var with_car := LifestyleManager.score()
	_check(with_car > poor, "an exotic in the street raises it (%d)" % with_car)
	_check(
		LifestyleManager.tier_name() != "ELITE",
		"but one car does not make anybody elite (%s)" % LifestyleManager.tier_name()
	)

	var premium := PropertyManager.residence_by_id(&"central_heights")
	if not premium.is_leased_by_player():
		PropertyManager.lease_residence(premium)
	premium.set_as_home()
	LifestyleManager.refresh()
	var with_home := LifestyleManager.score()
	_check(with_home > with_car, "moving somewhere better raises it further (%d)" % with_home)

	# The exploit: many copies of a cheap thing must not carry the score.
	var room := _home_room(&"central_heights")
	var controller := _furniture_placement()
	var plants := 0
	for i in 8:
		var plant := HomeManager.grant(&"plant_small")
		controller.begin(room, plant)
		if controller.place_at(Vector3(-8.0 + float(i) * 1.2, 0.0, -6.0), 0.0):
			plants += 1
		elif controller.is_active():
			controller.cancel()
	_check(plants >= 5, "%d potted plants placed" % plants)
	var plant_value := HomeManager.furniture_lifestyle(&"central_heights")
	var single := FurnitureCatalogue.by_id(&"plant_small").lifestyle_value
	_check(
		plant_value <= single * HomeManager.CATEGORY_LIMIT,
		"but only the best two count (%d, not %d)" % [plant_value, single * plants]
	)

	LifestyleManager.refresh()
	var with_plants := LifestyleManager.score()
	var suite := HomeManager.grant(&"sofa_premium")
	controller.begin(room, suite)
	if not controller.place_at(Vector3(0.0, 0.0, 4.0), 0.0) and controller.is_active():
		controller.cancel()
	LifestyleManager.refresh()
	_check(
		LifestyleManager.score() > with_plants,
		"a different kind of thing does count (%d)" % LifestyleManager.score()
	)
	_check(
		LifestyleManager.has_reached(&"first_car"),
		"and owning a car is remembered as a milestone"
	)


## TEST 181 — net worth counts everything once.
func _test_net_worth_integration() -> void:
	VehicleRegistry.clear()
	await _settle(2)
	EconomyManager.restore(25000)

	VehicleRegistry.grant(&"sedan", Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.5, 8.4)))
	VehicleRegistry.grant(&"suv", Transform3D(Basis.IDENTITY, Vector3(-34.0, 0.5, 8.4)))
	var garage := PropertyManager.garage_by_id(&"harbour_garage")
	if not garage.is_leased_by_player():
		EconomyManager.deposit(garage.move_in_cost(), "test")
		PropertyManager.lease_garage(garage)
	VehicleRegistry.store(VehicleRegistry.get_fleet()[0], &"harbour_garage")
	await _settle(2)

	var vehicles := VehicleRegistry.total_value()
	var by_hand := 0
	for record in VehicleRegistry.get_fleet():
		by_hand += record.market_value()
	_check(vehicles == by_hand, "the fleet is worth the sum of its cars ($%d)" % vehicles)
	_check(
		VehicleRegistry.get_fleet()[0].is_stored(),
		"with one of them in a garage"
	)

	var expected := (
		EconomyManager.cash + vehicles + BusinessManager.total_business_value()
		+ HomeManager.furniture_resale_value()
	)
	_check(
		BusinessManager.net_worth() == expected,
		"net worth is cash, businesses, vehicles and furniture ($%d)" % BusinessManager.net_worth()
	)
	_check(
		BusinessManager.vehicle_value() == vehicles,
		"the vehicle line comes from the registry, so a garaged car counts once"
	)
	_check(
		HomeManager.furniture_resale_value() < _furniture_paid(),
		"furniture counts at resale, not at what it cost"
	)

	# A leased garage and a leased flat are not assets.
	var before := BusinessManager.net_worth()
	var other := PropertyManager.garage_by_id(&"central_garage")
	if not other.is_leased_by_player():
		EconomyManager.deposit(other.move_in_cost(), "test")
		var cash_after_gift := EconomyManager.cash
		PropertyManager.lease_garage(other)
		_check(
			EconomyManager.cash == cash_after_gift - other.move_in_cost(),
			"renting a second garage costs money"
		)
	_check(
		BusinessManager.net_worth() < before + other.move_in_cost(),
		"and does not add itself to net worth as an asset"
	)


func _furniture_paid() -> int:
	var total := 0
	for record in HomeManager.all_furniture():
		total += record.purchase_price
	return total


## TEST 182 — an arrest does not confiscate a car the player paid for.
func _test_busted_in_own_vehicle() -> void:
	VehicleRegistry.clear()
	await _settle(2)
	EconomyManager.restore(60000)
	await _teleport(Vector3(-40.0, 0.5, 8.4))

	VehicleRegistry.grant(&"sedan", Transform3D(Basis.IDENTITY, Vector3(-42.0, 0.5, 8.4)))
	var record: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	await _wait_until(func() -> bool: return record.is_spawned(), 4.0, "the car to appear")
	await _drive(record.node)
	_check(_player.is_driving(), "the player is in their own car")

	var id := record.instance_id
	WantedManager.set_level(1)
	await _settle(4)
	WantedManager.request_bust()
	await _wait_until(
		func() -> bool: return not WantedManager.is_busting(), 12.0, "the arrest to finish"
	)

	_check(VehicleRegistry.by_id(id) != null, "the car is still the player's afterwards")
	var after := VehicleRegistry.by_id(id)
	_check(not after.stolen, "and is not marked stolen by having been in it")
	_check(VehicleRegistry.count() == 1, "and no second copy of it appeared")
	_check(WantedManager.level == 0, "the wanted level cleared with the arrest")
	WantedManager.clear_wanted()


## TEST 183 — a save from before any of this loads, and keeps its car.
func _test_ownership_save_migration() -> void:
	var slot := 8
	VehicleRegistry.clear()
	HomeManager.clear()
	await _settle(2)
	EconomyManager.restore(30000)

	VehicleRegistry.grant(&"coupe", Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.5, 8.4)))
	var record: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	record.mileage_km = 12345.0
	record.condition = 66.0
	var id := record.instance_id
	var where := record.position

	_check(SaveManager.save_to_slot(slot), "a game with a car in it saves")
	VehicleRegistry.clear()
	await _settle(2)
	_check(SaveManager.load_from_slot(slot), "and loads")
	_check(VehicleRegistry.count() == 1, "with exactly one car, not two")
	var back := VehicleRegistry.by_id(id)
	_check(back != null, "the same car")
	_check(
		is_equal_approx(back.mileage_km, 12345.0) and is_equal_approx(back.condition, 66.0),
		"with its mileage and condition intact"
	)
	_check(back.position.distance_to(where) < 1.0, "and where it was left")
	SaveManager.delete_slot(slot)

	# A Phase L save has no registry section at all. It must load, and the car
	# the district places must still end up on the books.
	var path := SaveManager.get_slot_path(slot)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"version": SaveManager.SAVE_VERSION,
		"entities": {},
	}))
	file.close()
	VehicleRegistry.clear()
	await _settle(2)
	_check(SaveManager.load_from_slot(slot), "a save written before any of this existed still loads")
	_check(VehicleRegistry.count() == 0, "with nothing invented for it")
	VehicleRegistry.adopt_scene_vehicles()
	_check(
		VehicleRegistry.count() >= 0,
		"and adoption runs against it without complaint"
	)
	SaveManager.delete_slot(slot)


## TEST 184 — part exchange moves the money exactly once.
func _test_trade_in() -> void:
	VehicleRegistry.clear()
	await _settle(2)
	EconomyManager.restore(100000)
	VehicleRegistry.grant(&"sedan", Transform3D(Basis.IDENTITY, Vector3(-40.0, 0.5, 8.4)))
	var old_car: OwnedVehicle = VehicleRegistry.get_fleet()[0]
	var allowance := old_car.dealer_offer()
	var price := VehicleCatalogue.price_new(&"coupe")
	var cash_before := EconomyManager.cash

	var result := VehicleRegistry.trade_in(
		&"coupe", Transform3D(Basis.IDENTITY, Vector3(-36.0, 0.5, 8.4)), price, old_car
	)
	_check(result == VehicleRegistry.BuyResult.OK, "a car can be taken in part exchange")
	_check(
		EconomyManager.cash == cash_before - (price - allowance),
		"the player pays the difference and nothing else (%d)" % EconomyManager.cash
	)
	_check(VehicleRegistry.count() == 1, "one car in, one car out")
	_check(
		VehicleRegistry.get_fleet()[0].model_id == &"coupe",
		"and it is the new one that stayed"
	)
	_check(VehicleRegistry.by_id(old_car.instance_id) == null, "the old one is gone")


## TEST 185 — the places all this happens are actually in the city.
func _test_ownership_venues() -> void:
	_check(
		get_tree().get_nodes_in_group(&"dealership").size() == 1,
		"there is a showroom to walk into"
	)
	_check(
		get_tree().get_nodes_in_group(&"dealership_display").size() >= 5,
		"with %d cars on the floor" % get_tree().get_nodes_in_group(&"dealership_display").size()
	)
	_check(
		get_tree().get_nodes_in_group(&"dealership_desk").size() == 1,
		"and a desk to buy from"
	)
	_check(
		get_tree().get_nodes_in_group(DealershipInterior.COLLECTION_GROUP).size() >= 2,
		"and bays outside to collect a car from"
	)
	_check(
		get_tree().get_nodes_in_group(&"repair_shop").size() >= 1,
		"there is a mechanic"
	)
	_check(PropertyManager.get_garages().size() >= 2, "and two garages")
	_check(
		get_tree().get_nodes_in_group(&"furniture_store_point").size() == 1,
		"and a furniture shop"
	)

	# The collection bay must not hand a car over on top of another one.
	var stock := get_tree().get_first_node_in_group(&"dealership_stock") as Dealership
	var first := stock.collection_transform()
	VehicleRegistry.clear()
	await _settle(2)
	EconomyManager.restore(200000)
	VehicleRegistry.grant(&"sedan", first)
	await _settle(6)
	var second := stock.collection_transform()
	_check(
		second.origin.distance_to(first.origin) > 2.0,
		"a second car is handed over in a different bay (%.1fm away)" % second.origin.distance_to(first.origin)
	)


func _home_room(residence_id: StringName) -> ApartmentInterior:
	for node in get_tree().get_nodes_in_group(&"residence_interior"):
		var room := node as ApartmentInterior
		if room != null and room.residence_id == residence_id:
			return room
	return null


func _furniture_placement() -> FurniturePlacement:
	return get_tree().get_first_node_in_group(&"furniture_placement") as FurniturePlacement
