extends Control
## The business management screen.
##
## Seven pages over one BusinessInstance: what it is doing, what it holds, what
## it charges, what it stands on, who works there, what it earned and when it
## opens. Everything is rebuilt from the instance on every change rather than
## kept in step by hand, because the shop trades while this is open and a stale
## number here is worse than a slow redraw.

signal opened()
signal closed()
signal empire_requested()

enum Page {
	OVERVIEW, INVENTORY, PRICING, EQUIPMENT, EMPLOYEES, MARKETING, FINANCES, HOURS, SHELF
}

const PAGE_NAMES := {
	Page.OVERVIEW: "OVERVIEW",
	Page.INVENTORY: "INVENTORY",
	Page.PRICING: "PRICING",
	Page.EQUIPMENT: "EQUIPMENT",
	Page.EMPLOYEES: "STAFF",
	Page.MARKETING: "GROWTH",
	Page.FINANCES: "FINANCES",
	Page.HOURS: "HOURS",
}

@onready var _title: Label = %BusinessTitle
@onready var _subtitle: Label = %BusinessSubtitle
@onready var _tabs: HBoxContainer = %BusinessTabs
@onready var _rows: VBoxContainer = %BusinessRows
@onready var _status: Label = %BusinessStatus

var _business: BusinessInstance = null
var _page: Page = Page.OVERVIEW
var _shelf: BusinessEquipment = null
var _transfer_amount: int = 500
## Set by the first press of SELL, cleared by anything else. A business is not
## sold by one click.
var _confirm_sale: bool = false


func _ready() -> void:
	visible = false
	BusinessManager.business_changed.connect(_on_business_changed)
	BusinessManager.candidates_refreshed.connect(_on_candidates_refreshed)
	EconomyManager.cash_changed.connect(_on_cash_changed)


func is_open() -> bool:
	return visible


func get_business() -> BusinessInstance:
	return _business


func open(business: BusinessInstance) -> void:
	if business == null:
		GameManager.notify("YOU DO NOT OWN A BUSINESS", GameManager.Tone.BAD)
		return
	_business = business
	_shelf = null
	if _page == Page.SHELF:
		_page = Page.INVENTORY
	_status.text = ""
	_build_tabs()
	_rebuild()
	visible = true
	opened.emit()


## Opened by walking up to a shelf: the same screen, straight to the page for
## that one unit.
func open_shelf(equipment: BusinessEquipment) -> void:
	if equipment == null or equipment.business == null:
		return
	_business = equipment.business
	_shelf = equipment
	_page = Page.SHELF
	_status.text = ""
	_build_tabs()
	_rebuild()
	visible = true
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_shelf = null
	closed.emit()


# --- Chrome --------------------------------------------------------------

func _build_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	for page in PAGE_NAMES:
		var button := BusinessUIKit.button(PAGE_NAMES[page], 96.0)
		button.toggle_mode = true
		button.button_pressed = _page == page
		button.pressed.connect(_show_page.bind(page))
		_tabs.add_child(button)


## Switches tab from outside — used by the screenshot tool and anything that
## wants to drop the player on a particular page.
func show_tab(page: Page) -> void:
	_show_page(page)


func _show_page(page: Page) -> void:
	_page = page
	_confirm_sale = false
	_shelf = null if page != Page.SHELF else _shelf
	_status.text = ""
	_build_tabs()
	_rebuild()


func _rebuild() -> void:
	if _business == null:
		return
	_title.text = _business.business_name.to_upper()
	var status := _business.status_text()
	_subtitle.text = "%s · %s · %s" % [
		BusinessCatalogue.by_id(_business.type_id).display_name, status,
		BusinessUIKit.money(_business.cash_balance),
	]

	for child in _rows.get_children():
		child.queue_free()

	match _page:
		Page.OVERVIEW: _build_overview()
		Page.INVENTORY: _build_inventory()
		Page.PRICING: _build_pricing()
		Page.EQUIPMENT: _build_equipment()
		Page.EMPLOYEES: _build_employees()
		Page.MARKETING: _build_growth()
		Page.FINANCES: _build_finances()
		Page.HOURS: _build_hours()
		Page.SHELF: _build_shelf()


func _pair(name: String, value: String, colour: Color = BusinessUIKit.TEXT) -> void:
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(name, 14, BusinessUIKit.MUTED),
		BusinessUIKit.value_label(value, 14, colour),
	]))


