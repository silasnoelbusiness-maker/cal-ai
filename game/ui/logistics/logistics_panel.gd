class_name LogisticsPanel
extends Control
## The company's distribution, on one screen.
##
## Five tabs because there are genuinely five questions: what is in the
## warehouse, what is on order, what is moving, what runs on a schedule, and
## what is driving it. Every figure is read from LogisticsManager rather than
## worked out here, so a number on this screen and a number in the simulation
## cannot drift apart.

signal opened()
signal closed()

enum Page { OVERVIEW, STOCK, SHIPMENTS, ROUTES, FLEET }

const PAGE_NAMES := {
	Page.OVERVIEW: "OVERVIEW",
	Page.STOCK: "STOCK",
	Page.SHIPMENTS: "SHIPMENTS",
	Page.ROUTES: "ROUTES",
	Page.FLEET: "FLEET",
}

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _tabs: HBoxContainer = null
var _page: Page = Page.OVERVIEW
## The line being ordered on the stock page.
var _order_item: StringName = &""
var _order_units: int = 200
## The branch a manual transfer is being sent to.
var _transfer_target: StringName = &""


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(960, 660))
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	_parts["body"].add_child(_tabs)
	_body = ScreenKit.scroller(_parts["body"])
	LogisticsManager.transfer_created.connect(_on_changed)
	LogisticsManager.transfer_delivered.connect(_on_changed)
	LogisticsManager.route_changed.connect(_on_route_changed)


func is_open() -> bool:
	return visible


func open(page: Page = Page.OVERVIEW) -> void:
	_page = page
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


func show_tab(page: Page) -> void:
	_page = page
	_rebuild()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _tabs.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()

	var figures := LogisticsManager.summary()
	_parts["title"].text = "LOGISTICS"
	_parts["subtitle"].text = "%d warehouse%s  ·  %d units held  ·  %d in transit" % [
		int(figures["warehouses"]), "" if int(figures["warehouses"]) == 1 else "s",
		int(figures["stock_units"]), int(figures["in_transit"]),
	]
	_parts["status"].text = ""

	for page: Page in PAGE_NAMES:
		var button := BusinessUIKit.button(String(PAGE_NAMES[page]), 110.0)
		button.toggle_mode = true
		button.button_pressed = _page == page
		button.pressed.connect(show_tab.bind(page))
		_tabs.add_child(button)

	if not LogisticsManager.has_warehouse():
		_build_no_warehouse()
	else:
		match _page:
			Page.STOCK:
				_build_stock()
			Page.SHIPMENTS:
				_build_shipments()
			Page.ROUTES:
				_build_routes()
			Page.FLEET:
				_build_fleet()
			_:
				_build_overview(figures)

	var close_button := BusinessUIKit.button("CLOSE", 130.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)


func _build_no_warehouse() -> void:
	_body.add_child(ScreenKit.heading("NO WAREHOUSE"))
	_body.add_child(BusinessUIKit.label(
		"Every branch orders its own stock direct from the supplier, which is "
		+ "the right way to run one or two of them.\n\n"
		+ "A depot is worth taking on once there are enough shops that buying "
		+ "in bulk beats the rent. There is one on Dock Road in Harbour Row.",
		14, ScreenKit.MUTED
	))


# --- Overview ------------------------------------------------------------

