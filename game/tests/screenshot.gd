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
##             central_business, city_empire, cross_district_chase, central_night,
##             pause_menu, loaded_game, dealer_exterior, showroom,
##             vehicle_detail, vehicle_compare, used_listing,
##             purchase_confirm, player_vehicle, my_vehicles, repair_shop,
##             repair_screen, garage_exterior, garage_stored,
##             premium_apartment, furniture_store, furniture_buying,
##             furniture_placing, furnished_apartment, profile, night_premium,
##             for_sale_board, property_sale_screen, mortgage_offer,
##             property_purchase_confirm, dockside_court, dockside_court_let,
##             property_portfolio, property_detail, letting_screen,
##             tenant_applicants, tenant_signed, mortgage_tab, income_tab,
##             renovation_screen, property_sale_confirm, property_map,
##             property_profile, owned_shop_unit, multi_unit_detail,
##             property_empire, restaurant_exterior, restaurant_empty,
##             restaurant_furnished, restaurant_kitchen, restaurant_customers,
##             restaurant_cook, restaurant_server, restaurant_dashboard,
##             gym_exterior, gym_furnished, gym_customers, gym_management,
##             club_exterior_night, club_interior, club_queue, club_operating,
##             brand_screen, company_dashboard, company_staff, multi_shift,
##             manager_permissions, bottleneck_report, company_portfolio,
##             warehouse_exterior, warehouse_interior, warehouse_inventory,
##             bulk_order, logistics_dashboard, branch_stock_request,
##             shipment_queued, company_van, delivery_driver,
##             warehouse_delivery, branch_transfer, company_vehicles,
##             delivery_route, logistics_bottlenecks, backup_pool,
##             manager_backup, finance_forecast, business_warning,
##             wages_overdue, rent_overdue, business_critical, branch_closure,
##             liquidation_screen, foreclosure_warning, foreclosure_cure,
##             company_logistics, eviction_notice, eviction_cured, wanted_one,
##             wanted_two, wanted_three, wanted_four, wanted_five,
##             police_search, search_map, known_vehicle, switched_vehicle,
##             foot_pursuit, roadblock_night, wanted_cleared, fence_exterior,
##             fence_screen, chop_shop, chop_delivery, criminal_contact,
##             job_offer, criminal_reputation, underworld_jobs,
##             business_while_wanted, arrest_summary, criminal_record,
##             active_case, court_reminder, civic_court, case_outcome,
##             record_tier, premium_refused, financing_refused, scandal_notice,
##             company_after_scandal, underworld_overview, contact_list,
##             contact_trust, broker_board, goods_request, vehicle_request,
##             higher_tier_job, career_progress, income_split,
##             business_with_court_pending
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

		"police_officer", "police_close", "business_exterior", "hero":
			await _phase_k_scenario(main, scenario)

		"pause_menu", "loaded_game":
			await _phase_l_scenario(main, scenario)

		"dealer_exterior", "showroom", "vehicle_detail", "vehicle_compare", \
		"used_listing", "purchase_confirm", "player_vehicle", "my_vehicles", \
		"repair_shop", "repair_screen", "garage_exterior", "garage_stored", \
		"premium_apartment", "furniture_store", "furniture_buying", \
		"furniture_placing", "furnished_apartment", "profile", "night_premium":
			await _phase_m_scenario(main, scenario)

		"for_sale_board", "property_sale_screen", "mortgage_offer", \
		"property_purchase_confirm", "dockside_court", "dockside_court_let", \
		"property_portfolio", "property_detail", "letting_screen", \
		"tenant_applicants", "tenant_signed", "mortgage_tab", "income_tab", \
		"renovation_screen", "property_sale_confirm", "property_map", \
		"property_profile", "owned_shop_unit", "multi_unit_detail", \
		"property_empire":
			await _phase_n_scenario(main, scenario)

		"restaurant_exterior", "restaurant_empty", "restaurant_furnished", \
		"restaurant_kitchen", "restaurant_customers", "restaurant_cook", \
		"restaurant_server", "restaurant_dashboard", "gym_exterior", \
		"gym_furnished", "gym_customers", "gym_management", "club_exterior_night", \
		"club_interior", "club_queue", "club_operating", "brand_screen", \
		"company_dashboard", "company_staff", "multi_shift", \
		"manager_permissions", "bottleneck_report", "company_portfolio":
			await _phase_o_scenario(main, scenario)

		"warehouse_exterior", "warehouse_interior", "warehouse_inventory", \
		"bulk_order", "logistics_dashboard", "branch_stock_request", \
		"shipment_queued", "company_van", "delivery_driver", \
		"warehouse_delivery", "branch_transfer", "company_vehicles", \
		"delivery_route", "logistics_bottlenecks", "backup_pool", \
		"manager_backup", "finance_forecast", "business_warning", \
		"wages_overdue", "rent_overdue", "business_critical", "branch_closure", \
		"liquidation_screen", "foreclosure_warning", "foreclosure_cure", \
		"company_logistics":
			await _phase_p_scenario(main, scenario)

		"eviction_notice", "eviction_cured", "wanted_one", "wanted_two", \
		"wanted_three", "wanted_four", "wanted_five", "police_search", \
		"search_map", "known_vehicle", "switched_vehicle", "foot_pursuit", \
		"roadblock_night", "wanted_cleared", "fence_exterior", "fence_screen", \
		"chop_shop", "chop_delivery", "criminal_contact", "job_offer", \
		"criminal_reputation", "underworld_jobs", "business_while_wanted":
			await _phase_q_scenario(main, scenario)

		"arrest_summary", "criminal_record", "active_case", "court_reminder", \
		"civic_court", "case_outcome", "record_tier", "premium_refused", \
		"financing_refused", "scandal_notice", "company_after_scandal", \
		"underworld_overview", "contact_list", "contact_trust", \
		"broker_board", "goods_request", "vehicle_request", "higher_tier_job", \
		"career_progress", "income_split", "business_with_court_pending":
			await _phase_r_scenario(main, scenario)

		"goals_legal", "goals_criminal", "journey", "statistics", "guide_screen", \
		"objective_banner", "onboarding_step", "venue_diner", "venue_cafe", \
		"venue_gym", "vending_machine", "diner_street", "plaza_life", \
		"park_life", "rush_hour", "quiet_hour", "night_machine", \
		"map_goal_filters", "tired_player":
			await _phase_s_scenario(main, scenario)

		"characters":
			# The five people the game draws, lined up at reading distance:
			# player, civilian, office worker, retail worker, officer.
			await _character_lineup(main)

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


# --- Phase K: the presentation shots ---------------------------------------

## The shots the visual pass exists for. Each drives the real systems: the
## officer is a real PoliceOfficer, the light bar is the pursuit light bar, and
## the shop exterior is the sign the business actually puts up.
## Phase M: what the money buys — the showroom, the garage, the flat and the
## screens that describe them.
func _phase_m_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	EconomyManager.restore(340000)

	match scenario:
		"dealer_exterior":
			player.global_position = Vector3(-88.0, 0.5, District02.RIVERSIDE_DR_Z - 8.0)
			await _wait(40)

		"showroom", "vehicle_detail", "vehicle_compare", "used_listing", \
		"purchase_confirm", "my_vehicles":
			await _enter_showroom(main, player)
			await _wait(20)
			match scenario:
				"vehicle_detail":
					_hud_screen(hud, "VehicleDetailPanel").open(&"coupe")
				"vehicle_compare":
					var panel: Node = _hud_screen(hud, "DealershipPanel")
					panel.open(DealershipPanel.Tab.NEW)
					panel.call("_toggle_compare", &"compact")
					panel.call("_toggle_compare", &"exotic")
				"used_listing":
					_hud_screen(hud, "DealershipPanel").open(DealershipPanel.Tab.USED)
				"purchase_confirm":
					var buy: Node = _hud_screen(hud, "VehicleDetailPanel")
					buy.open(&"luxury_sedan")
					await _wait(6)
					buy.call("_on_buy_pressed")
				"my_vehicles":
					_give_fleet()
					await _wait(10)
					_hud_screen(hud, "DealershipPanel").open(DealershipPanel.Tab.MINE)
			await _wait(14)

		"player_vehicle":
			# Bought, collected and standing in the bay it was handed over in.
			var stock := _dealership_stock()
			VehicleRegistry.buy(&"performance_sedan", stock.collection_transform())
			await _wait(20)
			var bought: OwnedVehicle = VehicleRegistry.get_fleet().back()
			player.global_position = bought.position + Vector3(0.0, 0.1, 5.0)
			await _wait(30)

		"repair_shop", "repair_screen":
			var shop: RepairShop = get_tree().get_first_node_in_group(&"repair_shop")
			var record := VehicleRegistry.grant(
				&"coupe", Transform3D(Basis(Vector3.UP, PI), shop.service_point)
			)
			record.health = record.max_health() * 0.32
			record.condition = 46.0
			record.mileage_km = 61250.0
			player.global_position = shop.service_point + Vector3(0.0, 0.1, 4.4)
			await _wait(30)
			if record.is_spawned():
				record.node.set_health(record.health)
			if scenario == "repair_screen":
				_hud_screen(hud, "RepairPanel").open(shop)
				await _wait(14)

		"garage_exterior", "garage_stored":
			var garage: GarageProperty = PropertyManager.garage_by_id(&"harbour_garage")
			PropertyManager.lease_garage(garage)
			if scenario == "garage_stored":
				for model_id: StringName in [&"coupe", &"suv", &"hatchback"]:
					var car := VehicleRegistry.grant(
						model_id, Transform3D(Basis.IDENTITY, garage.global_position + Vector3(0.0, 0.4, 6.0))
					)
					VehicleRegistry.store(car, &"harbour_garage")
			player.global_position = garage.global_position + Vector3(0.0, 0.1, 9.0)
			await _wait(40)

		"premium_apartment", "furnished_apartment", "furniture_placing", "profile":
			await _move_into_premium(main, player)
			if scenario == "furnished_apartment" or scenario == "profile":
				await _furnish_premium(main)
			await _wait(20)
			if scenario == "furniture_placing":
				var room := _premium_room()
				var controller: FurniturePlacement = get_tree().get_first_node_in_group(
					&"furniture_placement"
				)
				var piece := HomeManager.grant(&"sofa_premium")
				controller.begin(room, piece)
				# Held over a legal spot rather than set down, which is what the
				# mode looks like in the player's hands.
				controller.call("place_preview_at", Vector3(0.0, 0.0, 3.5), 0.0)
			if scenario == "profile":
				_give_fleet()
				await _wait(10)
				_hud_screen(hud, "ProfilePanel").open()
			await _wait(14)

		"furniture_store", "furniture_buying":
			await _move_into_premium(main, player)
			await _enter_furniture_store(main, player)
			await _wait(20)
			if scenario == "furniture_buying":
				_hud_screen(hud, "FurnitureStorePanel").open()
			await _wait(14)

		"night_premium":
			# The player has to be standing there for the car to exist at all:
			# an owned car more than a hundred metres away is a record with no
			# node, which is the whole point of the registry.
			# A clear northbound run up Centre Boulevard, well short of the next
			# junction, so the car has room to get to speed.
			var start := Vector3(District02.LANE_OFFSET, 0.4, -190.0)
			player.global_position = start + Vector3(3.0, 0.1, 0.0)
			await _wait(20)
			var car := VehicleRegistry.grant(&"luxury_sedan", Transform3D(Basis.IDENTITY, start))
			await _wait(20)
			if car.is_spawned():
				car.node.halt()
				player.global_position = car.node.global_position + Vector3(2.0, 0.5, 0.0)
				await _wait(10)
				car.node.enter(player)
				# The throttle is held down through the capture, the same way the
				# other driving shots do it: set_ai_input drives an AI car, and
				# this one has the player in it.
				# Held through the capture, so the speedometer and the speed zoom
				# are both showing real values when the frame is taken.
				Input.action_press("move_forward")
				await _wait(58)