# --- Overview ------------------------------------------------------------

func _build_overview() -> void:
	var missing := _business.missing_requirements()
	_pair("Status", _business.status_text(), BusinessUIKit.GOOD if _business.is_open() else BusinessUIKit.MUTED)
	if not missing.is_empty():
		_pair("Cannot open — missing", ", ".join(missing), BusinessUIKit.BAD)
	_pair("Business cash", BusinessUIKit.money(_business.cash_balance))
	_pair("Your cash", EconomyManager.get_cash_string())
	_pair("Customers today", str(_business.customer_count_today))
	_pair("Revenue today", BusinessUIKit.money(_business.revenue_today))
	_pair("Expenses today", BusinessUIKit.money(_business.expenses_today()))
	_pair(
		"Profit today", BusinessUIKit.money(_business.profit_today()),
		BusinessUIKit.tone_for(_business.profit_today())
	)
	_pair("Reputation", "%d%%" % roundi(_business.reputation))
	_pair("Profit margin", "%d%%" % roundi(_business.profit_margin() * 100.0))
	_pair("Estimated value", BusinessUIKit.money(_business.estimated_value()), BusinessUIKit.ACCENT)
	if _business.total_debt() > 0:
		_pair("Debt", BusinessUIKit.money(-_business.total_debt()), BusinessUIKit.BAD)
	_pair("Simulation", BusinessManager.simulation_mode(_business))

	_rows.add_child(BusinessUIKit.heading("Move money"))
	var amount := BusinessUIKit.spin(50, 100000, _transfer_amount, 50)
	amount.value_changed.connect(func(value: float) -> void: _transfer_amount = int(value))

	var deposit := BusinessUIKit.button("DEPOSIT TO BUSINESS", 200.0)
	deposit.pressed.connect(_on_deposit_pressed)
	var withdraw := BusinessUIKit.button("WITHDRAW", 130.0)
	withdraw.pressed.connect(_on_withdraw_pressed)
	_rows.add_child(BusinessUIKit.row([amount, deposit, withdraw]))

	_rows.add_child(BusinessUIKit.heading("The whole company"))
	var empire := BusinessUIKit.button("MY COMPANY", 160.0)
	empire.pressed.connect(func() -> void: empire_requested.emit())
	_rows.add_child(BusinessUIKit.row([empire]))

	_rows.add_child(BusinessUIKit.heading("Getting out"))
	var shut := BusinessUIKit.button("CLOSE BUSINESS", 170.0)
	shut.pressed.connect(_on_close_business)
	# Selling asks twice, because it cannot be undone.
	var sell := BusinessUIKit.button(
		"SELL FOR %s" % BusinessUIKit.money(_business.sale_price()) if _confirm_sale
		else "SELL BUSINESS", 210.0
	)
	sell.pressed.connect(_on_sell_pressed)
	_rows.add_child(BusinessUIKit.row([shut, sell]))
	if _confirm_sale:
		_note(
			"Press again to sell %s for %s. The lease ends, the staff go, and it cannot be undone."
			% [_business.business_name, BusinessUIKit.money(_business.sale_price())],
			BusinessUIKit.BAD
		)


func _on_deposit_pressed() -> void:
	var result := BusinessManager.deposit_to_business(_business, _transfer_amount)
	_report_transfer(result, "Moved %s into the business." % BusinessUIKit.money(_transfer_amount))


func _on_withdraw_pressed() -> void:
	var result := BusinessManager.withdraw_from_business(_business, _transfer_amount)
	_report_transfer(result, "Took %s out of the business." % BusinessUIKit.money(_transfer_amount))


func _report_transfer(result: int, success: String) -> void:
	if result == BusinessManager.TransferResult.OK:
		_note(success, BusinessUIKit.GOOD)
		return
	_note("Not enough funds." if result == BusinessManager.TransferResult.NOT_ENOUGH_FUNDS
		else "That transfer is not possible.", BusinessUIKit.BAD)


func _on_close_business() -> void:
	BusinessManager.close_business(_business)
	_confirm_sale = false
	_rebuild()


func _on_sell_pressed() -> void:
	if not _confirm_sale:
		_confirm_sale = true
		_rebuild()
		return
	var proceeds := BusinessManager.sell_business(_business)
	_confirm_sale = false
	_business = BusinessManager.primary_business()
	if _business == null:
		close()
		GameManager.notify("SOLD FOR $%d" % proceeds, GameManager.Tone.GOOD)
		return
	_rebuild()