func _build_overview(figures: Dictionary) -> void:
	for warehouse in LogisticsManager.warehouses():
		_body.add_child(ScreenKit.heading(warehouse.display_name.to_upper()))
		_body.add_child(ScreenKit.stat_bar(
			"Capacity", roundi(warehouse.fullness() * 100.0), warehouse.fullness() > 0.9
		))
		_body.add_child(ScreenKit.row(
			"Held", "%d of %d units" % [warehouse.used(), warehouse.capacity()]
		))
		_body.add_child(ScreenKit.row("Stock value", ScreenKit.money(warehouse.stock_value())))
		_body.add_child(ScreenKit.row("Racks", "%d" % warehouse.racks))
		_body.add_child(ScreenKit.row(
			"Dispatch left today", "%d units" % warehouse.dispatch_room()
		))

		var rack := BusinessUIKit.button("BUY RACKING", 160.0)
		rack.disabled = not warehouse.can_add_racks()
		rack.pressed.connect(func() -> void: _buy_rack(warehouse))
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(
				"+%d units for %s" % [
					WarehouseInstance.RACK_CAPACITY, ScreenKit.money(RACK_PRICE)
				], 13, ScreenKit.MUTED
			),
			rack,
		]))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("TODAY"))
	_body.add_child(ScreenKit.row("Shipments in transit", str(int(figures["in_transit"]))))
	_body.add_child(ScreenKit.row("Waiting to go", str(int(figures["queued"]))))
	_body.add_child(ScreenKit.row("Routes", str(int(figures["routes"]))))
	_body.add_child(ScreenKit.row("Vans", str(int(figures["vans"]))))
	_body.add_child(ScreenKit.row("Drivers", str(int(figures["drivers"]))))

	_body.add_child(ScreenKit.spacer(10))
	_body.add_child(ScreenKit.heading("SINCE YOU STARTED"))
	_body.add_child(ScreenKit.row(
		"Units distributed", str(int(figures["units_distributed"]))
	))
	_body.add_child(ScreenKit.row(
		"Shipments completed", str(int(figures["shipments_completed"]))
	))
	_body.add_child(ScreenKit.row(
		"Saved buying in bulk", ScreenKit.money(int(figures["bulk_savings"])), true
	))
	_body.add_child(ScreenKit.row(
		"Spent on delivery", ScreenKit.money(int(figures["delivery_costs"]))
	))
	var payer := LogisticsManager.funding_business()
	_body.add_child(ScreenKit.row(
		"Paid for by", payer.business_name if payer != null else "Nobody — set a branch"
	))


## What a rack costs. Here rather than on the warehouse because it is a price,
## and prices belong with the shop that charges them.
const RACK_PRICE := 640


func _buy_rack(warehouse: WarehouseInstance) -> void:
	var payer := LogisticsManager.funding_business()
	if payer == null:
		_note("No branch is set to pay for the depot.", ScreenKit.BAD)
		return
	if not payer.debit(RACK_PRICE, "Warehouse racking", &"equipment"):
		_note("%s cannot afford that." % payer.business_name, ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	warehouse.racks += 1
	AudioManager.play(&"purchase", AudioBuses.SFX, -10.0)
	_rebuild()


# --- Stock ---------------------------------------------------------------

func _build_stock() -> void:
	var warehouse := LogisticsManager.primary_warehouse()
	if warehouse == null:
		return
	_body.add_child(ScreenKit.heading("WHAT IS IN THE DEPOT"))
	var lines := warehouse.lines()
	if lines.is_empty():
		_body.add_child(BusinessUIKit.label("Empty.", 14, ScreenKit.MUTED))
	for line in lines:
		var reserved := int(line["reserved"])
		_body.add_child(ScreenKit.row(
			String(line["name"]),
			"%d held%s" % [
				int(line["held"]),
				"  ·  %d reserved" % reserved if reserved > 0 else "",
			]
		))

	_body.add_child(ScreenKit.spacer(10))
	_build_bulk_order(warehouse)


## The bulk order form. Everything the company's branches buy, in one list,
## with the discount shown before the player commits.
func _build_bulk_order(warehouse: WarehouseInstance) -> void:
	_body.add_child(ScreenKit.heading("BUY IN BULK"))
	var lines := _orderable_items()
	if lines.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Found a business first — the depot stocks what your branches sell.",
			13, ScreenKit.MUTED
		))
		return
	if _order_item == &"" or not lines.has(ItemCatalogue.by_id(_order_item)):
		_order_item = lines[0].id

	var picker := OptionButton.new()
	for i in lines.size():
		picker.add_item(lines[i].display_name, i)
		if lines[i].id == _order_item:
			picker.selected = i
	picker.item_selected.connect(func(index: int) -> void:
		_order_item = lines[index].id
		_rebuild()
	)
	var units := BusinessUIKit.spin(10, 800, float(_order_units), 10)
	units.value_changed.connect(func(value: float) -> void:
		_order_units = int(value)
		_rebuild()
	)
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Line", 13, ScreenKit.MUTED), picker,
	]))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Units", 13, ScreenKit.MUTED), units,
	]))

	var quote := LogisticsManager.bulk_quote(ItemCatalogue.by_id(_order_item), _order_units)
	_body.add_child(ScreenKit.row("List price", ScreenKit.money(int(quote["gross"]))))
	_body.add_child(ScreenKit.row(
		"Bulk discount", "%d%%  ·  saves %s" % [
			roundi(float(quote["discount"]) * 100.0), ScreenKit.money(int(quote["saved"]))
		]
	))
	_body.add_child(ScreenKit.row("To pay", ScreenKit.money(int(quote["cost"])), true))
	_body.add_child(ScreenKit.row("Room left", "%d units" % warehouse.room_left()))

	var payer := LogisticsManager.funding_business()
	var buy := BusinessUIKit.button("PLACE ORDER", 170.0)
	buy.disabled = payer == null or payer.cash_balance < int(quote["cost"]) \
		or warehouse.room_left() < 10
	buy.pressed.connect(func() -> void:
		var result := LogisticsManager.order_to_warehouse(
			warehouse, _order_item, _order_units
		)
		if result != BusinessManager.PurchaseResult.OK:
			AudioManager.play_ui(&"ui_error")
			_note(BusinessManager.describe_purchase(result), ScreenKit.BAD)
			return
		_rebuild()
	)
	_parts["actions"].add_child(buy)
	if buy.disabled and payer != null:
		_note(
			"%s has %s and the order costs %s." % [
				payer.business_name, ScreenKit.money(payer.cash_balance),
				ScreenKit.money(int(quote["cost"])),
			], ScreenKit.MUTED
		)


