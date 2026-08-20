extends CanvasLayer
## Dev-only readout for everything the player owns, hidden by default.
##
## Fifth of its kind, and the same rules as the traffic, crime, business and
## audio overlays: not part of the HUD, deleted by removing this node and its
## input action. F11 toggles it, and the commands are keys that only do anything
## while it is up.

const REFRESH_INTERVAL := 0.25

const COMMANDS := [
	"1 +$50,000", "2 give a compact", "3 give a coupe", "4 give the exotic",
	"5 damage the nearest", "6 repair the nearest", "7 +20,000 km",
	"8 condition to 40%", "9 rent both garages", "0 store the nearest",
	"Q retrieve everything", "W give a room of furniture", "E deliver now",
	"R rent the premium flat", "T lifestyle recalculated",
	"Y discover every listing", "U buy the cheapest", "I sign a tenant",
	"J skip 7 days", "K wear a property out",
]

var _label: Label = null
var _timer: float = 0.0


func _ready() -> void:
	layer = 100
	_build_label()
	visible = false
	set_process(false)


func _build_label() -> void:
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(18.0, 120.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	add_child(panel)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.043, 0.043, 0.059, 0.82)
	box.set_content_margin_all(10.0)
	box.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", box)

	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.90, 0.90, 0.96))
	panel.add_child(_label)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_ownership_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return

	match (event as InputEventKey).keycode:
		KEY_1: EconomyManager.deposit(50000, "Debug funds")
		KEY_2: _give(&"compact")
		KEY_3: _give(&"coupe")
		KEY_4: _give(&"exotic")
		KEY_5: _damage_nearest()
		KEY_6: _repair_nearest()
		KEY_7: _add_mileage()
		KEY_8: _set_condition(40.0)
		KEY_9: _rent_garages()
		KEY_0: _store_nearest()
		KEY_Q: _retrieve_all()
		KEY_W: _give_furniture()
		KEY_E: HomeManager.deliver_now()
		KEY_R: _rent_premium()
		KEY_T: LifestyleManager.refresh()
		KEY_Y: _discover_listings()
		KEY_U: _buy_cheapest()
		KEY_I: _sign_a_tenant()
		KEY_J: TimeManager.advance_minutes(7 * 1440)
		KEY_K: _wear_property()
		_: return
	get_viewport().set_input_as_handled()
	_refresh()


# --- Commands ------------------------------------------------------------

func _spawn_spot() -> Transform3D:
	var player := GameManager.player
	if player == null:
		return Transform3D.IDENTITY
	return Transform3D(Basis.IDENTITY, player.global_position + Vector3(0.0, 0.4, 6.0))


func _give(model_id: StringName) -> void:
	VehicleRegistry.grant(model_id, _spawn_spot())


## The player's own car nearest to them, which is what every "the nearest"
## command below acts on.
func _nearest() -> OwnedVehicle:
	var player := GameManager.player
	if player == null:
		return null
	var best: OwnedVehicle = null
	var best_distance := INF
	for record in VehicleRegistry.get_fleet():
		var where := record.position
		if record.is_spawned():
			where = record.node.global_position
		var distance := where.distance_to(player.global_position)
		if distance < best_distance:
			best = record
			best_distance = distance
	return best


func _damage_nearest() -> void:
	var record := _nearest()
	if record == null:
		return
	record.health = record.max_health() * 0.3
	record.condition = maxf(record.condition - 25.0, 1.0)
	if record.is_spawned():
		record.node.set_health(record.health)
	VehicleRegistry.fleet_changed.emit()


func _repair_nearest() -> void:
	var record := _nearest()
	if record == null:
		return
	record.health = record.max_health()
	record.condition = 100.0
	if record.is_spawned():
		record.node.restore_health()
	VehicleRegistry.fleet_changed.emit()


func _add_mileage() -> void:
	var record := _nearest()
	if record != null:
		record.mileage_km += 20000.0
		VehicleRegistry.fleet_changed.emit()


func _set_condition(value: float) -> void:
	var record := _nearest()
	if record != null:
		record.condition = value
		VehicleRegistry.fleet_changed.emit()


func _rent_garages() -> void:
	for garage in PropertyManager.get_garages():
		if not garage.is_leased_by_player():
			EconomyManager.deposit(garage.move_in_cost(), "Debug funds")
			PropertyManager.lease_garage(garage)


func _store_nearest() -> void:
	var record := _nearest()
	if record == null:
		return
	for garage in PropertyManager.leased_garages():
		if not garage.is_full():
			VehicleRegistry.store(record, garage.garage_id)
			return


func _retrieve_all() -> void:
	for garage in PropertyManager.leased_garages():
		for record in VehicleRegistry.stored_in(garage.garage_id):
			VehicleRegistry.retrieve(record, garage.bay_for(0))


func _give_furniture() -> void:
	for id: StringName in [
		&"bed_double", &"sofa_standard", &"table_standard", &"tv_basic",
		&"lamp_basic", &"plant_small", &"storage_locker", &"rug_basic",
	]:
		HomeManager.grant(id)


func _rent_premium() -> void:
	var home := PropertyManager.residence_by_id(&"central_heights")
	if home == null or home.is_leased_by_player():
		return
	EconomyManager.deposit(home.move_in_cost(), "Debug funds")
	if PropertyManager.lease_residence(home):
		home.set_as_home()


## Puts every board on the map without walking the city, which is the only
## reason the market screen is ever empty in a test.
func _discover_listings() -> void:
	for listing in RealEstate.listings():
		RealEstate.discover(listing.property_id)