# --- Inventory -----------------------------------------------------------

func _build_inventory() -> void:
	_pair("Store room", "%d / %d units" % [_business.storage_used(), _business.storage_capacity()])

	var incoming := BusinessManager.outstanding_orders(_business)
	if not incoming.is_empty():
		_rows.add_child(BusinessUIKit.heading("On its way (%d)" % incoming.size()))
		for order in incoming:
			var contents: Array[String] = []
			for item_id in order.items:
				var ordered := ItemCatalogue.by_id(item_id)
				contents.append("%s x%d" % [
					ordered.display_name if ordered != null else String(item_id),
					int(order.items[item_id]),
				])
			_rows.add_child(BusinessUIKit.row([
				BusinessUIKit.stretch_label(", ".join(contents), 14),
				BusinessUIKit.label(order.status_text(), 12, BusinessUIKit.ACCENT),
				BusinessUIKit.label(
					"placed by the manager" if order.automatic else "", 12, BusinessUIKit.MUTED
				),
				BusinessUIKit.value_label("arriving %s" % order.arrival_text(), 13),
			]))

	# A kitchen orders ingredients and sells what it makes from them, so the two
	# lists are not the same one.
	if _business.serves_prepared_goods():
		_rows.add_child(BusinessUIKit.heading("Menu"))
		for product in _business.catalogue():
			var possible := _business.available_units(product)
			_rows.add_child(BusinessUIKit.row([
				BusinessUIKit.stretch_label(product.display_name, 14),
				BusinessUIKit.label(
					"ingredients for %d" % possible, 13,
					BusinessUIKit.BAD if possible <= 0 else BusinessUIKit.MUTED
				),
				BusinessUIKit.value_label(
					"costs %s" % BusinessUIKit.money(_business.cost_basis(product)), 12,
					BusinessUIKit.MUTED
				),
			]))

	_rows.add_child(BusinessUIKit.heading("Order from the supplier"))

	for item in _business.orderable():
		var storage := _business.storage_of(item.id)
		var shelf := _business.shelf_stock_of(item.id)
		var warning := ""
		var colour := BusinessUIKit.TEXT
		var held := storage if _business.serves_prepared_goods() else shelf
		if held == 0:
			warning = "  OUT OF STOCK"
			colour = BusinessUIKit.BAD
		elif held <= BusinessInstance.LOW_STOCK_THRESHOLD:
			warning = "  LOW STOCK"
			colour = BusinessUIKit.BAD

		var quantity := BusinessUIKit.spin(0, 200, 20, 5)
		var order := BusinessUIKit.button("ORDER", 96.0)
		order.pressed.connect(_on_order_pressed.bind(item, quantity))
		var cells: Array = [
			BusinessUIKit.stretch_label("%s%s" % [item.display_name, warning], 14, colour),
			BusinessUIKit.label("storage %d" % storage, 13, BusinessUIKit.MUTED),
		]
		if not _business.serves_prepared_goods():
			cells.append(BusinessUIKit.label("shelf %d" % shelf, 13, BusinessUIKit.MUTED))
		cells.append(BusinessUIKit.label(
			"cost %s" % BusinessUIKit.money(item.get_wholesale_cost()), 13, BusinessUIKit.MUTED
		))
		cells.append(quantity)
		cells.append(order)
		_rows.add_child(BusinessUIKit.row(cells))

	_note(
		"Ordering charges the account now. The supplier takes a few hours to deliver.",
		BusinessUIKit.MUTED
	)


func _on_order_pressed(item: ItemData, quantity: SpinBox) -> void:
	var result := BusinessManager.order_stock(_business, item.id, int(quantity.value))
	if result == BusinessManager.PurchaseResult.OK:
		_note("Ordered %d %s." % [int(quantity.value), item.display_name], BusinessUIKit.GOOD)
	else:
		_note(BusinessManager.describe_purchase(result), BusinessUIKit.BAD)
	_rebuild()


# --- Pricing -------------------------------------------------------------