## Everything any branch of the company buys, without duplicates.
func _orderable_items() -> Array[ItemData]:
	var found: Array[ItemData] = []
	for business in BusinessManager.get_businesses():
		for item in business.orderable():
			if not found.has(item):
				found.append(item)
	return found


func _note(text: String, colour: Color) -> void:
	_parts["status"].text = text
	_parts["status"].add_theme_color_override("font_color", colour)


func _on_changed(_order: TransferOrder) -> void:
	if visible:
		_rebuild()


func _on_route_changed() -> void:
	if visible:
		_rebuild()


# --- Shipments -----------------------------------------------------------

func _build_shipments() -> void:
	_body.add_child(ScreenKit.heading("ON THE ROAD"))
	var now := TimeManager.total_minutes
	var live := LogisticsManager.open_transfers()
	if live.is_empty():
		_body.add_child(BusinessUIKit.label("Nothing moving.", 14, ScreenKit.MUTED))
	for order in live:
		_body.add_child(_shipment_card(order, now))

	_body.add_child(ScreenKit.spacer(10))
	_build_send_form()


func _shipment_card(order: TransferOrder, now: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(
			"%s → %s" % [
				LogisticsManager.call("_place_name", order.source_kind, order.source_id),
				LogisticsManager.call(
					"_place_name", order.destination_kind, order.destination_id
				),
			], 15, ScreenKit.TEXT
		),
		BusinessUIKit.value_label(
			order.eta_text(now), 14,
			ScreenKit.ACCENT if order.is_moving() else ScreenKit.MUTED
		),
	]))
	var driver := BusinessManager.employee_by_id(order.assigned_driver_id)
	var van := CompanyFleet.vehicle_by_id(order.assigned_vehicle_id)
	column.add_child(BusinessUIKit.label(
		"%s  ·  %s  ·  %s%s" % [
			order.cargo_text(), order.status_name(),
			"you" if order.player_driven
				else (driver.employee_name if driver != null else "no driver"),
			"  ·  %s" % van.display_name() if van != null else "",
		], 12, ScreenKit.MUTED
	))
	if not order.note.is_empty():
		column.add_child(BusinessUIKit.label(order.note, 12, ScreenKit.BAD))

	if order.can_cancel():
		var cancel := BusinessUIKit.button("CANCEL", 110.0)
		cancel.pressed.connect(func() -> void:
			LogisticsManager.cancel_transfer(order)
			_rebuild()
		)
		var send := BusinessUIKit.button("SEND NOW", 120.0)
		send.pressed.connect(func() -> void: _send(order))
		column.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("", 12, ScreenKit.MUTED), send, cancel,
		]))
	return card


