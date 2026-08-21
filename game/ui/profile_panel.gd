class_name ProfilePanel
extends Control
## Who the player has become.
##
## The finance screen and the progression screen in one, deliberately: the whole
## point of Phase M is that money and life are not the same measure, and the
## clearest way to say so is to put net worth and lifestyle on the same page and
## let them disagree.

signal opened()
signal closed()

var _parts: Dictionary = {}
var _body: VBoxContainer = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(820, 620))
	_body = ScreenKit.scroller(_parts["body"])
	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func is_open() -> bool:
	return visible


func open() -> void:
	LifestyleManager.refresh()
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()

	_parts["title"].text = "PROFILE"
	_parts["subtitle"].text = "%s, %s" % [TimeManager.get_day_name(), TimeManager.get_time_string()]
	_parts["status"].text = ""

	_build_worth()
	_body.add_child(ScreenKit.spacer(10))
	_build_lifestyle()
	_body.add_child(ScreenKit.spacer(10))
	_build_holdings()


## Every asset counted once. Vehicles come from the registry, so a car in a
## garage counts exactly as much as one at the kerb and neither is counted twice;
## a leased flat and a rented garage are not assets and do not appear. Property
## is counted at market value with the mortgages shown against it, so the two
## lines together are the equity that actually belongs to the player.
func _build_worth() -> void:
	_body.add_child(ScreenKit.heading("NET WORTH"))
	var cash := EconomyManager.cash
	var businesses := BusinessManager.total_business_value()
	var vehicles := VehicleRegistry.total_value()
	var furniture := HomeManager.furniture_resale_value()
	var debt := BusinessManager.total_debt()

	_body.add_child(ScreenKit.row("Cash", ScreenKit.money(cash)))
	_body.add_child(ScreenKit.row("Business equity", ScreenKit.money(businesses)))
	_body.add_child(ScreenKit.row(
		"Vehicles (%d)" % VehicleRegistry.count(), ScreenKit.money(vehicles)
	))
	_body.add_child(ScreenKit.row("Furniture, at resale", ScreenKit.money(furniture)))
	if RealEstate.count() > 0:
		_body.add_child(ScreenKit.row(
			"Property (%d)" % RealEstate.count(),
			ScreenKit.money(RealEstate.total_market_value())
		))
		var owed := RealEstate.total_mortgage_debt()
		if owed > 0:
			_body.add_child(ScreenKit.row("Mortgages", "-%s" % ScreenKit.money(owed)))
	if debt > 0:
		_body.add_child(ScreenKit.row("Debt", "-%s" % ScreenKit.money(debt)))
	_body.add_child(ScreenKit.row("Net worth", ScreenKit.money(BusinessManager.net_worth()), true))
	# The company is worth its own number, and it is not this one. Shown beside
	# net worth rather than folded into it, because confusing the two is how a
	# player talks themselves into thinking a house is an asset of the business.
	if BusinessManager.owned_count() > 0:
		_body.add_child(ScreenKit.row(
			"%s value" % CompanyManager.get_company_name(),
			ScreenKit.money(CompanyManager.company_value())
		))
		_body.add_child(BusinessUIKit.label(
			"Company value is the operating business alone. Net worth is that "
			+ "plus your property, your cars and your cash, less what you owe.",
			12, ScreenKit.MUTED
		))


func _build_lifestyle() -> void:
	_body.add_child(ScreenKit.heading("LIFESTYLE"))
	_body.add_child(ScreenKit.row(
		"%d / 100" % LifestyleManager.score(), LifestyleManager.tier_name(), true
	))
	var parts := LifestyleManager.breakdown()
	_body.add_child(ScreenKit.stat_bar("Home", int(parts["home"])))
	_body.add_child(ScreenKit.stat_bar("Vehicles", int(parts["vehicle"])))
	_body.add_child(ScreenKit.stat_bar("Furnishing", int(parts["comfort"])))
	_body.add_child(ScreenKit.stat_bar("Business", int(parts["business"])))
	_body.add_child(BusinessUIKit.label(
		"What you own and where you live, not what you are worth. The two can "
		+ "differ, and usually should.", 12, ScreenKit.MUTED
	))


func _build_holdings() -> void:
	_body.add_child(ScreenKit.heading("WHAT YOU HAVE"))

	var home := PropertyManager.current_home()
	_body.add_child(ScreenKit.row(
		"Home", "%s  ·  %s" % [home.display_name, home.address] if home != null else "None"
	))
	if home != null:
		_body.add_child(ScreenKit.row(
			"Comfort", "%d%%" % HomeManager.comfort_of(home.residence_id)
		))

	var garages := PropertyManager.leased_garages()
	if garages.is_empty():
		_body.add_child(ScreenKit.row("Garages", "None"))
	for garage in garages:
		_body.add_child(ScreenKit.row(
			garage.display_name, "%s%s" % [
				garage.occupancy_label(), "  ·  RENT OVERDUE" if garage.is_overdue() else ""
			]
		))

	_body.add_child(ScreenKit.row("Businesses", str(BusinessManager.owned_count())))

	var fleet := VehicleRegistry.get_fleet()
	if fleet.is_empty():
		_body.add_child(ScreenKit.row("Vehicles", "None"))
		return
	_body.add_child(ScreenKit.spacer(6))
	for record in fleet:
		_body.add_child(ScreenKit.row(
			record.display_name(),
			"%s  ·  %s  ·  %s  ·  %s" % [
				record.mileage_label(), record.condition_label(),
				ScreenKit.money(record.market_value()), _where(record)
			]
		))


func _where(record: OwnedVehicle) -> String:
	if record.is_stored():
		var garage := PropertyManager.garage_by_id(record.garage_id)
		return garage.display_name if garage != null else "Stored"
	var district := WorldManager.by_id(record.district_id)
	return district.display_name if district != null else "In the city"