## The showroom, through its own door.
func _enter_showroom(main: Node, player: Node3D) -> void:
	var district: Node = main.get_node("District02")
	var door: Portal = district.get_node("Interactables/NorthlineMotors")
	player.global_position = Vector3(-88.0, 0.5, District02.RIVERSIDE_DR_Z - 6.0)
	await _wait(10)
	door.interact(player)
	await _wait(20)
	# Stood in the middle of the floor, so the whole room composes.
	player.global_position = Vector3(1000.0, 0.5, 2450.0)
	await _wait(10)


func _enter_furniture_store(main: Node, player: Node3D) -> void:
	var district: Node = main.get_node("District02")
	var door: Portal = district.get_node("Interactables/KingstonFurnishings")
	player.global_position = Vector3(74.0, 0.5, District02.KINGSTON_RD_Z - 6.0)
	await _wait(10)
	door.interact(player)
	await _wait(20)
	player.global_position += Vector3(0.0, 0.0, -1.6)


## Rents the premium flat, makes it home and walks in.
func _move_into_premium(main: Node, player: Node3D) -> void:
	var home := PropertyManager.residence_by_id(&"central_heights")
	if not home.is_leased_by_player():
		PropertyManager.lease_residence(home)
	home.set_as_home()
	await _wait(6)
	var district: Node = main.get_node("District02")
	var door: ResidenceProperty = district.get_node("Interactables/CentralHeights")
	player.global_position = Vector3(88.0, 0.5, District02.RIVERSIDE_DR_Z - 6.0)
	await _wait(8)
	door.interact(player)
	await _wait(20)


## A room the player has furnished, laid out the way somebody would.
func _furnish_premium(main: Node) -> void:
	var room := _premium_room()
	var controller: FurniturePlacement = get_tree().get_first_node_in_group(&"furniture_placement")
	if room == null or controller == null:
		return
	var plan: Array = [
		[&"bed_kingsize", Vector3(5.0, 0.0, -4.5), 0.0],
		[&"sofa_premium", Vector3(-3.5, 0.0, 3.0), 0.0],
		[&"table_premium", Vector3(3.5, 0.0, 3.0), 0.0],
		[&"chair_premium", Vector3(6.5, 0.0, 3.0), 90.0],
		[&"tv_premium", Vector3(-3.5, 0.0, 6.0), 180.0],
		[&"lamp_premium", Vector3(-7.0, 0.0, 3.0), 0.0],
		[&"rug_premium", Vector3(-3.5, 0.0, 1.0), 0.0],
		[&"plant_large", Vector3(7.5, 0.0, 0.0), 0.0],
		[&"dresser_premium", Vector3(8.0, 0.0, -2.0), 90.0],
		[&"storage_wardrobe", Vector3(-8.0, 0.0, -4.0), 0.0],
	]
	for entry in plan:
		var piece := HomeManager.grant(entry[0])
		controller.begin(room, piece)
		if not controller.place_at(entry[1], entry[2]) and controller.is_active():
			controller.cancel()
	await _wait(6)


func _premium_room() -> ApartmentInterior:
	for node in get_tree().get_nodes_in_group(&"residence_interior"):
		var room := node as ApartmentInterior
		if room != null and room.residence_id == &"central_heights":
			return room
	return null


func _dealership_stock() -> Dealership:
	return get_tree().get_first_node_in_group(&"dealership_stock") as Dealership


## A fleet worth photographing: something cheap, something quick, something dear.
func _give_fleet() -> void:
	var spot := Vector3(-40.0, 0.4, 8.4)
	for i in 3:
		var model_id: StringName = [&"compact", &"coupe", &"luxury_suv"][i]
		var car := VehicleRegistry.grant(
			model_id, Transform3D(Basis.IDENTITY, spot + Vector3(float(i) * 6.0, 0.0, 0.0)),
			float(i) * 18000.0, 100.0 - float(i) * 17.0
		)
		car.mileage_km = float(i) * 18000.0


func _hud_screen(hud: Node, screen_name: String) -> Node:
	var root := hud.get_node_or_null("Root/%s" % screen_name)
	return root if root != null else hud.get_node_or_null(screen_name)