func _send(order: TransferOrder) -> void:
	var result := LogisticsManager.dispatch_transfer(order)
	if result != LogisticsManager.TransferResult.OK:
		AudioManager.play_ui(&"ui_error")
		_note(_describe(result), ScreenKit.BAD)
		_rebuild()
		return
	_rebuild()


func _describe(result: LogisticsManager.TransferResult) -> String:
	match result:
		LogisticsManager.TransferResult.NO_VEHICLE:
			return "No van is free. Buy one on the fleet page, or wait."
		LogisticsManager.TransferResult.NO_DRIVER:
			return "Nobody is on shift to drive it."
		LogisticsManager.TransferResult.NOT_ENOUGH_STOCK:
			return "There is not enough of it to send."
		LogisticsManager.TransferResult.NO_ROOM:
			return "There is no room for it at the other end."
		LogisticsManager.TransferResult.SAME_PLACE:
			return "That is where it already is."
		LogisticsManager.TransferResult.NOT_ALLOWED:
			return "That cannot be sent right now."
		_:
			return "That did not go through."


## Sending a branch whatever it is short of, in one press. The detailed form is
## deliberately absent: picking lines and quantities by hand for nine shops is
## the work the warehouse exists to remove.
func _build_send_form() -> void:
	_body.add_child(ScreenKit.heading("TOP UP A BRANCH"))
	var warehouse := LogisticsManager.primary_warehouse()
	if warehouse == null:
		return
	var any := false
	for business in BusinessManager.get_businesses():
		if not business.is_trading():
			continue
		var wanted := LogisticsManager.shortfall_for(business)
		var short_units := 0
		for id: StringName in wanted:
			short_units += int(wanted[id])
		var send := BusinessUIKit.button("SEND", 110.0)
		send.disabled = short_units <= 0
		send.pressed.connect(func() -> void: _top_up(warehouse, business))
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(business.business_name, 14, ScreenKit.TEXT),
			BusinessUIKit.value_label(
				"needs %d units" % short_units if short_units > 0 else "stocked",
				13, ScreenKit.BAD if short_units > 0 else ScreenKit.GOOD
			),
			send,
		]))
		any = true
	if not any:
		_body.add_child(BusinessUIKit.label("No branches trading.", 13, ScreenKit.MUTED))


func _top_up(warehouse: WarehouseInstance, business: BusinessInstance) -> void:
	var wanted := LogisticsManager.shortfall_for(business)
	if wanted.is_empty():
		return
	var made := LogisticsManager.request_transfer(
		TransferOrder.Place.WAREHOUSE, warehouse.warehouse_id,
		TransferOrder.Place.BUSINESS, business.business_id, wanted
	)
	if made["order"] == null:
		_note(_describe(made["result"]), ScreenKit.BAD)
		AudioManager.play_ui(&"ui_error")
		return
	_page = Page.SHIPMENTS
	_rebuild()


# --- Routes --------------------------------------------------------------

func _build_routes() -> void:
	var warehouse := LogisticsManager.primary_warehouse()
	if warehouse == null:
		return
	_body.add_child(ScreenKit.heading("SCHEDULED RUNS"))
	var routes := LogisticsManager.routes()
	if routes.is_empty():
		_body.add_child(BusinessUIKit.label(
			"No routes yet. A route tops its stops up to their own targets on "
			+ "the days it runs, which is the point at which the depot starts "
			+ "saving you work rather than making it.",
			13, ScreenKit.MUTED
		))
	for route in routes:
		_body.add_child(_route_card(route))

	var add := BusinessUIKit.button("NEW ROUTE", 150.0)
	add.pressed.connect(func() -> void:
		LogisticsManager.create_route(warehouse)
		_rebuild()
	)
	_parts["actions"].add_child(add)


