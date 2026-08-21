extends CanvasLayer
## Dev-only business readout, hidden by default.
##
## Third of its kind, and the same rules as the traffic and crime overlays: not
## part of the HUD, deleted by removing this node and its input action.
##
## F10 toggles it. The commands are number keys, and they only do anything while
## the overlay is up — which is how nine debug actions fit in a game that has
## already spent F1 to F12.

const REFRESH_INTERVAL := 0.25

const COMMANDS := [
	"1 money +$1000", "2 force open", "3 force closed", "4 follow hours",
	"5 spawn customer", "6 clear customers", "7 restock shelves",
	"8 trade an hour", "9 end the day", "0 reputation 50",
	"Q next business", "W deliver now", "E start campaign", "R hire a manager",
	"T take a loan", "Y pay a loan", "U advance 7 days", "I force far sim",
	"A stand up a restaurant", "S stand up a gym", "D stand up a nightclub",
	"F fill ingredients", "G set cleanliness 30", "H trade a whole day",
	"J fill to capacity", "Z make a brand", "X open a branch",
	"C transfer somebody", "V manager: all permissions",
]

## Where the three Phase O types get stood up by the debug keys. The same units
## the tests and the screenshot tool use, so what a key builds is what a test
## checks.
const DEBUG_SITES := {
	KEY_A: [&"unit_plaza_07", &"restaurant", "Debug Kitchen"],
	KEY_S: [&"unit_dock_09", &"gym", "Debug Fitness"],
	KEY_D: [&"unit_vault_03", &"nightclub", "Debug Venue"],
}

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
	panel.position = Vector2(18.0, 620.0)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.92)
	add_child(panel)

	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.043, 0.055, 0.043, 0.82)
	box.set_content_margin_all(10.0)
	box.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", box)

	_label = Label.new()
	_label.name = "Readout"
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.86, 0.96, 0.88))
	panel.add_child(_label)


func toggle() -> void:
	visible = not visible
	set_process(visible)
	if visible:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_business_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var business := _business()
	if business == null:
		return

	match (event as InputEventKey).keycode:
		KEY_Q: _cycle_business()
		KEY_W: BusinessManager.deliver_now(business)
		KEY_E: BusinessManager.start_campaign(business, &"flyers")
		KEY_R: _hire_manager(business)
		KEY_T: BusinessManager.take_loan(business, &"starter")
		KEY_Y: _pay_a_loan(business)
		KEY_U: TimeManager.advance_minutes(7 * 1440)
		KEY_I: BusinessManager.simulate_hour_now(business)
		KEY_1: business.credit(1000, "Debug funds", &"capital")
		KEY_2: _override(business, BusinessInstance.Override.FORCE_OPEN)
		KEY_3: _override(business, BusinessInstance.Override.FORCE_CLOSED)
		KEY_4: _override(business, BusinessInstance.Override.NONE)
		KEY_5: _spawn_customer()
		KEY_6: _clear_customers()
		KEY_7: _restock_all(business)
		KEY_8: BusinessManager.simulate_hour_now(business)
		KEY_9: BusinessManager._on_day_passed(TimeManager.day_index)
		KEY_0: business.reputation = 50.0
		# Phase O.
		KEY_A, KEY_S, KEY_D: _stand_up(int((event as InputEventKey).keycode))
		KEY_F: CompanyDebug.stock_up(business, 90)
		KEY_G: CompanyDebug.set_cleanliness(business, 30.0)
		KEY_H: CompanyDebug.advance_business_day(business)
		KEY_J: _fill_up(business)
		KEY_Z: CompanyManager.create_brand("Debug Brand", business.type_id)
		KEY_X: _open_a_branch(business)
		KEY_C: _transfer_somebody(business)
		KEY_V: _grant_everything(business)
		_: return
	get_viewport().set_input_as_handled()
	_refresh()


## Which business the commands act on. The overlay follows one at a time, and Q
## steps through them, because a debug key that acts on "all of them" is not much
## use for finding out why one of them is wrong.
var _focus: int = 0


func _business() -> BusinessInstance:
	var owned := BusinessManager.get_businesses()
	if owned.is_empty():
		return null
	return owned[_focus % owned.size()]


func _cycle_business() -> void:
	_focus += 1


func _hire_manager(business: BusinessInstance) -> void:
	BusinessManager.refresh_candidates()
	var candidates := BusinessManager.get_candidates()
	if candidates.is_empty():
		return
	BusinessManager.hire(business, candidates[0], EmployeeData.Role.MANAGER)
	business.auto_open = true
	business.auto_restock = true
	business.auto_order = true


## Leases, founds, fits, stocks and staffs one of the Phase O types.
func _stand_up(keycode: int) -> void:
	var site: Array = DEBUG_SITES.get(keycode, [])
	if site.size() < 3:
		return
	EconomyManager.restore(maxi(EconomyManager.cash, 120000))
	CompanyDebug.stand_up(site[0], site[1], String(site[2]), get_tree(), 30000)


func _fill_up(business: BusinessInstance) -> void:
	var unit := RetailUnit.for_business(business, get_tree())
	if unit != null:
		CompanyDebug.fill_to_capacity(business, unit)