func _build_pricing() -> void:
	_rows.add_child(BusinessUIKit.heading("What you charge"))
	for item in _business.catalogue():
		var price := BusinessUIKit.spin(0, 500, _business.price_of(item), 1)
		price.value_changed.connect(_on_price_changed.bind(item))
		var margin := _business.margin_of(item)
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(item.display_name, 14),
			BusinessUIKit.label("wholesale %s" % BusinessUIKit.money(item.get_wholesale_cost()), 13, BusinessUIKit.MUTED),
			BusinessUIKit.label("usual %s" % BusinessUIKit.money(item.get_recommended_price()), 13, BusinessUIKit.MUTED),
			price,
			BusinessUIKit.value_label(
				"%+d  ·  %d%% buy" % [margin, roundi(_business.purchase_chance(item) * 100.0)],
				13, BusinessUIKit.tone_for(margin)
			),
		]))
	_note("Charge over the usual price and fewer customers will pay it.", BusinessUIKit.MUTED)


func _on_price_changed(value: float, item: ItemData) -> void:
	_business.set_price(item, int(value))


# --- Equipment -----------------------------------------------------------

func _build_equipment() -> void:
	_rows.add_child(BusinessUIKit.heading("Buy"))
	for definition in EquipmentCatalogue.for_business(_business.type_id):
		var buy := BusinessUIKit.button("BUY %s" % BusinessUIKit.money(definition.purchase_price), 130.0)
		buy.pressed.connect(_on_buy_equipment.bind(definition))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(definition.display_name, 14),
			BusinessUIKit.label(definition.description, 12, BusinessUIKit.MUTED),
			buy,
		]))

	var waiting := BusinessManager.unplaced_equipment(_business)
	_rows.add_child(BusinessUIKit.heading("Delivered — waiting to be placed (%d)" % waiting.size()))
	for equipment_id in waiting:
		var definition := EquipmentCatalogue.by_id(equipment_id)
		if definition == null:
			continue
		var place := BusinessUIKit.button("PLACE", 110.0)
		place.pressed.connect(_on_place_pressed.bind(equipment_id))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(definition.display_name, 14),
			place,
		]))

	_rows.add_child(BusinessUIKit.heading("On the floor (%d)" % _business.equipment.size()))
	for record in _business.equipment:
		var definition := record.data()
		if definition == null:
			continue
		var detail := ""
		if record.is_shelf():
			var item := record.item()
			detail = "empty" if item == null else "%s %d/%d" % [
				item.display_name, record.stock_quantity, record.capacity()
			]
		var move := BusinessUIKit.button("MOVE", 90.0)
		move.pressed.connect(_on_move_pressed.bind(record.slot_id))
		var remove := BusinessUIKit.button("REMOVE", 100.0)
		remove.pressed.connect(_on_remove_pressed.bind(record.slot_id))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(definition.display_name, 14),
			BusinessUIKit.label(detail, 12, BusinessUIKit.MUTED),
			move, remove,
		]))


func _on_buy_equipment(definition: EquipmentData) -> void:
	var result := BusinessManager.buy_equipment(_business, definition.equipment_id)
	if result == BusinessManager.PurchaseResult.OK:
		_note("%s delivered. Place it from this tab." % definition.display_name, BusinessUIKit.GOOD)
	else:
		_note(BusinessManager.describe_purchase(result), BusinessUIKit.BAD)
	_rebuild()


func _on_place_pressed(equipment_id: StringName) -> void:
	var controller := _placement()
	var unit := RetailUnit.for_business(_business, get_tree())
	if controller == null or unit == null:
		_note("Go to the shop to place equipment.", BusinessUIKit.BAD)
		return
	if not unit.is_player_inside():
		_note("You have to be inside the unit to place equipment.", BusinessUIKit.BAD)
		return
	GameManager.close_menus()
	controller.begin(_business, unit, equipment_id)


func _on_move_pressed(slot_id: int) -> void:
	var controller := _placement()
	var unit := RetailUnit.for_business(_business, get_tree())
	if controller == null or unit == null or not unit.is_player_inside():
		_note("You have to be inside the unit to move equipment.", BusinessUIKit.BAD)
		return
	GameManager.close_menus()
	controller.begin_move(_business, unit, slot_id)


func _on_remove_pressed(slot_id: int) -> void:
	var record := _business.equipment_by_slot(slot_id)
	if record == null:
		return
	var equipment_id := record.equipment_id
	_business.remove_equipment(slot_id)
	BusinessManager.return_unplaced(_business, equipment_id)
	_note("Taken back to the delivery pile. Anything on it went to the store room.", BusinessUIKit.MUTED)
	_rebuild()