## Phase S: the city as somewhere to live in, and the progress screens.
func _phase_s_scenario(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	var player: Node3D = GameManager.player
	EconomyManager.restore(48000)
	await _wait(60)

	match scenario:
		"goals_legal", "goals_criminal", "journey", "statistics", "guide_screen":
			await _s_progress(main, scenario)
		"objective_banner":
			await _s_banner(main, false)
		"onboarding_step":
			await _s_banner(main, true)
		"venue_diner", "venue_cafe", "venue_gym":
			await _s_venue(main, scenario)
		"vending_machine", "night_machine":
			await _s_machine(main, scenario)
		"diner_street":
			# The Galley Diner from the pavement, at lunchtime.
			await _s_crowd_at(Vector3(20.5, 0.5, -21.0), 13)
		"plaza_life":
			await _s_crowd_at(Vector3(-30.0, 0.5, -181.0), 15)
		"park_life":
			await _s_crowd_at(Vector3(-25.0, 0.5, 38.0), 15)
		"rush_hour":
			await _s_traffic_at(8)
		"quiet_hour":
			await _s_traffic_at(3)
		"map_goal_filters":
			await _s_map_goals(main)
		"tired_player":
			await _s_tired(main)

	await _wait(10)


## A player with a life behind them, so the progress screens have something on
## them. Everything here goes through the real path.
func _s_history() -> void:
	Progression.clear()
	LifeStats.clear()
	Onboarding.clear()
	Onboarding.skip()
	LifeStats.add(&"shifts_worked", 21)
	LifeStats.add(&"shift_income", 3255)
	# Through the real ledger, so lifetime income is lifetime income and the
	# goals that watch it read what they should.
	EconomyManager.deposit(
		3255, "Wages", EconomyManager.Source.LEGAL, EconomyManager.Stream.EMPLOYMENT
	)
	LifeStats.add(&"deliveries_made", 46)
	LifeStats.add(&"meals_eaten", 38)
	LifeStats.add(&"coffees_drunk", 22)
	LifeStats.add(&"nights_slept", 17)
	LifeStats.add(&"gym_sessions", 6)
	LifeStats.add(&"days_lived", 17)
	LifeStats.add(&"vehicles_bought", 2)
	LifeStats.add_distance(214000.0)
	UnderworldDebug.set_reputation(48)
	UnderworldDebug.unlock_all_contacts()
	for i in 4:
		Underworld.career.credit(IllegalJobData.Objective.VEHICLE_DELIVERY)
	Progression.evaluate()


func _s_progress(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	await _s_history()
	var screen: Node = _hud_screen(hud, "ProgressPanel")
	var page := ProgressPanel.Page.GOALS
	match scenario:
		"journey":
			page = ProgressPanel.Page.JOURNAL
		"statistics":
			page = ProgressPanel.Page.STATISTICS
		"guide_screen":
			page = ProgressPanel.Page.GUIDE
	screen.call("open", page)
	if scenario == "goals_criminal":
		# The criminal ladder is the same screen with the other track showing.
		screen.set("_track", Goal.Track.CRIMINAL)
		screen.call("show_tab", ProgressPanel.Page.GOALS)
	await _wait(16)


## The corner list: the guide while it is running, the goals after.
func _s_banner(main: Node, guide: bool) -> void:
	var player: Node3D = GameManager.player
	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	if guide:
		Progression.clear()
		LifeStats.clear()
		Onboarding.clear()
	else:
		await _s_history()
		Progression.clear_pins()
		Progression.pin(&"first_vehicle")
	await _wait(40)


## Ordering at a counter, at the counter itself.
func _s_venue(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	var player: Node3D = GameManager.player
	var stats = player.call("get_stats")
	stats.restore_values(72.0, 44.0, 28.0)
	var point: ServicePoint = null
	for node in main.find_children("*", "ServicePoint", true, false):
		if scenario == "venue_cafe" and node.venue_kind == ServiceCatalogue.Kind.CAFE:
			point = node
		elif scenario == "venue_diner" and node.venue_kind == ServiceCatalogue.Kind.DINER:
			point = node
	if scenario == "venue_gym":
		# No gym stands on the street yet; the one the player can use is their
		# own, so this is the counter a gym owner sees.
		point = ServicePoint.new()
		point.venue_name = "Ironworks Gym"
		point.venue_kind = ServiceCatalogue.Kind.GYM
		point.opens_hour = 6
		point.closes_hour = 22
		main.add_child(point)
	if point == null:
		return
	player.global_position = point.global_position + Vector3(0.0, -0.7, 2.5)
	await _wait(30)
	_hud_screen(hud, "VenuePanel").call("open", point, player)
	await _wait(14)


func _s_machine(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	var player: Node3D = GameManager.player
	var machines: Array = main.find_children("*", "VendingMachine", true, false)
	if machines.is_empty():
		return
	var machine: Node3D = machines[0]
	player.global_position = machine.global_position + Vector3(0.0, 0.4, 2.6)
	await _wait(40)
	if scenario == "vending_machine":
		_hud_screen(hud, "ShopPanel").call("open", machine, player)
		await _wait(14)


## Somewhere the routines send people, with the player looking at it.
func _s_crowd_at(where: Vector3, wait_hours: int) -> void:
	var player: Node3D = GameManager.player
	player.global_position = where
	# Wind to the hour the place is busiest rather than waiting for it.
	var target := float(TimeManager.day_index * 1440 + wait_hours * 60)
	if target > TimeManager.total_minutes:
		TimeManager.set_total_minutes(target)
	# Long enough for people to actually walk there. A shorter wait shows the
	# moment they set off, which looks like an empty park.
	await _wait(320)


func _s_traffic_at(hour: int) -> void:
	var player: Node3D = GameManager.player
	player.global_position = Vector3(-6.0, 0.5, District01.MAIN_ST_Z + 2.0)
	var target := float(TimeManager.day_index * 1440 + hour * 60)
	if target < TimeManager.total_minutes:
		target += 1440.0
	TimeManager.set_total_minutes(target)
	await _wait(180)


func _s_map_goals(main: Node) -> void:
	var hud: Node = main.get_node("HUD")
	await _s_history()
	Progression.clear_pins()
	Progression.pin(&"first_vehicle")
	for goal in Progression.suggestions():
		if goal.metric == &"contacts_known" and Progression.pin(goal.goal_id):
			break
	_hud_screen(hud, "CityMap").call("open")
	await _wait(16)


## Hunger and tiredness where they are actually read: the bars on the HUD.
func _s_tired(main: Node) -> void:
	var player: Node3D = GameManager.player
	var stats = player.call("get_stats")
	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	stats.restore_values(58.0, 11.0, 14.0)
	await _wait(40)


## Phase L: the front end seen from inside a running game.
func _phase_l_scenario(_main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)

	if scenario == "loaded_game":
		# The HUD as it looks on arriving from the menu: a real save, restored
		# through the same path CONTINUE uses, rather than a fresh world
		# photographed and called a load.
		EconomyManager.restore(6400)
		SaveManager.save_to_slot(1)
		await _wait(4)
		EconomyManager.restore(50)
		SaveManager.load_from_slot(1)
		await _wait(40)
		return

	SaveManager.save_to_slot(1)
	await _wait(4)
	GameManager.toggle_pause()
	await _wait(20)


func _phase_k_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player

	match scenario:
		"police_officer":
			# One officer on an empty pavement, close enough to read the
			# uniform, the vest and the cap badge.
			for npc in get_tree().get_nodes_in_group(&"pedestrian"):
				if npc is Node3D:
					npc.global_position = Vector3(400.0, 0.0, 400.0)
				npc.process_mode = Node.PROCESS_MODE_DISABLED
			_traffic_manager().set_active(false)
			_traffic_manager().clear()
			await _wait(6)
			var officers: Array = get_tree().get_nodes_in_group(&"police").filter(
				func(u: Node) -> bool: return u is PoliceOfficer
			)
			var spot := Vector3(-12.0, 0.4, District01.MAIN_ST_Z - 9.4)
			for i in officers.size():
				var unit: Node3D = officers[i]
				unit.process_mode = Node.PROCESS_MODE_INHERIT
				unit.global_position = spot + Vector3(2.6 * float(i), 0.0, 0.0)
				if unit.has_method("wait_for"):
					unit.call("wait_for", 600.0)
			player.global_position = spot + Vector3(-2.8, 0.1, 0.0)
			await _wait(30)
			for i in officers.size():
				(officers[i] as Node3D).get_node("BodyPivot").rotation.y = PI
			player.get_node("BodyPivot").rotation.y = PI
			await _wait(20)

		"police_close":
			# A patrol car with its bar lit, which means putting a real unit on
			# a real call rather than turning the lights on by hand.
			await _crime_scenario(main, "pursuit", false)
			var cars: Array = get_tree().get_nodes_in_group(&"police_car")
			if not cars.is_empty():
				player.global_position = (
					(cars[0] as Node3D).global_position + Vector3(0.0, 0.5, 6.5)
				)
			await _wait(40)

		"business_exterior":
			# Stood outside a shop the player owns, with the sign lit and the
			# street alive around it.
			EconomyManager.restore(40000)
			_open_shop_at(main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market")
			await _wait(10)
			player.global_position = Vector3(-20.0, 0.5, -9.4)
			await _wait(60)

		"hero":
			# The store-page shot: the boulevard junction from the corner, with
			# traffic running, the crowd out and the afternoon sun low enough to
			# throw shadows down the street.
			_traffic_manager().set_active(true)
			_traffic_manager().prime()
			player.global_position = Vector3(-9.6, 0.5, 14.0)
			await _wait(360)


# --- Phase K: the people --------------------------------------------------

## Five figures side by side on an empty stretch of pavement. Built through the
## real NpcWalker so what the shot shows is what the crowd is made of.
func _character_lineup(main: Node) -> void:
	var player: Node3D = GameManager.player
	# Clear the street, so the only people in frame are the ones being shown.
	for npc in get_tree().get_nodes_in_group(&"pedestrian") + get_tree().get_nodes_in_group(&"police"):
		if npc is Node3D:
			npc.global_position = Vector3(400.0, 0.0, 400.0)
		npc.process_mode = Node.PROCESS_MODE_DISABLED
	_traffic_manager().set_active(false)
	_traffic_manager().clear()
	await _wait(6)

	var line_z := District01.MAIN_ST_Z - 9.4
	player.global_position = Vector3(-12.0, 0.5, line_z)
	await _wait(6)

	var kinds := [
		[CharacterLook.Category.CIVILIAN, Color(0.545, 0.373, 0.345)],
		[CharacterLook.Category.OFFICE, Color(0.208, 0.231, 0.290)],
		[CharacterLook.Category.RETAIL, Color(0.278, 0.435, 0.478)],
		[CharacterLook.Category.POLICE, Color(0.129, 0.169, 0.239)],
	]
	for i in kinds.size():
		var figure: Pedestrian = load("res://npc/pedestrian.tscn").instantiate()
		figure.name = "Lineup%d" % i
		figure.appearance_seed = 4100 + i * 37
		figure.look_category = kinds[i][0]
		figure.body_color = kinds[i][1]
		figure.accent_color = (
			Color(0.914, 0.792, 0.290) if kinds[i][0] == CharacterLook.Category.POLICE
			else Color(0.902, 0.902, 0.886)
		)
		figure.casts_shadow = true
		figure.wanders = false
		main.add_child(figure)
		figure.global_position = Vector3(-9.0 + float(i) * 2.6, 0.4, line_z)
		figure.wait_for(600.0)
	await _wait(30)
	# Everybody turned to face the camera rather than wherever they spawned.
	for i in kinds.size():
		var figure: Node3D = main.get_node("Lineup%d" % i)
		figure.get_node("BodyPivot").rotation.y = PI
	player.get_node("BodyPivot").rotation.y = PI
	await _wait(20)


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


# --- Phase N: the property ladder ----------------------------------------

## The landlord shots. Everything here starts from a cleared portfolio and a
## known amount of money, because a shot of the portfolio screen is only worth
## taking if what is on it was put there deliberately.
func _phase_n_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	RealEstate.clear()
	await _wait(4)
	EconomyManager.restore(650000)
	for listing in RealEstate.listings():
		RealEstate.discover(listing.property_id)
	# Long enough for the money toast that setting the cash throws up to fade,
	# so it is not sitting over every property shot.
	await _wait(150)

	match scenario:
		"for_sale_board":
			await _stand_at_board(player, &"larkspur", 3.2, 2.8)

		"property_sale_screen", "mortgage_offer", "property_purchase_confirm":
			var address := &"larkspur" if scenario == "property_sale_screen" else &"unit_main_18"
			await _stand_at_board(player, address, 4.0)
			var panel: Node = _hud_screen(hud, "PropertySalePanel")
			panel.call("open", address)
			await _wait(8)
			if scenario == "mortgage_offer":
				panel.set("_showing_mortgage", true)
				panel.call("_rebuild")
			elif scenario == "property_purchase_confirm":
				panel.call("_confirm_cash", RealEstate.listing_for(address))
			await _wait(12)

		"dockside_court", "dockside_court_let":
			if scenario == "dockside_court_let":
				RealEstate.buy_with_cash(&"dockside_block")
				_let_units(&"dockside_block", 3)
			# On the pavement across the frontage rather than out in the road:
			# the block fronts Main Street, and its own forward points at the
			# kerb. Stepped west along it as well, because the block is the
			# last address before the district edge and standing level with its
			# middle puts the edge of the world in frame.
			await _stand_at_board(player, &"dockside_block", 7.0, 9.0)

		"property_portfolio", "mortgage_tab", "income_tab", "property_empire":
			_build_a_portfolio()
			# Two of the four flats let, so the books have rent in them as well
			# as debt and the income tab is not a column of zeroes.
			_let_units(&"dockside_block", 2)
			await _wait(10)
			if scenario == "property_empire":
				_hud_screen(hud, "EmpireDashboard").call("open")
				await _wait(14)
				return
			var books: Node = _hud_screen(hud, "RealEstatePanel")
			books.call("open")
			await _wait(6)
			books.set("_tab", (
				RealEstatePanel.Tab.MORTGAGES if scenario == "mortgage_tab"
				else RealEstatePanel.Tab.INCOME if scenario == "income_tab"
				else RealEstatePanel.Tab.PORTFOLIO
			))
			books.set("_focus_id", &"")
			books.call("_rebuild")
			await _wait(12)

		"property_detail", "multi_unit_detail", "tenant_signed":
			_build_a_portfolio()
			if scenario == "tenant_signed":
				_let_units(&"larkspur", 1)
			if scenario == "multi_unit_detail":
				_let_units(&"dockside_block", 2)
			await _wait(10)
			var books: Node = _hud_screen(hud, "RealEstatePanel")
			books.call(
				"open",
				&"dockside_block" if scenario == "multi_unit_detail" else &"larkspur"
			)
			await _wait(14)

		"letting_screen", "tenant_applicants":
			RealEstate.buy_with_cash(&"larkspur")
			var flat := RealEstate.record_for(&"larkspur")
			flat.use = PropertyRecord.Use.VACANT
			if scenario == "tenant_applicants":
				RealEstate.list_for_rent(flat, RealEstate.unit_market_rent(flat), -1)
				_invite_applicants(flat, 2)
			await _wait(10)
			_hud_screen(hud, "RealEstatePanel").call("open", &"larkspur")
			await _wait(14)

		"renovation_screen", "property_sale_confirm":
			RealEstate.buy_with_cash(&"larkspur")
			var worn := RealEstate.record_for(&"larkspur")
			worn.use = PropertyRecord.Use.VACANT
			worn.condition = 42.0
			await _wait(10)
			var books: Node = _hud_screen(hud, "RealEstatePanel")
			books.call("open", &"larkspur")
			await _wait(10)
			if scenario == "property_sale_confirm":
				books.call("_confirm_sale", worn)
			else:
				# The works are the last section on the screen, which is where
				# they belong and not where a shot of them wants them.
				await _scroll_to_bottom(books)
			await _wait(12)

		"owned_shop_unit":
			var unit := PropertyManager.by_id(&"unit_main_18")
			if unit.is_vacant():
				PropertyManager.lease(unit)
			if BusinessManager.business_for_property(&"unit_main_18") == null:
				BusinessManager.create_business("Main Street Market", &"convenience_store", unit)
			EconomyManager.restore(650000)
			RealEstate.buy_with_cash(&"unit_main_18")
			await _wait(10)
			_hud_screen(hud, "RealEstatePanel").call("open", &"unit_main_18")
			await _wait(14)

		"property_map":
			_build_a_portfolio()
			_let_units(&"dockside_block", 2)
			await _wait(10)
			_hud_screen(hud, "CityMap").call("open")
			await _wait(16)

		"property_profile":
			_build_a_portfolio()
			_let_units(&"dockside_block", 3)
			await _wait(10)
			_hud_screen(hud, "ProfilePanel").call("open")
			await _wait(14)


## Winds a screen down to its last section. The screenshot tool has no mouse
## wheel, and several of these lists say the interesting part last — the
## discount under a bulk order, the last row of a property's figures.
func _scroll_to_bottom(panel: Node) -> void:
	var scroll: ScrollContainer = null
	var list: Node = panel.get("_list")
	if list != null:
		scroll = (list as Node).get_parent() as ScrollContainer
	if scroll == null:
		scroll = _find_scroll(panel)
	if scroll == null:
		return
	await _wait(4)
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _wait(6)


func _find_scroll(node: Node) -> ScrollContainer:
	for child in node.get_children():
		if child is ScrollContainer:
			return child
		var deeper := _find_scroll(child)
		if deeper != null:
			return deeper
	return null


## Puts the player on the pavement in front of an address, facing its door.
## `sideways` steps along the frontage, which is where the FOR SALE board is.
func _stand_at_board(
	player: Node3D, property_id: StringName, back_off: float, sideways: float = 0.0
) -> void:
	var door := RealEstate.door_for(property_id)
	if door == null:
		return
	var facing := door.global_transform.basis.z
	var beside := door.global_transform.basis.x
	player.global_position = (
		door.global_position + facing * back_off + beside * sideways + Vector3(0.0, 0.4, 0.0)
	)
	await _wait(24)


## A flat owned outright and a block on a mortgage: enough for the portfolio to
## have something to say about equity, debt and occupancy at once.
func _build_a_portfolio() -> void:
	RealEstate.buy_with_cash(&"larkspur")
	RealEstate.buy_with_mortgage(&"dockside_block")


func _let_units(property_id: StringName, count: int) -> void:
	var record := RealEstate.record_for(property_id)
	if record == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260820
	var rent := RealEstate.unit_market_rent(record)
	for i in count:
		var unit_index := i if record.is_multi_unit() else -1
		if not record.is_multi_unit():
			record.use = PropertyRecord.Use.VACANT
		RealEstate.list_for_rent(record, rent, unit_index)
		var tenant := TenantData.generate(
			TenantData.Kind.COMMERCIAL if record.kind == PropertyRecord.Kind.COMMERCIAL
			else TenantData.Kind.RESIDENTIAL,
			rent, rng, 3000 + i
		)
		tenant.reliability = 88
		RealEstate.accept_tenant(record, tenant, unit_index)


## Applicants waiting on the player's answer, without waiting the days out.
func _invite_applicants(record: PropertyRecord, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 606060
	var waiting: Array = []
	for i in count:
		waiting.append(TenantData.generate(
			TenantData.Kind.RESIDENTIAL, record.asking_rent, rng, 4000 + i
		))
	RealEstate._candidates[RealEstate._candidate_key(record.property_id, -1)] = waiting


# --- Phase O: the company -------------------------------------------------

## The three new business types, built through the real systems, and the
## screens that manage them. Nothing here pokes a number into a business that
## the player could not have put there themselves.
func _phase_o_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	EconomyManager.restore(500000)
	await _wait(90)

	match scenario:
		"restaurant_exterior":
			await _stand_outside(player, &"unit_plaza_07", 7.0)

		"restaurant_empty":
			var empty := PropertyManager.by_id(&"unit_plaza_07")
			PropertyManager.lease(empty)
			var bare: RetailUnit = main.get_node("Interiors/CentralPlazaUnit")
			bare.ensure_built()
			await _stand_in(player, bare, Vector3(0.0, 0.0, 2.0))

		"restaurant_furnished", "restaurant_kitchen", "restaurant_customers", \
		"restaurant_cook", "restaurant_server", "restaurant_dashboard":
			var diner := _open_restaurant(main)
			var room: RetailUnit = main.get_node("Interiors/CentralPlazaUnit")
			if scenario == "restaurant_kitchen":
				await _stand_in(player, room, Vector3(0.0, 0.0, room.storage_area.get_center().y))
			elif scenario == "restaurant_dashboard":
				await _stand_in(player, room, Vector3(0.0, 0.0, 2.0))
				var dashboard: Node = main.get_node("HUD/BusinessDashboard")
				dashboard.call("open", diner)
				dashboard.call("show_tab", 0)
				await _wait(10)
			else:
				await _stand_in(player, room, Vector3(0.0, 0.0, 3.4))
				await _fill_the_floor(room, 5, 900)

		"gym_exterior":
			await _stand_outside(player, &"unit_dock_09", 8.0)

		"gym_furnished", "gym_customers", "gym_management":
			var gym := _open_gym(main)
			var floor_room: RetailUnit = main.get_node("Interiors/DockRoadUnit")
			if scenario == "gym_management":
				CompanyDebug.set_cleanliness(gym, 38.0)
				await _stand_in(player, floor_room, Vector3(0.0, 0.0, 2.0))
				var manager: Node = _hud_screen(hud, "ManagerPanel")
				manager.call("open", gym)
				await _wait(10)
			else:
				await _stand_in(player, floor_room, Vector3(-4.0, 0.0, 2.5))
				if scenario == "gym_customers":
					await _fill_the_floor(floor_room, 6, 420)

		"club_exterior_night":
			await _stand_outside(player, &"unit_vault_03", 8.0)

		"club_interior", "club_queue", "club_operating":
			var club := _open_club(main)
			var venue: RetailUnit = main.get_node("Interiors/VaultStreetUnit")
			await _stand_in(player, venue, Vector3(-4.5, 0.0, 2.0))
			if scenario != "club_interior":
				await _fill_the_floor(venue, 9, 520)

		"brand_screen", "company_dashboard", "company_staff", "multi_shift", \
		"manager_permissions", "bottleneck_report", "company_portfolio":
			await _build_a_company(main, scenario)

	await _wait(10)


## Everything the company screens need behind them: a chain of two shops, a
## restaurant, a gym and a venue, all trading.
func _build_a_company(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	CompanyManager.set_company_name("Noel Group")

	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	var brand := CompanyManager.brand_for_business(market)
	var branch_door := PropertyManager.by_id(&"unit_central_88")
	PropertyManager.lease(branch_door)
	var branch := CompanyManager.found_business("", &"convenience_store", branch_door, brand)
	if branch != null:
		BusinessManager.deposit_to_business(branch, 4000)
		var branch_unit: RetailUnit = main.get_node("Interiors/CentralBoulevardUnit")
		branch_unit.ensure_built()
		CompanyDebug.fit_out(branch, branch_unit)
		CompanyDebug.stock_up(branch, 40)
		CompanyDebug.hire(branch, EmployeeData.Role.CASHIER, 0.7)
		branch.manual_override = BusinessInstance.Override.FORCE_OPEN

	var diner := _open_restaurant(main)
	var gym := _open_gym(main)
	var club := _open_club(main)

	# A day's trade behind the figures, so nothing on the screens reads zero.
	for business in [market, branch, diner, gym]:
		if business == null:
			continue
		for i in 5:
			BusinessManager.simulate_hour_now(business, 12)
	if club != null:
		for i in 4:
			BusinessManager.simulate_hour_now(club, 23)

	if scenario == "bottleneck_report" and diner != null:
		# One cook against a full dining room: the problem the report is for.
		# Everything is restocked first — a day's trading empties the store
		# rooms, and a report where every line reads LOW STOCK shows the one
		# problem this frame is not about.
		for business in [market, branch, diner, gym, club]:
			if business != null:
				CompanyDebug.stock_up(business, 90)
				CompanyDebug.set_cleanliness(business, 78.0)
		var cooks := diner.rostered_all(EmployeeData.Role.COOK, 12)
		while cooks.size() > 1:
			diner.fire(cooks.pop_back().employee_id)
		for i in 4:
			if BusinessManager.buy_equipment(diner, &"dining_table") == BusinessManager.PurchaseResult.OK \
					and BusinessManager.consume_unplaced(diner, &"dining_table"):
				diner.place_equipment(&"dining_table", Vector3(float(i) * 2.2 - 4.0, 0.0, 3.2), 0.0)
		# A lunch rush, so the kitchen is visibly the thing that cannot cope.
		CompanyDebug.force_demand(diner, 4.0)
		for i in 2:
			BusinessManager.simulate_hour_now(diner, 12)
		CompanyDebug.stock_up(diner, 90)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)

	var company: Node = _hud_screen(hud, "CompanyDashboard")
	match scenario:
		"brand_screen":
			company.call("open", CompanyDashboard.Page.BRANDS)
		"company_staff":
			company.call("open", CompanyDashboard.Page.EMPLOYEES)
		"bottleneck_report":
			company.call("open", CompanyDashboard.Page.OPERATIONS)
		"company_portfolio":
			company.call("open", CompanyDashboard.Page.LOCATIONS)
		"multi_shift":
			var rota: Node = _hud_screen(hud, "StaffSchedulePanel")
			var worker := _two_shift_worker(diner)
			if worker != null:
				rota.call("open", worker)
		"manager_permissions":
			var manager: Node = _hud_screen(hud, "ManagerPanel")
			if diner != null:
				if not diner.has_manager():
					CompanyDebug.hire(diner, EmployeeData.Role.MANAGER, 0.8)
				diner.auto_open = true
				diner.auto_order = true
				diner.auto_order_budget = 1500
				manager.call("open", diner)
		_:
			company.call("open", CompanyDashboard.Page.OVERVIEW)
	await _wait(12)


## Somebody working lunch and dinner, so the rota screen has a week to show.
func _two_shift_worker(diner: BusinessInstance) -> EmployeeData:
	if diner == null:
		return null
	var worker := CompanyDebug.hire(diner, EmployeeData.Role.SERVER, 0.7)
	if worker == null:
		return null
	worker.clear_shifts()
	worker.set_weekly_shifts([
		ShiftSlot.make(11, 15, EmployeeData.Role.SERVER, ShiftSlot.EVERY_DAY, diner.business_id),
		ShiftSlot.make(18, 23, EmployeeData.Role.SERVER, ShiftSlot.EVERY_DAY, diner.business_id),
		ShiftSlot.make(10, 15, EmployeeData.Role.SERVER, 5, diner.business_id),
	])
	return worker


func _open_restaurant(main: Node) -> BusinessInstance:
	var diner := CompanyDebug.stand_up(
		&"unit_plaza_07", &"restaurant", "Anchor Kitchen", get_tree(), 30000
	)
	if diner == null:
		return null
	# Six tables rather than the three a bare fit-out gives, so the dining room
	# reads as a dining room and there is somewhere for everybody to sit.
	for i in 3:
		if BusinessManager.buy_equipment(diner, &"dining_table") == BusinessManager.PurchaseResult.OK \
				and BusinessManager.consume_unplaced(diner, &"dining_table"):
			diner.place_equipment(
				&"dining_table", Vector3(3.6, 0.0, 1.0 + float(i) * 2.6), 0.0
			)
	diner.manual_override = BusinessInstance.Override.FORCE_OPEN
	diner.set_open(true)
	# A lunchtime already behind it, so the sign over the door reads as a
	# restaurant that has been trading rather than one that just unlocked.
	for i in 3:
		BusinessManager.simulate_hour_now(diner, 12)
	CompanyDebug.stock_up(diner, 90)
	var room: RetailUnit = main.get_node("Interiors/CentralPlazaUnit")
	room.rebuild_equipment()
	return diner


func _open_gym(main: Node) -> BusinessInstance:
	var gym := CompanyDebug.stand_up(
		&"unit_dock_09", &"gym", "Dock Road Fitness", get_tree(), 30000
	)
	if gym != null:
		CompanyDebug.hire(gym, EmployeeData.Role.CLEANER, 0.8)
		gym.manual_override = BusinessInstance.Override.FORCE_OPEN
		gym.set_open(true)
		for i in 4:
			BusinessManager.simulate_hour_now(gym, 18)
		var room: RetailUnit = main.get_node("Interiors/DockRoadUnit")
		room.rebuild_equipment()
	return gym


func _open_club(main: Node) -> BusinessInstance:
	var club := CompanyDebug.stand_up(
		&"unit_vault_03", &"nightclub", "Vault", get_tree(), 45000
	)
	if club != null:
		club.manual_override = BusinessInstance.Override.FORCE_OPEN
		club.set_open(true)
		for i in 3:
			BusinessManager.simulate_hour_now(club, 23)
		CompanyDebug.stock_up(club, 90)
		var room: RetailUnit = main.get_node("Interiors/VaultStreetUnit")
		room.rebuild_equipment()
	return club


## Drops the player on the pavement outside a unit's door, facing it.
func _stand_outside(player: Node3D, property_id: StringName, back_off: float) -> void:
	var door := PropertyManager.by_id(property_id)
	if door == null:
		return
	var facing := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(door.sign_yaw))
	player.global_position = door.global_position + facing * back_off + Vector3(0.0, 0.6, 0.0)
	await _wait(45)


## Puts the player inside a unit and waits for the room to settle.
func _stand_in(player: Node3D, unit: RetailUnit, offset: Vector3) -> void:
	unit.ensure_built()
	player.global_position = unit.global_position + offset + Vector3(0.0, 0.6, 0.0)
	await _wait(60)
	unit.call("_refresh_staff")
	await _wait(30)


## Spawns customers and lets them find their way to a table, a machine or the
## floor. They are the real customer AI, so the frames show what the game does.
func _fill_the_floor(unit: RetailUnit, count: int, settle_frames: int) -> void:
	var spawner := unit.get_spawner()
	if spawner == null:
		return
	for i in count:
		spawner.spawn_customer_now()
		await _wait(14)
	await _wait(settle_frames)


# --- Phase P ---------------------------------------------------------------

## The logistics and failure frames. Built on the same company the Phase O
## shots use, because the whole point of Phase P is that these systems sit on
## top of a business that already works rather than beside it.
func _phase_p_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	EconomyManager.restore(500000)
	await _wait(90)

	if scenario == "warehouse_exterior":
		# Long enough for the money popup from the restore above to fade, so
		# the frame is the goods shed rather than a green number over it.
		await _wait(150)
		# Stood on the depot side of Dock Road rather than the park side: the
		# door sits on the far pavement, and backing off from it puts the
		# camera in a hedge with the building behind it.
		var gate := PropertyManager.by_id(&"warehouse_dock_14")
		if gate != null:
			player.global_position = gate.global_position + Vector3(0.0, 0.6, -6.5)
		await _wait(60)
		return

	# Everything else needs a company behind it.
	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	BusinessManager.deposit_to_business(market, 90000)
	var depot: RetailUnit = main.get_node("Interiors/DocksideDepot")

	match scenario:
		"warehouse_interior", "warehouse_inventory":
			var warehouse := CompanyDebug.stand_up_logistics(market)
			# The hire and the money popups both fire above, and both land in
			# the middle of the frame if the shot is taken straight away.
			await _wait(150)
			await _stand_in(player, depot, Vector3(0.0, 0.0, 2.0))
			if scenario == "warehouse_inventory":
				var property_screen: Node = _hud_screen(hud, "PropertyPanel")
				property_screen.call("open", PropertyManager.by_id(&"warehouse_dock_14"))
				await _wait(12)
			elif warehouse == null:
				push_warning("No depot for the warehouse shot.")

		"bulk_order", "logistics_dashboard", "branch_stock_request", \
		"shipment_queued", "company_vehicles", "delivery_route", \
		"logistics_bottlenecks":
			await _logistics_screen(main, scenario)

		"company_van", "warehouse_delivery":
			await _delivery_in_the_street(main, scenario)

		"delivery_driver":
			await _the_driver(main)

		"branch_transfer":
			await _branch_to_branch(main)

		"backup_pool", "manager_backup":
			await _backup_scenario(main, scenario)

		"finance_forecast", "business_warning", "wages_overdue", \
		"rent_overdue", "business_critical", "branch_closure", \
		"liquidation_screen", "company_logistics":
			await _distress_scenario(main, scenario)

		"foreclosure_warning", "foreclosure_cure":
			await _foreclosure_scenario(main, scenario)

	await _wait(10)


## The logistics screen, on whichever tab the frame is about, with enough
## behind it that no tab reads empty.
func _logistics_screen(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := BusinessManager.get_businesses()[0]
	var warehouse := CompanyDebug.stand_up_logistics(market)
	if warehouse == null:
		return
	var branch := _second_branch(main)

	# A little history, so the overview has numbers on it.
	LogisticsManager.bulk_savings += 240
	LogisticsManager.units_distributed += 480
	LogisticsManager.shipments_completed += 6

	var queued: TransferOrder = null
	if branch != null:
		var made := LogisticsManager.request_transfer(
			TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
			TransferOrder.Place.BUSINESS, branch.business_id,
			{&"bottled_water": 40, &"snack_bar": 24}
		)
		queued = made["order"]
		var sent := LogisticsManager.request_transfer(
			TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
			TransferOrder.Place.BUSINESS, branch.business_id, {&"soda_can": 30}
		)
		if sent["order"] != null:
			LogisticsManager.dispatch_transfer(sent["order"])
		var route := LogisticsManager.create_route(warehouse, "Morning Round")
		if route != null and branch != null:
			route.stop_business_ids.append(branch.business_id)
			route.stop_business_ids.append(market.business_id)
			route.departure_hour = 7

	if scenario == "logistics_bottlenecks":
		# A depot that cannot keep up. Four shipments booked and nothing free
		# to drive them, an empty depot behind them, and a branch with a bare
		# store room at the other end — three different logistics problems,
		# which is what the report is for.
		if branch != null:
			for run in 4:
				LogisticsManager.request_transfer(
					TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
					TransferOrder.Place.BUSINESS, branch.business_id,
					{&"bottled_water": 6}
				)
			for id: StringName in branch.storage.keys():
				branch.take_storage(id, branch.storage_of(id))
		for id: StringName in warehouse.stock.keys():
			warehouse.take(id, warehouse.held(id))

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)

	if scenario == "logistics_bottlenecks":
		var company: Node = _hud_screen(hud, "CompanyDashboard")
		company.call("open", CompanyDashboard.Page.OPERATIONS)
		await _wait(12)
		return

	var screen: Node = _hud_screen(hud, "LogisticsPanel")
	match scenario:
		"bulk_order":
			screen.call("open", LogisticsPanel.Page.STOCK)
		"branch_stock_request", "shipment_queued":
			screen.call("open", LogisticsPanel.Page.SHIPMENTS)
		"delivery_route":
			screen.call("open", LogisticsPanel.Page.ROUTES)
		"company_vehicles":
			screen.call("open", LogisticsPanel.Page.FLEET)
		_:
			screen.call("open", LogisticsPanel.Page.OVERVIEW)
	await _wait(14)
	if queued != null and scenario == "shipment_queued":
		await _wait(6)
	if scenario == "bulk_order":
		# The discount is the whole point of this frame and it sits below the
		# fold, so scroll the screen the way a player reading it would.
		await _scroll_to_bottom(screen)
	elif scenario == "branch_stock_request":
		# This frame is about a branch asking, which is the section under the
		# shipments rather than the shipments themselves.
		await _scroll_to_bottom(screen)


## A van actually on the road between the depot and a shop, with the player
## stood where they can see it. §107.
func _delivery_in_the_street(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var market := BusinessManager.get_businesses()[0]
	var warehouse := CompanyDebug.stand_up_logistics(market)
	if warehouse == null:
		return
	var branch := _second_branch(main)
	if branch == null:
		return
	# The hires above post notifications, which otherwise sit in the middle of
	# a frame that is meant to be a van.
	await _wait(150)

	var made := LogisticsManager.request_transfer(
		TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
		TransferOrder.Place.BUSINESS, branch.business_id, {&"bottled_water": 40}
	)
	var order: TransferOrder = made["order"]
	if order == null:
		return
	LogisticsManager.dispatch_transfer(order)

	# Stand at the depot gate. The traffic layer spawns the van because the
	# player is near one end of the run; nothing here places it by hand.
	var depot_door := PropertyManager.by_id(&"warehouse_dock_14")
	if depot_door != null:
		player.global_position = depot_door.global_position + Vector3(0.0, 0.6, -4.0)

	# Wait for the van to appear rather than for a fixed number of frames: it
	# is spawned by the review tick, and a fixed wait either catches nothing
	# or catches the delivery already finished.
	var van := await _wait_for_van(order, player)
	if van == null:
		return
	if scenario == "warehouse_delivery":
		# Let it get down the road, so the frame is a van in traffic rather
		# than a van still at the kerb — then follow it again, because it has
		# moved and the player has not.
		await _wait(90)
		van = await _wait_for_van(order, player)
	await _wait(20)


## The person who drives the van: a real employee, on a real rota, hired into
## the role Phase P added. §29.
func _the_driver(main: Node) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := BusinessManager.get_businesses()[0]
	CompanyDebug.stand_up_logistics(market)
	var driver := CompanyFleet.free_driver(TimeManager.hour)
	if driver == null:
		for worker in market.employees:
			if worker.role == EmployeeData.Role.DELIVERY_DRIVER:
				driver = worker
				break
	if driver == null:
		return
	# A working week rather than the round-the-clock shift the debug hire
	# gives, so the rota reads like a rota.
	driver.clear_shifts()
	driver.set_weekly_shifts([
		ShiftSlot.make(
			8, 17, EmployeeData.Role.DELIVERY_DRIVER, ShiftSlot.EVERY_DAY,
			market.business_id
		),
	])
	# Out on a run, so the screen shows somebody with a job on rather than an
	# empty week.
	var branch := _second_branch(main)
	if branch != null:
		var made := LogisticsManager.request_transfer(
			TransferOrder.Place.WAREHOUSE,
			LogisticsManager.primary_warehouse().warehouse_id,
			TransferOrder.Place.BUSINESS, branch.business_id, {&"bottled_water": 30}
		)
		if made["order"] != null:
			LogisticsManager.dispatch_transfer(made["order"], null, driver)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(150)
	var rota: Node = _hud_screen(hud, "StaffSchedulePanel")
	rota.call("open", driver)
	await _wait(14)


## Stands the player behind whichever van the logistics layer put on the road
## for this shipment, once there is one. The van is real and nothing here
## places it; all this does is put the camera where a player who wanted to
## watch their own delivery would be standing.
func _wait_for_van(order: TransferOrder, player: Node3D) -> Vehicle:
	var traffic := LogisticsManager.traffic
	if traffic == null:
		return null
	for attempt in 40:
		var van := traffic.van_for(order.transfer_id)
		if van != null:
			var behind: Vector3 = van.global_transform * Vector3(0.0, 0.0, 6.0)
			player.global_position = Vector3(
				behind.x, van.global_position.y + 0.9, behind.z
			)
			await _wait(20)
			return traffic.van_for(order.transfer_id)
		await _wait(15)
	return null


## Two shops of the player's own, moving stock between them without the depot
## in the middle. §57.
func _branch_to_branch(main: Node) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := BusinessManager.get_businesses()[0]
	CompanyDebug.stand_up_logistics(market)
	var branch := _second_branch(main)
	if branch == null:
		return
	CompanyDebug.stock_up(market, 90)
	for id: StringName in branch.storage.keys():
		branch.take_storage(id, branch.storage_of(id))

	var made := LogisticsManager.request_transfer(
		TransferOrder.Place.BUSINESS, market.business_id,
		TransferOrder.Place.BUSINESS, branch.business_id,
		{&"bottled_water": 20, &"snack_bar": 12}
	)
	if made["order"] != null:
		LogisticsManager.dispatch_transfer(made["order"])

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)
	var screen: Node = _hud_screen(hud, "LogisticsPanel")
	screen.call("open", LogisticsPanel.Page.SHIPMENTS)
	await _wait(14)


## Somebody off shift covering for somebody who did not turn up. §96 to §100.
func _backup_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := BusinessManager.get_businesses()[0]
	var branch := _second_branch(main)
	if branch == null:
		return

	# Two people at the first shop, one of whom is free this afternoon, and a
	# branch with a manager who is allowed to pick up the phone.
	CompanyDebug.hire(market, EmployeeData.Role.CASHIER, 0.8)
	var spare := CompanyDebug.hire(market, EmployeeData.Role.CASHIER, 0.7)
	if spare != null:
		spare.available_for_backup = true
		spare.clear_shifts()
		spare.set_weekly_shifts([
			ShiftSlot.make(
				7, 11, EmployeeData.Role.CASHIER, ShiftSlot.EVERY_DAY, market.business_id
			),
		])
	if not branch.has_manager():
		CompanyDebug.hire(branch, EmployeeData.Role.MANAGER, 0.85)
	branch.set_permission(&"call_backup", true)

	if scenario == "manager_backup":
		# The branch's own cashier has not been paid in weeks and has stopped
		# turning up. That is the real trigger — the manager finds the till
		# uncovered on a day it should not be and rings round the company.
		for worker in branch.employees:
			if worker.role == EmployeeData.Role.CASHIER:
				CompanyDebug.owe_wages(branch, worker, 900)
				worker.missed_pay_runs = 4
		BusinessManager.call("_run_manager", branch, 14)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)
	var company: Node = _hud_screen(hud, "CompanyDashboard")
	company.call("open", CompanyDashboard.Page.EMPLOYEES)
	await _wait(14)


## Money trouble, at each of the stages the player is shown it.
func _distress_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := BusinessManager.get_businesses()[0]
	CompanyDebug.stand_up_logistics(market)
	var branch := _second_branch(main)
	var patient: BusinessInstance = branch if branch != null else market

	# A morning's trade behind the figures, so the forecast is forecasting
	# something rather than reading zero across the board.
	for business in [market, branch]:
		if business == null:
			continue
		business.manual_override = BusinessInstance.Override.FORCE_OPEN
		business.set_open(true)
		for i in 5:
			BusinessManager.simulate_hour_now(business, 12)

	match scenario:
		"business_warning", "wages_overdue":
			CompanyDebug.set_cash(patient, 60)
			for worker in patient.employees:
				CompanyDebug.owe_wages(patient, worker, 180)

		"rent_overdue":
			CompanyDebug.set_cash(patient, 40)
			var unit := patient.property()
			if unit != null:
				unit.arrears = unit.rent_amount * 2
				unit.next_rent_due_day = TimeManager.day_index - 3
			FinanceManager.review(patient)

		"business_critical", "branch_closure", "liquidation_screen":
			CompanyDebug.set_cash(patient, 0)
			for worker in patient.employees:
				CompanyDebug.owe_wages(patient, worker, 620)
				CompanyDebug.owe_wages(patient, worker, 620)
			var unit := patient.property()
			if unit != null:
				unit.arrears = unit.rent_amount * 3
			FinanceManager.review(patient)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)

	match scenario:
		"finance_forecast", "company_logistics":
			var company: Node = _hud_screen(hud, "CompanyDashboard")
			company.call("open", CompanyDashboard.Page.FINANCE)
		"branch_closure", "liquidation_screen":
			var finance: Node = _hud_screen(hud, "BranchFinancePanel")
			finance.call("open", patient)
			await _wait(8)
			finance.call(
				"show_page",
				BranchFinancePanel.Page.LIQUIDATE if scenario == "liquidation_screen"
					else BranchFinancePanel.Page.CLOSE
			)
		"wages_overdue", "rent_overdue":
			# The branch's own money page, which names what is owed and to
			# whom, rather than the company card that only totals it.
			var owed: Node = _hud_screen(hud, "BranchFinancePanel")
			owed.call("open", patient)
		_:
			var company: Node = _hud_screen(hud, "CompanyDashboard")
			company.call("open", CompanyDashboard.Page.LOCATIONS)
	await _wait(14)


## The lender coming for a building, and the way out of it. §88 and §174.
func _foreclosure_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	for listing in RealEstate.listings():
		RealEstate.discover(listing.property_id)
	var loan: MortgageData = null
	for listing in RealEstate.listings():
		if not listing.mortgage_available or RealEstate.owns(listing.property_id):
			continue
		if RealEstate.buy_with_mortgage(listing.property_id) == RealEstate.BuyResult.OK:
			loan = RealEstate.mortgage_for(listing.property_id)
			break
	if loan == null:
		return
	CompanyDebug.miss_mortgage_payments(loan, MortgageData.FORECLOSURE_MISSES)

	# The two frames are the same notice from either side of being able to
	# afford it: the warning is what a player who cannot pay sees, the cure is
	# the same screen with the money behind the button.
	if scenario == "foreclosure_warning":
		EconomyManager.restore(120)
	else:
		EconomyManager.restore(loan.arrears_amount() + 40000)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(30)
	var company: Node = _hud_screen(hud, "CompanyDashboard")
	company.call("open", CompanyDashboard.Page.FINANCE)
	await _wait(14)


## A second shop of the player's, so the transfer and cover frames have two
## ends to them.
func _second_branch(main: Node) -> BusinessInstance:
	var door := PropertyManager.by_id(&"unit_central_88")
	if door == null:
		return null
	if door.is_vacant():
		PropertyManager.lease(door)
	var existing := BusinessManager.business_for_property(&"unit_central_88")
	if existing != null:
		return existing
	var branch := BusinessManager.create_business(
		"Boulevard Market", &"convenience_store", door
	)
	if branch == null:
		return null
	BusinessManager.deposit_to_business(branch, 12000)
	var unit: RetailUnit = main.get_node("Interiors/CentralBoulevardUnit")
	unit.ensure_built()
	CompanyDebug.fit_out(branch, unit)
	CompanyDebug.stock_up(branch, 30)
	CompanyDebug.hire(branch, EmployeeData.Role.CASHIER, 0.7)
	branch.manual_override = BusinessInstance.Override.FORCE_OPEN
	return branch


# --- Phase Q ---------------------------------------------------------------

## The crime and police frames.
##
## Every one of these drives the real systems: the wanted level is raised by
## reporting real crimes, the roadblocks are placed by RoadblockManager against
## its own validation, and the search is the one the police actually run. The
## tool only decides where the camera stands.
func _phase_q_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	EconomyManager.restore(500000)
	await _wait(90)

	match scenario:
		"eviction_notice", "eviction_cured":
			await _eviction_scenario(main, scenario)
		"wanted_one", "wanted_two", "wanted_three", "wanted_four", "wanted_five", \
		"roadblock_night":
			await _wanted_scenario(main, scenario)
		"police_search", "search_map", "wanted_cleared":
			await _search_scenario(main, scenario)
		"known_vehicle", "switched_vehicle":
			await _vehicle_scenario(main, scenario)
		"foot_pursuit":
			await _foot_pursuit(main)
		"fence_exterior", "fence_screen", "chop_shop", "chop_delivery", \
		"criminal_contact", "job_offer":
			await _underworld_location(main, scenario)
		"criminal_reputation", "underworld_jobs":
			await _underworld_screen(main, scenario)
		"business_while_wanted":
			await _business_while_wanted(main)

	await _wait(10)


## §3 — the notice on the branch's own money page, and the same page after it
## has been paid.
func _eviction_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	BusinessManager.deposit_to_business(market, 6000)
	var unit := market.property()
	if unit == null:
		return
	CompanyDebug.evict(unit)
	if scenario == "eviction_cured":
		EconomyManager.restore(unit.arrears + 60000)
		FinanceManager.cure_eviction(unit)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(150)
	var finance: Node = _hud_screen(hud, "BranchFinancePanel")
	finance.call("open", market)
	await _wait(14)


## The five levels, and what each one puts on the street. The heat is earned by
## reporting real crimes rather than set, so the response is the real one.
func _wanted_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var wanted := {
		"wanted_one": 1, "wanted_two": 2, "wanted_three": 3,
		"wanted_four": 4, "wanted_five": 5, "roadblock_night": 5,
	}
	var level: int = int(wanted.get(scenario, 1))

	# Main Street, which is where the earlier crime frames were composed and is
	# a street rather than the blank apron behind the precinct — the first
	# attempt drifted onto that and photographed nothing.
	var start := Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
	player.global_position = start
	await _wait(60)
	await _clear_pedestrians()
	# Enough crimes to reach the level honestly, climbing one rung at a time.
	#
	# The ladder has to start small. Vehicle theft is worth twenty points and
	# two stars begin at twenty, so opening with it can never produce a
	# one-star frame — the first shot came back showing two. Shoplifting is
	# the only crime under the second threshold, so it is the bottom rung, and
	# each rung after it is chosen to land inside the next band rather than
	# jump over it: 10, 30, 55, 85, 120 against thresholds 0/20/40/70/110.
	var crimes := [
		CrimeManager.CrimeType.SHOPLIFTING,
		CrimeManager.CrimeType.VEHICLE_THEFT,
		CrimeManager.CrimeType.ASSAULT,
		CrimeManager.CrimeType.BURGLARY,
		CrimeManager.CrimeType.CARJACKING,
	]
	for i in crimes.size():
		if WantedManager.level >= level:
			break
		UnderworldDebug.force_report(crimes[i], player.global_position)
		await _wait(6)
	# The heat is earned above; this is what pins it to the band the frame is
	# labelled with. Reports are worth a little more than their base when
	# anybody confirms them, and the level is decaying the whole time the
	# player is out of sight, so left alone the ladder lands near the target
	# rather than on it — three stars rendered as four. `set_level` is the same
	# public call the debug menu uses, and the response on the street is the
	# real response for whatever level it ends on.
	if WantedManager.level != level:
		WantedManager.set_level(level)

	# The police answer the call themselves — the same dispatch the game uses,
	# given long enough to arrive. Long enough is the operative word: the first
	# version waited 220 frames, under four real seconds, and photographed a
	# street the units had not reached yet.
	await _keep_ahead(600, start)
	await _regain_sight()
	# Roadblocks need a moment to find a node they are happy with.
	if level >= RoadblockManager.MIN_LEVEL:
		for attempt in 4:
			if RoadblockManager.count() > 0:
				break
			UnderworldDebug.spawn_roadblock()
			await _wait(20)
		# Stand where one of them is, so the frame is the block rather than
		# the empty road it is not on.
		if RoadblockManager.count() > 0:
			var at: Vector3 = RoadblockManager.positions()[0]
			# Twenty-six metres due north of a roadblock is not necessarily a
			# road — on the first render it was the inside of a building, and
			# the frame came back as empty sky. So walk a ring around it and
			# take the open side that faces
			# furthest into the city. Taking the first side that happened to be
			# standable once put the camera at the southern boundary, and a
			# third of the five-star frame was the empty ground past the map.
			var chosen := Vector3.INF
			var inward := INF
			for i in 12:
				var angle := TAU * float(i) / 12.0
				var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * 20.0
				spot.y = 0.6
				if not _standable(spot):
					continue
				var from_edge := spot.length()
				if from_edge < inward:
					inward = from_edge
					chosen = spot
			if chosen != Vector3.INF:
				var spot: Vector3 = chosen
				player.global_position = spot
				# Standing near the block is not the same as looking at it —
				# the first night frame was a car park with the roadblock
				# somewhere behind the camera. Point the rig down the line from
				# the player to the block.
				_look_towards(main, spot, at)
				# Standing still beside a roadblock at four stars gets you
				# arrested, and the four-star frame came back as the release
				# point with a fine on it. Hold position, sidestepping anybody
				# who gets close enough to reach.
				await _keep_ahead(90, spot, 5.0)


## Takes the passers-by off the street, leaving the police on it.
##
## `UnderworldDebug.force_report` credits the crime immediately, but the same
## call still emits `crime_reported`, so any pedestrian who happens to be
## looking files the incident again a second or two later through the ordinary
## witness path — and that second report is worth full points, not the ten per
## cent a confirmation is worth. Whether anybody was looking is chance, which
## is why the ladder came out at one star once and three the next time from
## identical instructions.
##
## Emptying the pavement makes the forced reports the only reports, so a frame
## labelled two stars is two stars. The Phase E and F crime frames quiet the
## street for the same reason. Police are deliberately left alone: they are
## what the frame is of.
func _clear_pedestrians() -> void:
	for node in get_tree().get_nodes_in_group(&"pedestrian"):
		if node is Node3D:
			node.global_position = Vector3(400.0, 0.0, 400.0)
		node.process_mode = Node.PROCESS_MODE_DISABLED
	await _wait(4)


## How near an officer may get before the tool steps the player away.
const EVADE_RANGE := 12.0
## How far that step goes, and how far from where the scene started the player
## is allowed to drift while taking it.
##
## The leash is short on purpose. A long one let the player back away street
## after street until the frame was the front door of the police precinct
## rather than the response it was composed for, so the evasion stays inside
## the block the camera is pointed at.
## Both are short, and the leash is shorter than the range on purpose: the
## player keeps sidestepping whoever is nearest without ever leaving the block
## the shot was composed for. A longer leash let them drift to the retaining
## wall at the south end of Main Street, and half the frame came back as blank
## pavement.
const EVADE_STEP := 9.0
const EVADE_LEASH := 11.0


## Waiting out a police response without being arrested at the end of it.
##
## A player who stands perfectly still while four units converge is arrested,
## and an arrest clears the wanted level — which is the one thing these frames
## exist to show. The first attempt at the star frames came back with BUSTED
## across the middle of them for exactly that reason.
##
## Nothing here makes the player un-arrestable. The police run their real
## pursuit against a target that keeps moving, which is what a player at four
## stars is doing anyway; the tool just supplies the moving. The step is always
## directly away from whoever is closest, and a leash keeps it from wandering
## out of the streets the camera is framing.
func _keep_ahead(frames: int, start: Vector3, range_override: float = -1.0) -> void:
	var player: Node3D = GameManager.player
	if player == null:
		await _wait(frames)
		return
	var waited := 0
	while waited < frames:
		await _wait(8)
		waited += 8
		var closest: Node3D = null
		var nearest := INF
		for node in get_tree().get_nodes_in_group(&"police"):
			var unit := node as Node3D
			if unit == null or not is_instance_valid(unit):
				continue
			var away := unit.global_position.distance_to(player.global_position)
			if away < nearest:
				nearest = away
				closest = unit
		var reach := EVADE_RANGE if range_override < 0.0 else range_override
		if closest == null or nearest > reach:
			continue
		# Straight-away is the obvious step and the wrong one, because the leash
		# can clamp it back past the officer it was running from. Eight
		# directions are tried instead and the one that ends up furthest from
		# them — after the leash has had its say — wins.
		#
		# Two passes. The first wants a step with nothing in the way; the
		# second will settle for anywhere standable. Main Street is lined with
		# parked cars, and a parked car blocks the "is there a wall between
		# here and there" ray exactly as a wall does — so the strict pass alone
		# kept rejecting all eight directions, the player stood still, and the
		# three-star frame came back with BUSTED across it.
		var best := player.global_position
		var best_gap := nearest
		var fallback := player.global_position
		var fallback_gap := nearest
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var step := Vector3(cos(angle), 0.0, sin(angle)) * EVADE_STEP
			var candidate: Vector3 = player.global_position + step
			candidate = start + (candidate - start).limit_length(EVADE_LEASH)
			candidate.y = start.y
			if not _standable(candidate):
				continue
			var gap := candidate.distance_to(closest.global_position)
			if gap > fallback_gap:
				fallback_gap = gap
				fallback = candidate
			if not _clear_between(player.global_position, candidate):
				continue
			if gap > best_gap:
				best_gap = gap
				best = candidate
		player.global_position = best if best_gap > nearest else fallback


## Whether a step is somewhere the player could actually have walked to.
##
## Without this the search happily picked a point inside the building on the
## north side of the street, and a body placed inside a wall is pushed out
## through the floor: the five-star frame came back as empty grey sky with the
## player somewhere underneath the city.
##
## Two questions, both asked of the physics the game already has. Is there a
## wall between here and there, and is there any ground once you arrive.
func _clear_between(from: Vector3, to: Vector3) -> bool:
	var player: Node3D = GameManager.player
	if player == null:
		return false
	var space := player.get_world_3d().direct_space_state
	var eye := Vector3(0.0, 1.0, 0.0)
	var across := PhysicsRayQueryParameters3D.create(from + eye, to + eye)
	across.exclude = [player.get_rid()]
	return space.intersect_ray(across).is_empty()


## Whether a point is open street the player could be stood on.
##
## Ground underneath, and nothing overhead. The roof test is what catches being
## inside a building: a body placed in a wall is pushed out through the floor,
## and the four-star frame came back as empty sky with the city above it.
func _standable(at: Vector3) -> bool:
	var player: Node3D = GameManager.player
	if player == null:
		return false
	var space := player.get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, 3.0, 0.0), at - Vector3(0.0, 2.0, 0.0)
	)
	down.exclude = [player.get_rid()]
	if space.intersect_ray(down).is_empty():
		return false
	var overhead := PhysicsRayQueryParameters3D.create(
		at + Vector3(0.0, 40.0, 0.0), at + Vector3(0.0, 3.5, 0.0)
	)
	overhead.exclude = [player.get_rid()]
	return space.intersect_ray(overhead).is_empty()


## Turns the camera to face something specific.
##
## Only takes effect when the command line did not pass a yaw of its own: the
## overrides in `_ready` are applied after the scenario runs, deliberately, so
## that a caller always wins.
func _look_towards(main: Node, from: Vector3, to: Vector3) -> void:
	var rig := main.get_node_or_null("CameraRig") as TopDownCamera
	if rig == null:
		return
	var heading := to - from
	heading.y = 0.0
	if heading.length() < 0.5:
		return
	heading = heading.normalized()
	# The rig carries the camera at +Z and looks back at the target, so the
	# view runs along -(sin yaw, cos yaw).
	rig.yaw_degrees = rad_to_deg(atan2(-heading.x, -heading.z))
	rig.rotation_degrees.y = rig.yaw_degrees


## The last beat before the shutter on a pursuit frame.
##
## Stepping away breaks line of sight, and a broken line of sight is the state
## the HUD calls ESCAPING — so a frame taken immediately after a step shows a
## countdown rather than the chase it was composed for. This gives the officers
## a moment to close the gap and see the player again, which is short enough
## that nobody gets near arresting distance.
func _regain_sight(frames: int = 40) -> void:
	await _wait(frames)


## Breaking away, the search that follows, and the moment it runs out.
func _search_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var start := Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
	player.global_position = start
	await _wait(60)
	UnderworldDebug.force_report(CrimeManager.CrimeType.STORE_ROBBERY)
	UnderworldDebug.force_report(CrimeManager.CrimeType.CARJACKING)
	await _keep_ahead(420, start)

	# Away from them, then out of sight.
	player.global_position = Vector3(-58.0, 0.5, 66.0)
	UnderworldDebug.break_line_of_sight()
	UnderworldDebug.start_search()
	await _wait(90)

	if scenario == "wanted_cleared":
		WantedManager.clear_wanted("WANTED LEVEL CLEARED")
		await _wait(30)
	elif scenario == "search_map":
		var map: Control = hud.get_node_or_null("CityMap")
		if map != null:
			map.call("open")
			await _wait(16)


## A car the police are looking for, and the player after leaving it unseen.
func _vehicle_scenario(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	# Main Street, for the same reason the star frames use it: the first render
	# put the car in the park and the camera came back full of trees with the
	# vehicle the police are looking for nowhere in shot.
	var kerb := Vector3(-40.0, 0.4, District01.MAIN_ST_Z + District01.LANE_OFFSET)
	player.global_position = kerb + Vector3(4.0, 0.1, 4.0)
	await _wait(60)
	await _clear_pedestrians()
	var record := VehicleRegistry.grant(&"sedan", Transform3D(
		Basis.IDENTITY, kerb
	))
	if record == null:
		return
	UnderworldDebug.mark_vehicle_stolen(record)
	VehicleRegistry.call("_spawn", record)
	var car := record.node as Vehicle
	await _wait(30)
	UnderworldDebug.force_report(CrimeManager.CrimeType.CARJACKING)
	if car != null:
		UnderworldDebug.mark_vehicle_known(car)
	await _keep_ahead(300, kerb + Vector3(4.0, 0.1, 4.0))

	if scenario == "switched_vehicle":
		# §158 — out of it where nobody is watching, and away on foot.
		UnderworldDebug.break_line_of_sight()
		UnderworldDebug.lose_identity()
		UnderworldDebug.start_search()
		# On foot, a short walk from the car, which stays at the kerb being the
		# thing the police are still looking for.
		player.global_position = kerb + Vector3(16.0, 0.1, 9.0)
		await _wait(90)


## §117 — officers coming after somebody who left the car behind.
func _foot_pursuit(main: Node) -> void:
	var player: Node3D = GameManager.player
	var start := Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
	player.global_position = start
	await _wait(60)
	UnderworldDebug.force_report(CrimeManager.CrimeType.ROBBERY)
	UnderworldDebug.force_report(CrimeManager.CrimeType.ASSAULT)
	await _keep_ahead(420, start)
	UnderworldDebug.force_pursuit()
	# Let the officers actually get moving before the shutter.
	# Shorter, then a long hold at arm's length. A foot chase frame wants the
	# officers close enough to read as a chase; backing away from twelve metres
	# right up to the shutter left the street with nobody on it but the player,
	# and standing still ends in an arrest. Five metres is inside arresting
	# distance plus a margin, so they close right up and never quite get there.
	await _keep_ahead(200, start)
	await _keep_ahead(260, start, 5.0)


## The three addresses, from outside and from the back room.
func _underworld_location(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	UnderworldDebug.set_reputation(55)
	UnderworldDebug.unlock_all_contacts()

	var wanted_door := {
		"fence_exterior": &"quayside_fence",
		"fence_screen": &"quayside_fence",
		"chop_shop": &"dock_road_garage",
		"chop_delivery": &"dock_road_garage",
		"criminal_contact": &"the_broker",
		"job_offer": &"the_broker",
	}
	var id: StringName = wanted_door.get(scenario, &"quayside_fence")
	var door := _contact_door(id)
	if door == null:
		return
	player.global_position = door.global_position + Vector3(0.0, 0.6, 7.0)
	await _wait(120)

	match scenario:
		"fence_screen":
			UnderworldDebug.give_stolen_goods(&"energy_drink", 7)
			UnderworldDebug.give_stolen_goods(&"snack_bar", 5)
		"chop_delivery":
			var record := VehicleRegistry.grant(&"suv", Transform3D(
				Basis.IDENTITY, door.global_position + Vector3(3.0, 0.4, 8.0)
			))
			if record != null:
				UnderworldDebug.mark_vehicle_stolen(record)
				VehicleRegistry.call("_spawn", record)
				await _wait(60)
				# Arrive in it. The buyer's own words are "turn up in
				# something", and that is what the screen looks for first; a
				# car left standing nearby is only reached by a fallback, and
				# the first render came back on the empty state.
				var car := record.node as Node3D
				if car != null and car.has_node("Door"):
					car.get_node("Door").interact(player)
			await _wait(40)

	# The three exteriors. "criminal_contact" is the broker's own doorway —
	# opening the panel there made it a second copy of the job-offer frame.
	if scenario in ["fence_exterior", "chop_shop", "criminal_contact"]:
		# Face the place. Standing outside it with the camera pointed along the
		# street put the lit doorway at the edge of the frame and the dock in
		# the middle of it.
		_look_towards(main, player.global_position, door.global_position)
		await _wait(10)
		return

	var screen: Node = _hud_screen(hud, "ContactPanel")
	screen.call("open", CriminalContactData.by_id(id))
	await _wait(14)


## The underworld screen itself.
func _underworld_screen(main: Node, scenario: String) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	UnderworldDebug.set_reputation(62)
	UnderworldDebug.unlock_all_contacts()
	# Something behind the figures, so no tab reads zero.
	UnderworldDebug.give_stolen_goods(&"energy_drink", 6)
	var inventory = player.call("get_inventory")
	Underworld.sell_to_fence(inventory)
	var job := UnderworldDebug.create_job(&"the_broker")
	if job != null:
		Underworld.accept_job(job)

	player.global_position = Vector3(-20.0, 0.5, District01.MAIN_ST_Z - 9.4)
	await _wait(150)
	var screen: Node = _hud_screen(hud, "UnderworldPanel")
	screen.call(
		"open",
		UnderworldPanel.Page.JOBS if scenario == "underworld_jobs"
			else UnderworldPanel.Page.STANDING
	)
	await _wait(14)


## §107 and §173 — the company screen, while its owner is wanted.
func _business_while_wanted(main: Node) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	BusinessManager.deposit_to_business(market, 40000)
	CompanyDebug.stand_up_logistics(market)
	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	for i in 5:
		BusinessManager.simulate_hour_now(market, 12)

	player.global_position = Vector3(0.0, 0.5, 40.0)
	await _wait(60)
	UnderworldDebug.force_report(CrimeManager.CrimeType.STORE_ROBBERY)
	UnderworldDebug.force_report(CrimeManager.CrimeType.CARJACKING)
	await _wait(180)

	var company: Node = _hud_screen(hud, "CompanyDashboard")
	company.call("open", CompanyDashboard.Page.LOCATIONS)
	await _wait(14)


# --- Phase R ---------------------------------------------------------------

## The legal and career frames.
##
## Every one of these drives the real systems: an arrest is a real arrest, a
## case is opened by it, and the hearing goes through the one-outcome guard.
## The tool only decides where the camera stands and which screen is open.
func _phase_r_scenario(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	EconomyManager.restore(500000)
	await _wait(90)

	match scenario:
		"arrest_summary":
			await _r_arrest_summary(main)
		"criminal_record", "record_tier":
			await _r_record(main, scenario)
		"active_case", "case_outcome":
			await _r_case(main, scenario)
		"court_reminder":
			await _r_court_reminder(main)
		"civic_court":
			await _r_civic_court(main)
		"premium_refused":
			await _r_premium_refused(main)
		"financing_refused":
			await _r_financing_refused(main)
		"scandal_notice", "company_after_scandal":
			await _r_scandal(main, scenario)
		"underworld_overview", "contact_list", "contact_trust", \
		"broker_board", "goods_request", "vehicle_request", "higher_tier_job", \
		"career_progress", "income_split":
			await _r_underworld(main, scenario)
		"business_with_court_pending":
			await _r_business_with_court(main)

	await _wait(10)


## A record with some weight to it, built out of real arrests.
func _r_history(serious: int = 3) -> void:
	LegalManager.clear()
	# Real crimes, filed before each arrest, so the record reads as a record
	# rather than as a column of "arrested on suspicion".
	var ladder := [
		CrimeManager.CrimeType.ROBBERY,
		CrimeManager.CrimeType.CARJACKING,
		CrimeManager.CrimeType.BURGLARY,
		CrimeManager.CrimeType.STORE_ROBBERY,
	]
	for i in serious:
		LegalDebug.create_case(ladder[i % ladder.size()], 4)
	LegalDebug.create_case(CrimeManager.CrimeType.VEHICLE_THEFT, 2)


func _r_arrest_summary(main: Node) -> void:
	var player: Node3D = GameManager.player
	var hud: Node = main.get_node("HUD")
	player.global_position = Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
	await _wait(60)
	# A real pursuit, so the summary lists what a pursuit actually files.
	for type in [
		CrimeManager.CrimeType.VEHICLE_THEFT,
		CrimeManager.CrimeType.HIT_AND_RUN,
		CrimeManager.CrimeType.ROBBERY,
	]:
		UnderworldDebug.force_report(type)
		await _wait(6)
	WantedManager.set_level(4)
	await _wait(20)
	WantedManager.request_bust()
	# The summary appears when the arrest finishes, and the HUD opens it.
	await _wait(int(WantedManager.bust_hold_seconds * 60.0) + 90)


func _r_record(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	_r_history(4 if scenario == "record_tier" else 2)
	await _wait(20)
	var screen: Node = _hud_screen(hud, "LegalPanel")
	screen.call("open", LegalPanel.Page.RECORD if scenario == "criminal_record"
		else LegalPanel.Page.OVERVIEW)
	await _wait(14)


func _r_case(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	LegalManager.clear()
	LegalDebug.create_case(CrimeManager.CrimeType.ROBBERY, 4)
	if scenario == "case_outcome":
		LegalDebug.schedule_court_now()
		LegalDebug.resolve_court(true)
	await _wait(20)
	var screen: Node = _hud_screen(hud, "LegalPanel")
	screen.call("open", LegalPanel.Page.CASES)
	await _wait(14)


func _r_court_reminder(main: Node) -> void:
	var player: Node3D = GameManager.player
	LegalManager.clear()
	LegalDebug.create_case(CrimeManager.CrimeType.ROBBERY, 4)
	var case := LegalManager.next_case()
	if case != null:
		# The day before, which is when the reminder fires.
		case.court_day = TimeManager.day_index + 1
		case.reminder_shown = false
	player.global_position = Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
	await _wait(30)
	LegalManager._on_hour_passed(TimeManager.hour)
	await _wait(20)


func _r_civic_court(main: Node) -> void:
	var player: Node3D = GameManager.player
	LegalManager.clear()
	LegalDebug.create_case(CrimeManager.CrimeType.ROBBERY, 4)
	LegalDebug.schedule_court_now()
	var doors := get_tree().get_nodes_in_group(&"civic_court")
	if doors.is_empty():
		return
	var door := doors[0] as Node3D
	# Off the carriageway and off to one side: standing dead in front of it put
	# a lamp post straight down the middle of the frame.
	player.global_position = door.global_position + Vector3(-3.5, 0.5, 6.0)
	await _wait(60)
	_look_towards(main, player.global_position, door.global_position)
	await _wait(20)


func _r_premium_refused(main: Node) -> void:
	var player: Node3D = GameManager.player
	LegalDebug.set_record_tier(CriminalRecord.Tier.HIGH_RISK)
	await _wait(20)
	# Stand outside a premium address and try for it, so the refusal is the
	# game's own rather than a mocked message.
	var best: ResidenceProperty = null
	for node in get_tree().get_nodes_in_group(&"residence"):
		var home := node as ResidenceProperty
		if home == null or home.is_leased_by_player():
			continue
		if best == null or home.rent_amount > best.rent_amount:
			best = home
	if best == null:
		return
	player.global_position = best.global_position + Vector3(0.0, 0.5, 6.0)
	await _wait(40)
	PropertyManager.lease_residence(best)
	await _wait(20)


func _r_financing_refused(main: Node) -> void:
	var hud: Node = main.get_node("HUD")
	LegalDebug.set_record_tier(CriminalRecord.Tier.HIGH_RISK)
	await _wait(20)
	# The refusal is on the mortgage offer, not on the portfolio: it is what a
	# lender says when the player asks, so the frame has to be the asking.
	var listing: PropertyListing = null
	for candidate in RealEstate.listings():
		if candidate.mortgage_available and not RealEstate.owns(candidate.property_id):
			candidate.discovered = true
			listing = candidate
			break
	if listing == null:
		return
	var screen: Node = _hud_screen(hud, "PropertySalePanel")
	screen.call("open", listing.property_id)
	await _wait(10)
	screen.set("_showing_mortgage", true)
	screen.call("_rebuild")
	await _wait(14)


func _r_scandal(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	BusinessManager.deposit_to_business(market, 40000)
	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	for i in 4:
		BusinessManager.simulate_hour_now(market, 12)
	await _wait(30)
	LegalManager.clear()
	LegalDebug.create_case(CrimeManager.CrimeType.ROBBERY, 5)
	LegalDebug.schedule_court_now()
	LegalDebug.resolve_court(false)
	await _wait(30)
	if scenario == "scandal_notice":
		# The toast is the frame. Stand in the street to see it land.
		var player: Node3D = GameManager.player
		player.global_position = Vector3(-40.0, 0.5, District01.MAIN_ST_Z + 8.0)
		CompanyManager.apply_owner_scandal(7.0, "Robbery")
		await _wait(24)
		return
	CompanyManager.apply_owner_scandal(7.0, "Robbery")
	await _wait(20)
	var screen: Node = _hud_screen(hud, "CompanyDashboard")
	screen.call("open")
	await _wait(14)


func _r_underworld(main: Node, scenario: String) -> void:
	var hud: Node = main.get_node("HUD")
	UnderworldDebug.unlock_all_contacts()
	UnderworldDebug.set_reputation(64)
	LegalDebug.set_trust(&"quayside_fence", 58)
	LegalDebug.set_trust(&"dock_road_garage", 76)
	LegalDebug.set_trust(&"the_broker", 47)
	for i in 6:
		Underworld.career.credit(IllegalJobData.Objective.VEHICLE_DELIVERY)
	for i in 3:
		Underworld.career.credit(IllegalJobData.Objective.STOLEN_GOODS_RUN)
	Underworld.career.requests_filled = 4
	Underworld.career.best_single_payout = 14200
	LegalDebug.post_request(&"quayside_fence")
	LegalDebug.post_request(&"dock_road_garage")
	LegalDebug.generate_board(&"the_broker")
	await _wait(30)

	if scenario == "goods_request":
		var fence: Node = _hud_screen(hud, "ContactPanel")
		fence.call("open", CriminalContactData.by_id(&"quayside_fence"))
		await _wait(14)
		return
	if scenario == "vehicle_request":
		var garage: Node = _hud_screen(hud, "ContactPanel")
		garage.call("open", CriminalContactData.by_id(&"dock_road_garage"))
		await _wait(14)
		return
	if scenario == "broker_board" or scenario == "higher_tier_job":
		var broker: Node = _hud_screen(hud, "ContactPanel")
		broker.call("open", CriminalContactData.by_id(&"the_broker"))
		await _wait(14)
		return

	var page := UnderworldPanel.Page.STANDING
	match scenario:
		"contact_list", "contact_trust":
			page = UnderworldPanel.Page.CONTACTS
		"career_progress":
			page = UnderworldPanel.Page.CAREER
		"income_split":
			page = UnderworldPanel.Page.EARNINGS
		_:
			page = UnderworldPanel.Page.STANDING
	var screen: Node = _hud_screen(hud, "UnderworldPanel")
	screen.call("open", page)
	await _wait(14)


func _r_business_with_court(main: Node) -> void:
	var hud: Node = main.get_node("HUD")
	var market := _open_shop_at(
		main, &"unit_main_18", "Interiors/MainStreetUnit", "Silas Market"
	)
	BusinessManager.deposit_to_business(market, 40000)
	CompanyDebug.stand_up_logistics(market)
	market.manual_override = BusinessInstance.Override.FORCE_OPEN
	market.set_open(true)
	for i in 5:
		BusinessManager.simulate_hour_now(market, 12)
	LegalManager.clear()
	LegalDebug.create_case(CrimeManager.CrimeType.ROBBERY, 4)
	var case := LegalManager.next_case()
	if case != null:
		case.court_day = TimeManager.day_index + 1
		case.reminder_shown = false
	await _wait(20)
	LegalManager._on_hour_passed(TimeManager.hour)
	await _wait(20)
	var company: Node = _hud_screen(hud, "CompanyDashboard")
	company.call("open", CompanyDashboard.Page.LOCATIONS)
	await _wait(14)


## The door of a given contact, wherever in the city it stands.
func _contact_door(contact_id: StringName) -> Node3D:
	for node in get_tree().get_nodes_in_group(&"criminal_contact"):
		var door := node as CriminalContactPoint
		if door != null and door.contact_id == contact_id:
			return door
	return null