## Another branch of whatever this business trades under, in the first unit
## that will take one.
func _open_a_branch(business: BusinessInstance) -> void:
	var brand := CompanyManager.brand_for_business(business)
	if brand == null:
		return
	var definition := business.type_data()
	for unit in PropertyManager.get_properties():
		if not unit.is_vacant() or not unit.accepts_business(definition):
			continue
		EconomyManager.restore(maxi(EconomyManager.cash, 120000))
		PropertyManager.lease(unit)
		CompanyManager.found_business("", business.type_id, unit, brand)
		return


## Moves the first member of staff to the next business along, which is the
## quickest way to see a transfer land on both screens.
func _transfer_somebody(business: BusinessInstance) -> void:
	if business.employees.is_empty():
		return
	var owned := BusinessManager.get_businesses()
	if owned.size() < 2:
		return
	var target: BusinessInstance = owned[(_focus + 1) % owned.size()]
	CompanyManager.transfer_employee(business.employees[0], target)


func _grant_everything(business: BusinessInstance) -> void:
	business.auto_open = true
	business.auto_restock = true
	business.auto_order = true
	for key in business.manager_permissions.keys():
		business.set_permission(StringName(key), true)
	business.auto_order_budget = 2000


func _pay_a_loan(business: BusinessInstance) -> void:
	for loan in business.active_loans():
		BusinessManager.repay_loan(business, loan.loan_id, loan.payment_amount)
		return


func _unit() -> RetailUnit:
	return RetailUnit.for_business(_business(), get_tree())


func _override(business: BusinessInstance, value: BusinessInstance.Override) -> void:
	business.manual_override = value
	business.set_open(business.should_be_open(TimeManager.hour))


func _spawn_customer() -> void:
	var unit := _unit()
	if unit == null:
		return
	var spawner := unit.get_spawner()
	if spawner != null:
		spawner.spawn_customer_now()


func _clear_customers() -> void:
	var unit := _unit()
	if unit == null:
		return
	var spawner := unit.get_spawner()
	if spawner == null:
		return
	for customer in spawner.active_customers():
		customer.queue_free()


## Fills every shelf from the store room, in catalogue order.
func _restock_all(business: BusinessInstance) -> void:
	var wanted := business.catalogue()
	if wanted.is_empty():
		return
	var index := 0
	for shelf in business.shelves():
		var item: ItemData = wanted[index % wanted.size()]
		index += 1
		business.stock_shelf(shelf.slot_id, item.id, shelf.room_left() if shelf.stock_item == item.id else shelf.capacity())


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	_refresh()


func _refresh() -> void:
	var business := _business()
	if business == null:
		_label.text = "BUSINESS  (F10 hide)\n  you do not own a business"
		return

	var lines: Array[String] = ["BUSINESS  (F10 hide)"]
	var summary := BusinessManager.portfolio_summary()
	lines.append("  %s   %d businesses   net worth $%d   debt $%d" % [
		summary["company"], int(summary["businesses"]),
		int(summary["net_worth"]), int(summary["debt"]),
	])
	lines.append("  %s   %s   %s   value $%d" % [
		business.business_name, business.status_text(),
		BusinessManager.simulation_mode(business), business.estimated_value(),
	])
	lines.append("  cash $%d   rep %d%%   open %02d-%02d" % [
		business.cash_balance, roundi(business.reputation),
		business.opening_hour, business.closing_hour,
	])
	lines.append("  today: %d customers   $%d revenue   $%d expenses   $%d profit" % [
		business.customer_count_today, business.revenue_today,
		business.expenses_today(), business.profit_today(),
	])
	lines.append("  lost sales %d   units sold %d" % [
		business.lost_sales_today, business.units_sold_today
	])

	var unit := _unit()
	if unit != null:
		var spawner := unit.get_spawner()
		if spawner != null:
			lines.append("  on the floor %d   queue %d   till %s" % [
				spawner.active_customers().size(), spawner.queue_length(),
				"player" if spawner.is_player_working_register() else "-",
			])
	lines.append("  spawn rate %.1f/hour   capacity %d   marketing +%d%%" % [
		CustomerDemand.customers_per_hour(business, TimeManager.hour),
		business.customer_capacity(), roundi(business.marketing_bonus() * 100.0),
	])
	var boss := business.manager()
	if boss != null:
		lines.append("  manager %s   open %s  restock %s  order %s ($%d)" % [
			boss.employee_name, business.auto_open, business.auto_restock,
			business.auto_order, business.auto_order_budget,
		])
	for order in BusinessManager.outstanding_orders(business):
		lines.append("  order %s %s arriving %s" % [
			order.order_id, order.status_text(), order.arrival_text()
		])
	for loan in business.active_loans():
		lines.append("  loan %s $%d left, $%d due day %d" % [
			loan.display_name, loan.remaining_balance, loan.payment_amount, loan.next_payment_day
		])

	for shelf in business.shelves():
		var item := shelf.item()
		lines.append("  shelf %d: %s %d/%d" % [
			shelf.slot_id, "empty" if item == null else item.display_name,
			shelf.stock_quantity, shelf.capacity(),
		])
	for worker in business.employees:
		lines.append("  %s %s %s  served %d  $%d/h" % [
			worker.employee_name, worker.get_role_name(), worker.schedule_text(),
			worker.customers_served_today, worker.hourly_wage,
		])

	lines.append("  " + "   ".join(COMMANDS.slice(0, 5)))
	lines.append("  " + "   ".join(COMMANDS.slice(5)))
	_label.text = "\n".join(lines)