func _placement() -> PlacementController:
	return get_tree().get_first_node_in_group(&"placement_controller") as PlacementController


# --- Employees -----------------------------------------------------------

func _build_employees() -> void:
	_rows.add_child(BusinessUIKit.heading("Your staff (%d)" % _business.employees.size()))
	if _business.employees.is_empty():
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Nobody. Customers will queue and leave.", 13, BusinessUIKit.MUTED)
		]))

	for worker in _business.employees:
		var start := BusinessUIKit.spin(0, 23, worker.shift_start_hour, 1)
		start.value_changed.connect(func(value: float) -> void:
			worker.shift_start_hour = int(value)
			BusinessManager.business_changed.emit(_business)
		)
		var finish := BusinessUIKit.spin(0, 23, worker.shift_end_hour, 1)
		finish.value_changed.connect(func(value: float) -> void:
			worker.shift_end_hour = int(value)
			BusinessManager.business_changed.emit(_business)
		)
		var role := OptionButton.new()
		for name in EmployeeData.Role.keys():
			role.add_item(String(name).capitalize())
		role.selected = int(worker.role)
		role.custom_minimum_size = Vector2(120, 30)
		role.item_selected.connect(func(index: int) -> void:
			worker.assign_role(index as EmployeeData.Role)
			BusinessManager.business_changed.emit(_business)
		)
		var dismiss := BusinessUIKit.button("DISMISS", 100.0)
		dismiss.pressed.connect(_on_dismiss_pressed.bind(worker))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(worker.employee_name, 14),
			role,
			BusinessUIKit.label("skill %d" % worker.relevant_skill(), 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("$%d/h" % worker.hourly_wage, 13, BusinessUIKit.MUTED),
			BusinessUIKit.label(
				"served %d today" % worker.customers_served_today, 12, BusinessUIKit.MUTED
			),
			start, finish, dismiss,
		]))

	_build_manager_settings()

	_rows.add_child(BusinessUIKit.heading("Available workers"))
	for candidate in BusinessManager.get_candidates():
		var wanted := OptionButton.new()
		for name in EmployeeData.Role.keys():
			wanted.add_item(String(name).capitalize())
		wanted.selected = int(EmployeeData.Role.CASHIER)
		wanted.custom_minimum_size = Vector2(120, 30)
		var hire := BusinessUIKit.button("HIRE", 90.0)
		hire.pressed.connect(_on_hire_pressed.bind(candidate, wanted))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(candidate.employee_name, 14),
			BusinessUIKit.label("till %d" % candidate.skill_checkout, 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("stock %d" % candidate.skill_stocking, 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("bar %d" % candidate.skill_barista, 12, BusinessUIKit.MUTED),
			BusinessUIKit.label("mgmt %d" % candidate.skill_management, 12, BusinessUIKit.MUTED),
			wanted, hire,
		]))


## What the manager may do without being asked. Every one of these is off until
## the player turns it on: automation that spends money nobody authorised is a
## bug however convenient it is.
func _build_manager_settings() -> void:
	var boss := _business.manager()
	_rows.add_child(BusinessUIKit.heading("Manager"))
	if boss == null:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(
				"No manager. Hire one to have the shop run itself while you are away.",
				13, BusinessUIKit.MUTED
			)
		]))
		return

	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("%s runs this place" % boss.employee_name, 14),
		BusinessUIKit.label(
			"management %d  ·  $%d/h" % [boss.skill_management, boss.hourly_wage],
			12, BusinessUIKit.MUTED
		),
	]))

	var open_toggle := _toggle("Open and close to the published hours", _business.auto_open)
	open_toggle.toggled.connect(func(on: bool) -> void:
		_business.auto_open = on
		_business.changed.emit()
	)
	var restock_toggle := _toggle("Keep the shelves filled from the store room", _business.auto_restock)
	restock_toggle.toggled.connect(func(on: bool) -> void:
		_business.auto_restock = on
		_business.changed.emit()
	)
	var order_toggle := _toggle("Reorder stock when it runs low", _business.auto_order)
	order_toggle.toggled.connect(func(on: bool) -> void:
		_business.auto_order = on
		_business.changed.emit()
	)
	_rows.add_child(BusinessUIKit.row([open_toggle]))
	_rows.add_child(BusinessUIKit.row([restock_toggle]))
	_rows.add_child(BusinessUIKit.row([order_toggle]))

	var budget := BusinessUIKit.spin(0, 5000, _business.auto_order_budget, 50)
	budget.value_changed.connect(func(value: float) -> void:
		_business.auto_order_budget = int(value)
	)
	var minimum := BusinessUIKit.spin(0, 200, _business.auto_order_minimum, 5)
	minimum.value_changed.connect(func(value: float) -> void:
		_business.auto_order_minimum = int(value)
	)
	var target := BusinessUIKit.spin(0, 300, _business.auto_order_target, 5)
	target.value_changed.connect(func(value: float) -> void:
		_business.auto_order_target = int(value)
	)
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Order up to, when below, to a total of", 13, BusinessUIKit.MUTED),
		budget, minimum, target,
	]))


