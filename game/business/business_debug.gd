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
		_: return
	get_viewport().set_input_as_handled()
	_refresh()


func _business() -> BusinessInstance:
	return BusinessManager.primary_business()


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
	lines.append("  %s   %s   %s" % [
		business.business_name, business.status_text(),
		BusinessManager.simulation_mode(business),
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
	lines.append("  spawn rate %.1f/hour" % CustomerDemand.customers_per_hour(business, TimeManager.hour))

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