func _route_card(route: DeliveryRoute) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)

	var toggle := BusinessUIKit.button("ON" if route.enabled else "OFF", 70.0)
	toggle.toggle_mode = true
	toggle.button_pressed = route.enabled
	toggle.pressed.connect(func() -> void:
		route.enabled = not route.enabled
		_rebuild()
	)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(route.display_name.to_upper(), 15, ScreenKit.TEXT),
		BusinessUIKit.value_label(route.schedule_text(), 13, ScreenKit.MUTED),
		toggle,
	]))

	var hour := BusinessUIKit.spin(0, 23, float(route.departure_hour), 1)
	hour.value_changed.connect(func(value: float) -> void:
		route.departure_hour = int(value)
	)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Leaves at", 13, ScreenKit.MUTED), hour,
	]))

	# Stops, as a row of switches: every branch is either on the run or not.
	for business in BusinessManager.get_businesses():
		var on_route := route.stop_business_ids.has(business.business_id)
		var stop := BusinessUIKit.button("ON RUN" if on_route else "ADD", 100.0)
		stop.pressed.connect(func() -> void:
			if on_route:
				route.remove_stop(business.business_id)
			else:
				route.add_stop(business.business_id)
			_rebuild()
		)
		column.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(business.business_name, 13,
				ScreenKit.TEXT if on_route else ScreenKit.MUTED),
			stop,
		]))

	var remove := BusinessUIKit.button("DELETE", 100.0)
	remove.pressed.connect(func() -> void:
		LogisticsManager.delete_route(route)
		_rebuild()
	)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("", 12, ScreenKit.MUTED), remove,
	]))
	return card


# --- Fleet ---------------------------------------------------------------

func _build_fleet() -> void:
	_body.add_child(ScreenKit.heading("COMPANY VEHICLES"))
	var vans := CompanyFleet.company_vans()
	if vans.is_empty():
		_body.add_child(BusinessUIKit.label(
			"None. A depot with nothing to deliver in is a store room.",
			14, ScreenKit.MUTED
		))
	for van in vans:
		var owner := BusinessManager.by_id(van.owner_id)
		var sell := BusinessUIKit.button("SELL", 90.0)
		sell.disabled = CompanyFleet.is_busy(van)
		sell.pressed.connect(func() -> void:
			CompanyFleet.sell_company_vehicle(van)
			_rebuild()
		)
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(van.display_name(), 15, ScreenKit.TEXT),
			BusinessUIKit.value_label(
				"%d units" % CompanyFleet.cargo_capacity(van), 13, ScreenKit.MUTED
			),
			BusinessUIKit.value_label(
				"OUT" if CompanyFleet.is_busy(van) else "READY", 12,
				ScreenKit.ACCENT if CompanyFleet.is_busy(van) else ScreenKit.GOOD
			),
			sell,
		]))
		_body.add_child(BusinessUIKit.label(
			"%s  ·  %s  ·  owned by %s" % [
				van.condition_label(), CompanyFleet.assignment_text(van),
				owner.business_name if owner != null else "the company",
			], 12, ScreenKit.MUTED
		))

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("BUY A VAN"))
	var payer := LogisticsManager.funding_business()
	var model := VehicleCatalogue.data_for(&"van")
	if model != null:
		_body.add_child(ScreenKit.row("Panel van", ScreenKit.money(model.price_new), true))
		_body.add_child(ScreenKit.row("Carries", "%d units" % CompanyFleet.VAN_CAPACITY))
		_body.add_child(BusinessUIKit.label(
			"Bought with company money and owned by the business, not by you. "
			+ "It counts towards what the company is worth rather than towards "
			+ "your own cars.", 12, ScreenKit.MUTED
		))
		var buy := BusinessUIKit.button("BUY VAN", 150.0)
		buy.disabled = payer == null or payer.cash_balance < model.price_new
		buy.pressed.connect(func() -> void:
			CompanyFleet.buy_for_company(&"van", payer)
			_rebuild()
		)
		_parts["actions"].add_child(buy)

	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("DRIVERS"))
	var drivers := CompanyFleet.drivers()
	if drivers.is_empty():
		_body.add_child(BusinessUIKit.label(
			"Nobody. Hire a driver at any branch — the fleet is the company's, "
			+ "not one shop's.", 13, ScreenKit.MUTED
		))
	for driver in drivers:
		var home := BusinessManager.by_id(driver.assigned_business)
		_body.add_child(ScreenKit.row(
			driver.employee_name,
			"%s  ·  logistics %d  ·  %s" % [
				home.business_name if home != null else "unassigned",
				driver.skill_logistics, driver.schedule_text(),
			]
		))