func _toggle(text: String, pressed: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	box.add_theme_font_size_override("font_size", 13)
	return box

	var refresh := BusinessUIKit.button("NEW CANDIDATES", 170.0)
	refresh.pressed.connect(func() -> void: BusinessManager.refresh_candidates())
	_rows.add_child(BusinessUIKit.row([refresh]))
	_note("Wages are charged for the hours actually worked, when the shift ends.", BusinessUIKit.MUTED)


func _on_hire_pressed(candidate: EmployeeData, role: OptionButton) -> void:
	BusinessManager.hire(_business, candidate, role.selected)
	_rebuild()


func _on_dismiss_pressed(worker: EmployeeData) -> void:
	BusinessManager.fire(_business, worker.employee_id)
	_rebuild()


# --- Growth: marketing and upgrades --------------------------------------

func _build_growth() -> void:
	_rows.add_child(BusinessUIKit.heading("Marketing"))
	var running := _business.active_campaigns()
	if running.is_empty():
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Nothing running.", 13, BusinessUIKit.MUTED)
		]))
	for campaign in running:
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(campaign.display_name, 14, BusinessUIKit.GOOD),
			BusinessUIKit.label(
				"+%d%% customers" % roundi(campaign.demand_bonus * 100.0), 12, BusinessUIKit.MUTED
			),
			BusinessUIKit.value_label(
				"%d days left" % campaign.days_left(TimeManager.day_index), 13
			),
		]))

	for campaign in MarketingCampaign.catalogue():
		var start := BusinessUIKit.button("START %s" % BusinessUIKit.money(campaign.cost), 150.0)
		start.pressed.connect(_on_campaign_pressed.bind(campaign))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(campaign.display_name, 14),
			BusinessUIKit.label("%d days" % campaign.duration_days, 12, BusinessUIKit.MUTED),
			BusinessUIKit.label(
				"+%d%% customers" % roundi(campaign.demand_bonus * 100.0), 12, BusinessUIKit.MUTED
			),
			start,
		]))
	_note(
		"Advertising brings people in. It does not make them buy — that is what your prices do.",
		BusinessUIKit.MUTED
	)

	_rows.add_child(BusinessUIKit.heading("Upgrades"))
	for upgrade in BusinessUpgrade.available_for(_business.type_id):
		var owned := _business.has_upgrade(upgrade.upgrade_id)
		var buy := BusinessUIKit.button(
			"FITTED" if owned else "BUY %s" % BusinessUIKit.money(upgrade.cost), 150.0
		)
		buy.disabled = owned
		buy.pressed.connect(_on_upgrade_pressed.bind(upgrade))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(
				upgrade.display_name, 14,
				BusinessUIKit.GOOD if owned else BusinessUIKit.TEXT
			),
			BusinessUIKit.label(upgrade.description, 12, BusinessUIKit.MUTED),
			buy,
		]))


func _on_campaign_pressed(campaign: MarketingCampaign) -> void:
	var result := BusinessManager.start_campaign(_business, campaign.campaign_id)
	if result == BusinessManager.PurchaseResult.OK:
		_note("%s running for %d days." % [campaign.display_name, campaign.duration_days], BusinessUIKit.GOOD)
	else:
		_note(BusinessManager.describe_purchase(result), BusinessUIKit.BAD)
	_rebuild()


func _on_upgrade_pressed(upgrade: BusinessUpgrade) -> void:
	var result := BusinessManager.buy_upgrade(_business, upgrade.upgrade_id)
	if result == BusinessManager.PurchaseResult.OK:
		_note("%s fitted." % upgrade.display_name, BusinessUIKit.GOOD)
	else:
		_note(BusinessManager.describe_purchase(result), BusinessUIKit.BAD)
	_rebuild()