func _buy_cheapest() -> void:
	var cheapest: PropertyListing = null
	for listing in RealEstate.listings():
		if cheapest == null or listing.asking_price < cheapest.asking_price:
			cheapest = listing
	if cheapest == null:
		return
	RealEstate.discover(cheapest.property_id)
	if not EconomyManager.can_afford(cheapest.asking_price):
		EconomyManager.deposit(cheapest.asking_price, "Debug funds")
	RealEstate.buy_with_cash(cheapest.property_id)


## Lets the first thing that can be let, at the going rate, to an applicant
## invented on the spot. Saves waiting days for one to turn up.
func _sign_a_tenant() -> void:
	for record in RealEstate.portfolio():
		var unit_index := -1
		if record.is_multi_unit():
			unit_index = -1
			for i in record.unit_count():
				if record.unit_uses[i] != int(PropertyRecord.Use.TENANTED):
					unit_index = i
					break
			if unit_index < 0:
				continue
		elif record.use == PropertyRecord.Use.TENANTED:
			continue
		elif record.use == PropertyRecord.Use.OWNER_OCCUPIED:
			continue
		elif record.use == PropertyRecord.Use.BUSINESS_OCCUPIED:
			continue

		var rent := RealEstate.unit_market_rent(record)
		RealEstate.list_for_rent(record, rent, unit_index)
		var kind := (
			TenantData.Kind.COMMERCIAL if record.kind == PropertyRecord.Kind.COMMERCIAL
			else TenantData.Kind.RESIDENTIAL
		)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var applicant := TenantData.generate(kind, rent, rng, rng.randi_range(900, 9999))
		RealEstate.accept_tenant(record, applicant, unit_index)
		return


func _wear_property() -> void:
	for record in RealEstate.portfolio():
		record.condition = 45.0
	RealEstate.portfolio_changed.emit()


# --- Readout -------------------------------------------------------------

func _refresh() -> void:
	var lines: Array[String] = []
	lines.append("OWNERSHIP")
	lines.append(
		"cash %s   net worth %s   lifestyle %d (%s)" % [
			EconomyManager.get_cash_string(),
			"$%s" % EconomyManager.with_thousands_separator(BusinessManager.net_worth()),
			LifestyleManager.score(), LifestyleManager.tier_name(),
		]
	)
	var parts := LifestyleManager.breakdown()
	lines.append(
		"  home %d  vehicle %d  comfort %d  business %d" % [
			int(parts["home"]), int(parts["vehicle"]), int(parts["comfort"]),
			int(parts["business"])
		]
	)

	lines.append("")
	lines.append("VEHICLES (%d, worth $%s)" % [
		VehicleRegistry.count(),
		EconomyManager.with_thousands_separator(VehicleRegistry.total_value()),
	])
	for record in VehicleRegistry.get_fleet():
		lines.append("  %-18s %7s km  cond %3d%%  hp %3d%%  %s%s" % [
			record.display_name(), EconomyManager.with_thousands_separator(roundi(record.mileage_km)),
			roundi(record.condition), roundi(record.health_fraction() * 100.0),
			"GARAGE" if record.is_stored() else ("spawned" if record.is_spawned() else "parked"),
			"  $%s" % EconomyManager.with_thousands_separator(record.market_value()),
		])

	lines.append("")
	var home := PropertyManager.current_home()
	lines.append("HOME  %s" % (home.address if home != null else "none"))
	if home != null:
		lines.append("  comfort %d%%   furniture lifestyle +%d   storage %d slots" % [
			HomeManager.comfort_of(home.residence_id),
			HomeManager.furniture_lifestyle(home.residence_id),
			HomeManager.storage_slots_for(home.residence_id),
		])
	lines.append("  furniture owned %d, of which %d unplaced, %d on the van" % [
		HomeManager.all_furniture().size(), HomeManager.in_storage().size(),
		HomeManager.pending_count(),
	])
	for garage in PropertyManager.get_garages():
		lines.append("  %-26s %s%s" % [
			garage.display_name,
			garage.occupancy_label() if garage.is_leased_by_player() else "TO LET",
			"  OVERDUE" if garage.is_overdue() else "",
		])

	lines.append("")
	var books := RealEstate.portfolio_summary()
	lines.append("PROPERTY (%d owned, %d for sale)" % [
		int(books["properties"]), RealEstate.listings().size(),
	])
	lines.append("  value $%s   debt $%s   equity $%s   cash flow $%d/7d" % [
		EconomyManager.with_thousands_separator(int(books["market_value"])),
		EconomyManager.with_thousands_separator(int(books["debt"])),
		EconomyManager.with_thousands_separator(int(books["equity"])),
		int(books["cash_flow"]),
	])
	for record in RealEstate.portfolio():
		var loan := RealEstate.mortgage_for(record.property_id)
		lines.append("  %-20s %-18s cond %3d%%  val $%-9s %s" % [
			record.address, record.use_label(), roundi(record.condition),
			EconomyManager.with_thousands_separator(record.market_value),
			"owes $%s" % EconomyManager.with_thousands_separator(loan.remaining_principal)
			if loan != null else "outright",
		])
	for listing in RealEstate.listings():
		lines.append("  %-20s FOR SALE $%-9s %s%s" % [
			listing.address,
			EconomyManager.with_thousands_separator(listing.asking_price),
			listing.yield_label(), "" if listing.discovered else "  (unseen)",
		])

	lines.append("")
	lines.append(" ".join(COMMANDS))
	_label.text = "\n".join(lines)
