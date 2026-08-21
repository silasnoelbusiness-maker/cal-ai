class_name ManagerPanel
extends Control
## What one branch's manager is allowed to do while nobody is watching.
##
## The point of a manager has always been that the shop runs when the player is
## across the city. The point of this screen is that it runs the way the player
## wants: every switch is off until it is turned on, there is a hard cap on the
## money, and the one thing a manager may never do without being told is change
## what the business charges.

signal opened()
signal closed()

## The switches, as [permission, label, explanation].
const TOGGLES: Array = [
	[&"manage_cleanliness", "KEEP IT CLEAN",
		"Calls somebody in when cleanliness drops below the mark. Costs money."],
	[&"staff_positioning", "MOVE STAFF BETWEEN JOBS",
		"Puts somebody on a job nobody is covering, if they are spare."],
	[&"adjust_pricing", "ADJUST PRICING",
		"Lets the manager change what you charge. Off unless you say otherwise."],
]

var _parts: Dictionary = {}
var _body: VBoxContainer = null
var _business: BusinessInstance = null


func _ready() -> void:
	_parts = ScreenKit.build_frame(self, Vector2(800, 620))
	_body = ScreenKit.scroller(_parts["body"])


func is_open() -> bool:
	return visible


func open(business: BusinessInstance) -> void:
	if business == null:
		return
	_business = business
	_rebuild()
	visible = true
	AudioManager.play_ui(&"ui_confirm")
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	_business = null
	AudioManager.play_ui(&"ui_back")
	closed.emit()


func _rebuild() -> void:
	for child in _body.get_children():
		child.queue_free()
	for child in _parts["actions"].get_children():
		child.queue_free()
	if _business == null:
		return

	var boss := _business.manager()
	_parts["title"].text = "%s — MANAGER" % _business.business_name.to_upper()
	_parts["subtitle"].text = (
		"%s  ·  management %d" % [boss.employee_name, boss.skill_management]
		if boss != null else "Nobody is managing this branch."
	)
	_parts["status"].text = ""

	if boss == null:
		_body.add_child(BusinessUIKit.label(
			"Hire a manager on the branch's staff page. Until then nothing here "
			+ "does anything, because there is nobody to do it.", 14, ScreenKit.MUTED
		))
		_add_close()
		return

	_build_duties()
	_build_permissions()
	_build_budget()
	_build_stock_rules()
	_add_close()


func _build_duties() -> void:
	_body.add_child(ScreenKit.heading("DUTIES"))
	_body.add_child(_switch(
		"OPEN AND CLOSE", _business.auto_open,
		"Works the published hours without being told.",
		func(on: bool) -> void: _business.auto_open = on
	))
	_body.add_child(_switch(
		"RESTOCK SHELVES", _business.auto_restock,
		"Moves stock from the back room onto the shelves.",
		func(on: bool) -> void: _business.auto_restock = on
	))
	_body.add_child(_switch(
		"ORDER STOCK", _business.auto_order,
		"Reorders from the supplier before the shop runs dry.",
		func(on: bool) -> void: _business.auto_order = on
	))


func _build_permissions() -> void:
	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("PERMISSIONS"))
	for entry in TOGGLES:
		var key: StringName = entry[0]
		_body.add_child(_switch(
			String(entry[1]), _business.may(key), String(entry[2]),
			func(on: bool) -> void: _business.set_permission(key, on)
		))


func _switch(
	label: String, on: bool, detail: String, apply: Callable
) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", BusinessUIKit.row_style())
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	card.add_child(column)

	var button := BusinessUIKit.button("ON" if on else "OFF", 80.0)
	button.toggle_mode = true
	button.button_pressed = on
	button.pressed.connect(func() -> void:
		apply.call(button.button_pressed)
		AudioManager.play_ui(&"ui_click")
		_rebuild()
	)
	column.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label(label, 15, ScreenKit.TEXT), button,
	]))
	column.add_child(BusinessUIKit.label(detail, 12, ScreenKit.MUTED))
	return card


func _build_budget() -> void:
	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("SPENDING LIMIT"))
	var spin := BusinessUIKit.spin(0, 20000, float(_business.auto_order_budget), 50)
	spin.value_changed.connect(func(value: float) -> void:
		_business.auto_order_budget = int(value)
		_parts["status"].text = "Limit set to %s a day." % ScreenKit.money(int(value))
	)
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Per day", 14, ScreenKit.MUTED), spin,
	]))
	_body.add_child(ScreenKit.row(
		"Spent today", "%s of %s" % [
			ScreenKit.money(_business.manager_spent_today),
			ScreenKit.money(_business.auto_order_budget),
		]
	))
	_body.add_child(ScreenKit.row(
		"Left to spend", ScreenKit.money(_business.manager_budget_left()), true
	))
	_body.add_child(BusinessUIKit.label(
		"The manager never spends past this, and never past what the branch "
		+ "actually holds — whichever of the two is smaller.", 12, ScreenKit.MUTED
	))


func _build_stock_rules() -> void:
	_body.add_child(ScreenKit.spacer(8))
	_body.add_child(ScreenKit.heading("STOCK RULES"))
	var minimum := BusinessUIKit.spin(0, 500, float(_business.auto_order_minimum), 5)
	minimum.value_changed.connect(func(value: float) -> void:
		_business.auto_order_minimum = int(value)
	)
	var target := BusinessUIKit.spin(0, 999, float(_business.auto_order_target), 5)
	target.value_changed.connect(func(value: float) -> void:
		_business.auto_order_target = int(value)
	)
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Reorder below", 14, ScreenKit.MUTED), minimum,
	]))
	_body.add_child(BusinessUIKit.row([
		BusinessUIKit.stretch_label("Top up to", 14, ScreenKit.MUTED), target,
	]))

	if _business.uses_cleanliness():
		var clean := BusinessUIKit.spin(0, 100, float(_business.cleanliness_target), 5)
		clean.value_changed.connect(func(value: float) -> void:
			_business.cleanliness_target = int(value)
		)
		_body.add_child(BusinessUIKit.row([
			BusinessUIKit.stretch_label("Keep cleanliness above", 14, ScreenKit.MUTED), clean,
		]))
		_body.add_child(ScreenKit.stat_bar(
			"Cleanliness now", roundi(_business.cleanliness),
			_business.cleanliness < 55.0
		))


func _add_close() -> void:
	var close_button := BusinessUIKit.button("CLOSE", 120.0)
	close_button.pressed.connect(func() -> void: GameManager.close_menus())
	_parts["actions"].add_child(close_button)