# --- Finances ------------------------------------------------------------

func _build_finances() -> void:
	_rows.add_child(BusinessUIKit.heading("Today"))
	_pair("Revenue", BusinessUIKit.money(_business.revenue_today), BusinessUIKit.GOOD)
	_pair("Stock ordered", BusinessUIKit.money(-_business.inventory_spend_today))
	_pair("Wages", BusinessUIKit.money(-_business.wages_today))
	_pair("Rent", BusinessUIKit.money(-_business.rent_today))
	_pair("Equipment", BusinessUIKit.money(-_business.equipment_spend_today))
	_pair("Other", BusinessUIKit.money(-_business.other_expense_today))
	_pair(
		"Profit", BusinessUIKit.money(_business.profit_today()),
		BusinessUIKit.tone_for(_business.profit_today())
	)
	_pair("Cost of goods sold", BusinessUIKit.money(_business.cogs_today))
	_pair("Gross margin", BusinessUIKit.money(_business.revenue_today - _business.cogs_today))
	_pair("Units sold", str(_business.units_sold_today))
	_pair("Lost sales", str(_business.lost_sales_today), BusinessUIKit.BAD if _business.lost_sales_today > 0 else BusinessUIKit.TEXT)

	_rows.add_child(BusinessUIKit.heading("Lifetime"))
	_pair("Revenue", BusinessUIKit.money(_business.lifetime_revenue))
	_pair("Expenses", BusinessUIKit.money(_business.lifetime_expenses))
	_pair(
		"Profit", BusinessUIKit.money(_business.lifetime_profit()),
		BusinessUIKit.tone_for(_business.lifetime_profit())
	)
	_pair("Units sold", str(_business.lifetime_units_sold))

	var week := _business.weekly_report()
	if int(week["days"]) > 0:
		_rows.add_child(BusinessUIKit.heading("This week (%d days)" % int(week["days"])))
		_pair("Revenue", BusinessUIKit.money(int(week["revenue"])), BusinessUIKit.GOOD)
		_pair("Cost of goods sold", BusinessUIKit.money(-int(week["cogs"])))
		_pair("Wages", BusinessUIKit.money(-int(week["wages"])))
		_pair("Rent", BusinessUIKit.money(-int(week["rent"])))
		_pair("Marketing", BusinessUIKit.money(-int(week["marketing"])))
		_pair("Utilities", BusinessUIKit.money(-int(week["utilities"])))
		_pair("Loan payments", BusinessUIKit.money(-int(week["loans"])))
		_pair(
			"Net profit", BusinessUIKit.money(int(week["profit"])),
			BusinessUIKit.tone_for(int(week["profit"]))
		)
		_pair("Customers", str(int(week["customers"])))
		_pair("Average sale", "$%.2f" % float(week["average_sale"]))
		_pair("Margin", "%d%%" % roundi(float(week["margin"]) * 100.0))

	if not _business.last_report.is_empty():
		_rows.add_child(BusinessUIKit.heading("Yesterday's report"))
		var report := _business.last_report
		_pair("Customers", str(report.get("customers", 0)))
		_pair("Revenue", BusinessUIKit.money(int(report.get("revenue", 0))))
		_pair("Expenses", BusinessUIKit.money(int(report.get("expenses", 0))))
		_pair(
			"Profit", BusinessUIKit.money(int(report.get("profit", 0))),
			BusinessUIKit.tone_for(int(report.get("profit", 0)))
		)
		_pair("Lost sales", str(report.get("lost_sales", 0)))


# --- Hours ---------------------------------------------------------------

func _build_hours() -> void:
	var open_hour := BusinessUIKit.spin(0, 23, _business.opening_hour, 1)
	open_hour.value_changed.connect(func(value: float) -> void:
		_business.opening_hour = int(value)
		_business.changed.emit()
	)
	var close_hour := BusinessUIKit.spin(0, 23, _business.closing_hour, 1)
	close_hour.value_changed.connect(func(value: float) -> void:
		_business.closing_hour = int(value)
		_business.changed.emit()
	)
	_rows.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Opening hours", 14, BusinessUIKit.MUTED),
		open_hour, BusinessUIKit.label("to", 13, BusinessUIKit.MUTED), close_hour,
	]))

	_pair("Right now", "%02d:00" % TimeManager.hour)
	_pair("Status", _business.status_text(), BusinessUIKit.GOOD if _business.is_open() else BusinessUIKit.MUTED)

	var missing := _business.missing_requirements()
	if not missing.is_empty():
		_pair("BUSINESS CANNOT OPEN — missing", ", ".join(missing), BusinessUIKit.BAD)

	var open_now := BusinessUIKit.button("OPEN BUSINESS", 160.0)
	open_now.pressed.connect(_on_force_open)
	var close_now := BusinessUIKit.button("CLOSE BUSINESS", 160.0)
	close_now.pressed.connect(_on_force_closed)
	var schedule := BusinessUIKit.button("FOLLOW HOURS", 150.0)
	schedule.pressed.connect(_on_follow_schedule)
	_rows.add_child(BusinessUIKit.row([open_now, close_now, schedule]))
	_note(
		"A manual open lasts until you change it. The shop still cannot open without a till and stock.",
		BusinessUIKit.MUTED
	)


func _on_force_open() -> void:
	_business.manual_override = BusinessInstance.Override.FORCE_OPEN
	_business.set_open(_business.should_be_open(TimeManager.hour))
	if not _business.can_open():
		_note("BUSINESS CANNOT OPEN — missing %s" % ", ".join(_business.missing_requirements()), BusinessUIKit.BAD)
	_rebuild()


func _on_force_closed() -> void:
	_business.manual_override = BusinessInstance.Override.FORCE_CLOSED
	_business.set_open(false)
	_rebuild()


func _on_follow_schedule() -> void:
	_business.manual_override = BusinessInstance.Override.NONE
	_business.set_open(_business.should_be_open(TimeManager.hour))
	_rebuild()


# --- One shelf -----------------------------------------------------------

func _build_shelf() -> void:
	if _shelf == null or _shelf.placed == null:
		_build_inventory()
		return
	var record := _shelf.placed
	var item := record.item()
	_pair("Shelf", "%s  ·  %d / %d" % [
		"empty" if item == null else item.display_name, record.stock_quantity, record.capacity()
	])
	_pair("Store room", "%d / %d units" % [_business.storage_used(), _business.storage_capacity()])

	_rows.add_child(BusinessUIKit.heading("Stock this shelf"))
	for candidate in _business.catalogue():
		var held := _business.storage_of(candidate.id)
		var quantity := BusinessUIKit.spin(1, 200, mini(maxi(held, 1), record.capacity()), 1)
		var restock := BusinessUIKit.button("RESTOCK", 110.0)
		restock.disabled = held <= 0
		restock.pressed.connect(_on_restock_pressed.bind(candidate, quantity))
		_rows.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label(candidate.display_name, 14),
			BusinessUIKit.label("in store room %d" % held, 13, BusinessUIKit.MUTED),
			quantity, restock,
		]))

	var clear := BusinessUIKit.button("EMPTY SHELF", 140.0)
	clear.pressed.connect(_on_empty_shelf)
	_rows.add_child(BusinessUIKit.row([clear]))


func _on_restock_pressed(item: ItemData, quantity: SpinBox) -> void:
	var moved := _business.stock_shelf(_shelf.placed.slot_id, item.id, int(quantity.value))
	if moved <= 0:
		_note("Nothing moved — check the store room and the shelf's space.", BusinessUIKit.BAD)
	else:
		_note("Moved %d %s onto the shelf." % [moved, item.display_name], BusinessUIKit.GOOD)
	_rebuild()


func _on_empty_shelf() -> void:
	var record := _shelf.placed
	if record.stock_quantity > 0 and record.stock_item != &"":
		var returned := _business.add_storage(record.stock_item, record.stock_quantity)
		record.stock_quantity -= returned
		_business.changed.emit()
	_rebuild()


# --- Plumbing ------------------------------------------------------------

func _note(text: String, colour: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", colour)


func _on_business_changed(business: BusinessInstance) -> void:
	if visible and business == _business:
		_rebuild()


func _on_candidates_refreshed() -> void:
	if visible and _page == Page.EMPLOYEES:
		_rebuild()


func _on_cash_changed(_balance: int, _delta: int) -> void:
	if visible and (_page == Page.OVERVIEW or _page == Page.EQUIPMENT):
		_rebuild()
